import Foundation

// MARK: - Committed Cap Ledger (cap-compliance wave, PREVENTION half)

/// Cap the user has PROMISED but not yet spent.
///
/// **The hole this closes.** `Team.currentCapUsage` is a ledger of contracts
/// that exist. A free-agency offer is not a contract — it is an option the
/// player holds against the club — so until he signs it costs nothing, and the
/// offer screens happily let the user put $40M of offers out against $12M of
/// room. Every one of them could be accepted in the same round; the club has
/// promised money it does not have. Real front offices do not work that way:
/// an outstanding offer is committed cap the moment it leaves the building, and
/// the number a GM negotiates against is *room minus commitments*.
///
/// So this is the second half of the club's books: a per-save table of
/// outstanding user offers, and one derived number — ``Availability/available``
/// — that every offer surface quotes instead of `Team.availableCap`.
///
/// **Storage.** careerID-scoped `UserDefaults` through `CareerScopedDefaults`,
/// exactly like `NegotiationLedger` and `ContractIncentiveRegistry` next door:
/// no SwiftData model, no schema registration, no migration, and the same
/// `careerID` namespacing every other piece of career state got. Listed in
/// `CareerScopedDefaults.keys` so deleting a save purges its commitments.
///
/// **Why it cannot leak.** A reservation is a promise with a shelf life, and a
/// stale one would silently eat cap room forever — the worst failure mode this
/// file could have. Three defences, all of them self-healing:
///
/// 1. Every row carries the `seasonYear` it was made in. ``committed(careerID:season:)``
///    only counts rows stamped with the season being asked about, so a
///    reservation cannot survive a league year even if nothing ever cleans it up.
/// 2. ``prune(careerID:season:openPlayerIDs:)`` drops rows for anyone who is no
///    longer an open free agent (signed elsewhere, retired, off the market).
/// 3. ``clearAll(careerID:)`` empties the table when the market closes.
///
/// **Determinism.** Nothing here rolls a die and nothing here reads the clock
/// except to stamp `submittedAt` for display ordering.
enum CommittedCapLedger {

    // MARK: - Reservation

    /// One outstanding user offer, in the unit `Team.currentCapUsage` is kept in
    /// (thousands per year).
    struct Reservation: Codable, Equatable, Identifiable {

        /// The free agent the offer is out to.
        var playerID: UUID

        /// Cached for display so a pending-offers bar does not have to re-fetch
        /// the whole market to render three rows.
        var playerName: String

        /// The PER-YEAR cap charge the offer would create if accepted — salary
        /// plus prorated signing bonus, i.e. `NegotiationOffer.annualCapHit` and
        /// the same number `ContractEngine.applyNegotiatedDeal` books. Reserving
        /// the salary alone would under-reserve exactly the bonus, which is the
        /// half of a deal that used to be free money (see `applyNegotiatedDeal`).
        var annualCapHit: Int

        /// The BASE salary the user actually put on the table, when the caller
        /// knows it and it differs from the charge (#102 F5: a realistic deal
        /// for a veteran charges ~15 % above the base plus a prorated bonus).
        ///
        /// Optional because the table is persisted JSON and rows written before
        /// this field existed have to keep decoding; ``offeredSalary`` falls
        /// back to the charge, which is what those rows meant.
        var baseSalary: Int?

        var years: Int

        /// League year the offer was made in — see the leak note in the type doc.
        var seasonYear: Int

        var submittedAt: Date

        var id: UUID { playerID }

        /// What to put back on the dial when an offer is rehydrated. **Not**
        /// `annualCapHit`: re-seeding the composer with the charge would raise
        /// the club's own bid every time the screen was reloaded.
        var offeredSalary: Int { baseSalary ?? annualCapHit }

        /// What the whole deal is worth over its term. Display only: the cap is
        /// charged per league year, so only `annualCapHit` reserves room.
        var totalValue: Int { annualCapHit * max(1, years) }
    }

    // MARK: - Availability

    /// The three numbers an offer screen shows: room, commitments, and what is
    /// actually left to spend.
    struct Availability: Equatable {

        /// `Team.availableCap` — cap minus contracts that already exist.
        let capRoom: Int

        /// Sum of `annualCapHit` over this save's outstanding offers.
        let committed: Int

        /// How many offers are behind `committed`.
        let offerCount: Int

        /// False in sandbox, where the cap is switched off by definition. The
        /// numbers are still computed honestly so a screen can show them; they
        /// simply do not gate anything.
        let isEnforced: Bool

