import Foundation
import ImageIO
import Testing
@testable import CpasteCore

@Test func recopyingTextMovesItToTheTop() throws {
    let store = try makeStore()
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    try store.insert(.text("kamala beach estate"), sourceBundleID: "com.google.Chrome", at: start)
    try store.insert(.text("Nai Harn"), sourceBundleID: "com.apple.Notes", at: start.addingTimeInterval(10))
    try store.insert(.text("kamala beach estate"), sourceBundleID: "com.google.Chrome", at: start.addingTimeInterval(20))

    let clips = try store.recent(limit: 10)
    #expect(clips.map(\.content) == [.text("kamala beach estate"), .text("Nai Harn")])
    #expect(clips[0].copiedAt == start)
    #expect(clips[0].lastUsedAt == start.addingTimeInterval(20))
    #expect(clips[0].sourceBundleID == "com.google.Chrome")
}

@Test func sameStringAsTextAndLinkAreSeparateClips() throws {
    let store = try makeStore()
    try store.insert(.text("https://example.com"), sourceBundleID: nil)
    try store.insert(.link(URL(string: "https://example.com")!), sourceBundleID: nil)
    #expect(try store.recent(limit: 10).count == 2)
}

@Test func imageIsWrittenOnceWithThumbnail() throws {
    let store = try makeStore()
    let png = pngData(width: 800, height: 600)
    let first = try store.insert(.image(png), sourceBundleID: nil)
    try store.insert(.image(png), sourceBundleID: nil)

    guard case .image(let sha, let width, let height, let bytes) = first.content else {
        Issue.record("expected an image clip, got \(first.content)")
        return
    }
    #expect((width, height) == (800, 600))
    #expect(bytes > 0)
    #expect(try store.recent(limit: 10).count == 1)
    #expect(fileCount(in: store.imageFiles.directory.appendingPathComponent("images")) == 1)
    #expect(fileCount(in: store.imageFiles.directory.appendingPathComponent("thumbs")) == 1)

    let thumbnail = try #require(CGImageSourceCreateWithURL(store.imageFiles.thumbnailURL(sha256: sha) as CFURL, nil))
    let small = try #require(CGImageSourceCreateImageAtIndex(thumbnail, 0, nil))
    #expect(max(small.width, small.height) == ImageFiles.thumbnailMaxPixels)
}

@Test func undecodableImageIsRejected() throws {
    let store = try makeStore()
    #expect(throws: ImageFilesError.self) {
        try store.insert(.image(Data("not an image".utf8)), sourceBundleID: nil)
    }
    #expect(try store.recent(limit: 10).isEmpty)
}

@Test func clipsSurviveReopeningTheStore() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cpaste-tests-\(UUID().uuidString)")
    try ClipStore(directory: directory).insert(.text("Cape Panwa Hotel"), sourceBundleID: nil)
    #expect(try ClipStore(directory: directory).recent(limit: 10).map(\.content) == [.text("Cape Panwa Hotel")])
}

@Test func pastingAClipMovesItToTheTop() throws {
    let store = try makeStore()
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let older = try store.insert(.text("Nai Harn"), sourceBundleID: nil, at: start)
    try store.insert(.text("Cape Panwa Hotel"), sourceBundleID: nil, at: start.addingTimeInterval(10))
    try store.markUsed(id: older.id, at: start.addingTimeInterval(20))
    #expect(try store.recent(limit: 10).map(\.content) == [.text("Nai Harn"), .text("Cape Panwa Hotel")])
}

@Test func expiryDeletesOldClipsAndTheirImageFiles() throws {
    let store = try makeStore()
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    try store.insert(.image(pngData()), sourceBundleID: nil, at: start)
    try store.insert(.text("old"), sourceBundleID: nil, at: start)
    try store.insert(.text("new"), sourceBundleID: nil, at: start.addingTimeInterval(100))

    #expect(try store.expire(olderThan: start.addingTimeInterval(50)) == 2)
    #expect(try store.recent(limit: 10).map(\.content) == [.text("new")])
    #expect(fileCount(in: store.imageFiles.directory.appendingPathComponent("images")) == 0)
    #expect(fileCount(in: store.imageFiles.directory.appendingPathComponent("thumbs")) == 0)
}

@Test func editingATextClipChangesWhatSearchFinds() throws {
    let store = try makeStore()
    let clip = try store.insert(.text("kamala beech estate"), sourceBundleID: nil)
    let edited = try store.updateText(clipID: clip.id, to: "kamala beach estate")
    #expect(edited.content == .text("kamala beach estate"))
    #expect(edited.id == clip.id)
    #expect(try store.search("beach", in: .all, limit: 10).map(\.id) == [clip.id])
    #expect(try store.search("beech", in: .all, limit: 10).isEmpty)
}

@Test func editingTextIntoAWebAddressMakesItALink() throws {
    let store = try makeStore()
    let clip = try store.insert(.text("booking"), sourceBundleID: nil)
    let edited = try store.updateText(clipID: clip.id, to: "https://www.booking.com")
    #expect(edited.content == .link(URL(string: "https://www.booking.com")!))
}

@Test func editingIntoTheTextOfAnotherClipIsRefused() throws {
    let store = try makeStore()
    try store.insert(.text("Nai Harn"), sourceBundleID: nil)
    let clip = try store.insert(.text("Nai Yang"), sourceBundleID: nil)
    #expect(throws: ClipStoreError.duplicateText) { try store.updateText(clipID: clip.id, to: "Nai Harn") }
    #expect(try store.search("", in: .all, limit: 10).count == 2)
}

@Test func anImageClipCannotBeEdited() throws {
    let store = try makeStore()
    let clip = try store.insert(.image(pngData()), sourceBundleID: nil)
    #expect(throws: ClipStoreError.notEditable) { try store.updateText(clipID: clip.id, to: "text") }
}
