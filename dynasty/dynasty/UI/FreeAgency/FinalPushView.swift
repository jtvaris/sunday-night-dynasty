import SwiftUI
import SwiftData

// MARK: - Re-Sign Response

enum ReSignResponse {
    case accepted
    case countered(salary: Int, years: Int, reason: String)
    case rejected(reason: String)
    /// R22: a hardliner agent was insulted — talks are dead for the offseason.
    case brokenOff(reason: String)
}

// MARK: - Fifth-Year Option Decision (task #90)

/// What the user answered on a first-rounder's fifth-year option, and at what
/// price. Presentation state only — the contract itself is written by
/// `FreeAgencyEngine.exerciseFifthYearOption` / `declineFifthYearOption` the
/// moment the button is pressed.
enum FifthYearDecision {
    case exercised(price: Int)
    case declined
}

// MARK: - FinalPushView

struct FinalPushView: View {

    let career: Career

    @Environment(\.modelContext) private var modelContext

    @State private var team: Team?
    @State private var expiringPlayers: [Player] = []
    /// Task #90 — the user's own first-rounders standing in their fifth-year
    /// option window. A DIFFERENT cohort from `expiringPlayers`: those have one
    /// contract year left, these have two, so the two lists can never overlap
    /// and the same man is never asked about twice on one screen.
    @State private var fifthYearCandidates: [Player] = []
    /// The price the user paid on an option he exercised THIS session, keyed by
    /// player — the one thing the model does not keep separately (an exercised
    /// deal raises `annualSalary` to the option number, so it can be read back,
    /// but only until something else touches the contract).
    ///
    /// The DECISION itself is never read from here. `Player.fifthYearDecided` /
    /// `fifthYearExercised` are persisted and are the record of truth; this
    /// dictionary used to be it, which meant leaving the screen and coming back
    /// inside the same league year erased every answer the user had given —
    /// `isFifthYearOptionWindow` is false once decided, so the card vanished and
    /// the confirm alert silently dropped him from its count.
    @State private var fifthYearPrices: [UUID: Int] = [:]
    /// Every live salary in the league grouped by position — the franchise-tag
    /// input the option price is a share of. Built once in `loadData`.
    @State private var fifthYearSalaryTable: [Position: [Int]] = [:]
    @State private var allPlayers: [Player] = []
    @State private var allTeams: [Team] = []
    @State private var decisions: [UUID: PlayerDecisionState] = [:]
    @State private var showLeagueYearConfirm = false
    /// R23 — legal-tampering rumors for the top upcoming FAs (league-wide).
    @State private var tamperingRumors: [TamperingRumorEngine.TamperingRumor] = []
    /// The buzz board starts closed — see `tamperingBuzzCard`.
    @State private var showTamperingBuzz = false

    /// The player whose agent is on the phone. Non-nil while the Contact Agent
    /// thread is open.
    @State private var negotiationPlayer: Player?

    /// `DraftReputation.ownerTrust` — one of the five inputs to the GM factor.
    @State private var ownerTrust: Int = 70

    // MARK: - Economy Inputs
    //
    // Quick Offer and Contact Agent are two doors into ONE demand model, so
    // both have to hand it the same world.

    private var gmStanding: GMStanding {
        GMStanding.from(career: career, ownerTrust: ownerTrust)
    }

    /// The club and the season the demand model reads. Final Push runs after
    /// the season, so the record is the one just completed.
    private func reSignSituation(for player: Player) -> NegotiationSituation {
        let wins = team?.wins ?? 0
        let losses = team?.losses ?? 0
        // "Contender" comes from `ContractNegotiationEngine.isContender` (the
        // default when the parameter is omitted) rather than being spelled out
        // here — this screen used to carry its own copy of the threshold, which
        // meant the ring-chaser's exit condition and this screen agreed only by
        // coincidence.
        return ContractNegotiationEngine.situation(
            for: player,
            season: career.currentSeason,
            teamWins: wins,
            teamLosses: losses,
            weeksPlayed: max(wins + losses, career.currentWeek)
        )
    }

