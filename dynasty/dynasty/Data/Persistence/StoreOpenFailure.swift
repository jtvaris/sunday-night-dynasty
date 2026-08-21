import Foundation
import SwiftData

/// What happened when the save store could not be opened, and the breadcrumb
/// that survives to the next launch.
///
/// Before #171 a failed open was a `fatalError` inside `DataContainer.create()`
/// (`docs/SWIFTDATA_MIGRATION_PLAN.md` §1.3): the app died before the first
/// frame, before `CrashReportStore.shared.start()` had subscribed to MetricKit,
/// with no diagnostic surface and no recovery path except "delete the app" —
/// which destroys exactly the save the whole task exists to protect.
///
/// The replacement, per plan §3.5, is: boot anyway on a degraded in-memory
/// container, record what happened here, and **delete nothing**. There is no
/// "reset store" button: a tester who taps Reset at 1am has destroyed both the
/// evidence and the save.
///
/// Nothing on disk is touched by a recorded failure. The store file, its `-wal`
/// and its `-shm` are left exactly as they were found, and `StoreBackup` has
/// already put a copy aside if the schema version moved.
enum StoreOpenFailure {

    // MARK: - Breadcrumbs

    /// A failure recorded on **this** launch, waiting to be reported.
    ///
    /// Written in the `catch` around the container open, which runs before
    /// `CrashReportStore.shared.start()` (`DynastyApp.swift`: the container is a
    /// stored-property initializer, `start()` is in `init()`'s body), so it
    /// cannot go through MetricKit. `UserDefaults` is the one sink that is
    /// guaranteed to be available that early.
    static let pendingKey = "storeOpenFailure.pending"

    /// The last failure that was survived: moved here by the next successful
    /// open, so a crash-report / support surface can still find it after the
    /// store came back. One generation.
    static let lastResolvedKey = "storeOpenFailure.lastResolved"

    // MARK: - In-process state

    /// Set once per launch when the on-disk store could not be opened. A UI
    /// recovery screen reads this to say "Your saved careers could not be
    /// opened" instead of showing an empty main menu that looks like data loss.
    ///
    /// Read-only from outside; only `record` writes it.
    private(set) nonisolated(unsafe) static var current: Report?

    /// True when the app is running on the degraded in-memory container, i.e.
    /// nothing the user does this session will be saved.
    static var isDegraded: Bool { current != nil }

    struct Report {
        /// The `NSError` / SwiftData error, stringified at the moment it was
        /// thrown — the only copy of the diagnosis.
        let message: String
        /// Schema version the binary was compiled against.
        let schemaVersion: String
        /// The store the open was attempted against.
        let storePath: String
        let date: Date

        /// One block of text a tester can copy out of a support screen.
        var diagnostics: String {
            """
            Dynasty store open failure
            when:   \(ISO8601DateFormatter().string(from: date))
            schema: \(schemaVersion)
            store:  \(storePath)
            error:  \(message)
            """
        }
    }

    // MARK: - Recording

    /// Records a failed open. Never throws, never deletes, never blocks.
    static func record(_ error: Error, storeURL: URL?, schemaVersion: Schema.Version) {
        let report = Report(
            message: String(describing: error),
            schemaVersion: schemaVersion.dotted,
            storePath: storeURL?.path ?? "(unknown)",
            date: Date()
        )
        current = report

        // Breadcrumb for the next launch: MetricKit is not subscribed yet, so
        // this is the only record that survives the session.
        UserDefaults.standard.set(report.diagnostics, forKey: pendingKey)

        print("[Store] OPEN FAILED — running on a degraded in-memory container. "
              + "Nothing on disk was modified or deleted.")
        print(report.diagnostics)
    }

    /// Called after a **successful** open. Moves any breadcrumb from a previous
    /// launch out of `pending` and logs it, so a failure that has since been
    /// survived is visible in the console and still readable from defaults.
    ///
    /// - Returns: the breadcrumb text, if there was one.
    @discardableResult
    static func drainPendingBreadcrumb() -> String? {
        let defaults = UserDefaults.standard
        guard let pending = defaults.string(forKey: pendingKey) else { return nil }
        defaults.removeObject(forKey: pendingKey)
        defaults.set(pending, forKey: lastResolvedKey)
        print("[Store] a previous launch failed to open the store; it opened cleanly this time:")
        print(pending)
        return pending
    }
}
