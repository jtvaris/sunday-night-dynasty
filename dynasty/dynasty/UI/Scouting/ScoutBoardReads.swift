import Foundation
import SwiftUI
import SwiftData

// MARK: - Scout board reads (#105)
//
// THE DERIVED READ OVER THE BOARD, COMPUTED ONCE.
//
// Everything in here used to be `@State` on `BigBoardView` — `cachedTeamNeeds`,
// `cachedNeedPositions`, `cachedBestByPosition`, `cachedBestAvailable`, the
// depth rows, the picks line — filled by one private `refreshNeedReads()` and
// rendered by two sections of the board's own `List`. Those two sections have
// moved to their own surface (`ScoutNotesView`), and the board still needs the
// need SET for the NEED chip on every row, so the answer had to become a value
// both screens can hold rather than state one screen owns.
//
// The alternative — a second copy of the walk in the new screen — is the defect
// class this file exists to prevent. `ProspectFog.read` widens a stored band by
// `DraftIntel.scoutConfidence` for every man it is asked about; two independent
// walks over ~350 prospects is not just twice the work, it is two places for
// the tie-break to drift, and the moment they drift the board's NEED chip and
// the notes screen's "your #1 need" name different positions on the same night.
//
// Same convention as `DraftPrepProgress`: a dumb renderer fed by a value built
// once. Build it with ``make(prospects:teamRoster:teamDraftPicks:)``, hold it,
// render it.
//
// ## Fog discipline
//
// Nothing in this file reads `trueOverall`, and nothing sorts on the raw
// `scoutedOverall` integer. The one ordering primitive is ``BoardReadKey``,
// whose first component is the MIDPOINT of the fogged band the screen actually
// prints. See its doc comment, and ``gradeText(_:)``'s, for the two bugs that
// bought those rules.

struct ScoutBoardReads {

    // MARK: - Roster shape
    //
    // Declared once. `BigBoardView.needLevel(for:)` and the depth rows below
    // both measure a hole as `ideal - onRoster`, and they used to carry two
    // hand-copied tables of the same 19 numbers.

    /// A league-typical count at each position on a 53-man roster.
    static let idealRosterCounts: [Position: Int] = [
        .QB: 2, .RB: 3, .FB: 1, .WR: 5, .TE: 3,
        .LT: 2, .LG: 2, .C: 2, .RG: 2, .RT: 2,
        .DE: 4, .DT: 3, .OLB: 4, .MLB: 2,
        .CB: 5, .FS: 2, .SS: 2, .K: 1, .P: 1
    ]

    /// The ideal count for one position, with the same default (2) both old
    /// copies of the table used for anything unlisted.
    static func idealRosterCount(for position: Position) -> Int {
        idealRosterCounts[position] ?? 2
    }

    // MARK: - Depth row

    /// One need position: how many of him are on the board against how many the
    /// roster is short.
    struct DepthItem: Identifiable {
        let position: Position
        /// Men at this position the club's scouts have filed on.
        let onBoard: Int
        /// `max(1, ideal - onRoster)` — never zero, because a position only
        /// appears here when it is already one of the club's three holes.
        let needed: Int

        var id: Position { position }

        var isSufficient: Bool { onBoard >= needed }
    }

    /// A draft slot, flattened off `DraftPick` so this value type holds no
    /// model references and can be built, stored and compared freely.
    struct PickSlot {
        let round: Int
        let pickNumber: Int
    }

    // MARK: - Stored answers

    /// The club's holes, best first. See ``computeTeamNeeds(roster:)``.
    let needs: [Position]

    /// `Set(needs)`, or EMPTY when the roster is empty — every board ROW asks
    /// this, so it is built once rather than re-ranking the roster 350 times a
    /// pass, and "we do not know" is not the same claim as "we need nothing".
    let needPositions: Set<Position>

    /// Best man on the board per need position, ordered by what the user can
    /// actually see. See ``BoardReadKey``.
    let bestByPosition: [Position: CollegeProspect]

    /// Best man on the whole board, by the same yardstick.
    let bestAvailable: CollegeProspect?

    /// One row per need position, in need order.
    let depthItems: [DepthItem]

