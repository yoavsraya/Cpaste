import AppKit
import Testing
@testable import Cpaste

private func icon(_ parts: [(NSColor, NSRect)]) -> NSImage {
    NSImage(size: NSSize(width: 64, height: 64), flipped: false) { _ in
        for (color, rect) in parts {
            color.setFill()
            rect.fill()
        }
        return true
    }
}

@Test func aLogoOnAWhiteBackgroundGivesTheLogoColour() throws {
    let image = icon([(.white, NSRect(x: 0, y: 0, width: 64, height: 64)),
                      (NSColor(deviceRed: 0.1, green: 0.7, blue: 0.3, alpha: 1), NSRect(x: 16, y: 16, width: 32, height: 32))])
    let color = try #require(IconColor.dominant(of: image))
    #expect(color.greenComponent > color.redComponent + 0.2)
    #expect(color.greenComponent > color.blueComponent + 0.2)
}

@Test func theLargestOfSeveralColoursWins() throws {
    let image = icon([(NSColor(deviceRed: 0.9, green: 0.1, blue: 0.1, alpha: 1), NSRect(x: 0, y: 0, width: 64, height: 64)),
                      (NSColor(deviceRed: 0.1, green: 0.2, blue: 0.9, alpha: 1), NSRect(x: 0, y: 0, width: 20, height: 20))])
    let color = try #require(IconColor.dominant(of: image))
    #expect(color.redComponent > color.blueComponent + 0.2)
}

@Test func aGreyIconHasNoColour() {
    let image = icon([(.darkGray, NSRect(x: 0, y: 0, width: 64, height: 64)),
                      (.white, NSRect(x: 16, y: 16, width: 32, height: 32))])
    #expect(IconColor.dominant(of: image) == nil)
}

@Test func paletteScoringPrefersBalancedSaturationWhenAreasAreEqual() throws {
    let image = icon([(.red, NSRect(x: 0, y: 0, width: 32, height: 64)),
                      (NSColor(srgbRed: 0.25, green: 0.65, blue: 0.35, alpha: 1), NSRect(x: 32, y: 0, width: 32, height: 64))])
    let color = try #require(IconColor.dominant(of: image))
    #expect(color.greenComponent > color.redComponent + 0.15)
    #expect(color.greenComponent > color.blueComponent)
}

@Test func transparentPaddingDoesNotOutvoteTheLogo() throws {
    let blue = NSColor(srgbRed: 0.1, green: 0.3, blue: 0.9, alpha: 1)
    let image = icon([(.red.withAlphaComponent(0.1), NSRect(x: 0, y: 0, width: 64, height: 64)),
                      (blue, NSRect(x: 24, y: 24, width: 16, height: 16))])
    let color = try #require(IconColor.dominant(of: image))
    #expect(color.blueComponent > color.redComponent + 0.2)
}

@Test func movingPaletteColoursDoesNotChangeTheSelectedColour() throws {
    let green = NSColor(srgbRed: 0.25, green: 0.65, blue: 0.35, alpha: 1)
    let left = NSRect(x: 0, y: 0, width: 32, height: 64)
    let right = NSRect(x: 32, y: 0, width: 32, height: 64)
    let first = try #require(IconColor.dominant(of: icon([(.red, left), (green, right)])))
    let second = try #require(IconColor.dominant(of: icon([(green, left), (.red, right)])))
    #expect(abs(first.redComponent - second.redComponent) < 0.001)
    #expect(abs(first.greenComponent - second.greenComponent) < 0.001)
    #expect(abs(first.blueComponent - second.blueComponent) < 0.001)
}

@Test func contrastMatchesKnownSRGBExamples() {
    #expect(abs(IconColor.contrast(.white, on: .black) - 21) < 0.001)
    let gray = NSColor(srgbRed: 119.0 / 255, green: 119.0 / 255, blue: 119.0 / 255, alpha: 1)
    #expect(abs(IconColor.contrast(.white, on: gray) - 4.47809) < 0.001)
    #expect(IconColor.contrast(.white, on: .white) == 1)
}

// Independent foreground compositing checks catch the translucent timestamp being measured as solid white.
private func renderedContrast(_ text: NSColor, _ surface: NSColor) throws -> Double {
    let fg = try #require(text.usingColorSpace(.sRGB))
    let bg = try #require(surface.usingColorSpace(.sRGB))
    let background = [bg.redComponent, bg.greenComponent, bg.blueComponent]
    let foreground = zip([fg.redComponent, fg.greenComponent, fg.blueComponent], background)
        .map { $0 * fg.alphaComponent + $1 * (1 - fg.alphaComponent) }
    func luminance(_ channels: [Double]) -> Double {
        zip(channels, [0.2126, 0.7152, 0.0722]).reduce(0) { value, pair in
            let linear = pair.0 <= 0.04045 ? pair.0 / 12.92 : pow((pair.0 + 0.055) / 1.055, 2.4)
            return value + linear * pair.1
        }
    }
    let a = luminance(foreground.map(Double.init)), b = luminance(background.map(Double.init))
    return (max(a, b) + 0.05) / (min(a, b) + 0.05)
}

@Test(arguments: [0.0, 0.25, 0.5, 0.75, 1.0]) func extractedTonesAndCategoryLabelsStayReadable(red: Double) throws {
    for green in [0.0, 0.25, 0.5, 0.75, 1.0] {
        for blue in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let category = NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
            let toned = IconColor.readableBackground(category)
            #expect(try renderedContrast(.white.withAlphaComponent(0.85), toned) >= 4.5)
            #expect(try renderedContrast(IconColor.textColor(on: category), category) >= 4.5)
            #expect(try renderedContrast(IconColor.textColor(on: category, secondary: true), category) >= 4.5)
        }
    }
}

@Test func aReadableSourceColourKeepsItsOriginalTone() throws {
    let original = NSColor(srgbRed: 0.1, green: 0.2, blue: 0.4, alpha: 1)
    let result = try #require(IconColor.readableBackground(original).usingColorSpace(.sRGB))
    #expect(abs(result.redComponent - original.redComponent) < 0.0001)
    #expect(abs(result.greenComponent - original.greenComponent) < 0.0001)
    #expect(abs(result.blueComponent - original.blueComponent) < 0.0001)
}
