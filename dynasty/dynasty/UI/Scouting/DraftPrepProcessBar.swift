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
    /// The slat's position in the band, 1-based — **not** `step.order + 1`.
    ///
    /// The band draws six of the pipeline's nine steps (#164): the two mocks are
    /// filed in the War Room and `.ready` has no room of its own, so
    /// `top30Visits`, whose engine order is 6, is the SIXTH slat. Numbering the
    /// slats off the engine's order printed "7" on the last of six, which is a
    /// count the user cannot reconcile with what he can see. The engine's order
    /// is untouched — this is where the band is drawn, and only that.
    let displayIndex: Int
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
        var parts = ["Stage \(displayIndex) of \(DraftPrepStageCell.bandSteps.count), \(step.displayName)"]
        switch state {
        case .done:    parts.append("complete")
        case .current: parts.append("current stage")
        case .open:    parts.append("open")
        case .locked:  parts.append(isWaitingOnCalendar ? "waiting for the calendar" : "locked")
        }
        parts.append(counterText)
        if !spokenLockSentence.isEmpty { parts.append(spokenLockSentence) }
        return parts.joined(separator: ", ")
    }

    /// The unlock clause the screen reader speaks.
    ///
    /// Normally the engine's `lockReason`, which is the fuller sentence. The one
    /// exception is the case ``unlockCaption(for:stage:)`` was written for: when
    /// the blocker is a mock, the engine says "Finish or skip Mock 1.0 first."
    /// and Mock 1.0 has no slat, so that instruction cannot be followed from the
    /// band. The visible caption already names the ACT instead; the spoken one
    /// says the same thing rather than keeping the unfollowable version alive
    /// for VoiceOver only. A calendar wait keeps the engine's sentence — that
    /// one names a phase, which is on the calendar whether or not it is a slat.
    private var spokenLockSentence: String {
        guard state == .locked, !isWaitingOnCalendar,
              let previous = step.previous,
              DraftPrepStageCell.mockSteps.contains(previous),
              let caption = subcaption, !caption.isEmpty
        else { return lockReason }
        return caption
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
        // THE BLOCKER MAY BE A STAGE THAT HAS NO SLAT (#164). Both mocks were
        // taken off the band — they are filed in the War Room, not worked in a
        // room — so "Finish Mock 1.0" over the Top-30 slat pointed at a slat
        // that is not on screen. Naming the ACT instead is the only version of
        // the sentence a user can follow: it is the same words the hub's action
        // bar and the Mock Draft tab's badge use for the same obligation.
        if mockSteps.contains(previous) { return "Opens after \(previous.displayName) is filed" }
        return "Finish \(previous.displayName)"
    }

    // MARK: - Which steps the band draws (#164)

    /// The six stages the band renders, in pipeline order.
    ///
    /// `DraftPrepStep` still has nine cases and `DraftPrepProgress` still
    /// computes all nine — the machine, `canAct`, `satisfied`, the mock-read
    /// keys and the calendar gates are byte-identical. This is the band's slat
    /// list and nothing else: a stage the club WORKS gets a slat, and the two
    /// mocks (a read, filed in the War Room) and `.ready` (a state, not a room)
    /// do not.
    static let bandSteps: [DraftPrepStep] =
        [.combineReview, .interviews, .filmStudy, .proDayFocus, .workouts, .top30Visits]

    /// The two stages whose obligation surfaces in the War Room instead of on a
    /// slat. Named here because the unlock caption has to say so.
    static let mockSteps: Set<DraftPrepStep> = [.mockOne, .mockTwo]

    init(step: DraftPrepStep, displayIndex: Int, state: State, stage: DraftPrepProgress.Stage) {
        self.step = step
        self.displayIndex = displayIndex
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
            index: "\(displayIndex)",
            title: step.displayName,
            subcaption: subcaption,
            state: state,
            isAvailable: self.state == .open,
            outcome: outcome,
            // NO "NOW" PILL HERE. The band's `live` pill is a gold fill, and on
            // this hub gold already has its two jobs — the action bar's commit
            // and the War Room strip's active tab. The current slat is
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

/// The scouting hub's **whole** navigation: one ribbon carrying the War Room and
/// the pre-draft calendar — a place slat, a seam, then six numbered parallelogram
/// slats, each carrying its own state and its own count of work, and each opening
/// its stage's surface.
///
/// **ONE NAV ROW, NOT TWO (#165).** #164 shipped the band under a permanent War
/// Room tab strip, and live play made the cost obvious: two full-width, always-on
/// navigation rows above every surface in the hub, ~100 pt of chrome before the
/// screen's own title, and no statement anywhere of how the two related. They are
/// one navigation. The band holds all of it: `WAR ROOM` is its first slat — a
/// PLACE, unnumbered, stateless, outside the count and outside the meter — and
/// the five reference tabs appear beneath the band only while that slat is
/// selected, which is the only time they are the question.
///
/// **The band IS the stage navigation (#164).** It draws the six rooms the club
/// works — combine review, interviews, film, pro-day focus, private workouts,
/// Top-30 visits — and nothing else. `Mock 1.0`, `Final Mock` and `Ready` are
/// still nine-ninths of `DraftPrepProgress`; they simply have no slat, because
/// two of them are a read filed in the War Room and the third is a state rather
/// than a room. Their obligations surface where the act happens: the next locked
/// slat's caption names an unfiled mock, the hub's action bar states it, the War
/// Room's Mock Draft tab carries a needs-filing badge — and, since that tab is
/// only on screen while the War Room slat is selected, the SLAT carries a dot so
/// the obligation is visible from a stage surface too.
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

    /// The band's first slat's id. A `DraftPrepStep` raw value can never collide
    /// with it — the enum's cases are `combineReview`…`ready` — so the one
    /// `onSelect` closure can route by id without a second channel.
    static let warRoomSlatID = "warRoom"

    let cells: [DraftPrepStageCell]
    /// The stage whose screen is currently showing — not necessarily the stage
    /// the club is standing in: a done stage opens read-only. `nil` while the
    /// War Room slat owns the band.
    let selected: DraftPrepStep?
    /// "Stage 4 of 6". **The one place the hub prints its count** — it used to
    /// appear three times on this screen (the switcher subtitle, the metrics
    /// strip, the prep card's collapsed line).
    ///
    /// SIX, and the place slat does not move it. `WAR ROOM` is not a working
    /// week: it is outside this count and outside the meter, which is precisely
    /// what makes the seam beside it honest rather than decorative.
    let headline: String
    /// The spring's six working weeks. A filled pip is a spent pip.
    let meter: DSResourceMeter
    /// Whether the place slat is the selected one — i.e. a reference surface is
    /// on screen and the five War Room tabs are drawn beneath the band.
    var isWarRoomSelected: Bool = false
    /// A dot on the War Room slat: an unfiled mock inside its window (#165).
    ///
    /// The same predicate the Mock Draft tab's badge reads
    /// (`ScoutingHubView.pendingMock`), because it is the same obligation seen
    /// from one level up — the tab is only on screen while the War Room slat is
    /// selected, so without this the club can stand in a stage room all week
    /// with an unfiled mock and no mark anywhere in the chrome.
    var warRoomHasObligation: Bool = false
    /// Spoken suffix for the War Room slat while it is badged.
    var warRoomObligationText: String = ""
    /// Demoted rendering. **The scouting hub never passes it (#165).**
    ///
    /// #130 and #164 used it for the War Room surfaces, on the reasoning that
    /// the pipeline is context there rather than the subject. That held while a
    /// second full-size strip above the band carried the navigation. It does not
    /// now: this band IS the hub's navigation on every one of its surfaces, and
    /// a navigation row that loses 12 pt and its sub-captions depending on which
    /// of its own destinations is selected is a control that changes shape under
    /// the finger. The parameter stays because `DSSlatBand` is domain-agnostic
    /// and a band genuinely CAN be context on a screen it does not navigate —
    /// the season ladder over a game recap, say. That consumer has not shipped
    /// yet; when it does, this is how it asks.
    var isCompact: Bool = false
    var onSelect: (DraftPrepStep) -> Void
    /// Tapping the place slat. Opens the War Room's tab row and its surface.
    var onSelectWarRoom: () -> Void = {}

    /// The War Room as `DSSlatBand` draws it (#165).
    ///
    /// `DSSlat.place` is the additive role: no numeral, no check, no rule, no
    /// lift, no sub-caption, a fixed width off the flex and a wider seam behind
    /// it. It is prepended to the six stage slats, and it is deliberately NOT in
    /// `cells` — `cells` is what the head's "Stage N of 6" and the six-pip meter
    /// are counted from, and a place is not a working week.
    private var warRoomSlat: DSSlat {
        DSSlat.place(
            id: Self.warRoomSlatID,
            title: "War Room",
            // A room of screens, not a step: the grid glyph is the one thing on
            // the ribbon that is not an instrument or a stage.
            icon: "square.grid.2x2.fill",
            hasObligation: warRoomHasObligation,
            accessibilityText: warRoomHasObligation && !warRoomObligationText.isEmpty
                ? "War Room. \(warRoomObligationText)"
                : "War Room"
        )
    }

    var body: some View {
        DSSlatBand(
            slats: [warRoomSlat] + cells.map(\.slat),
            headline: headline,
            meter: meter,
            isCompact: isCompact,
            selectedID: isWarRoomSelected ? Self.warRoomSlatID : selected?.rawValue,
            onSelect: { id in
                if id == Self.warRoomSlatID { onSelectWarRoom(); return }
                guard let step = DraftPrepStep(rawValue: id) else { return }
                onSelect(step)
            }
        )
    }
}

