import Foundation

// MARK: - Field Personnel

/// The 11 starters each side sends onto the 3D field, ordered by the
/// `PlayChoreographer` role contract so node labels, matchup events, and
/// choreography all reference the same real players:
/// - offense: 0=QB 1=RB 2=LT 3=LG 4=C 5=RG 6=RT 7=WR-L 8=WR-R 9=slot 10=TE
/// - defense: 0=DE-L 1=DT 2=DT 3=DE-R 4=LB-L 5=MLB 6=LB-R 7=CB-L 8=CB-R 9=S-L 10=S-R
struct FieldUnit {
    let players: [SimPlayer]

    var numbers: [Int] { players.map(\.displayNumber) }

    subscript(role: Int) -> SimPlayer { players[role] }

    /// Role index of a player by id, if he is on the field.
    func role(of id: UUID?) -> Int? {
        guard let id else { return nil }
        return players.firstIndex { $0.id == id }
    }

    // MARK: Selection

    /// Best-available starters from a full roster, role-ordered for offense.
    static func offense(from roster: [SimPlayer]) -> FieldUnit {
        var picked = Set<UUID>()
        func best(_ positions: [Position]) -> SimPlayer {
            var choice: SimPlayer? = nil
            for player in roster where positions.contains(player.position) && !picked.contains(player.id) {
                if choice == nil || player.overall > choice!.overall { choice = player }
            }
            if choice == nil {
                for player in roster where !picked.contains(player.id) {
                    if choice == nil || player.overall > choice!.overall { choice = player }
                }
            }
            let result = choice ?? roster[0]
            picked.insert(result.id)
            return result
        }
        let qb = best([.QB])
        // Mirror PlaySimulator.findRB exactly (best RB, FB only as fallback)
        // so the carrier on the field is the carrier in the play feed.
        let hasRB = roster.contains { $0.position == .RB && !picked.contains($0.id) }
        let rb = hasRB ? best([.RB]) : best([.FB])
        let lt = best([.LT])
        let lg = best([.LG])
        let c  = best([.C])
        let rg = best([.RG])
        let rt = best([.RT])
        let wr1 = best([.WR])
        let wr2 = best([.WR])
        let slot = best([.WR])
        let te = best([.TE])
        return FieldUnit(players: [qb, rb, lt, lg, c, rg, rt, wr1, wr2, slot, te])
    }

    /// Best-available starters from a full roster, role-ordered for defense.
    static func defense(from roster: [SimPlayer]) -> FieldUnit {
        var picked = Set<UUID>()
        func best(_ positions: [Position]) -> SimPlayer {
            var choice: SimPlayer? = nil
            for player in roster where positions.contains(player.position) && !picked.contains(player.id) {
                if choice == nil || player.overall > choice!.overall { choice = player }
            }
            if choice == nil {
                for player in roster where !picked.contains(player.id) {
                    if choice == nil || player.overall > choice!.overall { choice = player }
                }
            }
            let result = choice ?? roster[0]
            picked.insert(result.id)
            return result
        }
        let deL = best([.DE])
        let dt1 = best([.DT])
        let dt2 = best([.DT])
        let deR = best([.DE])
        let lbL = best([.OLB])
        let mlb = best([.MLB, .OLB])
        let lbR = best([.OLB, .MLB])
        let cbL = best([.CB])
        let cbR = best([.CB])
        let sL  = best([.FS, .SS])
        let sR  = best([.SS, .FS])
        return FieldUnit(players: [deL, dt1, dt2, deR, lbL, mlb, lbR, cbL, cbR, sL, sR])
    }
}

