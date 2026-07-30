import Foundation

// MARK: - VersatilityDevelopmentEngine

/// Stateless engine responsible for developing player position versatility
/// and scheme familiarity over time. Works alongside PlayerDevelopmentEngine.
enum VersatilityDevelopmentEngine {

    // MARK: - Position Training

    /// Develop a player's alternate position familiarity.
    /// Returns the familiarity points gained this cycle.
    ///
    /// - Parameters:
    ///   - player: The player training at the new position.
    ///   - targetPosition: The alternate position being trained.
    ///   - positionCoach: The position coach for the target position group (if any).
    ///   - practiceIntensity: 0.5 during season, 1.0 during offseason.
    /// - Returns: Points gained (0+).
    static func trainPosition(
        player: Player,
        targetPosition: Position,
        positionCoach: Coach?,
        practiceIntensity: Double = 1.0
    ) -> Int {
        let rate = positionLearningRate(
            player: player,
            targetPosition: targetPosition,
            positionCoach: positionCoach,
            practiceIntensity: practiceIntensity
        )

        // Probabilistic rounding, not truncation-by-rounding — the same fix
        // `learnScheme` carries, for the same reason. `Int(rounded())` returns
        // 0 for every fractional gain below 0.5, and the in-season call runs at
        // `practiceIntensity` 0.3: a cross-training rate of 2.0 lands at 0.6
        // before the headroom taper, so a player two thirds of the way to his
        // ceiling banked NOTHING from an entire season of reps and the
        // conversion paths below could only ever advance in the offseason.
        // Rolling the fraction keeps the designed per-cycle expectation.
        return max(0, PlayerDevelopmentEngine.probabilisticPoints(rate))
    }

    /// The unrounded per-cycle learning rate behind `trainPosition`. Split out
    /// so the conversion UI can turn it into an honest week estimate instead of
    /// reverse-engineering the rounded integer.
    static func positionLearningRate(
        player: Player,
        targetPosition: Position,
        positionCoach: Coach?,
        practiceIntensity: Double = 1.0
    ) -> Double {
        // Base learning rate: 1-3 points per cycle
        var learningRate: Double = 2.0

        // Player coachability affects learning speed
        learningRate *= Double(player.mental.coachability) / 70.0

        // Coach teaching ability (playerDevelopment attribute)
        if let coach = positionCoach {
            learningRate *= Double(coach.playerDevelopment) / 60.0
        }

        // VersatilityEngine ceiling limits how far this player can go
        let ceiling = versatilityCeiling(player: player, at: targetPosition)
        let current = player.familiarity(at: targetPosition)

        // Diminishing returns as approaching ceiling
        let headroom = Double(ceiling - current) / Double(max(1, ceiling))
        learningRate *= max(0.1, headroom)

        // Practice intensity (season vs offseason)
        learningRate *= practiceIntensity

        // Age penalty (older players learn slower)
        if player.age > 30 { learningRate *= 0.7 }
        else if player.age > 28 { learningRate *= 0.85 }

        return max(0, learningRate)
    }

    /// The maximum familiarity a player can reach at a given position,
    /// based on their physical attributes and VersatilityEngine rating.
    static func versatilityCeiling(player: Player, at position: Position) -> Int {
        let rating = VersatilityEngine.rate(player: player, at: position)
        switch rating {
        case .natural:      return 100
        case .accomplished: return 85
        case .competent:    return 65
        case .unconvincing: return 40
        case .unqualified:  return 15
        }
    }

    // MARK: - Scheme Change Consequences (plan §2.9.2)

    /// Extra practice intensity during a scheme install year. The staff spends
    /// the whole season teaching a system nobody in the building has run, so
    /// the reps that DO happen teach more (`DEVELOPMENT_NFL_REFERENCE.md` §5:
    /// offenses under a new OC underperform in year 1 and recover in year 2 —
    /// the tax is the lost familiarity, this is the catch-up).
    static let schemeInstallIntensityBonus = 1.25

    /// Points a scheme nobody on the staff runs any more loses each offseason.
    static let unusedSchemeDecayPerOffseason = 4

    /// Floor the decay stops at. A player never forgets a system completely —
    /// he keeps a working knowledge of it, which is what makes a reunion with an
    /// old coordinator worth something.
    ///
    /// The number is `PlaySimulator`'s **blown-assignment pivot** (`famBustPivot`
    /// = 55), and that coupling is the whole point. Below that pivot every snap
    /// rolls a bust chance and the completion channel is docked; at or above it
    /// a squad is parity-neutral. A floor of 35 — 20 points UNDER the pivot —
    /// meant that a club which parked a system for four or five offseasons and
    /// then re-hired the coordinator who ran it found the room *in the busting
    /// regime*, which is the opposite of the reunion this floor exists to
    /// reward. `learnScheme` then needs the better part of a decade to climb
    /// back out (in-season gains are ~1 point/season by the time familiarity
    /// reaches the high 40s). Rusty, not broken.
    static let unusedSchemeFloor = 55

