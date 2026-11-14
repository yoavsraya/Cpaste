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
    private let model = ShelfModel()
    private let panel: NSPanel
    private let onPasted: (Clip) -> Void
    private var keyMonitor: Any?

    /// `onPasted` runs after a clip was written to the clipboard and before Command-V is sent.
    init(store: ClipStore, onPasted: @escaping (Clip) -> Void) {
        self.store = store
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
            assign: { [weak self] clip, categoryID in self?.assign(clip, to: categoryID) },
            delete: { [weak self] in self?.delete($0) },
            beginNaming: { [weak self] in self?.beginNaming($0) },
            deleteCategory: { [weak self] category in
                self?.change("delete the category") { try $0.deleteCategory(id: category.id) }
            },
            recolor: { [weak self] category, colorHex in
                self?.change("recolour the category") { try $0.recolorCategory(id: category.id, to: colorHex) }
            }
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
        model.canPasteDirectly = Paster.canPasteDirectly
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
        model.selection = 0
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
        if model.naming != nil {
            switch key {
            case kVK_Return, kVK_ANSI_KeypadEnter: commitName()
            case kVK_Escape: endNaming()
            default: return false
            }
            return true
        }
        switch key {
        case kVK_LeftArrow: move(by: -1)
        case kVK_RightArrow: move(by: 1)
        case kVK_Return, kVK_ANSI_KeypadEnter: selectedClip.map(paste)
        case kVK_Tab: cycleFilter(by: event.modifierFlags.contains(.shift) ? -1 : 1)
        case kVK_Escape:
            if model.query.isEmpty { close() } else { model.query = "" }
        case kVK_ANSI_S where command: selectedClip.map(showSaveMenu)
        case kVK_Delete where command: selectedClip.map(delete)
        default:
            guard command, let digit = event.characters(byApplyingModifiers: []).flatMap(Int.init),
                  (1...9).contains(digit), model.clips.indices.contains(digit - 1)
            else { return false }
            paste(model.clips[digit - 1])
        }
        return true
    }

    private var selectedClip: Clip? {
        model.clips.indices.contains(model.selection) ? model.clips[model.selection] : nil
    }

    private func move(by delta: Int) {
        if let moved = movedSelection(from: model.selection, by: delta, count: model.clips.count) {
            model.selection = moved
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
        guard Paster.canPasteDirectly else { return }
        Task { @MainActor in
            // The previous app needs a moment to become key again before it can take the keystroke.
            try? await Task.sleep(for: .milliseconds(80))
            Paster.sendCommandV()
        }
    }

    private func assign(_ clip: Clip, to categoryID: Int64?) {
        change("save the clip") { try $0.setCategory(clipID: clip.id, to: categoryID) }
    }

    private func delete(_ clip: Clip) {
        let selection = model.selection
        change("delete the clip") { try $0.delete(clipID: clip.id) }
        model.selection = movedSelection(from: selection, by: 0, count: model.clips.count) ?? 0
    }

    // MARK: Categories

    private func showSaveMenu(for clip: Clip) {
        let menu = NSMenu()
        for category in model.categories {
            let item = menu.addItem(withTitle: category.name, action: #selector(saveMenuPicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = SavePick(clip: clip, target: .category(category.id))
            item.state = clip.categoryID == category.id ? .on : .off
        }
        if !model.categories.isEmpty { menu.addItem(.separator()) }
        let new = menu.addItem(withTitle: "New category…", action: #selector(saveMenuPicked(_:)), keyEquivalent: "")
        new.target = self
        new.representedObject = SavePick(clip: clip, target: .newCategory)
        if clip.categoryID != nil {
            let remove = menu.addItem(withTitle: "Remove from category", action: #selector(saveMenuPicked(_:)), keyEquivalent: "")
            remove.target = self
            remove.representedObject = SavePick(clip: clip, target: .none)
        }
        let origin = NSPoint(x: 16 + CGFloat(model.selection) * 40, y: Self.height - 60)
        menu.popUp(positioning: nil, at: origin, in: panel.contentView)
    }

    private final class SavePick {
        enum Target { case category(Int64), newCategory, none }
        let clip: Clip
        let target: Target
        init(clip: Clip, target: Target) {
            self.clip = clip
            self.target = target
        }
    }

    @objc private func saveMenuPicked(_ item: NSMenuItem) {
        guard let pick = item.representedObject as? SavePick else { return }
        switch pick.target {
        case .category(let id): assign(pick.clip, to: id)
        case .none: assign(pick.clip, to: nil)
        case .newCategory: beginNaming(.new(assignTo: pick.clip))
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
            case .new(let clip):
                let category = try store.createCategory(name: name, colorHex: color)
                if let clip { try store.setCategory(clipID: clip.id, to: category.id) }
            case .rename(let category):
                try store.renameCategory(id: category.id, to: name)
            }
        }
        endNaming()
    }
}
