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

    private let totalSteps = 4

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

                    ReadyToBeginStep(
                        career: career,
                        onEnter: { completeIntro() }
                    )
                    .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.4), value: currentStep)
            } else {
                ProgressView()
                    .tint(Color.accentGold)
            }
        }
        .navigationBarBackButtonHidden(true)
        .navigationDestination(isPresented: $navigateToDashboard) {
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
        career.currentPhase = .superBowl
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

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer().frame(height: 20)

                // Meeting header
                if showHeader {
                    VStack(spacing: 12) {
                        Image(systemName: "person.crop.rectangle")
                            .font(.system(size: 36))
                            .foregroundStyle(Color.accentGold)

                        Text("OWNER MEETING")
                            .font(.system(size: 14, weight: .black))
                            .tracking(4)
                            .foregroundStyle(Color.accentGold)

                        if let ownerName = owner?.name {
                            Text(ownerName)
                                .font(.title2.weight(.bold))
                                .foregroundStyle(Color.textPrimary)

                            Text("Owner, \(team.fullName)")
                                .font(.subheadline)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Owner personality traits
                if showTraits, let owner = owner {
                    VStack(spacing: 16) {
                        // Vision
                        InfoRow(
                            icon: "eye.fill",
                            label: "Owner's Vision",
                            value: owner.prefersWinNow ? "Win Now" : "Build for the Future"
                        )

                        // Patience
                        InfoRow(
                            icon: "clock.fill",
                            label: "Patience",
                            value: "Expects results within \(patienceDescription) seasons"
                        )

                        // Spending
                        InfoRow(
                            icon: "dollarsign.circle.fill",
                            label: "Free Agency Budget",
                            value: spendingLevel
                        )
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

                // Meddling warning
                if showWarning, let owner = owner, owner.meddling > 60 {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.warning)
                        Text("\"I like to be involved in decisions. Don't be surprised to hear from me.\"")
                            .font(.subheadline.italic())
                            .foregroundStyle(Color.textSecondary)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.warning.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Color.warning.opacity(0.2), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 24)
                    .transition(.opacity)
                }

                Spacer().frame(height: 12)

                IntroContinueButton(action: onContinue)
                    .padding(.bottom, 40)
            }
        }
        .scrollIndicators(.hidden)
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
    @State private var showCap = false
    @State private var showDraft = false
    @State private var showTasks = false

    private var averageOverall: Int {
        guard !players.isEmpty else { return 0 }
        return players.map(\.overall).reduce(0, +) / players.count
    }

    private var bestPlayer: Player? {
        players.max(by: { $0.overall < $1.overall })
    }

    /// Position group with the lowest average overall.
    private var weakestPositionGroup: String {
        guard !players.isEmpty else { return "N/A" }
        let grouped = Dictionary(grouping: players, by: { $0.position.side })
        guard let weakest = grouped.min(by: {
            let avg0 = $0.value.map(\.overall).reduce(0, +) / max($0.value.count, 1)
            let avg1 = $1.value.map(\.overall).reduce(0, +) / max($1.value.count, 1)
            return avg0 < avg1
        }) else { return "N/A" }
        return weakest.key.rawValue
    }

    private var filledCoachingSlots: Int {
        coaches.count
    }

    /// Total coaching staff positions expected (HC + OC + DC + STC + position coaches).
    private var totalCoachingSlots: Int { 10 }

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

                // Roster snapshot
                if showRoster {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionLabel(text: "ROSTER")

                        StatRow(label: "Total Players", value: "\(players.count)")
                        StatRow(label: "Average Overall", value: "\(averageOverall)",
                                valueColor: Color.forRating(averageOverall))

                        if let best = bestPlayer {
                            StatRow(label: "Best Player",
                                    value: "\(best.fullName) (\(best.position.rawValue)) - \(best.overall) OVR",
                                    valueColor: Color.forRating(best.overall))
                        }

                        StatRow(label: "Weakest Group", value: weakestPositionGroup)

                        StatRow(label: "Coaching Staff",
                                value: "\(filledCoachingSlots) / \(totalCoachingSlots) filled")
                    }
                    .padding(20)
                    .cardBackground()
                    .padding(.horizontal, 24)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                // Cap situation
                if showCap {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionLabel(text: "SALARY CAP")

                        StatRow(label: "Total Cap", value: totalCapFormatted)
                        StatRow(label: "Used", value: capUsedFormatted)
                        StatRow(label: "Available", value: capAvailableFormatted,
                                valueColor: team.availableCap > 0 ? Color.success : Color.danger)
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
                            Text("No picks available for \(career.currentSeason)")
                                .font(.subheadline)
                                .foregroundStyle(Color.textSecondary)
                        } else {
                            let byRound = Dictionary(grouping: draftPicks, by: { $0.round })
                            ForEach(byRound.keys.sorted(), id: \.self) { round in
                                let picks = byRound[round] ?? []
                                let pickNumbers = picks.map { "#\($0.pickNumber)" }.joined(separator: ", ")
                                StatRow(label: "Round \(round)",
                                        value: pickNumbers)
                            }
                        }
                    }
                    .padding(20)
                    .cardBackground()
                    .padding(.horizontal, 24)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                // First tasks
                if showTasks {
                    VStack(alignment: .leading, spacing: 16) {
                        SectionLabel(text: "YOUR FIRST TASKS")

                        TaskRow(number: 1, text: "Hire your coaching staff")
                        TaskRow(number: 2, text: "Evaluate the roster")
                        TaskRow(number: 3, text: "Prepare for the Combine and Free Agency")
                    }
                    .padding(20)
                    .cardBackground()
                    .padding(.horizontal, 24)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                Spacer().frame(height: 12)

                IntroContinueButton(action: onContinue)
                    .padding(.bottom, 40)
            }
        }
        .scrollIndicators(.hidden)
        .onAppear { runAnimations() }
    }

    private func runAnimations() {
        withAnimation(.easeOut(duration: 0.5).delay(0.2)) { showHeader = true }
        withAnimation(.easeOut(duration: 0.5).delay(0.7)) { showRoster = true }
        withAnimation(.easeOut(duration: 0.5).delay(1.2)) { showCap = true }
        withAnimation(.easeOut(duration: 0.5).delay(1.7)) { showDraft = true }
        withAnimation(.easeOut(duration: 0.5).delay(2.2)) { showTasks = true }
    }
}

// MARK: - Step 4: Ready to Begin

private struct ReadyToBeginStep: View {

    let career: Career
    let onEnter: () -> Void

    @State private var showTitle = false
    @State private var showSubtitle = false
    @State private var showButton = false
    @State private var glowAmount: CGFloat = 0.3

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
                if showTitle {
                    VStack(spacing: 16) {
                        Image(systemName: "sportscourt.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.accentGold)
                            .shadow(color: Color.accentGold.opacity(glowAmount), radius: 20, y: 0)

                        Text("Your Journey Begins")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(Color.textPrimary)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }

                if showSubtitle {
                    Text("Build Your Dynasty.")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(Color.accentGold)
                        .transition(.opacity)
                }

                if showButton {
                    Button(action: onEnter) {
                        HStack(spacing: 12) {
                            Text("Enter the Front Office")
                                .font(.headline.weight(.bold))
                            Image(systemName: "arrow.right")
                                .font(.headline)
                        }
                        .foregroundStyle(Color.backgroundPrimary)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 18)
                        .background(
                            Capsule()
                                .fill(Color.accentGold)
                                .shadow(color: Color.accentGold.opacity(0.4), radius: 12, y: 4)
                        )
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }

            Spacer()
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