    /// The club's earliest unmade pick in the draft this cycle is building
    /// toward, or `nil` when it has none left.
    let firstPick: PickSlot?

    /// "Rd 1 #4, Rd 2 #36" — the club's remaining picks, in order.
    let picksSummary: String

    // MARK: - Derived

    var topNeed: Position? { needs.first }

    var bestAtTopNeed: CollegeProspect? {
        guard let need = topNeed else { return nil }
        return bestByPosition[need]
    }

    /// Best available prospect on the board for a given position.
    func best(at position: Position) -> CollegeProspect? {
        bestByPosition[position]
    }

    /// The empty read — no roster, no board, no picks. The `@State` seed, and
    /// what every surface renders for the frame before its `.task` runs.
    static let empty = ScoutBoardReads(
        needs: [],
        needPositions: [],
        bestByPosition: [:],
        bestAvailable: nil,
        depthItems: [],
        firstPick: nil,
        picksSummary: "No picks"
    )

    // MARK: - Grade text

    /// Grade text for a prospect — the stored band, else nothing at all.
    ///
    /// The old last resort was `LetterGrade.from(numericValue: … ?? trueOverall)`,
    /// which would have printed the generator's grade for a man nobody had filed
    /// on. Unreachable behind the scouted filter, and removed for the same
    /// reason `boardCompositeScore`'s twin was: fail soft, never fall back to
    /// the truth.
    ///
    /// Through the fog, not around it. Reading `scoutedOverallGrade` straight
    /// skipped the confidence widening `ProspectFog.read` applies, so this strip
    /// printed a pinpoint "B+" for a man whose own board row, two inches away,
    /// correctly read "B-/A-" — the same prospect, two certainties, on one
    /// screen.
    func gradeText(_ prospect: CollegeProspect) -> String {
        Self.gradeText(prospect)
    }

    /// Static twin of ``gradeText(_:)`` for call sites that do not hold a read.
    static func gradeText(_ prospect: CollegeProspect) -> String {
        let read = ProspectFog.read(prospect)
        return read.source == .scouts ? read.text : "\u{2014}"
    }

    // MARK: - Availability at the club's first pick

    /// Probability prospect is available at the user's first pick (#18).
    ///
    /// ONE availability model, shared with the Mock Draft and the war room's
    /// pick sheet (`DraftAvailability`). This used to bucket off the ROUND —
    /// `boardProjectedRound` vs the pick's round → 0.95/0.75/0.40/0.15/0.05 —
    /// so a man the media mocked at #18 read 40 % here and 76 % on the Mock
    /// Draft, and the two screens contradicted each other about the same
    /// player on the same day. The curve now reads the media's published
    /// window and is as flat as that window is wide.
    func availableAtPickProbability(for prospect: CollegeProspect) -> Double? {
        guard let firstPick else { return nil }
        return DraftAvailability.probability(
            for: prospect,
            atPick: firstPick.pickNumber,
            consensusRank: Self.marketRank(for: prospect)
        )
    }

    // MARK: - Market rank (pinned contract: media-only)

    /// The media's consensus board slot for one prospect.
    ///
    /// `DraftIntel` owns it, and by contract it is built from public
    /// information ONLY — the latest mock's pick number, then the projected
    /// round — never `scoutedOverall`. Routed through one call site so the
    /// board, the value chip and the seed all read the same number.
    static func marketRank(for prospect: CollegeProspect) -> Int? {
        DraftIntel.consensusRank(for: prospect.id)
    }

    // MARK: - Ordering

    /// How the recommendation strip ranks two men: the fogged band's MIDPOINT
    /// first, the media's consensus slot second, the prospect's own id last so
    /// two identical reads still order the same way twice.
    private struct BoardReadKey {
        /// `ProspectFog.Read.rank` — the mid-grade of the band the row prints.
        /// Higher is better.
        let readRank: Int
        /// `DraftIntel.consensusRank`. Public by contract; lower is better.
        let marketRank: Int
        let id: UUID

        func beats(_ other: BoardReadKey) -> Bool {
            if readRank != other.readRank { return readRank > other.readRank }
            if marketRank != other.marketRank { return marketRank < other.marketRank }
            return id.uuidString < other.id.uuidString
        }
    }

