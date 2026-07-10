import SwiftUI
import SceneKit
import Combine

// MARK: - CoachedGameView

/// Full-screen live coached game. Unlike ``MatchView`` (which replays a
/// pre-simulated result), every play here is decided by ``LiveGameEngine`` at
/// the moment it is called: the user's offensive play call and defensive
/// package genuinely bias the simulation.
///
/// Layout (portrait iPad):
///   scoreboard / situation strip
///   3D field (SceneKit) with play choreography
///   mini play feed
///   call panel — offense play calling, 4th-down decisions, or defense presets
struct CoachedGameView: View {

    // MARK: Input

    let homeTeam: Team
    let awayTeam: Team
    let playerTeamIsHome: Bool
    /// Game weather — biases the engine's plays and dresses the 3D field.
    let weather: GameWeather
    /// R19: single-elimination framing — gold PLAYOFFS badge on the
    /// scoreboard, "WIN OR GO HOME" at kickoff, season-over final text.
    /// Pure presentation; the engine never reads it.
    let isPlayoff: Bool
    /// Called when the user taps Continue on the final whistle overlay.
    /// The caller persists the result and presents the game summary.
    let onFinish: (LiveGameEngine) -> Void

    @StateObject private var engine: LiveGameEngine

    init(
        homeTeam: Team,
        awayTeam: Team,
        homeCoaches: [Coach],
        awayCoaches: [Coach],
        playerTeamIsHome: Bool,
        audibleBoost: Double = 0,
        defReadBoost: Double = 0,
        weather: GameWeather = .clear,
        isPlayoff: Bool = false,
        onFinish: @escaping (LiveGameEngine) -> Void
    ) {
        self.homeTeam = homeTeam
        self.awayTeam = awayTeam
        self.playerTeamIsHome = playerTeamIsHome
        self.weather = weather
        self.isPlayoff = isPlayoff
        self.onFinish = onFinish
        _engine = StateObject(wrappedValue: LiveGameEngine(
            homeTeam: homeTeam,
            awayTeam: awayTeam,
            homeCoaches: homeCoaches,
            awayCoaches: awayCoaches,
            playerTeamIsHome: playerTeamIsHome,
            audibleBoost: audibleBoost,
            defReadBoost: defReadBoost,
            weather: weather
        ))
    }

    // MARK: Scene & Flow State

    @State private var fieldScene = FootballFieldScene()
    /// Persisted Coach/Broadcast camera choice (HUD toggle over the field).
    /// Coach — the Madden-scale low shot — is the default.
    @AppStorage("coachCameraStyle") private var cameraStyleRaw: String =
        FootballFieldScene.CameraStyle.coach.rawValue
    private var cameraStyle: FootballFieldScene.CameraStyle {
        FootballFieldScene.CameraStyle(rawValue: cameraStyleRaw) ?? .coach
    }
    /// Persisted play-animation speed (HUD 1x/2x toggle) for the impatient:
    /// 2x halves every play timeline. Presentation only — sim results and
    /// clock runoff are identical at both speeds.
    @AppStorage("coachPlaybackSpeed") private var playbackSpeedRaw: Double = 1.0
    @State private var isAnimating = false
    /// While set (and in the future), the offense is in its between-plays
    /// huddle ring: formation previews hold off until the break time so a
    /// call-sheet browse doesn't snap the ring apart mid-gather.
    @State private var huddleBreakTime: Date? = nil
    /// The field grows while a play is live and shrinks back when the call
    /// sheet needs the room.
    private var fieldExpanded: Bool { isAnimating }
    @State private var gameStarted = false
    @State private var resultBanner: String? = nil
    @State private var possessionBanner: String? = nil
    /// Gold "WIN OR GO HOME" plate flashed over the field at a playoff
    /// opening kickoff (R19) — same visual language as the possession banner.
    @State private var playoffBanner: String? = nil
    /// Retro broadcast plate ("1ST & 10") flashed at the snap.
    @State private var snapPlate: String? = nil
    /// Player-vs-player callouts for the play that just resolved.
    @State private var matchupCallouts: [PlayMatchups.Event] = []
    /// Whether the player's team was the offense on the play those callouts
    /// describe (possession may have flipped since).
    @State private var calloutsOffenseWasPlayer = true
    /// Red injury banner ("INJURY: T. Hill (WR) — leaves the game").
    @State private var injuryBanner: String? = nil
    /// Gold milestone banner ("MILESTONE: M. Dixon — 100 rushing yards").
    @State private var milestoneBanner: String? = nil
    /// Small sideline note over the field ("Fresh legs: J. Cook in at RB").
    @State private var sidelineNote: String? = nil
    /// Adaptive-AI intel chip ("CHI is keying on the inside run") — shown
    /// when the opponent locks onto (or shifts) a read of your tendencies.
    @State private var adaptationNote: String? = nil

    // Offense call state
    @State private var selectedCategory: String = "Run"
    @State private var selectedCall: OffensivePlayCall? = nil
    @State private var wentForIt = false
    /// The special-teams option highlighted on the 4th-down panel. Selecting
    /// never snaps — only the explicit SNAP button commits the play.
    @State private var fourthDownChoice: PlayType? = nil
    /// AI suggestion cached per situation — the underlying hint rolls dice,
    /// so recomputing it on every body render would make the brain icon jump.
    @State private var cachedSuggestion: OffensivePlayCall? = nil

    // Defense call state
    @State private var defCall: DefensiveCall = .cover3Base
    @State private var defCategory: String = "Coverage"

    // Kickoff decision state (onside window): the choice renders as a call
    // panel — no timer, no tap-outside commitment — until KICK is pressed.
    @State private var awaitingKickoffDecision = false
    @State private var onsideSelected = false

    // Post-TD conversion state: after the player's touchdown the coach picks
    // XP or a two-point try (same card language as the onside window); "Go
    // for 2" opens the normal call sheet with a Back chevron, and the try
    // snaps only from the explicit button.
    @State private var awaitingConversionDecision = false
    @State private var conversionGoForTwo = false
    /// True while the coach is picking the two-point play from the call sheet.
    @State private var goingForTwo = false

    // Dialogs
    @State private var showSimToEndConfirm = false
    @State private var showExitConfirm = false
    @State private var showFinal = false
    @State private var showStatsSheet = false
    /// Coach's Board — full-screen in-game player management (formation view,
    /// day grades, category battles, substitutions).
    @State private var showManageSheet = false
    /// Halftime report overlay (raised by the engine's `halftimePending`).
    @State private var showHalftime = false

    // Two-minute drill presentation
    /// Quarters (2 and/or 4) whose two-minute warning chip already fired.
    @State private var twoMinuteWarnedQuarters: Set<Int> = []
    /// Transient "2-MINUTE WARNING" chip in the situation strip.
    @State private var showTwoMinuteChip = false

    // MARK: Play clock (decision countdown)

    /// Default decision-clock length: the coach gets this long to pick a
    /// call before the QB (or the DC) checks into a simple base play and
    /// the snap goes off automatically. Never a delay-of-game penalty.
    /// Settings can stretch the window to 15 s or switch the clock off.
    static let playClockSeconds: Double = 10
    /// How long the auto-picked card stays highlighted before the auto snap.
    private static let autoCallShowcaseSeconds: TimeInterval = 1.5

    @AppStorage("playClockSetting") private var playClockSettingRaw: String = PlayClockSetting.ten.rawValue

    /// True while a decision window is open and the countdown is live.
    @State private var playClockArmed = false
    /// Seconds left on the decision clock.
    @State private var playClockRemaining: Double = 0
    /// The window's full length (ring denominator) — 10 or 15 s per Settings.
    @State private var playClockTotal: Double = CoachedGameView.playClockSeconds
    /// True from expiry until the auto-called snap goes off (the showcase
    /// beat where the picked card highlights); the ring freezes at zero.
    @State private var playClockExpiring = false
    /// Invalidation token, bumped on every arm/disarm: a stale auto-snap
    /// closure (or one racing a manual snap) can never double-fire.
    @State private var playClockGeneration = 0
    /// Whether the coach actively tapped an offensive card this window —
    /// the pre-selected AI suggestion doesn't count; a delay still checks down.
    @State private var offCallDirtied = false
    /// Whether the coach touched the defensive call sheet this window.
    @State private var defCallDirtied = false

    /// 10 Hz heartbeat for the countdown — only decrements while a window
    /// is armed and nothing (overlay, dialog, live play) pauses it.
    private let playClockTicker = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    @Environment(\.dismiss) private var dismiss

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            GeometryReader { geo in
                VStack(spacing: 0) {
                    scoreboardBar
                    situationStrip
                    // The field takes over while the play is live — no dead
                    // spinner panel — and gives the space back for the call.
                    fieldSection(height: geo.size.height * (fieldExpanded ? 0.68 : 0.52))
                    miniPlayFeed
                    callPanel
                        .frame(maxHeight: .infinity)
                }
                .animation(.easeInOut(duration: 0.4), value: fieldExpanded)
            }

            if showHalftime {
                HalftimeView(
                    engine: engine,
                    homeTeam: homeTeam,
                    awayTeam: awayTeam,
                    playerTeamIsHome: playerTeamIsHome
                ) { choice in
                    engine.resolveHalftime(choosing: choice)
                    withAnimation(.easeInOut(duration: 0.3)) { showHalftime = false }
                    if let choice { showBanner("2nd-half adjustment: \(choice.rawValue).") }
                    proceed(after: 0.5)
                }
                .transition(.opacity)
            }