    /// Ages out the schemes this player's team no longer runs (plan §2.9.2).
    ///
    /// Without this, `schemeFamiliarity` was a monotone ratchet: a journeyman
    /// accumulated 90+ in every system he ever touched, so scheme fit stopped
    /// discriminating between clubs entirely. Only values ABOVE the floor
    /// decay — the floor is never used to lift a low number.
    ///
    /// - Parameters:
    ///   - player: The player whose dictionary is aged (mutated in place).
    ///   - activeSchemes: The `rawValue`s his current staff actually runs.
    static func decayUnusedSchemes(player: Player, activeSchemes: Set<String>) {
        var familiarity = player.schemeFamiliarity
        var changed = false
        for (scheme, value) in familiarity where !activeSchemes.contains(scheme) {
            let decayed = max(unusedSchemeFloor, value - unusedSchemeDecayPerOffseason)
            if decayed != value {
                familiarity[scheme] = decayed
                changed = true
            }
        }
        if changed { player.schemeFamiliarity = familiarity }
    }

    // MARK: - Scheme Learning

    /// Develop a player's scheme familiarity.
    /// Returns the familiarity points gained this cycle.
    ///
    /// - Parameters:
    ///   - player: The player learning the scheme.
    ///   - scheme: The scheme rawValue being learned (e.g., "WestCoast").
    ///   - coordinator: The coordinator teaching this scheme (if any).
    ///   - practiceIntensity: 0.5 during season, 1.0 during offseason.
    /// - Returns: Points gained (0+).
    static func learnScheme(
        player: Player,
        scheme: String,
        coordinator: Coach?,
        practiceIntensity: Double = 1.0
    ) -> Int {
        var learningRate: Double = 1.5

        // Player coachability
        learningRate *= Double(player.mental.coachability) / 70.0

        // Coach's expertise IN THIS SPECIFIC SCHEME drives teaching quality
        if let coord = coordinator {
            let expertise = Double(coord.expertise(for: scheme))
            learningRate *= expertise / 60.0

            // Coach's playerDevelopment = general teaching ability
            learningRate *= Double(coord.playerDevelopment) / 70.0
        }

        // Diminishing returns near 100
        let current = Double(player.schemeFam(for: scheme))
        let headroom = (100.0 - current) / 100.0
        learningRate *= max(0.1, headroom)

        // Practice intensity
        learningRate *= practiceIntensity

        // How fast the player absorbs a playbook. This used to read
        // `awareness / 70`, but awareness is the in-sim game-IQ every
        // PlaySimulator formula depends on — `learning` is now the canonical
        // "picks up the install" stat (plan §3.3), leaving awareness pure.
        // The divisor is chosen so the change is level-neutral: league-typical
        // awareness ~69.5 gave 0.993, league-typical learning ~69.5 gives 1.069
        // (+7.7 %, inside the ±10 % class-average guard).
        learningRate *= Double(player.learning) / 65.0

        // Probabilistic rounding, not truncation-by-rounding. `Int(rounded())`
        // silently returns 0 for every fractional gain below 0.5, and the
        // in-season call (`practiceIntensity` 0.5) drops under that threshold
        // once familiarity passes the high 40s — so a squad learning a new
        // playbook STALLED at ~47, below `PlaySimulator`'s bust pivot of 55,
        // and could only crawl out at +1 per offseason camp. Rolling the
        // fraction keeps the designed per-season expectation while letting the
        // in-season reps keep counting. Mirrors
        // `PlayerDevelopmentEngine.applyGameExperience`.
        return max(0, PlayerDevelopmentEngine.probabilisticPoints(learningRate))
    }

    // MARK: - Game Performance Impact

    /// Returns a 0.65-1.0 modifier for how well a player performs at a
    /// non-primary position during a game.
    ///
    /// - 100 familiarity = 1.0 (full performance)
    /// - 50 familiarity  = 0.825 (17.5% penalty)
    /// - 0 familiarity   = 0.65 (35% penalty)
    static func positionPerformanceModifier(player: Player, playingAt position: Position) -> Double {
        let familiarity = Double(player.familiarity(at: position))
        return 0.65 + (familiarity / 100.0) * 0.35
    }

