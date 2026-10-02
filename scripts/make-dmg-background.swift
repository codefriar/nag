// Draws the DMG window background (660x400 pt) at 1x and 2x, then combines
// them into a HiDPI TIFF for create-dmg.
// Usage (from the repo root): swift scripts/make-dmg-background.swift
import AppKit

let size = NSSize(width: 660, height: 400)
let backgroundColor = NSColor(srgbRed: 0xF7 / 255.0, green: 0xF5 / 255.0, blue: 0xF2 / 255.0, alpha: 1)
let arrowColor = NSColor(srgbRed: 0xB8 / 255.0, green: 0xB2 / 255.0, blue: 0xAA / 255.0, alpha: 1)
let captionColor = NSColor(srgbRed: 0x8A / 255.0, green: 0x84 / 255.0, blue: 0x7C / 255.0, alpha: 1)

let outputDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appending(path: "dmg")

/// Converts a Finder y coordinate (measured from the top) to AppKit's bottom-up y.
func appKitY(_ finderY: CGFloat) -> CGFloat { size.height - finderY }

func render(scale: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size.width) * scale, pixelsHigh: Int(size.height) * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = size

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    backgroundColor.setFill()
    NSRect(origin: .zero, size: size).fill()

    // Arrow from the app icon (x=180) toward the Applications link (x=480), at icon height.
    let y = appKitY(190)
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 260, y: y))
    arrow.line(to: NSPoint(x: 400, y: y))
    arrow.move(to: NSPoint(x: 382, y: y + 16))
    arrow.line(to: NSPoint(x: 400, y: y))
    arrow.line(to: NSPoint(x: 382, y: y - 16))
    arrow.lineWidth = 6
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrowColor.setStroke()
    arrow.stroke()

    let caption = NSAttributedString(
        string: "Drag Nag to Applications",
        attributes: [
            .font: NSFont.systemFont(ofSize: 15),
            .foregroundColor: captionColor
        ]
    )
    let captionSize = caption.size()
    caption.draw(at: NSPoint(
        x: (size.width - captionSize.width) / 2,
        y: appKitY(320) - captionSize.height / 2
    ))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
let png1x = outputDir.appending(path: "background.png")
let png2x = outputDir.appending(path: "background@2x.png")
let tiff = outputDir.appending(path: "background.tiff")
try render(scale: 1).write(to: png1x)
try render(scale: 2).write(to: png2x)

let tiffutil = Process()
tiffutil.executableURL = URL(fileURLWithPath: "/usr/bin/tiffutil")
tiffutil.arguments = ["-cathidpicheck", png1x.path, png2x.path, "-out", tiff.path]
try tiffutil.run()
tiffutil.waitUntilExit()
guard tiffutil.terminationStatus == 0 else {
    fatalError("tiffutil failed with status \(tiffutil.terminationStatus)")
}
print("Wrote \(tiff.path)")
