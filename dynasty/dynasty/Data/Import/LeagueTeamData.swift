import Foundation

struct LeagueTeamDefinition {
    let name: String
    let city: String
    let abbreviation: String
    let conference: Conference
    let division: Division
    let mediaMarket: MediaMarket
}

// MARK: - Team Preview (Pre-Generation Scouting Data)

/// One named roster player on the pre-generation scouting card.
///
/// Abbreviated exactly like `TeamPreview.startingQBName` — "D. Ashgrove" — for
/// the same reason: this is a scouting blurb, not a name. The given name behind
/// the initial is drawn when the man is actually generated (see
/// `LeagueGenerator.expandedGivenName`), so no player in the league ends up with
/// a letter for a first name.
struct TeamPreviewStar: Hashable {
    let name: String
    let position: Position
    let overall: Int
}

struct TeamPreview {
    let difficulty: Int          // 1-5 stars
    let situation: String        // "Rebuilding", "Rising", "Contender", "Win Now", "Dynasty"
    let ownerPatience: String    // "Very Patient", "Patient", "Moderate", "Demanding", "Win Now"
    let patienceSeasons: Int     // How many losing seasons before pressure mounts
    let marketDescription: String // Explains the media market
    let estimatedOVR: Int        // Approximate roster overall 60-88
    let estimatedCapSpace: Int   // In millions
    let estimatedDraftPicks: Int // Total picks
    let coachingBudget: Int      // In millions, for coaching + scouting staff (matches BudgetEngine output)
    let spendingWillingness: Int // Owner spending willingness (1-99), used by LeagueGenerator
    let lastSeasonWins: Int      // Previous season wins
    let lastSeasonLosses: Int    // Previous season losses

    /// How last season ended, already phrased for display — "Won the
    /// Championship", "Lost Divisional round", "Missed the playoffs".
    ///
    /// `nil` on the random/generated league, which has no franchise history to
    /// report: the static preview table carries one authored W-L per club and
    /// nothing about January. Only the fixed 2026 template knows this, so only
    /// the fixed path fills it in and every reader must handle the absence.
    var lastSeasonPlayoffResult: String? = nil
    let startingQBName: String   // Starting QB name for scouting preview
    let startingQBOverall: Int   // Starting QB overall rating
    var isLocked: Bool = false   // Whether the team requires an achievement to unlock

    /// The two or three players worth knowing besides the quarterback.
    ///
    /// The QB is deliberately NOT repeated here: the sheet already gives him a
    /// card of his own directly above this one, and a three-name list that
    /// spends a third of itself restating the card above says nothing new. This
    /// list exists to name the men that card does not.
    var stars: [TeamPreviewStar] = []

    /// The best and the worst position room on the roster, as the group labels
    /// the roster screen grades — "OL", "DB", "ST". Empty when the source has
    /// no opinion (the `LeagueTeamDefinition.preview` fallback), and the sheet
    /// simply omits the card.
    ///
    /// On the fixed template these are DERIVED from the real ratings
    /// (`TeamBrowseCatalog`); on the random league they are authored here and
    /// `LeagueGenerator.generateRoster` makes them true — it does not merely
    /// hope they are. See `LeagueTeamData.positionGroups`.
    var strongestGroup: String = ""
    var weakestGroup: String = ""

    /// What the badge carries into the room before a down is played — 1
    /// (overlooked) to 5 (storied).
    ///
    /// A franchise fact, in the same class as `ownerPatience` and
    /// `marketDescription`: authored per club below and NOT derived from the
    /// roster snapshot, because a bad year does not cost a club its history.
    /// The template path reads the same authored value for the same franchise
    /// (`TeamBrowseCatalog.preview(for:)`), which is what "derivation for
    /// template leagues" comes to once you notice the template renames the
    /// nickname but not the franchise.
    ///
    /// **Nothing in the season simulation reads this.** It is the standing the
    /// picker states, not a coefficient — see the card that prints it, which
    /// says so on screen rather than letting the player assume otherwise.
    var prestige: Int = 3

    /// The coaching style this building has been run on — the club's own
    /// playstyle, stated in the one vocabulary the career already speaks
    /// (`CoachingStyle`, chosen on NewCareerView's identity page).
    ///
    /// The player is never asked a second time: the style he already declared
    /// IS the preference, and this field is what a club is matched against.
    /// A mismatch is not a penalty and the sheet does not pretend it is —
    /// nothing in the engine reads this pairing. It says whose house you are
    /// walking into.
    var styleFit: CoachingStyle = .tactician

    /// The systems this club installs, offence and defence.
    ///
    /// Real on both paths, which is the whole point of the field: the fixed
    /// template states each club's `staff.offScheme`/`defScheme` and the
    /// picker reads them; the random league takes the authored pair below and
    /// `LeagueGenerator.generate` hires the head coach, the coordinator pair
    /// and builds the roster under it, so the card is a promise the generator
    /// keeps rather than a guess made before the coach exists. They were drawn
    /// with `allCases.randomElement()` inside `generate` until this field
    /// existed, and nothing could be said about them here.
    ///
    /// `nil` where the source does not state one (a template baked without the
    /// staff keys); the sheet then omits the card rather than naming a default.
    var offensiveScheme: OffensiveScheme? = nil
    var defensiveScheme: DefensiveScheme? = nil

    /// Previous season W-L record string for display.
    var lastSeasonRecord: String {
        "\(lastSeasonWins)-\(lastSeasonLosses)"
    }

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

