import Foundation

// MARK: - Sim Player (HARNESS STANDALONE — assembled by sync_sources.sh)
//
// The two standalone SPLICE marker lines below (STORAGE and COMPUTED) are
// replaced, on every sync, with the corresponding regions sliced VERBATIM out of
// the repo Engine/Simulation/SimPlayer.swift (storage decls; and the schemeFam +
// computed-property block + `enum MentalTemperament`). That makes the sim-read
// fields and the mental-game computeds drift-proof by construction — they are
// never hand-copied here.
//
// Only the memberwise `init` (which REPLACES the shipped SwiftData
// `init(from: Player)` — the harness has no `@Model Player`) and the harness
// stubs at the bottom are harness-owned. If the repo adds a stored property the
// splice re-emits it and this init fails to compile until updated — a loud,
// fail-closed signal, never silent drift.
struct SimPlayer {
    // @@SPLICE:STORAGE@@

    init(
        fullName: String,
        position: Position,
        physical: PhysicalAttributes,
        mental: MentalAttributes,
        positionAttributes: PositionAttributes,
        overall: Int,
        morale: Int = 70,
        isMoodDependent: Bool = false,
        personalityArchetype: PersonalityArchetype = .steadyPerformer,
        schemeFamiliarity: [String: Int] = [:],
        fatigue: Int = 0,
        // Optional identity seam: defaults to a fresh UUID (every existing call
        // site is unchanged), but `SimPlayer.init(from: Player)` passes the live
        // player's id so heat attribution + fatigue/morale write-back key correctly.
        id: UUID? = nil
    ) {
        self.id = id ?? UUID()
        self.fullName = fullName
        self.position = position
        self.physical = physical
        self.mental = mental
        self.positionAttributes = positionAttributes
        self.isMoodDependent = isMoodDependent
        self.personalityArchetype = personalityArchetype
        self.morale = morale
        self.overall = overall
        self.schemeFamiliarity = schemeFamiliarity
        self.fatigue = fatigue
    }

    // @@SPLICE:COMPUTED@@

// MARK: - Harness stubs
//
// PlaySimulator references these symbols, which in the shipped app live in files
// the harness does not compile (MatchupResolver / CoachingEngine /
// VersatilityDevelopmentEngine). They are only reachable on the crediting /
// scheme-fit paths; the all-70 no-scheme harness never exercises them
// (schemeFitModifier short-circuits to 0 when both schemes are nil), so these
// mirrors exist purely to satisfy the compiler and never affect the numbers.

extension SimPlayer {
    /// Verbatim from `MatchupResolver.swift` — stable pseudo jersey number.
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

    /// Verbatim from `MatchupResolver.swift` — "T. Hill" short display name.
    var shortName: String {
        let parts = fullName.split(separator: " ")
        guard parts.count >= 2, let first = parts.first?.first else { return fullName }
        return "\(first). \(parts.dropFirst().joined(separator: " "))"
    }
}

/// Neutral stub for `CoachingEngine.schemeFit` — never called by the harness
/// (nil schemes short-circuit before it). Returns the shipped neutral baseline.
enum CoachingEngine {
    static func schemeFit(
        player: SimPlayer,
        offensiveScheme: OffensiveScheme?,
        defensiveScheme: DefensiveScheme?
    ) -> Double {
        0.5
    }
}

/// Mirrors the shipped `VersatilityDevelopmentEngine.schemePerformanceModifier`
/// SimPlayer overload. Never called by the harness (nil schemes).
enum VersatilityDevelopmentEngine {
    static func schemePerformanceModifier(player: SimPlayer, scheme: String) -> Double {
        let familiarity = Double(player.schemeFam(for: scheme))
        return 0.70 + (familiarity / 100.0) * 0.30
    }
}
