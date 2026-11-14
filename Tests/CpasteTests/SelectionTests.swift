import CpasteCore
import Foundation
import Testing
@testable import Cpaste

@MainActor
private func modelWithClips(_ count: Int) throws -> (ShelfModel, ClipStore) {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cpaste-selection-\(UUID().uuidString)")
    let store = try ClipStore(directory: directory)
    for index in 0..<count {
        try store.insert(.text("clip \(index)"), sourceBundleID: nil, at: Date().addingTimeInterval(Double(index)))
    }
    let model = ShelfModel()
    model.clips = try store.search("", in: .all, limit: 200)
    return (model, store)
}

@MainActor
@Test func commandClickAddsToTheSelectedClip() throws {
    let (model, _) = try modelWithClips(4)
    model.toggleMark(at: 2)
    model.toggleMark(at: 3)
    #expect(model.selectedClips.map(\.id) == [0, 2, 3].map { model.clips[$0].id })
    #expect((0..<4).map(model.isSelected(at:)) == [true, false, true, true])
}

@MainActor
@Test func commandClickOnASelectedClipTakesItOut() throws {
    let (model, _) = try modelWithClips(4)
    model.toggleMark(at: 2)
    model.toggleMark(at: 2)
    #expect(model.selectedClips.map(\.id) == [model.clips[0].id])
    model.toggleMark(at: 3)
    model.toggleMark(at: 3)
    model.toggleMark(at: 0)
    #expect(model.selectedClips.map(\.id) == [model.clips[0].id])
}

@MainActor
@Test func removingTheCursorClipMovesTheCursorToAClipStillSelected() throws {
    let (model, _) = try modelWithClips(4)
    model.toggleMark(at: 2)
    #expect(model.selection == 2)
    model.toggleMark(at: 2)
    #expect(model.selection == 0)
}

@MainActor
@Test func anActionOnAnUnselectedClipLeavesTheSelectionAlone() throws {
    let (model, _) = try modelWithClips(4)
    model.toggleMark(at: 2)
    #expect(model.targets(for: model.clips[2]).count == 2)
    #expect(model.targets(for: model.clips[3]).map(\.id) == [model.clips[3].id])
}

@MainActor
@Test func aPlainClickDropsTheMultiSelection() throws {
    let (model, _) = try modelWithClips(4)
    model.toggleMark(at: 2)
    model.select(at: 1)
    #expect(model.selectedClips.map(\.id) == [model.clips[1].id])
}

@MainActor
@Test func savingAndDeletingManyClipsAtOnce() throws {
    let (model, store) = try modelWithClips(4)
    let category = try store.createCategory(name: "Work", colorHex: "#4CC764")
    model.toggleMark(at: 2)
    try store.setCategory(clipIDs: model.selectedClips.map(\.id), to: category.id)
    #expect(try store.search("", in: .category(category.id), limit: 10).count == 2)
    try store.delete(clipIDs: model.selectedClips.map(\.id))
    #expect(try store.search("", in: .all, limit: 10).count == 2)
}
