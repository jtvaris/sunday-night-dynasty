import SwiftUI
import SwiftData

/// Fetches the team's players from the model context and passes them to `RosterView`.
struct RosterViewWrapper: View {
    let career: Career
    @Environment(\.modelContext) private var modelContext
    @State private var players: [Player] = []
    @State private var teamSalaryCap: Int = 255_000

    var body: some View {
        RosterView(players: players, teamSalaryCap: teamSalaryCap)
            .task {
                guard let teamID = career.teamID else { return }
                let playerDescriptor = FetchDescriptor<Player>(
                    predicate: #Predicate { $0.teamID == teamID }
                )
                players = (try? modelContext.fetch(playerDescriptor)) ?? []

                // Fetch the team's dynamic salary cap
                let teamDescriptor = FetchDescriptor<Team>(
                    predicate: #Predicate { $0.id == teamID }
                )
                if let team = (try? modelContext.fetch(teamDescriptor))?.first {
                    teamSalaryCap = team.salaryCap
                }
            }
    }
}
