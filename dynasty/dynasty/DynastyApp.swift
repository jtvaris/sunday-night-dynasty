import SwiftUI
import SwiftData

@main
struct DynastyApp: App {
    // R39: PerfLog.time also stamps `processStart` on first touch, so
    // launch_to_menu measures from here (app init) to the menu's first frame.
    let container = PerfLog.time("data_container_create") { DataContainer.create() }

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