            if showFinal {
                finalOverlay
            }
        }
        .statusBarHidden()
        .onAppear(perform: startGame)
        .onReceive(playClockTicker) { _ in tickPlayClock() }
        .onChange(of: engine.timeRemaining) { _, remaining in
            checkTwoMinuteWarning(remaining)
        }
        .onChange(of: selectedCall) { _, _ in previewFormation() }
        .onChange(of: defCall) { _, _ in
            if !engine.playerIsOnOffense { previewFormation() }
        }
        .onChange(of: engine.lastRotation) { _, rotation in
            if let rotation { showSidelineNote("Fresh legs: \(rotation.inName) in at RB") }
        }
        .onChange(of: engine.lastAdaptationHint) { _, hint in
            if let hint { showAdaptationNote(hint.text) }
        }
        .onChange(of: engine.lastMilestones) { _, milestones in
            // Multiple lines can fall on the same drive end — stagger them.
            for (index, milestone) in milestones.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 3.4) {
                    showMilestoneBanner(milestone.text)
                }
            }
        }
        .confirmationDialog(
            "Sim rest of the game?",
            isPresented: $showSimToEndConfirm,
            titleVisibility: .visible
        ) {
            Button("Sim to Final") { simToEnd() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The engine finishes the game with AI play-calling on both sides.")
        }
        .confirmationDialog(
            "Leave the game?",
            isPresented: $showExitConfirm,
            titleVisibility: .visible
        ) {
            Button("Sim to Final & Leave") { simToEnd() }
            Button("Abandon Game", role: .destructive) { dismiss() }
            Button("Keep Coaching", role: .cancel) {}
        } message: {
            Text("You can sim the remaining plays or abandon (nothing is saved).")
        }
        .sheet(isPresented: $showStatsSheet) {
            LiveBoxScoreSheet(engine: engine, homeTeam: homeTeam, awayTeam: awayTeam)
        }
        .fullScreenCover(isPresented: $showManageSheet) {
            CoachesBoardView(
                engine: engine,
                teamAbbr: playerAbbr,
                holdouts: playerTeamModel.players
                    .filter(\.isHoldingOut)
                    .map { CoachesBoardView.HoldoutLine(id: $0.id, name: $0.fullName, position: $0.position) },
                initialUnitIsOffense: engine.playerIsOnOffense,
                subsDisabled: isAnimating || engine.isGameOver
            )
        }
    }

    // MARK: - Scoreboard

    /// True when the two teams share a division — rivalry framing (R19).
    private var isDivisionGame: Bool {
        homeTeam.conference == awayTeam.conference && homeTeam.division == awayTeam.division
    }

    private var scoreboardBar: some View {
        HStack(spacing: 0) {
            teamBlock(team: awayTeam, score: engine.awayScore, hasBall: !engine.homeHasPossession, leading: true)
            Spacer()
            VStack(spacing: 2) {
                Text(quarterLabel)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.textSecondary)
                clockDisplay
                // Stakes chip under the clock: a playoff game outranks the
                // division rivalry framing when both apply.
                if isPlayoff {
                    Text("PLAYOFFS")
                        .font(.system(size: 9, weight: .black))
                        .tracking(1.2)
                        .foregroundStyle(Color.backgroundPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.accentGold, in: Capsule())
                } else if isDivisionGame {
                    Text("DIVISION")
                        .font(.system(size: 9, weight: .black))
                        .tracking(1.2)
                        .foregroundStyle(Color.accentGold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.accentGold.opacity(0.14), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.accentGold.opacity(0.4), lineWidth: 1))
                }
                if weather != .clear {
                    HStack(spacing: 3) {
                        Image(systemName: weather.symbolName)
                            .font(.system(size: 9, weight: .bold))
                        Text(weather.label.uppercased())
                            .font(.system(size: 9, weight: .black))
                            .tracking(0.8)
                    }
                    .foregroundStyle(Color.accentBlue)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.accentBlue.opacity(0.14), in: Capsule())
                }
            }
            Spacer()
            teamBlock(team: homeTeam, score: engine.homeScore, hasBall: engine.homeHasPossession, leading: false)
        }
        .padding(.leading, 20)
        .padding(.trailing, 56) // keep the right team block clear of the exit button
        .padding(.top, 14)
        .padding(.bottom, 8)
        .background(Color.backgroundSecondary)
        .overlay(alignment: .topTrailing) { exitButton.padding(.top, 10).padding(.trailing, 12) }
    }

    private var quarterLabel: String {
        engine.quarter <= 4 ? "Q\(engine.quarter)" : "OT"
    }

    /// Q2/Q4 with two minutes or less on the clock — crunch time.
    private var isTwoMinuteDrill: Bool {
        (engine.quarter == 2 || engine.quarter == 4)
            && engine.timeRemaining <= 120 && engine.timeRemaining > 0
            && !engine.isGameOver
    }

    /// Broadcast clock — pulses red inside the two-minute drill (Q2/Q4).
    @ViewBuilder
    private var clockDisplay: some View {
        let clockText = Text(engine.formattedClock)
            .font(.system(size: 27, weight: .heavy).monospacedDigit())
        if isTwoMinuteDrill {
            clockText
                .foregroundStyle(Color.danger)
                .phaseAnimator([false, true]) { view, dimmed in
                    view
                        .opacity(dimmed ? 0.55 : 1.0)
                        .scaleEffect(dimmed ? 1.05 : 1.0)
                } animation: { _ in .easeInOut(duration: 0.55) }
        } else {
            clockText.foregroundStyle(Color.textPrimary)
        }
    }

    private func teamBlock(team: Team, score: Int, hasBall: Bool, leading: Bool) -> some View {
        HStack(spacing: 8) {
            if !leading, hasBall { possessionDot }
            VStack(alignment: leading ? .leading : .trailing, spacing: 0) {
                Text(team.abbreviation)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isPlayerTeam(team) ? Color.accentGold : Color.textSecondary)
                Text("\(score)")
                    .font(.system(size: 34, weight: .black).monospacedDigit())
                    .foregroundStyle(Color.textPrimary)
                    .contentTransition(.numericText())
                    .animation(.spring(duration: 0.4), value: score)
                timeoutPips(
                    remaining: team.id == homeTeam.id ? engine.homeTimeouts : engine.awayTimeouts
                )
                .padding(.top, 2)
            }
            if leading, hasBall { possessionDot }
        }
        .frame(minWidth: 84, alignment: leading ? .leading : .trailing)
    }

    /// Broadcast-style timeout indicator: three pips per side, dimmed as
    /// timeouts are spent (they restock at halftime).
    private func timeoutPips(remaining: Int) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(index < remaining ? Color.accentGold : Color.backgroundTertiary)
                    .frame(width: 10, height: 3)
            }
        }
    }

    private var possessionDot: some View {
        Image(systemName: "football.fill")
            .font(.system(size: 11))
            .foregroundStyle(Color.accentGold)
    }

    private func isPlayerTeam(_ team: Team) -> Bool {
        (team.id == homeTeam.id) == playerTeamIsHome
    }

    private var exitButton: some View {
        Button {
            if engine.isGameOver { dismiss() } else { showExitConfirm = true }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 30, height: 30)
                .background(Color.backgroundTertiary, in: Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Situation Strip

    private var situationStrip: some View {
        HStack(spacing: 10) {
            chip(downDistanceText, color: .accentGold)
            chip(fieldPositionText, color: .accentBlue)
            chip(possessionText, color: engine.playerIsOnOffense ? .success : .danger)
            if !engine.currentDrivePlays.isEmpty {
                chip(driveChipText, color: .textSecondary)
            }
            if showTwoMinuteChip {
                chip("2-MINUTE WARNING", color: .danger)
                    .transition(.scale.combined(with: .opacity))
            }
            if !engine.pendingSubstitutions.isEmpty {
                chip("Sub at next whistle", color: .warning)
            }
            Spacer(minLength: 12)
            // Action buttons: visually heavier than the info chips on the left —
            // full 44 pt tap targets with a solid plate and border.
            HStack(spacing: 8) {
                if !engine.isGameOver && engine.playerTimeoutsRemaining > 0 {
                    Button {
                        callTimeout()
                    } label: {
                        actionButtonLabel(
                            "TO · \(engine.playerTimeoutsRemaining)",
                            icon: "hand.raised.fill",
                            tint: .accentGold,
                            prominent: true
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isAnimating)
                    .opacity(isAnimating ? 0.45 : 1)
                }
                Button {
                    showManageSheet = true
                } label: {
                    actionButtonLabel("Manage", icon: "person.2.fill", tint: .textPrimary)
                }
                .buttonStyle(.plain)
                Button {
                    showStatsSheet = true
                } label: {
                    actionButtonLabel("Stats", icon: "chart.bar.fill", tint: .textPrimary)
                }
                .buttonStyle(.plain)
                if !engine.isGameOver {
                    Button {
                        showSimToEndConfirm = true
                    } label: {
                        actionButtonLabel("Sim to End", icon: "forward.end.fill", tint: .textPrimary)
                    }
                    .buttonStyle(.plain)
                    .disabled(isAnimating)
                    .opacity(isAnimating ? 0.45 : 1)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.backgroundSecondary)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.surfaceBorder), alignment: .bottom)
    }

    /// Shared plate for the strip's action buttons: 44 pt minimum tap target,
    /// bordered background so they read as controls, not status chips.
    /// `prominent` swaps the neutral plate for the tint's own accent wash.
    private func actionButtonLabel(
        _ title: String, icon: String, tint: Color, prominent: Bool = false
    ) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
        .foregroundStyle(tint)
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .background(
            prominent ? tint.opacity(0.16) : Color.backgroundTertiary,
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(prominent ? tint.opacity(0.45) : Color.surfaceBorder, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }

    /// Compact current-drive summary, e.g. "Drive: 5 plays, 42 yds".
    /// Penalty walk-offs don't count as offensive yards.
    private var driveChipText: String {
        let plays = engine.currentDrivePlays
        let yards = plays
            .filter { ($0.playType == .pass || $0.playType == .run) && $0.outcome != .penalty }
            .reduce(0) { $0 + $1.yardsGained }
        return "Drive: \(plays.count) \(plays.count == 1 ? "play" : "plays"), \(yards) yds"
    }

    private func chip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.14), in: Capsule())
    }

    private var downDistanceText: String {
        let ord: String
        switch engine.down {
        case 1: ord = "1st"; case 2: ord = "2nd"; case 3: ord = "3rd"; default: ord = "\(engine.down)th"
        }
        let goal = 100 - engine.yardLine <= engine.distance
        return "\(ord) & \(goal ? "Goal" : "\(engine.distance)")"
    }

    private var fieldPositionText: String {
        let yl = engine.yardLine
        if yl == 50 { return "Midfield" }
        return yl > 50 ? "OPP \(100 - yl)" : "OWN \(yl)"
    }

    private var possessionText: String {
        let abbr = engine.homeHasPossession ? homeTeam.abbreviation : awayTeam.abbreviation
        return "\(abbr) ball"
    }

    // MARK: - Field

    private func fieldSection(height: CGFloat) -> some View {
        // Camera control stays OFF in the live game: the Coach/Broadcast
        // framing owns the shot, and a stray touch on the field must not
        // hand the camera to SceneKit's free-orbit gestures (which would
        // freeze every scripted focus/follow move off-screen for good).
        SceneKitFieldView(scene: fieldScene, allowsCameraControl: false)
            .frame(height: height)
            .overlay(alignment: .topLeading) {
                if let text = possessionBanner {
                    Text(text)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.backgroundPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.accentGold, in: Capsule())
                        .padding(10)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .overlay(alignment: .top) {
                if let text = playoffBanner {
                    HStack(spacing: 6) {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 11, weight: .black))
                        Text(text)
                            .font(.system(size: 13, weight: .black))
                            .tracking(1.4)
                    }
                    .foregroundStyle(Color.backgroundPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(Color.accentGold, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .overlay(alignment: .topTrailing) {
                VStack(alignment: .trailing, spacing: 6) {
                    if let note = sidelineNote {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 10, weight: .bold))
                            Text(note)
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundStyle(Color.backgroundPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.success, in: Capsule())
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    // Adaptive-AI intel: the opponent has read a tendency.
                    if let intel = adaptationNote {
                        HStack(spacing: 6) {
                            Image(systemName: "eye.fill")
                                .font(.system(size: 10, weight: .bold))
                            Text(intel)
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundStyle(Color.backgroundPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.warning, in: Capsule())
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(10)
            }
            .overlay(alignment: .bottomLeading) {
                if !matchupCallouts.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(matchupCallouts) { event in
                            matchupCalloutRow(event)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 50) // clear of the broadcast plate
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .overlay(alignment: .bottomTrailing) {
                HStack(spacing: 8) {
                    playbackSpeedButton
                    cameraToggleButton
                }
                .padding(10)
            }
            .overlay(alignment: .bottom) {
                if let plate = snapPlate {
                    HStack(spacing: 0) {
                        Text(plate.uppercased())
                            .font(.system(size: 17, weight: .black, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 8)
                    }
                    .background(Color.black.opacity(0.88))
                    .overlay(Rectangle().strokeBorder(Color(red: 0.75, green: 0.1, blue: 0.1), lineWidth: 2.5))
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            // Result/injury/milestone toasts anchor to the field's own lower
            // edge, so they track the field height (0.52/0.68 expansion)
            // instead of a fixed screen offset that could land on the
            // play-call cards below.
            .overlay(alignment: .bottom) { bannerOverlay }
            .animation(.spring(duration: 0.3), value: possessionBanner)
            .animation(.spring(duration: 0.3), value: playoffBanner)
            .animation(.spring(duration: 0.3), value: matchupCallouts.count)
            .animation(.spring(duration: 0.25), value: snapPlate)
            .animation(.spring(duration: 0.3), value: sidelineNote)
            .animation(.spring(duration: 0.3), value: adaptationNote)
    }

    /// 1x/2x play-speed toggle over the field: 2x halves every play timeline
    /// for the impatient. Persists across games (UserDefaults); applies from
    /// the next snap. Presentation only — the sim and the clock don't change.
    private var playbackSpeedButton: some View {
        Button {
            playbackSpeedRaw = playbackSpeedRaw >= 2 ? 1.0 : 2.0
            fieldScene.playbackSpeed = playbackSpeedRaw
        } label: {
            Text(playbackSpeedRaw >= 2 ? "2×" : "1×")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Color.black.opacity(0.45), in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(playbackSpeedRaw >= 2 ? "Play speed 2x" : "Play speed 1x")
    }

    /// Coach/Broadcast camera toggle over the field: video = the Madden-scale
    /// coach shot (default), tv = the pulled-back broadcast frame. The choice
    /// persists across games (UserDefaults) and reframes the live shot.
    private var cameraToggleButton: some View {
        Button {
            let next: FootballFieldScene.CameraStyle = cameraStyle == .coach ? .broadcast : .coach
            cameraStyleRaw = next.rawValue
            fieldScene.setCameraStyle(next)
        } label: {
            Image(systemName: cameraStyle == .coach ? "video.fill" : "tv")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Color.black.opacity(0.45), in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(cameraStyle == .coach ? "Coach camera" : "Broadcast camera")
    }

    /// One "who won the rep" line over the field: gold sword for a battle
    /// your side won, red for one it lost, purple book for a scheme bust.
    private func matchupCalloutRow(_ event: PlayMatchups.Event) -> some View {
        let playerWon = event.offenseWon == calloutsOffenseWasPlayer
        let (icon, tint): (String, Color) = {
            switch event.kind {
            case .bust: return ("book.closed.fill", Color(red: 0.72, green: 0.55, blue: 0.95))
            case .star: return ("star.fill", .accentGold)
            default:    return ("figure.american.football", playerWon ? .success : .danger)
            }
        }()
        return HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
            Text(event.text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(Color.backgroundPrimary.opacity(0.82), in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(0.5), lineWidth: 1))
    }

    // MARK: - Mini Play Feed

    /// Broadcast ticker under the field: last three plays, chronological,
    /// with the newest call emphasized (bigger type, event-color accent,
    /// light plate) and older lines stepped down so the eye lands on "now".
    private var miniPlayFeed: some View {
        let recent = Array(engine.playLog.suffix(3))
        return VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(recent.enumerated()), id: \.offset) { index, play in
                feedRow(play, age: recent.count - 1 - index)
            }
            if recent.isEmpty {
                Text("Kickoff — the game is about to start.")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(height: 96, alignment: .bottomLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.backgroundPrimary)
    }

    /// One ticker line. `age` 0 = the play that just happened.
    private func feedRow(_ play: PlayResult, age: Int) -> some View {
        let accent = feedAccentColor(play)
        let isLatest = age == 0
        return HStack(spacing: 9) {
            Circle()
                .fill(accent ?? Color.textTertiary)
                .frame(width: isLatest ? 9 : 6, height: isLatest ? 9 : 6)
            Text(play.description)
                .font(.system(size: isLatest ? 16 : 13, weight: isLatest ? .semibold : .regular))
                .foregroundStyle(isLatest ? (accent ?? Color.textPrimary) : Color.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10) // shared inset keeps the dots aligned across rows
        .padding(.vertical, isLatest ? 6 : 0)
        .background {
            if isLatest {
                RoundedRectangle(cornerRadius: 8)
                    .fill((accent ?? Color.textSecondary).opacity(accent == nil ? 0.10 : 0.14))
            }
        }
        .opacity(isLatest ? 1.0 : (age == 1 ? 0.65 : 0.4))
    }

    /// Event accent for the ticker: touchdown/score gold, turnover or sack
    /// red, first down blue, routine play neutral (nil).
    private func feedAccentColor(_ play: PlayResult) -> Color? {
        if play.scoringPlay { return .accentGold }
        if play.isTurnover || play.outcome == .sack { return .danger }
        if play.isFirstDown { return .accentBlue }
        return nil
    }

    // MARK: - Call Panel

    @ViewBuilder
    private var callPanel: some View {
        VStack(spacing: 0) {
            Divider().background(Color.surfaceBorder)
            if engine.isGameOver {
                Spacer()
            } else if awaitingKickoffDecision {
                // Onside window: the choice sits in the panel until the coach
                // explicitly kicks — no timer, no accidental commitment.
                kickoffChoicePanel
            } else if awaitingConversionDecision {
                // Post-TD: kick the XP or go for two — same commitment rules.
                conversionChoicePanel
            } else if !engine.playerIsOnOffense {
                // Opponent possession: the coach browses the call sheet in
                // peace — their offense snaps only from the READY button.
                defensePanel
            } else if isAnimating {
                animatingPanel
            } else if engine.isFourthDown && !wentForIt {
                fourthDownPanel
            } else {
                offenseCallPanel
            }
        }
        .background(Color.backgroundSecondary)
    }

    private var animatingPanel: some View {
        VStack {
            Spacer()
            HStack(spacing: 10) {
                ProgressView()
                    .tint(Color.accentGold)
                Text(engine.playerIsOnOffense ? "Play is live…" : "\(opponentAbbr) offense on the field…")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var opponentAbbr: String {
        playerTeamIsHome ? awayTeam.abbreviation : homeTeam.abbreviation
    }

    // MARK: Offense panel

    private let categories = ["Run", "Short Pass", "Medium Pass", "Deep Pass", "Special"]

    private var offenseCallPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Playbook header: the scheme decides which plays are installed.
            HStack(spacing: 8) {
                // Going for it on 4th down keeps a way back to the special
                // teams choice — nothing locks in until the snap.
                if engine.isFourthDown && wentForIt {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            wentForIt = false
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 10, weight: .black))
                            Text("4th Down")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(Color.accentGold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.accentGold.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(.plain)
                } else if goingForTwo {
                    // Two-point call sheet keeps a way back to the XP choice
                    // — nothing locks in until the snap.
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            goingForTwo = false
                            awaitingConversionDecision = true
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 10, weight: .black))
                            Text("Try Options")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(Color.accentGold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.accentGold.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Image(systemName: "book.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.accentGold)
                Text(playbookTitle)
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(Color.textTertiary)
                    .tracking(1.4)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)

            HStack(spacing: 6) {
                ForEach(categories, id: \.self) { cat in
                    categoryTab(cat)
                }
            }
            .padding(.horizontal, 14)

            // Clipboard-style call sheet: every play as a card with its
            // chalkboard art and a one-line description; installed plays first.
            let sectionPlays = OffensivePlayCall.allCases
                .filter { $0.category == selectedCategory && $0 != .kneel && $0 != .spike }
            // Stable order: installed playbook plays first, original order kept.
            let plays = sectionPlays.filter { $0.isInPlaybook(of: engine.playerOffensiveScheme) }
                + sectionPlays.filter { !$0.isInPlaybook(of: engine.playerOffensiveScheme) }
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
                    ForEach(plays, id: \.self) { play in
                        playCard(play)
                    }
                }
                .padding(.horizontal, 14)
            }

            Spacer(minLength: 0)

            // Snap bar
            HStack(spacing: 12) {
                if let suggestion = cachedSuggestion {
                    Button {
                        offCallDirtied = true // explicitly adopted — stands on a delay
                        selectedCall = suggestion
                        selectedCategory = suggestion.category
                    } label: {
                        Label(suggestion.rawValue, systemImage: "brain")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.accentBlue)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.accentBlue.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                if clockManagementAvailable && engine.pendingConversion == nil {
                    Button { snap(call: .spike) } label: {
                        Text("Spike")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.backgroundTertiary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    Button { snap(call: .kneel) } label: {
                        Text("Kneel")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.backgroundTertiary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                playClockWrapped {
                    Button {
                        if let call = selectedCall { snap(call: call) }
                    } label: {
                        Label("SNAP", systemImage: "arrow.up.circle.fill")
                            .font(.system(size: 16, weight: .black))
                            .foregroundStyle(Color.backgroundPrimary)
                            .padding(.horizontal, 30)
                            .padding(.vertical, 12)
                            .background(selectedCall != nil ? Color.accentGold : Color.backgroundTertiary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedCall == nil)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
    }

    private var playbookTitle: String {
        guard let scheme = engine.playerOffensiveScheme else { return "BASE PLAYBOOK" }
        let name = schemeDisplayName(scheme).uppercased()
        return "\(name) PLAYBOOK · \(engine.playerPlaybookFamiliarity)% LEARNED"
    }

    private func schemeDisplayName(_ scheme: OffensiveScheme) -> String {
        switch scheme {
        case .westCoast:  return "West Coast"
        case .airRaid:    return "Air Raid"
        case .spread:     return "Spread"
        case .powerRun:   return "Power Run"
        case .shanahan:   return "Wide Zone"
        case .proPassing: return "Pro Style"
        case .rpo:        return "RPO"
        case .option:     return "Option"
        }
    }

    private func categoryTab(_ category: String) -> some View {
        let isSelected = selectedCategory == category
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { selectedCategory = category }
        } label: {
            Text(shortCategoryName(category))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isSelected ? Color.backgroundPrimary : Color.textSecondary)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity)
                .background(isSelected ? Color.accentGold : Color.backgroundTertiary, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func shortCategoryName(_ category: String) -> String {
        switch category {
        case "Short Pass": return "Short"
        case "Medium Pass": return "Medium"
        case "Deep Pass": return "Deep"
        default: return category
        }
    }

    /// Clipboard-style play card: chalkboard art on top, name + badges, and a
    /// one-line coach-speak description underneath.
    private func playCard(_ play: OffensivePlayCall) -> some View {
        let isSelected = selectedCall == play
        let isSuggested = cachedSuggestion == play
        let installed = play.isInPlaybook(of: engine.playerOffensiveScheme)
        return Button {
            offCallDirtied = true // the coach's own pick — a delay snaps it
            withAnimation(.spring(duration: 0.15)) { selectedCall = play }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                PlayDiagramView(call: play)
                    .frame(maxWidth: .infinity)
                    .opacity(installed ? 1 : 0.45)
                HStack(spacing: 4) {
                    Text(play.rawValue)
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(isSelected ? Color.accentGold
                                         : (installed ? Color.textPrimary : Color.textTertiary))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    if !installed {
                        Image(systemName: "book.closed")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.textTertiary)
                    }
                    if isSuggested {
                        Image(systemName: "brain")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.accentBlue)
                    }
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.accentGold)
                    }
                }
                Text(play.blurb)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
            }
            .padding(8)
            .background(
                isSelected ? Color.accentGold.opacity(0.14) : Color.backgroundTertiary,
                in: RoundedRectangle(cornerRadius: 11)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(isSelected ? Color.accentGold : Color.surfaceBorder,
                                  lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// Spike/kneel shortcuts are only meaningful late in a half.
    private var clockManagementAvailable: Bool {
        (engine.quarter == 2 || engine.quarter >= 4) && engine.timeRemaining <= 150
    }

    /// Maps the engine's situational PlayType hint to a concrete play call,
    /// keeping the suggestion inside the team's installed playbook.
    private var aiSuggestion: OffensivePlayCall? {
        let raw: OffensivePlayCall?
        switch engine.aiOffensiveCallHint() {
        case .run:
            raw = engine.distance <= 1 ? .qbSneak : (engine.distance <= 5 ? .insideRun : .outsideRun)
        case .pass:
            if engine.distance <= 4 { raw = .slant }
            else if engine.distance <= 8 { raw = .curl }
            else { raw = .dig }
        case .kneel: raw = .kneel
        case .spike: raw = .spike
        default: raw = nil
        }
        guard let pick = raw else { return nil }
        if pick.isInPlaybook(of: engine.playerOffensiveScheme) { return pick }
        // Substitute the closest installed play from the same category.
        return OffensivePlayCall.allCases.first {
            $0.category == pick.category && $0.isInPlaybook(of: engine.playerOffensiveScheme)
        } ?? pick
    }

    // MARK: 4th down panel

    /// Special-teams decision as a selection, not an instant commit: tapping
    /// a card highlights it, SNAP executes it, and "Go For It" opens the
    /// playbook with a Back chevron — nothing snaps until the SNAP button.
    private var fourthDownPanel: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.accentGold)
                Text("4th & \(engine.distance) — your call, coach")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Color.textPrimary)
            }
            .padding(.top, 14)

            HStack(spacing: 10) {
                fourthDownButton(
                    title: "Punt",
                    subtitle: "Flip the field",
                    icon: "arrow.up.forward",
                    selected: fourthDownChoice == .punt
                ) {
                    withAnimation(.easeInOut(duration: 0.15)) { fourthDownChoice = .punt }
                }

                if engine.canAttemptFieldGoal {
                    fourthDownButton(
                        title: "Field Goal",
                        subtitle: "\(engine.fieldGoalDistance) yd attempt",
                        icon: "flag.fill",
                        selected: fourthDownChoice == .fieldGoal
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) { fourthDownChoice = .fieldGoal }
                    }
                }

                fourthDownButton(
                    title: "Go For It",
                    subtitle: "Open the playbook",
                    icon: "flame.fill",
                    selected: false
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) { wentForIt = true }
                }
            }
            .padding(.horizontal, 14)

            Spacer(minLength: 0)

            // Snap bar: the special-teams play runs only from this button.
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Selected")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textTertiary)
                    Text(fourthDownChoiceLabel)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                }
                Spacer()
                playClockWrapped {
                    Button {
                        if let choice = fourthDownChoice { snap(forcedType: choice) }
                    } label: {
                        Label("SNAP", systemImage: "arrow.up.circle.fill")
                            .font(.system(size: 16, weight: .black))
                            .foregroundStyle(Color.backgroundPrimary)
                            .padding(.horizontal, 30)
                            .padding(.vertical, 12)
                            .background(fourthDownChoice != nil ? Color.accentGold : Color.backgroundTertiary,
                                        in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(fourthDownChoice == nil)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
    }

    private var fourthDownChoiceLabel: String {
        switch fourthDownChoice {
        case .punt:      return "Punt"
        case .fieldGoal: return "Field Goal (\(engine.fieldGoalDistance) yds)"
        default:         return "None selected"
        }
    }

    private func fourthDownButton(
        title: String,
        subtitle: String,
        icon: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold))
                Text(title)
                    .font(.system(size: 14, weight: .heavy))
                Text(subtitle)
                    .font(.system(size: 10))
                    .opacity(0.75)
            }
            .foregroundStyle(selected ? Color.accentGold : Color.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                selected ? Color.accentGold.opacity(0.16) : Color.backgroundTertiary,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(selected ? Color.accentGold : Color.surfaceBorder,
                                  lineWidth: selected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Kickoff choice panel (onside window)

    /// Post-score kickoff when the onside window is open. Both options are
    /// cards — the kick launches only from the explicit KICK button, and the
    /// selection can be flipped back and forth freely.
    private var kickoffChoicePanel: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.accentGold)
                Text("Kickoff — deep or onside?")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Color.textPrimary)
            }
            .padding(.top, 14)

            HStack(spacing: 10) {
                fourthDownButton(
                    title: "Kick Deep",
                    subtitle: "Play the field position",
                    icon: "arrow.up.forward",
                    selected: !onsideSelected
                ) {
                    withAnimation(.easeInOut(duration: 0.15)) { onsideSelected = false }
                }
                fourthDownButton(
                    title: "Onside Kick",
                    subtitle: "~12% to steal it — short field if it fails",
                    icon: "flame.fill",
                    selected: onsideSelected
                ) {
                    withAnimation(.easeInOut(duration: 0.15)) { onsideSelected = true }
                }
            }
            .padding(.horizontal, 14)

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Selected")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textTertiary)
                    Text(onsideSelected ? "Onside Kick" : "Kick Deep")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                }
                Spacer()
                playClockWrapped {
                    Button {
                        disarmPlayClock()
                        awaitingKickoffDecision = false
                        if onsideSelected { attemptOnside() } else { kickDeep() }
                    } label: {
                        Label("KICK", systemImage: "arrow.up.circle.fill")
                            .font(.system(size: 16, weight: .black))
                            .foregroundStyle(Color.backgroundPrimary)
                            .padding(.horizontal, 30)
                            .padding(.vertical, 12)
                            .background(Color.accentGold, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
    }

    // MARK: Post-TD conversion panel (XP / two-point choice)

    /// After the player's touchdown: kick the extra point or go for two.
    /// Both options are cards — nothing snaps until the explicit button —
    /// and "Go for 2" opens the normal call sheet (with a Back chevron) so
    /// the try is a real called play from the 2-yard line.
    private var conversionChoicePanel: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "flag.2.crossed.fill")
                    .foregroundStyle(Color.accentGold)
                Text("Touchdown! Kick the point or go for two?")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Color.textPrimary)
            }
            .padding(.top, 14)

            HStack(spacing: 10) {
                fourthDownButton(
                    title: "Kick XP",
                    subtitle: "Near-automatic +1",
                    icon: "flag.fill",
                    selected: !conversionGoForTwo
                ) {
                    withAnimation(.easeInOut(duration: 0.15)) { conversionGoForTwo = false }
                }
                fourthDownButton(
                    title: "Go for 2",
                    subtitle: "One snap from the 2 — +2 or nothing",
                    icon: "flame.fill",
                    selected: conversionGoForTwo
                ) {
                    withAnimation(.easeInOut(duration: 0.15)) { conversionGoForTwo = true }
                }
            }
            .padding(.horizontal, 14)

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Selected")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textTertiary)
                    Text(conversionGoForTwo ? "Go for 2" : "Kick XP")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                }
                Spacer()
                playClockWrapped {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { awaitingConversionDecision = false }
                        if conversionGoForTwo {
                            goingForTwo = true
                            selectedCategory = "Run"
                            selectedCall = nil
                            cachedSuggestion = nil
                            syncFieldToSituation()
                            armPlayClock() // fresh window for calling the try
                        } else {
                            runPlay(offCall: nil, forcedType: nil)
                        }
                    } label: {
                        Label(conversionGoForTwo ? "CALL THE PLAY" : "KICK XP",
                              systemImage: conversionGoForTwo ? "book.fill" : "arrow.up.circle.fill")
                            .font(.system(size: 16, weight: .black))
                            .foregroundStyle(Color.backgroundPrimary)
                            .padding(.horizontal, 30)
                            .padding(.vertical, 12)
                            .background(Color.accentGold, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
    }

    // MARK: Defense panel

    private let defensiveCategories = ["Coverage", "Pressure", "Man", "Packages"]

    private var defensePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "shield.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.accentBlue)
                Text(defensePanelTitle)
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(Color.textTertiary)
                    .tracking(1.5)
                Spacer()
                Button {
                    skipDrive()
                } label: {
                    Label("Skip Drive", systemImage: "forward.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.backgroundTertiary, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isAnimating)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            // Same clipboard category tabs as the offensive call sheet.
            HStack(spacing: 6) {
                ForEach(defensiveCategories, id: \.self) { cat in
                    defenseCategoryTab(cat)
                }
            }
            .padding(.horizontal, 14)

            // Installed playbook calls first, original order kept.
            let sectionCalls = DefensiveCall.allCases.filter { $0.category == defCategory }
            let calls = sectionCalls.filter { $0.isInPlaybook(of: engine.playerDefensiveScheme) }
                + sectionCalls.filter { !$0.isInPlaybook(of: engine.playerDefensiveScheme) }
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
                    ForEach(calls) { call in
                        defenseCallCard(call)
                    }
                }
                .padding(.horizontal, 14)
            }

            Spacer(minLength: 0)

            // Ready bar: the opponent's offense snaps only when the coach
            // confirms — no timer, no first-tap surprises.
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(engine.pendingConversion != nil
                         ? "\(opponentAbbr) going for TWO — call your stop"
                         : "\(opponentAbbr) ball — they wait for you")
                        .font(.system(size: 10))
                        .foregroundStyle(engine.pendingConversion != nil
                                         ? Color.warning : Color.textTertiary)
                    Text(defCall.rawValue)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                }
                Spacer()
                playClockWrapped {
                    Button {
                        runPlay(offCall: nil, forcedType: nil)
                    } label: {
                        Label(isAnimating ? "PLAY IS LIVE…" : "READY — SNAP",
                              systemImage: isAnimating ? "hourglass" : "shield.checkered")
                            .font(.system(size: 16, weight: .black))
                            .foregroundStyle(Color.backgroundPrimary)
                            .padding(.horizontal, 26)
                            .padding(.vertical, 12)
                            .background(isAnimating ? Color.backgroundTertiary : Color.accentGold,
                                        in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isAnimating)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
    }

    private func defenseCategoryTab(_ category: String) -> some View {
        let isSelected = defCategory == category
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { defCategory = category }
        } label: {
            Text(category)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isSelected ? Color.backgroundPrimary : Color.textSecondary)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity)
                .background(isSelected ? Color.accentGold : Color.backgroundTertiary, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var defensePanelTitle: String {
        guard let scheme = engine.playerDefensiveScheme else { return "DEFENSIVE STANCE" }
        let name: String
        switch scheme {
        case .base34:   name = "3-4 Base"
        case .base43:   name = "4-3 Base"
        case .cover3:   name = "Cover 3"
        case .pressMan: name = "Press Man"
        case .tampa2:   name = "Tampa 2"
        case .multiple: name = "Multiple"
        case .hybrid:   name = "Hybrid"
        }
        return "\(name.uppercased()) DEFENSE · STANCE"
    }

    /// Clipboard-style defensive call card: mini X&O art, name, one-line blurb.
    private func defenseCallCard(_ call: DefensiveCall) -> some View {
        let isSelected = defCall == call
        let installed = call.isInPlaybook(of: engine.playerDefensiveScheme)
        return Button {
            defCallDirtied = true // the coach's own pick — a delay snaps it
            withAnimation(.easeInOut(duration: 0.15)) { defCall = call }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                DefenseDiagramView(coverage: call.package.coverage, blitz: call.package.blitz,
                                   manUnder: call.category == "Man")
                    .frame(maxWidth: .infinity)
                    .opacity(installed ? 1 : 0.45)
                HStack(spacing: 4) {
                    Text(call.rawValue)
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(isSelected ? Color.accentGold
                                         : (installed ? Color.textPrimary : Color.textTertiary))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    if !installed {
                        Image(systemName: "book.closed")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.textTertiary)
                    }
                }
                Text(call.blurb)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
            }
            .padding(8)
            .background(
                isSelected ? Color.accentGold.opacity(0.14) : Color.backgroundTertiary,
                in: RoundedRectangle(cornerRadius: 11)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(isSelected ? Color.accentGold : Color.surfaceBorder,
                                  lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Banner

    /// Result/injury/milestone toasts. Rendered as a bottom overlay on the
    /// field section (see fieldSection), so the stack floats just above the
    /// bottom panel whatever height the panel happens to have.
    private var bannerOverlay: some View {
            VStack(spacing: 8) {
                if let injury = injuryBanner {
                    HStack(spacing: 8) {
                        Image(systemName: "cross.fill")
                            .font(.system(size: 12, weight: .black))
                        Text(injury)
                            .font(.system(size: 14, weight: .bold))
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(Color.danger.opacity(0.95), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if let milestone = milestoneBanner {
                    HStack(spacing: 8) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 12, weight: .black))
                        Text(milestone)
                            .font(.system(size: 14, weight: .black))
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(Color.backgroundPrimary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(Color.accentGold.opacity(0.96), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if let banner = resultBanner {
                    Text(banner)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .background(Color.backgroundTertiary.opacity(0.96), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.surfaceBorder, lineWidth: 1))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            // Clear of the snap plate / matchup callouts hugging the
            // field's bottom edge.
            .padding(.bottom, 54)
        .animation(.spring(duration: 0.35), value: resultBanner)
        .animation(.spring(duration: 0.35), value: injuryBanner)
        .animation(.spring(duration: 0.35), value: milestoneBanner)
        .allowsHitTesting(false)
    }

    // MARK: - Final Overlay

    private var finalOverlay: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()

            VStack(spacing: 18) {
                Text("FINAL")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(Color.backgroundPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .background(Color.accentGold, in: Capsule())

                HStack(spacing: 28) {
                    finalTeamScore(team: awayTeam, score: engine.awayScore)
                    Text("—")
                        .font(.system(size: 26, weight: .black))
                        .foregroundStyle(Color.textTertiary)
                    finalTeamScore(team: homeTeam, score: engine.homeScore)
                }

                Text(finalVerdictText)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(playerWon ? Color.success : Color.textSecondary)

                topPerformersRow

                Button {
                    onFinish(engine)
                } label: {
                    Text("Continue")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(Color.backgroundPrimary)
                        .padding(.horizontal, 44)
                        .padding(.vertical, 13)
                        .background(Color.accentGold, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(36)
            .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Color.accentGold.opacity(0.4), lineWidth: 1.5)
            )
        }
        .transition(.opacity)
    }

    /// The three players who won the most individual matchups this game
    /// (engine tallies winners/losers from every play's battle callouts).
    @ViewBuilder
    private var topPerformersRow: some View {
        let performers = engine.topPerformers(limit: 3)
        if !performers.isEmpty {
            VStack(spacing: 8) {
                Text("TOP PERFORMERS")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(Color.textTertiary)
                    .tracking(1.6)
                HStack(spacing: 14) {
                    ForEach(performers) { performer in
                        VStack(spacing: 2) {
                            Text(performer.name)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(
                                    performer.isHomeTeam == playerTeamIsHome
                                        ? Color.accentGold : Color.textPrimary
                                )
                                .lineLimit(1)
                            Text("\(performer.wins)-\(performer.losses) battles · \(performer.isHomeTeam ? homeTeam.abbreviation : awayTeam.abbreviation)")
                                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                                .foregroundStyle(Color.textSecondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: 9))
                    }
                }
            }
            .padding(.top, 2)
        }
    }

    private func finalTeamScore(team: Team, score: Int) -> some View {
        VStack(spacing: 4) {
            Text(team.abbreviation)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(isPlayerTeam(team) ? Color.accentGold : Color.textSecondary)
            Text("\(score)")
                .font(.system(size: 44, weight: .black).monospacedDigit())
                .foregroundStyle(Color.textPrimary)
        }
    }

    private var playerWon: Bool {
        playerTeamIsHome ? engine.homeScore > engine.awayScore : engine.awayScore > engine.homeScore
    }

    private var isTie: Bool { engine.homeScore == engine.awayScore }

    /// One-line verdict under the final score. Playoff games carry
    /// single-elimination weight; regular-season games keep the classic lines.
    private var finalVerdictText: String {
        if isTie { return "It ends in a tie." }
        if isPlayoff { return playerWon ? "Advancing, coach." : "Season over." }
        return playerWon ? "Victory, coach." : "They got us today."
    }

    // MARK: - Play Clock (decision countdown)

    /// The configured window length; nil when the user switched the clock off.
    private var playClockDuration: Double? {
        switch PlayClockSetting(rawValue: playClockSettingRaw) ?? .ten {
        case .off:     return nil
        case .fifteen: return 15
        case .ten:     return Self.playClockSeconds
        }
    }

    /// Overlays and dialogs that freeze the countdown; it resumes where it
    /// left off when they close. The halftime report and a live play always
    /// pause the clock, so it can never expire under either.
    private var playClockPaused: Bool {
        isAnimating || showHalftime || showFinal || showStatsSheet || showManageSheet
            || showSimToEndConfirm || showExitConfirm
    }

    /// Opens a fresh decision window: full clock, touch flags cleared.
    /// Call whenever a call panel becomes interactive (offense sheet, defense
    /// wait, 4th-down / kickoff / point-after choice panels).
    private func armPlayClock() {
        playClockGeneration += 1
        playClockExpiring = false
        offCallDirtied = false
        defCallDirtied = false
        guard let duration = playClockDuration, !engine.isGameOver else {
            playClockArmed = false
            return
        }
        playClockTotal = duration
        playClockRemaining = duration
        playClockArmed = true
    }

    /// Closes the window (snap committed, drive skipped, sim-to-final…).
    private func disarmPlayClock() {
        playClockGeneration += 1
        playClockArmed = false
        playClockExpiring = false
    }

    private func tickPlayClock() {
        guard playClockArmed, !playClockExpiring, !playClockPaused,
              !engine.isGameOver else { return }
        playClockRemaining = max(0, playClockRemaining - 0.1)
        if playClockRemaining <= 0 { playClockDidExpire() }
    }

    /// The clock hit zero: the QB (or the DC / special teams) checks into a
    /// simple call, the picked card highlights for a beat, and the snap goes
    /// off on its own. Never a delay-of-game penalty — the branch order
    /// mirrors `callPanel` so the auto call always matches the visible panel.
    private func playClockDidExpire() {
        playClockExpiring = true
        playClockRemaining = 0
        if awaitingKickoffDecision {
            autoCommitKickoff()
        } else if awaitingConversionDecision {
            autoCommitConversion()
        } else if !engine.playerIsOnOffense {
            autoCallDefense()
        } else if engine.isFourthDown && !wentForIt && engine.pendingConversion == nil {
            autoCommitFourthDown()
        } else {
            autoCallOffense()
        }
    }

    /// Runs `commit` after the "here's the auto call" showcase beat, unless
    /// the window was invalidated meanwhile (a manual snap won the race —
    /// every manual commit path bumps `playClockGeneration`).
    private func afterAutoCallShowcase(_ commit: @escaping () -> Void) {
        let generation = playClockGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.autoCallShowcaseSeconds) {
            guard generation == playClockGeneration, playClockExpiring else { return }
            disarmPlayClock()
            commit()
        }
    }

    // MARK: Auto calls (delay of decision, never delay of game)

    /// Offense delay: a card the coach dialed himself stands and snaps;
    /// otherwise the QB checks it down — 3rd/4th & long takes the installed
    /// short base pass, anything else ~50/50 Inside Run / short pass.
    private func autoCallOffense() {
        let qbName = engine.currentOffenseUnit[0].shortName
        let pick: OffensivePlayCall
        if offCallDirtied, let dialed = selectedCall {
            pick = dialed
            engine.postFeedNote("Delay — \(qbName) snaps the call as dialed: \(dialed.rawValue)")
        } else {
            pick = qbCheckdownCall()
            engine.postFeedNote("Delay — \(qbName) checks into \(pick.rawValue)")
            withAnimation(.spring(duration: 0.25)) {
                selectedCategory = pick.category
                selectedCall = pick
            }
        }
        afterAutoCallShowcase { snap(call: pick) }
    }

    /// Defense delay: a call the coach picked this window stands; otherwise
    /// the DC checks the unit into the scheme's base shell.
    private func autoCallDefense() {
        if defCallDirtied {
            engine.postFeedNote("Delay — \(playerAbbr) defense rolls with \(defCall.rawValue)")
        } else {
            let base = schemeBaseDefensiveCall
            engine.postFeedNote("Delay — \(playerAbbr) defense checks into \(base.rawValue)")
            withAnimation(.easeInOut(duration: 0.2)) {
                defCategory = base.category
                defCall = base
            }
        }
        afterAutoCallShowcase { runPlay(offCall: nil, forcedType: nil) }
    }

    /// 4th-down delay: send out whichever special-teams card is highlighted
    /// (the panel pre-selects FG when in range, punt otherwise).
    private func autoCommitFourthDown() {
        let choice = fourthDownChoice ?? (engine.canAttemptFieldGoal ? .fieldGoal : .punt)
        withAnimation(.easeInOut(duration: 0.15)) { fourthDownChoice = choice }
        engine.postFeedNote(choice == .fieldGoal
            ? "Delay — the field goal unit trots out"
            : "Delay — the punt team takes the field")
        afterAutoCallShowcase { snap(forcedType: choice) }
    }

    /// Kickoff-panel delay: boot whatever's highlighted (deep by default;
    /// an onside selection the coach dialed but never committed stands).
    private func autoCommitKickoff() {
        engine.postFeedNote(onsideSelected
            ? "Delay — the onside unit stays on"
            : "Delay — \(playerAbbr) kicks it deep")
        afterAutoCallShowcase {
            awaitingKickoffDecision = false
            if onsideSelected { attemptOnside() } else { kickDeep() }
        }
    }

    /// Post-TD panel delay: commit the highlighted try. XP just kicks; a
    /// dialed "Go for 2" opens the sheet with an auto-called simple play so
    /// the try still snaps on its own.
    private func autoCommitConversion() {
        if conversionGoForTwo {
            let pick = Bool.random() ? installedRun() : installedShortPass()
            engine.postFeedNote("Delay — \(engine.currentOffenseUnit[0].shortName) checks into \(pick.rawValue) on the try")
            withAnimation(.easeInOut(duration: 0.2)) { awaitingConversionDecision = false }
            goingForTwo = true
            selectedCategory = pick.category
            cachedSuggestion = nil
            selectedCall = pick
            afterAutoCallShowcase { snap(call: pick) }
        } else {
            engine.postFeedNote("Delay — the extra point unit holds steady")
            afterAutoCallShowcase { runPlay(offCall: nil, forcedType: nil) }
        }
    }

    /// The QB's bail-out call when the play clock runs dry.
    private func qbCheckdownCall() -> OffensivePlayCall {
        // 3rd/4th & long: no auto-run into the sticks — base short pass.
        if engine.down >= 3 && engine.distance >= 7 { return installedShortPass() }
        return Bool.random() ? installedRun() : installedShortPass()
    }

    /// The playbook's base short pass (first installed Short Pass; Slant fallback).
    private func installedShortPass() -> OffensivePlayCall {
        OffensivePlayCall.allCases.first {
            $0.category == "Short Pass" && $0.isInPlaybook(of: engine.playerOffensiveScheme)
        } ?? .slant
    }

    /// The playbook's base run (Inside Run whenever it's installed).
    private func installedRun() -> OffensivePlayCall {
        if OffensivePlayCall.insideRun.isInPlaybook(of: engine.playerOffensiveScheme) {
            return .insideRun
        }
        return OffensivePlayCall.allCases.first {
            $0.category == "Run" && $0.isInPlaybook(of: engine.playerOffensiveScheme)
        } ?? .insideRun
    }

    /// The DC's "check into base" call on a delay: the simplest sound shell
    /// from the coached team's defensive scheme (always installed).
    private var schemeBaseDefensiveCall: DefensiveCall {
        switch engine.playerDefensiveScheme {
        case .tampa2, .base43: return .cover2Shell
        case .pressMan:        return .manFree
        default:               return .cover3Base // base34 / cover3 / multiple / hybrid / nil
        }
    }

    // MARK: Play clock visuals

    private var playClockVisible: Bool {
        playClockArmed && !engine.isGameOver
    }

    /// Gold while comfortable, amber under 5 s, red (pulsing) under 3 s.
    private var playClockColor: Color {
        if playClockRemaining <= 3 { return .danger }
        if playClockRemaining <= 5 { return .warning }
        return .accentGold
    }

    private var playClockFraction: CGFloat {
        guard playClockTotal > 0 else { return 0 }
        return CGFloat(max(0, playClockRemaining) / playClockTotal)
    }

    /// Wraps a snap-bar commit button (SNAP / READY / KICK / KICK XP) with
    /// the decision-clock ring; the final five seconds add the countdown
    /// number beside it. Inert when the clock is off or disarmed.
    private func playClockWrapped<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 10) {
            if playClockVisible && playClockRemaining <= 5 {
                Text("\(Int(playClockRemaining.rounded(.up)))")
                    .font(.system(size: 17, weight: .black).monospacedDigit())
                    .foregroundStyle(playClockColor)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.snappy(duration: 0.2), value: Int(playClockRemaining.rounded(.up)))
                    .frame(width: 38, height: 38)
                    .background(playClockColor.opacity(0.14), in: Circle())
                    .overlay(Circle().strokeBorder(playClockColor, lineWidth: 2))
                    .modifier(PlayClockPulse(active: playClockRemaining <= 3))
                    .transition(.scale.combined(with: .opacity))
            }
            content()
                .overlay {
                    if playClockVisible {
                        Capsule()
                            .trim(from: 0, to: max(0.003, playClockFraction))
                            .stroke(playClockColor,
                                    style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .padding(-4.5)
                            .animation(.linear(duration: 0.1), value: playClockFraction)
                            .modifier(PlayClockPulse(active: playClockRemaining <= 3))
                            .allowsHitTesting(false)
                    }
                }
        }
        .animation(.spring(duration: 0.25), value: playClockVisible && playClockRemaining <= 5)
    }

    // MARK: - Game Flow

    private func startGame() {
        guard !gameStarted else { return }
        gameStarted = true

        // Scrimmage framing: the persisted Coach/Broadcast choice (billboard
        // numbers hide in the coach shot). No refocus yet — the opening
        // focusCamera below places the shot without animation.
        fieldScene.setCameraStyle(cameraStyle, refocus: false)

        // Persisted play-animation speed (the HUD 1x/2x toggle).
        fieldScene.playbackSpeed = playbackSpeedRaw

        // The camera always shoots from behind the PLAYER's own unit —
        // mirrored for away games (field text re-orients with it).
        fieldScene.setViewFacing(playerTeamIsHome ? 1 : -1)

        // Weather dressing: rain streaks + dim lights, snowfall + snow
        // blanket, or nothing for clear/wind.
        fieldScene.setWeather(weather)

        // NFL convention: home wears team color, road team wears white with
        // team-color pants and helmet — always readable against the grass.
        let colors = MatchTeamColors.matchup(home: homeTeam.abbreviation, away: awayTeam.abbreviation)
        fieldScene.setUniforms(
            home: .home(teamColor: colors.home, abbreviation: homeTeam.abbreviation),
            away: .away(teamColor: colors.away, abbreviation: awayTeam.abbreviation)
        )
        fieldScene.setFieldDressing(
            homeAbbr: homeTeam.abbreviation,
            awayAbbr: awayTeam.abbreviation,
            homeColor: colors.home
        )
        fieldScene.setEndZoneColors(home: colors.home, away: colors.away)

        // Opening lineup: kickoff formation when the opening kick is pending,
        // scrimmage formation otherwise.
        if let kickoff = engine.pendingKickoff {
            let kickFormation = PlayChoreographer.kickoffFormation(kickingTeamIsHome: kickoff.kickingTeamIsHome)
            fieldScene.movePlayersToFormation(home: kickFormation.home, away: kickFormation.away, duration: 0.1)
            // Kickoffs always use the wide broadcast frame — the units are
            // spread across 60 yards and the coach shot can't hold them.
            fieldScene.focusCamera(
                z: PlayChoreographer.kickoffSpotZ(kickingTeamIsHome: kickoff.kickingTeamIsHome),
                animated: false,
                style: .broadcast
            )
        } else {
            let losZ = PlayChoreographer.losZ(yardLine: engine.yardLine, offenseIsHome: engine.homeHasPossession)
            let formation = PlayChoreographer.formation(
                for: .run, losZ: losZ, direction: engine.homeHasPossession ? 1 : -1,
                offenseNumbers: engine.currentOffenseUnit.numbers,
                defenseNumbers: engine.currentDefenseUnit.numbers
            )
            let openingStances = PlayChoreographer.stances(offenseIsHome: engine.homeHasPossession)
            let openingBuilds = PlayChoreographer.bodyTypes(offenseIsHome: engine.homeHasPossession)
            fieldScene.movePlayersToFormation(home: formation.home, away: formation.away, duration: 0.1,
                                              stancesHome: openingStances.home, stancesAway: openingStances.away,
                                              bodyTypesHome: openingBuilds.home, bodyTypesAway: openingBuilds.away)
            fieldScene.setDefensiveFraming(engine.homeHasPossession != playerTeamIsHome)
            fieldScene.focusCamera(z: losZ, animated: false)
        }

        // Playoff kickoff: the stakes plate flashes over the field before the
        // opening boot — win or go home.
        if isPlayoff {
            let text = "WIN OR GO HOME"
            playoffBanner = text
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.4) {
                if playoffBanner == text { playoffBanner = nil }
            }
        }

        showPossessionBanner()
        proceed(after: 1.0)
    }

    /// Decides what happens after a play fully resolves.
    private func proceed(after delay: TimeInterval = 0.8) {
        guard !engine.isGameOver else {
            withAnimation(.easeInOut(duration: 0.3)) { showFinal = true }
            return
        }
        // Halftime: pause the flow on the report card before the second-half
        // kickoff. Dismissing it re-enters proceed() and runs the kick.
        if engine.halftimePending {
            withAnimation(.easeInOut(duration: 0.3)) { showHalftime = true }
            return
        }
        // Post-TD point-after try — it snaps before the ensuing kickoff (the
        // onside question, when live, follows it as the next panel). The
        // coach picks XP or two for his own team; the AI follows the shared
        // chart: its XP kicks run automatically, a two-point try lines up
        // and waits for the coach's defensive call (READY snaps it).
        if engine.pendingConversion != nil {
            goingForTwo = false
            if engine.playerAttemptsConversion {
                conversionGoForTwo = false
                withAnimation(.easeInOut(duration: 0.2)) { awaitingConversionDecision = true }
                armPlayClock()
            } else if engine.chartCallsForTwo {
                // The AI goes for two: the coach calls the stop — decision clock on.
                syncFieldToSituation()
                armPlayClock()
            } else {
                runPlay(offCall: nil, forcedType: nil)
            }
            return
        }
        // A drive that begins with a kickoff plays the boot first. When the
        // situation calls for it, the coach chooses deep/onside from a call
        // panel — cancellable until the explicit KICK button (or the clock).
        if let kickoff = engine.pendingKickoff {
            if engine.onsideKickAvailable {
                onsideSelected = false
                withAnimation(.easeInOut(duration: 0.2)) { awaitingKickoffDecision = true }
                armPlayClock()
                return
            }
            engine.clearPendingKickoff()
            runKickoff(kickoff)
            return
        }
        if engine.playerIsOnOffense {
            // Huddle up, then line the teams up at the new scrimmage spot
            // while the user considers the call, and pre-select the AI pick.
            lineUpWithHuddle()
            cachedSuggestion = aiSuggestion
            selectedCall = cachedSuggestion
            if let suggestion = selectedCall { selectedCategory = suggestion.category }
            wentForIt = false
            fourthDownChoice = engine.isFourthDown
                ? (engine.canAttemptFieldGoal ? .fieldGoal : .punt)
                : nil
            armPlayClock()
        } else {
            // Opponent possession: their offense huddles and lines up —
            // the snap comes from the READY button or the decision clock.
            lineUpWithHuddle()
            armPlayClock()
        }
    }

    /// Between-plays lineup: the offense gathers into a quick huddle ring
    /// ~7 yd behind the new spot for ~1.2 s, then breaks to the line.
    /// Hurry-up football (final two minutes of a half), skips and the very
    /// first snap go straight to the formation.
    private func lineUpWithHuddle() {
        let hurryUp = (engine.quarter == 2 || engine.quarter >= 4) && engine.timeRemaining <= 120
        guard gameStarted, !hurryUp, !engine.isGameOver else {
            syncFieldToSituation()
            return
        }
        let offenseIsHome = engine.homeHasPossession
        let losZ = PlayChoreographer.losZ(yardLine: engine.yardLine, offenseIsHome: offenseIsHome)
        fieldScene.huddle(
            teamIsHome: offenseIsHome,
            positions: PlayChoreographer.huddlePositions(losZ: losZ,
                                                         direction: offenseIsHome ? 1 : -1)
        )
        huddleBreakTime = Date().addingTimeInterval(1.2)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            huddleBreakTime = nil
            // The snap (or a skip) may already own the field again.
            guard !isAnimating, !engine.isGameOver else { return }
            syncFieldToSituation()
        }
    }

    private func snap(call: OffensivePlayCall) {
        runPlay(offCall: call, forcedType: nil)
    }

    private func snap(forcedType: PlayType) {
        runPlay(offCall: nil, forcedType: forcedType)
    }

    // MARK: - Kickoffs

    /// Animates a kickoff (opening kick, post-score, second half, OT) before
    /// the new drive's first snap. The outcome is already decided — this is
    /// pure presentation of the engine's kickoff draw.
    private func runKickoff(_ event: LiveGameEngine.KickoffEvent) {
        disarmPlayClock()
        isAnimating = true
        let formation = PlayChoreographer.kickoffFormation(kickingTeamIsHome: event.kickingTeamIsHome)
        fieldScene.movePlayersToFormation(home: formation.home, away: formation.away, duration: 0.7)
        fieldScene.updateMarkers(losZ: nil, firstDownZ: nil)
        fieldScene.setDefensiveFraming(false)
        // Broadcast frame for the whole kickoff presentation (the follow-cam
        // keeps the same style through the return; the next scrimmage
        // pre-snap hands the shot back to the Coach/Broadcast choice).
        fieldScene.focusCamera(z: PlayChoreographer.kickoffSpotZ(kickingTeamIsHome: event.kickingTeamIsHome),
                               style: .broadcast)

        let steps = PlayChoreographer.kickoffSteps(
            kickingTeamIsHome: event.kickingTeamIsHome,
            returnYardLine: event.startYardLine,
            isTouchback: event.isTouchback,
            isReturnTouchdown: event.isReturnTouchdown
        )
        // Covers the 0.7 s formation move + the staggered departures.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.15) {
            fieldScene.runPlay(steps: steps) {
                isAnimating = false
                if event.isReturnTouchdown {
                    // Housed: camera to the end zone the returner reached.
                    let endzoneZ: Float = event.kickingTeamIsHome ? -50 : 50
                    fieldScene.focusCamera(z: endzoneZ, duration: 1.0, style: .broadcast)
                    fieldScene.celebrate(atZ: endzoneZ)
                    showBanner("The kickoff is returned ALL THE WAY for a touchdown!")
                } else if event.isTouchback {
                    showBanner("Touchback — the drive starts at the \(event.startYardLine).")
                } else {
                    showBanner("The kick is returned out to the \(event.startYardLine).")
                }
                showPossessionBanner()
                proceed(after: event.isReturnTouchdown ? 1.8 : 0.8)
            }
        }
    }

    // MARK: - Onside kick

    private var playerAbbr: String {
        playerTeamIsHome ? homeTeam.abbreviation : awayTeam.abbreviation
    }

    /// The coached team's live model (Coach's Board holdout context).
    private var playerTeamModel: Team {
        playerTeamIsHome ? homeTeam : awayTeam
    }

    private func attemptOnside() {
        let recovered = engine.attemptOnsideKick()
        syncFieldToSituation()
        showBanner(recovered
            ? "ONSIDE KICK — \(playerAbbr) recovers!"
            : "The onside kick fails — \(opponentAbbr) takes over with a short field.")
        showPossessionBanner()
        proceed(after: 1.4)
    }

    private func kickDeep() {
        guard let kickoff = engine.pendingKickoff else {
            proceed()
            return
        }
        engine.clearPendingKickoff()
        runKickoff(kickoff)
    }

    /// Role-ordered top speeds (yd/s) for a field unit, mapped from each
    /// man's SPEED attribute (40-99) onto the choreographer's physical band:
    /// ~6.5 yd/s for a lumbering lineman up to ~9.5 for a burner. The play
    /// animation covers every yard at these speeds, so fast players are
    /// visibly fast — presentation only, outcomes are already decided.
    private func fieldSpeeds(_ unit: FieldUnit) -> [Float] {
        unit.players.map { player in
            let attribute = Float(player.physical.speed)
            return min(max(6.5 + (attribute - 40) / 59 * 3.0, 6.3), 9.5)
        }
    }

    /// Steps the engine one play and choreographs the result on the field.
    private func runPlay(offCall: OffensivePlayCall?, forcedType: PlayType?) {
        guard !isAnimating, !engine.isGameOver else { return }

        // The snap commits the decision — the countdown ends here (a manual
        // snap racing an in-flight auto call also invalidates it).
        disarmPlayClock()

        let losYard = engine.yardLine
        let distanceBefore = engine.distance
        let offenseIsHome = engine.homeHasPossession
        let possessionBefore = engine.homeHasPossession

        // Retro broadcast plate for the snap — situation plus the called play
        // when the coach dialed one ("2ND & 10 · DIG"); point-after tries get
        // their own plates ("2-PT TRY · GOAL LINE DIVE" / "EXTRA POINT").
        let isConversionSnap = engine.pendingConversion != nil
        let conversionIsTwo = isConversionSnap
            && (engine.playerAttemptsConversion ? conversionGoForTwo : engine.chartCallsForTwo)
        let plateText: String
        if isConversionSnap {
            plateText = conversionIsTwo
                ? (offCall.map { "2-PT TRY · \($0.rawValue.uppercased())" } ?? "2-PT TRY")
                : "EXTRA POINT"
        } else {
            plateText = offCall.map { "\(downDistanceText) · \($0.rawValue.uppercased())" }
                ?? downDistanceText
        }
        snapPlate = plateText
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            if snapPlate == plateText { snapPlate = nil }
        }

        // Both sides always play a real call: yours from the call sheet, the
        // AI's from its situational picker — so both formations mean something.
        let defPackage = engine.playerIsOnOffense
            ? engine.aiDefensivePackage()
            : defCall.package

        // Capture the on-field units BEFORE the step: if this play knocks a
        // player out, the engine swaps his replacement in immediately, but
        // THIS play must still animate with the men who actually ran it.
        let offUnit = possessionBefore ? engine.homeOffenseUnit : engine.awayOffenseUnit
        let defUnit = possessionBefore ? engine.awayDefenseUnit : engine.homeDefenseUnit

        let play: PlayResult
        // The call the choreography animates: yours as dialed, or — on the
        // opponent's snap — the adaptive AI's counter play when its read of
        // your defensive tendencies triggered one (nil = base AI, as today).
        var animatedCall = offCall
        if isConversionSnap {
            // Point-after try: the player's explicit XP/two choice (his own
            // score) or the shared chart (AI score, defended with defCall).
            play = engine.attemptConversion(
                goForTwo: engine.playerAttemptsConversion ? conversionGoForTwo : nil,
                offensiveCall: engine.playerAttemptsConversion ? offCall : nil,
                defensivePackage: defPackage
            )
        } else {
            if !engine.playerIsOnOffense { animatedCall = engine.aiOffensiveCall() }
            play = engine.step(
                offensiveCall: engine.playerIsOnOffense ? offCall : animatedCall,
                forcedPlayType: forcedType,
                defensivePackage: defPackage
            )
        }

        isAnimating = true
        selectedCall = nil

        let matchups = engine.lastMatchups

        // Pre-snap: shift both teams into the alignment their calls dictate,
        // then run the play from that same look.
        let formation = PlayChoreographer.preSnapStep(
            for: play, losYardLine: losYard, offenseIsHome: offenseIsHome,
            call: animatedCall, defensivePackage: defPackage,
            offenseNumbers: offUnit.numbers, defenseNumbers: defUnit.numbers
        )
        let presnapStances = PlayChoreographer.stances(offenseIsHome: offenseIsHome,
                                                       call: animatedCall)
        let presnapBuilds = PlayChoreographer.bodyTypes(offenseIsHome: offenseIsHome)
        fieldScene.movePlayersToFormation(home: formation.home, away: formation.away, duration: 0.7,
                                          stancesHome: presnapStances.home, stancesAway: presnapStances.away,
                                          bodyTypesHome: presnapBuilds.home, bodyTypesAway: presnapBuilds.away)

        // Markers stay on THIS play's line/1st-down through the animation.
        let playLosZ = PlayChoreographer.losZ(yardLine: losYard, offenseIsHome: offenseIsHome)
        let playDir: Float = offenseIsHome ? 1 : -1

        // Ball at the center's feet for the snap exchange.
        fieldScene.moveBall(to: SCNVector3(0, 0.26, playLosZ))

        // Kicks get the broadcast angle from low behind the posts; every
        // other play keeps the normal scrimmage framing.
        fieldScene.setDefensiveFraming(offenseIsHome != playerTeamIsHome)
        if play.playType == .fieldGoal || play.playType == .extraPoint {
            fieldScene.kickCamera(towardZ: playDir)
        } else {
            // Pre-snap push-in toward the LOS; the snap cuts it off.
            fieldScene.focusCamera(z: playLosZ, pushIn: true)
        }
        let playGoalToGo = 100 - losYard <= distanceBefore
        fieldScene.updateMarkers(
            losZ: playLosZ,
            firstDownZ: playGoalToGo ? nil : playLosZ + playDir * Float(distanceBefore),
            offenseDirection: playDir
        )

        // 1.15 s pre-snap window: the 0.7 s formation move plus the 0-0.4 s
        // staggered departures finish before the ball moves.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.15) {
            let steps = PlayChoreographer.steps(for: play, losYardLine: losYard,
                                                offenseIsHome: offenseIsHome, matchups: matchups,
                                                call: animatedCall, defensivePackage: defPackage,
                                                offenseSpeeds: fieldSpeeds(offUnit),
                                                defenseSpeeds: fieldSpeeds(defUnit))
            // A flagged play gets the yellow laundry: the flag flies in while
            // the (wiped-out) snap plays out.
            if play.outcome == .penalty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    fieldScene.throwFlag(atZ: playLosZ)
                }
            }
            fieldScene.runPlay(steps: steps) {
                finishPlay(play, possessionBefore: possessionBefore,
                           distanceBefore: distanceBefore)
            }
        }
    }

    private func finishPlay(_ play: PlayResult, possessionBefore: Bool,
                            distanceBefore: Int = 99) {
        isAnimating = false

        // The back judge sells the result: touchdown arms for scores, the
        // downfield point when the play moved the chains.
        let movedChains = play.playType != .twoPointConversion
            && (play.outcome == .rush || play.outcome == .completion)
            && play.yardsGained >= distanceBefore
        if play.pointsScored >= 6 {
            fieldScene.refereeSignalTouchdown()
        } else if movedChains {
            fieldScene.refereeSignalFirstDown()
        }

        // The kick camera hands the shot back to normal framing at the new
        // scrimmage spot (a made kick refocuses again to the end zone below).
        if play.playType == .fieldGoal || play.playType == .extraPoint {
            fieldScene.focusCamera(
                z: PlayChoreographer.losZ(yardLine: engine.yardLine,
                                          offenseIsHome: engine.homeHasPossession),
                duration: 1.0
            )
        }

        // Scoring plays get the full presentation: camera to the end zone
        // and a confetti burst for touchdowns.
        if play.scoringPlay {
            let endzoneZ: Float = possessionBefore ? 50 : -50
            fieldScene.focusCamera(z: endzoneZ, duration: 1.1)
            if play.pointsScored >= 6 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    fieldScene.celebrate(atZ: endzoneZ)
                }
            }
        }

        showBanner(play.description)

        // Two-point try verdict: gold broadcast plate over the field.
        if play.playType == .twoPointConversion {
            showMilestoneBanner(play.outcome == .twoPointGood
                ? "TWO-POINT CONVERSION — GOOD!"
                : "TWO-POINT TRY — NO GOOD")
        }

        showMatchupCallouts(possessionBefore: possessionBefore)

        // Injury on the play: the man stays on the turf (the next formation
        // move stands the node up wearing his replacement's number) and the
        // red banner names him.
        let hadInjury = !engine.lastPlayInjuries.isEmpty
        if hadInjury {
            for event in engine.lastPlayInjuries {
                if let node = event.nodeIndex { fieldScene.stayDown(nodeIndex: node) }
            }
            if let first = engine.lastPlayInjuries.first {
                showInjuryBanner("INJURY: \(first.playerName) (\(first.position)) — leaves the game")
            }
        }

        if engine.homeHasPossession != possessionBefore && !engine.isGameOver {
            showPossessionBanner()
        }

        // Post-tackle beat (coach shot only — a no-op in broadcast framing):
        // the camera eases ~30 % out for a second so the pile reads, then
        // the next pre-snap sync restores the tight frame. Kicks and scores
        // were refocused above and skip it.
        let wasKick = play.playType == .fieldGoal || play.playType == .extraPoint
        if !play.scoringPlay && !wasKick {
            fieldScene.pullBackAfterPlay()
        }

        if hadInjury {
            // Hold the shot on the downed player for a beat — the next
            // formation move (inside proceed) brings the replacement on.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) {
                guard !isAnimating else { return }
                proceed(after: 0.9)
            }
        } else if play.scoringPlay || wasKick {
            proceed(after: play.scoringPlay ? 1.6 : 0.9)
        } else {
            // Let the pull-back breathe before the next formation forms up.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) {
                guard !isAnimating else { return }
                proceed(after: 0.9)
            }
        }
    }

    /// Runs the rest of the opponent's drive instantly (no animation).
    /// Works mid-animation too — the current play's outcome is already
    /// decided, so cancelling the visuals loses nothing.
    private func skipDrive() {
        guard !engine.isGameOver, !engine.playerIsOnOffense else { return }
        disarmPlayClock() // skipping bypasses the clock; proceed() re-arms it
        fieldScene.cancelPlay()
        isAnimating = false
        var safety = 0
        // Stop at the break too — the halftime report must not be skipped
        // past when the opponent's drive ends the half.
        while !engine.playerIsOnOffense && !engine.isGameOver
                && !engine.halftimePending && safety < 40 {
            // The adaptive AI keeps exploiting the standing defensive call
            // inside a skipped drive too (nil = base logic, as before).
            engine.step(offensiveCall: engine.aiOffensiveCall(),
                        defensivePackage: defCall.package)
            safety += 1
        }
        syncFieldToSituation()
        if let last = engine.lastPlay { showBanner(last.description) }
        // Injuries rolled during the skipped plays still deserve the banner
        // (the write-back happens at persist regardless).
        if let injury = engine.lastPlayInjuries.first {
            showInjuryBanner("INJURY: \(injury.playerName) (\(injury.position)) — leaves the game")
        }
        showPossessionBanner()
        proceed(after: 0.6)
    }

    private func simToEnd() {
        guard !engine.isGameOver else { return }
        disarmPlayClock()
        fieldScene.cancelPlay()
        isAnimating = false
        engine.simToEnd()
        syncFieldToSituation()
        withAnimation(.easeInOut(duration: 0.3)) { showFinal = true }
    }

    /// Teleports the formation/camera to the engine's current situation,
    /// aligned to whatever calls are currently on the table.
    private func syncFieldToSituation() {
        let losZ = PlayChoreographer.losZ(yardLine: engine.yardLine, offenseIsHome: engine.homeHasPossession)
        let formation = PlayChoreographer.formation(
            for: .run,
            call: engine.playerIsOnOffense ? (selectedCall ?? cachedSuggestion) : nil,
            defensivePackage: engine.playerIsOnOffense ? engine.aiDefensivePackage() : defCall.package,
            losZ: losZ, direction: engine.homeHasPossession ? 1 : -1,
            offenseNumbers: engine.currentOffenseUnit.numbers,
            defenseNumbers: engine.currentDefenseUnit.numbers
        )
        let stances = PlayChoreographer.stances(
            offenseIsHome: engine.homeHasPossession,
            call: engine.playerIsOnOffense ? (selectedCall ?? cachedSuggestion) : nil)
        let builds = PlayChoreographer.bodyTypes(offenseIsHome: engine.homeHasPossession)
        fieldScene.movePlayersToFormation(home: formation.home, away: formation.away, duration: 0.3,
                                          stancesHome: stances.home, stancesAway: stances.away,
                                          bodyTypesHome: builds.home, bodyTypesAway: builds.away)
        fieldScene.setDefensiveFraming(engine.homeHasPossession != playerTeamIsHome)
        // Stage the ball at the new spot so the snap exchange starts at the
        // center's feet, not wherever the last play left it.
        fieldScene.moveBall(to: SCNVector3(0, 0.26, losZ))
        // Broadcast push-in: a slow 2-yard dolly toward the line while the
        // coach considers the call; the snap (runPlay) interrupts it.
        fieldScene.focusCamera(z: losZ, pushIn: true)
        updateMarkers()
    }

    /// Positions the broadcast LOS/first-down stripes for the current situation.
    private func updateMarkers() {
        guard !engine.isGameOver else {
            fieldScene.updateMarkers(losZ: nil, firstDownZ: nil)
            return
        }
        let dir: Float = engine.homeHasPossession ? 1 : -1
        let losZ = PlayChoreographer.losZ(yardLine: engine.yardLine, offenseIsHome: engine.homeHasPossession)
        let goalToGo = 100 - engine.yardLine <= engine.distance
        let firstDownZ: Float? = goalToGo ? nil : losZ + dir * Float(engine.distance)
        fieldScene.updateMarkers(losZ: losZ, firstDownZ: firstDownZ, offenseDirection: dir)
    }

    /// Live pre-snap preview: browsing the call sheet realigns the offense on
    /// the field (I-form for inside runs, spread for deep shots), and changing
    /// the defensive call re-shows the shell/blitz look. While the offense is
    /// mid-huddle the preview waits — the scheduled break applies the newest
    /// call anyway.
    private func previewFormation() {
        guard gameStarted, !isAnimating, !engine.isGameOver else { return }
        if let breakTime = huddleBreakTime, breakTime > Date() { return }
        syncFieldToSituation()
    }

    /// Fires the "2-MINUTE WARNING" chip once per half when the clock first
    /// crosses 2:00 in Q2/Q4 (the scoreboard clock keeps pulsing red for the
    /// rest of the window).
    private func checkTwoMinuteWarning(_ remaining: Int) {
        guard remaining <= 120, remaining > 0,
              engine.quarter == 2 || engine.quarter == 4,
              !engine.isGameOver,
              !twoMinuteWarnedQuarters.contains(engine.quarter) else { return }
        twoMinuteWarnedQuarters.insert(engine.quarter)
        withAnimation(.spring(duration: 0.3)) { showTwoMinuteChip = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            withAnimation(.easeOut(duration: 0.3)) { showTwoMinuteChip = false }
        }
    }

    /// Burns one of the player's timeouts: the game clock freezes for the
    /// next snap (the engine zeroes that play's clock runoff).
    private func callTimeout() {
        guard engine.useTimeout(home: playerTeamIsHome) else { return }
        showBanner("Timeout, \(playerAbbr) — the clock is stopped.")
        // A timeout buys thinking time: the decision clock refills (too late
        // once the delay auto-call is already in motion).
        if playClockArmed, !playClockExpiring, let duration = playClockDuration {
            playClockTotal = duration
            playClockRemaining = duration
        }
    }

    private func showBanner(_ text: String) {
        resultBanner = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
            if resultBanner == text { resultBanner = nil }
        }
    }

    private func showInjuryBanner(_ text: String) {
        injuryBanner = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.6) {
            if injuryBanner == text { injuryBanner = nil }
        }
    }

    private func showMilestoneBanner(_ text: String) {
        milestoneBanner = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
            if milestoneBanner == text { milestoneBanner = nil }
        }
    }

    private func showSidelineNote(_ text: String) {
        sidelineNote = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
            if sidelineNote == text { sidelineNote = nil }
        }
    }

    /// Adaptive-AI intel chip — held a beat longer than the sideline note so
    /// the coach can actually read the scouting line mid-broadcast.
    private func showAdaptationNote(_ text: String) {
        adaptationNote = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
            if adaptationNote == text { adaptationNote = nil }
        }
    }

    /// Surfaces the last play's individual battles: callout capsules over the
    /// field and a pulse on each matchup winner so the coach can find him.
    private func showMatchupCallouts(possessionBefore: Bool) {
        guard let matchups = engine.lastMatchups, !matchups.events.isEmpty else {
            matchupCallouts = []
            return
        }
        let events = Array(matchups.events.prefix(2))
        calloutsOffenseWasPlayer = (playerTeamIsHome == possessionBefore)
        matchupCallouts = events

        let oBase = possessionBefore ? 0 : 11
        let dBase = possessionBefore ? 11 : 0
        for event in events {
            let winnerNode = event.offenseWon
                ? event.offRole.map { oBase + $0 }
                : event.defRole.map { dBase + $0 }
            if let winnerNode { fieldScene.pulse(nodeIndex: winnerNode) }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.4) {
            if matchupCallouts.first?.id == events.first?.id { matchupCallouts = [] }
        }
    }

    private func showPossessionBanner() {
        let abbr = engine.homeHasPossession ? homeTeam.abbreviation : awayTeam.abbreviation
        let text = "\(abbr) ball · 1st & 10"
        possessionBanner = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            if possessionBanner == text { possessionBanner = nil }
        }
    }
}

