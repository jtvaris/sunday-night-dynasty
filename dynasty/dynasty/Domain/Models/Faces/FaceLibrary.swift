import Foundation

// MARK: - Person role

/// Which half of the face pool a person draws from.
enum FacePersonRole {
    case player
    case coach

    /// The bucket tag `generate_faces.py` writes for this role.
    var tag: String {
        switch self {
        case .player: return "player"
        case .coach:  return "coach"
        }
    }
}

// MARK: - Person gender

/// Which gender half of the face pool a person may draw from.
///
/// A separate type from the `String` stored on `Coach` and on `FaceBucket` on
/// purpose: the storage layers have to keep a lenient two-value string (an
/// absent key and an unknown value both mean male — see `Coach.gender`), while
/// every call into `FaceLibrary` should be spelled with something the compiler
/// can check. `init(tag:)` is that boundary and it is deliberately total: any
/// value other than `"female"` reads as male, so a corrupted row degrades to
/// the pre-female behaviour instead of failing.
enum FacePersonGender: String {
    case male, female

    /// The bucket tag `generate_faces.py` writes for this gender.
    var tag: String { rawValue }

    init(tag: String) { self = tag == "female" ? .female : .male }
}

// MARK: - Career-scoped registry

/// The career-scoped face bookkeeping, persisted as a JSON blob on `Career`.
///
/// * `inUse` — face id → the person currently wearing it. Rebuilt from the
///   live roster on every backfill pass, so it is self-healing: an orphaned
///   entry (person deleted, save edited, a hire path that forgot to claim)
///   corrects itself on the next league advance.
/// * `cooldown` — face id → the season the face was freed. A freed face stays
///   out of circulation for `FaceLibrary.cooldownSeasons` further seasons so a
///   retiring legend is not immediately re-skinned onto a rookie.
struct FaceAssignmentRegistry: Codable {
    var inUse: [String: UUID] = [:]
    var cooldown: [String: Int] = [:]

    init() {}
}

// MARK: - FaceLibrary

/// The face pool and its deterministic person → face assignment.
///
/// ## Catalog sources
///
/// 1. **`faces_manifest.json` in the bundle** (authoritative when present).
///    It is the only thing that knows which ids survived the human QA cull.
/// 2. **Synthesized from the generator seed** (`FaceCatalogSynthesizer`) when
///    the manifest has not shipped yet. Buckets are a pure function of
///    `(seed, faceID)`, so assignment is fully determined *before a single
///    image exists* — the images generate out-of-band and the app must behave
///    identically with an empty `Faces/` folder.
///
/// Neither path touches the filesystem for images: a missing HEIC is a
/// rendering concern (`PersonFaceView` draws a silhouette) and never an
/// assignment concern.
///
/// ## Pool arithmetic (why the reserve and female ranges exist)
///
/// The generated range is 2 048 faces — 1 672 player-age, 376 coach-age with
/// the shipped seed. A fresh random league is 32 × 53 = 1 696 players and
/// 32 × 16 = 512 coaches, and the fixed 2026 template is 1 807 players: MORE
/// persons than faces on both sides. "No two active persons share a face" is
/// therefore unachievable inside 2 048, so the pool carries a 512-id **reserve**
/// (`face_02048...face_02559`). The template pre-assigns its overflow out of
/// that range — `tools/league-data/make_templates.py` gives it to the 122 depth
/// players and the 13 lowest-rated backups — and this picker treats it as a last
/// resort: everything generated is exhausted before a reserve id is handed out,
/// so a random league keeps drawing exclusively from the ids whose pictures
/// exist. Measured on a full template league: 1 902 people, 1 902 distinct
/// faces, no player wearing a coach-age face.
///
/// Above the reserve sits the 1 024-id **female range**
/// (`face_02560...face_03583`; the whole pool is `generate_faces.py --count
/// 3584`). It is NOT a second reserve — it is first-class generated area, and
/// the only place female coach faces exist, so tier 1 has to be able to reach
/// it (`FaceGeneratorConstants.isReserve` is a bounded window for exactly that
/// reason). The full 3 584-id pool holds 2 924 player-age and 660 coach-age
/// faces, **35** of them female. Two consequences: 660 coach faces now exceed
/// the 512 coach slots of a full league, so the forced coach → player-face
/// overflow this class used to carry is gone (`crossRole` reads ~0 at league
/// creation); and the 35 female ids form a small, gender-strict sub-pool whose
/// exhaustion is the normal case, not a corner case (see `pickLocked`).
///
/// ## The invariant this class actually keeps
///
/// **Nobody shares a portrait while an unused one of the same gender exists.**
/// Not "never" — a
/// career outgrows 3 584 ids: a league starts at ~2 200 living people and every
/// offseason persists 224 draft picks plus up to ~124 AI UDFAs, against 40-90
/// portraits handed back by retirement. So the picker exhausts the catalog in
/// this order before it ever duplicates: free generated → free reserve → free
/// cross-role → **anything no LIVING person holds** (i.e. cooldown ignored:
/// re-skinning a retiree's face is much better than cloning a teammate's) →
/// reuse. `debugAuditActiveFaces` reports `free=`, so a log always says which
/// of the two happened, and `backfill` repairs a shared portrait only while the
/// pool has room — with a full pool a stable duplicate beats a portrait that
/// changes every week.
///
/// Every rung of that ladder is additionally filtered by gender, so "unused"
/// means "unused AND of this person's gender": a female coach duplicates
/// another female coach's portrait before she is ever handed a male one, and
/// takes no portrait at all (nil → the `coach_f*` placeholder photo) before
/// that. `free=` in the audit line is therefore split by gender too
/// (`freeFemale=`), because 600 free male ids say nothing about whether a
/// female duplicate was avoidable.
///
/// ## Threading
///
/// The module defaults to `MainActor` isolation, so today every call site —
/// engines, generators, views — is already serialized. The recursive lock is
/// cheap insurance so that moving a generator onto a background task later
/// cannot silently corrupt the registry.
final class FaceLibrary {

    /// Seasons a freed face stays out of circulation.
    static let cooldownSeasons = 2

    static let shared = FaceLibrary()

    /// Where the loaded catalog came from — surfaced for diagnostics only.
    enum CatalogSource: String {
        case manifest
        case synthesized
    }

