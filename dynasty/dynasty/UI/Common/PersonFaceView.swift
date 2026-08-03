import SwiftUI
import ImageIO

// MARK: - Placeholder identity

/// What a portrait falls back to when the face library has no image for this
/// person — which today is EVERY person, and after packaging is still everyone
/// holding a reserve-range id (`docs/FACE_GENERATION_PLAN.md` §6).
///
/// A single shared silhouette was the original fallback and it looked clean in
/// isolation while being useless in bulk: 53 identical discs down a roster,
/// which is worse than the per-person avatars this app already had. So every
/// caller that knows *who* the person is hands over an identity source, and the
/// silhouette is reserved for the case where nothing is known (a news item that
/// only carries a face id, a Hall-of-Fame row whose player row is long gone).
///
/// ## No drawn faces
///
/// There used to be three more cases here, each of which drew an *illustration*
/// of a person: a Canvas-rendered helmet cartoon for players, a hand-drawn
/// `coach_m*` portrait for coaches, a hand-drawn `owner_m*` portrait for owners.
/// They are gone. Sitting next to 3 712 photographic faces, a cartoon does not
/// read as "this person has no photo yet" — it reads as a different, worse art
/// style leaking into the same list. A monogram is honest about being a
/// stand-in, so that is the only per-person fallback left.
enum PersonFacePlaceholder {
    /// Neutral silhouette — nothing is known beyond the (missing) face id.
    case silhouette
    /// Initials on a per-person tinted disc — the fallback for anyone whose
    /// photograph has not shipped (draft prospects, a coach past the face-pool
    /// ceiling, an owner in a build without the extras).
    case monogram(initials: String, seed: UUID)
}

// MARK: - PersonFaceView

/// The portrait view for anyone in the league — player, coach, prospect.
///
/// Renders `Faces/<faceID>.heic` from the app bundle, or a per-person fallback
/// (see `PersonFacePlaceholder`) when there is no face id yet **or** the image
/// simply is not there. The second case is normal, not an error: the library
/// generates out-of-band and the manifest may ship ahead of the pictures, so a
/// bundle with zero HEICs has to look deliberate rather than broken — and has
/// to keep 53 people on a roster telling apart.
///
/// The image itself is decoded OFF the main thread (`FaceImageCache`), because a
/// screenful of first-time rows is ~16 decodes and doing those inline in `body`
/// put them straight into the frame that scrolled them into view.
struct PersonFaceView: View {

    /// Portrait sizes used across the app.
    enum Size {
        /// Roster/list rows.
        case small
        /// Cards, staff tiles, draft panels.
        case medium
        /// Detail-screen headers.
        case large

        /// Diameters are chosen so a portrait can be dropped into an existing
        /// row WITHOUT changing its height: `.small` matches the ~30 pt content
        /// height of a two-line roster/prospect row, so the list keeps its
        /// current rhythm whether or not the images have shipped.
        var diameter: CGFloat {
            switch self {
            case .small:  return 30
            case .medium: return 56
            case .large:  return 96
            }
        }

        var ringWidth: CGFloat {
            switch self {
            case .small:  return 1.5
            case .medium: return 2
            case .large:  return 3
            }
        }
    }

    let faceID: String?
    var size: Size = .medium
    /// Optional team accent for the ring. `nil` draws the neutral border.
    var ringColor: Color? = nil
    /// Spoken/VoiceOver name of the person, when the caller has one.
    var accessibilityName: String? = nil
    /// What to draw while (or instead of) the library image.
    var placeholder: PersonFacePlaceholder = .silhouette

    /// Seeded synchronously from the in-memory cache so an already-decoded
    /// portrait draws on the FIRST frame (no placeholder flash when scrolling
    /// back up a list); a miss is filled in by the `.task` below.
    @State private var image: UIImage?

