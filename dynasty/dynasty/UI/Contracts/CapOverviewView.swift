import SwiftUI
import SwiftData

struct CapOverviewView: View {

    let career: Career

    @Environment(\.modelContext) private var modelContext

    @State private var team: Team?
    @State private var players: [Player] = []

    /// Detailed contract rows keyed by `playerID`. Only realistic-mode signings
    /// mint one, so most players fall back to `annualSalary` — but where a deal
    /// exists its `capHit` (base + prorated bonus) is what the cap is charged,
    /// and that is the number this screen must show.
    @State private var contractsByPlayer: [UUID: Contract] = [:]

    /// The largest recorded releases of the current season — see ``deadMoneyCard``
    /// for what they can and cannot attribute.
    @State private var releaseReceipts: [ReleaseReceipt] = []

    /// Dead cap recorded across *all* of this season's releases, not just the
    /// handful the card lists — so the "everything else" line stays honest.
    @State private var releaseDeadCapTotal: Int = 0

    /// How many releases were recorded but not listed.
    @State private var releaseOverflowCount: Int = 0

    @State private var contractSort: ContractSort = .capHit

    @State private var cutSort: CutSort = .capHit

    /// What releasing each man on the roster would cost and free — see
    /// ``escapeCostCard()``.
    ///
    /// Priced in ``loadCutCosts()`` rather than inside the card, for the same
    /// reason `releaseReceipts` is a snapshot: the card re-sorts on a tap, and
    /// each row is an engine call (`Contract.deadCap` or the implied-guarantee
    /// proxy, plus the restructure ledger). Sorting a 90-man roster through a
    /// comparator that priced two releases per comparison would run that
    /// arithmetic several hundred times to draw eight rows. Refreshed on the
    /// same `loadData` beat as `players`, so it can never describe a roster the
    /// rest of the screen no longer has.
    @State private var cutCosts: [CutCost] = []

    /// The player whose agent is on the phone. Non-nil while the Contact Agent
    /// thread is open.
    @State private var negotiationPlayer: Player?

    // MARK: - The Open League Year

    /// **The league year every number on this screen is about.**
    ///
    /// `Career.currentSeason` is not it for six phases of the offseason:
    /// `FreeAgencyEngine.executeNewLeagueYear` opens the new league year — it
    /// decrements every contract clock and re-sums `Team.currentCapUsage` —
    /// while the counter is only bumped at the rosterCuts→regularSeason
    /// boundary. So from proDays through rosterCuts the ledger this screen
    /// prints belongs to `currentSeason + 1`.
    ///
    /// That matters because year offset 0 here IS the live ledger
    /// (`team.currentCapUsage`), so bar `k` depicts `openYear + k`. Keying the
    /// forward-row lookup off the raw counter asked for `currentSeason + k`
    /// instead and drew a deferred extension's new money one bar late, at the
    /// superseded rate in the year it actually binds — on the screen whose
    /// whole premise (see ``committedCap(team:yearOffset:)``) is that it cannot
    /// quote a different future than the negotiation gate, which prices its
    /// years through `DealTargetYear`.
    ///
    /// Delegated, not re-derived: `DealTargetYear.openSeason` is the same
    /// rollover test the booking path, `WeekAdvancer`'s compliance window and
    /// `FranchiseTagView` use.
    private var openYear: Int {
        DealTargetYear.openSeason(
            currentSeason: career.currentSeason,
            hasRolledOver: career.lastRolloverSeason >= career.currentSeason
        )
    }

    // MARK: - Contract Sort

    /// How the contract ledger is ordered. The list is the screen's working
    /// surface — 60-odd rows are only useful if you can ask them a question.
    enum ContractSort: String, CaseIterable, Identifiable {
        /// Biggest share of the cap first (identical ordering to cap hit, since
        /// every row divides by the same ceiling — the label names what the GM
        /// is actually reading off the row).
        case capHit
        case salary
        case years
        case expiring

        var id: String { rawValue }

        var label: String {
            switch self {
            case .capHit:   return "Cap %"
            case .salary:   return "Salary"
            case .years:    return "Years"
            case .expiring: return "Expiring"
            }
        }
    }

    /// One recorded release, resolved to a name for display.
    struct ReleaseReceipt: Identifiable {
        let id: UUID
        let name: String
        let deadCap: Int
        let seasonYear: Int
    }

    // MARK: - Escape Cost Sort

    /// How the escape-cost table is ordered.
    ///
    /// Three orderings because the table answers three different questions and
    /// **the biggest contract is frequently the answer to none of them**: Cap Hit
    /// is "what are my largest commitments", Freed is "who can actually give me
    /// room", Dead is "who am I stuck with". A bonus-heavy deal can cost more to
    /// cut than to keep — `ReleaseCapSplit.capSavings` goes negative and the row
    /// says so — so a shortlist ranked by size alone would put the least
    /// escapable contract at the top and present it as an option.
    enum CutSort: String, CaseIterable, Identifiable {
        case capHit
        case freed
        case dead

        var id: String { rawValue }

        var label: String {
            switch self {
            case .capHit: return "Cap Hit"
            case .freed:  return "Freed"
            case .dead:   return "Dead"
            }
        }

        /// The same ordering said in the card's own voice, for the "Top 8 by …"
        /// caption. The segment label has to fit a picker; the caption does not.
        var rankingPhrase: String {
            switch self {
            case .capHit: return "cap hit"
            case .freed:  return "cap freed"
            case .dead:   return "dead money"
            }
        }
    }

    /// One release, priced by the engine that prices releases.
    struct CutCost: Identifiable {
        let player: Player
        /// The charge he carries today, on the same precedence the rest of this
        /// screen reads (``capHit(for:)``).
        let capHit: Int
        /// What the club would still be charged for him after the release.
        let deadCap: Int
        /// Cap the release actually gives back. Negative when the bonus
        /// acceleration outruns the salary relief.
        let freed: Int
        /// `freed + deadCap`, kept as its own term because that sum — and not
        /// the cap hit beside it — is the pool the two columns divide: the part
        /// of this league year's charge that has not been paid out yet. This
        /// year's bonus slice is charged whether the man stays or goes, and
        /// in-season so are the game checks already written.
        let unpaidRemainder: Int

        var id: UUID { player.id }
    }