    /// The prestige tier as a word. Deliberately not a star row — the sheet
    /// already spends five stars on career difficulty two cards up, and a
    /// second five-of-something is read as the same scale.
    var prestigeLabel: String {
        switch prestige {
        case 5: return "Storied"
        case 4: return "Proud"
        case 3: return "Established"
        case 2: return "Modest"
        case 1: return "Overlooked"
        default: return "Established"
        }
    }

    /// What the tier means, in the terms a new GM cares about: whose history he
    /// is standing in front of. Five lines, not thirty-two — the authored part
    /// is the standing, and inventing a paragraph per club would be inventing
    /// history the game never simulates.
    var prestigeDetail: String {
        switch prestige {
        case 5: return "Banners in the rafters and a permanent seat at the top table."
        case 4: return "A proud franchise with a title era its supporters still measure by."
        case 3: return "A settled club — respected, without a legend to live up to."
        case 2: return "Little history to trade on. Whatever you build here is yours."
        case 1: return "Nobody outside the city expects anything. Nobody is watching either."
        default: return "A settled club — respected, without a legend to live up to."
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

extension LeagueTeamDefinition {
    var preview: TeamPreview {
        LeagueTeamData.previews[abbreviation] ?? TeamPreview(
            difficulty: 3, situation: "Rising", ownerPatience: "Moderate",
            patienceSeasons: 3, marketDescription: "Moderate expectations",
            estimatedOVR: 75, estimatedCapSpace: 25, estimatedDraftPicks: 7,
            coachingBudget: 38, spendingWillingness: 50, lastSeasonWins: 8, lastSeasonLosses: 9,
            startingQBName: "J. Doe", startingQBOverall: 72
        )
    }
}

enum LeagueTeamData {

    // MARK: - Position Groups

    /// The nine rooms a roster is graded in, and the label each one prints.
    ///
    /// The same nine the roster screen, the intro sequence and the roster
    /// evaluation already use; stated once here because three things now have
    /// to agree about them — the authored table below, the generator that makes
    /// its claim true, and the sheet that prints it.
    static let positionGroups: [(label: String, positions: [Position])] = [
        ("QB", [.QB]),
        ("RB", [.RB, .FB]),
        ("WR", [.WR]),
        ("TE", [.TE]),
        ("OL", [.LT, .LG, .C, .RG, .RT]),
        ("DL", [.DE, .DT]),
        ("LB", [.OLB, .MLB]),
        ("DB", [.CB, .FS, .SS]),
        ("ST", [.K, .P, .LS, .H]),
    ]

    /// Group label for a position, or `nil` if the position is in no group.
    static func positionGroupLabel(for position: Position) -> String? {
        positionGroups.first { $0.positions.contains(position) }?.label
    }

    // MARK: - Team Preview Data

    // AUTHORING NOTES for `stars` / `strongestGroup` / `weakestGroup`.
    //
    // • Star overalls track `estimatedOVR` and `situation`: a Contender's best
    //   man sits 6-9 above the club's roster estimate, a Rebuilding club's
    //   12-18 above it and never at 90 — one good player is what a bad roster
    //   has, three All-Pros is not.
    // • The starting quarterback is a star and is NOT repeated in `stars`; see
    //   the field's own comment.
    // • A star is never listed in the club's `weakestGroup` — that would be the
    //   card contradicting itself on one screen.
    // • `strongestGroup` is "QB" wherever the authored quarterback outrates
    //   anything another room can reach (roughly 86+). That is not taste: the
    //   QB room has exactly one starter, so its grade IS the quarterback's
    //   overall, and no amount of generator bias can lift a four-man defensive
    //   line above a 97-rated passer without wrecking the roster.
    // • `strongestGroup` is never "WR". The 53-man blueprint gives the receiver
    //   room one first-tier body and six depth ones, so its third starter is
    //   always a depth-tier player and the room cannot grade out on top. A star
    //   receiver is still a star — he just does not make the room the best one.
    //
    // AUTHORING NOTES for `prestige` / `styleFit` / the scheme pair.
    //
    // • `prestige` is history, never form. It does not move when a club has a
    //   bad year — that is what `situation` and the record are for — and no
    //   engine reads it, so it can never make one club quietly better to pick.
    //   Spread: 6 clubs at 5, 8 at 4, 9 at 3, 7 at 2, 2 at 1.
    // • `styleFit` is spread so no coaching style leaves its player a short
    //   list: tactician 7, innovator 7, playersCoach 7, motivator 6,
    //   disciplinarian 5. A style with two clubs would be a difficulty setting.
    // • The scheme pair keeps the MARGINAL DISTRIBUTION the uniform draw it
    //   replaced had, because the generated roster is built to its defence and
    //   the league's balance was measured under that draw: exactly 4 clubs per
    //   `OffensiveScheme` (8 × 4 = 32), and 4-5 per `DefensiveScheme`
    //   (base34 5, base43 5, cover3 5, pressMan 4, tampa2 4, multiple 5,
    //   hybrid 4 = 32) against a uniform expectation of 4.57. Fourteen of the
    //   32 run a 3-4 family front (base34 / hybrid / multiple), against 16 in
    //   the fixed 2026 template. Any re-authoring must hold those counts.

    static let previews: [String: TeamPreview] = [
        // AFC East
        "BUF": TeamPreview(difficulty: 3, situation: "Contender", ownerPatience: "Moderate", patienceSeasons: 3, marketDescription: "Passionate fan base with moderate media coverage", estimatedOVR: 82, estimatedCapSpace: 18, estimatedDraftPicks: 7, coachingBudget: 43, spendingWillingness: 55, lastSeasonWins: 11, lastSeasonLosses: 6, startingQBName: "S. Loftin", startingQBOverall: 92,
                           stars: [TeamPreviewStar(name: "D. Ashgrove", position: .WR, overall: 88),
                                   TeamPreviewStar(name: "T. Carbury", position: .MLB, overall: 84)],
                           strongestGroup: "QB", weakestGroup: "OL",
                           prestige: 3, styleFit: .motivator,
                           offensiveScheme: .spread, defensiveScheme: .base43),
        "MIA": TeamPreview(difficulty: 3, situation: "Rising", ownerPatience: "Moderate", patienceSeasons: 3, marketDescription: "Large market with national spotlight and high fan expectations", estimatedOVR: 78, estimatedCapSpace: 22, estimatedDraftPicks: 7, coachingBudget: 45, spendingWillingness: 50, lastSeasonWins: 9, lastSeasonLosses: 8, startingQBName: "G. Kimbrough", startingQBOverall: 81,
                           stars: [TeamPreviewStar(name: "K. Wilbraham", position: .WR, overall: 86),
                                   TeamPreviewStar(name: "D. Alcott", position: .CB, overall: 82)],
                           strongestGroup: "DB", weakestGroup: "OL",
                           prestige: 4, styleFit: .innovator,
                           offensiveScheme: .westCoast, defensiveScheme: .cover3),
        "NE":  TeamPreview(difficulty: 2, situation: "Rebuilding", ownerPatience: "Patient", patienceSeasons: 4, marketDescription: "Storied franchise, media expects return to glory", estimatedOVR: 70, estimatedCapSpace: 40, estimatedDraftPicks: 9, coachingBudget: 38, spendingWillingness: 45, lastSeasonWins: 4, lastSeasonLosses: 13, startingQBName: "H. Grimsley", startingQBOverall: 68,
                           stars: [TeamPreviewStar(name: "R. Halloway", position: .CB, overall: 83),
                                   TeamPreviewStar(name: "M. Pierrepont", position: .LT, overall: 78)],
                           strongestGroup: "DB", weakestGroup: "QB",
                           prestige: 5, styleFit: .tactician,
                           offensiveScheme: .proPassing, defensiveScheme: .base34),
        "NYJ": TeamPreview(difficulty: 4, situation: "Rising", ownerPatience: "Demanding", patienceSeasons: 2, marketDescription: "Intense scrutiny, win now pressure from NYC media", estimatedOVR: 74, estimatedCapSpace: 20, estimatedDraftPicks: 7, coachingBudget: 48, spendingWillingness: 70, lastSeasonWins: 5, lastSeasonLosses: 12, startingQBName: "F. Danforth", startingQBOverall: 74,
                           stars: [TeamPreviewStar(name: "A. Quillon", position: .DE, overall: 87),
                                   TeamPreviewStar(name: "S. Marchetti", position: .CB, overall: 82)],
                           strongestGroup: "DL", weakestGroup: "TE",
                           prestige: 3, styleFit: .motivator,
                           offensiveScheme: .shanahan, defensiveScheme: .pressMan),

        // AFC North
        "BAL": TeamPreview(difficulty: 3, situation: "Contender", ownerPatience: "Moderate", patienceSeasons: 3, marketDescription: "Loyal fan base that expects tough, competitive football", estimatedOVR: 83, estimatedCapSpace: 15, estimatedDraftPicks: 7, coachingBudget: 46, spendingWillingness: 55, lastSeasonWins: 12, lastSeasonLosses: 5, startingQBName: "J. Falkenrath", startingQBOverall: 94,
                           stars: [TeamPreviewStar(name: "C. Wexford", position: .MLB, overall: 89),
                                   TeamPreviewStar(name: "E. Thackery", position: .LT, overall: 84)],
                           strongestGroup: "QB", weakestGroup: "WR",
                           prestige: 4, styleFit: .tactician,
                           offensiveScheme: .rpo, defensiveScheme: .base34),
        "CIN": TeamPreview(difficulty: 3, situation: "Contender", ownerPatience: "Patient", patienceSeasons: 4, marketDescription: "Moderate expectations with a growing fan base", estimatedOVR: 80, estimatedCapSpace: 28, estimatedDraftPicks: 7, coachingBudget: 37, spendingWillingness: 40, lastSeasonWins: 9, lastSeasonLosses: 8, startingQBName: "E. Pallister", startingQBOverall: 91,
                           stars: [TeamPreviewStar(name: "J. Prendergast", position: .WR, overall: 89),
                                   TeamPreviewStar(name: "O. Ballinger", position: .DT, overall: 83)],
                           strongestGroup: "QB", weakestGroup: "OL",
                           prestige: 2, styleFit: .playersCoach,
                           offensiveScheme: .airRaid, defensiveScheme: .tampa2),
        "CLE": TeamPreview(difficulty: 4, situation: "Rebuilding", ownerPatience: "Demanding", patienceSeasons: 2, marketDescription: "Passionate but frustrated fan base demanding results", estimatedOVR: 68, estimatedCapSpace: 12, estimatedDraftPicks: 6, coachingBudget: 40, spendingWillingness: 65, lastSeasonWins: 3, lastSeasonLosses: 14, startingQBName: "L. Medlock", startingQBOverall: 65,
                           stars: [TeamPreviewStar(name: "M. Ashendon", position: .DE, overall: 86),
                                   TeamPreviewStar(name: "T. Corcoran", position: .DT, overall: 80)],
                           strongestGroup: "DL", weakestGroup: "QB",
                           prestige: 3, styleFit: .disciplinarian,
                           offensiveScheme: .powerRun, defensiveScheme: .base43),
        "PIT": TeamPreview(difficulty: 3, situation: "Rising", ownerPatience: "Patient", patienceSeasons: 4, marketDescription: "Blue-collar market that values toughness and consistency", estimatedOVR: 76, estimatedCapSpace: 30, estimatedDraftPicks: 8, coachingBudget: 39, spendingWillingness: 45, lastSeasonWins: 10, lastSeasonLosses: 7, startingQBName: "L. Rittenhouse", startingQBOverall: 76,
                           stars: [TeamPreviewStar(name: "B. Hollowell", position: .OLB, overall: 88),
                                   TeamPreviewStar(name: "K. Nesbitt", position: .SS, overall: 82)],
                           strongestGroup: "LB", weakestGroup: "WR",
                           prestige: 5, styleFit: .disciplinarian,
                           offensiveScheme: .powerRun, defensiveScheme: .base34),

        // AFC South
        "HOU": TeamPreview(difficulty: 3, situation: "Contender", ownerPatience: "Moderate", patienceSeasons: 3, marketDescription: "Large market with growing national media attention", estimatedOVR: 81, estimatedCapSpace: 20, estimatedDraftPicks: 7, coachingBudget: 47, spendingWillingness: 55, lastSeasonWins: 10, lastSeasonLosses: 7, startingQBName: "M. Wimberly", startingQBOverall: 86,
                           stars: [TeamPreviewStar(name: "D. Fairbrother", position: .WR, overall: 87),
                                   TeamPreviewStar(name: "L. Ockleton", position: .DE, overall: 84)],
                           strongestGroup: "QB", weakestGroup: "RB",
                           prestige: 1, styleFit: .innovator,
                           offensiveScheme: .spread, defensiveScheme: .base34),
        "IND": TeamPreview(difficulty: 2, situation: "Rising", ownerPatience: "Patient", patienceSeasons: 4, marketDescription: "Moderate expectations, patient ownership group", estimatedOVR: 75, estimatedCapSpace: 35, estimatedDraftPicks: 8, coachingBudget: 34, spendingWillingness: 40, lastSeasonWins: 8, lastSeasonLosses: 9, startingQBName: "J. Eberhardt", startingQBOverall: 73,
                           stars: [TeamPreviewStar(name: "R. Tolliver", position: .RB, overall: 86),
                                   TeamPreviewStar(name: "W. Braddock", position: .LG, overall: 81)],
                           strongestGroup: "OL", weakestGroup: "DB",
                           prestige: 3, styleFit: .tactician,
                           offensiveScheme: .proPassing, defensiveScheme: .tampa2),
        "JAX": TeamPreview(difficulty: 1, situation: "Rebuilding", ownerPatience: "Very Patient", patienceSeasons: 5, marketDescription: "Low pressure, patient fans rebuilding culture", estimatedOVR: 66, estimatedCapSpace: 50, estimatedDraftPicks: 10, coachingBudget: 24, spendingWillingness: 25, lastSeasonWins: 4, lastSeasonLosses: 13, startingQBName: "B. Vandenberg", startingQBOverall: 78,
                           stars: [TeamPreviewStar(name: "N. Ellery", position: .WR, overall: 82),
                                   TeamPreviewStar(name: "P. Vanterpool", position: .CB, overall: 78)],
                           strongestGroup: "DB", weakestGroup: "OL",
                           prestige: 1, styleFit: .playersCoach,
                           offensiveScheme: .rpo, defensiveScheme: .multiple),
        "TEN": TeamPreview(difficulty: 2, situation: "Rebuilding", ownerPatience: "Patient", patienceSeasons: 4, marketDescription: "Quiet market with room to build without pressure", estimatedOVR: 69, estimatedCapSpace: 42, estimatedDraftPicks: 9, coachingBudget: 29, spendingWillingness: 35, lastSeasonWins: 3, lastSeasonLosses: 14, startingQBName: "D. Yeardley", startingQBOverall: 67,
                           stars: [TeamPreviewStar(name: "H. Brambleton", position: .MLB, overall: 83),
                                   TeamPreviewStar(name: "J. Ormsby", position: .OLB, overall: 79)],
                           strongestGroup: "LB", weakestGroup: "QB",
                           prestige: 2, styleFit: .disciplinarian,
                           offensiveScheme: .powerRun, defensiveScheme: .base43),

        // AFC West
        "DEN": TeamPreview(difficulty: 3, situation: "Rising", ownerPatience: "Moderate", patienceSeasons: 3, marketDescription: "Dedicated fan base expecting a return to prominence", estimatedOVR: 76, estimatedCapSpace: 25, estimatedDraftPicks: 7, coachingBudget: 41, spendingWillingness: 50, lastSeasonWins: 10, lastSeasonLosses: 7, startingQBName: "A. Lemoine", startingQBOverall: 79,
                           stars: [TeamPreviewStar(name: "C. Aldington", position: .CB, overall: 88),
                                   TeamPreviewStar(name: "M. Duquesne", position: .OLB, overall: 83)],
                           strongestGroup: "DB", weakestGroup: "TE",
                           prestige: 4, styleFit: .motivator,
                           offensiveScheme: .shanahan, defensiveScheme: .pressMan),
        "KC":  TeamPreview(difficulty: 4, situation: "Dynasty", ownerPatience: "Moderate", patienceSeasons: 3, marketDescription: "Championship culture, high expectations to sustain success", estimatedOVR: 87, estimatedCapSpace: 10, estimatedDraftPicks: 6, coachingBudget: 48, spendingWillingness: 60, lastSeasonWins: 15, lastSeasonLosses: 2, startingQBName: "S. Osgood", startingQBOverall: 97,
                           stars: [TeamPreviewStar(name: "T. Vanderhoek", position: .TE, overall: 92),
                                   TeamPreviewStar(name: "R. Marchand", position: .DE, overall: 86)],
                           strongestGroup: "QB", weakestGroup: "OL",
                           prestige: 5, styleFit: .innovator,
                           offensiveScheme: .airRaid, defensiveScheme: .multiple),
        "LV":  TeamPreview(difficulty: 4, situation: "Rebuilding", ownerPatience: "Demanding", patienceSeasons: 2, marketDescription: "Flashy market with impatient ownership wanting results fast", estimatedOVR: 70, estimatedCapSpace: 18, estimatedDraftPicks: 7, coachingBudget: 48, spendingWillingness: 70, lastSeasonWins: 4, lastSeasonLosses: 13, startingQBName: "T. Hanneman", startingQBOverall: 66,
                           stars: [TeamPreviewStar(name: "E. Braithwaite", position: .DE, overall: 86),
                                   TeamPreviewStar(name: "C. Ludlow", position: .SS, overall: 79)],
                           strongestGroup: "DL", weakestGroup: "QB",
                           prestige: 4, styleFit: .motivator,
                           offensiveScheme: .option, defensiveScheme: .hybrid),
        "LAC": TeamPreview(difficulty: 3, situation: "Rising", ownerPatience: "Moderate", patienceSeasons: 3, marketDescription: "Large market but competing for attention in LA", estimatedOVR: 77, estimatedCapSpace: 28, estimatedDraftPicks: 7, coachingBudget: 45, spendingWillingness: 50, lastSeasonWins: 11, lastSeasonLosses: 6, startingQBName: "P. Jimison", startingQBOverall: 87,
                           stars: [TeamPreviewStar(name: "G. Maitland", position: .LT, overall: 87),
                                   TeamPreviewStar(name: "A. Sowerby", position: .OLB, overall: 83)],
                           strongestGroup: "QB", weakestGroup: "RB",
                           prestige: 2, styleFit: .tactician,
                           offensiveScheme: .proPassing, defensiveScheme: .base43),

        // NFC East
        "DAL": TeamPreview(difficulty: 5, situation: "Win Now", ownerPatience: "Win Now", patienceSeasons: 1, marketDescription: "The most-watched franchise in the League — maximum media pressure at all times", estimatedOVR: 80, estimatedCapSpace: 12, estimatedDraftPicks: 6, coachingBudget: 57, spendingWillingness: 85, lastSeasonWins: 7, lastSeasonLosses: 10, startingQBName: "R. Frobisher", startingQBOverall: 84,
                           stars: [TeamPreviewStar(name: "W. Ashcombe", position: .WR, overall: 90),
                                   TeamPreviewStar(name: "R. Delacroix", position: .DE, overall: 86)],
                           strongestGroup: "DL", weakestGroup: "DB",
                           prestige: 5, styleFit: .motivator,
                           offensiveScheme: .proPassing, defensiveScheme: .multiple),
        "NYG": TeamPreview(difficulty: 4, situation: "Rebuilding", ownerPatience: "Demanding", patienceSeasons: 2, marketDescription: "NYC market demands winners, legacy franchise with high bar", estimatedOVR: 67, estimatedCapSpace: 22, estimatedDraftPicks: 8, coachingBudget: 46, spendingWillingness: 70, lastSeasonWins: 3, lastSeasonLosses: 14, startingQBName: "W. Rigsbee", startingQBOverall: 64,
                           stars: [TeamPreviewStar(name: "F. Whitmarsh", position: .DE, overall: 84),
                                   TeamPreviewStar(name: "T. Blackwood", position: .DT, overall: 78)],
                           strongestGroup: "DL", weakestGroup: "QB",
                           prestige: 4, styleFit: .disciplinarian,
                           offensiveScheme: .powerRun, defensiveScheme: .base43),
        "PHI": TeamPreview(difficulty: 4, situation: "Contender", ownerPatience: "Demanding", patienceSeasons: 2, marketDescription: "Intense scrutiny, passionate fan base expects championships", estimatedOVR: 84, estimatedCapSpace: 14, estimatedDraftPicks: 6, coachingBudget: 60, spendingWillingness: 75, lastSeasonWins: 14, lastSeasonLosses: 3, startingQBName: "V. Sweetland", startingQBOverall: 90,
                           stars: [TeamPreviewStar(name: "D. Ferrers", position: .DT, overall: 91),
                                   TeamPreviewStar(name: "H. Alcorn", position: .CB, overall: 86),
                                   TeamPreviewStar(name: "M. Trentham", position: .LT, overall: 84)],
                           strongestGroup: "QB", weakestGroup: "TE",
                           prestige: 4, styleFit: .innovator,
                           offensiveScheme: .westCoast, defensiveScheme: .hybrid),
        "WAS": TeamPreview(difficulty: 3, situation: "Rising", ownerPatience: "Moderate", patienceSeasons: 3, marketDescription: "Rebuilding brand in a major market, moderate pressure", estimatedOVR: 73, estimatedCapSpace: 32, estimatedDraftPicks: 8, coachingBudget: 48, spendingWillingness: 50, lastSeasonWins: 12, lastSeasonLosses: 5, startingQBName: "S. Stapleton", startingQBOverall: 82,
                           stars: [TeamPreviewStar(name: "J. Pemberton", position: .WR, overall: 85),
                                   TeamPreviewStar(name: "S. Marlborough", position: .MLB, overall: 82)],
                           strongestGroup: "LB", weakestGroup: "OL",
                           prestige: 4, styleFit: .playersCoach,
                           offensiveScheme: .airRaid, defensiveScheme: .cover3),

        // NFC North
        "CHI": TeamPreview(difficulty: 4, situation: "Rising", ownerPatience: "Demanding", patienceSeasons: 2, marketDescription: "Massive market, title-starved fan base growing impatient", estimatedOVR: 74, estimatedCapSpace: 35, estimatedDraftPicks: 8, coachingBudget: 48, spendingWillingness: 70, lastSeasonWins: 5, lastSeasonLosses: 12, startingQBName: "J. Oldenburg", startingQBOverall: 74,
                           stars: [TeamPreviewStar(name: "V. Ostrander", position: .OLB, overall: 87),
                                   TeamPreviewStar(name: "R. Calloway", position: .CB, overall: 83)],
                           strongestGroup: "LB", weakestGroup: "TE",
                           prestige: 4, styleFit: .disciplinarian,
                           offensiveScheme: .spread, defensiveScheme: .tampa2),
        "DET": TeamPreview(difficulty: 3, situation: "Contender", ownerPatience: "Moderate", patienceSeasons: 3, marketDescription: "Hungry fan base riding momentum, rising expectations", estimatedOVR: 83, estimatedCapSpace: 16, estimatedDraftPicks: 7, coachingBudget: 46, spendingWillingness: 55, lastSeasonWins: 15, lastSeasonLosses: 2, startingQBName: "S. Carrington", startingQBOverall: 88,
                           stars: [TeamPreviewStar(name: "N. Hargreaves", position: .WR, overall: 90),
                                   TeamPreviewStar(name: "B. Sorensen", position: .LT, overall: 85),
                                   TeamPreviewStar(name: "K. Ridgeway", position: .OLB, overall: 83)],
                           strongestGroup: "QB", weakestGroup: "ST",
                           prestige: 3, styleFit: .playersCoach,
                           offensiveScheme: .option, defensiveScheme: .multiple),
        "GB":  TeamPreview(difficulty: 2, situation: "Rising", ownerPatience: "Very Patient", patienceSeasons: 5, marketDescription: "Small market, community-first ownership — unique patience and loyalty", estimatedOVR: 78, estimatedCapSpace: 25, estimatedDraftPicks: 7, coachingBudget: 27, spendingWillingness: 25, lastSeasonWins: 11, lastSeasonLosses: 6, startingQBName: "B. Bidwell", startingQBOverall: 83,
                           stars: [TeamPreviewStar(name: "L. Vandersloot", position: .WR, overall: 86),
                                   TeamPreviewStar(name: "T. Kirkbride", position: .C, overall: 82)],
                           strongestGroup: "OL", weakestGroup: "ST",
                           prestige: 5, styleFit: .playersCoach,
                           offensiveScheme: .westCoast, defensiveScheme: .base34),
        "MIN": TeamPreview(difficulty: 3, situation: "Contender", ownerPatience: "Moderate", patienceSeasons: 3, marketDescription: "Dedicated fans with moderate media presence", estimatedOVR: 80, estimatedCapSpace: 20, estimatedDraftPicks: 7, coachingBudget: 46, spendingWillingness: 55, lastSeasonWins: 14, lastSeasonLosses: 3, startingQBName: "B. Tanberg", startingQBOverall: 80,
                           stars: [TeamPreviewStar(name: "A. Fennimore", position: .WR, overall: 90),
                                   TeamPreviewStar(name: "D. Thorsby", position: .SS, overall: 84)],
                           strongestGroup: "DB", weakestGroup: "OL",
                           prestige: 3, styleFit: .tactician,
                           offensiveScheme: .shanahan, defensiveScheme: .cover3),

        // NFC South
        "ATL": TeamPreview(difficulty: 3, situation: "Rising", ownerPatience: "Moderate", patienceSeasons: 3, marketDescription: "Large market pushing for relevance, growing expectations", estimatedOVR: 75, estimatedCapSpace: 22, estimatedDraftPicks: 7, coachingBudget: 42, spendingWillingness: 50, lastSeasonWins: 8, lastSeasonLosses: 9, startingQBName: "R. Cunliffe", startingQBOverall: 77,
                           stars: [TeamPreviewStar(name: "J. Barlowe", position: .RB, overall: 87),
                                   TeamPreviewStar(name: "C. Winterbourne", position: .WR, overall: 83)],
                           strongestGroup: "RB", weakestGroup: "DL",
                           prestige: 2, styleFit: .motivator,
                           offensiveScheme: .shanahan, defensiveScheme: .cover3),
        "CAR": TeamPreview(difficulty: 1, situation: "Rebuilding", ownerPatience: "Very Patient", patienceSeasons: 5, marketDescription: "Low pressure market with a patient, long-term approach", estimatedOVR: 64, estimatedCapSpace: 55, estimatedDraftPicks: 10, coachingBudget: 24, spendingWillingness: 20, lastSeasonWins: 2, lastSeasonLosses: 15, startingQBName: "F. Gilliland", startingQBOverall: 62,
                           stars: [TeamPreviewStar(name: "E. Hollingsworth", position: .CB, overall: 81),
                                   TeamPreviewStar(name: "M. Prynne", position: .FS, overall: 76)],
                           strongestGroup: "DB", weakestGroup: "QB",
                           prestige: 2, styleFit: .playersCoach,
                           offensiveScheme: .rpo, defensiveScheme: .hybrid),
        "NO":  TeamPreview(difficulty: 3, situation: "Rebuilding", ownerPatience: "Moderate", patienceSeasons: 3, marketDescription: "Passionate city, transitioning from a championship era", estimatedOVR: 72, estimatedCapSpace: 8, estimatedDraftPicks: 7, coachingBudget: 36, spendingWillingness: 50, lastSeasonWins: 5, lastSeasonLosses: 12, startingQBName: "R. Greenhalgh", startingQBOverall: 75,
                           stars: [TeamPreviewStar(name: "R. Tancred", position: .OLB, overall: 85),
                                   TeamPreviewStar(name: "G. Ashby", position: .C, overall: 80)],
                           strongestGroup: "LB", weakestGroup: "WR",
                           prestige: 3, styleFit: .tactician,
                           offensiveScheme: .option, defensiveScheme: .multiple),
        "TB":  TeamPreview(difficulty: 2, situation: "Rebuilding", ownerPatience: "Patient", patienceSeasons: 4, marketDescription: "Moderate market, post-dynasty reset with room to grow", estimatedOVR: 71, estimatedCapSpace: 38, estimatedDraftPicks: 8, coachingBudget: 37, spendingWillingness: 40, lastSeasonWins: 10, lastSeasonLosses: 7, startingQBName: "V. Poteet", startingQBOverall: 80,
                           stars: [TeamPreviewStar(name: "D. Mowbray", position: .WR, overall: 84),
                                   TeamPreviewStar(name: "F. Larkspur", position: .C, overall: 79)],
                           strongestGroup: "OL", weakestGroup: "LB",
                           prestige: 2, styleFit: .playersCoach,
                           offensiveScheme: .option, defensiveScheme: .tampa2),

        // NFC West
        "ARI": TeamPreview(difficulty: 2, situation: "Rebuilding", ownerPatience: "Patient", patienceSeasons: 4, marketDescription: "Moderate market with a patient ownership group", estimatedOVR: 69, estimatedCapSpace: 40, estimatedDraftPicks: 9, coachingBudget: 32, spendingWillingness: 35, lastSeasonWins: 8, lastSeasonLosses: 9, startingQBName: "A. Jorgensen", startingQBOverall: 80,
                           stars: [TeamPreviewStar(name: "S. Everly", position: .TE, overall: 84),
                                   TeamPreviewStar(name: "N. Chadbourne", position: .CB, overall: 79)],
                           strongestGroup: "TE", weakestGroup: "DL",
                           prestige: 2, styleFit: .innovator,
                           offensiveScheme: .spread, defensiveScheme: .hybrid),
        "LAR": TeamPreview(difficulty: 4, situation: "Win Now", ownerPatience: "Demanding", patienceSeasons: 2, marketDescription: "Win now in LA — star-driven franchise under constant spotlight", estimatedOVR: 79, estimatedCapSpace: 10, estimatedDraftPicks: 5, coachingBudget: 57, spendingWillingness: 75, lastSeasonWins: 10, lastSeasonLosses: 7, startingQBName: "N. Willoughby", startingQBOverall: 83,
                           stars: [TeamPreviewStar(name: "K. Ravenel", position: .DT, overall: 90),
                                   TeamPreviewStar(name: "J. Sinclair", position: .WR, overall: 85)],
                           strongestGroup: "DL", weakestGroup: "OL",
                           prestige: 3, styleFit: .innovator,
                           offensiveScheme: .airRaid, defensiveScheme: .pressMan),
        "SF":  TeamPreview(difficulty: 4, situation: "Contender", ownerPatience: "Demanding", patienceSeasons: 2, marketDescription: "Elite expectations, championship-or-bust mentality", estimatedOVR: 85, estimatedCapSpace: 12, estimatedDraftPicks: 6, coachingBudget: 50, spendingWillingness: 75, lastSeasonWins: 6, lastSeasonLosses: 11, startingQBName: "N. Hardesty", startingQBOverall: 85,
                           stars: [TeamPreviewStar(name: "T. Whitlock", position: .TE, overall: 92),
                                   TeamPreviewStar(name: "R. Beaumont", position: .DE, overall: 87),
                                   TeamPreviewStar(name: "M. Callender", position: .FS, overall: 84)],
                           strongestGroup: "TE", weakestGroup: "OL",
                           prestige: 5, styleFit: .tactician,
                           offensiveScheme: .westCoast, defensiveScheme: .cover3),
        "SEA": TeamPreview(difficulty: 3, situation: "Rising", ownerPatience: "Moderate", patienceSeasons: 3, marketDescription: "Deafening home crowd, moderate media market", estimatedOVR: 77, estimatedCapSpace: 24, estimatedDraftPicks: 7, coachingBudget: 41, spendingWillingness: 50, lastSeasonWins: 10, lastSeasonLosses: 7, startingQBName: "J. Vestergaard", startingQBOverall: 79,
                           stars: [TeamPreviewStar(name: "H. Ellersby", position: .MLB, overall: 87),
                                   TeamPreviewStar(name: "P. Ashworth", position: .CB, overall: 83)],
                           strongestGroup: "LB", weakestGroup: "WR",
                           prestige: 3, styleFit: .innovator,
                           offensiveScheme: .rpo, defensiveScheme: .pressMan),
    ]

    static let allTeams: [LeagueTeamDefinition] = [
        // MARK: - AFC East
        LeagueTeamDefinition(name: "Blizzard", city: "Buffalo", abbreviation: "BUF", conference: .AFC, division: .east, mediaMarket: .medium),
        LeagueTeamDefinition(name: "Reefsharks", city: "Miami", abbreviation: "MIA", conference: .AFC, division: .east, mediaMarket: .large),
        LeagueTeamDefinition(name: "Colonials", city: "New England", abbreviation: "NE", conference: .AFC, division: .east, mediaMarket: .large),
        LeagueTeamDefinition(name: "Aviators", city: "New York", abbreviation: "NYJ", conference: .AFC, division: .east, mediaMarket: .large),

        // MARK: - AFC North
        LeagueTeamDefinition(name: "Harbormen", city: "Baltimore", abbreviation: "BAL", conference: .AFC, division: .north, mediaMarket: .medium),
        LeagueTeamDefinition(name: "Riverkings", city: "Cincinnati", abbreviation: "CIN", conference: .AFC, division: .north, mediaMarket: .medium),
        LeagueTeamDefinition(name: "Forgemen", city: "Cleveland", abbreviation: "CLE", conference: .AFC, division: .north, mediaMarket: .medium),
        LeagueTeamDefinition(name: "Steelworks", city: "Pittsburgh", abbreviation: "PIT", conference: .AFC, division: .north, mediaMarket: .medium),

        // MARK: - AFC South
        LeagueTeamDefinition(name: "Astronauts", city: "Houston", abbreviation: "HOU", conference: .AFC, division: .south, mediaMarket: .large),
        LeagueTeamDefinition(name: "Speedway", city: "Indianapolis", abbreviation: "IND", conference: .AFC, division: .south, mediaMarket: .medium),
        LeagueTeamDefinition(name: "Tidewater", city: "Jacksonville", abbreviation: "JAX", conference: .AFC, division: .south, mediaMarket: .small),
        LeagueTeamDefinition(name: "Cumberlands", city: "Tennessee", abbreviation: "TEN", conference: .AFC, division: .south, mediaMarket: .medium),

        // MARK: - AFC West
        LeagueTeamDefinition(name: "Summit", city: "Denver", abbreviation: "DEN", conference: .AFC, division: .west, mediaMarket: .medium),
        LeagueTeamDefinition(name: "Stockyards", city: "Kansas City", abbreviation: "KC", conference: .AFC, division: .west, mediaMarket: .medium),
        LeagueTeamDefinition(name: "Highrollers", city: "Las Vegas", abbreviation: "LV", conference: .AFC, division: .west, mediaMarket: .large),
        LeagueTeamDefinition(name: "Currents", city: "Los Angeles", abbreviation: "LAC", conference: .AFC, division: .west, mediaMarket: .large),

        // MARK: - NFC East
        LeagueTeamDefinition(name: "Longriders", city: "Dallas", abbreviation: "DAL", conference: .NFC, division: .east, mediaMarket: .large),
        LeagueTeamDefinition(name: "Skyline", city: "New York", abbreviation: "NYG", conference: .NFC, division: .east, mediaMarket: .large),
        LeagueTeamDefinition(name: "Bellringers", city: "Philadelphia", abbreviation: "PHI", conference: .NFC, division: .east, mediaMarket: .large),
        LeagueTeamDefinition(name: "Monuments", city: "Washington", abbreviation: "WAS", conference: .NFC, division: .east, mediaMarket: .large),

        // MARK: - NFC North
        LeagueTeamDefinition(name: "Ironworks", city: "Chicago", abbreviation: "CHI", conference: .NFC, division: .north, mediaMarket: .large),
        LeagueTeamDefinition(name: "Motorworks", city: "Detroit", abbreviation: "DET", conference: .NFC, division: .north, mediaMarket: .medium),
        LeagueTeamDefinition(name: "Timberjacks", city: "Green Bay", abbreviation: "GB", conference: .NFC, division: .north, mediaMarket: .small),
        LeagueTeamDefinition(name: "Nordics", city: "Minnesota", abbreviation: "MIN", conference: .NFC, division: .north, mediaMarket: .medium),

        // MARK: - NFC South
        LeagueTeamDefinition(name: "Ironclads", city: "Atlanta", abbreviation: "ATL", conference: .NFC, division: .south, mediaMarket: .large),
        LeagueTeamDefinition(name: "Foxhounds", city: "Carolina", abbreviation: "CAR", conference: .NFC, division: .south, mediaMarket: .medium),
        LeagueTeamDefinition(name: "Krewe", city: "New Orleans", abbreviation: "NO", conference: .NFC, division: .south, mediaMarket: .medium),
        LeagueTeamDefinition(name: "Freebooters", city: "Tampa Bay", abbreviation: "TB", conference: .NFC, division: .south, mediaMarket: .medium),

        // MARK: - NFC West
        LeagueTeamDefinition(name: "Sunspires", city: "Arizona", abbreviation: "ARI", conference: .NFC, division: .west, mediaMarket: .medium),
        LeagueTeamDefinition(name: "Pacifics", city: "Los Angeles", abbreviation: "LAR", conference: .NFC, division: .west, mediaMarket: .large),
        LeagueTeamDefinition(name: "Goldrush", city: "San Francisco", abbreviation: "SF", conference: .NFC, division: .west, mediaMarket: .large),
        LeagueTeamDefinition(name: "Evergreens", city: "Seattle", abbreviation: "SEA", conference: .NFC, division: .west, mediaMarket: .medium),
    ]
}
