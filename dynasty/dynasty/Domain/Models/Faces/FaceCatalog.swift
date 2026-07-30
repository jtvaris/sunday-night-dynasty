import Foundation
import CryptoKit

// MARK: - Bucket model

/// The five assignment tags every generated face carries.
///
/// Buckets are **assignment hints only** — they are never shown to the user.
/// The strings are the exact tag vocabulary emitted by
/// `tools/faces/generate_faces.py` (`build_spec`), so a decoded manifest and a
/// synthesized catalog are interchangeable.
struct FaceBucket: Codable, Hashable {
    let role: String        // "player" | "coach"

    /// "male" | "female". Only coach faces at `face_02560` and above can be
    /// female: the mixed female range draws for it, the female-ONLY range
    /// (`face_03584`…) is female by construction. Everything else is male.
    ///
    /// Decoded with `decodeIfPresent ?? "male"` because the manifests written
    /// before the female range existed have no `gender` key at all — an absent
    /// key means male, exactly as it does on `Coach.gender`. Keeping the
    /// property non-optional is what lets `FaceLibrary` key its grouping
    /// indexes on it without unwrapping.
    let gender: String

    let ageBand: String     // player: "20-24" | "25-29" | "30-36"
                            // coach:  "38-50" | "50-68"
    let tone: String        // "black" | "white" | "latino" | "pacific" | "mixed"
    let build: String       // "lean" | "athletic" | "heavy"

    /// Writing `init(from:)` below suppresses the synthesized memberwise init,
    /// so it is spelled out here — with the same male default, so the one
    /// construction site outside the female range needs no change.
    init(role: String, gender: String = "male", ageBand: String, tone: String, build: String) {
        self.role = role
        self.gender = gender
        self.ageBand = ageBand
        self.tone = tone
        self.build = build
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decode(String.self, forKey: .role)
        gender = try container.decodeIfPresent(String.self, forKey: .gender) ?? "male"
        ageBand = try container.decode(String.self, forKey: .ageBand)
        tone = try container.decode(String.self, forKey: .tone)
        build = try container.decode(String.self, forKey: .build)
    }

    var isFemale: Bool { gender == "female" }
}

/// One face in the library: a stable id, the bundle-relative file it *would*
/// live at, and its bucket. The file may legitimately not exist yet — image
/// generation runs out-of-band and the manifest ships first.
struct FaceEntry: Codable, Hashable {
    let id: String
    let file: String
    let bucket: FaceBucket
}

/// Decoded `faces_manifest.json` — the schema `tools/faces/package_faces.py`
/// writes: `{version, seed, faces: [{id, file, bucket}]}`.
struct FaceManifest: Codable {
    let version: Int
    let seed: Int?
    let faces: [FaceEntry]
}

// MARK: - Generator constants (single source of truth)

/// The generator-side constants, transcribed **verbatim** from
/// `tools/faces/generate_faces.py`. Nothing else in the app hard-codes a
/// bucket weight, a tag string or the pool size: change the Python and change
/// this enum together, or the synthesized catalog stops matching the shipped
/// manifest.
///
/// The weights are listed in the same order as the Python lists because
/// `weightedPick` reproduces the accumulation order exactly — floating-point
/// summation is order-dependent and the picks must land on the same side of
/// every boundary.
enum FaceGeneratorConstants {

    /// What `generate_faces.py --count` produces by default: the images for
    /// `face_00000...face_02047`.
    static let generatedPoolSize = 2048

    /// The **reserve** range `face_02048...face_02559`, produced only by
    /// `generate_faces.py --count 2560`.
    ///
    /// It exists because the fixed 2026 template needs 1 807 unique player-age
    /// faces and the generated range holds 1 672 (see
    /// `tools/league-data/make_templates.py`, TRANSFORM_QA §8): without it, two
    /// men in the SAME league would have to share a portrait. The transform
    /// hands these ids to its least visible people, and the runtime picker
    /// treats them as a last resort (`FaceLibrary.pickLocked`), so a career
    /// only reaches them once everything generated is genuinely taken.
    static let reservePoolSize = 512

    /// The **female-capable** extension `face_02560...face_03583`, produced by
    /// `generate_faces.py --count 3584`.
    ///
    /// It is a first-class generated area, NOT a second reserve: it is the only
    /// place female coach faces exist, so the runtime picker has to be able to
    /// reach it at tier 1 or a female coach could never get a portrait. It also
    /// ends the coach shortage — 660 coach faces against 512 league slots, where
    /// 2 560 ids only yielded 466 and forced ~46 coaches onto player faces.
    static let femaleRangeSize = 1024

