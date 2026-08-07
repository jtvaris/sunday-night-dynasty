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
    /// The slat's second line: what the current stage COSTS, or what opens a
    /// locked one. `nil` on a future stage, which is label-only by spec.
    let subcaption: String?
    /// What a finished stage produced, for the `done` slat's outcome slot. Empty
    /// for the read-only stages, whose check glyph already says everything.
    let outcome: String

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

    /// The short form of "what opens this stage", sized for a slat caption.
    ///
    /// The twin of ``DraftPrepProgress/Stage/waitLabel``: `lockReason` is the
    /// sentence the explainer has room for ("The pro-day circuit opens after
    /// free agency."), and this is the clause the band has room for. Both are
    /// derived from the same fact — the phase that has to pass — so the strip
    /// and the card can never describe one wait two ways.
    ///
    /// It names the phase that has to pass, not the stage: "opens at pro days"
    /// over the pro-day slat says only that the pro days open when the pro days
    /// open, and the fact a user in combine week actually needs is that FREE
    /// AGENCY comes first (#123).
    static func unlockCaption(for step: DraftPrepStep, stage: DraftPrepProgress.Stage) -> String {
        guard !stage.unlocked else { return "" }
        // ONE wait vocabulary, and it is the engine's: `waitLabel` is already
        // sized for a small cell ("Combine week" / "After FA" / "Draft week")
        // and already names the phase that has to pass rather than the stage
        // (#123). A second short table here would be a second place the same
        // wait could be described, which is the exact defect this file's header
        // comment was written about.
        if stage.isCalendarLocked { return stage.waitLabel }
        guard let previous = step.previous else { return "Not open yet" }
        return "Finish \(previous.displayName)"
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
        let resolved: State = (state == .current && !stage.unlocked) ? .locked : state
        self.state = resolved
        self.counterText = stage.counter
        self.fraction = stage.fraction
        self.lockReason = stage.lockReason ?? ""
        self.isWaitingOnCalendar = stage.isCalendarLocked
        // COST on the stage you are standing in, UNLOCK on the ones you are not.
        // A future stage carries neither: §2.1's `future` is label-only, and a
        // price tag on a room nobody is standing in is the noise the merged
        // explainer/counter/meter stack used to be.
        switch resolved {
        case .current:
            self.subcaption = step.next == nil
                ? stage.counter
                : "\(stage.counter) \u{00B7} spends 1 scouting week"
        case .locked:
            self.subcaption = DraftPrepStageCell.unlockCaption(for: step, stage: stage)
        case .done, .open:
            self.subcaption = nil
        }
        // A counted stage says what it banked; a read says nothing beyond its
        // tick, because "Done" next to a check glyph is the same claim twice.
        self.outcome = (resolved == .done && stage.isCounted) ? stage.counter : ""
    }
}

// MARK: - Slat adapter

extension DraftPrepStageCell {

    /// The cell as the shared band draws it.
    ///
    /// `DSSlatBand` has four states and the pipeline has four; `.open` maps onto
    /// `future` with `isAvailable`, because "you may already work here" is a
    /// promise about the SCREEN (`DraftPrepProgress.canAct`), not a fifth
    /// position in the process. §2.1 gives `future` a label and nothing else, so
    /// the promise rides on the label's text tier rather than on a colour of its
    /// own.
    var slat: DSSlat {
        let state: DSSlat.State
        switch self.state {
        case .done:    state = .done
        case .current: state = .current
        case .open:    state = .future
        case .locked:  state = .locked
        }
        return DSSlat(
            id: step.rawValue,
            index: "\(step.order + 1)",
            title: step.displayName,
            subcaption: subcaption,
            state: state,
            isAvailable: self.state == .open,
            outcome: outcome,
            // NO "NOW" PILL HERE. The band's `live` pill is a gold fill, and on
            // this hub gold already has its two jobs — the action bar's commit
            // and the surface switcher's active slot. The current slat is
            // already marked three ways (gold top rule, lifted gradient, 3x
            // width); a fourth marker that costs a third gold fill is exactly
            // the drift P5/P7 exist to stop. The pill stays in the component for
            // the season ladder, where "the week being played" and "the week
            // being looked at" are genuinely two different slats.
            isLive: false,
            accessibilityText: accessibilityText
        )
    }
}

