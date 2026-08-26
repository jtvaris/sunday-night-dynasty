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
/// on the CROSS PRODUCT: all 195 × 349 male and 40 × 349 female combinations are
/// Levenshtein ≥ 3 from every name in `tools/league-data/raw/league_raw_2026.json` plus the
/// notable-past list (`docs/ANONYMIZATION_SPEC.md` §1 guard 1), no surname is a
/// real surname or a one-edit variant of one, and no given name is a real
/// surname. `scan_bundle.py` gate E re-asserts all three on the source of truth
/// — this file — on every bundle-gate run, so a hand edit here fails the gate
/// rather than shipping quietly.
///
/// ## Why the pools are this large
///
/// They were 55 × 55, and a league is ~1 700 players plus a ~350-man class every
/// spring. Against 3 025 pairs that put roughly thirty men on each surname, so
/// every list the player scans by name had duplicates in it — two WRs called
/// Braithwaite in one position group, three Tanguays in an eleven-man draft
/// class, an assistant head coach and a defensive coordinator both called
/// Goddard. Growing the pools is the only lever that reaches the callers which
/// draw a bare `randomName()` (`LeagueGenerator`, `CoachingEngine`,
/// `ScoutingEngine`); `uniqueName` below handles the cohorts that thread a
/// `used` set. Every addition went through gate E before it landed here.
enum RandomNameGenerator {

    // MARK: - First Names

    private static let firstNames: [String] = [
        "Abel", "Alaric", "Alistair", "Alonso", "Amadou",
        "Amias", "Anders", "Ansel", "Archer", "Aurelio",
        "Barnaby", "Barrett", "Batiste", "Benicio", "Bertram",
        "Blaise", "Bodie", "Boone", "Bram", "Brixton",
        "Callum", "Casimir", "Caspian", "Cassian", "Cedric",
        "Cirilo", "Cormac", "Cyrus", "Dabney", "Darnell",
        "Dashiell", "Dashon", "Davion", "Deacon", "Declan",
        "Delphin", "Demetri", "Dermot", "Deshun", "Desmond",
        "Dimitri", "Donovan", "Dorian", "Eamon", "Easton",
        "Elias", "Ellery", "Elric", "Emeric", "Emrys",
        "Ephraim", "Everett", "Ezekiel", "Fabian", "Faron",
        "Fenwick", "Ferdinand", "Finnian", "Fitzroy", "Florian",
        "Gareth", "Gaspard", "Gideon", "Godfrey", "Grayling",
        "Gustav", "Hamish", "Harlan", "Hawthorne", "Hayden",
        "Hezekiah", "Hollis", "Horatio", "Hugo", "Idris",
        "Ignatius", "Immanuel", "Isaias", "Isandro", "Ivo",
        "Jabari", "Jace", "Jaden", "Jamari", "Jarreth",
        "Jarvis", "Jeremiah", "Jericho", "Jethro", "Joaquin",
        "Jonas", "Jorvik", "Judah", "Kaleo", "Kason",
        "Kenji", "Kester", "Killian", "Kolbe", "Konrad",
        "Kwabena", "Kwame", "Lachlan", "Lazarus", "Leander",
        "Lemuel", "Linus", "Lorenzo", "Lucian", "Lysander",
        "Maceo", "Magnus", "Malachi", "Marcellus", "Mathias",
        "Merrick", "Mordecai", "Nehemiah", "Nikoa", "Nikolai",
        "Nolan", "Norbert", "Obadiah", "Octavian", "Odalric",
        "Orrin", "Orson", "Osman", "Osric", "Oswin",
        "Pellham", "Percival", "Peregrine", "Phineas", "Quenton",
        "Quillon", "Quinton", "Rafferty", "Ramiro", "Rasheed",
        "Reginald", "Remus", "Rexford", "Ricardo", "Rigoberto",
        "Roderic", "Rodrigo", "Rohan", "Roman", "Ronin",
        "Rufus", "Sebastien", "Seneca", "Serafin", "Severin",
        "Silas", "Sincere", "Soren", "Stellan", "Sterling",
        "Sylvan", "Tadeo", "Tavish", "Thaddeus", "Tiberius",
        "Tobias", "Torrance", "Ulric", "Ulysses", "Umberto",
        "Valentin", "Vasco", "Vaughan", "Verner", "Vittorio",
        "Wade", "Waylon", "Wendell", "Wilkes", "Wilkin",
        "Wolfgang", "Wyatt", "Wystan", "Xander", "Xavion",
        "Yannick", "Yerik", "Yohance", "Yusuf", "Zachariah",
        "Zamir", "Zander", "Zavier", "Zebedee", "Zeno"
    ]