    /// The **female-only** extension `face_03584...face_03711`, produced by
    /// `generate_faces.py --count 3712`.
    ///
    /// Every id in it is a female coach face. The mixed range below it yields
    /// one woman per ~24 ids (0.22 of the 0.1875 coach share) — 35 across all
    /// 1 024 — which a career drains by season 2-3: `freeFemale` hit 0 in 2027
    /// and female coaches started sharing portraits in 2028. Buying the next
    /// 128 through the same lottery would have meant ~3 100 more images, ~2 975
    /// of them men nobody needs, so this range skips the lottery:
    /// `bucket(forFaceID:)` forces role and gender here instead of drawing them.
    static let femaleOnlyRangeSize = 128

    /// Ids the synthesized catalog covers: `face_00000...face_03711`.
    static let poolSize = generatedPoolSize + reservePoolSize
        + femaleRangeSize + femaleOnlyRangeSize

    /// Whether an id belongs to the reserve range `face_02048...face_02559` —
    /// the band the fixed 2026 template drains its overflow into, which the
    /// runtime picker treats as a last resort.
    ///
    /// Deliberately a half-open window rather than "everything above the
    /// generated range": the two female ranges above it are first-class (see
    /// `femaleRangeSize`, `femaleOnlyRangeSize`), and folding them in here
    /// would hide 1 152 perfectly good portraits — every female one among them
    /// — behind the last-resort tier.
    static func isReserve(_ faceID: String) -> Bool {
        guard faceID.hasPrefix("face_"),
              let index = Int(faceID.dropFirst("face_".count))
        else { return false }
        return index >= generatedPoolSize && index < generatedPoolSize + reservePoolSize
    }

    /// `generate_faces.py --seed` default; also stamped into the manifest.
    static let seed = 20260729

    /// `generate_faces.py --coach-share` default (384 of 2048).
    static let coachShare = 0.1875

    /// `generate_faces.py::FEMALE_RANGE_START` — the first id whose coach faces
    /// draw a gender. Ids below it predate the female range and MUST keep their
    /// draw sequence byte-identical, so the gate is on the id, never on the
    /// pool size.
    static let femaleRangeStart = 2560

    /// `generate_faces.py::FEMALE_ONLY_RANGE_START` — the first id that is a
    /// female coach face by definition. Same id-gated discipline as
    /// `femaleRangeStart`: ids below 3 584 keep the draw sequence their shipped
    /// picture was painted from no matter how far the pool is extended.
    static let femaleOnlyRangeStart = 3584

    /// `generate_faces.py --female-coach-share` default — the share of *faces*
    /// in the mixed female range drawn female (35 of the 194 coach faces
    /// there). It does not reach the female-only range, which draws nothing.
    ///
    /// Not to be confused with `CoachingEngine.femaleCoachShare` (0.06), which
    /// is the share of *coaches the game hires*. The generator's is deliberately
    /// the larger of the two: it buys headroom in the library so a 0.06 hiring
    /// rate never runs the female sub-pool dry.
    static let femaleCoachShare = 0.22

    /// `TONES` — editorial approximation of NFL demographics.
    static let tones: [(tag: String, weight: Double)] = [
        ("black", 0.55), ("white", 0.28), ("latino", 0.07),
        ("pacific", 0.04), ("mixed", 0.06),
    ]

    /// `PLAYER_AGES`
    static let playerAges: [(tag: String, weight: Double)] = [
        ("20-24", 0.38), ("25-29", 0.40), ("30-36", 0.22),
    ]

    /// `COACH_AGES`
    static let coachAges: [(tag: String, weight: Double)] = [
        ("38-50", 0.45), ("50-68", 0.55),
    ]

    /// `BUILDS` — used for the `player` role.
    static let playerBuilds: [(tag: String, weight: Double)] = [
        ("lean", 0.30), ("athletic", 0.50), ("heavy", 0.20),
    ]

    /// The inline coach build list in `build_spec` (different weights, same tags).
    static let coachBuilds: [(tag: String, weight: Double)] = [
        ("lean", 0.4), ("athletic", 0.35), ("heavy", 0.25),
    ]

    /// Bundle-relative folder the packaged HEICs land in.
    static let facesFolder = "Faces"

    /// Bundle resource name of the packaged manifest.
    static let manifestResource = "faces_manifest"

    /// Canonical id for a pool index.
    static func faceID(_ index: Int) -> String {
        String(format: "face_%05d", index)
    }

    /// The pool index behind a canonical id, or `nil` if it is not one.
    static func poolIndex(_ faceID: String) -> Int? {
        guard faceID.hasPrefix("face_") else { return nil }
        return Int(faceID.dropFirst("face_".count))
    }

    /// The per-face RNG seed string: `f"{args.seed}:{fid}"`.
    static func rngSeed(for faceID: String) -> String {
        "\(seed):\(faceID)"
    }
}

