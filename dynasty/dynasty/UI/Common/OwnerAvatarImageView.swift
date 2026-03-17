import SwiftUI

/// Displays an owner avatar from a pre-cropped individual image.
struct OwnerAvatarImageView: View {
    let avatarID: String   // "owner_m1" etc — matches the asset name
    var size: CGFloat = 64
    var grayscale: Bool = false

    var body: some View {
        Image(avatarID)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
            .saturation(grayscale ? 0 : 1)
            .overlay(
                Circle()
                    .strokeBorder(Color.surfaceBorder, lineWidth: 1.5)
            )
    }
}

/// All available owner avatar IDs.
enum OwnerAvatars {
    static let allIDs: [String] = [
        "owner_m1", "owner_m2", "owner_m3", "owner_m4", "owner_m5",
        "owner_m6", "owner_m7", "owner_m8", "owner_m9", "owner_m10", "owner_m11",
        "owner_f1", "owner_f2", "owner_f3"
    ]

    /// Returns a deterministic owner avatar ID based on the owner's name.
    static func avatarID(for ownerName: String) -> String {
        let hash = abs(ownerName.hashValue)
        let index = hash % allIDs.count
        return allIDs[index]
    }
}

#Preview {
    ZStack {
        Color.backgroundPrimary.ignoresSafeArea()
        VStack(spacing: 20) {
            HStack(spacing: 16) {
                OwnerAvatarImageView(avatarID: "owner_m1", size: 80)
                OwnerAvatarImageView(avatarID: "owner_m2", size: 80)
                OwnerAvatarImageView(avatarID: "owner_m3", size: 80)
                OwnerAvatarImageView(avatarID: "owner_f1", size: 80)
            }
            HStack(spacing: 16) {
                OwnerAvatarImageView(avatarID: "owner_m4", size: 80, grayscale: true)
                OwnerAvatarImageView(avatarID: "owner_m5", size: 80, grayscale: true)
                OwnerAvatarImageView(avatarID: "owner_f2", size: 80, grayscale: true)
                OwnerAvatarImageView(avatarID: "owner_f3", size: 80, grayscale: true)
            }
        }
    }
}
