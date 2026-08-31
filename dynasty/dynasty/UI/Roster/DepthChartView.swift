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
    /// One-line confirmation of what the last edit actually did, e.g. "Filled 6
    /// empty slots" or "Kwabena Winchester is now your kick returner". Without
    /// it the wand looked like it had done nothing — the chart it fills is
    /// mostly below the fold — and a manual swap two cards down said nothing at
    /// all, so the automated action got a sentence and the deliberate one got
    /// silence.
    @State private var statusMessage: String?
    @State private var statusTone: StatusTone = .neutral
    /// Guards the auto-dismiss timer so a second tap cannot hide the newer toast.
    @State private var statusFlashID = 0
    /// Set while the Auto-Set confirmation is on screen.
    @State private var pendingAutoSet = false
    /// The chart as it stood before the last Auto-Set, so the toast can offer
    /// the way back. Auto-Set replaces the WHOLE chart; without this the user's
    /// own work is gone with no trace anywhere on the screen.
    @State private var chartBeforeAutoSet: DepthChart?
    /// Latest development-report verdict per player, loaded once. Three backs
    /// rated 66/65/64 are indistinguishable on the row; which of them is
    /// climbing is the reason to open this screen twice a season.
    @State private var trajectory: [UUID: TrajectoryMark] = [:]

    /// One player's line in the newest development report, reduced to what a
    /// 10 pt indicator can carry plus the sentence VoiceOver reads out.
    private struct TrajectoryMark {
        enum Direction { case rising, breakout, stalled }
        let direction: Direction
        /// The report's own words, e.g. "+1 Route Running".
        let detail: String

        var glyph: String {
            switch direction {
            case .rising:   return "arrow.up.right"
            case .breakout: return "arrow.up.forward.circle.fill"
            case .stalled:  return "minus"
            }
        }

        var tint: Color {
            switch direction {
            case .rising:   return .success
            case .breakout: return .eliteGreen
            case .stalled:  return .textTertiary
            }
        }
    }

    /// What the toast is reporting. Green is a claim, not a decoration: an
    /// action that discarded the user's own choices must not be dressed as an
    /// improvement.
    private enum StatusTone {
        case success
        case neutral
    }

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

    /// Slots on a side that have a starter but nobody behind him.
    ///
    /// The tab bar used to count only empty STARTER slots while the group pill
    /// one level down ALSO went amber on a thin room, so two defensive rooms
    /// with nobody behind the starter were invisible from the Offense tab.
    private func thinRooms(on side: PositionSide) -> Int {
        slots(on: side).filter { isThin($0) }.count
    }

    /// A room the club cannot lose a man from: rankable depth, one body in it.
    private func isThin(_ slot: DepthChartSlot) -> Bool {
        slot.maxDepth > 1 && bodiesStanding(in: slot) == 1
    }

    /// Men actually rendered in this slot's rows — a name parked past the last
    /// drawn row is not depth the user can see.
    private func bodiesStanding(in slot: DepthChartSlot) -> Int {
        depthChart.depthOrder(for: slot).prefix(slot.maxDepth).compactMap { playerLookup[$0] }.count
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
                SlotGroup(id: "DL", name: "Defensive Line", icon: "bolt.shield", slots: [.LE, .DT1, .DT2, .RE]),
                SlotGroup(id: "LB", name: "Linebackers", icon: "shield", slots: [.LOLB, .MLB, .ROLB]),
                SlotGroup(id: "DB", name: "Secondary", icon: "eye", slots: [.CB1, .CB2, .FS, .SS]),
            ]
        case .specialTeams:
            return [
                SlotGroup(id: "Kickers", name: "Kickers & Punters", icon: "sportscourt", slots: [.K, .P]),
                SlotGroup(id: "Operation", name: "Snap & Hold", icon: "hand.raised.fill", slots: [.LS, .H]),
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

    /// The kicker and the punter only.
    ///
    /// `TeamStrength.lineupSlots` excludes special teams by construction, so on
    /// the Special Teams tab all three pills were frozen — the biggest numerals
    /// on the screen described nothing the tab could change. The returners are
    /// left out of this one too, and deliberately: KR and PR are ranked on
    /// speed and agility, so averaging their OVR in would quote a number
    /// neither slot uses. Their rows carry SPD/AGI instead.
    ///
    /// The long snapper and the holder are out of it for the same reason the
    /// pill is labelled K/P: their overall is a grade on snapping and holding,
    /// two things a kicking number has no business averaging in.
    private var kickingOVR: Int {
        TeamStrength.ovr(chart: depthChart, slots: [.K, .P], lookup: playerLookup)
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
                    // A twelve-position chart is not a reading column. At
                    // `contentMeasure` (720) each depth row spent ~380 pt of its
                    // width on nothing while Offense still cost two screens of
                    // scroll and Special Teams left a third of the iPad blank —
                    // `wideMeasure` is what Theme.swift describes for
                    // "two-up card rows", which is what the groups now draw.
                    .frame(maxWidth: DSLayout.wideMeasure)
                    .frame(maxWidth: .infinity)
                }
            }

            // Confirmation of the last edit — automated or manual
            if let message = statusMessage {
                VStack {
                    statusToast(message)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    Spacer()
                }
            }
        }
        .confirmationDialog(
            "Replace the whole depth chart?",
            isPresented: $pendingAutoSet,
            titleVisibility: .visible
        ) {
            Button("Auto-Set", role: .destructive) { applyAutoSet() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Every slot is refilled with the best available player by overall rating. Any changes you made by hand are replaced.")
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
                    if let assigned = playerLookup[playerID] {
                        flashEdit(placementSentence(assigned, slot: state.slot, index: state.slotIndex))
                    }
                    comparisonState = nil
                },
                onClear: {
                    if let currentDepth = depthChart.depthOrder(for: state.slot)[safe: state.slotIndex] {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            depthChart.remove(slot: state.slot, playerID: currentDepth)
                        }
                        persistDepthChart()
                        let name = playerLookup[currentDepth]?.fullName ?? "That player"
                        flashEdit("\(name) is off the \(state.slot.displayName.lowercased()) chart.")
                    }
                    comparisonState = nil
                },
                onDismiss: { comparisonState = nil }
            )
        }
        .task {
            loadOrSeedDepthChart()
            loadTrajectory()
        }
    }

    /// What a placement actually means, in a sentence. A manual edit — an
    /// assignment or a reorder — used to change two names inside one card and
    /// nothing else on a 1032 pt screen, so the automated action got a
    /// confirmation and the deliberate one got silence.
    private func placementSentence(_ player: Player, slot: DepthChartSlot, index: Int) -> String {
        guard index == 0 else {
            return "\(player.fullName) is \(depthLabel(index: index).lowercased()) at \(slot.shortLabel)."
        }
        if slot.isPackageRole {
            return "\(player.fullName) is your first-choice \(slot.displayName.lowercased())."
        }
        return "\(player.fullName) is now your \(slot.displayName.lowercased())."
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

    /// Folds the newest development report into a playerID → verdict map.
    ///
    /// Three backs rated 66 / 65 / 64, aged 25 / 25 / 24, are the same row
    /// three times over — nothing on the card says which of them is climbing,
    /// though the app has been recording exactly that every week. Read once
    /// here rather than per row: `Career.developmentReports` decodes JSON on
    /// every access.
    private func loadTrajectory() {
        guard let latest = career.developmentReports.first else { return }
        var marks: [UUID: TrajectoryMark] = [:]
        for entry in latest.risers {
            marks[entry.playerID] = TrajectoryMark(direction: .rising, detail: entry.detail)
        }
        for entry in latest.breakouts {
            marks[entry.playerID] = TrajectoryMark(direction: .breakout, detail: entry.detail)
        }
        // Stalled last so a man in two lists keeps the worse verdict — "he
        // broke out AND he is stalled" is not a thing one glyph can say.
        for entry in latest.stalled {
            marks[entry.playerID] = TrajectoryMark(direction: .stalled, detail: entry.detail)
        }
        trajectory = marks
    }

    // MARK: - Team Overall Bar

    /// TEAM, then the unit pills — with the one the open tab can actually move
    /// ringed, and a K/P pill that only exists where it means something.
    private var teamOverallBar: some View {
        HStack(spacing: 16) {
            ovrPill(label: "TEAM", value: teamOVR, isLive: false)
            Spacer()
            ovrPill(label: "OFF", value: offenseOVR, isLive: selectedTab == .offense)
            ovrPill(label: "DEF", value: defenseOVR, isLive: selectedTab == .defense)
            if selectedTab == .specialTeams {
                ovrPill(label: "K/P", value: kickingOVR, isLive: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.card)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: DSCornerRadius.card)
                        .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                )
        )
    }

    private func ovrPill(label: String, value: Int, isLive: Bool) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: DSType.Size.micro, weight: .bold))
                .foregroundStyle(isLive ? Color.textSecondary : Color.textTertiary)
            Text("\(value)")
                .font(.system(size: DSType.Size.callout, weight: .heavy).monospacedDigit())
                .foregroundStyle(Color.forRating(value))
        }
        .padding(.horizontal, isLive ? 8 : 0)
        .padding(.vertical, isLive ? 3 : 0)
        .background(
            isLive
                ? Capsule().strokeBorder(Color.surfaceBorder, lineWidth: 1)
                : nil
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isLive ? "\(label) \(value), the unit you are editing" : "\(label) \(value)")
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
                        // An empty starter blocks the next Advance; a thin room
                        // only bites when somebody goes down. Two marks, in that
                        // order of severity, so the harder problem still wins.
                        let gaps = unfilledStarters(on: side)
                        let thin = thinRooms(on: side)
                        if gaps > 0 {
                            HStack(spacing: 2) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: DSType.Size.micro, weight: .bold))
                                Text("\(gaps)")
                                    .font(.system(size: DSType.Size.micro, weight: .heavy).monospacedDigit())
                            }
                            .foregroundStyle(selectedTab == side ? Color.backgroundPrimary : Color.warning)
                        } else if thin > 0 {
                            HStack(spacing: 2) {
                                Image(systemName: "circle.righthalf.filled")
                                    .font(.system(size: DSType.Size.micro, weight: .bold))
                                Text("\(thin)")
                                    .font(.system(size: DSType.Size.micro, weight: .heavy).monospacedDigit())
                            }
                            .foregroundStyle(selectedTab == side ? Color.backgroundPrimary : Color.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 8)
                    .background(
                        selectedTab == side ? Color.accentBlue : Color.clear,
                        in: RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                    )
                    .overlay(
                        selectedTab == side
                            ? nil
                            : RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                                .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                    )
                }
                .contentShape(RoundedRectangle(cornerRadius: DSCornerRadius.inline))
                .accessibilityLabel(tabAccessibilityLabel(side))
            }
        }
        .padding(5)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: DSCornerRadius.card))
    }

    private func tabAccessibilityLabel(_ side: PositionSide) -> String {
        let gaps = unfilledStarters(on: side)
        let thin = thinRooms(on: side)
        if gaps > 0 {
            return "\(side.rawValue), \(gaps) starter slot\(gaps == 1 ? "" : "s") unfilled"
        }
        if thin > 0 {
            return "\(side.rawValue), \(thin) position\(thin == 1 ? "" : "s") with no backup"
        }
        return side.rawValue
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
            // A one-tap button that silently replaces the WHOLE chart is not a
            // fill, it is a discard, and "Auto-Set" reads to a football fan as
            // "fill in the blanks". Ask first — but only when there is something
            // to lose, so the empty-chart path the Lineup Incomplete dialog
            // sends people down is still one tap.
            if hasAnyAssignment {
                pendingAutoSet = true
            } else {
                applyAutoSet()
            }
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

    private var hasAnyAssignment: Bool {
        DepthChartSlot.allCases.contains { depthChart.starter(for: $0) != nil }
    }

    /// Runs the auto-generator and reports what it changed.
    ///
    /// `autoGenerate` rebuilds the whole chart, so "did anything happen?" is
    /// answered by diffing occupancy before and after rather than by trusting
    /// the call: filling six holes and re-ordering three rooms are different
    /// outcomes and read as different sentences.
    private func applyAutoSet() {
        let before = occupancySnapshot()
        let previousChart = depthChart
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
        // Only offer the way back when there is something to go back TO.
        chartBeforeAutoSet = replaced > 0 ? previousChart : nil
        flash(
            autoSetSummary(filled: filled, replaced: replaced),
            tone: replaced > 0 ? .neutral : .success
        )
    }

    private func undoAutoSet() {
        guard let previous = chartBeforeAutoSet else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            depthChart = previous
        }
        persistDepthChart()
        chartBeforeAutoSet = nil
        flash("Your chart is back.", tone: .neutral)
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

    /// What Auto-Set did, in the plainest words available.
    ///
    /// "Re-ordered N slots by overall" was told in success green, which reads
    /// to a casual player as "your lineup got better" — for an action whose
    /// whole effect was to throw away a decision they had just made. Filling a
    /// hole is a success; replacing a standing pick is a fact.
    private func autoSetSummary(filled: Int, replaced: Int) -> String {
        switch (filled, replaced) {
        case (0, 0):
            return "No change — every slot already held the top man by overall."
        case (0, let changed):
            return "Replaced your pick in \(changed) filled slot\(changed == 1 ? "" : "s")."
        case (let empty, 0):
            return "Filled \(empty) empty slot\(empty == 1 ? "" : "s")."
        case (let empty, let changed):
            return "Filled \(empty) empty slot\(empty == 1 ? "" : "s") · replaced \(changed)."
        }
    }

    /// Reports one deliberate edit. A hand-made change supersedes the Auto-Set
    /// it followed, so the way back stops being offered the moment the user
    /// starts building on top of it — an "Undo" that quietly took a manual
    /// swap with it would be the same discard this toast exists to prevent.
    private func flashEdit(_ message: String) {
        chartBeforeAutoSet = nil
        flash(message, tone: .neutral)
    }

    private func flash(_ message: String, tone: StatusTone) {
        statusFlashID += 1
        let flashID = statusFlashID
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            statusMessage = message
            statusTone = tone
        }
        // An undoable message has to outlive a glance across a 1032 pt screen.
        let life: TimeInterval = chartBeforeAutoSet == nil ? 2.6 : 6.0
        DispatchQueue.main.asyncAfter(deadline: .now() + life) {
            if flashID == statusFlashID {
                withAnimation(.easeOut(duration: 0.3)) {
                    statusMessage = nil
                    chartBeforeAutoSet = nil
                }
            }
        }
    }

    private func statusToast(_ message: String) -> some View {
        let accent = statusTone == .success ? Color.success : Color.accentBlue
        return HStack(spacing: 10) {
            // Not `arrow.triangle.swap`: that glyph already means "playing out
            // of position" on every row underneath.
            Image(systemName: statusTone == .success ? "checkmark.circle.fill" : "arrow.up.arrow.down.circle.fill")
                .font(.system(size: DSType.Size.callout, weight: .semibold))
                .foregroundStyle(accent)
            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
            Spacer(minLength: 0)
            if chartBeforeAutoSet != nil {
                Button("Undo", action: undoAutoSet)
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(Color.accentGold)
                    .buttonStyle(.plain)
                    .accessibilityHint("Restores the depth chart as it stood before Auto-Set")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.card)
                .fill(Color.backgroundSecondary)
                .overlay(RoundedRectangle(cornerRadius: DSCornerRadius.card).fill(accent.opacity(0.12)))
                .overlay(
                    RoundedRectangle(cornerRadius: DSCornerRadius.card)
                        .strokeBorder(accent.opacity(0.4), lineWidth: 1)
                )
        )
    }

    // MARK: - Group Collapse Controls

    private var groupCollapseControls: some View {
        HStack(spacing: 6) {
            Image(systemName: "list.bullet.indent")
                .font(.system(size: DSType.Size.caption, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
            Text("\(activeSlotGroups.count) groups · \(activeSlots.count) positions · deep = slots with a body in them")
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

    /// How sound a room is, in the three states it can actually be in.
    ///
    /// Two used to cover three. A green check sat over "1/1 · 2/3 deep" — a
    /// quarterback room with an empty third-string row — in exactly the
    /// treatment a genuinely full "4/4 · 8/8 deep" receiver room gets, so the
    /// one signal that says "there is still something to do here" said the
    /// opposite. Between "cannot lose a man" and "nothing to do" there is a
    /// middle, and the pill has to be able to draw it.
    private enum GroupState {
        /// A starter slot is empty, or a room has nobody behind its starter.
        case exposed
        /// Every starter and one backup standing, a spare depth row still open.
        case partial
        /// Every row the cards draw has a body in it.
        case complete

        var glyph: String {
            switch self {
            case .exposed:  return "exclamationmark.circle.fill"
            case .partial:  return "circle.righthalf.filled"
            case .complete: return "checkmark.circle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .exposed:  return .warning
            case .partial:  return .textSecondary
            case .complete: return .success
            }
        }
    }

    /// The two-up card grid the chart is laid out for on an iPad.
    ///
    /// Twelve offensive positions in one column cost two screens of scroll
    /// while 384 pt of every depth row sat empty and a third of the Special
    /// Teams tab stayed blank. `wideMeasure` is the measure `Theme.swift`
    /// describes for "two-up card rows"; this is the two-up.
    ///
    /// Driven by real width rather than by size class: an iPad in a half-width
    /// Split View is still `.regular`, and a 240 pt card cannot hold a name, a
    /// contract and a rating badge on one line.
    private var slotColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 360), spacing: 10)]
    }

    /// The room's problem in the words the accessibility label already used.
    ///
    /// The green/amber rule was real and never stated: one room went green with
    /// an empty row and the next went amber with an empty row, and the only
    /// sentence explaining the difference was spoken to VoiceOver and printed
    /// nowhere. Empty starters outrank thin rooms because that is the one the
    /// next Advance blocks on.
    private func roomWarning(_ slots: [DepthChartSlot]) -> String? {
        let empty = slots.filter { depthChart.starter(for: $0).flatMap { playerLookup[$0] } == nil }
        if !empty.isEmpty {
            let names = empty.map(\.shortLabel).joined(separator: ", ")
            // A package room has no starter to be missing — nobody in it is one.
            return empty.allSatisfy(\.isPackageRole) ? "Nobody at \(names)" : "No starter at \(names)"
        }
        let thin = slots.filter { isThin($0) }
        if !thin.isEmpty {
            return "No backup at \(thin.map(\.shortLabel).joined(separator: ", "))"
        }
        return nil
    }

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
        let warning = roomWarning(groupSlots)
        let state: GroupState = warning != nil
            ? .exposed
            : (filledDepth < totalDepth ? .partial : .complete)
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
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        // A disclosure triangle is navigation, not a decision —
                        // gold on this screen is meant to mark the second.
                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                            .font(.system(size: DSType.Size.caption, weight: .heavy))
                            .foregroundStyle(Color.textSecondary)
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
                            Image(systemName: state.glyph)
                                .font(.system(size: DSType.Size.micro))
                            Text("\(filledStarters)/\(groupSlots.count) \u{00B7} \(filledDepth)/\(totalDepth) deep")
                                .font(.system(size: DSType.Size.caption, weight: .bold).monospacedDigit())
                        }
                        .foregroundStyle(state.tint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(state.tint.opacity(0.12), in: Capsule())
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
                    if let warning {
                        Text(warning)
                            .font(.system(size: DSType.Size.caption, weight: .semibold))
                            .foregroundStyle(Color.warning)
                            .padding(.leading, 22)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: DSCornerRadius.card)
                        .fill(Color.backgroundSecondary)
                        .overlay(
                            RoundedRectangle(cornerRadius: DSCornerRadius.card)
                                .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(group.name), \(filledStarters) of \(groupSlots.count) first-string slots filled, \(filledDepth) of \(totalDepth) depth slots filled\(warning.map { ". \($0)" } ?? ""), \(isCollapsed ? "collapsed, tap to expand" : "expanded, tap to collapse")")

            // Slots — only render when expanded
            if !isCollapsed {
                LazyVGrid(columns: slotColumns, alignment: .leading, spacing: 10) {
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
            // Header. The badge and the abbreviation beside it were the same
            // string — `shortLabel` IS `rawValue` — so one card printed its
            // position six times. The badge keeps the abbreviation; the words
            // beside it are the gloss.
            HStack(spacing: 8) {
                slotBadge(slot)
                Text(slot.displayName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }

            if let note = slot.packageNote {
                Text(note)
                    .font(.system(size: DSType.Size.caption))
                    .foregroundStyle(Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
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
                        // Clamped to the rows the card draws: a "move down" that
                        // sends a man to a row nobody can see is a move the user
                        // cannot undo by looking at it.
                        totalInSlot: min(depth.count, maxSlots)
                    )
                }
            }
        }
        .padding(14)
        // Two-up cards sit in a grid row as tall as its deepest room, so the
        // plate has to grow with the row or a 2-deep card next to a 3-deep one
        // floats in a hole of its own background.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .cardBackground()
    }

    // MARK: - Depth Slot Row

    private func depthSlotRow(
        slot: DepthChartSlot,
        index: Int,
        player: Player?,
        totalInSlot: Int
    ) -> some View {
        // The gold plate is the eleven the game fields, and the fullback is not
        // one of them — the backfield is a single job, running back preferred,
        // everywhere a start is counted. He still leads his own room, so he
        // keeps the top row; he does not keep the starter's colours.
        let isFirstTeam = index == 0 && !slot.isPackageRole
        // A hole in the STARTER line is the thing the lineup gate blocks on, and
        // it used to look exactly like a spare depth row: same plate, same
        // "Tap to assign". Twelve positions deep in a scroll that is the
        // difference between finding it and being told again on the next
        // Advance.
        let isGap = index == 0 && player == nil

        return HStack(spacing: 10) {
            // Reorder stepper — always a PAIR, never a lone chevron.
            //
            // The inert half used to paint `backgroundTertiary` on this row's
            // fill: 1.03:1, which is not dimmed but absent. Ten of the twelve
            // offensive rooms are two deep, so every row in them showed exactly
            // one chevron — the universal iOS "tap to expand" shape, on a
            // control that instead demotes the man beside it.
            if player != nil, totalInSlot > 1 {
                VStack(spacing: 0) {
                    reorderButton(slot: slot, index: index, direction: -1,
                                  isEnabled: index > 0, player: player)
                    reorderButton(slot: slot, index: index, direction: 1,
                                  isEnabled: index < totalInSlot - 1, player: player)
                }
                .background(
                    RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                        .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                )
            } else {
                Color.clear.frame(width: reorderColumnWidth, height: 1)
            }

            // Slot label — the one word the screen exists to assign. It used to
            // share the 10 pt step with "Age 28" and "$848K", four strings of
            // meta out-weighing the rank they qualify.
            Text(depthLabelShort(index: index, slot: slot))
                .font(.system(size: DSType.Size.footnote, weight: .heavy))
                .tracking(0.4)
                .foregroundStyle(isFirstTeam ? Color.accentGold : Color.textSecondary)
                .textCase(.uppercase)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: 66, alignment: .leading)

            // Player info or empty
            Button {
                comparisonState = ComparisonState(slot: slot, slotIndex: index)
            } label: {
                if let player {
                    playerSlotContent(player: player, slot: slot)
                } else {
                    emptySlotContent()
                }
            }
            .buttonStyle(.plain)
        }
        .frame(minHeight: reorderColumnHeight)
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                .fill(
                    isGap ? Color.warning.opacity(0.10)
                        : (isFirstTeam ? Color.accentGold.opacity(0.06) : Color.backgroundTertiary.opacity(0.3))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                        .strokeBorder(
                            isGap ? Color.warning.opacity(0.7)
                                : (isFirstTeam ? Color.accentGold.opacity(0.3) : Color.surfaceBorder.opacity(0.5)),
                            lineWidth: isFirstTeam ? 1 : 0.5
                        )
                )
        )
        .accessibilityLabel(slotAccessibilityLabel(index: index, slot: slot, player: player))
    }

    // MARK: - Reorder Stepper

    /// 44 pt of gutter, split between the two arrows.
    ///
    /// The pair it replaces was 11 × 10 pt of ink with its two centres 9.5 pt
    /// apart — a quarter of the 44 pt minimum, on the one control that rewrites
    /// the lineup. A true 44 × 44 pair would make every depth row 88 pt tall and
    /// push the twelfth position three screens down, so the column takes the
    /// full 44 across (the row had 384 pt of dead width to pay for it) and
    /// splits the row's height between up and down: 44 × 30 each, centres 30 pt
    /// apart rather than 9.5.
    private var reorderColumnWidth: CGFloat { 44 }
    private var reorderStepHeight: CGFloat { 30 }
    private var reorderColumnHeight: CGFloat { reorderStepHeight * 2 }

    @ViewBuilder
    private func reorderButton(
        slot: DepthChartSlot,
        index: Int,
        direction: Int,
        isEnabled: Bool,
        player: Player?
    ) -> some View {
        let glyph = Image(systemName: direction < 0 ? "chevron.up" : "chevron.down")
            .font(.system(size: DSType.Size.caption, weight: .bold))
            .frame(width: reorderColumnWidth, height: reorderStepHeight)

        if isEnabled {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    depthChart.swap(slot: slot, indexA: index, indexB: index + direction)
                }
                persistDepthChart()
                if let player {
                    flashEdit(placementSentence(player, slot: slot, index: index + direction))
                }
            } label: {
                glyph
                    .foregroundStyle(Color.textSecondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(direction < 0 ? "Move up" : "Move down")
            .accessibilityHint(player.map { "Moves \($0.fullName) \(direction < 0 ? "up" : "down") the \(slot.displayName.lowercased()) order" } ?? "")
        } else {
            // Present and clearly inert, not erased.
            glyph
                .foregroundStyle(Color.textTertiary.opacity(0.35))
                .accessibilityHidden(true)
        }
    }

    // MARK: - Player Slot Content

    private func playerSlotContent(player: Player, slot: DepthChartSlot) -> some View {
        let alsoStarting = depthChart.startingSlots(of: player.id, excluding: slot)

        return HStack(spacing: 8) {
            // Player name
            VStack(alignment: .leading, spacing: 1) {
                Text(player.fullName)
                    .font(.system(size: DSType.Size.body, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                // Two-up cards make the meta line the tightest thing on the row,
                // so it drops a field rather than truncating into three
                // ellipses. Age goes first, then the overall the returner slot
                // does not rank on; the money and its term are the last to go,
                // because a salary with no term is the half-fact this line was
                // printing before.
                ViewThatFits(in: .horizontal) {
                    metaLine(player, slot: slot, showAge: true, showOverall: true)
                    metaLine(player, slot: slot, showAge: false, showOverall: true)
                    metaLine(player, slot: slot, showAge: false, showOverall: false)
                }
            }

            Spacer(minLength: 4)

            // Indicators
            HStack(spacing: 6) {
                // Every other job this man already holds. Three gold starter
                // plates across two tabs used to be three unrelated rows: the
                // WR1 who is also the KR and the PR was drawn exactly like a
                // man with one job, and the out-of-position arrow cannot cover
                // it because `acceptsAnyPosition` suppresses that arrow for
                // precisely the returner slots where the doubling happens.
                if !alsoStarting.isEmpty {
                    // `fixedSize` is load-bearing, not styling. In the two-up
                    // grid this capsule is the first thing the row's HStack
                    // offers to shrink, and a truncated "ALSO…" loses the only
                    // fact it carries — WHICH other jobs the man holds. The
                    // label is at most "ALSO KR·PR+2", so letting it hold its
                    // width costs the meta line a few points and never the name.
                    Text(alsoLabel(alsoStarting))
                        .font(.system(size: DSType.Size.micro, weight: .bold))
                        .foregroundStyle(Color.warning)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.warning.opacity(0.14)))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(1)
                        .accessibilityLabel("Also starts at \(alsoStarting.map(\.displayName).joined(separator: ", "))")
                }

                if let mark = trajectory[player.id] {
                    trajectoryIndicator(mark)
                }

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

                // The number this slot is ranked on
                if let trait = slot.rankingTrait {
                    traitBadge(trait: trait, player: player)
                } else {
                    ratingBadge(value: player.overall)
                }
            }
        }
        .contentShape(Rectangle())
    }

    /// The line under the name: who he is, what he costs, and — on a returner
    /// row only — the overall the slot does not rank on.
    private func metaLine(
        _ player: Player,
        slot: DepthChartSlot,
        showAge: Bool,
        showOverall: Bool
    ) -> some View {
        HStack(spacing: 6) {
            // Kept even on KR/PR, where it is the only thing on the card saying
            // the returner is a receiver.
            Text(player.position.rawValue)
                .font(.system(size: DSType.Size.micro, weight: .medium))
            if showAge {
                Text("Age \(player.age)")
                    .font(.system(size: DSType.Size.micro))
            }
            Text(contractLine(player))
                .font(.system(size: DSType.Size.micro))
            if showOverall, slot.rankingTrait != nil {
                Text("\(player.overall) OVR")
                    .font(.system(size: DSType.Size.micro))
            }
        }
        .foregroundStyle(Color.textTertiary)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    /// Money plus term. The row already spent the width on a salary, and an
    /// annual figure with no years attached cannot be reasoned about on the
    /// screen that decides who plays: $54.0M expiring and $54.0M with four
    /// years to run are opposite answers to "does the 32-year-old stay WR1".
    private func contractLine(_ player: Player) -> String {
        // `annualSalary` is in thousands, so integer division printed "$0M" for
        // everyone on a rookie deal — the ledger's own formatter says "$750K".
        let money = CommittedCapLedger.money(player.annualSalary)
        switch player.contractYearsRemaining {
        case ..<1:      return money
        case 1:         return "\(money) \u{00B7} exp"
        case let years: return "\(money) \u{00B7} \(years)yr"
        }
    }

    /// "ALSO KR·PR" — the other starting jobs, capped at what the row can hold.
    private func alsoLabel(_ slots: [DepthChartSlot]) -> String {
        let named = slots.prefix(2).map(\.shortLabel).joined(separator: "\u{00B7}")
        return slots.count > 2 ? "ALSO \(named)+\(slots.count - 2)" : "ALSO \(named)"
    }

    private func trajectoryIndicator(_ mark: TrajectoryMark) -> some View {
        Image(systemName: mark.glyph)
            .font(.system(size: DSType.Size.caption, weight: .bold))
            .foregroundStyle(mark.tint)
            .accessibilityLabel(mark.detail)
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
                RoundedRectangle(cornerRadius: DSCornerRadius.tight)
                    .fill(Color.forRating(value).opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: DSCornerRadius.tight)
                            .strokeBorder(Color.forRating(value).opacity(0.3), lineWidth: 1)
                    )
            )
    }

    // MARK: - Trait Badge

    /// The number the SLOT ranks on, where the row prints its rating.
    ///
    /// KR and PR are filled by speed and agility — in `autoGenerate`, in
    /// `reconcile`, and in the picker's default sort — and neither figure was
    /// printed anywhere on the app. The returner rows quoted an overall the
    /// slot ignores, so the candidate list arrived ordered by an invisible
    /// number and the visible column ran out of sequence.
    private func traitBadge(trait: DepthChartSlot.RankingTrait, player: Player) -> some View {
        let value = trait.value(of: player)
        return VStack(spacing: 0) {
            Text("\(value)")
                .font(.system(size: DSType.Size.body, weight: .bold).monospacedDigit())
                .foregroundStyle(Color.forRating(value))
            Text(trait.shortLabel)
                .font(.system(size: DSType.Size.micro, weight: .bold))
                .foregroundStyle(Color.textTertiary)
        }
        .frame(width: 38, height: 32)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.tight)
                .fill(Color.forRating(value).opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: DSCornerRadius.tight)
                        .strokeBorder(Color.forRating(value).opacity(0.3), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(trait.displayName) \(value)")
    }

    // MARK: - Fatigue Meter

    private func fatigueMeter(value: Int) -> some View {
        VStack(spacing: 1) {
            Image(systemName: "bolt.fill")
                .font(.system(size: DSType.Size.micro))
                .foregroundStyle(fatigueColor(value))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.backgroundTertiary)
                    Capsule()
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

    /// What rank 0 is called on THIS slot. On a package slot it is not
    /// "Starter": the top man there leads his room and is nowhere in the eleven
    /// the game fields, so the word the whole screen exists to assign has to
    /// stop being spent on him.
    private func depthLabel(index: Int, slot: DepthChartSlot) -> String {
        if index == 0 && slot.isPackageRole { return "1st Choice" }
        return depthLabel(index: index)
    }

    /// The printed label. "3RD STRING" and "1ST CHOICE" are too wide for the
    /// rank column and wrapped to two lines — which pushed the row's reorder
    /// chevrons and its player's name out of line with every row above it.
    /// `depthLabel` still says the whole thing out loud.
    private func depthLabelShort(index: Int, slot: DepthChartSlot) -> String {
        if index == 0 && slot.isPackageRole { return "1st" }
        return index == 2 ? "3rd" : depthLabel(index: index)
    }

    private func slotAccessibilityLabel(index: Int, slot: DepthChartSlot, player: Player?) -> String {
        let rank = depthLabel(index: index, slot: slot)
        if let player {
            if let trait = slot.rankingTrait {
                return "\(rank): \(player.fullName), \(trait.displayName.lowercased()) \(trait.value(of: player))"
            }
            return "\(rank): \(player.fullName), overall \(player.overall)"
        }
        return "\(rank): empty, tap to assign"
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
            if let trait = slot.rankingTrait {
                return trait.value(of: a.player) > trait.value(of: b.player)
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
        // The top of a package room is first in that room, not one of the
        // eleven — same reason the card no longer draws him in the gold plate.
        case 0: return slot.isPackageRole ? "1st Choice" : "Starter"
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

    /// The first segment is labelled for what it actually sorts on. On KR and PR
    /// it said "Overall" and ordered the list by speed or agility, so the one
    /// visible column ran out of sequence against the segment naming it.
    private func sortLabel(_ mode: ComparisonSort) -> String {
        guard mode == .overall, let trait = slot.rankingTrait else { return mode.rawValue }
        return trait.displayName
    }

    private var sortPicker: some View {
        Picker("Sort", selection: $sortMode) {
            ForEach(ComparisonSort.allCases, id: \.self) { mode in
                Text(sortLabel(mode)).tag(mode)
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
        // Every slot he already stands in, not just this one. Scoped to the open
        // slot, the badge stayed dark for a man who was already the WR1 and the
        // KR — so the sheet that makes the double-booking said nothing about it,
        // and the model deliberately permits it (`DepthChart.assign`).
        let heldElsewhere = depthChart.slots(holding: player.id, excluding: slot)

        return HStack(spacing: 10) {
            // Position badge
            Text(player.position.rawValue)
                .font(.system(size: DSType.Size.micro, weight: .bold))
                .foregroundStyle(Color.backgroundPrimary)
                .frame(width: 28, height: 18)
                .background(positionColor(player.position.side), in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))

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

                // What the other two pickers already print beside the same fit
                // grade for a man lined up away from his own position — the
                // `RosterView` starter picker and the `FormationView` player
                // picker both show `overall x familiarity% = ~N effective`.
                // This one showed the grade and no cost at all, which made the
                // depth chart the odd screen out.
                //
                // The number is COSMETIC and stays cosmetic:
                // `VersatilityDevelopmentEngine.positionPerformanceModifier`
                // has no call sites, the sim never fields a man off-position,
                // and no snap is docked for this anywhere. The delta in the
                // indicators column is position-blind for the same reason —
                // `DepthChart.teamOverall` averages raw `player.overall` — so
                // the two figures in this row measure different things on
                // purpose until the sim is taught the difference.
                //
                // Printed only where there is a familiarity reading to quote.
                // Both other pickers list a man as versatile only at
                // `familiarity(at:) > 0`; at zero there is nothing measured,
                // and "74 x 0% = ~0 effective" would be an invention rather
                // than a quotation.
                if !candidate.isNatural, !slot.acceptsAnyPosition {
                    let familiarity = player.familiarity(at: slot.basePosition)
                    if familiarity > 0 {
                        let effective = Int(Double(player.overall) * Double(familiarity) / 100.0)
                        Text("\(player.position.rawValue) at \(slot.basePosition.rawValue): "
                            + "\(player.overall) \u{00d7} \(familiarity)% = ~\(effective) effective")
                            .font(.system(size: DSType.Size.footnote))
                            .foregroundStyle(Color.warning)
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

            // Depth chart status — named, so the conflict is readable
            if !heldElsewhere.isEmpty && !isCurrent {
                Text("In \(heldElsewhere.prefix(2).map(\.shortLabel).joined(separator: "\u{00B7}"))")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.warning)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.warning.opacity(0.15)))
                    .accessibilityLabel("Already in the chart at \(heldElsewhere.map(\.displayName).joined(separator: ", "))")
            }

            // The number this slot ranks on, with the overall beside it when
            // they are not the same figure
            if let trait = slot.rankingTrait {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(trait.value(of: player))")
                        .font(.callout.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.forRating(trait.value(of: player)))
                    Text("\(trait.shortLabel) \u{00B7} \(player.overall) OVR")
                        .font(.system(size: DSType.Size.micro))
                        .foregroundStyle(Color.textTertiary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(trait.displayName) \(trait.value(of: player)), overall \(player.overall)")
            } else {
                Text("\(player.overall)")
                    .font(.callout.weight(.bold).monospacedDigit())
                    .foregroundStyle(Color.forRating(player.overall))
                    .frame(width: 32, alignment: .trailing)
            }
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
