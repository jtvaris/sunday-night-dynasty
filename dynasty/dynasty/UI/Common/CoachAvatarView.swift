import SwiftUI

// MARK: - Avatar Data

struct CoachAvatarInfo: Identifiable {
    let id: String
    let name: String
    let gender: Gender

    // Visual traits for procedural avatar
    let skinTone: Color
    let hairColor: Color
    let hairStyle: HairStyle
    let accessory: Accessory
    let facialHair: FacialHair

    enum Gender: String { case male, female }
    enum HairStyle { case short, slickedBack, flat, buzzCut, curly, bob, ponytail, shoulderLength, pixie, braided }
    enum Accessory { case none, headset, cap, glasses, visor, whistle }
    enum FacialHair { case none, mustache, stubble }
}

// MARK: - All Avatars

enum CoachAvatars {
    static let all: [CoachAvatarInfo] = [
        // Male coaches
        CoachAvatarInfo(id: "coach_m1", name: "The Veteran", gender: .male,
                        skinTone: Color(red: 0.87, green: 0.75, blue: 0.65),
                        hairColor: Color(white: 0.55),
                        hairStyle: .slickedBack, accessory: .headset, facialHair: .mustache),

        CoachAvatarInfo(id: "coach_m2", name: "The Strategist", gender: .male,
                        skinTone: Color(red: 0.72, green: 0.55, blue: 0.42),
                        hairColor: Color(red: 0.15, green: 0.12, blue: 0.10),
                        hairStyle: .short, accessory: .glasses, facialHair: .none),

        CoachAvatarInfo(id: "coach_m3", name: "The Old School", gender: .male,
                        skinTone: Color(red: 0.92, green: 0.82, blue: 0.72),
                        hairColor: Color(white: 0.75),
                        hairStyle: .flat, accessory: .cap, facialHair: .none),

        CoachAvatarInfo(id: "coach_m4", name: "The Motivator", gender: .male,
                        skinTone: Color(red: 0.55, green: 0.38, blue: 0.28),
                        hairColor: Color(red: 0.08, green: 0.06, blue: 0.05),
                        hairStyle: .buzzCut, accessory: .whistle, facialHair: .stubble),

        CoachAvatarInfo(id: "coach_m5", name: "The Innovator", gender: .male,
                        skinTone: Color(red: 0.82, green: 0.68, blue: 0.55),
                        hairColor: Color(red: 0.35, green: 0.20, blue: 0.12),
                        hairStyle: .curly, accessory: .visor, facialHair: .none),

        // Female coaches
        CoachAvatarInfo(id: "coach_f1", name: "The Pioneer", gender: .female,
                        skinTone: Color(red: 0.90, green: 0.78, blue: 0.68),
                        hairColor: Color(red: 0.60, green: 0.35, blue: 0.15),
                        hairStyle: .ponytail, accessory: .headset, facialHair: .none),

        CoachAvatarInfo(id: "coach_f2", name: "The Analyst", gender: .female,
                        skinTone: Color(red: 0.70, green: 0.52, blue: 0.40),
                        hairColor: Color(red: 0.10, green: 0.08, blue: 0.06),
                        hairStyle: .shoulderLength, accessory: .glasses, facialHair: .none),

        CoachAvatarInfo(id: "coach_f3", name: "The Trailblazer", gender: .female,
                        skinTone: Color(red: 0.55, green: 0.40, blue: 0.30),
                        hairColor: Color(red: 0.08, green: 0.06, blue: 0.05),
                        hairStyle: .braided, accessory: .visor, facialHair: .none),

        CoachAvatarInfo(id: "coach_f4", name: "The Tactician", gender: .female,
                        skinTone: Color(red: 0.85, green: 0.72, blue: 0.62),
                        hairColor: Color(red: 0.82, green: 0.72, blue: 0.55),
                        hairStyle: .bob, accessory: .cap, facialHair: .none),

        CoachAvatarInfo(id: "coach_f5", name: "The Commander", gender: .female,
                        skinTone: Color(red: 0.78, green: 0.62, blue: 0.50),
                        hairColor: Color(red: 0.20, green: 0.15, blue: 0.10),
                        hairStyle: .pixie, accessory: .whistle, facialHair: .none),
    ]

