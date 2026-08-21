import Foundation
import SwiftUI

// MARK: - UserDraftBoard
//
// The ONE reader of the user's own board.
//
// `prospectCustomBoard` is the persisted order the Big Board writes (seeded
// from the media consensus, re-ordered by the tier movers and the drag
// handles). It was readable from exactly two screens — `BigBoardView`, which
// owns it, and `ScoutingHubView`, which counts it — so every other surface that
// wanted to say "your board" invented its own: the Mock Draft sorted by
// `scoutedOverall`, the draft room did not have the concept at all, and the
// three numbers disagreed with each other by construction.
//
// This is a pure reader over `CareerScopedDefaults`, so the war room (an
// `ObservableObject`, not a `View`) can use it as easily as a screen can.
enum UserDraftBoard {

    /// The unsuffixed defaults key the Big Board writes.
    static let storageKey = "prospectCustomBoard"

    /// The raw stored order, exactly as the Big Board last wrote it.
    static func persistedOrder() -> [UUID] {
        let json: String = CareerScopedDefaults.value(storageKey) ?? "[]"
        let strings = (try? JSONDecoder().decode([String].self, from: Data(json.utf8))) ?? []
        return strings.compactMap { UUID(uuidString: $0) }
    }

    /// The board as the Big Board would render it for this population.
    ///
    /// Mirrors `BigBoardView.syncBoardOrder`: the stored order pruned to men who
    /// still exist, then anything the user's scouts have filed on but the stored
    /// order has never seen, appended in media-consensus order. A screen that
    /// calls this before the Big Board has ever been opened therefore prints the
    /// same ranks the Big Board will print the first time it is.
    static func order(among prospects: [CollegeProspect]) -> [UUID] {
        let byID = Dictionary(prospects.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let stored = persistedOrder().filter { byID[$0] != nil }
        let known = Set(stored)
        let missing = prospects
            .filter { !known.contains($0.id) && $0.scoutedOverall != nil }
            .sorted(by: { consensusOrder($0, $1) })
            .map(\.id)
        return stored + missing
    }

    /// `[ProspectID: 1-based board slot]` for this population. The map every
    /// "Your Board: #N" line must print from.
    static func rankMap(among prospects: [CollegeProspect]) -> [UUID: Int] {
        var result: [UUID: Int] = [:]
        for (index, id) in order(among: prospects).enumerated() {
            result[id] = index + 1
        }
        return result
    }

    /// The population every board slot is measured against: the declared class,
    /// falling back to the whole class while the January window is still open.
    ///
    /// Without this the same man had two slots on the same night — the war room
    /// ranked the declared class, the Mock Draft ranked everybody — so a scouted
    /// underclassman who withdrew in January shifted every number below him
    /// between the two screens.
    static func draftPopulation(_ prospects: [CollegeProspect]) -> [CollegeProspect] {
        let declared = prospects.filter(\.isDeclaringForDraft)
        return declared.isEmpty ? prospects : declared
    }

    /// THE "MY #N" map. Every surface that prints the user's own board slot —
    /// the Big Board's My Board, the Mock Draft, the war-room panel and the
    /// pick sheet — reads this one function, so the four numbers cannot drift.
    ///
    /// Deliberately NOT a position inside whatever the screen is currently
    /// showing: the Big Board's My Board used to print an index into its own
    /// filtered, mark-tier-sorted array, so marking three men `elite` printed
    /// them #1/#2/#3 there while the war room printed their real slots
    /// (#4/#19/#41) for the same three men on the same night.
    static func slotMap(among prospects: [CollegeProspect]) -> [UUID: Int] {
        rankMap(among: draftPopulation(prospects))
    }

    /// The population in board order. Men the board has never seen (unscouted,
    /// unmarked) fall in behind it in media-consensus order rather than being
    /// dropped — the draft room still has to show who is left on the board.
    static func sorted(_ prospects: [CollegeProspect]) -> [CollegeProspect] {
        let slot = rankMap(among: prospects)
        return prospects.sorted { lhs, rhs in
            let l = slot[lhs.id] ?? Int.max
            let r = slot[rhs.id] ?? Int.max
            if l != r { return l < r }
            return consensusOrder(lhs, rhs)
        }
    }

    /// Board order grouped by the user's mark, tier groups in `sortRank` order
    /// (elite → target → depth → unmarked → avoid) with empty groups dropped.
    ///
    /// This is the tier-break primitive the Big Board has had since the mark
    /// system landed, finally rendered on the night the marks decide something.
    static func groupedByMark(_ prospects: [CollegeProspect]) -> [(tier: ProspectMarkTier, prospects: [CollegeProspect])] {
        let ordered = sorted(prospects)
        let tiers: [ProspectMarkTier] = [.elite, .target, .depth, .none, .avoid]
        return tiers.compactMap { tier in
            let group = ordered.filter { $0.userMark == tier }
            return group.isEmpty ? nil : (tier: tier, prospects: group)
        }
    }

    /// The men the user actually wants, best mark first and then board order.
    ///
    /// Falls back to the top of the board when nothing is marked, so a user who
    /// has never touched the mark menu still gets a targets list rather than an
    /// empty one.
    static func targets(among prospects: [CollegeProspect], limit: Int = 10) -> [CollegeProspect] {
        let ordered = sorted(prospects)
        let marked = ordered.filter { $0.userMark.isBoardPositive }
        if !marked.isEmpty { return Array(marked.prefix(limit)) }
        return Array(ordered.filter { $0.userMark != .avoid }.prefix(limit))
    }

    /// THE NAME THE ROOM HANDS IN WHEN THE CLOCK BEATS THE USER (#207).
    ///
    /// The draft's expiry path used to call `DraftEngine.aiMakePick` — the
    /// league AI, scoring `trueOverall` / `truePotential` through
    /// `AIDraftPerception`. On the user's own card that is a fog breach with a
    /// scoreboard attached: the room reached past the board he spent a spring
    /// building and filed on the hidden rating, so a man his scouts had never
    /// seen could arrive with a first-round grade and the user would have no
    /// account of where the name came from.
    ///
    /// This is the same decision made from the USER's chair, and it reads
    /// exactly three things, all of them his:
    ///
    ///   1. **His marks.** `elite` before `target` — the two tiers that mean
    ///      "I want him". Inside a tier, his own board order breaks the tie.
    ///   2. **His board.** `prospectCustomBoard`, the order the Big Board
    ///      persists, for everyone he ever gave a slot.
    ///   3. **The media**, fogged, for a class he never touched — the same
    ///      `mediaConsensusOrder` the public board on screen is printed from.
    ///
    /// `avoid` is a veto, not a demotion: a man the user crossed off is skipped
    /// at every step above, and reached for only when the pool holds nobody
    /// else at all (better a name than a forfeited card).
    ///
    /// Nothing here can see a hidden rating. `scoutedOverall` is not read
    /// either — the board order already contains whatever the user's scouts
    /// told him, at the resolution he chose to believe them.
    ///
    /// - Parameters:
    ///   - pool: the men still on the board.
    ///   - boardRanks: the caller's cached `slotMap`, measured over the whole
    ///     DECLARED class so the ordering does not renumber itself as the pool
    ///     shrinks. Pass `[:]` to have it derived from `pool`.
    /// - Returns: `nil` only for an empty pool.
    static func autoPick(among pool: [CollegeProspect], boardRanks: [UUID: Int]) -> CollegeProspect? {
        guard !pool.isEmpty else { return nil }
        let ranks = boardRanks.isEmpty ? slotMap(among: pool) : boardRanks

        /// His board order, with the media as the tie-break for two men the
        /// board never separated. A total order, so `min(by:)` is stable.
        func boardOrder(_ lhs: CollegeProspect, _ rhs: CollegeProspect) -> Bool {
            let l = ranks[lhs.id] ?? Int.max
            let r = ranks[rhs.id] ?? Int.max
            if l != r { return l < r }
            return consensusOrder(lhs, rhs)
        }

        // 1) The marks, best tier first.
        for tier in [ProspectMarkTier.elite, .target] {
            if let best = pool.filter({ $0.userMark == tier }).min(by: boardOrder) {
                return best
            }
        }
        // 2) The board he built, for anyone he ranked.
        let ranked = pool.filter { $0.userMark != .avoid && ranks[$0.id] != nil }
        if let best = ranked.min(by: boardOrder) { return best }
        // 3) The fogged media consensus — best player available, publicly.
        let unvetoed = pool.filter { $0.userMark != .avoid }
        if let best = unvetoed.min(by: { consensusOrder($0, $1) }) { return best }
        // 4) Nothing left but men he crossed off. Still better than a forfeit.
        return pool.min(by: { consensusOrder($0, $1) })
    }

    /// Media consensus, preferring the shared board rank when one has been
    /// published and falling back to `DraftIntel`'s comparator.
    private static func consensusOrder(_ lhs: CollegeProspect, _ rhs: CollegeProspect) -> Bool {
        let l = DraftIntel.consensusRank(for: lhs.id) ?? Int.max
        let r = DraftIntel.consensusRank(for: rhs.id) ?? Int.max
        if l != r { return l < r }
        return DraftIntel.mediaConsensusOrder(lhs, rhs)
    }
}

// MARK: - DraftAvailability
//
// The ONE answer to "will he still be there at my pick?".
//
// There were two, and they disagreed on every prospect the media had named a
// slot for. `BigBoardView.availableAtPickProbability` bucketed off the ROUND
// (`boardProjectedRound` vs the pick's round → 0.95/0.75/0.40/0.15/0.05), while
// `MockDraftView.availabilityProbability` interpolated off `mockDraftPickNumber`
// — so a prospect mocked at #18 read "40 % at #20" on one screen and "76 %" on
// the other, and the pick sheet had no read at all.
//
// The reconciliation is already in `DraftIntel.consensusWindow`: a mock slot is
// a POINT opinion, a projected round is a BAND opinion 32 picks wide, and the
// media has no further view inside a band. One curve, whose steepness is set by
// how sharp the public opinion actually is.
enum DraftAvailability {

