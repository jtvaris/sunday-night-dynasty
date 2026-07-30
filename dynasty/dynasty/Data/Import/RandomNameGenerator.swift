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
