// ============================================================================
// PerceptionScenario — AI DRAFT FOG diagnostic (Track C)
// ============================================================================
//
// Measures what `AIDraftPerception` actually does to a draft, using the SHIPPED
// pieces end to end:
//
//   • `DraftClassBuilder.buildOrdered` + `ScoutingEngine` combine/declaration —
//     the same intake the `draftclass` scenario validates;
//   • `AIDraftPerception.read` (verbatim source) — the per-(team, prospect) fog;
//   • `DraftEngine.aiMakePick` (keep-list slice) — the AI scorer itself,
//     including `evaluateTeamNeeds` and the R24 top-4 weighted-random pick.
//
// Nothing about the draft is re-implemented here. The scenario only supplies
// what the app supplies: 32 clubs with rosters, a board, and a pick order.
//
// It is a DIAGNOSTIC, not a gate: it prints numbers and always exits 0. The
// gates that constrain this work are `draftclass` (the intake is unchanged) and
// `career` (league quality after 20 leagues × N seasons of AI drafting).
//
// Reported per draft:
//   reach   round-1 pick where the man taken sat >= 8 slots below the slot on
//           the TRUE board (true value = trueOverall + 0.15 * truePotential —
//           the same shape `aiMakePick` scores, minus need and minus fog);
//   steal   any pick where the man taken sat >= 20 slots ABOVE it;
//   BPA>5   the true board's #1 prospect was still on it after pick 5;
//   |err|   mean |perceived − true| on the current-level read, by GM persona.
//
// Both arms are run: `fog on` (shipped) and `fog off` (`perceptionEnabled:
// false`, the pre-Track-C behaviour) so every number has its own control.

import Foundation

// MARK: - Config

private struct PXConfig {
    var drafts = 12
    var classSize = 350
    var clubs = 32
    var picks = 224
    var rosterSize = 45
    /// Round-1 slots-below-true-board that counts as a reach.
    var reachGap = 8
    /// Slots-above-true-board that counts as a steal.
    var stealGap = 20
    var seed: UInt64 = 0x5EED_D24F_7C0F_0001
}

/// The true consensus board's value function: the value shape `aiMakePick`
/// scores, with the need multiplier and the fog removed. Ranking prospects by
/// it gives the board a perfectly-informed, need-free front office would use —
/// which is exactly the yardstick a reach or a steal is measured against.
private func pxTrueValue(_ p: CollegeProspect) -> Double {
    Double(p.trueOverall) + 0.15 * Double(p.truePotential)
}

/// The PUBLIC (media) board's ordering — a literal transcription of
/// `DraftIntel.mediaConsensusOrder`, which the harness cannot import (DraftIntel
/// is not on the `sync_sources.sh` keep-list and pulls in the whole scouting/UI
/// graph). Every field read here is published information: the latest mock's
/// slot, the projected round band, the combine invite, college production.
///
/// This is the yardstick task #155 is about. `pxTrueValue` above measures the AI
/// against OMNISCIENCE, which no fan and no beat writer has; this measures it
/// against the board the room, the user and the media all actually see. An AI
/// club may legitimately disagree with the consensus — that is what scouting is
/// for — but a whole league disagreeing by 100+ slots on every round-1 pick is
/// not disagreement, it is an anchor that is not attached to anything.
private func pxMediaConsensusOrder(_ lhs: CollegeProspect, _ rhs: CollegeProspect) -> Bool {
    let lhsMock = lhs.mockDraftPickNumber ?? Int.max
    let rhsMock = rhs.mockDraftPickNumber ?? Int.max
    if lhsMock != rhsMock { return lhsMock < rhsMock }
    let lhsRound = lhs.draftProjection ?? 9
    let rhsRound = rhs.draftProjection ?? 9
    if lhsRound != rhsRound { return lhsRound < rhsRound }
    if lhs.combineInvite != rhs.combineInvite { return lhs.combineInvite }
    if lhs.collegeProductionScore != rhs.collegeProductionScore {
        return lhs.collegeProductionScore > rhs.collegeProductionScore
    }
    return lhs.id.uuidString < rhs.id.uuidString
}

