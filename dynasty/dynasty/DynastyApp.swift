import SwiftUI
import SwiftData

@main
struct DynastyApp: App {
    let container = DataContainer.create()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
