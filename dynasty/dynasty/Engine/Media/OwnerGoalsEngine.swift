import Foundation

// MARK: - Supporting Types

struct SeasonGoal: Identifiable, Codable {
    let id: UUID
    let title: String
    let description: String
    let type: GoalType
    let target: Int?   // e.g., wins target, or nil for boolean goals
    var progress: Int
    var isAchieved: Bool
    let priority: GoalPriority

    init(
        id: UUID = UUID(),
        title: String,
        description: String,
        type: GoalType,
        target: Int? = nil,
        progress: Int = 0,
        isAchieved: Bool = false,
        priority: GoalPriority
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.type = type
        self.target = target
        self.progress = progress
        self.isAchieved = isAchieved
        self.priority = priority
    }
}

enum GoalType: String, Codable {
    case wins, playoffs, divisionTitle, conference, superBowl,
         developRookies, reduceCapUsage, improveDraft, winStreak,
         fanSatisfaction, tradeAcquisition
}

enum GoalPriority: String, Codable {
    case primary, secondary, bonus
}

// MARK: - OwnerGoalsEngine

enum OwnerGoalsEngine {

    // MARK: - Goal Generation

    /// Generates 3–4 season goals tailored to the team's strength,
    /// the owner's personality, and the current career context.
    static func generateSeasonGoals(team: Team, owner: Owner, career: Career) -> [SeasonGoal] {
        let avgOverall = averageOverall(team: team)
        var goals: [SeasonGoal] = []

        if avgOverall > 75 {
            // Good team — push for a championship
            goals.append(contenderPrimaryGoal(owner: owner))
            goals.append(
                SeasonGoal(
                    title: "Win 12+ Games",
                    description: "Prove your team belongs among the NFL elite with a dominant regular season.",
                    type: .wins,
                    target: 12,
                    priority: .secondary
                )
            )
            goals.append(
                SeasonGoal(
                    title: "Win the Division",
                    description: "Secure home-field advantage and divisional supremacy.",
                    type: .divisionTitle,
                    priority: .bonus
                )
            )

        } else if avgOverall >= 65 {
            // Middle-of-the-pack — playoffs are the realistic ceiling
            goals.append(
                SeasonGoal(
                    title: "Make the Playoffs",
                    description: "\(owner.name) expects a playoff berth this season. Don't leave him waiting.",
                    type: .playoffs,
                    priority: .primary
                )
            )
            goals.append(
                SeasonGoal(
                    title: "Win 9+ Games",
                    description: "A nine-win season demonstrates real progress and silences doubters.",
                    type: .wins,
                    target: 9,
                    priority: .secondary
                )
            )
            goals.append(
                SeasonGoal(
                    title: "Win the Division",
                    description: "Capturing the division title would be a franchise milestone.",
                    type: .divisionTitle,
                    priority: .bonus
                )
            )

        } else {
            // Rebuilding team — focus on development and stability
            if owner.prefersWinNow {
                // Impatient owner still wants a win target
                goals.append(
                    SeasonGoal(
                        title: "Win 6+ Games",
                        description: "\(owner.name) demands progress — at least six wins this season.",
                        type: .wins,
                        target: 6,
                        priority: .primary
                    )
                )
            } else {
                goals.append(
                    SeasonGoal(
                        title: "Develop 3 Rookies",
                        description: "Build the future by getting meaningful snaps for at least three rookies.",
                        type: .developRookies,
                        target: 3,
                        priority: .primary
                    )
                )
            }

            goals.append(
                SeasonGoal(
                    title: "Stay Under the Cap",
                    description: "Maintain financial flexibility heading into future free agency periods.",
                    type: .reduceCapUsage,
                    priority: .secondary
                )
            )

            if !owner.prefersWinNow {
                goals.append(
                    SeasonGoal(
                        title: "Win 6+ Games",
                        description: "Show tangible on-field improvement from last season.",
                        type: .wins,
                        target: 6,
                        priority: .bonus
                    )
                )
            } else {
                goals.append(
                    SeasonGoal(
                        title: "Win 9+ Games",
                        description: "\(owner.name) is not satisfied with a pure rebuild. Push for nine wins.",
                        type: .wins,
                        target: 9,
                        priority: .bonus
                    )
                )
            }
        }

        // Win-now owners always want a stretch win-streak goal appended
        if owner.prefersWinNow && avgOverall >= 65 {
            goals.append(
                SeasonGoal(
                    title: "Win 3 Straight",
                    description: "Demonstrate consistency by putting together a mid-season win streak.",
                    type: .winStreak,
                    target: 3,
                    priority: .bonus
                )
            )
        }

        return Array(goals.prefix(4))
    }

