import SwiftUI

// MARK: - Stage cell model
//
// The bar is a dumb renderer. Everything it draws — state, counters, the reason
// a locked stage is locked — is computed once by the hub off
// `DraftPrepProgress` and handed down as a value, so the bar cannot disagree
// with the screen underneath it and a body re-evaluation never re-walks a
// 350-man draft class.

/// One stage of the pre-draft process, as the process bar draws it.
///
/// Built straight off a ``DraftPrepProgress/Stage`` — the counter string, the
/// meter fraction and the lock sentence are all that struct's, so the bar and
/// the required-task chain can never print different numbers for the same work.
struct DraftPrepStageCell: Identifiable, Equatable {

    /// Where the club stands relative to this stage.
    ///
    /// Four states, not two: the old hub HID everything ahead of the current
    /// step, so a user parked on stage 1 was looking at a six-tab screen with no
    /// evidence that pro days, workouts or visits existed at all. A locked stage
    /// is drawn, greyed, with the sentence that unlocks it.
    enum State: Equatable {
        /// Behind the club. Its screen opens read-only.
        case done
        /// Where the club is standing **and may work**. Its screen is the
        /// working surface.
        ///
        /// Never emitted for a stage that is shut — see the init below. Standing
        /// somewhere and being allowed to work there are two different claims,
        /// and only the second one may be drawn as an invitation.
        case current
        /// Ahead of the club but already reachable — `DraftPrepProgress.reach`
        /// opens the next room the moment the current stage is satisfied, so
        /// this is the common state, not an edge case.
        case open
        /// Shut, by the pipeline or by the calendar. Usually ahead of the club —
        /// but the stage it is STANDING in lands here too whenever the calendar
        /// has not opened it, which is the whole pre-draft pipeline outside the
        /// four pre-draft phases.
        case locked
    }

    let step: DraftPrepStep
    let state: State
    /// "30/60 interviews", or "Done" / "Not read" for the stages that are a read
    /// rather than a spend — or "Opens at combine" for a stage the season has
    /// not reached. Straight off `DraftPrepProgress.Stage.counter`.
    let counterText: String
    /// 0…1 fill for the cell's hairline meter.
    let fraction: Double
    /// One clause saying what opens this stage. Empty unless it is shut.
    let lockReason: String
    /// `true` when the calendar, not the club's own work, is what shuts this
    /// stage. Changes the words, never the state: a wait is drawn locked.
    let isWaitingOnCalendar: Bool

    var id: String { step.rawValue }

    /// Screen-reader sentence: state, name, progress, and the unlock clause.
    var accessibilityText: String {
        var parts = ["Stage \(step.order + 1), \(step.displayName)"]
        switch state {
        case .done:    parts.append("complete")
        case .current: parts.append("current stage")
        case .open:    parts.append("open")
        case .locked:  parts.append(isWaitingOnCalendar ? "waiting for the calendar" : "locked")
        }
        parts.append(counterText)
        if !lockReason.isEmpty { parts.append(lockReason) }
        return parts.joined(separator: ", ")
    }

    init(step: DraftPrepStep, state: State, stage: DraftPrepProgress.Stage) {
        self.step = step
        // LOCKED WINS OVER CURRENT (#107). `Career.prepStep` is a floor, so
        // outside the pre-draft window it still points at stage 1 — and the bar
        // drew that stage in February with the gold "1" puck, the current-stage
        // ring and "Not read" underneath, over a combine nobody had held. The
        // hub's `stageState` already resolves this; the coercion is here as well
        // because the cell holds both facts and no caller should be able to draw
        // an invitation over a shut stage. A satisfied stage keeps its tick —
        // `done` is a claim about work, and the work happened.
        self.state = (state == .current && !stage.unlocked) ? .locked : state
        self.counterText = stage.counter
        self.fraction = stage.fraction
        self.lockReason = stage.lockReason ?? ""
        self.isWaitingOnCalendar = stage.isCalendarLocked
    }
}

// MARK: - Process bar