    static func avatar(for id: String) -> CoachAvatarInfo? {
        all.first { $0.id == id }
    }
}

// MARK: - Coach Avatar View (Retro Illustrated Style)

struct CoachAvatarView: View {
    let avatar: CoachAvatarInfo
    var size: CGFloat = 80

    var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let cx = w / 2

            // Background circle
            let bgRect = CGRect(origin: .zero, size: canvasSize)
            context.fill(Circle().path(in: bgRect), with: .color(Color.backgroundTertiary))

            // Shoulders / body
            let shoulderTop = h * 0.72
            var shoulderPath = Path()
            shoulderPath.move(to: CGPoint(x: cx - w * 0.45, y: h))
            shoulderPath.addCurve(
                to: CGPoint(x: cx + w * 0.45, y: h),
                control1: CGPoint(x: cx - w * 0.35, y: shoulderTop),
                control2: CGPoint(x: cx + w * 0.35, y: shoulderTop)
            )
            shoulderPath.addLine(to: CGPoint(x: w, y: h))
            shoulderPath.addLine(to: CGPoint(x: 0, y: h))
            shoulderPath.closeSubpath()
            context.fill(shoulderPath, with: .color(Color.backgroundSecondary.opacity(0.9)))

            // Neck
            let neckWidth = w * 0.12
            let neckTop = h * 0.58
            let neckRect = CGRect(x: cx - neckWidth, y: neckTop, width: neckWidth * 2, height: h * 0.16)
            context.fill(Path(neckRect), with: .color(avatar.skinTone))

            // Head
            let headWidth = w * 0.34
            let headHeight = h * 0.38
            let headTop = h * 0.18
            let headRect = CGRect(x: cx - headWidth, y: headTop, width: headWidth * 2, height: headHeight)
            context.fill(Ellipse().path(in: headRect), with: .color(avatar.skinTone))

            // Eyes
            let eyeY = headTop + headHeight * 0.45
            let eyeSpacing = w * 0.10
            let eyeSize = CGSize(width: w * 0.06, height: w * 0.035)
            let leftEye = CGRect(x: cx - eyeSpacing - eyeSize.width / 2, y: eyeY, width: eyeSize.width, height: eyeSize.height)
            let rightEye = CGRect(x: cx + eyeSpacing - eyeSize.width / 2, y: eyeY, width: eyeSize.width, height: eyeSize.height)
            context.fill(Ellipse().path(in: leftEye), with: .color(Color(white: 0.15)))
            context.fill(Ellipse().path(in: rightEye), with: .color(Color(white: 0.15)))

            // Mouth (slight smile)
            var mouthPath = Path()
            let mouthY = headTop + headHeight * 0.72
            mouthPath.move(to: CGPoint(x: cx - w * 0.06, y: mouthY))
            mouthPath.addQuadCurve(
                to: CGPoint(x: cx + w * 0.06, y: mouthY),
                control: CGPoint(x: cx, y: mouthY + w * 0.03)
            )
            context.stroke(mouthPath, with: .color(Color(white: 0.25)), lineWidth: 1.5)

            // Hair
            drawHair(in: &context, style: avatar.hairStyle, color: avatar.hairColor,
                     headRect: headRect, cx: cx, w: w, h: h)

            // Facial hair
            if avatar.facialHair == .mustache {
                var stachePath = Path()
                let stacheY = headTop + headHeight * 0.62
                stachePath.move(to: CGPoint(x: cx - w * 0.08, y: stacheY))
                stachePath.addQuadCurve(to: CGPoint(x: cx, y: stacheY + w * 0.015),
                                        control: CGPoint(x: cx - w * 0.04, y: stacheY + w * 0.025))
                stachePath.addQuadCurve(to: CGPoint(x: cx + w * 0.08, y: stacheY),
                                        control: CGPoint(x: cx + w * 0.04, y: stacheY + w * 0.025))
                context.stroke(stachePath, with: .color(avatar.hairColor), lineWidth: 2.5)
            } else if avatar.facialHair == .stubble {
                // Subtle dots for stubble
                let stubbleY = headTop + headHeight * 0.65
                for i in 0..<8 {
                    let angle = Double(i) * 0.4 - 1.4
                    let sx = cx + CGFloat(cos(angle)) * w * 0.1
                    let sy = stubbleY + CGFloat(sin(angle)) * w * 0.04
                    let dot = CGRect(x: sx, y: sy, width: 1.5, height: 1.5)
                    context.fill(Path(ellipseIn: dot), with: .color(avatar.hairColor.opacity(0.4)))
                }
            }

