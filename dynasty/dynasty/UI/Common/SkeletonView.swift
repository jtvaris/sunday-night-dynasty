import SwiftUI

// MARK: - Skeleton View
//
// Animated placeholder used while content is loading. Displays a
// shimmering rounded rectangle that matches our card aesthetic
// instead of a generic spinner.
//
// Usage:
//   SkeletonView(width: 160, height: 18)
//
// For a row of skeletons, compose with VStack/HStack as needed.

struct SkeletonView: View {

    let width: CGFloat?
    let height: CGFloat
    let cornerRadius: CGFloat

    @State private var phase: CGFloat = -1.0

    init(width: CGFloat? = nil, height: CGFloat = 14, cornerRadius: CGFloat = 6) {
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.backgroundTertiary)
            .frame(width: width, height: height)
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.clear,
                            Color.textSecondary.opacity(0.18),
                            Color.clear
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.6)
                    .offset(x: geo.size.width * phase)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1.6
                }
            }
    }
}

// MARK: - Skeleton Row
//
// A common card-row skeleton: avatar circle + 2 lines of text.

struct SkeletonRow: View {

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.backgroundTertiary)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 6) {
                SkeletonView(width: 140, height: 12)
                SkeletonView(width: 90, height: 10)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.backgroundSecondary)
        )
    }
}

#Preview {
    ZStack {
        Color.backgroundPrimary.ignoresSafeArea()
        VStack(alignment: .leading, spacing: 12) {
            SkeletonView(width: 200, height: 22)
            SkeletonView(width: 140, height: 14)
            VStack(spacing: 8) {
                SkeletonRow()
                SkeletonRow()
                SkeletonRow()
            }
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}
