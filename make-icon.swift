import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let factor = CGFloat(pixels) / 1024
        let transform = NSAffineTransform()
        transform.scale(by: factor)
        transform.concat()

        let tile = NSBezierPath(roundedRect: NSRect(x: 72, y: 72, width: 880, height: 880), xRadius: 198, yRadius: 198)
        NSGradient(starting: NSColor(white: 0.16, alpha: 1), ending: NSColor(white: 0.025, alpha: 1))!.draw(in: tile, angle: -90)
        NSColor(white: 0.30, alpha: 1).setStroke()
        tile.lineWidth = 3
        tile.stroke()

        let moon = NSBezierPath()
        moon.move(to: NSPoint(x: 628, y: 783))
        moon.curve(to: NSPoint(x: 628, y: 241), controlPoint1: NSPoint(x: 310, y: 872), controlPoint2: NSPoint(x: 221, y: 321))
        moon.curve(to: NSPoint(x: 791, y: 374), controlPoint1: NSPoint(x: 702, y: 265), controlPoint2: NSPoint(x: 755, y: 311))
        moon.curve(to: NSPoint(x: 628, y: 783), controlPoint1: NSPoint(x: 493, y: 292), controlPoint2: NSPoint(x: 415, y: 655))
        moon.close()
        NSGradient(starting: NSColor(red: 0.94, green: 0.99, blue: 0.97, alpha: 1),
                   ending: NSColor(red: 0.63, green: 0.83, blue: 0.79, alpha: 1))!.draw(in: moon, angle: -90)
        image.unlockFocus()

        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent(name))
    }
}
