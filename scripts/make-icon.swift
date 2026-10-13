import AppKit
import Foundation

// Draw the icon from vector primitives so the build has no external assets.
guard CommandLine.arguments.count == 2 else {
    fputs("Usage: swift scripts/make-icon.swift <output.iconset>\n", stderr)
    exit(2)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

func drawArrow(x: CGFloat, from startY: CGFloat, to endY: CGFloat, color: NSColor) {
    let arrow = NSBezierPath()
    arrow.lineWidth = 31
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: x, y: startY))
    arrow.line(to: NSPoint(x: x, y: endY))
    let headY = endY + (endY > startY ? -53 : 53)
    arrow.move(to: NSPoint(x: x - 49, y: headY))
    arrow.line(to: NSPoint(x: x, y: endY))
    arrow.line(to: NSPoint(x: x + 49, y: headY))
    color.setStroke()
    arrow.stroke()
}

func drawIcon(pixelSize: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "MOUSE.Icon", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Could not create bitmap context."])
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    defer { NSGraphicsContext.restoreGraphicsState() }
    context.imageInterpolation = .high
    context.cgContext.setAllowsAntialiasing(true)
    context.cgContext.scaleBy(x: CGFloat(pixelSize) / 1024, y: CGFloat(pixelSize) / 1024)

    let tile = NSBezierPath(roundedRect: NSRect(x: 80, y: 80, width: 864, height: 864),
                            xRadius: 191, yRadius: 191)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -14)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor(calibratedRed: 0.06, green: 0.23, blue: 0.29, alpha: 1).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(starting: NSColor(calibratedRed: 0.10, green: 0.39, blue: 0.46, alpha: 1),
               ending: NSColor(calibratedRed: 0.04, green: 0.15, blue: 0.24, alpha: 1))?
        .draw(in: tile, angle: -65)

    let deviceOutline = NSColor(calibratedRed: 0.82, green: 0.97, blue: 0.96, alpha: 1)
    let deviceFill = NSColor(calibratedRed: 0.57, green: 0.88, blue: 0.89, alpha: 0.10)
    let trackpad = NSBezierPath(roundedRect: NSRect(x: 210, y: 284, width: 347, height: 450),
                                xRadius: 46, yRadius: 46)
    trackpad.lineWidth = 24
    deviceFill.setFill()
    trackpad.fill()
    deviceOutline.setStroke()
    trackpad.stroke()

    let seam = NSBezierPath()
    seam.move(to: NSPoint(x: 226, y: 348))
    seam.line(to: NSPoint(x: 541, y: 348))
    seam.lineWidth = 13
    deviceOutline.withAlphaComponent(0.45).setStroke()
    seam.stroke()

    let mouse = NSBezierPath(roundedRect: NSRect(x: 625, y: 284, width: 183, height: 450),
                             xRadius: 91.5, yRadius: 91.5)
    mouse.lineWidth = 24
    deviceFill.setFill()
    mouse.fill()
    deviceOutline.setStroke()
    mouse.stroke()

    let wheel = NSBezierPath(roundedRect: NSRect(x: 704, y: 630, width: 25, height: 56),
                             xRadius: 12.5, yRadius: 12.5)
    deviceOutline.setFill()
    wheel.fill()

    drawArrow(x: 383.5, from: 406, to: 628, color: deviceOutline)
    drawArrow(x: 716.5, from: 566, to: 391,
              color: NSColor(calibratedRed: 0.36, green: 0.91, blue: 0.79, alpha: 1))

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "MOUSE.Icon", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "Could not encode PNG."])
    }
    return data
}

func appendBigEndian(_ value: UInt32, to data: inout Data) {
    var value = value.bigEndian
    withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
}

// ICNS supports PNG payloads for these standard and Retina representations.
// Writing the small container directly also works in sandboxed build sessions
// where the system iconutil service may be unavailable.
let representationTypes = [
    16: ["icp4", "ic11"],
    32: ["icp5", "ic12"],
    128: ["ic07", "ic13"],
    256: ["ic08", "ic14"],
    512: ["ic09", "ic10"]
]
var representations = Data()
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        let filename = "icon_\(size)x\(size)\(suffix).png"
        let png = try drawIcon(pixelSize: size * scale)
        try png.write(to: outputDirectory.appendingPathComponent(filename))
        representations.append(contentsOf: representationTypes[size]![scale - 1].utf8)
        appendBigEndian(UInt32(png.count + 8), to: &representations)
        representations.append(png)
    }
}
var icon = Data("icns".utf8)
appendBigEndian(UInt32(representations.count + 8), to: &icon)
icon.append(representations)
let iconURL = outputDirectory.deletingPathExtension().appendingPathExtension("icns")
try icon.write(to: iconURL)
guard let decodedIcon = NSImage(contentsOf: iconURL), !decodedIcon.representations.isEmpty else {
    throw NSError(domain: "MOUSE.Icon", code: 3,
                  userInfo: [NSLocalizedDescriptionKey: "Generated ICNS could not be decoded."])
}
print("Generated: \(iconURL.path)")
