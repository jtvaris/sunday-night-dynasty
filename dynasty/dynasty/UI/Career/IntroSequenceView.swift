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
                        onContinue: { advanceStep() }
                    )
                    .tag(1)

                    TeamOverviewStep(
                        career: career,
                        team: team!,
                        players: players,
                        coaches: coaches,
                        draftPicks: draftPicks,
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
                        teamOverall: players.isEmpty ? 60 : players.map(\.overall).reduce(0, +) / players.count,
                        onEnter: { completeIntro() }
                    )
                    .tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.4), value: currentStep)
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

    private func advanceStep() {
        withAnimation(.easeInOut(duration: 0.4)) {
            if currentStep < totalSteps - 1 {
                currentStep += 1
            }
        }
    }

    private func applyPressConferenceResult(_ result: PressConferenceResult) {
        // Apply effects to career legacy
        career.legacy.applyPressConferenceResult(result, season: career.currentSeason)

        // Apply owner satisfaction
        if let ownerObj = owner {
            ownerObj.satisfaction = max(0, min(100, ownerObj.satisfaction + result.totalEffects.ownerSatisfaction))
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
    }
}

// MARK: - Step 2: Owner Meeting

private struct OwnerMeetingStep: View {

    let career: Career
    let owner: Owner?
    let team: Team
    let seasonGoals: SeasonGoals?
    let onContinue: () -> Void

    @State private var showHeader = false
    @State private var showTraits = false
    @State private var showGoals = false
    @State private var showWarning = false

    private var patienceDescription: String {
        guard let patience = owner?.patience else { return "a few" }
        switch patience {
        case 1...3:  return "\(patience)"
        case 4...6:  return "\(patience)"
        case 7...10: return "\(patience)"
        default:     return "\(patience)"
        }
    }

    private var spendingLevel: String {
        guard let spending = owner?.spendingWillingness else { return "Moderate" }
        switch spending {
        case 1...30:  return "Conservative"
        case 31...60: return "Moderate"
        case 61...80: return "Aggressive"
        default:      return "All-In"
        }
    }

    // MARK: - #15 Practical Implications

    private var patienceImplication: String {
        guard let patience = owner?.patience else { return "" }
        let leagueAvg = 5
        let comparison: String
        if patience < leagueAvg - 1 {
            comparison = "Less patient than most owners"
        } else if patience > leagueAvg + 1 {
            comparison = "More patient than most owners"
        } else {
            comparison = "About average patience"
        }
        switch patience {
        case 1...3:  return "League avg: \(leagueAvg) seasons — \(comparison). Win fast or face consequences."
        case 4...6:  return "League avg: \(leagueAvg) seasons — \(comparison). Steady progress expected each year."
        case 7...10: return "League avg: \(leagueAvg) seasons — \(comparison). Time to build through the draft."
        default:     return ""
        }
    }

    private var visionImplication: String {
        guard let owner = owner else { return "" }
        if owner.prefersWinNow {
            return "Prioritizes free agency spending, expects playoff contention. Veterans favored over draft-and-develop."
        } else {
            return "Supports a long-term plan. Draft picks and player development are valued over quick fixes."
        }
    }

    private var budgetImplication: String {
        guard let owner = owner else { return "" }
        let budgetM = String(format: "$%.1fM", Double(owner.coachingBudget) / 1_000.0)
        let leagueAvgM = "$20.0M"
        switch owner.spendingWillingness {
        case 1...30:  return "Budget: \(budgetM) (league avg: \(leagueAvgM)). Build through the draft — free agency will be tight."
        case 31...60: return "Budget: \(budgetM) (league avg: \(leagueAvgM)). Modest spending — be strategic with signings."
        case 61...80: return "Budget: \(budgetM) (league avg: \(leagueAvgM)). Significant resources for roster upgrades."
        default:      return "Budget: \(budgetM) (league avg: \(leagueAvgM)). Money is no object — the owner backs any move."
        }
    }

    private var meddlingImplication: String {
        guard let meddling = owner?.meddling else { return "" }
        switch meddling {
        case 1...30:  return "Full autonomy on roster decisions. The owner trusts your football judgment completely."
        case 31...60: return "The owner may weigh in on major decisions but generally stays out of the way."
        case 61...80: return "Expect the owner to have opinions on key signings and draft picks."
        default:      return "The owner will frequently override your decisions. Pick your battles carefully."
        }
    }

