import Foundation

/// The 32 franchises the new-career team picker browses, for ONE league source.
///
/// The picker used to read `LeagueTeamData.allTeams` + `LeagueTeamData.previews`
/// directly, which is correct only for the random league. A fixed template
/// carries its own identities (the publish profile renames every nickname —
/// "Arizona Sunspires"), its own 2025 records, its own rosters and its own pick
/// ownership, so browsing it against the static preview table would show the
/// player numbers that have nothing to do with the league he is about to start.
///
/// This type is the adapter: one catalog per `LeagueSource`, holding the team
/// definitions to list and the `TeamPreview` to show for each of them.
///
/// ## What comes from where (template catalogs)
///
/// | Preview field | Source |
/// |---|---|
/// | record, roster OVR, starting QB, draft picks | the template |
/// | cap space | `LeagueTemplateImporter.capTarget` — the same number the import will produce |
/// | difficulty, situation | derived from the template's roster + record (see below) |
/// | owner patience, market copy, coaching budget, lock | `LeagueTeamData` — franchise/market facts a roster snapshot does not change |
struct TeamBrowseCatalog {

    /// Which league source this catalog describes. Career creation reads it
    /// back, so a template that failed to load can degrade to `.generated`
    /// and still record what was actually started.
    let source: LeagueSource

    /// Team definitions to list, in catalog order.
    let teams: [LeagueTeamDefinition]

    /// Abbreviation → preview.
    private let previews: [String: TeamPreview]

    private init(source: LeagueSource, teams: [LeagueTeamDefinition], previews: [String: TeamPreview]) {
        self.source = source
        self.teams = teams
        self.previews = previews
    }

    // MARK: - Lookup

    /// Scouting preview for a listed team; falls back to the static table.
    func preview(for team: LeagueTeamDefinition) -> TeamPreview {
        previews[team.abbreviation] ?? team.preview
    }

    /// The other three teams in `team`'s division, from this same catalog.
    func divisionRivals(of team: LeagueTeamDefinition) -> [LeagueTeamDefinition] {
        teams.filter {
            $0.conference == team.conference
            && $0.division == team.division
            && $0.abbreviation != team.abbreviation
        }
    }

    /// League-average coaching budget across this catalog.
    var averageCoachingBudget: Int {
        guard !teams.isEmpty else { return 0 }
        return teams.reduce(0) { $0 + preview(for: $1).coachingBudget } / teams.count
    }

    // MARK: - Random league

    /// The classic catalog: the static team table, with one number corrected.
    ///
    /// `estimatedDraftPicks` in the static table ranges 7-10 — a leftover from
    /// the hardcoded mock-draft order that used to hand some clubs two firsts
    /// and others none. `LeagueGenerator.generateInitialDraftPicks` now mints
    /// exactly one pick per team per round, so the picker was advertising "Draft
    /// Picks 10" to a GM who would find seven on the board. Compensatory picks
    /// are awarded later, in the career, and are not knowable here.
    static let generated: TeamBrowseCatalog = {
        var corrected: [String: TeamPreview] = [:]
        for (abbreviation, preview) in LeagueTeamData.previews {
            corrected[abbreviation] = TeamPreview(
                difficulty: preview.difficulty,
                situation: preview.situation,
                ownerPatience: preview.ownerPatience,
                patienceSeasons: preview.patienceSeasons,
                marketDescription: preview.marketDescription,
                estimatedOVR: preview.estimatedOVR,
                estimatedCapSpace: preview.estimatedCapSpace,
                estimatedDraftPicks: LeagueGenerator.roundsPerDraft,
                coachingBudget: preview.coachingBudget,
                spendingWillingness: preview.spendingWillingness,
                lastSeasonWins: preview.lastSeasonWins,
                lastSeasonLosses: preview.lastSeasonLosses,
                startingQBName: preview.startingQBName,
                startingQBOverall: preview.startingQBOverall,
                isLocked: preview.isLocked,
                // Authored, and the generator keeps its word about all three:
                // see `LeagueGenerator.generateRoster`.
                stars: preview.stars,
                strongestGroup: preview.strongestGroup,
                weakestGroup: preview.weakestGroup
            )
        }
        return TeamBrowseCatalog(
            source: .generated,
            teams: LeagueTeamData.allTeams,
            previews: corrected
        )
    }()

    // MARK: - Fixed template

