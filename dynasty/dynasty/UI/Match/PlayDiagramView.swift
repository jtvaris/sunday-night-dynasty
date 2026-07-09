import SwiftUI

// MARK: - Offensive Play Diagram

/// Chalkboard X&O art for an offensive play call, drawn with Canvas in a
/// normalized space (offense drives toward the top). O = offense; the primary
/// route/run lane is gold with an arrowhead, secondary routes are dashed gray.
///
/// The geometry is NOT hand-drawn here: it is `RouteSpec.diagram(for:)` — a
/// 2D projection of the exact spec + formation the 3D field choreographs, so
/// this card and the on-field routes can never disagree.
struct PlayDiagramView: View {

    let call: OffensivePlayCall

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let diagram = RouteSpec.diagram(for: call)
            func pt(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * w, y: p.y * h) }

            // Line of scrimmage
            var los = Path()
            los.move(to: CGPoint(x: 0.03 * w, y: diagram.losY * h))
            los.addLine(to: CGPoint(x: 0.97 * w, y: diagram.losY * h))
            context.stroke(los, with: .color(.white.opacity(0.35)),
                           style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))

            // Alignments straight from the field formation: five linemen,
            // the QB (filled) and the skill players.
            for spot in diagram.linemen {
                drawO(context, at: pt(spot), radius: 0.026 * w)
            }
            drawO(context, at: pt(diagram.qb), radius: 0.026 * w, filled: true)
            for spot in diagram.skill {
                drawO(context, at: pt(spot), radius: 0.026 * w)
            }

            // Routes — the spec's polylines, primary read in gold.
            for route in diagram.routes {
                guard route.points.count > 1 else { continue }
                var path = Path()
                path.move(to: pt(route.points[0]))
                for p in route.points.dropFirst() { path.addLine(to: pt(p)) }
                if route.primary {
                    context.stroke(path, with: .color(.accentGold),
                                   style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    drawArrowhead(context, path: route.points.map(pt), color: .accentGold)
                } else {
                    context.stroke(path, with: .color(.white.opacity(0.28)),
                                   style: StrokeStyle(lineWidth: 1.5, lineCap: .round,
                                                      lineJoin: .round, dash: [3, 3]))
                    drawArrowhead(context, path: route.points.map(pt), color: .white.opacity(0.28))
                }
            }
        }
        .aspectRatio(1.5, contentMode: .fit)
    }

    // MARK: Drawing helpers

    private func drawO(_ context: GraphicsContext, at point: CGPoint,
                       radius: CGFloat, filled: Bool = false) {
        let rect = CGRect(x: point.x - radius, y: point.y - radius,
                          width: radius * 2, height: radius * 2)
        if filled {
            context.fill(Path(ellipseIn: rect), with: .color(.accentGold.opacity(0.9)))
        } else {
            context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.8)),
                           lineWidth: 1.6)
        }
    }

    private func drawArrowhead(_ context: GraphicsContext, path: [CGPoint], color: Color) {
        guard path.count >= 2 else { return }
        let tip = path[path.count - 1]
        let prev = path[path.count - 2]
        let angle = atan2(tip.y - prev.y, tip.x - prev.x)
        let len: CGFloat = 7
        var arrow = Path()
        arrow.move(to: tip)
        arrow.addLine(to: CGPoint(x: tip.x - len * cos(angle - 0.5),
                                  y: tip.y - len * sin(angle - 0.5)))
        arrow.move(to: tip)
        arrow.addLine(to: CGPoint(x: tip.x - len * cos(angle + 0.5),
                                  y: tip.y - len * sin(angle + 0.5)))
        context.stroke(arrow, with: .color(color), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
    }
}

// MARK: - Defensive Look Diagram

/// X's-and-zones art for a defensive stance: front + linebackers + shells,
/// blitz arrows in red, zone drops as translucent arcs.
struct DefenseDiagramView: View {

    let coverage: DefensivePlayCall
    let blitz: DefensivePlayCall
    /// Draws man lock-on lines even for zone shells (2-Man Under etc.).
    var manUnder: Bool = false

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height

