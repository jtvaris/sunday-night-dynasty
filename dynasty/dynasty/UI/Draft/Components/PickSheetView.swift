import SwiftUI

struct PickSheetView: View {
    @ObservedObject var coordinator: DraftDayCoordinator
    @Environment(\.dismiss) private var dismiss

    /// Prospect awaiting draft confirmation. Every draft surface routes
    /// through this so a stray tap can't burn a pick instantly.
    @State private var pendingProspect: CollegeProspect? = nil

    // MARK: - Browsing the board (search + scope + depth)

    /// Which board the list is showing. The media's order is the default —
    /// it is the room's opinion and the one the value chips are graded against
    /// — but the user's own board is one tap away, in the order he left it.
    enum BoardScope: String, CaseIterable {
        case media = "Board"
        case mine  = "My Board"
    }

    @State private var boardScope: BoardScope = .media
    @State private var searchText: String = ""
    /// Off: the top 20, which is all anyone reads at pick 12. On: the whole
    /// board, which is the only way to find a man in round six.
    @State private var showsFullBoard: Bool = false
    @State private var positionFilter: Position? = nil

    // MARK: - Compare (the user picks who)

    /// Ids the user has ticked for comparison. Was a fixed "top three of the
    /// media board", i.e. a compare of three men he had not chosen.
    @State private var compareIDs: [UUID] = []
    @State private var isPickingCompare: Bool = false
    @State private var showCompareSheet: Bool = false

    /// The man whose scouting card is open.
    @State private var cardProspect: CollegeProspect? = nil

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

                // Each of the three sheets this screen can raise is attached to
                // a DIFFERENT subview on purpose: stacking three `.sheet`
                // modifiers on one view is the same trap `DraftDayView` already
                // documents — only one of them would ever present.
                browseBar
                    .sheet(isPresented: $showCompareSheet) {
                        // The scouting screens' compare, unchanged: it reads
                        // every value through `ProspectFog`, so nothing the user
                        // has not earned can leak out of a side-by-side taken at
                        // the clock.
                        if compareSelection.count >= 2 {
                            ProspectCompareSheet(
                                career: coordinator.careerRef,
                                prospects: compareSelection,
                                onDismiss: { showCompareSheet = false }
                            )
                        }
                    }

                if isPickingCompare {
                    compareBar
                }