    /// How confident the room is that he is gone by a given pick.
    enum Tier {
        case likely, coinflip, longShot

        var label: String {
            switch self {
            case .likely:   return "LIKELY"
            case .coinflip: return "COINFLIP"
            case .longShot: return "LONG SHOT"
            }
        }

        var color: Color {
            switch self {
            case .likely:   return .success
            case .coinflip: return .accentBlue
            case .longShot: return .danger
            }
        }
    }

    /// Rendering-ready availability read.
    struct Read {
        /// 0.03…0.95 — never 0 and never 1, because the media is never certain.
        let probability: Double
        /// The pick the media's published opinion centres on.
        let expectedPick: Int
        /// Width of the public window: 1 for a named mock slot, 32 for a bare
        /// round projection. The honesty knob — a wide window means the number
        /// is a shrug.
        let windowWidth: Int

        var percent: Int { Int((probability * 100).rounded()) }

        var tier: Tier {
            if probability >= 0.60 { return .likely }
            if probability >= 0.30 { return .coinflip }
            return .longShot
        }

        /// True when the read rests on a bare round projection, i.e. the media
        /// never named a slot and the percentage is a band estimate.
        var isBandEstimate: Bool { windowWidth > 1 }
    }

    /// Probability the prospect is still on the board at `pickNumber`.
    ///
    /// Pure, `DraftIntel`-style: pass `consensusRank` when the caller already
    /// holds a board, otherwise the shared consensus board is consulted.
    /// Returns 0.5 — an explicit "nobody knows" — when the media has published
    /// no opinion at all, which is the only honest answer for an unranked man.
    static func probability(
        for prospect: CollegeProspect,
        atPick pickNumber: Int,
        consensusRank: Int? = nil
    ) -> Double {
        guard let read = read(for: prospect, atPick: pickNumber, consensusRank: consensusRank) else { return 0.5 }
        return read.probability
    }

