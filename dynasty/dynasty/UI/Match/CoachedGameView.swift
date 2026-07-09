import SwiftUI
import SceneKit

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
    @State private var isAnimating = false
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

    // Offense call state
    @State private var selectedCategory: String = "Run"
    @State private var selectedCall: OffensivePlayCall? = nil
    @State private var wentForIt = false
    /// AI suggestion cached per situation — the underlying hint rolls dice,
    /// so recomputing it on every body render would make the brain icon jump.
    @State private var cachedSuggestion: OffensivePlayCall? = nil

    // Defense call state
    @State private var defCall: DefensiveCall = .cover3Base

    // Dialogs
    @State private var showSimToEndConfirm = false
    @State private var showExitConfirm = false
    @State private var showOnsideDialog = false
    @State private var showFinal = false
    @State private var showStatsSheet = false
    /// Halftime report overlay (raised by the engine's `halftimePending`).
    @State private var showHalftime = false

    // Two-minute drill presentation
    /// Quarters (2 and/or 4) whose two-minute warning chip already fired.
    @State private var twoMinuteWarnedQuarters: Set<Int> = []
    /// Transient "2-MINUTE WARNING" chip in the situation strip.
    @State private var showTwoMinuteChip = false

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

            bannerOverlay

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
        .confirmationDialog(
            "Onside kick?",
            isPresented: $showOnsideDialog,
            titleVisibility: .visible
        ) {
            Button("Onside Kick") { attemptOnside() }
            // Cancel role: tapping outside the dialog also kicks deep, so the
            // game never stalls waiting for a choice.
            Button("Kick Deep", role: .cancel) { kickDeep() }
        } message: {
            Text("Trailing in the 4th — try to steal the ball back (~12%)? A failed onside hands them a short field.")
        }
        .sheet(isPresented: $showStatsSheet) {
            LiveBoxScoreSheet(engine: engine, homeTeam: homeTeam, awayTeam: awayTeam)
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
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.textTertiary)
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
            .font(.system(size: 24, weight: .heavy).monospacedDigit())
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
            Spacer()
            if !engine.isGameOver && engine.playerTimeoutsRemaining > 0 {
                Button {
                    callTimeout()
                } label: {
                    Label("TO · \(engine.playerTimeoutsRemaining)", systemImage: "hand.raised.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentGold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.accentGold.opacity(0.14), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isAnimating)
            }
            Button {
                showStatsSheet = true
            } label: {
                Label("Stats", systemImage: "chart.bar.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.backgroundTertiary, in: Capsule())
            }
            .buttonStyle(.plain)
            if !engine.isGameOver {
                Button {
                    showSimToEndConfirm = true
                } label: {
                    Label("Sim to End", systemImage: "forward.end.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.backgroundTertiary, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isAnimating)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.backgroundSecondary)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.surfaceBorder), alignment: .bottom)
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
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
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
        SceneKitFieldView(scene: fieldScene)
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
                    .padding(10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
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
            .animation(.spring(duration: 0.3), value: possessionBanner)
            .animation(.spring(duration: 0.3), value: playoffBanner)
            .animation(.spring(duration: 0.3), value: matchupCallouts.count)
            .animation(.spring(duration: 0.25), value: snapPlate)
            .animation(.spring(duration: 0.3), value: sidelineNote)
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

    private var miniPlayFeed: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(engine.playLog.suffix(2).enumerated()), id: \.offset) { _, play in
                HStack(spacing: 8) {
                    Circle()
                        .fill(feedDotColor(play))
                        .frame(width: 6, height: 6)
                    Text(play.description)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                    Spacer()
                }
            }
            if engine.playLog.isEmpty {
                Text("Kickoff — the game is about to start.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(height: 56, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.backgroundPrimary)
    }

    private func feedDotColor(_ play: PlayResult) -> Color {
        if play.scoringPlay { return .accentGold }
        if play.isTurnover { return .danger }
        if play.isFirstDown { return .success }
        return .textTertiary
    }

    // MARK: - Call Panel

    @ViewBuilder
    private var callPanel: some View {
        VStack(spacing: 0) {
            Divider().background(Color.surfaceBorder)
            if engine.isGameOver {
                Spacer()
            } else if !engine.playerIsOnOffense {
                // Opponent possession: stance stays adjustable while plays
                // roll automatically, so no dead spinner panel.
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
                if clockManagementAvailable {
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
                    prominent: engine.yardLine < 55
                ) {
                    snap(forcedType: .punt)
                }

                if engine.canAttemptFieldGoal {
                    fourthDownButton(
                        title: "Field Goal",
                        subtitle: "\(engine.fieldGoalDistance) yd attempt",
                        icon: "flag.fill",
                        prominent: true
                    ) {
                        snap(forcedType: .fieldGoal)
                    }
                }

                fourthDownButton(
                    title: "Go For It",
                    subtitle: "Keep the drive alive",
                    icon: "flame.fill",
                    prominent: false
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) { wentForIt = true }
                }
            }
            .padding(.horizontal, 14)

            Spacer(minLength: 0)
        }
    }

    private func fourthDownButton(
        title: String,
        subtitle: String,
        icon: String,
        prominent: Bool,
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
            .foregroundStyle(prominent ? Color.backgroundPrimary : Color.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                prominent ? Color.accentGold : Color.backgroundTertiary,
                in: RoundedRectangle(cornerRadius: 12)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Defense panel

    private var defensePanel: some View {
        VStack(spacing: 10) {
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
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
                    ForEach(DefensiveCall.allCases) { call in
                        defenseCallCard(call)
                    }
                }
                .padding(.horizontal, 14)

                Text("\(opponentAbbr) has the ball — plays run automatically with your call applied.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
            }

            Spacer(minLength: 0)
        }
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
            withAnimation(.easeInOut(duration: 0.15)) { defCall = call }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                DefenseDiagramView(coverage: call.package.coverage, blitz: call.package.blitz)
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

    private var bannerOverlay: some View {
        VStack {
            Spacer()
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
            .padding(.bottom, 352)
        }
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

    // MARK: - Game Flow

    private func startGame() {
        guard !gameStarted else { return }
        gameStarted = true

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
            home: .home(teamColor: colors.home),
            away: .away(teamColor: colors.away)
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
            fieldScene.focusCamera(
                z: PlayChoreographer.kickoffSpotZ(kickingTeamIsHome: kickoff.kickingTeamIsHome),
                animated: false
            )
        } else {
            let losZ = PlayChoreographer.losZ(yardLine: engine.yardLine, offenseIsHome: engine.homeHasPossession)
            let formation = PlayChoreographer.formation(
                for: .run, losZ: losZ, direction: engine.homeHasPossession ? 1 : -1,
                offenseNumbers: engine.currentOffenseUnit.numbers,
                defenseNumbers: engine.currentDefenseUnit.numbers
            )
            let openingCrouch = PlayChoreographer.stanceCrouchIndices(offenseIsHome: engine.homeHasPossession)
            fieldScene.movePlayersToFormation(home: formation.home, away: formation.away, duration: 0.1,
                                              crouchHome: openingCrouch.home, crouchAway: openingCrouch.away)
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
        // A drive that begins with a kickoff plays the boot first. When the
        // situation calls for it, the coach gets the onside choice instead.
        if let kickoff = engine.pendingKickoff {
            if engine.onsideKickAvailable {
                showOnsideDialog = true
                return
            }
            engine.clearPendingKickoff()
            runKickoff(kickoff)
            return
        }
        if engine.playerIsOnOffense {
            // Line the teams up at the new scrimmage spot while the user
            // considers the call, and pre-select the AI pick.
            syncFieldToSituation()
            cachedSuggestion = aiSuggestion
            selectedCall = cachedSuggestion
            if let suggestion = selectedCall { selectedCategory = suggestion.category }
            wentForIt = false
        } else {
            // Opponent possession: auto-run the next play with the user's stance.
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard !isAnimating, !engine.isGameOver, !engine.playerIsOnOffense else { return }
                runPlay(offCall: nil, forcedType: nil)
            }
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
        isAnimating = true
        let formation = PlayChoreographer.kickoffFormation(kickingTeamIsHome: event.kickingTeamIsHome)
        fieldScene.movePlayersToFormation(home: formation.home, away: formation.away, duration: 0.7)
        fieldScene.updateMarkers(losZ: nil, firstDownZ: nil)
        fieldScene.focusCamera(z: PlayChoreographer.kickoffSpotZ(kickingTeamIsHome: event.kickingTeamIsHome))

        let steps = PlayChoreographer.kickoffSteps(
            kickingTeamIsHome: event.kickingTeamIsHome,
            returnYardLine: event.startYardLine,
            isTouchback: event.isTouchback,
            isReturnTouchdown: event.isReturnTouchdown
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            fieldScene.runPlay(steps: steps) {
                isAnimating = false
                if event.isReturnTouchdown {
                    // Housed: camera to the end zone the returner reached.
                    let endzoneZ: Float = event.kickingTeamIsHome ? -50 : 50
                    fieldScene.focusCamera(z: endzoneZ, duration: 1.0)
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

    /// Steps the engine one play and choreographs the result on the field.
    private func runPlay(offCall: OffensivePlayCall?, forcedType: PlayType?) {
        guard !isAnimating, !engine.isGameOver else { return }

        let losYard = engine.yardLine
        let distanceBefore = engine.distance
        let offenseIsHome = engine.homeHasPossession
        let possessionBefore = engine.homeHasPossession

        // Retro broadcast plate for the snap — situation plus the called play
        // when the coach dialed one ("2ND & 10 · DIG").
        let plateText = offCall.map { "\(downDistanceText) · \($0.rawValue.uppercased())" }
            ?? downDistanceText
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

        let play = engine.step(
            offensiveCall: engine.playerIsOnOffense ? offCall : nil,
            forcedPlayType: forcedType,
            defensivePackage: defPackage
        )

        isAnimating = true
        selectedCall = nil

        let matchups = engine.lastMatchups

        // Pre-snap: shift both teams into the alignment their calls dictate,
        // then run the play from that same look.
        let formation = PlayChoreographer.preSnapStep(
            for: play, losYardLine: losYard, offenseIsHome: offenseIsHome,
            call: offCall, defensivePackage: defPackage,
            offenseNumbers: offUnit.numbers, defenseNumbers: defUnit.numbers
        )
        let presnapCrouch = PlayChoreographer.stanceCrouchIndices(offenseIsHome: offenseIsHome)
        fieldScene.movePlayersToFormation(home: formation.home, away: formation.away, duration: 0.7,
                                          crouchHome: presnapCrouch.home, crouchAway: presnapCrouch.away)

        // Markers stay on THIS play's line/1st-down through the animation.
        let playLosZ = PlayChoreographer.losZ(yardLine: losYard, offenseIsHome: offenseIsHome)
        let playDir: Float = offenseIsHome ? 1 : -1

        // Kicks get the broadcast angle from low behind the posts; every
        // other play keeps the normal scrimmage framing.
        if play.playType == .fieldGoal || play.playType == .extraPoint {
            fieldScene.kickCamera(towardZ: playDir)
        } else {
            fieldScene.focusCamera(z: playLosZ)
        }
        let playGoalToGo = 100 - losYard <= distanceBefore
        fieldScene.updateMarkers(
            losZ: playLosZ,
            firstDownZ: playGoalToGo ? nil : playLosZ + playDir * Float(distanceBefore)
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            let steps = PlayChoreographer.steps(for: play, losYardLine: losYard,
                                                offenseIsHome: offenseIsHome, matchups: matchups,
                                                call: offCall, defensivePackage: defPackage)
            // A flagged play gets the yellow laundry: the flag flies in while
            // the (wiped-out) snap plays out.
            if play.outcome == .penalty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    fieldScene.throwFlag(atZ: playLosZ)
                }
            }
            fieldScene.runPlay(steps: steps) {
                finishPlay(play, possessionBefore: possessionBefore)
            }
        }
    }

    private func finishPlay(_ play: PlayResult, possessionBefore: Bool) {
        isAnimating = false

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

        if hadInjury {
            // Hold the shot on the downed player for a beat — the next
            // formation move (inside proceed) brings the replacement on.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) {
                guard !isAnimating else { return }
                proceed(after: 0.9)
            }
        } else {
            proceed(after: play.scoringPlay ? 1.6 : 0.9)
        }
    }

    /// Runs the rest of the opponent's drive instantly (no animation).
    /// Works mid-animation too — the current play's outcome is already
    /// decided, so cancelling the visuals loses nothing.
    private func skipDrive() {
        guard !engine.isGameOver, !engine.playerIsOnOffense else { return }
        fieldScene.cancelPlay()
        isAnimating = false
        var safety = 0
        // Stop at the break too — the halftime report must not be skipped
        // past when the opponent's drive ends the half.
        while !engine.playerIsOnOffense && !engine.isGameOver
                && !engine.halftimePending && safety < 40 {
            engine.step(defensivePackage: defCall.package)
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
        let crouch = PlayChoreographer.stanceCrouchIndices(offenseIsHome: engine.homeHasPossession)
        fieldScene.movePlayersToFormation(home: formation.home, away: formation.away, duration: 0.3,
                                          crouchHome: crouch.home, crouchAway: crouch.away)
        fieldScene.focusCamera(z: losZ)
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
        fieldScene.updateMarkers(losZ: losZ, firstDownZ: firstDownZ)
    }

    /// Live pre-snap preview: browsing the call sheet realigns the offense on
    /// the field (I-form for inside runs, spread for deep shots), and changing
    /// the defensive call re-shows the shell/blitz look.
    private func previewFormation() {
        guard gameStarted, !isAnimating, !engine.isGameOver else { return }
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