    private let lock = NSRecursiveLock()

    private var loaded = false
    private(set) var entries: [FaceEntry] = []
    private(set) var catalogSource: CatalogSource = .synthesized

    /// Bucket indexes, each sorted by id so a pick is reproducible.
    private var byRole: [String: [FaceEntry]] = [:]
    private var byRoleAge: [String: [FaceEntry]] = [:]
    private var byRoleAgeBuild: [String: [FaceEntry]] = [:]
    private var entriesByID: [String: FaceEntry] = [:]
    /// Ids in the reserve range — assigned only after everything generated is
    /// taken. See the pool-arithmetic note above.
    private var reserveIDs: Set<String> = []

    /// Faces currently worn by people **nobody sees on a roster or a staff
    /// page** — unsigned free agents and unemployed coaches. Rebuilt from the
    /// live population by `backfill` (so it is at most one league advance
    /// stale) and used only in the very last resort: when the catalog is full,
    /// the duplicate is aimed at one of these instead of at a starter. See
    /// `pickLocked`.
    private var backgroundHolders: Set<String> = []

    private var registry = FaceAssignmentRegistry()
    private weak var boundCareer: Career?
    private var boundCareerID: UUID?
    private var registryDirty = false
    private var batchDepth = 0

    private init() {}

    // MARK: - Catalog loading

    /// Loads the catalog once, manifest-first. Safe to call from anywhere.
    func ensureCatalogLoaded() {
        lock.lock()
        defer { lock.unlock() }
        guard !loaded else { return }
        loaded = true

        let loadedEntries: [FaceEntry]
        if let manifest = Self.loadManifest(), !manifest.faces.isEmpty {
            loadedEntries = manifest.faces
            catalogSource = .manifest
        } else {
            loadedEntries = FaceCatalogSynthesizer.synthesize()
            catalogSource = .synthesized
        }
        install(loadedEntries)
    }

    /// Test/diagnostic seam: replaces the catalog with an explicit list.
    func loadCatalog(_ explicitEntries: [FaceEntry], source: CatalogSource = .manifest) {
        lock.lock()
        defer { lock.unlock() }
        loaded = true
        catalogSource = source
        install(explicitEntries)
    }

    private func install(_ newEntries: [FaceEntry]) {
        entries = newEntries.sorted { $0.id < $1.id }
        entriesByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        reserveIDs = Set(entries.map(\.id).filter(FaceGeneratorConstants.isReserve))
        byRole = Dictionary(grouping: entries) { $0.bucket.role }
        byRoleAge = Dictionary(grouping: entries) { Self.key($0.bucket.role, $0.bucket.ageBand) }
        byRoleAgeBuild = Dictionary(grouping: entries) {
            Self.key($0.bucket.role, $0.bucket.ageBand, $0.bucket.build)
        }
    }

    /// Where `faces_manifest.json` resolves in the bundle, or `nil` when it has
    /// not shipped yet.
    ///
    /// Both arms are load-bearing. The Xcode project is a filesystem-
    /// synchronized root group and it FLATTENS `Resources/Faces/` into the
    /// bundle root, so the root arm is the one that hits today; the
    /// subdirectory arm covers a future move to a real resource folder or an
    /// On-Demand-Resources package. `FaceBundleAudit` reports which arm won so
    /// a packaging change cannot silently fall back to the synthesized catalog.
    static func manifestURL() -> URL? {
        let name = FaceGeneratorConstants.manifestResource
        return Bundle.main.url(forResource: name, withExtension: "json")
            ?? Bundle.main.url(
                forResource: name, withExtension: "json",
                subdirectory: FaceGeneratorConstants.facesFolder
            )
    }

    private static func loadManifest() -> FaceManifest? {
        guard let url = manifestURL(), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(FaceManifest.self, from: data)
    }

    private static func key(_ parts: String...) -> String {
        parts.joined(separator: "|")
    }

    // MARK: - Career binding

    /// Binds to a career that already exists on disk and adopts its stored
    /// registry. Re-binding to the SAME career is a no-op so the in-memory
    /// state (which may be ahead of the last save) is never clobbered.
    func activate(career: Career) {
        lock.lock()
        defer { lock.unlock() }
        ensureCatalogLoaded()
        guard boundCareerID != career.id else {
            boundCareer = career
            return
        }
        flushLocked()
        boundCareer = career
        boundCareerID = career.id
        registry = career.faceRegistry
        registryDirty = false
        pruneCooldownLocked()
    }

    /// Binds to a brand-new career and starts from an EMPTY registry. Call
    /// this before generating/importing the league so every person created
    /// during bootstrap lands in the new career's registry.
    func beginNewCareer(_ career: Career) {
        lock.lock()
        defer { lock.unlock() }
        ensureCatalogLoaded()
        flushLocked()
        boundCareer = career
        boundCareerID = career.id
        registry = FaceAssignmentRegistry()
        registryDirty = true
        flushLocked()
    }