            // LOS at the bottom; defense looks down the field (up).
            var los = Path()
            los.move(to: CGPoint(x: 0.03 * w, y: 0.86 * h))
            los.addLine(to: CGPoint(x: 0.97 * w, y: 0.86 * h))
            context.stroke(los, with: .color(.white.opacity(0.35)),
                           style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))

            // Front four X's
            for i in 0..<4 {
                let x = 0.5 + CGFloat(i * 2 - 3) * 0.07
                drawX(context, at: CGPoint(x: x * w, y: 0.78 * h), size: 0.025 * w)
            }
            // Linebackers — Double A-Gap mugs both outside backers over center.
            let lbY = 0.62
            let lbXs: [CGFloat] = blitz == .doubleAGap ? [0.44, 0.56, 0.68] : [0.32, 0.5, 0.68]
            for (i, x) in lbXs.enumerated() {
                let y = (blitz == .doubleAGap && i < 2) ? 0.72 : lbY
                drawX(context, at: CGPoint(x: x * w, y: y * h), size: 0.025 * w)
                if blitz == .lbBlitz || blitz == .allOutBlitz {
                    drawBlitzArrow(context, from: CGPoint(x: x * w, y: lbY * h),
                                   to: CGPoint(x: (0.5 + (x - 0.5) * 0.6) * w, y: 0.9 * h))
                } else if blitz == .doubleAGap && i < 2 {
                    drawBlitzArrow(context, from: CGPoint(x: x * w, y: y * h),
                                   to: CGPoint(x: (0.5 + (x - 0.5) * 0.5) * w, y: 0.92 * h))
                }
            }
            // Corners + safeties
            for x in [0.08, 0.92] {
                drawX(context, at: CGPoint(x: x * w, y: 0.6 * h), size: 0.025 * w)
                if blitz == .dbBlitz || blitz == .allOutBlitz {
                    drawBlitzArrow(context, from: CGPoint(x: x * w, y: 0.6 * h),
                                   to: CGPoint(x: (x < 0.5 ? x + 0.1 : x - 0.1) * w, y: 0.9 * h))
                }
            }
            // Safeties: Cover 1 shows a single-high dome with the other one
            // down in the box; the safety blitz sends him instead.
            let safetySpots: [CGPoint] = coverage == .cover1 || blitz == .safetyBlitz
                ? [CGPoint(x: 0.5, y: 0.22), CGPoint(x: 0.7, y: 0.5)]
                : [CGPoint(x: 0.34, y: 0.32), CGPoint(x: 0.66, y: 0.32)]
            for spot in safetySpots {
                drawX(context, at: CGPoint(x: spot.x * w, y: spot.y * h), size: 0.025 * w)
            }
            if blitz == .safetyBlitz {
                drawBlitzArrow(context, from: CGPoint(x: 0.7 * w, y: 0.5 * h),
                               to: CGPoint(x: 0.6 * w, y: 0.9 * h))
            }

            // Coverage shells
            switch coverage {
            case .cover1:
                // Single-high umbrella over man coverage underneath.
                drawZone(context, center: CGPoint(x: 0.5 * w, y: 0.13 * h), rx: 0.24 * w, ry: 0.09 * h)
                drawManLines(context, w: w, h: h)
            case .cover2:
                drawZone(context, center: CGPoint(x: 0.28 * w, y: 0.17 * h), rx: 0.20 * w, ry: 0.10 * h)
                drawZone(context, center: CGPoint(x: 0.72 * w, y: 0.17 * h), rx: 0.20 * w, ry: 0.10 * h)
                if manUnder { drawManLines(context, w: w, h: h) }
            case .cover3:
                for x in [0.18, 0.5, 0.82] {
                    drawZone(context, center: CGPoint(x: x * w, y: 0.17 * h), rx: 0.13 * w, ry: 0.09 * h)
                }
            case .cover4:
                for x in [0.14, 0.38, 0.62, 0.86] {
                    drawZone(context, center: CGPoint(x: x * w, y: 0.17 * h), rx: 0.10 * w, ry: 0.09 * h)
                }
            case .prevent:
                // Sky-deep umbrella: three deep zones pushed to the very top.
                for x in [0.2, 0.5, 0.8] {
                    drawZone(context, center: CGPoint(x: x * w, y: 0.1 * h), rx: 0.15 * w, ry: 0.07 * h)
                }
                drawZone(context, center: CGPoint(x: 0.5 * w, y: 0.42 * h), rx: 0.3 * w, ry: 0.07 * h)
            case .manToMan:
                drawManLines(context, w: w, h: h)
            default:
                if manUnder { drawManLines(context, w: w, h: h) }
            }
        }
        .aspectRatio(1.5, contentMode: .fit)
    }

    /// Man lock lines from the CBs/nickel down onto the receivers.
    private func drawManLines(_ context: GraphicsContext, w: CGFloat, h: CGFloat) {
        for x in [0.08, 0.34, 0.66, 0.92] {
            var line = Path()
            line.move(to: CGPoint(x: x * w, y: (x == 0.08 || x == 0.92 ? 0.6 : 0.45) * h))
            line.addLine(to: CGPoint(x: x * w, y: 0.84 * h))
            context.stroke(line, with: .color(.accentBlue.opacity(0.6)),
                           style: StrokeStyle(lineWidth: 1.5, dash: [2, 3]))
        }
    }

    private func drawX(_ context: GraphicsContext, at point: CGPoint, size: CGFloat) {
        var path = Path()
        path.move(to: CGPoint(x: point.x - size, y: point.y - size))
        path.addLine(to: CGPoint(x: point.x + size, y: point.y + size))
        path.move(to: CGPoint(x: point.x + size, y: point.y - size))
        path.addLine(to: CGPoint(x: point.x - size, y: point.y + size))
        context.stroke(path, with: .color(.white.opacity(0.8)), lineWidth: 1.8)
    }

    private func drawZone(_ context: GraphicsContext, center: CGPoint, rx: CGFloat, ry: CGFloat) {
        let rect = CGRect(x: center.x - rx, y: center.y - ry, width: rx * 2, height: ry * 2)
        context.fill(Path(ellipseIn: rect), with: .color(.accentBlue.opacity(0.14)))
        context.stroke(Path(ellipseIn: rect), with: .color(.accentBlue.opacity(0.4)),
                       style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
    }

    private func drawBlitzArrow(_ context: GraphicsContext, from: CGPoint, to: CGPoint) {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        context.stroke(path, with: .color(.danger.opacity(0.85)),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round))
        let angle = atan2(to.y - from.y, to.x - from.x)
        var arrow = Path()
        arrow.move(to: to)
        arrow.addLine(to: CGPoint(x: to.x - 6 * cos(angle - 0.5), y: to.y - 6 * sin(angle - 0.5)))
        arrow.move(to: to)
        arrow.addLine(to: CGPoint(x: to.x - 6 * cos(angle + 0.5), y: to.y - 6 * sin(angle + 0.5)))
        context.stroke(arrow, with: .color(.danger.opacity(0.85)),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round))
    }
}
