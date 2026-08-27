import SwiftUI
import SwiftData

// MARK: - Intro Sequence View

/// Multi-step immersive introduction shown once when a new career starts.
/// Walks the player through a press conference, owner meeting, team overview,
/// and a final call-to-action before entering the front office.
struct IntroSequenceView: View {

    @Bindable var career: Career
    @Environment(\.modelContext) private var modelContext

    @State private var currentStep = 0
    @State private var navigateToDashboard = false
    @State private var pressConferenceComplete = false

    // Loaded data
    @State private var team: Team?
    @State private var owner: Owner?
    @State private var players: [Player] = []
    @State private var coaches: [Coach] = []
    @State private var draftPicks: [DraftPick] = []
    @State private var seasonGoals: SeasonGoals?
    /// The owner's mandate in the form the SEASON is actually scored in.
    ///
    /// `SeasonGoals.generate` (above) is two prose lines — "Win the division",
    /// "Build depth through the draft" — with no target on either and no
    /// evaluation behind them anywhere in the app. The slate the season books
    /// its verdict against is `OwnerGoalsEngine`'s: counted goals with real
    /// bars (12+ wins, three rookies at a starts bar) that the Owner Relations
    /// screen tracks all year and the end-of-season review grades. The intro
    /// was therefore the one screen where the owner asked for something he
    /// would never measure.
    ///
    /// Generated here off the same engine and the same club, so the meeting
    /// states the real bar. Display only — `WeekAdvancer.startNewSeason` builds
    /// and persists the season's own slate at kickoff (after the draft and free
    /// agency have moved the roster), and this screen must not pre-empt it.
    @State private var ownerGoals: [SeasonGoal] = []
    /// Where the engine reads this franchise in its competitive cycle. Quoted,
    /// never re-derived: `TradeValueEngine.TeamStance` is what every trade and
    /// free-agency decision in the game is already priced against, so the
    /// briefing's verdict and the market's behaviour cannot disagree.
    @State private var teamStance: TradeValueEngine.TeamStance?

