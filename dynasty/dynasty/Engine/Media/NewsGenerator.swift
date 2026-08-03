import Foundation

// MARK: - Supporting Types

struct NewsItem: Identifiable, Codable {
    let id: UUID
    let headline: String
    let body: String
    let category: NewsCategory
    let week: Int
    let season: Int
    let relatedTeamID: UUID?
    let relatedPlayerID: UUID?
    let sentiment: NewsSentiment

    init(
        id: UUID = UUID(),
        headline: String,
        body: String,
        category: NewsCategory,
        week: Int,
        season: Int,
        relatedTeamID: UUID? = nil,
        relatedPlayerID: UUID? = nil,
        sentiment: NewsSentiment = .neutral
    ) {
        self.id = id
        self.headline = headline
        self.body = body
        self.category = category
        self.week = week
        self.season = season
        self.relatedTeamID = relatedTeamID
        self.relatedPlayerID = relatedPlayerID
        self.sentiment = sentiment
    }
}

enum NewsCategory: String, Codable {
    case gameResult, injury, trade, freeAgency, draft,
         coachingChange, playerPerformance, teamRanking,
         offFieldIncident, contract, retirement, award
}

enum NewsSentiment: String, Codable {
    case positive, negative, neutral
}

// MARK: - News Generator

/// Generates dynamic news headlines and stories based on league state.
enum NewsGenerator {

    // MARK: - Weekly News

    /// Produces 3-8 headlines for a given regular-season or playoff week.
    static func generateWeeklyNews(
        teams: [Team],
        players: [Player],
        career: Career,
        week: Int,
        season: Int
    ) -> [NewsItem] {
        var items: [NewsItem] = []

        // 1) Power rankings — owned by LeagueNarrativeEngine since R29 (it
        //    computes the full ranked board with movement); no duplicate here.

        // 2) Standout player performance (player of the week)
        if let potw = generatePlayerOfTheWeek(players: players, teams: teams, week: week, season: season) {
            items.append(potw)
        }

        // 3) Injury reports
        let injuredPlayers = players.filter { $0.isInjured && $0.injuryWeeksRemaining > 0 }
        if let injuryNews = generateInjuryReport(injured: injuredPlayers, teams: teams, week: week, season: season) {
            items.append(injuryNews)
        }

        // 4) Trade rumors (random chance, higher near trade deadline)
        if Bool.random() || career.currentPhase == .tradeDeadline {
            if let tradeRumor = generateTradeRumor(players: players, teams: teams, week: week, season: season) {
                items.append(tradeRumor)
            }
        }

        // 5) Coaching hot seat speculation
        let strugglingTeams = teams.filter { $0.losses > $0.wins && ($0.wins + $0.losses) >= 4 }
        if let hotSeat = generateCoachingHotSeat(teams: strugglingTeams, week: week, season: season) {
            items.append(hotSeat)
        }

        // 6) Draft prospect buzz (during college season, weeks 1-14)
        if week <= 14 {
            if let draftBuzz = generateDraftBuzz(week: week, season: season) {
                items.append(draftBuzz)
            }
        }

        // 7) Random game result headline for a non-player team
        let otherTeams = teams.filter { $0.id != career.teamID }
        if let gameNews = generateGameResultHeadline(teams: otherTeams, week: week, season: season) {
            items.append(gameNews)
        }

        // 8) Occasional contract or off-field story
        if Int.random(in: 0...3) == 0 {
            if let extra = generateContractNews(players: players, teams: teams, week: week, season: season) {
                items.append(extra)
            }
        }

        // Clamp to 3-8 items
        if items.count < 3 {
            while items.count < 3 {
                items.append(generateFillerHeadline(teams: teams, week: week, season: season))
            }
        }
        return Array(items.prefix(8))
    }

    // MARK: - Offseason News

