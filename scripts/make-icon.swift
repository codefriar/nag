// Draws Nag's app icon: a white speech bubble with an orange "!" on an
// orange rounded square. Original artwork; no SF Symbols.
// Usage (from the repo root): swift scripts/make-icon.swift
import AppKit

let canvas: CGFloat = 1024
let topColor = NSColor(srgbRed: 1.0, green: 0x9F / 255.0, blue: 0x0A / 255.0, alpha: 1)
let bottomColor = NSColor(srgbRed: 1.0, green: 0x6B / 255.0, blue: 0x00 / 255.0, alpha: 1)
let markColor = NSColor(srgbRed: 1.0, green: 0x7A / 255.0, blue: 0x00 / 255.0, alpha: 1)

let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let catalog = repoRoot.appending(path: "Nag/Assets.xcassets")
let iconSet = catalog.appending(path: "AppIcon.appiconset")

func drawBackground() {
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
}

func drawBubble() {
    // Body: 520x400, centered horizontally, slightly above center (AppKit y is up).
    let body = NSRect(x: (canvas - 520) / 2, y: 330, width: 520, height: 400)
    let bodyPath = NSBezierPath(roundedRect: body, xRadius: 110, yRadius: 110)

    // Tail: starts inside the body's bottom-left quarter and points down-left.
    // Filling both shapes in the same color renders their union.
    let tail = NSBezierPath()
    tail.move(to: NSPoint(x: body.minX + 120, y: body.minY + 40))
    tail.line(to: NSPoint(x: body.minX + 240, y: body.minY + 40))
    tail.line(to: NSPoint(x: body.minX + 60, y: body.minY - 110))
    tail.close()

    NSColor.white.setFill()
    bodyPath.fill()
    tail.fill()
}

func drawExclamation() {
    // Bar 64x200 + 36 gap + 72 dot = 308 tall, centered on the bubble body (y = 530).
    let centerX = canvas / 2
    let barTop: CGFloat = 530 + 154
    let bar = NSRect(x: centerX - 32, y: barTop - 200, width: 64, height: 200)
    let dot = NSRect(x: centerX - 36, y: bar.minY - 36 - 72, width: 72, height: 72)

    markColor.setFill()
    NSBezierPath(roundedRect: bar, xRadius: 32, yRadius: 32).fill()
    NSBezierPath(ovalIn: dot).fill()
}

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
    drawBackground()
    drawBubble()
    drawExclamation()
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