extension SimPlayer {
    /// Stable pseudo jersey number derived from the player's UUID (the data
    /// model has no real numbers). Deterministic across launches and mapped
    /// into a realistic range for the position.
    var displayNumber: Int {
        let bytes = id.uuid
        let seed = Int(bytes.0) << 8 | Int(bytes.1)
        let range: ClosedRange<Int>
        switch position {
        case .QB, .K, .P:      range = 1...19
        case .RB, .FB:         range = 20...49
        case .WR:              range = 80...89
        case .TE:              range = 80...89
        case .LT, .LG, .C, .RG, .RT: range = 60...79
        case .DE, .DT:         range = 90...99
        case .OLB, .MLB:       range = 50...59
        case .CB, .FS, .SS:    range = 20...39
        default:               range = 1...99
        }
        return range.lowerBound + seed % (range.upperBound - range.lowerBound + 1)
    }

    /// "T. Hill" — short display name for feed lines and callouts.
    var shortName: String {
        let parts = fullName.split(separator: " ")
        guard parts.count >= 2, let first = parts.first?.first else { return fullName }
        return "\(first). \(parts.dropFirst().joined(separator: " "))"
    }
}

// MARK: - Play Matchups

/// Named player-vs-player battles resolved for one live play. The play
/// OUTCOME is already decided by `PlaySimulator`; this layer attributes the
/// outcome to individual players — rating-weighted, so stars win their
/// matchups more often — and hands the choreographer the visual parameters
/// (pocket collapse, separation, hole size).
struct PlayMatchups {

    struct Event: Identifiable {
        enum Kind {
            case trench, separation, coverage, pressure, bust, star
        }
        let id = UUID()
        let kind: Kind
        /// Feed/banner line, e.g. "M. Parsons beats T. Davis around the edge".
        let text: String
        let offenseWon: Bool
        /// Role indices per the choreographer contract (nil = no field pulse).
        let offRole: Int?
        let defRole: Int?
        /// 0…1 how decisive the win was.
        let magnitude: Double
    }

    var events: [Event] = []

    // Visual parameters consumed by PlayChoreographer.
    /// 0 = clean pocket … 1 = instant collapse.
    var pocketCollapse: Double = 0.4
    /// Yards of separation at the catch point (0.4 blanket … 4 wide open).
    var separation: Double = 1.5
    /// 0 = stuffed at the line … 1 = gaping hole.
    var holeSize: Double = 0.5
    /// Defense role (0–3) of the winning rusher on sacks.
    var rushWinnerDefRole: Int = 2
    /// Offense role of the ball's destination (receiver/carrier), when known.
    var targetOffRole: Int?
    /// Defense role of the intercepting DB, when known.
    var pickDefRole: Int?
    /// Offense role of a NON-targeted receiver who clearly won his route on
    /// a pass play (visual: he uncovers, and if the ball never came his way
    /// he throws his hands up). Nil when nobody else was obviously open.
    var openNonTargetOffRole: Int?
    /// True when the open man above went unthrown on a failed or short
    /// dropback — the "QB missed the read" signal for the feed line and his
    /// day grade. Purely presentational; the sim never reads it.
    var qbMissedOpenMan = false
}

// MARK: - Matchup Resolver

enum MatchupResolver {

    /// Attributes a resolved play to individual matchup winners/losers.
    static func resolve(
        play: PlayResult,
        offense: FieldUnit,
        defense: FieldUnit,
        offensiveScheme: OffensiveScheme?,
        offensiveCall: OffensivePlayCall?
    ) -> PlayMatchups {
        var m = PlayMatchups()
        m.targetOffRole = offense.role(of: play.keyOffensePlayerID)
        m.pickDefRole = defense.role(of: play.keyDefensePlayerID)

        switch play.outcome {
        case .sack:
            resolveSack(&m, offense: offense, defense: defense)
        case .safety where play.playType == .pass:
            resolveSack(&m, offense: offense, defense: defense)
        case .completion, .touchdown where play.playType == .pass:
            resolveCompletion(&m, play: play, offense: offense, defense: defense)
        case .incompletion:
            resolveIncompletion(&m, play: play, offense: offense, defense: defense,
                                scheme: offensiveScheme, call: offensiveCall)
        case .interception:
            resolveInterception(&m, play: play, offense: offense, defense: defense)
        case .rush, .fumble, .fumbleLost, .safety,
             .touchdown where play.playType == .run:
            resolveRun(&m, play: play, offense: offense, defense: defense,
                       scheme: offensiveScheme, call: offensiveCall)
        default:
            break
        }

        // Dropbacks: was somebody ELSE clearly open? Rating-driven and purely
        // presentational — the outcome and target above never change.
        if play.playType == .pass {
            resolveOpenNonTarget(&m, play: play, offense: offense, defense: defense)
        }

        // Star showcase: an 88+ OVR winner gets flagged so the UI can shine.
        m.events = m.events.map { event in
            let winner: SimPlayer? = event.offenseWon
                ? event.offRole.map { offense[$0] }
                : event.defRole.map { defense[$0] }
            guard let winner, winner.overall >= 88, !event.text.hasPrefix("⭐") else { return event }
            return Event(kind: .star, text: "⭐ \(event.text)", offenseWon: event.offenseWon,
                         offRole: event.offRole, defRole: event.defRole, magnitude: event.magnitude)
        }
        return m
    }

