import Foundation

// MARK: - Aged manifest

/// One aged variant: an id of its own, the file it *would* live at, the bucket
/// it was painted into, and the main-pool id it ages.
///
/// A parallel type rather than a reuse of `FaceEntry` because of the one field
/// that matters here — `source`. Everything downstream of this catalog is a
/// lookup *from* a source id, so the link has to be decoded, not inferred; the
/// id prefix is only the fallback for a build whose manifest is absent.
struct AgedFaceEntry: Codable, Hashable {
    let id: String
    let file: String
    let bucket: FaceBucket
    let source: String
}

/// Decoded `aged_faces_manifest.json` — the schema `tools/faces/generate_aged.py`
/// writes: `{version, faces: [{id, file, bucket, source}]}`.
///
/// `version` is optional and unknown keys are ignored, so a manifest written by
/// a newer generator still decodes (same contract as `ExtrasManifest`).
struct AgedFacesManifest: Codable {
    let version: Int?
    let faces: [AgedFaceEntry]
}

// MARK: - AgedFaceCatalog

/// The face library's **"same person, later"** layer.
///
/// The main pool paints everyone once, at the age his bucket says: a player
/// drawn into the `25-29` band is still wearing that portrait at 35, and a head
/// coach hired at 46 is 64 with no gray in him. A career runs 20+ seasons, so
/// that mismatch is not an edge case — it is where every long save ends up.
///
/// This catalog holds at most ONE older variant per source id
/// (`aged_face_00042` ages `face_00042`) and `PersonFaceView` swaps to it once
/// the person crosses `playerAgeThreshold` / `coachAgeThreshold`. One step, not
/// a per-year progression: two portraits per person is the cheapest thing that
/// removes the "my 64-year-old head coach looks 45" reading, and each extra step
/// costs another image for every id in the pool.
///
/// ## Manifest-only, and absent by default
///
/// Same shape as `ExtrasCatalog` and for the same reason: there is nothing to
/// predict here. A variant's existence is a fact about which images were
/// generated, not a draw, so there is no RNG to keep bit-identical with Python
/// and no synthesis fallback. An absent or undecodable manifest degrades to
/// **nil for every lookup**, which renders exactly what the app rendered before
/// this layer existed — the un-aged portrait.
///
/// The full pass has since shipped — one variant for every id in the pool,
/// packaged into `Resources/Faces/` alongside the main pool — but nothing in
/// this file assumes it: a build made from a tree without those HEICs, or with
/// a partial manifest, renders un-aged portraits and nothing else changes.
/// `FaceBundleAudit` prints `agedImages=`/`coverage=` so a partial pass is
/// visible rather than merely quiet. See `docs/FACE_AGE_VARIANTS.md` for the
/// technique and its measured identity ceiling.
///
/// ## Threading
///
/// Loaded once, lazily, behind a lock, then read-only — same shape as
/// `ExtrasCatalog`.
final class AgedFaceCatalog {

    static let shared = AgedFaceCatalog()

    /// Bundle resource name of the packaged aged manifest.
    static let manifestResource = "aged_faces_manifest"

    /// Id prefix. `aged_face_00042` is the variant of `face_00042`, so a source
    /// id is recoverable from a variant id by string alone — which is what lets
    /// `isAgedID` work in a build whose manifest failed to load.
    private static let prefix = "aged_"

    /// A **player** wears his aged portrait from this age on.
    ///
    /// 34 because that is where the player bands run out: the oldest one is
    /// `30-36`, the calibrated league keeps ~2.8 % of players at 33+, and a
    /// 34-year-old in this game is a decade past the `20-24` portrait most of
    /// them are still wearing. Deliberately not 30 — the `30-36` band already
    /// covers the early thirties, and a threshold there would re-age faces that
    /// are already the right age.
    static let playerAgeThreshold = 34

    /// A **coach** wears his aged portrait from this age on. The coach bands top
    /// out at `50-68`, so 62 is the point where the un-aged portrait starts
    /// contradicting the number on the staff screen rather than merely sitting
    /// at the young end of its band.
    static let coachAgeThreshold = 62

    private let lock = NSRecursiveLock()
    private var loaded = false

