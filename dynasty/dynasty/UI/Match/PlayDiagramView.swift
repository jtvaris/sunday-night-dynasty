import SwiftUI

// MARK: - Offensive Play Diagram

/// Chalkboard X&O art for an offensive play call, drawn with Canvas in a
/// normalized space (offense drives toward the top). O = offense; the primary
/// route/run lane is gold with an arrowhead, secondary routes are dashed gray.
struct PlayDiagramView: View {

    let call: OffensivePlayCall

    /// One receiver/back path: polyline through normalized points.
    private struct Route {
        let points: [CGPoint]
        let primary: Bool
    }

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            func pt(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * w, y: p.y * h) }

            // Line of scrimmage
            var los = Path()
            los.move(to: CGPoint(x: 0.03 * w, y: losY * h))
            los.addLine(to: CGPoint(x: 0.97 * w, y: losY * h))
            context.stroke(los, with: .color(.white.opacity(0.35)),
                           style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))

            // Offensive linemen: five O's on the ball.
            for i in 0..<5 {
                let x = 0.5 + CGFloat(i - 2) * 0.09
                drawO(context, at: pt(CGPoint(x: x, y: losY + 0.055)), radius: 0.026 * w)
            }
            // QB (gun) + RB
            drawO(context, at: pt(qbSpot), radius: 0.026 * w, filled: true)
            if call != .qbSneak {
                drawO(context, at: pt(rbSpot), radius: 0.026 * w)
            }
            // Receivers
            for spot in receiverSpots {
                drawO(context, at: pt(spot), radius: 0.026 * w)
            }

            // Routes
            for route in routes {
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

    // MARK: Geometry

    private var losY: CGFloat { 0.60 }
    private var qbSpot: CGPoint { CGPoint(x: 0.5, y: losY + 0.20) }
    private var rbSpot: CGPoint { CGPoint(x: 0.58, y: losY + 0.20) }

    /// WR-L, slot, TE, WR-R alignment spots.
    private var receiverSpots: [CGPoint] {
        [CGPoint(x: 0.09, y: losY + 0.05),
         CGPoint(x: 0.24, y: losY + 0.07),
         CGPoint(x: 0.76, y: losY + 0.055),
         CGPoint(x: 0.91, y: losY + 0.05)]
    }

    /// The play's routes in normalized coords (y decreases downfield).
    private var routes: [Route] {
        let wrL = receiverSpots[0], slot = receiverSpots[1]
        let te = receiverSpots[2], wrR = receiverSpots[3]

        func up(_ p: CGPoint, _ dy: CGFloat) -> CGPoint { CGPoint(x: p.x, y: p.y - dy) }

        switch call {
        case .insideRun:
            return [Route(points: [rbSpot, CGPoint(x: 0.53, y: losY + 0.02), CGPoint(x: 0.5, y: 0.16)], primary: true),
                    Route(points: [wrL, up(wrL, 0.18)], primary: false),
                    Route(points: [wrR, up(wrR, 0.18)], primary: false)]
        case .outsideRun:
            return [Route(points: [rbSpot, CGPoint(x: 0.74, y: losY + 0.06), CGPoint(x: 0.88, y: 0.24)], primary: true),
                    Route(points: [te, up(te, 0.16)], primary: false),
                    Route(points: [wrL, up(wrL, 0.2)], primary: false)]
        case .counter:
            return [Route(points: [rbSpot, CGPoint(x: 0.68, y: losY + 0.14), CGPoint(x: 0.42, y: losY + 0.02), CGPoint(x: 0.36, y: 0.2)], primary: true),
                    Route(points: [wrR, up(wrR, 0.18)], primary: false),
                    Route(points: [te, up(te, 0.12)], primary: false)]
        case .toss:
            return [Route(points: [rbSpot, CGPoint(x: 0.8, y: losY + 0.16), CGPoint(x: 0.95, y: 0.3)], primary: true),
                    Route(points: [wrR, up(wrR, 0.12), CGPoint(x: 0.99, y: losY - 0.1)], primary: false),
                    Route(points: [wrL, up(wrL, 0.2)], primary: false)]
        case .draw:
            return [Route(points: [qbSpot, CGPoint(x: 0.5, y: losY + 0.26)], primary: false),
                    Route(points: [rbSpot, CGPoint(x: 0.52, y: losY + 0.05), CGPoint(x: 0.5, y: 0.2)], primary: true)]
        case .screen:
            return [Route(points: [rbSpot, CGPoint(x: 0.72, y: losY + 0.16), CGPoint(x: 0.86, y: losY + 0.1), CGPoint(x: 0.92, y: 0.3)], primary: true),
                    Route(points: [wrL, up(wrL, 0.22)], primary: false),
                    Route(points: [slot, up(slot, 0.18)], primary: false)]
        case .slant:
            return [Route(points: [wrL, up(wrL, 0.1), CGPoint(x: 0.34, y: 0.3)], primary: true),
                    Route(points: [slot, up(slot, 0.09), CGPoint(x: 0.44, y: 0.38)], primary: false),
                    Route(points: [wrR, up(wrR, 0.24)], primary: false)]
        case .quickOut:
            return [Route(points: [wrR, up(wrR, 0.12), CGPoint(x: 0.99, y: losY - 0.14)], primary: true),
                    Route(points: [wrL, up(wrL, 0.12), CGPoint(x: 0.01, y: losY - 0.14)], primary: false),
                    Route(points: [slot, up(slot, 0.2)], primary: false)]
        case .hitch:
            return [Route(points: [wrL, up(wrL, 0.14), CGPoint(x: 0.11, y: losY - 0.1)], primary: true),
                    Route(points: [wrR, up(wrR, 0.14), CGPoint(x: 0.89, y: losY - 0.1)], primary: false),
                    Route(points: [slot, up(slot, 0.2)], primary: false)]
        case .flat:
            return [Route(points: [rbSpot, CGPoint(x: 0.78, y: losY + 0.13), CGPoint(x: 0.95, y: losY - 0.02)], primary: true),
                    Route(points: [te, up(te, 0.14), CGPoint(x: 0.68, y: 0.34)], primary: false),
                    Route(points: [wrR, up(wrR, 0.26)], primary: false)]
        case .drag:
            return [Route(points: [slot, up(slot, 0.07), CGPoint(x: 0.72, y: losY - 0.11)], primary: true),
                    Route(points: [te, up(te, 0.07), CGPoint(x: 0.34, y: losY - 0.14)], primary: false),
                    Route(points: [wrL, up(wrL, 0.26)], primary: false)]
        case .curl:
            return [Route(points: [wrL, up(wrL, 0.26), CGPoint(x: 0.13, y: losY - 0.19)], primary: true),
                    Route(points: [wrR, up(wrR, 0.26), CGPoint(x: 0.87, y: losY - 0.19)], primary: false),
                    Route(points: [slot, up(slot, 0.14), CGPoint(x: 0.32, y: losY - 0.1)], primary: false)]
        case .dig:
            return [Route(points: [wrR, up(wrR, 0.3), CGPoint(x: 0.55, y: losY - 0.3)], primary: true),
                    Route(points: [wrL, up(wrL, 0.34)], primary: false),
                    Route(points: [slot, up(slot, 0.12), CGPoint(x: 0.4, y: losY - 0.08)], primary: false)]
        case .seam:
            return [Route(points: [te, CGPoint(x: 0.72, y: 0.12)], primary: true),
                    Route(points: [wrL, up(wrL, 0.3)], primary: false),
                    Route(points: [wrR, up(wrR, 0.14), CGPoint(x: 0.97, y: losY - 0.12)], primary: false)]
        case .cross:
            return [Route(points: [slot, up(slot, 0.12), CGPoint(x: 0.62, y: 0.3), CGPoint(x: 0.86, y: 0.22)], primary: true),
                    Route(points: [wrR, up(wrR, 0.3)], primary: false),
                    Route(points: [wrL, up(wrL, 0.16), CGPoint(x: 0.08, y: losY - 0.14)], primary: false)]
        case .postCorner:
            return [Route(points: [slot, up(slot, 0.2), CGPoint(x: 0.34, y: 0.26), CGPoint(x: 0.16, y: 0.1)], primary: true),
                    Route(points: [wrL, up(wrL, 0.3)], primary: false),
                    Route(points: [wrR, up(wrR, 0.26)], primary: false)]
        case .comeback:
            return [Route(points: [wrR, up(wrR, 0.34), CGPoint(x: 0.97, y: losY - 0.24)], primary: true),
                    Route(points: [wrL, up(wrL, 0.34), CGPoint(x: 0.03, y: losY - 0.24)], primary: false),
                    Route(points: [te, up(te, 0.16)], primary: false)]
        case .goRoute:
            return [Route(points: [wrL, CGPoint(x: 0.09, y: 0.06)], primary: true),
                    Route(points: [wrR, up(wrR, 0.3)], primary: false),
                    Route(points: [slot, up(slot, 0.16), CGPoint(x: 0.36, y: losY - 0.12)], primary: false)]
        case .post:
            return [Route(points: [wrR, up(wrR, 0.24), CGPoint(x: 0.62, y: 0.08)], primary: true),
                    Route(points: [wrL, up(wrL, 0.3)], primary: false),
                    Route(points: [rbSpot, CGPoint(x: 0.7, y: losY + 0.1), CGPoint(x: 0.85, y: losY - 0.02)], primary: false)]
        case .corner:
            return [Route(points: [slot, up(slot, 0.22), CGPoint(x: 0.08, y: 0.12)], primary: true),
                    Route(points: [wrR, up(wrR, 0.28)], primary: false),
                    Route(points: [wrL, up(wrL, 0.14), CGPoint(x: 0.3, y: losY - 0.1)], primary: false)]
        case .flood:
            return [Route(points: [wrR, up(wrR, 0.32)], primary: true),
                    Route(points: [te, up(te, 0.14), CGPoint(x: 0.93, y: losY - 0.16)], primary: false),
                    Route(points: [rbSpot, CGPoint(x: 0.78, y: losY + 0.12), CGPoint(x: 0.95, y: losY - 0.01)], primary: false)]
        case .bomb:
            return [Route(points: [wrL, CGPoint(x: 0.12, y: 0.03)], primary: true),
                    Route(points: [wrR, CGPoint(x: 0.88, y: 0.03)], primary: false),
                    Route(points: [slot, up(slot, 0.24)], primary: false)]
        case .qbSneak:
            return [Route(points: [qbSpot, CGPoint(x: 0.5, y: losY - 0.12)], primary: true)]
        case .spike:
            return [Route(points: [qbSpot, CGPoint(x: 0.5, y: losY + 0.28)], primary: true)]
        case .kneel:
            return [Route(points: [qbSpot, CGPoint(x: 0.5, y: losY + 0.28)], primary: true)]
        }
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
            // Linebackers
            let lbY = 0.62
            for x in [0.32, 0.5, 0.68] {
                drawX(context, at: CGPoint(x: x * w, y: lbY * h), size: 0.025 * w)
                if blitz == .lbBlitz || blitz == .allOutBlitz {
                    drawBlitzArrow(context, from: CGPoint(x: x * w, y: lbY * h),
                                   to: CGPoint(x: x * w, y: 0.9 * h))
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
            for x in [0.34, 0.66] {
                drawX(context, at: CGPoint(x: x * w, y: 0.32 * h), size: 0.025 * w)
            }

            // Coverage shells
            switch coverage {
            case .cover2:
                drawZone(context, center: CGPoint(x: 0.28 * w, y: 0.16 * h), rx: 0.24 * w, ry: 0.14 * h)
                drawZone(context, center: CGPoint(x: 0.72 * w, y: 0.16 * h), rx: 0.24 * w, ry: 0.14 * h)
            case .cover3:
                for x in [0.18, 0.5, 0.82] {
                    drawZone(context, center: CGPoint(x: x * w, y: 0.15 * h), rx: 0.16 * w, ry: 0.13 * h)
                }
            case .cover4:
                for x in [0.14, 0.38, 0.62, 0.86] {
                    drawZone(context, center: CGPoint(x: x * w, y: 0.15 * h), rx: 0.12 * w, ry: 0.12 * h)
                }
            case .manToMan:
                // Man: lock lines from CBs/safeties straight down at receivers.
                for x in [0.08, 0.34, 0.66, 0.92] {
                    var line = Path()
                    line.move(to: CGPoint(x: x * w, y: (x == 0.08 || x == 0.92 ? 0.6 : 0.32) * h))
                    line.addLine(to: CGPoint(x: x * w, y: 0.84 * h))
                    context.stroke(line, with: .color(.accentBlue.opacity(0.6)),
                                   style: StrokeStyle(lineWidth: 1.5, dash: [2, 3]))
                }
            default:
                break
            }
        }
        .aspectRatio(1.5, contentMode: .fit)
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
