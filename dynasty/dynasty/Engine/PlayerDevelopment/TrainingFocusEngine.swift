import Foundation

// MARK: - Training Focus Area (R26)

/// A weekly per-player training emphasis. Each area maps to a small set of
/// attributes relevant to the player's position; the weekly focus tick can
/// bump one of them by +1 (capped by the player's potential ceiling).
enum TrainingFocusArea: String, Codable, CaseIterable, Identifiable {
    case accuracy        = "Accuracy"
    case armTalent       = "Arm Talent"
    case pocketWork      = "Pocket Work"
    case ballCarrying    = "Ball Carrying"
    case receiving       = "Receiving"
    case routeRunning    = "Route Running"
    case hands           = "Hands"
    case runBlocking     = "Run Blocking"
    case passProtection  = "Pass Protection"
    case passRush        = "Pass Rush"
    case runDefense      = "Run Defense"
    case coverage        = "Coverage"
    case ballSkills      = "Ball Skills"
    case tackling        = "Tackling"
    case kickingCraft    = "Kicking Craft"
    case conditioning    = "Conditioning"
    case filmStudy       = "Film Study"

    var id: String { rawValue }

    var displayName: String { rawValue }

    /// SF Symbol used in focus chips and report rows.
    var icon: String {
        switch self {
        case .accuracy, .armTalent, .pocketWork:      return "target"
        case .ballCarrying, .receiving:               return "figure.run"
        case .routeRunning, .hands:                   return "point.topleft.down.curvedto.point.bottomright.up"
        case .runBlocking, .passProtection:           return "shield.lefthalf.filled"
        case .passRush, .runDefense, .tackling:       return "bolt.fill"
        case .coverage, .ballSkills:                  return "eye.fill"
        case .kickingCraft:                           return "figure.kickboxing"
        case .conditioning:                           return "figure.strengthtraining.traditional"
        case .filmStudy:                              return "play.rectangle.fill"
        }
    }

    /// The focus areas that make sense for a given position.
    /// Every position also gets the universal Conditioning / Film Study drills.
    static func areas(for position: Position) -> [TrainingFocusArea] {
        let specific: [TrainingFocusArea]
        switch position {
        case .QB:                       specific = [.accuracy, .armTalent, .pocketWork]
        case .RB, .FB:                  specific = [.ballCarrying, .receiving]
        case .WR:                       specific = [.routeRunning, .hands]
        case .TE:                       specific = [.routeRunning, .hands, .runBlocking]
        case .LT, .LG, .C, .RG, .RT:    specific = [.passProtection, .runBlocking]
        case .DE, .DT:                  specific = [.passRush, .runDefense]
        case .OLB, .MLB:                specific = [.tackling, .coverage, .passRush]
        case .CB, .FS, .SS:             specific = [.coverage, .ballSkills]
        case .K, .P:                    specific = [.kickingCraft]
        }
        return specific + [.conditioning, .filmStudy]
    }

    /// Default auto-pick (used by AI teams): the first position-specific area.
    static func defaultArea(for position: Position) -> TrainingFocusArea {
        areas(for: position).first ?? .filmStudy
    }
}

// MARK: - TrainingFocusEngine (R26)

/// Weekly micro-development driven by per-player training focus.
///
/// Rules:
/// - Up to 3 players per team hold a focus slot (user picks; AI auto-picks
///   its best young players so the user gains no free edge).
/// - Each week a focused player rolls one chance at +1 to a random attribute
///   inside the focus area, capped by the same potential ceiling the
///   offseason development engine uses (`truePotential * 0.65 + 35`).
/// - The gain chance scales DOWN with age (pre-peak > peak > post-peak) and
///   up/down with work ethic, position-coach quality, and morale — so
///   focusing youngsters is clearly the best use of the slots.
/// - This layer is additive micro-development; it does not touch the
///   existing offseason `PlayerDevelopmentEngine` pipeline.
enum TrainingFocusEngine {

    // MARK: - Tuning

    /// Maximum simultaneous focus players per team.
    static let maxFocusPlayersPerTeam = 3

    /// Hard cap of breakout events per team per season.
    static let maxBreakoutsPerSeason = 2

    /// Weekly league-wide roll for one breakout candidate per team
    /// (~1 expected breakout per team per season, capped at 2).
    private static let weeklyBreakoutChance = 0.06

    /// Breakouts consumed per "season|team" key. In-memory only — an app
    /// restart resets the cap, which errs on the side of more fun.
    private static var breakoutCounts: [String: Int] = [:]

    // MARK: - Result Type

