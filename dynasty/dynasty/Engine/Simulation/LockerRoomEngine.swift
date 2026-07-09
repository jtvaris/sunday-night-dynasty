import Foundation

// MARK: - Locker Room State

struct LockerRoomState: Codable {
    /// Overall team chemistry rating from 0 to 100.
    var teamChemistry: Int
    /// Sum of positive leader contributions to chemistry.
    var leadershipScore: Int
    /// Sum of negative toxic contributions dragging chemistry down.
    var toxicityScore: Int
    /// Human-readable log of recent events that affected chemistry.
    var recentEvents: [String]
}

// MARK: - Locker Room Engine

enum LockerRoomEngine {

    // MARK: - Calculate Chemistry

    /// Evaluates the full team chemistry based on player personalities, motivations,
    /// and how well players complement each other in the locker room.
    static func calculateChemistry(players: [Player]) -> LockerRoomState {
        var leadershipScore = 0
        var toxicityScore = 0
        var events: [String] = []

        for player in players {
            let archetype = player.personality.archetype

            switch archetype {
            case .teamLeader:
                // High-morale leaders give a strong chemistry boost
                let contribution = player.morale >= 70 ? 8 : 4
                leadershipScore += contribution
                if contribution >= 8 {
                    events.append("\(player.fullName) is leading the team with great energy.")
                }

            case .mentor:
                // Mentors uplift younger players; solid chemistry contributors
                let contribution = player.morale >= 60 ? 6 : 3
                leadershipScore += contribution
                if contribution >= 6 {
                    events.append("\(player.fullName) is mentoring teammates and building trust.")
                }

            case .dramaQueen:
                // Drama Queens create friction, especially when unhappy
                let penalty = player.morale < 50 ? 8 : 4
                toxicityScore += penalty
                if penalty >= 8 {
                    events.append("\(player.fullName) is stirring up drama in the locker room.")
                }

            case .fieryCompetitor:
                // Can be volatile — hurts chemistry when morale drops
                let penalty = player.morale < 45 ? 5 : 2
                toxicityScore += penalty
                if penalty >= 5 {
                    events.append("\(player.fullName)'s intensity is creating locker room tension.")
                }

            case .loneWolf:
                // Lone Wolves neither help nor hurt; they stay in their lane
                break

            case .feelPlayer:
                // Feel Players amplify the current mood — good when happy, bad when not
                if player.morale >= 75 {
                    leadershipScore += 3
                    events.append("\(player.fullName)'s high energy is lifting the room.")
                } else if player.morale < 45 {
                    toxicityScore += 3
                    events.append("\(player.fullName)'s low mood is bringing others down.")
                }

            case .steadyPerformer, .quietProfessional:
                // Stable presences that provide a small passive boost
                leadershipScore += 1

            case .classClown:
                // Keeps spirits up but can be a mild distraction
                leadershipScore += 2
                if player.morale < 40 {
                    toxicityScore += 2
                }
            }
        }

        // Motivation alignment: players with matching motivations bond better
        let motivationGroups = Dictionary(grouping: players, by: { $0.personality.motivation })
        for (motivation, group) in motivationGroups where group.count >= 3 {
            leadershipScore += 2
            events.append("Several \(motivation.rawValue.lowercased())-motivated players are bonding well.")
        }

        // Raw chemistry: base 50, add leadership, subtract toxicity
        let rawChemistry = 50 + leadershipScore - toxicityScore
        let teamChemistry = max(0, min(100, rawChemistry))

        return LockerRoomState(
            teamChemistry: teamChemistry,
            leadershipScore: leadershipScore,
            toxicityScore: toxicityScore,
            recentEvents: Array(events.prefix(8)) // cap log to 8 entries
        )
    }

    // MARK: - Apply Morale Effects

