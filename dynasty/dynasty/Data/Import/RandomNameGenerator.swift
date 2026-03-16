import Foundation

enum RandomNameGenerator {

    // MARK: - First Names

    private static let firstNames: [String] = [
        "James", "Marcus", "DeAndre", "Tyreek", "Davante",
        "Lamar", "Patrick", "Jalen", "Justin", "Derrick",
        "Brandon", "Jamal", "Darius", "Chris", "Travis",
        "Micah", "Josh", "Trevon", "Roquan", "Sauce",
        "Devin", "Stefon", "Jaylen", "Cameron", "Michael",
        "Andre", "Malik", "Darnell", "Tyrone", "Rasheed",
        "Antonio", "Robert", "DeSean", "Tavon", "Khalil",
        "Isaiah", "Jaylon", "Terrell", "Damien", "Dexter",
        "Kwame", "Marquise", "Javon", "Trey", "Kadarius",
        "Brock", "Joe", "Trevor", "Sam", "Daniel",
        "Ryan", "Garrett", "Cooper", "Cole", "Zach"
    ]

    // MARK: - Last Names

    private static let lastNames: [String] = [
        "Smith", "Johnson", "Williams", "Brown", "Jones",
        "Davis", "Jackson", "Wilson", "Thomas", "Harris",
        "Robinson", "Clark", "Lewis", "Walker", "Allen",
        "Young", "King", "Wright", "Hill", "Green",
        "Adams", "Baker", "Carter", "Mitchell", "Turner",
        "Moore", "Taylor", "Anderson", "White", "Martin",
        "Thompson", "Coleman", "Jenkins", "Perry", "Powell",
        "Brooks", "Bell", "Griffin", "Hayes", "Bryant",
        "Simmons", "Foster", "Reed", "Howard", "Warren",
        "Sanders", "Gordon", "Freeman", "Washington", "Dixon",
        "Parsons", "Diggs", "Kelce", "Bosa", "Garrett"
    ]

    // MARK: - Public

    /// Returns a random first and last name tuple.
    static func randomName() -> (first: String, last: String) {
        let first = firstNames.randomElement()!
        let last = lastNames.randomElement()!
        return (first, last)
    }
}
