import Foundation

// MARK: - Drive Simulator

/// Simulates an entire offensive drive from start to conclusion.
enum DriveSimulator {

    /// Result bundle returned after a drive completes.
    struct DriveSimulationResult {
        let drive: DriveResult
        let endQuarter: Int
        let endTime: Int
        let momentumShift: Double
    }

    // MARK: - Public API

    /// Simulates a full drive and returns the result along with updated game clock state.
    /// - Parameters:
    ///   - offensePlayers: The offensive team's players.
    ///   - defensePlayers: The defensive team's players.
    ///   - startingYardLine: Yards from the offense's own end zone (0-100).
    ///   - driveNumber: Sequential drive number in the game.
    ///   - quarter: Current quarter at the start of the drive.
    ///   - timeRemaining: Seconds remaining in the quarter at drive start.
    ///   - momentum: Current momentum value from -1.0 to 1.0.
    ///   - teamID: The UUID of the offensive team.
    static func simulateDrive(
        offensePlayers: [Player],
        defensePlayers: [Player],
        startingYardLine: Int,
        driveNumber: Int,
        quarter: Int,
        timeRemaining: Int,
        momentum: Double,
        teamID: UUID
    ) -> DriveSimulationResult {
        var plays: [PlayResult] = []
        var currentDown = 1
        var currentDistance = 10
        var currentYardLine = startingYardLine
        var currentQuarter = quarter
        var currentTime = timeRemaining
        var playNumber = 1

        // Cap first-down distance if near endzone
        if 100 - currentYardLine < 10 {
            currentDistance = 100 - currentYardLine
        }

        while true {
            // --- Time Expiration Check ---
            if isHalfOrGameOver(quarter: currentQuarter, time: currentTime) {
                let outcome = driveOutcomeForTimeExpiry(quarter: currentQuarter)
                let driveResult = DriveResult(
                    driveNumber: driveNumber,
                    teamID: teamID,
                    startingYardLine: startingYardLine,
                    plays: plays,
                    result: outcome
                )
                return DriveSimulationResult(
                    drive: driveResult,
                    endQuarter: currentQuarter,
                    endTime: 0,
                    momentumShift: 0.0
                )
            }

            // --- Simulate Play ---
            let result = PlaySimulator.simulatePlay(
                offensePlayers: offensePlayers,
                defensePlayers: defensePlayers,
                down: currentDown,
                distance: currentDistance,
                yardLine: currentYardLine,
                quarter: currentQuarter,
                timeRemaining: currentTime,
                momentum: momentum,
                playNumber: playNumber
            )

            // Store the play with current clock values
            var recordedPlay = result
            recordedPlay.quarter = currentQuarter
            recordedPlay.timeRemaining = currentTime
            plays.append(recordedPlay)

            // --- Consume Clock ---
            let elapsed = clockConsumption(for: result)
            currentTime -= elapsed

            // Handle quarter transition
            if currentTime <= 0 {
                let overflow = abs(currentTime)
                if shouldEndDrive(quarter: currentQuarter) {
                    currentTime = 0
                    // Check if this play ended the drive anyway
                    if let driveEnd = checkImmediateDriveEnd(result, plays: plays, driveNumber: driveNumber, teamID: teamID, startingYardLine: startingYardLine, quarter: currentQuarter, time: currentTime) {
                        return driveEnd
                    }
                    // Time expired at end of half/game
                    let outcome = driveOutcomeForTimeExpiry(quarter: currentQuarter)
                    let driveResult = DriveResult(
                        driveNumber: driveNumber,
                        teamID: teamID,
                        startingYardLine: startingYardLine,
                        plays: plays,
                        result: outcome
                    )
                    return DriveSimulationResult(
                        drive: driveResult,
                        endQuarter: currentQuarter,
                        endTime: 0,
                        momentumShift: 0.0
                    )
                } else {
                    // Quarter transition (Q1->Q2, Q3->Q4) — drive continues
                    currentQuarter += 1
                    currentTime = 900 - overflow
                }
            }

            // --- Check for Immediate Drive-Ending Outcomes ---
            if let driveEnd = checkImmediateDriveEnd(result, plays: plays, driveNumber: driveNumber, teamID: teamID, startingYardLine: startingYardLine, quarter: currentQuarter, time: currentTime) {
                return driveEnd
            }

            // --- Update Down & Distance ---
            let advanceResult = advanceDownAndDistance(
                playResult: result,
                currentDown: currentDown,
                currentDistance: currentDistance,
                currentYardLine: currentYardLine
            )

            currentDown = advanceResult.down
            currentDistance = advanceResult.distance
            currentYardLine = advanceResult.yardLine

            // --- Turnover on Downs ---
            if currentDown > 4 {
                let driveResult = DriveResult(
                    driveNumber: driveNumber,
                    teamID: teamID,
                    startingYardLine: startingYardLine,
                    plays: plays,
                    result: .turnoverOnDowns
                )
                return DriveSimulationResult(
                    drive: driveResult,
                    endQuarter: currentQuarter,
                    endTime: max(currentTime, 0),
                    momentumShift: -0.1
                )
            }

            playNumber += 1

            // Safety valve: prevent infinite drives
            if playNumber > 40 {
                let driveResult = DriveResult(
                    driveNumber: driveNumber,
                    teamID: teamID,
                    startingYardLine: startingYardLine,
                    plays: plays,
                    result: .punt
                )
                return DriveSimulationResult(
                    drive: driveResult,
                    endQuarter: currentQuarter,
                    endTime: max(currentTime, 0),
                    momentumShift: 0.0
                )
            }
        }
    }