    struct PlayerDecisionState {
        enum Status {
            case pending
            case offering(salary: Int, years: Int)
            case responded(response: ReSignResponse)
            case reSignedAccepted
            case letWalk
            /// R22: kept for one year via the franchise tag.
            case tagged(salary: Int)
        }
        var status: Status = .pending
        var offerSalary: Int = 0
        var offerYears: Int = 2
        /// R22: how many offers the GM has submitted (agents have finite patience).
        var offerRounds: Int = 0
        /// The agent's STANDING number in this quick-offer conversation. Every
        /// grade is measured against it rather than against raw market value —
        /// that is what makes this button and the Contact Agent button next to
        /// it negotiate against the same price.
        var standingAsk: NegotiationOfferSnapshot?
        /// Lowballs absorbed, so the insult ratchet and the patience cost work
        /// here exactly as they do in the chat.
        var insultCount: Int = 0
    }

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            if let team {
                VStack(spacing: 0) {
                // §2.1 — free agency's spine. Step 1 of 5.
                FAFlowBandView(
                    step: .finalPush,
                    currentSubcaption: finalPushSubcaption
                )
                ScrollView {
                    VStack(spacing: 24) {
                        headerCard(team: team)

                        if !tamperingRumors.isEmpty {
                            tamperingBuzzCard
                        }

                        // Task #90. Placed ABOVE the expiring men on purpose:
                        // it is a hard deadline that closes when the league year
                        // turns, and a fifth year picked up here is money the
                        // user has to know about before he starts bidding on
                        // his own free agents with the same cap space.
                        if !fifthYearCandidates.isEmpty {
                            fifthYearOptionSection(team: team)
                        }

                        if expiringPlayers.isEmpty {
                            noExpiringCard
                        } else {
                            ForEach(expiringPlayers, id: \.id) { player in
                                expiringPlayerCard(player: player, team: team)
                            }
                        }

                    }
                    .padding(24)
                    .frame(maxWidth: .infinity)
                }
                // §2.5 — the commit, pinned. It used to be the last item in a
                // ScrollView that a club with fifteen expiring men had to scroll
                // past fifteen cards to reach.
                DSActionBar(
                    explainer: startLeagueYearExplainer,
                    primary: .init(
                        title: "Start new league year \u{2192}",
                        handler: { showLeagueYearConfirm = true }
                    )
                )
                }
            } else {
                ProgressView()
                    .tint(Color.accentGold)
            }
        }
        .navigationTitle("Final Push")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { loadData() }
        .alert("Start New League Year?", isPresented: $showLeagueYearConfirm) {
            Button("Start New League Year") { advanceToLeagueYear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            let undecided = expiringPlayers.filter { decisions[$0.id]?.status == nil || isPending($0.id) }.count
            // Task #90: an unanswered option is a DECLINE, not a market entry —
            // he stays on the roster for one more year either way — so it gets
            // its own sentence rather than being folded into the count above.
            let openOptions = fifthYearCandidates.filter { !$0.fifthYearDecided }.count
            let market = undecided > 0
                ? "\(undecided) undecided player\(undecided == 1 ? "" : "s") will hit the open market."
                : "All decisions made. Proceed to advance contracts."
            let options = openOptions > 0
                ? " \(openOptions) fifth-year option\(openOptions == 1 ? "" : "s") will be declined."
                : ""
            Text(market + options)
        }
        .fullScreenCover(item: $negotiationPlayer) { player in
            // ContractNegotiationView supplies its own "Close" toolbar item, so
            // the wrapper must NOT add a second one.
            NavigationStack {
                ContractNegotiationView(
                    player: player,
                    negotiationType: .extend,
                    teamCapSpace: max(0, team?.availableCap ?? 0),
                    // #186 — the gate must plan the deal this screen BOOKS.
                    // `applyReSignOffer` REPLACES the expiring contract, so the
                    // deal charges the league year that is open. The default
                    // `.extendExisting` would have read `contractYearsRemaining
                    // == 1` (which every man on this list carries until the
                    // rollover decrements it) as a year still to run and quoted
                    // the re-sign against next season's projected cap while the
                    // booking charged it to this one.
                    dealApplication: .replaceContract,
                    onDealCompleted: { offer in
                        guard let team else { return }
                        // The same execution path the Quick Offer flow uses, so
                        // a deal struck in the chat lands on the cap and the
                        // roster identically — and, unlike `signFreeAgent`,
                        // this one has room for the structure that was actually
                        // negotiated (bonus, guarantee, no-trade clause) instead
                        // of drawing a fresh random bonus and hardcoding
                        // `noTrade: false`. Going through `applyReSignOffer`
                        // rather than calling the engine directly is what keeps
                        // the rollover compensation on BOTH doors into this
                        // screen — see that method.
                        applyReSignOffer(player: player, team: team, offer: offer)
                        FASigningTracker.trackSigning(player.id)
                        generateStorylinesForSigning(player: player, team: team)
                        decisions[player.id, default: PlayerDecisionState()].status = .reSignedAccepted
                        // No dismiss — the thread shows the signed card and the
                        // user closes it with Done.
                    }
                )
            }
        }
    }

    // MARK: - Header

    private func headerCard(team: Team) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(Color.accentGold)
                    .font(.system(size: DSType.Size.callout))
                Text("Final Push \u{2014} Re-sign or Let Walk")
                    .font(.headline)
                    .foregroundStyle(Color.accentGold)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            Text("Make final offers to your expiring players before the market opens. Compare with the best available free agents at each position.")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 16)

            HStack(spacing: 20) {
                statPill(label: "Expiring", value: "\(expiringPlayers.count)", color: .warning)
                statPill(label: "Cap Space", value: formatMillions(team.availableCap), color: team.availableCap > 0 ? .success : .danger)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.surfaceBorder, lineWidth: 1))
    }

    // MARK: - R23: Legal Tampering Buzz

    /// Pre-market intel: projected prices and early suitors for the top
    /// upcoming FAs, quoted from the same model the live market uses. Own
    /// expiring players are flagged — this is the last exclusive window.
    ///
    /// Closed by default. Open, it is eight rows of OTHER clubs' free agents
    /// sitting between the header and the first man the screen exists to ask
    /// about — six of seven decisions below the fold while the irreversible
    /// "Start new league year" stayed pinned in view. It is context for those
    /// decisions, so it keeps its place above them; the closed header still
    /// says how many of the leaked names are the user's own.
    private var tamperingBuzzCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showTamperingBuzz.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(Color.warning)
                        .font(.system(size: 14))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Legal Tampering Buzz")
                            .font(.headline)
                            .foregroundStyle(Color.warning)
                        Text(tamperingBuzzSummary)
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                    Spacer()
                    Text("LEAGUE SOURCES")
                        .font(.system(size: DSType.Size.micro, weight: .black))
                        .foregroundStyle(Color.textTertiary)
                    Image(systemName: showTamperingBuzz ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 14)

            if showTamperingBuzz {
                Text("Numbers already leaking ahead of the market. Names flagged in gold are YOUR expiring players — this is your last exclusive shot at them.")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, 16)

                VStack(spacing: 0) {
                    ForEach(tamperingRumors) { rumor in
                        tamperingRumorRow(rumor)
                        if rumor.id != tamperingRumors.last?.id {
                            Divider().overlay(Color.surfaceBorder.opacity(0.5))
                        }
                    }
                }
            }
        }
        .padding(.bottom, showTamperingBuzz ? 8 : 14)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.surfaceBorder, lineWidth: 1))
    }

    /// What the closed header says the board holds. The "yours" half is the
    /// reason to open it at all.
    private var tamperingBuzzSummary: String {
        let names = "\(tamperingRumors.count) name\(tamperingRumors.count == 1 ? "" : "s") leaking"
        let own = tamperingRumors.filter(\.isOwnPlayer).count
        return own > 0 ? "\(names) \u{2014} \(own) of them yours" : names
    }

    private func tamperingRumorRow(_ rumor: TamperingRumorEngine.TamperingRumor) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(rumor.position)
                    .font(.system(size: DSType.Size.caption, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                    .frame(width: 28)
                    .padding(.vertical, 2)
                    .background(Color.accentBlue, in: RoundedRectangle(cornerRadius: 3))
                Text(rumor.playerName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(rumor.isOwnPlayer ? Color.accentGold : Color.textPrimary)
                    .lineLimit(1)
                if rumor.isOwnPlayer {
                    Text("YOURS")
                        .font(.system(size: DSType.Size.micro, weight: .black))
                        .foregroundStyle(Color.backgroundPrimary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.accentGold, in: Capsule())
                }
                Text("\(rumor.overall) OVR")
                    .font(.system(size: DSType.Size.caption, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.forRating(rumor.overall))
                Spacer()
                // Another club's man at another club's price is REFERENCE, and
                // it was printing in the loudest colour on the page — eight
                // rumoured salaries in gold above the one number the screen is
                // actually asking about. The gold on this card belongs to the
                // "YOURS" flag and the commit action, nothing else.
                Text("~\(formatMillions(rumor.projectedSalary))/yr")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(Color.textSecondary)
            }
            HStack(spacing: 6) {
                if rumor.suitorAbbrs.isEmpty {
                    Text("Market still forming")
                        .font(.system(size: DSType.Size.caption).italic())
                        .foregroundStyle(Color.textTertiary)
                } else {
                    HStack(spacing: 3) {
                        Image(systemName: "eye.fill")
                            .font(.system(size: DSType.Size.micro))
                        Text("\(rumor.suitorAbbrs.joined(separator: ", ")) circling")
                            .font(.system(size: DSType.Size.caption, weight: .medium))
                    }
                    .foregroundStyle(Color.danger)
                }
                Text("\u{2022} \(TamperingRumorEngine.motivationBlurb(rumor.motivation))")
                    .font(.system(size: DSType.Size.caption).italic())
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.leading, 36)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Fifth-Year Options (task #90)

    /// The user's own first-rounders entering the final year of their rookie
    /// deals. One card, one row per man, two buttons.
    ///
    /// Deliberately NOT a negotiation. The fifth-year option is a unilateral
    /// club right at a price the league sets — there is no agent to call, no
    /// counter and no refusal — so it gets a flat yes/no surface rather than the
    /// offer ladder the expiring cards below carry.
    private func fifthYearOptionSection(team: Team) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: "calendar.badge.plus")
                        .foregroundStyle(Color.accentBlue)
                        .font(.system(size: DSType.Size.callout))
                    Text("Fifth-Year Options")
                        .font(.headline)
                        .foregroundStyle(Color.accentBlue)
                    Spacer()
                    Text("\(fifthYearCandidates.count)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.textSecondary)
                }
                Text("Your first-round picks are entering the last year of their rookie deals. Picking up the option adds a fifth season at 80% of the franchise tag for the position. Anything you leave undecided is declined when the league year starts.")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)

            Divider().overlay(Color.surfaceBorder.opacity(0.5))

            ForEach(Array(fifthYearCandidates.enumerated()), id: \.element.id) { index, player in
                if index > 0 {
                    Divider().overlay(Color.surfaceBorder.opacity(0.3))
                }
                fifthYearOptionRow(player: player, team: team)
            }
        }
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: DSCornerRadius.card))
        .overlay(RoundedRectangle(cornerRadius: DSCornerRadius.card).strokeBorder(Color.surfaceBorder, lineWidth: 1))
    }

    @ViewBuilder
    private func fifthYearOptionRow(player: Player, team: Team) -> some View {
        let price = fifthYearOptionPrice(for: player, team: team)
        // What the option really costs the club THIS league year: he is already
        // carried at rookie money, so only the difference is new spending. Same
        // arithmetic `FreeAgencyEngine.settleFifthYearOptions` charges the AI.
        let capDelta = price - player.annualSalary
        let affordable = career.capMode == .sandbox || team.availableCap >= capDelta

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text(player.position.rawValue)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                    .frame(width: 34)
                    .padding(.vertical, 4)
                    .background(positionSideColor(player.position), in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))

                VStack(alignment: .leading, spacing: 2) {
                    Text(player.fullName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.textPrimary)
                    HStack(spacing: 8) {
                        Text("\(player.overall) OVR")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Color.forRating(player.overall))
                        Text("Age \(player.age)")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                        Text(draftLine(for: player))
                            .font(.caption2)
                            .foregroundStyle(Color.textTertiary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatMillions(price))
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(affordable ? Color.accentGold : Color.danger)
                    Text("OPTION YR")
                        .font(.system(size: DSType.Size.micro, weight: .bold))
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(player.fullName), \(player.position.rawValue), \(player.overall) overall. Fifth-year option \(formatMillions(price)).")

            if let decision = fifthYearDecision(for: player) {
                switch decision {
                case .exercised(let paid):
                    decisionBanner(
                        icon: "checkmark.seal.fill",
                        text: "Option exercised — \(formatMillions(paid)) for a fifth season",
                        color: .success
                    )
                case .declined:
                    decisionBanner(
                        icon: "xmark.circle.fill",
                        text: "Option declined — plays out the final year of his rookie deal",
                        color: .textTertiary
                    )
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Button {
                            exerciseFifthYear(player: player, team: team, price: price)
                        } label: {
                            Text("EXERCISE")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(affordable ? Color.backgroundPrimary : Color.textTertiary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    affordable ? Color.accentGold : Color.backgroundTertiary,
                                    in: RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(!affordable)

                        Button {
                            declineFifthYear(player: player)
                        } label: {
                            Text("DECLINE")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: DSCornerRadius.inline))
                        }
                        .buttonStyle(.plain)
                    }

                    Text(affordable
                         ? "Costs \(formatMillions(capDelta)) more than his rookie deal this year."
                         : "Not enough cap room — \(formatMillions(capDelta)) needed, \(formatMillions(max(0, team.availableCap))) available.")
                        .font(.caption2)
                        .foregroundStyle(affordable ? Color.textTertiary : Color.danger)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func decisionBanner(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(text)
                .font(.caption)
                .foregroundStyle(color)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: DSCornerRadius.inline))
    }

    /// "Rd 1, Pick 14 · 2028" — why this man has an option at all.
    private func draftLine(for player: Player) -> String {
        var parts: [String] = ["Rd 1"]
        if let pick = player.draftPickNumber { parts.append("Pick \(pick)") }
        // #152 — the year the league calls that draft, matching the draft room
        // and every pick label (see `DraftYearLabel`).
        if let season = player.draftSeason {
            parts.append("\(DraftYearLabel.classYear(forStamped: season))")
        }
        return parts.joined(separator: " · ")
    }

    /// The option price, from the SAME engine call the rollover uses, against
    /// the same league-wide salary table this screen already loads. A second
    /// hand-typed formula here is exactly the split-brain task #87 closed for
    /// franchise-tag money.
    private func fifthYearOptionPrice(for player: Player, team: Team) -> Int {
        FreeAgencyEngine.fifthYearOptionPrice(
            player: player,
            salaryTable: fifthYearSalaryTable,
            salaryCap: team.salaryCap
        )
    }

    /// What the user has already answered on this man, read from the MODEL.
    ///
    /// `fifthYearDecided` / `fifthYearExercised` are persisted by
    /// `FreeAgencyEngine`'s two writers, so the answer survives leaving the
    /// screen, a relaunch and anything else — which is the whole point, since
    /// the moment a man is decided `isFifthYearOptionWindow` stops matching him
    /// and there is nothing else left to render the card from.
    private func fifthYearDecision(for player: Player) -> FifthYearDecision? {
        guard player.fifthYearDecided else { return nil }
        guard player.fifthYearExercised else { return .declined }
        // `exerciseFifthYearOption` writes the option number straight onto
        // `annualSalary`, so the salary IS the price; the session cache is only
        // there so the banner keeps quoting the exact figure the button showed.
        return .exercised(price: fifthYearPrices[player.id] ?? player.annualSalary)
    }

    private func exerciseFifthYear(player: Player, team: Team, price: Int) {
        FreeAgencyEngine.exerciseFifthYearOption(player: player, team: team, price: price)
        try? modelContext.save()
        fifthYearPrices[player.id] = price
    }

    private func declineFifthYear(player: Player) {
        FreeAgencyEngine.declineFifthYearOption(player: player)
        try? modelContext.save()
    }

    // MARK: - No Expiring

    private var noExpiringCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: DSType.Size.display))
                .foregroundStyle(Color.success)
            Text("No Expiring Contracts")
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
            Text("All your players are under contract. Proceed to start the new league year.")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: DSCornerRadius.card))
        .overlay(RoundedRectangle(cornerRadius: DSCornerRadius.card).strokeBorder(Color.surfaceBorder, lineWidth: 1))
    }

    // MARK: - Expiring Player Card

    private func expiringPlayerCard(player: Player, team: Team) -> some View {
        let state = decisions[player.id] ?? PlayerDecisionState()
        // The league's ACTUAL cap, not the 265 000 default. Two screens quoting
        // two different market values for the same man — and diverging further
        // every year the cap compounds — is the bug this argument closes.
        let marketValue = ContractEngine.estimateMarketValue(player: player, salaryCap: team.salaryCap)
        let faAlternatives = ContractEngine.previewFreeAgents(
            allPlayers: allPlayers,
            allTeams: allTeams,
            playerTeamID: career.teamID ?? UUID(),
            position: player.position,
            salaryCap: team.salaryCap,
            limit: 3
        )

        return VStack(alignment: .leading, spacing: 0) {
            // Player header
            HStack(spacing: 12) {
                Text(player.position.rawValue)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                    .frame(width: 34)
                    .padding(.vertical, 4)
                    .background(positionSideColor(player.position), in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))

                VStack(alignment: .leading, spacing: 2) {
                    Text(player.fullName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.textPrimary)
                    HStack(spacing: 8) {
                        Text("\(player.overall) OVR")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Color.forRating(player.overall))
                        Text("Age \(player.age)")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                        Text(formatMillions(player.annualSalary) + "/yr")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Color.textTertiary)
                        motivationBadge(player.personality.motivation)
                    }
                    // R22: agent identity + negotiation style
                    agentBadge(for: player)
                }

                Spacer()

                // The number every button under this header is measured
                // against, so it is the biggest number on the card — it read
                // one weight quieter than the rumoured salaries above it.
                Text("~\(formatMillions(marketValue))")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(Color.accentBlue)
                Text("MKT")
                    .font(.system(size: DSType.Size.micro, weight: .bold))
                    .foregroundStyle(Color.accentBlue.opacity(0.7))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().overlay(Color.surfaceBorder.opacity(0.5))

            // FA alternatives column
            if !faAlternatives.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                            .font(.caption2)
                            .foregroundStyle(Color.accentBlue)
                        Text("Top FA alternatives:")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.accentBlue)
                    }

                    ForEach(faAlternatives, id: \.playerID) { fa in
                        HStack(spacing: 8) {
                            Text(fa.name)
                                .font(.caption)
                                .foregroundStyle(Color.textPrimary)
                                .lineLimit(1)
                            Text("(\(fa.currentTeamAbbr))")
                                .font(.caption2)
                                .foregroundStyle(Color.textTertiary)
                            Spacer()
                            Text("\(fa.overall) OVR")
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(Color.forRating(fa.overall))
                            // The decision above this list is an aging player,
                            // so an alternative with no age on it cannot be
                            // compared to him. `FAPreviewPlayer` already carries
                            // it — the row simply threw it away.
                            Text("Age \(fa.age)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(Color.textSecondary)
                            Text("~\(formatMillions(fa.estimatedSalary))")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(Color.textTertiary)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.backgroundTertiary.opacity(0.3))

                Divider().overlay(Color.surfaceBorder.opacity(0.5))
            }

            // Action area based on state
            actionArea(player: player, state: state, marketValue: marketValue)
        }
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.surfaceBorder, lineWidth: 1))
    }

    // MARK: - Action Area

    @ViewBuilder
    private func actionArea(player: Player, state: PlayerDecisionState, marketValue: Int) -> some View {
        switch state.status {
        case .pending:
            pendingActions(player: player, marketValue: marketValue)

        case .offering(let salary, let years):
            offeringView(player: player, salary: salary, years: years, marketValue: marketValue)

        case .responded(let response):
            responseView(player: player, response: response, marketValue: marketValue)

        case .reSignedAccepted:
            resolvedBadge(text: "Re-signed", icon: "checkmark.circle.fill", color: .success)

        case .letWalk:
            resolvedBadge(text: "Will hit free agency", icon: "figure.walk.departure", color: .textTertiary)

        case .tagged(let salary):
            resolvedBadge(
                text: "Franchise tagged — 1 yr, \(formatMillions(salary))",
                icon: "tag.fill",
                color: .accentGold
            )
        }
    }

    @ViewBuilder
    private func pendingActions(player: Player, marketValue: Int) -> some View {
        // R22: a hardliner agent who was insulted earlier this offseason still
        // refuses to do business — but the ROW does not announce it, in ANY
        // form. Before this wave it printed "isn't returning your calls" right
        // here; then it merely hid the gold Quick Offer button on exactly the
        // frozen rows, which is the same leak one control over. Every row now
        // carries the identical pair of buttons and the agent says it himself,
        // in character, when you contact him — or when you submit the offer.
        HStack(spacing: 12) {
            Button {
                negotiationPlayer = player
            } label: {
                Label(ContactAgentEntry.title, systemImage: ContactAgentEntry.icon)
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.accentBlue)

            Button {
                var state = PlayerDecisionState()
                state.status = .offering(salary: marketValue, years: 2)
                state.offerSalary = marketValue
                state.offerYears = 2
                decisions[player.id] = state
            } label: {
                Label("Quick Offer", systemImage: "signature")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(Color.accentGold)

            // R22: franchise tag straight from the re-sign flow (1 per offseason).
            if !hasUsedFranchiseTag {
                Button {
                    applyFranchiseTag(to: player)
                } label: {
                    Label("Tag (\(formatMillions(franchiseTagValue(for: player.position))))", systemImage: "tag")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(Color.accentGold)
            }

            Button {
                var state = PlayerDecisionState()
                state.status = .letWalk
                decisions[player.id] = state
                applyLetWalkPenaltyIfNeeded(player: player)
            } label: {
                Label("Let Walk", systemImage: "figure.walk.departure")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func offeringView(player: Player, salary: Int, years: Int, marketValue: Int) -> some View {
        VStack(spacing: 10) {
            HStack {
                Text("Offer:")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)

                Stepper("\(years)yr", value: Binding(
                    get: { decisions[player.id]?.offerYears ?? years },
                    set: { newVal in
                        decisions[player.id]?.offerYears = newVal
                        decisions[player.id]?.status = .offering(salary: decisions[player.id]?.offerSalary ?? salary, years: newVal)
                    }
                ), in: 1...5)
                .font(.caption.weight(.semibold).monospacedDigit())

                Spacer()

                Text(formatMillions(salary) + "/yr")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(Color.accentGold)
            }

            // Salary slider
            HStack(spacing: 8) {
                Text(formatMillions(500))
                    .font(.system(size: DSType.Size.caption).monospacedDigit())
                    .foregroundStyle(Color.textTertiary)
                Slider(
                    value: Binding(
                        get: { Double(decisions[player.id]?.offerSalary ?? salary) },
                        set: { newVal in
                            let rounded = Int((newVal / 500).rounded()) * 500
                            decisions[player.id]?.offerSalary = rounded
                            decisions[player.id]?.status = .offering(salary: rounded, years: decisions[player.id]?.offerYears ?? years)
                        }
                    ),
                    in: 500...75000,
                    step: 500
                )
                .tint(Color.accentGold)
                Text(formatMillions(75000))
                    .font(.system(size: DSType.Size.caption).monospacedDigit())
                    .foregroundStyle(Color.textTertiary)
            }

            HStack(spacing: 12) {
                Button("Submit Offer") {
                    let currentSalary = decisions[player.id]?.offerSalary ?? salary
                    let currentYears = decisions[player.id]?.offerYears ?? years
                    decisions[player.id]?.offerRounds += 1
                    let outcome = Self.evaluateReSignOffer(
                        player: player,
                        offeredSalary: currentSalary,
                        offeredYears: currentYears,
                        salaryCap: team?.salaryCap ?? ContractEngine.openingSalaryCap,
                        situation: reSignSituation(for: player),
                        standing: gmStanding,
                        standingAsk: decisions[player.id]?.standingAsk?.offer,
                        roundNumber: decisions[player.id]?.offerRounds ?? 1,
                        insultCount: decisions[player.id]?.insultCount ?? 0
                    )
                    if case .brokenOff = outcome.response {
                        // R22: hardliner freeze-out persists for the offseason.
                        NegotiationLockRegistry.lock(player.id)
                    }
                    // Pestering costs the man morale here exactly as it does in
                    // the chat: the ask ratcheted inside `evaluateReSignOffer`,
                    // and the engine cannot reach the player row to do the rest.
                    // Detected by the count moving on a REJECTED offer — the
                    // only way that happens is the refusal path.
                    if case .rejected = outcome.response,
                       outcome.insultCount > (decisions[player.id]?.insultCount ?? 0) {
                        player.morale = max(1, min(100,
                            player.morale - ContractNegotiationEngine.pesterMoraleCost))
                    }
                    decisions[player.id]?.insultCount = outcome.insultCount
                    if let counter = outcome.standingAsk {
                        decisions[player.id]?.standingAsk = NegotiationOfferSnapshot(counter)
                    }
                    decisions[player.id]?.status = .responded(response: outcome.response)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accentGold)
                .font(.caption.weight(.semibold))

                Button("Cancel") {
                    decisions[player.id]?.status = .pending
                }
                .buttonStyle(.bordered)
                .font(.caption.weight(.semibold))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func responseView(player: Player, response: ReSignResponse, marketValue: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            switch response {
            case .accepted:
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.success)
                    Text("\(player.fullName) accepted your offer!")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.success)
                }
                HStack(spacing: 12) {
                    Button("Finalize") {
                        if let team {
                            let salary = decisions[player.id]?.offerSalary ?? marketValue
                            let years = decisions[player.id]?.offerYears ?? 2
                            finalizeReSign(
                                player: player,
                                team: team,
                                salary: salary,
                                years: years
                            )
                            FASigningTracker.trackSigning(player.id)
                            generateStorylinesForSigning(player: player, team: team)
                            decisions[player.id]?.status = .reSignedAccepted
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.success)
                    .font(.caption.weight(.semibold))
                }

            case .countered(let counterSalary, let counterYears, let reason):
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(Color.warning)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(player.fullName): \"\(reason)\"")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.warning)
                        Text("Counter: \(formatMillions(counterSalary))/yr \u{00B7} \(counterYears) years")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                HStack(spacing: 12) {
                    Button("Accept Counter") {
                        if let team {
                            finalizeReSign(
                                player: player,
                                team: team,
                                salary: counterSalary,
                                years: counterYears
                            )
                            FASigningTracker.trackSigning(player.id)
                            generateStorylinesForSigning(player: player, team: team)
                            decisions[player.id]?.status = .reSignedAccepted
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.accentGold)
                    .font(.caption.weight(.semibold))

                    Button("Revise") {
                        decisions[player.id]?.offerSalary = counterSalary
                        decisions[player.id]?.offerYears = counterYears
                        decisions[player.id]?.status = .offering(salary: counterSalary, years: counterYears)
                    }
                    .buttonStyle(.bordered)
                    .font(.caption.weight(.semibold))

                    Button("Let Walk") {
                        decisions[player.id]?.status = .letWalk
                        applyLetWalkPenaltyIfNeeded(player: player)
                    }
                    .buttonStyle(.bordered)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textTertiary)
                }

            case .rejected(let reason):
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.danger)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(player.fullName) declined")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.danger)
                        Text("\"\(reason)\"")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                            .italic()
                    }
                }
                Button("Understood") {
                    decisions[player.id]?.status = .letWalk
                    applyLetWalkPenaltyIfNeeded(player: player)
                }
                .buttonStyle(.bordered)
                .font(.caption.weight(.semibold))

            case .brokenOff(let reason):
                // R22: hardliner agent cut off talks for the offseason.
                HStack(spacing: 8) {
                    Image(systemName: "phone.down.fill")
                        .foregroundStyle(Color.danger)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(AgentPersona.agentName(for: player.id)) ended all talks")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.danger)
                        Text("\"\(reason)\"")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                            .italic()
                    }
                }
                Button("Understood") {
                    decisions[player.id]?.status = .letWalk
                    applyLetWalkPenaltyIfNeeded(player: player)
                }
                .buttonStyle(.bordered)
                .font(.caption.weight(.semibold))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func resolvedBadge(text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Start League Year — the band and the bar

    /// The current slat's sub-caption: what this step is still holding open.
    private var finalPushSubcaption: String {
        let undecided = expiringPlayers.filter { decisions[$0.id]?.status == nil || isPending($0.id) }.count
        if undecided == 0 { return "Every expiring man answered" }
        return "\(undecided) expiring \(undecided == 1 ? "man" : "men") still undecided"
    }

    /// What committing does and what it forfeits (P4). The old copy said only
    /// "All remaining undecided players will hit the open market" and left the
    /// fifth-year options — which decline silently — unmentioned.
    private var startLeagueYearExplainer: DSActionBar.Explainer {
        let undecided = expiringPlayers.filter { decisions[$0.id]?.status == nil || isPending($0.id) }.count
        let openOptions = fifthYearCandidates.filter { !$0.fifthYearDecided }.count
        var parts: [String] = []
        if undecided > 0 {
            parts.append("**\(undecided) undecided \(undecided == 1 ? "player" : "players")** hit the open market")
        }
        if openOptions > 0 {
            parts.append("**\(openOptions) fifth-year \(openOptions == 1 ? "option is" : "options are")** declined")
        }
        guard !parts.isEmpty else {
            return .init(
                title: "Start the league year",
                message: "Every decision is made. Contracts roll over and the market opens."
            )
        }
        return .init(
            title: "Start the league year",
            message: parts.joined(separator: ", and ") + ". This cannot be undone.",
            isWarning: true
        )
    }

    // MARK: - Re-Sign Evaluation Logic

    /// One graded quick offer, plus the conversation state that has to survive
    /// to the next one.
    struct ReSignOutcome {
        let response: ReSignResponse
        /// The agent's number after this round — what the NEXT offer is graded
        /// against.
        let standingAsk: NegotiationOffer?
        let insultCount: Int
    }

    /// **Quick Offer, graded by the demand model.**
    ///
    /// This used to be a third, independent price function living in a View:
    /// a threshold of `0.80 − 0.12 loyalty − motivationMod − archetypeMod +
    /// persona.reSignThresholdShift` applied to `offeredSalary / marketValue`.
    /// It knew nothing of the agent's floor, the insult ratchet, patience, the
    /// GM's standing, the tag, a holdout, or the theatre in an opening ask — and
    /// it disagreed violently with the button beside it. A cooperative,
    /// loyalty-motivated team leader accepted at **0.40 of market** through
    /// Quick Offer while the Contact Agent thread on the same row would not sign
    /// him below ~0.73. Two buttons, one player, 1.8× apart.
    ///
    /// It also had no concept of refusal, so a player whose agent "won't take
    /// the call" signed through the control next to the one that said so.
    ///
    /// Everything numeric now comes from `ContractNegotiationEngine`; this
    /// function only translates the engine's verdict into the four states this
    /// screen renders.
    static func evaluateReSignOffer(
        player: Player,
        offeredSalary: Int,
        offeredYears: Int,
        salaryCap: Int,
        situation: NegotiationSituation,
        standing: GMStanding,
        standingAsk: NegotiationOffer?,
        roundNumber: Int = 1,
        insultCount: Int = 0
    ) -> ReSignOutcome {
        // The freeze-out is a first-class outcome here too, not a hidden button.
        if NegotiationLockRegistry.isLocked(player.id) {
            return ReSignOutcome(
                response: .brokenOff(
                    reason: "\(AgentPersona.agentName(for: player.id)) isn't taking calls about \(player.firstName) until next league year."
                ),
                standingAsk: standingAsk,
                insultCount: insultCount
            )
        }

        let demand = ContractNegotiationEngine.demand(
            player: player,
            negotiationType: .extend,
            salaryCap: salaryCap,
            situation: situation,
            standing: standing,
            insultCount: insultCount
        )

        if demand.isRefusing {
            // **Pestering, Quick-Offer edition.** Same rule as the chat: the
            // door being shut does not stop the club offering, and the offer
            // does not stop the door being shut. `respond` books the insult and
            // ratchets the ask, and the count rides back out so the NEXT Quick
            // Offer is graded against the hardened number — which is the only
            // thing that makes repeated pushing cost anything on this screen.
            let response = ContractNegotiationEngine.respond(
                gmOffer: NegotiationOffer(
                    years: offeredYears,
                    annualSalary: offeredSalary,
                    signingBonus: 0,
                    guaranteedPercent: 0,
                    noTradeClause: false
                ),
                player: player,
                demand: demand,
                previousAgentOffer: standingAsk ?? demand.openingOffer,
                roundNumber: roundNumber
            )
            return ReSignOutcome(
                response: .rejected(reason: refusalReason(player: player, reason: demand.refusalReason)),
                standingAsk: standingAsk,
                insultCount: response.demand.insultCount
            )
        }

        let ask = standingAsk ?? demand.openingOffer
        let gmOffer = NegotiationOffer(
            years: offeredYears,
            annualSalary: offeredSalary,
            signingBonus: 0,
            guaranteedPercent: ask.guaranteedPercent,
            noTradeClause: false
        )

        let result = ContractNegotiationEngine.respond(
            gmOffer: gmOffer,
            player: player,
            demand: demand,
            previousAgentOffer: ask,
            roundNumber: roundNumber
        )

        let persona = demand.persona

        switch result.outcome {
        case .dealReached:
            return ReSignOutcome(response: .accepted, standingAsk: ask, insultCount: result.demand.insultCount)

        case .negotiationsBrokenOff:
            return ReSignOutcome(
                response: .brokenOff(
                    reason: "That offer is an insult. \(player.firstName) is done talking to this front office until next year."
                ),
                standingAsk: ask,
                insultCount: result.demand.insultCount
            )

        case .playerWalked:
            return ReSignOutcome(
                response: .rejected(
                    reason: rejectReason(player: player, askPerYear: ask.annualCapHit)
                ),
                standingAsk: ask,
                insultCount: result.demand.insultCount
            )

        case .pending, .walkedAway:
            guard let counter = result.counterOffer else {
                return ReSignOutcome(
                    response: .rejected(
                        reason: rejectReason(player: player, askPerYear: ask.annualCapHit)
                    ),
                    standingAsk: ask,
                    insultCount: result.demand.insultCount
                )
            }
            return ReSignOutcome(
                response: .countered(
                    salary: counter.annualCapHit,
                    years: counter.years,
                    reason: result.isYearsPushback
                        ? "At \(player.age), \(player.firstName) won't sign a \(offeredYears)-year deal"
                        : counterReason(player: player, persona: persona)
                ),
                standingAsk: counter,
                insultCount: result.demand.insultCount
            )
        }
    }

    /// The refusal, in this screen's shorter voice. The wording is the chat
    /// layer's; the verdict behind it is the engine's.
    private static func refusalReason(player: Player, reason: AgentRefusalReason?) -> String {
        guard let reason else { return "\(player.firstName)'s camp isn't negotiating right now" }
        switch reason {
        case .benched:
            return "He hasn't taken a meaningful snap all year \u{2014} his camp won't discuss an extension"
        case .losingCulture:
            return "He has no interest in signing up for another rebuild"
        case .wantsOut:
            return "\(player.firstName) has already decided he wants out"
        case .ridingIntoRetirement:
            return "He's weighing retirement and won't commit to a new deal"
        case .ringChasing:
            // Says "not the money" explicitly. On a screen whose whole idiom is
            // "offer more", a refusal that does not close the door on money is
            // read as a hard negotiation and answered with a bigger number.
            return "He wants to play for a contender \u{2014} no offer changes that while this team is going nowhere"
        }
    }

    private static func counterReason(player: Player, persona: AgentPersona) -> String {
        // R22: the agent's persona colors the justification.
        switch persona {
        case .hardliner:
            return "\(player.firstName) wants starter money \u{2014} this is the number"
        case .loyalist:
            return "He took a discount to stay \u{2014} meet us halfway"
        case .cooperative:
            switch player.personality.motivation {
            case .money:   return "Wants more money \u{2014} feels undervalued"
            case .winning: return "Needs assurance this team can compete"
            case .stats:   return "Wants a bigger role guarantee"
            case .loyalty: return "Willing to stay, but needs fair compensation"
            case .fame:    return "Looking for a market-value deal"
            }
        }
    }

    /// `askPerYear` is the AGENT'S standing number, which is what he actually
    /// walked away from — quoting raw market value here would name a price
    /// neither side was arguing about.
    private static func rejectReason(player: Player, askPerYear: Int) -> String {
        switch player.personality.motivation {
        case .money:
            return "Wants to test the free agent market \u{2014} asking price is \(formatMillionsStatic(askPerYear))"
        case .winning:
            return "Looking for a championship contender"
        case .stats:
            return "Wants a bigger role elsewhere"
        case .loyalty:
            return "Feels undervalued \u{2014} expected at least \(formatMillionsStatic(Int(Double(askPerYear) * 0.9)))"
        case .fame:
            return "Seeking a big-market team for more exposure"
        }
    }

    // MARK: - Agent Persona (R22)

    /// Compact agent chip: name + deterministic negotiation style.
    private func agentBadge(for player: Player) -> some View {
        let persona = AgentPersona.forPlayer(id: player.id)
        let color: Color = {
            switch persona {
            case .hardliner:   return .danger
            case .cooperative: return .success
            case .loyalist:    return .accentGold
            }
        }()
        return HStack(spacing: 4) {
            Image(systemName: persona.symbolName)
                .font(.system(size: DSType.Size.micro))
            Text("Agent: \(AgentPersona.agentName(for: player.id))")
                .font(.system(size: DSType.Size.caption, weight: .semibold))
            Text(persona.styleLabel)
                .font(.system(size: DSType.Size.caption, weight: .bold))
        }
        .foregroundStyle(color.opacity(0.9))
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(color.opacity(0.1), in: Capsule())
    }

    // MARK: - Franchise Tag (R22)

    /// Whether any player on the user's team already carries this season's tag.
    private var hasUsedFranchiseTag: Bool {
        guard let teamID = career.teamID else { return false }
        return allPlayers.contains { $0.teamID == teamID && $0.isFranchiseTagged }
            || expiringPlayers.contains { $0.isFranchiseTagged }
    }

    /// Tag cost for a position: average of the league's top-5 salaries there.
    private func franchiseTagValue(for position: Position) -> Int {
        let positionSalaries = allPlayers
            .filter { $0.position == position && $0.annualSalary > 0 }
            .map { $0.annualSalary }
        return ContractEngine.franchiseTagValue(
            position: position,
            topSalaries: positionSalaries,
            capMode: career.capMode,
            salaryCap: team?.salaryCap ?? ContractEngine.openingSalaryCap
        )
    }

    /// Applies the franchise tag to an expiring player straight from the
    /// re-sign flow. Player stays for 1 year at the tag number (morale -10
    /// is applied inside ContractEngine — nobody wants the tag).
    private func applyFranchiseTag(to player: Player) {
        guard let team, !hasUsedFranchiseTag else { return }
        let tagCost = franchiseTagValue(for: player.position)
        // #127: the tag binds the league year this screen's rollover opens. Final
        // Push runs immediately before `FreeAgencyEngine.executeNewLeagueYear`
        // and `career.currentSeason` does not move across the offseason, so the
        // binding year is the same `currentSeason + 1` the tag screen stamps.
        ContractEngine.applyFranchiseTag(
            player: player,
            tagValue: tagCost,
            team: team,
            capMode: career.capMode,
            bindingSeason: career.currentSeason + 1,
            careerID: career.id
        )
        try? modelContext.save()
        // Deliberately does NOT set `franchiseTagVisited`. That flag means "the
        // user has been through the tag screen in THIS Review Roster phase" and
        // it is only cleared when Review Roster is left — so setting it here, a
        // phase later in free agency, silently pre-ticked next cycle's
        // "Franchise Tag Decisions" task before the user had seen it. The tag
        // itself is the evidence the task checks for anyway.
        var state = decisions[player.id] ?? PlayerDecisionState()
        // `tagCost`, not `player.annualSalary` (#127): the tag no longer
        // overwrites the salary — the expiring deal keeps running until the
        // rollover — so reading the player row here would report the OLD
        // contract as the tag number.
        state.status = .tagged(salary: tagCost)
        decisions[player.id] = state
    }

    // MARK: - Helpers

    /// Books a Quick Offer re-sign. `signFreeAgent` is the wrong tool for a man
    /// who is ALREADY on the roster: it charges the club the full new cap hit
    /// without crediting the salary the club was already carrying, and in
    /// realistic mode it inserts a second `Contract` row alongside the live one.
    ///
    /// **The guarantee is the agent's standing number, not zero.** It used to be
    /// hardcoded `0`, which meant the Quick Offer door booked a `Contract` row
    /// with no guaranteed money on a deal `evaluateReSignOffer` had graded WITH
    /// one — that function builds the GM's offer as
    /// `guaranteedPercent: ask.guaranteedPercent`, and Accept Counter takes the
    /// agent's counter whole. A guarantee never touches `Contract.capHit`, only
    /// `Contract.deadCap`, so the only thing the zero changed was the price of
    /// walking away: the newest and largest contract on the books was the one
    /// row in the club that could be released for nothing, while every man
    /// without a `Contract` row is priced at `ContractEngine.impliedDeadCap`.
    /// Re-sign in March, cut in August, keep the cap room. The Contact Agent
    /// door has always carried the negotiated structure (see the
    /// `onDealCompleted` note above); this is the half that was missing.
    ///
    /// The fallback is that proxy's league-mean rate, so a deal that somehow
    /// reaches here with no ask recorded is priced like the rest of the league
    /// rather than being free again.
    private func finalizeReSign(player: Player, team: Team, salary: Int, years: Int) {
        applyReSignOffer(
            player: player,
            team: team,
            offer: NegotiationOffer(
                years: years,
                annualSalary: salary,
                signingBonus: 0,
                guaranteedPercent: decisions[player.id]?.standingAsk?.guaranteedPercent
                    ?? Int(ContractEngine.impliedGuaranteeRate * 100),
                noTradeClause: false
            )
        )
    }

    /// **The one place a Final Push deal is written**, and the one place the
    /// league-year rollover is compensated for.
    ///
    /// `applyNegotiatedDeal(.replaceContract)` writes
    /// `contractYearsRemaining = offer.years`, and this screen is the last thing
    /// that happens before `FreeAgencyEngine.executeNewLeagueYear`, whose expiry
    /// loop decrements every contract in the league that is not franchise-tagged.
    /// So a deal agreed here was silently ONE YEAR SHORT: a 1-year re-sign
    /// expired the instant the league year turned and the man appeared as LOST on
    /// the very next screen, having been re-signed thirty seconds earlier.
    ///
    /// The AI's own re-sign path has always compensated the same way — see the
    /// `years + 1` in `FreeAgencyEngine.resignAIOwnCore`, "+1 because the expiry
    /// loop below decrements". The user's path is the half that was missing.
    ///
    /// The +1 lives HERE and not inside `applyNegotiatedDeal` because that engine
    /// call is also the in-season extension path (`PlayerDetailView`,
    /// `CapOverviewView`, `FranchiseTagView`), where no rollover follows and the
    /// term must land verbatim. Only Final Push runs immediately ahead of the
    /// decrement.
    ///
    /// The franchise tag needs no adjustment and deliberately does not get one,
    /// but not because its year survives the rollover untouched — the year is
    /// REWRITTEN there. `FreeAgencyEngine.settleFranchiseTags` runs inside
    /// `executeNewLeagueYear` and sets every tagged man to exactly
    /// `contractYearsRemaining = 1` off the forward ledger, and the expiry loop
    /// below it skips `isFranchiseTagged` rows so nothing decrements what it
    /// just wrote. Compensating here would be adding a year to a number the
    /// rollover is about to overwrite.
    ///
    /// Only `Player.contractYearsRemaining` is adjusted. In realistic mode the
    /// `Contract` row keeps the negotiated `totalYears`, exactly as it does for
    /// every other contract in the save — `Contract.currentYear` is never
    /// advanced anywhere in the game, so the player row is the authority on
    /// years left and the two were never in lockstep to begin with.
    private func applyReSignOffer(player: Player, team: Team, offer: NegotiationOffer) {
        ContractEngine.applyNegotiatedDeal(
            player: player,
            team: team,
            offer: offer,
            application: .replaceContract,
            capMode: career.capMode,
            careerID: career.id,
            modelContext: modelContext
        )
        player.contractYearsRemaining += 1
        try? modelContext.save()
    }

    private func isPending(_ playerID: UUID) -> Bool {
        guard let state = decisions[playerID] else { return true }
        if case .pending = state.status { return true }
        return false
    }

    private func motivationBadge(_ motivation: Motivation) -> some View {
        let (icon, label): (String, String) = {
            switch motivation {
            case .money:   return ("dollarsign.circle", "Money")
            case .winning: return ("trophy", "Winning")
            case .stats:   return ("chart.bar", "Stats")
            case .loyalty: return ("heart", "Loyalty")
            case .fame:    return ("star", "Fame")
            }
        }()

        return HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: DSType.Size.micro))
            Text(label)
                .font(.system(size: DSType.Size.caption, weight: .bold))
        }
        .foregroundStyle(Color.accentGold.opacity(0.8))
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Color.accentGold.opacity(0.1), in: Capsule())
    }

    private func statPill(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
            Text(value)
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
        }
    }

    private func positionSideColor(_ position: Position) -> Color {
        switch position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }

    private func formatMillions(_ thousands: Int) -> String {
        Self.formatMillionsStatic(thousands)
    }

    private static func formatMillionsStatic(_ thousands: Int) -> String {
        let millions = Double(thousands) / 1000.0
        if millions >= 1.0 {
            return String(format: "$%.1fM", millions)
        } else {
            return "$\(thousands)K"
        }
    }

    private func advanceToLeagueYear() {
        career.freeAgencyStep = FreeAgencyStep.newLeagueYear.rawValue
    }

    // MARK: - FA Drama Storyline + Penalty Wire-up

    /// Generates FA Drama storyline events (revenge / loyalty / coach reunion / hometown /
    /// mentor pair / community / milestone) for a re-signed player.
    private func generateStorylinesForSigning(player: Player, team: Team) {
        let teamID = team.id
        let coachDesc = FetchDescriptor<Coach>(predicate: #Predicate { $0.teamID == teamID })
        let teamCoaches = (try? modelContext.fetch(coachDesc)) ?? []

        var teamAbbrevs: [UUID: String] = [:]
        for t in allTeams { teamAbbrevs[t.id] = t.abbreviation }

        let unsignedFAs = allPlayers.filter { $0.teamID == nil && !$0.isRetired }

        FreeAgencyEngine.generateStorylineEventsForSigning(
            player: player,
            signingTeam: team,
            teamCoaches: teamCoaches,
            teamRegion: nil,
            teamAbbrevs: teamAbbrevs,
            allFAs: unsignedFAs,
            modelContext: modelContext
        )
    }

    /// FA Drama: applies the loyalty let-walk media penalty when a 4+ year vet
    /// is allowed to hit the open market. Persists a "disrespected legend"
    /// FAStorylineEvent and tweaks owner satisfaction + career reputation.
    private func applyLetWalkPenaltyIfNeeded(player: Player) {
        guard player.loyaltyYears >= LoyaltyEngine.loyaltyThresholdYears else { return }

        let penalty = LoyaltyEngine.letWalkPenalty(player: player)

        if let owner = team?.owner {
            owner.satisfaction = max(0, min(100, owner.satisfaction + penalty.ownerTrust))
        }
        // Fan mood penalty leaks into the career reputation.
        career.reputation = max(0, min(100, career.reputation + penalty.fanMood / 2))

        if let evt = LoyaltyEngine.generateLetWalkEvent(player: player) {
            evt.careerID = career.id
            modelContext.insert(evt)
        }
        try? modelContext.save()
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let teamID = career.teamID else { return }

        let teamDesc = FetchDescriptor<Team>(predicate: #Predicate { $0.id == teamID })
        team = try? modelContext.fetch(teamDesc).first

        guard let fetchedTeamID = team?.id else { return }

        // Expiring players on this team
        var playerDesc = FetchDescriptor<Player>(
            predicate: #Predicate { $0.teamID == fetchedTeamID && $0.contractYearsRemaining <= 1 }
        )
        playerDesc.sortBy = [SortDescriptor(\.annualSalary, order: .reverse)]
        expiringPlayers = (try? modelContext.fetch(playerDesc)) ?? []

        // Initialize decisions
        for player in expiringPlayers where decisions[player.id] == nil {
            decisions[player.id] = PlayerDecisionState()
        }

        // All players + teams for FA preview
        let cid = career.id
        allPlayers = (try? modelContext.fetch(FetchDescriptor<Player>(
            predicate: #Predicate { $0.careerID == cid }
        ))) ?? []
        allTeams = (try? modelContext.fetch(FetchDescriptor<Team>(
            predicate: #Predicate { $0.careerID == cid }
        ))) ?? []

        // Task #90 — the fifth-year option board.
        //
        // Filtered in memory rather than in the `#Predicate`, because the window
        // is an engine rule (`isFifthYearOptionWindow`) and a SwiftData
        // predicate cannot call it — and a re-typed copy of that rule in a fetch
        // is precisely how the user's screen and the rollover would come to
        // disagree about who has an option. A roster is ~53 rows; the whole
        // league is already in memory a few lines above anyway.
        //
        // A man the user has ALREADY answered for stays on the board (his
        // `contractYearsRemaining` moved to 3 on an exercise, so the window no
        // longer holds) — otherwise pressing Exercise would make the card
        // vanish, which reads as a bug rather than as a confirmation.
        //
        // The "already answered" test is the PERSISTED pair, not a `@State`
        // dictionary: leaving the screen and coming back inside the same league
        // year used to wipe the board clean, so the user could not see what he
        // had decided or that he had decided at all.
        //
        // `yearsPro == fifthYearOptionYearsPro` is what keeps a decided man on
        // THIS year's board only. `fifthYearDecided` is a once-per-career
        // stamp, but `yearsPro` moves at training camp — after this screen —
        // so it is 3 for exactly the offseason in which the option was answered
        // and 4 or more forever after.
        fifthYearCandidates = allPlayers
            .filter { $0.teamID == fetchedTeamID }
            .filter {
                FreeAgencyEngine.isFifthYearOptionWindow($0)
                    || ($0.fifthYearDecided
                        && $0.isFirstRoundPick
                        && !$0.isRetired
                        && $0.yearsPro == FreeAgencyEngine.fifthYearOptionYearsPro)
            }
            .sorted { ($0.draftPickNumber ?? 99) < ($1.draftPickNumber ?? 99) }
        // The franchise-tag input, built once per screen load instead of once
        // per row render: it is a sweep of every salary in the league.
        fifthYearSalaryTable = FreeAgencyEngine.positionSalaryTable(allPlayers: allPlayers)

        // Owner trust — one of the five GM-standing inputs the demand model
        // reads. Absent means the owner has never reacted to anything, which
        // must cost nothing: `GMStanding`'s neutral is 70, not 50.
        if let reputation = (try? modelContext.fetch(FetchDescriptor<DraftReputation>(
            predicate: #Predicate { $0.careerID == cid }
        )))?.max(by: { $0.seasonYear < $1.seasonYear }) {
            ownerTrust = reputation.ownerTrust
        }

        // R23: legal-tampering buzz — same pricing/need model the market uses.
        tamperingRumors = TamperingRumorEngine.generateRumors(
            allPlayers: allPlayers,
            allTeams: allTeams,
            userTeamID: career.teamID
        )
    }
}
