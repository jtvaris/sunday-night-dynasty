import SwiftData
import Foundation

/// Opens the one on-disk SwiftData store the app has.
///
/// The model list and the save-format history live in `DynastySchema.swift`;
/// the policy a schema change has to obey is `docs/SWIFTDATA_MIGRATION_PLAN.md`
/// §3.4 / §4. Read §4 before editing any `@Model`.
enum DataContainer {

    /// The schema the binary was compiled against — always the NEWEST version.
    static var currentSchema: Schema { Schema(versionedSchema: DynastySchemaV1.self) }

    /// The version stamp that goes with `currentSchema`.
    static var currentVersion: Schema.Version { DynastySchemaV1.versionIdentifier }

    /// Where the on-disk store lives. `ModelConfiguration` resolves SwiftData's
    /// default path (`Application Support/default.store`) without opening
    /// anything, which is what lets `StoreBackup` copy the file aside *before*
    /// the migration runs.
    static var storeURL: URL { ModelConfiguration(isStoredInMemoryOnly: false).url }

    static func create() -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: false)

        // Insurance first: if this binary's schema version differs from the one
        // that last opened the store, copy the store aside before SwiftData is
        // allowed to migrate it. A no-op on every normal launch.
        StoreBackup.backupIfSchemaVersionChanged(storeURL: config.url, version: currentVersion)

        do {
            let container = try ModelContainer(
                for: currentSchema,
                migrationPlan: DynastyMigrationPlan.self,
                configurations: [config]
            )
            print("[Store] opened \(config.url.lastPathComponent) at schema v\(currentVersion.dotted)")
            // A failure recorded by an earlier launch has now been survived.
            StoreOpenFailure.drainPendingBreadcrumb()
            return container
        } catch {
            // NOT `fatalError`. The app has to reach a frame so it can say what
            // happened, and it must not delete or rewrite anything on disk —
            // `docs/SWIFTDATA_MIGRATION_PLAN.md` §3.5.
            StoreOpenFailure.record(error, storeURL: config.url, schemaVersion: currentVersion)
            return degradedInMemoryContainer()
        }
    }

    /// A throwaway container over the FULL schema, for previews and harnesses.
    ///
    /// Same schema as the real store, so a preview that fetches or deletes any
    /// model type behaves like the app instead of tripping over a type the
    /// container was never told about. Nothing reaches disk.
    static func inMemory() -> ModelContainer {
        degradedInMemoryContainer()
    }

    /// Last resort: an EMPTY in-memory store built from the schema this binary
    /// was compiled against. It cannot fail for migration reasons — there is no
    /// store on disk to disagree with it — so the force-try here is honest.
    ///
    /// The session is read-write but throwaway: nothing reaches disk, and the
    /// user's real store is left untouched for a later build (or a support
    /// step) to recover. `StoreOpenFailure.isDegraded` is the flag a recovery
    /// screen keys off.
    private static func degradedInMemoryContainer() -> ModelContainer {
        // swiftlint:disable:next force_try
        try! ModelContainer(
            for: currentSchema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }
}
