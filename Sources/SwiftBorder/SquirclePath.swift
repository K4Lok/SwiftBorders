import CoreGraphics
import Foundation

// Builds macOS's continuous "squircle" rounded-rect path — the corner shape the
// WindowServer actually uses — so a stroked border overlays the window's corner
// exactly. This is the figma-squircle construction (the documented match for
// Apple's continuous corners), NOT a superellipse: each corner is
//   straight → cubic ease-in → short circular arc → cubic ease-out → straight.
// That keeps the apex at the same place as a circle of radius r (so it matches
// the window) while easing the join. `smoothing` is 0…1 (Apple uses ~0.6).
//
// We stroke this centerline, so the border has uniform width everywhere.
enum SquirclePath {
    private struct Corner {
        let s, cp1, cp2, p3, acp1, acp2, p4, cp3, cp4, p5: CGPoint
    }

    static func path(in rect: CGRect, cornerRadius: CGFloat, smoothing: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let budget = min(rect.width, rect.height) / 2
        let r = min(max(cornerRadius, 0), budget)
        guard r > 0 else { path.addRect(rect); return path }

        let s = min(max(smoothing, 0), 1)
        func rad(_ d: CGFloat) -> CGFloat { d * .pi / 180 }

        // figma-squircle corner parameters
        let p = min((1 + s) * r, budget)
        let arcMeasure = 90 * (1 - s)
        let arc = sin(rad(arcMeasure / 2)) * r * 2.squareRoot()
        let angleAlpha = (90 - arcMeasure) / 2
        let p3p4 = r * tan(rad(angleAlpha / 2))
        let angleBeta = 45 * s
        let c = p3p4 * cos(rad(angleBeta))
        let d = c * tan(rad(angleBeta))
        let b = (p - arc - c - d) / 3
        let a = 2 * b
        let k = 4.0 / 3.0 * tan(rad(arcMeasure / 4))   // cubic control length factor for the arc

        // V = corner vertex; u = unit dir along the incoming edge (toward V);
        // v = unit dir along the outgoing edge (away from V).
        func corner(_ V: CGPoint, _ u: CGVector, _ v: CGVector) -> Corner {
            func at(_ du: CGFloat, _ dv: CGFloat, from base: CGPoint = V) -> CGPoint {
                CGPoint(x: base.x + u.dx * du + v.dx * dv, y: base.y + u.dy * du + v.dy * dv)
            }
            let s0 = at(-p, 0)
            let cp1 = CGPoint(x: s0.x + u.dx * a, y: s0.y + u.dy * a)
            let cp2 = CGPoint(x: s0.x + u.dx * (a + b), y: s0.y + u.dy * (a + b))
            let p3 = at(a + b + c, d, from: s0)
            let p4 = CGPoint(x: p3.x + (u.dx + v.dx) * arc, y: p3.y + (u.dy + v.dy) * arc)
            let cp3 = at(d, c, from: p4)
            let cp4 = at(d, b + c, from: p4)
            let p5 = at(0, p)
            let ctr = at(-r, r)
            // arc cubic controls: forward tangent = radius rotated +90°, fwd = (-ry, rx)
            let r3 = CGVector(dx: (p3.x - ctr.x) / r, dy: (p3.y - ctr.y) / r)
            let r4 = CGVector(dx: (p4.x - ctr.x) / r, dy: (p4.y - ctr.y) / r)
            let f3 = CGVector(dx: -r3.dy, dy: r3.dx)
            let f4 = CGVector(dx: -r4.dy, dy: r4.dx)
            let acp1 = CGPoint(x: p3.x + f3.dx * k * r, y: p3.y + f3.dy * k * r)
            let acp2 = CGPoint(x: p4.x - f4.dx * k * r, y: p4.y - f4.dy * k * r)
            return Corner(s: s0, cp1: cp1, cp2: cp2, p3: p3, acp1: acp1, acp2: acp2, p4: p4, cp3: cp3, cp4: cp4, p5: p5)
        }

        let minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
        let tr = corner(CGPoint(x: maxX, y: minY), CGVector(dx: 1, dy: 0), CGVector(dx: 0, dy: 1))
        let br = corner(CGPoint(x: maxX, y: maxY), CGVector(dx: 0, dy: 1), CGVector(dx: -1, dy: 0))
        let bl = corner(CGPoint(x: minX, y: maxY), CGVector(dx: -1, dy: 0), CGVector(dx: 0, dy: -1))
        let tl = corner(CGPoint(x: minX, y: minY), CGVector(dx: 0, dy: -1), CGVector(dx: 1, dy: 0))

        func emit(_ corner: Corner) {
            path.addCurve(to: corner.p3, control1: corner.cp1, control2: corner.cp2)
            path.addCurve(to: corner.p4, control1: corner.acp1, control2: corner.acp2)
            path.addCurve(to: corner.p5, control1: corner.cp3, control2: corner.cp4)
        }

        path.move(to: tl.p5)
        path.addLine(to: tr.s); emit(tr)
        path.addLine(to: br.s); emit(br)
        path.addLine(to: bl.s); emit(bl)
        path.addLine(to: tl.s); emit(tl)
        path.closeSubpath()
        return path
    }
}