    private typealias Event = PlayMatchups.Event

    // MARK: Sack

    private static func resolveSack(_ m: inout PlayMatchups, offense: FieldUnit, defense: FieldUnit) {
        // R37: the sim NAMES the sacker (keyDefensePlayerID → pickDefRole
        // when he's on the field), so the feed line, box score, and pocket
        // visual all point at the same man. A blitzing backer gets his own
        // line; the pocket still caves from a rating-weighted DL side.
        if let role = m.pickDefRole, (4...6).contains(role) {
            let rusher = defense[role]
            m.rushWinnerDefRole = weightedPick(roles: [0, 1, 2, 3], weight: { passRush(defense[$0]) })
            m.pocketCollapse = 0.9
            m.separation = 0.8
            m.events.append(Event(
                kind: .pressure,
                text: "\(rusher.shortName) times the blitz and gets home",
                offenseWon: false, offRole: nil, defRole: role, magnitude: 0.85
            ))
            return
        }
        // Who got home? The sim's named DL when he's on the field, else
        // rating-weighted among the four rushers, so elite edges/tackles
        // collect the wins.
        let rusherRole = m.pickDefRole.flatMap { (0...3).contains($0) ? $0 : nil }
            ?? weightedPick(roles: [0, 1, 2, 3], weight: { passRush(defense[$0]) })
        let blockerRole = blockerFacing(defRole: rusherRole)
        let rusher = defense[rusherRole]
        let blocker = offense[blockerRole]
        let diff = passRush(rusher) - passBlock(blocker)
        let magnitude = clamp(0.5 + diff / 40, 0.35, 1)
        let lane = (rusherRole == 0 || rusherRole == 3) ? "around the edge" : "up the middle"

        m.rushWinnerDefRole = rusherRole
        m.pocketCollapse = 0.7 + 0.3 * magnitude
        m.separation = 0.8
        m.events.append(Event(
            kind: .pressure,
            text: "\(rusher.shortName) beats \(blocker.shortName) \(lane)",
            offenseWon: false, offRole: blockerRole, defRole: rusherRole, magnitude: magnitude
        ))
    }

    // MARK: Completion

