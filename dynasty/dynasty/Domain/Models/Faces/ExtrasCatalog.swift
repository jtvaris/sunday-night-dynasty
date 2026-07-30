import Foundation

// MARK: - Extras manifest

/// Decoded `extra_faces_manifest.json` — the schema `tools/faces/generate_extras.py`
/// writes: `{version, faces: [{id, file, bucket}]}`.
///
/// Deliberately reuses `FaceEntry`/`FaceBucket` rather than declaring a parallel
/// pair: the extras generator emits the SAME five bucket tags as the main pool
/// (only the vocabulary differs — `role` is `"avatar"`/`"owner"` and the owner
/// age bands run past a coach's), and reusing the type is what lets
/// `FaceImageCache` and `PersonFaceView` treat an extras id as an ordinary face
/// id with no special-casing downstream.
///
/// `version` is optional and unknown keys are ignored, so a manifest written by
/// a newer generator still decodes here (see `ExtrasCatalog.load`).
struct ExtrasManifest: Codable {
    let version: Int?
    let faces: [FaceEntry]
}

// MARK: - ExtrasCatalog

/// The AI-portrait **extras**: 20 coach-style headshots the user picks their own
/// persona from (`avatar_00000`…`avatar_00019`, 10 male + 10 female) and 96
/// executive portraits for league owners (`owner_00000`…`owner_00095`, ~15 %
/// female).
///
/// ## Manifest-only, by design
///
/// Unlike `FaceCatalog`, this catalog has **no synthesis fallback and no parity
/// port** of the generator's RNG. That is deliberate, not an omission:
///
/// * The main pool needs synthesis because assignment has to be settled for
///   3 584 ids *before the images exist* — a person is handed a face id at
///   creation and must keep it when the pictures land later. The extras ship the
///   other way round: the 116 images were generated, culled by hand and copied
///   into `Resources/Faces/` in one step, so the manifest and the HEICs arrive
///   together and there is nothing to predict.
/// * Nothing here draws a bucket at random either. An owner's portrait is a pure
///   function of its UUID (`ownerFaceID`) and the user's is whatever they tapped,
///   so there is no RNG to keep bit-identical with Python.
///
/// The consequence is that an absent manifest degrades to **nil**: the avatar
/// picker shows only the illustrated `coach_m*`/`coach_f*` set and owners keep
/// their illustrated `owner_m*` avatar. That is the same "no pictures yet is a
/// designed state, not a defect" contract the main pool has, one level up.
///
/// ## Threading
///
/// Loaded once, lazily, behind a lock, then read-only — same shape as
/// `FaceLibrary`'s catalog, and for the same reason (today every caller is
/// `MainActor`-isolated; the lock is insurance against a future background
/// generator).
final class ExtrasCatalog {

    static let shared = ExtrasCatalog()

    /// Bundle resource name of the packaged extras manifest.
    static let manifestResource = "extra_faces_manifest"

    /// `role` tag of a user-avatar portrait.
    static let avatarRole = "avatar"
    /// `role` tag of an owner portrait.
    static let ownerRole = "owner"

    /// Id prefixes. Used by the two prefix predicates below, which are the only
    /// classification a *rendering* path is allowed to depend on — a saved
    /// `Career.avatarID` has to be recognised as a photo even in a build whose
    /// manifest failed to load, or `PersonFaceView` would ask the asset catalog
    /// for `avatar_00007` and draw nothing at all.
    private static let avatarPrefix = "avatar_"
    private static let ownerPrefix = "owner_"

    private let lock = NSRecursiveLock()
    private var loaded = false

    /// `nil` when the manifest is absent or did not decode — the whole feature
    /// is then off (see the class note).
    private var entriesByID: [String: FaceEntry]?
    private var avatarEntries: [FaceEntry] = []
    private var ownerEntries: [FaceEntry] = []

    private init() {}

    // MARK: - Loading