    /// One concrete attribute gain produced by the weekly focus tick.
    struct FocusGain {
        let playerID: UUID
        let playerName: String
        let position: Position
        let area: TrainingFocusArea
        let attributeName: String
        let points: Int
        /// True when high morale (≥ 80) boosted this week's roll.
        let moraleBoosted: Bool
    }

    // MARK: - Weekly Tick

    /// Runs the weekly focus roll for a single team's roster.
    /// Injured and holdout players never gain; the 3-slot cap is enforced
    /// here too in case stale focus flags linger after trades/cuts.
    static func applyWeeklyFocusTick(roster: [Player], coaches: [Coach]) -> [FocusGain] {
        var gains: [FocusGain] = []

        let focused = roster
            .filter { $0.trainingFocusArea != nil && !$0.isInjured && !$0.isHoldingOut }
            .sorted { $0.age < $1.age }
            .prefix(maxFocusPlayersPerTeam)

        for player in focused {
            guard let area = player.trainingFocusArea else { continue }
            let chance = weeklyGainChance(player: player, coaches: coaches)
            guard Double.random(in: 0.0..<1.0) < chance else { continue }

            let ceiling = potentialCeiling(for: player)
            if let attributeName = applyFocusPoint(player: player, area: area, ceiling: ceiling) {
                gains.append(FocusGain(
                    playerID: player.id,
                    playerName: player.fullName,
                    position: player.position,
                    area: area,
                    attributeName: attributeName,
                    points: 1,
                    moraleBoosted: player.morale >= 80
                ))
            }
        }
        return gains
    }

    /// Probability (0-0.6) that a focused player converts this week's extra
    /// reps into a +1 attribute point. Age is the dominant factor.
    static func weeklyGainChance(player: Player, coaches: [Coach]) -> Double {
        let peak = player.position.peakAgeRange
        let base: Double
        if player.age < peak.lowerBound {
            base = 0.32          // pre-peak: focus reps convert well
        } else if player.age <= peak.upperBound {
            base = 0.18          // at peak: maintenance-plus
        } else {
            base = 0.06          // post-peak: rare, mostly wasted slot
        }

        // Work ethic 1-99 → 0.75-1.25
        let workEthicFactor = 0.75 + Double(player.mental.workEthic) / 99.0 * 0.5

        // Position coach (coordinator fallback) sharpens the drills: ±15 %.
        let coach = coaches.first {
            CoachingEngine.positionRoleMatch(coachRole: $0.role, playerPosition: player.position)
        } ?? coaches.first {
            ($0.role == .offensiveCoordinator && player.position.side == .offense) ||
            ($0.role == .defensiveCoordinator && player.position.side == .defense)
        }
        let coachDev = Double(coach?.playerDevelopment ?? 50)
        let coachFactor = 1.0 + (coachDev - 50.0) / 99.0 * 0.3

        var chance = base * workEthicFactor * coachFactor

        // R18/R25 tie-in: locker-room mood moves the needle a little.
        if player.morale >= 80 {
            chance *= 1.15
        } else if player.morale <= 35 {
            chance *= 0.7
        }
        return min(0.6, chance)
    }

    // MARK: - AI Auto-Focus

    /// AI counterpart of the user's manual selection: keeps up to 3 focus
    /// slots filled with the team's best young players (highest potential,
    /// then youngest). Recycles slots held by players past their peak.
    static func autoAssignFocus(roster: [Player]) {
        // Free slots wasted on post-peak players.
        for player in roster where player.trainingFocusArea != nil
            && player.age > player.position.peakAgeRange.upperBound {
            player.trainingFocusAreaRaw = nil
        }

        var focused = roster.filter { $0.trainingFocusArea != nil }

        // Trim overflow (e.g. an already-focused player arrived via trade).
        if focused.count > maxFocusPlayersPerTeam {
            let keep = focused
                .sorted { $0.truePotential > $1.truePotential }
                .prefix(maxFocusPlayersPerTeam)
            let keepIDs = Set(keep.map(\.id))
            for player in focused where !keepIDs.contains(player.id) {
                player.trainingFocusAreaRaw = nil
            }
            focused = Array(keep)
        }

        guard focused.count < maxFocusPlayersPerTeam else { return }

        let candidates = roster
            .filter {
                $0.trainingFocusArea == nil
                && !$0.isInjured && !$0.isHoldingOut
                && $0.yearsPro <= 3
                && $0.age < $0.position.peakAgeRange.upperBound
            }
            .sorted {
                if $0.truePotential != $1.truePotential {
                    return $0.truePotential > $1.truePotential
                }
                return $0.age < $1.age
            }

        for player in candidates.prefix(maxFocusPlayersPerTeam - focused.count) {
            player.trainingFocusAreaRaw = TrainingFocusArea.defaultArea(for: player.position).rawValue
        }
    }