    /// Returns a 0.70-1.0 modifier for how well a player performs in
    /// a specific scheme during a game.
    ///
    /// - 100 familiarity = 1.0
    /// - 50 familiarity  = 0.85
    /// - 0 familiarity   = 0.70
    static func schemePerformanceModifier(player: Player, scheme: String) -> Double {
        let familiarity = Double(player.schemeFam(for: scheme))
        return 0.70 + (familiarity / 100.0) * 0.30
    }

    /// SimPlayer overload used by the game-simulation hot path, where reading
    /// the SwiftData @Model per play is too slow.
    static func schemePerformanceModifier(player: SimPlayer, scheme: String) -> Double {
        let familiarity = Double(player.schemeFam(for: scheme))
        return 0.70 + (familiarity / 100.0) * 0.30
    }

    // MARK: - Position Conversion Paths (TODO §5.3)

    /// **Position-pair plausibility matrix.** Source position → the positions a
    /// player may be CONVERTED to, i.e. the moves a coaching staff would
    /// actually put on the board.
    ///
    /// This is deliberately narrower than "any pair `VersatilityEngine.rate`
    /// scores above Unqualified". `rate` also answers emergency questions — can
    /// this safety line up at corner for a series, can the quarterback take a
    /// jet sweep — and those pairs top out at Unconvincing, which is exactly
    /// what an emergency is. A CONVERSION is permanent: the man's job title
    /// changes, his attribute block is rebuilt against the new position, and he
    /// is graded there for the rest of his career. So the matrix only holds
    /// pairs `rate` can lift to **Competent or better** given the right body,
    /// and `conversionCeilingFloor` enforces that at the individual level too.
    ///
    /// | Group          | Moves                                               |
    /// |----------------|-----------------------------------------------------|
    /// | Offensive line | tackle ↔ guard, guard ↔ centre, LT ↔ RT, tackle → C |
    /// | Receivers      | WR ↔ TE (big slot bulks up / move TE splits out)    |
    /// | Backfield      | RB ↔ FB                                             |
    /// | Secondary      | FS ↔ SS, CB → either safety spot                    |
    /// | Linebackers    | OLB ↔ MLB                                           |
    /// | Front seven    | DE ↔ OLB (the 3-4/4-3 conversion)                   |
    ///
    /// Deliberately absent: DE ↔ DT (`rate` never gets past Unconvincing —
    /// interior weight is a body type, not a skill you teach), safety → CB
    /// (same reason, in reverse: you do not teach recovery speed), and QB → WR
    /// (a trick-play package, not a career).
    static let conversionMatrix: [Position: [Position]] = [
        .LT:  [.LG, .RT, .C],
        .RT:  [.RG, .LT, .C],
        .LG:  [.LT, .C, .RG],
        .RG:  [.RT, .C, .LG],
        .C:   [.LG, .RG],
        .WR:  [.TE],
        .TE:  [.WR],
        .RB:  [.FB],
        .FB:  [.RB],
        .FS:  [.SS],
        .SS:  [.FS],
        .CB:  [.FS, .SS],
        .OLB: [.MLB, .DE],
        .MLB: [.OLB],
        .DE:  [.OLB]
    ]

    /// A conversion needs a ceiling of at least Competent (65). A pair the
    /// matrix allows but this particular body cannot reach — a 68-strength
    /// guard who will never anchor at tackle — is refused here, which is why
    /// the matrix and the individual gate are two separate checks.
    static let conversionCeilingFloor = 65

    /// Concurrent conversions one club will run. The staff can only rebuild so
    /// many players at once, and the cap doubles as the AI's appetite limit.
    static let maxActiveConversions = 3

    /// Familiarity a player must bank at the target before the switch is made:
    /// **half the new job learned and the staff will move him.**
    ///
    /// One flat number rather than a share of his ceiling, and that is
    /// deliberate. `trainPosition` tapers hard as a player approaches his
    /// ceiling, so a threshold scaled off the ceiling would take a natural fit
    /// LONGER to reach than a projection — backwards. Against a flat 50, the
    /// man with the higher ceiling has more headroom the whole way and gets
    /// there first, which is what "natural fit" should mean. It sits safely
    /// under `conversionCeilingFloor`, so every pair the matrix allows is
    /// actually reachable.
    static let conversionCommitFamiliarity = 50

    /// Extra practice intensity a COMMITTED conversion buys, on top of the 0.3
    /// ambient cross-training `WeekAdvancer` already runs for anyone with a
    /// training position set.
    ///
    /// This is the difference between dabbling and a programme: a player the
    /// club has decided to move takes first-team reps at the new spot, so the
    /// two together come to a full-intensity week. Without it a conversion
    /// crawled — ambient reps alone need four or five seasons to bank 50
    /// points, which is a cross-training side effect, not a development path
    /// anybody would choose.
    static let conversionPracticeIntensity = 0.7