        /// **The number the user negotiates against.** Deliberately signed: a
        /// negative value is a club that has already promised more than it has,
        /// which is a state the acceptance-time backstop can produce and which
        /// the compliance workspace exists to resolve.
        var available: Int { capRoom - committed }

        /// Whether an offer of `annualCapHit` per year can be submitted.
        func canCommit(_ annualCapHit: Int) -> Bool {
            !isEnforced || annualCapHit <= available
        }

        static let unconstrained = Availability(
            capRoom: 0, committed: 0, offerCount: 0, isEnforced: false
        )
    }

    // MARK: - Reserve Outcome

    /// What ``reserve(playerID:playerName:annualCapHit:years:team:careerID:season:capMode:)``
    /// decided. The blocked case carries a finished, user-facing sentence so
    /// every offer surface refuses in the same words.
    enum ReserveOutcome: Equatable {
        /// The offer is on the books. `remaining` is what is left afterwards.
        case reserved(remaining: Int)
        /// Hard block — the offer was NOT recorded and must not be submitted.
        case blocked(available: Int, shortfall: Int, message: String)

        var isReserved: Bool {
            if case .reserved = self { return true }
            return false
        }
    }

    // MARK: - Storage keys

    /// Base key — namespaced per save through `CareerScopedDefaults.key`.
    /// Listed in `CareerScopedDefaults.keys` so a deleted save takes its
    /// commitments with it.
    static let defaultsKey = "committedCapReservations"

    private static func storageKey(_ careerID: UUID) -> String {
        CareerScopedDefaults.key(defaultsKey, careerID: careerID)
    }

    // MARK: - Reads

    /// Every outstanding offer in one save, newest first.
    static func reservations(careerID: UUID) -> [Reservation] {
        table(careerID: careerID)
            .values
            .sorted { $0.submittedAt > $1.submittedAt }
    }

    /// Outstanding offers made in `season` — the only ones that reserve room.
    static func reservations(careerID: UUID, season: Int) -> [Reservation] {
        reservations(careerID: careerID).filter { $0.seasonYear == season }
    }

    /// This save's outstanding offer for one player, if any.
    static func reservation(playerID: UUID, careerID: UUID) -> Reservation? {
        table(careerID: careerID)[playerID.uuidString]
    }

    /// Total per-year cap promised but not yet signed, in thousands.
    static func committed(careerID: UUID, season: Int) -> Int {
        reservations(careerID: careerID, season: season).reduce(0) { $0 + $1.annualCapHit }
    }

    /// Cap room, commitments and what is left — the offer screen's header row.
    ///
    /// - Parameter excludingPlayerID: an offer being EDITED does not compete
    ///   with itself. The offer sheet passes the player it is open on so raising
    ///   a $10M offer to $12M is priced as a $2M change, not as $12M on top of
    ///   the $10M already promised to the same man.
    static func availability(
        team: Team?,
        careerID: UUID?,
        season: Int,
        capMode: CapMode,
        excludingPlayerID: UUID? = nil
    ) -> Availability {
        guard let team else { return .unconstrained }
        guard let careerID else {
            return Availability(
                capRoom: team.availableCap,
                committed: 0,
                offerCount: 0,
                isEnforced: capMode != .sandbox
            )
        }

        let rows = reservations(careerID: careerID, season: season)
            .filter { $0.playerID != excludingPlayerID }

        return Availability(
            capRoom: team.availableCap,
            committed: rows.reduce(0) { $0 + $1.annualCapHit },
            offerCount: rows.count,
            isEnforced: capMode != .sandbox
        )
    }

    // MARK: - Writes

