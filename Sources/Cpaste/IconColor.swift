import AppKit

enum IconColor {
    private static let side = 32
    private static let hueBins = 12

    /// The most common vivid colour of an icon, toned so white text reads on it. Nil when the icon is mostly grey, white or black.
    static func dominant(of icon: NSImage) -> NSColor? {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: side * 4, bitsPerPixel: 32),
            let context = NSGraphicsContext(bitmapImageRep: bitmap), let pixels = bitmap.bitmapData
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        icon.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()

        var bins = [(red: Double, green: Double, blue: Double, weight: Double, count: Int)](
            repeating: (0, 0, 0, 0, 0), count: hueBins)
        var opaque = 0
        for offset in stride(from: 0, to: side * side * 4, by: 4) {
            let alpha = Double(pixels[offset + 3]) / 255
            guard alpha > 0.5 else { continue }
            opaque += 1
            // The bitmap stores premultiplied colour.
            let red = Double(pixels[offset]) / 255 / alpha
            let green = Double(pixels[offset + 1]) / 255 / alpha
            let blue = Double(pixels[offset + 2]) / 255 / alpha
            let high = max(red, green, blue), low = min(red, green, blue), spread = high - low
            guard high > 0.2, spread / high > 0.3 else { continue }
            var hue = high == red ? (green - blue) / spread : high == green ? 2 + (blue - red) / spread : 4 + (red - green) / spread
            if hue < 0 { hue += 6 }
            // Offset by half a bin so pure red, at hue 0, is not split between the first and last bins.
            let bin = Int(hue / 6 * Double(hueBins) + 0.5) % hueBins
            // Vivid pixels count for more, so a pale background does not outvote the logo.
            let weight = spread
            bins[bin].red += red * weight
            bins[bin].green += green * weight
            bins[bin].blue += blue * weight
            bins[bin].weight += weight
            bins[bin].count += 1
        }
        guard let winner = bins.max(by: { $0.weight < $1.weight }), winner.count * 20 >= opaque, winner.weight > 0 else { return nil }
        let color = NSColor(deviceRed: winner.red / winner.weight, green: winner.green / winner.weight,
                            blue: winner.blue / winner.weight, alpha: 1)
        return NSColor(deviceHue: color.hueComponent, saturation: max(color.saturationComponent, 0.45),
                       brightness: min(max(color.brightnessComponent, 0.45), 0.8), alpha: 1)
    }
}
