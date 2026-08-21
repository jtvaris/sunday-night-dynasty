import Foundation

/// The ONE answer to "how good is this roster", for every screen that prints it.
///
/// ## Why this exists
///
/// A QA pass on a live career found the same label carrying two different
/// numbers on two screens of the same save:
///
/// * the team picker said **Roster OVR 76** — `TeamBrowseCatalog` averages the
///   template's `role == "starter"` men, deliberately, so that "the number in the
///   picker is the number the roster screen will report";
/// * the career dashboard said **Roster OVR 68** — the whole-roster mean, which
///   includes the camp tail.
///
/// Eight points apart, one label. And the gap is not a rounding artefact: an
/// offseason roster carries up to `CampRosterEngine.campRosterTarget` (87) men,
/// so the whole-roster mean is dragged down by forty bodies who will never take
/// a snap. It also fed the owner's goals and the UI's quality ladders, which is
/// why the fix queue asks for the rebase rather than for a relabel.
///
/// ## The definition
///
/// The mean `overall` of the best 22 — eleven on each side of the ball — which is
/// the same shape `DepthChart.teamOverall` produces from an assigned lineup and
/// the same one `MultiSeasonSmokeTest`'s competitive-balance diagnostic measures
/// the league with. Where a real depth chart is available, prefer it: this is the
/// answer for the screens that have a roster and no lineup.
///
/// It is deliberately NOT position-aware. A position-aware version would be a
/// better number and a fourth definition, and this codebase's recurring defect is
/// exactly that — a quantity spelled differently in each place that needs it.
/// When a position-aware answer is wanted, it belongs HERE, once.
enum RosterStrength {

    /// How many men count as "the team on the field".
    static let starterCount = 22

    /// Mean `overall` of the best ``starterCount`` players, rounded down.
    /// Returns `nil` for an empty roster rather than a misleading zero.
    static func starterAverage(_ players: [Player]) -> Int? {
        guard !players.isEmpty else { return nil }
        let best = players.map(\.overall).sorted(by: >).prefix(starterCount)
        return best.reduce(0, +) / best.count
    }

    /// Same, for a subset the caller has already filtered (a projection of who
    /// would remain after expiries, say). Kept as one call so a caller cannot
    /// accidentally average the survivors a different way from the baseline it
    /// is comparing them against.
    static func starterAverage(of players: [Player], keeping predicate: (Player) -> Bool) -> Int? {
        starterAverage(players.filter(predicate))
    }
}
