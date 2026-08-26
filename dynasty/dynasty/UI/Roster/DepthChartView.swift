import SwiftUI
import SwiftData

// MARK: - Main View

struct DepthChartView: View {

    let career: Career

    @Environment(\.modelContext) private var modelContext
    @Query private var allPlayersUnscoped: [Player]

    // `@Query` cannot take a runtime predicate built from a stored property,
    // so the store-wide result is narrowed to THIS save here. Without it the
    // screen mixes two careers' populations into one list.
    private var allPlayers: [Player] { allPlayersUnscoped.filter { $0.careerID == career.id } }

    @State private var depthChart = DepthChart()
    @State private var selectedTab: PositionSide = .offense
    @State private var comparisonState: ComparisonState? = nil
    /// Tracks which slots are collapsed. By default all are expanded.
    @State private var collapsedSlots: Set<String> = []
    /// Tracks which position groups are collapsed (e.g. "DL", "LB").
    @State private var collapsedGroups: Set<String> = []
    /// One-line confirmation of what Auto-Set actually did, e.g. "Filled 6
    /// empty slots". Without it the wand looked like it had done nothing —
    /// the chart it fills is mostly below the fold.
    @State private var autoSetMessage: String?
    /// Guards the auto-dismiss timer so a second tap cannot hide the newer toast.
    @State private var autoSetFlashID = 0

    // MARK: - Derived roster

    private var rosterPlayers: [Player] {
        guard let teamID = career.teamID else { return [] }
        return allPlayers.filter { $0.teamID == teamID }
    }

    private var playerLookup: [UUID: Player] {
        Dictionary(uniqueKeysWithValues: rosterPlayers.map { ($0.id, $0) })
    }

    // MARK: - Slot groups

    private var activeSlots: [DepthChartSlot] {
        slots(on: selectedTab)
    }

    private func slots(on side: PositionSide) -> [DepthChartSlot] {
        switch side {
        case .offense:      return DepthChartSlot.offenseSlots
        case .defense:      return DepthChartSlot.defenseSlots
        case .specialTeams: return DepthChartSlot.specialTeamsSlots
        }
    }

    /// Starter slots on a side with nobody standing in them.
    ///
    /// The same test the group pills use one level down, lifted to the tab bar.
    /// The Lineup Incomplete gate names the missing slots in a dialog and then
    /// navigates here, where the chart opens on Offense and neither of the
    /// other two tabs carries any mark — so a manager told "Defense: Left OLB
    /// unassigned" arrives on a screen that shows him the offensive line.
    private func unfilledStarters(on side: PositionSide) -> Int {
        slots(on: side).filter {
            depthChart.depthOrder(for: $0).first.flatMap { playerLookup[$0] } == nil
        }.count
    }

    // MARK: - Grouped Slots

    /// A position group containing related depth chart slots, used for collapse/expand.
    private struct SlotGroup: Identifiable {
        let id: String
        let name: String
        let icon: String
        let slots: [DepthChartSlot]
    }

    /// Returns slots grouped by position family for the active tab.
    private var activeSlotGroups: [SlotGroup] {
        switch selectedTab {
        case .offense:
            return [
                SlotGroup(id: "QB", name: "Quarterbacks", icon: "figure.american.football", slots: [.QB]),
                SlotGroup(id: "Backfield", name: "Backfield", icon: "figure.run", slots: [.RB, .FB]),
                SlotGroup(id: "Receivers", name: "Receivers", icon: "hand.wave", slots: [.WR1, .WR2, .WR3, .TE]),
                SlotGroup(id: "OL", name: "Offensive Line", icon: "shield.lefthalf.filled", slots: [.LT, .LG, .C, .RG, .RT]),
            ]
        case .defense:
            return [
                SlotGroup(id: "DL", name: "Defensive Line", icon: "bolt.shield", slots: [.LE, .DT, .RE]),
                SlotGroup(id: "LB", name: "Linebackers", icon: "shield", slots: [.LOLB, .MLB, .ROLB]),
                SlotGroup(id: "DB", name: "Secondary", icon: "eye", slots: [.CB1, .CB2, .FS, .SS]),
            ]
        case .specialTeams:
            return [
                SlotGroup(id: "Kickers", name: "Kickers & Punters", icon: "sportscourt", slots: [.K, .P]),
                SlotGroup(id: "Returners", name: "Returners", icon: "arrow.uturn.backward", slots: [.KR, .PR]),
            ]
        }
    }

    // MARK: - Team OVR

    /// All three pills go through `TeamStrength`, the single definition of a
    /// team's rating, so this screen, the schedule rows and the league roster
    /// browser can never quote three different numbers for the same club again.
    ///
    /// `DepthChart.teamOverall` — what TEAM used to read — averaged the first
    /// man in EVERY slot, kicker and punter included and the returners counted
    /// a second time, which is why TEAM sat below both OFF and DEF.
    private var teamOVR: Int {
        TeamStrength.ovr(chart: depthChart, slots: TeamStrength.lineupSlots, lookup: playerLookup)
    }