// MARK: - Process bar

/// The scouting hub's primary navigation: the pre-draft calendar as a
/// ``DSSlatBand`` — nine parallelogram slats, in order, each carrying its own
/// state and its own count of work.
///
/// This replaces the flat eleven-tab picker. The picker was a list of places,
/// which is the wrong shape for a process — it said nothing about order, nothing
/// about what was finished, and it *hid* every stage the club had not reached,
/// so the two most common failure reports against the shipped wizard ("pro days
/// were completely unavailable", "film study could not be assigned") were both a
/// user looking at a screen that had silently deleted the thing he was looking
/// for. Here every stage is always on screen, in calendar order, and a stage the
/// club cannot work yet says so in words.
///
/// **Wave 0 (#105) replaced the drawing, not the information.** What used to be
/// a row of 24 pt numbered pucks on a gold connector rail — the Bootstrap wizard,
/// a shape whose only differentiator at distance was fill hue — is now the shared
/// slat band, which is the same component the season ladder, free agency, the
/// draft board and negotiation will mount. Every semantic is unchanged: every
/// state, every counter, every tap target and the whole accessibility sentence
/// come through the same ``DraftPrepStageCell`` the hub already computed.
struct DraftPrepProcessBar: View {
    let cells: [DraftPrepStageCell]
    /// The stage whose screen is currently showing — not necessarily the stage
    /// the club is standing in: a done stage opens read-only.
    let selected: DraftPrepStep?
    /// "Stage 4 of 9". **The one place the hub prints its count** — it used to
    /// appear three times on this screen (the switcher subtitle, the metrics
    /// strip, the prep card's collapsed line).
    let headline: String
    /// The spring's nine scouting weeks. A filled pip is a spent pip.
    let meter: DSResourceMeter
    /// Demoted rendering for the surfaces the pipeline is not the subject of
    /// (#130).
    ///
    /// The band is the wizard's spine and it stays on every screen — the user
    /// asked to always see how much of each stage is done — but on the Big Board
    /// or the draft order it is *context*, not the control the eye should land
    /// on first. Compact keeps the geometry, the states and the targets, and
    /// drops the sub-captions and 12 pt of height.
    var isCompact: Bool = false
    var onSelect: (DraftPrepStep) -> Void

    var body: some View {
        DSSlatBand(
            slats: cells.map(\.slat),
            headline: headline,
            meter: meter,
            isCompact: isCompact,
            selectedID: selected?.rawValue,
            onSelect: { id in
                guard let step = DraftPrepStep(rawValue: id) else { return }
                onSelect(step)
            }
        )
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
    /// "3/11 focus slots" — the segment's second line.
    ///
    /// It used to lead with "Stage 4 of 9", which made this the second of three
    /// places the hub printed its own count. The band head owns the count now
    /// (#105 wave 0).
    let stageSubtitle: String
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

            // NO STATE CHIP (#105 wave 0). This segment used to carry a
            // CURRENT / DONE / OPEN / LOCKED capsule, which was a second
            // rendering of a state the band states in three channels one row
            // below — and whose CURRENT variant was a gold tint on a screen
            // where gold has exactly three jobs. The segment's job is "you are
            // here", and it does that by size and fill.
            segment(
                icon: stageTab.icon,
                title: stageTab.label,
                subtitle: stageSubtitle,
                chip: nil,
                chipTint: .accentGold,
                isActive: active == .stage,
                action: { onSelect(stageTab) }
            )

            toolsMenu
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
                // Neither the commit nor the current step, so not gold (#105
                // wave 0, P5). This drew a gold glyph on a gold plate directly
                // above a band whose one gold rule marks where the club is
                // standing — the audit's "all section header icons are the same
                // yellow tint … they compete for attention instead of guiding
                // it", reproduced one row apart.
                Image(systemName: icon)
                    .font(.system(size: DSType.Size.footnote, weight: .bold))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 20, height: 20)
                    .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))

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
                    .foregroundStyle(Color.textSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) insights. \(teaser)")
        .accessibilityHint(isExpanded ? "Collapse" : "Expand")
    }
}