    /// Updates each player's morale based on team record, chemistry, contract situation,
    /// and their personality archetype.
    static func applyMoraleEffects(
        players: [Player],
        teamWins: Int,
        teamLosses: Int,
        chemistry: Int
    ) {
        let totalGames = teamWins + teamLosses
        let winRate = totalGames > 0 ? Double(teamWins) / Double(totalGames) : 0.5

        for player in players {
            var delta = 0

            // --- Team record impact ---
            if winRate >= 0.7 {
                delta += 5
            } else if winRate >= 0.5 {
                delta += 2
            } else if winRate < 0.35 {
                delta -= 4
            } else {
                delta -= 1
            }

            // --- Chemistry impact ---
            if chemistry >= 75 {
                delta += 3
            } else if chemistry >= 50 {
                delta += 1
            } else if chemistry < 35 {
                delta -= 3
            } else {
                delta -= 1
            }

            // --- Contract situation: underpaid players lose morale ---
            let marketValue = ContractEngine.estimateMarketValue(player: player)
            let payRatio = marketValue > 0 ? Double(player.annualSalary) / Double(marketValue) : 1.0
            if payRatio < 0.65 {
                // Significantly underpaid
                let contractPenalty = player.personality.motivation == .money ? -6 : -3
                delta += contractPenalty
            } else if payRatio >= 1.1 {
                // Overpaid or on a great deal
                let contractBonus = player.personality.motivation == .money ? 4 : 2
                delta += contractBonus
            }

            // --- Contract years remaining: upcoming free agency creates anxiety ---
            if player.contractYearsRemaining == 1 {
                if player.personality.motivation == .money {
                    delta -= 3 // Money-motivated players want security
                } else if player.personality.motivation == .loyalty {
                    delta -= 1
                }
            }

            // --- Personality modifiers ---
            switch player.personality.archetype {
            case .feelPlayer:
                // Feel Players swing more dramatically in both directions
                delta = Int((Double(delta) * 1.5).rounded())

            case .dramaQueen:
                // Drama Queens amplify the swing and react to bad situations harder
                if delta < 0 {
                    delta = Int((Double(delta) * 1.4).rounded())
                }

            case .steadyPerformer, .quietProfessional:
                // Stable archetypes absorb volatility
                delta = Int((Double(delta) * 0.6).rounded())

            case .loneWolf:
                // Lone Wolves are less affected by team morale dynamics
                delta = Int((Double(delta) * 0.7).rounded())

            default:
                break
            }

            // Apply clamped morale update
            player.morale = max(1, min(100, player.morale + delta))
        }
    }

    // MARK: - Weekly Morale Update

    /// Small weekly morale adjustments tied to the most recent game result.
    /// Streaks compound these effects for feel players.
    static func weeklyMoraleUpdate(
        players: [Player],
        wonLastGame: Bool,
        chemistry: Int
    ) {
        for player in players {
            var delta = 0

            // Base shift from win/loss
            if wonLastGame {
                delta += 3
            } else {
                delta -= 3
            }

            // Chemistry still has a mild weekly influence
            if chemistry >= 70 {
                delta += 1
            } else if chemistry < 40 {
                delta -= 1
            }

            // Personality-based weekly variance
            switch player.personality.archetype {
            case .feelPlayer:
                // Feel Players ride the emotional rollercoaster week to week
                delta = wonLastGame ? delta + 3 : delta - 3

            case .dramaQueen:
                // Drama Queens are extra volatile — swings are steeper
                delta = wonLastGame ? delta + 2 : delta - 4

            case .steadyPerformer, .quietProfessional:
                // Dampen the weekly swing significantly
                delta = Int((Double(delta) * 0.4).rounded())

            case .teamLeader, .mentor:
                // Leaders stay grounded; winning gives a small extra lift
                delta = wonLastGame ? delta + 1 : delta - 1

            case .fieryCompetitor:
                // Competitors hate losing more than they love winning
                delta = wonLastGame ? delta + 1 : delta - 3

            default:
                break
            }

            // Money-motivated players on expiring contracts feel losses more
            if player.personality.motivation == .money && player.contractYearsRemaining <= 1 {
                if !wonLastGame { delta -= 2 }
            }

            // Winning-motivated players get an extra morale kick from victories
            if player.personality.motivation == .winning {
                delta = wonLastGame ? delta + 2 : delta - 2
            }

            // Apply clamped morale update
            player.morale = max(1, min(100, player.morale + delta))
        }
    }

