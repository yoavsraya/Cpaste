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