    /// Loads the manifest once. Safe to call from anywhere, any number of times.
    func ensureLoaded() {
        lock.lock()
        defer { lock.unlock() }
        guard !loaded else { return }
        loaded = true

        guard let manifest = Self.load(), !manifest.faces.isEmpty else { return }
        let all = manifest.faces
        entriesByID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // Sorted by id so every downstream pick — the picker's grid order and
        // `ownerFaceID`'s linear probe — is reproducible across launches.
        avatarEntries = all.filter { $0.bucket.role == Self.avatarRole }.sorted { $0.id < $1.id }
        ownerEntries = all.filter { $0.bucket.role == Self.ownerRole }.sorted { $0.id < $1.id }
    }

    /// Where `extra_faces_manifest.json` resolves in the bundle, or `nil` when
    /// the extras have not shipped.
    ///
    /// Both arms are load-bearing for exactly the reason `FaceLibrary.manifestURL`
    /// documents: the Xcode project is a filesystem-synchronized root group and
    /// FLATTENS `Resources/Faces/` into the bundle root, so the root arm is the
    /// one that hits today and the subdirectory arm covers a future move to a
    /// real resource folder.
    static func manifestURL() -> URL? {
        Bundle.main.url(forResource: manifestResource, withExtension: "json")
            ?? Bundle.main.url(
                forResource: manifestResource, withExtension: "json",
                subdirectory: FaceGeneratorConstants.facesFolder
            )
    }