// MARK: - War Room tab strip

/// The five War Room surfaces — **the War Room slat's own contents** (#165).
///
/// #164 drew this as a permanent strip ABOVE the band, which put two full-width
/// navigation rows on every surface in the hub. It is now a sub-row of one slat:
/// it is drawn directly beneath the band, and only while the band's `WAR ROOM`
/// place slat is selected. On a stage surface it is not on screen at all,
/// because on a stage surface it is not the question — and the obligation it
/// used to carry alone (the Mock Draft badge) is mirrored onto the slat so
/// nothing is lost by hiding the row.
///
/// The split this replaces is the point. #130 gave the hub one three-slot
/// switcher — Big Board · the stage surface · a Tools menu — which answered
/// *"where am I"* but folded the club's five permanent reference screens behind
/// a chevron and made the stage surface a slot that changed its own label. The
/// **band** is the navigation now — six rooms and one place, always on screen,
/// each one tap — and this is what is inside the place.
///
/// Exactly five tabs, and they are the war room: the board you build, the class
/// behind it, the order you pick in, the mock the league prints, and the
/// department that does the work. Nothing is behind a menu.
///
/// NO "WAR ROOM" HEAD LABEL. It had one while it was a top-level strip and
/// needed to name itself; the slat directly above it now says the word, and a
/// section head repeating its own parent one row down is the kind of duplicate
/// this hub has spent three tasks removing. Dropping it also returns ~90 pt to
/// the row, which is about what a sixth tab needs.
///
/// **Gold discipline (P5).** The active tab's fill is the current-marker for the
/// destination layer, and the row exists only while a War Room tab owns the
/// screen — on a stage surface there is no row, so the band's gold current rule
/// and the action bar's primary are the only gold on that screen. There is never
/// a third gold fill in the hub's chrome.
struct ScoutingWarRoomTabs: View {

