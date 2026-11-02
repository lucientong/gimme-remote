// Renders the App and Home Screen icons. Run from the repository root:
//   swift scripts/make-icons.swift
// Outputs are committed, so builds need no extra tools beyond iconutil.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

/// `inset` leaves the transparent margin and shadow macOS icons expect; Home Screen icons are full bleed.
func render(size: Int, inset: Bool, compact: Bool = false) -> CGImage {
    let s = CGFloat(size)
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let tile = inset ? CGRect(x: s * 0.098, y: s * 0.098 - s * 0.01, width: s * 0.804, height: s * 0.804)
                     : CGRect(x: 0, y: 0, width: s, height: s)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: inset ? tile.width * 0.225 : 0,
                          cornerHeight: inset ? tile.width * 0.225 : 0, transform: nil)
    if inset {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.01), blur: s * 0.02, color: color(0x000000, 0.35))
        ctx.addPath(tilePath); ctx.setFillColor(color(0x171a18)); ctx.fillPath()
        ctx.restoreGState()
    }
    ctx.saveGState()
    ctx.addPath(tilePath); ctx.clip()
    let gradient = CGGradient(colorsSpace: nil, colors: [color(0x2a3027), color(0x141714)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: tile.minX, y: tile.maxY), end: CGPoint(x: tile.maxX, y: tile.minY), options: [])

    // Finder's small icons use one large play key instead of an unreadable remote outline.
    if compact {
        let center = CGPoint(x: tile.midX, y: tile.midY)
        let radius = tile.width * 0.36
        ctx.setFillColor(color(0xa5b957))
        ctx.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius - s * 0.02, width: radius * 2, height: radius * 2))
        ctx.setFillColor(color(0xd9f279))
        ctx.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        let t = radius * 0.5
        ctx.move(to: CGPoint(x: center.x - t * 0.7, y: center.y + t))
        ctx.addLine(to: CGPoint(x: center.x + t * 1.05, y: center.y))
        ctx.addLine(to: CGPoint(x: center.x - t * 0.7, y: center.y - t))
        ctx.closePath(); ctx.setFillColor(color(0x242e15)); ctx.fillPath()
        ctx.restoreGState()
        return ctx.makeImage()!
    }

    // The remote, tilted counterclockwise like the brand mark on the phone page.
    let unit = tile.width
    ctx.translateBy(x: tile.midX, y: tile.midY)
    ctx.rotate(by: 12 * .pi / 180)
    let body = CGRect(x: -unit * 0.18, y: -unit * 0.36, width: unit * 0.36, height: unit * 0.72)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -unit * 0.02), blur: unit * 0.05, color: color(0x000000, 0.5))
    ctx.addPath(CGPath(roundedRect: body, cornerWidth: unit * 0.18, cornerHeight: unit * 0.18, transform: nil))
    ctx.setFillColor(color(0x30362d)); ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(CGPath(roundedRect: body.insetBy(dx: unit * 0.006, dy: unit * 0.006), cornerWidth: unit * 0.174, cornerHeight: unit * 0.174, transform: nil))
    ctx.setStrokeColor(color(0xffffff, 0.08)); ctx.setLineWidth(unit * 0.008); ctx.strokePath()

    // Big green play button.
    let center = CGPoint(x: 0, y: unit * 0.12)
    let radius = unit * 0.125
    ctx.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius - unit * 0.016, width: radius * 2, height: radius * 2))
    ctx.setFillColor(color(0xa5b957)); ctx.fillPath()
    ctx.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    ctx.setFillColor(color(0xd9f279)); ctx.fillPath()
    let t = radius * 0.42
    ctx.move(to: CGPoint(x: center.x - t * 0.7, y: center.y + t))
    ctx.addLine(to: CGPoint(x: center.x + t * 1.05, y: center.y))
    ctx.addLine(to: CGPoint(x: center.x - t * 0.7, y: center.y - t))
    ctx.closePath(); ctx.setFillColor(color(0x242e15)); ctx.fillPath()

    // Two small keys below.
    ctx.setLineCap(.round); ctx.setLineWidth(unit * 0.034); ctx.setStrokeColor(color(0x8a9671))
    for y in [-unit * 0.1, -unit * 0.19] {
        ctx.move(to: CGPoint(x: -unit * 0.06, y: y)); ctx.addLine(to: CGPoint(x: unit * 0.06, y: y))
    }
    ctx.strokePath()
    ctx.restoreGState()
    return ctx.makeImage()!
}

func write(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path)
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    precondition(CGImageDestinationFinalize(destination), "Cannot write \(path)")
}

let iconset = NSTemporaryDirectory() + "AppIcon-\(ProcessInfo.processInfo.processIdentifier).iconset"
for points in [16, 32, 128, 256, 512] {
    write(render(size: points, inset: true, compact: points <= 32), to: "\(iconset)/icon_\(points)x\(points).png")
    write(render(size: points * 2, inset: true, compact: points <= 32), to: "\(iconset)/icon_\(points)x\(points)@2x.png")
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset, "-o", "mac/AppIcon.icns"]
try iconutil.run(); iconutil.waitUntilExit()
precondition(iconutil.terminationStatus == 0, "iconutil failed")
try? FileManager.default.removeItem(atPath: iconset)
write(render(size: 180, inset: false), to: "web/public/icons/apple-touch-icon.png")
write(render(size: 192, inset: false), to: "web/public/icons/icon-192.png")
write(render(size: 512, inset: false), to: "web/public/icons/icon-512.png")
print("Wrote mac/AppIcon.icns and web/public/icons/*.png")
