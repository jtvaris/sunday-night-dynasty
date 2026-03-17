import Foundation

struct NFLTeamDefinition {
    let name: String
    let city: String
    let abbreviation: String
    let conference: Conference
    let division: Division
    let mediaMarket: MediaMarket
}

// MARK: - Team Preview (Pre-Generation Scouting Data)

struct TeamPreview {
    let difficulty: Int          // 1-5 stars
    let situation: String        // "Rebuilding", "Rising", "Contender", "Win Now", "Dynasty"
    let ownerPatience: String    // "Very Patient", "Patient", "Moderate", "Demanding", "Win Now"
    let patienceSeasons: Int     // How many losing seasons before pressure mounts
    let marketDescription: String // Explains the media market
    let estimatedOVR: Int        // Approximate roster overall 60-88
    let estimatedCapSpace: Int   // In millions
    let estimatedDraftPicks: Int // Total picks
    let coachingBudget: Int      // In millions, for coaching + scouting staff

    var difficultyLabel: String {
        switch difficulty {
        case 1: return "Very Easy"
        case 2: return "Easy"
        case 3: return "Moderate"
        case 4: return "Hard"
        case 5: return "Very Hard"
        default: return "Moderate"
        }
    }

    var ownerPatienceIcon: String {
        switch ownerPatience {
        case "Very Patient": return "clock.fill"
        case "Patient":      return "clock"
        case "Moderate":     return "gauge.medium"
        case "Demanding":    return "exclamationmark.triangle"
        case "Win Now":      return "exclamationmark.triangle.fill"
        default:             return "gauge.medium"
        }
    }
}

extension NFLTeamDefinition {
    var preview: TeamPreview {
        NFLTeamData.previews[abbreviation] ?? TeamPreview(
            difficulty: 3, situation: "Rising", ownerPatience: "Moderate",
            patienceSeasons: 3, marketDescription: "Moderate expectations",
            estimatedOVR: 75, estimatedCapSpace: 25, estimatedDraftPicks: 7,
            coachingBudget: 14
        )
    }
}

enum NFLTeamData {

    // MARK: - Team Preview Data

