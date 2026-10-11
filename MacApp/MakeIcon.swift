import AppKit

let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let side = CGFloat(pixels)
        let canvas = NSRect(x: 0, y: 0, width: side, height: side)
        NSColor(calibratedRed: 0.12, green: 0.35, blue: 0.78, alpha: 1).setFill()
        NSBezierPath(roundedRect: canvas.insetBy(dx: side * 0.05, dy: side * 0.05), xRadius: side * 0.2, yRadius: side * 0.2).fill()
        NSColor.white.setFill()
        let envelope = NSRect(x: side * 0.2, y: side * 0.31, width: side * 0.6, height: side * 0.4)
        NSBezierPath(roundedRect: envelope, xRadius: side * 0.045, yRadius: side * 0.045).fill()
        NSColor(calibratedRed: 0.12, green: 0.35, blue: 0.78, alpha: 1).setStroke()
        let flap = NSBezierPath()
        flap.move(to: NSPoint(x: envelope.minX + side * 0.025, y: envelope.maxY - side * 0.035))
        flap.line(to: NSPoint(x: side * 0.5, y: side * 0.48))
        flap.line(to: NSPoint(x: envelope.maxX - side * 0.025, y: envelope.maxY - side * 0.035))
        flap.lineWidth = side * 0.027; flap.stroke()
        NSColor(calibratedRed: 0.15, green: 0.7, blue: 0.46, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: side * 0.62, y: side * 0.16, width: side * 0.26, height: side * 0.26)).fill()
        NSColor.white.setStroke()
        let check = NSBezierPath()
        check.move(to: NSPoint(x: side * 0.68, y: side * 0.29))
        check.line(to: NSPoint(x: side * 0.73, y: side * 0.24))
        check.line(to: NSPoint(x: side * 0.82, y: side * 0.34))
        check.lineWidth = side * 0.028; check.lineCapStyle = .round; check.lineJoinStyle = .round; check.stroke()
        NSGraphicsContext.restoreGraphicsState()
        try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent("icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"))
    }
}
