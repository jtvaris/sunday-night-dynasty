import SwiftUI
import SwiftData
import Combine

// MARK: - FA Signing Tracker

/// Tracks actual FA signings via UserDefaults for FACompleteView.
enum FASigningTracker {
    private static let key = "faSigningIDs"
    private static let lostKey = "faLostPlayerIDs"
    private static let preCapKey = "faPreCapUsage"
    private static let preOVRKey = "faPreRosterOVR"
    private static let preStarterGapsKey = "faPreStarterGaps"
    private static let baseSalaryCapKey = "faBaseSalaryCap"

    static func trackSigning(_ playerID: UUID) {
        var ids = getSigningIDs()
        ids.insert(playerID)
        let strings = ids.map(\.uuidString)
        UserDefaults.standard.set(strings, forKey: key)
    }

    static func getSigningIDs() -> Set<UUID> {
        let strings = UserDefaults.standard.stringArray(forKey: key) ?? []
        return Set(strings.compactMap { UUID(uuidString: $0) })
    }

    // MARK: - Lost Players

    static func trackLostPlayers(_ playerIDs: [UUID]) {
        let strings = playerIDs.map(\.uuidString)
        UserDefaults.standard.set(strings, forKey: lostKey)
    }

    static func getLostPlayerIDs() -> [UUID] {
        let strings = UserDefaults.standard.stringArray(forKey: lostKey) ?? []
        return strings.compactMap { UUID(uuidString: $0) }
    }

    // MARK: - Pre-FA Snapshot

    static func savePreFASnapshot(capUsage: Int, rosterOVR: Int, starterGaps: Int, baseSalaryCap: Int) {
        UserDefaults.standard.set(capUsage, forKey: preCapKey)
        UserDefaults.standard.set(rosterOVR, forKey: preOVRKey)
        UserDefaults.standard.set(starterGaps, forKey: preStarterGapsKey)
        UserDefaults.standard.set(baseSalaryCap, forKey: baseSalaryCapKey)
    }

    static func getPreFACapUsage() -> Int {
        UserDefaults.standard.integer(forKey: preCapKey)
    }

    static func getPreFARosterOVR() -> Int {
        UserDefaults.standard.integer(forKey: preOVRKey)
    }

    static func getPreFAStarterGaps() -> Int {
        UserDefaults.standard.integer(forKey: preStarterGapsKey)
    }

    static func getBaseSalaryCap() -> Int {
        let val = UserDefaults.standard.integer(forKey: baseSalaryCapKey)
        return val > 0 ? val : ContractEngine.openingSalaryCap
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: lostKey)
        UserDefaults.standard.removeObject(forKey: preCapKey)
        UserDefaults.standard.removeObject(forKey: preOVRKey)
        UserDefaults.standard.removeObject(forKey: preStarterGapsKey)
        UserDefaults.standard.removeObject(forKey: baseSalaryCapKey)
    }
}

// MARK: - Contract Offer

struct ContractOffer: Identifiable {
    let id = UUID()
    let playerID: UUID
    let salary: Int
    let years: Int
}

// MARK: - FAWeeklyView

struct FAWeeklyView: View {

    let career: Career

    @Environment(\.modelContext) private var modelContext

    @State private var team: Team?
    @State private var allTeams: [Team] = []
    @State private var freeAgents: [FreeAgencyEngine.FreeAgent] = []
    @State private var myOffers: [UUID: ContractOffer] = [:]
    @State private var roundResults: RoundResults?
    @State private var showSkipConfirm = false
    /// **The one modal slot on this screen.**
    ///
    /// Wave 3 / house rule: four `.sheet` modifiers in one hierarchy is the bug
    /// class that has bitten this codebase four times — the later ones win and
    /// the earlier ones dismiss silently. This screen had three (`selectedFA`,
    /// `showRoundSummary`, `visitOutcome`) plus an alert doing a result's job.
    /// They are one enum-driven `.sheet(item:)` now.
    @State private var activeSheet: ActiveSheet?
    @State private var positionFilter: PositionFilter = .all

    /// #187 — the market's sortable columns, on the shared list standard
    /// (`DSSortState`, `DSListRow.swift`). Opens on OVR descending, which is the
    /// order the board should have been in all along: `generateFreeAgentMarket`
    /// returns the market in the order the SwiftData fetch happened to hand back
    /// its players, i.e. in no order at all, and nothing sorted it afterwards.
    @State private var marketSort = DSSortState<MarketSort>(key: .ovr)
    @State private var biddingUpdates: [FreeAgencyEngine.BiddingUpdate] = []
    /// #102 — the ledger refused an offer at submit time. Carries the ledger's
    /// own refusal sentence so the block is never silent.
    @State private var capBlockMessage: String?
    /// #102 F10 — a completed signing that put the club over the cap. The
    /// backstop's verdict, surfaced at signing time instead of being discarded.
    @State private var capBreachViolation: WeekAdvancer.CapComplianceViolation?
    @State private var allPlayers: [Player] = []
    /// Who the club already starts at each spot. Built with the board rather
    /// than per row: the reading is drawn on every line and `allPlayers` is the
    /// whole league.
    @State private var incumbentByPosition: [Position: Incumbent] = [:]
    /// Rows whose sheet has been opened this sitting.
    ///
    /// Session state, deliberately — the view outlives all six market days, so
    /// it carries a pass over the board for as long as the pass lasts, and the
    /// only way it can be wrong (after leaving free agency and coming back) is
    /// by forgetting a row the user saw, never by claiming one he did not.
    @State private var openedPlayerIDs: Set<UUID> = []

    // FA Drama Phase 5 — Milestone signing sheet
    @State private var milestonePlayer: Player?
    @State private var milestoneActive: FAMilestone?
    @State private var milestoneFA: FreeAgencyEngine.FreeAgent?

    // R23 — Facility visits + signing interest meter
    @State private var visitedPlayerIDs: Set<UUID> = []
    @State private var teamOffensiveScheme: OffensiveScheme?
    @State private var teamDefensiveScheme: DefensiveScheme?
    private static let faVisitLimit = 3

    // FA Drama Phase 2 — Live Ticker / Heat / Outbid
    @State private var allBids: [FABid] = []
    @State private var allVisits: [FAVisit] = []
    @State private var visibleOutbidEvent: OutbidEvent?
    @State private var nowTick: Date = Date()
    private let outbidTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    // MARK: - The one modal slot

    /// Every modal this screen can show, as one value.
    ///
    /// `.instantSigning` is new only as a *presentation*: the outcome it carries
    /// used to be an `.alert("Instant Signing!")`, which §2.8 bans outright —
    /// an alert confirms, it never reports a result.
    private enum ActiveSheet: Identifiable {
        /// The offer dial (or the milestone variant, when the man is chasing one).
        case offer(FreeAgencyEngine.FreeAgent)
        /// What the facility visit revealed.
        case visit(FAVisitOutcome)
        /// The market day resolved.
        case roundSummary
        /// He took the offer on the spot.
        case instantSigning(InstantSigning)

        var id: String {
            switch self {
            case .offer(let fa):          return "offer-\(fa.player.id.uuidString)"
            case .visit(let outcome):     return "visit-\(outcome.id.uuidString)"
            case .roundSummary:           return "roundSummary"
            case .instantSigning(let it): return "signing-\(it.id.uuidString)"
            }
        }
    }

    /// An accepted-on-the-spot deal, as `DSResultSheet` needs it.
    struct InstantSigning: Identifiable {
        let id: UUID
        let playerName: String
        let position: String
        let salary: Int
        let years: Int
        /// Cap room left after the pen went down — the "what it cost" number.
        let capAfter: Int
    }

    /// The best man already on the roster at one position — the half of "is he
    /// an upgrade" the market board never had.
    struct Incumbent {
        let lastName: String
        let overall: Int
    }

    // Position filter
    enum PositionFilter: String, CaseIterable {
        case all = "All"
        case qb = "QB"
        case skill = "Skill"
        case ol = "OL"
        case dl = "DL"
        case lb = "LB"
        case db = "DB"

        var positions: [Position]? {
            switch self {
            case .all:   return nil
            case .qb:    return [.QB]
            case .skill: return [.RB, .FB, .WR, .TE]
            case .ol:    return [.LT, .LG, .C, .RG, .RT]
            case .dl:    return [.DE, .DT]
            case .lb:    return [.OLB, .MLB]
            case .db:    return [.CB, .FS, .SS]
            }
        }
    }

    private var currentRound: Int { career.freeAgencyRound }
    private var roundLabel: String { FreeAgencyStep.roundLabel(currentRound) }
    private var visibility: AIVisibilityLevel { FreeAgencyStep.aiVisibility(currentRound) }

    /// The market's four sortable columns — the ones the row prints as numbers.
    /// Not the name: a market is scanned by rating and by price, and the header
    /// should only offer what the list is actually read for.
    enum MarketSort: Hashable { case ovr, age, asks, years }

