import SwiftUI

/// Displays an owner avatar cropped from a grid image.
/// Grid images are 1024x1024 with 4 columns x 3 rows of portraits.
struct OwnerAvatarImageView: View {
    let gridImage: String
    let row: Int        // 0-2
    let col: Int        // 0-3
    var size: CGFloat = 64
    var grayscale: Bool = false

    private let gridCols: CGFloat = 4
    private let gridRows: CGFloat = 3

    var body: some View {
        let scaledWidth = size * gridCols
        let scaledHeight = size * gridRows

        Image(gridImage)
            .resizable()
            .frame(width: scaledWidth, height: scaledHeight)
            .offset(
                x: -size * CGFloat(col) + (size * (gridCols - 1) / 2),
                y: -size * CGFloat(row) + (size * (gridRows - 1) / 2)
            )
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
    static func avatarPosition(for ownerName: String) -> (gridImage: String, row: Int, col: Int) {
        let hash = abs(ownerName.hashValue)
        let gridIndex = (hash % 4) + 1
        let totalPositions = 12
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
                ForEach(0..<4, id: \.self) { col in
                    OwnerAvatarImageView(gridImage: "OwnerAvatarGrid1", row: 0, col: col, size: 80)
                }
            }
            HStack(spacing: 16) {
                ForEach(0..<4, id: \.self) { col in
                    OwnerAvatarImageView(gridImage: "OwnerAvatarGrid1", row: 1, col: col, size: 80, grayscale: true)
                }
            }
        }
    }
}