    // MARK: - Chemistry Color Helper

    /// Returns a string label for the chemistry level, used for display.
    static func chemistryLabel(_ chemistry: Int) -> String {
        switch chemistry {
        case 80...100: return "Elite"
        case 65..<80:  return "Strong"
        case 50..<65:  return "Average"
        case 35..<50:  return "Shaky"
        default:       return "Toxic"
        }
    }

    /// Bucketed morale tier for a single player.
    static func moraleTier(_ morale: Int) -> MoraleTier {
        switch morale {
        case 75...100: return .high
        case 45..<75:  return .medium
        default:       return .low
        }
    }

    enum MoraleTier: String {
        case high   = "High"
        case medium = "Medium"
        case low    = "Low"
    }
}

// MARK: - R25: Position Group Chemistry

extension LockerRoomEngine {

    /// Chemistry state of a position room: good / neutral / tense.
    enum GroupChemistryState: String {
        case good    = "Good"
        case neutral = "Neutral"
        case tense   = "Tense"
    }

    /// An active veteran-mentor → young-player pairing at the same position.
    /// The protégé develops slightly faster while the pairing holds.
    struct Mentorship: Identifiable {
        let mentor: Player
        let protege: Player
        var id: UUID { protege.id }
    }

    /// Why a position room is at risk of boiling over.
    enum ConflictReason: String {
        case hotheads = "Two volatile personalities in one room"
        case starEgo  = "Two stars, no clear number one"
    }

    /// A brewing conflict between two players in the same position group.
    struct GroupConflict: Identifiable {
        let playerA: Player
        let playerB: Player
        let reason: ConflictReason
        var id: String { "\(playerA.id)-\(playerB.id)-\(reason)" }
    }

    /// Aggregated chemistry snapshot for one position room.
    struct PositionGroupChemistry: Identifiable {
        let id: String
        let label: String
        let icon: String
        let players: [Player]
        let mentorships: [Mentorship]
        let conflicts: [GroupConflict]
        let state: GroupChemistryState

        var avgMorale: Int {
            guard !players.isEmpty else { return 50 }
            return players.map(\.morale).reduce(0, +) / players.count
        }
    }

    /// Shared position-room definition (same grouping the Locker Room UI uses).
    static let positionRooms: [(id: String, label: String, icon: String, positions: Set<Position>)] = [
        ("offense_skill", "Offense - Skill", "figure.american.football", [.QB, .RB, .FB, .WR, .TE]),
        ("offense_line",  "Offensive Line",  "shield.lefthalf.filled",  [.LT, .LG, .C, .RG, .RT]),
        ("defense_front", "Defensive Front", "shield.fill",             [.DE, .DT, .OLB, .MLB]),
        ("defense_back",  "Secondary",       "eye.fill",                [.CB, .FS, .SS]),
        ("special_teams", "Special Teams",   "figure.kickboxing",       [.K, .P])
    ]

    /// Finds active mentorships on a roster: a Mentor/Team Leader veteran
    /// (4+ years pro, leadership ≥ 65) paired with the greenest young player
    /// (≤ 2 years pro) at his own position. One protégé per mentor and vice versa.
    static func activeMentorships(players: [Player]) -> [Mentorship] {
        let mentors = players
            .filter {
                $0.personality.isMentor && $0.yearsPro >= 4
                && $0.mental.leadership >= 65 && !$0.isHoldingOut
            }
            .sorted { $0.mental.leadership > $1.mental.leadership }
        guard !mentors.isEmpty else { return [] }

        let youngsters = players.filter { $0.yearsPro <= 2 && !$0.isHoldingOut }
        var takenProteges = Set<UUID>()
        var result: [Mentorship] = []

        for mentor in mentors {
            let candidate = youngsters
                .filter {
                    $0.position == mentor.position
                    && $0.id != mentor.id
                    && !takenProteges.contains($0.id)
                }
                .min { ($0.yearsPro, -$0.overall) < ($1.yearsPro, -$1.overall) }
            guard let protege = candidate else { continue }
            takenProteges.insert(protege.id)
            result.append(Mentorship(mentor: mentor, protege: protege))
        }
        return result
    }

