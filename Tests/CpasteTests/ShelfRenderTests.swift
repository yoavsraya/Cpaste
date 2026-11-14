import AppKit
import CpasteCore
import SwiftUI
import Testing
@testable import Cpaste

/// Preview renders run only with `CPASTE_RENDER=1`, because hosting real AppKit views crashes the test runner about one run in ten.
let rendersPreviews = ProcessInfo.processInfo.environment["CPASTE_RENDER"] != nil

/// Draws the shelf off screen into `build/shelf-preview.png`, so its layout can be reviewed without the running app.
@MainActor
@Test(.enabled(if: rendersPreviews)) func shelfRendersItsClips() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cpaste-render-\(UUID().uuidString)")
    let store = try ClipStore(directory: directory)
    let image = NSImage(size: NSSize(width: 1284, height: 742), flipped: false) { rect in
        NSColor.systemTeal.setFill(); rect.fill()
        NSColor.white.setFill(); NSRect(x: 80, y: 80, width: 600, height: 300).fill()
        return true
    }
    let now = Date()
    let samples: [(Capture, String?, TimeInterval)] = [
        (.text("Nai Harn"), "com.apple.Notes", -1500),
        (.text("מספר הזמנה 48213907"), "com.apple.mail", -1400),
        (.file(path: "/Users/yoav/Desktop/plan.pdf"), "com.apple.finder", -1350),
        (.link(URL(string: "https://www.booking.com/city/th/phuket.html")!), "com.google.Chrome", -1300),
        (.image(image.tiffRepresentation!), "com.apple.screencaptureui", -1140),
        (.text("Thavorn Beach Village Resort & Spa Phuket"), "com.google.Chrome", -960),
        (.text("kamala beach estate"), "com.google.Chrome", -300),
    ]
    for (capture, source, offset) in samples {
        try store.insert(capture, sourceBundleID: source, at: now.addingTimeInterval(offset))
    }

    let links = try store.createCategory(name: "Useful Links", colorHex: "#F0605D")
    try store.createCategory(name: "מספרים חשובים", colorHex: "#4C8DF6")
    try store.createCategory(name: "Work", colorHex: "#4CC764")
    try store.setCategory(clipIDs: [try #require(try store.search("booking", in: .all, limit: 1).first).id], to: links.id)

    let model = ShelfModel()
    model.categories = try store.categories()
    model.clips = try store.search("", in: .all, limit: 200)
    model.selection = 1
    model.toggleMark(at: 3)
    model.toggleMark(at: 5)
    let view = ShelfView(model: model, imageFiles: store.imageFiles, actions: ShelfActions())
        .background(Color(white: 0.16))
    let host = NSHostingView(rootView: view)
    host.frame = NSRect(x: 0, y: 0, width: 1440, height: 300)
    let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))

    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../../build/shelf-preview.png").standardizedFileURL
    try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
    try png.write(to: output)
    #expect(model.clips.count == samples.count)
}