/// Deterministic UUIDs so the 32 personas are the same league every run.
private func pxUUID(_ rng: inout SeededLeagueRandom) -> UUID {
    var bytes = [UInt8](repeating: 0, count: 16)
    var word = rng.next()
    for i in 0..<16 {
        if i % 8 == 0 && i > 0 { word = rng.next() }
        bytes[i] = UInt8(truncatingIfNeeded: word >> UInt64((i % 8) * 8))
    }
    return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                       bytes[4], bytes[5], bytes[6], bytes[7],
                       bytes[8], bytes[9], bytes[10], bytes[11],
                       bytes[12], bytes[13], bytes[14], bytes[15]))
}

/// A prospect turned into a roster body. Only `position` and `overall` are read
/// (by `DraftEngine.evaluateTeamNeeds`), so the shipped rookie scaling is used
/// straight — no development, no camp, no contract.
private func pxPlayer(from prospect: CollegeProspect, teamID: UUID) -> Player {
    let factors = DraftEngine.rookieScaleFactors(
        readiness: prospect.nflReadiness,
        learning: prospect.trueLearning,
        potential: prospect.truePotential,
        undrafted: false
    )
    let player = Player(
        fullName: prospect.fullName,
        position: prospect.position,
        physical: DraftEngine.scalePhysical(prospect.truePhysical, factor: factors.physical),
        mental: DraftEngine.scaleMental(prospect.trueMental, factor: factors.mental),
        positionAttributes: DraftEngine.scalePositionAttributes(
            prospect.truePositionAttributes, factor: factors.skill
        ),
        personalityArchetype: prospect.truePersonality.archetype
    )
    player.age = prospect.age
    player.truePotential = prospect.truePotential
    player.teamID = teamID
    return player
}

// MARK: - One draft

private struct PXDraftResult {
    var round1Reaches = 0
    var steals = 0
    var bpaSlidPastFive = false
    /// Mean |true-board rank − pick| over round 1.
    var round1RankGap = 0.0
    /// Mean OVR of the 32 players taken in round 1.
    var round1MeanOVR = 0.0
    /// Mean TRUE-board rank of the 32 men taken in round 1 — the quality of the
    /// first round. If the fog made AI clubs materially worse at drafting, this
    /// is where it shows: the same 32 slots spend on lower-ranked players.
    var round1MeanRank = 0.0
    /// Mean true ceiling of the 32 men taken in round 1.
    var round1MeanPotential = 0.0
    /// Task #155: |pickNumber − PUBLIC board rank|, collected per round for
    /// rounds 1-3 (index 0 = round 1). The public board is the only board a
    /// draft-day card, a fan reaction or a pick grade can be argued against.
    var publicGapByRound: [[Double]] = [[], [], []]
    /// Signed (pick − publicRank) over rounds 1-3 pooled: negative = the AI
    /// takes men the media has LATER than the slot (reaching), positive = it
    /// lets consensus men slide.
    var publicSignedR13: [Double] = []
    /// Position of every round-1 pick, to expose the premium-position skew.
    var round1Positions: [Position] = []
}

