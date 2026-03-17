import Foundation

// MARK: - Supporting Types

struct GameEvent: Identifiable, Codable {
    let id: UUID
    let type: EventType
    let headline: String
    let description: String
    let playerID: UUID?
    let coachID: UUID?
    let teamID: UUID
    let options: [EventOption]
    let week: Int
    let season: Int

    init(
        id: UUID = UUID(),
        type: EventType,
        headline: String,
        description: String,
        playerID: UUID? = nil,
        coachID: UUID? = nil,
        teamID: UUID,
        options: [EventOption],
        week: Int,
        season: Int
    ) {
        self.id = id
        self.type = type
        self.headline = headline
        self.description = description
        self.playerID = playerID
        self.coachID = coachID
        self.teamID = teamID
        self.options = options
        self.week = week
        self.season = season
    }
}

struct EventOption: Identifiable, Codable {
    let id: UUID
    let label: String
    let description: String
    let moraleEffect: Int
    let lockerRoomEffect: Int
    let ownerEffect: Int
    let mediaEffect: Int

    init(
        id: UUID = UUID(),
        label: String,
        description: String,
        moraleEffect: Int = 0,
        lockerRoomEffect: Int = 0,
        ownerEffect: Int = 0,
        mediaEffect: Int = 0
    ) {
        self.id = id
        self.label = label
        self.description = description
        self.moraleEffect = moraleEffect
        self.lockerRoomEffect = lockerRoomEffect
        self.ownerEffect = ownerEffect
        self.mediaEffect = mediaEffect
    }
}

enum EventType: String, Codable {
    case holdout, suspension, arrest, socialMediaIncident,
         retirementSpeculation, podcastControversy,
         manOfTheYear, voluntaryWorkouts, rookieImpresses,
         coachConflict, coordinatorInterview, veteranReturn,
         injurySetback, aheadOfSchedule, freakInjury,
         contractDispute, tradeRequest, teamChemistry
}

// MARK: - Event Engine

/// Generates off-field events and drama, and applies player choices.
enum EventEngine {

    // MARK: - Weekly Event Generation

    /// Generates 0-2 events per week based on team context.
    static func generateWeeklyEvents(
        team: Team,
        players: [Player],
        coaches: [Coach],
        career: Career
    ) -> [GameEvent] {
        let teamPlayers = players.filter { $0.teamID == team.id }
        let teamCoaches = coaches.filter { $0.teamID == team.id }

        guard !teamPlayers.isEmpty else { return [] }

        var events: [GameEvent] = []
        let week = career.currentWeek
        let season = career.currentSeason
        let isLosing = team.losses > team.wins
        let mediaPressure = team.mediaMarket.mediaPressureMultiplier

        // Base probability of any event: 40%, amplified by market/losing
        let eventChance = 0.40 * mediaPressure * (isLosing ? 1.3 : 1.0)

        // First event roll
        if Double.random(in: 0...1) < eventChance {
            if let event = rollEvent(
                team: team,
                players: teamPlayers,
                coaches: teamCoaches,
                week: week,
                season: season,
                isLosing: isLosing
            ) {
                events.append(event)
            }
        }

        // Second event roll (lower probability)
        if Double.random(in: 0...1) < eventChance * 0.4 {
            if let event = rollEvent(
                team: team,
                players: teamPlayers,
                coaches: teamCoaches,
                week: week,
                season: season,
                isLosing: isLosing
            ) {
                // Avoid duplicate event types
                if !events.contains(where: { $0.type == event.type }) {
                    events.append(event)
                }
            }
        }

        return Array(events.prefix(2))
    }

    // MARK: - Apply Choice

    /// Applies the effects of the chosen option to the relevant entities.
    static func applyEventChoice(
        event: GameEvent,
        chosenOption: EventOption,
        player: Player?,
        coach: Coach?,
        owner: Owner?
    ) {
        // Player morale
        if let player = player {
            player.morale = min(100, max(0, player.morale + chosenOption.moraleEffect))
        }

        // Locker room effect: apply to the player's morale as a proxy for team chemistry
        // In a full implementation this would affect all team players
        if let player = player {
            let lockerRoomDelta = chosenOption.lockerRoomEffect / 2
            player.morale = min(100, max(0, player.morale + lockerRoomDelta))
        }

        // Owner satisfaction
        if let owner = owner {
            owner.satisfaction = min(100, max(0, owner.satisfaction + chosenOption.ownerEffect))
        }

        // Coach reputation (media effect acts as reputation modifier)
        if let coach = coach {
            let reputationDelta = chosenOption.mediaEffect > 0 ? 1 : (chosenOption.mediaEffect < 0 ? -1 : 0)
            coach.reputation = min(99, max(1, coach.reputation + reputationDelta))
        }
    }