    /// Produces news for the current offseason phase.
    static func generateOffseasonNews(
        phase: SeasonPhase,
        career: Career,
        teams: [Team]
    ) -> [NewsItem] {
        var items: [NewsItem] = []
        let season = career.currentSeason

        switch phase {
        case .coachingChanges:
            let fireCandidates = teams.filter { $0.losses >= 10 }
            for team in fireCandidates.prefix(3) {
                items.append(NewsItem(
                    headline: "\(team.fullName) expected to make coaching change",
                    body: "After a disappointing \(team.record) season, sources indicate the \(team.fullName) are moving on from their coaching staff. Multiple candidates have already been contacted.",
                    category: .coachingChange,
                    week: 0,
                    season: season,
                    relatedTeamID: team.id,
                    sentiment: .negative
                ))
            }
            if items.isEmpty {
                items.append(NewsItem(
                    headline: "Coaching carousel quiet this offseason",
                    body: "League sources suggest most teams are standing pat with their current coaching staffs heading into the offseason.",
                    category: .coachingChange,
                    week: 0,
                    season: season,
                    sentiment: .neutral
                ))
            }

        case .combine:
            // Nothing generic here on purpose. The combine used to ship three
            // hardcoded headlines about prospects who did not exist — a "top QB"
            // and a "280-pound defensive tackle" who were never on any board and
            // could not be looked up, while the real risers, fallers and
            // standouts `ScoutingEngine.generateCombineMedia` had just named
            // never reached the feed at all. `combineMediaNews(mentions:…)`
            // below emits the real ones, from the real class.
            break

        case .freeAgency:
            items.append(NewsItem(
                headline: "Free agency frenzy: top targets hit the market",
                body: "The legal tampering period has begun and teams are scrambling to land the biggest names available. Multiple franchises are expected to be aggressive spenders.",
                category: .freeAgency,
                week: 0,
                season: season,
                sentiment: .neutral
            ))
            let bigMarketTeams = teams.filter { $0.mediaMarket == .large }
            if let spender = bigMarketTeams.randomElement() {
                items.append(NewsItem(
                    headline: "\(spender.fullName) making big splash in free agency",
                    body: "The \(spender.fullName) have reportedly offered massive deals to multiple top-tier free agents, signaling an all-in approach for the upcoming season.",
                    category: .freeAgency,
                    week: 0,
                    season: season,
                    relatedTeamID: spender.id,
                    sentiment: .positive
                ))
            }

        case .reviewRoster:
            items.append(NewsItem(
                headline: "Teams evaluate rosters ahead of the draft",
                body: "With free agency winding down, front offices are turning their attention to draft preparation. Identifying roster holes now will shape draft strategy.",
                category: .teamRanking,
                week: 0,
                season: season,
                sentiment: .neutral
            ))

        case .draft:
            items.append(NewsItem(
                headline: "Draft day arrives: who will go first overall?",
                body: "After months of speculation, mock drafts, and pro days, the moment of truth has arrived. Teams will make the picks that shape their franchises for years to come.",
                category: .draft,
                week: 0,
                season: season,
                sentiment: .neutral
            ))
            items.append(NewsItem(
                headline: "Trade rumors swirling around top pick",
                body: "Multiple teams have called about trading up into the top five, with at least two franchises reportedly willing to offer significant draft capital to move up.",
                category: .trade,
                week: 0,
                season: season,
                sentiment: .neutral
            ))

        case .otas:
            items.append(NewsItem(
                headline: "OTAs underway across the league",
                body: "Organized team activities have kicked off, giving coaches their first look at new acquisitions and draft picks working with the established roster.",
                category: .playerPerformance,
                week: 0,
                season: season,
                sentiment: .neutral
            ))

        case .trainingCamp:
            items.append(NewsItem(
                headline: "Training camp battles heating up",
                body: "Position battles are intensifying across the league as teams prepare to trim rosters to 53. Several high-profile rookies are pushing veterans for starting spots.",
                category: .playerPerformance,
                week: 0,
                season: season,
                sentiment: .neutral
            ))

        case .proDays:
            items.append(NewsItem(
                headline: "Pro day circuit kicks off across the country",
                body: "College programs are hosting pro days this month, giving prospects one last chance to impress NFL scouts in a controlled environment before the draft.",
                category: .draft,
                week: 0,
                season: season,
                sentiment: .neutral
            ))
            items.append(NewsItem(
                headline: "Teams scheduling private workouts with top targets",
                body: "Several teams have begun inviting top prospects for private workouts at their facilities, a sign that they're narrowing down their draft boards ahead of selection day.",
                category: .draft,
                week: 0,
                season: season,
                sentiment: .neutral
            ))

        case .rosterCuts:
            items.append(NewsItem(
                headline: "Final roster cuts loom: hundreds face anxious wait",
                body: "Teams must trim their rosters to 53 players by this week's deadline. The waiver wire is expected to be active as teams look for hidden gems among the released players.",
                category: .playerPerformance,
                week: 0,
                season: season,
                sentiment: .neutral
            ))

        default:
            items.append(NewsItem(
                headline: "League prepares for the next phase",
                body: "Front offices around the league are gearing up as the offseason calendar moves forward.",
                category: .teamRanking,
                week: 0,
                season: season,
                sentiment: .neutral
            ))
        }

        return items
    }

    // MARK: - Draft Cycle News
    //
    // The pre-draft calendar is a running story about named men, not a set of
    // generic phase banners. Everything here takes real engine output — the
    // combine media sheet, the Senior Bowl week, the mock-draft re-reads, the
    // spring medical attrition — and turns it into headlines the user can go
    // and look up on the board.

    /// Turns `ScoutingEngine.generateCombineMedia`'s named risers, fallers,
    /// standouts and surprises into the actual news feed.
    ///
    /// The mentions are already stamped on the prospects (and rebuildable via
    /// `ScoutingEngine.combineMediaDigest`), so these headlines always match
    /// what the Combine screen shows — no second, contradictory set.
    static func combineMediaNews(
        mentions: [ScoutingEngine.CombineMediaMention],
        inviteCount: Int,
        season: Int,
        limit: Int = 7
    ) -> [NewsItem] {
        var items: [NewsItem] = []

        items.append(NewsItem(
            headline: "Combine week wraps in Indianapolis: \(inviteCount) prospects tested",
            body: "The league's scouting combine is complete. \(inviteCount) invitees were measured, timed and interviewed over the week, and front offices now have the athletic testing numbers to set against a season of film.",
            category: .draft,
            week: 0,
            season: season,
            sentiment: .neutral
        ))

        // Lead with the men whose stock actually moved, then the standouts.
        let order = ["Stock Riser", "Surprise", "Stock Faller", "Standout"]
        let sorted = mentions.sorted {
            let a = order.firstIndex(of: $0.category) ?? order.count
            let b = order.firstIndex(of: $1.category) ?? order.count
            if a != b { return a < b }
            return $0.prospectName < $1.prospectName
        }

        for mention in sorted.prefix(max(0, limit - 1)) {
            items.append(NewsItem(
                headline: mention.headline,
                body: combineMentionBody(mention),
                category: .draft,
                week: 0,
                season: season,
                sentiment: combineMentionSentiment(mention.category)
            ))
        }

        return items
    }