    /// Records an outstanding offer, or refuses it because the club cannot
    /// afford to have it accepted.
    ///
    /// **This is the hard block.** An offer that exceeds `available` is not
    /// clamped, not warned about and not recorded — it is refused, because the
    /// alternative is a club that can be forced over the cap by a decision it
    /// does not control (the player's). Sandbox never refuses.
    ///
    /// Re-reserving for a player who already has an offer REPLACES that row, so
    /// the ledger holds at most one commitment per free agent.
    @discardableResult
    static func reserve(
        playerID: UUID,
        playerName: String,
        annualCapHit: Int,
        baseSalary: Int? = nil,
        years: Int,
        team: Team?,
        careerID: UUID?,
        season: Int,
        capMode: CapMode
    ) -> ReserveOutcome {
        let charge = max(0, annualCapHit)
        let room = availability(
            team: team,
            careerID: careerID,
            season: season,
            capMode: capMode,
            excludingPlayerID: playerID
        )

        guard room.canCommit(charge) else {
            let shortfall = charge - room.available
            return .blocked(
                available: room.available,
                shortfall: shortfall,
                message: blockMessage(
                    playerName: playerName,
                    charge: charge,
                    available: room.available,
                    shortfall: shortfall,
                    pendingCount: room.offerCount
                )
            )
        }

        // Sandbox keeps no books at all: nothing gates on the number, and a
        // table nobody reads is a table that can only go stale.
        guard capMode != .sandbox, let careerID else {
            return .reserved(remaining: room.available)
        }

        var rows = table(careerID: careerID)
        rows[playerID.uuidString] = Reservation(
            playerID: playerID,
            playerName: playerName,
            annualCapHit: charge,
            baseSalary: baseSalary.map { max(0, $0) },
            years: max(1, years),
            seasonYear: season,
            submittedAt: .now
        )
        write(rows, careerID: careerID)

        return .reserved(remaining: room.available - charge)
    }

    /// Releases one commitment — a withdrawn offer, a signed deal (the charge
    /// becomes a real contract), or an offer the player turned down.
    static func release(playerID: UUID, careerID: UUID?) {
        guard let careerID else { return }
        var rows = table(careerID: careerID)
        guard rows.removeValue(forKey: playerID.uuidString) != nil else { return }
        write(rows, careerID: careerID)
    }

    /// Empties the table — the market closed, or the save is being reset.
    static func clearAll(careerID: UUID?) {
        guard let careerID else { return }
        UserDefaults.standard.removeObject(forKey: storageKey(careerID))
    }

    /// Drops every row that can no longer become a contract.
    ///
    /// Called with the ids still on the open market: anything else has signed,
    /// retired or otherwise left, and its promise cannot be collected. Rows from
    /// an earlier league year are dropped in the same pass — `committed` already
    /// ignores them, this is what stops the table growing without bound.
    ///
    /// Returns how many rows were dropped (0 = nothing to do).
    @discardableResult
    static func prune(careerID: UUID?, season: Int, openPlayerIDs: Set<UUID>) -> Int {
        guard let careerID else { return 0 }
        let rows = table(careerID: careerID)
        let kept = rows.filter { _, row in
            row.seasonYear == season && openPlayerIDs.contains(row.playerID)
        }
        guard kept.count != rows.count else { return 0 }
        write(kept, careerID: careerID)
        return rows.count - kept.count
    }

    /// Drops every scoped value for a deleted save (paired with
    /// `CareerScopedDefaults.purge`, which lists this key).
    static func purge(careerID: UUID) {
        UserDefaults.standard.removeObject(forKey: storageKey(careerID))
    }

    // MARK: - Copy

    /// The refusal sentence, in one place so every surface refuses identically.
    static func blockMessage(
        playerName: String,
        charge: Int,
        available: Int,
        shortfall: Int,
        pendingCount: Int
    ) -> String {
        let pending = pendingCount == 1
            ? "1 pending offer"
            : "\(pendingCount) pending offers"
        let head = "This offer charges \(money(charge)) per year against \(money(max(0, available))) of available cap"
        let tail = pendingCount > 0
            ? " (cap room less \(pending))."
            : "."
        return head + tail
            + " Withdraw an offer, clear \(money(shortfall)) of room, or lower the terms."
    }

    /// `12_500` -> `"$12.5M"`, `750` -> `"$750K"`. Local on purpose: the ledger
    /// has to be able to phrase its own refusal without reaching into the UI.
    static func money(_ thousands: Int) -> String {
        let sign = thousands < 0 ? "-" : ""
        let magnitude = abs(thousands)
        if magnitude >= 1_000 {
            return sign + String(format: "$%.1fM", Double(magnitude) / 1_000.0)
        }
        return sign + "$\(magnitude)K"
    }

    // MARK: - Storage

    private static func table(careerID: UUID) -> [String: Reservation] {
        guard let data = UserDefaults.standard.data(forKey: storageKey(careerID)),
              let rows = try? JSONDecoder().decode([String: Reservation].self, from: data)
        else { return [:] }
        return rows
    }

    private static func write(_ rows: [String: Reservation], careerID: UUID) {
        let key = storageKey(careerID)
        guard !rows.isEmpty else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        guard let data = try? JSONEncoder().encode(rows) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