    // MARK: - #16 Personal Warning Quote

    private var personalWarningQuote: String {
        guard let owner = owner else { return "" }
        let name = owner.name.components(separatedBy: " ").first ?? owner.name

        if owner.prefersWinNow && owner.patience <= 3 {
            return "\"I didn't buy this team to lose. I want a championship, and I want it now.\" — \(name)"
        } else if owner.prefersWinNow && owner.meddling > 60 {
            return "\"I'll be watching every move you make. My fans deserve winners.\" — \(name)"
        } else if owner.prefersWinNow {
            return "\"I believe in winning. Show me results and you'll have everything you need.\" — \(name)"
        } else if owner.patience >= 7 {
            return "\"Take your time and build this the right way. I'm not going anywhere.\" — \(name)"
        } else if owner.meddling > 60 {
            return "\"I trust you, but I like to stay close to the operation. Don't shut me out.\" — \(name)"
        } else if owner.spendingWillingness < 30 {
            return "\"Be smart with the money. Every dollar has to count around here.\" — \(name)"
        } else {
            return "\"Just give me a team the city can be proud of. That's all I ask.\" — \(name)"
        }
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

        GeometryReader { geometry in
        ScrollView {
            VStack(spacing: 24) {
                Spacer().frame(height: 8)

                // Meeting header
                if showHeader {

                    VStack(spacing: 12) {
                        if let owner = owner {
                            OwnerAvatarImageView(
                                avatarID: owner.avatarID,
                                size: 96
                            )
                        } else {
                            Image(systemName: "person.crop.rectangle")
                                .font(.system(size: 36))
                                .foregroundStyle(Color.accentGold)
                        }

                        Text("OWNER MEETING")
                            .font(.system(size: 14, weight: .black))
                            .tracking(4)
                            .foregroundStyle(Color.accentGold)

                        if let ownerName = owner?.name {
                            Text(ownerName)
                                .font(.title2.weight(.bold))
                                .foregroundStyle(Color.textPrimary)

                            Text("Owner, \(team.fullName)")
                                .font(.body)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Owner personality traits + practical implications (#15)
                if showTraits, let owner = owner {
                    VStack(spacing: 16) {
                        // Vision
                        InfoRow(
                            icon: "eye.fill",
                            label: "Owner's Vision",
                            value: owner.prefersWinNow ? "Win Now" : "Build for the Future"
                        )
                        ImplicationRow(text: visionImplication)

                        // Patience
                        InfoRow(
                            icon: "clock.fill",
                            label: "Patience",
                            value: "Expects results within \(patienceDescription) seasons"
                        )
                        ImplicationRow(text: patienceImplication)

                        // Spending
                        InfoRow(
                            icon: "dollarsign.circle.fill",
                            label: "Free Agency Budget",
                            value: spendingLevel
                        )
                        ImplicationRow(text: budgetImplication)

                        // Meddling / Involvement
                        InfoRow(
                            icon: "person.badge.key.fill",
                            label: "Involvement",
                            value: owner.meddling < 25 ? "Hands Off" : owner.meddling < 50 ? "Occasionally Involved" : owner.meddling < 75 ? "Frequently Involved" : "Highly Controlling"
                        )
                        ImplicationRow(text: meddlingImplication)
                    }
                    .padding(20)
                    .cardBackground()
                    .padding(.horizontal, 24)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                // Season goals
                if showGoals, let goals = seasonGoals {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("SEASON GOALS")
                            .font(.system(size: 12, weight: .black))
                            .tracking(2)
                            .foregroundStyle(Color.accentGold)

                        VStack(alignment: .leading, spacing: 12) {
                            GoalRow(icon: "trophy.fill", label: "Primary", value: goals.primaryGoal)
                            GoalRow(icon: "star.fill", label: "Secondary", value: goals.secondaryGoal)
                        }
                    }
                    .padding(20)
                    .cardBackground()
                    .padding(.horizontal, 24)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                // Personal owner quote (#16)
                if showWarning, let _ = owner {
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: "quote.opening")
                                .font(.title3)
                                .foregroundStyle(Color.accentGold.opacity(0.7))
                            Text(personalWarningQuote)
                                .font(.subheadline.italic())
                                .foregroundStyle(Color.textSecondary)
                        }

                        // #129: Consequences warning
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(Color.warning)
                            Text("Failure may result in: budget cuts, forced trades, or termination")
                                .font(.caption)
                                .foregroundStyle(Color.textTertiary)
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.accentGold.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Color.accentGold.opacity(0.2), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 24)
                    .transition(.opacity)
                }

                Spacer().frame(height: 80)
            }
            .frame(maxWidth: 800)
            .frame(maxWidth: .infinity)
            .frame(minHeight: geometry.size.height)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) {
            IntroContinueButton(action: onContinue)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                .padding(.top, 12)
                .frame(maxWidth: .infinity)
                .background(Color.backgroundPrimary.opacity(0.95))
        }
        }
        }
        .onAppear { runAnimations() }
    }

    private func runAnimations() {
        withAnimation(.easeOut(duration: 0.5).delay(0.2)) { showHeader = true }
        withAnimation(.easeOut(duration: 0.5).delay(0.9)) { showTraits = true }
        withAnimation(.easeOut(duration: 0.5).delay(1.6)) { showGoals = true }
        withAnimation(.easeOut(duration: 0.5).delay(2.3)) { showWarning = true }
    }
}

// MARK: - Step 3: Team Overview

private struct TeamOverviewStep: View {