    /// Given names for the female coach candidates the hiring market invents
    /// (`CoachingEngine.femaleCoachShare`). Players and owners stay male, so
    /// nothing else draws from here.
    ///
    /// Crossed with the SAME `lastNames` array as `firstNames`, which means the
    /// reachable space grows by a second 40 × 349 product — held to the identical
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
        "Abernathy", "Ackerly", "Adeyemi", "Albinati", "Aldecoa",
        "Ambrosini", "Arbogast", "Arredondo", "Ashcombe", "Ashworth",
        "Atherton", "Auchter", "Aylesworth", "Babbington", "Balfour",
        "Barlowe", "Barrientos", "Barrowman", "Bascomb", "Baumgartner",
        "Beauchemin", "Beddingfield", "Bellandi", "Belrose", "Beneventi",
        "Bergstrom", "Bertolucci", "Bexley", "Bickerstaff", "Billingsley",
        "Birchall", "Blakemore", "Bletchley", "Boateng", "Boissonneault",
        "Bolliger", "Bonaventure", "Bosworth", "Bourgeois", "Braithwaite",
        "Bramhall", "Brancaleone", "Brancaster", "Bridgeford", "Brightwell",
        "Brindlecombe", "Broadwater", "Brockway", "Broughton", "Burlingame",
        "Burnleigh", "Caballero", "Cadwallader", "Calderaro", "Camberwell",
        "Campanella", "Carbury", "Carranza", "Cartwright", "Cavalieri",
        "Chadwick", "Charbonneau", "Charnwood", "Chatterton", "Chelmsford",
        "Cifuentes", "Cimarosa", "Clatterbuck", "Clayborne", "Coldwater",
        "Colgrove", "Coriolano", "Cranbrook", "Crisanti", "Crowhurst",
        "Cunliffe", "Cuthbertson", "Dalgaard", "Danquah", "Darlington",
        "Derringer", "Desrochers", "Deverell", "Dinsmore", "Dovecote",
        "Drakeford", "Dumoulin", "Dunsmore", "Eastwick", "Edgerton",
        "Ekstrand", "Ellingham", "Elmsworth", "Engelhardt", "Escalante",
        "Everleigh", "Falconbridge", "Falkenrath", "Farnsworth", "Featherstone",
        "Fernsby", "Ferrante", "Fleetwood", "Follansbee", "Fontanelli",
        "Fordham", "Fothergill", "Fournier", "Foxcroft", "Frobisher",
        "Gagliardi", "Galbraith", "Garrowby", "Gaudreault", "Gildersleeve",
        "Gjertsen", "Glenmore", "Goddard", "Goldthwaite", "Goodfellow",
        "Granholm", "Gravesend", "Greenhalgh", "Grimsby", "Guerrero",
        "Guillemette", "Hallowell", "Halvorsen", "Hambleton", "Harkness",
        "Harrowgate", "Hartfield", "Hartwell", "Hasbrouck", "Hausmann",
        "Havelock", "Hawksworth", "Haythorne", "Heathcote", "Hedgepeth",
        "Hedstrom", "Henshaw", "Herrington", "Hidalgo", "Highmore",
        "Hinsdale", "Hollingsworth", "Hopewell", "Hornsby", "Hoshino",
        "Hubbell", "Huddleston", "Izquierdo", "Jaramillo", "Jessup",
        "Kahananui", "Kaltenbach", "Kanemoto", "Karrington", "Kealoha",
        "Kellerman", "Kenilworth", "Kestrelwood", "Kimbrough", "Kingsbury",
        "Kirchner", "Kirkbride", "Kjellberg", "Klingman", "Lachapelle",
        "Lagerqvist", "Lamontagne", "Landseer", "Langstrom", "Larocque",
        "Larrabee", "Lathrop", "Latimer", "Laurelwood", "Lindenmuth",
        "Lindqvist", "Linscott", "Litchfield", "Littlefield", "Lockridge",
        "Lombardini", "Longstaff", "Lovegrove", "Ludlow", "Lymington",
        "Maddocks", "Maisonneuve", "Makuakane", "Malatesta", "Maldonado",
        "Marchbanks", "Marchesini", "Marchetti", "Marsden", "Matsubara",
        "Mazzarella", "Mensah", "Milbourne", "Millgate", "Montalvo",
        "Montcalm", "Montfort", "Moorcroft", "Morgenstern", "Mortlake",
        "Nadeau", "Nakagawa", "Netherby", "Newcombe", "Nordstrom",
        "Northcote", "Oakhurst", "Oberlander", "Ogletree", "Oldcastle",
        "Olivares", "Orrington", "Osgood", "Ottinger", "Overton",
        "Oyelaran", "Padgett", "Palfrey", "Pankhurst", "Pellegrini",
        "Pemberton", "Pennington", "Peralta", "Perrault", "Pettigrew",
        "Pfaffenbach", "Pickering", "Pilkington", "Plimpton", "Ponsonby",
        "Poundstone", "Prideaux", "Quaglia", "Quarterman", "Quimby",
        "Quintanilla", "Radcliffe", "Rademacher", "Ramsbottom", "Ravensworth",
        "Regalado", "Rennick", "Rivenhall", "Rookwood", "Rosewater",
        "Rothbury", "Rowntree", "Rutherford", "Ryecroft", "Saddleworth",
        "Saltonstall", "Sandoval", "Sandringham", "Sanfilippo", "Sankofa",
        "Satterfield", "Scarpetta", "Schoenfeld", "Sedgewick", "Selby",
        "Sharpsteen", "Shelburne", "Sherbourne", "Shortridge", "Silverthorne",
        "Skelmersdale", "Smallwood", "Solberg", "Southgate", "Sparrowhawk",
        "Stapleton", "Steinmetz", "Sternhagen", "Stillwater", "Stonebridge",
        "Strathmore", "Summerfield", "Sundqvist", "Swinburne", "Tanguay",
        "Tarleton", "Tattersall", "Tejeda", "Thistlewood", "Thornbury",
        "Thorncastle", "Ticehurst", "Tillinghast", "Tolliver", "Trebeck",
        "Tremblay", "Trenchard", "Truesdale", "Tuckerman", "Underhill",
        "Urbina", "Vaillancourt", "Valdespino", "Valenzuela", "Vanbrough",
        "Vancleave", "Vandenberg", "Vandermeer", "Vanhorn", "Vanterpool",
        "Verstraete", "Verwood", "Vestergaard", "Villalobos", "Villiers",
        "Vondracek", "Wachtmeister", "Wadsworth", "Wainwright", "Waldegrave",
        "Warburton", "Wardlow", "Waterhouse", "Weatherby", "Wellingford",
        "Wentworth", "Wetherell", "Whitcombe", "Wickersham", "Willoughby",
        "Winchester", "Windermere", "Winterbourne", "Wolcott", "Woodbine",
        "Woolridge", "Wrenfield", "Wycliffe", "Yarborough", "Yardley",
        "Yatesbury", "Yelverton", "Zabrowski", "Zamarripa"
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

