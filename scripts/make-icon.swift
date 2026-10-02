// Renders the SF Symbol `checkmark.seal.text.page` into Nag's AppIcon set.
// Usage (from the repo root): swift scripts/make-icon.swift
import AppKit

let symbolName = "checkmark.seal.text.page"
let canvas: CGFloat = 1024
let topColor = NSColor(srgbRed: 1.0, green: 0x9F / 255.0, blue: 0x0A / 255.0, alpha: 1)
let bottomColor = NSColor(srgbRed: 1.0, green: 0x6B / 255.0, blue: 0x00 / 255.0, alpha: 1)

let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let catalog = repoRoot.appending(path: "Nag/Assets.xcassets")
let iconSet = catalog.appending(path: "AppIcon.appiconset")

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    // Draw in a 1024-point coordinate space regardless of the output pixel size.
    rep.size = NSSize(width: canvas, height: canvas)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS icon grid: an 824-point body centered on a 1024-point canvas.
    let bodyRect = NSRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = NSBezierPath(roundedRect: bodyRect, xRadius: 185, yRadius: 185)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 20
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    bottomColor.setFill()
    bodyPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(starting: topColor, ending: bottomColor)!.draw(in: bodyPath, angle: -90)

    let config = NSImage.SymbolConfiguration(pointSize: 420, weight: .regular)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
        .withSymbolConfiguration(config) else {
        fatalError("SF Symbol \(symbolName) is not available on this system")
    }
    let scale = (canvas * 0.55) / max(symbol.size.width, symbol.size.height)
    let size = NSSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
    symbol.draw(in: NSRect(
        x: (canvas - size.width) / 2,
        y: (canvas - size.height) / 2,
        width: size.width,
        height: size.height
    ))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fileManager = FileManager.default
try fileManager.createDirectory(at: iconSet, withIntermediateDirectories: true)

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let filename = scale == 1
            ? "icon_\(points)x\(points).png"
            : "icon_\(points)x\(points)@2x.png"
        try render(pixels: points * scale).write(to: iconSet.appending(path: filename))
        images.append([
            "filename": filename,
            "idiom": "mac",
            "scale": "\(scale)x",
            "size": "\(points)x\(points)"
        ])
    }
}

let info = ["author": "xcode", "version": 1] as [String: Any]
let encoder = { (object: Any) in
    try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
}
try encoder(["images": images, "info": info]).write(to: iconSet.appending(path: "Contents.json"))
try encoder(["info": info]).write(to: catalog.appending(path: "Contents.json"))
print("Wrote \(images.count) icons to \(iconSet.path)")