    let career: Career
    let team: Team
    let players: [Player]
    let coaches: [Coach]
    let draftPicks: [DraftPick]
    let onContinue: () -> Void

    @State private var showHeader = false
    @State private var showRoster = false
    @State private var showPositionGrades = false
    @State private var showCap = false
    @State private var showDraft = false

    private var averageOverall: Int {
        guard !players.isEmpty else { return 0 }
        return players.map(\.overall).reduce(0, +) / players.count
    }

    private var bestPlayer: Player? {
        players.max(by: { $0.overall < $1.overall })
    }

    /// Top 3 players by overall rating.
    private var topPlayers: [Player] {
        Array(players.sorted { $0.overall > $1.overall }.prefix(3))
    }

    /// Position group with the lowest average overall, including grade and OVR.
    private var weakestPositionGroup: String {
        guard !players.isEmpty else { return "N/A" }
        let grouped = Dictionary(grouping: players, by: { Self.positionGroupName(for: $0.position) })
        guard let weakest = grouped.min(by: {
            let avg0 = $0.value.map(\.overall).reduce(0, +) / max($0.value.count, 1)
            let avg1 = $1.value.map(\.overall).reduce(0, +) / max($1.value.count, 1)
            return avg0 < avg1
        }) else { return "N/A" }
        let avg = weakest.value.map(\.overall).reduce(0, +) / max(weakest.value.count, 1)
        let grade = Self.gradeForAverage(avg)
        return "\(weakest.key) (\(grade), \(avg) OVR)"
    }

    private var filledCoachingSlots: Int {
        coaches.count
    }

    // MARK: - #20 Roster Age & Contract Summary

    private var averageAge: Double {
        guard !players.isEmpty else { return 0 }
        return Double(players.map(\.age).reduce(0, +)) / Double(players.count)
    }