    private let totalSteps = 5

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            if team != nil {
                TabView(selection: $currentStep) {
                    PressConferenceView(
                        career: career,
                        team: team!,
                        owner: owner,
                        // #161: the inherited roster is what the engine reads
                        // the locker-room band and the rebuild/contender
                        // standing off — a championship promise is priced
                        // against the players who would have to deliver it.
                        roster: players,
                        onComplete: { result in
                            applyPressConferenceResult(result)
                            advanceStep()
                        }
                    )
                    .tag(0)

                    OwnerMeetingStep(
                        career: career,
                        owner: owner,
                        team: team!,
                        seasonGoals: seasonGoals,
                        ownerGoals: ownerGoals,
                        onContinue: { advanceStep() }
                    )
                    .tag(1)

                    TeamOverviewStep(
                        career: career,
                        team: team!,
                        players: players,
                        coaches: coaches,
                        draftPicks: draftPicks,
                        stance: teamStance,
                        onContinue: { advanceStep() }
                    )
                    .tag(2)

                    YourRoadmapStep(
                        onContinue: { advanceStep() }
                    )
                    .tag(3)

                    ReadyToBeginStep(
                        career: career,
                        team: team,
                        // The closing line is graded on `RosterStrength`, the
                        // one sanctioned definition. The whole-roster mean this
                        // used to take reads eight points low on a camp roster,
                        // so an 80-OVR contender was being told to write its
                        // legacy while the hub called it a contender.
                        teamOverall: RosterStrength.starterAverage(players) ?? 60,
                        // The three counts the closing screen states, and the
                        // owner's own headline goal. All four are already loaded
                        // for the earlier steps — the last screen used to end the
                        // briefing without repeating a single number from it.
                        seasonGoals: seasonGoals,
                        rosterCount: players.count,
                        openStaffSeats: openStaffSeats,
                        draftPickCount: draftPicks.count,
                        onEnter: { completeIntro() }
                    )
                    .tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.4), value: currentStep)
                // HOW MUCH BRIEFING IS LEFT. Three screens in a row end in a
                // bare "Continue" with nothing on them saying the intro is
                // finite, so it reads as an unbounded corridor. A counter
                // rather than the page dots this style turns off, because a
                // count states the length and a row of dots only implies it.
                // It starts after the press conference, which prints its own
                // "QUESTION n OF 5" rail across this exact strip.
                .overlay(alignment: .topTrailing) {
                    if currentStep > 0 {
                        Text("STEP \(currentStep + 1) OF \(totalSteps)")
                            .font(.system(size: DSType.Size.caption, weight: .heavy))
                            .tracking(1.0)
                            .foregroundStyle(Color.textTertiary)
                            .padding(.horizontal, DSSpacing.md)
                            .padding(.top, DSSpacing.sm)
                            .accessibilityLabel("Step \(currentStep + 1) of \(totalSteps)")
                    }
                }
            } else {
                ProgressView()
                    .tint(Color.accentGold)
            }
        }
        .navigationBarBackButtonHidden(true)
        .fullScreenCover(isPresented: $navigateToDashboard) {
            CareerShellView(career: career)
        }
        .task { loadData() }
    }

    // MARK: - Actions

    /// Coaching seats still to fill. `StaffSlots` is the one authority on the
    /// denominator, so a GM+HC career is never told to fill the chair he is
    /// sitting in.
    private var openStaffSeats: Int {
        StaffSlots.coachRoles(for: career.role).count
            - StaffSlots.filledCoachSlots(coaches: coaches, careerRole: career.role)
    }

    private func advanceStep() {
        withAnimation(.easeInOut(duration: 0.4)) {
            if currentStep < totalSteps - 1 {
                currentStep += 1
            }
        }
    }

    private func applyPressConferenceResult(_ result: PressConferenceResult) {
        // #161: tone ledger + promise ledger, in the engine, so both press
        // screens book the same things.
        PressConferenceEngine.commit(result: result, to: career)

        // Apply effects to career legacy
        career.legacy.applyPressConferenceResult(result, season: career.currentSeason)

        // Apply owner satisfaction
        if let ownerObj = owner {
            ownerObj.satisfaction = max(0, min(100, ownerObj.satisfaction + result.totalEffects.ownerSatisfaction))
        }

        // F-56 — the podium is the first thing the league actually HEARS, so a
        // dominant tone that says something about how this man does business
        // overrules the identity his coaching style seeded at team selection.
        // Tones with no market read (confident, funny) leave the seed alone:
        // every new GM sounds confident at his own introduction, and that is not
        // information. See `FranchiseIdentityDeclaration`.
        if let teamID = career.teamID {
            FranchiseIdentityDeclaration.amend(
                tone: result.dominantTone, teamID: teamID
            )

            // Same two writes the weekly podium makes (`CareerShellView`), so
            // the introduction cannot book a different set than every session
            // after it: the team-wide morale read onto the roster, the fan read
            // onto `Career.fanSupport`.
            let descriptor = FetchDescriptor<Player>(
                predicate: #Predicate<Player> { $0.teamID == teamID }
            )
            let roster = (try? modelContext.fetch(descriptor)) ?? []
            PressConferenceEngine.applyRoomEffects(
                result: result,
                career: career,
                roster: roster
            )
        }

        pressConferenceComplete = true
        try? modelContext.save()
    }

    private func completeIntro() {
        career.hasCompletedIntro = true
        career.currentPhase = .coachingChanges
        career.currentWeek = 0
        if let goals = seasonGoals {
            career.seasonGoals = goals
        }
        try? modelContext.save()
        navigateToDashboard = true
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let teamID = career.teamID else { return }

        let teamDescriptor = FetchDescriptor<Team>(predicate: #Predicate { $0.id == teamID })
        team = try? modelContext.fetch(teamDescriptor).first
        owner = team?.owner

        let playerDescriptor = FetchDescriptor<Player>(predicate: #Predicate { $0.teamID == teamID })
        players = (try? modelContext.fetch(playerDescriptor)) ?? []

        let coachDescriptor = FetchDescriptor<Coach>(predicate: #Predicate { $0.teamID == teamID })
        coaches = (try? modelContext.fetch(coachDescriptor)) ?? []

        let season = career.currentSeason
        let pickDescriptor = FetchDescriptor<DraftPick>(predicate: #Predicate {
            $0.currentTeamID == teamID && $0.seasonYear == season && $0.isComplete == false
        })
        draftPicks = (try? modelContext.fetch(pickDescriptor)) ?? []

        // Generate season goals from roster quality and owner preference
        let avgOverall = players.isEmpty ? 60 : players.map(\.overall).reduce(0, +) / players.count
        let ownerPrefersWinNow = owner?.prefersWinNow ?? false
        seasonGoals = SeasonGoals.generate(teamQuality: avgOverall, ownerPreference: ownerPrefersWinNow)

        // The same mandate the season is scored against — see `ownerGoals`. One
        // league-wide fetch inside `rosterTier`, on a screen that already runs
        // five, and only ever once per career.
        if let team, let owner {
            ownerGoals = OwnerGoalsEngine.generateSeasonGoals(
                team: team, owner: owner, career: career
            )
        }

        // The contend / retool / rebuild verdict, read off the same model the
        // trade market uses. The league-wide fetch is what buys
        // `leagueCoreReference` its self-centring reference — the engine's own
        // note is explicit that a hardcoded 80.0 reads 20 contenders out of 31
        // on one calibration and none on the next. One fetch, once, on a screen
        // that already runs four.
        if let team {
            let careerID = career.id
            let leagueDescriptor = FetchDescriptor<Player>(
                predicate: #Predicate<Player> { $0.careerID == careerID }
            )
            let leaguePlayers = (try? modelContext.fetch(leagueDescriptor)) ?? []
            teamStance = TradeValueEngine.stance(
                for: team,
                roster: players,
                coreReference: leaguePlayers.isEmpty
                    ? 80.0
                    : TradeValueEngine.leagueCoreReference(allPlayers: leaguePlayers)
            )
        }
    }
}

// MARK: - Step 2: Owner Meeting
//
// #105 Wave 5a. This step used to be the app's SECOND owner screen: §3 row 12b
// names it against `News/OwnerMeetingView`, and §5's target is "one owner
// screen". It is now the intro's *staging* of the shared briefing — the scene,
// the reveal choreography and the Continue — and draws nothing about the owner
// itself. Every card below comes from `OwnerBriefing`, the same file the hub
// screen reads, so the two can no longer disagree about the same man.
//
// The explainers this screen used to own (#15's implication lines, #16's
// personal quote, #129's consequences line) moved INTO the shared briefing
// rather than being deleted — they were the better half of the pair, and the
// hub screen never had them.

private struct OwnerMeetingStep: View {

    let career: Career
    let owner: Owner?
    let team: Team
    let seasonGoals: SeasonGoals?
    /// The owner's tracked slate. Preferred over `seasonGoals` whenever the
    /// engine produced one — see `IntroSequenceView.ownerGoals`.
    let ownerGoals: [SeasonGoal]
    let onContinue: () -> Void

    @State private var showHeader = false
    @State private var showTraits = false
    @State private var showGoals = false
    @State private var showQuote = false

    /// The goals card's rows.
    ///
    /// The tracked slate first, mapped exactly the way the Owner Relations hub
    /// maps it (`OwnerMeetingView.briefingGoals`) so the two screens print the
    /// same four rows with the same priority tags and the same targets. The
    /// two-string `SeasonGoals` is the fallback for a save whose league is not
    /// stocked yet — `generateSeasonGoals` needs a club to rank against.
    private var goalRows: [OwnerBriefingGoal] {
        if !ownerGoals.isEmpty {
            return ownerGoals.prefix(4).map { goal in
                OwnerBriefingGoal(
                    id: goal.id.uuidString,
                    title: goal.title,
                    priorityLabel: goal.priority == .primary
                        ? "Primary"
                        : (goal.priority == .secondary ? "Secondary" : "Bonus"),
                    isPrimary: goal.priority == .primary,
                    // No progress fraction, deliberately. The target is already
                    // IN the engine's title — "Win 12+ Games", "Develop 3
                    // Rookies" — which is the half the intro's two prose lines
                    // never had. A `progress` pair on top of it would only say
                    // "0/12" for a season nobody has played, and it would flip
                    // `OwnerGoalsCard.hasReading` on and head the first owner
                    // meeting of a career "0/4 met": the exact zero score that
                    // card's `hasReading` exists to suppress.
                    isAchieved: goal.isAchieved
                )
            }
        }
        if let seasonGoals { return briefingGoals(seasonGoals) }
        return []
    }

    /// The legacy two-string goals in the briefing's vocabulary.
    private func briefingGoals(_ goals: SeasonGoals) -> [OwnerBriefingGoal] {
        [
            OwnerBriefingGoal(
                id: "primary",
                title: goals.primaryGoal,
                priorityLabel: "Primary",
                isPrimary: true
            ),
            OwnerBriefingGoal(
                id: "secondary",
                title: goals.secondaryGoal,
                priorityLabel: "Secondary",
                isPrimary: false
            )
        ]
    }

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()
            GeometryReader { geo in
                Image("BgContract")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .opacity(0.2)
            }
            .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.backgroundPrimary.opacity(0.7),
                    Color.backgroundPrimary.opacity(0.4),
                    Color.backgroundPrimary.opacity(0.7)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                GeometryReader { geometry in
                    ScrollView {
                        VStack(spacing: DSSpacing.md) {
                            Spacer().frame(height: DSSpacing.xs)

                            if showHeader, let owner {
                                OwnerBriefingHeader(
                                    career: career,
                                    owner: owner,
                                    teamName: team.fullName,
                                    isHero: true
                                )
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }

                            if showTraits, let owner {
                                OwnerPrioritiesCard(owner: owner)
                                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                                OwnerPatienceCard(owner: owner, career: career)
                                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                                OwnerBudgetCard(owner: owner)
                                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                            }

                            if showGoals {
                                let rows = goalRows
                                if !rows.isEmpty {
                                    OwnerGoalsCard(goals: rows)
                                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                                }
                            }

                            if showQuote, let owner {
                                OwnerQuoteCard(owner: owner)
                                    .transition(.opacity)
                            }

                            Spacer().frame(height: DSSpacing.lg)
                        }
                        .padding(.horizontal, DSSpacing.lg)
                        .frame(maxWidth: DSLayout.contentMeasure)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: geometry.size.height)
                    }
                    .scrollIndicators(.hidden)
                }

                // §2.5: the one commit surface, and now every intro step that
                // has a Continue uses it. The floating gold capsule the two
                // later steps used moved the button the player had just tapped
                // from bottom-right to bottom-centre between consecutive
                // screens, and it could carry no explainer.
                DSActionBar(
                    explainer: .init(
                        title: "Owner meeting",
                        message: "This is the bar you are measured against. **It does not change** because you disagree with it."
                    ),
                    primary: .init(title: "Continue", handler: onContinue)
                )
            }
        }
        .onAppear { runAnimations() }
    }

    private func runAnimations() {
        withAnimation(.easeOut(duration: 0.5).delay(0.2)) { showHeader = true }
        withAnimation(.easeOut(duration: 0.5).delay(0.9)) { showTraits = true }
        withAnimation(.easeOut(duration: 0.5).delay(1.6)) { showGoals = true }
        withAnimation(.easeOut(duration: 0.5).delay(2.3)) { showQuote = true }
    }
}

// MARK: - Step 3: Team Overview

private struct TeamOverviewStep: View {

    let career: Career
    let team: Team
    let players: [Player]
    let coaches: [Coach]
    let draftPicks: [DraftPick]
    /// `TradeValueEngine`'s read of this franchise's competitive cycle.
    let stance: TradeValueEngine.TeamStance?
    let onContinue: () -> Void

    @State private var showHeader = false
    @State private var showRoster = false
    @State private var showPositionGrades = false
    @State private var showCap = false
    @State private var showDraft = false
    /// Expiring-contract drill-down: the count row opens the names underneath
    /// it rather than being a dead figure.
    @State private var showExpiringList = false
    /// Key-player row tapped — opens the same `PlayerDetailView` the cap screen
    /// presents in a sheet.
    @State private var inspectedPlayer: Player?