    /// IDs of every mentored young player across the league (one lookup for
    /// the weekly development pass). Grouped per team so mentors only ever
    /// tutor their own teammates.
    static func mentoredProtegeIDs(allPlayers: [Player]) -> Set<UUID> {
        var ids = Set<UUID>()
        let byTeam = Dictionary(grouping: allPlayers.filter { $0.teamID != nil }, by: { $0.teamID! })
        for (_, roster) in byTeam {
            for pairing in activeMentorships(players: roster) {
                ids.insert(pairing.protege.id)
            }
        }
        return ids
    }

    /// Detects brewing conflicts inside position rooms:
    /// 1. Two hotheads (Fiery Competitor / Drama Queen) share a room and at
    ///    least one is frustrated (morale < 65).
    /// 2. Two stars at the SAME position (both ≥ 82 OVR, within 2 points) —
    ///    no clear number one, egos collide.
    static func activeConflicts(players: [Player]) -> [GroupConflict] {
        var conflicts: [GroupConflict] = []

        for room in positionRooms {
            let members = players.filter { room.positions.contains($0.position) }
            guard members.count >= 2 else { continue }

            // 1) Hothead pair.
            let hotheads = members
                .filter {
                    $0.personality.archetype == .fieryCompetitor
                    || $0.personality.archetype == .dramaQueen
                }
                .sorted { $0.overall > $1.overall }
            if hotheads.count >= 2, hotheads.contains(where: { $0.morale < 65 }) {
                conflicts.append(GroupConflict(
                    playerA: hotheads[0], playerB: hotheads[1], reason: .hotheads
                ))
            }

            // 2) Star + star without a clear top dog at the same position.
            let byPosition = Dictionary(grouping: members, by: { $0.position })
            for position in byPosition.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
                let stars = (byPosition[position] ?? [])
                    .filter { $0.overall >= 82 }
                    .sorted { $0.overall > $1.overall }
                if stars.count >= 2, stars[0].overall - stars[1].overall <= 2 {
                    conflicts.append(GroupConflict(
                        playerA: stars[0], playerB: stars[1], reason: .starEgo
                    ))
                }
            }
        }
        return conflicts
    }

    /// Full chemistry snapshot per position room: members, mentorships,
    /// conflicts, and a good/neutral/tense verdict.
    static func positionGroupChemistry(players: [Player]) -> [PositionGroupChemistry] {
        let mentorships = activeMentorships(players: players)
        let conflicts = activeConflicts(players: players)

        return positionRooms.compactMap { room in
            let members = players.filter { room.positions.contains($0.position) }
            guard !members.isEmpty else { return nil }
            let memberIDs = Set(members.map(\.id))
            let roomMentorships = mentorships.filter { memberIDs.contains($0.mentor.id) }
            let roomConflicts = conflicts.filter { memberIDs.contains($0.playerA.id) }
            let avg = members.map(\.morale).reduce(0, +) / members.count

            let state: GroupChemistryState
            if !roomConflicts.isEmpty || avg < 45 {
                state = .tense
            } else if !roomMentorships.isEmpty || avg >= 70 {
                state = .good
            } else {
                state = .neutral
            }

            return PositionGroupChemistry(
                id: room.id,
                label: room.label,
                icon: room.icon,
                players: members,
                mentorships: roomMentorships,
                conflicts: roomConflicts,
                state: state
            )
        }
    }
}

// MARK: - R25: Weekly Locker Room Events

extension LockerRoomEngine {