    private var offenseOVR: Int {
        TeamStrength.ovr(chart: depthChart, slots: DepthChartSlot.offenseSlots, lookup: playerLookup)
    }

    private var defenseOVR: Int {
        TeamStrength.ovr(chart: depthChart, slots: DepthChartSlot.defenseSlots, lookup: playerLookup)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                teamOverallBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                tabBar
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                ScrollView {
                    LazyVStack(spacing: 14) {
                        // Collapse-all / expand-all controls
                        groupCollapseControls
                            .padding(.horizontal, 20)
                            .padding(.top, 4)

                        ForEach(activeSlotGroups) { group in
                            groupSection(group)
                                .padding(.horizontal, 20)
                        }

                        practiceSquadSection
                            .padding(.horizontal, 20)
                    }
                    .padding(.vertical, 16)
                    .frame(maxWidth: DSLayout.contentMeasure)
                    .frame(maxWidth: .infinity)
                }
            }

            // Auto-Set confirmation toast
            if let message = autoSetMessage {
                VStack {
                    autoSetToast(message)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    Spacer()
                }
            }
        }
        .navigationTitle("Depth Chart")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                autoFillButton
            }
        }
        .sheet(item: $comparisonState) { state in
            ComparisonSheet(
                slot: state.slot,
                slotIndex: state.slotIndex,
                rosterPlayers: rosterPlayers,
                depthChart: depthChart,
                playerLookup: playerLookup,
                onSelect: { playerID in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        depthChart.assign(slot: state.slot, playerID: playerID, at: state.slotIndex)
                    }
                    persistDepthChart()
                    comparisonState = nil
                },
                onClear: {
                    if let currentDepth = depthChart.depthOrder(for: state.slot)[safe: state.slotIndex] {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            depthChart.remove(slot: state.slot, playerID: currentDepth)
                        }
                        persistDepthChart()
                    }
                    comparisonState = nil
                },
                onDismiss: { comparisonState = nil }
            )
        }
        .task {
            loadOrSeedDepthChart()
        }
    }

    // MARK: - Practice Squad Section (§5.1)

    /// The men one signature below the chart.
    ///
    /// Read-only on purpose: a squad player is not assignable to a depth slot —
    /// he cannot dress — so putting him in the chart proper would be a lie the
    /// simulator would then have to refuse. He shows up here filtered to the
    /// side being viewed, as the answer to "who covers this hole if a starter
    /// goes down", with promotion living on the roster screen where the
    /// active-roster spot it costs is visible.
    @ViewBuilder
    private var practiceSquadSection: some View {
        let squad = career.teamID.map { PracticeSquadEngine.squad(of: $0, in: allPlayers) } ?? []
        let onThisSide = squad.filter { $0.position.side == selectedTab }

        if !squad.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Practice Squad", systemImage: "person.3.sequence.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Text("\(squad.count)/\(PracticeSquadEngine.squadSize)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.textSecondary)
                }

                if onThisSide.isEmpty {
                    Text("Nobody on this side of the ball.")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                } else {
                    ForEach(onThisSide, id: \.id) { player in
                        HStack(spacing: 10) {
                            Text(player.position.rawValue)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.textSecondary)
                                .frame(width: 34, alignment: .leading)
                            Text(player.fullName)
                                .font(.subheadline)
                                .foregroundStyle(Color.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text("\(player.overall)")
                                .font(.subheadline.weight(.bold).monospacedDigit())
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                }

                Text("Squad players practise and develop with the team but cannot dress. Promote from the Roster screen.")
                    .font(.caption2)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(14)
            .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: DSCornerRadius.card))
        }
    }

    // MARK: - Persistence

    /// Loads the saved chart from the career, seeding a fresh auto-generated
    /// chart (without persisting it) when none has been saved yet. The chart
    /// is only persisted on explicit user action so the "Set depth chart"
    /// task completes from a real decision, not a screen visit.
    private func loadOrSeedDepthChart() {
        if let data = career.depthChartData,
           let saved = try? JSONDecoder().decode(DepthChart.self, from: data) {
            depthChart = saved
        } else {
            depthChart.autoGenerate(players: rosterPlayers)
        }
    }

    /// Writes the current chart back to the career and saves the context.
    /// Called after every user mutation (assign / clear / reorder / auto-set).
    private func persistDepthChart() {
        career.depthChartData = try? JSONEncoder().encode(depthChart)
        try? modelContext.save()
    }

    // MARK: - Team Overall Bar

    private var teamOverallBar: some View {
        HStack(spacing: 16) {
            ovrPill(label: "TEAM", value: teamOVR)
            Spacer()
            ovrPill(label: "OFF", value: offenseOVR)
            ovrPill(label: "DEF", value: defenseOVR)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                )
        )
    }

    private func ovrPill(label: String, value: Int) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: DSType.Size.micro, weight: .bold))
                .foregroundStyle(Color.textTertiary)
            Text("\(value)")
                .font(.system(size: DSType.Size.callout, weight: .heavy).monospacedDigit())
                .foregroundStyle(Color.forRating(value))
        }
    }

    // MARK: - Tab Bar

    /// Offense / Defense / Special Teams filter.
    ///
    /// Deliberately identical to `RosterView.filterPicker` — blue selection
    /// fill, not gold. A full-width saturated gold bar made the biggest,
    /// loudest element on the screen a mere view filter, out-shouting the
    /// starter rows and the gold accents that mark real decisions.
    private var tabBar: some View {
        HStack(spacing: 8) {
            ForEach([PositionSide.offense, .defense, .specialTeams], id: \.self) { side in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedTab = side
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(side.rawValue)
                            .font(.subheadline)
                            .fontWeight(selectedTab == side ? .heavy : .medium)
                            .foregroundStyle(selectedTab == side ? Color.backgroundPrimary : Color.textSecondary)
                        let gaps = unfilledStarters(on: side)
                        if gaps > 0 {
                            HStack(spacing: 2) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: DSType.Size.micro, weight: .bold))
                                Text("\(gaps)")
                                    .font(.system(size: DSType.Size.micro, weight: .heavy).monospacedDigit())
                            }
                            .foregroundStyle(selectedTab == side ? Color.backgroundPrimary : Color.warning)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 8)
                    .background(
                        selectedTab == side ? Color.accentBlue : Color.clear,
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                    .overlay(
                        selectedTab == side
                            ? nil
                            : RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                    )
                }
                .contentShape(RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel(
                    unfilledStarters(on: side) > 0
                        ? "\(side.rawValue), \(unfilledStarters(on: side)) starter slots unfilled"
                        : side.rawValue
                )
            }
        }
        .padding(5)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Auto-Fill Button

    /// The one-tap way out of an empty chart.
    ///
    /// The title is composed by hand rather than left to `Label`: the toolbar
    /// collapses a `Label` to icon-only even with `.labelStyle(.titleAndIcon)`,
    /// and the blocker dialog that sends a first-time manager here promises a
    /// button called "Auto-Set" — a bare wand glyph in the corner is not that.
    private var autoFillButton: some View {
        Button {
            applyAutoSet()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "wand.and.stars")
                Text("Auto-Set")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.accentGold)
        }
        .tint(Color.accentGold)
        .accessibilityLabel("Auto-set lineup")
        .accessibilityHint("Fills every depth slot with the best available player by overall rating")
    }

    // MARK: - Auto-Set

    /// Runs the auto-generator and reports what it changed.
    ///
    /// `autoGenerate` rebuilds the whole chart, so "did anything happen?" is
    /// answered by diffing occupancy before and after rather than by trusting
    /// the call: filling six holes and re-ordering three rooms are different
    /// outcomes and read as different sentences.
    private func applyAutoSet() {
        let before = occupancySnapshot()
        withAnimation {
            depthChart.autoGenerate(players: rosterPlayers)
        }
        persistDepthChart()
        let after = occupancySnapshot()

        var filled = 0
        var replaced = 0
        for (key, newValue) in after {
            switch before[key] {
            case .none:
                filled += 1
            case .some(let oldValue) where oldValue != newValue:
                replaced += 1
            default:
                break
            }
        }
        flashAutoSetMessage(autoSetSummary(filled: filled, replaced: replaced))
    }

    /// `slot|index` → player for every assignable slot on the whole chart.
    private func occupancySnapshot() -> [String: UUID] {
        var snapshot: [String: UUID] = [:]
        for slot in DepthChartSlot.allCases {
            let depth = depthChart.depthOrder(for: slot)
            for index in 0..<slot.maxDepth {
                if let playerID = depth[safe: index] {
                    snapshot["\(slot.rawValue)|\(index)"] = playerID
                }
            }
        }
        return snapshot
    }

    private func autoSetSummary(filled: Int, replaced: Int) -> String {
        switch (filled, replaced) {
        case (0, 0):
            return "Lineup already optimal — nothing to change."
        case (0, let changed):
            return "Re-ordered \(changed) slot\(changed == 1 ? "" : "s") by overall."
        case (let empty, 0):
            return "Filled \(empty) empty slot\(empty == 1 ? "" : "s")."
        case (let empty, let changed):
            return "Filled \(empty) empty slot\(empty == 1 ? "" : "s") · re-ordered \(changed)."
        }
    }

    private func flashAutoSetMessage(_ message: String) {
        autoSetFlashID += 1
        let flashID = autoSetFlashID
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            autoSetMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
            if flashID == autoSetFlashID {
                withAnimation(.easeOut(duration: 0.3)) { autoSetMessage = nil }
            }
        }
    }

    private func autoSetToast(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: DSType.Size.callout, weight: .semibold))
                .foregroundStyle(Color.success)
            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.backgroundSecondary)
                .overlay(RoundedRectangle(cornerRadius: 12).fill(Color.success.opacity(0.12)))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.success.opacity(0.4), lineWidth: 1)
                )
        )
        .accessibilityAddTraits(.isStaticText)
    }

    // MARK: - Group Collapse Controls

    private var groupCollapseControls: some View {
        HStack(spacing: 6) {
            Image(systemName: "list.bullet.indent")
                .font(.system(size: DSType.Size.caption, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
            Text("\(activeSlotGroups.count) groups · \(activeSlots.count) positions")
                .font(.system(size: DSType.Size.caption, weight: .medium))
                .foregroundStyle(Color.textTertiary)
            // The bolt meter on the rows is the one indicator with no legend
            // anywhere on the screen, and its ladder is inverted against every
            // other 0-100 bar in the app. This is the only place that says so.
            Image(systemName: "bolt.fill")
                .font(.system(size: DSType.Size.micro))
                .foregroundStyle(Color.textTertiary)
            Text("fatigue \u{00B7} lower is better")
                .font(.system(size: DSType.Size.caption, weight: .medium))
                .foregroundStyle(Color.textTertiary)
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if collapsedGroups.intersection(activeSlotGroups.map(\.id)).count == activeSlotGroups.count {
                        // All collapsed → expand all
                        for g in activeSlotGroups { collapsedGroups.remove(g.id) }
                    } else {
                        // Collapse all
                        for g in activeSlotGroups { collapsedGroups.insert(g.id) }
                    }
                }
            } label: {
                let allCollapsed = collapsedGroups.intersection(activeSlotGroups.map(\.id)).count == activeSlotGroups.count
                HStack(spacing: 3) {
                    Image(systemName: allCollapsed ? "chevron.down.square" : "chevron.up.square")
                        .font(.system(size: DSType.Size.caption, weight: .semibold))
                    Text(allCollapsed ? "Expand all" : "Collapse all")
                        .font(.system(size: DSType.Size.micro, weight: .semibold))
                }
                .foregroundStyle(Color.accentBlue)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(collapsedGroups.intersection(activeSlotGroups.map(\.id)).count == activeSlotGroups.count ? "Expand all groups" : "Collapse all groups")
        }
    }

    // MARK: - Group Section

    private func groupSection(_ group: SlotGroup) -> some View {
        let isCollapsed = collapsedGroups.contains(group.id)
        let groupSlots = group.slots
        let filledStarters = groupSlots.filter { depthChart.depthOrder(for: $0).first.flatMap { playerLookup[$0] } != nil }.count
        // A full starter line is not the same as a room that survives a
        // September injury, and the cut decision needs the second number too:
        // "1/1" over a card with an empty 3rd-string row was the only
        // completeness signal the header had. `prefix(maxDepth)` because that
        // is exactly what the card draws — a name parked past the last rendered
        // row is not depth the user can see.
        let filledDepth = groupSlots.reduce(0) { running, slot in
            running + depthChart.depthOrder(for: slot).prefix(slot.maxDepth).compactMap { playerLookup[$0] }.count
        }
        let totalDepth = groupSlots.reduce(0) { $0 + $1.maxDepth }
        let hasThinRoom = groupSlots.contains { slot in
            slot.maxDepth > 1
                && depthChart.depthOrder(for: slot).prefix(slot.maxDepth).compactMap { playerLookup[$0] }.count < 2
        }
        let isGroupSound = filledStarters == groupSlots.count && !hasThinRoom
        let starterAvg: Int = {
            let starters = groupSlots.compactMap { slot -> Int? in
                guard let pid = depthChart.depthOrder(for: slot).first, let p = playerLookup[pid] else { return nil }
                return p.overall
            }
            return starters.isEmpty ? 0 : starters.reduce(0, +) / starters.count
        }()

        return VStack(spacing: 10) {
            // Group header (tappable to collapse/expand)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isCollapsed {
                        collapsedGroups.remove(group.id)
                    } else {
                        collapsedGroups.insert(group.id)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: DSType.Size.caption, weight: .heavy))
                        .foregroundStyle(Color.accentGold)
                        .frame(width: 14)
                    Image(systemName: group.icon)
                        .font(.system(size: DSType.Size.footnote, weight: .semibold))
                        .foregroundStyle(Color.textSecondary)
                    Text(group.name)
                        .font(.system(size: DSType.Size.body, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    // Filled count — starters, then bodies behind them
                    HStack(spacing: 3) {
                        Image(systemName: isGroupSound ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .font(.system(size: DSType.Size.micro))
                        Text("\(filledStarters)/\(groupSlots.count) \u{00B7} \(filledDepth)/\(totalDepth) deep")
                            .font(.system(size: DSType.Size.caption, weight: .bold).monospacedDigit())
                    }
                    .foregroundStyle(isGroupSound ? Color.success : Color.warning)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        (isGroupSound ? Color.success : Color.warning).opacity(0.12),
                        in: Capsule()
                    )
                    // Average starter OVR
                    if starterAvg > 0 {
                        Text("AVG \(starterAvg)")
                            .font(.system(size: DSType.Size.caption, weight: .bold).monospacedDigit())
                            .foregroundStyle(Color.forRating(starterAvg))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.forRating(starterAvg).opacity(0.12), in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.forRating(starterAvg).opacity(0.3), lineWidth: 0.5))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.backgroundSecondary)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(group.name), \(filledStarters) of \(groupSlots.count) starters filled, \(filledDepth) of \(totalDepth) depth slots filled\(hasThinRoom ? ", a position here has no backup" : ""), \(isCollapsed ? "collapsed, tap to expand" : "expanded, tap to collapse")")

            // Slots — only render when expanded
            if !isCollapsed {
                VStack(spacing: 10) {
                    ForEach(groupSlots) { slot in
                        slotCard(slot: slot)
                    }
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity
                ))
            }
        }
    }

    // MARK: - Slot Card

    private func slotCard(slot: DepthChartSlot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                slotBadge(slot)
                Text(slot.shortLabel)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text(slot.displayName)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            // Depth slots in a vertical list (drag-to-reorder)
            let depth = depthChart.depthOrder(for: slot)
            let maxSlots = slot.maxDepth

            VStack(spacing: 6) {
                ForEach(0..<maxSlots, id: \.self) { index in
                    let playerID = depth[safe: index]
                    let player = playerID.flatMap { playerLookup[$0] }
                    depthSlotRow(
                        slot: slot,
                        index: index,
                        player: player,
                        totalInSlot: depth.count
                    )
                }
            }
        }
        .padding(14)
        .cardBackground()
    }

    // MARK: - Depth Slot Row

    private func depthSlotRow(
        slot: DepthChartSlot,
        index: Int,
        player: Player?,
        totalInSlot: Int
    ) -> some View {
        let isStarter = index == 0
        // A hole in the STARTER line is the thing the lineup gate blocks on, and
        // it used to look exactly like a spare depth row: same plate, same
        // "Tap to assign". Twelve positions deep in a scroll that is the
        // difference between finding it and being told again on the next
        // Advance.
        let isGap = isStarter && player == nil

        return HStack(spacing: 10) {
            // Reorder buttons
            if let _ = player, totalInSlot > 1 {
                VStack(spacing: 2) {
                    Button {
                        guard index > 0 else { return }
                        withAnimation(.easeInOut(duration: 0.2)) {
                            depthChart.swap(slot: slot, indexA: index, indexB: index - 1)
                        }
                        persistDepthChart()
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: DSType.Size.micro, weight: .bold))
                            .foregroundStyle(index > 0 ? Color.textSecondary : Color.backgroundTertiary)
                    }
                    .buttonStyle(.plain)
                    .disabled(index == 0)

                    Button {
                        guard index < totalInSlot - 1 else { return }
                        withAnimation(.easeInOut(duration: 0.2)) {
                            depthChart.swap(slot: slot, indexA: index, indexB: index + 1)
                        }
                        persistDepthChart()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: DSType.Size.micro, weight: .bold))
                            .foregroundStyle(index < totalInSlot - 1 ? Color.textSecondary : Color.backgroundTertiary)
                    }
                    .buttonStyle(.plain)
                    .disabled(index >= totalInSlot - 1)
                }
                .frame(width: 20)
            } else {
                Color.clear.frame(width: 20, height: 1)
            }

            // Slot label
            Text(depthLabelShort(index: index))
                .font(.system(size: DSType.Size.micro, weight: .bold))
                .foregroundStyle(isStarter ? Color.accentGold : Color.textTertiary)
                .textCase(.uppercase)
                .lineLimit(1)
                .frame(width: 48, alignment: .leading)

            // Player info or empty
            Button {
                comparisonState = ComparisonState(slot: slot, slotIndex: index)
            } label: {
                if let player {
                    playerSlotContent(player: player, slot: slot, isStarter: isStarter)
                } else {
                    emptySlotContent()
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    isGap ? Color.warning.opacity(0.10)
                        : (isStarter ? Color.accentGold.opacity(0.06) : Color.backgroundTertiary.opacity(0.3))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            isGap ? Color.warning.opacity(0.7)
                                : (isStarter ? Color.accentGold.opacity(0.3) : Color.surfaceBorder.opacity(0.5)),
                            lineWidth: isStarter ? 1 : 0.5
                        )
                )
        )
        .accessibilityLabel(slotAccessibilityLabel(index: index, player: player))
    }

    // MARK: - Player Slot Content

    private func playerSlotContent(player: Player, slot: DepthChartSlot, isStarter: Bool) -> some View {
        HStack(spacing: 8) {
            // Player name
            VStack(alignment: .leading, spacing: 1) {
                Text(player.fullName)
                    .font(.system(size: DSType.Size.body, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                HStack(spacing: 6) {
                    Text(player.position.rawValue)
                        .font(.system(size: DSType.Size.micro, weight: .medium))
                        .foregroundStyle(Color.textTertiary)

                    Text("Age \(player.age)")
                        .font(.system(size: DSType.Size.micro))
                        .foregroundStyle(Color.textTertiary)

                    // `annualSalary` is in thousands, so integer division
                    // printed "$0M" for everyone on a rookie deal — the ledger's
                    // own formatter says "$750K" / "$12.5M".
                    Text(CommittedCapLedger.money(player.annualSalary))
                        .font(.system(size: DSType.Size.micro))
                        .foregroundStyle(Color.textTertiary)
                }
            }

            Spacer()

            // Indicators
            HStack(spacing: 6) {
                // Wrong position indicator
                if !slot.acceptsAnyPosition && player.position != slot.basePosition {
                    Image(systemName: "arrow.triangle.swap")
                        .font(.system(size: DSType.Size.micro))
                        .foregroundStyle(Color.warning)
                        .help("Playing out of natural position")
                }

                // Injury icon
                if player.isInjured {
                    HStack(spacing: 2) {
                        Image(systemName: "cross.circle.fill")
                            .font(.system(size: DSType.Size.caption))
                            .foregroundStyle(Color.danger)
                        if player.injuryWeeksRemaining > 0 {
                            Text("\(player.injuryWeeksRemaining)w")
                                .font(.system(size: DSType.Size.caption, weight: .bold))
                                .foregroundStyle(Color.danger)
                        }
                    }
                }

                // Fatigue bar
                if player.fatigue > 0 {
                    fatigueMeter(value: player.fatigue)
                }

                // OVR rating badge
                ratingBadge(value: player.overall)
            }
        }
        .contentShape(Rectangle())
    }

    // MARK: - Empty Slot Content

    private func emptySlotContent() -> some View {
        HStack {
            // The glyph led the row, which started "Tap to assign" a glyph's
            // width right of where the names above it start. It sits in the
            // trailing indicator column now, where the OVR badge sits on a
            // filled row, so the two kinds of row share one left edge.
            Text("Tap to assign")
                .font(.system(size: DSType.Size.footnote))
                .foregroundStyle(Color.textTertiary)
            Spacer()
            Image(systemName: "plus.circle.dashed")
                .font(.system(size: DSType.Size.body))
                .foregroundStyle(Color.textTertiary)
        }
        .contentShape(Rectangle())
    }

    // MARK: - Rating Badge

    private func ratingBadge(value: Int) -> some View {
        Text("\(value)")
            .font(.system(size: DSType.Size.body, weight: .bold).monospacedDigit())
            .foregroundStyle(Color.forRating(value))
            .frame(width: 34, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.forRating(value).opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.forRating(value).opacity(0.3), lineWidth: 1)
                    )
            )
    }

    // MARK: - Fatigue Meter

    private func fatigueMeter(value: Int) -> some View {
        VStack(spacing: 1) {
            Image(systemName: "bolt.fill")
                .font(.system(size: DSType.Size.micro))
                .foregroundStyle(fatigueColor(value))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.backgroundTertiary)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(fatigueColor(value))
                        .frame(width: geo.size.width * CGFloat(value) / 100.0)
                }
            }
            .frame(width: 28, height: 5)
        }
        // P7 rule 3: a lower-is-better metric has to say so somewhere, and a
        // 28×5 meter has no room for words. It says so here, and in print on
        // the screen's own legend row (`groupCollapseControls`).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Fatigue \(value) percent, lower is better")
    }

    /// Fatigue is a 0–100 player quantity, so it belongs on the shared ladder —
    /// but INVERTED, because it is the app's clearest lower-is-better metric
    /// (P7 rule 3). 100 fatigue is a spent player and reads red; 0 reads green.
    /// The private three-band ladder it replaces disagreed with every other
    /// 0–100 bar on the same row.
    private func fatigueColor(_ value: Int) -> Color {
        Color.forRating(100 - value, scale: .percent)
    }

    // MARK: - Slot Badge

    private func slotBadge(_ slot: DepthChartSlot) -> some View {
        Text(slot.shortLabel)
            .font(.system(size: DSType.Size.micro, weight: .bold))
            .foregroundStyle(Color.backgroundPrimary)
            .frame(minWidth: 28, minHeight: 20)
            .padding(.horizontal, 4)
            .background(sideColor(slot.side), in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))
    }

    // MARK: - Helpers

    private func sideColor(_ side: PositionSide) -> Color {
        switch side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }

    private func depthLabel(index: Int) -> String {
        switch index {
        case 0: return "Starter"
        case 1: return "Backup"
        case 2: return "3rd String"
        default: return "Depth \(index + 1)"
        }
    }

    /// The printed label. "3RD STRING" is the one label too wide for the 48 pt
    /// column, and it wrapped to two lines — which pushed its row's reorder
    /// chevrons and its player's name out of line with every row above it.
    /// `depthLabel` still says the whole thing out loud.
    private func depthLabelShort(index: Int) -> String {
        index == 2 ? "3rd" : depthLabel(index: index)
    }

    private func slotAccessibilityLabel(index: Int, player: Player?) -> String {
        let slot = depthLabel(index: index)
        if let player {
            return "\(slot): \(player.fullName), overall \(player.overall)"
        }
        return "\(slot): empty, tap to assign"
    }
}