    private var averageOverall: Int {
        guard !players.isEmpty else { return 0 }
        return players.map(\.overall).reduce(0, +) / players.count
    }

    private var bestPlayer: Player? {
        players.max(by: { $0.overall < $1.overall })
    }

    /// The roster's three landmarks, each carrying the tag that says why it is
    /// on the list.
    ///
    /// This was "top 3 by overall", which put three unexplained names on the
    /// briefing and answered none of the three questions a GM opens a roster
    /// with: who plays quarterback, what the biggest contract is, and who is
    /// about to walk. One man can hold two of the three — a franchise QB in a
    /// contract year is exactly the case worth flagging — so the tags collect on
    /// the player rather than forcing three distinct rows.
    private struct KeyPlayer: Identifiable {
        let player: Player
        let tags: [String]
        var id: UUID { player.id }
    }

    private var keyPlayers: [KeyPlayer] {
        var tagsByPlayer: [UUID: [String]] = [:]
        var order: [Player] = []

        func mark(_ candidate: Player?, _ tag: String) {
            guard let candidate else { return }
            if tagsByPlayer[candidate.id] == nil { order.append(candidate) }
            tagsByPlayer[candidate.id, default: []].append(tag)
        }

        mark(players.filter { $0.position == .QB }.max { $0.overall < $1.overall }, "QB1")
        mark(players.max { $0.annualSalary < $1.annualSalary }, "TOP CAP")
        mark(expiringPlayers.first, "EXPIRING")

        return order.map { KeyPlayer(player: $0, tags: tagsByPlayer[$0.id] ?? []) }
    }

    /// Everyone in the last year of his deal, best first — the names behind the
    /// "Expiring Contracts" count.
    private var expiringPlayers: [Player] {
        players
            .filter { $0.contractYearsRemaining <= 1 }
            .sorted { $0.overall > $1.overall }
    }

    /// Position group with the lowest starter-average overall, including grade and OVR.
    /// Uses `PositionGradeCalculator` so it stays consistent with the
    /// "Position Group Strengths" card (both rely on the top-N starter average).
    private var weakestPositionGroup: String {
        guard !players.isEmpty else { return "N/A" }
        let groupGrades: [(name: String, grade: String, ovr: Int)] = Self.groupPositions.compactMap { group in
            let groupPlayers = players.filter { group.positions.contains($0.position) }
            guard !groupPlayers.isEmpty else { return nil }
            let g = PositionGradeCalculator.calculatePositionGrades(players: groupPlayers, positions: group.positions)
            return (group.name, g.starterGrade, g.starterOVR)
        }
        guard let weakest = groupGrades.min(by: { $0.ovr < $1.ovr }) else { return "N/A" }
        return "\(weakest.name) (\(weakest.grade), \(weakest.ovr) OVR)"
    }

    private var filledCoachingSlots: Int {
        StaffSlots.filledCoachSlots(coaches: coaches, careerRole: career.role)
    }

    // MARK: - #20 Roster Age & Contract Summary

    private var averageAge: Double {
        guard !players.isEmpty else { return 0 }
        return Double(players.map(\.age).reduce(0, +)) / Double(players.count)
    }

    private var expiringContracts: Int {
        expiringPlayers.count
    }

    // MARK: - #18 Position Group Grades

    private struct PositionGroupGrade: Identifiable {
        let id = UUID()
        let name: String
        let starterGrade: String
        let depthGrade: String
        let starterAverage: Int
        let depthAverage: Int
        let color: Color
        let playerCount: Int
        let need: String // e.g. "need starter", "need depth", "" if fine
    }

    /// Maps positions to position group names for grading.
    private static func positionGroupName(for position: Position) -> String {
        switch position {
        case .QB: return "QB"
        case .RB, .FB: return "RB"
        case .WR: return "WR"
        case .TE: return "TE"
        case .LT, .LG, .C, .RG, .RT: return "OL"
        case .DE, .DT: return "DL"
        case .OLB, .MLB: return "LB"
        case .CB, .FS, .SS: return "DB"
        case .K, .P: return "ST"
        }
    }

    /// Ideal minimum roster counts per position group.
    private static let idealGroupSize: [String: Int] = [
        "QB": 3, "RB": 4, "WR": 6, "TE": 3, "OL": 9,
        "DL": 6, "LB": 6, "DB": 8, "ST": 2
    ]

    private static func needLabel(groupName: String, count: Int, avg: Int) -> String {
        let ideal = idealGroupSize[groupName] ?? 4
        if count < ideal && avg < 70 {
            return "Need starter"
        } else if count < ideal {
            return "Need depth"
        } else if avg < 65 {
            return "Need upgrade"
        }
        return ""
    }

    /// Position groups with their positions for grade calculation.
    private static let groupPositions: [(name: String, positions: [Position])] = [
        ("QB", [.QB]),
        ("RB", [.RB, .FB]),
        ("WR", [.WR]),
        ("TE", [.TE]),
        ("OL", [.LT, .LG, .C, .RG, .RT]),
        ("DL", [.DE, .DT]),
        ("LB", [.OLB, .MLB]),
        ("DB", [.CB, .FS, .SS]),
        ("ST", [.K, .P]),
    ]

    private var positionGroupGrades: [PositionGroupGrade] {
        guard !players.isEmpty else { return [] }
        return Self.groupPositions.compactMap { group in
            let groupPlayers = players.filter { group.positions.contains($0.position) }
            guard !groupPlayers.isEmpty else { return nil }
            let grades = PositionGradeCalculator.calculatePositionGrades(players: groupPlayers, positions: group.positions)
            let count = groupPlayers.count
            return PositionGroupGrade(
                name: group.name,
                starterGrade: grades.starterGrade,
                depthGrade: grades.depthGrade,
                starterAverage: grades.starterOVR,
                depthAverage: grades.depthOVR,
                color: PositionGradeCalculator.gradeColor(for: grades.starterOVR),
                playerCount: count,
                need: Self.needLabel(groupName: group.name, count: count, avg: grades.starterOVR)
            )
        }
    }

    // MARK: - #19 League Average Context

    /// Approximate league averages for context display.
    private static let leagueAverages: [(label: String, keyPath: String, leagueAvg: Int)] = [
        ("Team Overall", "overall", 72),
        ("Average Age", "age", 26),
        ("Roster Size", "rosterSize", 53),
    ]

    /// Total coaching staff positions expected (HC + OC + DC + STC + position coaches).
    /// #133: the same seat list the staff screen and the dashboard tile count.
    /// This used to be raw `CoachRole.allCases`, so a GM+HC career was told
    /// "0 / 16 filled" for a staff that tops out at 15 — the head-coach chair in
    /// the denominator is the one he is sitting in.
    private var totalCoachingSlots: Int { StaffSlots.coachRoles(for: career.role).count }

    private var capAvailableFormatted: String {
        let available = team.availableCap
        if available >= 1_000 {
            return String(format: "$%.1fM", Double(available) / 1_000.0)
        }
        return "$\(available)K"
    }

    private var capUsedFormatted: String {
        let used = team.currentCapUsage
        if used >= 1_000 {
            return String(format: "$%.1fM", Double(used) / 1_000.0)
        }
        return "$\(used)K"
    }

    private var totalCapFormatted: String {
        let total = team.salaryCap
        if total >= 1_000 {
            return String(format: "$%.1fM", Double(total) / 1_000.0)
        }
        return "$\(total)K"
    }

    private var deadCapFormatted: String {
        let dead = team.deadCapCurrentYear
        if dead >= 1_000 {
            return String(format: "$%.1fM", Double(dead) / 1_000.0)
        }
        return "$\(dead)K"
    }

    private var capUsedFraction: Double {
        team.salaryCap > 0 ? Double(team.currentCapUsage) / Double(team.salaryCap) : 0
    }

