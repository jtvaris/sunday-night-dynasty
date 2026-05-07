import Foundation
import SwiftData

/// Tracks free-agent visits to team facilities. Enforces the visit-rhythm rules
/// from the FA Drama design brief (A3):
///
/// - Max 1 visit / day per team
/// - Max 3 visits / week per team
/// - Visit duration: 24h (default) or 48h (set on schedule)
/// - Visit blocks competing offers (other teams see "VISITING" tag)
@MainActor
enum VisitTracker {

    /// Default visit duration in hours.
    static let defaultDurationHours: Int = 24
    /// Maximum visits per week per team.
    static let weeklyVisitLimit: Int = 3

    /// Schedules a visit for `playerID` to `teamID`. Returns the persisted visit
    /// or `nil` if the visit is blocked by one of:
    ///   - team already booked another visit today
    ///   - team has hit the 3-visits/week ceiling
    ///   - player is already on an active visit (with another team or this team)
    @discardableResult
    static func scheduleVisit(
        playerID: UUID,
        teamID: UUID,
        currentDay: Int,
        existingVisits: [FAVisit],
        modelContext: ModelContext,
        durationHours: Int = defaultDurationHours,
        seasonYear: Int = Calendar.current.component(.year, from: Date())
    ) -> FAVisit? {
        let now = Date()

        // 1) Player must not be on any active visit
        if activeVisit(playerID: playerID, in: existingVisits) != nil {
            return nil
        }

        // 2) Team must not already have a visit started today (rolling 24h window)
        let oneDayAgo = now.addingTimeInterval(-24 * 60 * 60)
        let teamVisitsToday = existingVisits.filter {
            $0.teamID == teamID && $0.startedAt >= oneDayAgo
        }
        if !teamVisitsToday.isEmpty { return nil }

        // 3) Team must not have already used its 3 weekly visits
        let oneWeekAgo = now.addingTimeInterval(-7 * 24 * 60 * 60)
        let teamVisitsThisWeek = existingVisits.filter {
            $0.teamID == teamID && $0.startedAt >= oneWeekAgo
        }
        if teamVisitsThisWeek.count >= weeklyVisitLimit { return nil }

        // Schedule
        let expires = now.addingTimeInterval(TimeInterval(durationHours) * 60 * 60)
        let visit = FAVisit(
            playerID: playerID,
            teamID: teamID,
            seasonYear: seasonYear,
            startedAt: now,
            expiresAt: expires,
            status: .active
        )
        modelContext.insert(visit)
        return visit
    }

    /// Returns the active visit (if any) for the player.
    static func activeVisit(playerID: UUID, in visits: [FAVisit]) -> FAVisit? {
        let now = Date()
        return visits.first {
            $0.playerID == playerID && $0.status == .active && $0.expiresAt > now
        }
    }

    /// Returns all teams that currently have an active visit with the player.
    /// Useful for the "VISITING" UI tag on competing teams' offer panels.
    static func teamsCurrentlyVisiting(playerID: UUID, in visits: [FAVisit]) -> [UUID] {
        let now = Date()
        return visits
            .filter { $0.playerID == playerID && $0.status == .active && $0.expiresAt > now }
            .map { $0.teamID }
    }

    /// How many visits the team has scheduled in the rolling last 7 days.
    static func teamWeeklyVisitCount(teamID: UUID, in visits: [FAVisit]) -> Int {
        let now = Date()
        let oneWeekAgo = now.addingTimeInterval(-7 * 24 * 60 * 60)
        return visits.filter { $0.teamID == teamID && $0.startedAt >= oneWeekAgo }.count
    }

    /// Auto-expires visits whose `expiresAt` has passed. Mutates the array in place.
    /// Visits flagged via `convertedPlayerIDs` (i.e., player signed during the visit)
    /// are marked `.converted` instead of `.expired`.
    static func tickClock(
        now: Date,
        visits: inout [FAVisit],
        convertedPlayerIDs: Set<UUID> = []
    ) {
        for visit in visits where visit.status == .active {
            guard visit.expiresAt <= now else { continue }
            if convertedPlayerIDs.contains(visit.playerID) {
                visit.status = .converted
            } else {
                visit.status = .expired
            }
        }
    }
}
