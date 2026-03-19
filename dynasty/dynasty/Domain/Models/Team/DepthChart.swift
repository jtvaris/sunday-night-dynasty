import Foundation

// MARK: - Depth Chart Slot

/// Represents a named slot in the depth chart that maps to a base Position.
/// Some positions (WR, CB, OLB, DE) require multiple starters, so we use
/// labeled slots (e.g., WR1, WR2, WR3) that all map to the same underlying Position.
enum DepthChartSlot: String, Codable, CaseIterable, Identifiable, Hashable {

    // Offense
    case QB
    case RB
    case FB
    case WR1
    case WR2
    case WR3
    case TE
    case LT
    case LG
    case C
    case RG
    case RT

    // Defense
    case LE
    case RE
    case DT
    case LOLB
    case MLB
    case ROLB
    case CB1
    case CB2
    case FS
    case SS

    // Special Teams
    case K
    case P
    case KR
    case PR

    var id: String { rawValue }

    /// The base Position enum value that this slot accepts.
    var basePosition: Position {
        switch self {
        case .QB:   return .QB
        case .RB:   return .RB
        case .FB:   return .FB
        case .WR1, .WR2, .WR3: return .WR
        case .TE:   return .TE
        case .LT:   return .LT
        case .LG:   return .LG
        case .C:    return .C
        case .RG:   return .RG
        case .RT:   return .RT
        case .LE, .RE: return .DE
        case .DT:   return .DT
        case .LOLB, .ROLB: return .OLB
        case .MLB:  return .MLB
        case .CB1, .CB2: return .CB
        case .FS:   return .FS
        case .SS:   return .SS
        case .K:    return .K
        case .P:    return .P
        case .KR:   return .RB  // KR can be any fast player but defaults to RB
        case .PR:   return .WR  // PR can be any agile player but defaults to WR
        }
    }

    /// Human-readable label for display.
    var displayName: String {
        switch self {
        case .QB:   return "Quarterback"
        case .RB:   return "Running Back"
        case .FB:   return "Fullback"
        case .WR1:  return "Wide Receiver 1"
        case .WR2:  return "Wide Receiver 2"
        case .WR3:  return "Wide Receiver 3"
        case .TE:   return "Tight End"
        case .LT:   return "Left Tackle"
        case .LG:   return "Left Guard"
        case .C:    return "Center"
        case .RG:   return "Right Guard"
        case .RT:   return "Right Tackle"
        case .LE:   return "Left End"
        case .RE:   return "Right End"
        case .DT:   return "Defensive Tackle"
        case .LOLB: return "Left OLB"
        case .MLB:  return "Middle Linebacker"
        case .ROLB: return "Right OLB"
        case .CB1:  return "Cornerback 1"
        case .CB2:  return "Cornerback 2"
        case .FS:   return "Free Safety"
        case .SS:   return "Strong Safety"
        case .K:    return "Kicker"
        case .P:    return "Punter"
        case .KR:   return "Kick Returner"
        case .PR:   return "Punt Returner"
        }
    }

    /// Short label for badges.
    var shortLabel: String {
        rawValue
    }

    var side: PositionSide {
        switch self {
        case .QB, .RB, .FB, .WR1, .WR2, .WR3, .TE, .LT, .LG, .C, .RG, .RT:
            return .offense
        case .LE, .RE, .DT, .LOLB, .MLB, .ROLB, .CB1, .CB2, .FS, .SS:
            return .defense
        case .K, .P, .KR, .PR:
            return .specialTeams
        }
    }

    /// Maximum depth for this slot (starter + backups).
    var maxDepth: Int {
        switch self {
        case .QB:                        return 3
        case .RB:                        return 3
        case .FB:                        return 2
        case .WR1, .WR2, .WR3:          return 2
        case .TE:                        return 2
        case .LT, .LG, .C, .RG, .RT:   return 2
        case .LE, .RE:                   return 2
        case .DT:                        return 3
        case .LOLB, .MLB, .ROLB:        return 2
        case .CB1, .CB2:                 return 2
        case .FS, .SS:                   return 2
        case .K, .P:                     return 1
        case .KR, .PR:                   return 2
        }
    }

    /// Whether this slot allows any position (special teams returners).
    var acceptsAnyPosition: Bool {
        self == .KR || self == .PR
    }

    /// Slots organized by offensive unit.
    static let offenseSlots: [DepthChartSlot] = [
        .QB, .RB, .FB, .WR1, .WR2, .WR3, .TE, .LT, .LG, .C, .RG, .RT
    ]