    /// Category → sentiment. A faller is the only bad news at the combine; a
    /// surprise and a riser are both good news for the prospect, and a standout
    /// is the week's headline athlete.
    static func combineMentionSentiment(_ category: String) -> NewsSentiment {
        switch category {
        case "Stock Faller":            return .negative
        case "Stock Riser", "Surprise", "Standout": return .positive
        default:                        return .neutral
        }
    }

    private static func combineMentionBody(_ mention: ScoutingEngine.CombineMediaMention) -> String {
        switch mention.category {
        case "Stock Riser":
            return "\(mention.prospectName) (\(mention.position)) tested well above the expectations his film had set, and the boards are already moving. Clubs that had him graded as a mid-round flier are re-checking the tape this week."
        case "Stock Faller":
            return "\(mention.prospectName) (\(mention.position)) did not test the way his tape suggested he would. Nobody removes a player over one workout, but the athletic questions are on the record now and the medical and interview weeks matter more for him than they did on Monday."
        case "Surprise":
            return "Almost nobody had \(mention.prospectName) (\(mention.position)) on a short list before this week. The testing numbers changed that, and the private-workout requests have already started."
        default:
            return "\(mention.prospectName) (\(mention.position)) was one of the athletic stories of combine week, posting numbers that stand out even against the best testers at the position."
        }
    }

    /// The January all-star week: 2-4 named stories out of Mobile.
    static func seniorBowlNews(
        result: ScoutingEngine.SeniorBowlResult,
        season: Int
    ) -> [NewsItem] {
        var items: [NewsItem] = [
            NewsItem(
                headline: "Senior Bowl week opens with \(result.invitees) invitees",
                body: "The senior half of this draft class is in Mobile for a week of practices in front of every front office in the league. For a lot of these players it is the first time they have lined up against somebody as good as they are, and the practice tape will matter more than the game.",
                category: .draft,
                week: 0,
                season: season,
                sentiment: .neutral
            )
        ]

        for note in result.notes {
            items.append(NewsItem(
                headline: note.headline,
                body: note.body,
                category: .draft,
                week: 0,
                season: season,
                sentiment: note.isRiser ? .positive : .negative
            ))
        }

        return items
    }

    /// The board moving: the biggest climbers and slides of a drift moment.
    ///
    /// Only the men who crossed a round boundary get a headline, and only the
    /// largest few — the point is the story, not a changelog.
    static func projectionDriftNews(
        moves: [ScoutingEngine.ProjectionMove],
        season: Int,
        limit: Int = 3
    ) -> [NewsItem] {
        let ranked = moves.sorted {
            if $0.rounds != $1.rounds { return $0.rounds > $1.rounds }
            if $0.isRise != $1.isRise { return $0.isRise }
            return $0.to < $1.to
        }

        return ranked.prefix(limit).map { move in
            if move.isRise {
                return NewsItem(
                    headline: move.to == 1
                        ? "\(move.position) \(move.name) rockets into the round 1 conversation"
                        : "\(move.name) climbing: \(move.college) \(move.position) now a round \(move.to) projection",
                    body: "\(move.name) has moved from a round \(move.from) projection to round \(move.to). Analysts who had him behind two or three players at the position have started flipping that order, and the clubs picking in that range are re-working their boards around it.",
                    category: .draft,
                    week: 0,
                    season: season,
                    sentiment: .positive
                )
            }
            return NewsItem(
                headline: "\(move.college) \(move.position) \(move.name) sliding down boards to round \(move.to)",
                body: "\(move.name) was a round \(move.from) projection and is now being talked about in round \(move.to). Somebody will get value if the slide is an overreaction — that is how the second day of a draft gets interesting.",
                category: .draft,
                week: 0,
                season: season,
                sentiment: .negative
            )
        }
    }

    /// Spring medical attrition: the pro-day workout that ended a man's draft.
    static func preDraftInjuryNews(
        setbacks: [ScoutingEngine.PreDraftSetback],
        season: Int,
        limit: Int = 3
    ) -> [NewsItem] {
        setbacks.prefix(limit).map { setback in
            let slide: String
            if let from = setback.projectionFrom, let to = setback.projectionTo, to > from {
                slide = " His projection has already slipped from round \(from) to round \(to)."
            } else {
                slide = ""
            }
            return NewsItem(
                headline: "\(setback.college) \(setback.position) \(setback.name) suffers \(setback.injury) in pre-draft workout",
                body: "\(setback.name) went down during pre-draft work and is looking at roughly \(setback.weeksOut) weeks before he is cleared. Every club's medical staff will flag it before the draft, and the recheck in the weeks ahead decides how far he falls.\(slide)",
                category: .injury,
                week: 0,
                season: season,
                sentiment: .negative
            )
        }
    }

    // MARK: - Private Generators

    private static func generatePlayerOfTheWeek(
        players: [Player],
        teams: [Team],
        week: Int,
        season: Int
    ) -> NewsItem? {
        // Pick a high-overall, non-injured player as the standout
        let eligible = players.filter { !$0.isInjured && $0.teamID != nil }
        guard let standout = eligible.max(by: {
            ($0.overall + Int.random(in: -10...10)) < ($1.overall + Int.random(in: -10...10))
        }) else { return nil }

        let teamName = teams.first(where: { $0.id == standout.teamID })?.fullName ?? "his team"

        return NewsItem(
            headline: "\(standout.fullName) named Player of the Week",
            body: "\(standout.fullName) delivered a dominant performance for the \(teamName) in Week \(week), earning league-wide Player of the Week honors at the \(standout.position.rawValue) position.",
            category: .award,
            week: week,
            season: season,
            relatedTeamID: standout.teamID,
            relatedPlayerID: standout.id,
            sentiment: .positive
        )
    }

