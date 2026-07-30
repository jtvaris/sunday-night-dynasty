import Foundation
import SwiftData

@Model
final class Team {
    var id: UUID
    var name: String
    var city: String
    var abbreviation: String

    var conference: Conference
    var division: Division
    var mediaMarket: MediaMarket

    @Relationship(deleteRule: .nullify) var owner: Owner?

    // NOTE: The players relationship will be added once the Player model is available.
    // @Relationship(deleteRule: .nullify) var players: [Player]
    @Relationship(deleteRule: .nullify) var players: [Player]

    var wins: Int
    var losses: Int
    var ties: Int

    /// Wins from the season that just finished, snapshotted by
    /// `WeekAdvancer.startNewSeason` immediately BEFORE `wins` is reset.
    ///
    /// Only the user's franchise had a season archive (`Career.seasonSummaries`),
    /// so the offseason motivation triggers in
    /// `docs/PLAYER_DEVELOPMENT_OVERHAUL_PLAN.md` §2.3 ("team collapsed last
    /// season") were impossible to evaluate for the other 31 clubs. This is the
    /// cheap fix — one season back, league-wide, not a full archive (§3 keeps
    /// per-team season archives out of scope).
    ///
    /// `-1` means "no completed season on record yet" (a brand-new league, or a
    /// save created before this property existed); callers must treat it as
    /// "unknown", never as 0 wins. Default-value stored property, never in
    /// `init` → safe lightweight migration.
    var lastSeasonWins: Int = -1

    /// Losses from the season that just finished. Same contract as
    /// `lastSeasonWins`, including the `-1` "unknown" sentinel.
    var lastSeasonLosses: Int = -1

    /// Whether `lastSeasonWins` / `lastSeasonLosses` hold a real completed season.
    var hasLastSeasonRecord: Bool {
        lastSeasonWins >= 0 && lastSeasonLosses >= 0
    }

    /// The offensive scheme this franchise ran the last time camp opened
    /// (`OffensiveScheme.rawValue`). Snapshotted at the `.trainingCamp` phase
    /// and compared against the current OC's scheme on the next pass — that
    /// diff is the only scheme-CHANGE signal in the domain
    /// (`docs/PLAYER_DEVELOPMENT_OVERHAUL_PLAN.md` §1.3 defect #4: nothing ever
    /// taxed or decayed `Player.schemeFamiliarity` on coordinator turnover).
    ///
    /// `nil` means "never recorded" — a brand-new league or a save created
    /// before this property existed. The first camp after that only records;
    /// it never fires an install year, so no existing save is retroactively
    /// taxed. Default-value stored property, never in `init` → safe lightweight
    /// migration.
    var lastOffensiveSchemeRaw: String? = nil

    /// The defensive scheme this franchise ran at the last camp
    /// (`DefensiveScheme.rawValue`). Same contract as `lastOffensiveSchemeRaw`.
    var lastDefensiveSchemeRaw: String? = nil

    /// The season an install year is in effect for: the whole of that season's
    /// `learnScheme` work (camp AND the weekly in-season reps) runs at
    /// ×`VersatilityDevelopmentEngine.schemeInstallIntensityBonus` because the
    /// staff is teaching a brand-new system from scratch (plan §2.9.2,
    /// `DEVELOPMENT_NFL_REFERENCE.md` §5: "an OC change costs a measurable
    /// install year"). `0` = no install pending.
    var schemeInstallSeason: Int = 0

    /// Total salary cap in thousands of dollars (default: $265,000,000 → 265_000, 2026 projection).
    var salaryCap: Int

    /// Current cap usage in thousands of dollars.
    var currentCapUsage: Int

    // MARK: - Computed Properties

    /// Full franchise name combining city and team name (e.g. "Kansas City Chiefs").
    var fullName: String {
        "\(city) \(name)"
    }

    /// Win-loss record string. Includes ties only when at least one tie has occurred.
    var record: String {
        ties > 0 ? "\(wins)-\(losses)-\(ties)" : "\(wins)-\(losses)"
    }

    /// Remaining cap space in thousands of dollars.
    var availableCap: Int {
        salaryCap - currentCapUsage
    }

    init(
        id: UUID = UUID(),
        name: String,
        city: String,
        abbreviation: String,
        conference: Conference,
        division: Division,
        mediaMarket: MediaMarket,
        owner: Owner? = nil,
        players: [Player] = [],
        wins: Int = 0,
        losses: Int = 0,
        ties: Int = 0,
        salaryCap: Int = 265_000,
        currentCapUsage: Int = 0
    ) {
        self.id = id
        self.name = name
        self.city = city
        self.abbreviation = abbreviation
        self.conference = conference
        self.division = division
        self.mediaMarket = mediaMarket
        self.owner = owner
        self.players = players
        self.wins = wins
        self.losses = losses
        self.ties = ties
        self.salaryCap = salaryCap
        self.currentCapUsage = currentCapUsage
    }
}
