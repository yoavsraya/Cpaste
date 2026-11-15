import AppKit
import CpasteCore
import SwiftUI
import Testing
@testable import Cpaste

private let screen = NSRect(x: 0, y: 0, width: 1728, height: 1050)

@Test func thePreviewSitsCentredAboveABottomShelf() {
    let shelf = NSRect(x: 8, y: 8, width: 1712, height: 300)
    let frame = PreviewPanel.frame(beside: shelf, in: screen, position: .bottom)

    #expect(frame.size == CGSize(width: 900, height: 640))
    #expect(frame.midX == screen.midX)
    #expect(frame.minY > shelf.maxY)
    #expect(frame.maxY < screen.maxY)
}

@Test func thePreviewShrinksToTheSpaceASmallScreenLeaves() {
    let small = NSRect(x: 0, y: 0, width: 1280, height: 720)
    let shelf = NSRect(x: 8, y: 8, width: 1264, height: 300)
    let frame = PreviewPanel.frame(beside: shelf, in: small, position: .bottom)

    #expect(abs(frame.height - 380) < 0.001)
    #expect(frame.minY > shelf.maxY)
    #expect(frame.maxY < small.maxY)
}

@Test func thePreviewSitsLeftOfARightDrawer() {
    let drawer = NSRect(x: 1360, y: 8, width: 360, height: 1034)
    let frame = PreviewPanel.frame(beside: drawer, in: screen, position: .right)

    #expect(frame.maxX < drawer.minX)
    #expect(frame.midY == screen.midY)
}

/// Draws the preview of a few clip types into `build/`, so its layout can be reviewed without the running app.
@MainActor
@Test(.enabled(if: rendersPreviews)) func previewRendersEachKindOfClip() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cpaste-render-\(UUID().uuidString)")
    let store = try ClipStore(directory: directory)
    let image = NSImage(size: NSSize(width: 1284, height: 742), flipped: false) { rect in
        NSColor.systemTeal.setFill(); rect.fill()
        NSColor.white.setFill(); NSRect(x: 80, y: 80, width: 900, height: 300).fill()
        return true
    }
    let long = (1...40).map { "Line \($0). The road down to the beach is steep, so ask for the shuttle." }.joined(separator: "\n")
    let samples: [(String, Capture)] = [
        ("text", .text(long)),
        ("short", .text("+972 54-123-4567")),
        ("json", .text(#"{"name":"Cpaste","tags":["mac","clipboard"],"free":true}"#)),
        ("color", .text("#4C8DF6")),
        ("link", .link(URL(string: "https://www.booking.com/city/th/phuket.html")!)),
        ("image", .image(image.tiffRepresentation!)),
        ("file", .file(path: "/Applications/Safari.app")),
    ]
    let model = ShelfModel()
    let host = NSHostingView(rootView: PreviewView(model: model, imageFiles: store.imageFiles))
    host.frame = NSRect(x: 0, y: 0, width: 900, height: 640)
    let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView = host
    window.appearance = NSAppearance(named: .darkAqua)
    window.backgroundColor = NSColor(white: 0.16, alpha: 1)

    for (name, capture) in samples {
        try store.insert(capture, sourceBundleID: "com.apple.Safari", linkTitle: name == "link" ? "Hotels in Phuket, Thailand" : nil, at: Date())
        model.clips = try store.search("", in: .all, limit: 1)
        model.selection = 0
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../build/preview-\(name).png").standardizedFileURL
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: output)
    }

    try store.insert(.text("host: example.com\nport: 80\ndebug: no\nretries: 3"), sourceBundleID: "com.apple.Terminal", linkTitle: nil, at: Date().addingTimeInterval(-60))
    try store.insert(.text("host: example.com\nport: 8080\ndebug: no\ntimeout: 30\nretries: 3"), sourceBundleID: "com.apple.Terminal", linkTitle: nil, at: Date())
    model.clips = try store.search("host", in: .all, limit: 2)
    model.marked = Set(model.clips.map(\.id))
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../../build/preview-compare.png").standardizedFileURL
    try #require(bitmap.representation(using: .png, properties: [:])).write(to: output)
}