    /// Column widths for the escape-cost table, declared once so the header row
    /// and the value rows under it cannot drift apart — the same failure
    /// `PlayerRowView`'s own `Column` block exists to prevent.
    private enum CutColumn {
        static let capHit: CGFloat = 62
        static let deadCap: CGFloat = 72
        static let freed: CGFloat = 66
        /// The chevron's slot, reserved in the header so the numbers sit under
        /// their labels rather than one glyph to the left of them.
        static let chevron: CGFloat = 10
    }

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    if let team {
                        overCapBanner(team: team)
                        // #178: the screen reads as two league years and then the
                        // long view. Everything that is TRUE TODAY sits under one
                        // heading; everything that is a PROJECTION sits under the
                        // next; the three-season bars keep the tail.
                        thisYearSection(team: team)
                        nextYearSection(team: team)
                        capOutlookCard(team: team)
                        contractListCard(team: team)
                    } else {
                        ProgressView()
                            .tint(Color.accentBlue)
                            .padding(.top, 80)
                    }
                }
                .padding(20)
                .frame(maxWidth: DSLayout.contentMeasure)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Salary Cap")
        // Inline, not `.large` (#47): a large title is pinned to the window's
        // leading edge, so on an iPad it sat ~230 pt to the left of the centred
        // content column and read as broken alignment. The nav bar still names
        // the screen; the cards keep the reading measure the numbers need.
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        // `.onAppear`, not `.task` (#188). Every derivation on this screen but
        // the three headline figures reads `players` / `contractsByPlayer` /
        // `releaseReceipts` — one-shot `@State` snapshots. `.task` runs once for
        // the view's lifetime, and a push does not end that lifetime, so the
        // FIX IT banner's own workspace was the worst case: release three men in
        // `CapComplianceView`, pop back, and the roster snapshot still held all
        // three. `team.currentCapUsage` had dropped (SwiftData observes the
        // model object) while Σ roster cap hits had not, so the derived residual
        // went NEGATIVE and the Dead Money card flipped to "Ledger variance" —
        // the screen reporting a books-don't-reconcile bug it had just invented
        // by not looking again. `onAppear` fires on every return from a push;
        // `loadData` is synchronous, so `.task` was buying nothing.
        .onAppear { loadData() }
        .fullScreenCover(item: $negotiationPlayer) { player in
            // ContractNegotiationView supplies its own "Close" toolbar item, so
            // the wrapper must NOT add a second one.
            NavigationStack {
                ContractNegotiationView(
                    player: player,
                    negotiationType: .extend,
                    teamCapSpace: max(0, team?.availableCap ?? 0),
                    onDealCompleted: { offer in
                        // Extension: ADD new years to the existing contract.
                        // Through the engine, which is what moves
                        // `team.currentCapUsage` — without it a signing made on
                        // THIS screen left the cap bar untouched and pushed the
                        // derived dead-money residual negative, so the card
                        // right below flipped to "Ledger variance".
                        ContractEngine.applyNegotiatedDeal(
                            player: player,
                            team: team,
                            offer: offer,
                            application: .extendExisting,
                            capMode: career.capMode,
                            careerID: career.id,
                            existingContract: contractsByPlayer[player.id],
                            modelContext: modelContext
                        )
                        try? modelContext.save()
                        loadData()
                        // No dismiss — the thread shows the signed card and the
                        // user closes it with Done.
                    }
                )
            }
        }
    }

    // MARK: - Over-Cap Banner (#102)

    /// The debt, stated at the top of the screen, with the door to the workspace
    /// that fixes it.
    ///
    /// It sits ABOVE the summary card rather than inside it because being over
    /// the cap is not a statistic — it is a blocking condition with a required
    /// action, and a GM who is illegal should not have to read three cards to
    /// find that out. Absent entirely when the club is compliant, and in sandbox,
    /// where there is nothing to be over.
    @ViewBuilder
    private func overCapBanner(team: Team) -> some View {
        // From the engine, not re-derived here. `CapManagementEngine.complianceStatus`
        // is what the week-advance gate and the required task both read, and a
        // banner that computed its own overage could tell the user he is legal
        // on the very screen the gate just sent him to.
        let status = CapManagementEngine.complianceStatus(team: team, capMode: career.capMode)
        let overage = status.overage

        if !status.isCompliant, overage > 0 {
            NavigationLink {
                CapComplianceView(career: career, context: .weekAdvanceGate)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: DSType.Size.title2))
                        .foregroundStyle(Color.danger)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("You are \(formatMillions(overage)) over the cap")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color.danger)
                        Text("Release, restructure or renegotiate to get legal.")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                    Spacer()
                    Text("FIX IT")
                        .font(.system(size: DSType.Size.caption, weight: .black))
                        .foregroundStyle(Color.backgroundPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.danger, in: Capsule())
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.danger)
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(Color.danger.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.danger.opacity(0.45), lineWidth: 2)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Year Sections (#178)

    /// Everything that is a FACT about the open league year: what the ceiling
    /// is, what has been charged against it, and what that charge is made of.
    ///
    /// The first three cards were already here and are unchanged — the heading
    /// was #178's change. Without it the screen was six cards of numbers in
    /// which "used cap" (today) and "committed" (a projection three bars down)
    /// looked like the same kind of fact, and a GM reading the dead-money card
    /// had no way to know it described a balance that the March rollover
    /// deletes.
    ///
    /// ``escapeCostCard()`` is the fourth, and it belongs to this year for the
    /// same reason the dead-money card does: a release priced today is priced
    /// against today's ledger, at today's point in the league year.
    private func thisYearSection(team: Team) -> some View {
        VStack(spacing: 12) {
            yearSectionHeader(
                icon: "calendar",
                title: "THIS YEAR (\(openYear))",
                caption: "On the books now"
            )
            capSummaryCard(team: team)
            capBarCard(team: team)
            deadMoneyCard(team: team)
            escapeCostCard()
        }
    }

    /// The heading that separates a year section from the one above it.
    ///
    /// Display voice, uppercase, tracked — the same band idiom the hub uses, so
    /// it reads as structure rather than as another card title. It deliberately
    /// carries no card background: a heading that looked like a card would just
    /// be a seventh card.
    private func yearSectionHeader(icon: String, title: String, caption: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: DSType.Size.caption, weight: .semibold))
                .foregroundStyle(Color.textSecondary)
            Text(title)
                .font(DSType.display(DSType.Size.footnote, .black))
                .tracking(0.9)
                .foregroundStyle(Color.textPrimary)
            Spacer(minLength: 8)
            Text(caption)
                .font(.system(size: DSType.Size.micro, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(caption)")
    }

    // MARK: - Cap Summary Card

    private func capSummaryCard(team: Team) -> some View {
        let active = activeCapUsage
        let dead = deadMoney(team: team)

        return VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: DSType.Size.body, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
                Text("Cap Summary")
                    .font(.system(size: DSType.Size.callout, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider().overlay(Color.surfaceBorder)

            HStack(spacing: 0) {
                capStatColumn(
                    label: "Total Cap",
                    value: formatMillions(team.salaryCap),
                    color: .textPrimary
                )
                capStatColumn(
                    label: "Used Cap",
                    value: formatMillions(team.currentCapUsage),
                    color: capUsageColor(team: team)
                )
                capStatColumn(
                    label: "Available",
                    value: formatMillions(team.availableCap),
                    color: team.availableCap >= 0 ? .success : .danger
                )
            }

            Divider().overlay(Color.surfaceBorder.opacity(0.5))

            // The split the screen used to hide. "Used Cap" is one number for
            // two very different commitments: money paid to players who will
            // take a snap this year, and money owed to players who are gone.
            // A GM plans against the first and is punished by the second, so
            // both are named, and they add back up to the number above.
            HStack(spacing: 12) {
                capSplitPill(
                    label: "Active contracts",
                    value: formatMillions(active),
                    color: .textPrimary,
                    icon: "person.2.fill"
                )
                Text("+")
                    .font(.system(size: DSType.Size.body, weight: .bold))
                    .foregroundStyle(Color.textTertiary)
                capSplitPill(
                    label: deadLabel(dead),
                    value: formatMillions(dead),
                    color: dead > 0 ? .danger : .textTertiary,
                    icon: "xmark.circle.fill"
                )
            }

            Text("Active + \(deadLabel(dead).lowercased()) = used cap")
                .font(.system(size: DSType.Size.micro))
                .foregroundStyle(Color.textTertiary)

            ledgerVarianceRow(dead: dead)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .cardBackground()
    }

    /// The honest symptom, stated rather than hidden (#178 / #188).
    ///
    /// `dead` is a residual — `used cap − Σ roster cap hits` — so it cannot be
    /// negative in a ledger that balances. When it IS negative the club is being
    /// charged LESS than the contracts on its own roster add up to, which means
    /// a signing moved `Contract.capHit` without moving `currentCapUsage` by the
    /// same amount (`CapManagementEngine.applyRelease` documents the same gap
    /// from the other direction). That is a bug in the books, and the cheapest
    /// way to lose a bug in the books is to relabel it as a category of money.
    ///
    /// So: shown ONLY when the variance is non-zero, named as a variance rather
    /// than as dead money, and pointed at the two numbers that disagree — a user
    /// who reports it can quote both.
    @ViewBuilder
    private func ledgerVarianceRow(dead: Int) -> some View {
        if dead < 0 {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: DSType.Size.micro))
                    .foregroundStyle(Color.warning)
                Text("Ledger variance \(formatMillions(dead)) — used cap is below the sum of roster cap hits. Not dead money: the two ledgers disagree, and it is shown rather than swallowed while the cause is tracked down.")
                    .font(.system(size: DSType.Size.micro))
                    .foregroundStyle(Color.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.warning.opacity(0.10), in: RoundedRectangle(cornerRadius: DSCornerRadius.inline))
        }
    }

    private func capStatColumn(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.system(size: DSType.Size.title1, weight: .bold).monospacedDigit())
                .foregroundStyle(color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value)")
    }

    private func capSplitPill(label: String, value: String, color: Color, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: DSType.Size.caption))
                .foregroundStyle(color.opacity(0.8))
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: DSType.Size.callout, weight: .bold).monospacedDigit())
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(label)
                    .font(.system(size: DSType.Size.micro))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color.backgroundTertiary.opacity(0.5), in: RoundedRectangle(cornerRadius: DSCornerRadius.inline))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value)")
    }

    // MARK: - Cap Bar Card

    private func capBarCard(team: Team) -> some View {
        let dead = deadMoney(team: team)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Cap Usage")
                    .font(.system(size: DSType.Size.callout, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text(String(format: "%.1f%%", usagePercentage(team: team) * 100))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(capUsageColor(team: team))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.backgroundTertiary)
                        .frame(height: 14)

                    // Two segments, one bar: the dead-money tail sits at the
                    // right edge of the fill so the eye reads "this much of the
                    // spend buys nothing" without needing a second chart.
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(capBarGradient(team: team))
                            .frame(width: geo.size.width * clampedFraction(activeCapUsage, of: team.salaryCap))
                        if dead > 0 {
                            Rectangle()
                                .fill(Color.danger)
                                .frame(width: geo.size.width * clampedFraction(dead, of: team.salaryCap))
                        }
                    }
                    .frame(height: 14)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .animation(.easeOut(duration: 0.4), value: team.currentCapUsage)
                }
            }
            .frame(height: 14)

            if dead > 0 {
                HStack(spacing: 12) {
                    legendDot(color: .accentBlue, label: "Active \(formatMillions(activeCapUsage))")
                    legendDot(color: .danger, label: "Dead \(formatMillions(dead))")
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(20)
        .cardBackground()
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: DSType.Size.micro).monospacedDigit())
                .foregroundStyle(Color.textSecondary)
        }
    }

    // MARK: - Dead Money Card

    /// Dead money, named and attributed as far as the store allows.
    ///
    /// **What the ledger actually knows.** `Team.currentCapUsage` is a single
    /// running total; nothing stores a dead-money column and nothing stores who
    /// each dollar belonged to. The total here is therefore derived the only way
    /// it can be — the cap charge that no player on the roster accounts for:
    ///
    /// ```
    /// dead = team.currentCapUsage − Σ roster cap hits
    /// ```
    ///
    /// which is exactly what `TradeEngine.executeTrade` leaves behind when it
    /// subtracts a traded player's salary and adds `split.deadCap` back on.
    ///
    /// **Attribution** exists for one path only: `RosterCut` rows record a
    /// per-player `deadCap` for camp releases. Those are shown as receipts, and
    /// the remainder is labelled honestly rather than being silently split up —
    /// trades and in-season releases leave no per-player record to read.
    private func deadMoneyCard(team: Team) -> some View {
        let dead = deadMoney(team: team)
        let unattributed = dead - releaseDeadCapTotal
        // A negative residual is NOT a smaller amount of dead money — it is the
        // books failing to reconcile, and it gets its own voice all the way up
        // to the card's own title (#188). Before this the card kept the "Dead
        // Money" heading and then printed the clean-ledger line — "every dollar
        // of cap charge belongs to a player on the roster" — which is the one
        // sentence that is definitely false in exactly this state.
        let isVariance = dead < 0

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: isVariance ? "exclamationmark.triangle.fill" : "xmark.circle.fill")
                    .font(.system(size: DSType.Size.body, weight: .semibold))
                    .foregroundStyle(isVariance ? Color.warning : (dead > 0 ? Color.danger : Color.textSecondary))
                // Routed through `deadLabel`, the same call the summary pill and
                // the bar legend use, so one ledger state cannot be called two
                // different things on one screen.
                Text(deadLabel(dead))
                    .font(.system(size: DSType.Size.callout, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text(formatMillions(dead))
                    .font(.system(size: DSType.Size.title3, weight: .bold).monospacedDigit())
                    .foregroundStyle(isVariance ? Color.warning : (dead > 0 ? Color.danger : Color.textTertiary))
            }

            // A clean ledger gets the header row and nothing else: the rule and
            // a sentence under it were card chrome around the word "none".
            if dead != 0 {
                Divider().overlay(Color.surfaceBorder)
            }

            if isVariance {
                Text("Books don't reconcile — ledger variance of \(formatMillions(-dead)). The club is charged LESS cap than the contracts on its own roster add up to, so this is not dead money: some deal moved a cap hit without moving the team total by the same amount.")
                    .font(.caption)
                    .foregroundStyle(Color.warning)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Quote both figures if you report it: used cap \(formatMillions(team.currentCapUsage)) against \(formatMillions(activeCapUsage)) of roster cap hits.")
                    .font(.system(size: DSType.Size.micro))
                    .foregroundStyle(Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if dead == 0 {
                // The header above already reads "Dead money · $0"; saying "no
                // dead money on the books" under it was the same fact twice.
                // What is left is the part the number does not state.
                Text("Every dollar of cap charge belongs to a player on the roster.")
                    .font(.system(size: DSType.Size.micro))
                    .foregroundStyle(Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                if !releaseReceipts.isEmpty {
                    Text("RECORDED RELEASES THIS SEASON")
                        .font(.system(size: DSType.Size.micro, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(Color.textSecondary)

                    ForEach(releaseReceipts) { receipt in
                        HStack(spacing: 8) {
                            Image(systemName: "person.fill.xmark")
                                .font(.system(size: DSType.Size.micro))
                                .foregroundStyle(Color.textTertiary)
                            Text(receipt.name)
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                                .lineLimit(1)
                            Spacer()
                            Text(formatMillions(receipt.deadCap))
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(Color.textPrimary)
                        }
                        .padding(.vertical, 2)
                    }

                    if releaseOverflowCount > 0 {
                        Text("+ \(releaseOverflowCount) more release\(releaseOverflowCount == 1 ? "" : "s")")
                            .font(.system(size: DSType.Size.micro))
                            .foregroundStyle(Color.textTertiary)
                    }
                }

                if unattributed > 0 {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: DSType.Size.micro))
                            .foregroundStyle(Color.textTertiary)
                        Text(releaseReceipts.isEmpty
                             ? "Charged to players no longer on the roster"
                             : "Trades and earlier releases")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(2)
                        Spacer()
                        Text(formatMillions(unattributed))
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Color.textPrimary)
                    }
                    .padding(.vertical, 2)
                }

                Text("The cap ledger keeps dead money as one team total, so only recorded releases can be named player-by-player.")
                    .font(.system(size: DSType.Size.micro))
                    .foregroundStyle(Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .cardBackground()
    }

    // MARK: - Escape Cost Card

    /// **What the club's biggest commitments cost to walk away from.**
    ///
    /// Everything above this card prices the roster as it stands. Nothing on the
    /// screen priced the club's way OUT of it, so the only place a GM could
    /// learn that his $34M quarterback is unmovable was to go over the cap and
    /// be sent to `CapComplianceView` by the FIX IT banner — i.e. the screen
    /// answered the question only once it was too late to be planning.
    ///
    /// It sits directly under the Dead Money card on purpose. That card names
    /// money already owed to men who are gone; this one names the money that
    /// would BECOME that if the club cut the men it still has. Same category,
    /// one tense apart, and the second is the only one the GM can still decide.
    ///
    /// **Nothing here is re-derived.** Every figure comes from
    /// `CapManagementEngine.releaseCapSplit` — the same call the cut ladder, the
    /// player-detail cut, the contract screen and the compliance levers all
    /// quote — priced at ``leagueYearRemaining`` so a Week 12 read is the Week 12
    /// answer and not a March one. A card that ran its own release arithmetic
    /// would be the fifth answer to "what does cutting this man cost", which is
    /// the exact drift #68 spent a wave closing.
    ///
    /// **Absent in sandbox.** With cap rules off the engine returns zero dead cap
    /// and relieves the whole salary, so every row would read "$0 dead, frees his
    /// salary" — eight rows restating the salary column one card down. There is
    /// nothing to escape from when nothing binds.
    @ViewBuilder
    private func escapeCostCard() -> some View {
        let rows = topCutCosts

        if !rows.isEmpty {
            VStack(spacing: 0) {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "scissors")
                            .font(.system(size: DSType.Size.body, weight: .semibold))
                            .foregroundStyle(Color.textSecondary)
                        Text("Escape Cost")
                            .font(.system(size: DSType.Size.callout, weight: .bold))
                            .foregroundStyle(Color.textPrimary)
                    }
                    Spacer()
                    Text("Top \(rows.count) by \(cutSort.rankingPhrase)")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

                Picker("Rank releases by", selection: $cutSort) {
                    ForEach(CutSort.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

                cutColumnHeader
                    .padding(.horizontal, 20)
                    .padding(.bottom, 6)

                Divider().overlay(Color.surfaceBorder)
                    .padding(.horizontal, 20)

                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        // Same destination as the contract ledger's rows: this
                        // card ranks the decision, the player card is where the
                        // decision gets made. Ranking and acting in one row would
                        // put a release button on a screen whose whole job is to
                        // be read, and would duplicate the compliance workspace.
                        NavigationLink {
                            PlayerDetailView(player: row.player)
                        } label: {
                            cutCostRow(row)
                        }
                        .buttonStyle(.plain)

                        if index < rows.count - 1 {
                            Divider()
                                .overlay(Color.surfaceBorder.opacity(0.5))
                                .padding(.horizontal, 20)
                        }
                    }
                }

                Divider().overlay(Color.surfaceBorder)
                    .padding(.horizontal, 20)

                escapeCostFooter(rows: rows)
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity)
            .cardBackground()
        }
    }

    /// The table's column labels. Display voice, uppercase and tracked — the same
    /// band idiom the year headings and the "RECORDED RELEASES" strip use, so
    /// three numeric columns are readable without a legend.
    private var cutColumnHeader: some View {
        HStack(spacing: 12) {
            Text("PLAYER")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("CAP HIT")
                .frame(width: CutColumn.capHit, alignment: .trailing)
            Text("DEAD IF CUT")
                .frame(width: CutColumn.deadCap, alignment: .trailing)
            Text("FREED")
                .frame(width: CutColumn.freed, alignment: .trailing)
            // The chevron's slot. `Color.clear` rather than a Spacer: a spacer
            // would be flexible and the header's numbers would slide off the
            // row's numbers by whatever the chevron happened to measure.
            Color.clear.frame(width: CutColumn.chevron, height: 1)
        }
        .font(.system(size: DSType.Size.micro, weight: .semibold))
        .tracking(0.8)
        .foregroundStyle(Color.textSecondary)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        // The values below carry their own spoken labels, so reading the header
        // aloud as well would announce every column name twice per row.
        .accessibilityHidden(true)
    }

    private func cutCostRow(_ row: CutCost) -> some View {
        let player = row.player
        let years = player.contractYearsRemaining

        return HStack(spacing: 12) {
            Text(player.position.rawValue)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 34)
                .padding(.vertical, 4)
                .background(positionColor(player.position), in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))

            // Years sit UNDER the name rather than in their own column, which is
            // what buys the room for a third numeric column at this measure. It
            // is also the term that qualifies the two beside it: dead money is
            // acceleration over the years still on the deal, so "1 yr left" is
            // half the explanation of a small dead figure.
            VStack(alignment: .leading, spacing: 1) {
                Text(player.fullName)
                    .font(.subheadline)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text("\(years) yr\(years == 1 ? "" : "s") left")
                    .font(.system(size: DSType.Size.micro).monospacedDigit())
                    .foregroundStyle(yearsColor(years))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(formatMillions(row.capHit))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: CutColumn.capHit, alignment: .trailing)

            Text(formatMillions(row.deadCap))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(row.deadCap > 0 ? Color.danger : Color.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: CutColumn.deadCap, alignment: .trailing)

            Text("\(row.freed > 0 ? "+" : "")\(formatMillions(row.freed))")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(freedColor(row.freed))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: CutColumn.freed, alignment: .trailing)

            Image(systemName: "chevron.right")
                .font(.system(size: DSType.Size.caption, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
                .frame(width: CutColumn.chevron)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(player.fullName), \(player.position.rawValue), \(years) year\(years == 1 ? "" : "s") left, cap hit \(formatMillions(row.capHit)), dead money if cut \(formatMillions(row.deadCap)), frees \(formatMillions(row.freed))")
        .accessibilityHint("Opens player detail")
    }

    /// The ratio the eight rows add up to, and the two sentences that stop it
    /// being read as an equation with the cap-hit column.
    ///
    /// Deliberately NOT framed as "if you released all eight" — no club runs that
    /// scenario, and a total nobody would ever act on is decoration. What the bar
    /// states is a portfolio fact the individual rows cannot: how escapable the
    /// club's largest commitments are as a group. `freed + deadCap` is exactly
    /// `unpaidRemainder` per row (see ``CutCost``), so the split is a real
    /// division of a real pool rather than two totals drawn side by side.
    private func escapeCostFooter(rows: [CutCost]) -> some View {
        let trapped = rows.reduce(0) { $0 + $1.deadCap }
        let freed = rows.reduce(0) { $0 + $1.freed }
        let unpaid = rows.reduce(0) { $0 + $1.unpaidRemainder }
        // With nothing left unpaid there is nothing trapped either, and a
        // fraction that defaulted to zero would paint that state as fully dead.
        let freedFraction = unpaid > 0 ? min(1.0, clampedFraction(freed, of: unpaid)) : 1.0
        let unpaidShare = Int((leagueYearRemaining * 100).rounded())
        let stuckCount = rows.filter { $0.freed <= 0 }.count

        return VStack(alignment: .leading, spacing: 8) {
            Text("HOW MUCH OF THIS MONEY COMES BACK")
                .font(.system(size: DSType.Size.micro, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Color.textSecondary)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: DSCornerRadius.tight)
                        .fill(Color.backgroundTertiary)
                        .frame(height: 10)

                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.success)
                            .frame(width: geo.size.width * freedFraction)
                        Rectangle()
                            .fill(Color.danger)
                            .frame(width: geo.size.width * (1.0 - freedFraction))
                    }
                    .frame(height: 10)
                    .clipShape(RoundedRectangle(cornerRadius: DSCornerRadius.tight))
                }
            }
            .frame(height: 10)

            HStack(spacing: 12) {
                legendDot(color: .success, label: "Freed \(freed >= 0 ? "+" : "")\(formatMillions(freed))")
                legendDot(color: .danger, label: "Dead \(formatMillions(trapped))")
                Spacer(minLength: 0)
            }

            if stuckCount > 0 {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: DSType.Size.micro))
                        .foregroundStyle(Color.danger)
                    Text("\(stuckCount) of these deals free\(stuckCount == 1 ? "s" : "") nothing: the acceleration is at least as big as the relief, so cutting costs the club as much as keeping — a negative figure means more.")
                        .font(.system(size: DSType.Size.micro))
                        .foregroundStyle(Color.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Why the two columns need not add up to the cap hit next to them,
            // stated before a GM tries the subtraction and concludes the screen
            // is broken. They DO add up to it in the offseason on a plain deal —
            // the sentence names the pool rather than denying the coincidence.
            Text("Freed and dead always add up to \(formatMillions(unpaid)) across these \(rows.count) deals — the base salary still owed plus this year's bonus slice, which a release simply moves out of the cap hit and into the dead column. That pool, not the cap hit beside it, is what the two columns divide.")
                .font(.system(size: DSType.Size.micro))
                .foregroundStyle(Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            if unpaidShare < 100 {
                Text("Week \(career.currentWeek): only the \(unpaidShare)% of base salary still owed can be freed. The game checks already written stay charged — a cut gets cheaper to make, and worth less, every week.")
                    .font(.system(size: DSType.Size.micro))
                    .foregroundStyle(Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Green only when the release actually gives something back.
    ///
    /// A negative saving is not a small saving: the club would be charged MORE
    /// for the man it no longer has than for the one it kept, which is the whole
    /// mechanism dead money exists to enforce. It gets `danger`, the same colour
    /// as the dead column that caused it, and the footer counts how many rows
    /// are in that state.
    private func freedColor(_ freed: Int) -> Color {
        if freed > 0 { return .success }
        return freed < 0 ? .danger : .textTertiary
    }

    // MARK: - Next Year Section (#178)

    /// The league year the club is about to walk into, priced with the numbers
    /// that already exist.
    ///
    /// **Why it is its own section and not another bar.** The Cap Outlook bars
    /// below answer "does the shape hold for three years"; they are a trend. The
    /// question a GM actually asks in the last week of a season is a single-year
    /// one — *what am I working with in March* — and that answer was scattered
    /// across three places on this screen: the Y+1 bar had the ceiling and the
    /// commitment, the expiring block at the bottom had what comes off the books,
    /// and nothing at all had the money that survives the rollover. Same numbers,
    /// one place, stated as a balance rather than as a bar.
    ///
    /// **Every figure here is shared, not re-derived.** The ceiling comes from
    /// `ContractEngine.projectedCap` (the league's one projection), the
    /// commitment from ``committedCap(team:yearOffset:)`` — the same call the
    /// Y+1 bar renders, franchise tags and deferred extensions and all — and
    /// the expiring net from the
    /// same filter the Cap Outlook list prints. If this section and the bar ever
    /// disagreed, one of them would be lying.
    private func nextYearSection(team: Team) -> some View {
        let nextSeason = openYear + 1
        let cap = projectedCap(team: team, yearOffset: 1)
        let committed = committedCap(team: team, yearOffset: 1)
        let room = cap - committed

        return VStack(spacing: 12) {
            yearSectionHeader(
                icon: "calendar.badge.plus",
                title: "NEXT YEAR (\(nextSeason))",
                caption: "Projected — money already committed"
            )

            VStack(spacing: 12) {
                HStack(spacing: 0) {
                    capStatColumn(
                        label: "Projected Cap",
                        value: formatMillions(cap),
                        color: .textPrimary
                    )
                    capStatColumn(
                        label: "Committed",
                        value: formatMillions(committed),
                        color: committed > cap ? .danger : .textSecondary
                    )
                    capStatColumn(
                        label: "Projected Room",
                        value: "\(room >= 0 ? "+" : "")\(formatMillions(room))",
                        color: room >= 0 ? .success : .danger
                    )
                }

                Divider().overlay(Color.surfaceBorder.opacity(0.5))

                carriedMoneyBlock(team: team, nextSeason: nextSeason)

                Divider().overlay(Color.surfaceBorder.opacity(0.5))

                expiringNetBlock(team: team)

                // The rate is READ, not typed. The line it replaces claimed
                // "+7 %/yr" — a leftover from the hand-typed 1.07 that task #87
                // deleted from the arithmetic and forgot to delete from the
                // caption, so the screen spent a wave quoting a growth rate it
                // did not use. `capGrowthPerSeason` is the midpoint of the range
                // the rollover actually draws from, and if that range moves this
                // sentence moves with it.
                Text("Ceiling grows +\(capGrowthLabel)/yr (the league's own roll). Committed counts only money already under contract or promised — draft picks, re-signings and dead money from cuts not yet made are not in it.")
                    .font(.system(size: DSType.Size.micro))
                    .foregroundStyle(Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
            .padding(20)
            .cardBackground()
        }
    }

    /// **What follows the club through March.**
    ///
    /// Almost nothing does, and saying so is the point. `applyRelease` books a
    /// dead-cap residual against the OPEN league year only — the rollover's
    /// true-up rebuilds every club's usage from rostered salaries — so this
    /// season's dead money is not a future obligation and must not be shown as
    /// one. The one charge that genuinely survives is the restructure ledger
    /// (#102/#68): base salary already converted into bonus and prorated over
    /// the years still on the deal. That money is inside `annualSalary`, so it is
    /// already inside Committed above; it is named here because it is the part of
    /// Committed the club can no longer get rid of by cutting the player — cutting
    /// him ACCELERATES it instead, which is the second row.
    @ViewBuilder
    private func carriedMoneyBlock(team: Team, nextSeason: Int) -> some View {
        let proration = carriedProrationNextYear
        let exposure = carriedCutExposureNextYear
        let deadThisYear = deadMoney(team: team)

        VStack(alignment: .leading, spacing: 6) {
            // A year is a label, not a quantity: interpolating the Int straight
            // into a LocalizedStringKey runs it through the device locale's
            // grouping separator, which printed "CARRIED INTO 2 027" on a
            // fi/EU sim. Build the String first, the way seasonLabel does.
            Text("CARRIED INTO " + String(nextSeason))
                .font(.system(size: DSType.Size.micro, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Color.textSecondary)

            if proration > 0 {
                carriedRow(
                    icon: "arrow.uturn.forward",
                    label: "Restructured bonus still prorating",
                    detail: "inside Committed — cannot be cut away",
                    value: formatMillions(proration),
                    color: .warning
                )
                carriedRow(
                    icon: "person.fill.xmark",
                    label: "Accelerates if those men are released",
                    detail: "dead money the cuts would create",
                    value: formatMillions(exposure),
                    color: exposure > 0 ? .danger : .textTertiary
                )
            } else {
                carriedRow(
                    icon: "checkmark.circle",
                    label: "No restructured bonus carrying forward",
                    detail: "every cap charge next year belongs to a live deal",
                    value: formatMillions(0),
                    color: .textTertiary
                )
            }

            if deadThisYear > 0 {
                Text("This year's \(formatMillions(deadThisYear)) of dead money is NOT carried — the league-year rollover rebuilds the ledger from rostered salaries.")
                    .font(.system(size: DSType.Size.micro))
                    .foregroundStyle(Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func carriedRow(icon: String, label: String, detail: String, value: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: DSType.Size.micro))
                .foregroundStyle(color.opacity(0.85))
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: DSType.Size.caption))
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.system(size: DSType.Size.micro))
                    .foregroundStyle(Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: DSType.Size.caption, weight: .semibold).monospacedDigit())
                .foregroundStyle(color)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value). \(detail)")
    }

    /// The expiring-contracts arithmetic, moved up from the Cap Outlook card.
    ///
    /// It was the last line of a card about three seasons, but every term in it
    /// is a Y+1 term: the salary that comes off the books next March, what the
    /// market charges to replace those men, and the difference. Read next to the
    /// projected room above it, the net is the number the offseason plan is built
    /// on. The NAMES stay in the Cap Outlook list below — this is the total.
    @ViewBuilder
    private func expiringNetBlock(team: Team) -> some View {
        let ledger = expiringLedger(team: team)
        let count = expiringPlayers.count

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("EXPIRING AFTER THIS SEASON")
                    .font(.system(size: DSType.Size.micro, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Text("\(count) player\(count == 1 ? "" : "s")")
                    .font(.system(size: DSType.Size.micro).monospacedDigit())
                    .foregroundStyle(Color.textTertiary)
            }

            if count == 0 {
                Text("No contracts expiring — nothing comes off the books next March.")
                    .font(.system(size: DSType.Size.caption))
                    .foregroundStyle(Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 8) {
                    netTerm(label: "Cap freed", value: formatMillions(ledger.freed), color: .success)
                    netOperator("−")
                    netTerm(label: "Est. replacement", value: formatMillions(ledger.replacement), color: .textSecondary)
                    netOperator("=")
                    netTerm(
                        label: "Net",
                        value: "\(ledger.net >= 0 ? "+" : "")\(formatMillions(ledger.net))",
                        color: ledger.net >= 0 ? .success : .danger,
                        emphasised: true
                    )
                }
                Text("Replacement is each expiring player's own market value at this cap — not a veteran minimum. Names are listed in Cap Outlook below.")
                    .font(.system(size: DSType.Size.micro))
                    .foregroundStyle(Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func netTerm(label: String, value: String, color: Color, emphasised: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: DSType.Size.body, weight: emphasised ? .bold : .semibold).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: DSType.Size.micro))
                .foregroundStyle(Color.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value)")
    }

    private func netOperator(_ symbol: String) -> some View {
        Text(symbol)
            .font(.system(size: DSType.Size.caption, weight: .bold))
            .foregroundStyle(Color.textTertiary)
            .accessibilityHidden(true)
    }

    // MARK: - Cap Outlook Card

    /// What it costs to replace an expiring player — **his own market value**
    /// (task #87 / F11).
    ///
    /// This was a hardcoded per-position table of veteran-MINIMUM figures (QB
    /// 1 350, K/P 450) answering a MARKET question, and never scaled with the
    /// cap. `RosterEvaluationView:1255` answers the identical question with
    /// `estimateMarketValue` at the real cap; the two screens differed by ~30x.
    private func replacementCost(for player: Player, salaryCap: Int) -> Int {
        ContractEngine.estimateMarketValue(player: player, salaryCap: salaryCap)
    }

    /// The three-season trend. Y+1 is stated as a balance in the Next Year
    /// section above; this is the same year drawn as a bar, plus the two behind
    /// it and the roll call of who comes off the books.
    private func capOutlookCard(team: Team) -> some View {
        let expiring = expiringPlayers
        let taggedCount = players.filter(\.isFranchiseTagged).count
        // Gold discipline: one number in this list is the story — the biggest
        // deal coming off the books. Seventeen gold values were seventeen equal
        // alarms, which is the same as none.
        let largestExpiring = expiring.map(\.annualSalary).max() ?? 0

        return VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: DSType.Size.body, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
                Text("Cap Outlook")
                    .font(.system(size: DSType.Size.callout, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text("3 seasons")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            }

            Divider().overlay(Color.surfaceBorder)

            // Three years of committed money against the projected ceiling.
            // Y+1 alone answered "can I re-sign this guy"; it could not answer
            // "can I afford all three of these deals at once", which is the
            // question a dynasty is actually decided by.
            VStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { offset in
                    outlookYearRow(team: team, yearOffset: offset)
                }
            }

            Text("Committed money against the projected ceiling, on the same rules as the Next Year section above. The middle bar is that section, drawn as a bar.")
                .font(.system(size: DSType.Size.micro))
                .foregroundStyle(Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Divider().overlay(Color.surfaceBorder.opacity(0.5))

            // Expiring contracts list. The NET of this list lives in the Next
            // Year section above (#178) — what stays here is the roll call.
            if expiring.isEmpty {
                Text("No contracts expiring after this season")
                    .font(.subheadline)
                    .foregroundStyle(Color.textTertiary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text("Expiring Contracts")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        Text("\(expiring.count) player\(expiring.count == 1 ? "" : "s")")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Color.textTertiary)
                    }
                    .padding(.bottom, 8)

                    ForEach(expiring, id: \.id) { player in
                        HStack(spacing: 8) {
                            Text(player.position.rawValue)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color.textPrimary)
                                .frame(width: 30)
                                .padding(.vertical, 2)
                                .background(positionColor(player.position).opacity(0.8), in: RoundedRectangle(cornerRadius: 3))
                            Text(player.fullName)
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                                .lineLimit(1)
                            Spacer()
                            Text(formatMillions(player.annualSalary))
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(
                                    player.annualSalary == largestExpiring
                                        ? Color.accentGold
                                        : Color.textPrimary
                                )
                        }
                        .padding(.vertical, 3)
                    }
                }
            }

            // #141a: the tagged men are the reason this count can differ from a
            // naive "who is in the last year of his deal" read. Name them here
            // so the number is explained on the screen rather than looking like
            // a bug against the franchise-tag screen.
            if taggedCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "tag.fill")
                        .font(.system(size: DSType.Size.caption))
                    Text("\(taggedCount) franchise-tagged player\(taggedCount == 1 ? "" : "s") not counted — under club control for the tag year.")
                        .font(.system(size: DSType.Size.micro))
                }
                .foregroundStyle(Color.accentGold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }

        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .cardBackground()
    }

    private func outlookYearRow(team: Team, yearOffset: Int) -> some View {
        let cap = projectedCap(team: team, yearOffset: yearOffset)
        let committed = committedCap(team: team, yearOffset: yearOffset)
        let room = cap - committed
        let fraction = clampedFraction(committed, of: cap)
        let isCurrent = yearOffset == 0
        let barColor: Color = fraction > 1.0 ? .danger : (fraction > 0.9 ? .warning : .accentBlue)

        return VStack(spacing: 4) {
            HStack(spacing: 8) {
                Text(seasonLabel(yearOffset: yearOffset))
                    .font(.system(size: DSType.Size.caption, weight: isCurrent ? .bold : .semibold).monospacedDigit())
                    .foregroundStyle(isCurrent ? Color.textPrimary : Color.textSecondary)
                    .frame(width: 44, alignment: .leading)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: DSCornerRadius.tight)
                            .fill(Color.backgroundTertiary)
                            .frame(height: 10)
                        RoundedRectangle(cornerRadius: DSCornerRadius.tight)
                            .fill(barColor)
                            .frame(width: geo.size.width * min(fraction, 1.0), height: 10)
                    }
                }
                .frame(height: 10)

                Text(formatMillions(committed))
                    .font(.system(size: DSType.Size.caption, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.textPrimary)
                    .frame(width: 58, alignment: .trailing)

                Text("\(room >= 0 ? "+" : "")\(formatMillions(room))")
                    .font(.system(size: DSType.Size.caption, weight: .semibold).monospacedDigit())
                    .foregroundStyle(room >= 0 ? Color.success : Color.danger)
                    .frame(width: 62, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(seasonLabel(yearOffset: yearOffset)), committed \(formatMillions(committed)) of \(formatMillions(cap)), room \(formatMillions(room))")
    }

    // MARK: - Contract List Card

    private func contractListCard(team: Team) -> some View {
        let ordered = sortedContractPlayers
        let dead = deadMoney(team: team)

        return VStack(spacing: 0) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: DSType.Size.body, weight: .semibold))
                        .foregroundStyle(Color.textSecondary)
                    Text("Player Contracts")
                        .font(.system(size: DSType.Size.callout, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                }
                Spacer()
                Text("\(players.count) players")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Picker("Sort contracts", selection: $contractSort) {
                ForEach(ContractSort.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            Divider().overlay(Color.surfaceBorder)
                .padding(.horizontal, 20)

            if players.isEmpty {
                Text("No contracts on file")
                    .font(.subheadline)
                    .foregroundStyle(Color.textTertiary)
                    .padding(24)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(ordered.enumerated()), id: \.element.id) { index, player in
                        // The row still navigates to the profile; the agent
                        // button sits OUTSIDE the link so a tap on it opens the
                        // conversation instead of the player card.
                        HStack(spacing: 8) {
                            NavigationLink {
                                PlayerDetailView(player: player)
                            } label: {
                                contractRow(player: player, team: team)
                            }
                            .buttonStyle(.plain)

                            contactAgentButton(for: player)
                                .padding(.trailing, 20)
                        }

                        if index < ordered.count - 1 {
                            Divider()
                                .overlay(Color.surfaceBorder.opacity(0.5))
                                .padding(.horizontal, 20)
                        }
                    }
                }

                Divider().overlay(Color.surfaceBorder)
                    .padding(.horizontal, 20)

                // Total row. This is the number that used to lie: it summed
                // `annualSalary` and printed $221.5M under a Used-Cap card that
                // said $189.4M, because base salary is not what the cap is
                // charged. It sums the same cap hits the summary card does, and
                // the reconciliation line underneath names the difference.
                VStack(spacing: 4) {
                    HStack {
                        Text("Total cap hits")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        Text(formatMillions(activeCapUsage))
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(Color.textPrimary)
                    }
                    HStack {
                        Text("+ \(deadLabel(dead).lowercased()) \(formatMillions(dead))  =  used cap")
                            .font(.system(size: DSType.Size.micro))
                            .foregroundStyle(Color.textTertiary)
                        Spacer()
                        Text(formatMillions(team.currentCapUsage))
                            .font(.system(size: DSType.Size.micro, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
        }
        .frame(maxWidth: .infinity)
        .cardBackground()
    }

    // MARK: - Contact Agent Entry

    /// The uniform door into a contract conversation, compact enough for a
    /// ledger row. Same rule as everywhere else: it appears on every contract
    /// and gives away nothing about whether that camp will talk.
    private func contactAgentButton(for player: Player) -> some View {
        let badge = ContactAgentEntry.badge(for: player, season: career.currentSeason)
        return Button {
            negotiationPlayer = player
        } label: {
            VStack(spacing: 2) {
                Image(systemName: ContactAgentEntry.icon)
                    .font(.system(size: DSType.Size.body, weight: .semibold))
                    .foregroundStyle(Color.accentBlue)
                if let badge {
                    Text(badge)
                        .font(.system(size: DSType.Size.micro, weight: .bold))
                        .foregroundStyle(Color.accentBlue)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(width: 60)
            .padding(.vertical, 8)
            .background(Color.accentBlue.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Contact \(player.fullName)'s agent")
    }

    private func contractRow(player: Player, team: Team) -> some View {
        let hit = capHit(for: player)
        let share = team.salaryCap > 0 ? Double(hit) / Double(team.salaryCap) * 100.0 : 0

        return HStack(spacing: 12) {
            // Position badge
            Text(player.position.rawValue)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 34)
                .padding(.vertical, 4)
                .background(positionColor(player.position), in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))

            // Name
            Text(player.fullName)
                .font(.subheadline)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)

            Spacer()

            // Years remaining
            HStack(spacing: 4) {
                Text("\(player.contractYearsRemaining)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(yearsColor(player.contractYearsRemaining))
                Text("yr\(player.contractYearsRemaining == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            }

            // Cap hit + share of the ceiling
            VStack(alignment: .trailing, spacing: 0) {
                Text(formatMillions(hit))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.textSecondary)
                Text(String(format: "%.1f%%", share))
                    .font(.system(size: DSType.Size.caption).monospacedDigit())
                    .foregroundStyle(share >= 8 ? Color.warning : Color.textTertiary)
            }
            .frame(minWidth: 64, alignment: .trailing)

            Image(systemName: "chevron.right")
                .font(.system(size: DSType.Size.caption, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(player.fullName), \(player.position.rawValue), cap hit \(formatMillions(hit)), \(player.contractYearsRemaining) years remaining")
        .accessibilityHint("Opens player detail")
    }

    // MARK: - Cap Math

    /// The cap charge a player actually carries: his detailed contract's cap hit
    /// (base + prorated bonus) when a `Contract` row exists, and `annualSalary`
    /// when it does not. `PlayerRowView` reads the same precedence.
    private func capHit(for player: Player) -> Int {
        contractsByPlayer[player.id]?.capHit ?? player.annualSalary
    }

    /// Cap charged to players who are on the roster right now.
    private var activeCapUsage: Int {
        players.reduce(0) { $0 + capHit(for: $1) }
    }

    /// Cap charged to nobody on the roster — see ``deadMoneyCard`` for why this
    /// is derived rather than stored.
    private func deadMoney(team: Team) -> Int {
        team.currentCapUsage - activeCapUsage
    }

    /// The residual can go negative if a detailed contract's cap hit outruns the
    /// `annualSalary` the ledger was charged. That is a bookkeeping variance, not
    /// dead money, and calling it dead money would be a lie in the other
    /// direction from the bug this screen just fixed.
    private func deadLabel(_ dead: Int) -> String {
        dead < 0 ? "Ledger variance" : "Dead money"
    }

    /// Money already committed for a future season, in thousands.
    ///
    /// Reads the contract's own year table where one exists (`baseSalary[year] +
    /// prorated bonus`, exactly `yearlyBreakdown`'s arithmetic), and falls back
    /// to "still under contract that year → this year's salary" for the majority
    /// of players who only have `contractYearsRemaining`.
    ///
    /// Year 0 is the live ledger, dead money included, so the first bar ties back
    /// to the Used Cap number at the top of the screen.
    ///
    /// **#186 — every forward row counts, and a row SUPERSEDES the man's own
    /// contract for the years it covers.**
    ///
    /// Two corrections, both of them the same correction the cap gate in
    /// `ContractNegotiationView` now gets from `DealTargetYear.space`, so this
    /// screen and that gate cannot quote two different futures for one season:
    ///
    /// 1. **Not just tags.** `CommittedCapLedger`'s forward table used to hold
    ///    franchise tags and nothing else, so passing it the tagged men was the
    ///    whole roster of forward money. A deferred extension now parks its
    ///    charge in the same table — that is where #186 books a deal whose money
    ///    starts in a later league year — and this bar was blind to every one of
    ///    them. A GM who extended three men in one offseason saw a Y+2 bar with
    ///    none of that money on it, which is the exact failure the tag fix was
    ///    written to close, one mechanism later.
    /// 2. **Superseded, not stacked.** A deferred extension writes the contract
    ///    clock the day it is signed and deliberately leaves `annualSalary` at
    ///    the OLD rate until the rollover that binds it, so for those years the
    ///    man is both "still under contract" at the old number and carrying a
    ///    row at the new one. Adding both charges the club for a deal it signed
    ///    once. The coverage map does the netting: a player with a row for this
    ///    season contributes the ROW and nothing else.
    ///
    /// The schedule read survives rather than delegating wholesale to
    /// `DealTargetYear.space`: that function projects off the flat
    /// `annualSalary` (all it can do from a gate's vantage point), while this
    /// screen holds `contractsByPlayer` and can price a structured deal's year
    /// three at its actual base plus proration. Same forward rows, same
    /// exclusion rule, finer detail on the part it can see.
    ///
    /// The forward lookup keys off ``openYear``, not `career.currentSeason`,
    /// because offset 0 is the live ledger — see that property. The schedule
    /// branch's `contract.currentYear + yearOffset` is a DIFFERENT clock
    /// (`Contract.currentYear` is never advanced by the rollover — see
    /// `ContractEngine`) and is left as it stands; conflating the two fixes
    /// would hide one behind the other.
    private func committedCap(team: Team, yearOffset: Int) -> Int {
        guard yearOffset > 0 else { return team.currentCapUsage }

        // Player-scoped, not a blind sum of the table: an orphaned row (tagged
        // or extended, then released) must not keep charging a club for a man it
        // no longer employs.
        let coverage = CommittedCapLedger.forwardCoverage(
            playerIDs: players.map(\.id),
            careerID: career.id,
            season: openYear + yearOffset
        )

        let contracts = players.reduce(0) { total, player in
            // A man whose money for this season is on a forward row is priced by
            // that row, below — reading his contract as well would bill the club
            // twice for the same season.
            if coverage[player.id] != nil { return total }
            // #127: a franchise-tagged man's row still carries his EXPIRING deal
            // until the March rollover settles the tag onto it, so reading either
            // source for him would price a future year off a contract that ends
            // before it. His tag comes in below, at the number he was tagged for.
            if player.isFranchiseTagged { return total }
            if let contract = contractsByPlayer[player.id], contract.totalYears > 0 {
                let index = contract.currentYear + yearOffset
                guard index < contract.totalYears else { return total }
                let base = index < contract.baseSalary.count ? contract.baseSalary[index] : 0
                return total + base + contract.signingBonus / contract.totalYears
            }
            return player.contractYearsRemaining > yearOffset ? total + player.annualSalary : total
        }

        // Money promised for a league year that has not opened: the franchise
        // tag, and every deferred extension signed since. Without this the
        // year-1 bar reads a tagged quarterback as free, which is exactly the
        // year the club has just committed $32.8M to.
        return contracts + coverage.values.reduce(0, +)
    }

    /// The engine's cap-growth midpoint as a percentage, for captions.
    private var capGrowthLabel: String {
        String(format: "%.1f %%", ContractEngine.capGrowthPerSeason * 100)
    }

    /// The projected ceiling for a future league year.
    ///
    /// One line, and it delegates: `ContractEngine.projectedCap` is the league's
    /// single projection (task #87 / F15 — the arithmetic used to be hand-inlined
    /// in six places at three different growth rates). The Next Year section and
    /// the Cap Outlook bars call THIS, so a screen that showed two ceilings for
    /// the same season is not a shape the file can take.
    private func projectedCap(team: Team, yearOffset: Int) -> Int {
        ContractEngine.projectedCap(team.salaryCap, seasonsAhead: yearOffset)
    }

    /// **The one definition of "expiring" on this screen** (#141a), shared with
    /// `FranchiseTagView` (`contractYearsRemaining <= 1 && !isFranchiseTagged`).
    ///
    /// A tagged man is under club control for the tag year, so he is NOT expiring
    /// — the tag screen already said "0 expiring" while this card still listed
    /// him, which read as two screens disagreeing about the same roster. `<= 1`
    /// rather than `== 1` for the same reason `applyFranchiseTag` guards it: a
    /// rostered man whose clock has already run to 0 is expiring too.
    ///
    /// Hoisted out of `capOutlookCard` by #178 because the Next Year section
    /// prints the total of exactly this list and the Cap Outlook card prints its
    /// names; two filters would eventually be two different filters.
    private var expiringPlayers: [Player] {
        players.filter { $0.contractYearsRemaining <= 1 && !$0.isFranchiseTagged }
    }

    /// What the expiring class is worth: the salary that comes off the books, the
    /// market cost of replacing those men, and the difference.
    private func expiringLedger(team: Team) -> (freed: Int, replacement: Int, net: Int) {
        let list = expiringPlayers
        let freed = list.reduce(0) { $0 + $1.annualSalary }
        let replacement = list.reduce(0) {
            $0 + replacementCost(for: $1, salaryCap: team.salaryCap)
        }
        return (freed, replacement, freed - replacement)
    }

    /// Restructured signing-bonus proration that still charges the NEXT league
    /// year, in thousands.
    ///
    /// `restructureCarryYears` INCLUDES the current year (see the field's doc), so
    /// a man carrying `>= 2` is one whose proration is still running in Y+1 and a
    /// man at exactly 1 is paying his last slice this season. The charge is
    /// already folded into `annualSalary`, hence already inside the committed
    /// figure — this names it, it does not add it.
    private var carriedProrationNextYear: Int {
        players.reduce(0) { total, player in
            player.restructureCarryYears >= 2
                ? total + max(0, player.restructureProrationK)
                : total
        }
    }

    /// What releasing those same men in Y+1 would accelerate onto the books.
    ///
    /// The proration left AFTER next season's slice has been charged — `p × (N−1)`
    /// — which is exactly `Player.restructureDeadMoney` as it will stand once the
    /// rollover has decremented the clock. This is the number that makes a
    /// restructure a decision rather than free money (#68).
    private var carriedCutExposureNextYear: Int {
        players.reduce(0) { total, player in
            guard player.restructureCarryYears >= 2 else { return total }
            return total + max(0, player.restructureProrationK) * (player.restructureCarryYears - 1)
        }
    }

    /// The label under a Cap Outlook bar. Reads ``openYear``, not the raw
    /// counter, so the year printed on a bar is the year `committedCap` priced
    /// it at.
    private func seasonLabel(yearOffset: Int) -> String {
        "\(openYear + yearOffset)"
    }

    private var sortedContractPlayers: [Player] {
        switch contractSort {
        case .capHit:
            return players.sorted { capHit(for: $0) > capHit(for: $1) }
        case .salary:
            return players.sorted { $0.annualSalary > $1.annualSalary }
        case .years:
            return players.sorted {
                $0.contractYearsRemaining == $1.contractYearsRemaining
                    ? capHit(for: $0) > capHit(for: $1)
                    : $0.contractYearsRemaining > $1.contractYearsRemaining
            }
        case .expiring:
            return players.sorted {
                $0.contractYearsRemaining == $1.contractYearsRemaining
                    ? capHit(for: $0) > capHit(for: $1)
                    : $0.contractYearsRemaining < $1.contractYearsRemaining
            }
        }
    }

    /// The escape-cost card's rows.
    ///
    /// **Eight, and not the whole roster.** The full ledger is the Player
    /// Contracts card at the bottom of this screen; a table long enough to need
    /// its own scroll would just be that card with two more columns, and the
    /// question this one answers ("where is my room, and what is it going to
    /// cost me") is a shortlist question. Eight rows also keep the card inside a
    /// single screenful at the iPad's portrait measure, which is what lets the
    /// footer's ratio be read against the rows that produced it.
    ///
    /// The sort runs over the already-priced ``cutCosts``, so changing the
    /// ordering costs one sort and not ninety engine calls.
    private var topCutCosts: [CutCost] {
        let ordered: [CutCost]
        switch cutSort {
        case .capHit:
            ordered = cutCosts.sorted { $0.capHit > $1.capHit }
        case .freed:
            // Cap hit breaks the tie, for the same reason it does in
            // `sortedContractPlayers`: a run of equal figures should still read
            // biggest-contract-first rather than in fetch order.
            ordered = cutCosts.sorted {
                $0.freed == $1.freed ? $0.capHit > $1.capHit : $0.freed > $1.freed
            }
        case .dead:
            ordered = cutCosts.sorted {
                $0.deadCap == $1.deadCap ? $0.capHit > $1.capHit : $0.deadCap > $1.deadCap
            }
        }
        return Array(ordered.prefix(8))
    }

    /// The share of the league year still unpaid, for the release split (#26).
    ///
    /// Same adapter, same spelling as `CapComplianceView`'s: the two screens
    /// price the same release, and a Cap screen quoting a full-season saving
    /// against a workspace quoting a Week 12 one would be two answers for one
    /// cut.
    private var leagueYearRemaining: Double {
        CapManagementEngine.leagueYearRemaining(
            phase: career.currentPhase,
            week: career.currentWeek
        )
    }

    // MARK: - Helpers

    private func loadData() {
        guard let teamID = career.teamID else { return }

        let teamDescriptor = FetchDescriptor<Team>(predicate: #Predicate { $0.id == teamID })
        team = try? modelContext.fetch(teamDescriptor).first

        guard let fetchedTeamID = team?.id else { return }
        var playerDescriptor = FetchDescriptor<Player>(predicate: #Predicate { $0.teamID == fetchedTeamID })
        playerDescriptor.sortBy = [SortDescriptor(\.annualSalary, order: .reverse)]
        players = (try? modelContext.fetch(playerDescriptor)) ?? []

        // Detailed deals for this club. Team IDs are minted per save, so the
        // team predicate already scopes the fetch to this career.
        let contractDescriptor = FetchDescriptor<Contract>(
            predicate: #Predicate<Contract> { $0.teamID == fetchedTeamID }
        )
        let contracts = (try? modelContext.fetch(contractDescriptor)) ?? []
        contractsByPlayer = Dictionary(contracts.map { ($0.playerID, $0) }, uniquingKeysWith: { first, _ in first })

        // After the contracts, never before: a release is priced off the man's
        // detailed deal where one exists, and pricing the roster against a stale
        // (or empty) contract map would quote every structured deal at the
        // implied-guarantee proxy instead of its own bonus schedule.
        loadCutCosts()
        loadReleaseReceipts(teamID: fetchedTeamID)
    }

    /// Prices a release for every man on the roster, once per load.
    ///
    /// No fetch of its own — `players` and `contractsByPlayer` are already in
    /// hand and the split is pure arithmetic over them, which is why this can
    /// afford to run for the whole roster rather than for the eight rows that
    /// will be drawn. Running it for eight would mean re-running it whenever the
    /// sort changed, since a different ordering picks different eight.
    private func loadCutCosts() {
        // Sandbox has no cap rules to escape: the engine returns zero dead cap
        // and relieves the whole salary, so every row would restate the salary
        // column. An empty list is what makes ``escapeCostCard()`` absent.
        guard career.capMode != .sandbox else {
            cutCosts = []
            return
        }

        let remaining = leagueYearRemaining

        cutCosts = players.compactMap { player in
            // A camp body's minimum salary was never added to
            // `Team.currentCapUsage`, so the engine prices his release at zero
            // in BOTH columns (#205a). A row of zeroes is not a lever, and
            // ninety of them at the bottom of the ordering would still push real
            // contracts off the list under the Freed sort.
            guard !CampRosterEngine.isCampBody(player) else { return nil }

            let split = CapManagementEngine.releaseCapSplit(
                player: player,
                contract: contractsByPlayer[player.id],
                capMode: career.capMode,
                leagueYearRemaining: remaining
            )

            return CutCost(
                player: player,
                capHit: capHit(for: player),
                deadCap: split.deadCap,
                freed: split.capSavings,
                unpaidRemainder: split.salaryRelieved + split.proratedPerYear
            )
        }
    }

    /// Resolves this season's recorded releases into names + dead-cap charges.
    ///
    /// Only the rows that will actually be rendered are resolved to players: the
    /// dead-cap totals live on the `RosterCut` rows themselves, so the sum costs
    /// one fetch and the names cost at most six more.
    ///
    /// Keyed off the RAW `currentSeason` and deliberately not off ``openYear``:
    /// every writer stamps `RosterCut.seasonYear` with the raw counter
    /// (`RosterCutView`, `CapManagementEngine.releasePlayer`), so this is a
    /// lookup by the stamp that exists, not a statement about which league year
    /// the money sits in. The charges themselves are already in
    /// `team.currentCapUsage`, which is the open year's ledger — these rows only
    /// attribute it to names.
    private func loadReleaseReceipts(teamID: UUID) {
        let season = career.currentSeason
        let cutDescriptor = FetchDescriptor<RosterCut>(
            predicate: #Predicate<RosterCut> { $0.teamID == teamID && $0.seasonYear == season }
        )
        // One charge per man per league year (#188). Two writers can describe
        // the SAME release — the engine's receipt and the camp cutdown screen's
        // own row — and summing both would show a club twice the dead money it
        // actually carries. The rows agree on the amount, so keeping the first
        // per player is enough; a man cannot be released twice in one year
        // without being signed again in between, and that re-signing would not
        // reuse the charge.
        var seenPlayers: Set<UUID> = []
        let cuts = ((try? modelContext.fetch(cutDescriptor)) ?? [])
            .filter { $0.deadCap > 0 && $0.claimedByTeamID == nil }
            .sorted { $0.deadCap > $1.deadCap }
            .filter { seenPlayers.insert($0.playerID).inserted }

        releaseDeadCapTotal = cuts.reduce(0) { $0 + $1.deadCap }
        releaseOverflowCount = max(0, cuts.count - 6)

        releaseReceipts = cuts.prefix(6).map { cut in
            let playerID = cut.playerID
            let descriptor = FetchDescriptor<Player>(predicate: #Predicate<Player> { $0.id == playerID })
            let name = (try? modelContext.fetch(descriptor).first)?.fullName ?? "Released player"
            return ReleaseReceipt(id: cut.id, name: name, deadCap: cut.deadCap, seasonYear: cut.seasonYear)
        }
    }

    private func usagePercentage(team: Team) -> Double {
        guard team.salaryCap > 0 else { return 0 }
        return Double(team.currentCapUsage) / Double(team.salaryCap)
    }

    private func clampedFraction(_ value: Int, of total: Int) -> Double {
        guard total > 0 else { return 0 }
        return max(0, Double(value) / Double(total))
    }

    private func capUsageColor(team: Team) -> Color {
        let pct = usagePercentage(team: team)
        if pct > 1.0 { return .danger }
        if pct > 0.9 { return .warning }
        return .textSecondary
    }

    private func capBarGradient(team: Team) -> LinearGradient {
        let pct = usagePercentage(team: team)
        let color: Color = pct > 1.0 ? .danger : (pct > 0.9 ? .warning : .accentBlue)
        return LinearGradient(
            colors: [color.opacity(0.7), color],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func positionColor(_ position: Position) -> Color {
        switch position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }

    /// Contract runway is a countdown in years, not a rating, so P7 rule 2
    /// applies: the status palette at a stated threshold, never the 0–99 rating
    /// ladder. Gold left this ladder because P7 reserves it for
    /// "primary/current" — a two-year deal is neither.
    ///
    /// Thresholds are the league rule and stay here; the twin in
    /// `PlayerContractView.yearsColor` states the same three.
    private func yearsColor(_ years: Int) -> Color {
        if years >= 3 { return .forStatus(.ok) }      // comfortably under contract
        if years == 2 { return .forStatus(.neutral) } // no decision due yet
        if years == 1 { return .forStatus(.warn) }    // expiring — decide this year
        return .forStatus(.bad)                       // already off the books
    }

    private func formatMillions(_ thousands: Int) -> String {
        let sign = thousands < 0 ? "-" : ""
        let magnitude = abs(thousands)
        let millions = Double(magnitude) / 1000.0
        if millions >= 1.0 {
            return sign + String(format: "$%.1fM", millions)
        }
        // Nothing is not a quantity in thousands: "$0K" reads as a small sum
        // rounded down, when the whole point of the line is that there is none.
        if magnitude == 0 { return "$0" }
        return sign + "$\(magnitude)K"
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        CapOverviewView(career: Career(
            playerName: "John Doe",
            role: .gm,
            capMode: .simple
        ))
    }
    .modelContainer(for: [Career.self, Team.self, Player.self], inMemory: true)
}