    /// The ambient in-season cross-training intensity `WeekAdvancer` runs for
    /// any player with a training position. Named here so the week estimate and
    /// the conversion reps agree with what actually happens.
    static let ambientCrossTrainingIntensity = 0.3

    /// The tax a conversion charges on the rebuilt attribute block — **the
    /// temporary rating dip**.
    ///
    /// A converted player does not arrive at his new position as the man he was
    /// at his old one: the technique is new, the leverage is new, the reads are
    /// new. So the block he carries across is scaled down, hard for a
    /// projection (Competent, ×0.90) and lightly for a natural fit
    /// (Accomplished, ×0.96). Because `Player.overall` weights the position
    /// block at 50 %, that reads as roughly −1 to −4 OVR on the day of the
    /// switch.
    ///
    /// It is *temporary* because nothing else about him changed: potential,
    /// work ethic and the development ceiling are untouched, and every
    /// development pass from here on works on the NEW block. A 23-year-old
    /// earns it back inside a season or two. A 30-year-old mostly does not —
    /// which is precisely why `conversionOffers` will not suggest one.
    static func conversionTax(rating: VersatilityRating) -> Double {
        rating >= .accomplished ? 0.96 : 0.90
    }

    // MARK: - Offers

    /// A conversion the staff is willing to put in front of the head coach.
    struct ConversionOffer: Identifiable {
        let playerID: UUID
        let playerName: String
        let from: Position
        let to: Position
        /// 5-96. How well the staff thinks the move projects.
        let fitPercent: Int
        /// What the switch does to his OVR the day it completes (usually negative).
        let overallDelta: Int
        /// Familiarity he has banked at the target right now.
        let familiarity: Int
        /// Familiarity he needs before the switch happens.
        let threshold: Int
        /// In-season weeks of cross-training to get there, `nil` when the reps
        /// are too thin to project (he needs an offseason).
        let weeksEstimate: Int?
        /// Why the staff raised it — depth chart on both sides of the move.
        let rationale: String

        var id: String { "\(playerID.uuidString)|\(to.rawValue)" }

        /// "Convert OLB Kade Rusk to DE — 78% fit"
        var headline: String {
            "Convert \(from.rawValue) \(playerName) to \(to.rawValue) — \(fitPercent)% fit"
        }
    }

    /// The conversions worth raising for one club, best fit first.
    ///
    /// A move has to clear three bars: the player is not playing where he is
    /// (buried outside the top two at his own position), the target is a spot
    /// the club could actually use him at, and the projection is good enough to
    /// be worth a rebuild. Anything that fails one of them never reaches the
    /// coach — an offer list nobody would ever accept is just noise.
    ///
    /// - Parameters:
    ///   - roster: the club's players.
    ///   - coaches: the staff, for the week estimate's position coach.
    ///   - limit: how many offers to return.
    static func conversionOffers(
        roster: [Player],
        coaches: [Coach],
        limit: Int = 4
    ) -> [ConversionOffer] {
        let available = roster.filter { !$0.isRetired }
        guard !available.isEmpty else { return [] }

        // Depth chart by position, best first — used on both sides of a move.
        var byPosition: [Position: [Player]] = [:]
        for player in available {
            byPosition[player.position, default: []].append(player)
        }
        byPosition = byPosition.mapValues { $0.sorted { $0.overall > $1.overall } }

        var offers: [ConversionOffer] = []
        for player in available {
            // Already rebuilding somebody else's position, hurt, or holding
            // out: not a conversation to start this week.
            guard activeConversion(for: player) == nil else { continue }
            guard !player.isInjured, !player.isHoldingOut else { continue }

            // A conversion is an investment. Past 29 there is no career left to
            // amortise the dip over.
            guard player.age <= 29 else { continue }

            // He has to be buried. The top two at a position are playing.
            let ownDepth = byPosition[player.position] ?? []
            let ownRank = (ownDepth.firstIndex { $0.id == player.id } ?? 0) + 1
            guard ownRank > 2 else { continue }

            for target in conversionMatrix[player.position] ?? [] {
                let rating = VersatilityEngine.rate(player: player, at: target)
                let ceiling = versatilityCeiling(player: player, at: target)
                guard ceiling >= conversionCeilingFloor else { continue }

                let projected = projectedOverall(player: player, at: target)

                // Would he beat anybody there? Somebody who lands fourth on the
                // new depth chart is just buried in a different room.
                let targetDepth = (byPosition[target] ?? []).filter { $0.id != player.id }
                let betterThere = targetDepth.filter { $0.overall >= projected }.count
                guard betterThere <= 1 else { continue }

                let fit = conversionFit(player: player, at: target, projectedOverall: projected)
                guard fit >= 45 else { continue }

                let positionCoach = coaches.first {
                    CoachingEngine.positionRoleMatch(coachRole: $0.role, playerPosition: target)
                }
                offers.append(ConversionOffer(
                    playerID: player.id,
                    playerName: player.fullName,
                    from: player.position,
                    to: target,
                    fitPercent: fit,
                    overallDelta: projected - player.overall,
                    familiarity: player.familiarity(at: target),
                    threshold: conversionCommitFamiliarity,
                    weeksEstimate: conversionWeeksEstimate(
                        player: player, target: target, positionCoach: positionCoach
                    ),
                    rationale: conversionRationale(
                        player: player,
                        ownRank: ownRank,
                        target: target,
                        betterThere: betterThere,
                        rating: rating
                    )
                ))
            }
        }

        return offers
            .sorted {
                $0.fitPercent != $1.fitPercent
                    ? $0.fitPercent > $1.fitPercent
                    : $0.overallDelta > $1.overallDelta
            }
            .reduce(into: [ConversionOffer]()) { kept, offer in
                // One offer per player — the best target, not three variations
                // on the same conversation.
                guard !kept.contains(where: { $0.playerID == offer.playerID }) else { return }
                guard kept.count < limit else { return }
                kept.append(offer)
            }
    }

