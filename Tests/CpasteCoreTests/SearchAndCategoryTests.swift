import Foundation
import Testing
@testable import CpasteCore

private func seededStore() throws -> ClipStore {
    let store = try makeStore()
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let captures: [Capture] = [
        .text("amora beach resort phuket"),
        .text("kamala beach estate"),
        .text("מספר הזמנה 48213907"),
        .link(URL(string: "https://www.booking.com/city/th/phuket.html")!),
        .image(pngData(width: 40, height: 30)),
    ]
    for (offset, capture) in captures.enumerated() {
        try store.insert(capture, sourceBundleID: nil, at: start.addingTimeInterval(Double(offset)))
    }
    return store
}

private func texts(_ clips: [Clip]) -> [String] {
    clips.map { clip in
        switch clip.content {
        case .text(let string): string
        case .link(let url): url.absoluteString
        case .file(let path): path
        case .image: "<image>"
        }
    }
}

@Test func emptyQueryReturnsEverythingNewestFirst() throws {
    let found = try seededStore().search("  ", in: .all, limit: 10)
    #expect(texts(found).first == "<image>")
    #expect(found.count == 5)
}

@Test func searchMatchesTheStartOfAWord() throws {
    let found = try seededStore().search("phuk", in: .all, limit: 10)
    #expect(texts(found) == ["https://www.booking.com/city/th/phuket.html", "amora beach resort phuket"])
}

@Test func everyWordMustMatch() throws {
    #expect(texts(try seededStore().search("beach est", in: .all, limit: 10)) == ["kamala beach estate"])
}

@Test func searchFindsHebrew() throws {
    #expect(texts(try seededStore().search("מספר", in: .all, limit: 10)) == ["מספר הזמנה 48213907"])
}

@Test func typingImageFindsImages() throws {
    #expect(texts(try seededStore().search("ima", in: .all, limit: 10)) == ["<image>"])
}

@Test(arguments: ["\"", "-", "*", "a\"b", "AND", "(", "beach OR"])
func awkwardQueriesDoNotThrow(query: String) throws {
    _ = try seededStore().search(query, in: .all, limit: 10)
}

@Test func categoryFilterReturnsOnlyItsClips() throws {
    let store = try seededStore()
    let links = try store.createCategory(name: "Useful Links", colorHex: "#F0605D")
    let numbers = try store.createCategory(name: "מספרים חשובים", colorHex: "#4C8DF6")
    let link = try #require(try store.search("booking", in: .all, limit: 1).first)
    try store.setCategory(clipIDs: [link.id], to: links.id)

    #expect(try store.categories().map(\.name) == ["Useful Links", "מספרים חשובים"])
    #expect(texts(try store.search("", in: .category(links.id), limit: 10)) == ["https://www.booking.com/city/th/phuket.html"])
    #expect(try store.search("", in: .category(numbers.id), limit: 10).isEmpty)
    #expect(try store.search("kamala", in: .category(links.id), limit: 10).isEmpty)
}

@Test func deletingACategoryKeepsItsClips() throws {
    let store = try seededStore()
    let category = try store.createCategory(name: "Work", colorHex: "#4CC764")
    let clip = try #require(try store.search("kamala", in: .all, limit: 1).first)
    try store.setCategory(clipIDs: [clip.id], to: category.id)
    try store.deleteCategory(id: category.id)

    #expect(try store.categories().isEmpty)
    #expect(try store.search("kamala", in: .all, limit: 1).first?.categoryID == nil)
}

@Test func savedClipsDoNotExpire() throws {
    let store = try seededStore()
    let category = try store.createCategory(name: "Work", colorHex: "#4CC764")
    let clip = try #require(try store.search("kamala", in: .all, limit: 1).first)
    try store.setCategory(clipIDs: [clip.id], to: category.id)
    try store.expire(olderThan: .distantFuture)
    #expect(texts(try store.search("", in: .all, limit: 10)) == ["kamala beach estate"])
}

@Test func renamingACategory() throws {
    let store = try makeStore()
    let category = try store.createCategory(name: "links", colorHex: "#F0605D")
    try store.renameCategory(id: category.id, to: "Useful Links")
    #expect(try store.categories().map(\.name) == ["Useful Links"])
}

