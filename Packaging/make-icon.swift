// Renders the SwiftBorder app icon: a glowing squircle border (the product
// itself) on a dark gradient squircle. Run with `swift make-icon.swift`,
// then build-app.sh turns the PNG into AppIcon.icns.
import AppKit

let S: CGFloat = 1024

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
    fatalError("could not create bitmap rep")
}

NSGraphicsContext.saveGraphicsState()
let gctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = gctx
let cg = gctx.cgContext

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: a)
}

// --- Background squircle ---------------------------------------------------
// macOS icon grid: content inset a little, generous continuous corners.
let bgInset: CGFloat = 60
let bgRect = CGRect(x: bgInset, y: bgInset, width: S - 2*bgInset, height: S - 2*bgInset)
let bgRadius: CGFloat = 230
let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: bgRadius, yRadius: bgRadius).cgPath

cg.saveGState()
cg.addPath(bgPath)
cg.clip()
let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: [color(40, 42, 58), color(14, 14, 22)] as CFArray,
                    locations: [0, 1])!
cg.drawLinearGradient(bg, start: CGPoint(x: 0, y: S), end: CGPoint(x: 0, y: 0), options: [])

// Soft radial glow behind the border, on-brand cyan.
let halo = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                      colors: [color(70, 224, 255, 0.28), color(70, 224, 255, 0)] as CFArray,
                      locations: [0, 1])!
cg.drawRadialGradient(halo,
                      startCenter: CGPoint(x: S/2, y: S/2), startRadius: 0,
                      endCenter: CGPoint(x: S/2, y: S/2), endRadius: S*0.42,
                      options: [])
cg.restoreGState()

// --- The border (the product) ---------------------------------------------
let borderInset: CGFloat = 272
let borderRect = CGRect(x: borderInset, y: borderInset,
                        width: S - 2*borderInset, height: S - 2*borderInset)
let borderRadius: CGFloat = 108
let borderPath = NSBezierPath(roundedRect: borderRect,
                              xRadius: borderRadius, yRadius: borderRadius).cgPath
let lineWidth: CGFloat = 52
let band = borderPath.copy(strokingWithWidth: lineWidth, lineCap: .round,
                           lineJoin: .round, miterLimit: 10)

// Glow halo: fill the band with a bright color under a blurred shadow.
cg.saveGState()
cg.setShadow(offset: .zero, blur: 60, color: color(70, 224, 255, 0.9))
cg.addPath(band)
cg.setFillColor(color(120, 230, 255))
cg.fillPath()
cg.restoreGState()

// Crisp gradient stroke on top: cyan → blue → violet → pink (the beam look).
cg.saveGState()
cg.addPath(band)
cg.clip()
let beam = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                      colors: [color(70, 224, 255), color(90, 140, 255),
                               color(160, 107, 255), color(255, 120, 200)] as CFArray,
                      locations: [0, 0.4, 0.72, 1])!
cg.drawLinearGradient(beam,
                      start: CGPoint(x: borderRect.minX, y: borderRect.maxY),
                      end: CGPoint(x: borderRect.maxX, y: borderRect.minY),
                      options: [])
cg.restoreGState()

NSGraphicsContext.restoreGraphicsState()

let out = URL(fileURLWithPath: "icon-1024.png")
try! rep.representation(using: .png, properties: [:])!.write(to: out)
print("wrote \(out.path)")
