// Drives the real clipboard to check the running app, then puts back what was there.
// Usage: swift scripts/live-check.swift <marker>
import AppKit

let marker = CommandLine.arguments[1]
let pasteboard = NSPasteboard.general
let saved: [[(NSPasteboard.PasteboardType, Data)]] = (pasteboard.pasteboardItems ?? []).map { item in
    item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
}

func put(_ entries: [(NSPasteboard.PasteboardType, Data)]) {
    pasteboard.clearContents()
    let item = NSPasteboardItem()
    for (type, data) in entries { item.setData(data, forType: type) }
    pasteboard.writeObjects([item])
    Thread.sleep(forTimeInterval: 1.2)
}

let image = NSImage(size: NSSize(width: 640, height: 400), flipped: false) { rect in
    NSColor.systemTeal.setFill(); rect.fill(); return true
}
let png = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!

put([(.string, Data("\(marker) text".utf8))])
put([(.string, Data("https://example.com/\(marker)".utf8))])
put([(.png, png)])
put([(.string, Data("\(marker) secret".utf8)), (.init("org.nspasteboard.ConcealedType"), Data())])

pasteboard.clearContents()
pasteboard.writeObjects(saved.map { entries in
    let item = NSPasteboardItem()
    for (type, data) in entries { item.setData(data, forType: type) }
    return item
})
print("restored \(saved.count) item(s)")
