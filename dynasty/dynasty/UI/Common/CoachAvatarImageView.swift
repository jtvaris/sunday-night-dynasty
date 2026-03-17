import SwiftUI

/// Displays a single coach avatar cropped from a grid image.
/// The grid images are 5 columns x 3 rows of portraits.
struct CoachAvatarImageView: View {
    let gridImage: String
    let row: Int    // 0-2
    let col: Int    // 0-4
    var size: CGFloat = 80

    var body: some View {
        GeometryReader { _ in
            Image(gridImage)
                .resizable()
                .scaledToFill()
                .frame(width: size * 5, height: size * 3.3)
                .offset(
                    x: -size * CGFloat(col),
                    y: -size * 1.1 * CGFloat(row)
                )
        }
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
        HStack(spacing: 16) {
            CoachAvatarImageView(gridImage: "CoachAvatarGrid1", row: 0, col: 0, size: 80)
            CoachAvatarImageView(gridImage: "CoachAvatarGrid1", row: 0, col: 1, size: 80)
            CoachAvatarImageView(gridImage: "CoachAvatarGrid1", row: 0, col: 2, size: 80)
            CoachAvatarImageView(gridImage: "CoachAvatarGrid1", row: 1, col: 0, size: 80)
            CoachAvatarImageView(gridImage: "CoachAvatarGrid1", row: 1, col: 1, size: 80)
        }
    }
}