    /// The cap ladder the app already publishes to the player — `RosterEvaluationView`'s
    /// own legend: under 80 % healthy, 80–90 moderate, 90–95 tight, over 95
    /// critical. Quoted rather than re-invented, so the briefing's verdict and
    /// the roster screen's key cannot drift apart.
    private var capHealth: (label: String, color: Color) {
        switch capUsedFraction {
        case ..<0.80: return ("Healthy", .success)
        case ..<0.90: return ("Moderate", .warning)
        case ..<0.95: return ("Tight", .alertOrange)
        default:      return ("Critical", .dangerText)
        }
    }

    /// One line saying what the stance means for the offseason about to start.
    private func stanceRationale(_ stance: TradeValueEngine.TeamStance) -> String {
        switch stance {
        case .contend:
            return "The core is good enough now. Buy proven help and protect the window."
        case .retool:
            return "One good offseason from contending. Trade both ways and stay flexible."
        case .rebuild:
            return "The present is not worth defending. Collect picks and young players."
        }
    }

    private func stanceColor(_ stance: TradeValueEngine.TeamStance) -> Color {
        // Same three-tier ladder team selection uses for its situation chips:
        // gold = competing, green = ascending, blue = building.
        switch stance {
        case .contend: return .accentGold
        case .retool:  return .success
        case .rebuild: return .accentBlue
        }
    }

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()
            GeometryReader { geo in
                Image("BgTrainingCamp")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .opacity(0.2)
            }
            .ignoresSafeArea()
            LinearGradient(
                colors: [Color.backgroundPrimary.opacity(0.7), Color.backgroundPrimary.opacity(0.4), Color.backgroundPrimary.opacity(0.7)],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()

        GeometryReader { geometry in
        ScrollView {
            VStack(spacing: 24) {
                Spacer().frame(height: 20)

                // Header
                if showHeader {
                    VStack(spacing: 12) {
                        Image(systemName: "building.2.fill")
                            .font(.system(size: DSType.Size.display))
                            .foregroundStyle(Color.accentGold)

                        Text("TEAM OVERVIEW")
                            .font(.system(size: DSType.Size.body, weight: .black))
                            .tracking(4)
                            .foregroundStyle(Color.accentGold)

                        Text(team.fullName)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(Color.textPrimary)

                        // THE VERDICT. Everything below this line is a figure;
                        // nothing on the screen used to say what the figures add
                        // up to. `TradeValueEngine.TeamStance` is the same read
                        // the trade market and free agency price against, so the
                        // briefing states the club's actual position rather than
                        // a second opinion about it.
                        if let stance {
                            VStack(spacing: 4) {
                                Text(stance.label.uppercased())
                                    .font(DSType.display(DSType.Size.footnote, .heavy))
                                    .tracking(1.6)
                                    .foregroundStyle(stanceColor(stance))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 5)
                                    .background(
                                        Capsule().fill(stanceColor(stance).opacity(0.15))
                                    )
                                Text(stanceRationale(stance))
                                    .font(.caption)
                                    .foregroundStyle(Color.textSecondary)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.horizontal, 24)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(stance.label). \(stanceRationale(stance))")
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Roster snapshot + #20 age/contract summary + #21 coaching emphasis + #19 league averages
                if showRoster {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionLabel(text: "ROSTER")

                        StatRow(label: "Total Players", value: "\(players.count)")

                        // #19: Overall with league average context
                        ComparisonStatRow(
                            label: "Average Overall",
                            value: averageOverall,
                            leagueAvg: 72,
                            format: { "\($0)" }
                        )

                        // #20: Average roster age
                        HStack {
                            Text("Average Age")
                                .font(.subheadline)
                                .foregroundStyle(Color.textSecondary)
                            Spacer()
                            Text(String(format: "%.1f", averageAge))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.textPrimary)
                            // "(Avg: 26.0)" named no source. The Average Overall
                            // row directly above already spells the comparison
                            // out; this one was left behind on the old wording.
                            Text("vs league avg 26.0")
                                .font(.caption)
                                .foregroundStyle(averageAge > 27.5 ? Color.warning : averageAge < 25.0 ? Color.success : Color.textTertiary)
                        }

                        // #20: Expiring contracts — and who they are. The count
                        // on its own was a dead figure: "17 players" names a
                        // problem the briefing then refuses to identify.
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showExpiringList.toggle()
                            }
                        } label: {
                            HStack {
                                Text("Expiring Contracts")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.textSecondary)
                                Spacer()
                                Text("\(expiringContracts) player\(expiringContracts == 1 ? "" : "s")")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(expiringContracts > 15 ? Color.dangerText : expiringContracts > 8 ? Color.warning : Color.textPrimary)
                                if !expiringPlayers.isEmpty {
                                    Image(systemName: showExpiringList ? "chevron.up" : "chevron.down")
                                        .font(.system(size: DSType.Size.micro, weight: .bold))
                                        .foregroundStyle(Color.textTertiary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(expiringPlayers.isEmpty)
                        .accessibilityLabel("Expiring contracts, \(expiringContracts) players")
                        .accessibilityHint(expiringPlayers.isEmpty ? "" : "Shows who is in the last year of his deal")

                        if showExpiringList, !expiringPlayers.isEmpty {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(expiringPlayers, id: \.id) { player in
                                    HStack(spacing: 6) {
                                        Text(player.position.rawValue)
                                            .font(DSType.display(DSType.Size.micro, .bold))
                                            .foregroundStyle(Color.textTertiary)
                                            .frame(width: 26, alignment: .leading)
                                        Text(player.fullName)
                                            .font(DSType.text(DSType.Size.footnote, .medium))
                                            .foregroundStyle(Color.textSecondary)
                                        Spacer()
                                        Text("\(player.overall)")
                                            .font(DSType.display(DSType.Size.footnote, .bold))
                                            .foregroundStyle(Color.forRating(player.overall))
                                    }
                                }
                            }
                            .padding(.leading, 4)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        // #133: the roster's three landmarks, tagged and tappable.
                        if !keyPlayers.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Key Players")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.textSecondary)
                                ForEach(keyPlayers) { key in
                                    Button {
                                        inspectedPlayer = key.player
                                    } label: {
                                        HStack(spacing: 8) {
                                            Text(key.player.fullName)
                                                .font(.subheadline.weight(.medium))
                                                .foregroundStyle(Color.textPrimary)
                                            ForEach(key.tags, id: \.self) { tag in
                                                Text(tag)
                                                    .font(DSType.display(DSType.Size.micro, .heavy))
                                                    .tracking(0.6)
                                                    .foregroundStyle(Color.accentGold)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(
                                                        Capsule().fill(Color.accentGold.opacity(0.14))
                                                    )
                                            }
                                            Spacer(minLength: 4)
                                            Text("\(key.player.position.rawValue) — \(key.player.overall) OVR")
                                                .font(.subheadline.monospacedDigit())
                                                .foregroundStyle(Color.forRating(key.player.overall))
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: DSType.Size.micro, weight: .bold))
                                                .foregroundStyle(Color.textTertiary)
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("\(key.player.fullName), \(key.tags.joined(separator: ", ")), \(key.player.position.rawValue), \(key.player.overall) overall")
                                }
                            }
                        }

                        StatRow(label: "Weakest Group", value: weakestPositionGroup)

                        Divider().overlay(Color.surfaceBorder)

                        // #21: Coaching Staff vacancy with emphasis
                        HStack(spacing: 12) {
                            Image(systemName: "person.3.fill")
                                .foregroundStyle(filledCoachingSlots < totalCoachingSlots ? Color.warning : Color.success)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Coaching Staff")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.textSecondary)
                                if filledCoachingSlots == 0 {
                                    Text("0 / \(totalCoachingSlots) filled")
                                        .font(.title3.weight(.bold))
                                        .foregroundStyle(Color.dangerText)
                                } else {
                                    Text("\(filledCoachingSlots) / \(totalCoachingSlots) filled")
                                        .font(.title3.weight(.bold))
                                        .foregroundStyle(filledCoachingSlots < totalCoachingSlots ? Color.warning : Color.success)
                                }
                            }
                            Spacer()
                        }
                    }
                    .padding(20)
                    .cardBackground()
                    .padding(.horizontal, 24)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                // #18: Position Group Strengths Breakdown
                if showPositionGrades, !positionGroupGrades.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionLabel(text: "POSITION GROUP STRENGTHS")

                        // Without this the card is arithmetically impossible on
                        // its face: every group reads above the 53-man "Average
                        // Overall" on the card above, because every number here
                        // is a top-N starter average and none of them is a mean
                        // of the players counted underneath it.
                        Text("S is the starters, D the depth behind them. Each group's OVR is its starters' average \u{2014} which is why they read above the 53-man Average Overall.")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)

                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 10) {
                            ForEach(positionGroupGrades) { group in
                                VStack(spacing: 6) {
                                    // Dual grade: Starter/Depth (#235)
                                    HStack(spacing: 2) {
                                        Text("S:")
                                            .font(.system(size: DSType.Size.caption, weight: .medium))
                                            .foregroundStyle(Color.textTertiary)
                                        Text(group.starterGrade)
                                            .font(.title2.weight(.black))
                                            .foregroundStyle(PositionGradeCalculator.gradeColorForLetter(group.starterGrade))
                                        Text("/")
                                            .font(.title3)
                                            .foregroundStyle(Color.textTertiary)
                                        Text("D:")
                                            .font(.system(size: DSType.Size.caption, weight: .medium))
                                            .foregroundStyle(Color.textTertiary)
                                        Text(group.depthGrade)
                                            .font(.title2.weight(.black))
                                            .foregroundStyle(PositionGradeCalculator.gradeColorForLetter(group.depthGrade))
                                    }
                                    Text(group.name)
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(Color.textSecondary)
                                    Text("Starters \(group.starterAverage) OVR")
                                        .font(.subheadline.monospacedDigit())
                                        .foregroundStyle(Color.textTertiary)
                                    // #131/#134: Show count vs ideal with color
                                    let ideal = Self.idealGroupSize[group.name] ?? 4
                                    let staffColor: Color = group.playerCount >= ideal ? .success : group.playerCount >= ideal - 1 ? .warning : .dangerText
                                    // Not "7/6 players": a numerator larger than
                                    // its denominator reads as a broken
                                    // fraction, not as a roster count against
                                    // an ideal.
                                    Text("\(group.playerCount) (need \(ideal))")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(staffColor)
                                    if !group.need.isEmpty {
                                        Text(group.need)
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(Color.backgroundPrimary)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(
                                                Capsule().fill(group.need.contains("starter") ? Color.danger : Color.warning)
                                            )
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(group.color.opacity(0.08))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .strokeBorder(group.color.opacity(0.2), lineWidth: 1)
                                        )
                                )
                            }
                        }
                    }
                    .padding(20)
                    .cardBackground()
                    .padding(.horizontal, 24)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                // Cap situation with league average context (#19)
                if showCap {
                    VStack(alignment: .leading, spacing: 14) {
                        // THE VERDICT, beside the head. The card was five
                        // figures and a bar with no opinion in it — a new GM
                        // cannot tell whether $18M of room is comfortable or
                        // the reason he is about to be stuck.
                        HStack(spacing: 8) {
                            SectionLabel(text: "SALARY CAP")
                            Spacer(minLength: 4)
                            Text(capHealth.label.uppercased())
                                .font(DSType.display(DSType.Size.micro, .heavy))
                                .tracking(0.8)
                                .foregroundStyle(capHealth.color)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(capHealth.color.opacity(0.15)))
                        }

                        StatRow(label: "Total Cap", value: totalCapFormatted)
                        StatRow(label: "Used", value: capUsedFormatted)

                        // Cap usage bar. It used to be two bare rectangles: no
                        // caption saying it encodes cap USED, no mark for the
                        // minimum-spend floor a club can be under, and no
                        // separation of the money already owed to players who
                        // have left. All three are what turn a progress bar into
                        // a cap sheet.
                        let floorFraction = CapManagementEngine.salaryFloorFraction
                        let deadFraction = team.salaryCap > 0
                            ? Double(team.deadCapCurrentYear) / Double(team.salaryCap)
                            : 0
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: DSCornerRadius.tight)
                                    .fill(Color.backgroundTertiary)
                                    .frame(height: 10)
                                RoundedRectangle(cornerRadius: DSCornerRadius.tight)
                                    .fill(capUsedFraction > 0.9 ? Color.danger : Color.accentGold)
                                    .frame(width: geo.size.width * min(capUsedFraction, 1.0), height: 10)
                                if deadFraction > 0 {
                                    RoundedRectangle(cornerRadius: DSCornerRadius.tight)
                                        .fill(Color.dangerText)
                                        .frame(width: geo.size.width * min(deadFraction, 1.0), height: 10)
                                }
                                // Minimum-spend floor. Placed off
                                // `CapManagementEngine.salaryFloorFraction`, the
                                // same number the floor check itself runs on.
                                Rectangle()
                                    .fill(Color.textPrimary.opacity(0.7))
                                    .frame(width: 2, height: 18)
                                    .offset(x: geo.size.width * floorFraction - 1)
                            }
                            .frame(height: 18)
                        }
                        .frame(height: 18)

                        // What the bar is, in words.
                        HStack(spacing: 10) {
                            Text("Cap used \u{2014} \(String(format: "%.1f%%", capUsedFraction * 100)) of the \(totalCapFormatted) cap")
                                .font(DSType.text(DSType.Size.caption, .medium, prose: true))
                                .foregroundStyle(Color.textSecondary)
                            Spacer(minLength: 0)
                        }
                        HStack(spacing: 12) {
                            HStack(spacing: 4) {
                                Rectangle()
                                    .fill(Color.textPrimary.opacity(0.7))
                                    .frame(width: 2, height: 10)
                                Text("Minimum spend")
                                    .font(DSType.text(DSType.Size.micro, .regular, prose: true))
                                    .foregroundStyle(Color.textTertiary)
                            }
                            if team.deadCapCurrentYear > 0 {
                                HStack(spacing: 4) {
                                    RoundedRectangle(cornerRadius: 1)
                                        .fill(Color.dangerText)
                                        .frame(width: 8, height: 8)
                                    Text("Dead money \(deadCapFormatted)")
                                        .font(DSType.text(DSType.Size.micro, .regular, prose: true))
                                        .foregroundStyle(Color.textTertiary)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .accessibilityElement(children: .combine)

                        if CapManagementEngine.amountBelowFloor(team: team, capMode: career.capMode) > 0 {
                            Text("Below the minimum spend — the club has to commit more money before the season starts.")
                                .font(DSType.text(DSType.Size.caption, .regular, prose: true))
                                .foregroundStyle(Color.warning)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        // #19: Available cap with league average comparison
                        HStack {
                            Text("Available")
                                .font(.subheadline)
                                .foregroundStyle(Color.textSecondary)
                            Spacer()
                            Text(capAvailableFormatted)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(team.availableCap > 0 ? Color.success : Color.danger)
                            // League average cap space ~$25M = 25_000K
                            let aboveAvg = team.availableCap > 25_000
                            Image(systemName: aboveAvg ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                                .font(.caption)
                                .foregroundStyle(aboveAvg ? Color.success : Color.danger)
                        }

                        // #20: Cap space context. Same treatment team selection
                        // gives the identical fact ("League average: $NNM" on
                        // the coaching-budget card) — this is the anchor that
                        // makes the green figure above it mean anything, and it
                        // was the dimmest ink on the card.
                        Text("League average cap space: ~$25.0M")
                            .font(DSType.display(DSType.Size.caption, .semibold))
                            .foregroundStyle(Color.textSecondary)
                    }
                    .padding(20)
                    .cardBackground()
                    .padding(.horizontal, 24)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                // Draft picks
                if showDraft {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionLabel(text: "DRAFT PICKS")

                        if draftPicks.isEmpty {
                            Text("No picks available for \(String(career.currentSeason))")
                                .font(.subheadline)
                                .foregroundStyle(Color.textSecondary)
                        } else {
                            let sortedPicks = draftPicks.sorted { $0.round < $1.round || ($0.round == $1.round && $0.pickNumber < $1.pickNumber) }
                            let columns = [GridItem(.adaptive(minimum: 80), spacing: 8)]
                            LazyVGrid(columns: columns, spacing: 8) {
                                ForEach(sortedPicks, id: \.id) { pick in
                                    let pickColor: Color = {
                                        switch pick.round {
                                        case 1: return Color.accentGold
                                        case 2, 3: return Color.success
                                        case 4, 5: return Color(red: 0.3, green: 0.5, blue: 0.9)
                                        default: return Color.textTertiary
                                        }
                                    }()
                                    Text("Rd\(pick.round) #\(pick.pickNumber)")
                                        .font(.system(size: DSType.Size.body, weight: .semibold).monospacedDigit())
                                        .foregroundStyle(Color.textPrimary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(pickColor.opacity(0.12))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 6)
                                                        .strokeBorder(pickColor.opacity(0.4), lineWidth: 1)
                                                )
                                        )
                                }
                            }

                            Text("\(draftPicks.count) pick\(draftPicks.count == 1 ? "" : "s") total")
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                    .padding(20)
                    .cardBackground()
                    .padding(.horizontal, 24)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                Spacer().frame(height: 80)
            }
            .frame(maxWidth: DSLayout.wideMeasure)
            .frame(maxWidth: .infinity)
            .frame(minHeight: geometry.size.height)
        }
        // The briefing is taller than one screen, and the commit bar used to be
        // a capsule on a 0.95 background: the DRAFT PICKS head showed through it
        // as a rendering artefact rather than as "there is more below". Visible
        // indicators, an opaque bar, and an explainer that names what is still
        // down there.
        .scrollIndicators(.visible)
        .safeAreaInset(edge: .bottom) {
            DSActionBar(
                explainer: .init(
                    title: "Team overview",
                    message: "Keep scrolling — the **salary cap** and the **draft picks** you inherit are below."
                ),
                primary: .init(title: "Continue", handler: onContinue)
            )
        }
        }
        }
        // The player card, in the sheet placement the cap screen already uses
        // for it. The briefing has no navigation of its own, and a key player
        // the briefing names is exactly the man a new GM wants to open.
        .sheet(item: $inspectedPlayer) { player in
            NavigationStack {
                PlayerDetailView(player: player)
            }
        }
        .onAppear { runAnimations() }
    }

    private func runAnimations() {
        withAnimation(.easeOut(duration: 0.5).delay(0.2)) { showHeader = true }
        withAnimation(.easeOut(duration: 0.5).delay(0.7)) { showRoster = true }
        withAnimation(.easeOut(duration: 0.5).delay(1.2)) { showPositionGrades = true }
        withAnimation(.easeOut(duration: 0.5).delay(1.7)) { showCap = true }
        withAnimation(.easeOut(duration: 0.5).delay(2.2)) { showDraft = true }
    }
}

