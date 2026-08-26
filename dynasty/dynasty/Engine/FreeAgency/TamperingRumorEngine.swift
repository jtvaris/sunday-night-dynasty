import Foundation

/// R23 — Legal tampering window.
///
/// Before the FA market officially opens, league insiders leak the projected
/// price range and the early suitors for the top upcoming free agents. The
/// projections come from the SAME pricing model the live FA market uses
/// (`FreeAgencyEngine.projectedAskingPrice`, i.e. market value × motivation
/// multiplier) and the suitors from the same need assessment AI bidding uses
/// (`FreeAgencyEngine.assessPositionNeed`), so the rumor mill is honest
/// decision support rather than noise.
enum TamperingRumorEngine {

    // MARK: - Types

    struct TamperingRumor: Identifiable {
        let id: UUID                // player id
        let playerName: String
        let position: String
        let overall: Int
        let age: Int
        /// Projected asking price in thousands/yr — same formula as the market.
        let projectedSalary: Int
        let motivation: Motivation
        /// Abbreviations of AI teams expected to pursue (need + cap based).
        let suitorAbbrs: [String]
        /// True when the player is leaving the user's own roster.
        let isOwnPlayer: Bool
    }

    // MARK: - Pool

    /// Players about to hit the market when the FA phase opens: contracts that
    /// already expired at week 18, plus final-year contracts that expire at the
    /// new league year. Franchise-tagged players are off the market.
    ///
    /// A rostered man is expiring at `contractYearsRemaining <= 1` — the same
    /// test `FinalPushView`'s own fetch and `ContractEngine.previewFreeAgents`
    /// use. This clause read `== 1`, which silently dropped the man whose deal
    /// has already run to 0 while he still holds his roster spot (a state
    /// `ContractEngine.removeFranchiseTag` names outright). Those men are on
    /// the Final Push list, so the leak board could be missing the very names
    /// its caption promises to flag in gold.
    static func upcomingFreeAgents(allPlayers: [Player]) -> [Player] {
        allPlayers.filter { player in
            guard !player.isFranchiseTagged, !player.isRetired else { return false }
            if player.teamID == nil && player.contractYearsRemaining == 0 { return true }
            return player.teamID != nil && player.contractYearsRemaining <= 1
        }
    }

    // MARK: - Rumor Generation

    /// Builds tampering rumors for the top `limit` upcoming free agents.
    /// Suitors are AI teams with a High/Critical need at the position and the
    /// cap room to pay the projected price — the same inputs the AI bidding
    /// rounds use, so what the rumors promise is what the market delivers.
    static func generateRumors(
        allPlayers: [Player],
        allTeams: [Team],
        userTeamID: UUID?,
        limit: Int = 8
    ) -> [TamperingRumor] {
        let upcoming = upcomingFreeAgents(allPlayers: allPlayers)
        let pool = upcoming
            .sorted { $0.overall > $1.overall }
            .prefix(limit)

        // What each club's OWN expiring men are still costing it. The window
        // opens before the league year turns, so `availableCap` is measured
        // against books that still carry every deal about to run out; judged on
        // that figure alone almost nobody clears a top free agent's price and
        // the whole leak board falls into the empty-suitors branch — eight rows
        // of "market still forming". The money these clubs will bid with is
        // exactly the money coming off, so it is counted here.
        let expiringRelief: [UUID: Int] = upcoming.reduce(into: [:]) { totals, player in
            guard let teamID = player.teamID else { return }
            totals[teamID, default: 0] += player.annualSalary
        }

        let avgCap = allTeams.isEmpty
            ? ContractEngine.openingSalaryCap
            : allTeams.reduce(0) { $0 + $1.salaryCap } / allTeams.count

        return pool.map { player in
            let projected = FreeAgencyEngine.projectedAskingPrice(player: player, salaryCap: avgCap)

            // Suitors: AI teams (never the player's current team) that need the
            // position badly and can afford the projected price. Critical needs
            // sort first, then deepest pockets.
            let suitors = allTeams
                .filter { $0.id != userTeamID && $0.id != player.teamID }
                .filter { $0.availableCap + (expiringRelief[$0.id] ?? 0) >= projected }
                .compactMap { team -> (abbr: String, need: FreeAgencyEngine.PositionNeedLevel, cap: Int)? in
                    let need = FreeAgencyEngine.assessPositionNeed(
                        team: team,
                        position: player.position,
                        allPlayers: allPlayers
                    )
                    guard need == .critical || need == .high else { return nil }
                    return (team.abbreviation, need, team.availableCap + (expiringRelief[team.id] ?? 0))
                }
                .sorted { lhs, rhs in
                    if (lhs.need == .critical) != (rhs.need == .critical) {
                        return lhs.need == .critical
                    }
                    return lhs.cap > rhs.cap
                }
                .prefix(3)
                .map(\.abbr)

            return TamperingRumor(
                id: player.id,
                playerName: player.fullName,
                position: player.position.rawValue,
                overall: player.overall,
                age: player.age,
                projectedSalary: projected,
                motivation: player.personality.motivation,
                suitorAbbrs: Array(suitors),
                isOwnPlayer: player.teamID != nil && player.teamID == userTeamID
            )
        }
    }

