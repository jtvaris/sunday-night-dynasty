import SwiftUI
import SwiftData

// MARK: - FranchiseTagView

struct FranchiseTagView: View {

    let career: Career

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var team: Team?
    @State private var teamPlayers: [Player] = []
    @State private var allPlayers: [Player] = []
    @State private var showSkipConfirmation = false

    /// The player whose agent is on the phone. Non-nil while the Contact Agent
    /// thread is open.
    @State private var negotiationPlayer: Player?

    /// Which tag's arithmetic is open, if any.
    ///
    /// One piece of state at BODY level driving one `.sheet(item:)`, and
    /// deliberately not a `.popover(isPresented:)` hung off each row: eight rows
    /// in a `ForEach` sharing a single `@State` anchor the popover to whichever
    /// row SwiftUI laid out last, not to the one that was tapped. The request
    /// carries the whole quote (see `TagBreakdownRequest`), so the presented
    /// sheet has no nil case to render.
    @State private var tagBreakdown: TagBreakdownRequest?

    /// Every position this screen has to price, quoted once per load — see
    /// `buildTagQuotes`.
    @State private var tagQuotes: [Position: TagQuote] = [:]

    /// `Team.id` -> abbreviation, so the breakdown can say who the five men on
    /// it play for. Fetched with the rest of the screen's data, once.
    @State private var teamAbbreviations: [UUID: String] = [:]

    /// What each position's tag cost the LAST time this screen was opened —
    /// read from `CareerScopedDefaults` at the top of the first load and then
    /// left alone for the rest of the visit. See `captureTagPriceBaseline`.
    @State private var previousQuotes: [Position: TagPriceMemory.Quote] = [:]

