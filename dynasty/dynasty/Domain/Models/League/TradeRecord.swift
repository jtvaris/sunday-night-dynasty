import Foundation
import SwiftData

// MARK: - Trade Record (Wave 0 — `docs/TRADE_OVERHAUL_PLAN.md`)

/// One persisted row per EXECUTED trade — the league's trade ledger.
///
/// WHY this exists: nothing in the game measured or remembered trades
/// (plan finding S9). The Trade Center's history list was `@State`, i.e. it
/// evaporated the moment the view closed (S7); AI-vs-AI deadline deals and
/// draft-room pick swaps left behind only a news headline or a `DraftEvent`,
/// neither of which carries values or asset lists. That blindness is exactly
/// why S1 (no future picks exist → the pick-based trade paths are dead
/// branches) and S5 (the AI almost never calls) survived unnoticed through
/// 3 fully simulated seasons.
///
/// So this model lands FIRST, before any market/AI/UI change, and is written
/// at every execution site without altering behaviour. Two jobs:
/// 1. **Measurable baseline.** `MultiSeasonSmokeTest` aggregates these rows
///    into its `SMOKE: diag trades` line, so "the market is inert" becomes a
///    number instead of a hunch, and the §5 NFL reference bands become
///    assertable in Wave 2.
/// 2. **The ledger later waves read from.** Persisted trade history in the
///    Trade Center (Wave 3), the league transaction feed / news + owner and
///    locker-room reactions (Wave 5), and draft-pick provenance ("via ABC",
///    Wave 1) all need a durable record of who traded what, for what, and
///    what it was worth at the time.
///
/// Rows are append-only history: the summaries and values are SNAPSHOTS taken
/// at execution time, deliberately denormalized (names, not just IDs) so a
/// 12-season-old deal still reads correctly after the players retire and the
/// picks are consumed.
@Model
final class TradeRecord {
    var id: UUID


    /// The save slot (``Career.id``) this row belongs to. `nil` marks a legacy
    /// row written before multi-save isolation existed; `CareerScope.adopt`
    /// stamps those on first launch. Default-value stored property, never in
    /// `init` -> safe lightweight migration.
    var careerID: UUID? = nil

    // MARK: When

    /// League year the trade was executed in (`Career.currentSeason`).
    var season: Int
    /// `Career.currentWeek` at execution. Offseason phases keep the week they
    /// were advanced to; only the in-season rows are calendar-meaningful.
    var week: Int
    /// `SeasonPhase.rawValue` — stored raw so the ledger survives enum edits.
    var phaseRaw: String

    // MARK: Who / what kind

    /// `TradeRecordKind.rawValue`. Raw string for the same migration-safety
    /// reason as `phaseRaw`.
    var kindRaw: String
    /// The team that PROPOSED the deal (the proposal's offering team). For a
    /// draft-room pick swap this is the side that accepted the phone call,
    /// i.e. the user's team.
    var initiatorTeamID: UUID
    /// The counterparty.
    var partnerTeamID: UUID

    // MARK: What moved (initiator's perspective)

    /// Human-readable list of assets the initiator SENT, e.g.
    /// `"WR Cody Deval (84 OVR), 2027 R3 P76"`. Rendered directly by the
    /// history/news surfaces in later waves — no lookup needed.
    var sentSummary: String
    /// Human-readable list of assets the initiator RECEIVED.
    var receivedSummary: String
    /// Jimmy-Johnson points the initiator sent, valued by `TradeValueEngine`
    /// at execution time (the one valuation authority, plan §3).
    var sentValue: Int
    /// Jimmy-Johnson points the initiator received.
    var receivedValue: Int

    // MARK: Volume counters (both sides combined)

    /// Players that changed teams in this deal, both directions.
    var playersMovedCount: Int
    /// Draft picks that changed hands, both directions.
    var picksMovedCount: Int
    /// Of `picksMovedCount`, how many were for a LATER league year than
    /// `season`. The single most diagnostic number in Wave 0: S1 predicts a
    /// hard zero here forever, because future-year `DraftPick` rows do not
    /// exist yet (§6 Wave 1 mints them).
    var futurePicksCount: Int

    var occurredAt: Date

    /// The best player who changed hands, if any — the man a headline about
    /// this deal is actually about.
    ///
    /// F-70: `sentSummary` / `receivedSummary` store NAMES so the ledger
    /// survives retirements, which is right for the ledger and left the news
    /// feed unable to render a portrait: every trade story set
    /// `relatedPlayerID: nil` while every other person-story lit one up. This is
    /// the id the feed needs, kept deliberately OPTIONAL and separate from the
    /// summaries: it is a pointer to a row that may be gone, so a reader must
    /// tolerate a miss, and nothing about the ledger's own meaning depends on
    /// it. `nil` for a pick-only swap.
    ///
    /// Default-value stored property, never in `init` -> free lightweight
    /// migration (`docs/SWIFTDATA_MIGRATION_PLAN.md` §4).
    var headlinePlayerID: UUID? = nil