    /// Short insider blurb on what actually drives the player's decision.
    static func motivationBlurb(_ motivation: Motivation) -> String {
        switch motivation {
        case .money:   return "Expected to chase top dollar"
        case .winning: return "Wants to win now — contenders have the edge"
        case .stats:   return "Looking for a featured role"
        case .loyalty: return "Open to a discount to stay put"
        case .fame:    return "Drawn to the big-market spotlight"
        }
    }

    // MARK: - Inbox / News Output

    /// One digest message summarizing the tampering-window chatter.
    static func inboxDigest(rumors: [TamperingRumor], season: Int) -> InboxMessage? {
        guard !rumors.isEmpty else { return nil }

        var lines: [String] = []
        for rumor in rumors {
            let priceM = String(format: "$%.1fM", Double(rumor.projectedSalary) / 1000.0)
            let suitorText = rumor.suitorAbbrs.isEmpty
                ? "market still forming"
                : "\(rumor.suitorAbbrs.joined(separator: ", ")) circling"
            let ownTag = rumor.isOwnPlayer ? " [YOUR PLAYER]" : ""
            lines.append(
                "\u{2022} \(rumor.position) \(rumor.playerName) (\(rumor.overall) OVR)\(ownTag) — expected to command ~\(priceM)/yr; \(suitorText). \(motivationBlurb(rumor.motivation))."
            )
        }

        let body = """
        The legal tampering window is open. League sources are already leaking numbers ahead of the market opening — here's where the top names are headed:

        \(lines.joined(separator: "\n"))

        Projections use the same market model agents quote. If one of your own names is on this list, the Final Push is your last exclusive shot at him.
        """

        return InboxMessage(
            sender: .media(outlet: "League Insider"),
            subject: "Tampering Window: FA Market Preview",
            body: body,
            date: "Offseason - Free Agency, Season \(season)",
            category: .leagueNotice,
            actionRequired: false,
            actionDestination: .freeAgency
        )
    }

    /// News wire items for the loudest rumors (top 3).
    static func newsItems(rumors: [TamperingRumor], week: Int, season: Int) -> [NewsItem] {
        rumors.prefix(3).map { rumor in
            let priceM = String(format: "$%.1fM", Double(rumor.projectedSalary) / 1000.0)
            let suitorText = rumor.suitorAbbrs.isEmpty
                ? "Several teams are doing homework."
                : "\(rumor.suitorAbbrs.joined(separator: " and ")) reported interested."
            return NewsItem(
                headline: "Sources: \(rumor.playerName) expected to command \(priceM) per year",
                body: "\(rumor.position) \(rumor.playerName) (\(rumor.overall) OVR, age \(rumor.age)) headlines the tampering-window chatter. \(suitorText) \(motivationBlurb(rumor.motivation)).",
                category: .freeAgency,
                week: week,
                season: season,
                relatedPlayerID: rumor.id,
                sentiment: .neutral
            )
        }
    }
}