    /// One baseline per visit, not one per `loadData`.
    @State private var baselineCaptured = false

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            Group {
                if team != nil {
                    ScrollView {
                        VStack(spacing: 24) {
                            capBanner
                            tagRulesBanner
                            if !taggedPlayers.isEmpty {
                                taggedSection
                            }
                            expiringPlayersSection
                            skipTagButton
                        }
                        .padding(24)
                        .frame(maxWidth: DSLayout.contentMeasure)
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    ProgressView()
                        .tint(Color.accentGold)
                        .padding(.top, 80)
                }
            }
        }
        .navigationTitle("Franchise Tag")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            loadData()
        }
        .alert("Skip Franchise Tag?", isPresented: $showSkipConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Skip", role: .destructive) {
                CareerScopedDefaults.set(true, "franchiseTagVisited")
                dismiss()
            }
        } message: {
            Text("Are you sure? You won't be able to franchise tag any player this offseason.")
        }
        .sheet(item: $tagBreakdown) { request in
            TagBreakdownSheet(request: request, tagSeasonLabel: seasonLabel(nextSeason))
        }
        .fullScreenCover(item: $negotiationPlayer) { player in
            // ContractNegotiationView supplies its own "Close" toolbar item, so
            // the wrapper must NOT add a second one.
            NavigationStack {
                ContractNegotiationView(
                    player: player,
                    negotiationType: .extend,
                    teamCapSpace: max(0, team?.availableCap ?? 0),
                    // #186 — the gate must plan the deal this screen BOOKS. It
                    // replaces an expiring contract (see `onDealCompleted`
                    // below), so the money starts in the league year that is
                    // open; the default `.extendExisting` would have read the
                    // expiring man's last year as "one more year to wait" and
                    // quoted him against next season's projected cap.
                    dealApplication: .replaceContract,
                    onDealCompleted: { offer in
                        // Re-sign: the expiring deal is REPLACED, not extended.
                        // Through the engine so the club's cap ledger, the
                        // negotiated signing bonus and the detailed contract all
                        // move with the salary.
                        ContractEngine.applyNegotiatedDeal(
                            player: player,
                            team: team,
                            offer: offer,
                            application: .replaceContract,
                            capMode: career.capMode,
                            careerID: career.id,
                            modelContext: modelContext
                        )
                        // **The rollover's decrement, compensated for** — the
                        // same +1 `FinalPushView.applyReSignOffer` carries, and
                        // for the same reason. This screen runs in Review
                        // Roster, i.e. BEFORE `executeNewLeagueYear`, whose
                        // expiry loop decrements every contract in the league.
                        // `applyNegotiatedDeal(.replaceContract)` writes
                        // `contractYearsRemaining = offer.years`, so a deal
                        // agreed here was silently one year short and a 1-year
                        // re-sign expired the instant the league year turned —
                        // the man appeared as LOST on the very next screen,
                        // thirty seconds after being kept. (`FinalPushView`'s
                        // note lists this screen as an in-season path where "no
                        // rollover follows"; it is not one.)
                        //
                        // Conditional on the rollover still being PENDING, using
                        // the same test `WeekAdvancer` gates its own fallback
                        // with, so a screen re-entered after March cannot hand
                        // out a free extra year.
                        if career.lastRolloverSeason < career.currentSeason {
                            player.contractYearsRemaining += 1
                        }
                        try? modelContext.save()
                        loadData()
                        // No dismiss — the thread shows the signed card and the
                        // user closes it with Done.
                    }
                )
            }
        }
    }

    // MARK: - Cap Banner

    /// **The banner shows NEXT league year, because that is the year the tag is
    /// a decision about** (#127).
    ///
    /// It used to show "Available Cap Space" — this year's room — and the tag
    /// used to move it, which is how the bug announced itself: tagging a $36.9M
    /// quarterback at $32.8M *raised* the number by $4.0M. Both halves are now
    /// fixed, and the cheapest way to make the fix legible is to stop quoting a
    /// year the decision cannot touch. The tag charges the league year that opens
    /// in March; so does everything else on this screen.
    ///
    /// The three numbers are the ones a GM actually plans against, and each is
    /// read from the source the rest of the app already uses:
    ///
    /// * **Projected cap** — `salaryCap × (1 + capGrowthPerSeason)`, the engine's
    ///   own midpoint roll. Same one line `RosterEvaluationView`'s Next Season
    ///   Outlook, `CapOverviewView`'s year bars and the dashboard's 3-Year Cap
    ///   tile use, so no two screens can show the user two different futures
    ///   (task #87 / F15 closed exactly that split once already).
    /// * **Committed** — contracts that are still running next year
    ///   (`contractYearsRemaining > 1`) plus tags already applied. A man on an
    ///   expiring deal is deliberately NOT in it: if he is not re-signed he costs
    ///   nothing, and that is the whole question this screen asks.
    /// * **Projected space** — the difference, and the number "Cap after tag" on
    ///   every row is measured against.
    private var capBanner: some View {
        VStack(spacing: 10) {
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Projected \(seasonLabel(nextSeason)) Cap")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                    Text(formatMillions(projectedNextYearCap))
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.accentGold)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Committed to \(seasonLabel(nextSeason))")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                    Text(formatMillions(committedNextYear))
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.textPrimary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Projected Space")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                    Text(formatMillions(projectedNextYearSpace))
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(projectedNextYearSpace >= 0 ? Color.success : Color.danger)
                }
            }

            Divider().overlay(Color.surfaceBorder.opacity(0.6))

            // The current year is kept, small and explicitly labelled, because a
            // GM still wants to know where he stands today — but it is no longer
            // the headline and, more to the point, tagging no longer moves it.
            HStack(spacing: 8) {
                Text("\(seasonLabel(career.currentSeason)) cap space")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textTertiary)
                Text(formatMillions(team?.availableCap ?? 0))
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle((team?.availableCap ?? 0) >= 0 ? Color.textSecondary : Color.danger)
                Text("— unchanged by tagging")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textTertiary)
                Spacer()
                Text("\(expiringPlayers.count) expiring")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
                Text("\u{2022}")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textTertiary)
                // The tag is a one-shot, and the only place that said so was a
                // sentence buried in the grey rules paragraph — while eight rows
                // each offered a gold Apply Tag. The count of the resource
                // belongs next to the count of men it has to be spent on.
                Text(hasUsedTag ? "0 tags left" : "1 tag available")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(hasUsedTag ? Color.textTertiary : Color.accentGold)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(Color.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.surfaceBorder, lineWidth: 1)
        )
    }

    // MARK: - Next League Year Projection (#127)

    /// The league year a tag applied on this screen charges.
    ///
    /// `currentSeason + 1` and not `currentSeason`: `WeekAdvancer` only
    /// increments the year at the roster-cuts → regular-season transition, so
    /// every offseason phase of a given league year reads the same number, and
    /// the year being decided is always the one after it. Same arithmetic
    /// `RosterEvaluationView` labels its "Next Season Outlook" with.
    private var nextSeason: Int { career.currentSeason + 1 }

    /// The club's cap rolled forward one league year at the engine's own growth
    /// midpoint — one formula, shared with every other projection in the app.
    private var projectedNextYearCap: Int {
        let cap = team?.salaryCap ?? ContractEngine.openingSalaryCap
        return Int(Double(cap) * (1.0 + ContractEngine.capGrowthPerSeason))
    }

    /// Salary already owed for next league year, in thousands.
    ///
    /// `contractYearsRemaining > 1` is "still under contract after this year's
    /// rollover" — the same test `ContractTimelineView` and `CapOverviewView`
    /// project a future year's committed cap with. Tagged men are excluded from
    /// the sum and added back through the forward ledger instead, so the tag is
    /// counted at the number the user was quoted rather than at the salary his
    /// expiring deal happens to still be carrying.
    private var committedNextYear: Int {
        let underContract = teamPlayers
            .filter { $0.contractYearsRemaining > 1 && !$0.isFranchiseTagged }
            .reduce(0) { $0 + $1.annualSalary }
        // Walked from the ROSTER rather than summed straight off the ledger, so
        // a man who was tagged and then released still owes nothing here. His
        // orphaned row survives until the rollover drops it (`consumeForward`
        // takes everything due, matched or not), and reading the ledger blind
        // would keep charging the club for a player it no longer employs.
        let tags = taggedPlayers.reduce(0) { $0 + tagCommitment(for: $1) }
        return underContract + tags
    }

    private var projectedNextYearSpace: Int { projectedNextYearCap - committedNextYear }

    /// `2027`, never `2 027` — a league year is a name, not a quantity, so it
    /// must not pick up the locale's group separator.
    private func seasonLabel(_ season: Int) -> String { String(season) }

    // MARK: - Rules Banner

    /// The banner carries BOTH options' league year, not just the tag's.
    ///
    /// The row offers a tag and a Contact Agent thread side by side, and the two
    /// land in different years: the tag is a forward commitment against
    /// `nextSeason` and leaves today's room alone, while a re-sign agreed here
    /// REPLACES the expiring deal on the spot (the `.replaceContract` gate at the
    /// top of this file) and so charges the open year first. The screen used to
    /// state only the tag's year, which left the user comparing a `nextSeason`
    /// price against a conversation that quotes him this year's — and never said
    /// what keeping the man does to the projected space the tag is being weighed
    /// against. It is said once here rather than on every row, and deliberately
    /// without a price: what the agent will ASK is what Contact Agent is for
    /// (#127).
    private var tagRulesBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Color.accentGold)
            VStack(alignment: .leading, spacing: 2) {
                Text("Franchise Tag Rules")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text("You can apply up to 1 franchise tag per season. A tagged player finishes his current deal, then plays \(seasonLabel(nextSeason)) at the average of the top 5 salaries at his position — so the tag charges the \(seasonLabel(nextSeason)) cap, not this year's. Re-signing a man through Contact Agent instead replaces his expiring deal on the spot: it charges your \(seasonLabel(career.currentSeason)) space the moment he signs, and commits \(seasonLabel(nextSeason)) on top.")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Color.accentGold.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentGold.opacity(0.3), lineWidth: 1))
    }

    // MARK: - Tagged Players Section

    private var taggedSection: some View {
        sectionCard(title: "Tagged Players", icon: "tag.fill") {
            VStack(spacing: 0) {
                ForEach(Array(taggedPlayers.enumerated()), id: \.element.id) { index, player in
                    taggedPlayerRow(player)
                    if index < taggedPlayers.count - 1 {
                        Divider()
                            .overlay(Color.surfaceBorder.opacity(0.5))
                            .padding(.horizontal, 8)
                    }
                }
            }
        }
    }

    private func taggedPlayerRow(_ player: Player) -> some View {
        // Read once for the row. `tagCommitment` decodes the forward ledger out
        // of `UserDefaults`, and the row now shows the number, speaks it and
        // hands it to the sheet — three reads of a JSON table on a screen that
        // redraws on a timer, where one will do.
        let booked = tagCommitment(for: player)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                positionBadge(player.position)

                VStack(alignment: .leading, spacing: 2) {
                    Text(player.fullName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Text("Age \(player.age)")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                        Text("\(player.overall) OVR")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.forRating(player.overall))
                        // The deal the tag is an alternative to. Every expiring
                        // row states it; the tagged man's row did not, so his
                        // tag figure had nothing on the row to be read against.
                        Text(formatMillions(player.annualSalary) + "/yr")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Color.textTertiary)
                    }
                }

                Spacer()

                // The booked tag opens the same breakdown the expiring rows do,
                // carrying its booked number with it. It is the one figure on
                // the screen that does NOT move with the market — the club
                // agreed a price and owns it — and the sheet is the only place
                // that can say so next to the five salaries that have moved
                // since.
                Button {
                    tagBreakdown = tagBreakdownRequest(for: player, booked: booked)
                } label: {
                    VStack(alignment: .trailing, spacing: 2) {
                        // #127: `annualSalary` is still the EXPIRING deal — the tag has
                        // not been paid yet and does not overwrite it until the rollover
                        // — so the number quoted here comes off the forward commitment
                        // the tag actually booked. Showing `annualSalary` would now
                        // print the old contract under the words "Tag Value".
                        Text(formatMillions(booked))
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Color.accentGold)
                        HStack(spacing: 3) {
                            Text("\(seasonLabel(nextSeason)) Tag")
                                .font(.system(size: DSType.Size.caption).weight(.medium))
                            Image(systemName: "info.circle")
                                .font(.system(size: DSType.Size.micro, weight: .semibold))
                        }
                        .foregroundStyle(Color.textTertiary)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(seasonLabel(nextSeason)) tag \(formatMillions(booked)) for \(player.fullName)")
                .accessibilityHint("Shows the five salaries the \(player.position.rawValue) tag averages")

                Button {
                    removeTag(from: player)
                } label: {
                    Text("Remove")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.danger)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.danger.opacity(0.15), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.danger.opacity(0.4), lineWidth: 1))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            // A tag is not a terminal state. The man can still sign a long deal
            // — `applyNegotiatedDeal` rescinds the tag's books on signature — and
            // this row was the only one on the screen with no way to make the
            // call, so the one screen that applies tags offered no way to convert
            // one into a contract.
            contactAgentButton(for: player)
                .padding(.leading, 46)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Expiring Players Section

    private var expiringPlayersSection: some View {
        sectionCard(title: "Expiring Contracts (\(expiringPlayers.count) players)", icon: "clock.badge.exclamationmark") {
            if expiringPlayers.isEmpty {
                emptyStateRow("No players with expiring contracts.")
            } else {
                // Read once for the whole section rather than per row: the
                // favourite has to price every candidate's tag to find itself.
                let favouriteID = tagFavourite?.id
                VStack(spacing: 0) {
                    ForEach(Array(expiringPlayers.enumerated()), id: \.element.id) { index, player in
                        expiringPlayerRow(player, isFavourite: player.id == favouriteID)
                        if index < expiringPlayers.count - 1 {
                            Divider()
                                .overlay(Color.surfaceBorder.opacity(0.5))
                                .padding(.horizontal, 8)
                        }
                    }
                }
            }
        }
    }

    private func expiringPlayerRow(_ player: Player, isFavourite: Bool) -> some View {
        let tagCost = tagValue(for: player.position)
        // #127. This used to be `availableCap − tagCost + annualSalary`: next
        // year's tag netted against this year's room, with this year's salary
        // credited back as though the season already played were about to be
        // refunded. Every term was from the wrong year. The tag charges
        // `nextSeason`, where the man's expiring deal is already worth nothing —
        // so the honest answer is simply projected space less the tag.
        //
        // Both terms are snapped to the tenth of a million the screen prints
        // first. Subtracting the exact thousands and rounding once at the end
        // showed $70.8M − $15.6M = $55.3M on one row (70 845 − 15 550 = 55 295),
        // because the two operands rounded in opposite directions. Every row
        // here has to survive the subtraction the reader does in his head
        // against the banner.
        let capAfterTag = roundedToDisplay(projectedNextYearSpace) - roundedToDisplay(tagCost)
        let recommendation = smartRecommendation(for: player)
        // Read once for the row: the chip renders it and the button speaks it.
        let priceChange = tagPriceChange(for: player.position)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                positionBadge(player.position)

                VStack(alignment: .leading, spacing: 2) {
                    Text(player.fullName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Text("Age \(player.age)")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                        Text("\(player.overall) OVR")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.forRating(player.overall))
                        Text(formatMillions(player.annualSalary) + "/yr")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Color.textTertiary)
                    }
                }

                Spacer()

                // **The derived number now says where it derives from.** The
                // rules banner states the rule ("the average of the top 5
                // salaries at his position"); it cannot state the five
                // salaries, and until this sheet existed nothing on the screen
                // could — which is also why the price moving between two visits
                // read as the app changing its mind.
                Button {
                    tagBreakdown = tagBreakdownRequest(for: player, booked: nil)
                } label: {
                    VStack(alignment: .trailing, spacing: 2) {
                        // Not gold. Eight rows priced in the screen's emphasis
                        // colour made twenty gold elements out of a screen with one
                        // decision on it, and a price the club pays at most once is
                        // not a call to action — the headline number and the
                        // endorsed row's pill are. Once the tag is spent this figure
                        // is the price of a move the row can no longer make, so it
                        // drops again to tertiary.
                        Text(formatMillions(tagCost))
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(hasUsedTag ? Color.textTertiary : Color.textPrimary)
                        HStack(spacing: 3) {
                            Text("Tag Cost")
                                .font(.system(size: DSType.Size.caption).weight(.medium))
                            Image(systemName: "info.circle")
                                .font(.system(size: DSType.Size.micro, weight: .semibold))
                        }
                        .foregroundStyle(Color.textTertiary)
                        if let priceChange {
                            tagChangeChip(priceChange)
                        }
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(spokenTagCost(tagCost, for: player, change: priceChange))
                .accessibilityHint("Shows the five salaries the \(player.position.rawValue) tag averages")

                if hasUsedTag {
                    // Already used the tag — show disabled state
                    Text("Tag Used")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textTertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.backgroundTertiary, in: Capsule())
                } else {
                    Button {
                        applyTag(to: player, tagCost: tagCost)
                    } label: {
                        // One tag, eight rows: a filled gold pill on every one
                        // of them reads as eight primary actions for a resource
                        // the club has exactly one of. Only the favourite is
                        // filled; the rest are the same action, offered rather
                        // than urged.
                        Text("Apply Tag")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(isFavourite ? Color.backgroundPrimary : Color.accentGold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                isFavourite ? Color.accentGold : Color.accentGold.opacity(0.10),
                                in: Capsule()
                            )
                            .overlay(Capsule().strokeBorder(Color.accentGold.opacity(isFavourite ? 0 : 0.45), lineWidth: 1))
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            // Recommendation. `textPrimary`, not secondary: this is the only
            // line in the row that tells the GM what to do, and it was the
            // faintest string on it.
            HStack(spacing: 6) {
                Image(systemName: recommendation.icon)
                    .font(.caption)
                    .foregroundStyle(recommendation.color)
                Text(recommendation.text)
                    .font(.caption)
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 46)

            // Cap impact. Only while a tag is there to spend: `committedNextYear`
            // already carries the tag this club HAS applied, so once it is spent
            // this line was projecting the room left after a SECOND tag — a
            // number the rules three cards up forbid.
            if !hasUsedTag {
                HStack(spacing: 6) {
                    Image(systemName: "dollarsign.circle")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                    Text("\(seasonLabel(nextSeason)) space after tag: \(formatMillions(capAfterTag))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(capAfterTag >= 0 ? Color.textTertiary : Color.danger)
                    if capAfterTag < 0 {
                        Text("OVER CAP")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.danger)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.danger.opacity(0.15), in: Capsule())
                    }
                }
                .padding(.leading, 46)
            }

            // The alternative to the tag is a conversation, so it belongs on the
            // same row as the tag. Identical wording and behaviour to every other
            // Contact Agent button in the app — it never says whether this camp
            // will actually talk.
            contactAgentButton(for: player)
                .padding(.leading, 46)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Contact Agent Entry

    private func contactAgentButton(for player: Player) -> some View {
        let badge = ContactAgentEntry.badge(for: player, season: career.currentSeason)
        return Button {
            negotiationPlayer = player
        } label: {
            HStack(spacing: 6) {
                Image(systemName: ContactAgentEntry.icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(ContactAgentEntry.title)
                    .font(.caption.weight(.semibold))
                if let badge {
                    Text(badge)
                        .font(.system(size: DSType.Size.caption, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentBlue.opacity(0.18), in: Capsule())
                }
            }
            .foregroundStyle(Color.accentBlue)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.accentBlue.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.accentBlue.opacity(0.35), lineWidth: 1))
            // The pill stays a pill; the finger gets the 44pt it is entitled to.
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Contact \(player.fullName)'s agent")
    }

    // MARK: - Smart Recommendations

    private struct Recommendation {
        let text: String
        let icon: String
        let color: Color
        /// Whether the screen is actually steering the one tag at this man. It
        /// is what decides which single pill is filled — see `tagFavourite`.
        let endorsesTag: Bool
    }

    /// The judgement of the man never changes; the decision it is advice ABOUT
    /// does. Once the tag is spent, "strongly consider tagging" recommends a
    /// move this row has already disabled, so each tier states the choice that
    /// is still open — re-sign him through his agent, or let him walk.
    private func smartRecommendation(for player: Player) -> Recommendation {
        let isPastPeak = player.age > player.position.peakAgeRange.upperBound

        if player.overall >= 85 {
            return Recommendation(
                text: hasUsedTag
                    ? "Elite player — re-sign him or lose him for nothing."
                    : "Elite player — strongly consider tagging.",
                icon: "star.fill",
                color: .accentGold,
                endorsesTag: true
            )
        } else if isPastPeak {
            return Recommendation(
                text: hasUsedTag
                    ? "Aging veteran at \(player.age) — let him walk unless he re-signs cheap."
                    : "Aging veteran at \(player.age) — tag cost may not be worth it.",
                icon: "exclamationmark.triangle.fill",
                color: .warning,
                endorsesTag: false
            )
        } else if player.overall < 75 {
            return Recommendation(
                text: "Role player — better to let walk and address in free agency.",
                icon: "arrow.right.circle.fill",
                color: .textTertiary,
                endorsesTag: false
            )
        } else {
            return Recommendation(
                text: hasUsedTag
                    ? "Solid contributor — re-sign him if the price is right."
                    : "Solid contributor — tag if you can't afford to lose him.",
                icon: "checkmark.circle.fill",
                color: .success,
                endorsesTag: true
            )
        }
    }

    /// The one row that gets the filled pill.
    ///
    /// `expiringPlayers` is already sorted by rating, so this is the best man
    /// the screen endorses tagging whose tag the projected cap can actually
    /// absorb. Nobody qualifying means nothing is filled — the screen has no
    /// business urging a tag it would then have to call unaffordable two lines
    /// further down.
    private var tagFavourite: Player? {
        guard !hasUsedTag else { return nil }
        return expiringPlayers.first {
            smartRecommendation(for: $0).endorsesTag
                && projectedNextYearSpace - tagValue(for: $0.position) >= 0
        }
    }

    // MARK: - Section Card Shell

    private func sectionCard<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(Color.accentGold)
                    .font(.system(size: DSType.Size.callout))
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.accentGold)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.accentGold.opacity(0.08))

            Divider().overlay(Color.surfaceBorder)

            content()
                .padding(.vertical, 8)
        }
        .cardBackground()
    }

    private func emptyStateRow(_ text: String) -> some View {
        CompactEmptyStateView(icon: "tray", message: text)
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
    }

    // MARK: - Skip Tag Button

    @ViewBuilder
    private var skipTagButton: some View {
        if hasUsedTag {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.success)
                Text("Franchise tag applied")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.surfaceBorder, lineWidth: 1)
            )
        } else {
            Button {
                showSkipConfirmation = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "forward.fill")
                        .font(.caption)
                    Text("Skip — No Tag This Year")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Computed Properties

    /// Players on the user's team with expiring contracts (not already tagged).
    private var expiringPlayers: [Player] {
        teamPlayers
            .filter { $0.contractYearsRemaining <= 1 && !$0.isFranchiseTagged }
            .sorted { $0.overall > $1.overall }
    }

    /// Players currently franchise-tagged on the user's team.
    private var taggedPlayers: [Player] {
        teamPlayers.filter { $0.isFranchiseTagged }
    }

    /// Whether the team has already used their franchise tag this season.
    private var hasUsedTag: Bool {
        !taggedPlayers.isEmpty
    }

    // MARK: - Tag Value Calculation

    /// What the tag on this man actually costs next year — the number
    /// `ContractEngine.applyFranchiseTag` booked, falling back to a fresh quote
    /// for a save whose tag predates the forward ledger.
    private func tagCommitment(for player: Player) -> Int {
        CommittedCapLedger.forwardCommitment(playerID: player.id, careerID: career.id)?.annualCapHit
            ?? tagValue(for: player.position)
    }

    /// The quoted tag for a position, off the per-load table.
    ///
    /// The fallback is the same live calculation this function used to BE, kept
    /// for the position the table does not carry. Nothing on the screen asks for
    /// one — `buildTagQuotes` prices exactly the positions the rows are drawn
    /// from — but a miss returning a silent $0 would be a price, and a wrong one.
    private func tagValue(for position: Position) -> Int {
        tagQuotes[position]?.price ?? liveTagValue(for: position)
    }

    private func liveTagValue(for position: Position) -> Int {
        let positionSalaries = allPlayers
            .filter { $0.position == position && $0.annualSalary > 0 }
            .map { $0.annualSalary }
        // Task #87 / F16: the `capMode:` overload (this screen used to charge a
        // sandbox save a real tag) and the shared cap-relative floor.
        return ContractEngine.franchiseTagValue(
            position: position,
            topSalaries: positionSalaries,
            capMode: career.capMode,
            salaryCap: team?.salaryCap ?? ContractEngine.openingSalaryCap
        )
    }

    /// Prices every position this screen has to quote, **once per load**.
    ///
    /// `liveTagValue` walks all ~1 700 league players, and it is asked for a
    /// price by every expiring row, by every tagged row, and by `tagFavourite`
    /// — which prices the whole expiring list to find one man — on every
    /// redraw. The set of positions is small (the club's expiring men plus
    /// whoever is tagged), the answer only changes when `allPlayers` does, and
    /// `allPlayers` only changes in `loadData`. So it is one pass, there.
    ///
    /// The quote carries the five men behind the number as well as the number,
    /// because that is what the breakdown sheet exists to show and re-deriving
    /// it when the sheet opens would be a second, separate walk of the league.
    private func buildTagQuotes() -> [Position: TagQuote] {
        let priced = Set(
            teamPlayers
                .filter { $0.contractYearsRemaining <= 1 || $0.isFranchiseTagged }
                .map(\.position)
        )
        guard !priced.isEmpty else { return [:] }

        let salaryCap = team?.salaryCap ?? ContractEngine.openingSalaryCap
        let ownTeamID = team?.id

        // The same population `liveTagValue` filters, grouped in one pass
        // instead of re-filtered per position. A man with no club and a salary
        // still on him is in it, exactly as he is in the engine's list — the
        // screen must not print a five-man average the engine did not take.
        var byPosition: [Position: [Player]] = [:]
        for player in allPlayers where player.annualSalary > 0 && priced.contains(player.position) {
            byPosition[player.position, default: []].append(player)
        }

        var quotes: [Position: TagQuote] = [:]
        for position in priced {
            let candidates = byPosition[position] ?? []
            let salaries = candidates.map(\.annualSalary)

            // The engine sorts the bare numbers; this sorts the MEN carrying
            // them, so the sheet can name them. The id tiebreak only decides
            // which of two men on an identical salary is printed — the five
            // salaries, and therefore the average, are the engine's either way.
            let topFive = candidates
                .dsSorted(false, by: { $0.annualSalary }, id: { $0.id.uuidString })
                .prefix(5)
                .map { player in
                    TagTopSalary(
                        id: player.id,
                        name: player.fullName,
                        teamAbbreviation: player.teamID.flatMap { teamAbbreviations[$0] },
                        age: player.age,
                        overall: player.overall,
                        salary: player.annualSalary,
                        isOwnPlayer: player.teamID != nil && player.teamID == ownTeamID
                    )
                }

            // Both engine overloads, deliberately: the floored/sandbox price is
            // what the club is charged, the raw average is what the rules banner
            // describes, and the sheet has to be able to say when the two are
            // not the same number.
            let average = ContractEngine.franchiseTagValue(position: position, topSalaries: salaries)
            let price = ContractEngine.franchiseTagValue(
                position: position,
                topSalaries: salaries,
                capMode: career.capMode,
                salaryCap: salaryCap
            )

            quotes[position] = TagQuote(
                position: position,
                topFive: topFive,
                average: average,
                price: price,
                floor: Int(ContractEngine.franchiseTagFloorShare * Double(salaryCap)),
                isFloored: career.capMode != .sandbox && price > average,
                isSandbox: career.capMode == .sandbox
            )
        }
        return quotes
    }

    /// The breakdown request for one man's row, or nil for a position the load
    /// did not price (which is no row on this screen — see `buildTagQuotes`).
    private func tagBreakdownRequest(for player: Player, booked: Int?) -> TagBreakdownRequest? {
        guard let quote = tagQuotes[player.position] else { return nil }
        return TagBreakdownRequest(
            quote: quote,
            previous: previousQuotes[player.position],
            bookedCommitment: booked,
            playerName: player.fullName
        )
    }

    // MARK: - Tag Price Memory (#127 follow-up: "it moved, with no note")

    /// The scoped key the previous visit's quotes live under.
    ///
    /// **Not yet listed in `CareerScopedDefaults.keys`** — that file is another
    /// lane's this wave. The value is career-scoped regardless (`set` suffixes
    /// it with the open save's uuid, so no career can read another's) and it is
    /// season-stamped, so the only cost of the omission is that a deleted save
    /// leaves one small string behind. It belongs on the purge list.
    private static let tagPriceMemoryKey = "franchiseTagPriceMemory"

    /// Reads the previous visit's quotes, then records this one.
    ///
    /// **Once per appearance, not once per `loadData`.** Applying a tag, or
    /// signing a man through Contact Agent, reloads the screen; re-basing there
    /// would quietly zero the very delta the user came back to see. Measuring
    /// from the moment the screen opened also means a re-sign agreed HERE shows
    /// up against his own position's tag — which is exactly what it does to it,
    /// since a new top-five salary is a new top-five salary whoever wrote it.
    ///
    /// The clearing rule is the season stamp: a memory from an earlier league
    /// year is discarded rather than shown. At the rollover the cap grows and
    /// every contract in the league re-prices, so a cross-year delta measures
    /// inflation rather than the market — and the tag it would be compared
    /// against is a different league year's tag anyway.
    private func captureTagPriceBaseline() {
        guard !baselineCaptured, !tagQuotes.isEmpty else { return }
        baselineCaptured = true

        let stored = storedTagPriceMemory()
        let current: TagPriceMemory? = stored?.season == career.currentSeason ? stored : nil

        var previous: [Position: TagPriceMemory.Quote] = [:]
        for (raw, quote) in current?.quotes ?? [:] {
            guard let position = Position(rawValue: raw) else { continue }
            previous[position] = quote
        }
        previousQuotes = previous

        // This visit's quotes are merged over the season's existing ones rather
        // than replacing them: which positions the screen prices depends on who
        // is expiring TODAY, and a man re-signed this visit takes his position
        // off the list. Dropping it would silently restart that position's
        // baseline the next time somebody at it hits his last year.
        var quotes = current?.quotes ?? [:]
        for (position, quote) in tagQuotes {
            quotes[position.rawValue] = TagPriceMemory.Quote(
                price: quote.price,
                topFive: quote.topFiveSalaries
            )
        }
        writeTagPriceMemory(TagPriceMemory(season: career.currentSeason, quotes: quotes))
    }

    private func storedTagPriceMemory() -> TagPriceMemory? {
        guard let raw = CareerScopedDefaults.string(Self.tagPriceMemoryKey),
              let memory = try? JSONDecoder().decode(TagPriceMemory.self, from: Data(raw.utf8))
        else { return nil }
        return memory
    }

    private func writeTagPriceMemory(_ memory: TagPriceMemory) {
        guard let data = try? JSONEncoder().encode(memory) else { return }
        CareerScopedDefaults.set(String(decoding: data, as: UTF8.self), Self.tagPriceMemoryKey)
    }

    /// What this position's tag has done since the screen was last opened, in
    /// thousands — nil when there is nothing to report.
    ///
    /// Both ends are snapped to the tenth of a million the screen prints, for
    /// the same reason `capAfterTag` is: a move the reader cannot reproduce
    /// from the two figures he was shown is worse than no move at all. It is
    /// also what stops a $40K drift being announced as a change.
    private func tagPriceChange(for position: Position) -> Int? {
        guard let quote = tagQuotes[position],
              let previous = previousQuotes[position]
        else { return nil }
        let change = roundedToDisplay(quote.price) - roundedToDisplay(previous.price)
        return change == 0 ? nil : change
    }

    /// The move, as the smallest thing that can carry it.
    ///
    /// Warning and success, never gold: a tag that got dearer is a cost and one
    /// that got cheaper is a saving, and neither is the screen asking for a
    /// decision. The chip only appears on a row whose price actually moved, so
    /// on an ordinary revisit the column looks exactly as it did.
    private func tagChangeChip(_ change: Int) -> some View {
        HStack(spacing: 2) {
            Image(systemName: change > 0 ? "arrow.up.right" : "arrow.down.right")
            Text(formatMillions(abs(change)))
        }
        .font(.system(size: DSType.Size.micro, weight: .semibold).monospacedDigit())
        .foregroundStyle(change > 0 ? Color.warning : Color.success)
    }

    /// The row's price, spoken.
    ///
    /// The chip carries no label of its own: it lives inside a button that
    /// declares one, and VoiceOver reads the button rather than its children —
    /// so news left on the chip would be news nobody hears.
    private func spokenTagCost(_ tagCost: Int, for player: Player, change: Int?) -> String {
        var spoken = "Tag cost \(formatMillions(tagCost)) for \(player.fullName)"
        if let change {
            spoken += ", \(change > 0 ? "up" : "down") \(formatMillions(abs(change))) since your last visit"
        }
        return spoken
    }

    // MARK: - Actions

    private func applyTag(to player: Player, tagCost: Int) {
        guard let team, !hasUsedTag else { return }

        ContractEngine.applyFranchiseTag(
            player: player,
            tagValue: tagCost,
            team: team,
            capMode: career.capMode,
            bindingSeason: nextSeason,
            careerID: career.id
        )

        // Persist so CareerShellView picks up the change
        try? modelContext.save()
        CareerScopedDefaults.set(true, "franchiseTagVisited")

        // Refresh local state
        loadData()
    }

    private func removeTag(from player: Player) {
        guard let team else { return }

        ContractEngine.removeFranchiseTag(
            player: player,
            team: team,
            capMode: career.capMode,
            careerID: career.id
        )

        // Persist so CareerShellView picks up the change
        try? modelContext.save()

        // Refresh local state
        loadData()
    }

    // MARK: - Helpers

    private func positionBadge(_ position: Position) -> some View {
        Text(position.rawValue)
            .font(.caption.weight(.bold))
            .foregroundStyle(Color.textPrimary)
            .frame(width: 34)
            .padding(.vertical, 4)
            .background(positionSideColor(position), in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))
    }

    private func positionSideColor(_ position: Position) -> Color {
        switch position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }

    private func formatMillions(_ thousands: Int) -> String { tagMillions(thousands) }

    /// Money as this screen actually prints it: thousands snapped to the tenth
    /// of a million `formatMillions` rounds to. Arithmetic a reader can check
    /// on screen has to be done on the figures on screen.
    private func roundedToDisplay(_ thousands: Int) -> Int {
        Int((Double(thousands) / 100.0).rounded()) * 100
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let teamID = career.teamID else { return }

        let teamDesc = FetchDescriptor<Team>(predicate: #Predicate { $0.id == teamID })
        team = try? modelContext.fetch(teamDesc).first

        guard let fetchedTeamID = team?.id else { return }
        var playerDesc = FetchDescriptor<Player>(
            predicate: #Predicate { $0.teamID == fetchedTeamID }
        )
        playerDesc.sortBy = [SortDescriptor(\.annualSalary, order: .reverse)]
        teamPlayers = (try? modelContext.fetch(playerDesc)) ?? []

        // Fetch all players league-wide for tag value calculation
        let cid = career.id
        let allDesc = FetchDescriptor<Player>(predicate: #Predicate { $0.careerID == cid })
        allPlayers = (try? modelContext.fetch(allDesc)) ?? []

        // The 32 clubs, for the breakdown's five rows. One fetch per load, not
        // one per row: the sheet names the man's employer and `Player` carries
        // only his `teamID`.
        let teamsDesc = FetchDescriptor<Team>(predicate: #Predicate { $0.careerID == cid })
        teamAbbreviations = ((try? modelContext.fetch(teamsDesc)) ?? [])
            .reduce(into: [UUID: String]()) { $0[$1.id] = $1.abbreviation }

        tagQuotes = buildTagQuotes()
        captureTagPriceBaseline()
    }
}

// MARK: - Tag Cost Breakdown Model
//
// #127 left the tag price stated but not shown: the rules banner says it is the
// average of the top 5 salaries at the position, and nothing on the screen
// could name those five. A price that is derived, unexplained and free to move
// between two visits reads as the app changing its mind — which is precisely
// what the screenshot audit recorded ("moved $3.3M between visits with no
// note"). These four types are the answer: the quote, the men behind it, the
// request that opens it, and the memory that makes "since your last visit" a
// real measurement rather than a claim.
//
// File-scope `private` rather than nested in the view, because the sheet is its
// own `View` and a type nested `private` inside `FranchiseTagView` is not
// visible to it.

/// One position's tag price, and everything needed to explain it.
private struct TagQuote {
    let position: Position
    /// The five salaries the engine averages, highest first. Fewer than five
    /// when the league has fewer salaried men at the position — the engine
    /// divides by what it has, and so does the sheet.
    let topFive: [TagTopSalary]
    /// The straight average of `topFive`: the number the rules banner
    /// describes, before the floor.
    let average: Int
    /// What the club is actually charged — the average, the floor, or $0 in
    /// sandbox.
    let price: Int
    /// The cap-relative floor as it stands for this club, this year.
    let floor: Int
    /// The floor is doing the work: `price` is not the average.
    let isFloored: Bool
    let isSandbox: Bool

    /// The salaries as the memory stores them.
    var topFiveSalaries: [Int] { topFive.map(\.salary) }
}

/// One man in a position's top five.
private struct TagTopSalary: Identifiable {
    let id: UUID
    let name: String
    /// `nil` for a man with no club. A free agent still carrying a salary is in
    /// the engine's own list, so he is in this one.
    let teamAbbreviation: String?
    let age: Int
    let overall: Int
    let salary: Int
    /// Your own player. Worth marking: a club's own big contract raises the tag
    /// it would have to pay to keep the next man at that position.
    let isOwnPlayer: Bool

    var subtitle: String {
        "\(teamAbbreviation ?? "FA") \u{00B7} Age \(age) \u{00B7} \(overall) OVR"
    }
}

/// One request to open the breakdown.
///
/// It carries the quote rather than a key into the view's table, so the
/// presented sheet cannot have a nil case to render — the alternative is a
/// `.sheet` whose content is an `if let` with an empty else, i.e. a modal that
/// can come up blank.
private struct TagBreakdownRequest: Identifiable {
    let id = UUID()
    let quote: TagQuote
    let previous: TagPriceMemory.Quote?
    /// The tagged man's BOOKED price, when the sheet was opened from his row.
    /// Non-nil is what tells the sheet to explain that his number is fixed and
    /// the market's is not.
    let bookedCommitment: Int?
    let playerName: String
}

/// What the screen quoted on its last visit, per position.
///
/// Persisted through `CareerScopedDefaults` because the whole complaint it
/// answers is about what happened BETWEEN two visits — in-memory state cannot
/// see across the gap.
private struct TagPriceMemory: Codable {
    /// The league year the quotes were taken in. See
    /// `FranchiseTagView.captureTagPriceBaseline` for why a stamp from an
    /// earlier season is discarded rather than shown.
    var season: Int
    /// `Position.rawValue` -> the quote.
    var quotes: [String: Quote]

    struct Quote: Codable {
        /// What the screen printed as Tag Cost.
        var price: Int
        /// The five salaries behind it, so the breakdown can show WHICH rank
        /// moved rather than only that the average did.
        var topFive: [Int]
    }
}

/// Money as this screen prints it, in one place: the view formats a dozen
/// figures with it and the breakdown sheet another dozen, and two copies of a
/// rounding rule is how a screen ends up disagreeing with its own sheet.
private func tagMillions(_ thousands: Int) -> String {
    let millions = Double(thousands) / 1000.0
    if millions >= 1.0 {
        return String(format: "$%.1fM", millions)
    } else {
        return "$\(thousands)K"
    }
}

// MARK: - Tag Cost Breakdown Sheet

/// Where a derived number shows its work.
///
/// Three questions, in the order a GM asks them: **what is this number** (the
/// headline and the arithmetic that produced it), **what has it done since I
/// last looked** (the change card, and the LAST VISIT column that says which
/// rank moved), and **whose salaries are these** (the five rows). The notes at
/// the foot cover the cases where the headline is not simply the average — the
/// floor, sandbox, a thin position, and a tag already booked.
///
/// It reads nothing. Every figure arrives on the `TagBreakdownRequest`, priced
/// in the one pass `buildTagQuotes` already makes, so opening the sheet does
/// not walk the league a second time.
private struct TagBreakdownSheet: View {

    let request: TagBreakdownRequest
    /// The league year the tag charges, already labelled by the parent — one
    /// screen, one answer to "which season is this".
    let tagSeasonLabel: String

    @Environment(\.dismiss) private var dismiss

    private var quote: TagQuote { request.quote }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.md) {
                    headline
                    if let change { changeCard(change) }
                    salaryTable
                    notes
                }
                .padding(DSSpacing.lg)
                .frame(maxWidth: DSLayout.contentMeasure)
                .frame(maxWidth: .infinity)
            }
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("\(quote.position.rawValue) Tag Cost")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Headline

    private var headline: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text(tagMillions(quote.price))
                .font(.system(size: DSType.Size.title1, weight: .bold).monospacedDigit())
                .foregroundStyle(Color.accentGold)

            Text(quote.isSandbox
                 ? "Sandbox cap mode: a tag is booked at $0. The salaries below are what it would cost in a capped save."
                 : "The average of the top 5 \(quote.position.rawValue) salaries in the league — charged against your \(tagSeasonLabel) cap, not this year's.")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if !quote.topFive.isEmpty {
                // The sum on one line. It is the shortest possible proof that
                // the five rows underneath are the whole of the number above
                // them, and it is the line a reader checks when he does not
                // believe the price.
                Text(arithmetic)
                    .font(.system(size: DSType.Size.footnote).monospacedDigit())
                    .foregroundStyle(Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.md)
        .background(Color.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: DSCornerRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: DSCornerRadius.card)
                .strokeBorder(Color.surfaceBorder, lineWidth: 1)
        )
    }

    private var arithmetic: String {
        let terms = quote.topFive.map { tagMillions($0.salary) }.joined(separator: " + ")
        return "(\(terms)) \u{00F7} \(quote.topFive.count) = \(tagMillions(quote.average))"
    }

    // MARK: - Since Last Visit

    /// The move, on the price the screen actually printed. Nil when there is no
    /// baseline (a first visit this league year) or nothing moved.
    private var change: Int? {
        guard let previous = request.previous else { return nil }
        let delta = displayRounded(quote.price) - displayRounded(previous.price)
        return delta == 0 ? nil : delta
    }

    private func changeCard(_ change: Int) -> some View {
        HStack(alignment: .top, spacing: DSSpacing.sm) {
            Image(systemName: change > 0 ? "arrow.up.right" : "arrow.down.right")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(change > 0 ? Color.warning : Color.success)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(change > 0 ? "Up" : "Down") \(tagMillions(abs(change))) since your last visit")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text("It was \(tagMillions(request.previous?.price ?? 0)) when you last opened this screen. The tag follows the league's top five at the position, so any signing anywhere in the league can move it — including one you made yourself.")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.sm)
        .background(
            (change > 0 ? Color.warning : Color.success).opacity(0.08),
            in: RoundedRectangle(cornerRadius: DSCornerRadius.inline)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                .strokeBorder((change > 0 ? Color.warning : Color.success).opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - The Five Salaries

    private var salaryTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "list.number")
                    .foregroundStyle(Color.accentGold)
                    .font(.system(size: DSType.Size.callout))
                Text(tableTitle)
                    .font(.headline)
                    .foregroundStyle(Color.accentGold)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.accentGold.opacity(0.08))

            Divider().overlay(Color.surfaceBorder)

            if quote.topFive.isEmpty {
                CompactEmptyStateView(
                    icon: "tray",
                    message: "No salaried \(quote.position.rawValue) in the league — the tag falls back to its floor."
                )
                .padding(.horizontal, 8)
                .padding(.vertical, 12)
            } else {
                VStack(spacing: 0) {
                    DSListHeaderRow(
                        density: .scan,
                        reservesRank: true,
                        portraitWidth: 0,
                        identityLabel: "PLAYER"
                    ) {
                        DSColumnHeader("SALARY", width: DSListColumn.money, alignment: .trailing)
                        if request.previous != nil {
                            DSColumnHeader("LAST VISIT", width: DSListColumn.money, alignment: .trailing)
                        }
                    }
                    .padding(.horizontal, 12)

                    Divider().overlay(Color.surfaceBorder.opacity(0.5))

                    ForEach(Array(quote.topFive.enumerated()), id: \.element.id) { index, entry in
                        salaryRow(entry, rank: index + 1, previous: previousSalary(at: index))
                            .padding(.horizontal, 12)
                        if index < quote.topFive.count - 1 {
                            Divider()
                                .overlay(Color.surfaceBorder.opacity(0.5))
                                .padding(.horizontal, 8)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .cardBackground()
    }

    /// "Top 5" is the rule; the count is what the league could actually supply.
    /// The empty case still says 5, because there is nothing to have taken 0 of.
    private var tableTitle: String {
        let count = quote.topFive.isEmpty ? 5 : quote.topFive.count
        return "Top \(count) \(quote.position.rawValue) Salaries"
    }

    private func salaryRow(_ entry: TagTopSalary, rank: Int, previous: Int?) -> some View {
        DSListRow(
            density: .scan,
            rank: DSRank(value: rank),
            portraitWidth: 0,
            portrait: { EmptyView() },
            identity: {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(entry.name)
                            .font(DSType.text(DSListDensity.scan.nameSize, .semibold, prose: true))
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                        if entry.isOwnPlayer {
                            // Your own contract is in your own tag. It is the
                            // one thing on this list the GM can do something
                            // about, so it is the one thing marked.
                            Text("YOUR CLUB")
                                .font(DSType.display(11, .heavy))
                                .foregroundStyle(Color.accentGold)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.accentGold.opacity(0.15), in: Capsule())
                        }
                    }
                    Text(entry.subtitle)
                        .font(DSType.display(11, .medium))
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)
                }
            },
            columns: {
                Text(tagMillions(entry.salary))
                    .font(DSType.display(13, .bold))
                    .foregroundStyle(Color.textPrimary)
                    .dsColumn(DSListColumn.money, alignment: .trailing)
                if request.previous != nil {
                    Text(previous.map(tagMillions) ?? "\u{2014}")
                        .font(DSType.display(11, .semibold))
                        .foregroundStyle(previousTint(current: entry.salary, previous: previous))
                        .dsColumn(DSListColumn.money, alignment: .trailing)
                }
            }
        )
    }

    /// What sat at this rank last visit. Nil when the position had fewer men at
    /// a salary then than it does now — an em dash rather than a zero, because
    /// "there was nobody here" is not "he earned nothing".
    private func previousSalary(at index: Int) -> Int? {
        guard let previous = request.previous, index < previous.topFive.count else { return nil }
        return previous.topFive[index]
    }

    /// Tertiary while the rank is unchanged, tinted when it moved: the column is
    /// there to be scanned for the line that is not grey.
    private func previousTint(current: Int, previous: Int?) -> Color {
        guard let previous, displayRounded(previous) != displayRounded(current) else {
            return Color.textTertiary
        }
        return current > previous ? Color.warning : Color.success
    }

    // MARK: - Notes

    @ViewBuilder
    private var notes: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            if let booked = request.bookedCommitment {
                note(
                    "lock.fill",
                    "\(request.playerName)'s tag is booked at \(tagMillions(booked)) and does not move with the market. The price above is what tagging a \(quote.position.rawValue) would cost today."
                )
            }
            if quote.isFloored {
                note(
                    "arrow.up.to.line",
                    "The average is under the league's minimum tag (\(tagMillions(quote.floor))), so the tag is charged at that floor instead."
                )
            }
            // No sandbox note: the headline already says the tag is $0 there,
            // and saying it twice on one sheet is the app arguing with itself.
            if !quote.topFive.isEmpty && quote.topFive.count < 5 {
                note(
                    "exclamationmark.triangle.fill",
                    "Only \(quote.topFive.count) salaried \(quote.position.rawValue) in the league, so the average is taken over \(quote.topFive.count) rather than 5."
                )
            }
            note(
                "arrow.triangle.2.circlepath",
                "This price is re-read every time the screen opens. Re-signings, free-agent deals and trades anywhere in the league move the top five, and the tag with it."
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.sm)
        .background(Color.backgroundSecondary.opacity(0.6), in: RoundedRectangle(cornerRadius: DSCornerRadius.inline))
    }

    private func note(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
                .frame(width: 16)
            Text(text)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The same snap-to-the-printed-figure rule the parent screen uses, so a
    /// delta on the row and a delta in this sheet cannot disagree.
    private func displayRounded(_ thousands: Int) -> Int {
        Int((Double(thousands) / 100.0).rounded()) * 100
    }
}

// MARK: - Preview

#Preview {
    let career = Career(playerName: "Sam Greer", role: .gm, capMode: .simple)
    NavigationStack {
        FranchiseTagView(career: career)
    }
    .modelContainer(for: [Career.self, Team.self, Player.self], inMemory: true)
}