// MARK: - Comparison State

private struct ComparisonState: Identifiable {
    let id = UUID()
    let slot: DepthChartSlot
    let slotIndex: Int
}

// MARK: - Comparison Sheet

private struct ComparisonSheet: View {

    let slot: DepthChartSlot
    let slotIndex: Int
    let rosterPlayers: [Player]
    let depthChart: DepthChart
    let playerLookup: [UUID: Player]
    let onSelect: (UUID) -> Void
    let onClear: () -> Void
    let onDismiss: () -> Void

    @State private var sortMode: ComparisonSort = .overall

    private enum ComparisonSort: String, CaseIterable {
        case overall = "Overall"
        case fit = "Position Fit"
        case age = "Age"
    }

    // MARK: - Candidate Players

    /// Returns all players who could fill this slot, including out-of-position candidates.
    private var candidates: [CandidatePlayer] {
        rosterPlayers.map { player in
            let isNatural = player.position == slot.basePosition
            let versatility = VersatilityEngine.rate(player: player, at: slot.basePosition)
            let isViable = isNatural || versatility.rawValue >= VersatilityRating.unconvincing.rawValue
            let ovrDelta = depthChart.impactOfAssigning(
                playerID: player.id,
                toSlot: slot,
                at: slotIndex,
                lookup: playerLookup
            )
            return CandidatePlayer(
                player: player,
                isNatural: isNatural,
                versatility: versatility,
                isViable: isViable,
                ovrDelta: ovrDelta
            )
        }
        .filter { $0.isViable || slot.acceptsAnyPosition }
        .sorted { sortCandidate($0, $1) }
    }

