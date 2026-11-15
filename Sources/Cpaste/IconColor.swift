import AppKit

enum IconColor {
    private static let side = 64
    private static let paletteSize = 8

    private struct Sample {
        var red: Double
        var green: Double
        var blue: Double
        var count: Int

        var components: [Double] { [red, green, blue] }
        var color: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }
    }

    /// A representative palette colour, toned for white labels. Neutral icons use the clip-type fallback.
    static func dominant(of icon: NSImage) -> NSColor? {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: side * 4, bitsPerPixel: 32),
            let context = NSGraphicsContext(bitmapImageRep: bitmap), let pixels = bitmap.bitmapData
        else { return nil }
        // Make unused transparent pixels deterministic, including on reused allocator memory.
        pixels.initialize(repeating: 0, count: bitmap.bytesPerRow * side)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        icon.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        guard let rgb = bitmap.converting(to: .sRGB, renderingIntent: .default) else { return nil }

        var histogram: [Int: Sample] = [:]
        var opaque = 0
        for y in 0..<side {
            for x in 0..<side {
                guard let color = rgb.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), color.alphaComponent > 0.5 else { continue }
                opaque += 1
                let red = Double(color.redComponent), green = Double(color.greenComponent), blue = Double(color.blueComponent)
                let high = max(red, green, blue), low = min(red, green, blue)
                guard high > 0.2, (high - low) / high > 0.2 else { continue }
                // Four bits per channel keep near-identical antialiased pixels together.
                let key = (min(15, Int(red * 16)) << 8) | (min(15, Int(green * 16)) << 4) | min(15, Int(blue * 16))
                var sample = histogram[key] ?? Sample(red: 0, green: 0, blue: 0, count: 0)
                sample.red += red; sample.green += green; sample.blue += blue; sample.count += 1
                histogram[key] = sample
            }
        }
        let samples = histogram.keys.sorted().map { key in
            let sum = histogram[key]!
            return Sample(red: sum.red / Double(sum.count), green: sum.green / Double(sum.count),
                          blue: sum.blue / Double(sum.count), count: sum.count)
        }
        guard samples.reduce(0, { $0 + $1.count }) * 20 >= opaque, !samples.isEmpty else { return nil }
        let candidates = palette(samples).filter { $0.count * 100 >= opaque }
        guard let largest = candidates.map(\.count).max() else { return nil }
        func score(_ sample: Sample) -> Double {
            let high = max(sample.red, sample.green, sample.blue), low = min(sample.red, sample.green, sample.blue)
            let saturation = (high - low) / high
            let lightness = (high + low) / 2
            // Population leads; moderate saturation and mid-lightness break close contests.
            return 0.6 * Double(sample.count) / Double(largest)
                + 0.25 * (1 - abs(saturation - 0.65))
                + 0.15 * (1 - abs(lightness - 0.45))
        }
        guard let winner = candidates.max(by: { score($0) < score($1) }) else { return nil }
        return readableBackground(winner.color)
    }

    /// Weighted median cut: divide the most varied populated box, then average each resulting swatch.
    private static func palette(_ samples: [Sample]) -> [Sample] {
        func range(_ box: [Sample], axis: Int) -> Double {
            let values = box.map { $0.components[axis] }
            return (values.max() ?? 0) - (values.min() ?? 0)
        }
        func axis(_ box: [Sample]) -> Int {
            (0..<3).max(by: { range(box, axis: $0) < range(box, axis: $1) }) ?? 0
        }
        var boxes = [samples]
        while boxes.count < paletteSize {
            let splittable = boxes.indices.filter { boxes[$0].count > 1 }
            guard let index = splittable.max(by: {
                range(boxes[$0], axis: axis(boxes[$0])) * Double(boxes[$0].reduce(0) { $0 + $1.count })
                    < range(boxes[$1], axis: axis(boxes[$1])) * Double(boxes[$1].reduce(0) { $0 + $1.count })
            }) else { break }
            let component = axis(boxes[index])
            let sorted = boxes.remove(at: index).sorted {
                if $0.components[component] != $1.components[component] {
                    return $0.components[component] < $1.components[component]
                }
                return $0.components.lexicographicallyPrecedes($1.components)
            }
            let half = sorted.reduce(0) { $0 + $1.count } / 2
            var cumulative = 0
            var split = 1
            for i in 0..<(sorted.count - 1) {
                cumulative += sorted[i].count
                split = i + 1
                if cumulative >= half { break }
            }
            boxes.append(Array(sorted[..<split]))
            boxes.append(Array(sorted[split...]))
        }
        return boxes.map { box in
            let count = box.reduce(0) { $0 + $1.count }
            return Sample(red: box.reduce(0) { $0 + $1.red * Double($1.count) } / Double(count),
                          green: box.reduce(0) { $0 + $1.green * Double($1.count) } / Double(count),
                          blue: box.reduce(0) { $0 + $1.blue * Double($1.count) } / Double(count), count: count)
        }
    }

    /// Keep the hue while darkening just enough for the 85%-white timestamp to reach 4.5:1.
    static func readableBackground(_ color: NSColor) -> NSColor {
        guard let rgb = color.usingColorSpace(.sRGB) else { return color }
        func scaled(_ value: Double) -> NSColor {
            NSColor(srgbRed: rgb.redComponent * value, green: rgb.greenComponent * value,
                    blue: rgb.blueComponent * value, alpha: 1)
        }
        let timestamp = NSColor.white.withAlphaComponent(0.85)
        if contrast(timestamp, on: rgb) >= 4.5 { return rgb }
        var low = 0.0, high = 1.0
        for _ in 0..<20 {
            let middle = (low + high) / 2
            if contrast(timestamp, on: scaled(middle)) >= 4.5 { low = middle } else { high = middle }
        }
        return scaled(low)
    }

    /// Categories keep their exact colour; choose readable text instead of altering the background.
    static func textColor(on background: NSColor, secondary: Bool = false) -> NSColor {
        let base: NSColor = contrast(.white, on: background) >= 4.5 ? .white : .black
        let muted = base.withAlphaComponent(0.85)
        return secondary && contrast(muted, on: background) >= 4.5 ? muted : base
    }

    /// WCAG relative luminance after compositing translucent text onto an opaque sRGB background.
    static func contrast(_ foreground: NSColor, on background: NSColor) -> Double {
        guard let fg = foreground.usingColorSpace(.sRGB), let bg = background.usingColorSpace(.sRGB) else { return 1 }
        func luminance(_ r: Double, _ g: Double, _ b: Double) -> Double {
            func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        }
        let alpha = fg.alphaComponent
        let text = luminance(fg.redComponent * alpha + bg.redComponent * (1 - alpha),
                             fg.greenComponent * alpha + bg.greenComponent * (1 - alpha),
                             fg.blueComponent * alpha + bg.blueComponent * (1 - alpha))
        let surface = luminance(bg.redComponent, bg.greenComponent, bg.blueComponent)
        return (max(text, surface) + 0.05) / (min(text, surface) + 0.05)
    }
}