    /// 5-96. Ceiling at the target sets the base; age, the between-the-ears
    /// attributes that decide whether a rebuild takes, and what the move does
    /// to his rating move it from there.
    static func conversionFit(player: Player, at target: Position, projectedOverall: Int) -> Int {
        let base = Double(versatilityCeiling(player: player, at: target))

        let age: Double
        switch player.age {
        case ...24: age = 1.10
        case 25...27: age = 1.00
        case 28...30: age = 0.88
        default: age = 0.72
        }

        // Coachability, learning speed and work ethic: the three that decide
        // whether a man rebuilds his technique or just resents being asked.
        let mind = Double(player.mental.coachability + player.learning + player.mental.workEthic) / 3.0
        let mindFactor = 0.85 + mind / 99.0 * 0.30

        // A move that makes him better is a better idea than one that does not.
        let delta = Double(projectedOverall - player.overall)
        let projection = min(1.15, max(0.75, 1.0 + delta / 40.0))

        return min(96, max(5, Int((base * age * mindFactor * projection).rounded())))
    }

    /// What his OVR reads the day the switch completes, dip included.
    static func projectedOverall(player: Player, at target: Position) -> Int {
        let rating = VersatilityEngine.rate(player: player, at: target)
        let converted = convertedAttributes(
            player: player, to: target, tax: conversionTax(rating: rating)
        )
        let positionAvg = converted.overall
        let physicalAvg = player.physical.average
        let mentalAvg = player.mental.average
        return Int((positionAvg * 0.5 + physicalAvg * 0.3 + mentalAvg * 0.2).rounded())
    }

    /// In-season weeks of cross-training left before the switch, or `nil` when
    /// the weekly reps are too thin to bank anything worth projecting (the
    /// answer there is "he needs an offseason", not "999 weeks").
    static func conversionWeeksEstimate(
        player: Player,
        target: Position,
        positionCoach: Coach?
    ) -> Int? {
        let remaining = conversionCommitFamiliarity - player.familiarity(at: target)
        guard remaining > 0 else { return 0 }
        // What a converting player actually banks in a week: the ambient
        // cross-training reps plus the conversion programme's own.
        let rate = positionLearningRate(
            player: player, targetPosition: target,
            positionCoach: positionCoach,
            practiceIntensity: ambientCrossTrainingIntensity + conversionPracticeIntensity
        )
        guard rate >= 0.05 else { return nil }
        return Int((Double(remaining) / rate).rounded(.up))
    }

    private static func conversionRationale(
        player: Player,
        ownRank: Int,
        target: Position,
        betterThere: Int,
        rating: VersatilityRating
    ) -> String {
        let buried = "\(ordinal(ownRank)) on the \(player.position.rawValue) depth chart"
        let room = betterThere == 0
            ? "nobody ahead of him at \(target.rawValue)"
            : "one man ahead of him at \(target.rawValue)"
        return "\(buried), \(room). Staff grades the body \(rating.label.lowercased()) there."
    }

    private static func ordinal(_ value: Int) -> String {
        switch value {
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        default: return "\(value)th"
        }
    }

