import SwiftUI
import SwiftData

@main
struct DynastyApp: App {
    let container = DataContainer.create()

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, newPhase in
            // Flush pending changes when the app leaves the foreground so a
            // force-quit can't drop edits that autosave hasn't written yet.
            if newPhase == .background || newPhase == .inactive {
                try? container.mainContext.save()
            }
        }
    }
}