    /// Typed accessor over `phaseRaw`; unknown/legacy values read as
    /// `.regularSeason` rather than crashing a history screen.
    var phase: SeasonPhase {
        get { SeasonPhase(rawValue: phaseRaw) ?? .regularSeason }
        set { phaseRaw = newValue.rawValue }
    }

    /// Typed accessor over `kindRaw`.
    var kind: TradeRecordKind {
        get { TradeRecordKind(rawValue: kindRaw) ?? .userProposal }
        set { kindRaw = newValue.rawValue }
    }

    /// True when the user's franchise was not involved — the "other 31 teams
    /// actually trade with each other" metric (S5).
    func isAIvsAI(userTeamID: UUID?) -> Bool {
        guard let userTeamID else { return true }
        return initiatorTeamID != userTeamID && partnerTeamID != userTeamID
    }

    /// True for a deal struck between kickoff and the deadline.
    ///
    /// Keyed on the PHASE, not on `week`: offseason rows keep whatever week the
    /// career was advanced to (19-22 after the playoffs), so a week test would
    /// bucket a March trade as in-season. §5 states its volume bands separately
    /// for the two halves of the league year, and this is the split the Wave 2
    /// smoke asserts read.
    var isInSeason: Bool {
        phase == .regularSeason || phase == .tradeDeadline
    }

    init(
        id: UUID = UUID(),
        season: Int,
        week: Int,
        phase: SeasonPhase,
        kind: TradeRecordKind,
        initiatorTeamID: UUID,
        partnerTeamID: UUID,
        sentSummary: String,
        receivedSummary: String,
        sentValue: Int,
        receivedValue: Int,
        playersMovedCount: Int,
        picksMovedCount: Int,
        futurePicksCount: Int,
        occurredAt: Date = .now
    ) {
        self.id = id
        self.season = season
        self.week = week
        self.phaseRaw = phase.rawValue
        self.kindRaw = kind.rawValue
        self.initiatorTeamID = initiatorTeamID
        self.partnerTeamID = partnerTeamID
        self.sentSummary = sentSummary
        self.receivedSummary = receivedSummary
        self.sentValue = sentValue
        self.receivedValue = receivedValue
        self.playersMovedCount = playersMovedCount
        self.picksMovedCount = picksMovedCount
        self.futurePicksCount = futurePicksCount
        self.occurredAt = occurredAt
    }
}

// MARK: - Kind

/// Which execution path produced a ledger row. Raw-string backed so rows keep
/// their meaning across schema changes, and so the smoke harness can bucket
/// counts without a lookup table.
enum TradeRecordKind: String, Codable, CaseIterable {
    /// User built the deal in the Trade Center and the AI accepted it.
    case userProposal
    /// User accepted an AI-initiated offer (the `generateAIOffer` roll that
    /// landed in the inbox — weekly in-season, or an offseason window).
    case aiWeeklyOffer
    /// AI-vs-AI deal from an ordinary in-season week of
    /// `TradeValueEngine.runLeagueMarketPass` (Wave 2). Bucketed apart from
    /// `.aiDeadline` because §5 bands the deadline-week flurry (5-15) separately
    /// from the rest of the in-season market (8-25 total, ≥60 % of it in the last
    /// three pre-deadline weeks).
    case aiMarket
    /// AI-vs-AI deal from the deadline-week pass. The user's team never
    /// participates in these.
    case aiDeadline
    /// AI-vs-AI deal from an offseason market window (post-season retool,
    /// post-FA, pre-draft, cut days, OTAs). §5's 15-40 offseason band.
    case aiOffseason
    /// Draft-room pick swap accepted in `DraftDayCoordinator` (R24).
    case draftDay
    /// Front office capitulated to a holdout and shipped the player out
    /// (`HoldoutEngine.forceTrade`). Bucketed separately from `.userProposal`
    /// because the user never built the package — the engine did, under duress,
    /// at a deliberate discount (Wave 1, finding S3).
    case holdoutForced

    var label: String {
        switch self {
        case .userProposal:   return "Your proposal"
        case .aiWeeklyOffer:  return "Incoming offer"
        case .aiMarket:       return "League deal"
        case .aiDeadline:     return "Deadline deal"
        case .aiOffseason:    return "Offseason deal"
        case .draftDay:       return "Draft-day swap"
        case .holdoutForced:  return "Holdout trade"
        }
    }

    /// The three AI-vs-AI market buckets — the league doing business without the
    /// user. Handy for history filters and the smoke bands.
    static let aiMarketKinds: Set<TradeRecordKind> = [.aiMarket, .aiDeadline, .aiOffseason]
}

// MARK: - Trade Ledger

/// The single place that turns an executed trade into a `TradeRecord`.
///
/// Centralized so every execution path prices its deal with the SAME authority
/// (`TradeValueEngine`) and formats its summaries identically — the Wave 0
/// counters are only comparable if nothing hand-rolls its own numbers. Wave 0
/// adds no behaviour here: `record` reads the assets, writes one row, and
/// returns.
enum TradeLedger {