    // MARK: - Breakout Events

    /// Rare, newsworthy leap for a high-potential youngster: a one-time
    /// 4-6 point jump inside his position skill set (plus +1 awareness).
    /// Hard-capped at `maxBreakoutsPerSeason` per team per season.
    static func rollBreakout(
        roster: [Player],
        season: Int,
        teamID: UUID
    ) -> (player: Player, pointsGained: Int)? {
        let key = "\(season)|\(teamID.uuidString)"
        guard breakoutCounts[key, default: 0] < maxBreakoutsPerSeason else { return nil }
        guard Double.random(in: 0.0..<1.0) < weeklyBreakoutChance else { return nil }

        let candidates = roster.filter {
            $0.yearsPro <= 3 && $0.age <= 25
            && $0.truePotential >= 82
            && $0.morale >= 60
            && !$0.isInjured && !$0.isHoldingOut
        }
        guard let star = candidates.randomElement() else { return nil }

        let ceiling = potentialCeiling(for: star)
        let attempts = Int.random(in: 4...6)
        var applied = 0
        let areaPool = TrainingFocusArea.areas(for: star.position).dropLast(2) // position-specific only
        for _ in 0..<attempts {
            let area = star.trainingFocusArea ?? areaPool.randomElement() ?? .filmStudy
            if applyFocusPoint(player: star, area: area, ceiling: ceiling) != nil {
                applied += 1
            }
        }
        // The game slows down for him — small awareness bump on top.
        if star.mental.awareness < min(99, ceiling) {
            star.mental.awareness += 1
            applied += 1
        }
        guard applied > 0 else { return nil }

        breakoutCounts[key, default: 0] += 1
        return (star, applied)
    }

    // MARK: - Attribute Application

    /// Same ceiling formula as `PlayerDevelopmentEngine`.
    static func potentialCeiling(for player: Player) -> Int {
        Int(Double(player.truePotential) * 0.65 + 35.0)
    }