            // Accessory
            drawAccessory(in: &context, accessory: avatar.accessory,
                          headRect: headRect, cx: cx, w: w, h: h)

            // Circle border
            context.stroke(Circle().path(in: bgRect.insetBy(dx: 1, dy: 1)),
                           with: .color(Color.surfaceBorder), lineWidth: 2)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    // MARK: - Hair Drawing

    private func drawHair(in context: inout GraphicsContext, style: CoachAvatarInfo.HairStyle,
                          color: Color, headRect: CGRect, cx: CGFloat, w: CGFloat, h: CGFloat) {
        let hairTop = headRect.minY - headRect.height * 0.08

        switch style {
        case .slickedBack:
            var path = Path()
            path.addEllipse(in: CGRect(x: headRect.minX - w * 0.02, y: hairTop,
                                       width: headRect.width + w * 0.04, height: headRect.height * 0.55))
            context.fill(path, with: .color(color))

        case .short:
            var path = Path()
            path.addEllipse(in: CGRect(x: headRect.minX, y: hairTop,
                                       width: headRect.width, height: headRect.height * 0.45))
            context.fill(path, with: .color(color))

        case .flat:
            let flatRect = CGRect(x: headRect.minX - w * 0.01, y: hairTop,
                                  width: headRect.width + w * 0.02, height: headRect.height * 0.3)
            context.fill(Path(flatRect), with: .color(color))

        case .buzzCut:
            var path = Path()
            path.addEllipse(in: CGRect(x: headRect.minX + w * 0.02, y: hairTop + headRect.height * 0.05,
                                       width: headRect.width - w * 0.04, height: headRect.height * 0.35))
            context.fill(path, with: .color(color.opacity(0.6)))

        case .curly:
            for i in 0..<7 {
                let angle = Double(i) * 0.5 - 1.3
                let bx = cx + CGFloat(cos(angle)) * headRect.width * 0.5
                let by = hairTop + headRect.height * 0.1 + CGFloat(sin(angle + 1.5)) * headRect.height * 0.1
                let blobRect = CGRect(x: bx - w * 0.05, y: by, width: w * 0.10, height: w * 0.10)
                context.fill(Circle().path(in: blobRect), with: .color(color))
            }

        case .bob:
            var path = Path()
            path.addEllipse(in: CGRect(x: headRect.minX - w * 0.06, y: hairTop,
                                       width: headRect.width + w * 0.12, height: headRect.height * 0.65))
            context.fill(path, with: .color(color))

        case .ponytail:
            var path = Path()
            path.addEllipse(in: CGRect(x: headRect.minX, y: hairTop,
                                       width: headRect.width, height: headRect.height * 0.48))
            context.fill(path, with: .color(color))
            // Ponytail behind
            var tailPath = Path()
            tailPath.move(to: CGPoint(x: cx + headRect.width * 0.35, y: headRect.minY + headRect.height * 0.15))
            tailPath.addCurve(
                to: CGPoint(x: cx + w * 0.35, y: headRect.maxY - headRect.height * 0.1),
                control1: CGPoint(x: cx + w * 0.38, y: headRect.midY - headRect.height * 0.15),
                control2: CGPoint(x: cx + w * 0.40, y: headRect.midY + headRect.height * 0.1)
            )
            context.stroke(tailPath, with: .color(color), lineWidth: w * 0.05)

        case .shoulderLength:
            var path = Path()
            path.addEllipse(in: CGRect(x: headRect.minX - w * 0.05, y: hairTop,
                                       width: headRect.width + w * 0.10, height: headRect.height * 0.8))
            context.fill(path, with: .color(color))

        case .pixie:
            var path = Path()
            path.addEllipse(in: CGRect(x: headRect.minX - w * 0.01, y: hairTop,
                                       width: headRect.width + w * 0.06, height: headRect.height * 0.42))
            context.fill(path, with: .color(color))

        case .braided:
            var path = Path()
            path.addEllipse(in: CGRect(x: headRect.minX, y: hairTop,
                                       width: headRect.width, height: headRect.height * 0.48))
            context.fill(path, with: .color(color))
            // Two braids
            for side in [-1.0, 1.0] {
                let startX = cx + CGFloat(side) * headRect.width * 0.3
                for j in 0..<4 {
                    let segY = headRect.midY + CGFloat(j) * w * 0.05
                    let segX = startX + CGFloat(j % 2 == 0 ? -1 : 1) * w * 0.015
                    let segRect = CGRect(x: segX - w * 0.025, y: segY, width: w * 0.05, height: w * 0.045)
                    context.fill(Ellipse().path(in: segRect), with: .color(color))
                }
            }
        }
    }