    static let previews: [String: TeamPreview] = [
        // AFC East
        "BUF": TeamPreview(difficulty: 3, situation: "Contender", ownerPatience: "Moderate", patienceSeasons: 3, marketDescription: "Passionate fan base with moderate media coverage", estimatedOVR: 82, estimatedCapSpace: 18, estimatedDraftPicks: 7, coachingBudget: 15),
        "MIA": TeamPreview(difficulty: 3, situation: "Rising", ownerPatience: "Moderate", patienceSeasons: 3, marketDescription: "Large market with national spotlight and high fan expectations", estimatedOVR: 78, estimatedCapSpace: 22, estimatedDraftPicks: 7, coachingBudget: 14),
        "NE":  TeamPreview(difficulty: 2, situation: "Rebuilding", ownerPatience: "Patient", patienceSeasons: 4, marketDescription: "Storied franchise, media expects return to glory", estimatedOVR: 70, estimatedCapSpace: 40, estimatedDraftPicks: 9, coachingBudget: 20),
        "NYJ": TeamPreview(difficulty: 4, situation: "Rising", ownerPatience: "Demanding", patienceSeasons: 2, marketDescription: "Intense scrutiny, win now pressure from NYC media", estimatedOVR: 74, estimatedCapSpace: 20, estimatedDraftPicks: 7, coachingBudget: 19),

        // AFC North
        "BAL": TeamPreview(difficulty: 3, situation: "Contender", ownerPatience: "Moderate", patienceSeasons: 3, marketDescription: "Loyal fan base that expects tough, competitive football", estimatedOVR: 83, estimatedCapSpace: 15, estimatedDraftPicks: 7, coachingBudget: 13),
        "CIN": TeamPreview(difficulty: 3, situation: "Contender", ownerPatience: "Patient", patienceSeasons: 4, marketDescription: "Moderate expectations with a growing fan base", estimatedOVR: 80, estimatedCapSpace: 28, estimatedDraftPicks: 7, coachingBudget: 12),
        "CLE": TeamPreview(difficulty: 4, situation: "Rebuilding", ownerPatience: "Demanding", patienceSeasons: 2, marketDescription: "Passionate but frustrated fan base demanding results", estimatedOVR: 68, estimatedCapSpace: 12, estimatedDraftPicks: 6, coachingBudget: 10),
        "PIT": TeamPreview(difficulty: 3, situation: "Rising", ownerPatience: "Patient", patienceSeasons: 4, marketDescription: "Blue-collar market that values toughness and consistency", estimatedOVR: 76, estimatedCapSpace: 30, estimatedDraftPicks: 8, coachingBudget: 14),

        // AFC South
        "HOU": TeamPreview(difficulty: 3, situation: "Contender", ownerPatience: "Moderate", patienceSeasons: 3, marketDescription: "Large market with growing national media attention", estimatedOVR: 81, estimatedCapSpace: 20, estimatedDraftPicks: 7, coachingBudget: 15),
        "IND": TeamPreview(difficulty: 2, situation: "Rising", ownerPatience: "Patient", patienceSeasons: 4, marketDescription: "Moderate expectations, patient ownership group", estimatedOVR: 75, estimatedCapSpace: 35, estimatedDraftPicks: 8, coachingBudget: 10),
        "JAX": TeamPreview(difficulty: 1, situation: "Rebuilding", ownerPatience: "Very Patient", patienceSeasons: 5, marketDescription: "Low pressure, patient fans rebuilding culture", estimatedOVR: 66, estimatedCapSpace: 50, estimatedDraftPicks: 10, coachingBudget: 8),
        "TEN": TeamPreview(difficulty: 2, situation: "Rebuilding", ownerPatience: "Patient", patienceSeasons: 4, marketDescription: "Quiet market with room to build without pressure", estimatedOVR: 69, estimatedCapSpace: 42, estimatedDraftPicks: 9, coachingBudget: 9),

        // AFC West
        "DEN": TeamPreview(difficulty: 3, situation: "Rising", ownerPatience: "Moderate", patienceSeasons: 3, marketDescription: "Dedicated fan base expecting a return to prominence", estimatedOVR: 76, estimatedCapSpace: 25, estimatedDraftPicks: 7, coachingBudget: 13),
        "KC":  TeamPreview(difficulty: 4, situation: "Dynasty", ownerPatience: "Moderate", patienceSeasons: 3, marketDescription: "Championship culture, high expectations to sustain success", estimatedOVR: 87, estimatedCapSpace: 10, estimatedDraftPicks: 6, coachingBudget: 16),
        "LV":  TeamPreview(difficulty: 4, situation: "Rebuilding", ownerPatience: "Demanding", patienceSeasons: 2, marketDescription: "Flashy market with impatient ownership wanting results fast", estimatedOVR: 70, estimatedCapSpace: 18, estimatedDraftPicks: 7, coachingBudget: 9),
        "LAC": TeamPreview(difficulty: 3, situation: "Rising", ownerPatience: "Moderate", patienceSeasons: 3, marketDescription: "Large market but competing for attention in LA", estimatedOVR: 77, estimatedCapSpace: 28, estimatedDraftPicks: 7, coachingBudget: 14),

        // NFC East
        "DAL": TeamPreview(difficulty: 5, situation: "Win Now", ownerPatience: "Win Now", patienceSeasons: 1, marketDescription: "America's Team — maximum media pressure at all times", estimatedOVR: 80, estimatedCapSpace: 12, estimatedDraftPicks: 6, coachingBudget: 22),
        "NYG": TeamPreview(difficulty: 4, situation: "Rebuilding", ownerPatience: "Demanding", patienceSeasons: 2, marketDescription: "NYC market demands winners, legacy franchise with high bar", estimatedOVR: 67, estimatedCapSpace: 22, estimatedDraftPicks: 8, coachingBudget: 18),
        "PHI": TeamPreview(difficulty: 4, situation: "Contender", ownerPatience: "Demanding", patienceSeasons: 2, marketDescription: "Intense scrutiny, passionate fan base expects championships", estimatedOVR: 84, estimatedCapSpace: 14, estimatedDraftPicks: 6, coachingBudget: 16),
        "WAS": TeamPreview(difficulty: 3, situation: "Rising", ownerPatience: "Moderate", patienceSeasons: 3, marketDescription: "Rebuilding brand in a major market, moderate pressure", estimatedOVR: 73, estimatedCapSpace: 32, estimatedDraftPicks: 8, coachingBudget: 10),

        // NFC North
        "CHI": TeamPreview(difficulty: 4, situation: "Rising", ownerPatience: "Demanding", patienceSeasons: 2, marketDescription: "Massive market, title-starved fan base growing impatient", estimatedOVR: 74, estimatedCapSpace: 35, estimatedDraftPicks: 8, coachingBudget: 15),
        "DET": TeamPreview(difficulty: 3, situation: "Contender", ownerPatience: "Moderate", patienceSeasons: 3, marketDescription: "Hungry fan base riding momentum, rising expectations", estimatedOVR: 83, estimatedCapSpace: 16, estimatedDraftPicks: 7, coachingBudget: 14),
        "GB":  TeamPreview(difficulty: 2, situation: "Rising", ownerPatience: "Very Patient", patienceSeasons: 5, marketDescription: "Small market, community-owned — unique patience and loyalty", estimatedOVR: 78, estimatedCapSpace: 25, estimatedDraftPicks: 7, coachingBudget: 11),
        "MIN": TeamPreview(difficulty: 3, situation: "Contender", ownerPatience: "Moderate", patienceSeasons: 3, marketDescription: "Dedicated fans with moderate media presence", estimatedOVR: 80, estimatedCapSpace: 20, estimatedDraftPicks: 7, coachingBudget: 13),

        // NFC South
        "ATL": TeamPreview(difficulty: 3, situation: "Rising", ownerPatience: "Moderate", patienceSeasons: 3, marketDescription: "Large market pushing for relevance, growing expectations", estimatedOVR: 75, estimatedCapSpace: 22, estimatedDraftPicks: 7, coachingBudget: 14),
        "CAR": TeamPreview(difficulty: 1, situation: "Rebuilding", ownerPatience: "Very Patient", patienceSeasons: 5, marketDescription: "Low pressure market with a patient, long-term approach", estimatedOVR: 64, estimatedCapSpace: 55, estimatedDraftPicks: 10, coachingBudget: 8),
        "NO":  TeamPreview(difficulty: 3, situation: "Rebuilding", ownerPatience: "Moderate", patienceSeasons: 3, marketDescription: "Passionate city, transitioning from a championship era", estimatedOVR: 72, estimatedCapSpace: 8, estimatedDraftPicks: 7, coachingBudget: 13),
        "TB":  TeamPreview(difficulty: 2, situation: "Rebuilding", ownerPatience: "Patient", patienceSeasons: 4, marketDescription: "Moderate market, post-dynasty reset with room to grow", estimatedOVR: 71, estimatedCapSpace: 38, estimatedDraftPicks: 8, coachingBudget: 12),

        // NFC West
        "ARI": TeamPreview(difficulty: 2, situation: "Rebuilding", ownerPatience: "Patient", patienceSeasons: 4, marketDescription: "Moderate market with a patient ownership group", estimatedOVR: 69, estimatedCapSpace: 40, estimatedDraftPicks: 9, coachingBudget: 9),
        "LAR": TeamPreview(difficulty: 4, situation: "Win Now", ownerPatience: "Demanding", patienceSeasons: 2, marketDescription: "Win now in LA — star-driven franchise under constant spotlight", estimatedOVR: 79, estimatedCapSpace: 10, estimatedDraftPicks: 5, coachingBudget: 20),
        "SF":  TeamPreview(difficulty: 4, situation: "Contender", ownerPatience: "Demanding", patienceSeasons: 2, marketDescription: "Elite expectations, championship-or-bust mentality", estimatedOVR: 85, estimatedCapSpace: 12, estimatedDraftPicks: 6, coachingBudget: 20),
        "SEA": TeamPreview(difficulty: 3, situation: "Rising", ownerPatience: "Moderate", patienceSeasons: 3, marketDescription: "Passionate 12th Man fan base, moderate media market", estimatedOVR: 77, estimatedCapSpace: 24, estimatedDraftPicks: 7, coachingBudget: 13),
    ]

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
