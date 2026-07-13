import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        NavigationStack {
            MainMenuView()
        }
        .preferredColorScheme(.dark)
        #if DEBUG
        // R39 perf harness — runs ONLY when the matching env var is set
        // (e.g. `SIMCTL_CHILD_PERF_SMOKE_SEASONS=3 simctl launch --console-pty …`).
        // Never executes in a normal user launch; compiled out of Release.
        .task {
            let env = ProcessInfo.processInfo.environment
            if let seasons = env["PERF_SMOKE_SEASONS"].flatMap(Int.init) {
                try? await Task.sleep(for: .seconds(1))   // let first frame settle
                MultiSeasonSmokeTest.run(seasons: seasons)
            }
            if let games = env["PERF_DEBUG_SIM"].flatMap(Int.init) {
                try? await Task.sleep(for: .seconds(1))
                GameSimulator.debugSimulate(n: games)
            }
        }
        #endif
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Career.self, inMemory: true)
}
