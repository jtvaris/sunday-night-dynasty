import SwiftUI

/// Procedurally generated player avatar using SwiftUI shapes.
/// All visual properties are deterministically derived from the player's UUID,
/// so every player always gets the same unique face with zero storage cost.
struct PlayerAvatarView: View {
    let player: Player
    let size: CGFloat

    // MARK: - Deterministic Seed

    private var seed: UInt64 {
        let uuid = player.id
        let uuidString = uuid.uuidString.replacingOccurrences(of: "-", with: "")
        // Use first 16 hex chars as seed
        var hash: UInt64 = 0
        for (i, char) in uuidString.prefix(16).enumerated() {
            let value = UInt64(char.hexDigitValue ?? 0)
            hash ^= value << (UInt64(i % 8) * 4)
        }
        return hash
    }

    /// Returns a deterministic value 0..<upperBound from the seed, using a bit offset.
    private func seededValue(_ offset: Int, upperBound: Int) -> Int {
        guard upperBound > 0 else { return 0 }
        let shifted = seed &>> UInt64(offset % 64)
        let mixed = shifted &* 6364136223846793005 &+ 1442695040888963407
        return Int(mixed % UInt64(upperBound))
    }

    // MARK: - Derived Appearance

    private var skinTone: Color {
        let tones: [Color] = [
            Color(red: 0.96, green: 0.87, blue: 0.76),  // Light
            Color(red: 0.87, green: 0.74, blue: 0.60),  // Light-medium
            Color(red: 0.76, green: 0.60, blue: 0.44),  // Medium
            Color(red: 0.62, green: 0.44, blue: 0.31),  // Medium-dark
            Color(red: 0.50, green: 0.35, blue: 0.24),  // Dark
            Color(red: 0.40, green: 0.27, blue: 0.18),  // Deeper
        ]
        return tones[seededValue(0, upperBound: tones.count)]
    }

    private var skinToneDarker: Color {
        let tones: [Color] = [
            Color(red: 0.88, green: 0.78, blue: 0.66),
            Color(red: 0.78, green: 0.64, blue: 0.50),
            Color(red: 0.66, green: 0.50, blue: 0.34),
            Color(red: 0.52, green: 0.34, blue: 0.21),
            Color(red: 0.40, green: 0.25, blue: 0.14),
            Color(red: 0.30, green: 0.17, blue: 0.08),
        ]
        return tones[seededValue(0, upperBound: tones.count)]
    }

    private var helmetColor: Color {
        switch player.position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }

    private var helmetHighlight: Color {
        switch player.position.side {
        case .offense:      return Color(red: 0.35, green: 0.60, blue: 1.0)
        case .defense:      return Color(red: 1.0, green: 0.40, blue: 0.40)
        case .specialTeams: return Color(red: 0.90, green: 0.78, blue: 0.42)
        }
    }

    /// Face width ratio varies slightly per player (0.72 - 0.82 of size)
    private var faceWidthRatio: CGFloat {
        0.72 + CGFloat(seededValue(8, upperBound: 11)) * 0.01
    }

    /// Eye spacing varies slightly
    private var eyeSpacing: CGFloat {
        0.28 + CGFloat(seededValue(16, upperBound: 6)) * 0.01
    }

    /// Whether player has a visor (QB/WR/RB/CB/FS/SS) or cage (linemen, LB)
    private var hasCageFacemask: Bool {
        switch player.position {
        case .LT, .LG, .C, .RG, .RT, .DE, .DT, .OLB, .MLB, .FB:
            return true
        default:
            return false
        }
    }

    /// Eyebrow thickness varies
    private var eyebrowThickness: CGFloat {
        let base: CGFloat = size * 0.018
        return base + CGFloat(seededValue(24, upperBound: 4)) * size * 0.004
    }

    /// Mouth style: 0 = neutral, 1 = slight smile, 2 = serious
    private var mouthStyle: Int {
        seededValue(32, upperBound: 3)
    }

    /// Nose width ratio
    private var noseWidthRatio: CGFloat {
        0.10 + CGFloat(seededValue(40, upperBound: 6)) * 0.01
    }

    /// Eye size
    private var eyeSize: CGFloat {
        size * (0.065 + CGFloat(seededValue(48, upperBound: 4)) * 0.005)
    }

    // MARK: - Body

