import SwiftUI

/// Displays a single coach avatar by id, at any diameter.
///
/// Two families of id live in the same namespace and this view is the seam
/// between them:
///
/// * `coach_m1`…`coach_f10` — the 20 **illustrated** portraits, pre-cropped in
///   the asset catalog.
/// * `avatar_00000`…`avatar_00019` — the 20 **AI photo** headshots from
///   `ExtrasCatalog`, which ship as bundled HEICs and are NOT in the asset
///   catalog. `Image("avatar_00007")` would silently draw nothing, so the branch
///   below is what keeps a saved `Career.avatarID` renderable wherever it is
///   read.
///
/// Callers never have to know which family an id belongs to — that is the point.
struct CoachAvatarImageView: View {
    let avatarID: String   // "coach_m1" or "avatar_00007"
    var size: CGFloat = 80

    var body: some View {
        if ExtrasCatalog.isAvatarID(avatarID) {
            BundledFacePhotoView(faceID: avatarID, size: size)
        } else {
            Image(avatarID)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .strokeBorder(Color.surfaceBorder, lineWidth: 1.5)
                )
        }
    }
}

/// A bundled face HEIC at an arbitrary diameter, decoded through the same
/// `FaceImageCache` every real portrait uses (off the main thread, downscaled
/// once, bounded in bytes).
///
/// `PersonFaceView` covers the three canonical portrait sizes; this exists for
/// the one place that needs a free diameter — the avatar picker's grid, whose
/// cell size is a caller-supplied `CGFloat`. It deliberately shares the cache
/// rather than decoding its own copy, so a picked avatar is already warm
/// everywhere else it appears.
struct BundledFacePhotoView: View {
    let faceID: String
    var size: CGFloat = 80

    @State private var image: UIImage?

    init(faceID: String, size: CGFloat = 80) {
        self.faceID = faceID
        self.size = size
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
                // Same quiet "no photo" disc `PersonFaceView` draws — reached
                // only when the extras HEICs did not ship.
                ZStack {
                    Circle().fill(Color.backgroundTertiary)
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .padding(size * 0.07)
                        .foregroundStyle(Color.textTertiary.opacity(0.55))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle().strokeBorder(Color.surfaceBorder, lineWidth: 1.5)
        )
        .task(id: faceID) {
            guard image == nil else { return }
            image = await FaceImageCache.shared.loadImage(for: faceID)
        }
    }
}

#Preview {
    ZStack {
        Color.backgroundPrimary.ignoresSafeArea()
        VStack(spacing: 20) {
            HStack(spacing: 16) {
                CoachAvatarImageView(avatarID: "coach_m1", size: 80)
                CoachAvatarImageView(avatarID: "coach_m2", size: 80)
                CoachAvatarImageView(avatarID: "coach_m3", size: 80)
                CoachAvatarImageView(avatarID: "coach_m4", size: 80)
                CoachAvatarImageView(avatarID: "coach_m5", size: 80)
            }
            HStack(spacing: 16) {
                CoachAvatarImageView(avatarID: "coach_f1", size: 80)
                CoachAvatarImageView(avatarID: "coach_f2", size: 80)
                CoachAvatarImageView(avatarID: "coach_f3", size: 80)
                CoachAvatarImageView(avatarID: "coach_f4", size: 80)
                CoachAvatarImageView(avatarID: "coach_f5", size: 80)
            }
            // AI photo picks — resolve through FaceImageCache, not the asset catalog.
            HStack(spacing: 16) {
                CoachAvatarImageView(avatarID: "avatar_00000", size: 80)
                CoachAvatarImageView(avatarID: "avatar_00007", size: 80)
                CoachAvatarImageView(avatarID: "avatar_00012", size: 80)
                CoachAvatarImageView(avatarID: "avatar_00019", size: 80)
            }
        }
    }
}
