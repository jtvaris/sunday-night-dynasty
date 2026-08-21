import Foundation
import SwiftData

// MARK: - Persisted market state
//
// These types are the CONTENTS of `Career.udfaMarketData` (Wave 0, agent B —
// `OFFSEASON_ROSTER_PLAN.md` §2.4 / §3.2). They live here, next to the only
// engine that writes them, for the same reason `PreseasonState` lives next to
// `PreseasonEngine`: one owner per blob.
//
// Career-scoped by construction (invariant 6) — the blob is a column on the
// `Career` row, so a second save slot cannot see this market at all.

/// One standing offer on one undrafted man, for one round.
///
/// Not an `FABid` row. `FABid` is a `@Model`, and a market that writes ~90 rows
/// a round × 3 rounds × every season would put ~1 000 short-lived SwiftData rows
/// a career into the store for state whose whole lifetime is four phases. The
/// heat curve is still `BiddingHeatEngine`'s, though — see
/// ``UDFAMarketEngine/heat(prospectID:career:)``, which projects these into
/// transient `FABid` values so there is exactly one definition of what "six
/// clubs are in on him" means.
nonisolated struct UDFABid: Codable, Equatable {
    var prospectID: UUID
    var teamID: UUID
    /// Thousands per year.
    var salary: Int
    var years: Int
    /// The market round this offer was made in.
    var round: Int
    var submittedAt: Date

    init(
        prospectID: UUID,
        teamID: UUID,
        salary: Int,
        years: Int,
        round: Int,
        submittedAt: Date = Date()
    ) {
        self.prospectID = prospectID
        self.teamID = teamID
        self.salary = salary
        self.years = years
        self.round = round
        self.submittedAt = submittedAt
    }
}

/// A completed UDFA signing — the receipt, kept so a round summary can be
/// rebuilt after a cold launch.
nonisolated struct UDFASigning: Codable, Equatable {
    var prospectID: UUID
    var teamID: UUID
    var salary: Int
    var years: Int
    var round: Int
}

/// The whole market, as one decodable blob.
nonisolated struct UDFAMarketState: Codable {
    /// The season whose undrafted class this market is for. The idempotency
    /// stamp: `openMarket` refuses to re-seed a season it has already opened,
    /// which is what makes a re-entered `.otas` phase — or a cold launch in the
    /// middle of it — safe. Replaces `WeekAdvancer.udfaStageCompletedSeasons`,
    /// a PROCESS GLOBAL that did not survive a relaunch and so let the bulk
    /// signing pass run a second time over the same class.
    var season: Int

    /// `0` not opened · `1...roundCount` live · `roundCount + 1` closed.
    var round: Int

    var signings: [UDFASigning]

    /// Offers standing in the CURRENT round only. Resolution consumes them:
    /// an offer that did not win has expired, and the club (or the user) must
    /// come back with a better one next round. That is the drama.
    var bids: [UDFABid]

    /// **Who the market finished with**: the undrafted men nobody signed, as of
    /// the moment ``UDFAMarketEngine/closeMarket(career:prospects:teams:allPlayers:allCoaches:modelContext:)``
    /// settled it. Written there, read once, by the camp fill.
    ///
    /// It has to be recorded rather than re-derived. `closeMarket` clears
    /// `isDeclaringForDraft` on every survivor — that is defect D1's fix, and it
    /// is what stops the scouting screens listing men the market has finished
    /// with — so a moment later the pool predicate
    /// (`ScoutingEngine.udfaPoolMembers`) cannot tell a survivor apart from a man
    /// the Draft Day panel signed on draft night. This list is the only record.
    ///
    /// Optional so a blob written before the field existed still decodes: Swift's
    /// synthesized `Codable` does not fall back to a property's default value for
    /// a missing key, and a market blob that failed to decode would silently
    /// re-open a settled market.
    var unsignedProspectIDs: [UUID]?

    init(
        season: Int,
        round: Int = 0,
        signings: [UDFASigning] = [],
        bids: [UDFABid] = [],
        unsignedProspectIDs: [UUID]? = nil
    ) {
        self.season = season
        self.round = round
        self.signings = signings
        self.bids = bids
        self.unsignedProspectIDs = unsignedProspectIDs
    }

    /// The round number that means "this market is finished".
    static var closedRound: Int { UDFAMarketEngine.roundCount + 1 }

    var isOpen: Bool { (1...UDFAMarketEngine.roundCount).contains(round) }
    var isClosed: Bool { round >= UDFAMarketState.closedRound }
    /// True once the market has been seeded for this season, open or not.
    var hasOpened: Bool { round > 0 }

    func signingCount(for teamID: UUID) -> Int {
        signings.reduce(0) { $0 + ($1.teamID == teamID ? 1 : 0) }
    }

    func isSigned(_ prospectID: UUID) -> Bool {
        signings.contains { $0.prospectID == prospectID }
    }

    func offers(on prospectID: UUID) -> [UDFABid] {
        bids.filter { $0.prospectID == prospectID }
    }

    func offer(on prospectID: UUID, by teamID: UUID) -> UDFABid? {
        bids.first { $0.prospectID == prospectID && $0.teamID == teamID }
    }
}

// MARK: - The market