    /// Calendar + provenance stamp that the mutating call site must supply.
    /// Bundled into one value so `TradeEngine.executeTrade` can stay a single
    /// primitive that CANNOT be called without leaving a ledger row behind —
    /// the invariant that S9 (nothing measures trades) violated.
    struct Context {
        let kind: TradeRecordKind
        let season: Int
        let week: Int
        let phase: SeasonPhase
    }

    /// Writes the ledger row for a player/pick trade.
    ///
    /// Call this BEFORE the assets are moved: the summaries name the players
    /// and picks as they stood when the deal was struck.
    @discardableResult
    static func record(
        proposal: TradeProposal,
        context: Context,
        allPlayers: [Player],
        allPicks: [DraftPick],
        modelContext: ModelContext
    ) -> TradeRecord {
        let playerLookup = Dictionary(uniqueKeysWithValues: allPlayers.map { ($0.id, $0) })
        let pickLookup   = Dictionary(uniqueKeysWithValues: allPicks.map   { ($0.id, $0) })

        let sentPlayers     = proposal.sendingPlayers.compactMap   { playerLookup[$0] }
        let sentPicks       = proposal.sendingPicks.compactMap     { pickLookup[$0] }
        let receivedPlayers = proposal.receivingPlayers.compactMap { playerLookup[$0] }
        let receivedPicks   = proposal.receivingPicks.compactMap   { pickLookup[$0] }

        let values = TradeValueEngine.proposalValues(
            proposal: proposal,
            allPlayers: allPlayers,
            allPicks: allPicks,
            currentSeason: context.season
        )

        let record = TradeRecord(
            season: context.season,
            week: context.week,
            phase: context.phase,
            kind: context.kind,
            initiatorTeamID: proposal.offeringTeamID,
            partnerTeamID: proposal.receivingTeamID,
            sentSummary: summary(players: sentPlayers, picks: sentPicks),
            receivedSummary: summary(players: receivedPlayers, picks: receivedPicks),
            sentValue: values.sendingValue,
            receivedValue: values.receivingValue,
            playersMovedCount: sentPlayers.count + receivedPlayers.count,
            picksMovedCount: sentPicks.count + receivedPicks.count,
            futurePicksCount: (sentPicks + receivedPicks)
                .filter { $0.seasonYear > context.season }.count
        )
        // The headline man is the best player in the deal, whichever way he
        // went — "Denver land Vale" and "Vegas ship Vale out" are the same
        // story and it carries the same face.
        record.headlinePlayerID = (sentPlayers + receivedPlayers)
            .max(by: { $0.overall < $1.overall })?.id
        record.careerID = (sentPlayers + receivedPlayers).first?.careerID
            ?? (sentPicks + receivedPicks).first?.careerID
            ?? WeekAdvancer.activeCareerID
        modelContext.insert(record)
        return record
    }

    /// Writes the ledger row for a draft-room pick swap, which moves
    /// `DraftPick` rows directly instead of going through a `TradeProposal`.
    ///
    /// Call this BEFORE flipping `currentTeamID`.
    @discardableResult
    static func recordPickSwap(
        initiatorTeamID: UUID,
        partnerTeamID: UUID,
        picksSent: [DraftPick],
        picksReceived: [DraftPick],
        sentValue: Int,
        receivedValue: Int,
        context: Context,
        modelContext: ModelContext
    ) -> TradeRecord {
        let record = TradeRecord(
            season: context.season,
            week: context.week,
            phase: context.phase,
            kind: context.kind,
            initiatorTeamID: initiatorTeamID,
            partnerTeamID: partnerTeamID,
            sentSummary: summary(players: [], picks: picksSent),
            receivedSummary: summary(players: [], picks: picksReceived),
            sentValue: sentValue,
            receivedValue: receivedValue,
            playersMovedCount: 0,
            picksMovedCount: picksSent.count + picksReceived.count,
            futurePicksCount: (picksSent + picksReceived)
                .filter { $0.seasonYear > context.season }.count
        )
        record.careerID = (picksSent + picksReceived).first?.careerID
            ?? WeekAdvancer.activeCareerID
        modelContext.insert(record)
        return record
    }

    // MARK: - Formatting

    /// `"QB Sam Ruiz (91 OVR), 2027 R1 P14"` — players first, then picks, in
    /// the order the package listed them. `"nothing"` for an empty side (a
    /// one-way asset dump is legal and should read as such in history).
    private static func summary(players: [Player], picks: [DraftPick]) -> String {
        var parts = players.map { "\($0.position.rawValue) \($0.fullName) (\($0.overall) OVR)" }
        // #152: the year the league calls that draft, so a trade in the history
        // names the same pick the trade screen and the war room named.
        parts += picks.map { "\($0.displayDraftYear) R\($0.round) P\($0.pickNumber)" }
        return parts.isEmpty ? "nothing" : parts.joined(separator: ", ")
    }
}