    private static func generateInjuryReport(
        injured: [Player],
        teams: [Team],
        week: Int,
        season: Int
    ) -> NewsItem? {
        guard let player = injured.randomElement() else { return nil }
        let teamName = teams.first(where: { $0.id == player.teamID })?.fullName ?? "his team"

        let weeksLabel = player.injuryWeeksRemaining == 1 ? "week" : "weeks"
        return NewsItem(
            headline: "\(teamName) \(player.position.rawValue) \(player.fullName) to miss \(player.injuryWeeksRemaining) \(weeksLabel)",
            body: "The \(teamName) will be without \(player.fullName) for the next \(player.injuryWeeksRemaining) \(weeksLabel). The team is evaluating options to fill the void at \(player.position.rawValue).",
            category: .injury,
            week: week,
            season: season,
            relatedTeamID: player.teamID,
            relatedPlayerID: player.id,
            sentiment: .negative
        )
    }

    private static func generateTradeRumor(
        players: [Player],
        teams: [Team],
        week: Int,
        season: Int
    ) -> NewsItem? {
        // Players in last year of contract or unhappy are trade candidates
        let candidates = players.filter {
            $0.teamID != nil && ($0.contractYearsRemaining <= 1 || $0.morale < 40)
        }
        guard let player = candidates.randomElement() else { return nil }
        let currentTeam = teams.first(where: { $0.id == player.teamID })?.fullName ?? "his team"
        let suitors = teams.filter { $0.id != player.teamID }
        let suitor = suitors.randomElement()?.fullName ?? "multiple teams"

        return NewsItem(
            headline: "Trade rumors swirl around \(player.fullName)",
            body: "\(currentTeam) \(player.position.rawValue) \(player.fullName) has drawn interest from \(suitor) as the trade deadline approaches. The \(player.overall)-overall rated player could be on the move.",
            category: .trade,
            week: week,
            season: season,
            relatedTeamID: player.teamID,
            relatedPlayerID: player.id,
            sentiment: .neutral
        )
    }

    private static func generateCoachingHotSeat(
        teams: [Team],
        week: Int,
        season: Int
    ) -> NewsItem? {
        guard let team = teams.randomElement() else { return nil }

        return NewsItem(
            headline: "\(team.fullName) coach under fire after slow start",
            body: "At \(team.record), the \(team.fullName) are underperforming expectations. Sources say the coaching staff is feeling the heat from the front office and ownership.",
            category: .coachingChange,
            week: week,
            season: season,
            relatedTeamID: team.id,
            sentiment: .negative
        )
    }

    private static func generateDraftBuzz(week: Int, season: Int) -> NewsItem? {
        let positions = ["QB", "EDGE", "OT", "WR", "CB", "DT", "RB", "TE", "S", "LB"]
        let position = positions.randomElement() ?? "QB"
        let templates = [
            (
                headline: "College \(position) continues to climb draft boards",
                body: "After another impressive week of college football, scouts are raving about a \(position) prospect who has the tools to be a franchise-changing talent at the next level."
            ),
            (
                headline: "Mock draft shakeup: new consensus number one overall",
                body: "A dominant performance this past weekend has reshuffled the top of mock drafts league-wide. The \(position) position could hear its name called first in April."
            ),
            (
                headline: "Top prospect suffers injury, draft stock in question",
                body: "One of the top \(position) prospects in next year's draft class suffered a significant injury during this weekend's games. Teams will be closely monitoring his recovery timeline."
            )
        ]

        guard let template = templates.randomElement() else { return nil }
        return NewsItem(
            headline: template.headline,
            body: template.body,
            category: .draft,
            week: week,
            season: season,
            sentiment: .neutral
        )
    }

    private static func generateGameResultHeadline(
        teams: [Team],
        week: Int,
        season: Int
    ) -> NewsItem? {
        guard let team = teams.randomElement() else { return nil }
        let isWinning = team.wins > team.losses

        if isWinning {
            return NewsItem(
                headline: "\(team.fullName) continue strong season at \(team.record)",
                body: "The \(team.fullName) are establishing themselves as legitimate contenders with another impressive showing in Week \(week).",
                category: .gameResult,
                week: week,
                season: season,
                relatedTeamID: team.id,
                sentiment: .positive
            )
        } else {
            return NewsItem(
                headline: "\(team.fullName) drop to \(team.record) after tough loss",
                body: "It was another rough week for the \(team.fullName), who now sit at \(team.record) and find themselves searching for answers.",
                category: .gameResult,
                week: week,
                season: season,
                relatedTeamID: team.id,
                sentiment: .negative
            )
        }
    }

    private static func generateContractNews(
        players: [Player],
        teams: [Team],
        week: Int,
        season: Int
    ) -> NewsItem? {
        let expiringDeals = players.filter {
            $0.contractYearsRemaining == 1 && $0.teamID != nil && $0.overall >= 75
        }
        guard let player = expiringDeals.randomElement() else { return nil }
        let teamName = teams.first(where: { $0.id == player.teamID })?.fullName ?? "his team"

        return NewsItem(
            headline: "\(player.fullName) extension talks stall with \(teamName)",
            body: "Negotiations between \(player.fullName) and the \(teamName) have hit a snag. The star \(player.position.rawValue) is seeking a deal that would make him one of the highest-paid players at his position.",
            category: .contract,
            week: week,
            season: season,
            relatedTeamID: player.teamID,
            relatedPlayerID: player.id,
            sentiment: .negative
        )
    }

