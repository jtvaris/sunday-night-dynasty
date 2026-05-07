import Foundation

/// Event surfaced to the user when a competing team has topped their offer
/// for a free agent. Drives the slide-in `OutbidAlertBanner` (A4).
struct OutbidEvent: Identifiable, Hashable {
    let id: UUID
    let playerID: UUID
    let playerName: String
    let outbidByTeamID: UUID
    let outbidByTeamAbbrev: String
    let userOfferAnnualValue: Int      // thousands per year
    let competingOfferAnnualValue: Int // thousands per year
    let respondByDeadline: Date

    init(
        id: UUID = UUID(),
        playerID: UUID,
        playerName: String,
        outbidByTeamID: UUID,
        outbidByTeamAbbrev: String,
        userOfferAnnualValue: Int,
        competingOfferAnnualValue: Int,
        respondByDeadline: Date
    ) {
        self.id = id
        self.playerID = playerID
        self.playerName = playerName
        self.outbidByTeamID = outbidByTeamID
        self.outbidByTeamAbbrev = outbidByTeamAbbrev
        self.userOfferAnnualValue = userOfferAnnualValue
        self.competingOfferAnnualValue = competingOfferAnnualValue
        self.respondByDeadline = respondByDeadline
    }
}

/// Detects bidding-war "outbid" events: any time a competing team's bid for a
/// player has a higher annual value than the user team's most recent offer.
@MainActor
enum OutbidNotifier {

    /// Window in which the user can respond before the offer is locked in.
    static let respondWindow: TimeInterval = 12 * 60 * 60 // 12h

    /// Returns one OutbidEvent per player where the user's pending bid has been
    /// surpassed in annual value by a competing team. Most recent competing bid
    /// per player is used as the trigger.
    static func detect(
        userTeamID: UUID,
        bids: [FABid],
        playerNames: [UUID: String],
        teamAbbrevs: [UUID: String]
    ) -> [OutbidEvent] {
        // Group bids by player; ignore expired or accepted (resolved) bids.
        let actionable = bids.filter {
            $0.status == .pending || $0.status == .countered || $0.status == .outbid
        }

        let byPlayer = Dictionary(grouping: actionable, by: { $0.playerID })
        var events: [OutbidEvent] = []

        for (playerID, playerBids) in byPlayer {
            // User's latest bid for this player (highest annual value among user bids)
            let userBids = playerBids.filter { $0.teamID == userTeamID }
            guard let userBest = userBids.max(by: { annualValue(of: $0) < annualValue(of: $1) }) else {
                continue
            }
            let userAAV = annualValue(of: userBest)

            // Competing best (highest annual value from any other team)
            let competingBids = playerBids.filter { $0.teamID != userTeamID }
            guard let competingBest = competingBids.max(by: {
                annualValue(of: $0) < annualValue(of: $1)
            }) else { continue }
            let competingAAV = annualValue(of: competingBest)

            guard competingAAV > userAAV else { continue }

            // Use the competing bid's expiry if it's in the future, else +12h from now.
            let now = Date()
            let deadline: Date
            if let bidExpiry = competingBest.expiresAt, bidExpiry > now {
                deadline = bidExpiry
            } else {
                deadline = now.addingTimeInterval(respondWindow)
            }

            let event = OutbidEvent(
                playerID: playerID,
                playerName: playerNames[playerID] ?? "Unknown",
                outbidByTeamID: competingBest.teamID,
                outbidByTeamAbbrev: teamAbbrevs[competingBest.teamID] ?? "???",
                userOfferAnnualValue: userAAV,
                competingOfferAnnualValue: competingAAV,
                respondByDeadline: deadline
            )
            events.append(event)
        }

        // Sort by largest gap first — most urgent at top
        return events.sorted { lhs, rhs in
            let gapA = lhs.competingOfferAnnualValue - lhs.userOfferAnnualValue
            let gapB = rhs.competingOfferAnnualValue - rhs.userOfferAnnualValue
            return gapA > gapB
        }
    }

    // MARK: - Private

    private static func annualValue(of bid: FABid) -> Int {
        guard bid.years > 0 else { return bid.baseSalary + bid.signingBonus }
        return bid.baseSalary + (bid.signingBonus / max(bid.years, 1))
    }
}