    // MARK: - Progress Evaluation

    /// Re-evaluates each goal's progress against current team state and marks
    /// goals achieved or failed where applicable.
    static func evaluateGoalProgress(goals: [SeasonGoal], team: Team, career: Career) -> [SeasonGoal] {
        goals.map { goal in
            var updated = goal

            switch goal.type {

            case .wins:
                updated.progress = team.wins
                if let target = goal.target {
                    updated.isAchieved = team.wins >= target
                }

            case .playoffs:
                // A playoff appearance is tracked on the career object
                updated.progress = career.playoffAppearances > 0 ? 1 : 0
                updated.isAchieved = career.playoffAppearances > 0

            case .divisionTitle:
                // Division-title detection is approximate: best record among division,
                // represented here by a heuristic — wins lead the pack.
                // Full detection requires standings; we track wins as a proxy.
                updated.progress = team.wins
                // Achieved when the career logged a playoff appearance and wins are strong
                updated.isAchieved = team.wins >= 11 && career.playoffAppearances > 0

            case .conference:
                updated.progress = career.championships > 0 ? 1 : 0
                updated.isAchieved = career.championships > 0   // championships implies conf win

            case .superBowl:
                updated.progress = career.championships > 0 ? 1 : 0
                updated.isAchieved = career.championships > 0

            case .developRookies:
                let rookieCount = team.players.filter { $0.yearsPro <= 1 && $0.overall >= 60 }.count
                updated.progress = rookieCount
                if let target = goal.target {
                    updated.isAchieved = rookieCount >= target
                }

            case .reduceCapUsage:
                let usagePct = team.salaryCap > 0
                    ? Double(team.currentCapUsage) / Double(team.salaryCap)
                    : 1.0
                // Goal: stay under 95% of the cap
                updated.progress = Int(usagePct * 100)
                updated.isAchieved = usagePct <= 0.95

            case .winStreak:
                // Approximate: if wins greatly outpace losses in recent history
                // Full streak tracking requires game log; wins-minus-losses is a proxy.
                let recentSurplus = team.wins - team.losses
                updated.progress = max(0, recentSurplus)
                if let target = goal.target {
                    updated.isAchieved = recentSurplus >= target
                }

            case .improveDraft, .fanSatisfaction, .tradeAcquisition:
                // These goal types rely on external tracking; leave unchanged
                break
            }

            return updated
        }
    }

    // MARK: - Private Helpers

    private static func averageOverall(team: Team) -> Double {
        guard !team.players.isEmpty else { return 0 }
        let total = team.players.reduce(0) { $0 + $1.overall }
        return Double(total) / Double(team.players.count)
    }

    private static func contenderPrimaryGoal(owner: Owner) -> SeasonGoal {
        if owner.prefersWinNow {
            return SeasonGoal(
                title: "Win the Super Bowl",
                description: "\(owner.name) has invested in this roster to win a championship. Nothing less will do.",
                type: .superBowl,
                priority: .primary
            )
        } else {
            return SeasonGoal(
                title: "Win the Conference",
                description: "Reach the Super Bowl and prove this team is one of the NFL's elite franchises.",
                type: .conference,
                priority: .primary
            )
        }
    }
}