    // MARK: - Running a Conversion

    /// A conversion in progress, reported for the UI.
    struct ConversionProgress {
        let target: Position
        let familiarity: Int
        let threshold: Int
        /// 0.0-1.0 toward the switch.
        let fraction: Double
    }

    /// The conversion this player is on, if any.
    ///
    /// Conversions ride `Player.trainingPosition` rather than a field of their
    /// own — that property already means "the alternate position this man is
    /// taking reps at", the weekly and offseason passes already feed it, and a
    /// second parallel field would have been two sources of truth for one
    /// thing. What makes it a *conversion* rather than cross-training is that
    /// the pair is in `conversionMatrix` and the ceiling clears
    /// `conversionCeilingFloor`; a player cross-training at an emergency
    /// position never trips the switch below.
    static func activeConversion(for player: Player) -> ConversionProgress? {
        guard let target = player.trainingPosition, target != player.position else { return nil }
        guard conversionMatrix[player.position]?.contains(target) == true else { return nil }
        guard versatilityCeiling(player: player, at: target) >= conversionCeilingFloor else {
            return nil
        }

        let familiarity = player.familiarity(at: target)
        return ConversionProgress(
            target: target,
            familiarity: familiarity,
            threshold: conversionCommitFamiliarity,
            fraction: min(1.0, Double(familiarity) / Double(conversionCommitFamiliarity))
        )
    }

    /// Puts a player on a conversion path. Refuses pairs outside the matrix and
    /// bodies that cannot reach Competent at the target.
    @discardableResult
    static func startConversion(player: Player, to target: Position) -> Bool {
        guard conversionMatrix[player.position]?.contains(target) == true else { return false }
        guard versatilityCeiling(player: player, at: target) >= conversionCeilingFloor else {
            return false
        }
        player.trainingPosition = target
        return true
    }

    /// Takes a player off a conversion path. The familiarity he banked stays —
    /// he really did learn it, and it is what makes him a usable backup there.
    static func cancelConversion(player: Player) {
        player.trainingPosition = nil
    }

    /// A completed switch, for the surfaces that want to announce it.
    struct CompletedConversion {
        let playerID: UUID
        let playerName: String
        let from: Position
        let to: Position
        let overallBefore: Int
        let overallAfter: Int

        var summary: String {
            "\(playerName) has made the move from \(from.rawValue) to \(to.rawValue) "
                + "(\(overallBefore) → \(overallAfter) OVR)."
        }
    }

    /// One week of every conversion running on this roster: bank the
    /// programme's reps, then switch anyone who has learned enough. Called from
    /// the weekly training tick, so it runs for the user's club and the other
    /// 31 alike.
    ///
    /// The reps here are ON TOP of the ambient cross-training `WeekAdvancer`
    /// already gives anyone with a training position set — see
    /// `conversionPracticeIntensity` for why a committed move has to move
    /// faster than dabbling.
    ///
    /// The switch also re-checks the depth chart, and does it more leniently
    /// than the offer did. `conversionOffers` will only RAISE a move for a man
    /// buried outside the top two; completing one only asks that he has not
    /// become the outright starter at his old spot in the meantime. The
    /// asymmetry is on purpose — a conversion the coach accepted should not be
    /// cancelled by one injury ahead of him, but taking a club's only starting
    /// left tackle and making him a centre is never the right call. A held
    /// conversion waits at full progress until the depth chart moves, or until
    /// the coach stops it.
    ///
    /// A conversion that banks its last points during the OFFSEASON (where
    /// `PlayerDevelopmentEngine` runs the same training) lands on the first
    /// weekly tick of the new season — which is when a position change gets
    /// announced anyway.
    @discardableResult
    static func tickConversions(roster: [Player], coaches: [Coach]) -> [CompletedConversion] {
        var depthRank: [UUID: Int] = [:]
        var byPosition: [Position: [Player]] = [:]
        for player in roster where !player.isRetired {
            byPosition[player.position, default: []].append(player)
        }
        for (_, group) in byPosition {
            for (index, player) in group.sorted(by: { $0.overall > $1.overall }).enumerated() {
                depthRank[player.id] = index + 1
            }
        }

        var completed: [CompletedConversion] = []
        for player in roster where !player.isRetired {
            guard let progress = activeConversion(for: player) else { continue }

            // The programme's own reps. Injured and holdout players are not in
            // the building, exactly like the focus tick below.
            if !player.isInjured && !player.isHoldingOut {
                let positionCoach = coaches.first {
                    CoachingEngine.positionRoleMatch(
                        coachRole: $0.role, playerPosition: progress.target
                    )
                }
                let gain = trainPosition(
                    player: player,
                    targetPosition: progress.target,
                    positionCoach: positionCoach,
                    practiceIntensity: conversionPracticeIntensity
                )
                if gain > 0 {
                    let key = progress.target.rawValue
                    let ceiling = versatilityCeiling(player: player, at: progress.target)
                    player.positionFamiliarity[key] = min(
                        ceiling, (player.positionFamiliarity[key] ?? 0) + gain
                    )
                }
            }

            guard player.familiarity(at: progress.target) >= conversionCommitFamiliarity else {
                continue
            }
            guard (depthRank[player.id] ?? 2) > 1 else { continue }
            completed.append(completeConversion(player: player, to: progress.target))
        }
        return completed
    }

