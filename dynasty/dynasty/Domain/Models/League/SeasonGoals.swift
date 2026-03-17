import Foundation

struct SeasonGoals: Codable, Equatable {

    var primaryGoal: String
    var secondaryGoal: String
    var ownerExpectation: OwnerExpectation
    var isAchieved: Bool

    // MARK: - Owner Expectation

    enum OwnerExpectation: String, Codable {
        case superBowl
        case conference
        case playoff
        case winningRecord
        case development
        case rebuild
    }

    // MARK: - Generation

    /// Generate season goals based on team quality (average overall 1-99) and owner preference.
    static func generate(teamQuality: Int, ownerPreference: Bool) -> SeasonGoals {
        // ownerPreference == true means owner prefers win-now
        switch teamQuality {
        case 80...:
            // Elite team
            return SeasonGoals(
                primaryGoal: "Win the Super Bowl",
                secondaryGoal: ownerPreference
                    ? "Maintain the championship window"
                    : "Develop young talent for sustained success",
                ownerExpectation: .superBowl,
                isAchieved: false
            )
        case 70..<80:
            // Good team
            if ownerPreference {
                return SeasonGoals(
                    primaryGoal: "Win the Super Bowl",
                    secondaryGoal: "Upgrade key roster positions",
                    ownerExpectation: .conference,
                    isAchieved: false
                )
            } else {
                return SeasonGoals(
                    primaryGoal: "Win the division",
                    secondaryGoal: "Build depth through the draft",
                    ownerExpectation: .playoff,
                    isAchieved: false
                )
            }
        case 60..<70:
            // Average team
            if ownerPreference {
                return SeasonGoals(
                    primaryGoal: "Make the playoffs",
                    secondaryGoal: "Compete for the division title",
                    ownerExpectation: .playoff,
                    isAchieved: false
                )
            } else {
                return SeasonGoals(
                    primaryGoal: "Finish with a winning record",
                    secondaryGoal: "Develop young talent",
                    ownerExpectation: .winningRecord,
                    isAchieved: false
                )
            }
        case 50..<60:
            // Below average team
            if ownerPreference {
                return SeasonGoals(
                    primaryGoal: "Compete for a playoff spot",
                    secondaryGoal: "Improve the roster through free agency",
                    ownerExpectation: .winningRecord,
                    isAchieved: false
                )
            } else {
                return SeasonGoals(
                    primaryGoal: "Show improvement on the field",
                    secondaryGoal: "Identify franchise cornerstones",
                    ownerExpectation: .development,
                    isAchieved: false
                )
            }
        default:
            // Bad team
            if ownerPreference {
                return SeasonGoals(
                    primaryGoal: "Compete for a playoff spot",
                    secondaryGoal: "Sign impact free agents",
                    ownerExpectation: .winningRecord,
                    isAchieved: false
                )
            } else {
                return SeasonGoals(
                    primaryGoal: "Start the rebuild",
                    secondaryGoal: "Accumulate draft capital",
                    ownerExpectation: .rebuild,
                    isAchieved: false
                )
            }
        }
    }
}