    /// Rolls a weekly locker-room event for the user's team (~25 % of weeks).
    /// Candidates are built from personalities + morale + recent results, so
    /// the coach can always trace WHY something happened:
    /// - loss + frustrated hothead → outburst (choice: step in / let it play out)
    /// - win + team leader → players-only meeting (small team-wide boost)
    /// - mentor + young player at his position → mentor moment (protégé boost)
    /// - two stars without a clear number one → simmering tension (choice)
    /// - class clown after a loss → keeps the room loose (tiny lift)
    ///
    /// Informational events apply their morale effect immediately and return
    /// with `resolutionSummary` set; choice events return unresolved.
    static func rollWeeklyEvent(
        players: [Player],
        wonLastGame: Bool?,
        teamWins: Int,
        teamLosses: Int,
        week: Int,
        season: Int
    ) -> LockerRoomEvent? {
        guard !players.isEmpty else { return nil }
        guard Int.random(in: 1...100) <= 25 else { return nil }

        let losing = teamLosses > teamWins
        var candidates: [(weight: Int, build: () -> LockerRoomEvent)] = []

        // 1) Loss + frustrated hothead → outburst (choice).
        if wonLastGame == false {
            let frustrated = players
                .filter {
                    ($0.personality.archetype == .fieryCompetitor
                     || $0.personality.archetype == .dramaQueen)
                    && $0.morale < 55 && !$0.isHoldingOut
                }
                .sorted { $0.overall > $1.overall }
            if let hothead = frustrated.first {
                candidates.append((weight: 4 + (losing ? 2 : 0), build: {
                    LockerRoomEvent(
                        season: season, week: week, kind: .outburst,
                        title: "Locker Room Outburst",
                        detail: "\(hothead.fullName) (\(hothead.position.rawValue)) tore into teammates after the loss. The \(hothead.personality.archetype.displayName.lowercased()) is boiling over and the room is looking at you.",
                        playerIDs: [hothead.id],
                        playerNames: [hothead.fullName],
                        options: [
                            LockerRoomEventOption(
                                label: "Step In",
                                detail: "Pull \(hothead.lastName) aside and address it head-on. He won't like it, but the room sees accountability.",
                                targetMoraleDelta: -2,
                                teamMoraleDelta: +2,
                                outcomeSummary: "You confronted \(hothead.fullName) about the outburst — the room appreciated the accountability."
                            ),
                            LockerRoomEventOption(
                                label: "Let It Play Out",
                                detail: "Sometimes the room polices itself. \(hothead.lastName) keeps his edge, but teammates may feel it went unchecked.",
                                targetMoraleDelta: +1,
                                teamMoraleDelta: -3,
                                outcomeSummary: "The outburst by \(hothead.fullName) went unaddressed — some players felt it was let slide."
                            )
                        ]
                    )
                }))
            }
        }

        // 2) Win + team leader → players-only meeting (auto boost).
        if wonLastGame == true, teamWins >= teamLosses {
            let leaders = players
                .filter { $0.personality.archetype == .teamLeader && $0.morale >= 60 }
                .sorted { $0.mental.leadership > $1.mental.leadership }
            if let leader = leaders.first {
                candidates.append((weight: 3, build: {
                    LockerRoomEvent(
                        season: season, week: week, kind: .playersOnlyMeeting,
                        title: "Players-Only Meeting",
                        detail: "\(leader.fullName) called a players-only meeting to keep the streak alive. Voices stayed low, standards stayed high.",
                        playerIDs: [leader.id],
                        playerNames: [leader.fullName],
                        resolutionSummary: "The meeting galvanized the room — team morale ticked up."
                    )
                }))
            }
        }

        // 3) Mentor moment (auto): protégé gets a lift.
        let mentorships = activeMentorships(players: players)
        if let pairing = mentorships.first {
            candidates.append((weight: 2, build: {
                LockerRoomEvent(
                    season: season, week: week, kind: .mentorMoment,
                    title: "Under His Wing",
                    detail: "\(pairing.mentor.fullName) has been staying late with \(pairing.protege.fullName), walking him through film and pro habits.",
                    playerIDs: [pairing.protege.id],
                    playerNames: [pairing.mentor.fullName, pairing.protege.fullName],
                    resolutionSummary: "\(pairing.protege.fullName) is soaking it up — his confidence is growing."
                )
            }))
        }

        // 4) Simmering star tension (choice).
        let conflicts = activeConflicts(players: players)
        if let conflict = conflicts.first {
            candidates.append((weight: 2 + (losing ? 1 : 0), build: {
                LockerRoomEvent(
                    season: season, week: week, kind: .starTension,
                    title: "Tension in the Room",
                    detail: "\(conflict.playerA.fullName) and \(conflict.playerB.fullName) are circling each other — \(conflict.reason.rawValue.lowercased()). Beat writers are starting to ask questions.",
                    playerIDs: [conflict.playerA.id, conflict.playerB.id],
                    playerNames: [conflict.playerA.fullName, conflict.playerB.fullName],
                    options: [
                        LockerRoomEventOption(
                            label: "Define Roles",
                            detail: "Set the pecking order in front of the room. Not everyone will love it, but everyone will know where they stand.",
                            targetMoraleDelta: -1,
                            teamMoraleDelta: +2,
                            outcomeSummary: "You defined the roles publicly — the room has clarity, even if the stars grumbled."
                        ),
                        LockerRoomEventOption(
                            label: "Let Them Compete",
                            detail: "Competition sharpens stars — but teammates may start picking sides.",
                            targetMoraleDelta: +2,
                            teamMoraleDelta: -2,
                            outcomeSummary: "You let the rivalry burn — the stars are pushing each other, but the room is picking sides."
                        )
                    ]
                )
            }))
        }

        // 5) Class clown keeps things loose after a loss (auto).
        if wonLastGame == false {
            let clowns = players.filter { $0.personality.archetype == .classClown }
            if let clown = clowns.max(by: { $0.morale < $1.morale }) {
                candidates.append((weight: 1, build: {
                    LockerRoomEvent(
                        season: season, week: week, kind: .moodLift,
                        title: "Keeping It Loose",
                        detail: "After a rough Sunday, \(clown.fullName) had the room laughing again by Wednesday's walkthrough.",
                        playerIDs: [clown.id],
                        playerNames: [clown.fullName],
                        resolutionSummary: "The mood lightened — a short week feels a little shorter."
                    )
                }))
            }
        }

        // Weighted pick.
        let totalWeight = candidates.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return nil }
        var roll = Int.random(in: 1...totalWeight)
        var chosen: LockerRoomEvent?
        for candidate in candidates {
            roll -= candidate.weight
            if roll <= 0 {
                chosen = candidate.build()
                break
            }
        }
        guard let event = chosen else { return nil }