    private static func generateFillerHeadline(teams: [Team], week: Int, season: Int) -> NewsItem {
        let fillers = [
            (
                headline: "Around the league: Week \(week) storylines to watch",
                body: "From surprise contenders to unexpected struggles, here are the top storylines heading into this week's slate of games."
            ),
            (
                headline: "Analysts debate midseason award favorites",
                body: "With the season approaching the halfway point, the race for MVP, Rookie of the Year, and other major awards is beginning to take shape."
            ),
            (
                headline: "Bye weeks create roster management challenges",
                body: "Several teams are navigating bye weeks and must balance rest with maintaining competitive momentum down the stretch."
            )
        ]

        let filler = fillers.randomElement() ?? fillers[0]
        return NewsItem(
            headline: filler.headline,
            body: filler.body,
            category: .teamRanking,
            week: week,
            season: season,
            sentiment: .neutral
        )
    }

    // MARK: - Rookie Class Press (TRACK B)

    /// The one headline the draft class earns when the rookies report to camp
    /// and the fog comes off them (`RookieClassRevealView`).
    ///
    /// Deliberately primitive parameters: the summary itself is assembled by
    /// `RookieClassReveal.build`, and both this item and the letter below quote
    /// the SAME verdict paragraph so the news screen, the inbox and the modal
    /// can never tell three different stories about the same draft.
    static func rookieClassGraded(
        teamName: String,
        teamID: UUID,
        classGrade: String,
        verdict: String,
        season: Int
    ) -> NewsItem {
        NewsItem(
            headline: "Press grades: \(teamName)'s draft class earns \(classGrade)",
            body: verdict,
            category: .draft,
            week: 0,
            season: season,
            relatedTeamID: teamID,
            sentiment: rookieClassSentiment(classGrade)
        )
    }

    /// The scouting department's own note on the same class — mirrors the
    /// `InboxEngine` phase-message pattern (sender, dated label, a destination
    /// the user can act on) without living in the phase switch, because it only
    /// exists in the seasons the club actually drafted somebody.
    static func rookieClassInboxMessage(
        teamName: String,
        classGrade: String,
        verdict: String,
        bestPickLine: String?,
        biggestReachLine: String?,
        season: Int
    ) -> InboxMessage {
        var lines: [String] = [
            "Coach,",
            "",
            "The rookies are in the building and our first full evaluation is on your desk — real numbers now, not the spring's ranges.",
            "",
            "The press has us at \(classGrade) for the class. \(verdict)",
        ]
        if let bestPickLine {
            lines.append("")
            lines.append("Best-reviewed selection: \(bestPickLine).")
        }
        if let biggestReachLine {
            lines.append("Most questioned selection: \(biggestReachLine).")
        }
        lines.append("")
        lines.append("Scouting Department")

        return InboxMessage(
            sender: .scout(name: "Director of Scouting"),
            subject: "Rookie Class Report — \(teamName)",
            body: lines.joined(separator: "\n"),
            date: "Offseason - Training Camp, Season \(String(season))",
            category: .scoutingReport,
            attachments: [
                MessageAttachment(title: "View Roster", destination: .roster)
            ]
        )
    }

    private static func rookieClassSentiment(_ classGrade: String) -> NewsSentiment {
        if classGrade.hasPrefix("A") { return .positive }
        if classGrade.hasPrefix("D") || classGrade.hasPrefix("F") { return .negative }
        if classGrade == "C-" { return .negative }
        return .neutral
    }

}

// MARK: - Trade News Factory (Wave 2 — `docs/TRADE_OVERHAUL_PLAN.md`)

/// Turns one executed trade (its persisted `TradeRecord`) into the two surfaces
/// a trade has to reach: the league news feed, and the user's inbox whenever the
/// deal concerns him.
///
/// WHY a factory instead of copy at each call site: five execution paths write
/// ledger rows (`TradeRecordKind`) and before this every one of them either
/// hand-rolled its own headline or — far more often — announced nothing at all
/// (plan finding S7). A league that moves 30+ players a year invisibly reads as
/// a league where nothing happens, so every path now announces through the same
/// two sentences of copy.
///
/// The record's denormalized SNAPSHOT strings are the only input, deliberately:
/// by the time this runs the players have already changed teams, so re-deriving
/// "who got what" from live rosters would describe the trade backwards.
enum TradeNewsFactory {