    /// Full read, or `nil` when the media has published nothing to read.
    static func read(
        for prospect: CollegeProspect,
        atPick pickNumber: Int,
        consensusRank: Int? = nil
    ) -> Read? {
        guard let window = DraftIntel.consensusWindow(for: prospect, consensusRank: consensusRank) else { return nil }
        let width = max(1, window.late - window.early + 1)
        // The centre of the published window is where the room expects him gone.
        let expected = (window.early + window.late) / 2
        // Positive gap = the room has him coming off AFTER your pick.
        let gap = Double(expected - pickNumber)
        // Slope scales with the width of the opinion: a named slot is sharp
        // (~4 picks of doubt), a round band is deliberately flat (~16), because
        // grading a band to the slot is exactly the fake precision the value
        // dead zone in `DraftIntel.pickValueDelta` exists to prevent.
        let spread = max(4.0, Double(width) * 0.5)
        let raw = 1.0 / (1.0 + exp(-gap / spread))
        return Read(
            probability: min(0.95, max(0.03, raw)),
            expectedPick: expected,
            windowWidth: width
        )
    }

    /// Short sentence for a detail row.
    static func summary(for read: Read, atPick pickNumber: Int) -> String {
        let placement = read.isBandEstimate
            ? "The media has him in the \(roundLabel(ofPick: read.expectedPick)) band"
            : "The media mocks him at #\(read.expectedPick)"
        return "\(placement) — \(read.percent)% still there at #\(pickNumber)."
    }

    private static func roundLabel(ofPick pickNumber: Int) -> String {
        let round = max(1, ((pickNumber - 1) / DraftIntel.picksPerRound) + 1)
        return "Rd \(round)"
    }
}
