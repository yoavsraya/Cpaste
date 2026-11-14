import Foundation
import Testing
@testable import CpasteCore

@Test func plainTextIsText() {
    #expect(classify([PasteboardType.text: Data("kamala beach estate".utf8)]) == .text("kamala beach estate"))
}

@Test func webAddressIsLink() {
    let address = "https://www.booking.com/city/th/phuket.html"
    #expect(classify([PasteboardType.text: Data(address.utf8)]) == .link(URL(string: address)!))
}

@Test func sentenceContainingAddressIsText() {
    let sentence = "see https://www.booking.com for prices"
    #expect(classify([PasteboardType.text: Data(sentence.utf8)]) == .text(sentence))
}

@Test(arguments: [PasteboardType.concealed, PasteboardType.transient])
func passwordManagerItemsAreSkipped(marker: String) {
    #expect(classify([PasteboardType.text: Data("hunter2".utf8), marker: Data()]) == nil)
}

@Test func emptyTextWithImageIsImage() {
    let png = pngData(width: 4, height: 4)
    #expect(classify([PasteboardType.text: Data(), PasteboardType.png: png]) == .image(png))
}

@Test func textWithRenderedImageIsText() {
    let items = [PasteboardType.text: Data("Q3 total".utf8), PasteboardType.png: pngData(width: 4, height: 4)]
    #expect(classify(items) == .text("Q3 total"))
}

@Test func copiedFileIsFile() {
    let items = [
        PasteboardType.fileURL: Data("file:///Users/yoav/Desktop/plan.pdf".utf8),
        PasteboardType.text: Data("plan.pdf".utf8),
    ]
    #expect(classify(items) == .file(path: "/Users/yoav/Desktop/plan.pdf"))
}

@Test func emptyClipboardIsNothing() {
    #expect(classify([:]) == nil)
}
