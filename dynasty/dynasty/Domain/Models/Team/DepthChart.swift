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
    // Two interior slots, not one. `MatchupResolver.defense` seats `dt1` and
    // `dt2`, and `WeekAdvancer.startingLineupIDs` fills `.DT` twice — every
    // engine that counts a start fields two tackles. A single `DT` slot with a
    // compensating `maxDepth: 3` printed the club's second-best tackle as a
    // BACKUP, which is a job he does not have.
    case DT1
    case DT2
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
        case .DT1, .DT2: return .DT
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
        case .DT1:  return "Defensive Tackle 1"
        case .DT2:  return "Defensive Tackle 2"
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
        case .LE, .RE, .DT1, .DT2, .LOLB, .MLB, .ROLB, .CB1, .CB2, .FS, .SS:
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
        case .DT1, .DT2:                 return 2
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

    /// One line saying why the man at the top of this slot is not a starter,
    /// or nil when he is.
    ///
    /// `MatchupResolver.offense` and `WeekAdvancer.startingLineupIDs` both fill
    /// the backfield as ONE job — `[.RB, .FB]`, running back preferred — so a
    /// fullback takes a snap only when the club has no back at all. The room is
    /// still worth ranking (somebody is the first fullback off the bench), but
    /// the chart must not draw him in the starter plate the other eleven earn.
    var packageNote: String? {
        self == .FB ? "The backfield is one job \u{2014} a fullback takes snaps only when no running back is available." : nil
    }

    /// True when this slot's top man is NOT one of the starters the game fields.
    var isPackageRole: Bool {
        packageNote != nil
    }

    /// The attribute this slot is ranked on, when it is not overall.
    ///
    /// KR and PR draw from the whole roster by speed and agility — in
    /// `autoGenerate`, in `reconcile`, and in the candidate picker's default
    /// sort. All three used to hard-code the trait separately and none of them
    /// printed it, so the returner rows showed an OVR the slot ignores and the
    /// candidate list arrived sorted by an invisible number.
    var rankingTrait: RankingTrait? {
        switch self {
        case .KR: return .speed
        case .PR: return .agility
        default:  return nil
        }
    }

    /// A player attribute a slot ranks on instead of overall.
    enum RankingTrait {
        case speed
        case agility

        /// Badge caption — the row has room for three letters, not a word.
        var shortLabel: String {
            switch self {
            case .speed:   return "SPD"
            case .agility: return "AGI"
            }
        }

        var displayName: String {
            switch self {
            case .speed:   return "Speed"
            case .agility: return "Agility"
            }
        }

        func value(of player: Player) -> Int {
            switch self {
            case .speed:   return player.physical.speed
            case .agility: return player.physical.agility
            }
        }
    }

    /// Slots organized by offensive unit.
    static let offenseSlots: [DepthChartSlot] = [
        .QB, .RB, .FB, .WR1, .WR2, .WR3, .TE, .LT, .LG, .C, .RG, .RT
    ]

    /// Slots organized by defensive unit.
    static let defenseSlots: [DepthChartSlot] = [
        .LE, .RE, .DT1, .DT2, .LOLB, .MLB, .ROLB, .CB1, .CB2, .FS, .SS
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

    // MARK: - Decoding

    private enum CodingKeys: String, CodingKey {
        case storage
    }

    /// Decodes a saved chart, migrating slots that have since been split.
    ///
    /// Storage is keyed by raw value, so a key nothing maps to any more is not
    /// an error — it is silently invisible, which is worse: the room reads as
    /// empty and the next Advance stops on "Lineup Incomplete" for a slot the
    /// user filled months ago.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var decoded = try container.decode([String: [UUID]].self, forKey: .storage)
        Self.splitLegacyInteriorLine(&decoded)
        storage = decoded
    }

    /// Charts saved before the interior line was split keep the whole tackle
    /// room under one `DT` key. Deal them out alternately — first man to DT1,
    /// second to DT2 — because that is what the old list MEANT: the engines
    /// have always fielded both of the top two, whatever the card labelled them.
    private static func splitLegacyInteriorLine(_ storage: inout [String: [UUID]]) {
        guard let legacy = storage.removeValue(forKey: "DT"), !legacy.isEmpty,
              storage[DepthChartSlot.DT1.rawValue] == nil,
              storage[DepthChartSlot.DT2.rawValue] == nil else { return }

        var first: [UUID] = []
        var second: [UUID] = []
        for (offset, id) in legacy.enumerated() {
            if offset.isMultiple(of: 2) { first.append(id) } else { second.append(id) }
        }
        storage[DepthChartSlot.DT1.rawValue] = Array(first.prefix(DepthChartSlot.DT1.maxDepth))
        if !second.isEmpty {
            storage[DepthChartSlot.DT2.rawValue] = Array(second.prefix(DepthChartSlot.DT2.maxDepth))
        }
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

    /// Every slot other than `excluding` where this man already stands first.
    ///
    /// `assign` deliberately lets one player hold a returner slot on top of a
    /// position slot, which is right — a club's best receiver often is its
    /// best returner. But a permitted double-booking still has to be visible:
    /// three starting jobs used to be drawn as three unrelated gold plates on
    /// two tabs, with nothing on any of them naming the other two.
    func startingSlots(of playerID: UUID, excluding slot: DepthChartSlot? = nil) -> [DepthChartSlot] {
        DepthChartSlot.allCases.filter { $0 != slot && starter(for: $0) == playerID }
    }

    /// Every slot other than `excluding` where this man appears at any depth.
    func slots(holding playerID: UUID, excluding slot: DepthChartSlot? = nil) -> [DepthChartSlot] {
        DepthChartSlot.allCases.filter { $0 != slot && depthOrder(for: $0).contains(playerID) }
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

        // Sort each group by overall descending, with the tie broken the same
        // way every run (see `outranks`).
        for key in positionGroups.keys {
            positionGroups[key]?.sort { a, b in Self.outranks(a, b, on: { $0.overall }) }
        }

        // Returners first, and BEFORE the position rooms are drained.
        //
        // KR and PR draw from the whole roster by the trait `rankingTrait`
        // names — their `basePosition` (RB, WR) is only a display default. They
        // used to be filled inside the position loop, which reads that same
        // pool AFTER the RB and WR1-3 slots have consumed it: a club with three
        // running backs and three receivers emptied both groups before the loop
        // ever reached the returners, so Auto-Set left them unassigned — while
        // the "Lineup Incomplete" dialog told the user Auto-Set fills every
        // empty slot in one tap, and the phase would not advance.
        for slot in DepthChartSlot.allCases {
            guard let trait = slot.rankingTrait else { continue }
            let ranked = players
                .sorted { a, b in Self.outranks(a, b, on: { trait.value(of: $0) }) }
                .prefix(slot.maxDepth)
            newStorage[slot.rawValue] = ranked.map { $0.id }
        }

        // Position rooms, BREADTH-FIRST across sibling slots.
        //
        // WR1/WR2/WR3, CB1/CB2 and DT1/DT2 are one room split into jobs, so
        // every starter has to be seated before any backup is. Filling them
        // slot by slot handed WR1 the two best receivers and made the
        // THIRD-best man WR2's starter — a card whose gold plate held a worse
        // player than the backup row on the card above it.
        var roomOrder: [Position] = []
        var roomSlots: [Position: [DepthChartSlot]] = [:]
        for slot in DepthChartSlot.allCases where slot.rankingTrait == nil {
            if roomSlots[slot.basePosition] == nil { roomOrder.append(slot.basePosition) }
            roomSlots[slot.basePosition, default: []].append(slot)
        }

        for position in roomOrder {
            guard var pool = positionGroups[position], !pool.isEmpty else { continue }
            let slots = roomSlots[position] ?? []
            let deepest = slots.map(\.maxDepth).max() ?? 0
            filling: for index in 0..<deepest {
                for slot in slots where index < slot.maxDepth {
                    guard !pool.isEmpty else { break filling }
                    newStorage[slot.rawValue, default: []].append(pool.removeFirst().id)
                }
            }
        }

        storage = newStorage
    }

    /// Ranks two men on `value`, breaking the tie the same way every run.
    ///
    /// Overall alone is not a total order — two 79s at the same position are
    /// common, and Swift's sort is not stable, so Auto-Set could hand back a
    /// different starter from the same roster twice. Years pro then id settles
    /// it: at equal rating the younger man gets the reps.
    private static func outranks(_ a: Player, _ b: Player, on value: (Player) -> Int) -> Bool {
        let aValue = value(a)
        let bValue = value(b)
        if aValue != bValue { return aValue > bValue }
        if a.yearsPro != b.yearsPro { return a.yearsPro < b.yearsPro }
        return a.id.uuidString < b.id.uuidString
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
            if let trait = slot.rankingTrait {
                // The returners draw from the whole roster, by the same trait
                // `autoGenerate` ranks them on — their `basePosition` is a
                // display default, not a pool.
                let pool = available.sorted { a, b in Self.outranks(a, b, on: { trait.value(of: $0) }) }
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

    // MARK: - Engine Handoff

    /// The chart the CAREER has saved, decoded and reconciled against `roster`.
    ///
    /// The single door every engine reader goes through, so "the chart as it
    /// stands against today's roster" has one definition rather than one per
    /// caller. Reconciling first is why no reader has to re-derive *is this man
    /// still on the club* (see ``reconcile(with:)``): a released man's UUID is
    /// pruned and an emptied starter slot is refilled before anybody reads a
    /// rank off it.
    ///
    /// Reconciles a LOCAL copy and never writes back — persisting the result is
    /// ``reconcileSaved(career:roster:)``'s job, called from the release paths
    /// that caused the drift. A week advance must not quietly rewrite the user's
    /// own work.
    ///
    /// `nil` = this career has never saved a chart, which is also the answer for
    /// all 31 AI clubs: `depthChartData` is a `Career` field, and there is one
    /// `Career`. See ``depthRanks`` for why that asymmetry is safe.
    static func saved(career: Career, roster: [Player]) -> DepthChart? {
        guard let data = career.depthChartData,
              var chart = try? JSONDecoder().decode(DepthChart.self, from: data) else { return nil }
        chart.reconcile(with: roster)
        return chart
    }

    /// Every listed man's index inside his own slot — 0 for a starter, 1 for the
    /// first man behind him — flattened into the one shape the simulator reads.
    ///
    /// Deliberately a plain `[UUID: Int]` and not the chart itself.
    /// `GameSimulator` and `PlaySimulator` are mirrored verbatim into
    /// `tools/balance-harness`, which compiles neither this file nor `Career`; a
    /// rank is the whole of what they need, and a bare number keeps the engine
    /// free of the Domain layer it would otherwise have to drag along.
    ///
    /// **The returner slots are skipped, and that is the point.**
    /// `GameSimulator.rollKickoff` takes no player at all — a flat 2 % housed
    /// return and a random 20-35 start — so KR and PR feed nothing today and
    /// nothing here pretends otherwise. Ranking them would be worse than
    /// useless: a man may hold KR on top of a position slot, so his returner
    /// index 0 would silently promote a WR3 backup into the starting trio. If a
    /// real return game is ever modelled, it reads the KR/PR slots directly;
    /// it does not arrive through this map.
    ///
    /// A man listed in two position slots (which ``assign(slot:playerID:at:)``
    /// prevents, but a legacy save may still carry) keeps his best index.
    var depthRanks: [UUID: Int] {
        var ranks: [UUID: Int] = [:]
        for slot in DepthChartSlot.allCases where !slot.acceptsAnyPosition {
            for (index, id) in depthOrder(for: slot).enumerated() {
                if let existing = ranks[id], existing <= index { continue }
                ranks[id] = index
            }
        }
        return ranks
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
