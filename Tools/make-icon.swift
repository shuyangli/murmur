// Renders Resources/Murmur.icns.
// Run from the project root with: swift Tools/make-icon.swift
import AppKit
import Foundation

let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let outputDirectory = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : projectRoot.appendingPathComponent("Resources")

let iconset = outputDirectory.appendingPathComponent("Murmur.iconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

/// Heights of the waveform bars as a fraction of the icon, read left to right.
let barHeights: [CGFloat] = [0.20, 0.38, 0.62, 0.86, 0.62, 0.38, 0.20]

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS app icons sit inside the canvas with a margin rather than
    // bleeding to the edges.
    let inset = size * 0.085
    let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let corner = rect.width * 0.235
    let squircle = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)

    NSGradient(colors: [
        NSColor(srgbRed: 0.42, green: 0.33, blue: 0.92, alpha: 1),
        NSColor(srgbRed: 0.28, green: 0.18, blue: 0.62, alpha: 1),
    ])!.draw(in: squircle, angle: -90)

    let barWidth = rect.width * 0.062
    let spacing = barWidth * 1.72
    let totalWidth = spacing * CGFloat(barHeights.count - 1)
    let startX = rect.midX - totalWidth / 2

    NSColor.white.setFill()
    for (index, fraction) in barHeights.enumerated() {
        let height = rect.height * 0.60 * fraction
        let barRect = NSRect(
            x: startX + spacing * CGFloat(index) - barWidth / 2,
            y: rect.midY - height / 2,
            width: barWidth,
            height: height
        )
        NSBezierPath(roundedRect: barRect, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// Names iconutil expects inside an .iconset directory.
let variants: [(name: String, pixels: CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for variant in variants {
    let rep = drawIcon(size: variant.pixels)
    guard let data = rep.representation(using: .png, properties: [:]) else { continue }
    try data.write(to: iconset.appendingPathComponent("\(variant.name).png"))
}

print(iconset.path)
