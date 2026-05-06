import SwiftUI

struct PickSheetView: View {
    @ObservedObject var coordinator: DraftDayCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var showComparison: Bool = false

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

                bestByPositionStrip
                    .padding(.bottom, DSSpacing.xs)

                if showComparison {
                    comparisonView
                } else {
                    ScrollView {
                        LazyVStack(spacing: DSSpacing.xs) {
                            ForEach(topProspects, id: \.id) { prospect in
                                prospectButton(prospect)
                            }
                        }
                    }
                }

                tradeActionRow
            }
            .padding(DSSpacing.lg)
            .background(Color.backgroundPrimary)
            .navigationTitle("Make Your Pick")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showComparison.toggle()
                    } label: {
                        Label(showComparison ? "List" : "Compare",
                              systemImage: showComparison ? "list.bullet" : "rectangle.split.3x1")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    // MARK: - Top Prospects List

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
        let showReachWarning: Bool = {
            guard let bb = bbRank else { return false }
            return (preview.grade == .reach || preview.grade == .bigReach) && (pickNumber - bb) >= 4
        }()

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
                    if showReachWarning {
                        Text("⚠️ Position not a top need")
                            .font(.caption2)
                            .foregroundStyle(Color.warning)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    gradeChip(preview.grade)
                    if let bb = bbRank {
                        Text("BB #\(bb) · \(reachLabel(grade: preview.grade, bb: bb, pick: pickNumber))")
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

    // MARK: - Side-by-side Comparison

    private var comparisonView: some View {
        let top3 = Array(topProspects.prefix(3))
        return ScrollView {
            HStack(alignment: .top, spacing: DSSpacing.sm) {
                ForEach(top3, id: \.id) { prospect in
                    comparisonCard(prospect)
                }
                if top3.count < 3 {
                    Spacer()
                }
            }
        }
    }

    private func comparisonCard(_ prospect: CollegeProspect) -> some View {
        let bbRank = coordinator.publicBoardRanks[prospect.id]
        let pickNumber = coordinator.currentPick?.pickNumber ?? 0
        let needScore = coordinator.teamNeedScores[prospect.position] ?? 0.2
        let preview = pickGradePreview(prospect: prospect, bbRank: bbRank, pickNumber: pickNumber, needScore: needScore)

        return VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text("\(prospect.firstName) \(prospect.lastName)")
                .font(.callout.weight(.bold))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(2)
            HStack(spacing: 4) {
                Text("OVR \(prospect.trueOverall)")
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text("·")
                    .foregroundStyle(Color.textSecondary)
                Text(prospect.position.rawValue)
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(Color.accentGold)
            }
            if let bb = bbRank {
                Text("Big Board #\(bb)")
                    .font(.caption2)
                    .foregroundStyle(Color.textSecondary)
            }
            gradeChip(preview.grade)
            if needScore >= 0.7 {
                Text("NEED")
                    .font(.caption2.weight(.heavy))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Color.draftStealGold.opacity(0.25))
                    .foregroundStyle(Color.draftStealGold)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            Divider().overlay(Color.surfaceBorder)
            VStack(alignment: .leading, spacing: 2) {
                Text("Speed")
                    .font(.caption2)
                    .foregroundStyle(Color.textSecondary)
                Text("\(prospect.truePhysical.speed)")
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text("Strength")
                    .font(.caption2)
                    .foregroundStyle(Color.textSecondary)
                Text("\(prospect.truePhysical.strength)")
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text("Agility")
                    .font(.caption2)
                    .foregroundStyle(Color.textSecondary)
                Text("\(prospect.truePhysical.agility)")
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
            }
            Button {
                coordinator.selectProspect(prospect)
                dismiss()
            } label: {
                Text("DRAFT")
                    .font(.caption.weight(.heavy))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.accentGold)
                    .foregroundStyle(Color.backgroundPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: DSCornerRadius.inline))
            }
            .buttonStyle(.plain)
        }
        .padding(DSSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
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

    // MARK: - Trade Action Row

    private var tradeActionRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: DSSpacing.sm) {
                Button {
                    // Placeholder: AI must propose first
                } label: {
                    Label("Trade Up", systemImage: "arrow.up.right.circle.fill")
                        .font(.callout.weight(.semibold))
                }
                .disabled(true)

                Button {
                    // Placeholder: AI must propose first
                } label: {
                    Label("Trade Down", systemImage: "arrow.down.right.circle.fill")
                        .font(.callout.weight(.semibold))
                }
                .disabled(true)
                Spacer()
            }
            Text("Trade offers come from rival GMs — watch the Trade Radar in the War Room.")
                .font(.caption2)
                .foregroundStyle(Color.textSecondary)
        }
        .padding(.horizontal, DSSpacing.lg)
        .padding(.vertical, DSSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                .fill(Color.backgroundSecondary.opacity(0.5))
        )
    }

    // MARK: - Best By Position Strip

    private var bestByPositionStrip: some View {
        let topByPosition = computeTopByPosition()
        let entries = topByPosition.sorted { $0.value.trueOverall > $1.value.trueOverall }.prefix(8)
        return VStack(alignment: .leading, spacing: 4) {
            Text("BEST AVAILABLE BY POSITION")
                .font(.caption2.weight(.heavy))
                .foregroundStyle(Color.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DSSpacing.xs) {
                    ForEach(Array(entries), id: \.key) { entry in
                        positionPick(entry.value, position: entry.key)
                    }
                }
            }
        }
    }

    private func computeTopByPosition() -> [Position: CollegeProspect] {
        var result: [Position: CollegeProspect] = [:]
        let sorted = coordinator.availableProspects.sorted {
            (coordinator.publicBoardRanks[$0.id] ?? 999) <
            (coordinator.publicBoardRanks[$1.id] ?? 999)
        }
        for prospect in sorted {
            if result[prospect.position] == nil {
                result[prospect.position] = prospect
            }
        }
        return result
    }

    private func positionPick(_ prospect: CollegeProspect, position: Position) -> some View {
        Button {
            coordinator.selectProspect(prospect)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(position.rawValue)
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(Color.accentGold)
                Text("\(prospect.firstName.prefix(1)). \(prospect.lastName)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                HStack(spacing: 4) {
                    Text("OVR \(prospect.trueOverall)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(Color.textSecondary)
                    if (coordinator.teamNeedScores[position] ?? 0) >= 0.7 {
                        Text("•").foregroundStyle(Color.draftStealGold)
                        Text("NEED")
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(Color.draftStealGold)
                    }
                }
            }
            .padding(.horizontal, DSSpacing.sm)
            .padding(.vertical, DSSpacing.xs)
            .background(
                RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                    .fill(Color.backgroundTertiary)
                    .overlay(
                        RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                            .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

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

    private func reachLabel(grade: PickGrade, bb: Int, pick: Int) -> String {
        let delta = pick - bb
        switch grade {
        case .reach, .bigReach:
            return delta >= 4 ? "VALUE +\(delta)" : "REACH \(delta)"
        case .stealAPlus, .hofTrack:
            return delta >= 4 ? "STEAL +\(delta)" : "FAIR"
        default:
            if delta >= 4 { return "STEAL +\(delta)" }
            if delta <= -4 { return "REACH \(delta)" }
            return "FAIR"
        }
    }

    private func stars(_ prospect: CollegeProspect) -> String {
        let n = DraftIntel.scoutConfidence(for: prospect)
        return String(repeating: "★", count: n)
    }
}
