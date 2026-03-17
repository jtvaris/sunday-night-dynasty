import SwiftUI
import SceneKit

// MARK: - MatchView

/// Live game replay view that steps through a pre-simulated ``GameSimulator.GameResult``
/// play-by-play, updating the scoreboard and play feed as each play is revealed.
///
/// The 3D field (``SceneKitFieldView``) is displayed but full play animation will be
/// wired in a later pass once ``FootballFieldScene`` integration is complete.
struct MatchView: View {

    // MARK: Input

    let homeTeam: Team
    let awayTeam: Team
    /// Which team the player coaches.  Determines which side of the ball the
    /// play-call UI is presented for in `callOffense` / `callDefense` modes.
    let playerTeamIsHome: Bool
    let gameResult: GameSimulator.GameResult

    // MARK: Private Derived Data

    /// Flat array of every play in the game, in drive order.
    private var allPlays: [PlayResult] {
        gameResult.boxScore.drives.flatMap { $0.plays }
    }

    // MARK: Scene

    /// Lazily created once; FootballFieldScene sets itself up in its own init.
    @State private var fieldScene: FootballFieldScene = FootballFieldScene()

    // MARK: Playback State

    @State private var currentPlayIndex: Int = 0
    @State private var homeScore: Int = 0
    @State private var awayScore: Int = 0
    @State private var quarter: Int = 1
    @State private var timeRemaining: Int = 900
    @State private var isPlaying: Bool = false
    @State private var gameSpeed: Double = 1.0
    @State private var playLog: [PlayResult] = []
    @State private var isGameOver: Bool = false

    // MARK: Control Mode

    /// Determines whether the player calls plays or lets the engine auto-simulate.
    @State private var controlMode: MatchControlMode = .autoSimulate

    // MARK: Manual Play-Calling State

    /// Set to `true` when the game is paused waiting for the player to call the
    /// next offensive play.
    @State private var awaitingOffensiveCall: Bool = false
    /// Set to `true` when the game is paused waiting for the player to call the
    /// next defensive alignment.
    @State private var awaitingDefensiveCall: Bool = false

    /// The offensive call the player has confirmed for the current play.
    @State private var pendingOffensiveCall: OffensivePlayCall? = nil
    /// The defensive package the player has confirmed for the current play.
    @State private var pendingDefensiveCall: DefensivePackage? = nil

    /// Log of every play call the player made this game, for review purposes.
    @State private var callHistory: [(play: PlayResult, offCall: OffensivePlayCall?, defCall: DefensivePackage?)] = []

    /// Result banner shown briefly after each manually-called play resolves.
    @State private var latestResultBanner: String? = nil

    // MARK: Scroll Proxy ID

    private let feedBottomID = "feedBottom"

    // MARK: Timers / Tasks

    @State private var playbackTask: Task<Void, Never>? = nil

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            GeometryReader { geo in
                VStack(spacing: 0) {
                    scoreboardBar
                    controlModeBar          // play-calling mode toggle
                    fieldSection(height: geo.size.height * 0.50)
                    bottomPanel
                }
            }