    var body: some View {
        Canvas { context, canvasSize in
            let s = min(canvasSize.width, canvasSize.height)
            let cx = canvasSize.width / 2
            let cy = canvasSize.height / 2

            // -- Background circle fill (ensures visibility against any background) --
            let bgRect = CGRect(x: 0, y: 0, width: canvasSize.width, height: canvasSize.height)
            context.fill(Path(ellipseIn: bgRect), with: .color(Color(red: 0.14, green: 0.16, blue: 0.20)))

            // -- Helmet (back) --
            drawHelmet(context: &context, cx: cx, cy: cy, s: s)

            // -- Face --
            drawFace(context: &context, cx: cx, cy: cy, s: s)

            // -- Facemask --
            drawFacemask(context: &context, cx: cx, cy: cy, s: s)

            // -- Jersey number (small, at bottom) --
            drawJerseyNumber(context: &context, cx: cx, cy: cy, s: s)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle()
                .strokeBorder(Color.surfaceBorder, lineWidth: size > 40 ? 1.5 : 1)
        )
        .accessibilityLabel("\(player.fullName) avatar")
    }

    // MARK: - Drawing

    private func drawHelmet(context: inout GraphicsContext, cx: CGFloat, cy: CGFloat, s: CGFloat) {
        // Helmet shell - slightly larger than face, covering top half
        let helmetRect = CGRect(
            x: cx - s * 0.44,
            y: cy - s * 0.46,
            width: s * 0.88,
            height: s * 0.62
        )
        let helmetPath = Path(ellipseIn: helmetRect)
        context.fill(helmetPath, with: .color(helmetColor))

        // Helmet highlight stripe (center)
        let stripeWidth = s * 0.04
        let stripePath = Path { p in
            p.move(to: CGPoint(x: cx - stripeWidth / 2, y: cy - s * 0.44))
            p.addLine(to: CGPoint(x: cx + stripeWidth / 2, y: cy - s * 0.44))
            p.addLine(to: CGPoint(x: cx + stripeWidth / 2, y: cy - s * 0.10))
            p.addLine(to: CGPoint(x: cx - stripeWidth / 2, y: cy - s * 0.10))
            p.closeSubpath()
        }
        context.fill(stripePath, with: .color(helmetHighlight.opacity(0.6)))
    }