    /// How many men in one cohort may share a surname before the draw is
    /// rejected. Unique full names were never enough: the draft feed, the cut
    /// list and the depth chart all abbreviate to "N. Abernathy", which names
    /// every Abernathy on the board equally. Two is deliberate rather than one —
    /// real squads do carry the occasional shared surname, and a hard ban reads
    /// as machine-generated in the other direction.
    private static let surnameQuota = 2

    /// The same cap on given names. Surnames were the ambiguity problem; first
    /// names are a texture problem — 350 prospects drawn from 195 given names
    /// put as many as ten men called Kenji on one board, and a list where six of
    /// eight share a colleague's first name reads as generated rather than
    /// scouted.
    ///
    /// Three rather than two: measured over 200 full classes, a cap of two runs
    /// the rejection sampler out of road a few hundred times per class and drops
    /// it into the cross-product walk below, which is the slow path this design
    /// exists to avoid. Three never reaches that walk.
    private static let givenNameQuota = 3

    /// Draws a full name no caller has taken yet, recording it in `used`.
    ///
    /// The two halves are drawn independently, so a cohort the size of a draft
    /// class (350) collides by birthday unless something stops it — two different
    /// men called Nehemiah Abernathy sitting on the same board, and eleven-man
    /// rookie classes that came out with three Tanguays in them. Uniqueness on
    /// the full name alone did not fix that; `surnameQuota` and `givenNameQuota`
    /// are the parts that do.
    ///
    /// Rejection sampling is the fast path. When it stops paying — a crowded
    /// pool rather than bad luck — the cross product is walked from a random
    /// offset instead, so a free pair is found whenever one still exists.
    static func uniqueName(
        female: Bool = false,
        used: inout Set<String>
    ) -> (first: String, last: String) {
        for _ in 0..<16 {
            let name = randomName(female: female)
            if claim(first: name.first, last: name.last, in: &used) { return name }
        }

        let firsts = female ? femaleFirstNames : firstNames
        let combinations = firsts.count * lastNames.count
        let offset = Int.random(in: 0..<combinations)
        for step in 0..<combinations {
            let index = (offset + step) % combinations
            let first = firsts[index / lastNames.count]
            let last = lastNames[index % lastNames.count]
            if claim(first: first, last: last, in: &used) { return (first, last) }
        }

        // Every pair the quota still allows is spoken for. Callers ask for a
        // fraction of what the product holds, so this is unreachable at the
        // shipped cohort sizes.
        return randomName(female: female)
    }