    /// Performs the switch: rebuild the attribute block against the new
    /// position (with the dip), keep what he knew about the old one, and clear
    /// the training slot.
    @discardableResult
    static func completeConversion(player: Player, to target: Position) -> CompletedConversion {
        let from = player.position
        let overallBefore = player.overall
        let rating = VersatilityEngine.rate(player: player, at: target)

        let rebuilt = convertedAttributes(
            player: player, to: target, tax: conversionTax(rating: rating)
        )

        // What he knew at the old spot does not evaporate — he played there for
        // years, and that is exactly what makes a converted player the valuable
        // swing man he is. It is capped below 100 because he is no longer
        // taking those reps.
        player.positionFamiliarity[from.rawValue] = max(
            player.positionFamiliarity[from.rawValue] ?? 0, 85
        )

        player.position = target
        player.positionAttributes = rebuilt
        // Same convention `DraftEngine` and `LeagueGenerator` write: a man's
        // primary position reads 100.
        player.positionFamiliarity[target.rawValue] = 100
        player.trainingPosition = nil

        return CompletedConversion(
            playerID: player.id,
            playerName: player.fullName,
            from: from,
            to: target,
            overallBefore: overallBefore,
            overallAfter: player.overall
        )
    }

    // MARK: - Attribute Transfer

    /// Which attribute block a position is graded on.
    private enum AttributeFamily {
        case qb, wr, rb, te, ol, dl, lb, db, kick
    }

    private static func attributeFamily(of position: Position) -> AttributeFamily {
        switch position {
        case .QB:                       return .qb
        case .WR:                       return .wr
        case .RB, .FB:                  return .rb
        case .TE:                       return .te
        case .LT, .LG, .C, .RG, .RT:    return .ol
        case .DE, .DT:                  return .dl
        case .OLB, .MLB:                return .lb
        case .CB, .FS, .SS:             return .db
        case .K, .P:                    return .kick
        }
    }