    /// League-visible news + optional user inbox message for an executed trade.
    /// Call AFTER the TradeLedger row at EVERY execution site.
    static func announce(
        record: TradeRecord,
        teamsByID: [UUID: Team],
        userTeamID: UUID?
    ) -> (news: NewsItem, inbox: InboxMessage?) {
        let initiator = teamsByID[record.initiatorTeamID]
        let partner   = teamsByID[record.partnerTeamID]

        let initiatorAbbr = initiator?.abbreviation ?? "???"
        let partnerAbbr   = partner?.abbreviation   ?? "???"
        let initiatorName = initiator?.fullName ?? "A rival club"
        let partnerName   = partner?.fullName   ?? "a rival club"

        // Ledger rows are written from the INITIATOR's perspective; the news
        // reads from the perspective of whoever landed the best player, because
        // that is the side a headline is about ("DEN acquire WR …", not "LV
        // send WR …").
        let sent     = parse(record.sentSummary)
        let received = parse(record.receivedSummary)
        let centerpiece = bestPlayer(in: sent + received)
        let initiatorIsAcquirer = centerpiece.map { star in
            !contains(player: star, in: sent)
        } ?? true

        let acquiredAssets = initiatorIsAcquirer ? received : sent
        let priceAssets    = initiatorIsAcquirer ? sent : received
        let acquiredValue  = initiatorIsAcquirer ? record.receivedValue : record.sentValue
        let priceValue     = initiatorIsAcquirer ? record.sentValue : record.receivedValue

        let acquirerAbbr = initiatorIsAcquirer ? initiatorAbbr : partnerAbbr
        let acquirerName = initiatorIsAcquirer ? initiatorName : partnerName
        let sellerAbbr   = initiatorIsAcquirer ? partnerAbbr : initiatorAbbr
        let sellerName   = initiatorIsAcquirer ? partnerName : initiatorName
        let acquirerTeamID = initiatorIsAcquirer ? record.initiatorTeamID : record.partnerTeamID

        // "Big deal" = a headline star or first-round capital. Those get the
        // louder headline; everything else stays a transaction line so the feed
        // doesn't shout about a 5th-rounder for a backup guard.
        let topOverall = (sent + received).compactMap(\.overall).max() ?? 0
        let hasFirstRounder = (sent + received).contains { asset in
            if case .pick(_, let round) = asset { return round == 1 }
            return false
        }
        let isBigDeal = topOverall >= 85 || hasFirstRounder

        let headline: String
        if let star = centerpiece, isBigDeal {
            headline = "Blockbuster: \(acquirerAbbr) land \(shortLabel(star)) (\(star.overall ?? 0) OVR) from \(sellerAbbr)"
        } else if let star = centerpiece, priceAssets.isEmpty {
            // A one-way asset dump is legal and has to read as one, not as
            // "… for nothing", which sounds like a formatting bug.
            headline = "\(sellerAbbr) send \(shortLabel(star)) to \(acquirerAbbr) for nothing in return"
        } else if let star = centerpiece {
            headline = "\(acquirerAbbr) acquire \(shortLabel(star)) from \(sellerAbbr) for \(clause(priceAssets, limit: 2))"
        } else {
            headline = "\(initiatorAbbr) and \(partnerAbbr) swap draft picks"
        }

        let whenPhrase: String
        switch record.phase {
        case .regularSeason, .tradeDeadline, .playoffs:
            whenPhrase = " in Week \(record.week)"
        default:
            whenPhrase = ""
        }

        let body = """
        \(acquirerName) acquired \(clause(acquiredAssets, long: true)) from \(sellerName)\(whenPhrase) in exchange for \(clause(priceAssets, long: true)). \(contextSentence(kind: record.kind, sellerAbbr: sellerAbbr, acquirerAbbr: acquirerAbbr)) \(valueSentence(paid: priceValue, got: acquiredValue, acquirerAbbr: acquirerAbbr))
        """

        // The feed's "My Team" filter keys off `relatedTeamID`, so a deal the
        // user was part of has to point at HIS club whichever side he was on —
        // selling a star is his story too.
        let userWasInvolved = userTeamID.map {
            record.initiatorTeamID == $0 || record.partnerTeamID == $0
        } ?? false

        let news = NewsItem(
            headline: headline,
            body: body,
            category: .trade,
            week: record.week,
            season: record.season,
            relatedTeamID: userWasInvolved ? userTeamID : acquirerTeamID,
            // The ledger stores names, not player ids (it has to survive
            // retirements), so news rows from trades carry no portrait. Handoff:
            // a `headlinePlayerID` on `TradeRecord` would light one up.
            relatedPlayerID: nil,
            sentiment: isBigDeal
                ? .positive
                : (record.kind == .holdoutForced ? .negative : .neutral)
        )

        let dateString = InboxEngine.dateLabel(
            week: record.week,
            season: record.season,
            phase: record.phase
        )

        // Inbox rule: the user always gets a receipt for his own trades, and a
        // wire note for league business he would want to know about — a star
        // changing teams, first-round capital moving, or a division rival
        // making a move. Everything else stays news-feed-only so the inbox
        // keeps its signal.
        var inbox: InboxMessage?
        if let userTeamID,
           record.initiatorTeamID == userTeamID || record.partnerTeamID == userTeamID {
            let userIsInitiator = record.initiatorTeamID == userTeamID
            inbox = InboxEngine.tradeCompletedMessage(
                partnerName: userIsInitiator ? partnerName : initiatorName,
                partnerAbbr: userIsInitiator ? partnerAbbr : initiatorAbbr,
                weReceive: clause(userIsInitiator ? received : sent, long: true),
                weSend: clause(userIsInitiator ? sent : received, long: true),
                dateString: dateString,
                wasOurProposal: userIsInitiator
            )
        } else {
            let userTeam = userTeamID.flatMap { teamsByID[$0] }
            let isDivisionRival = userTeam.map { home in
                [initiator, partner].contains {
                    $0?.conference == home.conference && $0?.division == home.division
                }
            } ?? false
            if isBigDeal || isDivisionRival {
                inbox = InboxEngine.leagueTradeWireMessage(
                    headline: headline,
                    detail: body,
                    dateString: dateString,
                    isDivisionRival: isDivisionRival
                )
            }
        }

        return (news, inbox)
    }

    // MARK: - Asset Parsing

    /// One asset lifted back out of a ledger summary string
    /// (`"WR Marcus Vale (84 OVR), 2027 R2 P48"`).
    ///
    /// Parsing our own formatter's output is not elegant, but it is the only
    /// input a 12-season-old ledger row still has — and it lets the copy say
    /// "a 2027 2nd" where the ledger says "2027 R2 P48".
    private enum Asset {
        case player(position: String, name: String, overall: Int)
        case pick(year: Int, round: Int)
        case other(String)

        var overall: Int? {
            if case .player(_, _, let overall) = self { return overall }
            return nil
        }
    }