// MARK: - CPython `random.Random` port

/// A bit-exact port of CPython's `random.Random` — enough of it to reproduce
/// `generate_faces.py`'s bucket draws without the images.
///
/// Why a full Mersenne-Twister port instead of "any deterministic RNG": the
/// synthesized catalog has to agree with the manifest that ships later,
/// face-for-face. A face's bucket decides whether it reads as a 22-year-old
/// receiver or a 60-year-old coordinator; if synthesis and manifest disagreed,
/// a person assigned a face before the images landed would visibly change
/// character afterwards. So the three moving parts are all reproduced:
///
/// 1. **String seeding** — `Random.seed(str)` hashes to
///    `int.from_bytes(s + sha512(s).digest(), "big")`, takes the absolute
///    value, splits it into 32-bit little-endian words and calls
///    `init_by_array`.
/// 2. **MT19937** — `init_genrand(19650218)` + `init_by_array` + the standard
///    tempered generator.
/// 3. **`random()`** — CPython's `genrand_res53`: two draws, `(a*2^26+b)/2^53`.
///
/// Only `random()` is needed: `build_spec` decides role/tone/ageBand/build
/// from the first four `random()` calls, before it ever touches `choice`.
struct PythonRandom {

    private static let n = 624
    private static let m = 397
    private static let matrixA: UInt32 = 0x9908_b0df
    private static let upperMask: UInt32 = 0x8000_0000
    private static let lowerMask: UInt32 = 0x7fff_ffff

    private var mt = [UInt32](repeating: 0, count: PythonRandom.n)
    private var index = PythonRandom.n

    /// Seeds exactly like `random.Random(seed)` for a `str` seed.
    init(seed: String) {
        var bytes = Array(seed.utf8)
        bytes.append(contentsOf: Array(SHA512.hash(data: Data(bytes))))
        initByArray(Self.keyWords(bigEndianBytes: bytes))
    }

    /// Big-endian byte string → the little-endian 32-bit word array CPython's
    /// `random_seed` hands to `init_by_array`. Most-significant zero words are
    /// dropped because CPython sizes the key from the integer's *bit* length.
    private static func keyWords(bigEndianBytes bytes: [UInt8]) -> [UInt32] {
        var words: [UInt32] = []
        var high = bytes.count - 1
        while high >= 0 {
            var word: UInt32 = 0
            for shift in 0..<4 {
                let idx = high - shift
                if idx < 0 { break }
                word |= UInt32(bytes[idx]) << (8 * shift)
            }
            words.append(word)
            high -= 4
        }
        while words.count > 1, words.last == 0 { words.removeLast() }
        return words.isEmpty ? [0] : words
    }

    /// `init_genrand`
    private mutating func initGenrand(_ s: UInt32) {
        mt[0] = s
        for i in 1..<Self.n {
            let prev = mt[i - 1]
            mt[i] = 1_812_433_253 &* (prev ^ (prev >> 30)) &+ UInt32(i)
        }
        index = Self.n
    }

    /// `init_by_array`
    private mutating func initByArray(_ key: [UInt32]) {
        initGenrand(19_650_218)
        var i = 1
        var j = 0
        var k = max(Self.n, key.count)
        while k > 0 {
            let prev = mt[i - 1]
            mt[i] = (mt[i] ^ ((prev ^ (prev >> 30)) &* 1_664_525)) &+ key[j] &+ UInt32(j)
            i += 1
            j += 1
            if i >= Self.n { mt[0] = mt[Self.n - 1]; i = 1 }
            if j >= key.count { j = 0 }
            k -= 1
        }
        k = Self.n - 1
        while k > 0 {
            let prev = mt[i - 1]
            mt[i] = (mt[i] ^ ((prev ^ (prev >> 30)) &* 1_566_083_941)) &- UInt32(i)
            i += 1
            if i >= Self.n { mt[0] = mt[Self.n - 1]; i = 1 }
            k -= 1
        }
        mt[0] = 0x8000_0000
        index = Self.n
    }

    private mutating func twist() {
        for i in 0..<Self.n {
            let y = (mt[i] & Self.upperMask) | (mt[(i + 1) % Self.n] & Self.lowerMask)
            var next = mt[(i + Self.m) % Self.n] ^ (y >> 1)
            if y & 1 == 1 { next ^= Self.matrixA }
            mt[i] = next
        }
        index = 0
    }

    /// `genrand_uint32`
    mutating func nextUInt32() -> UInt32 {
        if index >= Self.n { twist() }
        var y = mt[index]
        index += 1
        y ^= (y >> 11)
        y ^= (y << 7) & 0x9d2c_5680
        y ^= (y << 15) & 0xefc6_0000
        y ^= (y >> 18)
        return y
    }