/// #204 — the undrafted free-agent market.
///
/// ## What this replaces
///
/// Two unrelated UDFA paths shipped side by side and shared no pool definition,
/// no quota and no ordering (`OFFSEASON_ROSTER_PLAN.md` §0, audit A):
///
/// 1. `DraftDayCoordinator.prepareUDFAStage / signUDFA / finishUDFASigning`,
///    reachable **only** from inside the Draft Day route — a user who advanced
///    the calendar out of the draft never saw a UDFA in his life.
///
///    Wave 1 left this path standing beside the new market, and #208 G2 is what
///    that cost. `finishUDFASigning` signed ten men per AI club on draft night
///    and then cleared `isDeclaringForDraft` on the whole remainder, so by the
///    time the advance reached ``openMarket`` the pool predicate was empty, the
///    market opened CLOSED, `closeMarket` wrote an empty survivor list, and
///    `CampRosterEngine`'s undrafted source — which reads exactly that list —
///    did not exist. The draft-night panel now closes the **user's** window and
///    consumes nobody else; this engine is the only market again.
/// 2. A bulk fallback in `WeekAdvancer case .otas` that explicitly excluded the
///    user's own club (`teams.filter { $0.id != career.teamID }`) and then sent
///    him an inbox message about the market he had just been left out of.
///
/// The bulk path had three named defects, and each rule below answers one:
/// **D1** it never cleared `prospect.isDeclaringForDraft`, so signed men stayed
/// "available" on every scouting screen; **D2** its inbox message printed the
/// pool's top five off a `trueOverall` sort, straight past the fog; **D3** it
/// signed with no cap check, no need matching and no roster ceiling.
///
/// ## Prospect-native, on purpose
///
/// The market prices `CollegeProspect`s and never builds a `Player` before a
/// deal is struck (§2.1). Two reasons, both load-bearing:
///
/// - **Fog.** A `Player` carries true attributes. The user bids on the bands his
///   own department produced (`scoutedOverallGrade`, `scoutedPotentialLabel`),
///   so the fog is the DATA he has, not a display convention laid over the truth
///   (invariant 5).
/// - **Faces.** `DraftEngine.convertUDFAToPlayer` claims a face out of a 3 584-id
///   pool that `MultiSeasonSmokeTest.auditFaces` already reports running to
///   `free=0`. Converting ~110 candidates a season to price a market would burn
///   faces on men nobody signs.
///
/// ## No duplicated market math
///
/// `SigningInterestEngine.interest(candidate:…)` decides who a man signs with,
/// `BiddingHeatEngine.computeHeat` sets the temperature, `FrenzyHeatTier`
/// inflates the price, `PlayerPreferenceEngine.offerRanking` tells the user where
/// he stands and `OutbidNotifier.detect` tells him he has been topped. All five
/// are the free-agency engines, reused — this file adds the *market machine*,
/// not a second pricing model.
///
/// ## Integration surface — where each door is called from
///
/// ```
/// openMarket(career:prospects:teams:allPlayers:)   WeekAdvancer .draft exit — seeds, signs nobody
/// closeMarket(career:…)                            WeekAdvancer .otas  exit — settles what is left
/// submitUserOffer(career:prospect:…)               the board's commit   ── NOT WIRED YET
/// withdrawUserOffer(career:prospectID:)            the board's undo     ── NOT WIRED YET
/// runAIRound(career:…)                             the board's "next round" ── NOT WIRED YET
/// ```
///
/// **The calendar half is live; the board is not.** The three user doors wait on
/// `UI/FreeAgency/UDFABoardView.swift`, and until it lands the user's club makes
/// no offers at OTAs — `postAIOffers` bids for the 31 AI clubs only, never for
/// him, so nothing signs players on his behalf. That is exactly the reach the
/// deleted bulk block had (it excluded his club too), minus its three defects,
/// and his interactive UDFA surface is still the Draft Day panel. The board is
/// an addition to make, not a regression to carry.
///
/// `closeMarket` is safe to call at any point, including on a market the user
/// never opened: it runs the rounds that are still owed and then settles. A user
/// who ignores the market is not punished for it (risk R9) — he simply carries a
/// smaller camp roster, which is legal.
@MainActor
enum UDFAMarketEngine {

    // MARK: - Tuning
    //
    // Every constant here is a level, not a mechanism. §6/B10 of the plan owns
    // the measured numbers; the doc comments say what each one trades against so
    // the measurement pass knows which way to turn them.

    /// Rounds the market runs before it settles. Three, matching the FA market's
    /// round shape (`Career.freeAgencyRound`) — long enough that being outbid in
    /// round 1 is a setback rather than the end, short enough to be three taps.
    nonisolated static let roundCount = 3

    /// Most UDFAs any one club may sign, the user's club included. The real
    /// number is 15-20; this league's undrafted remainder is ~100-126 men against
    /// 32 clubs, so 15 apiece is arithmetically impossible and would leave the
    /// user no market to compete in. Six is what the pool supports.
    ///
    /// **No privileged quota**: the user's ceiling is the same 6, through
    /// ``draftNightUserWindow`` — read it for why the ceiling has to be stated
    /// twice and derived once.
    static let clubSigningQuota = 6

    /// What the user's ONE interactive UDFA door should let him sign.
    ///
    /// ### The audit (#199)
    ///
    /// The user never bids in this market: `postAIOffers` builds its club list as
    /// `teams.filter { $0.id != career.teamID }`, deliberately, because his
    /// undrafted business happens earlier — on draft night, in the Draft Day
    /// panel, before ``openMarket`` seeds a round. His draft-night signings go
    /// through `DraftEngine.convertUDFAToPlayer` and are therefore **invisible to
    /// `UDFAMarketState.signings`**, so ``clubSigningQuota`` — the guard that
    /// makes the ceiling real for the 31 AI clubs, checked at both bid time and
    /// settle time — cannot see or bind them. The user's real ceiling is whatever
    /// that panel says, and when this audit was written it said **5**
    /// (`UI/Draft/DraftDayCoordinator.swift`, `maxUDFASignings`), which made the
    /// "no privileged quota" line above one man short of true in the other
    /// direction. That view now derives its number from here, so the two cannot
    /// disagree again.
    ///
    /// ### Why the number here is 6 and not 5
    ///
    /// Parity is the rule the market was designed around, so the number belongs
    /// in the engine next to the quota it is supposed to equal rather than as a
    /// literal in a view — that literal is exactly how the two drifted apart. It
    /// is expressed as ``clubSigningQuota`` rather than as its own `6` so a
    /// future tuning pass cannot move one without the other.
    ///
    /// **Effective volume is not the same question, and there the user is ahead.**
    /// The declared class is ~285-350 men and `generateDeclarations` targets 224
    /// picks, so the remainder the undrafted market runs on is ~60-126. The user
    /// takes his men FIRST, unopposed, off the top of an untouched pool; the 31
    /// AI clubs then split what is left, which is ~2-4 apiece against a ceiling
    /// of 6. So this is an invariant repair, not a competitive one — nobody is
    /// being out-signed.
    static var draftNightUserWindow: Int { clubSigningQuota }

