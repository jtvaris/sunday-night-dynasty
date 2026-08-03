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

    /// The twenty names the sheet offers, in MEDIA board order.
    ///
    /// This list used to be ordered by `publicBoardRanks` when that map was
    /// `scoutedOverall ?? trueOverall` — so for every prospect the user had not
    /// scouted, the hidden rating decided where he appeared in the list he was
    /// picking from. The order was a bigger leak than any number on the row.
    /// Your own read is on each row (the grade band); the ORDER is the room's.
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
        let valueDelta = DraftIntel.pickValueDelta(for: prospect, pickNumber: pickNumber, consensusRank: bbRank)
        let preview = pickGradePreview(prospect: prospect, valueDelta: valueDelta, needScore: needScore)
        // Graded a reach even though the board says he is fair value here —
        // i.e. the reach is coming from need, not from value.
        let showReachWarning = (preview.grade == .reach || preview.grade == .bigReach) && valueDelta >= 4
        let mark = DraftIntel.mark(for: prospect)

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
                        // His own mark from the scouting board, on the screen
                        // where it finally decides something.
                        if let mark {
                            Label(mark.shortLabel, systemImage: mark.icon)
                                .labelStyle(.titleAndIcon)
                                .font(.caption2.weight(.heavy))
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(mark.color.opacity(0.22))
                                .foregroundStyle(mark.color)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
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
                        Text("BB #\(bb) · \(reachLabel(grade: preview.grade, delta: valueDelta))")
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
        let valueDelta = DraftIntel.pickValueDelta(for: prospect, pickNumber: pickNumber, consensusRank: bbRank)
        let preview = pickGradePreview(prospect: prospect, valueDelta: valueDelta, needScore: needScore)

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

    /// One name per position, taken in MEDIA board order — the same reason
    /// `topProspects` is: picking the "best" at a position off a board that
    /// fell back to `trueOverall` handed the user the hidden answer for every
    /// prospect his scouts had never seen.
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

    /// `valueDelta` comes from `DraftIntel.pickValueDelta` — the same helper the
    /// coordinator grades the finished pick with, so the preview chip and the
    /// grade the pick actually receives can never disagree.
    private func pickGradePreview(prospect: CollegeProspect, valueDelta: Int, needScore: Double) -> PickGradeCalculator.Output {
        // Same public OVR the coordinator grades the finished pick on
        // (`DraftDayCoordinator.computePickGrade`): `DraftIntel
        // .publicOVREstimate` — your scouts' number, or the media band for his
        // projected round. The old `?? trueOverall` fallback leaked the hidden
        // rating into the STEAL / HOF-TRACK chip for every man your own
        // department had not filed on, which from season 2 is most of the board.
        let inputs = PickGradeCalculator.Inputs(
            valueDelta: valueDelta,
            needScore: needScore,
            publicOVR: DraftIntel.publicOVREstimate(for: prospect),
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

    private func reachLabel(grade: PickGrade, delta: Int) -> String {
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
