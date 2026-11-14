// Builds Resources/AppIcon.icns from the square master artwork.
// Usage: swift scripts/make-icon.swift Resources/Icons/cpaste-app-icon.png Resources/AppIcon.icns
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3, let master = NSImage(contentsOfFile: arguments[1]) else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <master.png> <output.icns>\n".utf8))
    exit(1)
}
let output = URL(fileURLWithPath: arguments[2])
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("cpaste-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(pixels: Int) throws -> Data {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    // Apple's macOS icon grid puts an 824 point rounded square with a 185 point corner radius on a 1024 point canvas.
    let scale = Double(pixels) / 1024
    let body = NSRect(x: 100 * scale, y: 100 * scale, width: 824 * scale, height: 824 * scale)
    NSBezierPath(roundedRect: body, xRadius: 185 * scale, yRadius: 185 * scale).addClip()
    NSGraphicsContext.current?.imageInterpolation = .high
    master.draw(in: body)
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    try render(pixels: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try render(pixels: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
try FileManager.default.removeItem(at: iconset)
exit(iconutil.terminationStatus)