    /// Slots organized by defensive unit.
    static let defenseSlots: [DepthChartSlot] = [
        .LE, .RE, .DT, .LOLB, .MLB, .ROLB, .CB1, .CB2, .FS, .SS
    ]

    /// Slots organized by special teams.
    static let specialTeamsSlots: [DepthChartSlot] = [
        .K, .P, .KR, .PR
    ]
}

// MARK: - Depth Chart

/// A plain Codable value type that maps each DepthChartSlot to an ordered list of player IDs.
/// Index 0 is the starter, index 1 is the first backup, and so on.
struct DepthChart: Codable {

    // MARK: - Storage

    /// Backing storage keyed by slot raw value.
    private var storage: [String: [UUID]]

    // MARK: - Init

    init() {
        storage = [:]
    }

    // MARK: - Public Interface (Slot-Based)

    /// Returns the full ordered depth list for a slot.
    func depthOrder(for slot: DepthChartSlot) -> [UUID] {
        storage[slot.rawValue] ?? []
    }

    /// Returns the starter (depth index 0) for a slot, if any.
    func starter(for slot: DepthChartSlot) -> UUID? {
        storage[slot.rawValue]?.first
    }

    /// Returns all starter IDs across all slots.
    var allStarters: [UUID] {
        storage.values.compactMap { $0.first }
    }

    // MARK: - Legacy Public Interface (Position-Based)

    /// All current entries as a Position-keyed dictionary (read-only computed view).
    /// Maintained for backward compatibility with GameSimulator.
    var entries: [Position: [UUID]] {
        var result: [Position: [UUID]] = [:]
        for (key, value) in storage {
            if let slot = DepthChartSlot(rawValue: key) {
                let pos = slot.basePosition
                var existing = result[pos] ?? []
                existing.append(contentsOf: value)
                result[pos] = existing
            }
        }
        return result
    }

    /// Returns the starter (depth index 0) for `position`, if any.
    /// Uses the first slot that matches this position.
    func starter(at position: Position) -> UUID? {
        let matchingSlots = DepthChartSlot.allCases.filter { $0.basePosition == position }
        return matchingSlots.compactMap { starter(for: $0) }.first
    }

    /// Returns the first backup (depth index 1) for `position`, if any.
    func backup(at position: Position) -> UUID? {
        let matchingSlots = DepthChartSlot.allCases.filter { $0.basePosition == position }
        for slot in matchingSlots {
            let list = depthOrder(for: slot)
            if list.count > 1 { return list[1] }
        }
        return nil
    }

    /// Returns the full ordered depth list for `position` (combines all slots for that position).
    func depthOrder(at position: Position) -> [UUID] {
        let matchingSlots = DepthChartSlot.allCases.filter { $0.basePosition == position }
        var combined: [UUID] = []
        for slot in matchingSlots {
            combined.append(contentsOf: depthOrder(for: slot))
        }
        // Deduplicate preserving order
        var seen = Set<UUID>()
        return combined.filter { seen.insert($0).inserted }
    }

    // MARK: - Mutations (Slot-Based)

    /// Assigns a player to a specific depth index in the given slot.
    mutating func assign(slot: DepthChartSlot, playerID: UUID, at index: Int) {
        var list = storage[slot.rawValue] ?? []
        // Remove from this slot if already present
        list.removeAll { $0 == playerID }
        if index < list.count {
            list[index] = playerID
        } else {
            list.append(playerID)
        }
        storage[slot.rawValue] = list
    }

    /// Removes a player from a specific slot.
    mutating func remove(slot: DepthChartSlot, playerID: UUID) {
        var list = storage[slot.rawValue] ?? []
        list.removeAll { $0 == playerID }
        storage[slot.rawValue] = list
    }

    /// Moves a player within a slot's depth order.
    mutating func move(slot: DepthChartSlot, fromIndex: Int, toIndex: Int) {
        var list = storage[slot.rawValue] ?? []
        guard list.indices.contains(fromIndex) else { return }
        let player = list.remove(at: fromIndex)
        let clampedTo = min(toIndex, list.count)
        list.insert(player, at: clampedTo)
        storage[slot.rawValue] = list
    }

    /// Swaps two players within a slot's depth order.
    mutating func swap(slot: DepthChartSlot, indexA: Int, indexB: Int) {
        var list = storage[slot.rawValue] ?? []
        guard list.indices.contains(indexA), list.indices.contains(indexB) else { return }
        list.swapAt(indexA, indexB)
        storage[slot.rawValue] = list
    }

    // MARK: - Legacy Mutations (Position-Based)

