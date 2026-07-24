import Foundation

// MARK: - Heat State (round 4 mental game — hot/cold player FORM)

/// The unified hot/cold FORM tracker, shared by both engines exactly the way
/// `AdaptiveOpponentAI.RunKeyState` is shared: one pure in-memory component,
/// two feeders. `LiveGameEngine` feeds it richly (every resolved battle from the
/// `MatchupResolver`), `GameSimulator` feeds it coarsely (per-drive from the
/// `PlayResult` stream), but both call the SAME `reward` math with the SAME
/// step constants, so an identical signal produces identical heat — that is the
/// engine-parity guarantee round 4 rests on.
///
/// Heat lives here (the feeder side); it is READ off `SimPlayer.heat`, which the
/// engines stamp from `value(_:)` each drive. Never persisted — a streak is a
/// per-game state, so this is a ZERO save-schema change.
struct HeatState {

    // MARK: Accumulation constants (shared by BOTH feeders)
    //
    // Centralized here (not on the engines) so the live feed, the sim feed, and
    // the balance harness all reference the identical literals — a feeder can
    // never drift from the other, and the harness measures the real component.

    /// A won individual battle (blocker beats rusher, WR beats CB, …).
    static let winStep = 0.34
    /// A lost individual battle.
    static let lossStep = 0.34
    /// A 20+ chunk / TD / big defensive stop.
    static let bigStep = 0.50
    /// A turnover (INT thrown, fumble lost) — the biggest single swing.
    static let turnoverStep = 0.55
    /// Per-drive-boundary decay factor toward neutral (both engines).
    static let decayPerDrive = 0.80
    /// A frustrated ego star's per-drive heat penalty folded through this
    /// channel by the SIM ego analogue (§4). Live ego stays its own richer
    /// attribute mechanic.
    static let egoFrustrationHeat = 0.30

    // MARK: Write-back thresholds (§5 — end-of-game heat → morale)

    /// At or above this heat, a hot game nudges morale up.
    static let hotThreshold = 0.5
    /// At or below this heat, a cold game nudges morale down.
    static let coldThreshold = -0.5
    /// Signed morale nudge applied at the write-back (clamped 1…100 by caller).
    static let moraleNudge = 2

    // MARK: State

    private var heat: [UUID: Double] = [:]

    /// Current heat for a player, 0 (neutral) if untracked.
    func value(_ id: UUID) -> Double { heat[id] ?? 0 }

    /// The single shared accumulation step both feeders call. `scaleEligible`
    /// is `!archetype.isFormImmune`: an immune metronome pro never accumulates,
    /// so his trajectory stays dead flat (belt-and-suspenders with the 0.0
    /// `heatEffectScale`). Form-sensitive and neutral players accumulate
    /// IDENTICALLY here — they differ only later, at the effect scale.
    mutating func reward(_ id: UUID, _ amount: Double, scaleEligible: Bool) {
        guard scaleEligible else { return }
        let updated = (heat[id] ?? 0) + amount
        heat[id] = Swift.max(-1.0, Swift.min(1.0, updated))
    }

    /// Decays every tracked player toward neutral at each drive boundary. Small
    /// residuals snap to exactly 0 so the dictionary does not fill with dust.
    mutating func decayAll(_ factor: Double) {
        for id in Array(heat.keys) {
            let decayed = heat[id]! * factor
            heat[id] = abs(decayed) < 0.02 ? 0 : decayed
        }
    }
}
