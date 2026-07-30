import Foundation

/// Names for everybody the game invents at runtime — draft classes, UDFAs, free
/// agents, replacement staff — in every league source, the Fixed 2026 template
/// included.
///
/// ## Why these pools are fictional
///
/// A given-name array and the surname array are drawn from INDEPENDENTLY, so the
/// reachable space is the whole cross product, not the pairs anybody wrote down.
/// The previous pools
/// were seeded with real NFL names (`Travis`/`Kelce`, `Micah`/`Parsons`,
/// `Davante`/`Adams`), and cross-producing them reconstructed the exact full
/// names of 68 players on the 2026 rosters — names the app then displayed as
/// generated people. `scan_bundle.py` could not see it either: it matches whole
/// names inside one string, and a given-name array and a surname array in
/// separate literals never form one.
///
/// So every pool here is fictional and blocklist-checked, and the constraint is
/// on the CROSS PRODUCT: all 55 × 55 male and 40 × 55 female combinations are
/// Levenshtein ≥ 3 from every name in `tools/league-data/raw/league_raw_2026.json` plus the
/// notable-past list (`docs/ANONYMIZATION_SPEC.md` §1 guard 1), no surname is a
/// real surname or a one-edit variant of one, and no given name is a real
/// surname. `scan_bundle.py` gate E re-asserts all three on the source of truth
/// — this file — on every bundle-gate run, so a hand edit here fails the gate
/// rather than shipping quietly.
enum RandomNameGenerator {

    // MARK: - First Names

    private static let firstNames: [String] = [
        "Alaric", "Alonso", "Barrett", "Bodie", "Boone",
        "Bram", "Brixton", "Callum", "Dashiell", "Davion",
        "Declan", "Demetri", "Deshun", "Easton", "Elias",
        "Ezekiel", "Faron", "Finnian", "Harlan", "Hayden",
        "Isaias", "Jace", "Jaden", "Jamari", "Jarreth",
        "Jeremiah", "Jonas", "Judah", "Kaleo", "Kason",
        "Kenji", "Kester", "Kwabena", "Leander", "Nehemiah",
        "Norbert", "Odalric", "Orrin", "Osman", "Osric",
        "Rafferty", "Ramiro", "Ricardo", "Rohan", "Roman",
        "Seneca", "Sincere", "Tobias", "Wade", "Waylon",
        "Wilkes", "Wyatt", "Xander", "Zachariah", "Zavier"
    ]

    /// Given names for the female coach candidates the hiring market invents
    /// (`CoachingEngine.femaleCoachShare`). Players and owners stay male, so
    /// nothing else draws from here.
    ///
    /// Crossed with the SAME `lastNames` array as `firstNames`, which means the
    /// reachable space grows by a second 40 × 55 product — held to the identical
    /// gate-E rule, and checked the same way.
    private static let femaleFirstNames: [String] = [
        "Alicia", "Angela", "Brianna", "Bridget", "Camille",
        "Carmen", "Colleen", "Cynthia", "Danielle", "Deborah",
        "Denise", "Felicia", "Gloria", "Ingrid", "Janelle",
        "Justine", "Keisha", "Latasha", "Marisol", "Marlene",
        "Michelle", "Monica", "Nadia", "Noelle", "Octavia",
        "Patrice", "Priya", "Regina", "Renee", "Rochelle",
        "Rosalind", "Sabrina", "Simone", "Stephanie", "Tamara",
        "Teresa", "Valerie", "Vanessa", "Yolanda", "Yvette"
    ]

    // MARK: - Last Names

    private static let lastNames: [String] = [
        "Abernathy", "Ackerly", "Arbogast", "Auchter", "Balfour",
        "Bascomb", "Bolliger", "Bonaventure", "Bourgeois", "Braithwaite",
        "Broadwater", "Brockway", "Cartwright", "Colgrove", "Crisanti",
        "Cunliffe", "Derringer", "Engelhardt", "Ferrante", "Frobisher",
        "Goddard", "Hambleton", "Hedgepeth", "Henshaw", "Hinsdale",
        "Hopewell", "Hubbell", "Jaramillo", "Karrington", "Kirkbride",
        "Klingman", "Larrabee", "Latimer", "Laurelwood", "Littlefield",
        "Lockridge", "Lovegrove", "Maddocks", "Marchetti", "Marsden",
        "Nadeau", "Ogletree", "Ottinger", "Pankhurst", "Quarterman",
        "Shelburne", "Smallwood", "Tanguay", "Truesdale", "Vandenberg",
        "Vanterpool", "Vestergaard", "Waterhouse", "Winchester", "Yarborough"
    ]

