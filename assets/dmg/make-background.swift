#!/usr/bin/env swift
// Renders the installer window background for the drag-to-Applications DMG.
//
// Usage: swift assets/dmg/make-background.swift [output-dir]
// Writes background.png (660x400 pt, 1x) and background@2x.png (1320x800 px).
// scripts/build-dmg.sh combines them into background.tiff with tiffutil.
import AppKit

let W: CGFloat = 660
let H: CGFloat = 400

// Palette
let gradTop = NSColor(srgbRed: 0.984, green: 0.984, blue: 0.988, alpha: 1)    // #FBFBFC
let gradBottom = NSColor(srgbRed: 0.941, green: 0.941, blue: 0.949, alpha: 1) // #F0F0F2
let titleColor = NSColor(srgbRed: 0.114, green: 0.114, blue: 0.122, alpha: 1) // #1D1D1F
let noteColor = NSColor(srgbRed: 0.431, green: 0.431, blue: 0.451, alpha: 1)  // #6E6E73
let arrowColor = NSColor(srgbRed: 0.745, green: 0.745, blue: 0.776, alpha: 1) // #BEBEC6

// Coordinates below are "top-left" points (matching Finder icon positions); convert to Quartz's bottom-left.
func flipY(_ top: CGFloat) -> CGFloat { H - top }

func drawCentered(_ text: String, font: NSFont, color: NSColor, topY: CGFloat, kern: CGFloat = 0) {
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .kern: kern]
    let str = NSAttributedString(string: text, attributes: attrs)
    let size = str.size()
    str.draw(at: NSPoint(x: (W - size.width) / 2, y: flipY(topY) - size.height))
}

func drawBackground(_ cg: CGContext) {
    let space = CGColorSpaceCreateDeviceRGB()
    let colors = [gradTop.cgColor, gradBottom.cgColor] as CFArray
    guard let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) else { return }
    // Top-to-bottom: lighter at the top, slightly darker at the bottom.
    cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: H), end: CGPoint(x: 0, y: 0), options: [])
}

func drawArrow() {
    let y = flipY(190)

    // Soft drop shadow under the arrow.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowOffset = NSSize(width: 0, height: -1)
    shadow.shadowBlurRadius = 3
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.08)
    shadow.set()

    let shaft = NSBezierPath()
    shaft.move(to: NSPoint(x: 262, y: y))
    shaft.line(to: NSPoint(x: 394, y: y))
    shaft.lineWidth = 7
    shaft.lineCapStyle = .round
    arrowColor.setStroke()
    shaft.stroke()

    let head = NSBezierPath()
    head.move(to: NSPoint(x: 376, y: y + 16))
    head.line(to: NSPoint(x: 402, y: y))
    head.line(to: NSPoint(x: 376, y: y - 16))
    head.lineWidth = 7
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    head.stroke()
    NSGraphicsContext.restoreGraphicsState()
}

func drawAll(_ cg: CGContext) {
    drawBackground(cg)
    drawCentered("Drag Focus to Applications",
                 font: NSFont.systemFont(ofSize: 22, weight: .semibold),
                 color: titleColor, topY: 40, kern: -0.3)
    drawArrow()
    drawCentered("First launch: System Settings \u{2192} Privacy & Security \u{2192} Open Anyway",
                 font: NSFont.systemFont(ofSize: 12, weight: .regular),
                 color: noteColor, topY: 352)
}

func render(scale: Int, to url: URL) throws {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(W) * scale, pixelsHigh: Int(H) * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { throw NSError(domain: "make-background", code: 1) }
    // Point size stays 660x400 for both files, so the pair is a proper HiDPI set.
    rep.size = NSSize(width: W, height: H)

    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
        throw NSError(domain: "make-background", code: 2)
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high
    drawAll(ctx.cgContext)
    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "make-background", code: 3)
    }
    try png.write(to: url)
}

let outDir = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    : URL(fileURLWithPath: #filePath).deletingLastPathComponent()

do {
    try render(scale: 1, to: outDir.appendingPathComponent("background.png"))
    try render(scale: 2, to: outDir.appendingPathComponent("background@2x.png"))
    print("Written: \(outDir.path)/background.png and background@2x.png")
} catch {
    FileHandle.standardError.write("make-background failed: \(error)\n".data(using: .utf8)!)
    exit(1)
}
