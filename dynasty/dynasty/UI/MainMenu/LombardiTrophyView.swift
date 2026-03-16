import SwiftUI

/// A stylized Lombardi Trophy silhouette rendered entirely in SwiftUI.
/// Monochrome with subtle glow animation — evokes championship legacy.
struct LombardiTrophyView: View {

    @State private var glowIntensity: Double = 0.3

    var body: some View {
        ZStack {
            // Outer glow
            trophyShape
                .fill(Color.white.opacity(glowIntensity * 0.15))
                .blur(radius: 30)

            // Trophy body
            trophyShape
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.9),
                            Color(white: 0.7),
                            Color(white: 0.5),
                            Color(white: 0.65),
                            Color.white.opacity(0.85)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            // Highlight edge
            trophyShape
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.6),
                            Color.white.opacity(0.1),
                            Color.white.opacity(0.3)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        }
        .compositingGroup()
        .opacity(0.85)
        .onAppear {
            withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
                glowIntensity = 1.0
            }
        }
    }

    // MARK: - Trophy Shape

    private var trophyShape: some Shape {
        LombardiShape()
    }
}

/// Custom Shape that draws a Lombardi Trophy silhouette.
struct LombardiShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        let w = rect.width
        let h = rect.height

        // The trophy is drawn relative to the bounding rect.
        // Proportions: football on top, narrow neck, flared body, pedestal base.

        let centerX = w * 0.5

        // --- Football (top) ---
        let footballTop = h * 0.0
        let footballBottom = h * 0.22
        let footballWidth = w * 0.20
        let footballCenterY = (footballTop + footballBottom) * 0.5

        // Football shape (pointed oval / lens shape)
        path.move(to: CGPoint(x: centerX, y: footballTop))
        path.addQuadCurve(
            to: CGPoint(x: centerX, y: footballBottom),
            control: CGPoint(x: centerX + footballWidth, y: footballCenterY)
        )
        path.addQuadCurve(
            to: CGPoint(x: centerX, y: footballTop),
            control: CGPoint(x: centerX - footballWidth, y: footballCenterY)
        )

        // --- Neck (thin stem from football to body) ---
        let neckTop = footballBottom
        let neckBottom = h * 0.38
        let neckWidth = w * 0.035

        path.move(to: CGPoint(x: centerX - neckWidth, y: neckTop))
        path.addLine(to: CGPoint(x: centerX - neckWidth * 0.8, y: neckBottom))
        path.addLine(to: CGPoint(x: centerX + neckWidth * 0.8, y: neckBottom))
        path.addLine(to: CGPoint(x: centerX + neckWidth, y: neckTop))
        path.closeSubpath()

        // --- Body (flared vase shape) ---
        let bodyTop = neckBottom
        let bodyBottom = h * 0.72
        let bodyTopWidth = w * 0.06
        let bodyMidWidth = w * 0.22
        let bodyBottomWidth = w * 0.10
        let bodyMidY = (bodyTop + bodyBottom) * 0.45

        // Left side
        path.move(to: CGPoint(x: centerX - bodyTopWidth, y: bodyTop))
        path.addCurve(
            to: CGPoint(x: centerX - bodyBottomWidth, y: bodyBottom),
            control1: CGPoint(x: centerX - bodyMidWidth, y: bodyMidY),
            control2: CGPoint(x: centerX - bodyMidWidth * 0.6, y: bodyBottom - h * 0.04)
        )

        // Bottom connector
        path.addLine(to: CGPoint(x: centerX + bodyBottomWidth, y: bodyBottom))

        // Right side
        path.addCurve(
            to: CGPoint(x: centerX + bodyTopWidth, y: bodyTop),
            control1: CGPoint(x: centerX + bodyMidWidth * 0.6, y: bodyBottom - h * 0.04),
            control2: CGPoint(x: centerX + bodyMidWidth, y: bodyMidY)
        )
        path.closeSubpath()

        // --- Base pedestal ---
        let baseTop = bodyBottom
        let baseMid = h * 0.78
        let baseBottom = h * 1.0
        let baseTopWidth = bodyBottomWidth * 1.1
        let baseMidWidth = w * 0.08
        let baseBottomWidth = w * 0.18

        // Pedestal stem
        path.move(to: CGPoint(x: centerX - baseTopWidth, y: baseTop))
        path.addLine(to: CGPoint(x: centerX - baseMidWidth, y: baseMid))
        path.addLine(to: CGPoint(x: centerX + baseMidWidth, y: baseMid))
        path.addLine(to: CGPoint(x: centerX + baseTopWidth, y: baseTop))
        path.closeSubpath()

        // Base plate
        let plateHeight = h * 0.06
        path.addRoundedRect(
            in: CGRect(
                x: centerX - baseBottomWidth,
                y: baseBottom - plateHeight,
                width: baseBottomWidth * 2,
                height: plateHeight
            ),
            cornerSize: CGSize(width: 4, height: 4)
        )

        // Base connector (trapezoid from stem to plate)
        path.move(to: CGPoint(x: centerX - baseMidWidth, y: baseMid))
        path.addLine(to: CGPoint(x: centerX - baseBottomWidth * 0.85, y: baseBottom - plateHeight))
        path.addLine(to: CGPoint(x: centerX + baseBottomWidth * 0.85, y: baseBottom - plateHeight))
        path.addLine(to: CGPoint(x: centerX + baseMidWidth, y: baseMid))
        path.closeSubpath()

        return path
    }
}

#Preview {
    ZStack {
        Color.backgroundPrimary.ignoresSafeArea()
        LombardiTrophyView()
            .frame(width: 160, height: 320)
    }
}
