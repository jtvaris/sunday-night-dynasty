import SwiftUI
import SwiftData

struct ProspectDetailView: View {
    let career: Career
    let prospect: CollegeProspect

    @Environment(\.modelContext) private var modelContext
    @State private var scouts: [Scout] = []
    @State private var coaches: [Coach] = []
    @State private var showSendScout = false
    @State private var showInterviewResult = false
    @State private var interviewResult: (personality: PersonalityArchetype, footballIQ: Int, characterNotes: [String])?

    // MARK: - Derived

    private var isScouted: Bool { prospect.scoutedOverall != nil }
    private var hasCombine: Bool {
        prospect.fortyTime != nil || prospect.benchPress != nil ||
        prospect.verticalJump != nil || prospect.broadJump != nil ||
        prospect.shuttleTime != nil || prospect.coneDrill != nil
    }
    private var isCombinePhase: Bool { career.currentPhase == .combine }
    private var isDraftPhase: Bool { career.currentPhase == .draft }
    private var canInterview: Bool { isCombinePhase && !prospect.interviewCompleted && career.interviewsUsed < 60 }
    private var canWorkout: Bool { (isCombinePhase || isDraftPhase) && !prospect.proDayCompleted && career.workoutsUsed < 30 }

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            List {
                headerSection
                combineSection
                if prospect.interviewCompleted { interviewResultsSection }
                if isScouted { scoutingReportSection }
                draftSection
                actionsSection
            }
            .scrollContentBackground(.hidden)
            .listStyle(.insetGrouped)
        }
        .navigationTitle(prospect.fullName)
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { loadScouts(); loadCoaches() }
        .sheet(isPresented: $showSendScout) {
            SendScoutSheet(prospect: prospect, scouts: scouts, scoutingPhase: currentScoutingPhase)
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        Section {
            HStack(alignment: .top, spacing: 16) {
                // Position badge
                VStack {
                    Text(prospect.position.rawValue)
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(Color.textPrimary)
                        .frame(width: 54, height: 54)
                        .background(positionColor, in: RoundedRectangle(cornerRadius: 10))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(prospect.college)
                        .font(.headline)
                        .foregroundStyle(Color.textSecondary)

                    HStack(spacing: 16) {
                        ProspectInfoPill(label: "Age", value: "\(prospect.age)")
                        ProspectInfoPill(label: "Ht", value: heightLabel)
                        ProspectInfoPill(label: "Wt", value: "\(prospect.weight) lbs")
                    }
                }

                Spacer()

                if let overall = prospect.scoutedOverall {
                    VStack(spacing: 2) {
                        Text("\(overall)")
                            .font(.system(size: 36, weight: .heavy).monospacedDigit())
                            .foregroundStyle(Color.forRating(overall))
                        Text("Overall")
                            .font(.caption2)
                            .foregroundStyle(Color.textTertiary)
                    }
                } else {
                    VStack(spacing: 2) {
                        Text("?")
                            .font(.system(size: 36, weight: .heavy))
                            .foregroundStyle(Color.textTertiary)
                        Text("Unscouted")
                            .font(.caption2)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    // MARK: - Combine Section

    private var combineSection: some View {
        Section("Physical Measurables") {
            MeasurableRow(label: "40-Yard Dash",   value: prospect.fortyTime.map { String(format: "%.2f sec", $0) })
            MeasurableRow(label: "Bench Press",    value: prospect.benchPress.map { "\($0) reps" })
            MeasurableRow(label: "Vertical Jump",  value: prospect.verticalJump.map { String(format: "%.1f in", $0) })
            MeasurableRow(label: "Broad Jump",     value: prospect.broadJump.map { "\($0) in" })
            MeasurableRow(label: "Shuttle",        value: prospect.shuttleTime.map { String(format: "%.2f sec", $0) })
            MeasurableRow(label: "3-Cone Drill",   value: prospect.coneDrill.map { String(format: "%.2f sec", $0) })

            if !hasCombine {
                HStack {
                    Image(systemName: "clock")
                        .foregroundStyle(Color.textTertiary)
                    Text("Combine results pending")
                        .font(.subheadline)
                        .foregroundStyle(Color.textTertiary)
                }
            }
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    // MARK: - Scouting Report Section

    @ViewBuilder
    private var scoutingReportSection: some View {
        Section("Scouting Report") {
            if let overall = prospect.scoutedOverall {
                LabeledContent("Overall Grade") {
                    Text("\(overall)")
                        .font(.body.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.forRating(overall))
                }
            }

            if let potential = prospect.scoutedPotential {
                LabeledContent("Potential Grade") {
                    Text("\(potential)")
                        .font(.body.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.forRating(potential))
                }
            }

            if let grade = prospect.scoutGrade {
                LabeledContent("Scout Grade") {
                    Text(grade)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentGold)
                }
            }

            if let personality = prospect.scoutedPersonality {
                LabeledContent("Personality") {
                    Text(personality.displayName)
                        .foregroundStyle(Color.textPrimary)
                }
            }

            // Status indicators
            HStack(spacing: 16) {
                StatusPill(label: "Interview", completed: prospect.interviewCompleted)
                StatusPill(label: "Pro Day",   completed: prospect.proDayCompleted)
            }
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    // MARK: - Interview Results Section

    @ViewBuilder
    private var interviewResultsSection: some View {
        Section("Interview Results") {
            if let personality = prospect.scoutedPersonality {
                LabeledContent("Personality") {
                    Text(personality.displayName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentGold)
                }
            }

            if let iq = prospect.interviewFootballIQ {
                LabeledContent("Football IQ") {
                    Text("\(iq)")
                        .font(.body.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.forRating(iq))
                }
            }

            if let notes = prospect.interviewCharacterNotes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Character Notes")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                    ForEach(notes, id: \.self) { note in
                        HStack(spacing: 6) {
                            Image(systemName: "person.fill.checkmark")
                                .font(.caption)
                                .foregroundStyle(Color.accentBlue)
                            Text(note)
                                .font(.subheadline)
                                .foregroundStyle(Color.textPrimary)
                        }
                    }
                }
            }
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    // MARK: - Draft Section

    private var draftSection: some View {
        Section("Draft Information") {
            LabeledContent("Declaring for Draft") {
                Text(prospect.isDeclaringForDraft ? "Yes" : "No")
                    .foregroundStyle(prospect.isDeclaringForDraft ? Color.success : Color.textSecondary)
            }

            if let proj = prospect.draftProjection {
                LabeledContent("Draft Projection") {
                    Text("Round \(proj)")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(projectionColor(proj))
                        .monospacedDigit()
                }
            } else {
                LabeledContent("Draft Projection") {
                    Text("Unknown")
                        .foregroundStyle(Color.textTertiary)
                }
            }

            // Mock draft projection
            if let mockPick = prospect.mockDraftPickNumber,
               let mockTeam = prospect.mockDraftTeam {
                LabeledContent("Mock Draft") {
                    Text("Rd1 Pick #\(mockPick) — \(mockTeam)")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentGold)
                        .monospacedDigit()
                }
            }

            // Team interest indicator
            LabeledContent("Team Interest") {
                InterestBadge(level: prospect.interestLevel)
            }
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        Section {
            Button {
                showSendScout = true
            } label: {
                Label(
                    isScouted ? "Send Another Scout (\(currentScoutingPhase.displayName))" : "Send Scout to Evaluate",
                    systemImage: "magnifyingglass"
                )
                .foregroundStyle(Color.accentGold)
            }

            // Interview button (combine phase, max 60)
            if canInterview {
                Button {
                    performInterview()
                } label: {
                    HStack {
                        Label("Conduct Interview", systemImage: "person.crop.circle.badge.questionmark")
                            .foregroundStyle(Color.accentBlue)
                        Spacer()
                        Text("Interviews: \(career.interviewsUsed)/60 used")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            } else if prospect.interviewCompleted {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.success)
                        .font(.caption)
                    Text("Interview completed")
                        .font(.subheadline)
                        .foregroundStyle(Color.success)
                }
            }

            // Personal workout button (combine/draft phase, max 30)
            if canWorkout {
                Button {
                    performWorkout()
                } label: {
                    HStack {
                        Label("Invite for Workout", systemImage: "figure.run")
                            .foregroundStyle(Color.accentGold)
                        Spacer()
                        Text("Workouts: \(career.workoutsUsed)/30 used")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            } else if prospect.proDayCompleted {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.success)
                        .font(.caption)
                    Text("Workout/Pro Day completed")
                        .font(.subheadline)
                        .foregroundStyle(Color.success)
                }
            }

            if isScouted {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Color.success)
                    Text("Scouted (\(prospect.scoutingReports.count) report\(prospect.scoutingReports.count == 1 ? "" : "s"))")
                        .foregroundStyle(Color.success)
                }
            }
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    // MARK: - Helpers

    private var positionColor: Color {
        switch prospect.position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }

    private var heightLabel: String {
        let feet = prospect.height / 12
        let inches = prospect.height % 12
        return "\(feet)'\(inches)\""
    }

    private func projectionColor(_ round: Int) -> Color {
        switch round {
        case 1:    return .success
        case 2...3: return .accentGold
        case 4...5: return .warning
        default:   return .textSecondary
        }
    }

    /// Maps the career's current season phase to a scouting phase for report generation.
    private var currentScoutingPhase: ScoutingPhase {
        switch career.currentPhase {
        case .combine:
            return .combine
        case .freeAgency, .draft:
            return .proDay
        case .otas, .trainingCamp, .preseason, .rosterCuts:
            return .personalWorkout
        default:
            // Pre-combine phases: college season or senior bowl
            return .collegeSeason
        }
    }

    private func loadScouts() {
        guard let teamID = career.teamID else { return }
        let desc = FetchDescriptor<Scout>(predicate: #Predicate { $0.teamID == teamID })
        scouts = (try? modelContext.fetch(desc)) ?? []
    }

    private func loadCoaches() {
        guard let teamID = career.teamID else { return }
        let desc = FetchDescriptor<Coach>(predicate: #Predicate { $0.teamID == teamID })
        coaches = (try? modelContext.fetch(desc)) ?? []
    }

    private func performInterview() {
        // Use best scout's personalityRead or HC's motivation as interviewer quality
        let interviewerQuality: Int
        if let bestScout = scouts.max(by: { $0.personalityRead < $1.personalityRead }) {
            interviewerQuality = bestScout.personalityRead
        } else if let hc = coaches.first(where: { $0.role == .headCoach }) {
            interviewerQuality = hc.motivation
        } else {
            interviewerQuality = 50
        }

        let result = ScoutingEngine.conductInterview(
            prospect: prospect,
            interviewerQuality: interviewerQuality
        )
        interviewResult = result
        career.interviewsUsed += 1
        try? modelContext.save()
    }

    private func performWorkout() {
        ScoutingEngine.conductPersonalWorkout(
            prospect: prospect,
            coaches: coaches
        )
        career.workoutsUsed += 1
        try? modelContext.save()
    }
}

// MARK: - Supporting Views

private struct ProspectInfoPill: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.textPrimary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
        }
    }
}

private struct MeasurableRow: View {
    let label: String
    let value: String?

    var body: some View {
        LabeledContent(label) {
            Text(value ?? "—")
                .font(.body.monospacedDigit())
                .foregroundStyle(value != nil ? Color.textPrimary : Color.textTertiary)
        }
    }
}

private struct StatusPill: View {
    let label: String
    let completed: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(completed ? Color.success : Color.textTertiary)
                .font(.caption)
            Text(label)
                .font(.caption)
                .foregroundStyle(completed ? Color.textPrimary : Color.textTertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(completed ? Color.success.opacity(0.15) : Color.backgroundTertiary)
        )
        .accessibilityLabel("\(label) \(completed ? "completed" : "not completed")")
    }
}

private struct InterestBadge: View {
    let level: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: iconName)
                .foregroundStyle(badgeColor)
                .font(.caption)
            Text(level)
                .font(.caption.weight(.semibold))
                .foregroundStyle(badgeColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(badgeColor.opacity(0.15))
        )
    }

    private var iconName: String {
        switch level {
        case "Hot":     return "flame.fill"
        case "Warm":    return "thermometer.medium"
        case "Cold":    return "thermometer.snowflake"
        default:        return "questionmark.circle"
        }
    }

    private var badgeColor: Color {
        switch level {
        case "Hot":     return .danger
        case "Warm":    return .warning
        case "Cold":    return .accentBlue
        default:        return .textTertiary
        }
    }
}

// MARK: - Send Scout Sheet

private struct SendScoutSheet: View {
    let prospect: CollegeProspect
    let scouts: [Scout]
    let scoutingPhase: ScoutingPhase
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()

                if scouts.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "person.slash")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.textTertiary)
                        Text("No Scouts Available")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                        Text("Hire scouts from the Scout Team tab.")
                            .foregroundStyle(Color.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section {
                            HStack(spacing: 8) {
                                Image(systemName: "info.circle")
                                    .foregroundStyle(Color.accentGold)
                                Text("Phase: \(scoutingPhase.displayName) (Confidence: \(Int(scoutingPhase.confidenceLevel * 100))%)")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                        .listRowBackground(Color.backgroundSecondary)

                        Section("Select a Scout") {
                            ForEach(scouts) { scout in
                                Button {
                                    sendScout(scout)
                                } label: {
                                    ScoutRowView(scout: scout)
                                }
                                .listRowBackground(Color.backgroundSecondary)
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Send Scout to \(prospect.firstName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func sendScout(_ scout: Scout) {
        let report = ScoutingEngine.generateScoutReport(
            scout: scout,
            prospect: prospect,
            phase: scoutingPhase
        )
        ScoutingEngine.applyReport(report: report, to: prospect)
        dismiss()
    }
}


// MARK: - Preview

#Preview {
    NavigationStack {
        ProspectDetailView(
            career: Career(playerName: "John Doe", role: .gm, capMode: .simple),
            prospect: CollegeProspect(
                firstName: "Caleb", lastName: "Williams",
                college: "USC", position: .QB,
                age: 21, height: 74, weight: 214,
                truePositionAttributes: .quarterback(QBAttributes(
                    armStrength: 92, accuracyShort: 88, accuracyMid: 90,
                    accuracyDeep: 85, pocketPresence: 87, scrambling: 78
                )),
                truePersonality: PlayerPersonality(archetype: .fieryCompetitor, motivation: .winning),
                scoutedOverall: 89, scoutedPotential: 94,
                scoutedPersonality: .fieryCompetitor,
                scoutGrade: "A",
                fortyTime: 4.62, benchPress: 18, verticalJump: 33.5,
                broadJump: 118, shuttleTime: 4.24, coneDrill: 6.87,
                interviewCompleted: true, proDayCompleted: false,
                draftProjection: 1
            )
        )
    }
    .modelContainer(for: [Career.self, Scout.self, CollegeProspect.self], inMemory: true)
}