    /// The best man in a pool AS THE USER SEES HIM.
    ///
    /// These answers used to sort on raw `scoutedOverall` — a number the screen
    /// never prints — while the grade text beside the name printed the FOGGED
    /// band. One point of a hidden integer could therefore hand the "Best:"
    /// chip to a man whose visible band ("B-/B+") was plainly worse than the
    /// next man's ("A-/A+"): the strip contradicted itself on one line.
    /// Ordering by the read's own midpoint makes the recommendation and the
    /// grade beside it the same claim.
    ///
    /// Kept as a named entry point even though ``make`` inlines the same key
    /// into its single pass: it is the definition the pass implements, and a
    /// caller holding one pool should never write a second comparator.
    static func bestByRead(_ pool: [CollegeProspect]) -> CollegeProspect? {
        var best: (prospect: CollegeProspect, key: BoardReadKey)?
        for prospect in pool {
            let read = ProspectFog.read(prospect)
            // Our own paper only. A media projection is not a scouting answer,
            // and `gradeText` would print "—" beside the name.
            guard read.source == .scouts, read.band != nil else { continue }
            let key = BoardReadKey(
                readRank: read.rank,
                marketRank: marketRank(for: prospect) ?? Int.max,
                id: prospect.id
            )
            if best == nil || key.beats(best!.key) {
                best = (prospect, key)
            }
        }
        return best?.prospect
    }

    // MARK: - Needs

    /// The club's holes, best first, and the SAME answer every visit.
    ///
    /// `DraftEngine.topTeamNeeds` was the old source and it is not stable. It
    /// sorts a `[Position: Double]` on value alone, and on a full roster the
    /// EVIDENCE half of that score is exactly 1.0 nearly everywhere (the ideal
    /// counts sum to 48 against a 53-man roster), so the ranking collapses onto
    /// the five weight-1.0 positions {QB, DE, CB, WR, LT} — five EQUAL scores,
    /// handed back in whatever order `Dictionary` iteration and an unstable
    /// `sorted` produce. "Your #1 need" therefore read LT, then CB, then LT,
    /// then DE over four visits with nothing about the roster changed, and the
    /// "Scout: Need" trio reshuffled underneath it.
    ///
    /// `teamNeedDeficits` is the deterministic sibling and the one the rest of
    /// this hub already reads (`ClassDepthView`, the interview room's NEED
    /// column): only positions whose evidence half clears 1.0 survive, and equal
    /// scores tiebreak on `rawValue`. Three surfaces of one hub now name the
    /// same holes.
    ///
    /// An empty deficit list is a real and common answer — a well-built roster
    /// has no holes — and the fallback is exact rather than arbitrary: deficits
    /// come back empty only when every multiplier is exactly 1.0, which is
    /// precisely the case where `topTeamNeeds`' scores ARE the bare positional
    /// weights and its top five tie. Sorting those five by `rawValue` loses no
    /// ordering, because there was none to lose.
    static func computeTeamNeeds(roster: [Player]) -> [Position] {
        let deficits = DraftEngine.teamNeedDeficits(roster: roster, limit: 3)
        if !deficits.isEmpty { return deficits }
        return Array(
            DraftEngine.topTeamNeeds(roster: roster, limit: 5)
                .sorted { $0.rawValue < $1.rawValue }
                .prefix(3)
        )
    }

    // MARK: - The factory

