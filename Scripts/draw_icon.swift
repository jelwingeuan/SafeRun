import AppKit

// Minimal, deterministic SafeRun artwork: a cool shield and a cyan play mark.
// Render every native icon representation; no downloaded assets or image service.
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let transform = AffineTransform(scale: CGFloat(pixels) / 1024)
        (transform as NSAffineTransform).concat()
        let tile = NSBezierPath(roundedRect: NSRect(x: 60, y: 60, width: 904, height: 904), xRadius: 205, yRadius: 205)
        NSColor(srgbRed: 0.075, green: 0.105, blue: 0.145, alpha: 1).setFill()
        tile.fill()

        let shield = NSBezierPath()
        shield.move(to: NSPoint(x: 512, y: 810))
        shield.curve(to: NSPoint(x: 760, y: 700), controlPoint1: NSPoint(x: 620, y: 770), controlPoint2: NSPoint(x: 720, y: 735))
        shield.line(to: NSPoint(x: 744, y: 470))
        shield.curve(to: NSPoint(x: 512, y: 242), controlPoint1: NSPoint(x: 720, y: 360), controlPoint2: NSPoint(x: 620, y: 285))
        shield.curve(to: NSPoint(x: 280, y: 470), controlPoint1: NSPoint(x: 404, y: 285), controlPoint2: NSPoint(x: 304, y: 360))
        shield.line(to: NSPoint(x: 264, y: 700))
        shield.curve(to: NSPoint(x: 512, y: 810), controlPoint1: NSPoint(x: 304, y: 735), controlPoint2: NSPoint(x: 404, y: 770))
        shield.close()
        NSColor(srgbRed: 0.66, green: 0.75, blue: 0.84, alpha: 1).setFill()
        shield.fill()

        let play = NSBezierPath()
        play.move(to: NSPoint(x: 438, y: 390))
        play.line(to: NSPoint(x: 438, y: 634))
        play.line(to: NSPoint(x: 658, y: 512))
        play.close()
        NSColor(srgbRed: 0.08, green: 0.67, blue: 0.92, alpha: 1).setFill()
        play.fill()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let output = directory.appendingPathComponent("icon_\(points)x\(points)\(suffix).png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: output)
    }
}