    // MARK: - Public

    /// Returns a random first and last name tuple.
    ///
    /// `female` only swaps which given-name pool is read; the surname comes from
    /// the same array either way, and exactly two draws happen in either case.
    static func randomName(female: Bool = false) -> (first: String, last: String) {
        let first = (female ? femaleFirstNames : firstNames).randomElement()!
        let last = lastNames.randomElement()!
        return (first, last)
    }

    /// R27: Seeded variant — returns a deterministic name for a given generator state.
    static func randomName<G: RandomNumberGenerator>(
        female: Bool = false,
        using generator: inout G
    ) -> (first: String, last: String) {
        let first = (female ? femaleFirstNames : firstNames).randomElement(using: &generator)!
        let last = lastNames.randomElement(using: &generator)!
        return (first, last)
    }
}

// MARK: - Hometowns

/// Where a generated player is from.
///
/// `Player.hometownState` / `hometownCity` have existed since the FA-drama brief
/// and **nothing ever wrote them**: `DraftEngine.copyProspectMetadata` carries the
/// pair across the draft boundary, but the prospect side is nil too, so the whole
/// hometown layer — `HometownDetector`'s 5 % regional discount, the "comes home to
/// play in the South" storyline, `PlayerPreferenceEngine`'s family/home motivation
/// term — has been dead code guarded by `hometownState != nil`. This is the
/// generator that turns it on for the veterans a random league is built from.
///
/// Deliberately NOT in `HometownDetector`: that type answers "does this state sit
/// in that team's region", which is a *rule*. This is a content pool, and content
/// pools live next to the name pools they are drawn beside.
enum HometownGenerator {