/// The scouting hub's primary navigation: the pre-draft calendar as a strip of
/// stage cells, in order, each carrying its own state and its own count of work.
///
/// This replaces the flat eleven-tab picker. The picker was a list of places,
/// which is the wrong shape for a process — it said nothing about order, nothing
/// about what was finished, and it *hid* every stage the club had not reached,
/// so the two most common failure reports against the shipped wizard ("pro days
/// were completely unavailable", "film study could not be assigned") were both a
/// user looking at a screen that had silently deleted the thing he was looking
/// for. Here every stage is always on screen, in calendar order, and a stage the
/// club cannot work yet says so in words.
struct DraftPrepProcessBar: View {
    let cells: [DraftPrepStageCell]
    /// The stage whose screen is currently showing — not necessarily the stage
    /// the club is standing in: a done stage opens read-only.
    let selected: DraftPrepStep?
    /// Demoted rendering for the surfaces the pipeline is not the subject of
    /// (#130).
    ///
    /// The bar is the wizard's spine and it stays on every screen — the user
    /// asked to always see how much of each stage is done — but on the Big Board
    /// or the draft order it is *context*, not the control the eye should land
    /// on first. Compact keeps the puck (state + stage number) and the counter,
    /// drops the meter, and names only the cell that is selected or current, so
    /// the strip halves in height without losing a single semantic: every state,
    /// every counter, every tap target and the whole accessibility sentence are
    /// unchanged.
    var isCompact: Bool = false
    var onSelect: (DraftPrepStep) -> Void