    private func sortCandidate(_ a: CandidatePlayer, _ b: CandidatePlayer) -> Bool {
        switch sortMode {
        case .overall:
            // Returner slots rank by the trait that actually matters back deep
            // (speed for KR, agility for PR) — raw overall would put QBs on top.
            if slot == .KR {
                return a.player.physical.speed > b.player.physical.speed
            }
            if slot == .PR {
                return a.player.physical.agility > b.player.physical.agility
            }
            return a.player.overall > b.player.overall
        case .fit:
            if a.versatility != b.versatility {
                return a.versatility > b.versatility
            }
            return a.player.overall > b.player.overall
        case .age:
            return a.player.age < b.player.age
        }
    }

    private var currentPlayerID: UUID? {
        depthChart.depthOrder(for: slot)[safe: slotIndex]
    }

    private var slotLabel: String {
        switch slotIndex {
        case 0: return "Starter"
        case 1: return "Backup"
        case 2: return "3rd String"
        default: return "Depth \(slotIndex + 1)"
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Impact header
                    if let currentID = currentPlayerID, let current = playerLookup[currentID] {
                        currentPlayerHeader(current)
                    }

                    // Sort picker
                    sortPicker

                    // Candidate list
                    List {
                        Section {
                            Button(action: onClear) {
                                HStack {
                                    Image(systemName: "xmark.circle")
                                        .foregroundStyle(Color.textTertiary)
                                    Text("Clear Slot")
                                        .foregroundStyle(Color.textSecondary)
                                }
                            }
                        }
                        .listRowBackground(Color.backgroundSecondary)

                        Section("Candidates (\(candidates.count))") {
                            if candidates.isEmpty {
                                Text("No viable players for \(slot.shortLabel)")
                                    .foregroundStyle(Color.textTertiary)
                                    .font(.subheadline)
                            } else {
                                ForEach(candidates, id: \.player.id) { candidate in
                                    Button {
                                        onSelect(candidate.player.id)
                                    } label: {
                                        candidateRow(candidate)
                                    }
                                    .listRowBackground(
                                        candidate.player.id == currentPlayerID
                                            ? Color.accentGold.opacity(0.08)
                                            : Color.backgroundSecondary
                                    )
                                }
                            }
                        }
                        .listRowBackground(Color.backgroundSecondary)
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("\(slot.shortLabel) — \(slotLabel)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDismiss)
                        .foregroundStyle(Color.accentGold)
                }
            }
        }
    }