    /// Every answer above, in ONE pass over the board.
    ///
    /// One pass because `ProspectFog.read` widens a stored band by
    /// `DraftIntel.scoutConfidence` for every man it is asked about, and the
    /// old shape asked once per candidate per strip line, per body pass — plus
    /// one filter of the whole class per depth row on top of that.
    ///
    /// `prospects` is the class as the host holds it; the scouted filter is
    /// applied HERE so no caller can accidentally hand in a pool that includes
    /// men nobody has filed on.
    static func make(
        prospects: [CollegeProspect],
        teamRoster: [Player],
        teamDraftPicks: [DraftPick]
    ) -> ScoutBoardReads {
        let needs = computeTeamNeeds(roster: teamRoster)
        // An empty roster is "we do not know", not "we need nothing" — the NEED
        // badge on a row must stay dark until the club has players to compare.
        let needPositions: Set<Position> = teamRoster.isEmpty ? [] : Set(needs)

        let wanted = Set(needs)
        var bestByPosition: [Position: (prospect: CollegeProspect, key: BoardReadKey)] = [:]
        var bestOverall: (prospect: CollegeProspect, key: BoardReadKey)?
        /// Men on the board per need position — counted in the same walk, and
        /// BEFORE the scouts-only guard below, because the depth row counts
        /// everyone the department has filed on, not only the men who survive
        /// the "best" comparator.
        var onBoardByPosition: [Position: Int] = [:]

        for prospect in prospects where prospect.scoutedOverall != nil {
            if wanted.contains(prospect.position) {
                onBoardByPosition[prospect.position, default: 0] += 1
            }
            let read = ProspectFog.read(prospect)
            guard read.source == .scouts, read.band != nil else { continue }
            let key = BoardReadKey(
                readRank: read.rank,
                marketRank: marketRank(for: prospect) ?? Int.max,
                id: prospect.id
            )
            if bestOverall == nil || key.beats(bestOverall!.key) {
                bestOverall = (prospect, key)
            }
            guard wanted.contains(prospect.position) else { continue }
            if let current = bestByPosition[prospect.position], !key.beats(current.key) { continue }
            bestByPosition[prospect.position] = (prospect, key)
        }

        var rosterCounts: [Position: Int] = [:]
        for player in teamRoster where wanted.contains(player.position) {
            rosterCounts[player.position, default: 0] += 1
        }

        let depthItems = needs.map { position in
            DepthItem(
                position: position,
                onBoard: onBoardByPosition[position] ?? 0,
                // Estimate need count from roster deficit (1-3 range).
                needed: max(1, idealRosterCount(for: position) - (rosterCounts[position] ?? 0))
            )
        }

        let openPicks = teamDraftPicks
            .filter { !$0.isComplete }
            .sorted { $0.pickNumber < $1.pickNumber }

        return ScoutBoardReads(
            needs: needs,
            needPositions: needPositions,
            bestByPosition: bestByPosition.mapValues(\.prospect),
            bestAvailable: bestOverall?.prospect,
            depthItems: depthItems,
            firstPick: openPicks.first.map { PickSlot(round: $0.round, pickNumber: $0.pickNumber) },
            picksSummary: openPicks.isEmpty
                ? "No picks"
                : openPicks.map { "Rd \($0.round) #\($0.pickNumber)" }.joined(separator: ", ")
        )
    }

    // MARK: - Fetch

    /// The club's picks in the draft this cycle is building toward — and ONLY
    /// those.
    ///
    /// This used to fetch every `DraftPick` the team owned, in any year. The
    /// pick pool always holds three future drafts as well (`futureDraftPicks`,
    /// the tradable horizon), and each of those rows carries a *provisional*
    /// slot: the midpoint of its round, `round * 32 - 16`. So the Draft Prep
    /// card listed "Rd 1 #16, Rd 1 #16, Rd 1 #16, Rd 2 #48, Rd 2 #48…" — 28
    /// picks in triplicate — and "available at your first pick" was computed
    /// against a fabricated #16 belonging to a draft three years out, on a team
    /// that in this year's draft was picking fourth.
    static func teamPicks(career: Career, in context: ModelContext) -> [DraftPick] {
        guard let teamID = career.teamID else { return [] }
        let season = career.currentSeason
        let desc = FetchDescriptor<DraftPick>(
            predicate: #Predicate<DraftPick> {
                $0.currentTeamID == teamID && $0.seasonYear == season
            }
        )
        return (try? context.fetch(desc)) ?? []
    }

    // MARK: - Roster priorities (the user's own half of the depth read)

    /// Map a Position to its `EvalPositionGroup` id for roster priority lookup.
    static func positionGroupID(for position: Position) -> String {
        switch position {
        case .QB: return "QB"
        case .RB, .FB: return "RB"
        case .WR: return "WR"
        case .TE: return "TE"
        case .LT, .LG, .C, .RG, .RT: return "OL"
        case .DE, .DT: return "DL"
        case .OLB, .MLB: return "LB"
        case .CB, .FS, .SS: return "DB"
        case .K, .P: return "ST"
        }
    }
}