        // Informational events apply their (small) effect right away.
        if !event.options.isEmpty { return event }
        switch event.kind {
        case .playersOnlyMeeting:
            applyEventEffects(targetIDs: event.playerIDs, targetDelta: +3, teamDelta: +2, players: players)
        case .mentorMoment:
            applyEventEffects(targetIDs: event.playerIDs, targetDelta: +3, teamDelta: 0, players: players)
        case .moodLift:
            applyEventEffects(targetIDs: event.playerIDs, targetDelta: +2, teamDelta: +1, players: players)
        case .outburst, .starTension:
            break // choice events never reach here
        }
        return event
    }

    /// Applies a resolved option's morale deltas: involved players get the
    /// target delta, everyone else on the roster the team delta. Clamped 1-100.
    static func applyEventEffects(
        targetIDs: [UUID],
        targetDelta: Int,
        teamDelta: Int,
        players: [Player]
    ) {
        for player in players {
            let delta = targetIDs.contains(player.id) ? targetDelta : teamDelta
            guard delta != 0 else { continue }
            player.morale = max(1, min(100, player.morale + delta))
        }
    }

    /// Applies the chosen option to the roster and returns the resolved event
    /// for logging (caller persists it on the career).
    static func resolve(
        event: LockerRoomEvent,
        option: LockerRoomEventOption,
        players: [Player]
    ) -> LockerRoomEvent {
        applyEventEffects(
            targetIDs: event.playerIDs,
            targetDelta: option.targetMoraleDelta,
            teamDelta: option.teamMoraleDelta,
            players: players
        )
        var resolved = event
        resolved.resolutionSummary = option.outcomeSummary
        return resolved
    }
}
