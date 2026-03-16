import Foundation

struct NFLTeamDefinition {
    let name: String
    let city: String
    let abbreviation: String
    let conference: Conference
    let division: Division
    let mediaMarket: MediaMarket
}

enum NFLTeamData {

    static let allTeams: [NFLTeamDefinition] = [
        // MARK: - AFC East
        NFLTeamDefinition(name: "Bills", city: "Buffalo", abbreviation: "BUF", conference: .AFC, division: .east, mediaMarket: .medium),
        NFLTeamDefinition(name: "Dolphins", city: "Miami", abbreviation: "MIA", conference: .AFC, division: .east, mediaMarket: .large),
        NFLTeamDefinition(name: "Patriots", city: "New England", abbreviation: "NE", conference: .AFC, division: .east, mediaMarket: .large),
        NFLTeamDefinition(name: "Jets", city: "New York", abbreviation: "NYJ", conference: .AFC, division: .east, mediaMarket: .large),

        // MARK: - AFC North
        NFLTeamDefinition(name: "Ravens", city: "Baltimore", abbreviation: "BAL", conference: .AFC, division: .north, mediaMarket: .medium),
        NFLTeamDefinition(name: "Bengals", city: "Cincinnati", abbreviation: "CIN", conference: .AFC, division: .north, mediaMarket: .medium),
        NFLTeamDefinition(name: "Browns", city: "Cleveland", abbreviation: "CLE", conference: .AFC, division: .north, mediaMarket: .medium),
        NFLTeamDefinition(name: "Steelers", city: "Pittsburgh", abbreviation: "PIT", conference: .AFC, division: .north, mediaMarket: .medium),

        // MARK: - AFC South
        NFLTeamDefinition(name: "Texans", city: "Houston", abbreviation: "HOU", conference: .AFC, division: .south, mediaMarket: .large),
        NFLTeamDefinition(name: "Colts", city: "Indianapolis", abbreviation: "IND", conference: .AFC, division: .south, mediaMarket: .medium),
        NFLTeamDefinition(name: "Jaguars", city: "Jacksonville", abbreviation: "JAX", conference: .AFC, division: .south, mediaMarket: .small),
        NFLTeamDefinition(name: "Titans", city: "Tennessee", abbreviation: "TEN", conference: .AFC, division: .south, mediaMarket: .medium),

        // MARK: - AFC West
        NFLTeamDefinition(name: "Broncos", city: "Denver", abbreviation: "DEN", conference: .AFC, division: .west, mediaMarket: .medium),
        NFLTeamDefinition(name: "Chiefs", city: "Kansas City", abbreviation: "KC", conference: .AFC, division: .west, mediaMarket: .medium),
        NFLTeamDefinition(name: "Raiders", city: "Las Vegas", abbreviation: "LV", conference: .AFC, division: .west, mediaMarket: .large),
        NFLTeamDefinition(name: "Chargers", city: "Los Angeles", abbreviation: "LAC", conference: .AFC, division: .west, mediaMarket: .large),

        // MARK: - NFC East
        NFLTeamDefinition(name: "Cowboys", city: "Dallas", abbreviation: "DAL", conference: .NFC, division: .east, mediaMarket: .large),
        NFLTeamDefinition(name: "Giants", city: "New York", abbreviation: "NYG", conference: .NFC, division: .east, mediaMarket: .large),
        NFLTeamDefinition(name: "Eagles", city: "Philadelphia", abbreviation: "PHI", conference: .NFC, division: .east, mediaMarket: .large),
        NFLTeamDefinition(name: "Commanders", city: "Washington", abbreviation: "WAS", conference: .NFC, division: .east, mediaMarket: .large),

        // MARK: - NFC North
        NFLTeamDefinition(name: "Bears", city: "Chicago", abbreviation: "CHI", conference: .NFC, division: .north, mediaMarket: .large),
        NFLTeamDefinition(name: "Lions", city: "Detroit", abbreviation: "DET", conference: .NFC, division: .north, mediaMarket: .medium),
        NFLTeamDefinition(name: "Packers", city: "Green Bay", abbreviation: "GB", conference: .NFC, division: .north, mediaMarket: .small),
        NFLTeamDefinition(name: "Vikings", city: "Minnesota", abbreviation: "MIN", conference: .NFC, division: .north, mediaMarket: .medium),

        // MARK: - NFC South
        NFLTeamDefinition(name: "Falcons", city: "Atlanta", abbreviation: "ATL", conference: .NFC, division: .south, mediaMarket: .large),
        NFLTeamDefinition(name: "Panthers", city: "Carolina", abbreviation: "CAR", conference: .NFC, division: .south, mediaMarket: .medium),
        NFLTeamDefinition(name: "Saints", city: "New Orleans", abbreviation: "NO", conference: .NFC, division: .south, mediaMarket: .medium),
        NFLTeamDefinition(name: "Buccaneers", city: "Tampa Bay", abbreviation: "TB", conference: .NFC, division: .south, mediaMarket: .medium),

        // MARK: - NFC West
        NFLTeamDefinition(name: "Cardinals", city: "Arizona", abbreviation: "ARI", conference: .NFC, division: .west, mediaMarket: .medium),
        NFLTeamDefinition(name: "Rams", city: "Los Angeles", abbreviation: "LAR", conference: .NFC, division: .west, mediaMarket: .large),
        NFLTeamDefinition(name: "49ers", city: "San Francisco", abbreviation: "SF", conference: .NFC, division: .west, mediaMarket: .large),
        NFLTeamDefinition(name: "Seahawks", city: "Seattle", abbreviation: "SEA", conference: .NFC, division: .west, mediaMarket: .medium),
    ]
}
