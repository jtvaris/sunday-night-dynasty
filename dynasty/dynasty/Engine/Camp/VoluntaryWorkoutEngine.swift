import Foundation
import SwiftData

// MARK: - VoluntaryWorkoutEngine

/// Runs voluntary / mandatory workout request flow. Personality archetype affects
/// participation: workhorses & mentors show up; divas & lone wolves duck.
/// Voluntary OTAs bump scheme knowledge; mandatory minicamp is a heavier hammer
/// with locker-room costs and injury-risk tradeoffs.
@MainActor
enum VoluntaryWorkoutEngine {

    // MARK: - Public API

    /// Computes participation pct based on type + roster personality mix.
    static func participation(
        type: VoluntaryWorkoutType,
        roster: [Player]
    ) -> Int {
        guard !roster.isEmpty else { return 0 }

        // Each type has a base attendance rate; personality adjusts per-player.
        let baseAttendance: Double
        switch type {
        case .voluntaryOTAs:      baseAttendance = 0.70
        case .mandatoryMinicamp:  baseAttendance = 0.95
        case .saturdayFilm:       baseAttendance = 0.40
        case .offDayPractice:     baseAttendance = 0.55
        }

        // Each player rolls a personality-adjusted attendance probability.
        var attended = 0
        for player in roster {
            let personalityDelta = personalityAttendanceDelta(player.personality.archetype)
            let workEthicDelta = (Double(player.mental.workEthic) - 50.0) / 100.0 * 0.20
            // Mandatory has a hard floor — even divas usually show.
            let floor = (type == .mandatoryMinicamp) ? 0.85 : 0.0
            let pct = max(floor, min(1.0, baseAttendance + personalityDelta + workEthicDelta))
            if Double.random(in: 0.0..<1.0) < pct {
                attended += 1
            }
        }

        return Int((Double(attended) / Double(roster.count) * 100.0).rounded())
    }

    /// Applies the workout: scheme bonuses, locker room delta, hidden fatigue.
    static func apply(
        workout: VoluntaryWorkout,
        roster: [Player],
        modelContext: ModelContext
    ) {
        let cfg = config(for: workout.type)
        workout.schemeBonus = cfg.schemeBonus
        workout.lockerRoomDelta = cfg.lrDelta
        workout.injuryRiskBoost = cfg.injuryRiskBoost

        // Apply scheme bonuses to attendees only. Use the workout's
        // participation pct as a probability filter per player.
        let participationProb = Double(workout.participationPct) / 100.0

        for player in roster {
            // Did this player attend?
            let attended = Double.random(in: 0.0..<1.0) < participationProb

            // Apply scheme bump only to attendees.
            if attended, cfg.schemeBonus > 0 {
                if let primary = player.schemeFamiliarity.max(by: { $0.value < $1.value })?.key {
                    let cur = player.schemeFamiliarity[primary] ?? 0
                    player.schemeFamiliarity[primary] = min(100, cur + cfg.schemeBonus)
                }
            }

            // Hidden fatigue accumulates on attendees from harder workouts.
            if attended, cfg.injuryRiskBoost > 0 {
                player.cumulativeLoad = min(200, player.cumulativeLoad + cfg.injuryRiskBoost * 2)
                player.workloadStatus = WorkloadEngine.classify(load: player.cumulativeLoad)
            }

            // Locker-room delta nudges morale slightly across whole roster (attendees + skippers).
            if cfg.lrDelta != 0 {
                player.morale = max(1, min(100, player.morale + cfg.lrDelta))
            }
        }
    }

    /// Type-specific configuration values pulled from the design brief.
    static func config(for type: VoluntaryWorkoutType) -> (schemeBonus: Int, lrDelta: Int, injuryRiskBoost: Int) {
        switch type {
        case .voluntaryOTAs:
            return (schemeBonus: 3, lrDelta: 2,  injuryRiskBoost: 0)
        case .mandatoryMinicamp:
            return (schemeBonus: 5, lrDelta: -5, injuryRiskBoost: 2)
        case .saturdayFilm:
            return (schemeBonus: 1, lrDelta: 0,  injuryRiskBoost: 0)
        case .offDayPractice:
            return (schemeBonus: 2, lrDelta: -3, injuryRiskBoost: 3)
        }
    }

    // MARK: - Private Helpers

    private static func personalityAttendanceDelta(_ archetype: PersonalityArchetype) -> Double {
        switch archetype {
        case .teamLeader, .mentor, .quietProfessional, .steadyPerformer:
            return 0.15
        case .fieryCompetitor:
            return 0.05
        case .feelPlayer, .classClown:
            return 0.0
        case .loneWolf:
            return -0.10
        case .dramaQueen:
            return -0.20
        }
    }
}
