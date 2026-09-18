import AppKit

// Original, deterministic artwork: a blue shield and a mint checkmark.
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
        NSGradient(starting: NSColor(srgbRed: 0.08, green: 0.16, blue: 0.32, alpha: 1),
                   ending: NSColor(srgbRed: 0.16, green: 0.48, blue: 0.88, alpha: 1))!.draw(in: tile, angle: 60)
        let shield = NSBezierPath()
        shield.move(to: NSPoint(x: 512, y: 825))
        shield.curve(to: NSPoint(x: 770, y: 730), controlPoint1: NSPoint(x: 620, y: 765), controlPoint2: NSPoint(x: 700, y: 745))
        shield.line(to: NSPoint(x: 755, y: 490))
        shield.curve(to: NSPoint(x: 512, y: 210), controlPoint1: NSPoint(x: 735, y: 350), controlPoint2: NSPoint(x: 630, y: 260))
        shield.curve(to: NSPoint(x: 269, y: 490), controlPoint1: NSPoint(x: 394, y: 260), controlPoint2: NSPoint(x: 289, y: 350))
        shield.line(to: NSPoint(x: 254, y: 730))
        shield.curve(to: NSPoint(x: 512, y: 825), controlPoint1: NSPoint(x: 324, y: 745), controlPoint2: NSPoint(x: 404, y: 765))
        shield.close()
        NSColor.white.withAlphaComponent(0.96).setStroke()
        shield.lineWidth = 37
        shield.lineJoinStyle = .round
        shield.stroke()
        let check = NSBezierPath()
        check.move(to: NSPoint(x: 380, y: 532))
        check.line(to: NSPoint(x: 479, y: 428))
        check.line(to: NSPoint(x: 659, y: 633))
        check.lineWidth = 64
        check.lineCapStyle = .round
        check.lineJoinStyle = .round
        NSColor(srgbRed: 0.44, green: 0.98, blue: 0.79, alpha: 1).setStroke()
        check.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let output = directory.appendingPathComponent("icon_\(points)x\(points)\(suffix).png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: output)
    }
}