    /// `random.random()` — CPython's `genrand_res53`.
    mutating func random() -> Double {
        let a = Double(nextUInt32() >> 5)
        let b = Double(nextUInt32() >> 6)
        return (a * 67_108_864.0 + b) * (1.0 / 9_007_199_254_740_992.0)
    }
}

// MARK: - Catalog synthesis

/// Rebuilds the full 3 712-face id + bucket list from the generator seed
/// (2 048 generated + the 512-id reserve range the fixed template draws its
/// overflow from + the 1 024-id female range + the 128-id female-only range).
///
/// This is the fallback the app runs on until `faces_manifest.json` is in the
/// bundle: the buckets are a pure function of `(seed, faceID)`, so assignment
/// is fully determined long before a single image exists. Once the manifest
/// ships it wins — it is the authority on which ids actually made it through
/// QA (culled ids are absent) — but the two agree on every surviving id.
///
/// Verified against the live generator output: all 3 712 faces produced
/// synthesize to byte-identical buckets — gender included, across both female
/// range boundaries — and `make_templates.py` gate 19 re-runs that comparison
/// from the Python side on every template build.
///
/// Cost: 3 712 × (SHA-512 + `init_by_array` + one twist) ≈ 36 ms in Release,
/// ~500 ms in a Debug build, paid ONCE per app session by
/// `FaceLibrary.ensureCatalogLoaded` — and not at all once the manifest ships.
enum FaceCatalogSynthesizer {

    /// Port of `generate_faces.py::wpick`, including the accumulation order.
    static func weightedPick(_ rng: inout PythonRandom, _ items: [(tag: String, weight: Double)]) -> String {
        let total = items.reduce(0.0) { $0 + $1.weight }
        let r = rng.random() * total
        var acc = 0.0
        for item in items {
            acc += item.weight
            if r <= acc { return item.tag }
        }
        return items[items.count - 1].tag
    }

    /// Port of the bucket half of `generate_faces.py::build_spec` — the prompt
    /// half (hair / facial hair / style text) is irrelevant to the app and is
    /// deliberately not reproduced. The draw order (role, gender, tone, ageBand,
    /// build) is load-bearing: each `wpick` consumes exactly one `random()`, and
    /// so does the gender draw.
    static func bucket(forFaceID faceID: String) -> FaceBucket {
        var rng = PythonRandom(seed: FaceGeneratorConstants.rngSeed(for: faceID))
        let index = FaceGeneratorConstants.poolIndex(faceID) ?? 0
        let role: String
        var gender = "male"
        if index >= FaceGeneratorConstants.femaleOnlyRangeStart {
            // `generate_faces.py::work` — the female-only range states its role
            // and gender instead of drawing them, and consumes NO `random()`
            // doing so, so `tone` below reads the FIRST value off this stream.
            // Skipping the two draws is the whole point: a draw with a
            // predetermined outcome would only shift the tone/age/build stream
            // for nothing.
            role = "coach"
            gender = "female"
        } else {
            role = rng.random() < FaceGeneratorConstants.coachShare ? "coach" : "player"
            // ONE extra draw, coach-only, ids 2560..3583. Gated on the id and
            // never on the pool size, so every id below the female range keeps
            // the bucket its shipped picture was painted from. Python emits a
            // `"gender"` key for new-range players too, but it never draws for
            // them: the key's presence only matters inside the Python gate, the
            // VALUE is what has to match here.
            if index >= FaceGeneratorConstants.femaleRangeStart, role == "coach" {
                gender = rng.random() < FaceGeneratorConstants.femaleCoachShare ? "female" : "male"
            }
        }
        let tone = weightedPick(&rng, FaceGeneratorConstants.tones)
        let ageBand = weightedPick(
            &rng,
            role == "coach" ? FaceGeneratorConstants.coachAges : FaceGeneratorConstants.playerAges
        )
        let build = weightedPick(
            &rng,
            role == "player" ? FaceGeneratorConstants.playerBuilds : FaceGeneratorConstants.coachBuilds
        )
        return FaceBucket(role: role, gender: gender, ageBand: ageBand, tone: tone, build: build)
    }

    /// The whole synthesized pool, in id order.
    static func synthesize(poolSize: Int = FaceGeneratorConstants.poolSize) -> [FaceEntry] {
        (0..<poolSize).map { index in
            let id = FaceGeneratorConstants.faceID(index)
            return FaceEntry(
                id: id,
                file: "\(FaceGeneratorConstants.facesFolder)/\(id).heic",
                bucket: bucket(forFaceID: id)
            )
        }
    }
}