    /// Builds the catalog for a decoded template.
    static func template(_ template: LeagueTemplate, source: LeagueSource) -> TeamBrowseCatalog {
        // Team strength first — the situation and difficulty derivations below
        // are relative to the league, so they need every team's number.
        var strengths: [String: Double] = [:]
        for team in template.teams {
            strengths[team.identity.key] = starterAverage(team)
        }
        let leagueMean = strengths.isEmpty
            ? 0
            : strengths.values.reduce(0, +) / Double(strengths.count)

        var definitions: [LeagueTeamDefinition] = []
        var previews: [String: TeamPreview] = [:]

        for teamTemplate in template.teams {
            let identity = teamTemplate.identity
            let abbreviation = identity.appAbbr
            // The app's own row for this franchise — market facts and the
            // conference/division fallback, exactly as the importer resolves it.
            let known = LeagueTeamData.allTeams.first { $0.abbreviation == abbreviation }

            definitions.append(LeagueTeamDefinition(
                name: identity.nickname,
                city: identity.city,
                abbreviation: abbreviation,
                conference: Conference(rawValue: teamTemplate.conference) ?? known?.conference ?? .AFC,
                division: Division(rawValue: teamTemplate.division) ?? known?.division ?? .east,
                mediaMarket: known?.mediaMarket ?? .medium
            ))

            previews[abbreviation] = preview(
                for: teamTemplate,
                strength: strengths[identity.key] ?? leagueMean,
                leagueMean: leagueMean,
                globalSeed: template.globalSeed
            )
        }

        return TeamBrowseCatalog(source: source, teams: definitions, previews: previews)
    }

    // MARK: - Derivation

    /// Average `ratingTarget` of the team's starters — the same shape the game
    /// itself shows once the career runs (`DepthChart.teamOverall` averages the
    /// starting lineup), so the number in the picker is the number the roster
    /// screen will report. Falls back to the whole roster if no roles are set.
    private static func starterAverage(_ team: LeagueTemplate.TeamTemplate) -> Double {
        let starters = team.players.filter { $0.role == "starter" }
        let pool = starters.isEmpty ? team.players : starters
        guard !pool.isEmpty else { return 0 }
        return Double(pool.reduce(0) { $0 + $1.ratingTarget }) / Double(pool.count)
    }

    private static func preview(
        for team: LeagueTemplate.TeamTemplate,
        strength: Double,
        leagueMean: Double,
        globalSeed: UInt64
    ) -> TeamPreview {
        // Owner, market and budget are properties of the franchise, not of the
        // roster snapshot, so they stay on the static table for both sources.
        let base = LeagueTeamData.previews[team.identity.appAbbr]
        let patience = base?.ownerPatience ?? "Moderate"
        let patienceSeasons = base?.patienceSeasons ?? 3
        let record = team.record2025

        // The template states both halves; the random league states neither, so
        // this stays nil there and the sheet simply omits the line.
        let playoffResult: String? = {
            guard let made = record.madePlayoffs else { return nil }
            guard made else { return "Missed the playoffs" }
            return record.playoffResult
        }()

        let qb = startingQB(team)
        let rooms = roomGrades(team)
        // Cap space the import will really produce, to within the $750K salary
        // floor's rounding: same helper, same seed, same draw.
        let capUsage = LeagueTemplateImporter.capTarget(
            teamKey: team.identity.key, globalSeed: globalSeed
        )
        let capSpaceMillions = max(0, (defaultSalaryCap - capUsage) / 1_000)

        return TeamPreview(
            difficulty: difficulty(
                patience: patience,
                strength: strength,
                leagueMean: leagueMean,
                wins: record.wins
            ),
            situation: situation(
                wins: record.wins,
                strength: strength,
                leagueMean: leagueMean,
                patienceSeasons: patienceSeasons
            ),
            ownerPatience: patience,
            patienceSeasons: patienceSeasons,
            marketDescription: base?.marketDescription ?? "Moderate expectations",
            estimatedOVR: Int(strength.rounded()),
            estimatedCapSpace: capSpaceMillions,
            estimatedDraftPicks: team.picks2026.count,
            coachingBudget: base?.coachingBudget ?? 38,
            spendingWillingness: base?.spendingWillingness ?? 50,
            lastSeasonWins: record.wins,
            lastSeasonLosses: record.losses,
            lastSeasonPlayoffResult: playoffResult,
            startingQBName: qb.map({ shortName($0) }) ?? "—",
            startingQBOverall: qb?.ratingTarget ?? 0,
            isLocked: base?.isLocked ?? false,
            // Real ratings beat authored ones wherever real ratings exist. The
            // static table's stars and group pair are a promise the random
            // league's generator has to keep; here the roster is already
            // written, so the sheet reads it instead of guessing at it.
            stars: stars(team, excluding: qb),
            strongestGroup: rooms.max(by: { $0.grade < $1.grade })?.label ?? "",
            weakestGroup: rooms.min(by: { $0.grade < $1.grade })?.label ?? ""
        )
    }