    /// Applies a single +1 point inside the given focus area, respecting the
    /// potential ceiling. Returns the display name of the bumped attribute,
    /// or nil when every attribute in the area is already capped (or the
    /// area doesn't match the player's position kind).
    @discardableResult
    static func applyFocusPoint(player: Player, area: TrainingFocusArea, ceiling: Int) -> String? {
        let cap = min(99, ceiling)

        // Universal drills first — they work for every position.
        switch area {
        case .conditioning:
            var physical = player.physical
            let options: [(String, WritableKeyPath<PhysicalAttributes, Int>)] = [
                ("Speed", \.speed), ("Acceleration", \.acceleration),
                ("Agility", \.agility), ("Stamina", \.stamina)
            ]
            guard let name = bump(&physical, options, cap: cap) else { return nil }
            player.physical = physical
            return name
        case .filmStudy:
            var mental = player.mental
            let options: [(String, WritableKeyPath<MentalAttributes, Int>)] = [
                ("Awareness", \.awareness), ("Decision Making", \.decisionMaking)
            ]
            guard let name = bump(&mental, options, cap: cap) else { return nil }
            player.mental = mental
            return name
        default:
            break
        }

        // Position-specific drills.
        switch player.positionAttributes {
        case .quarterback(var qb):
            let options: [(String, WritableKeyPath<QBAttributes, Int>)]
            switch area {
            case .accuracy:
                options = [("Short Accuracy", \.accuracyShort),
                           ("Mid Accuracy", \.accuracyMid),
                           ("Deep Accuracy", \.accuracyDeep)]
            case .armTalent:
                options = [("Arm Strength", \.armStrength)]
            case .pocketWork:
                options = [("Pocket Presence", \.pocketPresence), ("Scrambling", \.scrambling)]
            default: return nil
            }
            guard let name = bump(&qb, options, cap: cap) else { return nil }
            player.positionAttributes = .quarterback(qb)
            return name

        case .runningBack(var rb):
            let options: [(String, WritableKeyPath<RBAttributes, Int>)]
            switch area {
            case .ballCarrying:
                options = [("Vision", \.vision), ("Elusiveness", \.elusiveness),
                           ("Break Tackle", \.breakTackle)]
            case .receiving:
                options = [("Receiving", \.receiving)]
            default: return nil
            }
            guard let name = bump(&rb, options, cap: cap) else { return nil }
            player.positionAttributes = .runningBack(rb)
            return name

        case .wideReceiver(var wr):
            let options: [(String, WritableKeyPath<WRAttributes, Int>)]
            switch area {
            case .routeRunning:
                options = [("Route Running", \.routeRunning), ("Release", \.release)]
            case .hands:
                options = [("Catching", \.catching), ("Spectacular Catch", \.spectacularCatch)]
            default: return nil
            }
            guard let name = bump(&wr, options, cap: cap) else { return nil }
            player.positionAttributes = .wideReceiver(wr)
            return name

        case .tightEnd(var te):
            let options: [(String, WritableKeyPath<TEAttributes, Int>)]
            switch area {
            case .routeRunning:
                options = [("Route Running", \.routeRunning)]
            case .hands:
                options = [("Catching", \.catching)]
            case .runBlocking:
                options = [("Blocking", \.blocking)]
            default: return nil
            }
            guard let name = bump(&te, options, cap: cap) else { return nil }
            player.positionAttributes = .tightEnd(te)
            return name

        case .offensiveLine(var ol):
            let options: [(String, WritableKeyPath<OLAttributes, Int>)]
            switch area {
            case .passProtection:
                options = [("Pass Block", \.passBlock), ("Anchor", \.anchor)]
            case .runBlocking:
                options = [("Run Block", \.runBlock), ("Pull", \.pull)]
            default: return nil
            }
            guard let name = bump(&ol, options, cap: cap) else { return nil }
            player.positionAttributes = .offensiveLine(ol)
            return name

        case .defensiveLine(var dl):
            let options: [(String, WritableKeyPath<DLAttributes, Int>)]
            switch area {
            case .passRush:
                options = [("Pass Rush", \.passRush), ("Finesse Moves", \.finesseMoves)]
            case .runDefense:
                options = [("Block Shedding", \.blockShedding), ("Power Moves", \.powerMoves)]
            default: return nil
            }
            guard let name = bump(&dl, options, cap: cap) else { return nil }
            player.positionAttributes = .defensiveLine(dl)
            return name

        case .linebacker(var lb):
            let options: [(String, WritableKeyPath<LBAttributes, Int>)]
            switch area {
            case .tackling:
                options = [("Tackling", \.tackling)]
            case .coverage:
                options = [("Zone Coverage", \.zoneCoverage), ("Man Coverage", \.manCoverage)]
            case .passRush:
                options = [("Blitzing", \.blitzing)]
            default: return nil
            }
            guard let name = bump(&lb, options, cap: cap) else { return nil }
            player.positionAttributes = .linebacker(lb)
            return name

        case .defensiveBack(var db):
            let options: [(String, WritableKeyPath<DBAttributes, Int>)]
            switch area {
            case .coverage:
                options = [("Man Coverage", \.manCoverage),
                           ("Zone Coverage", \.zoneCoverage),
                           ("Press", \.press)]
            case .ballSkills:
                options = [("Ball Skills", \.ballSkills)]
            default: return nil
            }
            guard let name = bump(&db, options, cap: cap) else { return nil }
            player.positionAttributes = .defensiveBack(db)
            return name

        case .kicking(var k):
            guard area == .kickingCraft else { return nil }
            let options: [(String, WritableKeyPath<KickingAttributes, Int>)] = [
                ("Kick Power", \.kickPower), ("Kick Accuracy", \.kickAccuracy)
            ]
            guard let name = bump(&k, options, cap: cap) else { return nil }
            player.positionAttributes = .kicking(k)
            return name
        }
    }

    /// Bumps one random viable attribute (+1) inside a struct. Returns the
    /// display name of the attribute, or nil when all options are capped.
    private static func bump<T>(
        _ attrs: inout T,
        _ options: [(String, WritableKeyPath<T, Int>)],
        cap: Int
    ) -> String? {
        let viable = options.filter { attrs[keyPath: $0.1] < cap }
        guard let choice = viable.randomElement() else { return nil }
        attrs[keyPath: choice.1] += 1
        return choice.0
    }
}

// MARK: - DevelopmentReportBuilder (R26)

/// Assembles the user-facing weekly Development Report from the focus tick
/// results, the R25 mentorship pairs, and roster status (holdouts, injuries,
/// morale, age curve).
enum DevelopmentReportBuilder {