// MARK: - Step 3: Your Roadmap

private struct YourRoadmapStep: View {

    let onContinue: () -> Void

    @State private var showHeader = false
    @State private var showCalendar = false
    @State private var showTasks = false

    private struct CalendarEntry {
        let name: String
        let description: String
        let duration: String
        let isMandatory: Bool
    }

    private static let offseasonCalendarEntries: [CalendarEntry] = [
        CalendarEntry(name: "Coaching Changes", description: "Hire and fire coaches, set coordinator schemes, build your staff", duration: "Feb", isMandatory: true),
        CalendarEntry(name: "Roster Evaluation", description: "Review every player, identify positional needs, plan your offseason strategy", duration: "Feb", isMandatory: true),
        CalendarEntry(name: "The Combine", description: "Scout draft prospects, evaluate measurables, update your draft board", duration: "Late Feb", isMandatory: false),
        CalendarEntry(name: "Free Agency", description: "Sign free agents, re-sign your own players, fill roster gaps", duration: "Mar", isMandatory: true),
        CalendarEntry(name: "The Draft & UDFAs", description: "Select new talent across 7 rounds, then sign undrafted free agents", duration: "Late Apr", isMandatory: true),
        CalendarEntry(name: "OTAs", description: "Set depth chart, assign mentoring pairs, install playbook basics", duration: "May-Jun", isMandatory: false),
        CalendarEntry(name: "Training Camp", description: "Player development, position battles, final roster decisions", duration: "Jul-Aug", isMandatory: true),
        CalendarEntry(name: "Preseason", description: "Evaluate young players and bubble roster candidates in live games", duration: "Aug", isMandatory: false),
        CalendarEntry(name: "Roster Cuts", description: "Cut to 53-man roster — tough decisions on borderline players", duration: "Late Aug", isMandatory: true),
        CalendarEntry(name: "Regular Season", description: "18 weeks of football — manage injuries, trades, and weekly gameplans", duration: "Sep-Jan", isMandatory: true),
    ]