    /// State weights are an editorial approximation of where NFL players are
    /// actually born — California, Texas, Florida and Georgia together produce
    /// roughly a third of the league, and the tail runs a long way down. A flat
    /// draw over 30-odd states would have put as many players in Nebraska as in
    /// Texas and made the regional storylines read as noise.
    ///
    /// **Every state here is a key of `HometownDetector.stateRegions`.** That is
    /// a hard requirement, not a coincidence: a state the detector cannot map to
    /// a region returns `nil` from `region(for:)`, which silently disables the
    /// discount and the storyline for everyone born there. Adding a state below
    /// without adding it there ships a hometown that can never be a hometown.
    ///
    /// Cities are real places, which is fine and unrelated to
    /// `ANONYMIZATION_SPEC.md` — that document is about not naming real *people*,
    /// and the league's own team cities have always been real.
    private static let hometowns: [(state: String, weight: Double, cities: [String])] = [
        ("California", 10.0, ["Los Angeles", "Long Beach", "Oakland", "Fresno", "San Diego", "Sacramento"]),
        ("Texas", 10.0, ["Houston", "Dallas", "Austin", "San Antonio", "Fort Worth", "Beaumont"]),
        ("Florida", 9.0, ["Miami", "Tampa", "Orlando", "Jacksonville", "Fort Lauderdale", "Pensacola"]),
        ("Georgia", 7.0, ["Atlanta", "Savannah", "Columbus", "Macon", "Augusta"]),
        ("Ohio", 4.0, ["Cleveland", "Cincinnati", "Columbus", "Toledo", "Akron"]),
        ("Louisiana", 3.5, ["New Orleans", "Baton Rouge", "Shreveport", "Lafayette"]),
        ("North Carolina", 3.2, ["Charlotte", "Raleigh", "Greensboro", "Durham"]),
        ("Pennsylvania", 3.0, ["Philadelphia", "Pittsburgh", "Harrisburg", "Allentown"]),
        ("Alabama", 3.0, ["Birmingham", "Mobile", "Montgomery", "Huntsville"]),
        ("Illinois", 3.0, ["Chicago", "Rockford", "Peoria", "Springfield"]),
        ("New Jersey", 2.6, ["Newark", "Camden", "Paterson", "Trenton"]),
        ("Virginia", 2.5, ["Virginia Beach", "Richmond", "Norfolk", "Hampton"]),
        ("Michigan", 2.5, ["Detroit", "Flint", "Grand Rapids", "Lansing"]),
        ("New York", 2.5, ["Brooklyn", "The Bronx", "Buffalo", "Rochester", "Yonkers"]),
        ("South Carolina", 2.2, ["Columbia", "Charleston", "Greenville", "Rock Hill"]),
        ("Tennessee", 2.2, ["Memphis", "Nashville", "Knoxville", "Chattanooga"]),
        ("Mississippi", 2.0, ["Jackson", "Gulfport", "Hattiesburg", "Meridian"]),
        ("Maryland", 2.0, ["Baltimore", "Silver Spring", "Landover", "Annapolis"]),
        ("Arizona", 1.6, ["Phoenix", "Tucson", "Mesa", "Glendale"]),
        ("Washington", 1.5, ["Seattle", "Tacoma", "Spokane", "Federal Way"]),
        ("Missouri", 1.5, ["St. Louis", "Kansas City", "Springfield", "Columbia"]),
        ("Indiana", 1.2, ["Indianapolis", "Fort Wayne", "Gary", "Evansville"]),
        ("Wisconsin", 1.1, ["Milwaukee", "Madison", "Racine", "Green Bay"]),
        ("Minnesota", 1.1, ["Minneapolis", "St. Paul", "Duluth", "Bloomington"]),
        ("Oklahoma", 1.1, ["Oklahoma City", "Tulsa", "Norman", "Lawton"]),
        ("Arkansas", 1.0, ["Little Rock", "Fort Smith", "Pine Bluff", "Fayetteville"]),
        ("Colorado", 1.0, ["Denver", "Aurora", "Colorado Springs", "Pueblo"]),
        ("Massachusetts", 0.8, ["Boston", "Springfield", "Brockton", "Worcester"]),
        ("Utah", 0.7, ["Salt Lake City", "Provo", "Ogden", "West Valley City"]),
        ("Oregon", 0.7, ["Portland", "Eugene", "Salem", "Gresham"]),
        ("Nevada", 0.6, ["Las Vegas", "Reno", "Henderson", "North Las Vegas"]),
        ("Kansas", 0.6, ["Wichita", "Topeka", "Kansas City", "Olathe"]),
        ("Hawaii", 0.5, ["Honolulu", "Waipahu", "Kahului", "Hilo"]),
        ("Iowa", 0.5, ["Des Moines", "Cedar Rapids", "Davenport", "Waterloo"]),
        ("Connecticut", 0.4, ["Hartford", "Bridgeport", "New Haven", "Stamford"]),
        ("Nebraska", 0.3, ["Omaha", "Lincoln", "Bellevue", "Grand Island"]),
        ("New Hampshire", 0.1, ["Manchester", "Nashua", "Concord"]),
        ("Maine", 0.1, ["Portland", "Lewiston", "Bangor"]),
    ]

    private static let totalWeight = hometowns.reduce(0) { $0 + $1.weight }

    /// A weighted state plus a uniform city inside it.
    static func randomHometown() -> (state: String, city: String) {
        var generator = SystemRandomNumberGenerator()
        return randomHometown(using: &generator)
    }

    /// Seeded variant — same shape as `randomName(using:)`, so a seeded league
    /// generator produces the same hometowns twice.
    static func randomHometown<G: RandomNumberGenerator>(
        using generator: inout G
    ) -> (state: String, city: String) {
        var roll = Double.random(in: 0..<totalWeight, using: &generator)
        for entry in hometowns {
            roll -= entry.weight
            if roll < 0 {
                return (entry.state, entry.cities.randomElement(using: &generator)!)
            }
        }
        // Floating-point tail only — the loop consumes the whole range.
        let last = hometowns[hometowns.count - 1]
        return (last.state, last.cities[0])
    }
}