    /// Promotes `playerID` to the starter slot for `position`.
    mutating func setStarter(position: Position, playerID: UUID) {
        let slot = DepthChartSlot.allCases.first { $0.basePosition == position } ?? .QB
        var list = storage[slot.rawValue] ?? []
        if let existingIndex = list.firstIndex(of: playerID) {
            list.swapAt(0, existingIndex)
        } else {
            list.insert(playerID, at: 0)
        }
        storage[slot.rawValue] = list
    }

    /// Moves a player within a position's depth chart (legacy).
    mutating func move(position: Position, fromIndex: Int, toIndex: Int) {
        let slot = DepthChartSlot.allCases.first { $0.basePosition == position } ?? .QB
        move(slot: slot, fromIndex: fromIndex, toIndex: toIndex)
    }

    /// Replaces the player at `index` in the depth chart for `position` (legacy).
    mutating func assign(position: Position, playerID: UUID, at index: Int) {
        let slot = DepthChartSlot.allCases.first { $0.basePosition == position } ?? .QB
        assign(slot: slot, playerID: playerID, at: index)
    }

    // MARK: - Auto-Generate

    /// Sorts each position group by overall rating (descending) and fills all slots.
    /// Multi-slot positions (WR1/WR2/WR3, CB1/CB2, etc.) distribute players across slots.
    mutating func autoGenerate(players: [Player]) {
        var newStorage: [String: [UUID]] = [:]

        // Group players by their base position
        var positionGroups: [Position: [Player]] = [:]
        for player in players {
            positionGroups[player.position, default: []].append(player)
        }

        // Sort each group by overall descending
        for key in positionGroups.keys {
            positionGroups[key]?.sort { $0.overall > $1.overall }
        }

        // Fill each slot
        for slot in DepthChartSlot.allCases {
            guard var available = positionGroups[slot.basePosition], !available.isEmpty else {
                continue
            }

            // For special teams returners, pick from fast players
            if slot == .KR {
                let fastPlayers = players
                    .sorted { $0.physical.speed > $1.physical.speed }
                    .prefix(slot.maxDepth)
                newStorage[slot.rawValue] = Array(fastPlayers).map { $0.id }
                continue
            }
            if slot == .PR {
                let agilePlayers = players
                    .sorted { $0.physical.agility > $1.physical.agility }
                    .prefix(slot.maxDepth)
                newStorage[slot.rawValue] = Array(agilePlayers).map { $0.id }
                continue
            }

            // Take players for this slot's depth, removing them from the pool
            let count = min(slot.maxDepth, available.count)
            let assigned = Array(available.prefix(count))
            newStorage[slot.rawValue] = assigned.map { $0.id }

            // Remove assigned players from the pool so they don't appear in sibling slots
            let assignedIDs = Set(assigned.map { $0.id })
            available.removeAll { assignedIDs.contains($0.id) }
            positionGroups[slot.basePosition] = available
        }

        storage = newStorage
    }

    // MARK: - Analytics

    /// Calculates team overall rating from current starters.
    func teamOverall(lookup: [UUID: Player]) -> Int {
        let starters = allStarters.compactMap { lookup[$0] }
        guard !starters.isEmpty else { return 0 }
        let total = starters.reduce(0) { $0 + $1.overall }
        return total / starters.count
    }

    /// Calculates offense overall from offensive starters.
    func offenseOverall(lookup: [UUID: Player]) -> Int {
        let offStarters = DepthChartSlot.offenseSlots
            .compactMap { starter(for: $0) }
            .compactMap { lookup[$0] }
        guard !offStarters.isEmpty else { return 0 }
        return offStarters.reduce(0) { $0 + $1.overall } / offStarters.count
    }

    /// Calculates defense overall from defensive starters.
    func defenseOverall(lookup: [UUID: Player]) -> Int {
        let defStarters = DepthChartSlot.defenseSlots
            .compactMap { starter(for: $0) }
            .compactMap { lookup[$0] }
        guard !defStarters.isEmpty else { return 0 }
        return defStarters.reduce(0) { $0 + $1.overall } / defStarters.count
    }

    /// Calculates the impact of swapping a player into a slot.
    /// Returns the delta in team OVR (positive = improvement).
    func impactOfAssigning(playerID: UUID, toSlot: DepthChartSlot, at index: Int, lookup: [UUID: Player]) -> Int {
        let currentOVR = teamOverall(lookup: lookup)
        var modified = self
        modified.assign(slot: toSlot, playerID: playerID, at: index)
        let newOVR = modified.teamOverall(lookup: lookup)
        return newOVR - currentOVR
    }
}