    private var calendarCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "OFFSEASON CALENDAR")

            Text("Your journey through the League year:")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)

            // WHY THIS ORDER. The list read as ten things that happen to come
            // in this sequence; it is a dependency chain, and the first link is
            // the one a new GM is most likely to rush. The staff he hires in
            // February set the schemes, and the schemes decide who fits in free
            // agency and which prospects grade out on his own board.
            Text("The order is a chain: the staff you hire first sets your schemes, and your schemes decide who is worth signing in free agency and who fits on your draft board.")
                .font(DSType.text(DSType.Size.caption, .regular, prose: true))
                .foregroundStyle(Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(Self.offseasonCalendarEntries.enumerated()), id: \.offset) { index, entry in
                    let isCurrent = index == 0
                    let totalEntries = Self.offseasonCalendarEntries.count
                    // The last row is not a tenth bullet, it is what the other
                    // nine are for. It used to go through the identical
                    // template and then get faded harder than any row above it,
                    // so the destination was the dimmest thing on the page.
                    let isDestination = index == totalEntries - 1
                    // #137: Fade distant phases progressively. The floor is
                    // 0.7, not 0.4 — the rows now carry a line of prose each,
                    // and a description has to stay readable at the far end of
                    // the timeline in a way a two-word phase name did not.
                    let distanceFade: Double = (isCurrent || isDestination) ? 1.0 : max(0.7, 1.0 - Double(index) * 0.08)

                    HStack(alignment: .top, spacing: 10) {
                        // Timeline connector
                        VStack(spacing: 0) {
                            ZStack {
                                if isCurrent {
                                    Circle()
                                        .fill(Color.accentGold.opacity(0.25))
                                        .frame(width: 16, height: 16)
                                }
                                if isDestination {
                                    // The chequered flag at the end of the road,
                                    // not another dot on it.
                                    Image(systemName: "flag.checkered")
                                        .font(.system(size: DSType.Size.footnote, weight: .bold))
                                        .foregroundStyle(Color.accentGold)
                                } else {
                                    Circle()
                                        .fill(isCurrent ? Color.accentGold : Color.textTertiary.opacity(0.3))
                                        .frame(width: isCurrent ? 10 : 6, height: isCurrent ? 10 : 6)
                                }
                            }

                            if index < totalEntries - 1 {
                                Rectangle()
                                    .fill(isCurrent ? Color.accentGold.opacity(0.4) : Color.surfaceBorder)
                                    .frame(width: 2)
                                    .frame(maxHeight: .infinity)
                            }
                        }
                        .frame(width: 16)

                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(entry.name)
                                    .font((isCurrent || isDestination) ? .caption.weight(.bold) : .caption.weight(.medium))
                                    .foregroundStyle((isCurrent || isDestination) ? Color.accentGold : Color.textPrimary)

                                if isCurrent {
                                    Text("CURRENT")
                                        .font(.system(size: DSType.Size.micro, weight: .black))
                                        .foregroundStyle(Color.backgroundPrimary)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Capsule().fill(Color.accentGold))
                                }

                                if isDestination {
                                    Text("WHERE IT ALL LEADS")
                                        .font(.system(size: DSType.Size.micro, weight: .black))
                                        .foregroundStyle(Color.accentGold)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(
                                            Capsule().strokeBorder(Color.accentGold.opacity(0.6), lineWidth: 1)
                                        )
                                }

                                // #140: Mandatory vs optional badge
                                if !isCurrent && !isDestination {
                                    Text(entry.isMandatory ? "REQUIRED" : "OPTIONAL")
                                        .font(.system(size: DSType.Size.micro, weight: .bold))
                                        .foregroundStyle(entry.isMandatory ? Color.textSecondary : Color.textTertiary)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(
                                            Capsule()
                                                .fill(entry.isMandatory ? Color.backgroundSecondary : Color.backgroundSecondary.opacity(0.5))
                                        )
                                }

                                Text(entry.duration)
                                    .font(.system(size: DSType.Size.micro, weight: .semibold))
                                    .foregroundStyle(Color.textTertiary)
                            }

                            // Every phase says what it is. Nine of the ten
                            // descriptions used to be withheld, which left the
                            // screen that sells the shape of the whole offseason
                            // ending at half a portrait iPad with a name and a
                            // month per row.
                            Text(entry.description)
                                .font(.caption2)
                                .foregroundStyle(Color.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()
                    }
                    .padding(.vertical, (isCurrent || isDestination) ? 8 : 4)
                    .padding(.horizontal, (isCurrent || isDestination) ? 8 : 4)
                    .opacity(distanceFade)
                    .background(
                        Group {
                            if isCurrent {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.accentGold.opacity(0.06))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .strokeBorder(Color.accentGold.opacity(0.2), lineWidth: 1)
                                    )
                            } else if isDestination {
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(Color.accentGold.opacity(0.25), lineWidth: 1)
                            }
                        }
                    )
                }
            }
        }
        .padding(20)
        .cardBackground()
    }

    private var tasksCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionLabel(text: "YOUR FIRST TASKS")

            // Task 3 used to be "Prepare for the Combine and Free Agency" —
            // two separate jobs, in two different months, under one number.
            // The Combine is optional scouting in late February; free agency
            // is a required market that opens in March.
            TaskRow(number: 1, text: "Hire your coaching staff", isActive: true)
            TaskRow(number: 2, text: "Evaluate the roster")
            TaskRow(number: 3, text: "Scout the Combine class")
            TaskRow(number: 4, text: "Prepare for free agency")
        }
        // The calendar card above is stretched by the `Spacer()` in its rows;
        // without this the tasks card hugs its longest task and neither edge
        // lines up with the card it sits under.
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .cardBackground()
    }

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()
            // The two intro steps either side of this one run their backdrop at
            // 0.2 under a gradient; this one sat at 0.1 with no gradient at all,
            // so the stadium was neither visible enough to be scenery nor
            // controlled enough to keep the cards clean. Same recipe as its
            // siblings, so the sequence stops changing its mind mid-way.
            GeometryReader { geo in
                Image("BgCoachStadium1")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .opacity(0.2)
            }
            .ignoresSafeArea()

            LinearGradient(
                colors: [Color.backgroundPrimary.opacity(0.7), Color.backgroundPrimary.opacity(0.4), Color.backgroundPrimary.opacity(0.7)],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()

        ScrollView {
            VStack(spacing: 24) {
                Spacer().frame(height: 20)

                // Header
                if showHeader {
                    VStack(spacing: 12) {
                        Image(systemName: "map.fill")
                            .font(.system(size: DSType.Size.display))
                            .foregroundStyle(Color.accentGold)

                        Text("YOUR ROADMAP")
                            .font(.system(size: DSType.Size.body, weight: .black))
                            .tracking(4)
                            .foregroundStyle(Color.accentGold)

                        // Names the destination. The page used to scope itself
                        // to "your first offseason" while its own list ended on
                        // the Regular Season, so nothing said what the nine
                        // offseason phases were building toward.
                        Text("Ten phases between here and kickoff. Here's your first offseason.")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // #136: Wider layout with reduced padding
                if showCalendar {
                    calendarCard
                        .padding(.horizontal, 16)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                if showTasks {
                    tasksCard
                        .padding(.horizontal, 16)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                Spacer().frame(height: 80)
            }
            .frame(maxWidth: DSLayout.wideMeasure)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) {
            DSActionBar(
                explainer: .init(
                    title: "Your roadmap",
                    message: "Ten phases, February to January. The **required** ones you work through; the **optional** ones you can skip."
                ),
                primary: .init(title: "Continue", handler: onContinue)
            )
        }
        }
        .onAppear { runAnimations() }
    }

    private func runAnimations() {
        withAnimation(.easeOut(duration: 0.5).delay(0.2)) { showHeader = true }
        withAnimation(.easeOut(duration: 0.5).delay(0.7)) { showCalendar = true }
        withAnimation(.easeOut(duration: 0.5).delay(1.2)) { showTasks = true }
    }
}

// MARK: - Step 4: Ready to Begin (tag 4)

private struct ReadyToBeginStep: View {

    let career: Career
    let team: Team?
    let teamOverall: Int
    /// The owner's headline demand, generated two steps back and never repeated.
    let seasonGoals: SeasonGoals?
    let rosterCount: Int
    let openStaffSeats: Int
    let draftPickCount: Int
    let onEnter: () -> Void

    @State private var showTitle = false
    @State private var showSubtitle = false
    @State private var showButton = false
    @State private var glowAmount: CGFloat = 0.3

    private var motivationalLine: String {
        switch teamOverall {
        case ...64:   return "Turn this franchise around."
        case 65...74: return "Write your legacy."
        case 75...84: return "Finish what they started."
        default:      return "Defend the throne."
        }
    }

    private var roleTitle: String {
        career.role == .gm ? "General Manager" : "GM & Head Coach"
    }

    /// Where on the calendar the dynasty actually starts.
    ///
    /// `completeIntro()` sets `.coachingChanges` and week 0, so this is the
    /// February that opens the League year — NOT Week 1, which is seven phases
    /// and five months away.
    private var startStamp: String {
        "February \(career.currentSeason) \u{2022} \(SeasonPhase.coachingChanges.displayName)"
    }

    var body: some View {
        ZStack {
            // The stadium at dawn, actually visible. It ran at 0.3 under a
            // gradient that reached 0.85 black, which multiplies out to almost
            // nothing at the bottom of the frame — the photograph that is meant
            // to carry the moment was doing no work at all. The image comes up,
            // the veil comes down, and the bottom stop stays dark enough that
            // the gold taglines still sit on their own ground.
            GeometryReader { geo in
                Image("BgStadiumDawn")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .opacity(0.55)
            }
            .ignoresSafeArea()

            // Dramatic gradient overlay: dark bottom fading to more visible stadium top
            LinearGradient(
                colors: [
                    Color.backgroundPrimary.opacity(0.15),
                    Color.backgroundPrimary.opacity(0.40),
                    Color.backgroundPrimary.opacity(0.78)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 28) {
                    if showTitle {
                        VStack(spacing: 16) {
                            Image(systemName: "football.fill")
                                .font(.system(size: DSType.Size.hero))
                                .foregroundStyle(Color.accentGold)
                                .shadow(color: Color.accentGold.opacity(glowAmount), radius: 20, y: 0)

                            // `hero` is the size the token scale reserves for
                            // full-bleed moments, and this is the only one in
                            // the app: a title screen on a 13" portrait iPad
                            // with two thirds of the page empty around it.
                            Text("Your Journey Begins")
                                .font(.system(size: DSType.Size.hero, weight: .bold))
                                .foregroundStyle(Color.textPrimary)

                            // The club's own mark and colour, which the app has
                            // had all along (`TeamLogoPlaceholder` /
                            // `TeamColors`) and this screen never used: it named
                            // the franchise in grey body text and painted every
                            // accent on the page the same league gold.
                            if let team = team {
                                HStack(spacing: 10) {
                                    TeamLogoPlaceholder(abbreviation: team.abbreviation, size: 34)
                                    Text("with the \(team.fullName)")
                                        .font(.title3.weight(.medium))
                                        .foregroundStyle(Color.textSecondary)
                                }
                            }

                            // Where on the calendar this starts.
                            Text(startStamp.uppercased())
                                .font(DSType.display(DSType.Size.caption, .heavy))
                                .tracking(1.4)
                                .foregroundStyle(Color.textTertiary)
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }

                    if showSubtitle {
                        VStack(spacing: 22) {
                            VStack(spacing: 8) {
                                Text("Build Your Dynasty.")
                                    .font(.title3.weight(.medium))
                                    .foregroundStyle(Color.accentGold)
                                    .shadow(color: Color.accentGold.opacity(0.5), radius: 12)

                                Text(motivationalLine)
                                    .font(.subheadline.italic())
                                    .foregroundStyle(Color.accentGold.opacity(0.75))
                            }

                            handoverCard
                        }
                        .transition(.opacity)
                    }
                }

                Spacer()
            }
        }
        .safeAreaInset(edge: .bottom) {
            if showButton {
                VStack(spacing: 8) {
                    Button(action: onEnter) {
                        HStack(spacing: 14) {
                            Text("Enter the Front Office")
                                .font(.title3.weight(.bold))
                            Image(systemName: "arrow.right")
                                .font(.title3.weight(.bold))
                        }
                        .foregroundStyle(Color.backgroundPrimary)
                        .padding(.horizontal, 48)
                        .padding(.vertical, 22)
                        .background(
                            Capsule()
                                .fill(Color.accentGold)
                                .shadow(color: Color.accentGold.opacity(0.4), radius: 12, y: 4)
                        )
                    }
                    .accessibilityHint("Starts the offseason on the Coaching Changes phase, with hiring your staff as the first task")

                    // What is actually on the other side of the door.
                    // `completeIntro()` opens on `.coachingChanges`, and
                    // `TaskGenerator` files the coordinator hires as that
                    // phase's required tasks — so the answer is not a guess.
                    Text(openStaffSeats > 0
                         ? "First job: hire your coaching staff \u{2014} \(openStaffSeats) seat\(openStaffSeats == 1 ? "" : "s") to fill."
                         : "First job: review the staff you inherited.")
                        .font(DSType.text(DSType.Size.caption, .medium, prose: true))
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.bottom, 16)
                .padding(.top, 12)
                .frame(maxWidth: .infinity)
                .background(Color.backgroundPrimary.opacity(0.95))
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .onAppear { runAnimations() }
    }

    // MARK: - Hand-over card
    //
    // The middle of this screen was empty: a title block between two `Spacer`s,
    // with nothing on the page that came from the four steps the player had just
    // sat through. This is that hand-over — who he is, what the owner wants, and
    // the three counts that describe the club he is walking into.

    private var handoverCard: some View {
        VStack(spacing: 12) {
            VStack(spacing: 2) {
                Text(career.playerName)
                    .font(DSType.text(DSType.Size.callout, .bold))
                    .foregroundStyle(Color.textPrimary)
                Text(roleTitle.uppercased())
                    .font(DSType.display(DSType.Size.micro, .heavy))
                    .tracking(1.2)
                    .foregroundStyle(Color.textTertiary)
            }

            if let goals = seasonGoals {
                VStack(spacing: 2) {
                    Text("THE OWNER WANTS")
                        .font(DSType.display(DSType.Size.micro, .heavy))
                        .tracking(1.2)
                        .foregroundStyle(Color.textTertiary)
                    Text(goals.primaryGoal)
                        .font(DSType.text(DSType.Size.footnote, .semibold, prose: true))
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }

            HStack(alignment: .top, spacing: 0) {
                handoverStat(value: "\(rosterCount)", label: "Players")
                handoverDivider
                handoverStat(value: "\(openStaffSeats)", label: "Staff seats open")
                handoverDivider
                handoverStat(value: "\(draftPickCount)", label: "Draft picks")
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .frame(maxWidth: 460)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.card)
                .fill(Color.backgroundPrimary.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: DSCornerRadius.card)
                        .strokeBorder(Color.accentGold.opacity(0.25), lineWidth: 1)
                )
        )
        .padding(.horizontal, 24)
    }

    private func handoverStat(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(DSType.display(DSType.Size.title2, .black))
                .foregroundStyle(Color.accentGold)
            Text(label.uppercased())
                .font(DSType.display(DSType.Size.micro, .heavy))
                .tracking(0.8)
                .foregroundStyle(Color.textTertiary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }

    private var handoverDivider: some View {
        Rectangle()
            .fill(Color.surfaceBorder)
            .frame(width: 1, height: 34)
    }

    private func runAnimations() {
        withAnimation(.easeOut(duration: 0.7).delay(0.3)) { showTitle = true }
        withAnimation(.easeOut(duration: 0.6).delay(1.0)) { showSubtitle = true }
        withAnimation(.easeOut(duration: 0.6).delay(1.7)) { showButton = true }
        withAnimation(
            .easeInOut(duration: 2.0)
            .repeatForever(autoreverses: true)
            .delay(0.3)
        ) {
            glowAmount = 0.7
        }
    }
}

// MARK: - Shared Components

/// §2.9: section heads are `textSecondary` and tracked, not gold — gold has
/// three jobs and "every heading on the screen" is not one of them. The owner
/// meeting already obeyed this (see `OwnerCard`); the two steps that follow it
/// put gold on every card head, so the intro contradicted itself mid-sequence.
private struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: DSType.Size.footnote, weight: .black))
            .tracking(2)
            .foregroundStyle(Color.textSecondary)
    }
}

private struct StatRow: View {
    let label: String
    let value: String
    var valueColor: Color = .textPrimary

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(valueColor)
        }
    }
}

