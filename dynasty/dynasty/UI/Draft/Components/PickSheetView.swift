import SwiftUI

struct PickSheetView: View {
    @ObservedObject var coordinator: DraftDayCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var showComparison: Bool = false

    /// Prospect awaiting draft confirmation. Every draft surface routes
    /// through this so a stray tap can't burn a pick instantly.
    @State private var pendingProspect: CollegeProspect? = nil

    private var showDraftConfirm: Binding<Bool> {
        Binding(
            get: { pendingProspect != nil },
            set: { if !$0 { pendingProspect = nil } }
        )
    }

    /// Commits the confirmed pick.
    private func draftPendingProspect() {
        guard let prospect = pendingProspect else { return }
        pendingProspect = nil
        coordinator.selectProspect(prospect)
        dismiss()
    }

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

                // R24 — a pending offer surfaces inside the sheet (the
                // main-view banner is hidden behind this modal).
                if let offer = coordinator.pendingTradeOffer {
                    TradeOfferBanner(
                        motive: offer.motive,
                        outgoing: offer.givesLabel(currentSeason: coordinator.draftYear),
                        incoming: offer.getsLabel(currentSeason: coordinator.draftYear),
                        gmLine: "\(offer.gmName) · \(offer.gmStyle)",
                        valueSummary: "Chart value: you send \(offer.userGivesValue) pts · receive \(offer.userGetsValue) pts",
                        onAccept: { coordinator.acceptTradeOffer() },
                        onDecline: { coordinator.declineTradeOffer() }
                    )
                    .frame(maxWidth: .infinity)
                }

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
            .alert(
                "Confirm Pick",
                isPresented: showDraftConfirm,
                presenting: pendingProspect
            ) { prospect in
                Button("Draft \(prospect.lastName)") { draftPendingProspect() }
                Button("Cancel", role: .cancel) { pendingProspect = nil }
            } message: { prospect in
                Text("\(prospect.position.rawValue) \(prospect.firstName) \(prospect.lastName) — \(ProspectFog.read(prospect).labelledText) · \(prospect.college)")
            }
            // Presented from here rather than from `DraftDayView` because this
            // sheet is already up when the user is on the clock, and one view
            // can only present one sheet at a time.
            .sheet(isPresented: Binding(
                get: { coordinator.isTradeUpBoardOpen },
                set: { if !$0 { coordinator.closeTradeUpBoard() } }
            )) {
                TradeUpBoardSheet(coordinator: coordinator)
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
            pendingProspect = prospect
        } label: {
            HStack(spacing: DSSpacing.sm) {
                PersonFaceView(prospect: prospect, size: .small)

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
                    HStack(spacing: 4) {
                        Text("\(prospect.position.rawValue) · \(prospect.college)")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                        // The confidence stars are the band width now — a
                        // single "B+" is a converged read, "C+/A-" is a class
                        // your scouts have barely opened.
                        ProspectGradeBand(prospect: prospect, alignment: .leading, font: .caption.monospaced().weight(.heavy))
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                        ProductionMicroLabel(tier: prospect.collegeProductionTier, fontSize: 9)
                    }
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
            PersonFaceView(prospect: prospect, size: .small)

            Text("\(prospect.firstName) \(prospect.lastName)")
                .font(.callout.weight(.bold))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(2)
            HStack(spacing: 4) {
                ProspectGradeBand(prospect: prospect, alignment: .leading, font: .caption.monospaced().weight(.heavy))
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
                Text("Production")
                    .font(.caption2)
                    .foregroundStyle(Color.textSecondary)
                Text(prospect.collegeProductionTier.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(prospect.collegeProductionTier.chipColor)
                // Measurables are public the moment a man runs them in front of
                // 32 clubs — but only then. A prospect with no combine invite,
                // no pro day and no report filed has none the user could know.
                let hasMeasurables = ProspectFog.showsMeasurables(prospect)
                Text("Speed")
                    .font(.caption2)
                    .foregroundStyle(Color.textSecondary)
                Text(hasMeasurables ? "\(prospect.truePhysical.speed)" : "—")
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(hasMeasurables ? Color.textPrimary : Color.textTertiary)
                Text("Strength")
                    .font(.caption2)
                    .foregroundStyle(Color.textSecondary)
                Text(hasMeasurables ? "\(prospect.truePhysical.strength)" : "—")
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(hasMeasurables ? Color.textPrimary : Color.textTertiary)
                Text("Agility")
                    .font(.caption2)
                    .foregroundStyle(Color.textSecondary)
                Text(hasMeasurables ? "\(prospect.truePhysical.agility)" : "—")
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(hasMeasurables ? Color.textPrimary : Color.textTertiary)
            }
            Button {
                pendingProspect = prospect
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
                    coordinator.requestTradeDown()
                } label: {
                    Label("Trade Down", systemImage: "arrow.down.right.circle.fill")
                        .font(.callout.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(Color.accentGold)
                .disabled(coordinator.pendingTradeOffer != nil)
                // Wave 4: the pick sheet is the second entry point into the
                // move-up call sheet (the big board is the first). From the
                // clock it prices the slots ahead of the user's NEXT turn.
                Button {
                    coordinator.openTradeUpBoard()
                } label: {
                    Label("Call About Moving Up", systemImage: "arrow.up.right.circle.fill")
                        .font(.callout.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(Color.draftStealGold)
                .disabled(coordinator.pendingTradeOffer != nil)
                Spacer()
            }
            if let feedback = coordinator.tradeDownMessage {
                Text(feedback)
                    .font(.caption2)
                    .foregroundStyle(Color.warning)
            } else if coordinator.pendingTradeOffer == nil {
                Text("Shop this pick to teams behind you — interest rises when top prospects are still on the board. Or call ahead and pay a rival GM's price to move up.")
                    .font(.caption2)
                    .foregroundStyle(Color.textSecondary)
            }
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
        // Deterministic ordering with a position tiebreaker — dictionary
        // iteration order + OVR ties made the chips visibly reshuffle on
        // every clock tick, which caused mis-taps on an instant-draft UI.
        let entries = topByPosition
            .sorted {
                // Ordered by the fogged band, not by the hidden overall — the
                // strip used to rank the whole class for the user for free.
                let lhs = ProspectFog.rank($0.value)
                let rhs = ProspectFog.rank($1.value)
                if lhs != rhs { return lhs > rhs }
                return $0.key.rawValue < $1.key.rawValue
            }
            .prefix(8)
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
            pendingProspect = prospect
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(position.rawValue)
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(Color.accentGold)
                Text("\(prospect.firstName.prefix(1)). \(prospect.lastName)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                HStack(spacing: 4) {
                    ProspectGradeBand(prospect: prospect, alignment: .leading, font: .caption2.monospaced().weight(.heavy))
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
        // Same public OVR the coordinator grades the finished pick on
        // (`DraftDayCoordinator.computePickGrade`, #33 OSA B): the scouted
        // consensus, falling back to the hidden value only for a prospect
        // nobody in the league has seen. Feeding `trueOverall` in here made the
        // *preview* grade sharper than the grade the pick would actually get.
        let inputs = PickGradeCalculator.Inputs(
            valueDelta: valueDelta,
            needScore: needScore,
            publicOVR: prospect.scoutedOverall ?? prospect.trueOverall,
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
}
