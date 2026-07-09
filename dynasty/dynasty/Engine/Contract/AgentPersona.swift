import Foundation

// MARK: - Agent Persona (R22)

/// Deterministic negotiation persona for a player's agent. Purely derived
/// from the player's UUID (same pattern as `GameWeather.forGame`), so no
/// SwiftData field is needed and every screen shows the same agent for the
/// same player across launches.
///
/// The persona shapes the whole negotiation:
/// - demand level (±10-15% on the opening ask)
/// - patience (how many counter-offer rounds the agent tolerates)
/// - lowball tolerance (a hardliner cuts off talks for the offseason)
enum AgentPersona: String, CaseIterable {

    /// Drives a hard bargain: asks high, walks early, and a lowball offer
    /// ends negotiations for the rest of the offseason.
    case hardliner

    /// Deal-maker: reasonable ask, patient, always keeps talking.
    case cooperative

    /// Values loyalty and fit: modest ask for the home team, but expects
    /// the relationship to be honored.
    case loyalist

    // MARK: - Deterministic Derivation

    /// Deterministic persona draw for one player.
    ///
    /// Distribution: hardliner 30% / cooperative 40% / loyalist 30%.
    /// The roll comes from the UUID's raw bytes (bytes 8-15), NOT `hashValue`
    /// — Hashable's seed changes every launch, which would re-roll the
    /// persona per run.
    static func forPlayer(id: UUID) -> AgentPersona {
        let roll = Int(uuidValue(id, byteOffset: 8) % 100)
        switch roll {
        case ..<30:  return .hardliner
        case ..<70:  return .cooperative
        default:     return .loyalist
        }
    }

    /// Deterministic agent name for one player (stable across launches).
    static func agentName(for id: UUID) -> String {
        let index = Int(uuidValue(id, byteOffset: 0) % UInt64(agentNamePool.count))
        return agentNamePool[index]
    }

    /// Packs 8 UUID bytes (starting at `byteOffset`, wrapping at 16) into a UInt64.
    private static func uuidValue(_ id: UUID, byteOffset: Int) -> UInt64 {
        let b = id.uuid
        let bytes = [b.0, b.1, b.2, b.3, b.4, b.5, b.6, b.7,
                     b.8, b.9, b.10, b.11, b.12, b.13, b.14, b.15]
        var value: UInt64 = 0
        for i in 0..<8 {
            value = (value << 8) | UInt64(bytes[(byteOffset + i) % 16])
        }
        return value
    }

    private static let agentNamePool: [String] = [
        "Marcus Cole", "Dana Whitfield", "Sol Bergman", "Rich Alvarez",
        "Tanya Brooks", "Jerry Feldman", "Andre Simmons", "Kate Donovan",
        "Vince Caruso", "Lamar Ellis", "Priya Nair", "Doug McAllister",
        "Renee Ortiz", "Chad Barker", "Isaiah Grant", "Monica Reyes",
        "Bill Straub", "Terrell Watkins", "Nina Kowalski", "Gary Lipman",
        "Omar Haddad", "Jess Trainor", "Frank DiMarco", "Alicia Vaughn"
    ]

    // MARK: - Display

    /// Short style label shown next to the agent's name in negotiation UI.
    var styleLabel: String {
        switch self {
        case .hardliner:   return "Hard Negotiator"
        case .cooperative: return "Deal-Maker"
        case .loyalist:    return "Loyalty-Driven"
        }
    }

    /// One-line style description for headers/tooltips.
    var styleDescription: String {
        switch self {
        case .hardliner:   return "Asks high, walks early. Lowball at your own risk."
        case .cooperative: return "Wants a deal done. Willing to meet in the middle."
        case .loyalist:    return "Rewards commitment. Discounts for teams that show respect."
        }
    }

    /// SF Symbol for compact persona chips.
    var symbolName: String {
        switch self {
        case .hardliner:   return "flame.fill"
        case .cooperative: return "hand.thumbsup.fill"
        case .loyalist:    return "heart.fill"
        }
    }

    // MARK: - Negotiation Behavior

    /// Multiplier on the agent's opening demand (spec: ±10-15%).
    var demandFactor: Double {
        switch self {
        case .hardliner:   return 1.13
        case .cooperative: return 0.90
        case .loyalist:    return 0.97
        }
    }

    /// How many GM counter-offer rounds the agent tolerates before walking.
    var maxRounds: Int {
        switch self {
        case .hardliner:   return 2
        case .cooperative: return 4
        case .loyalist:    return 3
        }
    }

    /// Offer-to-ask ratio below which the agent considers the offer insulting.
    /// For a hardliner this ends negotiations for the rest of the offseason.
    var lowballCutoff: Double {
        switch self {
        case .hardliner:   return 0.72
        case .cooperative: return 0.55
        case .loyalist:    return 0.62
        }
    }

    /// Whether an insulting offer cuts off talks until next offseason.
    var breaksOffForSeason: Bool {
        self == .hardliner
    }

    /// Extra acceptance-threshold shift used by the quick re-sign flow
    /// (positive = harder to satisfy).
    var reSignThresholdShift: Double {
        switch self {
        case .hardliner:   return 0.08
        case .cooperative: return -0.05
        case .loyalist:    return -0.02
        }
    }
}

// MARK: - Negotiation Lock Registry (R22)

/// Tracks players whose agents have cut off contract talks for the current
/// offseason (hardliner insulted by a lowball). UserDefaults-backed —
/// intentionally lightweight; cleared when a new season kicks off in
/// `WeekAdvancer.startNewSeason`.
enum NegotiationLockRegistry {

    private static let key = "negotiationLockedPlayerIDs"

    /// Marks a player's agent as refusing further talks this offseason.
    static func lock(_ playerID: UUID) {
        var ids = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        ids.insert(playerID.uuidString)
        UserDefaults.standard.set(Array(ids), forKey: key)
    }

    /// Whether the player's agent refuses to negotiate right now.
    static func isLocked(_ playerID: UUID) -> Bool {
        let ids = UserDefaults.standard.stringArray(forKey: key) ?? []
        return ids.contains(playerID.uuidString)
    }

    /// Clears every lock — called when a new season starts.
    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
