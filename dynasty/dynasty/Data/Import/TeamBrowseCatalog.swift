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
/// | installed offensive/defensive scheme | the template's `staff.offScheme`/`defScheme` — the same two values `LeagueTemplateImporter.makeStaff` hires the HC/OC/DC under |
/// | owner patience, market copy, coaching budget, lock, prestige, playstyle | `LeagueTeamData` — franchise/market facts a roster snapshot does not change |
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
                weakestGroup: preview.weakestGroup,
                // Franchise facts, and the scheme pair the generator now
                // installs rather than draws — `LeagueGenerator.generate`
                // reads these very fields to hire the staff and build the
                // defence, so the card and the league cannot disagree.
                prestige: preview.prestige,
                styleFit: preview.styleFit,
                offensiveScheme: preview.offensiveScheme,
                defensiveScheme: preview.defensiveScheme
            )
        }
        return TeamBrowseCatalog(
            source: .generated,
            teams: LeagueTeamData.allTeams,
            previews: corrected
        )
    }()

    // MARK: - Random league, after it has been rolled

    /// The catalog for a random league that has **already been generated**.
    ///
    /// ``generated`` above is the *pre*-generation catalog. It can only quote
    /// `LeagueTeamData`'s authored table, because at the moment it is built no
    /// roster exists — which is exactly why the picker kept promising things it
    /// could not know. `TeamSelectionView` now rolls the random league before it
    /// draws the list, so for the fields a roster can genuinely answer the card
    /// READS the league instead of promising it:
    ///
    /// | Preview field | The function it now comes from |
    /// |---|---|
    /// | `estimatedOVR` | `RosterStrength.starterAverage` — the mean `overall` of the best 22, this repo's one answer to "how good is this roster" |
    /// | `estimatedCapSpace` | `Team.salaryCap - Team.currentCapUsage`, ÷ 1 000 (both are in thousands), floored at 0 |
    /// | `estimatedDraftPicks` | the `draftPicks` rows for `league.currentSeason` whose `currentTeamID` is this club |
    /// | `startingQBName` / `startingQBOverall` | the club's best quarterback under `DepthChart.autoGenerate`'s own ranking — i.e. the man Auto-Set will start on day one |
    /// | `stars` | the three best non-quarterbacks by that same ranking |
    /// | `strongestGroup` / `weakestGroup` | `PositionGradeCalculator.calculatePositionGrades(...).starterOVR` per room, graded under the club's own defensive coordinator's scheme — the same call `RosterView` grades with |
    ///
    /// Everything else stays authored, and stays authored for the same reason
    /// the template catalog keeps it authored: `lastSeasonWins` /
    /// `lastSeasonLosses` describe a season a freshly generated league has never
    /// played, and owner patience, market copy, budgets, prestige, playstyle and
    /// the offensive scheme are franchise facts rather than roster facts.
    ///
    /// ## What reading the real roster exposes, and what is deliberately NOT
    /// tuned to hide it
    ///
    /// The authored `estimatedOVR` column spans 60-88 across the 32 clubs. The
    /// generator does not produce that spread and never has:
    /// `LeagueGenerator.talentLevelShift(depthIndex:)` takes a depth tier and
    /// nothing else — there is no team term anywhere in it — so all 32 rosters
    /// are drawn from one distribution, and the only club-to-club difference the
    /// roster actually carries is the named QB1 and the two or three named stars
    /// `generateRoster` pins to authored targets: four men out of the best 22.
    /// The honest number therefore sits much closer to the league mean than the
    /// authored one did. That is a real finding about the random league, not a
    /// defect in this function, and nothing here is fudged to restore the old
    /// spread.
    static func generated(from generated: LeagueGenerator.GeneratedLeague) -> TeamBrowseCatalog {
        var rosters: [UUID: [Player]] = [:]
        for player in generated.players {
            guard let teamID = player.teamID else { continue }
            rosters[teamID, default: []].append(player)
        }

        // The UPCOMING draft only. `LeagueGenerator.generate` also mints three
        // further years of tradable picks (`futureDraftPicks`); the card's
        // "Draft Picks" figure has always meant the board the new GM walks into,
        // which is `generateInitialDraftPicks` — one pick per round, seven
        // rounds, before any trade has happened.
        var upcomingPicks: [UUID: Int] = [:]
        for pick in generated.draftPicks where pick.seasonYear == generated.league.currentSeason {
            upcomingPicks[pick.currentTeamID, default: 0] += 1
        }

        // The defence each club installs, taken off the coordinator who was
        // hired under it — the seat the roster screen reads its starter counts
        // from, and the one `LeagueGenerator.generate` pins to the club's own
        // `TeamPreview.defensiveScheme`.
        var defensiveSchemes: [UUID: DefensiveScheme] = [:]
        for coach in generated.coaches where coach.role == .defensiveCoordinator {
            guard let teamID = coach.teamID, let scheme = coach.defensiveScheme else { continue }
            defensiveSchemes[teamID] = scheme
        }

        var byAbbreviation: [String: Team] = [:]
        for team in generated.teams { byAbbreviation[team.abbreviation] = team }

        // Listed in `LeagueTeamData.allTeams` order, which is the order
        // `generate` builds them in and the order the static catalog lists.
        var previews: [String: TeamPreview] = [:]
        for definition in LeagueTeamData.allTeams {
            guard let team = byAbbreviation[definition.abbreviation] else { continue }
            previews[definition.abbreviation] = preview(
                for: team,
                roster: rosters[team.id] ?? [],
                upcomingPicks: upcomingPicks[team.id] ?? 0,
                defensiveScheme: defensiveSchemes[team.id]
            )
        }

        return TeamBrowseCatalog(
            source: .generated,
            teams: LeagueTeamData.allTeams,
            previews: previews
        )
    }

    private static func preview(
        for team: Team,
        roster: [Player],
        upcomingPicks: Int,
        defensiveScheme: DefensiveScheme?
    ) -> TeamPreview {
        // Franchise facts stay on the static row for both league sources.
        let base = LeagueTeamData.previews[team.abbreviation]
        let ranked = roster.sorted(by: outranks)
        let quarterback = ranked.first { $0.position == .QB }
        let rooms = roomGrades(roster, defensiveScheme: defensiveScheme)

        return TeamPreview(
            difficulty: base?.difficulty ?? 3,
            situation: base?.situation ?? "Rising",
            ownerPatience: base?.ownerPatience ?? "Moderate",
            patienceSeasons: base?.patienceSeasons ?? 3,
            marketDescription: base?.marketDescription ?? "Moderate expectations",
            estimatedOVR: RosterStrength.starterAverage(roster) ?? base?.estimatedOVR ?? 0,
            // Both figures are in thousands (`ContractEngine.openingSalaryCap`
            // is 265_000 for a $265M cap), so the millions the card prints are
            // the difference ÷ 1 000. `generate` sets `currentCapUsage` to the
            // sum of the 53 salaries it just wrote, so this is the number the
            // cap screen will report on day one.
            estimatedCapSpace: max(0, (team.salaryCap - team.currentCapUsage) / 1_000),
            estimatedDraftPicks: upcomingPicks,
            coachingBudget: base?.coachingBudget ?? 38,
            spendingWillingness: base?.spendingWillingness ?? 50,
            // A generated league has played no season; the authored W-L is the
            // backstory the picker states and the only thing there is to state.
            lastSeasonWins: base?.lastSeasonWins ?? 8,
            lastSeasonLosses: base?.lastSeasonLosses ?? 9,
            startingQBName: quarterback.map { shortName($0) } ?? "\u{2014}",
            startingQBOverall: quarterback?.overall ?? 0,
            isLocked: base?.isLocked ?? false,
            // The QB is skipped for the reason the authored table skips him: the
            // sheet gives him a card of his own directly above this list.
            stars: ranked
                .filter { $0.position != .QB }
                .prefix(3)
                .map {
                    TeamPreviewStar(
                        name: shortName($0), position: $0.position, overall: $0.overall
                    )
                },
            strongestGroup: rooms.max(by: { $0.grade < $1.grade })?.label ?? "",
            weakestGroup: rooms.min(by: { $0.grade < $1.grade })?.label ?? "",
            prestige: base?.prestige ?? 3,
            styleFit: base?.styleFit ?? .tactician,
            // The offensive install is not readable off a roster, so it stays
            // the authored value `generate` hires the HC and OC under. The
            // defensive one is read back off the coordinator who was actually
            // hired, which is the same value by construction and stops being an
            // assumption if that ever changes.
            offensiveScheme: base?.offensiveScheme,
            defensiveScheme: defensiveScheme ?? base?.defensiveScheme
        )
    }

    /// Ranks two men the way the opening depth chart will.
    ///
    /// The picker must name the quarterback Auto-Set names. `DepthChart`
    /// `.autoGenerate` sorts each position room on `overall` and breaks a tie by
    /// fewer years pro, then by id — `DepthChart.outranks`, which is `private`
    /// to that type, so the rule is restated here rather than shared. If it is
    /// ever hoisted into a shared helper, this call site is one of two.
    private static func outranks(_ a: Player, _ b: Player) -> Bool {
        if a.overall != b.overall { return a.overall > b.overall }
        if a.yearsPro != b.yearsPro { return a.yearsPro < b.yearsPro }
        return a.id.uuidString < b.id.uuidString
    }

    /// Room grades for a generated roster, by the roster screen's own call.
    ///
    /// `PositionGradeCalculator.calculatePositionGrades` with the club's
    /// defensive scheme passed for the defensive rooms ONLY — precisely what
    /// `RosterView` does, and precisely what `LeagueGenerator.generateRoster`
    /// step 5 grades its own strongest/weakest claim with. Passing the scheme to
    /// an offensive room would be a difference, and a difference is the defect.
    ///
    /// This is what makes the claim exact rather than nearly always true: the
    /// generator earns the authored labels with a repair loop capped at
    /// `groupClaimPassLimit` passes, and a roster that exhausts the cap keeps
    /// the label it did not earn. Reading the finished roster cannot be wrong.
    ///
    /// Ordered, not a dictionary: two rooms can grade out identically and the
    /// sheet must name the same one on every launch.
    private static func roomGrades(
        _ roster: [Player],
        defensiveScheme: DefensiveScheme?
    ) -> [(label: String, grade: Int)] {
        LeagueTeamData.positionGroups.compactMap { group in
            let room = roster.filter { group.positions.contains($0.position) }
            guard !room.isEmpty else { return nil }
            let isDefensive = group.positions.first?.side == .defense
            let grades = PositionGradeCalculator.calculatePositionGrades(
                players: room,
                positions: group.positions,
                scheme: isDefensive ? defensiveScheme : nil
            )
            return (group.label, grades.starterOVR)
        }
    }

    /// "F. Shelburne" — the abbreviated form the picker's QB column uses.
    private static func shortName(_ player: Player) -> String {
        shortName(first: player.firstName, last: player.lastName)
    }

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
            weakestGroup: rooms.min(by: { $0.grade < $1.grade })?.label ?? "",
            // Prestige and the club's own playstyle are FRANCHISE facts, so
            // they follow owner patience and market copy onto the static row
            // rather than being read off a roster snapshot: the template
            // renames the nickname, not the franchise, and a 4-13 season does
            // not cost a club its history. A club the app has no row for takes
            // prestige 3, which is genuinely the middle of the 1-5 tier, and
            // `.tactician`, which is NOT the middle of anything: `CoachingStyle`
            // is five unordered cases and `.tactician` is simply the first one
            // declared. It is a named default rather than a computed midpoint,
            // and it is safe only because the pairing carries no mechanic — the
            // sheet's Coaching Style card states in as many words that nothing
            // is docked for a difference, so an unmatched club reads as
            // unremarkable rather than as wrong.
            prestige: base?.prestige ?? 3,
            styleFit: base?.styleFit ?? .tactician,
            // The schemes, by contrast, are NOT authored here: the template
            // states what each club really installs and `makeStaff` hires the
            // HC/OC/DC under exactly these two values, so the picker quotes
            // the file rather than the static table. `nil` when a template was
            // baked without the staff keys, and the sheet omits the card.
            offensiveScheme: team.staff.offScheme.flatMap(OffensiveScheme.init(rawValue:)),
            defensiveScheme: team.staff.defScheme.flatMap(DefensiveScheme.init(rawValue:))
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
    /// N is scheme-aware for the defensive rooms, because the roster screen's
    /// is (`RosterView` line 120). The template authors a real `staff.defScheme`
    /// per club and exactly 16 of the 32 run a 3-4 family defence, which fields
    /// one nose tackle and two inside linebackers where a 4-3 fields two
    /// tackles and one.
    ///
    /// Recomputed both ways over `league_2026_publish.json`, grading with the
    /// 4-3 default cost one club a headline outright: PIT's card said its
    /// linebackers were the strongest room (LB 84 under 4-3 counts) where its
    /// own Hybrid coordinator grades LB 82 behind DB 83. Three more — LAR, LV
    /// and NO — were ties under the default that the club's real scheme breaks
    /// cleanly. IND and NYG change headline between two rooms that grade level
    /// under their own scheme.
    ///
    /// Ordered, not a dictionary: two rooms can grade out identically and the
    /// sheet must name the same one on every launch.
    private static func roomGrades(
        _ team: LeagueTemplate.TeamTemplate
    ) -> [(label: String, grade: Int)] {
        // Resolved exactly as `LeagueTemplateImporter.makeStaff` resolves it, so
        // the scheme the card grades under is the one the imported DC carries.
        let scheme = team.staff.defScheme.flatMap(DefensiveScheme.init(rawValue:))
        return LeagueTeamData.positionGroups.compactMap { group in
            let wanted = Set(group.positions.map(\.rawValue))
            let room = team.players
                .filter { wanted.contains($0.pos) }
                .map(\.ratingTarget)
                .sorted(by: >)
            guard !room.isEmpty else { return nil }
            let isDefensive = group.positions.first?.side == .defense
            let starterCount: Int
            if isDefensive, let scheme {
                starterCount = PositionGradeCalculator.starterCount(
                    for: group.positions, scheme: scheme
                )
            } else {
                starterCount = PositionGradeCalculator.starterCount(for: group.positions)
            }
            let starters = Array(room.prefix(starterCount))
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
        guard let first = player.firstName ?? parts.first else { return last }
        return shortName(first: first, last: last)
    }

    /// The one abbreviation rule, so a template card and a generated card
    /// spell the same man the same way.
    private static func shortName(first: String, last: String) -> String {
        guard let initial = first.first else { return last }
        return "\(initial). \(last)"
    }
}