    private static func parse(_ summary: String) -> [Asset] {
        guard !summary.isEmpty, summary != "nothing" else { return [] }
        return summary.components(separatedBy: ", ").compactMap { token in
            let text = token.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return nil }
            return parsePick(text) ?? parsePlayer(text) ?? .other(text)
        }
    }

    /// `"2027 R2 P48"` → `.pick(year: 2027, round: 2)`. The pick NUMBER is
    /// dropped on purpose: for a future pick it is a provisional placeholder,
    /// so quoting it would invent precision the league does not have.
    private static func parsePick(_ text: String) -> Asset? {
        let parts = text.split(separator: " ")
        guard parts.count >= 2,
              parts[0].count == 4,
              let year = Int(parts[0]),
              parts[1].hasPrefix("R"),
              let round = Int(parts[1].dropFirst())
        else { return nil }
        return .pick(year: year, round: round)
    }

    /// `"WR Marcus Vale (84 OVR)"` → `.player(position: "WR", …)`.
    private static func parsePlayer(_ text: String) -> Asset? {
        guard text.hasSuffix(" OVR)"), let open = text.lastIndex(of: "(") else { return nil }
        let head = text[text.startIndex..<open].trimmingCharacters(in: .whitespaces)
        let rating = text[text.index(after: open)...]
            .replacingOccurrences(of: " OVR)", with: "")
        guard let overall = Int(rating) else { return nil }
        var words = head.split(separator: " ").map(String.init)
        guard words.count >= 2 else { return nil }
        let position = words.removeFirst()
        return .player(position: position, name: words.joined(separator: " "), overall: overall)
    }

    private static func bestPlayer(in assets: [Asset]) -> Asset? {
        assets
            .filter { $0.overall != nil }
            .max { ($0.overall ?? 0) < ($1.overall ?? 0) }
    }

    private static func contains(player: Asset, in assets: [Asset]) -> Bool {
        guard case .player(_, let name, let overall) = player else { return false }
        return assets.contains { asset in
            if case .player(_, let otherName, let otherOverall) = asset {
                return otherName == name && otherOverall == overall
            }
            return false
        }
    }

    // MARK: - Copy Helpers

    private static func shortLabel(_ asset: Asset) -> String {
        switch asset {
        case .player(let position, let name, _): return "\(position) \(name)"
        case .pick(let year, let round):         return "a \(year) \(ordinal(round))"
        case .other(let text):                   return text
        }
    }

    private static func longLabel(_ asset: Asset) -> String {
        switch asset {
        case .player(let position, let name, let overall):
            return "\(position) \(name) (\(overall) OVR)"
        case .pick(let year, let round):
            return "a \(year) \(ordinal(round))-round pick"
        case .other(let text):
            return text
        }
    }

    /// `"a 2027 2nd + G Tavon Reeves"`. `limit` keeps headlines from running
    /// off the row on a five-asset package.
    private static func clause(_ assets: [Asset], long: Bool = false, limit: Int? = nil) -> String {
        guard !assets.isEmpty else { return "nothing" }
        let labels = assets.map { long ? longLabel($0) : shortLabel($0) }
        if let limit, labels.count > limit {
            return labels.prefix(limit).joined(separator: " + ") + " and more"
        }
        return labels.joined(separator: " + ")
    }

    private static func ordinal(_ round: Int) -> String {
        switch round {
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        default: return "\(round)th"
        }
    }

    private static func contextSentence(
        kind: TradeRecordKind,
        sellerAbbr: String,
        acquirerAbbr: String
    ) -> String {
        // Deliberately NOT an exhaustive switch: Wave 2 keeps adding ledger kinds
        // (offseason windows, cap-cut days) and a new market path must be able to
        // announce itself with the neutral line rather than breaking the build on
        // this file.
        if kind == .aiDeadline {
            return "\(sellerAbbr) are clearly selling; \(acquirerAbbr) believe they are one piece away."
        }
        if kind == .draftDay {
            return "The swap came together on the clock during the draft."
        }
        if kind == .holdoutForced {
            return "\(sellerAbbr) had a holdout on their hands, and the return reflects it."
        }
        return "The two front offices finalized the paperwork with the league office."
    }

    private static func valueSentence(paid: Int, got: Int, acquirerAbbr: String) -> String {
        guard got > 0, paid > 0 else {
            return "League evaluators called it a low-cost move."
        }
        let ratio = Double(paid) / Double(got)
        if ratio >= 1.15 { return "Rival executives called the price steep." }
        if ratio <= 0.85 { return "\(acquirerAbbr) look like they got a bargain." }
        return "Both sides walked away calling it fair value."
    }
}

// MARK: - Career Milestone News Factory (#23)

/// Turns the season-history rows week 18 has just written into the two surfaces
/// a career milestone has to reach: the league news feed, and the user's inbox
/// whenever the player is one of his own.
///
/// Same shape and the same reasoning as `TradeNewsFactory`. The league moves 30+
/// players a year and a silent feed reads as a league where nothing happens —
/// careers are the other half of that. A back passing 10 000 yards, a rusher
/// reaching 100 sacks and a quarterback building a Canton case are the moments
/// season-long stat tracking exists to produce, and until now the numbers were
/// persisted and never spoken about.
///
/// Everything here is DERIVED from `PlayerSeasonHistory`; nothing is invented and
/// nothing is stored. Run it twice on the same season and it says the same thing,
/// which is what lets the week-18 handler call it without a "already announced"
/// ledger: a crossing is measured between last season's career total and this
/// one's, so it can only fire in the season it happened.
enum MilestoneNewsFactory {

    /// Feed items about OTHER teams' players, per season. The user's own roster
    /// is never capped — his players' careers are the ones he is guaranteed to
    /// care about — but the rest of the league has to stay a feed rather than a
    /// record book dump.
    static let maxLeagueItems = 5

