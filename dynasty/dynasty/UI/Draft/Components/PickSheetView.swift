import SwiftUI

struct PickSheetView: View {
    @ObservedObject var coordinator: DraftDayCoordinator
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                if let pick = coordinator.currentPick {
                    Text("Pick #\(pick.pickNumber) (Round \(pick.round))")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color.textPrimary)
                    Text("⏱ \(coordinator.clockSeconds) seconds remaining")
                        .font(.callout)
                        .foregroundStyle(coordinator.clockSeconds <= 30 ? Color.draftClockUrgent : Color.textSecondary)
                }
                Divider().overlay(Color.surfaceBorder)
                ScrollView {
                    LazyVStack(spacing: DSSpacing.xs) {
                        ForEach(topProspects, id: \.id) { prospect in
                            prospectButton(prospect)
                        }
                    }
                }
            }
            .padding(DSSpacing.lg)
            .background(Color.backgroundPrimary)
            .navigationTitle("Make Your Pick")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var topProspects: [CollegeProspect] {
        Array(
            coordinator.availableProspects
                .sorted {
                    (coordinator.publicBoardRanks[$0.id] ?? 999) <
                    (coordinator.publicBoardRanks[$1.id] ?? 999)
                }
                .prefix(20)
        )
    }

    private func prospectButton(_ prospect: CollegeProspect) -> some View {
        let bbRank = coordinator.publicBoardRanks[prospect.id]
        let pickNumber = coordinator.currentPick?.pickNumber ?? 0
        let needScore = coordinator.teamNeedScores[prospect.position] ?? 0.2
        let preview = pickGradePreview(prospect: prospect, bbRank: bbRank, pickNumber: pickNumber, needScore: needScore)

        return Button {
            coordinator.selectProspect(prospect)
            dismiss()
        } label: {
            HStack(spacing: DSSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("\(prospect.firstName) \(prospect.lastName)")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                        if needScore >= 0.7 {
                            Text("NEED")
                                .font(.caption2.weight(.heavy))
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Color.draftStealGold.opacity(0.25))
                                .foregroundStyle(Color.draftStealGold)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }
                    Text("\(prospect.position.rawValue) · \(prospect.college) · OVR \(prospect.trueOverall) · \(stars(prospect))")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    gradeChip(preview.grade)
                    if let bb = bbRank {
                        Text("BB #\(bb) · \(reachLabel(bb: bb, pick: pickNumber))")
                            .font(.caption2)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
            .padding(DSSpacing.sm)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: DSCornerRadius.card)
                    .fill(Color.backgroundSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: DSCornerRadius.card)
                            .strokeBorder(borderColor(for: preview.grade),
                                          lineWidth: preview.isGemCandidate ? 2 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func pickGradePreview(prospect: CollegeProspect, bbRank: Int?, pickNumber: Int, needScore: Double) -> PickGradeCalculator.Output {
        let valueDelta = pickNumber - (bbRank ?? pickNumber)
        let inputs = PickGradeCalculator.Inputs(
            valueDelta: valueDelta,
            needScore: needScore,
            publicOVR: prospect.trueOverall,
            schemeFit: 0.6
        )
        return PickGradeCalculator.compute(inputs)
    }

    private func gradeChip(_ grade: PickGrade) -> some View {
        Text(grade.rawValue)
            .font(.caption.weight(.heavy))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(Color.textPrimary)
            .background(gradeColor(grade))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func gradeColor(_ grade: PickGrade) -> Color {
        switch grade {
        case .stealAPlus, .hofTrack: return Color.draftStealGold
        case .smartA:                return Color.success
        case .solid:                 return Color.draftSolidNeutral
        case .reach:                 return Color.warning
        case .bigReach:              return Color.draftReachRed
        }
    }

    private func borderColor(for grade: PickGrade) -> Color {
        switch grade {
        case .stealAPlus, .hofTrack: return Color.draftStealGold
        case .smartA:                return Color.success.opacity(0.6)
        case .reach, .bigReach:      return Color.draftReachRed.opacity(0.6)
        default:                     return Color.surfaceBorder
        }
    }

    private func reachLabel(bb: Int, pick: Int) -> String {
        let delta = pick - bb
        if delta >= 4  { return "STEAL +\(delta)" }
        if delta <= -4 { return "REACH \(delta)" }
        return "FAIR"
    }

    private func stars(_ prospect: CollegeProspect) -> String {
        let n = DraftIntel.scoutConfidence(for: prospect)
        return String(repeating: "★", count: n)
    }
}