private func pxRunDraft(
    cfg: PXConfig,
    board: [CollegeProspect],
    clubs: [Team],
    baseRosters: [UUID: [Player]],
    fog: Bool
) -> PXDraftResult {
    // True-board rank, 1-based.
    let ranked = board.sorted { pxTrueValue($0) > pxTrueValue($1) }
    var trueRank: [UUID: Int] = [:]
    for (i, p) in ranked.enumerated() { trueRank[p.id] = i + 1 }
    let bestID = ranked.first?.id

    // PUBLIC board rank, 1-based, over the same declared class (#155).
    var publicRank: [UUID: Int] = [:]
    for (i, p) in board.sorted(by: pxMediaConsensusOrder).enumerated() { publicRank[p.id] = i + 1 }

    var available = board
    var rosters = baseRosters
    var result = PXDraftResult()
    var round1Gaps: [Double] = []
    var round1OVR: [Double] = []
    var round1Ranks: [Double] = []
    var round1Pot: [Double] = []

    var pick = 0
    while pick < cfg.picks, !available.isEmpty {
        let club = clubs[pick % clubs.count]
        let chosen = DraftEngine.aiMakePick(
            team: club,
            availableProspects: available,
            teamRoster: rosters[club.id] ?? [],
            perceptionEnabled: fog
        )
        let pickNumber = pick + 1
        let rank = trueRank[chosen.id] ?? cfg.picks

        if pickNumber == 6, let bestID, available.contains(where: { $0.id == bestID }) {
            result.bpaSlidPastFive = true
        }
        if pickNumber <= 32 {
            if rank - pickNumber >= cfg.reachGap { result.round1Reaches += 1 }
            round1Gaps.append(Double(abs(rank - pickNumber)))
            round1Ranks.append(Double(rank))
            round1Pot.append(Double(chosen.truePotential))
            result.round1Positions.append(chosen.position)
        }
        if pickNumber - rank >= cfg.stealGap { result.steals += 1 }

        // #155: the same pick measured against the PUBLIC board.
        if pickNumber <= 96, let pub = publicRank[chosen.id] {
            let round = (pickNumber - 1) / 32
            result.publicGapByRound[round].append(Double(abs(pickNumber - pub)))
            result.publicSignedR13.append(Double(pickNumber - pub))
        }

        let player = pxPlayer(from: chosen, teamID: club.id)
        if pickNumber <= 32 { round1OVR.append(Double(player.overall)) }
        rosters[club.id, default: []].append(player)
        available.removeAll { $0.id == chosen.id }
        pick += 1
    }

    // The #1 prospect can also go inside the first five picks and never trip the
    // check above if the board ran out early — guard the degenerate case.
    if let bestID, available.contains(where: { $0.id == bestID }) { result.bpaSlidPastFive = true }

    result.round1RankGap = round1Gaps.isEmpty ? 0 : round1Gaps.reduce(0, +) / Double(round1Gaps.count)
    result.round1MeanOVR = round1OVR.isEmpty ? 0 : round1OVR.reduce(0, +) / Double(round1OVR.count)
    result.round1MeanRank = round1Ranks.isEmpty ? 0 : round1Ranks.reduce(0, +) / Double(round1Ranks.count)
    result.round1MeanPotential = round1Pot.isEmpty ? 0 : round1Pot.reduce(0, +) / Double(round1Pot.count)
    return result
}

// MARK: - Scenario

