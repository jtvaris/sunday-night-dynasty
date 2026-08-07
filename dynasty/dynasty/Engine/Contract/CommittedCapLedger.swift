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

        /// FORWARD rows only: `Player.contractYearsRemaining` as it stood before
        /// the commitment was written, when the write RAISED it.
        ///
        /// `ContractEngine.applyFranchiseTag` floors the clock at 1 so a man
        /// whose deal has already run to 0 still carries his year of club
        /// control. Without this stash `removeFranchiseTag` could not undo that
        /// floor — it had no way to tell "was already at 1" from "was raised from
        /// 0" — so rescinding left him at 1, i.e. under contract for a year the
        /// club never agreed to. Nil means the write changed nothing and the
        /// remove must leave the clock alone.
        ///
        /// Optional because the table is persisted JSON: rows written before this
        /// field existed decode as nil, which is exactly the "leave it alone"
        /// case. (`Reservation` has no custom `CodingKeys`, so the synthesised
        /// decoder treats a missing optional as nil.)
        var priorYears: Int?

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
    }

    // MARK: - Storage keys

    /// Base key — namespaced per save through `CareerScopedDefaults.key`.
    /// Listed in `CareerScopedDefaults.keys` so a deleted save takes its
    /// commitments with it.
    static let defaultsKey = "committedCapReservations"

    /// Base key for the FORWARD table — see the "Forward commitments" section
    /// below for why it is a second table rather than more rows in the first.
    static let forwardDefaultsKey = "committedCapForwardCommitments"

    private static func storageKey(_ careerID: UUID) -> String {
        CareerScopedDefaults.key(defaultsKey, careerID: careerID)
    }

    private static func forwardStorageKey(_ careerID: UUID) -> String {
        CareerScopedDefaults.key(forwardDefaultsKey, careerID: careerID)
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
            priorYears: nil,   // forward-only field; an offer touches no clock
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
    /// `CareerScopedDefaults.purge`, which lists both keys).
    static func purge(careerID: UUID) {
        UserDefaults.standard.removeObject(forKey: storageKey(careerID))
        UserDefaults.standard.removeObject(forKey: forwardStorageKey(careerID))
    }

    // MARK: - Forward Commitments (task #127)

    /// Money the club has promised for a league year that has **not started
    /// yet**.
    ///
    /// **The hole this closes.** A franchise tag is decided in the offseason and
    /// binds the NEXT league year: the man's existing deal keeps running and
    /// being paid through the season just played, and the tag number replaces it
    /// from the new league year. `ContractEngine.applyFranchiseTag` used to book
    /// it the other way round — it overwrote `annualSalary` with the tag and
    /// moved `Team.currentCapUsage` by the difference on the spot, so tagging a
    /// quarterback at $32.8M whose current deal paid $36.9M *gave the club back
    /// $4.0M of this year's room*. The decision showed up as a refund in the year
    /// before the one it applies to.
    ///
    /// Fixing that leaves the tag number with nowhere to live between the tap and
    /// the March rollover that consumes it, which is what this table is: the same
    /// careerID-scoped `UserDefaults` storage, the same `Reservation` row and the
    /// same `release`/`purge` discipline as the free-agency half above, with one
    /// difference in meaning — `seasonYear` is the league year the money **binds
    /// in**, not the year the promise was made in.
    ///
    /// **Why a second table and not more rows in the first.** The offer table's
    /// three defences are all built around "a row is only live in the season it
    /// was stamped with": `committed`/`availability` filter on `seasonYear ==
    /// season`, `prune` DELETES anything stamped differently, and `clearAll`
    /// empties the lot when the market closes. Every one of those would be wrong
    /// for a row that is deliberately stamped a year ahead — `prune` would
    /// silently eat the tag. Splitting the storage keeps both sets of rules
    /// intact and makes the two kinds of promise impossible to confuse.
    ///
    /// **Why it cannot leak.** ``consumeForward(careerID:bindingSeason:)`` is a
    /// read-and-delete that takes everything binding at or before the year being
    /// opened, so an orphan row — a tagged man who retired, was cut, or had his
    /// flag cleared by some other engine — is dropped by the same pass that
    /// settles the live ones. A save that never reaches another rollover is
    /// purged with the rest of its career state.

    // There is deliberately NO year-filtered listing or club-wide
    // `forwardCommitted(careerID:season:)` reader above the sum below. Both are
    // the obvious shape and both are traps: a row can outlive the man it was
    // written for, so any read that filters by year alone will keep charging a
    // club for a player it released. Every consumer goes through the
    // player-scoped sum below.

    /// **Forward money owed in `season` by these players and nobody else**, in
    /// thousands. The read every cap projection in the app should use.
    ///
    /// Player-scoped rather than a blind sum over the table, and that is the
    /// whole point. A row can outlive the man it was written for — a tagged
    /// player who is then released, retires or has his flag cleared by another
    /// engine keeps his row until the next rollover's `consumeForward` drops it,
    /// because nothing else sweeps a table stamped a year ahead. Summing the
    /// table would keep charging a club for a player it no longer employs, on a
    /// screen whose whole job is telling the user what he can afford. Callers
    /// pass the ids they actually hold — normally `roster.filter(\.isFranchiseTagged)`
    /// — so an orphan simply is not in the set.
    static func forwardCommitted(playerIDs: some Sequence<UUID>, careerID: UUID?, season: Int) -> Int {
        guard let careerID else { return 0 }
        let rows = forwardTable(careerID: careerID)
        return playerIDs.reduce(0) { total, id in
            guard let row = rows[id.uuidString],
                  season >= row.seasonYear,
                  season < row.seasonYear + max(1, row.years)
            else { return total }
            return total + row.annualCapHit
        }
    }

    /// This save's forward commitment for one player, if any.
    static func forwardCommitment(playerID: UUID, careerID: UUID?) -> Reservation? {
        guard let careerID else { return nil }
        return forwardTable(careerID: careerID)[playerID.uuidString]
    }

    /// Records money promised for a future league year.
    ///
    /// **Deliberately never refuses.** The free-agency half hard-blocks because
    /// an outstanding offer is a promise the club cannot take back once the
    /// player accepts it — the cap has to be able to say no. A forward
    /// commitment is a different animal: the franchise tag is the club's own
    /// unilateral decision, the year it charges has not opened yet, and the GM
    /// has a whole offseason of cuts, restructures and non-tenders to get legal
    /// before it does. Refusing here would be the cap gate answering a question
    /// about 2027 with 2026's bank balance — exactly the year confusion this
    /// table exists to end. The surface quotes the projected room instead and
    /// lets the user decide.
    ///
    /// - Parameter priorYears: the contract clock as it stood before the caller
    ///   raised it, or nil when the caller changed nothing — see
    ///   ``Reservation/priorYears``.
    static func commitForward(
        playerID: UUID,
        playerName: String,
        annualCapHit: Int,
        baseSalary: Int? = nil,
        years: Int,
        priorYears: Int? = nil,
        bindingSeason: Int,
        careerID: UUID?
    ) {
        guard let careerID else { return }
        var rows = forwardTable(careerID: careerID)
        rows[playerID.uuidString] = Reservation(
            playerID: playerID,
            playerName: playerName,
            annualCapHit: max(0, annualCapHit),
            baseSalary: baseSalary.map { max(0, $0) },
            years: max(1, years),
            priorYears: priorYears,
            seasonYear: bindingSeason,
            submittedAt: .now
        )
        writeForward(rows, careerID: careerID)
    }

    /// Takes one forward commitment back off the books — the symmetric undo of
    /// ``commitForward``, which is what "Remove Tag" is.
    static func releaseForward(playerID: UUID, careerID: UUID?) {
        guard let careerID else { return }
        var rows = forwardTable(careerID: careerID)
        guard rows.removeValue(forKey: playerID.uuidString) != nil else { return }
        writeForward(rows, careerID: careerID)
    }

    /// **The rollover's read.** Returns every commitment that binds at or before
    /// `bindingSeason` and REMOVES it from the table in the same call.
    ///
    /// Read-and-delete rather than read-then-delete because the two must not be
    /// separable: a caller that settled the rows and then failed to clear them
    /// would charge the same tag again at the next rollover. `<=` and not `==`
    /// so a row from a league year that somehow never got consumed (a save
    /// restored mid-offseason, a rollover run by a path that predates this
    /// table) is settled late rather than carried forever.
    @discardableResult
    static func consumeForward(careerID: UUID?, bindingSeason: Int) -> [Reservation] {
        guard let careerID else { return [] }
        let rows = forwardTable(careerID: careerID)
        let due = rows.values.filter { $0.seasonYear <= bindingSeason }
        guard !due.isEmpty else { return [] }
        let kept = rows.filter { $0.value.seasonYear > bindingSeason }
        writeForward(kept, careerID: careerID)
        return due.sorted { $0.annualCapHit > $1.annualCapHit }
    }

    // There is deliberately no `clearAllForward`. Nothing in normal play would
    // call it — the rollover consumes what is due and "Remove Tag" releases what
    // the user changed his mind about — and save deletion already takes the
    // table with it: `forwardDefaultsKey` is listed on `CareerScopedDefaults`.

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

    private static func forwardTable(careerID: UUID) -> [String: Reservation] {
        guard let data = UserDefaults.standard.data(forKey: forwardStorageKey(careerID)),
              let rows = try? JSONDecoder().decode([String: Reservation].self, from: data)
        else { return [:] }
        return rows
    }

    private static func writeForward(_ rows: [String: Reservation], careerID: UUID) {
        let key = forwardStorageKey(careerID)
        guard !rows.isEmpty else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        guard let data = try? JSONEncoder().encode(rows) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
