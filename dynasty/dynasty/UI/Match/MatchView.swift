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
                    fieldSection(height: geo.size.height * 0.58)
                    bottomPanel
                }
            }
        }
        .onAppear {
            fieldScene.setupField()
        }
        .onDisappear {
            playbackTask?.cancel()
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
            .disabled(isGameOver)

            Divider()
                .frame(height: 28)
                .background(Color.surfaceBorder)

            // Speed controls
            HStack(spacing: 6) {
                ForEach([1.0, 2.0, 4.0], id: \.self) { speed in
                    speedButton(speed: speed)
                }
            }

            Spacer()

            // Skip to end
            if !isGameOver {
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
    /// The delay scales inversely with ``gameSpeed``.
    private func advancePlays() async {
        let plays = allPlays
        while currentPlayIndex < plays.count {
            guard !Task.isCancelled else { return }

            let play = plays[currentPlayIndex]
            await MainActor.run {
                applyPlay(play)
            }

            // Determine per-play delay: base is 2 seconds; scoring plays linger
            let baseDelay: Double = play.scoringPlay ? 3.0 : 2.0
            let delay = baseDelay / gameSpeed
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

    MatchView(homeTeam: homeTeam, awayTeam: awayTeam, gameResult: result)
}
