import Foundation
import Testing
@testable import CpasteCore

@Test func anExportImportsIntoAnEmptyStoreAsItWas() throws {
    let source = try makeStore()
    let links = try source.createCategory(name: "Useful Links", colorHex: "#F0605D")
    let numbers = try source.createCategory(name: "מספרים חשובים", colorHex: "#4C8DF6")
    let start = Date(timeIntervalSince1970: 1_000)
    let link = try source.insert(.link(URL(string: "https://www.booking.com")!), sourceBundleID: "com.google.Chrome", at: start)
    let image = try source.insert(.image(pngData()), sourceBundleID: nil, at: start.addingTimeInterval(1))
    let number = try source.insert(.text("48213907"), sourceBundleID: "com.apple.mail", at: start.addingTimeInterval(2))
    try source.insert(.text("not saved, so not exported"), sourceBundleID: nil)
    try source.setCategory(clipIDs: [link.id, image.id], to: links.id)
    try source.setCategory(clipIDs: [number.id], to: numbers.id)
    try source.rename(clipID: number.id, to: "הזמנה")
    try source.setPinned(clipIDs: [link.id], to: true)

    let target = try makeStore()
    #expect(try target.importArchive(try source.exportArchive()) == 3)

    #expect(try target.categories().map(\.name) == ["Useful Links", "מספרים חשובים"])
    #expect(try target.categories().map(\.colorHex) == ["#F0605D", "#4C8DF6"])
    let imported = try target.search("", in: .category(try target.categories()[0].id), limit: 10)
    #expect(imported.map(\.content.kind) == [.link, .image])
    #expect(imported.map(\.isPinned) == [true, false])
    #expect(imported.first?.sourceBundleID == "com.google.Chrome")
    #expect(try target.search("", in: .category(try target.categories()[1].id), limit: 10).map(\.title) == ["הזמנה"])
    #expect(try target.search("", in: .all, limit: 10).count == 3)
    #expect(fileCount(in: target.imageFiles.directory.appendingPathComponent("images")) == 1)
}

@Test func importingTwiceAddsNothingNew() throws {
    let source = try makeStore()
    let work = try source.createCategory(name: "Work", colorHex: "#4CC764")
    try source.setCategory(clipIDs: [try source.insert(.text("swift test"), sourceBundleID: nil).id], to: work.id)
    let file = try source.exportArchive()

    try source.importArchive(file)
    try source.importArchive(file)
    #expect(try source.categories().count == 1)
    #expect(try source.search("", in: .all, limit: 10).count == 1)
}

@Test func aFileThatIsNotAnExportIsRefused() throws {
    let store = try makeStore()
    #expect(throws: ClipArchiveError.self) { try store.importArchive(Data("hello".utf8)) }
    #expect(throws: ClipArchiveError.self) { try store.importArchive(Data(#"{"format":99,"categories":[]}"#.utf8)) }
}

@Test func anImportCannotPlantFilePathsOrLinksThatOpenOtherApps() throws {
    let store = try makeStore()
    let planted = #"""
    {"format":1,"categories":[{"name":"Shared","colorHex":"#4C8DF6","clips":[
      {"kind":"file","text":"/Users/you/.ssh/id_ed25519","title":"Holiday photo","isPinned":false},
      {"kind":"link","text":"file:///etc/passwd","isPinned":false},
      {"kind":"link","text":"x-apple.systempreferences:com.apple.preference.security","isPinned":false},
      {"kind":"link","text":"https://www.booking.com","isPinned":false}
    ]}]}
    """#
    #expect(try store.importArchive(Data(planted.utf8)) == 3)
    let clips = try store.search("", in: .all, limit: 10)
    #expect(clips.map(\.content.kind).sorted { $0.rawValue < $1.rawValue } == [.link, .text, .text])
    #expect(clips.contains { $0.content == .link(URL(string: "https://www.booking.com")!) })
}

@Test func copiedFilesAreNotExported() throws {
    let store = try makeStore()
    let work = try store.createCategory(name: "Work", colorHex: "#4CC764")
    let file = try store.insert(.file(path: "/Applications/Safari.app"), sourceBundleID: nil)
    let text = try store.insert(.text("swift test"), sourceBundleID: nil)
    try store.setCategory(clipIDs: [file.id, text.id], to: work.id)
    let archive = try JSONDecoder().decode(ClipArchive.self, from: try store.exportArchive())
    #expect(archive.categories.flatMap(\.clips).map(\.kind) == [.text])
}