    private func drawFace(context: inout GraphicsContext, cx: CGFloat, cy: CGFloat, s: CGFloat) {
        let faceW = s * faceWidthRatio
        let faceH = s * 0.52
        let faceRect = CGRect(
            x: cx - faceW / 2,
            y: cy - s * 0.10,
            width: faceW,
            height: faceH
        )
        let facePath = Path(ellipseIn: faceRect)
        context.fill(facePath, with: .color(skinTone))

        // -- Eyes --
        let eyeY = cy + s * 0.04
        let eyeOffsetX = s * eyeSpacing / 2

        // Eye whites
        let eyeW = eyeSize * 1.4
        let eyeH = eyeSize * 0.9
        let leftEyeRect = CGRect(x: cx - eyeOffsetX - eyeW / 2, y: eyeY - eyeH / 2, width: eyeW, height: eyeH)
        let rightEyeRect = CGRect(x: cx + eyeOffsetX - eyeW / 2, y: eyeY - eyeH / 2, width: eyeW, height: eyeH)
        context.fill(Path(ellipseIn: leftEyeRect), with: .color(.white.opacity(0.9)))
        context.fill(Path(ellipseIn: rightEyeRect), with: .color(.white.opacity(0.9)))

        // Pupils
        let pupilSize = eyeSize * 0.65
        let leftPupilRect = CGRect(x: cx - eyeOffsetX - pupilSize / 2, y: eyeY - pupilSize / 2, width: pupilSize, height: pupilSize)
        let rightPupilRect = CGRect(x: cx + eyeOffsetX - pupilSize / 2, y: eyeY - pupilSize / 2, width: pupilSize, height: pupilSize)
        context.fill(Path(ellipseIn: leftPupilRect), with: .color(Color(red: 0.15, green: 0.12, blue: 0.10)))
        context.fill(Path(ellipseIn: rightPupilRect), with: .color(Color(red: 0.15, green: 0.12, blue: 0.10)))

        // Pupil highlights
        let hlSize = pupilSize * 0.3
        let hlOffset = pupilSize * 0.15
        let leftHL = CGRect(x: cx - eyeOffsetX - hlOffset, y: eyeY - hlOffset - hlSize / 2, width: hlSize, height: hlSize)
        let rightHL = CGRect(x: cx + eyeOffsetX - hlOffset, y: eyeY - hlOffset - hlSize / 2, width: hlSize, height: hlSize)
        context.fill(Path(ellipseIn: leftHL), with: .color(.white.opacity(0.7)))
        context.fill(Path(ellipseIn: rightHL), with: .color(.white.opacity(0.7)))

        // -- Eyebrows --
        let browY = eyeY - eyeH / 2 - s * 0.02
        let browW = eyeW * 1.1
        let leftBrow = Path { p in
            p.move(to: CGPoint(x: cx - eyeOffsetX - browW / 2, y: browY + eyebrowThickness * 0.5))
            p.addLine(to: CGPoint(x: cx - eyeOffsetX + browW / 2, y: browY - eyebrowThickness * 0.3))
            p.addLine(to: CGPoint(x: cx - eyeOffsetX + browW / 2, y: browY - eyebrowThickness * 0.3 + eyebrowThickness))
            p.addLine(to: CGPoint(x: cx - eyeOffsetX - browW / 2, y: browY + eyebrowThickness * 0.5 + eyebrowThickness))
            p.closeSubpath()
        }
        let rightBrow = Path { p in
            p.move(to: CGPoint(x: cx + eyeOffsetX + browW / 2, y: browY + eyebrowThickness * 0.5))
            p.addLine(to: CGPoint(x: cx + eyeOffsetX - browW / 2, y: browY - eyebrowThickness * 0.3))
            p.addLine(to: CGPoint(x: cx + eyeOffsetX - browW / 2, y: browY - eyebrowThickness * 0.3 + eyebrowThickness))
            p.addLine(to: CGPoint(x: cx + eyeOffsetX + browW / 2, y: browY + eyebrowThickness * 0.5 + eyebrowThickness))
            p.closeSubpath()
        }
        context.fill(leftBrow, with: .color(skinToneDarker.opacity(0.8)))
        context.fill(rightBrow, with: .color(skinToneDarker.opacity(0.8)))

        // -- Nose --
        let noseW = s * noseWidthRatio
        let noseY = cy + s * 0.12
        let nosePath = Path { p in
            p.move(to: CGPoint(x: cx, y: noseY - s * 0.03))
            p.addLine(to: CGPoint(x: cx - noseW, y: noseY + s * 0.04))
            p.addQuadCurve(
                to: CGPoint(x: cx + noseW, y: noseY + s * 0.04),
                control: CGPoint(x: cx, y: noseY + s * 0.06)
            )
            p.closeSubpath()
        }
        context.fill(nosePath, with: .color(skinToneDarker.opacity(0.4)))

        // -- Mouth --
        let mouthY = cy + s * 0.22
        let mouthW = s * 0.14
        let mouthPath = Path { p in
            switch mouthStyle {
            case 1: // Slight smile
                p.move(to: CGPoint(x: cx - mouthW, y: mouthY))
                p.addQuadCurve(
                    to: CGPoint(x: cx + mouthW, y: mouthY),
                    control: CGPoint(x: cx, y: mouthY + s * 0.04)
                )
            case 2: // Serious
                p.move(to: CGPoint(x: cx - mouthW, y: mouthY + s * 0.01))
                p.addQuadCurve(
                    to: CGPoint(x: cx + mouthW, y: mouthY + s * 0.01),
                    control: CGPoint(x: cx, y: mouthY - s * 0.01)
                )
            default: // Neutral
                p.move(to: CGPoint(x: cx - mouthW, y: mouthY))
                p.addLine(to: CGPoint(x: cx + mouthW, y: mouthY))
            }
        }
        context.stroke(mouthPath, with: .color(skinToneDarker.opacity(0.6)), lineWidth: s * 0.015)
    }

    private func drawFacemask(context: inout GraphicsContext, cx: CGFloat, cy: CGFloat, s: CGFloat) {
        let maskColor = Color(white: 0.75) // Silver/gray facemask

        if hasCageFacemask {
            // Cage style: multiple horizontal bars
            let barSpacing = s * 0.06
            let barWidth = s * 0.5
            let startY = cy + s * 0.02
            for i in 0..<4 {
                let y = startY + CGFloat(i) * barSpacing
                let narrowFactor = 1.0 - CGFloat(i) * 0.08
                let w = barWidth * narrowFactor
                let barPath = Path { p in
                    p.move(to: CGPoint(x: cx - w / 2, y: y))
                    p.addLine(to: CGPoint(x: cx + w / 2, y: y))
                }
                context.stroke(barPath, with: .color(maskColor.opacity(0.7)), lineWidth: s * 0.012)
            }
            // Vertical center bar
            let vertPath = Path { p in
                p.move(to: CGPoint(x: cx, y: startY))
                p.addLine(to: CGPoint(x: cx, y: startY + 3 * barSpacing))
            }
            context.stroke(vertPath, with: .color(maskColor.opacity(0.7)), lineWidth: s * 0.012)
        } else {
            // Open visor style: single bar across middle
            let barY = cy + s * 0.02
            let barW = s * 0.48
            let barPath = Path { p in
                p.move(to: CGPoint(x: cx - barW / 2, y: barY))
                p.addLine(to: CGPoint(x: cx + barW / 2, y: barY))
            }
            context.stroke(barPath, with: .color(maskColor.opacity(0.6)), lineWidth: s * 0.018)

            // Chin bar
            let chinY = cy + s * 0.22
            let chinW = s * 0.20
            let chinPath = Path { p in
                p.move(to: CGPoint(x: cx - chinW / 2, y: chinY))
                p.addQuadCurve(
                    to: CGPoint(x: cx + chinW / 2, y: chinY),
                    control: CGPoint(x: cx, y: chinY + s * 0.04)
                )
            }
            context.stroke(chinPath, with: .color(maskColor.opacity(0.6)), lineWidth: s * 0.014)
        }
    }

