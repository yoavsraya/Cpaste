import AppKit
import Carbon.HIToolbox
import CpasteCore
import SwiftUI

private final class ShelfPanel: NSPanel {
    // A borderless panel refuses key status by default, and the shelf needs the keyboard.
    override var canBecomeKey: Bool { true }
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private static let height: CGFloat = 300
    private static let margin: CGFloat = 8

    private let store: ClipStore
    private let settings: AppSettings
    private let model = ShelfModel()
    private let panel: NSPanel
    private let onPasted: (Clip) -> Void
    private var keyMonitor: Any?

    /// `onPasted` runs after a clip was written to the clipboard and before Command-V is sent.
    init(store: ClipStore, settings: AppSettings, onPasted: @escaping (Clip) -> Void) {
        self.store = store
        self.settings = settings
        self.onPasted = onPasted
        // Non-activating, so the app the user came from stays frontmost and receives the paste.
        panel = ShelfPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        super.init()
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.delegate = self
        let actions = ShelfActions(
            paste: { [weak self] in self?.paste($0) },
            requestDirectPaste: { [weak self] in
                self?.close()
                Paster.requestDirectPaste()
            },
            reload: { [weak self] in self?.reload() },
            assign: { [weak self] clips, categoryID in self?.assign(clips, to: categoryID) },
            delete: { [weak self] in self?.delete($0) },
            beginNaming: { [weak self] in self?.beginNaming($0) },
            deleteCategory: { [weak self] category in
                self?.change("delete the category") { try $0.deleteCategory(id: category.id) }
            },
            recolor: { [weak self] category, colorHex in
                self?.change("recolour the category") { try $0.recolorCategory(id: category.id, to: colorHex) }
            },
            beginEditing: { [weak self] in self?.beginEditing($0) },
            commitEdit: { [weak self] in self?.commitEdit() },
            cancelEdit: { [weak self] in self?.endEditing() },
            setPinned: { [weak self] clips, isPinned in self?.setPinned(clips, to: isPinned) }
        )
        panel.contentView = NSHostingView(rootView: ShelfView(model: model, imageFiles: store.imageFiles, actions: actions))
    }

    func toggle() {
        panel.isVisible ? close() : show()
    }

