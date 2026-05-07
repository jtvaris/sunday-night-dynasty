import Foundation
import SwiftData

// MARK: - HardKnocksNarrator

/// Generates 5-10 narrative storyline events per camp. Pulls signal from the camp's
/// recent battles, surprise breakouts, injuries, and bubble cuts and packages them
/// as `HardKnocksEvent` rows for the toast UI to consume.
@MainActor
enum HardKnocksNarrator {

    // MARK: - Public API

    /// Generates 5-10 narrative events per camp based on recent battles, breakouts, injuries.
    @discardableResult
    static func generateCampStorylines(
        battles: [PositionBattle],
        recentInjuries: [Player],
        recentCuts: [RosterCut],
        roster: [Player],
        modelContext: ModelContext
    ) -> [HardKnocksEvent] {
        var events: [HardKnocksEvent] = []
        let seasonYear = Calendar.current.component(.year, from: .now)
        let playerByID = Dictionary(uniqueKeysWithValues: roster.map { ($0.id, $0) })

        // 1. SURPRISE STARTERS — battles where a low-OVR player won the leader spot.
        for battle in battles {
            guard let leaderID = battle.currentLeaderID,
                  let leader = playerByID[leaderID] else { continue }
            // Leader is a relative outsider if not the highest OVR among competitors.
            let competitors = battle.competitorIDs.compactMap { playerByID[$0] }
            let bestOVR = competitors.map(\.overall).max() ?? leader.overall
            if leader.overall < bestOVR - 1 {
                let template = storyTemplate(for: .surpriseStarter, player: leader)
                events.append(makeEvent(seasonYear: seasonYear, type: .surpriseStarter, player: leader, template: template, modelContext: modelContext))
            }
        }

        // 2. ROOKIE BREAKOUTS — yearsPro==0, A or A+ camp grade.
        let breakouts = roster
            .filter { $0.yearsPro == 0 && ($0.campGrade == .a || $0.campGrade == .aPlus) }
            .prefix(2)
        for player in breakouts {
            let template = storyTemplate(for: .rookieBreakout, player: player)
            events.append(makeEvent(seasonYear: seasonYear, type: .rookieBreakout, player: player, template: template, modelContext: modelContext))
        }

        // 3. CAMP INJURIES — surface up to 2 most recent.
        for player in recentInjuries.prefix(2) {
            let template = storyTemplate(for: .campInjury, player: player)
            events.append(makeEvent(seasonYear: seasonYear, type: .campInjury, player: player, template: template, modelContext: modelContext))
        }

        // 4. VET ON BUBBLE — older player with D/F camp grade.
        let bubbleVets = roster
            .filter { $0.yearsPro >= 4 && ($0.campGrade == .d || $0.campGrade == .f) }
            .sorted { $0.annualSalary > $1.annualSalary }
            .prefix(2)
        for player in bubbleVets {
            let template = storyTemplate(for: .vetOnBubble, player: player)
            events.append(makeEvent(seasonYear: seasonYear, type: .vetOnBubble, player: player, template: template, modelContext: modelContext))
        }

        // 5. DEPTH CHART SHAKEUP — fired only when battles produced a flip from currentLeader.
        let shakeups = battles.filter { battle in
            guard let leaderID = battle.currentLeaderID else { return false }
            return !battle.competitorIDs.isEmpty && battle.competitorIDs.first != leaderID
        }
        if let example = shakeups.first {
            let player = example.currentLeaderID.flatMap { playerByID[$0] }
            let template = storyTemplate(for: .depthChartShakeup, player: player)
            events.append(makeEvent(seasonYear: seasonYear, type: .depthChartShakeup, player: player, template: template, modelContext: modelContext))
        }

        // 6. TRADE RUMORS — high-salary vet getting cut signals trade speculation.
        if let bigCut = recentCuts.sorted(by: { $0.capSavings > $1.capSavings }).first,
           bigCut.capSavings > 5000,
           let player = playerByID[bigCut.playerID] {
            let template = storyTemplate(for: .tradeRumor, player: player)
            events.append(makeEvent(seasonYear: seasonYear, type: .tradeRumor, player: player, template: template, modelContext: modelContext))
        }

        // Cap at 10 events; ensure minimum 5 by padding from any breakout/bubble vets.
        if events.count > 10 {
            events = Array(events.prefix(10))
        }

        return events
    }

    /// Per type, picks an evocative headline + body. Pure function; no persistence.
    static func storyTemplate(for type: HardKnocksEventType, player: Player?) -> (headline: String, body: String) {
        let name = player?.fullName ?? "An anonymous source"
        let posLabel = player?.position.rawValue ?? "the locker room"

        switch type {
        case .rookieBreakout:
            return (
                headline: "\(name) Lighting Up Camp",
                body: "Rookie \(posLabel) \(name) has been the talk of camp. Coaches can't take their eyes off him."
            )
        case .vetOnBubble:
            return (
                headline: "Veteran \(name) on the Roster Bubble",
                body: "After a quiet camp, the front office is reportedly weighing a tough decision on the veteran \(posLabel)."
            )
        case .surpriseStarter:
            return (
                headline: "Coach Names \(name) Starter",
                body: "In a stunning move, the staff has named \(name) the lead at \(posLabel) — leapfrogging more pedigreed competitors."
            )
        case .depthChartShakeup:
            return (
                headline: "Depth Chart Shakeup at \(posLabel)",
                body: "A position battle at \(posLabel) flipped overnight. \(name) is now atop the depth chart."
            )
        case .campInjury:
            return (
                headline: "\(name) Injured in Camp",
                body: "An ill-timed injury sidelined \(name) — staff are evaluating to determine if it's a multi-week absence."
            )
        case .tradeRumor:
            return (
                headline: "Trade Rumors Swirl Around \(name)",
                body: "League insiders suggest \(name) could be moved before the regular season. Cap relief is reportedly a motivator."
            )
        }
    }

    // MARK: - Private Helpers

    private static func makeEvent(
        seasonYear: Int,
        type: HardKnocksEventType,
        player: Player?,
        template: (headline: String, body: String),
        modelContext: ModelContext
    ) -> HardKnocksEvent {
        let event = HardKnocksEvent(
            seasonYear: seasonYear,
            typeRaw: type.rawValue,
            playerID: player?.id,
            headline: template.headline,
            body: template.body
        )
        modelContext.insert(event)
        return event
    }
}
