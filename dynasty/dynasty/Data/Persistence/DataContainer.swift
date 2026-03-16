import SwiftData
import Foundation

enum DataContainer {
    static func create() -> ModelContainer {
        let schema = Schema([
            Career.self,
            League.self,
            Team.self,
            Player.self,
            Owner.self,
            Coach.self,
            Season.self,
            Game.self,
            Schedule.self,
            Contract.self,
            Scout.self,
            CollegeProspect.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
}