    private var expiringContracts: Int {
        players.filter { $0.contractYearsRemaining <= 1 }.count
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

    private static func gradeForAverage(_ avg: Int) -> String {
        switch avg {
        case 90...:    return "A+"
        case 85...89:  return "A"
        case 80...84:  return "A-"
        case 77...79:  return "B+"
        case 73...76:  return "B"
        case 70...72:  return "B-"
        case 67...69:  return "C+"
        case 63...66:  return "C"
        case 60...62:  return "C-"
        case 55...59:  return "D+"
        case 50...54:  return "D"
        default:       return "F"
        }
    }

    private static func colorForGrade(_ avg: Int) -> Color {
        switch avg {
        case 80...:   return Color.success
        case 70...79: return Color.accentBlue
        case 60...69: return Color.accentGold
        case 50...59: return Color.warning
        default:      return Color.danger
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
    private var totalCoachingSlots: Int { CoachRole.allCases.count }

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
                            .font(.system(size: 36))
                            .foregroundStyle(Color.accentGold)

                        Text("TEAM OVERVIEW")
                            .font(.system(size: 14, weight: .black))
                            .tracking(4)
                            .foregroundStyle(Color.accentGold)

                        Text(team.fullName)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(Color.textPrimary)
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
                            Text("(Avg: 26.0)")
                                .font(.caption)
                                .foregroundStyle(averageAge > 27.5 ? Color.warning : averageAge < 25.0 ? Color.success : Color.textTertiary)
                        }

                        // #20: Expiring contracts
                        StatRow(
                            label: "Expiring Contracts",
                            value: "\(expiringContracts) player\(expiringContracts == 1 ? "" : "s")",
                            valueColor: expiringContracts > 15 ? Color.danger : expiringContracts > 8 ? Color.warning : Color.textPrimary
                        )

                        // #133: Top 3 key players
                        if !topPlayers.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Key Players")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.textSecondary)
                                ForEach(topPlayers, id: \.id) { player in
                                    HStack {
                                        Text("\(player.fullName)")
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(Color.textPrimary)
                                        Spacer()
                                        Text("\(player.position.rawValue) — \(player.overall) OVR")
                                            .font(.subheadline.monospacedDigit())
                                            .foregroundStyle(Color.forRating(player.overall))
                                    }
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
                                        .foregroundStyle(Color.danger)
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

                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 10) {
                            ForEach(positionGroupGrades) { group in
                                VStack(spacing: 6) {
                                    // Dual grade: Starter/Depth (#235)
                                    HStack(spacing: 3) {
                                        Text(group.starterGrade)
                                            .font(.title2.weight(.black))
                                            .foregroundStyle(Color.accentBlue)
                                        Text("/")
                                            .font(.title3)
                                            .foregroundStyle(Color.textTertiary)
                                        Text(group.depthGrade)
                                            .font(.title2.weight(.black))
                                            .foregroundStyle(Color.warning)
                                    }
                                    Text(group.name)
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(Color.textSecondary)
                                    Text("\(group.starterAverage) OVR")
                                        .font(.subheadline.monospacedDigit())
                                        .foregroundStyle(Color.textTertiary)
                                    // #131/#134: Show count vs ideal with color
                                    let ideal = Self.idealGroupSize[group.name] ?? 4
                                    let staffColor: Color = group.playerCount >= ideal ? .success : group.playerCount >= ideal - 1 ? .warning : .danger
                                    Text("\(group.playerCount)/\(ideal) players")
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
                        SectionLabel(text: "SALARY CAP")

                        StatRow(label: "Total Cap", value: totalCapFormatted)
                        StatRow(label: "Used", value: capUsedFormatted)

                        // Cap usage progress bar
                        GeometryReader { geo in
                            let usedFraction = team.salaryCap > 0
                                ? Double(team.currentCapUsage) / Double(team.salaryCap)
                                : 0
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.backgroundTertiary)
                                    .frame(height: 8)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(usedFraction > 0.9 ? Color.danger : Color.accentGold)
                                    .frame(width: geo.size.width * min(usedFraction, 1.0), height: 8)
                            }
                        }
                        .frame(height: 8)

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

                        // #20: Cap space context
                        Text("League Avg Cap Space: ~$25.0M")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
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
                                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
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
            .frame(maxWidth: 800)
            .frame(maxWidth: .infinity)
            .frame(minHeight: geometry.size.height)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) {
            IntroContinueButton(action: onContinue)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                .padding(.top, 12)
                .frame(maxWidth: .infinity)
                .background(Color.backgroundPrimary.opacity(0.95))
        }
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
        CalendarEntry(name: "NFL Combine", description: "Scout draft prospects, evaluate measurables, update your draft board", duration: "Late Feb", isMandatory: false),
        CalendarEntry(name: "Free Agency", description: "Sign free agents, re-sign your own players, fill roster gaps", duration: "Mar", isMandatory: true),
        CalendarEntry(name: "NFL Draft & UDFAs", description: "Select new talent across 7 rounds, then sign undrafted free agents", duration: "Late Apr", isMandatory: true),
        CalendarEntry(name: "OTAs", description: "Set depth chart, assign mentoring pairs, install playbook basics", duration: "May-Jun", isMandatory: false),
        CalendarEntry(name: "Training Camp", description: "Player development, position battles, final roster decisions", duration: "Jul-Aug", isMandatory: true),
        CalendarEntry(name: "Preseason", description: "Evaluate young players and bubble roster candidates in live games", duration: "Aug", isMandatory: false),
        CalendarEntry(name: "Roster Cuts", description: "Cut to 53-man roster — tough decisions on borderline players", duration: "Late Aug", isMandatory: true),
        CalendarEntry(name: "Regular Season", description: "18 weeks of football — manage injuries, trades, and weekly gameplans", duration: "Sep-Jan", isMandatory: true),
    ]

    private var calendarCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionLabel(text: "OFFSEASON CALENDAR")

            Text("Your journey through the NFL year:")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(Self.offseasonCalendarEntries.enumerated()), id: \.offset) { index, entry in
                    let isCurrent = index == 0
                    let totalEntries = Self.offseasonCalendarEntries.count
                    // #137: Fade distant phases progressively
                    let distanceFade: Double = isCurrent ? 1.0 : max(0.4, 1.0 - Double(index) * 0.08)

                    HStack(alignment: .top, spacing: 14) {
                        // Timeline connector
                        VStack(spacing: 0) {
                            ZStack {
                                if isCurrent {
                                    Circle()
                                        .fill(Color.accentGold.opacity(0.25))
                                        .frame(width: 20, height: 20)
                                }
                                Circle()
                                    .fill(isCurrent ? Color.accentGold : Color.textTertiary.opacity(0.3))
                                    .frame(width: isCurrent ? 12 : 8, height: isCurrent ? 12 : 8)
                            }

                            if index < totalEntries - 1 {
                                Rectangle()
                                    .fill(isCurrent ? Color.accentGold.opacity(0.4) : Color.surfaceBorder)
                                    .frame(width: 2)
                                    .frame(maxHeight: .infinity)
                            }
                        }
                        .frame(width: 20)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text(entry.name)
                                    .font(isCurrent ? .subheadline.weight(.bold) : .subheadline.weight(.medium))
                                    .foregroundStyle(isCurrent ? Color.accentGold : Color.textPrimary)

                                if isCurrent {
                                    Text("CURRENT")
                                        .font(.system(size: 9, weight: .black))
                                        .foregroundStyle(Color.backgroundPrimary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(Color.accentGold))
                                }

                                // #140: Mandatory vs optional badge
                                if !isCurrent {
                                    Text(entry.isMandatory ? "REQUIRED" : "OPTIONAL")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(entry.isMandatory ? Color.textSecondary : Color.textTertiary)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(
                                            Capsule()
                                                .fill(entry.isMandatory ? Color.backgroundSecondary : Color.backgroundSecondary.opacity(0.5))
                                        )
                                }
                            }

                            // #139: Expanded description
                            Text(entry.description)
                                .font(.caption)
                                .foregroundStyle(isCurrent ? Color.textSecondary : Color.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)

                            // #138: Duration label
                            Text(entry.duration)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.textTertiary)
                        }

