import Foundation

/// A plain Codable value type that maps each Position to an ordered list of player IDs.
/// Index 0 is the starter, index 1 is the first backup, and so on.
struct DepthChart: Codable {

    // MARK: - Storage

    /// Backing storage keyed by position raw value because Dictionary<Position, [UUID]>
    /// requires Position to be RawRepresentable<String> for Codable conformance.
    private var storage: [String: [UUID]]

    // MARK: - Init

    init() {
        storage = [:]
    }

    // MARK: - Public Interface

    /// All current entries as a Position-keyed dictionary (read-only computed view).
    var entries: [Position: [UUID]] {
        var result: [Position: [UUID]] = [:]
        for (key, value) in storage {
            if let position = Position(rawValue: key) {
                result[position] = value
            }
        }
        return result
    }

    /// Returns the starter (depth index 0) for `position`, if any.
    func starter(at position: Position) -> UUID? {
        storage[position.rawValue]?.first
    }

    /// Returns the first backup (depth index 1) for `position`, if any.
    func backup(at position: Position) -> UUID? {
        let list = storage[position.rawValue] ?? []
        return list.count > 1 ? list[1] : nil
    }

    /// Returns the full ordered depth list for `position`.
    func depthOrder(at position: Position) -> [UUID] {
        storage[position.rawValue] ?? []
    }

    // MARK: - Mutations

    /// Promotes `playerID` to the starter slot for `position`.
    /// If the player is already in the depth chart for this position, their current slot
    /// is swapped with slot 0; otherwise they are prepended.
    mutating func setStarter(position: Position, playerID: UUID) {
        var list = storage[position.rawValue] ?? []
        if let existingIndex = list.firstIndex(of: playerID) {
            list.swapAt(0, existingIndex)
        } else {
            list.insert(playerID, at: 0)
        }
        storage[position.rawValue] = list
    }

    /// Moves a player at `fromIndex` to `toIndex` within a position's depth chart.
    mutating func move(position: Position, fromIndex: Int, toIndex: Int) {
        var list = storage[position.rawValue] ?? []
        guard list.indices.contains(fromIndex), list.indices.contains(toIndex) else { return }
        let player = list.remove(at: fromIndex)
        list.insert(player, at: toIndex)
        storage[position.rawValue] = list
    }

    /// Replaces the player at `index` in the depth chart for `position` with `playerID`.
    mutating func assign(position: Position, playerID: UUID, at index: Int) {
        var list = storage[position.rawValue] ?? []
        // Remove the player if already present at a different slot (no duplicates).
        list.removeAll { $0 == playerID }
        if index < list.count {
            list[index] = playerID
        } else {
            // Pad with empty UUIDs if needed, then assign (should not happen in normal usage).
            list.append(playerID)
        }
        storage[position.rawValue] = list
    }

    // MARK: - Auto-Generate

    /// Sorts each position group by overall rating (descending) and rebuilds the depth chart.
    /// Existing manual overrides are discarded.
    mutating func autoGenerate(players: [Player]) {
        var newStorage: [String: [UUID]] = [:]
        for position in Position.allCases {
            let group = players
                .filter { $0.position == position }
                .sorted { $0.overall > $1.overall }
            if !group.isEmpty {
                newStorage[position.rawValue] = group.map { $0.id }
            }
        }
        storage = newStorage
    }
}