    // MARK: - Down & Distance Management

    private struct DownDistanceState {
        let down: Int
        let distance: Int
        let yardLine: Int
    }

    private static func advanceDownAndDistance(
        playResult: PlayResult,
        currentDown: Int,
        currentDistance: Int,
        currentYardLine: Int
    ) -> DownDistanceState {
        let newYardLine = max(1, min(99, currentYardLine + playResult.yardsGained))

        if playResult.isFirstDown {
            let yardsToEndzone = 100 - newYardLine
            return DownDistanceState(
                down: 1,
                distance: min(10, yardsToEndzone),
                yardLine: newYardLine
            )
        }

        let newDistance = max(1, currentDistance - playResult.yardsGained)
        return DownDistanceState(
            down: currentDown + 1,
            distance: newDistance,
            yardLine: newYardLine
        )
    }

    // MARK: - Drive End Checks

    /// Returns a DriveSimulationResult if the play immediately ends the drive, nil otherwise.
    private static func checkImmediateDriveEnd(
        _ result: PlayResult,
        plays: [PlayResult],
        driveNumber: Int,
        teamID: UUID,
        startingYardLine: Int,
        quarter: Int,
        time: Int
    ) -> DriveSimulationResult? {
        switch result.outcome {
        case .touchdown:
            let driveResult = DriveResult(
                driveNumber: driveNumber,
                teamID: teamID,
                startingYardLine: startingYardLine,
                plays: plays,
                result: .touchdown
            )
            return DriveSimulationResult(
                drive: driveResult,
                endQuarter: quarter,
                endTime: max(time, 0),
                momentumShift: 0.1
            )

        case .fieldGoalGood:
            let driveResult = DriveResult(
                driveNumber: driveNumber,
                teamID: teamID,
                startingYardLine: startingYardLine,
                plays: plays,
                result: .fieldGoal
            )
            return DriveSimulationResult(
                drive: driveResult,
                endQuarter: quarter,
                endTime: max(time, 0),
                momentumShift: 0.05
            )

        case .fieldGoalMissed:
            let driveResult = DriveResult(
                driveNumber: driveNumber,
                teamID: teamID,
                startingYardLine: startingYardLine,
                plays: plays,
                result: .turnover
            )
            return DriveSimulationResult(
                drive: driveResult,
                endQuarter: quarter,
                endTime: max(time, 0),
                momentumShift: -0.05
            )

        case .interception, .fumbleLost:
            let driveResult = DriveResult(
                driveNumber: driveNumber,
                teamID: teamID,
                startingYardLine: startingYardLine,
                plays: plays,
                result: .turnover
            )
            return DriveSimulationResult(
                drive: driveResult,
                endQuarter: quarter,
                endTime: max(time, 0),
                momentumShift: -0.1
            )

        case .punt, .touchback:
            let driveResult = DriveResult(
                driveNumber: driveNumber,
                teamID: teamID,
                startingYardLine: startingYardLine,
                plays: plays,
                result: .punt
            )
            return DriveSimulationResult(
                drive: driveResult,
                endQuarter: quarter,
                endTime: max(time, 0),
                momentumShift: 0.0
            )

        case .safety:
            let driveResult = DriveResult(
                driveNumber: driveNumber,
                teamID: teamID,
                startingYardLine: startingYardLine,
                plays: plays,
                result: .safety
            )
            return DriveSimulationResult(
                drive: driveResult,
                endQuarter: quarter,
                endTime: max(time, 0),
                momentumShift: -0.15
            )

        default:
            return nil
        }
    }

    // MARK: - Clock Management

    /// Calculates seconds consumed by a play.
    /// Incomplete passes and spikes stop the clock (less time consumed).
    /// Run plays and completions keep the clock running.
    private static func clockConsumption(for play: PlayResult) -> Int {
        switch play.outcome {
        case .incompletion:
            // Clock stops on incompletion: just the play itself
            return Int.random(in: 4...8)
        case .spike:
            return 3
        case .kneel:
            return 40
        case .punt, .touchback:
            return Int.random(in: 5...10)
        case .fieldGoalGood, .fieldGoalMissed:
            return Int.random(in: 5...8)
        case .touchdown:
            return Int.random(in: 5...10)
        case .interception, .fumbleLost:
            return Int.random(in: 5...10)
        case .safety:
            return Int.random(in: 5...10)
        default:
            // Completions, rushes, sacks — clock keeps running
            return Int.random(in: 25...40)
        }
    }

    // MARK: - Time Helpers

    /// Determines if the current quarter ends the half or game (Q2, Q4, or OT).
    private static func shouldEndDrive(quarter: Int) -> Bool {
        quarter == 2 || quarter >= 4
    }

    /// Checks if time has fully expired for a half-ending or game-ending quarter.
    private static func isHalfOrGameOver(quarter: Int, time: Int) -> Bool {
        time <= 0 && shouldEndDrive(quarter: quarter)
    }

    /// Returns the appropriate drive outcome when time expires.
    private static func driveOutcomeForTimeExpiry(quarter: Int) -> DriveOutcome {
        if quarter == 2 {
            return .endOfHalf
        }
        return .endOfGame
    }
}