    // MARK: - Accessory Drawing

    private func drawAccessory(in context: inout GraphicsContext, accessory: CoachAvatarInfo.Accessory,
                               headRect: CGRect, cx: CGFloat, w: CGFloat, h: CGFloat) {
        switch accessory {
        case .none:
            break

        case .headset:
            // Headband
            var bandPath = Path()
            bandPath.addArc(center: CGPoint(x: cx, y: headRect.minY + headRect.height * 0.3),
                            radius: headRect.width * 0.52,
                            startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
            context.stroke(bandPath, with: .color(Color(white: 0.3)), lineWidth: 2.5)
            // Earpiece
            let earRect = CGRect(x: headRect.minX - w * 0.04,
                                 y: headRect.minY + headRect.height * 0.35,
                                 width: w * 0.07, height: w * 0.08)
            context.fill(RoundedRectangle(cornerRadius: 2).path(in: earRect),
                         with: .color(Color(white: 0.25)))
            // Mic arm
            var micPath = Path()
            micPath.move(to: CGPoint(x: earRect.midX, y: earRect.maxY))
            micPath.addLine(to: CGPoint(x: cx - w * 0.06, y: headRect.minY + headRect.height * 0.68))
            context.stroke(micPath, with: .color(Color(white: 0.3)), lineWidth: 1.5)

        case .cap:
            var capPath = Path()
            let capY = headRect.minY - headRect.height * 0.02
            capPath.move(to: CGPoint(x: headRect.minX - w * 0.02, y: capY + headRect.height * 0.22))
            capPath.addQuadCurve(
                to: CGPoint(x: headRect.maxX + w * 0.02, y: capY + headRect.height * 0.22),
                control: CGPoint(x: cx, y: capY - headRect.height * 0.05)
            )
            capPath.closeSubpath()
            context.fill(capPath, with: .color(Color(white: 0.2)))
            // Brim
            var brimPath = Path()
            brimPath.move(to: CGPoint(x: headRect.minX - w * 0.08, y: capY + headRect.height * 0.22))
            brimPath.addLine(to: CGPoint(x: cx + w * 0.02, y: capY + headRect.height * 0.26))
            brimPath.addLine(to: CGPoint(x: headRect.minX - w * 0.02, y: capY + headRect.height * 0.22))
            brimPath.closeSubpath()
            context.fill(brimPath, with: .color(Color(white: 0.15)))

        case .glasses:
            let glassY = headRect.minY + headRect.height * 0.42
            let glassW = w * 0.10
            let glassH = w * 0.07
            // Frames
            let leftGlass = CGRect(x: cx - w * 0.15, y: glassY, width: glassW, height: glassH)
            let rightGlass = CGRect(x: cx + w * 0.05, y: glassY, width: glassW, height: glassH)
            context.stroke(RoundedRectangle(cornerRadius: 3).path(in: leftGlass),
                           with: .color(Color(white: 0.2)), lineWidth: 1.8)
            context.stroke(RoundedRectangle(cornerRadius: 3).path(in: rightGlass),
                           with: .color(Color(white: 0.2)), lineWidth: 1.8)
            // Bridge
            var bridge = Path()
            bridge.move(to: CGPoint(x: leftGlass.maxX, y: glassY + glassH * 0.4))
            bridge.addLine(to: CGPoint(x: rightGlass.minX, y: glassY + glassH * 0.4))
            context.stroke(bridge, with: .color(Color(white: 0.2)), lineWidth: 1.5)

        case .visor:
            var visorPath = Path()
            let visorY = headRect.minY + headRect.height * 0.18
            visorPath.move(to: CGPoint(x: headRect.minX - w * 0.06, y: visorY + headRect.height * 0.08))
            visorPath.addQuadCurve(
                to: CGPoint(x: headRect.maxX + w * 0.06, y: visorY + headRect.height * 0.08),
                control: CGPoint(x: cx, y: visorY - headRect.height * 0.02)
            )
            context.stroke(visorPath, with: .color(Color(white: 0.25)), lineWidth: 2)
            // Visor shade
            var shadePath = Path()
            shadePath.move(to: CGPoint(x: headRect.minX - w * 0.06, y: visorY + headRect.height * 0.08))
            shadePath.addLine(to: CGPoint(x: headRect.minX - w * 0.10, y: visorY + headRect.height * 0.14))
            shadePath.addQuadCurve(
                to: CGPoint(x: cx, y: visorY + headRect.height * 0.12),
                control: CGPoint(x: headRect.minX, y: visorY + headRect.height * 0.16)
            )
            shadePath.addLine(to: CGPoint(x: headRect.minX - w * 0.06, y: visorY + headRect.height * 0.08))
            context.fill(shadePath, with: .color(Color(white: 0.2).opacity(0.7)))

        case .whistle:
            var whistlePath = Path()
            let whistleY = h * 0.74
            whistlePath.move(to: CGPoint(x: cx - w * 0.04, y: h * 0.68))
            whistlePath.addLine(to: CGPoint(x: cx + w * 0.06, y: whistleY))
            context.stroke(whistlePath, with: .color(Color(white: 0.45)), lineWidth: 1.5)
            let whistleRect = CGRect(x: cx + w * 0.04, y: whistleY - w * 0.015,
                                     width: w * 0.06, height: w * 0.03)
            context.fill(RoundedRectangle(cornerRadius: 2).path(in: whistleRect),
                         with: .color(Color(white: 0.5)))
        }
    }
}

// MARK: - Avatar Selection Grid

struct AvatarSelectionView: View {
    @Binding var selectedAvatarID: String
    let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 5)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(CoachAvatars.all) { avatar in
                    VStack(spacing: 6) {
                        CoachAvatarView(avatar: avatar, size: 72)
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        selectedAvatarID == avatar.id ? Color.accentGold : Color.clear,
                                        lineWidth: 3
                                    )
                            )
                            .scaleEffect(selectedAvatarID == avatar.id ? 1.1 : 1.0)
                            .animation(.spring(response: 0.3), value: selectedAvatarID)

                        Text(avatar.name)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(selectedAvatarID == avatar.id ? Color.accentGold : Color.textSecondary)
                            .lineLimit(1)
                    }
                    .onTapGesture {
                        selectedAvatarID = avatar.id
                    }
                }
            }
        }
    }
}

#Preview {
    ZStack {
        Color.backgroundPrimary.ignoresSafeArea()
        VStack(spacing: 30) {
            HStack(spacing: 20) {
                ForEach(CoachAvatars.all.prefix(5)) { avatar in
                    VStack {
                        CoachAvatarView(avatar: avatar, size: 80)
                        Text(avatar.name)
                            .font(.caption2)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
            HStack(spacing: 20) {
                ForEach(CoachAvatars.all.suffix(5)) { avatar in
                    VStack {
                        CoachAvatarView(avatar: avatar, size: 80)
                        Text(avatar.name)
                            .font(.caption2)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
        }
    }
}