                        Spacer()
                    }
                    .padding(.vertical, isCurrent ? 10 : 7)
                    .padding(.horizontal, isCurrent ? 10 : 6)
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

            TaskRow(number: 1, text: "Hire your coaching staff")
            TaskRow(number: 2, text: "Evaluate the roster")
            TaskRow(number: 3, text: "Prepare for the Combine and Free Agency")
        }
        .padding(20)
        .cardBackground()
    }

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()
            GeometryReader { geo in
                Image("BgCoachStadium1")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .opacity(0.1)
            }
            .ignoresSafeArea()

        ScrollView {
            VStack(spacing: 24) {
                Spacer().frame(height: 20)

                // Header
                if showHeader {
                    VStack(spacing: 12) {
                        Image(systemName: "map.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(Color.accentGold)

                        Text("YOUR ROADMAP")
                            .font(.system(size: 14, weight: .black))
                            .tracking(4)
                            .foregroundStyle(Color.accentGold)

                        Text("Here's what lies ahead in your first offseason")
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
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) {
            IntroContinueButton(action: onContinue)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                .padding(.top, 12)
                .frame(maxWidth: .infinity)
                .background(Color.backgroundPrimary.opacity(0.95))
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

    var body: some View {
        ZStack {
            // Dimmed background image
            GeometryReader { geo in
                Image("BgStadiumDawn")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .opacity(0.3)
            }
            .ignoresSafeArea()

            // Dramatic gradient overlay: dark bottom fading to more visible stadium top
            LinearGradient(
                colors: [
                    Color.backgroundPrimary.opacity(0.3),
                    Color.backgroundPrimary.opacity(0.5),
                    Color.backgroundPrimary.opacity(0.85)
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
                                .font(.system(size: 48))
                                .foregroundStyle(Color.accentGold)
                                .shadow(color: Color.accentGold.opacity(glowAmount), radius: 20, y: 0)

                            Text("Your Journey Begins")
                                .font(.system(size: 36, weight: .bold))
                                .foregroundStyle(Color.textPrimary)

                            if let team = team {
                                Text("with the \(team.fullName)")
                                    .font(.title3.weight(.medium))
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }

                    if showSubtitle {
                        VStack(spacing: 8) {
                            Text("Build Your Dynasty.")
                                .font(.title3.weight(.medium))
                                .foregroundStyle(Color.accentGold)
                                .shadow(color: Color.accentGold.opacity(0.5), radius: 12)

                            Text(motivationalLine)
                                .font(.subheadline.italic())
                                .foregroundStyle(Color.accentGold.opacity(0.75))
                        }
                        .transition(.opacity)
                    }
                }

                Spacer()
            }
        }
        .safeAreaInset(edge: .bottom) {
            if showButton {
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
                .padding(.bottom, 16)
                .padding(.top, 12)
                .frame(maxWidth: .infinity)
                .background(Color.backgroundPrimary.opacity(0.95))
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .onAppear { runAnimations() }
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

private struct QuoteBubble: View {
    let speaker: String
    let quote: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(speaker)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.accentGold)

            Text("\"\(quote)\"")
                .font(.body)
                .italic()
                .foregroundStyle(Color.textPrimary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }
}

private struct InfoRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(Color.accentGold)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                Text(value)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.textPrimary)
            }

            Spacer()
        }
    }
}

private struct GoalRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentGold)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(Color.textTertiary)
                Text(value)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.textPrimary)
            }
        }
    }
}

private struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .black))
            .tracking(2)
            .foregroundStyle(Color.accentGold)
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

private struct TaskRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(spacing: 14) {
            Text("\(number)")
                .font(.caption.weight(.black))
                .foregroundStyle(Color.backgroundPrimary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.accentGold))

            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.textPrimary)
        }
    }
}

/// Shows a subtle implication/tip below an InfoRow (#15).
private struct ImplicationRow: View {
    let text: String

    var body: some View {
        if !text.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.caption2)
                    .foregroundStyle(Color.accentGold.opacity(0.6))
                Text(text)
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 38)
        }
    }
}

/// Stat row that shows a value compared to a league average, with green/red indicator (#19).
private struct ComparisonStatRow: View {
    let label: String
    let value: Int
    let leagueAvg: Int
    let format: (Int) -> String

    private var isAbove: Bool { value >= leagueAvg }

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(format(value))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.forRating(value))
            Text("(Avg: \(format(leagueAvg)))")
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
            Image(systemName: isAbove ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .font(.caption)
                .foregroundStyle(isAbove ? Color.success : Color.danger)
        }
    }
}

private struct IntroContinueButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text("Continue")
                    .font(.headline.weight(.semibold))
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(Color.backgroundPrimary)
            .padding(.horizontal, 36)
            .padding(.vertical, 14)
            .background(
                Capsule()
                    .fill(Color.accentGold)
            )
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        IntroSequenceView(career: Career(
            playerName: "Mike Johnson",
            avatarID: "coach_m1",
            role: .gmAndHeadCoach,
            capMode: .simple
        ))
    }
    .modelContainer(for: Career.self, inMemory: true)
}
