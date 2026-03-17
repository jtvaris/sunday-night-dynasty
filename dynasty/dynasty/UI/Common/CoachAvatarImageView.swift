import SwiftUI

/// Displays a single coach avatar cropped from a grid image.
/// Grid images are 1024x1024 with 5 columns x 3 rows of portraits.
struct CoachAvatarImageView: View {
    let gridImage: String
    let row: Int    // 0-2
    let col: Int    // 0-4
    var size: CGFloat = 80

    // Grid layout: 5 cols, 3 rows in a 1024x1024 image
    // Each cell is approximately 204.8 x 341.3
    private let gridCols: CGFloat = 5
    private let gridRows: CGFloat = 3

    var body: some View {
        // Scale the full image so each cell matches our desired size
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
            Text("Row 0").foregroundStyle(.white)
            HStack(spacing: 16) {
                ForEach(0..<5, id: \.self) { col in
                    CoachAvatarImageView(gridImage: "CoachAvatarGrid1", row: 0, col: col, size: 80)
                }
            }
            Text("Row 1").foregroundStyle(.white)
            HStack(spacing: 16) {
                ForEach(0..<5, id: \.self) { col in
                    CoachAvatarImageView(gridImage: "CoachAvatarGrid1", row: 1, col: col, size: 80)
                }
            }
            Text("Row 2").foregroundStyle(.white)
            HStack(spacing: 16) {
                ForEach(0..<5, id: \.self) { col in
                    CoachAvatarImageView(gridImage: "CoachAvatarGrid1", row: 2, col: col, size: 80)
                }
            }
        }
    }
}