    /// Offers one AI club puts out per round. Sets market throughput: 31 clubs ×
    /// 4 is ~124 offers a round chasing a ~110-man pool, which is a market that
    /// clears without emptying. §6/B10 measures actual signings per season and
    /// this is the knob that moves them.
    static let aiOffersPerRound = 4

    /// Ceiling on how far above the standard undrafted deal an AI club will go
    /// for a man it badly wants (+35 %). Above `FrenzyHeatTier.burning`'s +30 %
    /// on purpose: a club that really wants somebody has to be able to beat a
    /// burning market, or the top of the board deadlocks and nobody signs.
    static let aiAggressionCeiling = 0.35

    /// How much a club's own board may differ from the true ordering, in overall
    /// points (±). Undrafted men are exactly where scouting departments disagree
    /// most, and without this every club chases the same four names and the
    /// market never spreads. Deterministic per (club, man, season) — see
    /// ``boardNoise(teamID:prospectID:season:)`` — so a save reloads to the same
    /// market rather than re-rolling it.
    static let aiBoardNoise = 6

    /// Round-by-round softening of the ask. An undrafted man still unsigned after
    /// a round of bidding does not hold out for a premium — he takes the job.
    /// Without this, a man whose heat inflated the price above what anybody bid
    /// would sit unsigned in every round and the top of the board would never
    /// clear.
    static let roundAskSoftening: [Double] = [1.00, 0.92, 0.85]

    /// Largest roster a club may carry out of this market. Shared with the trade
    /// market so the two cannot disagree about what a legal offseason roster is.
    static var rosterCeiling: Int { TradeValueEngine.offseasonRosterCeiling }

    // MARK: - Outcomes

    /// What happened to one offer the user submitted. Every rejection carries the
    /// number the UI needs to write an honest line ("You're $310K short").
    enum OfferOutcome: Equatable {
        /// The offer is on the table. `bidders` counts every club in on him,
        /// the user included.
        case submitted(bidders: Int, heat: FrenzyHeatTier, priceToBeat: Int)
        case marketClosed
        case notInPool
        case alreadySigned
        /// The club is at ``clubSigningQuota``.
        case quotaReached(quota: Int)
        case rosterFull(ceiling: Int)
        case belowMinimum(minimum: Int)
        case noCapSpace(shortfall: Int)
        case noTeam
    }

    /// One signing, resolved into the strings a recap sheet needs. Carries no
    /// true attribute of any kind — a round summary is a user-facing surface.
    struct SigningReceipt: Identifiable, Equatable {
        var id: UUID { prospectID }
        let prospectID: UUID
        let prospectName: String
        let position: Position
        let teamID: UUID
        let teamAbbreviation: String
        let salary: Int
        let years: Int
        /// The band the user's own department had on him, or `nil` if his staff
        /// never filed a report. Never a number (invariant 5).
        let scoutedGrade: String?
    }

    /// One man the user bid on and lost.
    struct LostBid: Identifiable, Equatable {
        var id: UUID { prospectID }
        let prospectID: UUID
        let prospectName: String
        let position: Position
        let winningTeamAbbreviation: String
        let userOffer: Int
        let winningOffer: Int
    }

    /// The result of one resolved round — the payload `DSResultSheet` renders.
    struct RoundOutcome: Equatable {
        let round: Int
        let userSignings: [SigningReceipt]
        let leagueSigningCount: Int
        /// Thousands per year the user committed this round.
        let userCapSpent: Int
        let lostBids: [LostBid]
        let openProspectCount: Int
        let isMarketClosed: Bool

        static let empty = RoundOutcome(
            round: 0, userSignings: [], leagueSigningCount: 0,
            userCapSpent: 0, lostBids: [], openProspectCount: 0, isMarketClosed: true
        )
    }

    // MARK: - Reading the market

    /// The persisted market, or `nil` if this career has never opened one.
    ///
    /// A blob stamped with a DIFFERENT season is treated as absent: the offseason
    /// rolls a new class every year, and last year's market must never be read as
    /// this year's.
    /// The codec itself is `Career.udfaMarketState`, next to every other blob
    /// accessor on the model; this adds the season check, which is the part no
    /// caller may skip.
    static func state(career: Career) -> UDFAMarketState? {
        guard let state = career.udfaMarketState,
              state.season == career.currentSeason else {
            return nil
        }
        return state
    }

    static func isOpen(career: Career) -> Bool { state(career: career)?.isOpen ?? false }

    /// `0` when the market has not been seeded this season.
    static func currentRound(career: Career) -> Int { state(career: career)?.round ?? 0 }

    /// How many undrafted men this club has signed in this market.
    static func signingCount(teamID: UUID, career: Career) -> Int {
        state(career: career)?.signingCount(for: teamID) ?? 0
    }

    /// The board, **fog-safe**: still-open men in the user's own scouted order.
    ///
    /// This is the only ordering a view may render. `ScoutingEngine.getUDFAPool`
    /// sorts on `effectiveOverallGrade`, so an unscouted man sorts last instead of
    /// being ranked by a number nobody in the building has seen.
    static func board(career: Career, prospects: [CollegeProspect]) -> [CollegeProspect] {
        let state = state(career: career)
        return ScoutingEngine.getUDFAPool(prospects: prospects).filter {
            state?.isSigned($0.id) != true
        }
    }

