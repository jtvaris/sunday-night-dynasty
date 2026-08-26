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
        case .LOLB: return "Left Outside Linebacker"
        case .MLB:  return "Middle Linebacker"
        case .ROLB: return "Right Outside Linebacker"
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
    ///
    /// A player may hold a returner slot (KR/PR) in addition to a position
    /// slot, but never two position slots at once — assigning to a position
    /// slot removes the player from every other non-returner slot first.
    mutating func assign(slot: DepthChartSlot, playerID: UUID, at index: Int) {
        if !slot.acceptsAnyPosition {
            for other in DepthChartSlot.allCases
            where other != slot && !other.acceptsAnyPosition {
                if var otherList = storage[other.rawValue], otherList.contains(playerID) {
                    otherList.removeAll { $0 == playerID }
                    storage[other.rawValue] = otherList
                }
            }
        }

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

        // Sort each group by overall descending. Overall alone is not a total
        // order — two 79s at the same position are common, and Swift's sort is
        // not stable, so Auto-Set could hand back a different starter from the
        // same roster twice. Years pro then id breaks the tie the same way every
        // run: at equal rating the younger man gets the reps.
        for key in positionGroups.keys {
            positionGroups[key]?.sort {
                if $0.overall != $1.overall { return $0.overall > $1.overall }
                if $0.yearsPro != $1.yearsPro { return $0.yearsPro < $1.yearsPro }
                return $0.id.uuidString < $1.id.uuidString
            }
        }

        // Fill each slot
        for slot in DepthChartSlot.allCases {
            // Returners first, and BEFORE the base-position guard.
            //
            // KR and PR draw from the whole roster by speed and agility — their
            // `basePosition` (RB, WR) is only a display default. They used to sit
            // below the guard, which reads that same pool AFTER the RB and WR1-3
            // slots have consumed it: a club with three running backs and three
            // receivers emptied both groups before the loop ever reached the
            // returners, so `continue` fired and Auto-Set left them unassigned —
            // while the "Lineup Incomplete" dialog told the user Auto-Set fills
            // every empty slot in one tap, and the phase would not advance.
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

            guard var available = positionGroups[slot.basePosition], !available.isEmpty else {
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

    // MARK: - Reconcile after a roster change

    /// Drops released/retired men from every slot and re-fills the starter
    /// holes that leaves, in one pass.
    ///
    /// Why this exists: a cut-down round used to invalidate the chart silently.
    /// Releasing twelve men to reach 75 could empty a starter slot, and the only
    /// feedback was the blocking "Lineup Incomplete" dialog one screen later, on
    /// the next Advance — three rounds, three blocks, with nothing on the cut
    /// screen warning that a marked man was somebody's starter.
    ///
    /// Deliberately conservative, because the chart is the user's own work:
    ///
    /// * **Prune is unconditional** — an ID that is no longer on the roster is a
    ///   dangling reference and every reader already treats it as empty.
    /// * **Back-fill only reaches EMPTY slots.** A slot whose starter survived is
    ///   never re-ordered, even if the cut left a better body behind. Auto-Set is
    ///   still the one control that rewrites a standing chart.
    /// * **Only a slot the club can actually cover**, using the same spare-body
    ///   accounting as `CareerShellView.depthChartGaps`, so this fills exactly
    ///   the slots that gate would have flagged and can never assign one man to
    ///   two rooms.
    ///
    /// Returns the slots it filled, so a caller can tell the user what moved.
    @discardableResult
    mutating func reconcile(with roster: [Player]) -> [DepthChartSlot] {
        let available = roster.filter { !$0.isRetired }
        let onRoster = Set(available.map(\.id))

        // 1. Prune. Survivors keep their order.
        for key in storage.keys {
            storage[key] = (storage[key] ?? []).filter { onRoster.contains($0) }
        }

        guard !available.isEmpty else { return [] }

        // 2. What is left over per room, after the slots still standing.
        var spareByPosition: [Position: [Player]] = [:]
        for player in available {
            spareByPosition[player.position, default: []].append(player)
        }
        for key in spareByPosition.keys {
            spareByPosition[key]?.sort { $0.overall > $1.overall }
        }

        var assigned = Set<UUID>()
        for slot in DepthChartSlot.allCases {
            for id in storage[slot.rawValue] ?? [] { assigned.insert(id) }
        }
        for slot in DepthChartSlot.allCases where !slot.acceptsAnyPosition {
            guard let starter = storage[slot.rawValue]?.first else { continue }
            spareByPosition[slot.basePosition]?.removeAll { $0.id == starter }
        }

        // 3. Back-fill the empties.
        var filled: [DepthChartSlot] = []
        for slot in DepthChartSlot.allCases
        where (storage[slot.rawValue] ?? []).isEmpty {
            if slot == .KR || slot == .PR {
                // The returners draw from the whole roster, by the same trait
                // `autoGenerate` ranks them on — their `basePosition` is a
                // display default, not a pool.
                let pool = available.sorted {
                    slot == .KR
                        ? $0.physical.speed > $1.physical.speed
                        : $0.physical.agility > $1.physical.agility
                }
                guard let pick = pool.first else { continue }
                storage[slot.rawValue] = [pick.id]
                filled.append(slot)
                continue
            }
            guard var room = spareByPosition[slot.basePosition], !room.isEmpty else { continue }
            let pick = room.removeFirst()
            spareByPosition[slot.basePosition] = room
            storage[slot.rawValue] = [pick.id]
            assigned.insert(pick.id)
            filled.append(slot)
        }
        return filled
    }

    /// Reconciles the chart the CAREER has saved, and writes it back.
    ///
    /// The shared half of the fix: every user-facing release path — the cut
    /// screen, the cap-compliance sweep, a player card, a contract page — used
    /// to leave the released man's UUID sitting in his slot. Nothing resolves it
    /// afterwards, so the slot reads as empty and the next offseason advance
    /// stops on "Lineup Incomplete", one screen and sometimes one phase away
    /// from the release that caused it.
    ///
    /// Returns the starter slots that had to be re-filled (an empty list when
    /// the prune alone was enough, which is the common case — dropping a
    /// dangling ID promotes the backup behind it).
    @discardableResult
    static func reconcileSaved(career: Career, roster: [Player]) -> [DepthChartSlot] {
        guard let data = career.depthChartData,
              var chart = try? JSONDecoder().decode(DepthChart.self, from: data) else { return [] }
        let filled = chart.reconcile(with: roster)
        guard let encoded = try? JSONEncoder().encode(chart) else { return [] }
        career.depthChartData = encoded
        return filled
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