    private var filteredAgents: [FreeAgencyEngine.FreeAgent] {
        let filtered: [FreeAgencyEngine.FreeAgent]
        if let positions = positionFilter.positions {
            filtered = freeAgents.filter { positions.contains($0.player.position) }
        } else {
            filtered = freeAgents
        }

        // #187 / #134a: the id tiebreak is what stops two 78-OVR guards from
        // trading places between redraws. It matters more here than anywhere
        // else on the screen, because the row the user reaches for is
        // identified by its POSITION in the list and this list re-renders on a
        // 60-second ticker.
        let asc = marketSort.ascending
        switch marketSort.key {
        case .ovr:   return filtered.dsSorted(asc, by: { $0.player.overall }, id: { $0.player.id })
        case .age:   return filtered.dsSorted(asc, by: { $0.player.age },     id: { $0.player.id })
        case .asks:  return filtered.dsSorted(asc, by: { $0.askingPrice },    id: { $0.player.id })
        case .years: return filtered.dsSorted(asc, by: { $0.desiredYears },   id: { $0.player.id })
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.backgroundPrimary.ignoresSafeArea()

            if team != nil {
                VStack(spacing: 0) {
                    // §2.1 — the spine, pinned. It is the one place the flow
                    // prints its position, and its meter is the one place the
                    // market days are counted.
                    FAFlowBandView(
                        step: .signing,
                        currentSubcaption: signingSubcaption,
                        outcomes: flowOutcomes,
                        meter: marketDayMeter
                    )
                    liveTicker
                    biddingUpdatesBar
                    pendingOffersBar
                    positionFilterBar
                    freeAgentList
                    // §2.5 — the only place this screen commits.
                    actionBar
                }
            } else {
                // Blue: a spinner is informational, and P5's gold is spoken for
                // twice over on this screen (the band's current slat, the
                // commit) before the market has even loaded.
                ProgressView()
                    .tint(Color.accentBlue)
            }

            // Outbid alert banner overlay
            VStack {
                outbidBanner
                Spacer()
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: visibleOutbidEvent?.id)
        }
        .navigationTitle("Free Agency")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { loadData() }
        .onReceive(outbidTimer) { _ in
            nowTick = Date()
            refreshOutbidEvents()
        }
        // #102 — the committed-cap ledger refused this offer. Never silent: the
        // ledger's own sentence, so the block reads the same wherever it fires.
        .alert(
            "Not Enough Available Cap",
            isPresented: Binding(
                get: { capBlockMessage != nil },
                set: { if !$0 { capBlockMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { capBlockMessage = nil }
        } message: {
            Text(capBlockMessage ?? "")
        }
        // #102 F10 — the ACCEPTANCE-time backstop, spoken. A deal that was
        // accepted always completes (see `FreeAgencyEngine.SigningOutcome`), so
        // the only question is when the club finds out it is now illegal. Same
        // violation and same league-office letter the week-advance gate uses,
        // said the moment the pen goes down rather than at the next advance.
        .alert(
            "Over the Salary Cap",
            isPresented: Binding(
                get: { capBreachViolation != nil },
                set: { if !$0 { capBreachViolation = nil } }
            ),
            presenting: capBreachViolation
        ) { _ in
            Button("OK", role: .cancel) { capBreachViolation = nil }
        } message: { violation in
            Text(
                "That signing puts your club \(CommittedCapLedger.money(violation.overage)) over the cap. "
                + "The deal stands — but no week can be advanced until the books balance. "
                + "Release, restructure or renegotiate on the Cap Overview; the largest single saving "
                + "on your roster right now is \(CommittedCapLedger.money(violation.bestLeverSavings))."
            )
        }
        // Confirmation, not result (§2.8) — skipping forfeits the rest of the
        // market, and that is irreversible.
        .alert("Skip Remaining Free Agency?", isPresented: $showSkipConfirm) {
            Button("Skip", role: .destructive) { skipRemainingFA() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(skipConfirmMessage)
        }
        // ONE presentation point (house rule / wave 3). Everything modal this
        // screen can show is a case of `ActiveSheet`.
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .offer(let fa):          offerSheet(fa)
            case .visit(let outcome):     FAVisitResultSheet(outcome: outcome, visitsRemaining: visitsRemaining)
            case .roundSummary:           roundSummarySheet
            case .instantSigning(let it): instantSigningSheet(it)
            }
        }
    }

    // MARK: - Sheet content

    @ViewBuilder
    private func offerSheet(_ fa: FreeAgencyEngine.FreeAgent) -> some View {
        if let team {
            if let milestone = MilestoneTracker.activeMilestones(
                player: fa.player,
                history: MilestoneTracker.history(
                    playerID: fa.player.id,
                    careerID: fa.player.careerID,
                    modelContext: modelContext
                )
            ).first {
                MilestoneSigningSheet(
                    playerName: fa.player.fullName,
                    position: fa.player.position.rawValue,
                    age: fa.player.age,
                    milestone: milestone,
                    onSign: { years, multiplier in
                        let salary = max(Int(Double(fa.askingPrice) * multiplier), 750)
                        let outcome = FreeAgencyEngine.signFreeAgent(
                            player: fa.player,
                            team: team,
                            years: years,
                            salary: salary,
                            capMode: career.capMode,
                            modelContext: modelContext
                        )
                        reportSigningOutcome(outcome)
                        FASigningTracker.trackSigning(fa.player.id)
                        markVisitConverted(fa.player.id)
                        generateStorylinesForSigning(player: fa.player, team: team)
                        loadData()
                    }
                )
            } else {
                FAOfferSheet(
                    player: fa.player,
                    career: career,
                    team: team,
                    marketValue: fa.askingPrice,
                    allPlayers: allPlayers,
                    offensiveScheme: teamOffensiveScheme,
                    defensiveScheme: teamDefensiveScheme,
                    hostedVisit: visitedPlayerIDs.contains(fa.player.id),
                    // #102: every OTHER outstanding offer reserves cap. This
                    // man's own standing offer is excluded — re-opening the
                    // sheet to raise a bid must not price the bid it replaces.
                    pendingReserved: pendingReservedCap(excluding: fa.player.id),
                    onSubmit: { salary, years in
                    // #102 — the ledger has the last word. The sheet's own
                    // hard block already refuses an unaffordable offer, but
                    // the ledger is the authority and it is what the week
                    // gate reads, so the offer is booked THERE first and
                    // simply does not happen if it is refused.
                    guard reserveOffer(player: fa.player, salary: salary, years: years) else { return }

                    // Check for instant signing (big overpay on Day 1)
                    let instantResult = FreeAgencyEngine.checkInstantSigning(
                        offeredSalary: salary,
                        askingPrice: fa.askingPrice,
                        round: currentRound
                    )

                    switch instantResult {
                    case .signedImmediately, .coinFlipSigned:
                        // Player signs immediately -- too good to refuse.
                        // `signFreeAgent` releases the reservation it just
                        // took: the promise has become a contract.
                        let outcome = FreeAgencyEngine.signFreeAgent(
                            player: fa.player,
                            team: team,
                            years: years,
                            salary: salary,
                            capMode: career.capMode,
                            modelContext: modelContext
                        )
                        reportSigningOutcome(outcome)
                        FASigningTracker.trackSigning(fa.player.id)
                        markVisitConverted(fa.player.id)
                        generateStorylinesForSigning(player: fa.player, team: team)
                        loadData()
                        // §2.6: the result gets a result sheet. It used to
                        // be an alert, which §2.8 bans for exactly this job.
                        // Sequenced onto the next runloop turn because the
                        // offer sheet is dismissing itself in this same one,
                        // and a swap inside the dismissal is dropped.
                        let signed = InstantSigning(
                            id: fa.player.id,
                            playerName: fa.player.fullName,
                            position: fa.player.position.rawValue,
                            salary: salary,
                            years: years,
                            capAfter: team.availableCap
                        )
                        DispatchQueue.main.async { activeSheet = .instantSigning(signed) }

                    case .goesToMarket:
                        // Normal offer, goes to bidding process
                        myOffers[fa.player.id] = ContractOffer(
                            playerID: fa.player.id,
                            salary: salary,
                            years: years
                        )
                    }
                }
            )
            }
        }
    }

    @ViewBuilder
    private var roundSummarySheet: some View {
        if let results = roundResults {
            FARoundSummaryView(
                results: results,
                roundLabel: FreeAgencyStep.roundLabel(currentRound - 1),
                nextRoundLabel: currentRound <= 6 ? FreeAgencyStep.roundLabel(currentRound) : "Complete",
                onContinue: { activeSheet = nil }
            )
        }
    }

    /// §2.6 — outcome headline, what changed, what it cost, one Continue.
    private func instantSigningSheet(_ signing: InstantSigning) -> some View {
        DSResultSheet(
            tone: .good,
            eyebrow: "Free agency \u{00B7} \(roundLabel)",
            headline: "\(signing.playerName) signed on the spot",
            message: "The offer was too good to refuse — he took it before the market could answer.",
            chips: [
                .init(id: "pos", label: "Position", value: signing.position),
                .init(id: "aav", label: "Per year", value: formatMillions(signing.salary)),
                .init(id: "years", label: "Years", value: "\(signing.years)"),
                .init(
                    id: "cap",
                    label: "Cap room",
                    value: formatMillions(signing.capAfter),
                    context: "after the deal",
                    valueColor: signing.capAfter > 0 ? Color.textPrimary : Color.dangerText
                )
            ],
            cost: "Charges **\(formatMillions(signing.salary)) a year** for **\(signing.years) year\(signing.years == 1 ? "" : "s")** and takes him off the board for everyone else.",
            continueTitle: "Back to the market",
            onContinue: { activeSheet = nil }
        )
    }

    // MARK: - R23: Visits

    private var visitsRemaining: Int {
        max(0, Self.faVisitLimit - career.faVisitsUsed)
    }

    /// Hosts the free agent on a facility visit: burns a visit slot, persists
    /// the FAVisit, and reveals the player's true decision drivers.
    private func hostVisit(fa: FreeAgencyEngine.FreeAgent) {
        guard let team, let teamID = career.teamID else { return }
        guard career.faVisitsUsed < Self.faVisitLimit else { return }
        guard !visitedPlayerIDs.contains(fa.player.id) else { return }

        let visit = FAVisit(
            playerID: fa.player.id,
            teamID: teamID,
            seasonYear: career.currentSeason,
            expiresAt: Date().addingTimeInterval(48 * 3600),
            status: .active
        )
        visit.careerID = career.id
        modelContext.insert(visit)
        allVisits.append(visit)
        career.faVisitsUsed += 1
        visitedPlayerIDs.insert(fa.player.id)
        try? modelContext.save()

        let offer = myOffers[fa.player.id].map { (salary: $0.salary, years: $0.years) }
        let breakdown = SigningInterestEngine.interest(
            player: fa.player,
            askingPrice: fa.askingPrice,
            offer: offer,
            team: team,
            allPlayers: allPlayers,
            offensiveScheme: teamOffensiveScheme,
            defensiveScheme: teamDefensiveScheme,
            hostedVisit: true
        )
        activeSheet = .visit(FAVisitOutcome(
            id: fa.player.id,
            playerName: fa.player.fullName,
            position: fa.player.position.rawValue,
            overall: fa.player.overall,
            age: fa.player.age,
            askingPrice: fa.askingPrice,
            motivation: fa.player.personality.motivation,
            preferences: PlayerPreferenceEngine.generatePreferences(
                playerID: fa.player.id,
                position: fa.player.position
            ),
            roleNote: SigningInterestEngine.roleNote(
                player: fa.player,
                teamID: teamID,
                allPlayers: allPlayers
            ),
            breakdown: breakdown
        ))
    }

    /// Marks the player's active visit with us as converted (he signed here).
    private func markVisitConverted(_ playerID: UUID) {
        guard let teamID = career.teamID else { return }
        for visit in allVisits
        where visit.playerID == playerID && visit.teamID == teamID && visit.status == .active {
            visit.status = .converted
        }
    }

    // MARK: - Market day metadata

    /// Phase metadata for the progression indicator.
    private struct PhaseInfo {
        let label: String
        let description: String
        let isFrenzy: Bool
    }

    private func phaseInfo(for round: Int) -> PhaseInfo {
        // The frenzy rounds do not name the frenzy themselves: `isFrenzy` makes
        // `signingSubcaption` prefix the word, and both halves saying it printed
        // "Day 1 · Frenzy · Frenzy: top FAs sign fast".
        switch round {
        case 1: return PhaseInfo(label: "Day 1", description: "top FAs sign fast", isFrenzy: true)
        case 2: return PhaseInfo(label: "Day 2", description: "bidding wars peak", isFrenzy: true)
        case 3: return PhaseInfo(label: "Day 3", description: "Mid-tier FAs settle", isFrenzy: false)
        case 4: return PhaseInfo(label: "Week 2", description: "Bargains begin to appear", isFrenzy: false)
        case 5: return PhaseInfo(label: "Week 3", description: "Late market: depth signings", isFrenzy: false)
        case 6: return PhaseInfo(label: "Week 4", description: "Final round: cleanup signings", isFrenzy: false)
        default: return PhaseInfo(label: "Complete", description: "FA closed", isFrenzy: false)
        }
    }

    // MARK: The band's bindings (§2.1)

    /// The current slat's sub-caption: the market day and what that day is for.
    ///
    /// **This is the only place the day is named on this screen.** It used to be
    /// printed four times — a title, a six-dot rail, a "Day N" phase header and
    /// the submit button — which is precisely the "stage count rendered three
    /// times" that §2.1's one-count rule exists to stop. The commit button still
    /// names the day it is advancing TO, because naming a destination is what a
    /// commit label is for.
    private var signingSubcaption: String {
        let phase = phaseInfo(for: currentRound)
        let frenzy = phase.isFrenzy ? "Frenzy \u{00B7} " : ""
        return "\(phase.label) \u{00B7} \(frenzy)\(phase.description)"
    }

    /// A filled pip is a spent market day — the meter's one meaning, everywhere.
    private var marketDayMeter: DSResourceMeter {
        DSResourceMeter(spent: min(currentRound, 6), total: 6, unit: "market days")
    }

    /// What the steps behind this one produced (§2.1's `done` row is "check
    /// glyph + the outcome").
    ///
    /// Only what the screen can state honestly: the club is under the cap,
    /// because `CapComplianceView` would not have let it through otherwise.
    /// Final Push's re-signings are NOT reported here — `FASigningTracker`
    /// pools its own re-signings with market signings, so any count taken from
    /// it would be wrong from the first market day onward.
    private var flowOutcomes: [FreeAgencyStep: String] {
        career.capMode == .sandbox ? [:] : [.capReview: "Under the cap"]
    }

    /// The market's meta reading: the visit budget and the board size.
    ///
    /// **It used to be a bar of its own.** The day, the phase description and
    /// the six-step rail moved into the band (§2.1) and the cap ledger moved
    /// down onto the board (#187c), which left a full-width bar with a
    /// background, a hairline and 16 pt of padding carrying two 11 pt readings
    /// and a `Spacer` — about 31 pt of permanent chrome for one line of text,
    /// on the screen in the game with the most rows and the least room for
    /// them. It is now one end of the board's own head line, opposite
    /// `slotLegend`, which follows the same argument #187c made about the
    /// money: a reading belongs next to the thing it is a reading OF, not four
    /// bars above it.
    ///
    /// The visit budget is the one that has to be near the board. `Host Visit`
    /// stops being drawn once the allowance is spent (see `visitControl`), so
    /// this is where the user finds out why.
    private var boardMeta: some View {
        HStack(spacing: DSSpacing.sm) {
            // R23: facility visit budget for this FA period.
            HStack(spacing: DSSpacing.xxs) {
                Image(systemName: "building.2")
                    .font(DSType.display(11, .bold))
                Text("Visits left \(visitsRemaining)/\(Self.faVisitLimit)")
                    .font(DSType.display(11, .heavy))
            }
            .foregroundStyle(visitsRemaining > 0 ? Color.accentBlue : Color.textTertiaryReadable)

            Text("\(freeAgents.count) on the board")
                .font(DSType.display(11, .semibold))
                .foregroundStyle(Color.textTertiaryReadable)
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - Bidding Updates Bar

    /// What happened to the offers still on the table, as a list.
    ///
    /// #177: the second hand-built list on this screen. Its head was gold on
    /// gold (§2.9 says section heads are tracked `textSecondary` — gold has
    /// three jobs and "heading" is not one), its "Dismiss" was a 9 pt word with
    /// no target, and each row invented a 26 pt position chip, four type sizes
    /// between 9 and 12 pt, and two capsule buttons under 20 pt tall.
    @ViewBuilder
    private var biddingUpdatesBar: some View {
        if !biddingUpdates.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: DSSpacing.xxs + 2) {
                    Image(systemName: "megaphone.fill")
                        .font(DSType.text(DSType.Size.caption, .semibold))
                        .foregroundStyle(Color.textSecondary)
                    Text("BIDDING UPDATES")
                        .font(DSType.display(11, .heavy))
                        .tracking(0.7)
                        .foregroundStyle(Color.textSecondary)
                    Spacer(minLength: DSSpacing.xs)
                    Button {
                        biddingUpdates.removeAll()
                    } label: {
                        Text("Dismiss")
                            .font(DSType.text(DSType.Size.footnote, .semibold))
                            .foregroundStyle(Color.textSecondary)
                            .padding(.horizontal, DSSpacing.xs)
                            // 44 pt, measured (§2.12).
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Clears these updates. Your offers stay on the table.")
                }
                .padding(.leading, DSSpacing.md)
                .padding(.trailing, DSSpacing.xs)

                ForEach(biddingUpdates, id: \.playerID) { update in
                    biddingUpdateRow(update)
                }
            }
            .background(Color.backgroundSecondary)
            .overlay(
                Rectangle()
                    .fill(Color.surfaceBorder)
                    .frame(height: 1),
                alignment: .bottom
            )
        }
    }

    /// One outstanding offer, on the same anatomy as the market row below it —
    /// which is the point: the man in the updates bar and the man on the board
    /// are the same man, and they used to be drawn as two different objects.
    private func biddingUpdateRow(_ update: FreeAgencyEngine.BiddingUpdate) -> some View {
        let leaningTone: DSStatusPill.Tone = {
            switch update.playerLeaning {
            case .strongInterest, .prefersYou: return .ok
            case .undecided:                   return .warn
            case .leaningAway:                 return .bad
            }
        }()

        return VStack(alignment: .leading, spacing: DSSpacing.xxs) {
            DSListRow(
                density: .scan,
                badge: DSRowBadge(text: update.position, tint: Color.accentBlue),
                // No face: the updates bar is fed by `BiddingUpdate` values, not
                // by `Player`s, and reserving a portrait gutter it can never
                // fill would only push the columns in.
                portraitWidth: 0
            ) {
                EmptyView()
            } identity: {
                VStack(alignment: .leading, spacing: 1) {  // ds-lint:allow(spacing) name-over-slots lockup inside one row
                    Text(update.playerName)
                        .font(DSType.text(DSListDensity.scan.nameSize, .semibold, prose: true))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    DSStateSlotRow(slots: [
                        DSStateSlot(
                            label: "Lean",
                            tone: leaningTone,
                            // A short ident, not the engine's sentence: §2.2's
                            // documented defect is an 87 pt `nowrap` label in a
                            // 66 pt column painting over its neighbour, and
                            // "Strong Interest" is that label.
                            value: leaningShort(update.playerLeaning),
                            spokenLabel: "He is \(update.playerLeaning.rawValue.lowercased())"
                        ),
                        .slot(
                            "WAR",
                            isSet: update.isBiddingWar,
                            tone: .bad,
                            spoken: update.isBiddingWar ? "Bidding war" : "No bidding war"
                        ),
                        DSStateSlot(
                            label: "Bids",
                            tone: update.totalBidders >= 4 ? .bad : .neutral,
                            value: "\(update.totalBidders)",
                            spokenLabel: "\(update.totalBidders) club\(update.totalBidders == 1 ? "" : "s") bidding"
                        )
                    ])
                }
            } columns: {
                Spacer(minLength: DSSpacing.xxs)

                bidCell(
                    caption: "Yours",
                    value: formatMillions(update.yourOffer),
                    color: Color.textPrimary
                )
                bidCell(
                    caption: update.highestCompetingTeam.map { "Top \u{00B7} \($0)" } ?? "Top",
                    value: update.highestCompetingOffer.map { "~\(formatMillions($0))" } ?? "\u{2014}",
                    color: update.highestCompetingOffer == nil ? Color.textTertiaryReadable : Color.alertOrange
                )
            }

            // The two scoped actions, at the target floor and in the fixed
            // order §2.5 gives an action row: destructive on the left, behind
            // its own gap; the constructive one last.
            HStack(spacing: DSSpacing.xs) {
                Spacer(minLength: 0)

                Button {
                    dropOffer(update.playerID)
                    biddingUpdates.removeAll { $0.playerID == update.playerID }
                } label: {
                    Text("Withdraw")
                        .font(DSType.text(DSType.Size.footnote, .semibold))
                        .foregroundStyle(Color.dangerText)
                        .padding(.horizontal, DSSpacing.sm)
                        .frame(minHeight: 44)
                        .background(Color.danger.opacity(0.12), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Withdraw your offer to \(update.playerName)")
                .accessibilityHint("Releases the cap it is holding.")

                Button {
                    if let fa = freeAgents.first(where: { $0.player.id == update.playerID }) {
                        activeSheet = .offer(fa)
                    }
                } label: {
                    Text("Raise Offer")
                        .font(DSType.text(DSType.Size.footnote, .bold))
                        .foregroundStyle(Color.accentBlue)
                        .padding(.horizontal, DSSpacing.sm)
                        .frame(minHeight: 44)
                        .background(Color.accentBlue.opacity(0.12), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.accentBlue.opacity(0.4), lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Raise your offer to \(update.playerName)")
            }
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.xxs)
        .overlay(
            Rectangle()
                .fill(Color.surfaceBorder.opacity(0.5))
                .frame(height: 1),
            alignment: .top
        )
    }

    /// The lean, in one short word the pill can hold.
    private func leaningShort(_ leaning: FreeAgencyEngine.PlayerLeaning) -> String {
        switch leaning {
        case .strongInterest: return "Keen"
        case .prefersYou:     return "Ours"
        case .undecided:      return "Open"
        case .leaningAway:    return "Away"
        }
    }

    /// A money reading over its caption, in one column. Same width constant the
    /// market list uses for money, so the two lists' figures sit on one grid.
    private func bidCell(caption: String, value: String, color: Color) -> some View {
        VStack(spacing: 0) {
            Text(value)
                .font(DSType.display(DSType.Size.footnote, .heavy))
                .foregroundStyle(color)
            Text(caption.uppercased())
                .font(DSType.display(11, .semibold))
                .tracking(0.5)
                .foregroundStyle(Color.textTertiaryReadable)
        }
        .dsColumn(DSListColumn.money)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(caption): \(value)")
    }

    // `leaningIcon` is gone with #177: the leaning is a `Lean` state slot on
    // the row now, and a status pill carries a dot rather than a glyph — a
    // thumbs-up, a right arrow and a left arrow meant "he likes us", "he
    // prefers us" and "he is leaving", which is three icons for one axis.

    // MARK: - Cap Reservation Ledger (#102)

    /// Cap rules are off in sandbox — nothing is reserved and nothing is blocked.
    private var reservesCap: Bool { career.capMode != .sandbox }

    /// **The reservation ledger, read.**
    ///
    /// `CommittedCapLedger` is the authority and it is PERSISTED, not derived
    /// from `myOffers`: a promise has to survive the user backing out of the
    /// screen, and the week-advance gate has to be able to see it from a
    /// different part of the app. `myOffers` remains this screen's working set
    /// for resolving the round; the ledger is what the money means.
    ///
    /// - Parameter excludingPlayerID: a player whose standing offer should NOT
    ///   count. Re-opening the sheet on a man the club has already bid for is an
    ///   EDIT of that bid, so pricing it against itself would make every raise
    ///   illegal.
    private func capAvailability(excludingPlayerID: UUID? = nil) -> CommittedCapLedger.Availability {
        CommittedCapLedger.availability(
            team: team,
            careerID: career.id,
            season: career.currentSeason,
            capMode: career.capMode,
            excludingPlayerID: excludingPlayerID
        )
    }

    /// Cap the club's outstanding offers have already spoken for, in thousands
    /// per year.
    private func pendingReservedCap(excluding playerID: UUID? = nil) -> Int {
        capAvailability(excludingPlayerID: playerID).committed
    }

    /// **What this offer will really cost, per year** — the engine's own
    /// projection, not the dial.
    ///
    /// #102 F5. A realistic deal for a 28-year-old opens 15 % above the average
    /// and carries a prorated signing bonus on top, so reserving `salary`
    /// under-reserved every veteran signing by exactly the difference: $12M of
    /// room, three $4M offers to 30-year-olds, all three reserved 12 000, all
    /// three accepted, ~15 000 charged — through the very door this ledger
    /// exists to hold shut. `ContractEngine.projectedCapHit` builds the contract
    /// `FreeAgencyEngine.signFreeAgent` will write and reads its `capHit`, so
    /// there is one formula and the promise is the price.
    private func projectedCharge(player: Player, salary: Int, years: Int) -> Int {
        ContractEngine.projectedCapHit(
            playerID: player.id,
            annualSalary: salary,
            years: years,
            playerAge: player.age,
            capMode: career.capMode
        )
    }

    /// Cap Room minus everything already promised — the number every offer in
    /// this round is actually measured against.
    private var availableCapAfterOffers: Int { capAvailability().available }

    /// Books one outstanding offer. Returns false when the ledger refused it,
    /// in which case the offer must NOT be recorded anywhere else either.
    ///
    /// **A refusal is spoken.** The offer sheet's own hard block catches the
    /// ordinary case, but it prices against the `pendingReserved` it was handed
    /// when it opened — and the ledger is the authority, checked at submit time
    /// against the club's live books. When those two disagree (a bidding war
    /// resolved behind the sheet, a signing that moved cap usage, a stale sheet)
    /// the ledger wins, and dropping the offer without a word would look exactly
    /// like a dead button. `CommittedCapLedger.blockMessage` is the one sentence
    /// every offer surface refuses in, so it is what the user is shown.
    @discardableResult
    private func reserveOffer(player: Player, salary: Int, years: Int) -> Bool {
        let outcome = CommittedCapLedger.reserve(
            playerID: player.id,
            playerName: player.fullName,
            // #102 F5 — the PROJECTED charge, not the dial. `Reservation`'s own
            // doc has always said this field is "the per-year cap charge the
            // offer would create if accepted"; until now free agency handed it
            // the base salary.
            annualCapHit: projectedCharge(player: player, salary: salary, years: years),
            // The terms as the user typed them, so a rehydrated offer goes back
            // on the dial at the bid he made rather than at what it costs.
            baseSalary: salary,
            years: years,
            team: team,
            careerID: career.id,
            season: career.currentSeason,
            capMode: career.capMode
        )
        if case .blocked(_, _, let message) = outcome {
            capBlockMessage = message
            return false
        }
        return true
    }

    /// **The acceptance-time backstop, reported** (#102 F10).
    ///
    /// `FreeAgencyEngine.signFreeAgent` is documented as always COMPLETING an
    /// accepted deal and reporting the breach instead of voiding a contract the
    /// user was waiting on — and then every call site in the game threw the
    /// report away, so a club that signed its way over the cap heard nothing
    /// until the next Advance Week refused it. The verdict is re-derived through
    /// `WeekAdvancer.userCapComplianceViolation`, i.e. through the gate's own
    /// precheck, so the alert and the block can never disagree: it returns nil
    /// outside the compliance window, in sandbox, and — the anti-deadlock rule —
    /// for a club holding no lever that frees any cap, none of which is a state
    /// the user should be warned about.
    private func reportSigningOutcome(_ outcome: FreeAgencyEngine.SigningOutcome) {
        guard outcome.breachedCap else { return }
        guard let violation = WeekAdvancer.userCapComplianceViolation(
            career: career,
            modelContext: modelContext
        ) else { return }

        capBreachViolation = violation
        let letter = WeekAdvancer.capComplianceInboxMessage(
            violation,
            season: career.currentSeason,
            phase: career.currentPhase
        )
        // The process-global staging channel every out-of-shell producer posts
        // through; `CareerShellView.collectInboxMessages` drains it on the way
        // back out. Deduped against both books so a run of signings leaves one
        // letter rather than one per contract.
        let alreadyFiled = career.inbox.contains { $0.subject == letter.subject }
            || WeekAdvancer.lastInboxMessages.contains { $0.subject == letter.subject }
        if !alreadyFiled {
            WeekAdvancer.lastInboxMessages.append(letter)
        }
    }

    /// Drops an offer from BOTH books at once. Every place an offer stops being
    /// outstanding — withdrawn, outbid, signed, declined — goes through here, so
    /// the working set and the ledger cannot diverge.
    private func dropOffer(_ playerID: UUID) {
        myOffers.removeValue(forKey: playerID)
        CommittedCapLedger.release(playerID: playerID, careerID: career.id)
    }

    /// **Reconciles the two books on every load, in that order: prune, then
    /// rehydrate.**
    ///
    /// The reason this has to exist at all is that the two halves have different
    /// lifetimes. `myOffers` is `@State` — it dies the moment the user taps
    /// through to the roster and comes back, or backgrounds the app — while the
    /// ledger is careerID-scoped `UserDefaults` and survives everything. Without
    /// a reconcile the asymmetry is a one-way leak: the reservations stay,
    /// shrinking Available and hard-blocking legitimate offers, while the chips
    /// that could withdraw them are gone with the working set. A GM would be
    /// locked out of his own cap room by offers the screen no longer admits to
    /// having made.
    ///
    /// 1. **Prune.** `CommittedCapLedger.prune` drops every row for a player who
    ///    is no longer on the open market — signed elsewhere, retired, gone —
    ///    and every row stamped with an earlier league year. This is the file's
    ///    own documented defence #2, and until now nothing called it.
    /// 2. **Rehydrate.** Whatever survives is a live promise, so it goes back
    ///    into `myOffers` where the pending bar can render it and the user can
    ///    take it back. Existing entries win: an offer edited this session is
    ///    fresher than the row that seeded it.
    private func reconcileReservations() {
        guard reservesCap else { return }

        let openIDs = Set(
            freeAgents
                .filter { $0.player.teamID == nil }
                .map(\.player.id)
        )
        CommittedCapLedger.prune(
            careerID: career.id,
            season: career.currentSeason,
            openPlayerIDs: openIDs
        )

        for row in CommittedCapLedger.reservations(
            careerID: career.id,
            season: career.currentSeason
        ) where myOffers[row.playerID] == nil {
            myOffers[row.playerID] = ContractOffer(
                playerID: row.playerID,
                // The bid, not the charge (#102 F5) — `offeredSalary` falls back
                // to the charge for rows written before the two diverged.
                salary: row.offeredSalary,
                years: row.years
            )
        }
    }

    /// The market is closed — nothing outstanding can become a contract any
    /// more, so nothing may keep reserving room. Defence #3 from the ledger's
    /// own doc, and the reason a finished free agency hands the club its cap
    /// back instead of carrying phantom promises into the draft.
    private func closeReservations() {
        CommittedCapLedger.clearAll(careerID: career.id)
        myOffers.removeAll()
    }

    // #187c: `headerCapStat` — the stacked LABEL-over-value lockup the round
    // header used for Cap Room / Pending / Available — is gone with the block it
    // served. The same three readings are now `capStripStat`, inline, pinned to
    // the top of the board.

    // MARK: - Pending Offers Bar

    /// The outstanding offers, each with the room it is holding and a way to let
    /// that room go. **Withdrawing releases the reservation** — the promise is
    /// the only thing making the money unavailable, so taking the promise back
    /// has to hand it straight back.
    ///
    /// #177: blue, not gold. "You have money on this man" is the same fact the
    /// row's `BID` slot and the row's own tint now state, and it is
    /// informational (P7) — the screen's one gold belongs to the action bar's
    /// commit (P5). Three different paints for one fact was the reason a user
    /// could not tell the pending bar from the primary button.
    ///
    /// #199: the third hand-built list on this screen, and the one the #177 pass
    /// stopped short of. Its head spoke in `Font.caption` while the sibling bar
    /// three lines above it spoke in the tracked display voice (§2.10 allows two
    /// voices, and "whatever `Font.caption` resolves to" is a third), and its
    /// withdraw control was an 11 pt glyph — the same sub-target defect the
    /// bidding bar's "Dismiss" had before it was measured to 44.
    @ViewBuilder
    private var pendingOffersBar: some View {
        if !myOffers.isEmpty {
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                // The same head anatomy as `biddingUpdatesBar`: glyph, tracked
                // ident, the reading on the right. §2.9 — a section head is
                // tracked `textSecondary`, not a second accent competing with
                // the chips it introduces.
                HStack(spacing: DSSpacing.xs) {
                    Image(systemName: "doc.text.fill")
                        .font(DSType.text(DSType.Size.caption, .semibold))
                        .foregroundStyle(Color.textSecondary)
                    Text("\(myOffers.count) PENDING OFFER\(myOffers.count == 1 ? "" : "S")")
                        .font(DSType.display(DSType.Size.caption, .heavy))
                        .tracking(0.7)
                        .foregroundStyle(Color.textSecondary)
                    Spacer(minLength: DSSpacing.xs)
                    let totalCost = myOffers.values.reduce(0) { $0 + $1.salary }
                    Text(reservesCap
                         ? "Reserving \(formatMillions(totalCost))/yr"
                         : "Total: \(formatMillions(totalCost))/yr")
                        .font(DSType.display(DSType.Size.caption, .semibold))
                        .foregroundStyle(Color.textSecondary)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DSSpacing.xxs) {
                        ForEach(pendingOfferRows, id: \.offer.id) { row in
                            pendingOfferChip(name: row.name, offer: row.offer)
                        }
                    }
                }
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.xs)
            .background(Color.accentBlue.opacity(0.08))
        }
    }

    /// Offers resolved to names, in a stable order so the chips do not shuffle
    /// under the user's finger between renders.
    private var pendingOfferRows: [(name: String, offer: ContractOffer)] {
        myOffers.values
            .map { offer in
                let name = freeAgents.first { $0.player.id == offer.playerID }?.player.fullName
                    ?? allPlayers.first { $0.id == offer.playerID }?.fullName
                    ?? "Unknown"
                return (name: name, offer: offer)
            }
            .sorted { $0.offer.salary > $1.offer.salary }
    }

    /// One outstanding offer as a chip: who, what it costs, and the one control
    /// that hands the reserved room back.
    ///
    /// The withdraw target is **44 pt, measured** (§2.12) — the same treatment
    /// the bidding bar's "Dismiss" got, and it is what sets the chip's height, so
    /// the vertical padding lives on the button rather than on the capsule.
    ///
    /// The money stays on plain `textTertiary`: the token doc for
    /// `textTertiaryReadable` is explicit that it is the *darker* of the two and
    /// is only for sites shedding an opacity modifier, and this one never had one.
    private func pendingOfferChip(name: String, offer: ContractOffer) -> some View {
        HStack(spacing: DSSpacing.xxs) {
            // One size across the chip. `DSType.display` clamps to its 11 pt
            // floor, so a 10 pt name beside it would have read as two sizes.
            Text(name)
                .font(DSType.text(DSType.Size.caption, .semibold, prose: true))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
            Text("\(formatMillions(offer.salary))/yr × \(offer.years)")
                .font(DSType.display(DSType.Size.caption, .semibold))
                .foregroundStyle(Color.textTertiary)
            Button {
                dropOffer(offer.playerID)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(DSType.text(DSType.Size.caption, .semibold))
                    .foregroundStyle(Color.danger)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Withdraw offer to \(name)")
            .accessibilityHint("Releases \(formatMillions(offer.salary)) of reserved cap.")
        }
        // Leading only: the 44 pt target owns the trailing edge.
        .padding(.leading, DSSpacing.sm)
        .background(Color.backgroundSecondary, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.surfaceBorder, lineWidth: 1))
    }

    // MARK: - Position Filter

    /// Lens tabs: one control style, one selected fill (§2.2).
    ///
    /// The selected fill is **not gold** any more. P5 gives a screen one gold,
    /// and it now belongs to the action bar's commit; a filter chip wearing the
    /// same paint as the one irreversible button on the screen is the "four
    /// incompatible chip styles" problem in its loudest form. Selection is the
    /// same 2 pt `accentBlue` ring the slat band uses.
    private var positionFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DSSpacing.xxs) {
                ForEach(PositionFilter.allCases, id: \.self) { filter in
                    let isSelected = positionFilter == filter
                    Button {
                        positionFilter = filter
                    } label: {
                        Text(filter.rawValue)
                            .font(DSType.text(DSType.Size.footnote, .semibold))
                            .foregroundStyle(isSelected ? Color.textPrimary : Color.textSecondary)
                            .padding(.horizontal, DSSpacing.sm)
                            .padding(.vertical, DSSpacing.xs)
                            // The vertical padding alone drew a 31 pt chip. The
                            // rule is a measured rect, not a declared style.
                            .frame(minHeight: 44)
                            .background(
                                isSelected ? Color.backgroundTertiary : Color.backgroundSecondary,
                                in: Capsule()
                            )
                            .overlay(
                                Capsule().strokeBorder(
                                    isSelected ? Color.accentBlue : Color.surfaceBorder,
                                    lineWidth: isSelected ? 2 : 1
                                )
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.xs)
        }
    }

    // MARK: - Free Agent List

    /// The market, on the W1 list standard.
    ///
    /// #177: the conversion stopped at the screen's chrome and left the rows
    /// themselves hand-built — a bespoke position chip at 30 pt, a name line
    /// with four differently-shaped inline badges, an asking price in a
    /// free-floating `VStack` and no header at all, so nothing in the list had a
    /// column and nothing lined up down the page. It is `DSListRow` now, over a
    /// `DSListHeaderRow` that reads the same `DSListColumn` constants, which is
    /// the whole point of the standard: the header cannot drift from the cells.
    private var freeAgentList: some View {
        // Filtered AND sorted exactly once per body pass. `filteredAgents` was
        // read three times here, one of them inside the `ForEach` closure — i.e.
        // once per rendered row. That was already a wasted filter per row; with
        // #187's sort behind the same property it would have been a wasted SORT
        // per row, which on a 200-name board is the difference between a linear
        // pass and a quadratic one on every redraw of a screen that redraws on a
        // 60-second ticker.
        let agents = filteredAgents

        // The room every row's cap badge is measured against, read once for the
        // whole board: `availableCapAfterOffers` goes through the ledger, and
        // the badge is drawn on every line.
        let room = reservesCap ? availableCapAfterOffers : (team?.availableCap ?? 0)

        return VStack(spacing: 0) {
            // The board's own pinned head: what we can spend, then what the
            // columns mean. Both sit OUTSIDE the `ScrollView`, so neither can
            // scroll away from the rows they govern.
            VStack(spacing: DSSpacing.xxs) {
                capRoomStrip
                // The legend and the market's meta reading share one line: the
                // legend is short, `lineLimit(1)` prose and the meta is two
                // fixed readings, so between them they filled a line that each
                // of them was previously given on its own (the meta had a whole
                // bar — see `boardMeta`).
                HStack(spacing: DSSpacing.sm) {
                    if !agents.isEmpty {
                        slotLegend
                    }
                    Spacer(minLength: DSSpacing.xs)
                    boardMeta
                }
                if !agents.isEmpty {
                    marketHeader
                }
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.xxs)
            .background(Color.backgroundSecondary)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.surfaceBorder).frame(height: 1)
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(agents.enumerated()), id: \.element.player.id) { index, fa in
                        freeAgentRow(fa: fa, room: room)

                        if index < agents.count - 1 {
                            Divider()
                                .overlay(Color.surfaceBorder.opacity(0.5))
                                .padding(.horizontal, DSSpacing.xs)
                        }
                    }

                    if agents.isEmpty {
                        // §2.7's four beats. "No free agents available" answered
                        // none of them: it did not say WHY the list was empty
                        // (a filter with nobody behind it is a different problem
                        // from a market that has been cleared out) and it
                        // offered nothing to press.
                        DSEmptyState(
                            density: .scan,
                            icon: "person.slash",
                            title: positionFilter == .all
                                ? "The Board Is Empty"
                                : "No \(positionFilter.rawValue) On The Board",
                            message: emptyMarketMessage,
                            actions: positionFilter == .all
                                ? []
                                : [
                                    .init(
                                        title: "Show All Positions",
                                        systemImage: "line.3.horizontal.decrease.circle",
                                        isPrimary: false
                                    ) {
                                        positionFilter = .all
                                    }
                                ]
                        )
                    }
                }
            }
        }
    }