@Test func recolouringACategory() throws {
    let store = try makeStore()
    let category = try store.createCategory(name: "Useful Links", colorHex: "#F0605D")
    try store.recolorCategory(id: category.id, to: "#4C8DF6")
    #expect(try store.categories().map(\.colorHex) == ["#4C8DF6"])
}

@Test func deletingAnImageClipRemovesItsFiles() throws {
    let store = try seededStore()
    let image = try #require(try store.search("image", in: .all, limit: 1).first)
    try store.discard(try store.delete(clipIDs: [image.id]))
    #expect(try store.search("", in: .all, limit: 10).count == 4)
    #expect(fileCount(in: store.imageFiles.directory.appendingPathComponent("images")) == 0)
}

@Test func movingACategoryTakesThePlaceOfItsTarget() throws {
    let store = try makeStore()
    let ids = try ["Links", "Numbers", "Work", "Travel"].map { try store.createCategory(name: $0, colorHex: "#4C8DF6").id }
    try store.moveCategory(id: ids[0], toPlaceOf: ids[2])
    #expect(try store.categories().map(\.name) == ["Numbers", "Work", "Links", "Travel"])
    try store.moveCategory(id: ids[3], toPlaceOf: ids[1])
    #expect(try store.categories().map(\.name) == ["Travel", "Numbers", "Work", "Links"])
    try store.moveCategory(id: ids[1], toPlaceOf: ids[1])
    #expect(try store.categories().map(\.name) == ["Travel", "Numbers", "Work", "Links"])
}

@Test func filteringByTypeAndByApp() throws {
    let store = try makeStore()
    let start = Date(timeIntervalSince1970: 1_000)
    try store.insert(.text("kamala beach estate"), sourceBundleID: "com.google.Chrome", at: start)
    try store.insert(.link(URL(string: "https://www.booking.com/kamala")!), sourceBundleID: "com.google.Chrome", at: start.addingTimeInterval(1))
    try store.insert(.text("kamala notes"), sourceBundleID: "com.apple.Notes", at: start.addingTimeInterval(2))
    try store.insert(.image(pngData()), sourceBundleID: nil, at: start.addingTimeInterval(3))

    #expect(try store.search("", in: .all, kind: .link, limit: 10).map(\.content.kind) == [.link])
    #expect(try store.search("", in: .all, sourceBundleID: "com.google.Chrome", limit: 10).count == 2)
    #expect(try store.search("kamala", in: .all, kind: .text, sourceBundleID: "com.google.Chrome", limit: 10).count == 1)
    #expect(try store.search("", in: .all, kind: .file, limit: 10).isEmpty)
    #expect(try store.sourceBundleIDs() == ["com.apple.Notes", "com.google.Chrome"])
}

@Test func clipsOfAHiddenCategoryAreLeftOutOfEveryList() throws {
    let store = try makeStore()
    let secrets = try store.createCategory(name: "Private", colorHex: "#8E99A4")
    let work = try store.createCategory(name: "Work", colorHex: "#4CC764")
    let hidden = try store.insert(.text("door code 4821"), sourceBundleID: nil)
    let saved = try store.insert(.text("standup notes"), sourceBundleID: nil)
    let loose = try store.insert(.text("door is open"), sourceBundleID: nil)
    try store.setCategory(clipIDs: [hidden.id], to: secrets.id)
    try store.setCategory(clipIDs: [saved.id], to: work.id)
    try store.setCategoryPrivate(id: secrets.id, to: true)
    #expect(try store.categories().map(\.isPrivate) == [true, false])

    let locked: Set<Int64> = [secrets.id]
    #expect(Set(try store.search("", in: .all, hiding: locked, limit: 10).map(\.id)) == [saved.id, loose.id])
    #expect(try store.search("door", in: .all, hiding: locked, limit: 10).map(\.id) == [loose.id])
    #expect(try store.search("door", in: .all, order: .mostUsed, hiding: locked, limit: 10).map(\.id) == [loose.id])
    #expect(try store.search("door", in: .all, limit: 10).count == 2)
}
