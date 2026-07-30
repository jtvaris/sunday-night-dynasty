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
enum PersonFacePlaceholder {
    /// Neutral silhouette — nothing is known beyond the (missing) face id.
    case silhouette
    /// The procedural, UUID-derived helmet avatar (`PlayerAvatarView`): every
    /// player gets a different skin tone, face shape, facemask and jersey
    /// number, and it always renders.
    case playerAvatar(Player)
    /// One of the 20 bundled `coach_m*`/`coach_f*` photographs, picked stably
    /// from a person id.
    case coachAvatar(String)
    /// One of the illustrated `owner_m*`/`owner_f*` portraits — what every owner
    /// surface drew before the AI executive photographs existed, and therefore
    /// the natural fallback for an owner whose `faceID` is nil (a career created
    /// before the field, or a build without the extras).
    case ownerAvatar(String)
    /// Initials on a per-person tinted disc — for people with no `Player` row
    /// and no bundled asset (draft prospects).
    case monogram(initials: String, seed: UUID)
}

extension CoachAvatars {

    /// A stable pick from the bundled coach portraits **of the matching
    /// gender**.
    ///
    /// Deliberately NOT `fullName.hashValue`, which is what the pre-face-library
    /// code used: Swift's string hashing is seeded per process, so that version
    /// handed the same coach a different photo on every launch. `stableHash` is
    /// FNV-1a over the person's UUID bytes and survives relaunches.
    ///
    /// Scoped by gender because `all` is 10 `coach_m*` + 10 `coach_f*`: the
    /// unscoped version drew from the mixed list, so roughly half of every male
    /// coach in the game wore a woman's photograph. The male default keeps the
    /// one gender-less caller (`Career.avatarID`, chosen in the new-career
    /// wizard) source-compatible, and an empty sub-list falls back to the full
    /// list so a pruned asset catalog degrades instead of returning a missing
    /// image name.
    static func avatarID(
        for personID: UUID,
        gender: CoachAvatarInfo.Gender = .male
    ) -> String {
        let scoped = (gender == .female ? femaleAvatars : maleAvatars).map(\.id)
        let ids = scoped.isEmpty ? all.map(\.id) : scoped
        guard !ids.isEmpty else { return gender == .female ? "coach_f1" : "coach_m1" }
        return ids[Int(FaceLibrary.stableHash(personID) % UInt64(ids.count))]
    }
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
        case .playerAvatar(let player):
            PlayerAvatarView(player: player, size: size.diameter)
        case .coachAvatar(let avatarID):
            CoachAvatarImageView(avatarID: avatarID, size: size.diameter)
        case .ownerAvatar(let avatarID):
            OwnerAvatarImageView(avatarID: avatarID, size: size.diameter)
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
nonisolated final class FaceImageCache: @unchecked Sendable {

    static let shared = FaceImageCache()

    /// Longest edge the cache keeps, in pixels: `.large` (96 pt) at 3×.
    /// Bundled faces are 384², so this is a mild downscale for the biggest
    /// call site and a big one for the 30 pt rows that dominate.
    private static let maxPixelSize = 288

    /// ~40 decoded 288² thumbnails (288 × 288 × 4 B ≈ 332 kB each).
    private static let byteLimit = 16 * 1024 * 1024

    private let cache = NSCache<NSString, UIImage>()
    private let lock = NSLock()
    private var misses: Set<String> = []

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
        lock.unlock()
        if knownMiss { return nil }

        guard let url = Self.bundleURL(for: faceID) else {
            noteMiss(faceID)
            return nil
        }
        let maxPixel = Self.maxPixelSize
        let decoded = await Task.detached(priority: .userInitiated) {
            Self.decodeThumbnail(at: url, maxPixel: maxPixel)
        }.value
        guard let decoded else {
            noteMiss(faceID)
            return nil
        }
        let image = UIImage(cgImage: decoded)
        cache.setObject(image, forKey: faceID as NSString, cost: decoded.height * decoded.bytesPerRow)
        return image
    }

    private func noteMiss(_ faceID: String) {
        lock.lock()
        misses.insert(faceID)
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

    init(player: Player, size: Size = .medium, ringColor: Color? = nil) {
        self.init(
            faceID: player.faceID,
            size: size,
            ringColor: ringColor,
            accessibilityName: player.fullName,
            placeholder: .playerAvatar(player)
        )
    }

    init(coach: Coach, size: Size = .medium, ringColor: Color? = nil) {
        self.init(
            faceID: coach.faceID,
            size: size,
            ringColor: ringColor,
            accessibilityName: coach.fullName,
            // A nil `faceID` is the normal outcome for a female coach hired past
            // the 35-face ceiling (`FaceLibrary.pickLocked` stage 20), so this
            // placeholder has to be gender-correct — it is the fallback the
            // gender-strict picker deliberately falls back TO.
            placeholder: .coachAvatar(
                CoachAvatars.avatarID(for: coach.id, gender: coach.avatarGender)
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

    /// The user's own head-coach portrait: the avatar they picked in the new-
    /// career wizard, so the person they created is not the only face-less row
    /// on their own staff screen.
    ///
    /// `Career.avatarID` holds whatever the picker wrote, and the picker offers
    /// two families (`AvatarSelectionView`): the illustrated `coach_m*`/`coach_f*`
    /// asset-catalog art and the 20 AI photo headshots
    /// (`avatar_00000`…`avatar_00019`, `ExtrasCatalog`). Only the first kind is an
    /// asset — a photo id has to travel the ordinary face path, through
    /// `FaceImageCache`, so it is decoded off the main thread, downscaled once and
    /// shared with every other portrait on screen. Hence the split: a photo id
    /// becomes the `faceID` (and falls back to the neutral silhouette if the HEICs
    /// did not ship), an illustrated id stays a placeholder.
    ///
    /// The prefix test is manifest-independent on purpose — a saved career must
    /// not render a missing asset-catalog image in a build whose extras manifest
    /// failed to load.
    init(careerAvatarID: String, size: Size = .medium, ringColor: Color? = nil, name: String? = nil) {
        let isPhoto = ExtrasCatalog.isAvatarID(careerAvatarID)
        self.init(
            faceID: isPhoto ? careerAvatarID : nil,
            size: size,
            ringColor: ringColor,
            accessibilityName: name,
            placeholder: isPhoto ? .silhouette : .coachAvatar(careerAvatarID)
        )
    }

    /// A league owner's portrait: the AI executive photograph when the extras
    /// shipped, otherwise the illustrated `owner_m*`/`owner_f*` avatar the owner
    /// screens have always shown.
    init(owner: Owner, size: Size = .medium, ringColor: Color? = nil) {
        self.init(
            faceID: owner.faceID,
            size: size,
            ringColor: ringColor,
            accessibilityName: owner.name,
            placeholder: .ownerAvatar(owner.avatarID)
        )
    }

    static func initials(_ first: String, _ last: String) -> String {
        let f = first.first.map(String.init) ?? ""
        let l = last.first.map(String.init) ?? ""
        let combined = (f + l).uppercased()
        return combined.isEmpty ? "?" : combined
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
            Text("Per-person fallbacks: bundled coach photo + monogram")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
            HStack(alignment: .center, spacing: 16) {
                PersonFaceView(careerAvatarID: "coach_m3", size: .small, ringColor: .accentGold)
                PersonFaceView(careerAvatarID: "coach_f4", size: .medium, ringColor: .accentGold)
                // AI photo pick — travels the FaceImageCache path, not the assets.
                PersonFaceView(careerAvatarID: "avatar_00000", size: .medium, ringColor: .accentGold)
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