    private static func resolveCompletion(_ m: inout PlayMatchups, play: PlayResult,
                                          offense: FieldUnit, defense: FieldUnit) {
        // No named callout when the sim targeted someone off the field —
        // the text must never contradict the play feed.
        guard let targetRole = m.targetOffRole, targetRole >= 1 else { return }
        let receiver = offense[targetRole]
        let cbRole = coverFor(offRole: targetRole)
        let corner = defense[cbRole]

        let diff = catchRating(receiver) - coverage(corner)
        let sep = clamp(1.2 + Double(play.yardsGained) / 12 + diff / 40, 0.6, 4)
        m.separation = sep
        m.pocketCollapse = 0.15

        if play.yardsGained >= 15 || sep >= 2.6 {
            m.events.append(Event(
                kind: .separation,
                text: "\(receiver.shortName) leaves \(corner.shortName) behind at the break",
                offenseWon: true, offRole: targetRole, defRole: cbRole,
                magnitude: clamp(sep / 4, 0.4, 1)
            ))
        } else if sep < 1.2 {
            m.events.append(Event(
                kind: .separation,
                text: "\(receiver.shortName) hangs on through \(corner.shortName)'s blanket coverage",
                offenseWon: true, offRole: targetRole, defRole: cbRole, magnitude: 0.5
            ))
        }

        // Clean-pocket shoutout when the line is clearly winning.
        let bestBlocker = weightedPick(roles: [2, 3, 4, 5, 6], weight: { passBlock(offense[$0]) })
        let bestRusher = weightedPick(roles: [0, 1, 2, 3], weight: { passRush(defense[$0]) })
        if passBlock(offense[bestBlocker]) - passRush(defense[bestRusher]) > 10, play.yardsGained >= 12 {
            m.events.append(Event(
                kind: .trench,
                text: "\(offense[bestBlocker].shortName) gives him all day in the pocket",
                offenseWon: true, offRole: bestBlocker, defRole: bestRusher, magnitude: 0.6
            ))
        }
    }

    // MARK: Incompletion

    private static func resolveIncompletion(_ m: inout PlayMatchups, play: PlayResult,
                                            offense: FieldUnit, defense: FieldUnit,
                                            scheme: OffensiveScheme?, call: OffensivePlayCall?) {
        guard let targetRole = m.targetOffRole, targetRole >= 1 else { return }
        let receiver = offense[targetRole]
        let cbRole = coverFor(offRole: targetRole)
        let corner = defense[cbRole]
        m.separation = 0.6

        // Scheme bust: a receiver who hasn't learned the playbook sometimes
        // cuts the route short — surfaced so the coach can SEE why it failed.
        if let scheme, bustRoll(receiver, scheme: scheme, call: call) {
            m.events.append(Event(
                kind: .bust,
                text: "\(receiver.shortName) cuts the route short — still learning the playbook",
                offenseWon: false, offRole: targetRole, defRole: nil, magnitude: 0.7
            ))
            return
        }

        // R37: the sim named a pass breakup — the field callout credits the
        // SAME defender the feed line and the PD stat do.
        if play.passBreakup == true, let dbRole = m.pickDefRole {
            let db = defense[dbRole]
            m.separation = 0.5
            m.events.append(Event(
                kind: .coverage,
                text: "\(db.shortName) closes and breaks it up at the catch point",
                offenseWon: false, offRole: targetRole, defRole: dbRole, magnitude: 0.7
            ))
            return
        }

        if coverage(corner) - catchRating(receiver) > 5 {
            m.events.append(Event(
                kind: .coverage,
                text: "\(corner.shortName) blankets \(receiver.shortName) — nowhere to fit it",
                offenseWon: false, offRole: targetRole, defRole: cbRole,
                magnitude: clamp((coverage(corner) - catchRating(receiver)) / 30, 0.4, 1)
            ))
        }
    }

    // MARK: Open Non-Target (QB read layer)

    /// Finds the best NON-targeted eligible on a pass play. When his edge
    /// over his cover man is decisive he's flagged as clearly open — the
    /// choreographer uncovers him on the field. If the ball then failed or
    /// died short, that reads as a missed read: a feed line names him and
    /// the QB's day grade takes a small ding (`qbMissedOpenMan`). Outcome,
    /// target selection and sim distributions are untouched.
    private static func resolveOpenNonTarget(_ m: inout PlayMatchups, play: PlayResult,
                                             offense: FieldUnit, defense: FieldUnit) {
        let eligible: [Int] = [7, 8, 9, 10, 1].filter { $0 != m.targetOffRole }
        var best: (role: Int, edge: Double)?
        for role in eligible {
            let edge = catchRating(offense[role]) - coverage(defense[coverFor(offRole: role)])
                + Double.random(in: -5...5)
            if best == nil || edge > best!.edge { best = (role, edge) }
        }
        guard let best, best.edge >= 8 else { return }
        m.openNonTargetOffRole = best.role

        let failed = play.outcome == .incompletion || play.outcome == .interception
            || play.outcome == .sack
        let short = play.outcome == .completion && play.yardsGained < min(play.distance, 4)
        guard failed || short else { return }
        m.qbMissedOpenMan = true
        let receiver = offense[best.role]
        m.events.append(Event(
            kind: .separation,
            text: "\(receiver.shortName) had a step — the ball went elsewhere",
            offenseWon: true, offRole: best.role, defRole: coverFor(offRole: best.role),
            magnitude: 0.55
        ))
    }