// MARK: - Play Clock Pulse

/// Opacity pulse applied to the decision-clock ring and countdown number
/// over the final three seconds. A steady no-op while `active` is false.
private struct PlayClockPulse: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        content.phaseAnimator([false, true]) { view, dimmed in
            view.opacity(active && dimmed ? 0.35 : 1.0)
        } animation: { _ in .easeInOut(duration: 0.3) }
    }
}

// MARK: - Live Box Score Sheet

/// Mid-game box score: quarter-by-quarter line score, total yards, and the
/// statistical leaders for both teams. Stats accumulate per completed drive
/// (mirroring the quick sim), so the current drive is not yet included.
private struct LiveBoxScoreSheet: View {

    @ObservedObject var engine: LiveGameEngine
    let homeTeam: Team
    let awayTeam: Team

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 14) {
                    lineScoreCard
                    totalsCard
                    leadersCard
                }
                .padding(16)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(Color.backgroundTertiary, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(14)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Line score

    private var lineScoreCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("LINE SCORE", icon: "chart.bar.fill")

            Grid(horizontalSpacing: 0, verticalSpacing: 8) {
                GridRow {
                    Text("")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(quarterLabels, id: \.self) { label in
                        Text(label)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.textTertiary)
                            .frame(width: 36)
                    }
                    Text("T")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: 40)
                }
                lineScoreRow(
                    abbr: awayTeam.abbreviation,
                    quarters: engine.awayQuarterScores,
                    total: engine.awayScore,
                    isPlayer: !engine.playerTeamIsHome
                )
                lineScoreRow(
                    abbr: homeTeam.abbreviation,
                    quarters: engine.homeQuarterScores,
                    total: engine.homeScore,
                    isPlayer: engine.playerTeamIsHome
                )
            }
        }
        .padding(16)
        .cardBackground()
    }

    /// Q1–Q4 plus OT once overtime has begun.
    private var quarterLabels: [String] {
        var labels = ["1", "2", "3", "4"]
        if engine.homeQuarterScores.count > 4 { labels.append("OT") }
        return labels
    }

    private func lineScoreRow(abbr: String, quarters: [Int], total: Int, isPlayer: Bool) -> some View {
        GridRow {
            Text(abbr)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(isPlayer ? Color.accentGold : Color.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(quarterLabels.indices, id: \.self) { index in
                // Quarters not yet reached show a dash instead of a zero.
                let reached = index < engine.quarter
                Text(reached ? "\(quarters.indices.contains(index) ? quarters[index] : 0)" : "–")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(reached ? Color.textPrimary : Color.textTertiary)
                    .frame(width: 36)
            }
            Text("\(total)")
                .font(.system(size: 14, weight: .black).monospacedDigit())
                .foregroundStyle(isPlayer ? Color.accentGold : Color.textPrimary)
                .frame(width: 40)
        }
    }

    // MARK: Team totals

    private var totalsCard: some View {
        let awayYards = engine.totalYards(forHome: false)
        let homeYards = engine.totalYards(forHome: true)
        return VStack(alignment: .leading, spacing: 12) {
            sectionTitle("TEAM STATS", icon: "scalemass.fill")
            StatComparisonRow(
                label: "Total Yards",
                awayValue: "\(awayYards)",
                homeValue: "\(homeYards)",
                awayRaw: Double(awayYards),
                homeRaw: Double(homeYards)
            )
        }
        .padding(16)
        .cardBackground()
    }

    // MARK: Leaders

    private var leadersCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("LEADERS", icon: "star.fill")

            leadersRow("Passing", away: engine.passingLeader(forHome: false),
                       home: engine.passingLeader(forHome: true))
            leadersRow("Rushing", away: engine.rushingLeader(forHome: false),
                       home: engine.rushingLeader(forHome: true))
            leadersRow("Receiving", away: engine.receivingLeader(forHome: false),
                       home: engine.receivingLeader(forHome: true))
            leadersRow("Sacks", away: engine.sackLeader(forHome: false),
                       home: engine.sackLeader(forHome: true))
        }
        .padding(16)
        .cardBackground()
    }

    private func leadersRow(
        _ category: String,
        away: LiveGameEngine.StatLeader?,
        home: LiveGameEngine.StatLeader?
    ) -> some View {
        VStack(spacing: 6) {
            Text(category.uppercased())
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(Color.textTertiary)
                .tracking(1.4)
                .frame(maxWidth: .infinity, alignment: .center)
            HStack(alignment: .top, spacing: 12) {
                leaderCell(away, alignment: .leading)
                leaderCell(home, alignment: .trailing)
            }
        }
        .padding(.vertical, 4)
    }

    private func leaderCell(_ leader: LiveGameEngine.StatLeader?, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(leader?.name ?? "—")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(leader == nil ? Color.textTertiary : Color.textPrimary)
                .lineLimit(1)
            if let leader {
                Text(leader.detail)
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }

    // MARK: Bits

    private func sectionTitle(_ text: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.accentGold)
            Text(text)
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(Color.textTertiary)
                .tracking(1.5)
        }
    }
}