    private static func load() -> ExtrasManifest? {
        guard let url = manifestURL(), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ExtrasManifest.self, from: data)
    }

    // MARK: - Lookup

    /// Whether the extras shipped at all. `false` means every extras-backed
    /// surface falls back to what it showed before this feature existed.
    var isAvailable: Bool {
        ensureLoaded()
        lock.lock()
        defer { lock.unlock() }
        return entriesByID != nil
    }

    /// The manifest entry for an id, or `nil` for an unknown id / absent manifest.
    func entry(id: String) -> FaceEntry? {
        ensureLoaded()
        lock.lock()
        defer { lock.unlock() }
        return entriesByID?[id]
    }

    /// The 20 user-avatar portraits, id-sorted. Empty when the manifest is absent.
    var avatars: [FaceEntry] {
        ensureLoaded()
        lock.lock()
        defer { lock.unlock() }
        return avatarEntries
    }

    /// The 96 owner portraits, id-sorted. Empty when the manifest is absent.
    var owners: [FaceEntry] {
        ensureLoaded()
        lock.lock()
        defer { lock.unlock() }
        return ownerEntries
    }

    /// The user-avatar portraits of one gender, id-sorted — the two groups the
    /// picker shows under its existing "Male" / "Female" dividers.
    func avatars(gender: FacePersonGender) -> [FaceEntry] {
        avatars.filter { FacePersonGender(tag: $0.bucket.gender) == gender }
    }

    /// The owner portraits of one gender, id-sorted: 84 male, 12 female.
    ///
    /// Normalised through `FacePersonGender` rather than compared as raw strings
    /// for the reason that type documents — an unknown tag has to land on male
    /// rather than silently matching nothing, or one bad manifest row would take
    /// a portrait away from an owner instead of just mis-sorting it.
    func owners(gender: FacePersonGender) -> [FaceEntry] {
        owners.filter { FacePersonGender(tag: $0.bucket.gender) == gender }
    }

    // MARK: - Id classification

    /// Whether an id names a user-avatar portrait, by PREFIX — independent of
    /// whether the manifest loaded. See `avatarPrefix`.
    static func isAvatarID(_ id: String) -> Bool { id.hasPrefix(avatarPrefix) }

    /// Whether an id names an owner portrait, by PREFIX. Same contract as
    /// `isAvatarID`.
    static func isOwnerID(_ id: String) -> Bool { id.hasPrefix(ownerPrefix) }

    /// Whether an id belongs to the extras at all — the one predicate
    /// `FaceBundleAudit` needs to tell an extras HEIC from a main-pool one.
    static func isExtraID(_ id: String) -> Bool { isAvatarID(id) || isOwnerID(id) }

    // MARK: - Owner assignment

    /// The portrait for one owner: a deterministic pick from the 96 owner ids,
    /// skipped forward past anything already `taken`.
    ///
    /// Deliberately NOT routed through `FaceLibrary`. That class carries a claim
    /// registry and a retirement cooldown because its population *churns* — a
    /// league persists 224 draft picks a year and hands portraits back as people
    /// retire. Owners do neither: all 32 are created once, during league
    /// generation or template import, and no code path ever creates, retires or
    /// replaces one afterwards. So the only bookkeeping the assignment needs is
    /// the set of ids already handed out inside the same league, which the caller
    /// already has in hand (32 of 96 — a third of the pool, so a probe is short).
    ///
    /// - Parameters:
    ///   - ownerID: The owner's UUID. `FaceLibrary.stableHash` (FNV-1a over the
    ///     raw bytes) is used rather than `hashValue`, which is seeded per
    ///     process and would move the portrait on every launch.
    ///   - gender: Restricts the draw to that gender's portraits, and the probe
    ///     never leaves them. Gender-strict, exactly like the coach half of
    ///     `FaceLibrary`: handing a female owner a male photograph is a visible
    ///     defect, so an exhausted female pool degrades to `nil` — the
    ///     illustrated `owner_f*` avatar — rather than crossing over. There are
    ///     12 female ids against at most a handful of female owners in a league,
    ///     so the fallback is theory, not a case anybody meets.
    ///   - taken: Ids already assigned in this league. Collisions resolve by
    ///     linear probing forward over the id-sorted list, so the result stays a
    ///     pure function of (ownerID, gender, taken) — no RNG, no ordering
    ///     surprises. Shared across both genders because the two id sets are
    ///     disjoint anyway; one set keeps the caller's bookkeeping to one line.
    /// - Returns: `nil` only when the extras did not ship or every id of that
    ///   gender is taken (impossible at 32 owners against 84 + 12 ids, but
    ///   handled rather than trapped).
    func ownerFaceID(for ownerID: UUID, gender: FacePersonGender, taken: Set<String>) -> String? {
        let ids = owners(gender: gender).map(\.id)
        guard !ids.isEmpty else { return nil }
        let start = Int(FaceLibrary.stableHash(ownerID) % UInt64(ids.count))
        for offset in 0..<ids.count {
            let candidate = ids[(start + offset) % ids.count]
            if !taken.contains(candidate) { return candidate }
        }
        return nil
    }

    /// Fills in `faceID` for every owner that has none, re-draws any that is the
    /// wrong gender, and returns how many portraits it wrote.
    ///
    /// The load-time repair for careers created before owners carried a portrait
    /// — the owner half of `FaceLibrary.backfill`. Reads each owner's own
    /// `gender`, which is why the signature never needed one: a save written
    /// before that field existed decodes as male, and male is what those owners'
    /// names have always been.
    ///
    /// The gender re-draw covers a real window rather than a hypothetical one.
    /// The extras shipped one commit before `Owner.gender` did, and in between
    /// the draw ran over all 96 ids — so a career created in that window handed
    /// roughly one owner in eight a photograph of the wrong sex. Same repair the
    /// coach half performs for the same reason (`FaceLibrary.backfill`).
    ///
    /// Still idempotent: a matching id seeds `taken` and is never re-drawn, and
    /// an id the manifest does not know is left alone (it cannot be classified,
    /// so churning it would be guessing), so a second pass writes nothing.
    @discardableResult
    func backfillOwnerFaces(_ ownerList: [Owner]) -> Int {
        guard isAvailable else { return 0 }
        // Sorted by id so the probe order — and therefore who gets which
        // portrait when two owners collide — does not depend on fetch order.
        let ordered = ownerList.sorted { $0.id.uuidString < $1.id.uuidString }
        var taken = Set(ordered.compactMap(\.faceID))
        var assigned = 0
        for owner in ordered {
            let gender = FacePersonGender(tag: owner.gender)
            if let current = owner.faceID {
                guard let entry = entry(id: current),
                      FacePersonGender(tag: entry.bucket.gender) != gender
                else { continue }
                // Freed before the re-draw: nobody else can be holding it, so it
                // goes straight back to the owners of the gender it belongs to.
                taken.remove(current)
                owner.faceID = nil
            }
            guard let faceID = ownerFaceID(for: owner.id, gender: gender, taken: taken) else { continue }
            owner.faceID = faceID
            taken.insert(faceID)
            assigned += 1
        }
        return assigned
    }
}