            // Result banner — briefly visible after a manually-called play lands
            if let banner = latestResultBanner {
                VStack {
                    Spacer()
                    Text(banner)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.backgroundTertiary, in: Capsule())
                        .padding(.bottom, 100)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .animation(.spring(duration: 0.35), value: latestResultBanner)
            }
        }
        .onAppear {
            fieldScene.setupField()
        }
        .onDisappear {
            playbackTask?.cancel()
        }
        // ---- Play-call sheets ----
        .sheet(isPresented: $awaitingDefensiveCall) {
            PlayCallView(
                side: .defense,
                situation: currentSituation,
                aiOffensiveSuggestion: nil,
                aiDefensiveSuggestion: aiDefensiveSuggestion,
                onDefensiveCall: { pkg in
                    pendingDefensiveCall = pkg
                    awaitingDefensiveCall = false
                    // If we also need an offensive call, present that next
                    if controlMode.playerCallsOffense && isPlayerTeamOnOffense {
                        awaitingOffensiveCall = true
                    }
                    // Otherwise resume playback (offensive call goes straight to engine)
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $awaitingOffensiveCall) {
            PlayCallView(
                side: .offense,
                situation: currentSituation,
                aiOffensiveSuggestion: aiOffensiveSuggestion,
                aiDefensiveSuggestion: nil,
                onOffensiveCall: { call in
                    pendingOffensiveCall = call
                    awaitingOffensiveCall = false
                    // All calls are now in; signal the playback task to continue
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Scoreboard Bar

    private var scoreboardBar: some View {
        HStack(spacing: 0) {
            // Away team
            teamScoreBlock(
                abbreviation: awayTeam.abbreviation,
                score: awayScore,
                alignment: .leading
            )

            Spacer()

            // Quarter / Clock
            VStack(spacing: 2) {
                Text(quarterLabel)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.textTertiary)
                Text(formattedClock)
                    .font(.system(size: 20, weight: .heavy).monospacedDigit())
                    .foregroundStyle(Color.textPrimary)
            }

            Spacer()

            // Home team
            teamScoreBlock(
                abbreviation: homeTeam.abbreviation,
                score: homeScore,
                alignment: .trailing
            )
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(Color.backgroundSecondary)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color.surfaceBorder),
            alignment: .bottom
        )
    }

    private func teamScoreBlock(
        abbreviation: String,
        score: Int,
        alignment: HorizontalAlignment
    ) -> some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(abbreviation)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.textSecondary)
            Text("\(score)")
                .font(.system(size: 34, weight: .black).monospacedDigit())
                .foregroundStyle(Color.textPrimary)
                .contentTransition(.numericText())
                .animation(.spring(duration: 0.3), value: score)
        }
        .frame(minWidth: 70, alignment: alignment == .leading ? .leading : .trailing)
    }

    // MARK: - Control Mode Bar

    /// Horizontal strip beneath the scoreboard that lets the player switch
    /// between auto-simulate and the various play-calling modes at any time,
    /// even mid-game.
    private var controlModeBar: some View {
        HStack(spacing: 0) {
            ForEach(MatchControlMode.allCases, id: \.self) { mode in
                controlModeButton(mode)
            }
        }
        .background(Color.backgroundSecondary)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color.surfaceBorder),
            alignment: .bottom
        )
    }

    private func controlModeButton(_ mode: MatchControlMode) -> some View {
        let isSelected = controlMode == mode
        return Button {
            guard controlMode != mode else { return }
            // Switching away from auto-simulate pauses ongoing playback
            if controlMode == .autoSimulate && mode != .autoSimulate {
                pausePlayback()
            }
            // Switching back to auto resumes
            if mode == .autoSimulate {
                controlMode = mode
                if !isGameOver { startPlayback() }
            } else {
                controlMode = mode
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: mode.icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(mode.label)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(isSelected ? Color.backgroundPrimary : Color.textSecondary)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(isSelected ? Color.accentGold : Color.clear)
            .animation(.easeInOut(duration: 0.15), value: isSelected)
        }
        .buttonStyle(.plain)
        .disabled(isGameOver)
    }

    // MARK: - 3D Field

    private func fieldSection(height: CGFloat) -> some View {
        SceneKitFieldView(scene: fieldScene)
            .frame(height: height)
            .overlay(alignment: .topTrailing) {
                if isGameOver {
                    finalBadge
                        .padding(12)
                }
            }
    }

    private var finalBadge: some View {
        Text("FINAL")
            .font(.system(size: 11, weight: .black))
            .foregroundStyle(Color.backgroundPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.accentGold, in: Capsule())
    }

    // MARK: - Bottom Panel

    private var bottomPanel: some View {
        VStack(spacing: 0) {
            // Current situation bar
            situationBar

            Divider().background(Color.surfaceBorder)

            // Play-by-play feed
            playFeed

            Divider().background(Color.surfaceBorder)

            // Controls
            controlBar
        }
        .background(Color.backgroundSecondary)
    }

    // MARK: Situation Bar

    private var situationBar: some View {
        HStack(spacing: 16) {
            if let latest = playLog.last {
                // Down & distance
                Text(downDistanceText(for: latest))
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.accentGold)

                // Separator dot
                Circle()
                    .fill(Color.textTertiary)
                    .frame(width: 4, height: 4)

                // Yard line
                Text(yardLineText(for: latest))
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textSecondary)
            } else {
                Text("Kickoff")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
            }

            Spacer()

            // Play counter
            Text("\(currentPlayIndex) / \(allPlays.count) plays")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(Color.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: Play Feed

    private var playFeed: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(playLog.enumerated()), id: \.offset) { idx, play in
                        PlayFeedRow(play: play, isLatest: idx == playLog.count - 1)

                        if idx < playLog.count - 1 {
                            Divider()
                                .background(Color.surfaceBorder)
                                .padding(.leading, 48)
                        }
                    }

                    // Invisible anchor at the bottom for auto-scrolling
                    Color.clear
                        .frame(height: 1)
                        .id(feedBottomID)
                }
                .padding(.vertical, 4)
            }
            .frame(maxWidth: .infinity)
            .onChange(of: playLog.count) { _, _ in
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo(feedBottomID, anchor: .bottom)
                }
            }
        }
    }

    // MARK: Control Bar

    private var controlBar: some View {
        HStack(spacing: 12) {
            // Play / Pause
            Button {
                togglePlayback()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(Color.backgroundTertiary, in: Circle())
            }
            .disabled(isGameOver || awaitingOffensiveCall || awaitingDefensiveCall)

            Divider()
                .frame(height: 28)
                .background(Color.surfaceBorder)

            if controlMode == .autoSimulate {
                // Speed controls — only relevant in auto-simulate mode
                HStack(spacing: 6) {
                    ForEach([1.0, 2.0, 4.0], id: \.self) { speed in
                        speedButton(speed: speed)
                    }
                }
            } else {
                // Manual mode status label
                if awaitingOffensiveCall || awaitingDefensiveCall {
                    Label("Waiting for call…", systemImage: "hand.tap")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.accentGold)
                } else {
                    Label("Play-calling on", systemImage: "person.fill.checkmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                }
            }

            Spacer()

            // Skip to end (auto-simulate only; skipping would bypass play calls)
            if !isGameOver && controlMode == .autoSimulate {
                Button {
                    skipToEnd()
                } label: {
                    Label("Skip", systemImage: "forward.end.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: 8))
                }
            }

            // Call history badge
            if !callHistory.isEmpty {
                Text("\(callHistory.count) calls")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func speedButton(speed: Double) -> some View {
        let isSelected = gameSpeed == speed
        return Button {
            gameSpeed = speed
            // If currently playing, restart the task at new speed
            if isPlaying {
                restartPlayback()
            }
        } label: {
            Text(speedLabel(for: speed))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isSelected ? Color.backgroundPrimary : Color.textSecondary)
                .frame(width: 36, height: 28)
                .background(
                    isSelected ? Color.accentGold : Color.backgroundTertiary,
                    in: RoundedRectangle(cornerRadius: 6)
                )
        }
        .animation(.easeInOut(duration: 0.15), value: gameSpeed)
    }

    // MARK: - Playback Logic

    private func togglePlayback() {
        if isPlaying {
            pausePlayback()
        } else {
            startPlayback()
        }
    }

    private func startPlayback() {
        guard !isGameOver else { return }
        isPlaying = true
        playbackTask = Task {
            await advancePlays()
        }
    }

    private func pausePlayback() {
        isPlaying = false
        playbackTask?.cancel()
        playbackTask = nil
    }

    private func restartPlayback() {
        playbackTask?.cancel()
        playbackTask = Task {
            await advancePlays()
        }
    }

    /// Advances through remaining plays one at a time, sleeping between each.
    ///
    /// In auto-simulate mode this behaves identically to the original
    /// implementation.  In a manual mode the loop pauses before each play,
    /// waits for the player to confirm their call(s) via the sheet UI, then
    /// records the call alongside the pre-simulated `PlayResult` and continues.
    ///
    /// Because the underlying game is fully pre-simulated, the play call does
    /// not change the actual `PlayResult` stored in `gameResult`; instead it is
    /// logged in `callHistory` and the simulator hint is available for future
    /// live simulation integration.  Visual feedback is provided through
    /// `latestResultBanner`.
    private func advancePlays() async {
        let plays = allPlays

        while currentPlayIndex < plays.count {
            guard !Task.isCancelled else { return }

            let play = plays[currentPlayIndex]

            // ---- Manual play-calling pause ----
            if controlMode != .autoSimulate {
                // Determine whether this play is on the player's offense/defense
                let playerOnOffense = isPlayerTeamOnOffense(for: play)
                let needsOffCall = controlMode.playerCallsOffense && playerOnOffense
                let needsDefCall = controlMode.playerCallsDefense && !playerOnOffense

                if needsOffCall || needsDefCall {
                    // Reset pending calls
                    await MainActor.run {
                        pendingOffensiveCall = nil
                        pendingDefensiveCall = nil
                    }

                    // Present defensive sheet first (so player knows coverage they're
                    // running before committing to an offensive call)
                    if needsDefCall {
                        await MainActor.run { awaitingDefensiveCall = true }
                        // Wait until the defensive sheet is dismissed
                        while await MainActor.run(resultType: Bool.self, body: { awaitingDefensiveCall }) {
                            guard !Task.isCancelled else { return }
                            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 s poll
                        }
                    }

                    // Present offensive sheet
                    if needsOffCall && !needsDefCall {
                        // Defense is not player-controlled; show offense sheet directly
                        await MainActor.run { awaitingOffensiveCall = true }
                    }
                    // If both sides are player-controlled, the defensive sheet's
                    // completion handler already sets awaitingOffensiveCall = true.

                    // Wait until the offensive sheet is dismissed (if it was opened)
                    if needsOffCall {
                        while await MainActor.run(resultType: Bool.self, body: { awaitingOffensiveCall }) {
                            guard !Task.isCancelled else { return }
                            try? await Task.sleep(nanoseconds: 100_000_000)
                        }
                    }

                    guard !Task.isCancelled else { return }

                    // Record the call in history
                    let capturedOff = await MainActor.run(resultType: OffensivePlayCall?.self) { pendingOffensiveCall }
                    let capturedDef = await MainActor.run(resultType: DefensivePackage?.self)  { pendingDefensiveCall }

                    await MainActor.run {
                        callHistory.append((play: play, offCall: capturedOff, defCall: capturedDef))
                    }
                }
            }

            guard !Task.isCancelled else { return }

            await MainActor.run {
                applyPlay(play)
                showResultBanner(for: play)
            }

            // Determine per-play delay: base is 2 seconds; scoring plays linger.
            // In manual mode, stay on the result a beat longer so the player can
            // read the outcome before the next call sheet appears.
            let baseDelay: Double = play.scoringPlay ? 3.0 : (controlMode == .autoSimulate ? 2.0 : 2.5)
            let delay = baseDelay / (controlMode == .autoSimulate ? gameSpeed : 1.0)
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }

        await MainActor.run {
            finalizeGame()
        }
    }

    /// Applies a single play to the live state.
    private func applyPlay(_ play: PlayResult) {
        currentPlayIndex += 1
        quarter = play.quarter
        timeRemaining = play.timeRemaining
        playLog.append(play)

        // Update score on scoring plays
        if play.scoringPlay && play.pointsScored > 0 {
            // Determine which team scored from the drive that owns this play
            if let drive = driveForPlay(play) {
                if drive.teamID == homeTeam.id {
                    homeScore += play.pointsScored
                } else {
                    awayScore += play.pointsScored
                }
            }
        }
    }

    /// Jumps directly to the final state.
    private func skipToEnd() {
        pausePlayback()
        let plays = allPlays
        for play in plays[currentPlayIndex...] {
            applyPlay(play)
        }
        finalizeGame()
    }

    private func finalizeGame() {
        isPlaying = false
        isGameOver = true
        // Sync to definitive final scores from GameResult
        homeScore = gameResult.homeScore
        awayScore = gameResult.awayScore
    }

    // MARK: - Manual Mode Helpers

    /// Returns `true` when the player's team is on offense for the given play.
    /// Falls back to checking the current live `quarter` and `timeRemaining`
    /// when no specific play is provided.
    private func isPlayerTeamOnOffense(for play: PlayResult? = nil) -> Bool {
        guard let play = play else { return isPlayerTeamOnOffense }
        // The drive that owns this play tells us which team had possession
        guard let drive = driveForPlay(play) else { return false }
        return playerTeamIsHome ? drive.teamID == homeTeam.id : drive.teamID == awayTeam.id
    }

    /// Convenience computed property for the current play (used in sheet bindings).
    private var isPlayerTeamOnOffense: Bool {
        guard let latest = playLog.last else { return playerTeamIsHome }
        return isPlayerTeamOnOffense(for: latest)
    }

    /// Build a `PlayCallView.GameSituation` from current live state.
    private var currentSituation: PlayCallView.GameSituation {
        let latest = playLog.last
        return PlayCallView.GameSituation(
            down: latest?.down ?? 1,
            distance: latest?.distance ?? 10,
            yardLine: latest?.yardLine ?? 25,
            quarter: quarter,
            timeRemaining: timeRemaining,
            homeScore: homeScore,
            awayScore: awayScore,
            homeAbbreviation: homeTeam.abbreviation,
            awayAbbreviation: awayTeam.abbreviation,
            playerTeamIsHome: playerTeamIsHome
        )
    }

    /// Simple AI suggestion: delegate to `PlaySimulator.decidePlayCall` and map
    /// the result to the nearest `OffensivePlayCall`.
    private var aiOffensiveSuggestion: OffensivePlayCall? {
        guard let latest = playLog.last else { return .slant }
        let aiType = PlaySimulator.decidePlayCall(
            down: latest.down,
            distance: latest.distance,
            yardLine: latest.yardLine,
            quarter: quarter,
            timeRemaining: timeRemaining
        )
        switch aiType {
        case .run:       return latest.distance <= 2 ? .qbSneak : (latest.distance <= 5 ? .insideRun : .outsideRun)
        case .pass:
            if latest.distance <= 4  { return .slant }
            if latest.distance <= 8  { return .curl }
            return .dig
        case .kneel:     return .kneel
        case .spike:     return .spike
        default:         return nil
        }
    }

    /// Simple AI defensive suggestion based on down/distance.
    private var aiDefensiveSuggestion: DefensivePackage {
        guard let latest = playLog.last else { return .standard }
        let isShortYardage  = latest.distance <= 3
        let isLongDistance  = latest.distance >= 8
        let isRedZone       = latest.yardLine >= 80

        if isRedZone {
            return DefensivePackage(coverage: .manToMan, blitz: .noBlitz, front: .goalLine)
        }
        if isShortYardage {
            return DefensivePackage(coverage: .cover3, blitz: .noBlitz, front: .base)
        }
        if isLongDistance {
            return DefensivePackage(coverage: .cover4, blitz: .dbBlitz, front: .nickel)
        }
        return .standard
    }

    /// Briefly show a result banner after a manually-called play resolves.
    private func showResultBanner(for play: PlayResult) {
        guard controlMode != .autoSimulate else { return }
        withAnimation {
            latestResultBanner = play.description
        }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000) // 2.5 s
            await MainActor.run {
                withAnimation { latestResultBanner = nil }
            }
        }
    }

    // MARK: - Helpers

    /// Finds the DriveResult that contains the given play by matching quarter,
    /// time remaining, and play number.
    private func driveForPlay(_ play: PlayResult) -> DriveResult? {
        gameResult.boxScore.drives.first { drive in
            drive.plays.contains { $0.playNumber == play.playNumber && $0.quarter == play.quarter }
        }
    }

    private var quarterLabel: String {
        quarter <= 4 ? "Q\(quarter)" : "OT"
    }

    private var formattedClock: String {
        let m = timeRemaining / 60
        let s = timeRemaining % 60
        return String(format: "%d:%02d", m, s)
    }

    private func downDistanceText(for play: PlayResult) -> String {
        "\(ordinal(play.down)) & \(play.distance)"
    }

    private func yardLineText(for play: PlayResult) -> String {
        let yl = play.yardLine
        if yl == 50 { return "50 yd line" }
        return yl > 50 ? "OPP \(100 - yl)" : "OWN \(yl)"
    }

    private func speedLabel(for speed: Double) -> String {
        speed == 1.0 ? "1x" : speed == 2.0 ? "2x" : "4x"
    }

    private func ordinal(_ n: Int) -> String {
        switch n {
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        case 4: return "4th"
        default: return "\(n)th"
        }
    }
}

// MARK: - PlayFeedRow

/// A single row in the play-by-play feed.
private struct PlayFeedRow: View {

    let play: PlayResult
    let isLatest: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Quarter pill
            Text(quarterLabel)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(accentColor)
                .frame(width: 26, height: 18)
                .background(accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                // Down & distance header
                Text(downDistanceText)
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.textTertiary)

                // Play description
                Text(play.description)
                    .font(.system(size: 13))
                    .foregroundStyle(isLatest ? Color.textPrimary : Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            // Yards badge
            if play.yardsGained != 0 {
                Text(yardsBadgeText)
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(accentColor.opacity(0.12), in: Capsule())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isLatest ? Color.backgroundTertiary.opacity(0.6) : Color.clear)
        .animation(.easeIn(duration: 0.2), value: isLatest)
    }

    private var quarterLabel: String {
        play.quarter <= 4 ? "Q\(play.quarter)" : "OT"
    }

    private var downDistanceText: String {
        "\(ordinal(play.down)) & \(play.distance) — \(yardLineShort)"
    }

    private var yardLineShort: String {
        let yl = play.yardLine
        if yl == 50 { return "50" }
        return yl > 50 ? "OPP \(100 - yl)" : "OWN \(yl)"
    }

    private var accentColor: Color {
        if play.scoringPlay  { return .accentGold }
        if play.isTurnover   { return .danger     }
        if play.isFirstDown  { return .success    }
        return .textTertiary
    }

    private var yardsBadgeText: String {
        if play.scoringPlay && play.pointsScored > 0 { return "+\(play.pointsScored) pts" }
        let y = play.yardsGained
        return y >= 0 ? "+\(y) yds" : "\(y) yds"
    }

    private func ordinal(_ n: Int) -> String {
        switch n {
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        case 4: return "4th"
        default: return "\(n)th"
        }
    }
}

// MARK: - Preview

#Preview {
    let homeTeam = Team(
        name: "Chiefs", city: "Kansas City", abbreviation: "KC",
        conference: .AFC, division: .west, mediaMarket: .large
    )
    let awayTeam = Team(
        name: "Eagles", city: "Philadelphia", abbreviation: "PHI",
        conference: .NFC, division: .east, mediaMarket: .large
    )

    let plays: [PlayResult] = [
        PlayResult(
            playNumber: 1, quarter: 1, timeRemaining: 840,
            down: 1, distance: 10, yardLine: 25,
            playType: .run, outcome: .rush,
            yardsGained: 6, description: "Pacheco rushes for 6 yards up the middle",
            isFirstDown: false, isTurnover: false, scoringPlay: false, pointsScored: 0
        ),
        PlayResult(
            playNumber: 2, quarter: 1, timeRemaining: 795,
            down: 2, distance: 4, yardLine: 31,
            playType: .pass, outcome: .completion,
            yardsGained: 12, description: "Mahomes hits Kelce on a crossing route for 12 yards and a first down",
            isFirstDown: true, isTurnover: false, scoringPlay: false, pointsScored: 0
        ),
        PlayResult(
            playNumber: 3, quarter: 1, timeRemaining: 710,
            down: 1, distance: 10, yardLine: 43,
            playType: .pass, outcome: .touchdown,
            yardsGained: 57, description: "Mahomes deep to Rice — TOUCHDOWN! 57-yard score!",
            isFirstDown: true, isTurnover: false, scoringPlay: true, pointsScored: 7
        ),
    ]

    let drive = DriveResult(
        driveNumber: 1, teamID: homeTeam.id,
        startingYardLine: 25, plays: plays, result: .touchdown
    )

    let boxScore = BoxScore(
        home: TeamBoxScore(
            teamID: homeTeam.id, score: 7,
            quarterScores: [7, 0, 0, 0],
            totalYards: 75, passingYards: 57, rushingYards: 18,
            firstDowns: 2, thirdDownConversions: 0, thirdDownAttempts: 0,
            turnovers: 0, sacks: 0, penalties: 0, penaltyYards: 0,
            timeOfPossession: 190, drives: 1
        ),
        away: TeamBoxScore(
            teamID: awayTeam.id, score: 0,
            quarterScores: [0, 0, 0, 0],
            totalYards: 0, passingYards: 0, rushingYards: 0,
            firstDowns: 0, thirdDownConversions: 0, thirdDownAttempts: 0,
            turnovers: 0, sacks: 0, penalties: 0, penaltyYards: 0,
            timeOfPossession: 0, drives: 0
        ),
        drives: [drive],
        highlights: [plays[2]]
    )

    let result = GameSimulator.GameResult(
        homeScore: 7,
        awayScore: 0,
        boxScore: boxScore,
        playerStats: [],
        mvp: nil
    )

    MatchView(homeTeam: homeTeam, awayTeam: awayTeam, playerTeamIsHome: true, gameResult: result)
}