    // MARK: Interception

    private static func resolveInterception(_ m: inout PlayMatchups, play: PlayResult,
                                            offense: FieldUnit, defense: FieldUnit) {
        m.separation = 0.4
        // Only call out the pick when the crediting DB is one of the eleven
        // on the field — naming someone else would contradict the play feed.
        guard let dbRole = m.pickDefRole else { return }
        let db = defense[dbRole]
        m.events.append(Event(
            kind: .coverage,
            text: "\(db.shortName) reads it all the way and jumps the route",
            offenseWon: false, offRole: m.targetOffRole, defRole: dbRole, magnitude: 1
        ))
    }

    // MARK: Run

    private static func resolveRun(_ m: inout PlayMatchups, play: PlayResult,
                                   offense: FieldUnit, defense: FieldUnit,
                                   scheme: OffensiveScheme?, call: OffensivePlayCall?) {
        let yards = play.yardsGained
        m.holeSize = yards <= 0 ? 0.1 : (yards <= 3 ? 0.35 : (yards <= 7 ? 0.6 : 0.95))

        // Point of attack: interior for inside runs/sneaks, edge otherwise.
        let inside = call.map { [.insideRun, .qbSneak, .draw, .counter, .dive].contains($0) } ?? true
        let poaBlockers = inside ? [3, 4, 5] : [2, 6]
        let poaDefenders = inside ? [1, 2, 5] : [0, 3]
        let carrierRole = m.targetOffRole ?? 1
        let carrier = offense[carrierRole]

        // R37: a named big hit gets its field callout — same tackler as the
        // feed line ("lays the wood").
        if play.defensiveHighlight == true, let hitRole = m.pickDefRole {
            m.events.append(Event(
                kind: .trench,
                text: "\(defense[hitRole].shortName) lays the wood on \(carrier.shortName)",
                offenseWon: false, offRole: carrierRole, defRole: hitRole, magnitude: 0.9
            ))
        }

        if yards >= 8 {
            let blockerRole = weightedPick(roles: poaBlockers, weight: { runBlock(offense[$0]) })
            m.events.append(Event(
                kind: .trench,
                text: "\(offense[blockerRole].shortName) paves the lane — \(carrier.shortName) hits it clean",
                offenseWon: true, offRole: blockerRole, defRole: nil,
                magnitude: clamp(Double(yards) / 20, 0.5, 1)
            ))
        } else if yards <= 1 {
            // Bust first: a lineman who hasn't learned the scheme misses his man.
            if let scheme,
               let bustRole = poaBlockers.first(where: { bustRoll(offense[$0], scheme: scheme, call: call) }) {
                m.events.append(Event(
                    kind: .bust,
                    text: "\(offense[bustRole].shortName) blows the assignment — the gap never opens",
                    offenseWon: false, offRole: bustRole, defRole: nil, magnitude: 0.7
                ))
                return
            }
            // Prefer the tackler the sim NAMED when he's at the point of
            // attack (R37) — feed, stats and field pulse stay in agreement.
            let stufferRole = m.pickDefRole.flatMap { poaDefenders.contains($0) ? $0 : nil }
                ?? weightedPick(roles: poaDefenders, weight: {
                    $0 <= 3 ? blockShed(defense[$0]) : tackling(defense[$0])
                })
            let blockerRole = poaBlockers.min {
                runBlock(offense[$0]) < runBlock(offense[$1])
            } ?? poaBlockers[0]
            m.events.append(Event(
                kind: .trench,
                text: "\(defense[stufferRole].shortName) sheds \(offense[blockerRole].shortName) and stuffs it",
                offenseWon: false, offRole: blockerRole, defRole: stufferRole,
                magnitude: 0.7
            ))
        }

        if yards >= 15 {
            m.events.append(Event(
                kind: .star,
                text: "⭐ \(carrier.shortName) turns on the jets",
                offenseWon: true, offRole: carrierRole, defRole: nil, magnitude: 1
            ))
        }
    }

