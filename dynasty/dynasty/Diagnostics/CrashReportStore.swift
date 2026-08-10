import Foundation
import MetricKit
import os.log

// MARK: - CrashReportStore (#172)
//
// Crash / hang / CPU-exception reporting with zero third-party code and zero
// network traffic. The system hands us MetricKit diagnostic payloads (usually
// once every 24h, and once shortly after launch for anything gathered while
// the app was dead); we persist each relevant payload's JSON to
//
//     Application Support/CrashReports/<kind>-<payload end timestamp>.json
//
// and keep only the newest `maxStoredReports` files. Nothing is uploaded and
// nothing is shown in the UI — a report is a file on disk that a developer can
// pull with the container, or that a future Settings screen can surface.
//
// Threading: MetricKit invokes subscriber callbacks on an unspecified
// background queue, so every filesystem touch is funnelled through one private
// serial queue. `start()` may be called from anywhere (it is called from the
// app's `init`), and is idempotent.
// `nonisolated` + `@unchecked Sendable`: the target defaults new types to
// `@MainActor`, but MetricKit calls its subscriber on a background queue, and
// all mutable state here (`isStarted`) is confined to `queue` — same pattern as
// `FaceImageCache`.
nonisolated final class CrashReportStore: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {

    /// Process-wide singleton — MetricKit keeps a weak reference to the
    /// subscriber, so the store has to outlive the call that registers it.
    static let shared = CrashReportStore()

    /// How many report files survive a prune. Oldest go first.
    private static let maxStoredReports = 20

    private static let directoryName = "CrashReports"

    private let queue = DispatchQueue(label: "com.brewcrow.dynasty.crash-reports")

    private let log = Logger(subsystem: "com.brewcrow.dynasty", category: "diagnostics")

    /// Guarded by `queue`; keeps a double `start()` from registering twice.
    private var isStarted = false

    /// UTC, filename-safe, and lexicographically sortable — the prune step
    /// relies on that last property to find the oldest files by name.
    /// Instance-level (not static) and only ever touched on `queue`, so the
    /// non-Sendable `DateFormatter` never escapes.
    private let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        return f
    }()

    private override init() { super.init() }

    // MARK: - Lifecycle

    /// Subscribes to MetricKit. Call once, as early in launch as possible, so
    /// payloads delivered right after a crashing session aren't missed.
    func start() {
        queue.async { [weak self] in
            guard let self, !self.isStarted else { return }
            self.isStarted = true
            // MetricKit registration is cheap; keep it on the main queue so we
            // don't depend on MXMetricManager's (undocumented) thread safety.
            DispatchQueue.main.async { MXMetricManager.shared.add(self) }

            #if DEBUG
            let count = self.storedReportURLsLocked().count
            self.log.debug("CrashReportStore: \(count, privacy: .public) stored report(s) on disk")
            print("DIAG|crash_reports_on_disk|\(count)")
            #endif
        }
    }

    // MARK: - MXMetricManagerSubscriber

    /// Performance metrics — not our business here, but the protocol asks for
    /// it and MetricKit will call it.
    func didReceive(_ payloads: [MXMetricPayload]) {
        // Intentionally empty: #172 only covers diagnostics.
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        // Snapshot everything we need off MetricKit's queue immediately, then
        // do the file I/O on our own serial queue.
        let pending: [(kind: String, date: Date, json: Data)] = payloads.compactMap { payload in
            guard let kind = Self.kindTag(for: payload) else { return nil }
            return (kind, payload.timeStampEnd, payload.jsonRepresentation())
        }
        guard !pending.isEmpty else { return }

        queue.async { [weak self] in
            guard let self else { return }
            for item in pending {
                self.writeLocked(kind: item.kind, date: item.date, json: item.json)
            }
            self.pruneLocked()
        }
    }

    // MARK: - Classification

    /// A short filename tag naming what the payload carries, or `nil` when the
    /// payload holds none of the three kinds we keep (e.g. disk-write-exception
    /// only). Order is severity-first so a mixed payload files under the worst
    /// thing in it.
    private static func kindTag(for payload: MXDiagnosticPayload) -> String? {
        if payload.crashDiagnostics?.isEmpty == false { return "crash" }
        if payload.hangDiagnostics?.isEmpty == false { return "hang" }
        if payload.cpuExceptionDiagnostics?.isEmpty == false { return "cpu" }
        return nil
    }

    // MARK: - Storage (all `…Locked` helpers must run on `queue`)

    /// `Application Support/CrashReports`, created on demand. `nil` when the
    /// directory can't be made — diagnostics must never be the thing that
    /// breaks a launch, so callers just skip the write.
    private func directoryLocked() -> URL? {
        let fm = FileManager.default
        guard let support = try? fm.url(for: .applicationSupportDirectory,
                                        in: .userDomainMask,
                                        appropriateFor: nil,
                                        create: true) else { return nil }
        var dir = support.appendingPathComponent(Self.directoryName, isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                // Crash reports are reproducible debris, not user data.
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                try? dir.setResourceValues(values)
            } catch {
                log.error("CrashReportStore: could not create directory — \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
        return dir
    }

    private func storedReportURLsLocked() -> [URL] {
        guard let dir = directoryLocked() else { return [] }
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return contents.filter { $0.pathExtension == "json" }
    }

    private func writeLocked(kind: String, date: Date, json: Data) {
        guard let dir = directoryLocked() else { return }
        let stamp = timestampFormatter.string(from: date)

        // Two payloads of the same kind can share a second; walk a suffix
        // rather than overwrite the earlier one.
        var url = dir.appendingPathComponent("\(kind)-\(stamp).json")
        var suffix = 1
        while FileManager.default.fileExists(atPath: url.path), suffix < 100 {
            url = dir.appendingPathComponent("\(kind)-\(stamp)-\(suffix).json")
            suffix += 1
        }

        do {
            try json.write(to: url, options: [.atomic])
            log.info("CrashReportStore: wrote \(url.lastPathComponent, privacy: .public)")
        } catch {
            log.error("CrashReportStore: write failed — \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Keeps the newest `maxStoredReports` files. Names start with a kind tag,
    /// so sorting has to key off the timestamp portion rather than the whole
    /// name — otherwise "crash-" would always outrank "hang-".
    private func pruneLocked() {
        let urls = storedReportURLsLocked()
        guard urls.count > Self.maxStoredReports else { return }

        let sorted = urls.sorted { lhs, rhs in
            Self.sortKey(for: lhs) > Self.sortKey(for: rhs)   // newest first
        }
        for url in sorted.dropFirst(Self.maxStoredReports) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// The timestamp (plus collision suffix) part of a report filename — i.e.
    /// everything after the first `-`. Lexicographic order on this string is
    /// chronological order, by construction of `timestampFormatter`.
    private static func sortKey(for url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        guard let dash = name.firstIndex(of: "-") else { return name }
        return String(name[name.index(after: dash)...])
    }
}
