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
            // Phase-4 stage-4: did the packaged face library actually ship, and
            // does the code find it where the build put it? (`FACE_BUNDLE_AUDIT=1`).
            // Runs BEFORE the template validation so the catalog source is
            // reported before anything has assigned a face.
            if env["FACE_BUNDLE_AUDIT"] != nil {
                try? await Task.sleep(for: .seconds(1))
                FaceBundleAudit.run()
            }
            // Phase-3 stage-4: determinism + ordering checks on a baked league
            // template, plus the phase-4 face-uniqueness sweep
            // (`LEAGUE_TEMPLATE_VALIDATE=publish|dev`).
            if let profileName = env["LEAGUE_TEMPLATE_VALIDATE"] {
                try? await Task.sleep(for: .seconds(1))
                LeagueTemplateValidation.run(profileNamed: profileName)
            }
            if let seasons = env["PERF_SMOKE_SEASONS"].flatMap(Int.init) {
                try? await Task.sleep(for: .seconds(1))   // let first frame settle
                // `PERF_SMOKE_LEAGUE` selects the league source: omit (or
                // "generated") for the classic random roll, "fixed2026" /
                // "fixed2026Dev" to run the smoke test on an imported template.
                let source = env["PERF_SMOKE_LEAGUE"].flatMap(LeagueSource.init(rawValue:)) ?? .generated
                MultiSeasonSmokeTest.run(seasons: seasons, source: source)
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
