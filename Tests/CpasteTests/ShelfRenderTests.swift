import AppKit
import ImageIO
import UniformTypeIdentifiers
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
        NSColor.white.setFill(); NSRect(x: 80, y: 80, width: 900, height: 300).fill()
        ("Invoice 48213907 total" as NSString).draw(at: NSPoint(x: 110, y: 190), withAttributes: [
            .font: NSFont.systemFont(ofSize: 64), .foregroundColor: NSColor.black,
        ])
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
        (.text("Kamala is quieter than Patong and closer to the airport. The estate has four villas, each with a private pool, and a shared kitchen on the ground floor that stays open late. Check-in is after three. The road down to the beach is steep, so ask for the shuttle. Breakfast is served until eleven and the cook makes a very good khao tom."), "com.apple.Notes", -280),
        (.text("#4C8DF6"), "com.apple.Safari", -250),
        (.text("+972 54-123-4567"), "net.whatsapp.WhatsApp", -240),
        (.text("yoav@example.com"), "com.apple.mail", -235),
        (.text("14 November 2026"), "com.apple.Notes", -230),
        (.text("1 Infinite Loop, Cupertino, CA 95014"), "com.apple.Maps", -225),
        (.text(#"{"name":"Cpaste","tags":["mac","clipboard"],"free":true}"#), "com.apple.Terminal", -220),
        (.text("git log --oneline -5\nswift test\n./scripts/build-app.sh"), "com.apple.Terminal", -200),
        (.file(path: "/Applications/Safari.app"), "com.apple.finder", -150),
        (.link(URL(string: "https://github.com/yoavsraya/Cpaste/releases")!), "com.apple.Safari", -100),
    ]
    for (capture, source, offset) in samples {
        let isBooking = capture == .link(URL(string: "https://www.booking.com/city/th/phuket.html")!)
        try store.insert(capture, sourceBundleID: source, linkTitle: isBooking ? "Hotels in Phuket, Thailand" : nil,
                         at: now.addingTimeInterval(offset))
    }

    let links = try store.createCategory(name: "Useful Links", colorHex: "#F0605D")
    try store.createCategory(name: "מספרים חשובים", colorHex: "#4C8DF6")
    try store.createCategory(name: "Work", colorHex: "#4CC764")
    try store.setCategory(clipIDs: [try #require(try store.search("booking", in: .all, limit: 1).first).id], to: links.id)

    let model = ShelfModel()
    model.categories = try store.categories()
    TextRecognizer.readPendingImages(in: store)
    try store.setPinned(clipIDs: [try #require(try store.search("Nai", in: .all, limit: 1).first).id], to: true)
    try store.rename(clipID: try #require(try store.search("kamala", in: .all, limit: 1).first).id, to: "Hotel shortlist")
    model.clips = try store.search("", in: .all, limit: 200)
    model.sourceApps = try store.sourceBundleIDs()
    model.selection = 1
    let host = NSHostingView(rootView: ShelfView(model: model, imageFiles: store.imageFiles, actions: ShelfActions()))
    host.frame = NSRect(x: 0, y: 0, width: 1900, height: 300)
    let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView = host

    func snapshot(_ name: String, appearance: NSAppearance.Name) throws {
        window.appearance = NSAppearance(named: appearance)
        window.backgroundColor = appearance == .darkAqua ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.86, alpha: 1)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../build/\(name).png").standardizedFileURL
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: output)
    }

    try snapshot("shelf-preview", appearance: .darkAqua)
    try snapshot("shelf-light-preview", appearance: .aqua)

    model.cardSize = .small
    host.frame.size.height = CardSize.small.shelfHeight
    try snapshot("shelf-small-preview", appearance: .darkAqua)
    model.cardSize = .medium
    host.frame.size.height = CardSize.medium.shelfHeight

    model.position = .right
    host.frame.size = CGSize(width: CardSize.medium.drawerWidth, height: 900)
    try snapshot("shelf-drawer-preview", appearance: .darkAqua)
    model.position = .bottom
    host.frame.size = CGSize(width: 1900, height: CardSize.medium.shelfHeight)

    // The README demo: a few real shelf states in a row, written as an animated GIF.
    host.frame.size = CGSize(width: 1440, height: CardSize.medium.shelfHeight)
    var frames: [CGImage] = []
    func frame() throws {
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let context = try #require(CGContext(data: nil, width: 1440, height: Int(CardSize.medium.shelfHeight), bitsPerComponent: 8,
                                             bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor(white: 0.16, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 1440, height: CardSize.medium.shelfHeight))
        context.interpolationQuality = .high
        context.draw(try #require(bitmap.cgImage), in: CGRect(x: 0, y: 0, width: 1440, height: CardSize.medium.shelfHeight))
        frames.append(try #require(context.makeImage()))
    }
    let everything = model.clips
    for index in [0, 1, 2, 3] {
        model.select(at: index)
        try frame()
    }
    model.query = "kamala"
    model.clips = try store.search("kamala", in: .all, limit: 200)
    model.select(at: 0)
    try frame()
    model.query = ""
    model.filter = .category(links.id)
    model.clips = try store.search("", in: .category(links.id), limit: 200)
    try frame()
    model.filter = .all
    model.clips = everything
    model.select(at: 1)
    model.toggleMark(at: 3)
    model.toggleMark(at: 4)
    try frame()
    model.select(at: 0)
    model.editor = .composing
    model.editDraft = "Wi-Fi password is on the fridge"
    model.focusToken += 1
    try frame()
    model.editor = nil

    let gifURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../../docs/demo.gif").standardizedFileURL
    let gif = try #require(CGImageDestinationCreateWithURL(gifURL as CFURL, UTType.gif.identifier as CFString, frames.count, nil))
    CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    for image in frames {
        CGImageDestinationAddImage(gif, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.4]] as CFDictionary)
    }
    #expect(CGImageDestinationFinalize(gif))
    host.frame.size = CGSize(width: 1900, height: CardSize.medium.shelfHeight)

    model.editor = .editing(model.clips[0])
    model.editDraft = "Nai Harn beach, Phuket"
    model.focusToken += 1
    try snapshot("shelf-edit-preview", appearance: .darkAqua)
    #expect(model.clips.count == samples.count)
}