    // MARK: - Private Event Rolling

    private static func rollEvent(
        team: Team,
        players: [Player],
        coaches: [Coach],
        week: Int,
        season: Int,
        isLosing: Bool
    ) -> GameEvent? {
        // Build weighted pool of possible event types
        var pool: [(type: EventType, weight: Int)] = []

        // Drama-prone players increase negative event probability
        let dramaPlayers = players.filter { $0.personality.isDramaticInMedia }
        let unhappyPlayers = players.filter { $0.morale < 40 }
        let underpaidPlayers = players.filter { $0.contractYearsRemaining <= 1 && $0.overall >= 75 }
        let rookies = players.filter { $0.yearsPro <= 1 }
        let veterans = players.filter { $0.yearsPro >= 8 }
        let injuredRehabbing = players.filter { $0.isInjured }

        // Negative events (weighted higher when losing or drama players present)
        let negativeBias = (isLosing ? 2 : 0) + (dramaPlayers.isEmpty ? 0 : 2)

        pool.append((.holdout, 3 + underpaidPlayers.count * 3))
        pool.append((.socialMediaIncident, 2 + dramaPlayers.count * 3))
        pool.append((.suspension, 1 + negativeBias))
        pool.append((.arrest, 1))
        pool.append((.podcastControversy, 2 + dramaPlayers.count * 2))
        pool.append((.contractDispute, 2 + underpaidPlayers.count * 2))
        pool.append((.tradeRequest, 1 + unhappyPlayers.count * 2))
        pool.append((.coachConflict, 2 + negativeBias))
        pool.append((.retirementSpeculation, veterans.isEmpty ? 0 : 3))
        pool.append((.freakInjury, 1))
        pool.append((.injurySetback, injuredRehabbing.isEmpty ? 0 : 3))

        // Positive events
        pool.append((.teamChemistry, isLosing ? 2 : 5))
        pool.append((.rookieImpresses, rookies.isEmpty ? 0 : 4))
        pool.append((.voluntaryWorkouts, 3))
        pool.append((.manOfTheYear, 2))
        pool.append((.aheadOfSchedule, injuredRehabbing.isEmpty ? 0 : 3))
        pool.append((.veteranReturn, veterans.isEmpty ? 0 : 2))

        // Coach-related
        if !coaches.isEmpty {
            pool.append((.coordinatorInterview, isLosing ? 1 : 3))
        }

        // Filter zero-weight entries and pick
        let validPool = pool.filter { $0.weight > 0 }
        guard !validPool.isEmpty else { return nil }

        let totalWeight = validPool.reduce(0) { $0 + $1.weight }
        var roll = Int.random(in: 1...totalWeight)

        var selectedType: EventType = .teamChemistry
        for entry in validPool {
            roll -= entry.weight
            if roll <= 0 {
                selectedType = entry.type
                break
            }
        }

        // Pick the relevant player/coach for this event
        let player: Player? = {
            switch selectedType {
            case .holdout, .contractDispute:
                return underpaidPlayers.randomElement() ?? players.randomElement()
            case .socialMediaIncident, .podcastControversy:
                return dramaPlayers.randomElement() ?? players.randomElement()
            case .tradeRequest:
                return unhappyPlayers.randomElement() ?? players.randomElement()
            case .rookieImpresses:
                return rookies.randomElement()
            case .retirementSpeculation, .veteranReturn:
                return veterans.randomElement()
            case .injurySetback, .aheadOfSchedule:
                return injuredRehabbing.randomElement()
            case .freakInjury:
                return players.filter({ !$0.isInjured }).randomElement()
            case .suspension, .arrest:
                return players.randomElement()
            case .manOfTheYear:
                return players.filter({ $0.personality.isMentor }).randomElement() ?? players.randomElement()
            case .voluntaryWorkouts, .teamChemistry:
                return nil
            case .coachConflict, .coordinatorInterview:
                return nil
            }
        }()

        let coach: Coach? = {
            switch selectedType {
            case .coachConflict, .coordinatorInterview:
                return coaches.randomElement()
            default:
                return nil
            }
        }()

        return EventTemplates.buildEvent(
            type: selectedType,
            teamID: team.id,
            teamName: team.fullName,
            playerID: player?.id,
            playerName: player?.fullName,
            coachID: coach?.id,
            coachName: coach?.fullName,
            week: week,
            season: season
        )
    }
}
