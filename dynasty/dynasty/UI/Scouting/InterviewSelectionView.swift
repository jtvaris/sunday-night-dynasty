import SwiftUI
import SwiftData

/// Allows the player to select combine-invited prospects for batch interviews.
/// After conducting interviews, reveals personality, football IQ, and character notes.
struct InterviewSelectionView: View {
    let career: Career
    @Environment(\.modelContext) private var modelContext

    @State private var selectedProspectIDs: Set<UUID> = []
    @State private var prospects: [CollegeProspect] = []
    @State private var showResults = false
    @State private var interviewResults: [InterviewResult] = []
    @State private var positionFilter: Position?

    private let maxInterviews = 60

    private var remainingSlots: Int {
        max(0, maxInterviews - career.interviewsUsed)
    }

    private var selectableProspects: [CollegeProspect] {
        var filtered = prospects
            .filter { $0.combineInvite && !$0.interviewCompleted }
        if let pos = positionFilter {
            filtered = filtered.filter { $0.position == pos }
        }
        return filtered.sorted { ($0.draftProjection ?? 999) < ($1.draftProjection ?? 999) }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.surfaceBorder.opacity(0.6))

            if showResults {
                InterviewReportView(results: interviewResults) {
                    showResults = false
                    interviewResults = []
                    loadProspects()
                }
            } else if remainingSlots == 0 {
                allInterviewsUsedView
            } else {
                selectionList
            }
        }
        .onAppear { loadProspects() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("PROSPECT INTERVIEWS")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Color.accentGold)
                    .tracking(0.5)

                Spacer()

                Text("\(career.interviewsUsed)/\(maxInterviews) used")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.textSecondary)
            }

            HStack(spacing: 8) {
                Text("Selected: \(selectedProspectIDs.count)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.textSecondary)

                Text("\u{2022}")
                    .foregroundStyle(Color.textTertiary)

                Text("\(remainingSlots) remaining")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(remainingSlots < 10 ? Color.danger : Color.textSecondary)

                Spacer()

                positionFilterMenu
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var positionFilterMenu: some View {
        Menu {
            Button("All Positions") { positionFilter = nil }
            Divider()
            ForEach(Position.allCases, id: \.self) { pos in
                Button(pos.rawValue) { positionFilter = pos }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 12))
                Text(positionFilter?.rawValue ?? "All")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(Color.accentGold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.accentGold.opacity(0.12)))
        }
    }

    // MARK: - Selection List

    private var selectionList: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(selectableProspects) { prospect in
                        prospectRow(prospect)
                        Divider().overlay(Color.surfaceBorder.opacity(0.3))
                    }
                }
                .padding(.horizontal, 16)
            }

            conductButton
        }
    }

    private func prospectRow(_ prospect: CollegeProspect) -> some View {
        let isSelected = selectedProspectIDs.contains(prospect.id)
        let canSelect = isSelected || selectedProspectIDs.count < remainingSlots

        return Button {
            if isSelected {
                selectedProspectIDs.remove(prospect.id)
            } else if canSelect {
                selectedProspectIDs.insert(prospect.id)
            }
        } label: {
            HStack(spacing: 12) {
                // Checkbox
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? Color.accentGold : Color.textTertiary)

                // Prospect info
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(prospect.firstName) \(prospect.lastName)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)

                    HStack(spacing: 6) {
                        Text(prospect.position.rawValue)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.accentGold)

                        Text(prospect.college)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                Spacer()

                // Draft projection
                if let proj = prospect.draftProjection {
                    VStack(spacing: 1) {
                        Text("Proj")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(Color.textTertiary)
                        Text("#\(proj)")
                            .font(.system(size: 13, weight: .bold).monospacedDigit())
                            .foregroundStyle(Color.textPrimary)
                    }
                }

                // Scouted overall
                if let ovr = prospect.scoutedOverall {
                    VStack(spacing: 1) {
                        Text("OVR")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(Color.textTertiary)
                        Text("\(ovr)")
                            .font(.system(size: 13, weight: .bold).monospacedDigit())
                            .foregroundStyle(overallColor(ovr))
                    }
                }

                // Scout grade
                if let grade = prospect.scoutGrade {
                    Text(grade)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(gradeColor(grade))
                        .frame(width: 30)
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(canSelect || isSelected ? 1.0 : 0.4)
    }

    private var conductButton: some View {
        Button {
            conductInterviews()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 14, weight: .bold))
                Text("Conduct \(selectedProspectIDs.count) Interview\(selectedProspectIDs.count == 1 ? "" : "s")")
                    .font(.system(size: 15, weight: .bold))
            }
            .foregroundStyle(selectedProspectIDs.isEmpty ? Color.textTertiary : Color.backgroundPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selectedProspectIDs.isEmpty ? Color.backgroundTertiary : Color.accentGold)
            )
        }
        .disabled(selectedProspectIDs.isEmpty)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - All Used View

    private var allInterviewsUsedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.success)

            Text("All Interview Slots Used")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.textPrimary)

            Text("You've used all \(maxInterviews) interviews this combine.")
                .font(.system(size: 14))
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Interview Logic

    private func conductInterviews() {
        var results: [InterviewResult] = []

        for prospectID in selectedProspectIDs {
            guard let prospect = prospects.first(where: { $0.id == prospectID }) else { continue }

            // Reveal personality
            let personality = prospect.truePersonality.archetype

            // Generate football IQ (correlated with true mental attributes)
            let baseIQ = (prospect.trueMental.awareness + prospect.trueMental.decisionMaking) / 2
            let iq = max(30, min(99, baseIQ + Int.random(in: -5...5)))

            // Generate character notes
            let notes = generateCharacterNotes(prospect: prospect, personality: personality)

            // Update prospect model
            prospect.interviewCompleted = true
            prospect.scoutedPersonality = personality
            prospect.interviewFootballIQ = iq
            prospect.interviewCharacterNotes = notes
            prospect.interviewNotes = "Personality: \(personality.displayName). Football IQ: \(iq). \(notes.joined(separator: " "))"

            results.append(InterviewResult(
                prospect: prospect,
                personality: personality,
                footballIQ: iq,
                notes: notes
            ))
        }

        // Update career
        career.interviewsUsed += selectedProspectIDs.count

        try? modelContext.save()

        selectedProspectIDs.removeAll()
        interviewResults = results
        showResults = true
    }

    private func generateCharacterNotes(prospect: CollegeProspect, personality: PersonalityArchetype) -> [String] {
        var notes: [String] = []

        // Personality-based notes
        switch personality {
        case .teamLeader:
            notes.append("Natural leader \u{2014} teammates gravitate to him.")
        case .loneWolf:
            notes.append("Keeps to himself. Doesn't engage much with teammates.")
        case .feelPlayer:
            notes.append("Plays by instinct. Can be brilliant but inconsistent.")
        case .steadyPerformer:
            notes.append("Even-keeled personality. Consistent day in, day out.")
        case .dramaQueen:
            notes.append("High-maintenance personality. Wants to be the center of attention.")
        case .quietProfessional:
            notes.append("Very professional. Does his work without fanfare.")
        case .mentor:
            notes.append("Mature beyond his years. Already helping younger players.")
        case .fieryCompetitor:
            notes.append("Extremely competitive. Could be an issue in the locker room.")
        case .classClown:
            notes.append("Fun personality but can be a distraction at times.")
        }

        // Football IQ note
        let baseIQ = (prospect.trueMental.awareness + prospect.trueMental.decisionMaking) / 2
        if baseIQ >= 80 {
            notes.append("Exceptional football intelligence. Picks up concepts quickly.")
        } else if baseIQ >= 65 {
            notes.append("Solid understanding of the game. Should adapt well.")
        } else if baseIQ < 50 {
            notes.append("Concerns about his ability to handle a complex playbook.")
        }

        // Random character flag
        let flagRoll = Int.random(in: 0...100)
        if flagRoll < 10 {
            notes.append("\u{1F6A9} Off-field concerns reported by multiple sources.")
        } else if flagRoll < 25 {
            notes.append("\u{2705} Exemplary character. Community involvement noted.")
        }

        return notes
    }

    // MARK: - Helpers

    private func loadProspects() {
        prospects = WeekAdvancer.currentDraftClass
    }

    private func overallColor(_ ovr: Int) -> Color {
        if ovr >= 80 { return Color.success }
        if ovr >= 65 { return Color.accentGold }
        if ovr >= 50 { return Color.warning }
        return Color.danger
    }

    private func gradeColor(_ grade: String) -> Color {
        if grade.hasPrefix("A") { return Color.success }
        if grade.hasPrefix("B") { return Color.accentGold }
        if grade.hasPrefix("C") { return Color.warning }
        return Color.danger
    }
}