/// A numbered first task.
///
/// Every row used to be an identical 26 pt filled-gold disc, so the list said
/// "here are four equally urgent things" when only the first one is actually
/// open — the other three are gated behind phases that have not started. The
/// active row keeps the filled disc and grows; the rest are outlined.
private struct TaskRow: View {
    let number: Int
    let text: String
    var isActive: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            Text("\(number)")
                .font(isActive ? .body.weight(.black) : .caption.weight(.black))
                .foregroundStyle(isActive ? Color.backgroundPrimary : Color.accentGold)
                .frame(width: isActive ? 34 : 26, height: isActive ? 34 : 26)
                .background(
                    Group {
                        if isActive {
                            Circle().fill(Color.accentGold)
                        } else {
                            Circle().strokeBorder(Color.accentGold.opacity(0.5), lineWidth: 1.5)
                        }
                    }
                )

            Text(text)
                .font(isActive ? .subheadline.weight(.bold) : .subheadline.weight(.medium))
                .foregroundStyle(isActive ? Color.textPrimary : Color.textSecondary)

            if isActive {
                Text("START HERE")
                    .font(DSType.display(DSType.Size.micro, .heavy))
                    .tracking(0.8)
                    .foregroundStyle(Color.accentGold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentGold.opacity(0.14)))
            }
        }
    }
}

/// Stat row that shows a value against a league average (#19).
///
/// One carrier for the verdict, and it is the delta. The row used to paint the
/// value with `Color.forRating` *and* flag it with a red arrow, so "70" read
/// good and failing in the same breath — and a 2-point shortfall wore the same
/// saturated red a 20-point one would. The signed number shows the magnitude
/// the arrow could not.
private struct ComparisonStatRow: View {
    let label: String
    let value: Int
    let leagueAvg: Int
    let format: (Int) -> String

    private var delta: Int { value - leagueAvg }

    private var deltaText: String {
        guard delta != 0 else { return "level with league avg \(format(leagueAvg))" }
        return "\(delta > 0 ? "+" : "")\(delta) vs league avg \(format(leagueAvg))"
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(format(value))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
            Text(deltaText)
                .font(.caption)
                .foregroundStyle(delta == 0 ? Color.textTertiary : delta > 0 ? Color.success : Color.warning)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        IntroSequenceView(career: Career(
            playerName: "Mike Johnson",
            avatarID: "avatar_00000",
            role: .gmAndHeadCoach,
            capMode: .simple
        ))
    }
    .modelContainer(for: Career.self, inMemory: true)
}