    // MARK: Helpers

    /// The blocker who faces a given defensive line role.
    private static func blockerFacing(defRole: Int) -> Int {
        switch defRole {
        case 0: return 6   // DE-L rushes the offense's right tackle
        case 1: return 4   // DT vs C/G interior
        case 2: return 3
        default: return 2  // DE-R vs LT
        }
    }

    /// The primary cover man for a receiving role.
    private static func coverFor(offRole: Int) -> Int {
        switch offRole {
        case 7: return 7          // WR-L vs CB-L
        case 8: return 8          // WR-R vs CB-R
        case 9: return 9          // slot vs S-L
        case 10: return 5         // TE vs MLB
        case 1: return 6          // RB checkdown vs LB-R
        default: return 7
        }
    }

    /// Rating-weighted role pick, so better players are credited more often.
    private static func weightedPick(roles: [Int], weight: (Int) -> Double) -> Int {
        let weights = roles.map { max(1, weight($0) * weight($0)) }
        var roll = Double.random(in: 0..<weights.reduce(0, +))
        for (role, w) in zip(roles, weights) {
            roll -= w
            if roll <= 0 { return role }
        }
        return roles.last ?? 0
    }

    /// Scheme-familiarity bust roll — low familiarity busts more often.
    private static func bustRoll(_ player: SimPlayer, scheme: OffensiveScheme,
                                 call: OffensivePlayCall?) -> Bool {
        var fam = Double(player.schemeFam(for: scheme.rawValue))
        // Calling a play outside the installed playbook is harder on everyone.
        if let call, !call.schemes.contains(scheme) { fam -= 15 }
        guard fam < 45 else { return false }
        return Double.random(in: 0...1) < (45 - fam) / 120
    }

    // Attribute extractors (mirror PlaySimulator's private helpers).

    private static func passRush(_ p: SimPlayer) -> Double {
        if case .defensiveLine(let a) = p.positionAttributes {
            return Double((a.passRush + a.powerMoves + a.finesseMoves) / 3)
        }
        return 50
    }

    private static func passBlock(_ p: SimPlayer) -> Double {
        if case .offensiveLine(let a) = p.positionAttributes { return Double(a.passBlock) }
        return 50
    }

    private static func runBlock(_ p: SimPlayer) -> Double {
        if case .offensiveLine(let a) = p.positionAttributes { return Double(a.runBlock) }
        return 50
    }

    private static func blockShed(_ p: SimPlayer) -> Double {
        if case .defensiveLine(let a) = p.positionAttributes { return Double(a.blockShedding) }
        return 50
    }

    private static func tackling(_ p: SimPlayer) -> Double {
        if case .linebacker(let a) = p.positionAttributes { return Double(a.tackling) }
        return 50
    }

    private static func coverage(_ p: SimPlayer) -> Double {
        if case .defensiveBack(let a) = p.positionAttributes {
            return Double((a.manCoverage + a.zoneCoverage) / 2)
        }
        if case .linebacker(let a) = p.positionAttributes {
            return Double((a.manCoverage + a.zoneCoverage) / 2)
        }
        return 50
    }

    private static func catchRating(_ p: SimPlayer) -> Double {
        switch p.positionAttributes {
        case .wideReceiver(let a): return Double((a.catching + a.routeRunning) / 2)
        case .tightEnd(let a):     return Double((a.catching + a.routeRunning) / 2)
        case .runningBack(let a):  return Double(a.receiving)
        default: return 45
        }
    }

    private static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        Swift.min(hi, Swift.max(lo, v))
    }
}