    // MARK: - Sticky cap strip (#187c)

    /// **What the club can actually spend, pinned to the top of the board.**
    ///
    /// Three readings, and the middle one is the whole reason the strip exists:
    /// an outstanding offer is money already promised, so a board that quotes
    /// only Cap Room invites the user to promise the same dollar twice. All
    /// three are drawn on every render — `PENDING` shows a dash when nothing is
    /// on the table rather than disappearing, because "no offers out" and "we
    /// never showed you" must not look the same.
    ///
    /// `AVAILABLE` is captioned in words — *after 3 pending offers* — instead of
    /// leaving the user to work out why it is smaller than Cap Room.
    @ViewBuilder
    private var capRoomStrip: some View {
        if let team {
            // In sandbox nothing reserves cap (`reservesCap`), so the ledger has
            // no claim to report and Available IS Cap Room. Quoting a pending
            // total there would be quoting a rule the mode does not run.
            let pending = reservesCap ? pendingReservedCap() : 0
            let available = reservesCap ? availableCapAfterOffers : team.availableCap
            let offerCount = reservesCap ? myOffers.count : 0

            HStack(spacing: DSSpacing.sm) {
                capStripStat(
                    label: "Cap Room",
                    value: formatMillions(team.availableCap),
                    color: team.availableCap >= 0 ? Color.textPrimary : Color.dangerText,
                    spoken: "Cap room \(formatMillions(team.availableCap))"
                )

                capStripStat(
                    label: "Pending",
                    value: pending > 0 ? "\u{2212}\(formatMillions(pending))" : "\u{2014}",
                    color: pending > 0 ? Color.warning : Color.textTertiaryReadable,
                    spoken: pending > 0
                        ? "\(formatMillions(pending)) held by \(offerCount) outstanding offer\(offerCount == 1 ? "" : "s")"
                        : "No offers on the table"
                )

                Spacer(minLength: DSSpacing.xs)

                capStripStat(
                    label: "Available",
                    value: formatMillions(available),
                    color: available > 0 ? Color.success : Color.dangerText,
                    spoken: pending > 0
                        ? "\(formatMillions(available)) available after \(offerCount) pending offer\(offerCount == 1 ? "" : "s")"
                        : "\(formatMillions(available)) available"
                )

                if pending > 0 {
                    Text("after \(offerCount) pending offer\(offerCount == 1 ? "" : "s")")
                        .font(DSType.display(11, .semibold))
                        .foregroundStyle(Color.textTertiaryReadable)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        // Spoken as part of the Available stat above.
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// One reading in the strip: LABEL then value, on one line.
    ///
    /// Inline rather than the stacked `headerCapStat` lockup because this strip
    /// is a list header, not a summary card — a two-line block above the column
    /// labels would push the first row of the market a full 40 pt further down
    /// the page on every visit.
    private func capStripStat(
        label: String,
        value: String,
        color: Color,
        spoken: String
    ) -> some View {
        HStack(spacing: DSSpacing.xxs) {
            Text(label.uppercased())
                .font(DSType.display(11, .heavy))
                .tracking(0.6)
                .foregroundStyle(Color.textTertiaryReadable)
            Text(value)
                .font(DSType.display(DSType.Size.body, .black))
                .foregroundStyle(color)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    /// Beat three: the condition that is missing, in the user's vocabulary.
    private var emptyMarketMessage: String {
        if positionFilter == .all {
            return currentRound >= 6
                ? "Every unsigned veteran has come off the board. The next names arrive when contracts expire at the end of the season."
                : "Nobody is left unsigned. Submit the day to let the rest of the league finish its business."
        }
        return "Nobody still on the market plays \(positionFilter.rawValue). Widen the filter to see who is left."
    }

    /// The header that labels the row's columns. Same constants, same order,
    /// same reserved gutters — including the trailing chevron, which the header
    /// reserves without drawing (§2.2's twice-documented off-by-one-column bug).
    ///
    /// #187: the four number columns sort now. Same component, same tap rule and
    /// same chevron as the roster and the league browser — the market was the
    /// one big list in the game whose columns were labels only, so "who is the
    /// cheapest 80-plus body left" was a question the board could not answer
    /// without the user reading all of it.
    ///
    /// `UPGRADE` and `ROOM` are not sortable and are deliberately not sortable:
    /// both are derived (the delta from `incumbentByPosition`, the percentage
    /// from `askingPrice / room`), and a sort on either is a sort on a column
    /// the header already offers. They are here to be **read down**, which is
    /// the whole reason they stopped being sentences.
    private var marketHeader: some View {
        DSListHeaderRow(
            density: .scan,
            reservesBadge: true,
            badgeLabel: "POS",
            identityLabel: "Free agent",
            affordance: .disclosure
        ) {
            Spacer(minLength: DSSpacing.xxs)
            DSColumnHeader("Upgrade", width: Self.upgradeColumn)
            DSSortableColumnHeader("OVR",  key: .ovr,   sort: $marketSort, width: DSListColumn.ovr)
            DSSortableColumnHeader("Age",  key: .age,   sort: $marketSort, width: DSListColumn.age)
            DSSortableColumnHeader("Asks", key: .asks,  sort: $marketSort, width: DSListColumn.money)
            DSSortableColumnHeader("Yrs",  key: .years, sort: $marketSort, width: DSListColumn.tight)
            DSColumnHeader("Room", width: DSListColumn.attribute)
        }
    }

    /// What the row's four state slots mean, in one line.
    ///
    /// The idents are a good scanning system once learned, and nothing else on
    /// the board taught them: `BID`, `VST` and `HEAT` were expanded only in
    /// their spoken labels, and the grey word beside the name (`motivationLabel`)
    /// is a bare noun. The line sits with the header, outside the scroll, so it
    /// cannot be lost the moment the list moves.
    private var slotLegend: some View {
        Text("SEEN opened \u{00B7} BID your offer \u{00B7} VST visited you \u{00B7} "
             + "HEAT rival bidding \u{00B7} grey word is what he chases")
            .font(DSType.text(11, .regular))
            .foregroundStyle(Color.textTertiaryReadable)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            // No `maxWidth: .infinity`: the line it shares with `boardMeta` has
            // a `Spacer` doing that job, and two greedy children would split
            // the slack down the middle instead of packing the legend left.
    }

    /// One free agent.
    ///
    /// The tap target is still the whole row and it still opens the offer dial;
    /// what changed is that the top line is now `DSListRow` — one anatomy, one
    /// badge shape, one set of column widths — and the single supporting line
    /// sits under it, indented to the row's own identity gutter rather than to
    /// a hand-typed `40`.
    ///
    /// **Why one supporting line and not two.** The market is the screen with
    /// the most rows in the game (a day-one board is 90+ names) and the least
    /// room to show them: a slat band, a ticker, two conditional bars, a filter
    /// strip, a three-line pinned board head and a commit bar all sit above and
    /// below the list. At three lines the row measured ~133 pt, which is
    /// seven names to a 1032 pt iPad — a market you page through rather than
    /// scan. Promoting the two always-present readings to columns (`UPGRADE`,
    /// `ROOM`) removed a line without removing a fact, and spent slack the
    /// identity slot was hoarding: at this width the flexible name column had
    /// several hundred points of void between the state pills and the OVR cell
    /// while the two most decision-relevant numbers on the row were crammed
    /// into an 11 pt sentence underneath it.
    ///
    /// The row reserves **four state slots** (§2.2), chosen once for the whole
    /// list and drawn on every line whether or not the fact behind them exists.
    /// The first three are ours, in the order the decision is made; the last is
    /// the rest of the league's:
    ///
    ///   * `SEEN` — have we opened his sheet at all
    ///   * `BID`  — is our money on the table, and how much
    ///   * `VST`  — have we had him in the building
    ///   * `HEAT` — how hard the rest of the league is chasing him
    ///
    /// `SEEN` is there because 126 names, seven rows to a screen and six market
    /// days is a pass nobody finishes in one go, and the board carried no mark
    /// of where the last one stopped — returning from a sheet left the row
    /// pixel-identical to before the tap.
    ///
    /// All three used to be conditional inline badges of three different
    /// shapes, so the answer the user actually scans a market for — *who has
    /// nobody on him yet* — was a column of gaps that were invisible because
    /// nothing was drawn in them.
    private func freeAgentRow(fa: FreeAgencyEngine.FreeAgent, room: Int) -> some View {
        let hasOffer = myOffers[fa.player.id] != nil

        return Button {
            openedPlayerIDs.insert(fa.player.id)
            activeSheet = .offer(fa)
        } label: {
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                DSListRow(
                    density: .scan,
                    // No rank: the board is filtered and re-sorted, so a "#4"
                    // would mean something different after every tap.
                    badge: DSRowBadge(
                        text: fa.player.position.rawValue,
                        tint: positionSideColor(fa.player.position),
                        accessibilityLabel: "\(fa.player.position.rawValue), \(fa.player.position.side.rawValue)"
                    ),
                    // The row IS the button, so it draws the affordance the
                    // header reserves for it.
                    affordance: .disclosure
                ) {
                    PersonFaceView(player: fa.player, size: .small)
                } identity: {
                    freeAgentIdentity(fa: fa, hasOffer: hasOffer)
                } columns: {
                    Spacer(minLength: DSSpacing.xxs)

                    upgradeCell(fa: fa)

                    Text("\(fa.player.overall)")
                        .font(DSType.display(DSType.Size.body, .heavy))
                        .foregroundStyle(Color.forRating(fa.player.overall))
                        .dsColumn(DSListColumn.ovr)

                    Text("\(fa.player.age)")
                        .font(DSType.display(DSType.Size.body, .semibold))
                        .foregroundStyle(Color.textSecondary)
                        .dsColumn(DSListColumn.age)

                    Text(formatMillions(fa.askingPrice))
                        .font(DSType.display(DSType.Size.body, .heavy))
                        .foregroundStyle(Color.textPrimary)
                        .dsColumn(DSListColumn.money)

                    Text("\(fa.desiredYears)")
                        .font(DSType.display(DSType.Size.body, .semibold))
                        .foregroundStyle(Color.textTertiaryReadable)
                        .dsColumn(DSListColumn.tight)

                    roomCell(asking: fa.askingPrice, room: room)
                }

                // What the rest of the league is saying about him, and the one
                // scoped control the row carries.
                //
                // This was TWO stacked lines. The four things on them were not
                // four of a kind: two were readings every row prints (what he
                // costs out of the room, who he would displace) and two are
                // occasional (a rumour, a rival count). The two that are always
                // there are columns now — see `upgradeCell` / `roomCell` — and
                // what is left fits on one line beside the control.
                //
                // `minHeight` keeps the line reserved on a row that happens to
                // have no rumour and no rivals, so the board's rhythm does not
                // depend on which facts exist.
                HStack(spacing: DSSpacing.xs) {
                    if let rumor = rumorText(for: fa) {
                        HStack(spacing: 3) {  // ds-lint:allow(spacing) icon-to-text gap
                            Image(systemName: rumor.icon)
                                .font(DSType.text(DSType.Size.caption))
                            Text(rumor.text)
                                .font(DSType.text(11, .regular))
                                .lineLimit(1)
                        }
                        .foregroundStyle(rumor.color)
                    }
                    aiInterestLabel(fa: fa)
                    Spacer(minLength: DSSpacing.xs)
                    interestChip(fa: fa)
                    visitControl(fa: fa)
                }
                .frame(minHeight: 22, alignment: .leading)
                .padding(.leading, Self.supportingInset)
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.xs)
            .background(hasOffer ? Color.accentBlue.opacity(0.06) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(hasOffer ? "Tap to update your offer" : "Tap to make an offer")
    }

    /// Where the supporting line starts: the badge column plus the portrait
    /// slot plus the identity gap, i.e. exactly under the player's name. It was
    /// a literal `40` that matched neither the old chip nor the new badge.
    private static let supportingInset: CGFloat =
        DSListColumn.position + DSListColumn.scanPortrait + DSListColumn.identityGap

    /// The `UPGRADE` cell. `DSListColumn.state` (76) is the app's widest cell
    /// constant — sized for "Discouraged" — and "Beckham 88" is the same shape
    /// of label, so the market borrows it rather than inventing a ninth width.
    private static let upgradeColumn: CGFloat = DSListColumn.state

    /// Name line, then the three reserved slots (§2.2).
    private func freeAgentIdentity(fa: FreeAgencyEngine.FreeAgent, hasOffer: Bool) -> some View {
        let heat = BiddingHeatEngine.computeHeat(
            playerID: fa.player.id,
            currentDay: career.freeAgencyRound,
            bids: allBids,
            visits: allVisits
        )
        let offer = myOffers[fa.player.id]
        let visited = visitedPlayerIDs.contains(fa.player.id)
        let opened = openedPlayerIDs.contains(fa.player.id)

        return VStack(alignment: .leading, spacing: 1) {  // ds-lint:allow(spacing) name-over-slots lockup inside one row
            HStack(spacing: DSSpacing.xxs) {
                Text(fa.player.fullName)
                    .font(DSType.text(DSListDensity.scan.nameSize, .semibold, prose: true))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)

                // What he is chasing. A category, not a status, so it carries
                // no colour: the badge it replaces was a gold capsule on every
                // row of the market (P5 allows one gold per screen, and it
                // belongs to the action bar's commit).
                //
                // No `Spacer` on this line — the identity block is the row's
                // one FLEXIBLE column, and a greedy child inside it competes
                // with the `Spacer` that opens `columns()` for the same slack.
                Text(motivationLabel(fa.player.personality.motivation))
                    .font(DSType.display(11, .semibold))
                    .foregroundStyle(Color.textTertiaryReadable)
                    .lineLimit(1)
            }

            DSStateSlotRow(slots: [
                // Neutral, not info: having looked at a man is a bookmark, not
                // a recommendation.
                .slot(
                    "SEEN",
                    isSet: opened,
                    tone: .neutral,
                    spoken: opened ? "You have opened his sheet" : "Not opened yet"
                ),
                .slot(
                    "BID",
                    isSet: hasOffer,
                    tone: .info,
                    value: offer.map { formatMillions($0.salary) },
                    spoken: hasOffer
                        ? "Your offer, \(formatMillions(offer?.salary ?? 0)) a year"
                        : "No offer from you"
                ),
                .slot(
                    "VST",
                    isSet: visited,
                    tone: .ok,
                    spoken: visited ? "Visited your facility" : "No facility visit"
                ),
                // HEAT is always set — the engine returns a tier for everyone,
                // and "cool" is a real reading rather than a hole.
                DSStateSlot(
                    label: "HEAT",
                    tone: heatTone(heat),
                    value: heatLabel(heat),
                    spokenLabel: "Market heat \(heatLabel(heat).lowercased())"
                )
            ])
        }
    }

    /// The heat tier on the status ladder. `cool` is `neutral`, not `info`:
    /// nothing about a quiet market is a selection or a recommendation.
    private func heatTone(_ tier: FrenzyHeatTier) -> DSStatusPill.Tone {
        switch tier {
        case .cool:    return .neutral
        case .yellow:  return .warn
        case .red:     return .bad
        case .burning: return .bad
        }
    }

    // MARK: - R23: Visit Control + Interest Chip

    /// The visit control, which is now **only a control**.
    ///
    /// It used to render a "VISITED" chip in the done case. That is a state,
    /// not an action, and §2.12's complaint is exactly this: a static chip and
    /// a tappable one drawn at the same size on the same line, so the user
    /// cannot tell which half of the row he may press. The state moved to the
    /// row's `VST` slot; what is left here is the button, and nothing when
    /// there is nothing left to press.
    ///
    /// **"Nothing left to press" now includes a spent budget.** The visit
    /// allowance is three for the whole free-agency period and it is stored on
    /// the career (`career.faVisitsUsed`), so once it is gone it does not come
    /// back until next offseason — a disabled "Host Visit" on all ninety
    /// remaining rows is 44 pt of dead control per row that can never become
    /// live again. The budget itself is still stated, once, where a budget
    /// belongs: `boardMeta`'s "Visits left 0/3", which now sits on the board's
    /// own head line rather than four bars up. Gating on the shared counter
    /// rather than on anything per-row means every row changes together, so the
    /// board's rhythm never breaks mid-list.
    @ViewBuilder
    private func visitControl(fa: FreeAgencyEngine.FreeAgent) -> some View {
        if visitsRemaining > 0 && !visitedPlayerIDs.contains(fa.player.id) {
            Button {
                hostVisit(fa: fa)
            } label: {
                HStack(spacing: DSSpacing.xxs) {
                    Image(systemName: "building.2")
                        .font(DSType.text(DSType.Size.caption))
                    Text("Host Visit")
                        .font(DSType.text(11, .semibold))
                }
                .foregroundStyle(Color.accentBlue)
                .padding(.horizontal, DSSpacing.xs)
                // 44, not 32: this button sits INSIDE a row that is itself a
                // button to the offer sheet, so every pixel it is short of the
                // rule opens the wrong surface instead of missing.
                .frame(minHeight: 44)
                .background(Color.accentBlue.opacity(0.12), in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Host \(fa.player.fullName) on a facility visit")
        }
    }

    /// Live interest reading — shown once we have skin in the game (an offer
    /// on the table or a hosted visit), matching the decision engine's factors.
    @ViewBuilder
    private func interestChip(fa: FreeAgencyEngine.FreeAgent) -> some View {
        if let team, myOffers[fa.player.id] != nil || visitedPlayerIDs.contains(fa.player.id) {
            let offer = myOffers[fa.player.id].map { (salary: $0.salary, years: $0.years) }
            let breakdown = SigningInterestEngine.interest(
                player: fa.player,
                askingPrice: fa.askingPrice,
                offer: offer,
                team: team,
                allPlayers: allPlayers,
                offensiveScheme: teamOffensiveScheme,
                defensiveScheme: teamDefensiveScheme,
                hostedVisit: visitedPlayerIDs.contains(fa.player.id)
            )
            // 11 pt, the display voice's floor (P7 corollary). This shipped at
            // 9 pt on the one reading that tells the user whether his money is
            // working.
            HStack(spacing: 3) {
                Image(systemName: breakdown.tier.icon)
                    .font(DSType.text(DSType.Size.caption))
                Text("Interest: \(breakdown.tier.rawValue)")
                    .font(DSType.display(11, .heavy))
            }
            .foregroundStyle(interestTierColor(breakdown.tier))
            .padding(.horizontal, DSSpacing.xxs + 2)
            .padding(.vertical, 2)
            .background(interestTierColor(breakdown.tier).opacity(0.12), in: Capsule())
        }
    }

    /// The interest tier, on the **status ladder** — bad at the bottom, good at
    /// the top.
    ///
    /// It used to run cold → blue, warm → amber, hot → red, scorching → gold,
    /// which put two opposite readings in the same paint on the same row: the
    /// `HEAT` slot two lines above is RIVAL heat, where red means "the league is
    /// all over him" (bad for us), and this chip is HIS heat for US, where the
    /// old red meant "he is nearly ours" (good for us). One row, one red, two
    /// meanings — and the top of the ladder wearing the screen's commit gold
    /// (P5 gives gold exactly three jobs, and "a hot lead" is none of them).
    ///
    /// The two top tiers share green deliberately. A five-hue ramp on an 11 pt
    /// chip is a palette, not a ladder; `Hot` and `Scorching` are told apart by
    /// the word the chip already prints.
    private func interestTierColor(_ tier: SigningInterestEngine.InterestTier) -> Color {
        switch tier {
        case .cold:      return .dangerText
        case .lukewarm:  return .alertOrange
        case .warm:      return .warning
        case .hot:       return .success
        case .scorching: return .success
        }
    }

    // MARK: - `ROOM` column

    /// What the ask costs out of **the room the club still has** — the same
    /// number the strip at the top of the board labels `AVAILABLE`, handed in
    /// so the cell does not re-read the ledger once per row.
    ///
    /// It used to divide by `salaryCap`, so an $18.1M ask on a club with $64.8M
    /// of room read "Will use 6 % of cap": true of a ~$264M total that appears
    /// nowhere on this screen, and a quarter of the answer to the only question
    /// the row is ever asked — can I afford him out of what is left.
    ///
    /// **It also used to be a sentence.** "Will use 34 % of your room" is a fine
    /// thing to read once and a terrible thing to read ninety times: the badge
    /// before it was a different width on every line, so the percentages never
    /// landed on a common x and could not be compared by eye. As a column the
    /// board answers "who is cheap out of what I have left" by scanning, which
    /// is what a market is for. The sentence survives as the spoken label.
    ///
    /// `OVER` rather than a true percentage above 100: the exact multiple of a
    /// room you do not have is not a reading anyone acts on, and "2400 %" in a
    /// 34 pt cell is a clip.
    private func roomCell(asking: Int, room: Int) -> some View {
        let pctRounded = room > 0 ? Int((Double(asking) / Double(room) * 100).rounded()) : 0
        let unaffordable = room <= 0 || asking > room
        let color: Color = {
            if unaffordable { return .dangerText }
            if pctRounded >= 50 { return .warning }
            return .textSecondary
        }()
        let value: String = {
            if room <= 0 { return "\u{2014}" }
            if asking > room { return "OVER" }
            return pctRounded <= 0 ? "<1%" : "\(pctRounded)%"
        }()
        let spoken: String = {
            if room <= 0 { return "No cap room left" }
            if asking > room { return "More than your remaining room" }
            return pctRounded <= 0
                ? "Under one per cent of your room"
                : "Would use \(pctRounded) per cent of your room"
        }()
        return Text(value)
            .font(DSType.display(DSType.Size.body, .heavy))
            .foregroundStyle(color)
            .dsColumn(DSListColumn.attribute)
            .accessibilityLabel(spoken)
    }

    // MARK: - `UPGRADE` column

    /// **What signing him would actually change.**
    ///
    /// The board's columns were POS / OVR / AGE / ASKS / YRS, so the highest
    /// rating left was always the apparent right answer: two strong safeties at
    /// the top of the list read as the two best buys on the screen whether the
    /// club already starts an 88 there or has nobody at all. Nothing else on
    /// this screen names the man he would be replacing — the position filter
    /// narrows the board but never ranks it by need — so the trade-off the
    /// market exists to pose was fake, and "sort by OVR, buy the top name you
    /// can afford" was the whole game.
    ///
    /// It is a **column** and not the sentence it used to be for the same
    /// reason `roomCell` is: need is the second axis of every buy on this
    /// board, and a second axis has to be readable down the page. `+9` over
    /// `Weeks 74` and `−4` under `Weeks 74` are two glances in a column and two
    /// readings of a paragraph anywhere else.
    ///
    /// Cheap by construction: `incumbentByPosition` is one dictionary lookup,
    /// built once per load rather than by scanning the roster per row.
    private func upgradeCell(fa: FreeAgencyEngine.FreeAgent) -> some View {
        let (value, caption, color, spoken) = { () -> (String, String, Color, String) in
            guard let held = incumbentByPosition[fa.player.position] else {
                // Nobody at the spot is the strongest reason on the board to
                // sign a man, and it is the one case the OVR column cannot say.
                return ("OPEN", "unfilled", .success,
                        "No \(fa.player.position.rawValue) on your roster")
            }
            let under = "\(held.lastName) \(held.overall)"
            let delta = fa.player.overall - held.overall
            if delta > 0 {
                return ("+\(delta)", under, .success,
                        "\(delta) better than \(held.lastName), \(held.overall) overall")
            }
            if delta == 0 {
                return ("=", under, .textTertiaryReadable,
                        "Level with \(held.lastName), \(held.overall) overall")
            }
            // A true minus sign, and `abs` — "-3 behind" was a double negative.
            return ("\u{2212}\(abs(delta))", under, .textTertiaryReadable,
                    "\(abs(delta)) worse than \(held.lastName), \(held.overall) overall")
        }()

        return VStack(spacing: 0) {
            Text(value)
                .font(DSType.display(DSType.Size.body, .heavy))
                .foregroundStyle(color)
            Text(caption)
                .font(DSType.display(11, .semibold))
                .foregroundStyle(Color.textTertiaryReadable)
        }
        .dsColumn(Self.upgradeColumn)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    // MARK: - Rumor System

    private struct Rumor {
        let text: String
        let icon: String
        let color: Color
    }

    private func rumorText(for fa: FreeAgencyEngine.FreeAgent) -> Rumor? {
        // Pick a single rumor in priority order (most signal first)
        // 1. Loyalty motivation -> hometown discount
        if fa.player.personality.motivation == .loyalty {
            return Rumor(text: "Hometown discount possible", icon: "house.fill", color: .accentBlue)
        }
        // 2. Heavy market interest -> bidding war chatter.
        //
        // The COUNT is not ours to print: `aiInterestLabel` is the next element
        // in the same HStack and it exists to say how many clubs are in, in
        // whatever detail the user's scouting has earned. Both of us naming the
        // number produced "7 teams interested — bidding war  7 teams interested"
        // on every row above the threshold. A rumour carries the flavour the
        // count cannot — that the room is bidding — and nothing else. Below
        // that, a bare count is not a rumour at all, so the chain falls through
        // to the motivation reads, which say something the number does not.
        if fa.marketInterest >= 7 {
            return Rumor(text: "Bidding war", icon: "flame.fill", color: .danger)
        }
        // 3. Money motivation -> wants top dollar
        if fa.player.personality.motivation == .money && fa.askingPrice > 8_000 {
            // Not gold: a rumour is a stated fact with no verdict, and this one
            // sat on the same paint as the screen's commit (#177).
            return Rumor(text: "Wants top-of-market money", icon: "dollarsign.circle.fill", color: .textSecondary)
        }
        // 4. Winning motivation -> contender discount
        if fa.player.personality.motivation == .winning {
            return Rumor(text: "Will take less for a contender", icon: "trophy.fill", color: .success)
        }
        // 5. Aging veteran -> short deal likely
        if fa.player.age >= 32 && fa.desiredYears <= 2 {
            return Rumor(text: "Likely short prove-it deal", icon: "clock.fill", color: .textSecondary)
        }
        return nil
    }

    // MARK: - AI Interest Label

    private func aiInterestLabel(fa: FreeAgencyEngine.FreeAgent) -> some View {
        let interest = fa.marketInterest
        guard interest > 0 else {
            return AnyView(EmptyView())
        }

        let text: String = {
            switch visibility {
            case .countOnly:
                return "\(interest) team\(interest == 1 ? "" : "s") interested"
            case .hints:
                let hint = interest >= 7 ? "A championship contender" : (interest >= 4 ? "Several teams" : "A team")
                return "\(hint) and \(max(interest - 1, 0)) other\(interest - 1 == 1 ? "" : "s") interested"
            case .partialNames:
                let sampleTeam = allTeams.filter { $0.id != team?.id }.randomElement()?.abbreviation ?? "???"
                return "\(sampleTeam) and \(max(interest - 1, 0)) other\(interest - 1 == 1 ? "" : "s")"
            case .fullNames:
                let otherTeams = allTeams.filter { $0.id != team?.id }.shuffled().prefix(min(interest, 3))
                let names = otherTeams.map(\.abbreviation).joined(separator: ", ")
                return names + (interest > 3 ? " +\(interest - 3) more" : "")
            }
        }()

        return AnyView(
            HStack(spacing: 3) {
                Image(systemName: "flame.fill")
                    .font(DSType.text(DSType.Size.caption))
                Text(text)
                    .font(DSType.text(11, .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(interest >= 7 ? Color.danger : (interest >= 4 ? Color.warning : Color.textTertiaryReadable))
        )
    }

    // MARK: - Bottom Bar

    /// §2.5 — the commit surface. Left: what advancing does and what it spends.
    /// Right: the fixed order, with the destructive skip behind its own rule and
    /// never adjacent to the primary.
    private var actionBar: some View {
        let nextLabel = currentRound < 6 ? FreeAgencyStep.roundLabel(currentRound + 1) : "Complete"
        // The commit names what the tap actually does. It used to read "Submit
        // offers" on a day with nothing on the table, directly beside an
        // explainer warning that nothing was on the table — the gold button
        // promising a submission the screen's own ledger said could not happen.
        let commit = myOffers.isEmpty
            ? "Advance"
            : "Submit \(myOffers.count) offer\(myOffers.count == 1 ? "" : "s")"
        return DSActionBar(
            explainer: submitExplainer,
            destructive: .init(
                title: "Skip the rest",
                caption: "AI clubs sign everyone left.",
                accessibilityLabel: "Skip the rest of free agency. AI clubs will sign everyone left.",
                handler: { showSkipConfirm = true }
            ),
            primary: .init(
                title: currentRound < 6 ? "\(commit) \u{2192} \(nextLabel)" : "Close the market",
                handler: { processRound() }
            )
        )
    }

    /// What the commit costs, said before it is made (P4).
    ///
    /// A day with nothing on the table is a warning rather than a price: the
    /// club is about to let the league bid unopposed, which is a real decision
    /// and used to be an unremarked side effect of a gold button.
    private var submitExplainer: DSActionBar.Explainer {
        let offerCount = myOffers.count
        guard offerCount > 0 else {
            return .init(
                title: "No offers on the table",
                message: "Advancing lets the league sign **unopposed** for a day you cannot get back.",
                isWarning: true
            )
        }
        let reserved = pendingReservedCap()
        let money = reservesCap && reserved > 0
            ? " They are holding **\(formatMillions(reserved))** of your room until they answer."
            : ""
        return .init(
            title: "Submit \(offerCount) offer\(offerCount == 1 ? "" : "s")",
            message: "Every club answers, then the rest of the league signs.\(money)"
        )
    }

    // MARK: - Process Round

    private func processRound() {
        guard let team else { return }

        // Generate AI bids for all free agents this round (need-based)
        // Task #93 F7: both of these take a `capMode` and both were letting it
        // default to `.simple`, so a sandbox league's AI clubs bid against a cap
        // their own signings do not respect and a realistic one priced its
        // bidding wars on the wrong rules.
        var aiBids = FreeAgencyEngine.generateAIOffers(
            freeAgents: freeAgents,
            round: currentRound,
            allTeams: allTeams,
            allPlayers: allPlayers.isEmpty ? nil : allPlayers,
            playerTeamID: career.teamID,
            capMode: career.capMode,
            season: career.currentSeason
        )

        // Process bidding wars (4+ teams on same player)
        let biddingWarInfos = FreeAgencyEngine.processBiddingWars(
            aiBids: &aiBids,
            freeAgents: freeAgents,
            allTeams: allTeams,
            capMode: career.capMode
        )

        // Process player's offers using resolvePlayerDecision
        var accepted: [(playerName: String, position: String, salary: Int, years: Int)] = []
        var rejected: [(playerName: String, position: String, reason: String, chosenTeam: String?, salary: Int?)] = []
        var shoppingAround: [(playerName: String, position: String)] = []

        for (playerID, offer) in myOffers {
            guard let fa = freeAgents.first(where: { $0.player.id == playerID }) else { continue }
            let player = fa.player

            let playerBids = aiBids[player.id] ?? []
            let decision = FreeAgencyEngine.resolvePlayerDecision(
                player: player,
                playerOffer: (salary: offer.salary, years: offer.years),
                aiBids: playerBids,
                round: currentRound,
                allTeams: allTeams,
                allPlayers: allPlayers,
                userTeamID: career.teamID,
                hostedVisit: visitedPlayerIDs.contains(player.id),
                fanSupport: career.fanSupport
            )

            if decision.shoppingAround {
                // Player wants to see more offers -- keep the offer active
                shoppingAround.append((
                    playerName: player.fullName,
                    position: player.position.rawValue
                ))
                // Don't remove from myOffers -- carry forward
                continue
            }

            if decision.accepted {
                // Signed with us
                let outcome = FreeAgencyEngine.signFreeAgent(
                    player: player,
                    team: team,
                    years: offer.years,
                    salary: offer.salary,
                    capMode: career.capMode,
                    modelContext: modelContext
                )
                reportSigningOutcome(outcome)
                FASigningTracker.trackSigning(player.id)
                markVisitConverted(player.id)
                generateStorylinesForSigning(player: player, team: team)
                accepted.append((
                    playerName: player.fullName,
                    position: player.position.rawValue,
                    salary: offer.salary,
                    years: offer.years
                ))
            } else {
                // Rejected -- chose another team.
                //
                // Task #93 F7: the signing goes through the market's own door,
                // so the deal is written the way the active cap mode says and
                // the club's `capReservePercent` reserve is honoured — the
                // affordability test used to be a bare `availableCap` check that
                // spent the reserve its own bid had respected.
                //
                // And that door can say NO. `processBiddingWars` escalates the
                // winner 5-15 % above a bid that was priced inside the reserve,
                // and every bid in a round is priced against one cap snapshot,
                // so a club that has already signed two men this round can lose
                // the man it just "won". The round summary is written from the
                // RESULT, not from the intention: reporting "chose CHI" for a
                // deal that was refused told the user his target was gone while
                // the man was still on the board, reappearing next round.
                var signedElsewhere = false
                if let chosenID = decision.chosenTeamID,
                   let aiTeam = allTeams.first(where: { $0.id == chosenID }) {
                    signedElsewhere = FreeAgencyEngine.signFreeAgentAI(
                        player: player,
                        team: aiTeam,
                        // Task #89: the AI's fallback term is bounded by the
                        // signing club's willingness at this age, exactly like
                        // the bid it is standing in for.
                        years: decision.years ?? max(1, min(
                            fa.desiredYears,
                            FreeAgencyEngine.contractYearsCeiling(age: fa.player.age)
                        )),
                        salary: decision.salary ?? fa.askingPrice,
                        capMode: career.capMode,
                        modelContext: modelContext
                    )
                }

                guard signedElsewhere else {
                    // Nobody could afford him. He is still a free agent and the
                    // user's offer is still on the table, which is the same
                    // state `shoppingAround` leaves him in — so it gets the same
                    // treatment: carried forward, reported as undecided.
                    shoppingAround.append((
                        playerName: player.fullName,
                        position: player.position.rawValue
                    ))
                    continue
                }

                rejected.append((
                    playerName: player.fullName,
                    position: player.position.rawValue,
                    reason: decision.reason,
                    chosenTeam: decision.chosenTeamName,
                    salary: decision.salary
                ))
            }
        }

        // Remove signed/rejected players from offers; keep shopping-around ones.
        // (A `shoppingIDs` set used to be built here from a map that produced
        //  nothing but `nil`, was never read, and is gone with #102's move to
        //  `dropOffer` — the names below are the real test.)
        for (playerID, _) in myOffers {
            let isShoppingAround = freeAgents
                .first(where: { $0.player.id == playerID })
                .map { fa in shoppingAround.contains(where: { $0.playerName == fa.player.fullName }) } ?? false
            if !isShoppingAround {
                // #102: the promise is over — the reservation goes with it.
                dropOffer(playerID)
            }
        }

        // Generate bidding updates for remaining offers (players still shopping)
        let offerTuples = myOffers.mapValues { offer in (salary: offer.salary, years: offer.years) }
        biddingUpdates = FreeAgencyEngine.generateBiddingUpdates(
            myOffers: offerTuples,
            aiBids: aiBids,
            freeAgents: freeAgents,
            playerTeamID: career.teamID
        )

        // AI signings for this round (players without our offers)
        let aiSignings = simulateAIRound(excludePlayerIDs: Set(myOffers.keys), aiBids: aiBids)

        // Generate media headlines (with bidding war info)
        let headlines = FreeAgencyEngine.generateHeadlines(
            signings: aiSignings,
            rejections: rejected.map { (playerName: $0.playerName, chosenTeam: $0.chosenTeam) },
            biddingWars: biddingWarInfos,
            playerTeamAbbr: team.abbreviation,
            round: currentRound
        )

        // Build results
        roundResults = RoundResults(
            yourSignings: accepted,
            yourRejections: rejected,
            aiSignings: aiSignings,
            headlines: headlines,
            playersRemaining: freeAgents.filter { $0.player.teamID == nil }.count - accepted.count,
            capRemaining: team.availableCap,
            biddingWars: biddingWarInfos,
            shoppingAround: shoppingAround,
            biddingUpdates: biddingUpdates
        )

        if currentRound >= 6 {
            career.freeAgencyStep = FreeAgencyStep.complete.rawValue
            // #102: the market is shut. Nothing outstanding can become a
            // contract, so nothing may keep reserving room.
            closeReservations()
        } else {
            career.freeAgencyRound += 1
        }

        // Refresh free agents
        loadData()
        activeSheet = .roundSummary
    }

    private func simulateAIRound(excludePlayerIDs: Set<UUID>, aiBids: [UUID: [FreeAgencyEngine.AIBid]]) -> [(playerName: String, position: String, team: String, salary: Int)] {
        let roundFAs = freeAgents.filter { !excludePlayerIDs.contains($0.player.id) && $0.player.teamID == nil }

        var signings: [(playerName: String, position: String, team: String, salary: Int)] = []

        for fa in roundFAs {
            // Use AI bids generated by generateAIOffers
            guard let bids = aiBids[fa.player.id], !bids.isEmpty else { continue }

            // Resolve which team wins -- player decides among AI offers only
            // (R23: role factor applies to AI rosters too via allPlayers).
            let decision = FreeAgencyEngine.resolvePlayerDecision(
                player: fa.player,
                playerOffer: nil,
                aiBids: bids,
                round: currentRound,
                allTeams: allTeams,
                allPlayers: allPlayers,
                fanSupport: career.fanSupport
            )

            // Task #93 F8: "wants to explore all options before committing" was
            // computed, handed back and then ignored on this path — the same
            // decision that keeps the USER's offer alive for another round
            // signed the man to an AI club immediately.
            //
            // `resolvePlayerDecision` now only raises the flag when the user is
            // one of the bidders, so on this all-AI pass it never fires and the
            // guard is a rail rather than a filter. That is the point: honouring
            // it unconditionally emptied rounds 1-2 of every contested elite
            // free agent — the two days whose whole purpose is the opening
            // splash — and dumped them into round 3 at `aiAggression` 0.7.
            guard !decision.shoppingAround else { continue }

            if let chosenID = decision.chosenTeamID,
               let signingTeam = allTeams.first(where: { $0.id == chosenID }),
               let salary = decision.salary {
                // Task #93 F7: cap-mode-aware, reserve-respecting signing door.
                let signed = FreeAgencyEngine.signFreeAgentAI(
                    player: fa.player,
                    team: signingTeam,
                    years: decision.years ?? fa.desiredYears,
                    salary: salary,
                    capMode: career.capMode,
                    modelContext: modelContext
                )
                guard signed else { continue }

                signings.append((
                    playerName: fa.player.fullName,
                    position: fa.player.position.rawValue,
                    team: signingTeam.abbreviation,
                    salary: salary
                ))
            }
        }

        return signings
    }

    // MARK: - Skip

    /// What skipping actually forfeits, counted.
    ///
    /// The static version said only that the AI would sign the rest — which is
    /// true of every market day and so tells the user nothing about the one he
    /// is about to give away permanently. All four numbers are already on the
    /// screen behind the alert; the confirm step is where they matter.
    private var skipConfirmMessage: String {
        let room = reservesCap ? availableCapAfterOffers : (team?.availableCap ?? 0)
        let daysLeft = max(6 - currentRound, 0)
        var stakes: [String] = []
        if room > 0 { stakes.append("\(formatMillions(room)) in cap room") }
        if visitsRemaining > 0 {
            stakes.append("\(visitsRemaining) facility visit\(visitsRemaining == 1 ? "" : "s")")
        }
        stakes.append("\(freeAgents.count) free agent\(freeAgents.count == 1 ? "" : "s")")

        let listed = stakes.count > 1
            ? stakes.dropLast().joined(separator: ", ") + " and " + (stakes.last ?? "")
            : (stakes.first ?? "")
        return "You are leaving \(listed) to the rest of the league, with "
            + "\(daysLeft) market day\(daysLeft == 1 ? "" : "s") unplayed. "
            + "The AI clubs will sign whoever is left, and this cannot be undone."
    }

    private func skipRemainingFA() {
        let cid = career.id
        let allPlayers = (try? modelContext.fetch(FetchDescriptor<Player>(
            predicate: #Predicate { $0.careerID == cid }
        ))) ?? []
        // Task #93 F7/F9: the career's cap mode reaches the market (it defaulted
        // to `.simple` here, so a sandbox or realistic league had its bulk
        // signings booked under simple-mode rules), and the run is stamped so
        // `WeekAdvancer`'s mop-up cannot open the same market a second time.
        FreeAgencyEngine.simulateRemainingFAOnce(
            allPlayers: allPlayers,
            allTeams: allTeams,
            playerTeamID: career.teamID,
            modelContext: modelContext,
            capMode: career.capMode,
            career: career
        )
        career.freeAgencyStep = FreeAgencyStep.complete.rawValue
        // #102: skipping the rest of free agency closes the market too — the
        // reservations behind the skipped rounds can never be collected.
        closeReservations()
        // The stamp is a MODEL mutation now, so it has to reach the store before
        // the user can quit — the relaunch it defends against is the one where
        // `WeekAdvancer`'s mop-up would otherwise open the market a second time.
        try? modelContext.save()
    }

    // MARK: - Helpers

    private func rejectReason(player: Player) -> String {
        switch player.personality.motivation {
        case .money:   return "Chose a higher offer from another team"
        case .winning: return "Chose a championship contender"
        case .stats:   return "Chose a team offering a larger role"
        case .loyalty: return "Returned to familiar surroundings"
        case .fame:    return "Chose a big-market team for more exposure"
        }
    }

    /// One word for what he is chasing. The gold-capsule-with-a-glyph version
    /// this replaces is gone with #177 — same decision, same word list and same
    /// reasoning the market list on the contracts side reached before it was
    /// merged into this screen.
    private func motivationLabel(_ motivation: Motivation) -> String {
        switch motivation {
        case .money:   return "Money"
        case .winning: return "Winning"
        case .stats:   return "Stats"
        case .loyalty: return "Loyalty"
        case .fame:    return "Fame"
        }
    }

    /// The position badge's fill — which SIDE of the ball he plays on.
    ///
    /// Special teams was gold, which put the screen's primary-action paint on
    /// every kicker in the market (#177). It is the neutral surface now: the
    /// third side of the ball is a category, not an emphasis.
    private func positionSideColor(_ position: Position) -> Color {
        switch position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .backgroundTertiary
        }
    }

    private func formatMillions(_ thousands: Int) -> String {
        let millions = Double(thousands) / 1000.0
        if millions >= 1.0 {
            return String(format: "$%.1fM", millions)
        } else {
            return "$\(thousands)K"
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let teamID = career.teamID else { return }

        let teamDesc = FetchDescriptor<Team>(predicate: #Predicate { $0.id == teamID })
        team = try? modelContext.fetch(teamDesc).first

        let cid = career.id
        allTeams = (try? modelContext.fetch(FetchDescriptor<Team>(
            predicate: #Predicate { $0.careerID == cid }
        ))) ?? []

        allPlayers = (try? modelContext.fetch(FetchDescriptor<Player>(
            predicate: #Predicate { $0.careerID == cid }
        ))) ?? []

        // Our own depth chart, one entry per spot. Rebuilt on every load, so a
        // man signed this morning is the incumbent every row is measured
        // against this afternoon.
        var incumbents: [Position: Incumbent] = [:]
        for p in allPlayers where p.teamID == teamID && !p.isRetired {
            if let held = incumbents[p.position], held.overall >= p.overall { continue }
            incumbents[p.position] = Incumbent(lastName: p.lastName, overall: p.overall)
        }
        incumbentByPosition = incumbents

        // Task #87 / F9: this whole screen's asking prices used to be generated
        // against `generateFreeAgentMarket`'s season-one default while `team` sat
        // in scope eleven lines above, so from season two onward this screen
        // quoted season-one prices for every free agent.
        freeAgents = FreeAgencyEngine.generateFreeAgentMarket(
            allPlayers: allPlayers,
            salaryCap: team?.salaryCap ?? ContractEngine.openingSalaryCap
        )

        // FA Drama: load bids + visits for heat / ticker / outbid detection
        allBids = (try? modelContext.fetch(FetchDescriptor<FABid>(
            predicate: #Predicate { $0.careerID == cid }
        ))) ?? []
        allVisits = (try? modelContext.fetch(FetchDescriptor<FAVisit>(
            predicate: #Predicate { $0.careerID == cid }
        ))) ?? []
        refreshOutbidEvents()

        // R23: visits already hosted by the user's team this FA period, plus
        // the coaching staff's schemes for the interest meter's scheme-fit factor.
        visitedPlayerIDs = Set(
            allVisits
                .filter { $0.teamID == teamID && $0.seasonYear == career.currentSeason }
                .map(\.playerID)
        )
        let coachDesc = FetchDescriptor<Coach>(predicate: #Predicate { $0.teamID == teamID })
        let teamCoaches = (try? modelContext.fetch(coachDesc)) ?? []
        teamOffensiveScheme = teamCoaches.first(where: { $0.role == .offensiveCoordinator })?.offensiveScheme
            ?? teamCoaches.first(where: { $0.role == .headCoach })?.offensiveScheme
        teamDefensiveScheme = teamCoaches.first(where: { $0.role == .defensiveCoordinator })?.defensiveScheme
            ?? teamCoaches.first(where: { $0.role == .headCoach })?.defensiveScheme

        // #102 — LAST, because it needs the finished market: the prune half
        // decides what is still collectable by asking who is still on it.
        reconcileReservations()
    }

    /// FA Drama: generate storyline events (revenge tour, hometown, coach reunion,
    /// mentor pair, community impact, milestone) for a successful FA signing.
    private func generateStorylinesForSigning(player: Player, team: Team) {
        let teamID = team.id
        let coachDesc = FetchDescriptor<Coach>(predicate: #Predicate { $0.teamID == teamID })
        let teamCoaches = (try? modelContext.fetch(coachDesc)) ?? []

        var teamAbbrevs: [UUID: String] = [:]
        for t in allTeams { teamAbbrevs[t.id] = t.abbreviation }

        // Free agents currently on the market — used for mentor-protégé matching.
        let unsignedFAs = allPlayers.filter { $0.teamID == nil && !$0.isRetired }

        FreeAgencyEngine.generateStorylineEventsForSigning(
            player: player,
            signingTeam: team,
            teamCoaches: teamCoaches,
            teamRegion: nil, // Team region not yet tracked; hometown match disabled here.
            teamAbbrevs: teamAbbrevs,
            allFAs: unsignedFAs,
            modelContext: modelContext
        )
    }

    // MARK: - FA Drama Phase 2 — Live Ticker

    private struct TickerItem: Identifiable {
        let id = UUID()
        let icon: String
        let tint: Color
        let text: String
    }

    @ViewBuilder
    private var liveTicker: some View {
        let recentEvents = computeTickerEvents()
        if !recentEvents.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DSSpacing.md) {
                    ForEach(recentEvents) { item in
                        // The two voices, not a third: `.caption2` / `.caption`
                        // resolve to whatever the system decides, which is how a
                        // strip pinned directly above an 11 pt tracked column
                        // header ended up a size and a face away from it.
                        HStack(spacing: 6) {  // ds-lint:allow(spacing) icon-to-text gap
                            Image(systemName: item.icon)
                                .font(DSType.text(DSType.Size.caption))
                                .foregroundStyle(item.tint)
                            Text(item.text)
                                .font(DSType.text(DSType.Size.footnote, .medium, prose: true))
                                .foregroundStyle(Color.textSecondary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, DSSpacing.sm)
                        .padding(.vertical, DSSpacing.xs)
                        .background(
                            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                                .fill(Color.backgroundTertiary)
                        )
                    }
                }
                .padding(.horizontal, DSSpacing.md)
            }
            // The strip holds more than fits, and the viewport cut the last
            // chip flat mid-word — which reads as a rendering fault rather than
            // as "there is more this way". The fade is on the SCROLL only, so
            // the bar's own background and rule below it stay solid.
            .mask(
                HStack(spacing: 0) {
                    Color.white
                    LinearGradient(colors: [.white, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 20)
                }
            )
            .padding(.vertical, DSSpacing.xs)
            .background(Color.backgroundSecondary)
            .overlay(
                Rectangle()
                    .fill(Color.surfaceBorder.opacity(0.3))
                    .frame(height: 1),
                alignment: .bottom
            )
        }
    }

    private func computeTickerEvents() -> [TickerItem] {
        var items: [TickerItem] = []

        // 1. Counter offers / outbid bids (newest first, max 4)
        let counters = allBids
            .filter { $0.status == .countered || $0.status == .outbid }
            .sorted { $0.submittedAt > $1.submittedAt }
            .prefix(4)
        for bid in counters {
            let teamAbbr = allTeams.first(where: { $0.id == bid.teamID })?.abbreviation ?? "???"
            let playerName = freeAgents.first(where: { $0.player.id == bid.playerID })?.player.fullName
                ?? allPlayers.first(where: { $0.id == bid.playerID })?.fullName
                ?? "Unknown"
            let aav = bid.baseSalary + (bid.years > 0 ? bid.signingBonus / max(bid.years, 1) : bid.signingBonus)
            let aavM = max(aav / 1000, 1)
            let icon = bid.status == .outbid ? "arrow.up.circle.fill" : "arrow.up.right"
            // `danger`, not the draft's `draftReachRed`: this is a free-agency
            // surface and the app has a semantic red for "this went against us".
            let tint: Color = bid.status == .outbid ? .danger : .warning
            items.append(TickerItem(
                icon: icon,
                tint: tint,
                text: "\(teamAbbr) countered \(playerName) at $\(aavM)M/yr"
            ))
        }

        // 2. Active visits (latest 3)
        let activeVisits = allVisits
            .filter { $0.status == .active }
            .sorted { $0.startedAt > $1.startedAt }
            .prefix(3)
        for visit in activeVisits {
            let teamAbbr = allTeams.first(where: { $0.id == visit.teamID })?.abbreviation ?? "???"
            let playerName = freeAgents.first(where: { $0.player.id == visit.playerID })?.player.fullName
                ?? allPlayers.first(where: { $0.id == visit.playerID })?.fullName
                ?? "Unknown"
            items.append(TickerItem(
                icon: "airplane",
                tint: .accentBlue,
                text: "\(playerName) visiting \(teamAbbr)"
            ))
        }

        // 3. Burning-heat players (max 2)
        var heatPairs: [(FreeAgencyEngine.FreeAgent, FrenzyHeatTier)] = []
        for fa in freeAgents {
            let tier = BiddingHeatEngine.computeHeat(
                playerID: fa.player.id,
                currentDay: career.freeAgencyRound,
                bids: allBids,
                visits: allVisits
            )
            if tier == .burning || tier == .red {
                heatPairs.append((fa, tier))
                if heatPairs.count >= 2 { break }
            }
        }
        for (fa, tier) in heatPairs {
            // No `tier.emoji`: the chip has an SF Symbol flame on its leading
            // edge already, and §2.12 bans dingbats outright — this is the same
            // emoji-plus-word lockup #177 took off the row, left behind in the
            // ticker. And no `draftStealGold`: the burning tier is the top of a
            // heat ladder, not the screen's commit (P5).
            let tint: Color = tier == .burning ? .danger : .alertOrange
            let label: String = tier == .burning ? "FIRE" : "HOT"
            items.append(TickerItem(
                icon: "flame.fill",
                tint: tint,
                text: "\(fa.player.fullName) \(label)"
            ))
        }

        // 4. Day 1 has no bids, no visits and no heat, so items 1-3 are empty on
        // the first and most consequential market day of every season. The stub
        // that used to fill that gap was five fixed sentences, and one of them
        // ("bidding wars expected on premier QBs") contradicted any board whose
        // top names are safeties. These read the board instead, which exists
        // before a single bid is cast.
        if items.isEmpty {
            // Neutral, not gold. A board count is a fact, and P5 spends this
            // screen's gold on the band's current slat and the commit.
            items.append(TickerItem(
                icon: "newspaper",
                tint: .textSecondary,
                text: "\(freeAgents.count) free agent\(freeAgents.count == 1 ? "" : "s") on the wire"
            ))

            var named: Set<UUID> = []
            let byInterest = freeAgents.sorted { $0.marketInterest > $1.marketInterest }
            for fa in byInterest.prefix(2) where fa.marketInterest >= 2 {
                named.insert(fa.player.id)
                items.append(TickerItem(
                    icon: "flame.fill",
                    tint: fa.marketInterest >= 7 ? .danger : .warning,
                    text: "\(fa.player.fullName) (\(fa.player.position.rawValue), \(fa.player.overall)) "
                        + "draws \(fa.marketInterest) clubs \u{2014} \(formatMillions(fa.askingPrice)) ask"
                ))
            }

            if let priciest = freeAgents.max(by: { $0.askingPrice < $1.askingPrice }),
               !named.contains(priciest.player.id) {
                items.append(TickerItem(
                    icon: "dollarsign.circle.fill",
                    tint: .accentBlue,
                    text: "Biggest ask on the board: \(priciest.player.fullName) at "
                        + "\(formatMillions(priciest.askingPrice))/yr over \(priciest.desiredYears) yrs"
                ))
            }

            if let team, allTeams.count > 1 {
                let rivals = allTeams.filter { $0.id != team.id }
                let poorer = rivals.filter { $0.availableCap < team.availableCap }.count
                items.append(TickerItem(
                    icon: "chart.bar.fill",
                    tint: .accentBlue,
                    text: "\(team.abbreviation) opens with \(formatMillions(team.availableCap)) \u{2014} "
                        + "more room than \(poorer) of \(rivals.count) clubs"
                ))
            }
        }

        return Array(items.prefix(8))
    }

    // MARK: - FA Drama Phase 2 — Heat
    //
    // `heatBadge` and `heatColor` are gone with #177: the emoji-plus-word chip
    // they drew (a dingbat, which §2.12 bans outright, at `caption2`) is now
    // the row's `HEAT` slot, and the slot takes its colour from the status
    // ladder through `heatTone` instead of from a fourth bespoke palette that
    // reached into `draftStealGold` for a free-agency reading. Only the word
    // survives, because the ticker prints it too.

    private func heatLabel(_ tier: FrenzyHeatTier) -> String {
        switch tier {
        case .cool:    return "COOL"
        case .yellow:  return "WARM"
        case .red:     return "HOT"
        case .burning: return "FIRE"
        }
    }

    // MARK: - FA Drama Phase 2 — Outbid Alert Banner

    /// The one thing on this screen that interrupts: a rival has taken a man
    /// the club has money on, and there is a clock on the answer.
    ///
    /// It shipped in a **third** voice — `.caption` / `.subheadline`, i.e.
    /// whatever the system resolves — wearing the DRAFT's palette
    /// (`draftReachRed`, `draftClockUrgent`) on a free-agency surface. Both are
    /// now the app's: the two DSType voices, and `danger` for the alarm with
    /// `alertOrange` for the countdown, which is the same warn hue the rest of
    /// this screen uses. Nothing about the banner's urgency depended on
    /// borrowing another screen's colours.
    ///
    /// The dismiss target is 44 pt, measured — it was a bare 17 pt glyph on the
    /// one control that makes an interrupting banner go away.
    @ViewBuilder
    private var outbidBanner: some View {
        if let evt = visibleOutbidEvent {
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                HStack(spacing: DSSpacing.xxs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(DSType.text(DSType.Size.caption, .semibold))
                        .foregroundStyle(Color.danger)
                    Text("OUTBID")
                        .font(DSType.display(DSType.Size.caption, .heavy))
                        .tracking(1)
                        .foregroundStyle(Color.dangerText)
                    Spacer(minLength: DSSpacing.xs)
                    Text(timeRemaining(until: evt.respondByDeadline))
                        .font(DSType.display(DSType.Size.footnote, .bold).monospacedDigit())
                        .foregroundStyle(Color.alertOrange)
                    Button {
                        visibleOutbidEvent = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(DSType.text(DSType.Size.callout))
                            .foregroundStyle(Color.textTertiary)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss the outbid alert")
                }
                Text("\(evt.outbidByTeamAbbrev) bumped \(evt.playerName) to $\(evt.competingOfferAnnualValue / 1000)M/yr")
                    .font(DSType.text(DSType.Size.callout, .semibold, prose: true))
                    .foregroundStyle(Color.textPrimary)
                Text("Match by deadline or lose the player.")
                    .font(DSType.text(DSType.Size.footnote, .regular, prose: true))
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(DSSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DSCornerRadius.card)
                    .fill(Color.backgroundSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: DSCornerRadius.card)
                            .strokeBorder(Color.danger, lineWidth: 2)
                    )
            )
            .padding(.horizontal, DSSpacing.md)
            .padding(.top, DSSpacing.xs)
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Outbid by \(evt.outbidByTeamAbbrev) on \(evt.playerName)")
        }
    }

    private func timeRemaining(until: Date) -> String {
        let interval = until.timeIntervalSinceNow
        if interval <= 0 { return "EXPIRED" }
        let h = Int(interval) / 3600
        let m = (Int(interval) % 3600) / 60
        return String(format: "%dh %02dm", h, m)
    }

    private func refreshOutbidEvents() {
        guard let teamID = career.teamID else {
            visibleOutbidEvent = nil
            return
        }
        // Build name + abbreviation lookups
        var playerNames: [UUID: String] = [:]
        for fa in freeAgents { playerNames[fa.player.id] = fa.player.fullName }
        for p in allPlayers where playerNames[p.id] == nil { playerNames[p.id] = p.fullName }

        var teamAbbrevs: [UUID: String] = [:]
        for t in allTeams { teamAbbrevs[t.id] = t.abbreviation }

        let events = OutbidNotifier.detect(
            userTeamID: teamID,
            bids: allBids,
            playerNames: playerNames,
            teamAbbrevs: teamAbbrevs
        )
        visibleOutbidEvent = events.first
    }

    // MARK: - FA Drama Phase 2 — Day Phase Header (REMOVED, wave 3)
    //
    // The morning / afternoon / evening strip and its gold "Next" button are
    // gone. Two reasons, both hard:
    //
    //   * It was a **second progress metaphor** on a screen that now has a
    //     `DSSlatBand` (P1: only ordered things get a band, and they get ONE).
    //   * Its "Next" was the **second gold control** on the screen (P5 allows
    //     one) and it did nothing: `advancePhase` cycled a local `@State
    //     FABidPhase` that no engine, no bid, no heat computation and no query
    //     ever read. A prominent button that changes only its own highlight is
    //     worse than no button.
    //
    // The market day it half-implied is now the band's meter and the current
    // slat's sub-caption, which are read from `career.freeAgencyRound` and
    // therefore cannot drift from the simulation.
}

// MARK: - FreeAgent Identifiable conformance

// No `@retroactive`: `FreeAgent` is declared in this module, so the attribute
// does not apply — a warning in Swift 5 mode and an error in Swift 6 mode. The
// conformance itself stays here because it exists for this screen's `ForEach`.
extension FreeAgencyEngine.FreeAgent: Identifiable {
    var id: UUID { player.id }
}

// MARK: - Round Results

struct RoundResults {
    let yourSignings: [(playerName: String, position: String, salary: Int, years: Int)]
    let yourRejections: [(playerName: String, position: String, reason: String, chosenTeam: String?, salary: Int?)]
    let aiSignings: [(playerName: String, position: String, team: String, salary: Int)]
    let headlines: [String]
    let playersRemaining: Int
    let capRemaining: Int
    var biddingWars: [FreeAgencyEngine.BiddingWarInfo] = []
    var shoppingAround: [(playerName: String, position: String)] = []
    var biddingUpdates: [FreeAgencyEngine.BiddingUpdate] = []
}
