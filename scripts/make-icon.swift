import AppKit

let output = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let pixels = points * scale
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = NSSize(width: 1024, height: 1024)
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
    NSColor.clear.setFill(); NSRect(x: 0, y: 0, width: 1024, height: 1024).fill()
    let rect = NSRect(x: 84, y: 84, width: 856, height: 856)
    let background = NSBezierPath(roundedRect: rect, xRadius: 196, yRadius: 196)
    NSGradient(starting: NSColor(srgbRed: 0.26, green: 0.47, blue: 1, alpha: 1), ending: NSColor(srgbRed: 0.20, green: 0.24, blue: 0.81, alpha: 1))!.draw(in: background, angle: -90)
    NSColor.white.setStroke()
    // A near-square glyph, with enough vertical shaft for two distinct arrows.
    let fork = NSBezierPath(); fork.lineWidth = 56; fork.lineCapStyle = .round; fork.lineJoinStyle = .round
    fork.move(to: NSPoint(x: 512, y: 242)); fork.line(to: NSPoint(x: 512, y: 450))
    fork.curve(to: NSPoint(x: 328, y: 724), controlPoint1: NSPoint(x: 512, y: 610), controlPoint2: NSPoint(x: 328, y: 548))
    fork.line(to: NSPoint(x: 328, y: 792))
    fork.move(to: NSPoint(x: 512, y: 450))
    fork.curve(to: NSPoint(x: 696, y: 724), controlPoint1: NSPoint(x: 512, y: 610), controlPoint2: NSPoint(x: 696, y: 548))
    fork.line(to: NSPoint(x: 696, y: 792))
    fork.move(to: NSPoint(x: 252, y: 716)); fork.line(to: NSPoint(x: 328, y: 792)); fork.line(to: NSPoint(x: 404, y: 716))
    fork.move(to: NSPoint(x: 620, y: 716)); fork.line(to: NSPoint(x: 696, y: 792)); fork.line(to: NSPoint(x: 772, y: 716)); fork.stroke()
    NSGraphicsContext.restoreGraphicsState()
    bitmap.size = NSSize(width: pixels, height: pixels)
    let suffix = scale == 2 ? "@2x" : ""
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output + "/icon_\(points)x\(points)\(suffix).png"))
}