// MARK: - Interview Result Model

struct InterviewResult: Identifiable {
    let id = UUID()
    let prospect: CollegeProspect
    let personality: PersonalityArchetype
    let footballIQ: Int
    let notes: [String]
}

// MARK: - Interview Report View

struct InterviewReportView: View {
    let results: [InterviewResult]
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("INTERVIEW REPORT")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Color.accentGold)
                    .tracking(0.5)

                Spacer()

                Text("\(results.count) interview\(results.count == 1 ? "" : "s")")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider().overlay(Color.surfaceBorder.opacity(0.6))

            // Results
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(results) { result in
                        resultCard(result)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

            // Dismiss button
            Button {
                onDismiss()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text("Complete Review")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(Color.backgroundPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.accentGold)
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func resultCard(_ result: InterviewResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Name, position, college, projection
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("\(result.prospect.firstName) \(result.prospect.lastName)")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.textPrimary)

                        Text(result.prospect.position.rawValue)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.accentGold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentGold.opacity(0.15)))
                    }

                    HStack(spacing: 6) {
                        Text(result.prospect.college)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.textSecondary)
                        if let proj = result.prospect.draftProjection {
                            Text("Proj #\(proj)")
                                .font(.system(size: 11, weight: .medium).monospacedDigit())
                                .foregroundStyle(Color.textTertiary)
                        }
                    }
                }

                Spacer()
            }

            // Personality and IQ
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(personalityColor(result.personality))
                    Text(result.personality.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(personalityColor(result.personality))
                }

                HStack(spacing: 4) {
                    Image(systemName: "brain.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(iqColor(result.footballIQ))
                    Text("Football IQ: \(result.footballIQ)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(iqColor(result.footballIQ))
                }
            }

            // Character notes
            ForEach(result.notes, id: \.self) { note in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: noteIcon(note))
                        .font(.system(size: 9))
                        .foregroundStyle(noteColor(note))
                        .frame(width: 12)
                        .padding(.top, 2)
                    Text(note)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.surfaceBorder.opacity(0.3))
                )
        )
    }

    private func personalityColor(_ p: PersonalityArchetype) -> Color {
        switch p {
        case .teamLeader, .mentor, .quietProfessional, .steadyPerformer:
            return Color.success
        case .dramaQueen, .loneWolf:
            return Color.danger
        default:
            return Color.warning
        }
    }

    private func iqColor(_ iq: Int) -> Color {
        if iq >= 80 { return Color.success }
        if iq >= 60 { return Color.accentGold }
        if iq >= 45 { return Color.warning }
        return Color.danger
    }

    private func noteIcon(_ note: String) -> String {
        if note.contains("\u{1F6A9}") { return "exclamationmark.triangle.fill" }
        if note.contains("\u{2705}") { return "checkmark.seal.fill" }
        return "quote.bubble.fill"
    }

    private func noteColor(_ note: String) -> Color {
        if note.contains("\u{1F6A9}") { return Color.danger }
        if note.contains("\u{2705}") { return Color.success }
        return Color.textTertiary
    }
}