    /// **The men the market finished with**, best true value first — the second
    /// source the camp fill draws on (`OFFSEASON_ROSTER_PLAN.md` §3.3, #208 fix
    /// B).
    ///
    /// The market gives ~192 undrafted men real three-year deals; the remainder
    /// used to be discarded entirely, cleared off the declaration list here and
    /// then deleted with the rest of the class at `purgeStaleSeasonData`. In the
    /// real league that remainder IS the camp: a 90-man August roster is mostly
    /// undrafted rookies on minimum tryout deals, and the men who do not stick
    /// become next year's street free agents.
    ///
    /// The camp fill takes them **only after the unsigned pool is exhausted**,
    /// because each one is a `Player` row that has to be minted and a face that
    /// has to be claimed, while a pool man costs neither. In an established
    /// league (#99's ~900-man pool) that means almost none of them are called;
    /// in the league's first two offseasons, where the pool has not accumulated
    /// yet, they are what makes a camp roster exist at all.
    ///
    /// **Engine-only ordering.** Sorted by true value, exactly as
    /// ``postAIOffers``' board is: no user-facing surface reads this list — the
    /// camp fill is a league-wide pass whose output the user sees only as bodies
    /// on his roster — so invariant 5 is not in play. `getUDFAPoolByTrueValue`
    /// is not reusable here for the reason the doc on
    /// ``UDFAMarketState/unsignedProspectIDs`` gives: these men are no longer
    /// declared, so the pool predicate no longer contains them.
    ///
    /// **No mock-slot clause (#208 G2).** This used to re-filter the survivor
    /// list on `mockDraftPickNumber == nil`, mirroring the market's pool
    /// predicate. The survivor list is now the whole undrafted remainder — see
    /// the sweep in ``closeMarket(career:prospects:teams:allPlayers:allCoaches:modelContext:)``
    /// — and re-applying the market's clause here would throw the best part of
    /// it away: a man the mock had going in the fifth round who then went
    /// undrafted is the single most valuable camp invite in the class, and the
    /// mock is an annotation about February, not a statement about whether he
    /// has a job in July.
    static func campInviteCandidates(
        career: Career,
        prospects: [CollegeProspect]
    ) -> [CollegeProspect] {
        guard let ids = state(career: career)?.unsignedProspectIDs, !ids.isEmpty else { return [] }
        let survivors = Set(ids)
        return prospects
            .filter { survivors.contains($0.id) }
            .sorted { lhs, rhs in
                let lhsValue = DraftEngine.udfaEntryOverall(prospect: lhs)
                let rhsValue = DraftEngine.udfaEntryOverall(prospect: rhs)
                if lhsValue != rhsValue { return lhsValue > rhsValue }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    /// Strikes one man off ``campInviteCandidates`` once a camp has taken him,
    /// so a second club cannot invite the same rookie.
    ///
    /// The camp fill signs into a snapshot and calls this as it goes; the state
    /// is the record that survives the advance, which is what keeps a re-entered
    /// phase from offering a man who is already in somebody's camp.
    static func consumeCampInvite(career: Career, prospectID: UUID) {
        guard var state = state(career: career) else { return }
        state.unsignedProspectIDs?.removeAll { $0 == prospectID }
        write(state, to: career)
    }

    /// The standard undrafted deal at this cap — the market's single definition
    /// of what a UDFA costs, shared with the Draft Day panel and the AI path.
    static func askingPrice(salaryCap: Int) -> Int {
        DraftEngine.udfaContract(salaryCap: salaryCap).salary
    }

    static func contractYears(salaryCap: Int) -> Int {
        DraftEngine.udfaContract(salaryCap: salaryCap).years
    }

    /// How hot the bidding on one man is, straight off `BiddingHeatEngine`.
    ///
    /// Heat is a market signal, and it is *supposed* to be informative: clubs
    /// chase the men they rate, so a burning pill tells the user the league likes
    /// somebody his own scouts may have missed. That is not a fog leak — no true
    /// number reaches the surface, only the fact that four other buildings are in
    /// the room, which is exactly what a real war room would know.
    ///
    /// The market's own `UDFABid`s are projected into transient `FABid` values —
    /// built, never inserted — so the count → tier curve has exactly one
    /// definition in the game. There are no visits in this market (there is no
    /// time for one in the real league either), so `visits: []`.
    static func heat(prospectID: UUID, career: Career) -> FrenzyHeatTier {
        guard let state = state(career: career) else { return .cool }
        return heat(bids: state.offers(on: prospectID), round: state.round, season: state.season)
    }

    /// The number an offer has to clear to be live this round.
    ///
    /// `ask × heat inflation × round softening`, floored at the ask itself: a man
    /// nobody else wants still signs the standard deal, never less.
    static func priceToBeat(prospectID: UUID, career: Career, salaryCap: Int) -> Int {
        guard let state = state(career: career) else { return askingPrice(salaryCap: salaryCap) }
        return clearingPrice(
            askingPrice: askingPrice(salaryCap: salaryCap),
            heat: heat(bids: state.offers(on: prospectID), round: state.round, season: state.season),
            round: state.round
        )
    }

    /// Clubs currently in on this man, the user included.
    static func bidderCount(prospectID: UUID, career: Career) -> Int {
        Set(state(career: career)?.offers(on: prospectID).map(\.teamID) ?? []).count
    }

    /// The user's standing offer on this man, if he has one.
    static func userBid(prospectID: UUID, career: Career) -> UDFABid? {
        guard let teamID = career.teamID else { return nil }
        return state(career: career)?.offer(on: prospectID, by: teamID)
    }

    /// Where the user's offer ranks among the competing ones, via
    /// `PlayerPreferenceEngine.offerRanking` — reused as-is, since it is keyed on
    /// bids and team ids and reads nothing off a `Player`.
    static func userOfferRank(prospectID: UUID, career: Career) -> (yourRank: Int, totalOffers: Int) {
        guard let teamID = career.teamID, let state = state(career: career) else { return (0, 0) }
        return PlayerPreferenceEngine.offerRanking(
            userTeamID: teamID,
            bids: state.offers(on: prospectID).map(transientFABid(from:)),
            preferences: [],
            teamFits: [:]
        )
    }

    /// "You've been topped on him" alerts for the live round, via
    /// `OutbidNotifier.detect` — also reused as-is.
    static func outbidEvents(
        career: Career,
        prospects: [CollegeProspect],
        teams: [Team]
    ) -> [OutbidEvent] {
        guard let teamID = career.teamID, let state = state(career: career), state.isOpen else {
            return []
        }
        var names: [UUID: String] = [:]
        for prospect in prospects { names[prospect.id] = prospect.fullName }
        var abbrevs: [UUID: String] = [:]
        for team in teams { abbrevs[team.id] = team.abbreviation }
        return OutbidNotifier.detect(
            userTeamID: teamID,
            bids: state.bids.map(transientFABid(from:)),
            playerNames: names,
            teamAbbrevs: abbrevs
        )
    }

    // MARK: - 1. Open the market

    /// Seeds the market at the `.draft` exit and posts the league's opening
    /// offers. **Signs nobody.**
    ///
    /// Idempotent two ways. It refuses to re-seed a season already stamped in the
    /// blob, and if the undrafted pool is empty it opens the market in its CLOSED
    /// state.
    ///
    /// An empty pool used to be the NORMAL case rather than the degenerate one:
    /// the Draft Day panel's "Finish" cleared `isDeclaringForDraft` on the whole
    /// remainder, so a user who played draft night through — which is the only
    /// way to reach the panel — left this method nothing to open a market on,
    /// and the camp fill downstream nothing to invite (#208 G2). That blanket
    /// clear is gone. The two signing paths stay mutually exclusive on the pool
    /// predicate alone, with no process-global flag: `ScoutingEngine
    /// .udfaPoolMembers` is the one authority, and `DraftEngine
    /// .convertUDFAToPlayer` removes a man from it at the moment he signs (D1).
    @discardableResult
    static func openMarket(
        career: Career,
        prospects: [CollegeProspect],
        teams: [Team],
        allPlayers: [Player]
    ) -> UDFAMarketState {
        if let existing = state(career: career) { return existing }

        let pool = ScoutingEngine.udfaPoolMembers(prospects: prospects)
        var state = UDFAMarketState(season: career.currentSeason)

        guard !pool.isEmpty else {
            // Nothing left to sign — the draft-night panel already cleared the
            // board. Open closed, so the OTAs surface can say so honestly.
            state.round = UDFAMarketState.closedRound
            write(state, to: career)
            return state
        }

        state.round = 1
        postAIOffers(state: &state, prospects: prospects, teams: teams, allPlayers: allPlayers, career: career)
        write(state, to: career)
        return state
    }

    // MARK: - 2. The user's offer

    /// Puts the user's club on a man. Replaces his standing offer on the same man
    /// rather than stacking a second one.
    ///
    /// Gated on the same three things every AI offer is gated on — quota, roster
    /// ceiling and cap room (**D3**) — plus the floor that no undrafted deal may
    /// pay less than the standard one.
    @discardableResult
    static func submitUserOffer(
        career: Career,
        prospect: CollegeProspect,
        salary: Int,
        years: Int? = nil,
        teams: [Team],
        allPlayers: [Player]
    ) -> OfferOutcome {
        guard let teamID = career.teamID, let team = teams.first(where: { $0.id == teamID }) else {
            return .noTeam
        }
        guard var state = state(career: career), state.isOpen else { return .marketClosed }
        guard !state.isSigned(prospect.id) else { return .alreadySigned }
        guard prospect.isDeclaringForDraft, prospect.mockDraftPickNumber == nil else { return .notInPool }
        guard state.signingCount(for: teamID) < clubSigningQuota else {
            return .quotaReached(quota: clubSigningQuota)
        }

        let rosterCount = allPlayers.reduce(0) { $0 + ($1.teamID == teamID ? 1 : 0) }
        guard rosterCount < rosterCeiling else { return .rosterFull(ceiling: rosterCeiling) }

        let minimum = askingPrice(salaryCap: team.salaryCap)
        guard salary >= minimum else { return .belowMinimum(minimum: minimum) }
        guard CapManagementEngine.canAfford(team: team, cost: salary, capMode: career.capMode) else {
            return .noCapSpace(shortfall: max(0, salary - team.availableCap))
        }

        state.bids.removeAll { $0.prospectID == prospect.id && $0.teamID == teamID }
        state.bids.append(UDFABid(
            prospectID: prospect.id,
            teamID: teamID,
            salary: salary,
            years: years ?? contractYears(salaryCap: team.salaryCap),
            round: state.round
        ))
        write(state, to: career)

        let onHim = state.offers(on: prospect.id)
        return .submitted(
            bidders: Set(onHim.map(\.teamID)).count,
            heat: heat(bids: onHim, round: state.round, season: state.season),
            priceToBeat: clearingPrice(
                askingPrice: minimum,
                heat: heat(bids: onHim, round: state.round, season: state.season),
                round: state.round
            )
        )
    }

    /// Pulls the user's club off a man before the round resolves.
    static func withdrawUserOffer(career: Career, prospectID: UUID) {
        guard let teamID = career.teamID, var state = state(career: career), state.isOpen else { return }
        state.bids.removeAll { $0.prospectID == prospectID && $0.teamID == teamID }
        write(state, to: career)
    }

    // MARK: - 3. Run a round

    /// Resolves the standing offers, signs the winners, and opens the next round.
    ///
    /// Agent B calls this when the user commits a round on the board (and, via
    /// ``closeMarket``, for any rounds he never worked).
    @discardableResult
    static func runAIRound(
        career: Career,
        prospects: [CollegeProspect],
        teams: [Team],
        allPlayers: [Player],
        allCoaches: [Coach],
        modelContext: ModelContext
    ) -> RoundOutcome {
        guard var state = state(career: career), state.isOpen else { return .empty }

        var players = allPlayers
        let outcome = resolveRound(
            state: &state,
            career: career,
            prospects: prospects,
            teams: teams,
            allPlayers: &players,
            allCoaches: allCoaches,
            modelContext: modelContext
        )

        if state.isOpen {
            postAIOffers(
                state: &state, prospects: prospects, teams: teams,
                allPlayers: players, career: career
            )
        }
        write(state, to: career)
        return outcome
    }

    // MARK: - 4. Close the market

    /// Settles the market at the `.otas` exit.
    ///
    /// Runs whatever rounds are still owed — a user who never opened the board
    /// still gets a league that signed its undrafted men — then takes every
    /// survivor off the declaration list.
    ///
    /// **Survivors are not converted to `Player` rows.** They leave the market as
    /// street free agents, exactly as the draft-night path already leaves them.
    /// Minting ~30-50 `Player`s a season here would claim that many faces and
    /// push that many bodies into the unsigned pool whose equilibrium the camp
    /// fill is measured against (§6/B4) — a large balance change smuggled in as
    /// housekeeping. The camp fill draws from the pool that already exists.
    @discardableResult
    static func closeMarket(
        career: Career,
        prospects: [CollegeProspect],
        teams: [Team],
        allPlayers: [Player],
        allCoaches: [Coach],
        modelContext: ModelContext
    ) -> RoundOutcome {
        if state(career: career) == nil {
            openMarket(career: career, prospects: prospects, teams: teams, allPlayers: allPlayers)
        }
        guard var state = state(career: career) else { return .empty }

        var players = allPlayers
        var totalLeagueSignings = 0
        var userSignings: [SigningReceipt] = []
        var lostBids: [LostBid] = []
        var userCapSpent = 0

        // Owed rounds. Bounded by `roundCount` so a corrupted `round` cannot spin.
        var guardCounter = 0
        while state.isOpen, guardCounter < roundCount {
            guardCounter += 1
            let outcome = resolveRound(
                state: &state,
                career: career,
                prospects: prospects,
                teams: teams,
                allPlayers: &players,
                allCoaches: allCoaches,
                modelContext: modelContext
            )
            totalLeagueSignings += outcome.leagueSigningCount
            userSignings.append(contentsOf: outcome.userSignings)
            lostBids.append(contentsOf: outcome.lostBids)
            userCapSpent += outcome.userCapSpent
            if state.isOpen {
                postAIOffers(
                    state: &state, prospects: prospects, teams: teams,
                    allPlayers: players, career: career
                )
            }
        }

        // Everyone still on the board goes off the declaration list. Without this
        // the scouting screens keep listing men the market has finished with —
        // the user-facing half of defect D1.
        //
        // Their ids are kept (`unsignedProspectIDs`): clearing the flag is what
        // makes them indistinguishable from the men the Draft Day panel signed,
        // and `CampRosterEngine` needs to tell those two groups apart a moment
        // later. See ``UDFAMarketEngine/campInviteCandidates(career:prospects:)``.
        //
        // **The sweep is `isDeclaringForDraft`, not `udfaPoolMembers` (#208 G2).**
        // The pool predicate carries a second clause — `mockDraftPickNumber ==
        // nil` — which is right for the market (a man the mock had going in the
        // fourth round is not a UDFA to bid on) and wrong for this sweep twice
        // over. A projected pick who slid out of all seven rounds is undrafted
        // like everybody else: leaving him declared keeps him "available" on
        // `ClassDepthView` and the scouting hub until `purgeStaleSeasonData`
        // deletes him a year later, which is exactly the lie D1 was about, and
        // leaving him off the survivor list throws away the most attractive camp
        // invite in the class. Every man the draft did not take is swept, and
        // every one of them is camp inventory.
        var survivors = 0
        var survivorIDs: [UUID] = []
        for prospect in prospects where prospect.isDeclaringForDraft {
            prospect.isDeclaringForDraft = false
            survivorIDs.append(prospect.id)
            survivors += 1
        }
        state.unsignedProspectIDs = survivorIDs

        state.round = UDFAMarketState.closedRound
        state.bids = []
        write(state, to: career)
        try? modelContext.save()

        return RoundOutcome(
            round: roundCount,
            userSignings: userSignings,
            leagueSigningCount: totalLeagueSignings,
            userCapSpent: userCapSpent,
            lostBids: lostBids,
            openProspectCount: survivors,
            isMarketClosed: true
        )
    }

    // MARK: - Resolution (the one signing door)

    /// Turns this round's standing offers into signings.
    ///
    /// Private on purpose: ``runAIRound`` and ``closeMarket`` are the two doors,
    /// and both go through here, so there is exactly one place in the game where
    /// an undrafted man changes hands.
    /// - Parameter allPlayers: the league's players, **inout**: a man signed in
    ///   round 1 is on a roster for round 2's need reads and ceiling checks.
    ///   Without this the market would spend three rounds looking at the roster
    ///   it started with.
    private static func resolveRound(
        state: inout UDFAMarketState,
        career: Career,
        prospects: [CollegeProspect],
        teams: [Team],
        allPlayers: inout [Player],
        allCoaches: [Coach],
        modelContext: ModelContext
    ) -> RoundOutcome {
        let round = state.round
        let userTeamID = career.teamID
        let prospectsByID = Dictionary(prospects.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let teamsByID = Dictionary(teams.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var rosters: [UUID: [Player]] = [:]
        for player in allPlayers {
            guard let teamID = player.teamID else { continue }
            rosters[teamID, default: []].append(player)
        }
        var coachesByTeam: [UUID: [Coach]] = [:]
        for coach in allCoaches {
            guard let teamID = coach.teamID else { continue }
            coachesByTeam[teamID, default: []].append(coach)
        }

        var userSignings: [SigningReceipt] = []
        var lostBids: [LostBid] = []
        var leagueSignings = 0
        var userCapSpent = 0

        // Contested men first: a club that wins a scramble should not have spent
        // its cap room on an uncontested body a moment earlier. Deterministic
        // ordering (bidder count, then id) so the same market resolves the same
        // way twice — a `Dictionary` iteration here would reshuffle every launch.
        let contested = Dictionary(grouping: state.bids, by: \.prospectID)
            .sorted { lhs, rhs in
                let lhsBidders = Set(lhs.value.map(\.teamID)).count
                let rhsBidders = Set(rhs.value.map(\.teamID)).count
                if lhsBidders != rhsBidders { return lhsBidders > rhsBidders }
                return lhs.key.uuidString < rhs.key.uuidString
            }

        for (prospectID, bidsOnHim) in contested {
            guard let prospect = prospectsByID[prospectID],
                  prospect.isDeclaringForDraft,
                  !state.isSigned(prospectID) else { continue }

            let heatTier = heat(bids: bidsOnHim, round: round, season: state.season)
            let candidate = SigningInterestEngine.Candidate(
                id: prospect.id,
                position: prospect.position,
                overall: DraftEngine.udfaEntryOverall(prospect: prospect),
                motivation: prospect.truePersonality.motivation
            )

            // Rank every live offer by how much the man actually wants it.
            var ranked: [(bid: UDFABid, team: Team, interest: Double)] = []
            for bid in bidsOnHim {
                guard let team = teamsByID[bid.teamID] else { continue }
                let ask = askingPrice(salaryCap: team.salaryCap)
                guard bid.salary >= clearingPrice(askingPrice: ask, heat: heatTier, round: round) else {
                    continue        // under the market — not a live offer this round
                }
                let breakdown = SigningInterestEngine.interest(
                    candidate: candidate,
                    askingPrice: ask,
                    offer: (salary: bid.salary, years: bid.years),
                    team: team,
                    allPlayers: rosters[team.id] ?? [],
                    schemeFit: nil,     // nobody knows how an undrafted rookie fits a system
                    hostedVisit: false  // there are no visits in this market
                )
                ranked.append((bid: bid, team: team, interest: breakdown.total))
            }
            ranked.sort { lhs, rhs in
                if lhs.interest != rhs.interest { return lhs.interest > rhs.interest }
                if lhs.bid.salary != rhs.bid.salary { return lhs.bid.salary > rhs.bid.salary }
                return lhs.bid.teamID.uuidString < rhs.bid.teamID.uuidString
            }

            // Walk down the ranking until somebody can actually execute the deal.
            // Quota, roster ceiling and cap room are re-checked HERE and not only
            // at bid time, because an earlier signing in this same round may have
            // used up the room (D3).
            var winner: (bid: UDFABid, team: Team)?
            for entry in ranked {
                let teamID = entry.team.id
                guard state.signingCount(for: teamID) < clubSigningQuota,
                      (rosters[teamID]?.count ?? 0) < rosterCeiling,
                      CapManagementEngine.canAfford(
                          team: entry.team, cost: entry.bid.salary, capMode: career.capMode
                      ) else { continue }
                winner = (bid: entry.bid, team: entry.team)
                break
            }
            guard let winner else { continue }

            let player = sign(
                prospect: prospect,
                to: winner.team,
                salary: winner.bid.salary,
                years: winner.bid.years,
                coaches: coachesByTeam[winner.team.id] ?? [],
                career: career,
                modelContext: modelContext
            )
            rosters[winner.team.id, default: []].append(player)
            allPlayers.append(player)
            state.signings.append(UDFASigning(
                prospectID: prospect.id,
                teamID: winner.team.id,
                salary: winner.bid.salary,
                years: winner.bid.years,
                round: round
            ))
            leagueSignings += 1

            if winner.team.id == userTeamID {
                userCapSpent += winner.bid.salary
                userSignings.append(receipt(
                    prospect: prospect, team: winner.team,
                    salary: winner.bid.salary, years: winner.bid.years
                ))
            } else if let userTeamID,
                      let userBid = bidsOnHim.first(where: { $0.teamID == userTeamID }) {
                lostBids.append(LostBid(
                    prospectID: prospect.id,
                    prospectName: prospect.fullName,
                    position: prospect.position,
                    winningTeamAbbreviation: winner.team.abbreviation,
                    userOffer: userBid.salary,
                    winningOffer: winner.bid.salary
                ))
            }
        }

        // Offers that did not win have expired; next round starts clean.
        state.bids = []
        state.round = round + 1
        try? modelContext.save()

        let open = ScoutingEngine.udfaPoolMembers(prospects: prospects)
            .filter { !state.isSigned($0.id) }
            .count

        return RoundOutcome(
            round: round,
            userSignings: userSignings,
            leagueSigningCount: leagueSignings,
            userCapSpent: userCapSpent,
            lostBids: lostBids,
            openProspectCount: open,
            isMarketClosed: state.isClosed
        )
    }

    /// The signing itself. Every UDFA in the game is created here or by the Draft
    /// Day panel, and both route through `DraftEngine.convertUDFAToPlayer`, which
    /// is what takes the man off the declaration list (D1).
    private static func sign(
        prospect: CollegeProspect,
        to team: Team,
        salary: Int,
        years: Int,
        coaches: [Coach],
        career: Career,
        modelContext: ModelContext
    ) -> Player {
        let player = DraftEngine.convertUDFAToPlayer(
            prospect: prospect,
            teamID: team.id,
            salaryCap: team.salaryCap
        )
        // The standard deal is the FLOOR; a contested man is paid what he was bid.
        player.annualSalary = salary
        player.contractYearsRemaining = years
        DraftEngine.initializeRookieFamiliarity(
            player: player,
            prospect: prospect,
            coaches: coaches,
            isUndrafted: true
        )
        player.careerID = career.id          // invariant 6
        modelContext.insert(player)
        // A signed UDFA is a cap liability like any other (task #89). The bulk
        // path used to insert him and charge nobody.
        team.currentCapUsage += salary
        return player
    }

    // MARK: - The AI's offers

    /// Puts the league's offers on the board for the current round.
    ///
    /// Round-robin over a SHUFFLED club order, one pass of `aiOffersPerRound`
    /// offers per club. The shuffle is defect #10's lesson (carried over from the
    /// OTAs bulk block this engine replaced) and #144's re-learning of it in
    /// `PracticeSquadEngine.fillSquads`: with a fixed order the same clubs picked
    /// first every season and the first few emptied the market.
    ///
    /// Clubs bid on holes, not on a league-wide positional-value table
    /// (**D3**): `DraftEngine.teamNeedDeficits` returns only positions where the
    /// evidence half of the need score clears 1.0, which is the ranking its own
    /// doc comment says a market should read. `topTeamNeeds` — which the plan
    /// named — hands back the identical {QB, DE, CB, WR, LT} quintet to all 32
    /// clubs on a full roster, so used here it would have every club in the
    /// league chasing the same five positions. `topTeamNeeds` is kept as the
    /// fallback for a club with no genuine hole, which still needs *some*
    /// preference order.
    private static func postAIOffers(
        state: inout UDFAMarketState,
        prospects: [CollegeProspect],
        teams: [Team],
        allPlayers: [Player],
        career: Career
    ) {
        let round = state.round
        let openPool = ScoutingEngine.getUDFAPoolByTrueValue(prospects: prospects)
            .filter { !state.isSigned($0.id) }
        guard !openPool.isEmpty else { return }

        // Entry level is a property of the man, not of the club looking at him —
        // computed once for the whole pool rather than 31 times over (risk R5).
        var entryOverall: [UUID: Int] = [:]
        for prospect in openPool {
            entryOverall[prospect.id] = DraftEngine.udfaEntryOverall(prospect: prospect)
        }

        var rosters: [UUID: [Player]] = [:]
        for player in allPlayers {
            guard let teamID = player.teamID else { continue }
            rosters[teamID, default: []].append(player)
        }

        let aiTeams = teams.filter { $0.id != career.teamID }.shuffled()
        for team in aiTeams {
            guard state.signingCount(for: team.id) < clubSigningQuota else { continue }
            let roster = rosters[team.id] ?? []
            guard roster.count < rosterCeiling else { continue }

            let ask = askingPrice(salaryCap: team.salaryCap)
            let years = contractYears(salaryCap: team.salaryCap)
            var needs = DraftEngine.teamNeedDeficits(roster: roster, limit: 5)
            if needs.isEmpty { needs = DraftEngine.topTeamNeeds(roster: roster, limit: 5) }
            let needRank = Dictionary(
                uniqueKeysWithValues: needs.enumerated().map { ($0.element, $0.offset) }
            )

            // This club's own board: true value, plus what it needs, plus the
            // disagreement every scouting department has about undrafted men.
            let scored = openPool.map { prospect -> (prospect: CollegeProspect, score: Double) in
                var score = Double(entryOverall[prospect.id] ?? 0)
                if let rank = needRank[prospect.position] {
                    score += Double(10 - rank * 2)      // 10 down to 2 across the five holes
                }
                score += Double(boardNoise(
                    teamID: team.id, prospectID: prospect.id, season: state.season
                ))
                return (prospect: prospect, score: score)
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.prospect.id.uuidString < rhs.prospect.id.uuidString
            }

            var placed = 0
            for entry in scored {
                guard placed < aiOffersPerRound else { break }
                guard state.offer(on: entry.prospect.id, by: team.id) == nil else { continue }

                // How badly this club wants him, 0...1, off the need rank alone —
                // a hole is the only thing that makes a club overpay for an
                // undrafted body.
                let urgency: Double
                if let rank = needRank[entry.prospect.position] {
                    urgency = 1.0 - (Double(rank) / Double(max(needs.count, 1)))
                } else {
                    urgency = 0.0
                }
                let salary = Int((Double(ask) * (1.0 + aiAggressionCeiling * urgency)).rounded())

                guard CapManagementEngine.canAfford(
                    team: team, cost: salary, capMode: career.capMode
                ) else { continue }

                state.bids.append(UDFABid(
                    prospectID: entry.prospect.id,
                    teamID: team.id,
                    salary: salary,
                    years: years,
                    round: round
                ))
                placed += 1
            }
        }
    }

    // MARK: - Pricing

    /// `ask × heat inflation × round softening`, never below the ask.
    static func clearingPrice(askingPrice: Int, heat: FrenzyHeatTier, round: Int) -> Int {
        let index = min(max(round, 1), roundAskSoftening.count) - 1
        let priced = Double(askingPrice) * heat.inflationModifier * roundAskSoftening[index]
        return max(askingPrice, Int(priced.rounded()))
    }

    private static func heat(bids: [UDFABid], round: Int, season: Int) -> FrenzyHeatTier {
        guard let prospectID = bids.first?.prospectID else { return .cool }
        return BiddingHeatEngine.computeHeat(
            playerID: prospectID,
            currentDay: round,          // rounds are days here; < 5, so no stale decay
            bids: bids.map(transientFABid(from:)),
            visits: []
        )
    }

    /// A `UDFABid` as the `FABid` value the FA engines take.
    ///
    /// Built, never inserted: this object exists for the length of one call so
    /// `BiddingHeatEngine`, `PlayerPreferenceEngine` and `OutbidNotifier` can be
    /// reused verbatim instead of re-implemented against a second bid type.
    private static func transientFABid(from bid: UDFABid) -> FABid {
        FABid(
            playerID: bid.prospectID,
            teamID: bid.teamID,
            seasonYear: 0,
            dayNumber: bid.round,
            years: bid.years,
            baseSalary: bid.salary,
            status: .pending,
            submittedAt: bid.submittedAt
        )
    }

    /// Deterministic ±``aiBoardNoise`` disagreement, seeded on (club, man,
    /// season). Deterministic so a save reloads into the same market instead of
    /// re-rolling every club's board on every launch.
    private static func boardNoise(teamID: UUID, prospectID: UUID, season: Int) -> Int {
        var hash: UInt64 = 1469598103934665603        // FNV-1a offset basis
        func mix(_ bytes: [UInt8]) {
            for byte in bytes {
                hash ^= UInt64(byte)
                hash = hash &* 1099511628211
            }
        }
        mix(withUnsafeBytes(of: teamID.uuid) { Array($0) })
        mix(withUnsafeBytes(of: prospectID.uuid) { Array($0) })
        mix(withUnsafeBytes(of: UInt64(bitPattern: Int64(season))) { Array($0) })
        let span = aiBoardNoise * 2 + 1
        return Int(hash % UInt64(span)) - aiBoardNoise
    }

    // MARK: - Receipts

    private static func receipt(
        prospect: CollegeProspect,
        team: Team,
        salary: Int,
        years: Int
    ) -> SigningReceipt {
        SigningReceipt(
            prospectID: prospect.id,
            prospectName: prospect.fullName,
            position: prospect.position,
            teamID: team.id,
            teamAbbreviation: team.abbreviation,
            salary: salary,
            years: years,
            // The band his own department filed, never a number (invariant 5).
            scoutedGrade: prospect.effectiveOverallGrade?.displayText
        )
    }

    // MARK: - Persistence
    //
    // The market touches exactly ONE stored property, through these two
    // functions and nowhere else:
    //
    //     // Domain/Models/Career.swift — Wave 0, agent B (plan §3.2)
    //     var udfaMarketData: Data? = nil
    //
    // Inline default, never an `init` parameter → lightweight migration, the
    // same shape as `pendingTradeOffersData` and `inboxData`. A save written
    // before this wave decodes to `nil`, which reads as "no market this season"
    // and opens one on the next `.draft` exit (risk R8).

    private static func write(_ state: UDFAMarketState, to career: Career) {
        career.udfaMarketState = state
    }
}