    /// Rebuilds a player's position block for a new position.
    ///
    /// Most of the matrix stays inside one attribute family — every offensive
    /// line move, RB ↔ FB, the whole secondary, OLB ↔ MLB — and there the block
    /// carries across as it stands, because it is literally the same set of
    /// skills being graded. Only two pairs cross families, and each gets an
    /// explicit map rather than an average, so the man who moves keeps being
    /// recognisably himself:
    ///
    /// - **WR ↔ TE** — hands and route running are the same craft; a receiver's
    ///   blocking is seeded off his strength, and a tight end's release is his
    ///   hand usage at the line.
    /// - **DE ↔ OLB** — the 3-4/4-3 conversion. Rushing the passer is rushing
    ///   the passer (blitzing ↔ pass rush) and shedding a block is making the
    ///   tackle; what a converted end has to learn from scratch is coverage,
    ///   which is why it is seeded off awareness and agility rather than
    ///   carried.
    ///
    /// `tax` is the conversion dip (see `conversionTax`), applied to every
    /// field of the result.
    static func convertedAttributes(
        player: Player,
        to target: Position,
        tax: Double
    ) -> PositionAttributes {
        let physical = player.physical
        let mental = player.mental

        func t(_ value: Int) -> Int {
            max(1, min(99, Int((Double(value) * tax).rounded())))
        }

        // Same family: the grading sheet does not change.
        if attributeFamily(of: player.position) == attributeFamily(of: target) {
            switch player.positionAttributes {
            case .quarterback(let a):
                return .quarterback(QBAttributes(
                    armStrength: t(a.armStrength), accuracyShort: t(a.accuracyShort),
                    accuracyMid: t(a.accuracyMid), accuracyDeep: t(a.accuracyDeep),
                    pocketPresence: t(a.pocketPresence), scrambling: t(a.scrambling)
                ))
            case .wideReceiver(let a):
                return .wideReceiver(WRAttributes(
                    routeRunning: t(a.routeRunning), catching: t(a.catching),
                    release: t(a.release), spectacularCatch: t(a.spectacularCatch)
                ))
            case .runningBack(let a):
                return .runningBack(RBAttributes(
                    vision: t(a.vision), elusiveness: t(a.elusiveness),
                    breakTackle: t(a.breakTackle), receiving: t(a.receiving)
                ))
            case .tightEnd(let a):
                return .tightEnd(TEAttributes(
                    blocking: t(a.blocking), catching: t(a.catching),
                    routeRunning: t(a.routeRunning), speed: t(a.speed)
                ))
            case .offensiveLine(let a):
                return .offensiveLine(OLAttributes(
                    runBlock: t(a.runBlock), passBlock: t(a.passBlock),
                    pull: t(a.pull), anchor: t(a.anchor)
                ))
            case .defensiveLine(let a):
                return .defensiveLine(DLAttributes(
                    passRush: t(a.passRush), blockShedding: t(a.blockShedding),
                    powerMoves: t(a.powerMoves), finesseMoves: t(a.finesseMoves)
                ))
            case .linebacker(let a):
                return .linebacker(LBAttributes(
                    tackling: t(a.tackling), zoneCoverage: t(a.zoneCoverage),
                    manCoverage: t(a.manCoverage), blitzing: t(a.blitzing)
                ))
            case .defensiveBack(let a):
                return .defensiveBack(DBAttributes(
                    manCoverage: t(a.manCoverage), zoneCoverage: t(a.zoneCoverage),
                    press: t(a.press), ballSkills: t(a.ballSkills)
                ))
            case .kicking(let a):
                return .kicking(KickingAttributes(
                    kickPower: t(a.kickPower), kickAccuracy: t(a.kickAccuracy)
                ))
            }
        }

        // Cross-family: the two explicit maps.
        switch (player.positionAttributes, attributeFamily(of: target)) {
        case (.wideReceiver(let a), .te):
            return .tightEnd(TEAttributes(
                blocking: t(max(35, physical.strength - 12)),
                catching: t(a.catching),
                routeRunning: t(a.routeRunning),
                speed: t(physical.speed)
            ))

        case (.tightEnd(let a), .wr):
            return .wideReceiver(WRAttributes(
                routeRunning: t(a.routeRunning),
                catching: t(a.catching),
                release: t(a.blocking),
                spectacularCatch: t((a.catching + physical.agility) / 2)
            ))

        case (.linebacker(let a), .dl):
            return .defensiveLine(DLAttributes(
                passRush: t(a.blitzing),
                blockShedding: t(a.tackling),
                powerMoves: t((physical.strength + a.tackling) / 2),
                finesseMoves: t((physical.agility + a.blitzing) / 2)
            ))

        case (.defensiveLine(let a), .lb):
            return .linebacker(LBAttributes(
                tackling: t(a.blockShedding),
                zoneCoverage: t(max(30, mental.awareness - 18)),
                manCoverage: t(max(25, physical.agility - 22)),
                blitzing: t(a.passRush)
            ))

        default:
            // Unreachable through `conversionMatrix`, but this function has to
            // be total: seed the new block flat off the old one's grade.
            let flat = t(Int(player.positionAttributes.overall.rounded()))
            return TemplateAttributeSolver.makePositionAttributes(
                target, Array(repeating: flat, count: 6)
            )
        }
    }

    // MARK: - AI Conversions

    /// Per-week chance an AI club opens a conversion, checked once per club.
    /// Over an 18-week season that is roughly one conversion started every
    /// three seasons per club — visible across a league, rare for any one team.
    static let aiConversionWeeklyChance = 0.02

    /// AI counterpart of the user accepting an offer. Occasionally puts the
    /// club's best-graded conversion candidate on a path, respecting the same
    /// concurrency cap the user's club has.
    ///
    /// - Returns: the conversion that was started, if any.
    @discardableResult
    static func aiConsiderConversion(roster: [Player], coaches: [Coach]) -> ConversionOffer? {
        guard Double.random(in: 0.0..<1.0) < aiConversionWeeklyChance else { return nil }

        let active = roster.filter { activeConversion(for: $0) != nil }.count
        guard active < maxActiveConversions else { return nil }

        // AI clubs are pickier than the offer list: they only take moves the
        // staff is genuinely sold on.
        guard let offer = conversionOffers(roster: roster, coaches: coaches, limit: 3)
            .first(where: { $0.fitPercent >= 70 }) else { return nil }
        guard let player = roster.first(where: { $0.id == offer.playerID }) else { return nil }
        guard startConversion(player: player, to: offer.to) else { return nil }
        return offer
    }
}