    init(
        faceID: String?,
        size: Size = .medium,
        ringColor: Color? = nil,
        accessibilityName: String? = nil,
        placeholder: PersonFacePlaceholder = .silhouette
    ) {
        self.faceID = faceID
        self.size = size
        self.ringColor = ringColor
        self.accessibilityName = accessibilityName
        self.placeholder = placeholder
        _image = State(initialValue: FaceImageCache.shared.cachedImage(for: faceID))
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                placeholderView
            }
        }
        .frame(width: size.diameter, height: size.diameter)
        .clipShape(Circle())
        .overlay(
            Circle().strokeBorder(
                ringColor ?? Color.surfaceBorder,
                lineWidth: ringColor == nil ? 1 : size.ringWidth
            )
        )
        .accessibilityLabel(accessibilityName.map { "\($0) portrait" } ?? "Portrait")
        .task(id: faceID) {
            guard image == nil, let faceID else { return }
            image = await FaceImageCache.shared.loadImage(for: faceID)
        }
    }

    // MARK: - Placeholder

    @ViewBuilder
    private var placeholderView: some View {
        switch placeholder {
        case .silhouette:
            silhouette
        case .monogram(let initials, let seed):
            monogram(initials: initials, seed: seed)
        }
    }

    /// A neutral silhouette. Deliberately flat and quiet — it should read as
    /// "no photo" and never compete with a real portrait next to it.
    private var silhouette: some View {
        ZStack {
            Circle().fill(
                LinearGradient(
                    colors: [Color.backgroundTertiary, Color.backgroundSecondary],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .scaledToFit()
                .padding(size.diameter * 0.07)
                .foregroundStyle(Color.textTertiary.opacity(0.55))
        }
    }

    /// Initials on a disc tinted from the person's id — distinguishable at a
    /// glance down a 350-row board, and stable for the same person forever.
    private func monogram(initials: String, seed: UUID) -> some View {
        let hue = Double(FaceLibrary.stableHash(seed) % 360) / 360.0
        return ZStack {
            Circle().fill(
                LinearGradient(
                    colors: [
                        Color(hue: hue, saturation: 0.34, brightness: 0.42),
                        Color(hue: hue, saturation: 0.40, brightness: 0.26),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            Text(initials)
                .font(.system(size: size.diameter * 0.40, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.88))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
    }
}

// MARK: - Image cache

/// Small in-memory cache in front of the bundled HEICs.
///
/// Three things it has to get right, all of them measured rather than assumed
/// (a 384² HEIC at the shipping spec is ~11 kB on disk and ~590 kB decoded):
///
/// 1. **Bounded in bytes, not in count.** A count-only limit of 160 full-size
///    bitmaps is ~90 MB of RAM to draw 30 pt circles, next to the SceneKit
///    match view. Every entry is stored with its byte cost against
///    `totalCostLimit`.
/// 2. **Decoded once, small.** Nothing on screen is wider than `.large` (96 pt
///    ⇒ 288 px at 3×), so the cache holds a thumbnail of that size instead of
///    the full bitmap — 18× less memory per entry.
/// 3. **Off the main thread.** `UIImage(contentsOfFile:)` defers the decode to
///    first draw, which lands it in the frame that scrolled the row into view.
///    `loadImage(for:)` decodes on a detached task, so a fling through the
///    350-row Big Board costs no frames.
///
/// Every miss is remembered too (`misses`): with the library still generating,
/// most lookups fail, and re-hitting the bundle for every scroll frame of a
/// 53-row roster would be pure waste. Nothing here can throw or trap — a
/// missing, unreadable or corrupt file all resolve to `nil`.
///
/// ## Why the decode is rationed
///
/// The first version dispatched one `Task.detached` per portrait. That reads as
/// "get off the main thread", but a detached task runs on the **Swift
/// cooperative pool**, whose width is the core count — and `CGImageSource`
/// thumbnailing is a *blocking* call, so each one parks a pool thread for the
/// whole decode. A screenful of 20-53 faces therefore parked every thread the
/// process has for async work, and the starvation was global: coach-candidate
/// generation, league loading, every `.task` in the app queued behind portraits.
/// On a device with a hardware HEVC decoder each decode is milliseconds and the
/// bug is invisible; in the Simulator, where HEVC is decoded in software, it is
/// a hard hang (19 of 30 threads inside `decodeThumbnail`).
///
/// The fix is two rules, both enforced here rather than at the call sites:
///
/// 1. Decodes run on a **private GCD queue**, never on the cooperative pool, so
///    a blocked decode can never be a blocked `async` task somewhere else.
/// 2. At most `maxConcurrentDecodes` run at once (`DecodeGate`). Callers past
///    the limit *suspend* — they do not occupy a thread — and a caller whose
///    view scrolled away is dropped when its turn comes rather than decoded.
nonisolated final class FaceImageCache: @unchecked Sendable {

    static let shared = FaceImageCache()

    // MARK: - Decode rationing

    /// Admission control for the decoder: `limit` concurrent decodes, everyone
    /// else suspended (not blocked) until a slot frees.
    private actor DecodeGate {
        private let limit: Int
        private var active = 0
        private var waiters: [CheckedContinuation<Void, Never>] = []

        init(limit: Int) { self.limit = max(1, limit) }

        func acquire() async {
            if active < limit {
                active += 1
                return
            }
            await withCheckedContinuation { waiters.append($0) }
        }

        func release() {
            if waiters.isEmpty {
                active = max(0, active - 1)
            } else {
                waiters.removeFirst().resume()
            }
        }
    }

    /// Two cores' worth of decoding, never more than 3. Enough to keep a scroll
    /// filling in, small enough that the rest of the app never notices.
    private static let maxConcurrentDecodes =
        min(3, max(1, ProcessInfo.processInfo.activeProcessorCount - 2))

    private let gate = DecodeGate(limit: FaceImageCache.maxConcurrentDecodes)

    /// Private, off the cooperative pool. Concurrent because the gate — not the
    /// queue — is what bounds the width.
    private static let decodeQueue = DispatchQueue(
        label: "com.dynasty.faces.decode",
        qos: .userInitiated,
        attributes: .concurrent
    )

    /// Longest edge the cache keeps, in pixels: `.large` (96 pt) at 3×.
    /// Bundled faces are 384², so this is a mild downscale for the biggest
    /// call site and a big one for the 30 pt rows that dominate.
    private static let maxPixelSize = 288

    /// ~40 decoded 288² thumbnails (288 × 288 × 4 B ≈ 332 kB each).
    private static let byteLimit = 16 * 1024 * 1024

    private let cache = NSCache<NSString, UIImage>()
    private let lock = NSLock()
    /// Ids proven not to be in the bundle. A packaging fact, so it never expires.
    private var misses: Set<String> = []
    /// Ids whose file EXISTS but whose decode failed, and how often. A decode
    /// can fail for reasons that are not about the file — memory pressure above
    /// all — so one failure must not blank a face for the rest of the launch,
    /// which is what a single shared miss set used to do.
    private var decodeFailures: [String: Int] = [:]

    /// Decode attempts a present-but-unreadable file gets before it is written
    /// off. Three is enough to ride out a transient; small enough that a genuinely
    /// corrupt image is not re-decoded on every scroll frame.
    private static let maxDecodeAttempts = 3

    private init() {
        cache.countLimit = 160
        cache.totalCostLimit = Self.byteLimit
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.purge()
        }
    }

    /// Cache-only lookup — never touches the filesystem. Used to seed a view's
    /// state synchronously so a warm portrait draws on its first frame.
    func cachedImage(for faceID: String?) -> UIImage? {
        guard let faceID, !faceID.isEmpty else { return nil }
        return cache.object(forKey: faceID as NSString)
    }

    /// Cache, then a decode on a background task. Returns `nil` for a face
    /// whose image has not shipped (the normal case today), and remembers that
    /// so the bundle is probed at most once per id per launch.
    func loadImage(for faceID: String) async -> UIImage? {
        guard !faceID.isEmpty else { return nil }
        if let cached = cachedImage(for: faceID) { return cached }

        lock.lock()
        let knownMiss = misses.contains(faceID)
            || (decodeFailures[faceID] ?? 0) >= Self.maxDecodeAttempts
        lock.unlock()
        if knownMiss { return nil }

        guard let url = Self.bundleURL(for: faceID) else {
            noteMiss(faceID)
            return nil
        }

        // Wait for a decoder slot. Suspends — no thread is held while queued.
        // The slot is released on EVERY exit below; `defer` is not used because
        // releasing it needs an `await`.
        await gate.acquire()

        // The row that asked may be long gone by the time a slot frees (a fling
        // through the 350-row Big Board queues hundreds). Decoding for a
        // cancelled view is pure waste, and skipping it is what keeps a fast
        // scroll from paying for every row it flew past.
        if Task.isCancelled {
            await gate.release()
            return nil
        }

        // Another caller may have decoded the same id while this one waited.
        if let cached = cachedImage(for: faceID) {
            await gate.release()
            return cached
        }

        let maxPixel = Self.maxPixelSize
        let decoded: CGImage? = await withCheckedContinuation { continuation in
            Self.decodeQueue.async {
                continuation.resume(returning: Self.decodeThumbnail(at: url, maxPixel: maxPixel))
            }
        }
        await gate.release()

        guard let decoded else {
            noteDecodeFailure(faceID)
            return nil
        }
        let image = UIImage(cgImage: decoded)
        cache.setObject(image, forKey: faceID as NSString, cost: decoded.height * decoded.bytesPerRow)
        return image
    }

    /// The file is not in the bundle. Permanent for this launch — packaging
    /// does not change while the app runs.
    private func noteMiss(_ faceID: String) {
        lock.lock()
        misses.insert(faceID)
        lock.unlock()
    }

    /// The file is there but would not decode. Counted, not blacklisted, so a
    /// transient failure costs one retry instead of the whole session.
    private func noteDecodeFailure(_ faceID: String) {
        lock.lock()
        decodeFailures[faceID, default: 0] += 1
        lock.unlock()
    }

    /// Fully decodes a bundled portrait at a bounded size, on whatever thread
    /// calls it. `shouldCacheImmediately` forces the pixel work here instead of
    /// leaving it for the render pass.
    private static func decodeThumbnail(at url: URL, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Drops the cache. Also clears the miss set, so images that landed in a
    /// later build/download are picked up without a relaunch.
    func purge() {
        cache.removeAllObjects()
        lock.lock()
        misses.removeAll()
        decodeFailures.removeAll()
        lock.unlock()
    }

    /// Where a face's image resolves in the bundle. Deliberately not private:
    /// `FaceBundleAudit` measures packaging through THIS function, so the audit
    /// can never pass on a lookup the renderer does not actually perform.
    static func bundleURL(for faceID: String) -> URL? {
        Bundle.main.url(
            forResource: faceID,
            withExtension: "heic",
            subdirectory: FaceGeneratorConstants.facesFolder
        ) ?? Bundle.main.url(forResource: faceID, withExtension: "heic")
    }
}

// MARK: - Convenience initializers

extension PersonFaceView {

    /// The face id is resolved through `AgedFaceCatalog` on the way in, so a
    /// player who has aged past `playerAgeThreshold` renders the older variant of
    /// the portrait he has always worn.
    ///
    /// Render-time only: the resolved id is never written back to `player.faceID`.
    /// The stored id stays the person's identity for the whole save — the claim
    /// registry, the retirement cooldown and every duplicate check key on it —
    /// and only the pixels change. That also makes the swap free to undo: pull
    /// the aged manifest and every portrait is exactly what it was.
    init(player: Player, size: Size = .medium, ringColor: Color? = nil) {
        self.init(
            faceID: AgedFaceCatalog.shared.resolveForPlayer(
                faceID: player.faceID, age: player.age
            ),
            size: size,
            ringColor: ringColor,
            accessibilityName: player.fullName,
            // Was a procedurally drawn helmet cartoon. A roster is 53 rows of
            // photographs with a handful of gaps; a cartoon in those gaps looked
            // like a different game, initials look like a missing photo.
            placeholder: .monogram(
                initials: Self.initials(player.firstName, player.lastName),
                seed: player.id
            )
        )
    }

    /// Same age-variant resolution as the player initializer, on the coach clock
    /// (`AgedFaceCatalog.coachAgeThreshold`) — the one this whole layer exists for,
    /// since a coach can be hired at 46 and still be on the sideline at 70.
    init(coach: Coach, size: Size = .medium, ringColor: Color? = nil) {
        self.init(
            faceID: AgedFaceCatalog.shared.resolveForCoach(
                faceID: coach.faceID, age: coach.age
            ),
            size: size,
            ringColor: ringColor,
            accessibilityName: coach.fullName,
            // A nil `faceID` is the normal outcome for a female coach hired past
            // the 35-face ceiling (`FaceLibrary.pickLocked` stage 20). The old
            // fallback drew one of the 20 illustrated `coach_*` portraits and
            // therefore had to be gender-matched; a monogram carries no gender to
            // get wrong, which removes that whole failure mode.
            placeholder: .monogram(
                initials: Self.initials(coach.firstName, coach.lastName),
                seed: coach.id
            )
        )
    }

    init(prospect: CollegeProspect, size: Size = .medium, ringColor: Color? = nil) {
        self.init(
            faceID: prospect.faceID,
            size: size,
            ringColor: ringColor,
            accessibilityName: "\(prospect.firstName) \(prospect.lastName)",
            placeholder: .monogram(
                initials: Self.initials(prospect.firstName, prospect.lastName),
                seed: prospect.id
            )
        )
    }

    /// A league owner's portrait: one of the 96 AI executive photographs
    /// (`ExtrasCatalog`), or the owner's initials when the extras did not ship.
    ///
    /// The illustrated `owner_m*`/`owner_f*` art that used to fill that gap is
    /// gone with the rest of the drawn faces; `Owner.avatarID` still exists as a
    /// stored property (dropping it would be a schema change for no gain) but
    /// nothing renders it.
    init(owner: Owner, size: Size = .medium, ringColor: Color? = nil) {
        self.init(
            faceID: owner.faceID,
            size: size,
            ringColor: ringColor,
            accessibilityName: owner.name,
            placeholder: .monogram(
                initials: Self.initials(fromFullName: owner.name),
                seed: owner.id
            )
        )
    }

    static func initials(_ first: String, _ last: String) -> String {
        let f = first.first.map(String.init) ?? ""
        let l = last.first.map(String.init) ?? ""
        let combined = (f + l).uppercased()
        return combined.isEmpty ? "?" : combined
    }

    /// Initials from a single "First Last" string — for the people the app
    /// stores as one name (owners, and the user's own career name).
    static func initials(fromFullName name: String) -> String {
        let parts = name
            .split(whereSeparator: { $0 == " " || $0 == "\u{00A0}" })
            .filter { !$0.isEmpty }
        guard let first = parts.first else { return "?" }
        if parts.count == 1 {
            return String(first.prefix(1)).uppercased()
        }
        return initials(String(first), String(parts[parts.count - 1]))
    }
}

// MARK: - Preview

#Preview("Person faces") {
    ZStack {
        Color.backgroundPrimary.ignoresSafeArea()
        VStack(spacing: 24) {
            Text("Images missing (expected until the library ships) — silhouette")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
            HStack(alignment: .center, spacing: 16) {
                PersonFaceView(faceID: "face_00000", size: .small)
                PersonFaceView(faceID: "face_00001", size: .medium)
                PersonFaceView(faceID: "face_00002", size: .large)
            }
            Text("Per-person fallback: monogram (the only one left)")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
            HStack(alignment: .center, spacing: 16) {
                // The user's own portrait — an AI photo travelling the
                // FaceImageCache path, never an asset-catalog illustration.
                UserPortraitView(avatarID: "avatar_00000", name: "Juha Varis", size: .medium)
                PersonFaceView(
                    faceID: nil, size: .medium, ringColor: .accentBlue,
                    placeholder: .monogram(initials: "JV", seed: UUID())
                )
                PersonFaceView(
                    faceID: nil, size: .large,
                    placeholder: .monogram(initials: "DK", seed: UUID())
                )
            }
        }
        .padding()
    }
}