    private func drawJerseyNumber(context: inout GraphicsContext, cx: CGFloat, cy: CGFloat, s: CGFloat) {
        // Jersey number at bottom of circle
        let jerseyNum = (seededValue(56, upperBound: 89) + 1) // 1-89
        let numStr = "\(jerseyNum)"
        let fontSize = s * 0.13
        let numY = cy + s * 0.36

        let text = Text(numStr)
            .font(.system(size: fontSize, weight: .heavy, design: .rounded))
            .foregroundColor(.textPrimary)

        // Small background pill behind number
        let pillW = s * 0.22
        let pillH = s * 0.14
        let pillRect = CGRect(x: cx - pillW / 2, y: numY - pillH / 2, width: pillW, height: pillH)
        let pillPath = Path(roundedRect: pillRect, cornerRadius: pillH / 2)
        context.fill(pillPath, with: .color(Color.backgroundPrimary.opacity(0.7)))

        context.draw(
            context.resolve(text),
            at: CGPoint(x: cx, y: numY),
            anchor: .center
        )
    }
}

// MARK: - Preview

#Preview("Player Avatars - Various") {
    ZStack {
        Color.backgroundPrimary.ignoresSafeArea()
        ScrollView {
            VStack(spacing: 20) {
                Text("Player Avatar System")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.accentGold)

                // Large avatars
                HStack(spacing: 16) {
                    PlayerAvatarView(
                        player: Player(
                            firstName: "Patrick",
                            lastName: "Mahomes",
                            position: .QB,
                            age: 28,
                            positionAttributes: .quarterback(QBAttributes(
                                armStrength: 95, accuracyShort: 88, accuracyMid: 91,
                                accuracyDeep: 87, pocketPresence: 92, scrambling: 80
                            )),
                            personality: PlayerPersonality(archetype: .fieryCompetitor, motivation: .winning)
                        ),
                        size: 80
                    )
                    PlayerAvatarView(
                        player: Player(
                            firstName: "Myles",
                            lastName: "Garrett",
                            position: .DE,
                            age: 28,
                            positionAttributes: .defensiveLine(DLAttributes(
                                passRush: 96, blockShedding: 90, powerMoves: 88, finesseMoves: 91
                            )),
                            personality: PlayerPersonality(archetype: .quietProfessional, motivation: .winning)
                        ),
                        size: 80
                    )
                    PlayerAvatarView(
                        player: Player(
                            firstName: "Justin",
                            lastName: "Tucker",
                            position: .K,
                            age: 34,
                            positionAttributes: .kicking(KickingAttributes(kickPower: 95, kickAccuracy: 98)),
                            personality: PlayerPersonality(archetype: .steadyPerformer, motivation: .loyalty)
                        ),
                        size: 80
                    )
                }

                // Small avatars (row size)
                Text("Row Size (28pt)")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                HStack(spacing: 8) {
                    ForEach(0..<6) { i in
                        PlayerAvatarView(
                            player: Player(
                                id: UUID(),
                                firstName: "Player",
                                lastName: "\(i)",
                                position: [.QB, .WR, .RB, .CB, .DT, .K][i],
                                age: 25 + i,
                                positionAttributes: .quarterback(QBAttributes(
                                    armStrength: 80, accuracyShort: 80, accuracyMid: 80,
                                    accuracyDeep: 80, pocketPresence: 80, scrambling: 80
                                )),
                                personality: PlayerPersonality(archetype: .steadyPerformer, motivation: .winning)
                            ),
                            size: 28
                        )
                    }
                }
            }
            .padding()
        }
    }
}
