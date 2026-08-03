import Foundation

/// Player-facing knowledge layer for the draft.
///
/// `DraftIntel` exposes only what the user legitimately knows: the MEDIA's
/// board (mock slot, projected round, public workout/production signals),
/// scout-confidence stars, position need scoring, and reach indicators. It does
/// NOT expose hidden information such as `truePotential`, and — since the
/// media-board rewrite — it does not read the user's own scouting either.
enum DraftIntel {

    // MARK: - Public board rank

    /// Ordering of the PUBLIC (media) board. Every field read here is published
    /// information: the latest mock's pick number, the projected round, whether
    /// the league invited him to Indianapolis, and his college production.
    ///
    /// Deliberately NOT `scoutedOverall`: that is the user's own scouting
    /// department talking. Sorting the "consensus" board on it made the media
    /// agree with your scouts by construction — a prospect could only be a
    /// STEAL if *you* had graded him, `WarRoomPanel`'s SLEEPER tag compared a
    /// list against a re-ordering of itself, and the AI trade market reacted to
    /// the user's private board. Worse, the old fallback (`?? trueOverall`)
    /// leaked the hidden rating for anybody unscouted straight into the board's
    /// ORDER, which is a bigger tell than any number the UI prints.
    ///
    /// Positional value is baked into the class blueprint, so no multiplier
    /// belongs here at all.
    static func mediaConsensusOrder(_ lhs: CollegeProspect, _ rhs: CollegeProspect) -> Bool {
        // 1) The latest mock named a slot for him — the sharpest public opinion.
        let lhsMock = lhs.mockDraftPickNumber ?? Int.max
        let rhsMock = rhs.mockDraftPickNumber ?? Int.max
        if lhsMock != rhsMock { return lhsMock < rhsMock }
        // 2) The projected round band.
        let lhsRound = lhs.draftProjection ?? 9
        let rhsRound = rhs.draftProjection ?? 9
        if lhsRound != rhsRound { return lhsRound < rhsRound }
        // 3) Invited to the combine — public, and a real signal inside a band.
        if lhs.combineInvite != rhs.combineInvite { return lhs.combineInvite }
        // 4) College production. Public by definition (it happened on TV) and
        //    the only thing that separates two men the media put in the same
        //    round. Without it the whole band would order by UUID.
        if lhs.collegeProductionScore != rhs.collegeProductionScore {
            return lhs.collegeProductionScore > rhs.collegeProductionScore
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    /// Builds a `[ProspectID: boardRank (1...N)]` map for the draft class from
    /// public information only (see `mediaConsensusOrder`). The rank is where
    /// the *media* would slot him, which is what every STEAL / REACH / slide
    /// comparison in the draft room claims to measure against.
    ///
    /// PURE. It used to publish its result to the shared cache as a side
    /// effect, which let any caller holding a *subset* redefine the board for
    /// every other screen: the draft room passes its live available pool, the
    /// hub passes the declared class, a deep-linked prospect card passed the
    /// whole class including undeclared men — so the `VAL` chip on a list row
    /// and the `market ≈ #N` line on that same prospect's card could print
    /// different numbers depending on which screen had been opened first.
    /// `refreshConsensusBoard(for:)` is now the ONE writer.
    @discardableResult
    static func publicBoardRanks(for prospects: [CollegeProspect]) -> [UUID: Int] {
        let sorted = prospects.sorted(by: mediaConsensusOrder)
        var result: [UUID: Int] = [:]
        for (idx, prospect) in sorted.enumerated() {
            result[prospect.id] = idx + 1
        }
        return result
    }

    // MARK: - Shared consensus board (cross-screen)

    /// Last board built by `publicBoardRanks(for:)` / `refreshConsensusBoard(for:)`.
    /// Static because the scouting screens and the draft room are different
    /// object graphs looking at the same published board; nothing here is
    /// persisted and a rebuild is one sort of the class.
    private static var cachedConsensusRanks: [UUID: Int] = [:]

    /// Rebuilds the shared board — the ONLY writer of `cachedConsensusRanks`.
    ///
    /// The population is normalised here rather than at the call sites: the
    /// shared board is always the DECLARED draft class, never a live pool that
    /// shrinks as picks come off it and never a class array that still carries
    /// undeclared underclassmen. Every screen that publishes therefore agrees
    /// with every other, whichever one the user opened first.
    static func refreshConsensusBoard(for prospects: [CollegeProspect]) {
        let declared = prospects.filter(\.isDeclaringForDraft)
        let population = declared.isEmpty ? prospects : declared
        let result = publicBoardRanks(for: population)
        if !result.isEmpty { cachedConsensusRanks = result }
    }

    /// MEDIA-ONLY board rank for one prospect, or `nil` when no board has been
    /// built yet this session. Never derived from `scoutedOverall`.
    static func consensusRank(for prospectID: UUID) -> Int? {
        cachedConsensusRanks[prospectID]
    }

    /// Drops the shared board. Called from
    /// `WeekAdvancer.resetProcessStateForCareerSwitch` with every other
    /// process-global cache: the ranks are keyed by prospect id, so another
    /// save's board is harmless but its memory is not worth carrying, and a
    /// stale board surviving a career switch is the kind of cross-save leak
    /// that is easier to prevent than to debug.
    static func resetProcessState() {
        cachedConsensusRanks = [:]
    }

    /// Board rank computed against an explicit class — for call sites that
    /// already hold the array and do not want to depend on build order. Pure:
    /// it does not touch the shared cache (see `refreshConsensusBoard`).
    static func consensusRank(for prospectID: UUID, in prospects: [CollegeProspect]) -> Int? {
        publicBoardRanks(for: prospects)[prospectID]
    }

    // MARK: - Public OVR

    /// The overall the LEAGUE can quote for a prospect, 40...99.
    ///
    /// `scoutedOverall` when your department has filed on him; otherwise the
    /// midpoint of the media's band for his projected round — never
    /// `trueOverall`. The old `scoutedOverall ?? trueOverall` fallback looked
    /// harmless because season 1 runs `applyPreScoutedData` over the whole
    /// class, but that pass is gated on the first season: from season 2 onward
    /// `scoutedOverall` is nil for everything your own scouts have not covered,
    /// so the STEAL / HOF-TRACK chip on the pick sheet was computed from the
    /// hidden rating for the majority of the board.
    ///
    /// Band centres are `BigBoardView.boardProjectedRound`'s cut points read
    /// backwards (the class blueprint's talent curve): #28 ≈ 78.9, #99 ≈ 72.5,
    /// #189 ≈ 69.2, #295 ≈ 64.8.
    static func publicOVREstimate(for prospect: CollegeProspect) -> Int {
        if let scouted = prospect.scoutedOverall { return scouted }
        switch prospect.draftProjection ?? 8 {
        case 1:  return 82
        case 2:  return 77
        case 3:  return 74
        case 4:  return 71
        case 5:  return 70
        case 6:  return 68
        case 7:  return 66
        default: return 63
        }
    }

    // MARK: - Scout confidence

    /// Returns 1...5 stars representing how confident the player can be in
    /// what the scouts have reported. In Vaihe 2 we approximate this from
    /// the depth of scouting reports + whether combine / interview / pro day
    /// happened. Vaihe 5 will integrate per-scout coverage more tightly.
    static func scoutConfidence(for prospect: CollegeProspect) -> Int {
        var score = 1
        if !prospect.scoutingReports.isEmpty { score += 1 }
        if prospect.scoutingReports.count >= 2 { score += 1 }
        if prospect.combineInvite { score += 1 }
        if prospect.interviewCompleted || prospect.proDayCompleted { score += 1 }
        return min(5, score)
    }

    // MARK: - Reach indicator

    enum ReachIndicator {
        case steal(delta: Int)
        case solid
        case reach(delta: Int)

        var label: String {
            switch self {
            case .steal(let d): return "STEAL +\(d)"
            case .solid:        return "SOLID"
            case .reach(let d): return "REACH \(d)"
            }
        }
    }

    /// Compares the prospect's public rank to the current pick number.
    /// `boardRanks` should come from `publicBoardRanks(for:)`.
    ///
    /// Slot-precise by design — this is the badge for a man the media put in a
    /// numbered slot. For a pick graded against a *round* projection use
    /// `pickValueDelta(for:pickNumber:)`, which respects the band the media
    /// actually claimed.
    static func reachIndicator(
        prospectID: UUID,
        pickNumber: Int,
        boardRanks: [UUID: Int]
    ) -> ReachIndicator {
        guard let rank = boardRanks[prospectID] else { return .solid }
        let delta = pickNumber - rank
        if delta >= 4 { return .steal(delta: delta) }
        if delta <= -4 { return .reach(delta: delta) }
        return .solid
    }

    // MARK: - Consensus board (public information only)

    /// The `count` prospects the *media* rates highest.
    ///
    /// Same ordering as `publicBoardRanks` — one board, one comparator. (These
    /// two used to disagree: the board sorted on `scoutedOverall ?? trueOverall`
    /// while coverage statistics sorted on the mock, so "you have scouted 40 %
    /// of the top 100" counted a different hundred men than the ones the room
    /// was ranking.)
    static func consensusTop(_ prospects: [CollegeProspect], count: Int) -> [CollegeProspect] {
        Array(prospects.sorted(by: mediaConsensusOrder).prefix(count))
    }

    // MARK: - Where the media put him

    /// Picks in a full round. Draft order is 32 clubs; kept as a parameter so a
    /// future expansion league does not silently re-tune every slide beat.
    static let picksPerRound = 32

    /// The window of pick numbers the media's published opinion covers.
    ///
    /// - a mock slot is a *point* opinion ("he goes 14th");
    /// - a projected round is a *band* opinion ("he is a third-rounder"), and
    ///   inside that band the media has no further view — which is precisely
    ///   why value must not be graded to the slot down there;
    /// - the board rank is the last resort (a class with neither mock nor
    ///   projection, e.g. a legacy save).
    static func consensusWindow(
        for prospect: CollegeProspect,
        consensusRank: Int? = nil
    ) -> (early: Int, late: Int)? {
        if let mock = prospect.mockDraftPickNumber, mock > 0 {
            return (mock, mock)
        }
        if let round = prospect.draftProjection, round > 0 {
            let late = round * picksPerRound
            return (late - picksPerRound + 1, late)
        }
        if let rank = consensusRank ?? Self.consensusRank(for: prospect.id), rank > 0 {
            return (rank, rank)
        }
        return nil
    }

    /// Pick value against the PUBLIC board: positive = he lasted past what the
    /// media said (value/steal), negative = taken ahead of it (reach), zero =
    /// inside the window the media actually claimed.
    ///
    /// The dead zone is the fix for a real defect: grading a day-three pick to
    /// the exact board slot turned the media's coarse "he's a fifth-rounder"
    /// into a fake ±30-slot opinion, and the steal/reach chips fired on noise.
    static func pickValueDelta(
        for prospect: CollegeProspect,
        pickNumber: Int,
        consensusRank: Int? = nil
    ) -> Int {
        guard let window = consensusWindow(for: prospect, consensusRank: consensusRank) else { return 0 }
        if pickNumber < window.early { return pickNumber - window.early }
        if pickNumber > window.late { return pickNumber - window.late }
        return 0
    }

    // MARK: - Slides

    /// A slide has to clear both bars: an absolute number of picks…
    static let slideFloorPicks = 20
    /// …and a share of the man's own board slot, so "a third-rounder went in
    /// the fifth" is a story while "pick 190 went at 214" is not.
    static let slideRelativeShare = 0.6

    /// How far past the media's window he actually fell (0 = not past it).
    static func slideMagnitude(
        for prospect: CollegeProspect,
        pickNumber: Int,
        consensusRank: Int? = nil
    ) -> Int {
        guard let window = consensusWindow(for: prospect, consensusRank: consensusRank) else { return 0 }
        return max(0, pickNumber - window.late)
    }

    /// The rare, real "he is still sitting there" moment.
    ///
    /// The old test compared a PICK NUMBER against `draftProjection + 8` — a
    /// ROUND. Every prospect projected inside round 7 therefore "slid" from
    /// pick 16 onward, so the slide beat fired on essentially every card of the
    /// draft and meant nothing.
    static func isBigSlide(
        for prospect: CollegeProspect,
        pickNumber: Int,
        consensusRank: Int? = nil
    ) -> Bool {
        guard let window = consensusWindow(for: prospect, consensusRank: consensusRank) else { return false }
        let magnitude = max(0, pickNumber - window.late)
        guard magnitude >= slideFloorPicks else { return false }
        return Double(magnitude) >= Double(window.late) * slideRelativeShare
    }

    // MARK: - My grade vs the market

    /// Where a letter grade implies a man should come off the board, in pick
    /// numbers. Anchored on the class blueprint's talent curve (#10 ≈ 84 OVR,
    /// #28 ≈ 79, #99 ≈ 72.5, #189 ≈ 69, #295 ≈ 65 — see
    /// `CollegeProspect.scoutedTier`), so an A- grade implies a top-15 slot
    /// rather than an arbitrary constant.
    ///
    /// `userGradeOrdinal` is `LetterGrade.rank` (A+ = 12 … F = 1).
    ///
    /// Every slot the table returns has to exist on the board it is compared
    /// against. The bottom five grades used to return 310-365 against a
    /// declared class of ~285, so `valueDelta` read the man the media had 285th
    /// as an 80-slot "market darling" purely because his own scouts graded him
    /// F. `UserGrade` cannot reach those rows (it stops at "UDFA" → C), but
    /// `marketVerdict(for prospect:)` goes through `effectiveOverallGrade`, and
    /// scout grades do run to F.
    static func impliedBoardSlot(userGradeOrdinal: Int) -> Int {
        switch max(1, min(12, userGradeOrdinal)) {
        case 12: return 3      // A+
        case 11: return 7      // A
        case 10: return 14     // A-
        case 9:  return 26     // B+
        case 8:  return 48     // B
        case 7:  return 95     // B-
        case 6:  return 170    // C+
        case 5:  return 260    // C
        case 4:  return 275    // C-
        case 3:  return 281    // D+
        case 2:  return 284    // D
        default: return rankedBoardDepth // F — the last row on the board
        }
    }

    /// Deepest slot the ranked media board actually has. `generateDeclarations`
    /// targets 224 picks + a ~60-man UDFA cushion, so the declared class the
    /// board ranks is ~285 men; nothing may imply a slot past its last row.
    static let rankedBoardDepth = 285

    /// YOUR grade minus THE MARKET, in board slots.
    ///
    /// Positive = the media has him later than your scouts' grade implies (he
    /// is cheap — the sleeper case). Negative = the market is higher on him
    /// than you are (you would be paying the room's price).
    ///
    /// Pure function on purpose: the scouting screens render the column, this
    /// file owns the arithmetic, so steal/reach logic lives in one place.
    static func valueDelta(userGradeOrdinal: Int, consensusRank: Int) -> Int {
        guard consensusRank > 0 else { return 0 }
        return consensusRank - impliedBoardSlot(userGradeOrdinal: userGradeOrdinal)
    }

    /// Rendering-ready reading of `valueDelta`.
    enum MarketVerdict: Equatable {
        /// Your scouts are ahead of the room.
        case sleeper(delta: Int)
        /// You and the room agree.
        case aligned(delta: Int)
        /// The room is ahead of your scouts.
        case marketDarling(delta: Int)

        var delta: Int {
            switch self {
            case .sleeper(let d), .aligned(let d), .marketDarling(let d): return d
            }
        }

        /// Short chip text ("+34 VALUE" / "IN LINE" / "-21 MARKET").
        var label: String {
            switch self {
            case .sleeper(let d):       return "+\(d) VALUE"
            case .aligned:              return "IN LINE"
            case .marketDarling(let d): return "\(d) MARKET"
            }
        }

        /// One line of prose for a detail row.
        var detail: String {
            switch self {
            case .sleeper(let d):
                return "Your grade puts him \(d) slots above where the media has him."
            case .aligned:
                return "Your grade and the consensus board agree on him."
            case .marketDarling(let d):
                return "The media has him \(abs(d)) slots above your grade — you would be paying their price."
            }
        }
    }

    /// The gap has to scale with depth: 20 slots at the top of the board is a
    /// different claim from 20 slots at pick 250.
    static func marketVerdict(userGradeOrdinal: Int, consensusRank: Int) -> MarketVerdict {
        let delta = valueDelta(userGradeOrdinal: userGradeOrdinal, consensusRank: consensusRank)
        let implied = impliedBoardSlot(userGradeOrdinal: userGradeOrdinal)
        let threshold = max(12, Int(Double(implied) * 0.35))
        if delta >= threshold { return .sleeper(delta: delta) }
        if delta <= -threshold { return .marketDarling(delta: delta) }
        return .aligned(delta: delta)
    }

    /// Convenience for a prospect the user has actually graded. `nil` when his
    /// scouts have filed nothing (no grade = no opinion to compare).
    static func marketVerdict(for prospect: CollegeProspect, consensusRank: Int? = nil) -> MarketVerdict? {
        guard let grade = prospect.effectiveOverallGrade?.midGrade.rank,
              let rank = consensusRank ?? Self.consensusRank(for: prospect.id) else { return nil }
        return marketVerdict(userGradeOrdinal: grade, consensusRank: rank)
    }

    // MARK: - User's own marks on the board

    /// The user's mark on this prospect, or `nil` when unmarked.
    ///
    /// Thin wrapper on `CollegeProspect.userMark` so the draft room can use
    /// `if let` — and so the ONE verdict type (`ProspectMarkTier`, with its own
    /// icon/colour/short label) is shared with the scouting screens instead of
    /// the board growing a second vocabulary for the same four words.
    static func mark(for prospect: CollegeProspect) -> ProspectMarkTier? {
        let mark = prospect.userMark
        return mark == .none ? nil : mark
    }

    /// Wanted men still on the board, best mark first, then board order.
    static func markedTargets(
        in prospects: [CollegeProspect],
        tier: ProspectMarkTier? = nil
    ) -> [CollegeProspect] {
        prospects
            .filter { prospect in
                let mark = prospect.userMark
                if let tier { return mark == tier }
                return mark.isBoardPositive
            }
            .sorted { lhs, rhs in
                if lhs.userMark.sortRank != rhs.userMark.sortRank {
                    return lhs.userMark.sortRank < rhs.userMark.sortRank
                }
                return mediaConsensusOrder(lhs, rhs)
            }
    }

    // MARK: - Draft prep coverage

    /// How far along one prospect's evaluation is. Every case is a fact stored
    /// on the prospect — nothing here is inferred from a phase or a timer.
    struct PrepStatus {
        let reportCount: Int
        let isInterviewed: Bool
        /// The league measured him and the numbers reached your building.
        let hasMeasurables: Bool
        let hasProDay: Bool

        /// Nobody in the building has done a thing.
        var isUntouched: Bool {
            reportCount == 0 && !isInterviewed && !hasMeasurables && !hasProDay
        }

        /// Tape filed AND a meeting taken — the bar for "we know this man".
        var isWellScouted: Bool { reportCount >= 2 && isInterviewed }
    }

    static func prepStatus(for prospect: CollegeProspect) -> PrepStatus {
        PrepStatus(
            reportCount: prospect.scoutingReports.count,
            isInterviewed: prospect.interviewCompleted,
            hasMeasurables: prospect.fortyTime != nil,
            hasProDay: prospect.proDayCompleted
        )
    }

    /// Aggregate coverage of the consensus board's top slice.
    struct BoardCoverage {
        /// Size of the slice examined (may be < requested when the class is small).
        let sampleSize: Int
        /// How many of them carry at least one filed report.
        let scouted: Int
        /// How many of them your staff has interviewed.
        let interviewed: Int

        var scoutedPercent: Int {
            guard sampleSize > 0 else { return 0 }
            return Int((Double(scouted) / Double(sampleSize) * 100).rounded())
        }

        var interviewedPercent: Int {
            guard sampleSize > 0 else { return 0 }
            return Int((Double(interviewed) / Double(sampleSize) * 100).rounded())
        }
    }

    static func boardCoverage(prospects: [CollegeProspect], topCount: Int = 100) -> BoardCoverage {
        let slice = consensusTop(prospects, count: topCount)
        return BoardCoverage(
            sampleSize: slice.count,
            scouted: slice.filter { !$0.scoutingReports.isEmpty }.count,
            interviewed: slice.filter(\.interviewCompleted).count
        )
    }

    /// Coverage of one position group inside the consensus top slice — the
    /// input to "you have three picks and have filed on one linebacker".
    struct PositionCoverage: Identifiable {
        let position: Position
        let onBoard: Int
        let scouted: Int

        var id: String { position.rawValue }

        /// Thin means the group is a stated need and you have filed on fewer
        /// than two of the men the media rates inside it.
        var isThin: Bool { scouted < 2 && onBoard > 0 }
    }

    /// Scouting coverage for the team's top needs, restricted to the consensus
    /// top slice so a need is not declared "covered" by a seventh-round flier.
    static func needCoverage(
        prospects: [CollegeProspect],
        roster: [Player],
        topCount: Int = 100,
        needLimit: Int = 5
    ) -> [PositionCoverage] {
        let needs = DraftEngine.topTeamNeeds(roster: roster, limit: needLimit)
        guard !needs.isEmpty else { return [] }
        let slice = consensusTop(prospects, count: topCount)
        return needs.map { position in
            let group = slice.filter { $0.position == position }
            return PositionCoverage(
                position: position,
                onBoard: group.count,
                scouted: group.filter { !$0.scoutingReports.isEmpty }.count
            )
        }
    }

    // MARK: - Team needs

    /// Returns a `[Position: priority(0..1)]` map for the team.
    /// Highest-need position gets ~1.0, secondary needs scale down.
    static func teamNeedScores(roster: [Player]) -> [Position: Double] {
        let topNeeds = DraftEngine.topTeamNeeds(roster: roster, limit: 6)
        var scores: [Position: Double] = [:]
        for (idx, position) in topNeeds.enumerated() {
            scores[position] = max(0.3, 1.0 - Double(idx) * 0.15)
        }
        return scores
    }

}