    /// source id -> aged id. `nil` (not empty) when the manifest is absent, so
    /// "the feature did not ship" and "the feature shipped with no variants" stay
    /// distinguishable in the audit.
    private var agedBySource: [String: String]?
    private var entriesByID: [String: AgedFaceEntry] = [:]

    private init() {}

    // MARK: - Loading

    /// Loads the manifest once. Safe to call from anywhere, any number of times.
    func ensureLoaded() {
        lock.lock()
        defer { lock.unlock() }
        guard !loaded else { return }
        loaded = true

        guard let manifest = Self.load(), !manifest.faces.isEmpty else { return }
        // Last writer would win on a duplicated source; first wins instead, so a
        // hand-merged manifest cannot silently change which variant a person
        // already saw. Same `uniquingKeysWith` discipline as `ExtrasCatalog`.
        agedBySource = Dictionary(manifest.faces.map { ($0.source, $0.id) },
                                  uniquingKeysWith: { first, _ in first })
        entriesByID = Dictionary(manifest.faces.map { ($0.id, $0) },
                                 uniquingKeysWith: { first, _ in first })
    }

    /// Where `aged_faces_manifest.json` resolves in the bundle, or `nil` when the
    /// aged variants have not shipped.
    ///
    /// Both arms are load-bearing for the reason `ExtrasCatalog.manifestURL`
    /// documents: the Xcode project is a filesystem-synchronized root group and
    /// FLATTENS `Resources/Faces/` into the bundle root.
    static func manifestURL() -> URL? {
        Bundle.main.url(forResource: manifestResource, withExtension: "json")
            ?? Bundle.main.url(
                forResource: manifestResource, withExtension: "json",
                subdirectory: FaceGeneratorConstants.facesFolder
            )
    }

    private static func load() -> AgedFacesManifest? {
        guard let url = manifestURL(), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AgedFacesManifest.self, from: data)
    }

    // MARK: - Lookup

    /// Whether any aged variant shipped. `false` means every portrait resolves
    /// exactly as it did before this layer existed.
    var isAvailable: Bool {
        ensureLoaded()
        lock.lock()
        defer { lock.unlock() }
        return agedBySource != nil
    }

    /// Ids in the manifest — what `FaceBundleAudit` needs to count them.
    var entries: [AgedFaceEntry] {
        ensureLoaded()
        lock.lock()
        defer { lock.unlock() }
        return Array(entriesByID.values)
    }

    /// The aged variant of a source id, or `nil` when none was generated.
    func agedID(for sourceID: String) -> String? {
        ensureLoaded()
        lock.lock()
        defer { lock.unlock() }
        return agedBySource?[sourceID]
    }

    /// Whether an id names an aged variant, by PREFIX — independent of whether
    /// the manifest loaded, for the reason `ExtrasCatalog.isAvatarID` documents.
    static func isAgedID(_ id: String) -> Bool { id.hasPrefix(prefix) }

    // MARK: - Resolution

    /// The portrait id to render for a person: the aged variant once `age` has
    /// crossed `threshold` and a variant exists, otherwise the id handed in.
    ///
    /// Every arm falls back to `faceID` rather than to nil. A person past the
    /// threshold whose face has no variant — the normal case while the aged pass
    /// is partial — must keep his ordinary portrait; taking it away would trade a
    /// slightly-too-young photograph for no photograph at all.
    ///
    /// Idempotent on an id that is already aged, so nothing breaks if a caller
    /// hands back a resolved id (a saved `faceID` never is one — the swap is a
    /// render-time decision and is never written to the model).
    func resolve(faceID: String?, age: Int, threshold: Int) -> String? {
        guard let faceID, !faceID.isEmpty else { return faceID }
        guard age >= threshold, !Self.isAgedID(faceID) else { return faceID }
        return agedID(for: faceID) ?? faceID
    }

    /// `resolve` with the player threshold.
    func resolveForPlayer(faceID: String?, age: Int) -> String? {
        resolve(faceID: faceID, age: age, threshold: Self.playerAgeThreshold)
    }

    /// `resolve` with the coach threshold. Also the owner/staff path: everyone
    /// whose portrait came out of the coach half of the pool ages on the coach
    /// clock, because that is the clock their source bucket was painted on.
    func resolveForCoach(faceID: String?, age: Int) -> String? {
        resolve(faceID: faceID, age: age, threshold: Self.coachAgeThreshold)
    }
}
