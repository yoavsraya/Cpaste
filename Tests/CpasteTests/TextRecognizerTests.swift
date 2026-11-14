import AppKit
import CpasteCore
import Testing
@testable import Cpaste

private func screenshot(saying text: String) -> Data {
    let image = NSImage(size: NSSize(width: 900, height: 200), flipped: false) { rect in
        NSColor.white.setFill()
        rect.fill()
        (text as NSString).draw(at: NSPoint(x: 30, y: 70), withAttributes: [
            .font: NSFont.systemFont(ofSize: 48), .foregroundColor: NSColor.black,
        ])
        return true
    }
    return image.tiffRepresentation!
}

@Test func searchFindsAScreenshotByTheWordsInIt() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cpaste-ocr-\(UUID().uuidString)")
    let store = try ClipStore(directory: directory)
    let invoice = try store.insert(.image(screenshot(saying: "Invoice 48213907 total")), sourceBundleID: nil)
    try store.insert(.image(screenshot(saying: "Boarding pass Phuket")), sourceBundleID: nil)
    #expect(try store.search("invoice", in: .all, limit: 10).isEmpty)

    TextRecognizer.readPendingImages(in: store)

    #expect(try store.search("invoice", in: .all, limit: 10).map(\.id) == [invoice.id])
    #expect(try store.search("48213907", in: .all, limit: 10).map(\.id) == [invoice.id])
    #expect(try store.search("image", in: .all, limit: 10).count == 2)
    #expect(try store.imagesAwaitingText(limit: 10).isEmpty)
}

@Test func anImageWithoutTextIsReadOnlyOnce() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cpaste-ocr-\(UUID().uuidString)")
    let store = try ClipStore(directory: directory)
    try store.insert(.image(screenshot(saying: "")), sourceBundleID: nil)
    TextRecognizer.readPendingImages(in: store)
    #expect(try store.imagesAwaitingText(limit: 10).isEmpty)
    #expect(try store.search("", in: .all, limit: 10).count == 1)
}
