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
