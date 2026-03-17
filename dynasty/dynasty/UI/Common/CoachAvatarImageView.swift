import SwiftUI

/// Displays a single coach avatar from a pre-cropped individual image.
struct CoachAvatarImageView: View {
    let avatarID: String   // "coach_m1" etc — matches the asset name
    var size: CGFloat = 80

    var body: some View {
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
        }
    }
}
