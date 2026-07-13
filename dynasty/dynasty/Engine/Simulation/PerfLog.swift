import Foundation
import os.signpost

// MARK: - PerfLog (R39)
//
// Lightweight performance instrumentation. Every entry point compiles to a
// no-op in Release builds — the game ships with zero measurement overhead.
//
// In DEBUG builds each measurement prints a single greppable line:
//     PERF|<metric>|<milliseconds>
// readable via `xcrun simctl launch --console-pty <udid> com.brewcrow.dynasty`.
// Signposts are emitted too, so Instruments' os_signpost track shows the same
// intervals when a deeper dive is ever needed.
enum PerfLog {

    #if DEBUG
    /// First-touch timestamp — effectively "app init" (DynastyApp touches
    /// PerfLog before the SwiftData container is created).
    static let processStart = CFAbsoluteTimeGetCurrent()

    private static let signposter = OSSignposter(
        subsystem: "com.brewcrow.dynasty", category: "perf"
    )
    private static var marks: [String: CFAbsoluteTime] = [:]
    private static var emittedOnce: Set<String> = []
    #endif

    // MARK: One-shot marks

    /// Records a named start time (e.g. the tap that opens a screen).
    @inline(__always)
    static func mark(_ name: String) {
        #if DEBUG
        marks[name] = CFAbsoluteTimeGetCurrent()
        #endif
    }

    /// Prints the elapsed time since `mark(_:)` with the same name and clears
    /// the mark. Silent when the mark was never set (e.g. screen re-appear).
    @inline(__always)
    static func measure(_ metric: String, sinceMark name: String) {
        #if DEBUG
        guard let start = marks.removeValue(forKey: name) else { return }
        emit(metric, ms: (CFAbsoluteTimeGetCurrent() - start) * 1000)
        #endif
    }

    /// Prints the elapsed time since `mark(_:)` WITHOUT consuming the mark —
    /// for intermediate checkpoints along one measured journey.
    @inline(__always)
    static func lap(_ metric: String, sinceMark name: String) {
        #if DEBUG
        guard let start = marks[name] else { return }
        emit(metric, ms: (CFAbsoluteTimeGetCurrent() - start) * 1000)
        #endif
    }

    /// Prints the elapsed time since process start — only once per metric, so
    /// re-appearing views don't spam fake "launch" numbers.
    @inline(__always)
    static func measureLaunch(_ metric: String) {
        #if DEBUG
        guard !emittedOnce.contains(metric) else { return }
        emittedOnce.insert(metric)
        emit(metric, ms: (CFAbsoluteTimeGetCurrent() - processStart) * 1000)
        #endif
    }

    // MARK: Block timing

    /// Times a synchronous block and prints the result.
    @discardableResult
    @inline(__always)
    static func time<T>(_ metric: String, _ block: () throws -> T) rethrows -> T {
        #if DEBUG
        _ = processStart   // materialize the lazy static on first PerfLog use
        let state = signposter.beginInterval("perf", "\(metric)")
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            signposter.endInterval("perf", state)
            emit(metric, ms: (CFAbsoluteTimeGetCurrent() - start) * 1000)
        }
        return try block()
        #else
        return try block()
        #endif
    }

    #if DEBUG
    private static func emit(_ metric: String, ms: Double) {
        print(String(format: "PERF|%@|%.1f", metric, ms))
    }
    #endif

    // MARK: Lap timer (multi-section breakdown)

    /// Section-by-section breakdown of one long operation. DEBUG prints one
    /// line per lap plus a total; Release compiles to an empty struct.
    struct Lap {
        #if DEBUG
        private let name: String
        private let start: CFAbsoluteTime
        private var last: CFAbsoluteTime
        #endif

        init(_ name: String) {
            #if DEBUG
            self.name = name
            self.start = CFAbsoluteTimeGetCurrent()
            self.last = start
            #endif
        }

        /// Prints the time spent since the previous lap (or since init).
        mutating func lap(_ section: String) {
            #if DEBUG
            let now = CFAbsoluteTimeGetCurrent()
            PerfLog.emit("\(name).\(section)", ms: (now - last) * 1000)
            last = now
            #endif
        }

        /// Prints the total elapsed time since init.
        func finish() {
            #if DEBUG
            PerfLog.emit("\(name).TOTAL", ms: (CFAbsoluteTimeGetCurrent() - start) * 1000)
            #endif
        }
    }
}
