import Foundation
import SwiftData

/// One-generation copy of the save store, taken **before** a schema version bump
/// is allowed to touch it.
///
/// This is the piece that converts every migration failure from *save destroyed*
/// into *save recoverable* (`docs/SWIFTDATA_MIGRATION_PLAN.md` §3.5.5). The app
/// itself never restores from the copy — restoring is a support action, and doing
/// it automatically would risk overwriting a store that migrated fine — but the
/// bytes are there, next to the live store, for as long as they are needed.
///
/// Cost: the copy runs only on a launch where the schema version *changed*, so a
/// normal launch does no file I/O beyond one `UserDefaults` read.
enum StoreBackup {

    /// Version of the schema the store was last opened with, as `major.minor.patch`.
    /// Absent means "written by a build that predates versioning" (pre-#171).
    static let versionStampKey = "storeSchemaVersion"

    /// Suffix on the backup set: `default.store.backup-v0` + `-wal` / `-shm`.
    private static func backupURL(for url: URL, versionTag: String) -> URL {
        url.appendingPathExtension("backup-v\(versionTag)")
    }

    /// The three files SwiftData's SQLite store is made of. Copied as a set —
    /// a `.store` without its `-wal` is not the same database.
    private static func fileSet(_ url: URL) -> [URL] {
        [url,
         URL(fileURLWithPath: url.path + "-wal"),
         URL(fileURLWithPath: url.path + "-shm")]
    }

    /// Deletes every backup set next to `storeURL`.
    ///
    /// Called by "Delete All Save Data" (#201b). Without this the button would
    /// keep its own counter-example on disk: a byte-for-byte copy of the careers
    /// it just promised to remove, sitting beside the emptied store until the
    /// next schema bump overwrote it.
    ///
    /// - Returns: the file names removed (diagnostics only).
    ///
    /// Refuses while the app is running degraded. That guard lives HERE rather
    /// than at the call site because the rule is a property of the backups, not
    /// of one button: when the on-disk store could not be opened, these copies
    /// are the only readable version of the user's careers, and a wipe would
    /// take the recovery copy while leaving the careers it never reached.
    @discardableResult
    static func purgeAll(storeURL: URL) -> [String] {
        guard !StoreOpenFailure.isDegraded else {
            print("[StoreBackup] purgeAll REFUSED: the store failed to open this launch, "
                  + "so these copies are the only readable save data left. Nothing removed.")
            return []
        }

        let fm = FileManager.default
        let directory = storeURL.deletingLastPathComponent()
        let prefix = storeURL.lastPathComponent + ".backup-"
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { return [] }

        var removed: [String] = []
        for name in names where name.hasPrefix(prefix) {
            do {
                try fm.removeItem(at: directory.appendingPathComponent(name))
                removed.append(name)
            } catch {
                print("[StoreBackup] FAILED to remove \(name): \(error)")
            }
        }
        print("[StoreBackup] purgeAll: "
              + (removed.isEmpty ? "no backups on disk" : "removed \(removed.joined(separator: ", "))"))
        return removed
    }

    /// Writes the stamp without copying anything — "the store on disk is at
    /// `version`, no backup needed".
    ///
    /// "Delete All Save Data" wipes the whole `UserDefaults` domain, and the
    /// stamp lives in that domain. Left wiped, the NEXT launch reads
    /// "unversioned", concludes the schema moved, and copies the store the user
    /// just emptied into a fresh `default.store.backup-v0` set — a backup file
    /// reappearing immediately after a full wipe (observed in the #171 fixture
    /// run's `launch-after-delete` log). Re-stamping after the wipe keeps the
    /// stamp honest.
    static func stampCurrentVersion(_ version: Schema.Version) {
        UserDefaults.standard.set(version.dotted, forKey: versionStampKey)
    }

    /// Copies the store aside when the binary's schema version differs from the
    /// one that last opened it, then records the new stamp.
    ///
    /// The stamp is written **before** the open on purpose: if the open then
    /// fails, the next launch must not take a second backup and overwrite the
    /// good copy with the same (possibly half-migrated) store.
    ///
    /// - Parameters:
    ///   - storeURL: the live store. Nothing happens if it does not exist yet
    ///     (a first run has nothing to protect).
    ///   - version: the version the binary was compiled against.
    static func backupIfSchemaVersionChanged(storeURL: URL, version: Schema.Version) {
        let defaults = UserDefaults.standard
        let newStamp = version.dotted
        let oldStamp = defaults.string(forKey: versionStampKey)

        guard oldStamp != newStamp else { return }

        let fm = FileManager.default
        guard fm.fileExists(atPath: storeURL.path) else {
            // Nothing on disk yet: stamp and move on.
            defaults.set(newStamp, forKey: versionStampKey)
            print("[StoreBackup] no existing store — stamping schema v\(newStamp)")
            return
        }

        // `nil` means the store was written before schema versioning existed.
        let leavingTag = (oldStamp ?? "0").replacingOccurrences(of: ".", with: "_")
        let target = backupURL(for: storeURL, versionTag: leavingTag)

        // One generation: drop the previous copy of the same tag first.
        for url in fileSet(target) where fm.fileExists(atPath: url.path) {
            try? fm.removeItem(at: url)
        }

        var copied: [String] = []
        for src in fileSet(storeURL) where fm.fileExists(atPath: src.path) {
            let dst = URL(fileURLWithPath: target.path + String(src.path.dropFirst(storeURL.path.count)))
            do {
                try fm.copyItem(at: src, to: dst)
                copied.append(dst.lastPathComponent)
            } catch {
                // A failed backup must not stop the app from launching — the
                // store is still untouched at this point. Say so and continue.
                print("[StoreBackup] FAILED to copy \(src.lastPathComponent): \(error)")
            }
        }

        defaults.set(newStamp, forKey: versionStampKey)
        print("[StoreBackup] schema v\(oldStamp ?? "unversioned") -> v\(newStamp): "
              + (copied.isEmpty ? "no files copied" : "backed up \(copied.joined(separator: ", "))"))
    }
}