    // MARK: - Current Player Header

    private func currentPlayerHeader(_ player: Player) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Current: \(player.fullName)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                HStack(spacing: 8) {
                    Text("\(player.position.rawValue) · \(player.overall) OVR")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                    if player.isInjured {
                        Label("Injured", systemImage: "cross.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.danger)
                    }
                }
            }
            Spacer()
            Text("\(player.overall)")
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(Color.forRating(player.overall))
        }
        .padding(16)
        .background(Color.backgroundSecondary)
    }

    // MARK: - Sort Picker

    private var sortPicker: some View {
        Picker("Sort", selection: $sortMode) {
            ForEach(ComparisonSort.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Candidate Row

    private func candidateRow(_ candidate: CandidatePlayer) -> some View {
        let player = candidate.player
        let isCurrent = player.id == currentPlayerID
        let isInDepthChart = depthChart.depthOrder(for: slot).contains(player.id)

        return HStack(spacing: 10) {
            // Position badge
            Text(player.position.rawValue)
                .font(.system(size: DSType.Size.micro, weight: .bold))
                .foregroundStyle(Color.backgroundPrimary)
                .frame(width: 28, height: 18)
                .background(positionColor(player.position.side), in: RoundedRectangle(cornerRadius: 3))

            // Player info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(player.fullName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    if isCurrent {
                        Text("Current")
                            .font(.system(size: DSType.Size.micro, weight: .bold))
                            .foregroundStyle(Color.accentGold)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentGold.opacity(0.15)))
                    }
                }
                HStack(spacing: 6) {
                    Text("Age \(player.age)")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                    Text(player.yearsPro == 0 ? "Rookie" : "\(player.yearsPro)yr pro")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)

                    // Versatility rating
                    if !candidate.isNatural && !slot.acceptsAnyPosition {
                        Text(candidate.versatility.label)
                            .font(.system(size: DSType.Size.micro, weight: .medium))
                            .foregroundStyle(candidate.versatility.color)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                Capsule().fill(candidate.versatility.color.opacity(0.12))
                            )
                    }
                }
            }

            Spacer()

            // Indicators column
            VStack(alignment: .trailing, spacing: 2) {
                // OVR impact delta
                if candidate.ovrDelta != 0 && !isCurrent {
                    HStack(spacing: 2) {
                        Image(systemName: candidate.ovrDelta > 0 ? "arrow.up" : "arrow.down")
                            .font(.system(size: DSType.Size.micro, weight: .bold))
                        Text("\(abs(candidate.ovrDelta))")
                            .font(.system(size: DSType.Size.micro, weight: .bold).monospacedDigit())
                    }
                    .foregroundStyle(candidate.ovrDelta > 0 ? Color.success : Color.danger)
                }

                // Injury status
                if player.isInjured {
                    HStack(spacing: 2) {
                        Image(systemName: "cross.circle.fill")
                            .foregroundStyle(Color.danger)
                            .font(.system(size: DSType.Size.caption))
                        if player.injuryWeeksRemaining > 0 {
                            Text("\(player.injuryWeeksRemaining)w")
                                .font(.system(size: DSType.Size.caption))
                                .foregroundStyle(Color.danger)
                        }
                    }
                }
            }

            // Depth chart status
            if isInDepthChart && !isCurrent {
                Text("In Chart")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.accentGold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.accentGold.opacity(0.15)))
            }

            // OVR badge
            Text("\(player.overall)")
                .font(.callout.weight(.bold).monospacedDigit())
                .foregroundStyle(Color.forRating(player.overall))
                .frame(width: 32, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private func positionColor(_ side: PositionSide) -> Color {
        switch side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }
}

// MARK: - Candidate Player

private struct CandidatePlayer {
    let player: Player
    let isNatural: Bool
    let versatility: VersatilityRating
    let isViable: Bool
    let ovrDelta: Int
}

// MARK: - Safe Collection Index

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DepthChartView(career: Career(
            playerName: "John Doe",
            role: .gm,
            capMode: .simple
        ))
    }
    .modelContainer(for: [Career.self, Player.self], inMemory: true)
}