func scenarioPerception(_ flags: [String: String]) {
    var cfg = PXConfig()
    if let v = Int(flags["drafts"] ?? "") { cfg.drafts = max(1, v) }
    if let v = Int(flags["size"] ?? "") { cfg.classSize = max(120, v) }
    if let v = UInt64(flags["seed"] ?? "") { cfg.seed = v }

    print("===== SCENARIO perception: AI draft fog (Track C) =====")
    print("  \(cfg.drafts) drafts x \(cfg.picks) picks | class size \(cfg.classSize) | \(cfg.clubs) clubs")
    print(String(format: "  model: sigma analytics %.1f / balanced %.1f / aggressive %.1f / oldSchool %.1f  (+%.1f on potential)",
                 AIDraftPerception.sigmaOverall(for: .analytics),
                 AIDraftPerception.sigmaOverall(for: .balanced),
                 AIDraftPerception.sigmaOverall(for: .aggressive),
                 AIDraftPerception.sigmaOverall(for: .oldSchool),
                 AIDraftPerception.potentialSigmaBonus))
    print(String(format: "         fat tail %.0f%% of pairs at +-%.0f..%.0f OVR | read correlation %.2f",
                 AIDraftPerception.fatTailRate * 100,
                 AIDraftPerception.fatTailMin, AIDraftPerception.fatTailMax,
                 AIDraftPerception.readCorrelation))
    print("")

    // --- 32 clubs with stable ids (=> stable personas) and rosters ------------
    var idRNG = SeededLeagueRandom(seed: cfg.seed)
    let clubIDs = (0..<cfg.clubs).map { _ in pxUUID(&idRNG) }

    // Roster stock: throwaway classes dealt out at random, so the 32 need
    // profiles genuinely differ (a club short at CB really does chase CBs).
    var stock: [CollegeProspect] = []
    while stock.count < cfg.clubs * cfg.rosterSize {
        stock += DraftClassBuilder.buildOrdered(count: cfg.classSize).prospects
    }
    stock.shuffle()
    var clubs: [Team] = []
    var baseRosters: [UUID: [Player]] = [:]
    for (i, id) in clubIDs.enumerated() {
        let slice = stock[(i * cfg.rosterSize)..<((i + 1) * cfg.rosterSize)]
        let roster = slice.map { pxPlayer(from: $0, teamID: id) }
        baseRosters[id] = roster
        clubs.append(Team(id: id, players: roster))
    }

    // --- persona census -------------------------------------------------------
    var personaCount: [String: Int] = [:]
    for id in clubIDs {
        let a = AIDraftPerception.lens(forTeam: id).archetype
        personaCount[a.rawValue, default: 0] += 1
    }
    let census = TradeValueEngine.GMArchetype.allCases
        .map { "\($0.rawValue) \(personaCount[$0.rawValue] ?? 0)" }
        .joined(separator: " | ")
    print("  personas in this league: \(census)")

    // --- run both arms --------------------------------------------------------
    var errByPersona: [String: [Double]] = [:]
    var fatTailHits = 0
    var fatTailPairs = 0
    var armOn: [PXDraftResult] = []
    var armOff: [PXDraftResult] = []
    var absErrAll: [Double] = []

    for _ in 0..<cfg.drafts {
        var prospects = DraftClassBuilder.buildOrdered(count: cfg.classSize).prospects
        ScoutingEngine.generateCombineResults(for: &prospects, scoutingAbility: 50)
        _ = ScoutingEngine.generateDeclarations(prospects: &prospects)
        let board = prospects.filter { $0.isDeclaringForDraft }
        guard board.count > 40 else { continue }

        // Per-(club, prospect) read error census — the raw fog, before any pick.
        for id in clubIDs {
            let lens = AIDraftPerception.lens(forTeam: id)
            for p in board {
                let read = AIDraftPerception.read(
                    teamID: id, prospectID: p.id,
                    trueOverall: p.trueOverall, truePotential: p.truePotential,
                    lens: lens
                )
                errByPersona[lens.archetype.rawValue, default: []].append(abs(read.overallError))
                absErrAll.append(abs(read.overallError))
                fatTailPairs += 1
                if read.isFatTail { fatTailHits += 1 }
            }
        }

        armOn.append(pxRunDraft(cfg: cfg, board: board, clubs: clubs, baseRosters: baseRosters, fog: true))
        armOff.append(pxRunDraft(cfg: cfg, board: board, clubs: clubs, baseRosters: baseRosters, fog: false))
    }

    func mean(_ xs: [Double]) -> Double { xs.isEmpty ? 0 : xs.reduce(0, +) / Double(xs.count) }
    func summarize(_ arm: [PXDraftResult], label: String) {
        let reaches = mean(arm.map { Double($0.round1Reaches) })
        let steals = mean(arm.map { Double($0.steals) })
        let bpa = arm.isEmpty ? 0 : Double(arm.filter(\.bpaSlidPastFive).count) / Double(arm.count) * 100
        let gap = mean(arm.map(\.round1RankGap))
        let ovr = mean(arm.map(\.round1MeanOVR))
        let rank = mean(arm.map(\.round1MeanRank))
        let pot = mean(arm.map(\.round1MeanPotential))
        print(String(format: "  %-8@ R1 reaches %.2f/draft | steals %.2f/draft | true-BPA slid past pick 5 in %.0f%% of drafts",
                     label, reaches, steals, bpa))
        print(String(format: "           R1 quality: mean true-board rank %.1f | mean rookie OVR %.2f | mean true ceiling %.2f | mean |rank-pick| %.2f",
                     rank, ovr, pot, gap))
    }

    print("")
    print("--- DRAFT OUTCOMES (both arms, identical boards + rosters) --------------------")
    summarize(armOff, label: "fog off")
    summarize(armOn, label: "fog ON")

    // --- #155: AI board vs the PUBLIC board ----------------------------------
    func pctl(_ xs: [Double], _ q: Double) -> Double {
        guard !xs.isEmpty else { return 0 }
        let s = xs.sorted()
        let i = min(s.count - 1, max(0, Int((Double(s.count - 1) * q).rounded())))
        return s[i]
    }
    func publicReport(_ arm: [PXDraftResult], label: String) {
        var pooled: [Double] = []
        var perRound: [[Double]] = [[], [], []]
        var signed: [Double] = []
        for d in arm {
            for r in 0..<3 { perRound[r] += d.publicGapByRound[r] }
            pooled += d.publicGapByRound.flatMap { $0 }
            signed += d.publicSignedR13
        }
        let rounds = (0..<3).map { r -> String in
            String(format: "R%d %.1f", r + 1, mean(perRound[r]))
        }.joined(separator: " | ")
        print(String(format: "  %-8@ mean |pick-publicRank| %.1f  (%@)   median %.0f  p90 %.0f  max %.0f",
                     label, mean(pooled), rounds,
                     pctl(pooled, 0.5), pctl(pooled, 0.90), pooled.max() ?? 0))
        let ahead = signed.filter { $0 < -20 }.count
        print(String(format: "           signed mean %+.1f | taken >20 slots AHEAD of the media on %.0f%% of R1-3 picks (n=%d)",
                     mean(signed),
                     signed.isEmpty ? 0 : Double(ahead) / Double(signed.count) * 100,
                     signed.count))
        // Positional census of round 1 — the premium-position skew, if any.
        var posCount: [String: Int] = [:]
        var total = 0
        for d in arm { for p in d.round1Positions { posCount[p.rawValue, default: 0] += 1; total += 1 } }
        let top = posCount.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.prefix(6)
        let census = top.map { String(format: "%@ %.0f%%", $0.key, Double($0.value) / Double(max(1, total)) * 100) }
            .joined(separator: " ")
        print("           R1 positions: \(census)")
    }

    print("")
    print("--- vs THE PUBLIC BOARD (task #155) ------------------------------------------")
    publicReport(armOff, label: "fog off")
    publicReport(armOn, label: "fog ON")

    print("")
    print("--- READ ERROR ---------------------------------------------------------------")
    for a in TradeValueEngine.GMArchetype.allCases {
        let xs = errByPersona[a.rawValue] ?? []
        guard !xs.isEmpty else { continue }
        let over = xs.filter { $0 >= 8 }.count
        print(String(format: "  %-11@ mean |perceived-true| %.2f OVR   (>=8 OVR off on %.1f%% of prospects, n=%d)",
                     a.rawValue, mean(xs), Double(over) / Double(xs.count) * 100, xs.count))
    }
    print(String(format: "  LEAGUE      mean |perceived-true| %.2f OVR   fat tail fired on %.2f%% of pairs (target %.0f%%)",
                 mean(absErrAll),
                 fatTailPairs == 0 ? 0 : Double(fatTailHits) / Double(fatTailPairs) * 100,
                 AIDraftPerception.fatTailRate * 100))

    // --- determinism check ----------------------------------------------------
    // The whole model rests on "the same club misjudges the same man the same
    // way, forever". Prove it rather than assert it in a comment.
    let t = clubIDs[0]
    let p = UUID()
    let a = AIDraftPerception.read(teamID: t, prospectID: p, trueOverall: 74, truePotential: 88)
    let b = AIDraftPerception.read(teamID: t, prospectID: p, trueOverall: 74, truePotential: 88)
    print("")
    print("  determinism: repeat read identical = \(a.overall == b.overall && a.potential == b.potential)")

    print("")
    print("PERCEPTION: OK (diagnostic — no gate)")
}