    struct Announcement {
        let news: [NewsItem]
        let inbox: [InboxMessage]
    }

    /// Every milestone the just-finished season produced.
    ///
    /// - Parameters:
    ///   - players: The whole league; retired players are skipped (their story is
    ///     the retirement ceremony, not a milestone note).
    ///   - historyByPlayer: Season rows keyed by player, INCLUDING the row for
    ///     `season` — the week-18 snapshot must already be written or every
    ///     crossing measures zero against zero.
    ///   - userTeamID: `nil` for a career with no team (the harness), which then
    ///     produces news only.
    static func seasonMilestones(
        players: [Player],
        historyByPlayer: [UUID: [PlayerSeasonHistory]],
        teamsByID: [UUID: Team],
        userTeamID: UUID?,
        season: Int
    ) -> Announcement {
        /// One player's worth of findings, before the league-wide cap is applied.
        struct Finding {
            let player: Player
            let crossing: MilestoneTracker.CareerCrossing?
            let hallOfFameSummary: String?
        }

        var userFindings: [Finding] = []
        var leagueFindings: [Finding] = []

        for player in players where !player.isRetired {
            guard let history = historyByPlayer[player.id], !history.isEmpty else { continue }
            let after = MilestoneTracker.careerFacts(history: history, through: season)
            guard !after.isEmpty else { continue }
            let before = MilestoneTracker.careerFacts(history: history, through: season - 1)

            var findings: [Finding] = []
            // The loudest round number he passed. One a season keeps the feed
            // readable even when a monster year clears two rungs at once.
            if let crossing = MilestoneTracker.careerCrossings(
                position: player.position, before: before, after: after
            ).first {
                findings.append(Finding(player: player, crossing: crossing, hallOfFameSummary: nil))
            }
            // Hall of Fame watch fires on the CROSSING of the threshold, so it
            // reads once per career instead of every year of a great one.
            let caseBefore = MilestoneTracker.hallOfFameCase(position: player.position, facts: before)
            let caseAfter = MilestoneTracker.hallOfFameCase(position: player.position, facts: after)
            if caseBefore < MilestoneTracker.hallOfFameWatchThreshold,
               caseAfter >= MilestoneTracker.hallOfFameWatchThreshold {
                findings.append(Finding(
                    player: player,
                    crossing: nil,
                    hallOfFameSummary: MilestoneTracker.hallOfFameSummary(
                        position: player.position, facts: after
                    )
                ))
            }

            guard !findings.isEmpty else { continue }
            if userTeamID != nil && player.teamID == userTeamID {
                userFindings.append(contentsOf: findings)
            } else {
                leagueFindings.append(contentsOf: findings)
            }
        }

        // The biggest names lead, and the deepest milestone breaks a tie: a
        // 15 000-yard back outranks a 2 500-yard one at the same rating.
        leagueFindings.sort {
            if $0.player.overall != $1.player.overall {
                return $0.player.overall > $1.player.overall
            }
            return ($0.crossing?.milestone ?? 0) > ($1.crossing?.milestone ?? 0)
        }

        var news: [NewsItem] = []
        var inbox: [InboxMessage] = []

        for finding in userFindings + leagueFindings.prefix(maxLeagueItems) {
            let teamName = finding.player.teamID.flatMap { teamsByID[$0]?.fullName }
            let copy = finding.crossing.map {
                crossingCopy(player: finding.player, crossing: $0, teamName: teamName)
            } ?? hallOfFameCopy(
                player: finding.player,
                summary: finding.hallOfFameSummary ?? "",
                teamName: teamName
            )

            news.append(NewsItem(
                headline: copy.headline,
                body: copy.body,
                category: .award,
                week: 18,
                season: season,
                relatedTeamID: finding.player.teamID,
                relatedPlayerID: finding.player.id,
                sentiment: .positive
            ))

            if userTeamID != nil, finding.player.teamID == userTeamID {
                inbox.append(InboxMessage(
                    sender: .leagueOffice,
                    subject: copy.headline,
                    body: copy.body,
                    date: "Week 18, Season \(season)",
                    category: .leagueNotice
                ))
            }
        }

        return Announcement(news: news, inbox: inbox)
    }

    // MARK: - Copy

    /// Round numbers print bare, without thousands separators — the same way
    /// every other career number in the game is written (`MilestoneTracker`'s
    /// storyline bodies), and locale-proof by construction.
    private static func number(_ value: Double, fractional: Bool) -> String {
        fractional
            ? String(format: "%.1f", value)
            : "\(Int(value.rounded()))"
    }

    private static func crossingCopy(
        player: Player,
        crossing: MilestoneTracker.CareerCrossing,
        teamName: String?
    ) -> (headline: String, body: String) {
        let milestone = number(crossing.milestone, fractional: false)
        let total = number(crossing.total, fractional: crossing.isFractional)
        let club = teamName.map { "The \($0) " } ?? "The "
        return (
            headline: "\(player.fullName) reaches \(milestone) career \(crossing.category)",
            body: "\(club)\(player.position.rawValue) went past \(milestone) career \(crossing.category) this season and finished the year on \(total). It is the kind of number that turns a good career into a résumé."
        )
    }

    private static func hallOfFameCopy(
        player: Player,
        summary: String,
        teamName: String?
    ) -> (headline: String, body: String) {
        let club = teamName.map { "the \($0) " } ?? ""
        return (
            headline: "Hall of Fame watch: \(player.fullName)",
            body: "Voters have started saying the word out loud about \(club)\(player.position.rawValue). \(summary) — at \(player.age), with the career still going, \(player.lastName) has built a case that no longer needs a qualifier."
        )
    }

}