    /// Builds the weekly report for the user's roster.
    static func buildWeeklyReport(
        roster: [Player],
        focusGains: [TrainingFocusEngine.FocusGain],
        breakout: (player: Player, pointsGained: Int)?,
        week: Int,
        season: Int
    ) -> DevelopmentReport {
        var report = DevelopmentReport(season: season, week: week)

        // --- Risers: concrete focus gains ---
        for gain in focusGains {
            var detail = "+\(gain.points) \(gain.attributeName)"
            if gain.moraleBoosted { detail += " — riding high morale" }
            report.risers.append(DevelopmentReport.Entry(
                playerID: gain.playerID,
                playerName: gain.playerName,
                positionRaw: gain.position.rawValue,
                detail: detail,
                reasonRaw: DevelopmentReport.Reason.focus.rawValue
            ))
        }

        // --- Breakout ---
        if let breakout {
            report.breakouts.append(DevelopmentReport.Entry(
                playerID: breakout.player.id,
                playerName: breakout.player.fullName,
                positionRaw: breakout.player.position.rawValue,
                detail: "+\(breakout.pointsGained) attribute points — breakout leap",
                reasonRaw: DevelopmentReport.Reason.breakout.rawValue
            ))
        }

        // --- Mentorships (R25): protégés develop +10 % faster ---
        for pairing in LockerRoomEngine.activeMentorships(players: roster) {
            report.mentorships.append(DevelopmentReport.MentorLine(
                mentorName: pairing.mentor.fullName,
                protegeName: pairing.protege.fullName,
                positionRaw: pairing.protege.position.rawValue,
                boostText: "+10% development speed"
            ))
        }

        // --- Stalled / falling ---
        for player in roster where player.isHoldingOut {
            report.stalled.append(DevelopmentReport.Entry(
                playerID: player.id,
                playerName: player.fullName,
                positionRaw: player.position.rawValue,
                detail: "Holding out — development paused",
                reasonRaw: DevelopmentReport.Reason.holdout.rawValue
            ))
        }
        for player in roster where player.isInjured {
            report.stalled.append(DevelopmentReport.Entry(
                playerID: player.id,
                playerName: player.fullName,
                positionRaw: player.position.rawValue,
                detail: "Injured (\(max(1, player.injuryWeeksRemaining)) wk left) — development paused",
                reasonRaw: DevelopmentReport.Reason.injury.rawValue
            ))
        }
        for player in roster where !player.isInjured && !player.isHoldingOut
            && player.morale <= 35
            && player.age <= player.position.peakAgeRange.upperBound {
            report.stalled.append(DevelopmentReport.Entry(
                playerID: player.id,
                playerName: player.fullName,
                positionRaw: player.position.rawValue,
                detail: "Low morale is dragging his development",
                reasonRaw: DevelopmentReport.Reason.morale.rawValue
            ))
        }
        // A focus slot spent on a post-peak veteran is flagged so the user
        // understands why the gains never come.
        for player in roster where player.trainingFocusArea != nil
            && player.age > player.position.peakAgeRange.upperBound {
            report.stalled.append(DevelopmentReport.Entry(
                playerID: player.id,
                playerName: player.fullName,
                positionRaw: player.position.rawValue,
                detail: "Past his physical peak — focus gains are rare",
                reasonRaw: DevelopmentReport.Reason.ageCurve.rawValue
            ))
        }

        return report
    }

    /// Weekly inbox digest linking to the Development Report screen.
    static func inboxMessage(report: DevelopmentReport, focusedCount: Int) -> InboxMessage {
        var lines: [String] = []

        if !report.risers.isEmpty {
            let names = report.risers.prefix(3)
                .map { "\($0.playerName) (\($0.detail))" }
                .joined(separator: ", ")
            lines.append("Trending up: \(names).")
        }
        if let breakoutEntry = report.breakouts.first {
            lines.append("BREAKOUT: \(breakoutEntry.playerName) took a massive developmental leap this week — the game has slowed down for him.")
        }
        if !report.mentorships.isEmpty {
            let pairs = report.mentorships.prefix(2)
                .map { "\($0.mentorName) → \($0.protegeName)" }
                .joined(separator: ", ")
            lines.append("Mentorships paying off (\(pairs)): protégés develop +10% faster.")
        }
        if !report.stalled.isEmpty {
            lines.append("\(report.stalled.count) player\(report.stalled.count == 1 ? " is" : "s are") developing slowly or not at all — details in the full report.")
        }
        if focusedCount == 0 {
            lines.append("Reminder: no training-focus players are set. Assign up to \(TrainingFocusEngine.maxFocusPlayersPerTeam) in the Development hub — young players benefit the most.")
        }

        return InboxMessage(
            sender: .developmentStaff,
            subject: "Development Report — Week \(report.week)",
            body: lines.joined(separator: "\n\n"),
            date: "Week \(report.week), Season \(report.season)",
            category: .rosterAnalysis,
            attachments: [
                MessageAttachment(title: "Development Report", destination: .developmentReport)
            ]
        )
    }
}
