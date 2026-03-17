import SwiftUI

/// Displays an owner avatar cropped from a grid image.
/// The grid images are 4 columns x 3 rows of portraits.
struct OwnerAvatarImageView: View {
    let gridImage: String    // "OwnerAvatarGrid1" etc
    let row: Int             // 0-2
    let col: Int             // 0-3
    var size: CGFloat = 64
    var grayscale: Bool = false

    var body: some View {
        GeometryReader { _ in
            Image(gridImage)
                .resizable()
                .scaledToFill()
                .frame(width: size * 4, height: size * 3.5)
                .offset(
                    x: -size * CGFloat(col),
                    y: -size * 1.16 * CGFloat(row)
                )
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .saturation(grayscale ? 0 : 1)
        .overlay(
            Circle()
                .strokeBorder(Color.surfaceBorder, lineWidth: 1.5)
        )
    }
}

/// Helper to get a deterministic owner avatar based on owner name hash
enum OwnerAvatarMapper {
    /// Maps an owner to a specific grid position based on their name
    static func avatarPosition(for ownerName: String) -> (gridImage: String, row: Int, col: Int) {
        let hash = abs(ownerName.hashValue)
        let gridIndex = (hash % 4) + 1
        let totalPositions = 12  // 4 cols x 3 rows
        let position = hash % totalPositions
        let row = position / 4
        let col = position % 4
        return (gridImage: "OwnerAvatarGrid\(gridIndex)", row: row, col: col)
    }
}

#Preview {
    ZStack {
        Color.backgroundPrimary.ignoresSafeArea()
        VStack(spacing: 20) {
            HStack(spacing: 16) {
                OwnerAvatarImageView(gridImage: "OwnerAvatarGrid1", row: 0, col: 0, size: 80)
                OwnerAvatarImageView(gridImage: "OwnerAvatarGrid1", row: 0, col: 1, size: 80)
                OwnerAvatarImageView(gridImage: "OwnerAvatarGrid1", row: 0, col: 2, size: 80)
                OwnerAvatarImageView(gridImage: "OwnerAvatarGrid1", row: 0, col: 3, size: 80)
            }
            Text("Grayscale (for dramatic backgrounds):")
                .foregroundStyle(Color.textSecondary)
            HStack(spacing: 16) {
                OwnerAvatarImageView(gridImage: "OwnerAvatarGrid1", row: 1, col: 0, size: 80, grayscale: true)
                OwnerAvatarImageView(gridImage: "OwnerAvatarGrid1", row: 1, col: 1, size: 80, grayscale: true)
                OwnerAvatarImageView(gridImage: "OwnerAvatarGrid1", row: 1, col: 2, size: 80, grayscale: true)
                OwnerAvatarImageView(gridImage: "OwnerAvatarGrid1", row: 1, col: 3, size: 80, grayscale: true)
            }
        }
    }
}