    private func show() {
        model.query = ""
        model.filter = .all
        model.naming = nil
        model.editing = nil
        model.canPasteDirectly = !pastesIntoActiveApp || Paster.canPasteDirectly
        panel.sharingType = settings.showsDuringScreenSharing ? .readOnly : .none
        reload()

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            panel.setFrame(NSRect(x: visible.minX + Self.margin, y: visible.minY + Self.margin,
                                  width: visible.width - 2 * Self.margin, height: Self.height), display: true)
        }
        panel.makeKeyAndOrderFront(nil)
        model.focusToken += 1
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return handled ? nil : event
        }
    }

    private func close() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    private func reload() {
        do {
            model.categories = try store.categories()
            if case .category(let id) = model.filter, !model.categories.contains(where: { $0.id == id }) {
                model.filter = .all
            }
            model.clips = try store.search(model.query, in: model.filter, limit: 200)
            model.errorMessage = nil
        } catch {
            log.error("cannot load clips: \(String(describing: error), privacy: .public)")
            model.clips = []
            model.errorMessage = "Cpaste could not read its history. \(error.localizedDescription)"
        }
        model.select(at: 0)
    }

    /// Runs a change to the store and redraws. A failure is shown in the shelf.
    private func change(_ what: String, _ body: (ClipStore) throws -> Void) {
        do {
            try body(store)
            reload()
        } catch {
            log.error("cannot \(what, privacy: .public): \(String(describing: error), privacy: .public)")
            model.errorMessage = "Cpaste could not \(what). \(error.localizedDescription)"
        }
    }

    // MARK: Keyboard

    private func handle(_ event: NSEvent) -> Bool {
        let key = Int(event.keyCode)
        let command = event.modifierFlags.contains(.command)
        if model.editing != nil {
            switch key {
            case kVK_Return where command: commitEdit()
            case kVK_Escape: endEditing()
            default: return false
            }
            return true
        }
        if model.naming != nil {
            switch key {
            case kVK_Return, kVK_ANSI_KeypadEnter: commitName()
            case kVK_Escape: endNaming()
            default: return false
            }
            return true
        }
        if settings.nextCategoryShortcut.matches(event) {
            cycleFilter(by: 1)
            return true
        }
        if settings.previousCategoryShortcut.matches(event) {
            cycleFilter(by: -1)
            return true
        }
        switch key {
        case kVK_LeftArrow: move(by: -1)
        case kVK_RightArrow: move(by: 1)
        case kVK_Return, kVK_ANSI_KeypadEnter: selectedClip.map(paste)
        case kVK_Tab: cycleFilter(by: event.modifierFlags.contains(.shift) ? -1 : 1)
        case kVK_Escape:
            if model.query.isEmpty { close() } else { model.query = "" }
        case kVK_ANSI_S where command: showSaveMenu(for: model.selectedClips)
        case kVK_Delete where command: delete(model.selectedClips)
        case kVK_ANSI_E where command: selectedClip.map(beginEditing)
        case kVK_ANSI_P where command:
            let clips = model.selectedClips
            setPinned(clips, to: !clips.allSatisfy(\.isPinned))
        default:
            guard settings.quickPasteModifier.isHeld(alone: event.modifierFlags),
                  let digit = event.characters(byApplyingModifiers: []).flatMap(Int.init),
                  (1...9).contains(digit), model.clips.indices.contains(digit - 1)
            else { return false }
            paste(model.clips[digit - 1])
        }
        return true
    }

    private var pastesIntoActiveApp: Bool { settings.pasteTarget == .activeApp }

    private var selectedClip: Clip? {
        model.clips.indices.contains(model.selection) ? model.clips[model.selection] : nil
    }

    private func move(by delta: Int) {
        if let moved = movedSelection(from: model.selection, by: delta, count: model.clips.count) {
            model.select(at: moved)
        }
    }

    private func cycleFilter(by delta: Int) {
        let filters = [ClipFilter.all] + model.categories.map { .category($0.id) }
        let current = filters.firstIndex(of: model.filter) ?? 0
        model.filter = filters[(current + delta + filters.count) % filters.count]
        reload()
    }

    // MARK: Clips

    private func paste(_ clip: Clip) {
        do {
            try Paster.write(clip, imageFiles: store.imageFiles)
        } catch {
            log.error("cannot put clip on the clipboard: \(String(describing: error), privacy: .public)")
            model.errorMessage = "That clip could not be copied. \(error.localizedDescription)"
            return
        }
        onPasted(clip)
        close()
        guard pastesIntoActiveApp, Paster.canPasteDirectly else { return }
        Task { @MainActor in
            // The previous app needs a moment to become key again before it can take the keystroke.
            try? await Task.sleep(for: .milliseconds(80))
            Paster.sendCommandV()
        }
    }

    private func assign(_ clips: [Clip], to categoryID: Int64?) {
        change("save the clips") { try $0.setCategory(clipIDs: clips.map(\.id), to: categoryID) }
    }

    private func delete(_ clips: [Clip]) {
        let selection = model.selection
        change("delete the clips") { try $0.delete(clipIDs: clips.map(\.id)) }
        model.selection = movedSelection(from: selection, by: 0, count: model.clips.count) ?? 0
    }

    private func setPinned(_ clips: [Clip], to isPinned: Bool) {
        guard !clips.isEmpty else { return }
        change(isPinned ? "pin the clips" : "unpin the clips") { try $0.setPinned(clipIDs: clips.map(\.id), to: isPinned) }
    }

    private func beginEditing(_ clip: Clip) {
        guard let text = clip.editableText else { return }
        model.naming = nil
        model.editDraft = text
        model.editError = nil
        model.editing = clip
        model.focusToken += 1
    }

    private func endEditing() {
        model.editing = nil
        model.focusToken += 1
    }

    private func commitEdit() {
        guard let clip = model.editing else { return }
        guard !model.editDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            model.editError = "A clip cannot be empty. Delete it instead."
            return
        }
        guard model.editDraft != clip.editableText else { return endEditing() }
        do {
            try store.updateText(clipID: clip.id, to: model.editDraft)
        } catch {
            log.error("cannot edit the clip: \(String(describing: error), privacy: .public)")
            model.editError = error.localizedDescription
            return
        }
        let selection = model.selection
        endEditing()
        reload()
        model.select(at: movedSelection(from: selection, by: 0, count: model.clips.count) ?? 0)
    }

    // MARK: Categories

    private func showSaveMenu(for clips: [Clip]) {
        guard !clips.isEmpty else { return }
        let menu = NSMenu()
        func add(_ title: String, _ target: SavePick.Target) -> NSMenuItem {
            let item = menu.addItem(withTitle: title, action: #selector(saveMenuPicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = SavePick(clips: clips, target: target)
            return item
        }
        for category in model.categories {
            add(category.name, .category(category.id)).state = clips.allSatisfy { $0.categoryID == category.id } ? .on : .off
        }
        if !model.categories.isEmpty { menu.addItem(.separator()) }
        _ = add("New category…", .newCategory)
        if clips.contains(where: { $0.categoryID != nil }) {
            _ = add("Remove from category", .none)
        }
        let origin = NSPoint(x: 16 + CGFloat(model.selection) * 40, y: Self.height - 60)
        menu.popUp(positioning: nil, at: origin, in: panel.contentView)
    }

    private final class SavePick {
        enum Target { case category(Int64), newCategory, none }
        let clips: [Clip]
        let target: Target
        init(clips: [Clip], target: Target) {
            self.clips = clips
            self.target = target
        }
    }

    @objc private func saveMenuPicked(_ item: NSMenuItem) {
        guard let pick = item.representedObject as? SavePick else { return }
        switch pick.target {
        case .category(let id): assign(pick.clips, to: id)
        case .none: assign(pick.clips, to: nil)
        case .newCategory: beginNaming(.new(assignTo: pick.clips))
        }
    }

    private func beginNaming(_ naming: ShelfModel.Naming) {
        if case .rename(let category) = naming {
            model.nameDraft = category.name
        } else {
            model.nameDraft = ""
        }
        model.naming = naming
        model.focusToken += 1
    }

    private func endNaming() {
        model.naming = nil
        model.focusToken += 1
    }

    private func commitName() {
        let name = model.nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let naming = model.naming else { return endNaming() }
        let color = CategoryPalette.colors[model.categories.count % CategoryPalette.colors.count].hex
        change("save the category") { store in
            switch naming {
            case .new(let clips):
                let category = try store.createCategory(name: name, colorHex: color)
                try store.setCategory(clipIDs: clips.map(\.id), to: category.id)
            case .rename(let category):
                try store.renameCategory(id: category.id, to: name)
            }
        }
        endNaming()
    }
}