                ScrollView {
                    LazyVStack(spacing: DSSpacing.xs) {
                        if listedProspects.isEmpty {
                            Text(searchText.isEmpty
                                 ? "Nobody left matching that filter."
                                 : "No prospect matches \u{201C}\(searchText)\u{201D}.")
                                .font(.caption)
                                .foregroundStyle(Color.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, DSSpacing.md)
                        }
                        ForEach(listedProspects, id: \.id) { prospect in
                            prospectRow(prospect)
                        }
                        if !showsFullBoard && searchText.isEmpty && truncatedCount > 0 {
                            Button {
                                showsFullBoard = true
                            } label: {
                                Text("Show all \(scopePool.count) on the board")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.accentGold)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, DSSpacing.sm)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .sheet(item: $cardProspect) { prospect in
                    NavigationStack {
                        // Read-only on the clock — see `isLiveDraftCard`.
                        ProspectDetailView(
                            career: coordinator.careerRef,
                            prospect: prospect,
                            isLiveDraftCard: true
                        )
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button("Close") { cardProspect = nil }
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
                        isPickingCompare.toggle()
                        if !isPickingCompare { compareIDs.removeAll() }
                    } label: {
                        Label(isPickingCompare ? "Cancel Compare" : "Compare",
                              systemImage: isPickingCompare ? "xmark.circle" : "rectangle.split.3x1")
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

    // MARK: - Browse bar (search · scope · position)

    private var browseBar: some View {
        VStack(spacing: DSSpacing.xs) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                TextField("Search name, position or college", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .foregroundStyle(Color.textPrimary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, DSSpacing.sm)
            .padding(.vertical, DSSpacing.xs)
            .background(
                RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                    .fill(Color.backgroundSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                            .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                    )
            )

            HStack(spacing: DSSpacing.xs) {
                Picker("Board", selection: $boardScope) {
                    ForEach(BoardScope.allCases, id: \.self) { scope in
                        Text(scope.rawValue).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)

                Menu {
                    Button("All positions") { positionFilter = nil }
                    ForEach(Position.allCases, id: \.self) { pos in
                        Button(pos.rawValue) { positionFilter = pos }
                    }
                } label: {
                    Label(positionFilter?.rawValue ?? "All", systemImage: "line.3.horizontal.decrease.circle")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, DSSpacing.xs)
                        .padding(.vertical, 5)
                        .background(Color.backgroundSecondary)
                        .foregroundStyle(positionFilter == nil ? Color.textSecondary : Color.accentGold)
                        .clipShape(RoundedRectangle(cornerRadius: DSCornerRadius.inline))
                }

                Spacer()

                Text(boardScope == .mine
                     ? "Your order, your marks."
                     : "Media consensus order.")
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
            }
        }
    }

    // MARK: - Compare bar

    private var compareSelection: [CollegeProspect] {
        compareIDs.compactMap { id in
            coordinator.availableProspects.first { $0.id == id }
        }
    }

    private var compareBar: some View {
        HStack(spacing: DSSpacing.sm) {
            Image(systemName: "rectangle.split.3x1")
                .font(.caption)
                .foregroundStyle(Color.accentBlue)
            Text(compareIDs.isEmpty
                 ? "Tap up to \(ProspectCompareSheet.maxProspects) prospects to compare"
                 : "\(compareIDs.count) selected")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
            Spacer()
            Button {
                showCompareSheet = true
            } label: {
                Text("Compare \(compareIDs.count)")
                    .font(.caption.weight(.heavy))
                    .padding(.horizontal, DSSpacing.sm)
                    .padding(.vertical, 5)
                    .background(compareIDs.count >= 2 ? Color.accentBlue : Color.backgroundTertiary)
                    .foregroundStyle(compareIDs.count >= 2 ? Color.backgroundPrimary : Color.textTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: DSCornerRadius.inline))
            }
            .buttonStyle(.plain)
            .disabled(compareIDs.count < 2)
        }
        .padding(DSSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                .fill(Color.accentBlue.opacity(0.12))
        )
    }

    private func toggleCompare(_ prospect: CollegeProspect) {
        if let idx = compareIDs.firstIndex(of: prospect.id) {
            compareIDs.remove(at: idx)
        } else {
            if compareIDs.count >= ProspectCompareSheet.maxProspects {
                compareIDs.removeFirst()
            }
            compareIDs.append(prospect.id)
        }
    }

    // MARK: - The list

    /// The pool the chosen scope defines, before search and the depth cut.
    ///
    /// The media order used to be the only one available, and it was the right
    /// default for the value chips — but it meant the board the user spent the
    /// whole spring building was invisible at the only moment it mattered.
    private var scopePool: [CollegeProspect] {
        let pool = positionFilter.map { pos in
            coordinator.availableProspects.filter { $0.position == pos }
        } ?? coordinator.availableProspects

        switch boardScope {
        case .media:
            return pool.sorted {
                (coordinator.publicBoardRanks[$0.id] ?? 999) <
                (coordinator.publicBoardRanks[$1.id] ?? 999)
            }
        case .mine:
            // ONE comparator, not two `sorted` passes: Swift's sort is not
            // stable, so sinking the `avoid` men in a second pass would have
            // scrambled the board order the first pass just established.
            // `avoid` sinks rather than disappearing — the user still has to
            // see who is left on the board.
            return pool.sorted { lhs, rhs in
                let lAvoid = lhs.userMark == .avoid ? 1 : 0
                let rAvoid = rhs.userMark == .avoid ? 1 : 0
                if lAvoid != rAvoid { return lAvoid < rAvoid }
                let lSlot = coordinator.userBoardRanks[lhs.id] ?? Int.max
                let rSlot = coordinator.userBoardRanks[rhs.id] ?? Int.max
                if lSlot != rSlot { return lSlot < rSlot }
                return (coordinator.publicBoardRanks[lhs.id] ?? 999) <
                       (coordinator.publicBoardRanks[rhs.id] ?? 999)
            }
        }
    }

    /// Default depth. Twenty is what fits without scrolling on the clock; the
    /// full board is one tap (or one search) away.
    private static let defaultDepth = 20

    private var listedProspects: [CollegeProspect] {
        let pool = scopePool
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !query.isEmpty {
            // Search always spans the whole board — a name typed in is a name
            // the user already has in mind, and he may well be in round five.
            return Array(pool.filter { matches($0, query: query) }.prefix(60))
        }
        return showsFullBoard ? pool : Array(pool.prefix(Self.defaultDepth))
    }

    private var truncatedCount: Int {
        max(0, scopePool.count - Self.defaultDepth)
    }

    private func matches(_ prospect: CollegeProspect, query: String) -> Bool {
        prospect.lastName.lowercased().contains(query)
            || prospect.firstName.lowercased().contains(query)
            || prospect.college.lowercased().contains(query)
            || prospect.position.rawValue.lowercased().contains(query)
    }

    private func prospectRow(_ prospect: CollegeProspect) -> some View {
        HStack(spacing: DSSpacing.xs) {
            if isPickingCompare {
                Button {
                    toggleCompare(prospect)
                } label: {
                    Image(systemName: compareIDs.contains(prospect.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(compareIDs.contains(prospect.id) ? Color.accentBlue : Color.textTertiary)
                        .frame(width: 32, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(compareIDs.contains(prospect.id)
                                    ? "Remove \(prospect.fullName) from compare"
                                    : "Add \(prospect.fullName) to compare")
            }

            Button {
                if isPickingCompare {
                    toggleCompare(prospect)
                } else {
                    pendingProspect = prospect
                }
            } label: {
                prospectRowContent(prospect)
            }
            .buttonStyle(.plain)

            // The card is the reason the notes, the medical flags and the
            // interview your staff took are readable AT the clock instead of
            // only in the spring.
            Button {
                cardProspect = prospect
            } label: {
                Image(systemName: "person.text.rectangle")
                    .font(.callout)
                    .foregroundStyle(Color.accentGold)
                    .frame(width: 40, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Scouting card for \(prospect.fullName)")
        }
    }

    private func prospectRowContent(_ prospect: CollegeProspect) -> some View {
        let bbRank = coordinator.publicBoardRanks[prospect.id]
        let myRank = coordinator.userBoardRanks[prospect.id]
        let pickNumber = coordinator.currentPick?.pickNumber ?? 0
        let needScore = coordinator.teamNeedScores[prospect.position] ?? 0.2
        let valueDelta = DraftIntel.pickValueDelta(for: prospect, pickNumber: pickNumber, consensusRank: bbRank)
        let preview = pickGradePreview(prospect: prospect, valueDelta: valueDelta, needScore: needScore)
        // Graded a reach even though the board says he is fair value here —
        // i.e. the reach is coming from need, not from value.
        let showReachWarning = (preview.grade == .reach || preview.grade == .bigReach) && valueDelta >= 4
        let mark = DraftIntel.mark(for: prospect)

        return HStack(spacing: DSSpacing.sm) {
            PersonFaceView(prospect: prospect, size: .small)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("\(prospect.firstName) \(prospect.lastName)")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(mark == .avoid ? Color.textTertiary : Color.textPrimary)
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
                // The trade-down question, answered on the row instead of in
                // the user's head: is this man still here next time I pick?
                // Same model the Mock Draft and the Big Board now read from
                // (`DraftAvailability`), so the number cannot contradict the
                // one he planned against in the spring.
                if let nextPick = coordinator.pickNumberAfterCurrent,
                   let read = DraftAvailability.read(for: prospect, atPick: nextPick, consensusRank: bbRank) {
                    Text("\(read.percent)% still there at your #\(nextPick)\(read.isBandEstimate ? " (band)" : "")")
                        .font(.caption2)
                        .foregroundStyle(read.tier.color)
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
                // Same slot the Big Board and the Mock Draft print — the three
                // "your board" numbers used to be three different sorts.
                if let my = myRank {
                    Text("MY #\(my)")
                        .font(.caption2.monospaced().weight(.heavy))
                        .foregroundStyle(Color.accentGold.opacity(0.85))
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
        .opacity(mark == .avoid ? 0.55 : 1.0)
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
    /// `scopePool` is: picking the "best" at a position off a board that
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