    let tabs: [ScoutingTab]
    /// The tab that owns the screen, or `nil` when a stage surface does.
    let selected: ScoutingTab?
    /// Tabs carrying an obligation the user has not settled — today exactly one:
    /// Mock Draft, while a mock is unfiled and its calendar window is open.
    ///
    /// A dot, not a word: P7's legibility floor puts the condensed display voice
    /// at 11 pt, which is the tab label's own size, so a text badge would be as
    /// loud as the tab. `alertOrange` rather than gold — gold has three jobs and
    /// "something is owed here" is not one of them.
    var badgedTabs: Set<ScoutingTab> = []
    /// Spoken suffix for a badged tab, e.g. "Mock 1.0 has not been filed".
    var badgeAccessibilityText: String = ""
    var onSelect: (ScoutingTab) -> Void

    var body: some View {
        HStack(spacing: DSSpacing.xs) {
            ForEach(tabs) { tab in
                tabButton(tab)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("War Room")
    }

    private func tabButton(_ tab: ScoutingTab) -> some View {
        let isActive = selected == tab
        let isBadged = badgedTabs.contains(tab)
        return Button {
            onSelect(tab)
        } label: {
            HStack(spacing: DSSpacing.xxs) {
                Image(systemName: tab.icon)
                    .font(.system(size: DSType.Size.micro, weight: .bold))
                // NO `minimumScaleFactor`. 11 pt IS the condensed display
                // voice's floor (P7), so a scale factor here can only render
                // BELOW it — the flex the band refuses to take. Five tabs get
                // ~195 pt each at 1032 pt portrait (the head label went with
                // #165) and the longest label ("CLASS DEPTH") needs ~110, so the
                // row has the headroom for a sixth; a seventh must scroll or
                // wrap rather than shrink.
                Text(tab.label.uppercased())
                    .font(DSType.display(11, .heavy))
                    .tracking(0.6)
                    .lineLimit(1)
                if isBadged {
                    // The dot is a foreground mark, so it takes the foreground's
                    // plate ink on the gold active fill — alertOrange on
                    // accentGold is ~1.4:1 and disappears exactly where the tab
                    // is loudest.
                    Circle()
                        .fill(isActive ? Color.backgroundPlate : Color.alertOrange)
                        .frame(width: 7, height: 7)  // ds-lint:allow(spacing) obligation dot: a 44 pt tab has no room for a second text tier
                }
            }
            .foregroundStyle(isActive ? Color.backgroundPlate : Color.textSecondary)
            .padding(.horizontal, DSSpacing.xs)
            // §2.12 has no exceptions: every tab is a legal touch target whether
            // it is active or not.
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                    .fill(isActive ? Color.accentGold : Color.backgroundTertiary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                    .strokeBorder(isActive ? Color.clear : Color.surfaceBorder, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            isBadged && !badgeAccessibilityText.isEmpty
                ? "\(tab.label). \(badgeAccessibilityText)"
                : tab.label
        )
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
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
/// ## Default state — **CLOSED, on every surface** (#166)
///
/// It used to open itself once per surface per phase, on the theory that a phase
/// boundary is when the numbers change and so the block has earned a second
/// look. Live play says otherwise: the hub has eleven surfaces and a phase
/// boundary re-armed all eleven, so a single advance meant eleven screens that
/// each opened with a block of prose over the table the user came for — which is
/// the "content starts below the fold" complaint this section was built to fix,
/// arriving by a different door.
///
/// One rule now: **the block is shut until the user opens it, and then it stays
/// however he last left THAT surface.** No re-arming, no free expansion, no
/// phase token. A collapsed block still states its one teaser line, which is the
/// part that was ever worth an unasked-for row.
///
/// Lifted out of the view so the HOST can ask the same question. The section
/// resolves in `onAppear`, which is one frame too late for a hub that owns
/// `isExpanded` across surfaces: switching from an expanded board to a collapsed
/// combine drew the combine's block open for that frame, then snapped it shut.
/// The hub seeds the binding from here the moment the tab changes and the
/// section's own `onAppear` then agrees with it.
enum ScoutingInsightsDefaults {

    /// The one key. **The caller scopes it to the career** — see
    /// `ScoutingHubView.insightsSurfaceKey`. This is plain `UserDefaults`, not
    /// `@CareerScopedStorage`, and it is not on `CareerScopedDefaults.keys`
    /// either, so an unscoped key would outlive the save that wrote it and hand
    /// the next career somebody else's open block. The phase token used to mask
    /// that by re-arming every surface; with the re-arming gone the scoping has
    /// to be real.
    static func openKey(_ surfaceKey: String) -> String { "scoutInsightsOpen_\(surfaceKey)" }

    /// What `resolveDefault` would land on, computed WITHOUT writing: whatever
    /// the user last chose on this surface, and `false` — shut — when he has
    /// never chosen.
    static func resolvedExpansion(surfaceKey: String) -> Bool {
        UserDefaults.standard.bool(forKey: openKey(surfaceKey))
    }
}

struct ScoutingInsightsSection<Content: View>: View {

    /// Stable identity for the storage key — "<career-uuid>-<tab rawValue>".
    /// **Career-scoped by the caller** (#166); see ``ScoutingInsightsDefaults``.
    let surfaceKey: String
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

    init(
        surfaceKey: String,
        title: String,
        icon: String,
        stateChip: String? = nil,
        stateChipTint: Color = .accentGold,
        teaser: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.surfaceKey = surfaceKey
        self.title = title
        self.icon = icon
        self.stateChip = stateChip
        self.stateChipTint = stateChipTint
        self.teaser = teaser
        self._isExpanded = isExpanded
        self.content = content
        // Per-surface key, exactly like `prepExplainerOpen_<stage>`: collapsing
        // the board's insights must not collapse the combine's. The hub gives
        // this view `.id(surfaceKey)` so a surface switch builds a fresh
        // instance and this wrapper re-binds to the new key. `false` is the
        // wrappedValue, which IS the new default rule (#166).
        _openPreference = AppStorage(wrappedValue: false, ScoutingInsightsDefaults.openKey(surfaceKey))
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
    }

    /// Honours the user, and shows shut when he has never said otherwise (#166).
    ///
    /// NO `onChange(of: phaseToken)` any more, and no write. The phase used to
    /// re-arm a free expansion here — which is exactly the behaviour that put a
    /// block of prose over eleven tables every time the calendar moved — and the
    /// re-arm was also the only writer, so this is now a pure read.
    private func resolveDefault() {
        isExpanded = openPreference
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