    /// Groups many assignments into a single registry encode. Nesting is safe.
    func batch<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        batchDepth += 1
        defer {
            batchDepth -= 1
            if batchDepth == 0 { flushLocked() }
            lock.unlock()
        }
        return try body()
    }

    /// Writes the registry back onto the bound career (caller saves the context).
    func flush() {
        lock.lock()
        defer { lock.unlock() }
        flushLocked()
    }

    private func flushLocked() {
        guard registryDirty, let career = boundCareer else { return }
        career.faceRegistry = registry
        registryDirty = false
    }

    private var currentSeasonLocked: Int {
        boundCareer?.currentSeason ?? 0
    }

    // MARK: - Availability

    /// A face is free when nobody holds it and its retirement cooldown expired.
    private func isFreeLocked(_ faceID: String, season: Int) -> Bool {
        if registry.inUse[faceID] != nil { return false }
        if let released = registry.cooldown[faceID], season - released < Self.cooldownSeasons {
            return false
        }
        return true
    }

    /// How many catalog ids NOBODY currently holds — cooldown ignored.
    ///
    /// This is the honest capacity signal: as long as it is > 0, `pickLocked`
    /// is guaranteed to hand out a portrait no living person wears (the
    /// cooldown-reclaim stage sees exactly these ids). At 0 the pool is
    /// genuinely full and a duplicate is arithmetic, not a bug — which is the
    /// difference `debugAuditActiveFaces` reports and the collision repair in
    /// `backfill` keys off.
    private func unheldCountLocked() -> Int {
        entries.reduce(0) { registry.inUse[$1.id] == nil ? $0 + 1 : $0 }
    }

    private func pruneCooldownLocked() {
        let season = currentSeasonLocked
        let before = registry.cooldown.count
        registry.cooldown = registry.cooldown.filter { season - $0.value < Self.cooldownSeasons }
        if registry.cooldown.count != before { registryDirty = true }
    }

    private func reserveLocked(_ faceID: String, for personID: UUID) {
        registry.inUse[faceID] = personID
        registry.cooldown[faceID] = nil
        // Whoever wore it before, a freshly signed/hired person wears it now, so
        // it is no longer a safe duplication target.
        backgroundHolders.remove(faceID)
        registryDirty = true
        if batchDepth == 0 { flushLocked() }
    }

    // MARK: - Assignment

    /// Reserves a face for a person and returns its id.
    ///
    /// The pick is a stable hash of `personID` modulo the candidate count, so
    /// the same person in the same registry state always draws the same face.
    ///
    /// `nil` means "no face of this role AND gender exists" — an empty catalog,
    /// or (the realistic case) a female coach hired after the 35 female ids are
    /// all worn. The registry is left untouched in that case, so the caller can
    /// simply leave `faceID` nil and let `PersonFaceView` render the
    /// gender-matched placeholder photo.
    @discardableResult
    func assignFace(
        personID: UUID,
        role: FacePersonRole,
        age: Int,
        position: Position?,
        gender: FacePersonGender = .male
    ) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let pick = pickLocked(
            personID: personID, role: role, age: age, position: position, gender: gender
        ) else {
            return nil
        }
        reserveLocked(pick, for: personID)
        return pick
    }

    /// Picks a face WITHOUT reserving it — for transient people who mostly
    /// never join the league: draft prospects (350/class, ~30 of them ever get
    /// signed) and coach-search candidates (25/search, one gets hired).
    /// Reserving those would drain the pool in a single offseason. The pick
    /// still prefers free faces, so a preview face usually survives the later
    /// `claimFace` unchanged.
    func previewFace(
        personID: UUID,
        role: FacePersonRole,
        age: Int,
        position: Position?,
        gender: FacePersonGender = .male
    ) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return pickLocked(
            personID: personID, role: role, age: age, position: position, gender: gender
        )
    }

    /// The shared pick used by both `assignFace` (which then reserves) and
    /// `previewFace` (which does not).
    ///
    /// The degradation order is deliberate: everything role-correct is
    /// exhausted — including the reserve range — before anything else, and a
    /// portrait somebody already wears is the LAST thing handed out.
    ///
    /// The one crossing of the role barrier, before reuse, used to be forced by
    /// arithmetic: the 2 560-id pool split 2 094 player / **466 coach** against a
    /// full league's 32 × 16 = **512** coaches, so 46 of them could not have a
    /// coach-age face, in a random league and an imported template alike. The
    /// 3 584-id pool inverts that — 2 924 player / **660 coach** — so a fresh
    /// league crosses the barrier zero times and the `crossRole` audit counter
    /// reads ~0 at creation. The tier stays because a long career still outgrows
    /// the coach half; when it is reached the overflow takes a free player-age
    /// face rather than a duplicate (`docs/FACE_GENERATION_PLAN.md` §6), and
    /// takes it from the OLDEST player band first, so what lands on a position
    /// coach is a man in his early thirties, not a rookie. Only after the whole
    /// catalog is spoken for does anyone get a face twice.
    ///
    /// `gender` is a HARD constraint applied at EVERY tier, so for a female
    /// coach the whole ladder walks a 35-id sub-pool and then terminates at nil
    /// (stage 20) rather than handing back a male portrait — see the stage-20
    /// comment for why nil is the correct answer there.
    private func pickLocked(
        personID: UUID,
        role: FacePersonRole,
        age: Int,
        position: Position?,
        gender: FacePersonGender = .male
    ) -> String? {
        ensureCatalogLoaded()
        guard !entries.isEmpty else { return nil }

        let season = currentSeasonLocked
        let tiers = roleTiersLocked(role: role, age: age, position: position, personID: personID)
        // A HARD constraint, not a preference: a male coach must never wear a
        // female portrait and vice versa. Applied at EVERY tier below —
        // including cross-role, the cooldown reclaim, the whole-catalog sweep
        // and the reuse tiers — because a gender mismatch is the one
        // degradation a player reads as a bug rather than as a repeated face.
        //
        // Cheap for the 99 % case: players and male coaches match every
        // pre-expansion id (a bucket with no `gender` key decodes to "male"), so
        // for them the filter only ever removes the 35 female ids.
        let genderOK: (FaceEntry) -> Bool = { $0.bucket.gender == gender.tag }

        // 1-3: free faces from the GENERATED range (the ids `--count 2048`
        //      produces), tightening constraints relaxed one at a time.
        for tier in tiers {
            let free = tier.filter {
                genderOK($0) && !reserveIDs.contains($0.id) && isFreeLocked($0.id, season: season)
            }
            if let pick = Self.deterministicPick(free, personID: personID) { return pick.id }
        }
        // 4-6: free faces from the RESERVE range. Reached by the fixed
        //      template (which pre-assigns the whole generated player half) and
        //      by any league that outgrows the pool. A reserve id renders as a
        //      silhouette until the extended `--count 3584` run lands, which is
        //      still better than two active players sharing a portrait.
        //
        //      Note the female range (2560+) is NOT in here: it is first-class
        //      generated area and is reached at tier 1, which is what makes a
        //      female coach's exact-bucket pick possible at all.
        for tier in tiers {
            let free = tier.filter { genderOK($0) && isFreeLocked($0.id, season: season) }
            if let pick = Self.deterministicPick(free, personID: personID) { return pick.id }
        }
        // 7-9: the role's free pool — generated AND reserve — is gone. Cross
        //      into the other role's still-free faces, age-plausible band
        //      first, because a duplicate portrait is the worse failure. Before
        //      the 3 584-id pool this is where the last ~46 coaches of every
        //      full league landed; with 660 coach faces against 512 slots a
        //      fresh league no longer reaches it at all.
        //
        //      Provably EMPTY for a female coach: the generator draws gender
        //      only for coach faces, so there are no female player faces. The
        //      three filtered passes cost nothing and are kept deliberately — a
        //      future batch of female player faces has to flow THROUGH the
        //      ladder, not around it. Symmetrically, this is the tier that would
        //      have put a female coach's portrait on a male player, and
        //      `genderOK` is what stops it.
        for tier in crossRoleTiersLocked(role: role) {
            let free = tier.filter { genderOK($0) && isFreeLocked($0.id, season: season) }
            if let pick = Self.deterministicPick(free, personID: personID) { return pick.id }
        }
        // 10-15: EARLY COOLDOWN RECLAIM. Nothing is free by the polite
        //        definition, but faces whose holder LEFT the league (retired
        //        player, retired coach) are only blocked by the two-season
        //        cooldown. Taking one of those early is strictly better than a
        //        duplicate: the invariant that matters is "no two LIVING people
        //        share a portrait", while the cooldown is only cosmetic
        //        politeness ("don't re-skin a retiring legend onto a rookie").
        //
        //        This stage is what a real career runs into. The pool holds
        //        3 584 ids and a league is ~2 200 people at kickoff, so the
        //        first draft + UDFA wave (224 + up to 124 new players) empties
        //        the polite free list inside the first few offseasons — while
        //        the 40-90 portraits handed back by that same offseason's
        //        retirements sit unusable behind the cooldown. Without this
        //        stage every rookie from then on drew a face an ACTIVE
        //        teammate was already wearing.
        //
        //        Filtered by gender this is exactly right for the 35-id female
        //        sub-pool: a retired female coach's portrait comes back to the
        //        next female hire two seasons early, which matters a great deal
        //        more at 35 ids than it does at 2 924.
        for tier in tiers {
            let unheld = tier.filter { genderOK($0) && registry.inUse[$0.id] == nil }
            if let pick = Self.deterministicPick(unheld, personID: personID) { return pick.id }
        }
        for tier in crossRoleTiersLocked(role: role) {
            let unheld = tier.filter { genderOK($0) && registry.inUse[$0.id] == nil }
            if let pick = Self.deterministicPick(unheld, personID: personID) { return pick.id }
        }
        // 16: role-correct tiers and the plausible cross-role bands are all
        //     held. Sweep the WHOLE catalog for anything unheld before giving
        //     up on uniqueness — an implausible age band still beats a
        //     duplicate. Gender is NOT relaxed here: an implausible age is a
        //     shrug, a wrong-gender portrait is a bug report.
        let unheldAnywhere = entries.filter { genderOK($0) && registry.inUse[$0.id] == nil }
        if let pick = Self.deterministicPick(unheldAnywhere, personID: personID) { return pick.id }
        // 17-19: the catalog is genuinely full — every id is on a living
        //        person. From here a duplicate is arithmetic, not a defect;
        //        `debugAuditActiveFaces` reports `free=0` so the two cases can
        //        never be confused in a log.
        //
        //        Which portrait gets doubled up still matters, though: aim at a
        //        face worn by somebody NOBODY LOOKS AT — an unsigned free agent
        //        or an unemployed coach — rather than at a starter. Measured on
        //        a 3-season smoke run, the excess is ~200 people against ~550
        //        such background holders, so the 32 rosters and 16-man staffs
        //        keep unique portraits well past the point where the raw
        //        arithmetic runs out.
        //
        //        Gender-filtered, this is the tier a female coach hired past the
        //        35-face ceiling actually lands in: she duplicates ANOTHER
        //        FEMALE coach's portrait. That ordering is the whole point — a
        //        repeated correct-gender portrait beats a placeholder, and a
        //        placeholder beats a male portrait.
        for tier in tiers {
            let background = tier.filter { genderOK($0) && backgroundHolders.contains($0.id) }
            if let pick = Self.deterministicPick(background, personID: personID) { return pick.id }
        }
        for tier in tiers {
            if let pick = Self.deterministicPick(tier.filter(genderOK), personID: personID) {
                return pick.id
            }
        }
        // 20: no face of this role AND this gender exists at all — a cull that
        //     removed a whole role, a save opened against a catalog that
        //     predates the female range, or simply a female coach in a build
        //     whose manifest carries no female ids yet.
        //
        //     Returning nil here is the CORRECT answer and the only genuine nil
        //     terminal in this function (the `entries.isEmpty` guard above is
        //     the other): the caller leaves `faceID` nil and `PersonFaceView`
        //     renders the gender-matched `coach_f*` placeholder photograph.
        //     Handing back a male portrait instead would be the one failure a
        //     player reads as a bug rather than as a missing asset.
        return Self.deterministicPick(entries.filter(genderOK), personID: personID)?.id
    }

    /// Turns a preview face into a reserved one. Used when a transient person
    /// becomes permanent (prospect drafted / UDFA signed / candidate hired).
    /// Falls back to a fresh assignment when the preferred face was taken in
    /// the meantime — or when it does not match the person's gender.
    @discardableResult
    func claimFace(
        _ preferred: String?,
        personID: UUID,
        role: FacePersonRole,
        age: Int,
        position: Position?,
        gender: FacePersonGender = .male
    ) -> String? {
        lock.lock()
        defer { lock.unlock() }
        ensureCatalogLoaded()

        // The gender check on the fast path is load-bearing: this path used to
        // validate nothing but "the catalog knows it and nobody holds it", so a
        // preview drawn before the person's gender was known — or carried across
        // a gender flip — was claimed verbatim. That is the likeliest way the
        // gender-strict invariant leaks in practice, and a mismatch here costs
        // only a re-draw through the full ladder below.
        if let preferred, let entry = entriesByID[preferred], entry.bucket.gender == gender.tag {
            if registry.inUse[preferred] == personID { return preferred }
            if isFreeLocked(preferred, season: currentSeasonLocked) {
                reserveLocked(preferred, for: personID)
                return preferred
            }
        }
        return assignFace(
            personID: personID, role: role, age: age, position: position, gender: gender
        )
    }

    /// Frees a face and starts its cooldown (retirement, washout, a coach
    /// leaving the league for good). Keeping `faceID` on the row is deliberate:
    /// history and Hall-of-Fame views still render the person's portrait.
    func releaseFace(_ faceID: String?) {
        guard let faceID, !faceID.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        // Only a face somebody actually held goes on cooldown. Releasing an
        // unheld id must stay a no-op, or a stray call would freeze a free
        // face out of circulation for two seasons for nothing.
        guard registry.inUse[faceID] != nil else { return }
        registry.inUse[faceID] = nil
        registry.cooldown[faceID] = currentSeasonLocked
        registryDirty = true
        if batchDepth == 0 { flushLocked() }
    }

    // MARK: - Backfill / reconciliation

    /// Legacy-save backfill + registry reconciliation in one pass, mirroring
    /// `WeekAdvancer.backfillLegacyLearning`: rows created before `faceID`
    /// existed (or by a code path that never assigned one) get a face on the
    /// next league advance, and the in-use map is rebuilt from what the roster
    /// actually holds.
    ///
    /// Idempotent: a second run over the same rows assigns nothing and leaves
    /// the registry byte-identical.
    ///
    /// It repairs three states, not just the missing one:
    ///
    /// * `faceID == nil` — never assigned (legacy save, template import, a code
    ///   path that forgot).
    /// * `faceID` the catalog does not know — the human QA cull removed that id
    ///   from `faces_manifest.json`, or a save predates a re-cut library. Left
    ///   alone these rendered a silhouette FOREVER while hundreds of valid
    ///   faces sat free, because "has an id" used to mean "has a face".
    /// * two living people on the SAME id — the collision a non-reserving
    ///   preview face can leave behind (see `previewFace`). Repaired only while
    ///   an unheld id exists; with a genuinely full pool the duplicate is kept
    ///   deliberately, because re-drawing it every advance would make portraits
    ///   flicker from week to week for no gain.
    ///
    /// - Returns: how many faces this pass assigned.
    @discardableResult
    func backfill(players: [Player], coaches: [Coach]) -> Int {
        lock.lock()
        defer { lock.unlock() }
        ensureCatalogLoaded()
        guard !entries.isEmpty else { return 0 }

        return batch {
            let season = currentSeasonLocked

            // 1. Rebuild the in-use map from the live population. Living people
            //    hold their face; retired players and retired coaches do not
            //    (their portrait still renders — the face just re-enters
            //    circulation after cooldown).
            //
            //    Iteration is by person id, not by fetch order, so a collision
            //    always resolves the same way: the lower id keeps the portrait
            //    and the other row is re-drawn. Fetch order is not guaranteed
            //    stable, and a non-deterministic repair would make the template
            //    determinism harness flap.
            //
            //    Repair is gated on the population, not on the current registry:
            //    if the catalog holds more ids than there are living people, a
            //    collision-free assignment provably exists (step 2 runs against
            //    the REBUILT map, so it has at least `entries - living` unheld
            //    ids to draw from). With a genuinely full pool the gate is false
            //    and duplicates are left stable on purpose.
            let living = players.reduce(0) { $0 + ($1.isRetired ? 0 : 1) }
                + coaches.reduce(0) { $0 + ($1.isRetired ? 0 : 1) }
            let canRepairCollisions = entries.count > living
            var rebuilt: [String: UUID] = [:]
            var rebuiltOnTeam: Set<String> = []
            var background: Set<String> = []
            var collisions = 0
            var reaimed = 0
            var genderRepairs = 0

            func claimRebuilt(_ face: String?, personID: UUID, onTeam: Bool) -> Bool {
                guard let face, entriesByID[face] != nil else { return false }
                if let holder = rebuilt[face], holder != personID {
                    if canRepairCollisions {
                        collisions += 1
                        return false    // caller clears the id → step 2 re-draws
                    }
                    // Pool is full, so a duplicate cannot be removed — but it
                    // CAN be moved off the visible league. Two people on a
                    // roster/staff sharing a portrait is the only version a
                    // player ever notices, so re-draw this one: with the pool
                    // full the picker aims at a face worn by an unsigned /
                    // unemployed person, leaving one visible holder per face.
                    if onTeam, rebuiltOnTeam.contains(face), !backgroundHolders.isEmpty {
                        reaimed += 1
                        return false
                    }
                    return true         // keep the duplicate, stable
                }
                rebuilt[face] = personID
                if onTeam {
                    rebuiltOnTeam.insert(face)
                    background.remove(face)
                } else {
                    background.insert(face)
                }
                return true
            }

            for player in players.filter({ !$0.isRetired }).sorted(by: Self.byID) {
                if !claimRebuilt(player.faceID, personID: player.id, onTeam: player.teamID != nil),
                   player.faceID != nil {
                    player.faceID = nil
                }
            }
            for coach in coaches.filter({ !$0.isRetired }).sorted(by: Self.byID) {
                // A coach wearing a face of the wrong gender — a save written
                // before the female range existed, or a row whose gender was
                // set after the portrait was — is repaired in THIS pass, not in
                // phase 2, and the id is released as well as cleared.
                //
                // Both halves are needed. Clearing alone would leave the
                // mismatched id registered to her in the rebuilt `inUse` map (it
                // is her row that carries it), so it would never return to
                // anybody's free pool; releasing alone would leave her wearing
                // it. Together the row is corrected, the male id goes back into
                // circulation behind the normal cooldown, and phase 2 draws her
                // a female portrait.
                //
                // Normalized through `FacePersonGender` rather than compared as
                // raw strings, so the test agrees exactly with what
                // `needsFaceLocked` and `pickLocked` do next — an unexpected
                // stored value must not make this pass clear a face phase 2 then
                // hands straight back, which would flicker the portrait on every
                // advance.
                if let faceID = coach.faceID, let entry = entriesByID[faceID],
                   entry.bucket.gender != FacePersonGender(tag: coach.gender).tag {
                    genderRepairs += 1
                    coach.faceID = nil
                    releaseFace(faceID)
                }
                if !claimRebuilt(coach.faceID, personID: coach.id, onTeam: coach.teamID != nil),
                   coach.faceID != nil {
                    coach.faceID = nil
                }
            }
            backgroundHolders = background
            for (face, _) in registry.inUse where rebuilt[face] == nil {
                if registry.cooldown[face] == nil { registry.cooldown[face] = season }
            }
            if rebuilt != registry.inUse {
                registry.inUse = rebuilt
                registryDirty = true
            }
            pruneCooldownLocked()

            // 2. Assign to everyone still missing a USABLE face — an id the
            //    catalog cannot resolve counts as missing.
            var assigned = 0
            for player in players where needsFaceLocked(player.faceID) {
                if player.isRetired {
                    // History rows do not compete for the active pool.
                    player.faceID = previewFace(
                        personID: player.id, role: .player,
                        age: player.age, position: player.position
                    )
                } else {
                    player.faceID = assignFace(
                        personID: player.id, role: .player,
                        age: player.age, position: player.position
                    )
                }
                if player.faceID != nil { assigned += 1 }
            }
            // Coaches carry gender, so "needs a face" includes "wears one of the
            // wrong gender" (phase 1 already cleared and released the living
            // ones; this catches retired rows, which phase 1 skips).
            //
            // Cost note: when the female sub-pool is exhausted a female coach's
            // assignment returns nil, `needsFaceLocked(nil)` stays true, and she
            // walks the whole ladder again on the NEXT advance. With the ~31
            // female coaches a 0.06 hiring share produces, that is ~20 filtered
            // passes over ≤ 3 584 entries each, per advance — well under a
            // millisecond, and deliberately not cached: the moment a female
            // portrait frees up she should pick it up.
            for coach in coaches
            where needsFaceLocked(coach.faceID, gender: FacePersonGender(tag: coach.gender)) {
                let gender = FacePersonGender(tag: coach.gender)
                if coach.isRetired {
                    coach.faceID = previewFace(
                        personID: coach.id, role: .coach, age: coach.age, position: nil,
                        gender: gender
                    )
                } else {
                    coach.faceID = assignFace(
                        personID: coach.id, role: .coach, age: coach.age, position: nil,
                        gender: gender
                    )
                }
                if coach.faceID != nil { assigned += 1 }
            }
            if collisions > 0 || reaimed > 0 || genderRepairs > 0 {
                print("FACEQA: backfill repaired \(collisions) shared portrait(s), "
                      + "re-aimed \(reaimed) off the visible league, "
                      + "re-drew \(genderRepairs) wrong-gender portrait(s)")
            }
            return assigned
        }
    }

    /// Whether a row needs a (re)assignment: no id at all, an id this catalog
    /// cannot resolve — a culled face, or one from a wider library — or an id
    /// whose bucket gender contradicts the person's.
    ///
    /// The gender arm is what repairs legacy saves: resolvability alone said
    /// nothing about gender, so a female coach who was minted before the female
    /// range shipped would have kept her male portrait forever.
    private func needsFaceLocked(
        _ faceID: String?,
        gender: FacePersonGender = .male
    ) -> Bool {
        guard let faceID, !faceID.isEmpty else { return true }
        guard let entry = entriesByID[faceID] else { return true }
        return entry.bucket.gender != gender.tag
    }

    /// Stable person ordering for the reconciliation pass.
    private static func byID(_ lhs: Player, _ rhs: Player) -> Bool {
        lhs.id.uuidString < rhs.id.uuidString
    }

    private static func byID(_ lhs: Coach, _ rhs: Coach) -> Bool {
        lhs.id.uuidString < rhs.id.uuidString
    }

    // MARK: - Bucket selection

    /// The three role-correct candidate tiers, tightest first:
    /// exact bucket → same age band, any build → any face of the role.
    private func roleTiersLocked(
        role: FacePersonRole,
        age: Int,
        position: Position?,
        personID: UUID
    ) -> [[FaceEntry]] {
        let ageBand = Self.ageBand(role: role, age: age)
        let build = Self.buildTag(role: role, position: position, personID: personID)
        return [
            byRoleAgeBuild[Self.key(role.tag, ageBand, build)] ?? [],
            byRoleAge[Self.key(role.tag, ageBand)] ?? [],
            byRole[role.tag] ?? [],
        ]
    }

    /// The other role's faces, ordered by how plausible they are on this
    /// person: a coach takes the oldest players first, a player the youngest
    /// coaches first. Only reached when the person's own role is exhausted.
    private func crossRoleTiersLocked(role: FacePersonRole) -> [[FaceEntry]] {
        let bands: [String]
        let otherRole: String
        switch role {
        case .coach:  otherRole = "player"; bands = ["30-36", "25-29", "20-24"]
        case .player: otherRole = "coach";  bands = ["38-50", "50-68"]
        }
        return bands.map { byRoleAge[Self.key(otherRole, $0)] ?? [] }
    }

    /// Maps a person's age onto the generator's age bands. Ages outside the
    /// generated range clamp to the nearest band — a 37-year-old kicker gets a
    /// "30-36" face, a 34-year-old position coach a "38-50" one.
    static func ageBand(role: FacePersonRole, age: Int) -> String {
        switch role {
        case .player:
            if age <= 24 { return "20-24" }
            if age <= 29 { return "25-29" }
            return "30-36"
        case .coach:
            return age <= 50 ? "38-50" : "50-68"
        }
    }

    /// Position-group → build weights. Trenches skew heavy, perimeter skill
    /// positions skew lean; the actual tag is drawn deterministically from the
    /// person's id so a position group is not uniformly one body type.
    static func buildTag(role: FacePersonRole, position: Position?, personID: UUID) -> String {
        let weights: [(tag: String, weight: Double)]
        switch role {
        case .coach: weights = FaceGeneratorConstants.coachBuilds
        case .player: weights = playerBuildWeights(position)
        }
        // A different mix constant than `deterministicPick` so the build draw
        // and the in-tier index are uncorrelated for the same person.
        let roll = Self.unitRoll(personID, salt: 0x9E37_79B9_7F4A_7C15)
        let total = weights.reduce(0.0) { $0 + $1.weight }
        var acc = 0.0
        for entry in weights {
            acc += entry.weight
            if roll * total <= acc { return entry.tag }
        }
        return weights[weights.count - 1].tag
    }

    private static func playerBuildWeights(_ position: Position?) -> [(tag: String, weight: Double)] {
        guard let position else { return FaceGeneratorConstants.playerBuilds }
        switch position {
        case .LT, .LG, .C, .RG, .RT, .DT:
            return [("heavy", 0.78), ("athletic", 0.20), ("lean", 0.02)]
        case .DE, .FB:
            return [("heavy", 0.40), ("athletic", 0.55), ("lean", 0.05)]
        case .TE, .MLB:
            return [("heavy", 0.22), ("athletic", 0.68), ("lean", 0.10)]
        case .OLB, .SS:
            return [("heavy", 0.10), ("athletic", 0.72), ("lean", 0.18)]
        case .QB, .RB, .FS:
            return [("heavy", 0.04), ("athletic", 0.66), ("lean", 0.30)]
        case .WR, .CB:
            return [("heavy", 0.01), ("athletic", 0.39), ("lean", 0.60)]
        case .K, .P:
            return [("heavy", 0.08), ("athletic", 0.42), ("lean", 0.50)]
        }
    }

    // MARK: - Deterministic hashing

    /// FNV-1a over the raw UUID bytes. Swift's `Hasher` is seeded per process
    /// and would hand the same person a different face on every launch, so it
    /// must not be used here.
    static func stableHash(_ id: UUID) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        withUnsafeBytes(of: id.uuid) { bytes in
            for byte in bytes {
                hash ^= UInt64(byte)
                hash = hash &* 0x0000_0100_0000_01b3
            }
        }
        return hash
    }

    /// A deterministic value in `[0, 1)` derived from a person id.
    private static func unitRoll(_ id: UUID, salt: UInt64) -> Double {
        let mixed = (stableHash(id) ^ salt) &* 0x2545_F491_4F6C_DD1D
        return Double(mixed >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    private static func deterministicPick(_ list: [FaceEntry], personID: UUID) -> FaceEntry? {
        guard !list.isEmpty else { return nil }
        let index = Int(stableHash(personID) % UInt64(list.count))
        return list[index]
    }

#if DEBUG
    // MARK: - Uniqueness audit (DEBUG only)

    /// What one uniqueness sweep found.
    struct FaceAudit {
        /// Active people examined (retired players excluded — their portrait
        /// still renders, but the face is back in circulation).
        var persons = 0
        /// Distinct face ids among them.
        var distinct = 0
        /// People wearing a face somebody else in the SAME league also wears.
        /// The invariant this whole audit exists for: must be 0 while a face of
        /// the same GENDER was free (see `isRegression`).
        var duplicated = 0
        /// Of `duplicated`, the ones sharing a FEMALE-bucket id. Classified by
        /// the face's bucket rather than by the holder's row because assignment
        /// is gender-strict: the holders of a female id are female coaches, and
        /// the bucket is the thing the picker actually filtered on.
        var duplicatedFemale = 0
        /// Of those, how many are on a roster or a coaching staff — i.e. how
        /// many duplicates a player can actually run into. The reuse ladder aims
        /// the unavoidable ones at unsigned/unemployed people, so this stays 0
        /// long after `duplicated` stops being 0.
        var duplicatedOnTeam = 0
        /// Active people with no face id at all (only possible with an empty
        /// catalog, which cannot happen once either source has loaded).
        var unassigned = 0
        /// How many landed in the reserve range `face_02048...face_02559` — i.e.
        /// how many render a silhouette until `generate_faces.py --count 3584`
        /// finishes. Ids in the female range above it are NOT counted here: they
        /// are first-class generated area, not a last resort.
        var reserve = 0
        /// How many took a face of the other role (the forced coach overflow;
        /// see `pickLocked`). With the 3 584-id pool this should read ~0 at
        /// league creation — 660 coach faces against 512 slots.
        var crossRole = 0
        /// People whose face's bucket gender contradicts their own. The
        /// gender-strict invariant is absolute, so this must ALWAYS be 0 — but it
        /// is reported, never trapped: it is a diagnostic for a claim site that
        /// forgot to pass `gender:`, and trapping would turn a cosmetic leak into
        /// a crash in a multi-season run.
        var genderMismatch = 0
        /// Catalog ids no living person holds at audit time (cooldown ignored).
        /// `0` means the pool is genuinely full, so a duplicate is arithmetic;
        /// `> 0` with `duplicated > 0` is a real regression, because the picker
        /// had a unique portrait available and handed out a shared one anyway.
        var free = 0
        /// Of `free`, the ids in the FEMALE half. The 35-id female sub-pool runs
        /// dry long before the 3 549 male ids do, so this is the only number that
        /// says whether a female duplicate was avoidable.
        var freeFemale = 0
        /// A couple of offending ids, for the failure line.
        var examples: [String] = []

        var isUnique: Bool { duplicated == 0 }

        /// Free ids a MALE person could have taken.
        var freeMale: Int { free - freeFemale }
        /// Duplicated holders on male-bucket ids.
        var duplicatedMale: Int { duplicated - duplicatedFemale }

        /// The invariant the picker can actually keep: nobody shares a portrait
        /// while an unused one **of their own gender** exists.
        ///
        /// Split per gender on purpose. The old `duplicated > 0 && free > 0` form
        /// trapped on the normal case as soon as female coaches shipped: two
        /// female coaches sharing one of 35 female portraits while 3 500 male
        /// ids sit free is arithmetic, not a regression, because `pickLocked`
        /// never had a female id to hand out. Each gender is therefore judged
        /// against its OWN free supply.
        var isRegression: Bool {
            (duplicatedMale > 0 && freeMale > 0) || (duplicatedFemale > 0 && freeFemale > 0)
        }
    }

    /// Whether a failed audit traps. `true` everywhere except inside
    /// `LeagueTemplateValidation`, which has to survive a failure long enough
    /// to print the numbers that explain it.
    static var debugTrapsOnDuplicateFace = true

    /// Sweeps a whole league and reports whether any two ACTIVE people share a
    /// portrait. Called right after league creation on both sources
    /// (`LeagueGenerator.generate` and `TeamSelectionView.finalizeCareer`) and
    /// by `LeagueTemplateValidation`; compiled out of Release.
    ///
    /// Prints one `FACEQA:` line and, on a duplicate, trips `assertionFailure`
    /// — with the pool arithmetic in `pickLocked` a duplicate at creation time
    /// means a real regression, not a capacity limit.
    @discardableResult
    func debugAuditActiveFaces(
        players: [Player],
        coaches: [Coach],
        label: String
    ) -> FaceAudit {
        lock.lock()
        defer { lock.unlock() }
        ensureCatalogLoaded()

        var audit = FaceAudit()
        var holdersByFace: [String: [String]] = [:]
        var onTeamByFace: [String: Int] = [:]

        func note(
            _ faceID: String?,
            _ who: String,
            role: FacePersonRole,
            gender: FacePersonGender,
            onTeam: Bool
        ) {
            audit.persons += 1
            guard let faceID, !faceID.isEmpty else {
                audit.unassigned += 1
                return
            }
            holdersByFace[faceID, default: []].append(who)
            if onTeam { onTeamByFace[faceID, default: 0] += 1 }
            if FaceGeneratorConstants.isReserve(faceID) { audit.reserve += 1 }
            if let entry = entriesByID[faceID] {
                if entry.bucket.role != role.tag { audit.crossRole += 1 }
                if entry.bucket.gender != gender.tag { audit.genderMismatch += 1 }
            }
        }

        for player in players where !player.isRetired {
            note(player.faceID, "\(player.lastName) (\(player.position.rawValue))",
                 role: .player, gender: .male, onTeam: player.teamID != nil)
        }
        for coach in coaches where !coach.isRetired {
            note(coach.faceID, "\(coach.lastName) (\(coach.role.rawValue))",
                 role: .coach, gender: FacePersonGender(tag: coach.gender),
                 onTeam: coach.teamID != nil)
        }

        audit.distinct = holdersByFace.count
        audit.free = entries.reduce(0) { holdersByFace[$1.id] == nil ? $0 + 1 : $0 }
        audit.freeFemale = entries.reduce(0) {
            ($1.bucket.isFemale && holdersByFace[$1.id] == nil) ? $0 + 1 : $0
        }
        for (faceID, holders) in holdersByFace.sorted(by: { $0.key < $1.key }) where holders.count > 1 {
            audit.duplicated += holders.count
            if entriesByID[faceID]?.bucket.isFemale == true {
                audit.duplicatedFemale += holders.count
            }
            // Only counts as a duplicate a player can SEE when two of the
            // holders are on a roster/staff.
            if let onTeam = onTeamByFace[faceID], onTeam > 1 { audit.duplicatedOnTeam += onTeam }
            if audit.examples.count < 3 {
                audit.examples.append("\(faceID)←\(holders.joined(separator: "+"))")
            }
        }

        print("FACEQA: \(label) persons=\(audit.persons) distinctFaces=\(audit.distinct) "
              + "duplicated=\(audit.duplicated)(f:\(audit.duplicatedFemale)) "
              + "onTeamDuplicates=\(audit.duplicatedOnTeam) "
              + "unassigned=\(audit.unassigned) "
              + "free=\(audit.free) freeFemale=\(audit.freeFemale) "
              + "reserveRange=\(audit.reserve) crossRole=\(audit.crossRole) "
              + "genderMismatch=\(audit.genderMismatch) "
              + "catalog=\(catalogSource.rawValue)/\(entries.count)")
        if audit.genderMismatch > 0 {
            // Never trapped — see `FaceAudit.genderMismatch`. A non-zero value
            // means a claim/assign site is not passing `gender:`, or a row's
            // gender changed after its portrait was drawn; `backfill` re-draws
            // those on the next advance, so this is a "fix the call site" signal
            // rather than a reason to kill a multi-season run.
            print("FACEQA: \(label) GENDER MISMATCH — \(audit.genderMismatch) "
                  + "active people wear a portrait of the wrong gender "
                  + "(a claim site is missing gender:, or backfill has not run yet)")
        }
        if !audit.isUnique {
            // Two very different failures, told apart by the free supply OF THE
            // DUPLICATED ID'S GENDER:
            //
            // * a gender-matching id was free — the picker shared a portrait
            //   while an unused one it was allowed to hand out existed. That is a
            //   regression and it traps.
            // * none was free — every id that person could legally wear is on a
            //   living person. Either the whole pool is smaller than the league
            //   (3 584 ids vs a population that grows by ~350 rookies a year) or,
            //   far sooner, the 35-id female sub-pool is full. Reuse is then
            //   arithmetic: reported loudly, never trapped, because a
            //   multi-season run must not die on a capacity limit the library can
            //   only fix by generating more images.
            // The female sub-pool fills thousands of ids before the male one
            // does, so name which half ran out — "POOL FULL" next to
            // `free=3400` would read as a contradiction in a smoke log.
            let verdict: String
            if audit.isRegression {
                verdict = "DUPLICATES"
            } else if audit.duplicatedFemale > 0, audit.duplicatedMale == 0 {
                verdict = "FEMALE SUB-POOL FULL — within-gender reuse unavoidable"
            } else {
                verdict = "POOL FULL — reuse unavoidable"
            }
            print("FACEQA: \(label) \(verdict) — \(audit.examples.joined(separator: " | "))")
            if audit.isRegression, Self.debugTrapsOnDuplicateFace {
                assertionFailure(
                    "FaceLibrary: \(audit.duplicated) active people share a portrait in \(label) "
                    + "(male \(audit.duplicatedMale) with \(audit.freeMale) male faces unused, "
                    + "female \(audit.duplicatedFemale) with \(audit.freeFemale) female faces "
                    + "unused) — \(audit.examples.joined(separator: " | "))"
                )
            }
        }
        return audit
    }
#endif

    // MARK: - Lookup

    /// The catalog entry for an id, if the catalog knows it.
    func entry(for faceID: String?) -> FaceEntry? {
        guard let faceID else { return nil }
        ensureCatalogLoaded()
        lock.lock()
        defer { lock.unlock() }
        return entriesByID[faceID]
    }
}

// MARK: - Career bridge

extension Career {

    /// Career-scoped face bookkeeping, JSON-decoded from `faceRegistryData`.
    /// Reading an untouched career yields an empty registry; writing encodes
    /// and stores it (caller saves the context).
    var faceRegistry: FaceAssignmentRegistry {
        get {
            guard let data = faceRegistryData,
                  let registry = try? JSONDecoder().decode(FaceAssignmentRegistry.self, from: data)
            else {
                return FaceAssignmentRegistry()
            }
            return registry
        }
        set {
            faceRegistryData = try? JSONEncoder().encode(newValue)
        }
    }
}