    private var cellWidth: CGFloat { isCompact ? 60 : 92 }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(cells.enumerated()), id: \.element.id) { index, cell in
                        if index > 0 { connector(before: cell) }
                        cellView(cell)
                            .id(cell.step)
                    }
                }
                .padding(.vertical, 2)
            }
            .onAppear { scroll(proxy, animated: false) }
            .onChange(of: selected) { _, _ in scroll(proxy, animated: true) }
        }
        .mask(
            HStack(spacing: 0) {
                Color.white
                LinearGradient(colors: [.white, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 20)
            }
        )
    }

    private func scroll(_ proxy: ScrollViewProxy, animated: Bool) {
        // Follow the SELECTED stage, falling back to the current one. Without
        // this the bar opens parked on stage 1 and a club six stages in has to
        // hunt for itself. Outside the pre-draft window there IS no current
        // cell — the whole strip is shut — so the head of the pipeline is the
        // honest place to park.
        let target = selected
            ?? cells.first(where: { $0.state == .current })?.step
            ?? cells.first?.step
        guard let target else { return }
        if animated {
            withAnimation(.easeInOut(duration: 0.22)) { proxy.scrollTo(target, anchor: .center) }
        } else {
            proxy.scrollTo(target, anchor: .center)
        }
    }

    // MARK: - Connector

    /// The rail between two cells: gold behind work already done, hairline ahead
    /// of it. It is what makes the strip read as a pipeline rather than as a row
    /// of buttons.
    private func connector(before cell: DraftPrepStageCell) -> some View {
        Rectangle()
            .fill(cell.state == .done || cell.state == .current ? Color.accentGold : Color.surfaceBorder)
            .frame(width: 10, height: 1.5)
            .accessibilityHidden(true)
    }

    // MARK: - Cell

    private func cellView(_ cell: DraftPrepStageCell) -> some View {
        let isSelected = selected == cell.step
        // Compact reserves the name slot on EVERY cell even when it prints
        // nothing, so the pucks stay on one line across the strip — a row of
        // markers that jog up and down reads as a rendering fault.
        let namesThisCell = !isCompact || isSelected || cell.state == .current
        return Button {
            onSelect(cell.step)
        } label: {
            VStack(spacing: isCompact ? 2 : 3) {
                marker(cell, isSelected: isSelected)

                Text(namesThisCell ? cell.step.displayName : "")
                    .font(.system(size: isCompact ? 9 : DSType.Size.micro,
                                  weight: isSelected ? .heavy : .semibold))
                    .foregroundStyle(nameColor(cell, isSelected: isSelected))
                    .lineLimit(isCompact ? 1 : 2)
                    .minimumScaleFactor(isCompact ? 0.75 : 1)
                    .multilineTextAlignment(.center)
                    .frame(height: isCompact ? 11 : 24, alignment: .top)
                    .fixedSize(horizontal: false, vertical: true)

                counterLine(cell)
                if !isCompact { meter(cell) }
            }
            .frame(width: cellWidth)
            .padding(.vertical, isCompact ? 3 : 6)
            .background(
                RoundedRectangle(cornerRadius: DSCornerRadius.tight)
                    .fill(isSelected ? Color.backgroundTertiary : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DSCornerRadius.tight)
                    .strokeBorder(
                        isSelected ? Color.accentGold.opacity(0.55) : Color.clear,
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(cell.accessibilityText)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// The numbered puck: a check when the stage is finished, a lock when it is
    /// ahead, the stage number otherwise.
    private func marker(_ cell: DraftPrepStageCell, isSelected: Bool) -> some View {
        let puck: CGFloat = isCompact ? 16 : 20
        let ring: CGFloat = isCompact ? 20 : 24
        let glyph: CGFloat = isCompact ? 8 : DSType.Size.micro
        return ZStack {
            Circle()
                .fill(markerFill(cell))
                .frame(width: puck, height: puck)
            Circle()
                .strokeBorder(
                    cell.state == .current ? Color.accentGold
                        : cell.state == .open ? Color.accentGold.opacity(0.5) : Color.clear,
                    lineWidth: 1.5
                )
                .frame(width: ring, height: ring)
            switch cell.state {
            case .done:
                Image(systemName: "checkmark")
                    .font(.system(size: glyph, weight: .black))
                    .foregroundStyle(Color.backgroundPrimary)
            case .current:
                Text("\(cell.step.order + 1)")
                    .font(.system(size: glyph, weight: .black).monospacedDigit())
                    .foregroundStyle(Color.backgroundPrimary)
            case .open:
                Text("\(cell.step.order + 1)")
                    .font(.system(size: glyph, weight: .black).monospacedDigit())
                    .foregroundStyle(Color.accentGold)
            case .locked:
                Image(systemName: "lock.fill")
                    .font(.system(size: isCompact ? 7 : 9, weight: .bold))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .frame(height: ring)
    }

    private func markerFill(_ cell: DraftPrepStageCell) -> Color {
        switch cell.state {
        case .done:    return Color.success
        case .current: return Color.accentGold
        // Outlined, not filled: the room is open, nobody is standing in it yet.
        case .open:    return Color.backgroundTertiary
        case .locked:  return Color.backgroundTertiary
        }
    }

    private func nameColor(_ cell: DraftPrepStageCell, isSelected: Bool) -> Color {
        switch cell.state {
        case .current: return .accentGold
        case .open:    return .textPrimary
        case .done:    return isSelected ? .textPrimary : .textSecondary
        case .locked:  return .textTertiaryReadable
        }
    }

    private func counterLine(_ cell: DraftPrepStageCell) -> some View {
        // The counter is the whole point of the bar: the user asked to always
        // see "how much is done per stage", and a chevron between two tab names
        // never said that. The string is `DraftPrepProgress`'s, so the required
        // task in the left bar reads the same numbers.
        Text(cell.counterText)
            .font(.system(size: isCompact ? 9 : DSType.Size.micro, weight: .heavy).monospacedDigit())
            .foregroundStyle(counterColor(cell))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private func counterColor(_ cell: DraftPrepStageCell) -> Color {
        switch cell.state {
        case .locked:  return .textTertiaryReadable
        case .done:    return cell.fraction > 0 ? .success : .textTertiaryReadable
        case .current: return .textPrimary
        case .open:    return .textSecondary
        }
    }

    private func meter(_ cell: DraftPrepStageCell) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.backgroundTertiary)
                Capsule()
                    .fill(cell.state == .done ? Color.success : Color.accentGold)
                    .frame(width: geo.size.width * cell.fraction)
            }
        }
        .frame(width: cellWidth - 24, height: 2.5)
        .accessibilityHidden(true)
    }
}

// MARK: - Primary surface switcher

/// The hub's ONE primary navigation control (#130).
///
/// It replaces a six-chip reference row that sat under a nine-cell process bar
/// under a five-chip mode row: four stacked strips of equally-sized capsules,
/// each drawn in the same 11 pt semibold, each differing from the others only by
/// a fill colour. The user's verdict was exact — *"when is Big Board selected,
/// when Combine"* — and the answer, on the shipped build, was a 1 pt hue
/// difference on a chip in whichever of the four rows happened to own it.
///
/// Three slots now, and the active one is loud by SIZE and FILL, not by hue:
///
///  * **Big Board** — the club's own board, the reference surface every user
///    comes back to.
///  * **The stage surface** — labelled by the stage it shows ("Combine",
///    "Private Workouts"), carrying that stage's number and state, so the
///    pipeline's *current work* is always one tap away and always named.
///  * **Tools** — the remaining reference surfaces (class depth, the mocks, the
///    draft order, the department, next year) behind one labelled menu. They are
///    read-only lookups; none of them is where the spring is won, and none of
///    them earned a permanent quarter of the chrome.
struct ScoutingSurfaceSwitcher: View {

    /// Which of the three slots owns the screen underneath.
    enum Slot: Equatable { case board, stage, tools }

    let boardSubtitle: String
    /// The tab the stage segment shows — the stage screen the user is standing
    /// on, or the club's current stage when he is somewhere else.
    let stageTab: ScoutingTab
    /// "Stage 4 of 9 · Current" — the segment's second line.
    let stageSubtitle: String
    let stageState: DraftPrepStageCell.State
    /// `true` when the CALENDAR, not the club's own work, is what shuts the
    /// stage. Same rule as the process bar: a wait is drawn locked, only the word
    /// changes — LOCKED reads as "you have not got here yet", which is untrue of
    /// a club standing in November.
    var stageIsWaiting: Bool = false
    /// The reference surfaces behind the menu, in the order they are drawn.
    let toolTabs: [ScoutingTab]
    let selected: ScoutingTab
    let active: Slot
    var onSelect: (ScoutingTab) -> Void

    var body: some View {
        HStack(spacing: 8) {
            segment(
                icon: ScoutingTab.board.icon,
                title: ScoutingTab.board.label,
                subtitle: boardSubtitle,
                chip: nil,
                chipTint: .accentGold,
                isActive: active == .board,
                action: { onSelect(.board) }
            )

            segment(
                icon: stageTab.icon,
                title: stageTab.label,
                subtitle: stageSubtitle,
                chip: stageChipText,
                chipTint: stageChipTint,
                isActive: active == .stage,
                action: { onSelect(stageTab) }
            )

            toolsMenu
        }
    }

    // MARK: - Stage chip

    private var stageChipText: String? {
        switch stageState {
        case .current: return "CURRENT"
        case .done:    return "DONE"
        case .open:    return "OPEN"
        case .locked:  return stageIsWaiting ? "WAITING" : "LOCKED"
        }
    }

    private var stageChipTint: Color {
        switch stageState {
        case .current: return .accentGold
        case .done:    return .success
        case .open:    return .accentBlue
        case .locked:  return .textTertiaryReadable
        }
    }

    // MARK: - Segment

    /// One big surface button.
    ///
    /// Active and inactive differ in three dimensions at once — height (56 vs
    /// 44), fill (gold vs tertiary) and type size (16 black vs 13 semibold) —
    /// because a single dimension is what failed here before. Hue alone also
    /// fails colour-blind users and reads as decoration on a screen that already
    /// spends gold on the pipeline.
    private func segment(
        icon: String,
        title: String,
        subtitle: String,
        chip: String?,
        chipTint: Color,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: isActive ? 17 : 13, weight: .bold))
                    .foregroundStyle(isActive ? Color.backgroundPrimary : Color.textSecondary)
                    .frame(width: isActive ? 22 : 16)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(title)
                            .font(.system(size: isActive ? DSType.Size.callout : DSType.Size.footnote,
                                          weight: isActive ? .black : .semibold))
                            .foregroundStyle(isActive ? Color.backgroundPrimary : Color.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if let chip {
                            Text(chip)
                                .font(.system(size: 8, weight: .black))
                                .foregroundStyle(isActive ? Color.backgroundPrimary.opacity(0.75) : chipTint)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(
                                    Capsule().fill(
                                        isActive
                                            ? Color.backgroundPrimary.opacity(0.18)
                                            : chipTint.opacity(0.15)
                                    )
                                )
                        }
                    }
                    Text(subtitle)
                        .font(.system(size: isActive ? DSType.Size.micro : 9, weight: .semibold))
                        .foregroundStyle(isActive
                                         ? Color.backgroundPrimary.opacity(0.8)
                                         : Color.textTertiaryReadable)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, isActive ? 12 : 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: isActive ? 56 : 44)
            .background(
                RoundedRectangle(cornerRadius: DSCornerRadius.card)
                    .fill(isActive ? Color.accentGold : Color.backgroundTertiary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DSCornerRadius.card)
                    .strokeBorder(isActive ? Color.clear : Color.surfaceBorder, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title). \(subtitle)")
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Tools

    /// The reference surfaces, behind one labelled menu.
    ///
    /// It draws itself with the ACTIVE surface's name and icon whenever one of
    /// them owns the screen, so "you are here" is never a claim only a chip two
    /// rows up could make.
    private var toolsMenu: some View {
        let activeTool = active == .tools ? selected : nil
        return Menu {
            ForEach(toolTabs) { tab in
                Button {
                    onSelect(tab)
                } label: {
                    if selected == tab {
                        Label("\(tab.label)  \u{2713}", systemImage: tab.icon)
                    } else {
                        Label(tab.label, systemImage: tab.icon)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: activeTool?.icon ?? "square.grid.2x2")
                    .font(.system(size: activeTool != nil ? 15 : 12, weight: .bold))
                VStack(alignment: .leading, spacing: 1) {
                    Text(activeTool?.label ?? "Tools")
                        .font(.system(size: activeTool != nil ? DSType.Size.body : DSType.Size.caption,
                                      weight: activeTool != nil ? .black : .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if activeTool != nil {
                        Text("Reference")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.backgroundPrimary.opacity(0.8))
                    }
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .black))
            }
            .foregroundStyle(activeTool != nil ? Color.backgroundPrimary : Color.textSecondary)
            .padding(.horizontal, 10)
            .frame(minWidth: 104)
            .frame(height: activeTool != nil ? 56 : 44)
            .background(
                RoundedRectangle(cornerRadius: DSCornerRadius.card)
                    .fill(activeTool != nil ? Color.accentGold : Color.backgroundTertiary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DSCornerRadius.card)
                    .strokeBorder(activeTool != nil ? Color.clear : Color.surfaceBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(activeTool.map { "Tools. \($0.label) selected" } ?? "Tools. Reference surfaces")
        .accessibilityAddTraits(activeTool != nil ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Insights section

/// The one collapsible block every scouting surface opens with (#130).
///
/// Before this the hub stacked, above the list and below four rows of controls:
/// the stage explainer card, a "83 % scouted · Review Roster" strip, the Draft
/// Prep summary card, and — on the combine — two horizontal RISERS / FALLERS
/// rails. Every one of them is worth reading exactly once per phase; none of
/// them is worth the top third of the screen on every visit, which is what the
/// user meant by *"content starts below the fold"*. They fold into this.
///
/// The header row is also the surface's **title bar**, and that is deliberate:
/// the hub needed a loud "you are here" and this section needed a chevron, and
/// two separate rows for the two would have re-created the stacking the section
/// exists to remove.
///
/// ## Default state
///
/// Expanded the first time a surface is seen **in a phase**, collapsed on every
/// visit after that. A phase boundary is when the numbers actually change — new
/// invitations, a new stage, a different set of risers — so that is when the
/// block earns a second look. `seenToken` records the phase a surface has been
/// opened for; `openPreference` records what the user last chose inside it.
/// The two `UserDefaults` keys ``ScoutingInsightsSection`` remembers a surface's
/// fold state in, and the rule that turns them into an answer.
///
/// Lifted out of the view so the HOST can ask the same question. The section
/// resolves in `onAppear`, which is one frame too late for a hub that owns
/// `isExpanded` across surfaces: switching from an expanded board to a collapsed
/// combine drew the combine's block open for that frame, then snapped it shut.
/// The hub seeds the binding from here the moment the tab changes and the
/// section's own `onAppear` then agrees with it.
enum ScoutingInsightsDefaults {

    static func openKey(_ surfaceKey: String) -> String { "scoutInsightsOpen_\(surfaceKey)" }
    static func seenKey(_ surfaceKey: String) -> String { "scoutInsightsSeen_\(surfaceKey)" }

    /// What `resolveDefault` would land on, computed WITHOUT writing: a surface
    /// not yet seen in this phase gets its one free expansion, everything else
    /// gets what the user last chose. The write stays in the view, because
    /// spending the free expansion is the act of showing it.
    static func resolvedExpansion(surfaceKey: String, phaseToken: String) -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: seenKey(surfaceKey)) == phaseToken else { return true }
        return defaults.bool(forKey: openKey(surfaceKey))
    }
}

struct ScoutingInsightsSection<Content: View>: View {

    /// Stable identity for the storage keys — the surface's tab rawValue.
    let surfaceKey: String
    /// "<season>-<phase>". Changing it re-arms the one free expansion.
    let phaseToken: String
    let title: String
    let icon: String
    /// "STAGE 4 · CURRENT", or `nil` on a reference surface.
    var stateChip: String? = nil
    var stateChipTint: Color = .accentGold
    /// One line of what is inside, readable while collapsed.
    let teaser: String
    /// Owned by the hub so the surfaces underneath (the combine's movers rails,
    /// the class-depth declaration card) can fold with the same one tap.
    @Binding var isExpanded: Bool
    let content: () -> Content

    @AppStorage private var openPreference: Bool
    @AppStorage private var seenToken: String

    init(
        surfaceKey: String,
        phaseToken: String,
        title: String,
        icon: String,
        stateChip: String? = nil,
        stateChipTint: Color = .accentGold,
        teaser: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.surfaceKey = surfaceKey
        self.phaseToken = phaseToken
        self.title = title
        self.icon = icon
        self.stateChip = stateChip
        self.stateChipTint = stateChipTint
        self.teaser = teaser
        self._isExpanded = isExpanded
        self.content = content
        // Per-surface keys, exactly like `prepExplainerOpen_<stage>`: collapsing
        // the board's insights must not collapse the combine's. The hub gives
        // this view `.id(surfaceKey)` so a surface switch builds a fresh
        // instance and these two wrappers re-bind to the new keys.
        _openPreference = AppStorage(wrappedValue: false, ScoutingInsightsDefaults.openKey(surfaceKey))
        _seenToken = AppStorage(wrappedValue: "", ScoutingInsightsDefaults.seenKey(surfaceKey))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow
            if isExpanded {
                content()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        // PRIMARY, not secondary. Everything this block contains — the metrics
        // strip, the Draft Prep card, the stage explainer — is drawn on
        // `backgroundSecondary`, because each of them used to sit directly on the
        // page. Filling the container with the same value would flatten all three
        // into one grey slab; the border is what makes it a block.
        .background(Color.backgroundPrimary, in: RoundedRectangle(cornerRadius: DSCornerRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: DSCornerRadius.card)
                .strokeBorder(Color.surfaceBorder.opacity(0.8), lineWidth: 1)
        )
        .onAppear { resolveDefault() }
        .onChange(of: phaseToken) { _, _ in resolveDefault() }
    }

    /// Opens the block once per surface per phase, then honours the user.
    ///
    /// Never called from `body` — it writes two defaults, and a write during a
    /// body pass is a re-entrant update.
    private func resolveDefault() {
        if seenToken != phaseToken {
            seenToken = phaseToken
            openPreference = true
            isExpanded = true
        } else {
            isExpanded = openPreference
        }
    }

    private var headerRow: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                isExpanded.toggle()
                openPreference = isExpanded
            }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: DSType.Size.footnote, weight: .bold))
                    .foregroundStyle(Color.accentGold)
                    .frame(width: 20, height: 20)
                    .background(Color.accentGold.opacity(0.14), in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(title.uppercased())
                            .font(.system(size: DSType.Size.body, weight: .black))
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                        if let stateChip {
                            Text(stateChip)
                                .font(.system(size: 8, weight: .black))
                                .foregroundStyle(stateChipTint)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(stateChipTint.opacity(0.15)))
                        }
                    }
                    Text(teaser)
                        .font(.system(size: DSType.Size.micro, weight: .semibold))
                        .foregroundStyle(Color.textTertiaryReadable)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Text("INSIGHTS")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(Color.textTertiaryReadable)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(Color.accentGold)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) insights. \(teaser)")
        .accessibilityHint(isExpanded ? "Collapse" : "Expand")
    }
}
