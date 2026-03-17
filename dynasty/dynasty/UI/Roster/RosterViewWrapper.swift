import SwiftUI
import SwiftData

/// Fetches the team's players from the model context and passes them to `RosterView`.
struct RosterViewWrapper: View {
    let career: Career
    @Environment(\.modelContext) private var modelContext
    @State private var players: [Player] = []

    var body: some View {
        RosterView(players: players)
            .task {
                guard let teamID = career.teamID else { return }
                let descriptor = FetchDescriptor<Player>(
                    predicate: #Predicate { $0.teamID == teamID }
                )
                players = (try? modelContext.fetch(descriptor)) ?? []
            }
    }
}
