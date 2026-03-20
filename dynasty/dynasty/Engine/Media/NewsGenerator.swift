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

        // 1) Power rankings
        items.append(generatePowerRankings(teams: teams, week: week, season: season))

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
            items.append(NewsItem(
                headline: "Combine workouts set to begin",
                body: "Over 300 prospects will descend on the combine this week, looking to improve their draft stock with impressive athletic testing numbers.",
                category: .draft,
                week: 0,
                season: season,
                sentiment: .neutral
            ))
            items.append(NewsItem(
                headline: "Top QB prospect dazzles in throwing drills",
                body: "The consensus top quarterback in this year's class turned heads with his arm strength and accuracy, further solidifying his position as a potential first overall pick.",
                category: .draft,
                week: 0,
                season: season,
                sentiment: .positive
            ))
            items.append(NewsItem(
                headline: "Defensive lineman runs record 40-yard dash",
                body: "A 280-pound defensive tackle shocked scouts by running a sub-4.6 forty, the fastest ever recorded at the position during combine testing.",
                category: .draft,
                week: 0,
                season: season,
                sentiment: .positive
            ))

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

    // MARK: - Private Generators

    private static func generatePowerRankings(teams: [Team], week: Int, season: Int) -> NewsItem {
        let sorted = teams.sorted { lhs, rhs in
            let lhsWinPct = (lhs.wins + lhs.losses) > 0
                ? Double(lhs.wins) / Double(lhs.wins + lhs.losses)
                : 0.5
            let rhsWinPct = (rhs.wins + rhs.losses) > 0
                ? Double(rhs.wins) / Double(rhs.wins + rhs.losses)
                : 0.5
            return lhsWinPct > rhsWinPct
        }

        let topThree = sorted.prefix(3).map { $0.fullName }
        let headline = "Week \(week) Power Rankings: \(topThree.first ?? "TBD") holds top spot"
        let body: String
        if topThree.count >= 3 {
            body = "This week's top three: 1. \(topThree[0]), 2. \(topThree[1]), 3. \(topThree[2]). The race for the number one seed continues to tighten."
        } else {
            body = "The power rankings are taking shape as the season progresses."
        }

        return NewsItem(
            headline: headline,
            body: body,
            category: .teamRanking,
            week: week,
            season: season,
            sentiment: .neutral
        )
    }

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
}