    /// The two or three names worth knowing besides the quarterback, best
    /// first. The QB1 is skipped for the same reason the authored table skips
    /// him: the sheet gives him a card of his own directly above this list.
    private static func stars(
        _ team: LeagueTemplate.TeamTemplate,
        excluding qb: LeagueTemplate.PlayerTemplate?
    ) -> [TeamPreviewStar] {
        team.players
            .filter { $0.id != qb?.id }
            .sorted { $0.ratingTarget > $1.ratingTarget }
            .prefix(3)
            .compactMap { player in
                guard let position = Position(rawValue: player.pos) else { return nil }
                return TeamPreviewStar(
                    name: shortName(player), position: position, overall: player.ratingTarget
                )
            }
    }

    /// Starter-average rating per position room, by the roster screen's rule:
    /// the group's best N by rating, where N is
    /// `PositionGradeCalculator.starterCount` — the same arithmetic
    /// `LeagueGenerator` checks its own claim against, so the two league
    /// sources answer "which room is strongest" the same way.
    ///
    /// Ordered, not a dictionary: two rooms can grade out identically and the
    /// sheet must name the same one on every launch.
    private static func roomGrades(
        _ team: LeagueTemplate.TeamTemplate
    ) -> [(label: String, grade: Int)] {
        LeagueTeamData.positionGroups.compactMap { group in
            let wanted = Set(group.positions.map(\.rawValue))
            let room = team.players
                .filter { wanted.contains($0.pos) }
                .map(\.ratingTarget)
                .sorted(by: >)
            guard !room.isEmpty else { return nil }
            let starters = Array(room.prefix(PositionGradeCalculator.starterCount(for: group.positions)))
            return (group.label, starters.reduce(0, +) / starters.count)
        }
    }

    /// `Team.salaryCap`'s default, in thousands.
    private static let defaultSalaryCap = ContractEngine.openingSalaryCap

    /// Career difficulty = how much pressure the job carries.
    ///
    /// Owner patience sets the baseline (the same ladder the static table
    /// follows: Very Patient 1 → Win Now 5); an elite roster and a big winning
    /// season each add a star, because both turn the brief from "improve" into
    /// "win it all" no matter how relaxed the owner is.
    private static func difficulty(
        patience: String,
        strength: Double,
        leagueMean: Double,
        wins: Int
    ) -> Int {
        var stars: Int
        switch patience {
        case "Very Patient": stars = 1
        case "Patient":      stars = 2
        case "Moderate":     stars = 3
        case "Demanding":    stars = 4
        case "Win Now":      stars = 5
        default:             stars = 3
        }
        if strength >= leagueMean + 2 { stars += 1 }
        if wins >= 12 { stars += 1 }
        return min(5, max(1, stars))
    }

    /// Franchise situation from last season's record and roster strength, using
    /// the same five labels the picker's filter menu offers. "Dynasty" is kept
    /// scarce — a big record alone is a contender, it takes an elite roster too.
    private static func situation(
        wins: Int,
        strength: Double,
        leagueMean: Double,
        patienceSeasons: Int
    ) -> String {
        if wins >= 13 && strength >= leagueMean + 2 { return "Dynasty" }
        if patienceSeasons <= 1 && strength >= leagueMean { return "Win Now" }
        if wins >= 10 { return "Contender" }
        if wins <= 5 || strength <= leagueMean - 1.5 { return "Rebuilding" }
        return "Rising"
    }

    /// The team's QB1 — depth rank 1, or the best-rated QB if ranks are absent.
    private static func startingQB(_ team: LeagueTemplate.TeamTemplate) -> LeagueTemplate.PlayerTemplate? {
        let quarterbacks = team.players.filter { $0.pos == Position.QB.rawValue }
        return quarterbacks.first { ($0.depthRank ?? 0) == 1 }
            ?? quarterbacks.max { $0.ratingTarget < $1.ratingTarget }
    }

    /// "F. Shelburne" — the abbreviated form the picker's QB column uses.
    private static func shortName(_ player: LeagueTemplate.PlayerTemplate) -> String {
        let parts = player.name.split(separator: " ").map(String.init)
        let last = player.lastName ?? parts.last ?? player.name
        let first = player.firstName ?? parts.first
        guard let initial = first?.first else { return last }
        return "\(initial). \(last)"
    }
}