    /// Takes the full name plus a slot against each half's quota, or takes
    /// nothing at all and reports the pair unavailable.
    ///
    /// Both slots are located before either is written. Taking the given name
    /// and then finding the surname full would burn a slot on a man who was
    /// never issued, and those leaks accumulate over a whole draft class.
    ///
    /// The slot markers share the caller's `used` set. That set is opaque to
    /// every caller — they hand in an empty one and never read it back — and a
    /// marker can never be mistaken for a full name because it is joined by "@"
    /// or "#" rather than a space, so the quotas need no second parameter.
    private static func claim(
        first: String,
        last: String,
        in used: inout Set<String>
    ) -> Bool {
        guard !used.contains("\(first) \(last)"),
              let givenSlot = freeSlot(for: "\(first)@", upTo: givenNameQuota, in: used),
              let surnameSlot = freeSlot(for: "\(last)#", upTo: surnameQuota, in: used)
        else { return false }
        used.insert(givenSlot)
        used.insert(surnameSlot)
        used.insert("\(first) \(last)")
        return true
    }

    /// The lowest marker in a quota's run that nobody holds, or nil when the
    /// run is full.
    private static func freeSlot(
        for prefix: String,
        upTo quota: Int,
        in used: Set<String>
    ) -> String? {
        for slot in 1...quota where !used.contains("\(prefix)\(slot)") {
            return "\(prefix)\(slot)"
        }
        return nil
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
