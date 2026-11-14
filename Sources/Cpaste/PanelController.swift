import AppKit
import QuartzCore
import Carbon.HIToolbox
import CpasteCore
import SwiftUI

private final class ShelfPanel: NSPanel {
    // A borderless panel refuses key status by default, and the shelf needs the keyboard.
    override var canBecomeKey: Bool { true }
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private static let margin: CGFloat = 8

    private let store: ClipStore
    private let settings: AppSettings
    private let model = ShelfModel()
    private let panel: NSPanel
    private let onPasted: (Clip) -> Void
    private var keyMonitor: Any?
    /// The last delete, kept until the shelf closes or another delete replaces it, so Command-Z can undo it.
    private var lastDeleted: DeletedClips?
    /// True while the shelf slides away, when it is still on screen but already closed to the user.
    private var isClosing = false

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
            copy: { [weak self] in self?.paste($0, into: .clipboard) },
            open: { [weak self] in self?.open($0) },
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
            setIcon: { [weak self] category, icon in
                self?.change("set the category icon") { try $0.setCategoryIcon(id: category.id, to: icon) }
            },
            beginEditing: { [weak self] in self?.beginEditing($0) },
            commitEdit: { [weak self] in self?.commitEdit() },
            cancelEdit: { [weak self] in self?.endEditing() },
            compose: { [weak self] in self?.beginComposing() },
            setPinned: { [weak self] clips, isPinned in self?.setPinned(clips, to: isPinned) },
            moveCategory: { [weak self] category, targetID in
                self?.change("move the category") { try $0.moveCategory(id: category.id, toPlaceOf: targetID) }
            },
            moveClip: { [weak self] clip, target in
                self?.change("move the clip") { try $0.moveClip(id: clip.id, toPlaceOf: target.id) }
            },
            merge: { [weak self] in self?.merge($0) },
            copyImageText: { [weak self] in self?.copyImageText(of: $0) }
        )
        panel.contentView = NSHostingView(rootView: ShelfView(model: model, imageFiles: store.imageFiles, actions: actions))
    }

    /// Opens the shelf with the edit box ready for a new clip.
    func compose() {
        if !panel.isVisible || isClosing { show() }
        beginComposing()
    }

    func toggle() {
        panel.isVisible && !isClosing ? close(animated: true) : show()
    }

    private func show() {
        model.query = ""
        model.filter = .all
        model.kindFilter = nil
        model.appFilter = nil
        model.order = .shelf
        model.naming = nil
        model.editor = nil
        model.cardSize = settings.cardSize
        model.position = settings.shelfPosition
        model.canPasteDirectly = !pastesIntoActiveApp || Paster.canPasteDirectly
        panel.sharingType = settings.showsDuringScreenSharing ? .readOnly : .none
        reload()

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let frame: NSRect
        switch settings.shelfPosition {
        case .bottom:
            frame = NSRect(x: visible.minX + Self.margin, y: visible.minY + Self.margin,
                           width: visible.width - 2 * Self.margin, height: settings.cardSize.shelfHeight)
        case .right:
            let width = settings.cardSize.drawerWidth
            frame = NSRect(x: visible.maxX - width - Self.margin, y: visible.minY + Self.margin,
                           width: width, height: visible.height - 2 * Self.margin)
        }
        isClosing = false
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.alphaValue = 1
            panel.setFrame(frame, display: true)
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.alphaValue = 0
            panel.setFrame(frame.offsetBy(dx: offscreen.dx, dy: offscreen.dy), display: true)
            panel.makeKeyAndOrderFront(nil)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
                panel.animator().alphaValue = 1
            }
        }
        model.focusToken += 1
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return handled ? nil : event
        }
    }

    /// How far the shelf travels when it slides in from its screen edge.
    private var offscreen: (dx: CGFloat, dy: CGFloat) {
        settings.shelfPosition == .bottom ? (0, -60) : (60, 0)
    }

    /// `animated` slides the shelf away. A paste closes without it, because the app behind needs the keyboard back at once.
    private func close(animated: Bool = false) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        forgetLastDelete()
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            isClosing = false
            panel.orderOut(nil)
            return
        }
        isClosing = true
        let target = panel.frame.offsetBy(dx: offscreen.dx, dy: offscreen.dy)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.13
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // Reopened during the slide, so the shelf must stay.
                guard let self, self.isClosing else { return }
                self.isClosing = false
                self.panel.orderOut(nil)
            }
        })
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
            model.sourceApps = try store.sourceBundleIDs()
            model.clips = try store.search(model.query, in: model.filter, kind: model.kindFilter,
                                           sourceBundleID: model.appFilter, order: model.order, limit: 200)
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
        if model.editor != nil {
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
        case kVK_UpArrow where settings.shelfPosition == .right: move(by: -1)
        case kVK_DownArrow where settings.shelfPosition == .right: move(by: 1)
        case kVK_Return, kVK_ANSI_KeypadEnter: selectedClip.map { paste($0) }
        case kVK_Tab: cycleFilter(by: event.modifierFlags.contains(.shift) ? -1 : 1)
        case kVK_Escape:
            if model.query.isEmpty { close(animated: true) } else { model.query = "" }
        case kVK_ANSI_S where command: showSaveMenu(for: model.selectedClips)
        case kVK_Delete where command: delete(model.selectedClips)
        case kVK_ANSI_Z where command && lastDeleted != nil: undoDelete()
        case kVK_ANSI_J where command: merge(model.selectedClips)
        case kVK_ANSI_C where command && event.modifierFlags.contains(.shift): selectedClip.map(copyImageText)
        case kVK_ANSI_C where command: selectedClip.map { paste($0, into: .clipboard) }
        case kVK_ANSI_O where command: selectedClip.map(open)
        case kVK_ANSI_N where command: beginComposing()
        case kVK_ANSI_E where command: selectedClip.map(beginEditing)
        case kVK_ANSI_R where command: selectedClip.map { beginNaming(.renameClip($0)) }
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

    private func open(_ clip: Clip) {
        switch clip.content {
        case .text: return
        case .link(let url):
            // Only web addresses are opened, whatever a clip row claims to be.
            guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
            NSWorkspace.shared.open(url)
        case .file(let path): NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        case .image(let sha, _, _, _): NSWorkspace.shared.open(store.imageFiles.imageURL(sha256: sha))
        }
        close()
    }

    /// Puts the clip on the clipboard and closes. With `.activeApp` it also presses Command-V in the app the user came from.
    private func paste(_ clip: Clip, into target: PasteTarget? = nil) {
        do {
            try Paster.write(clip, imageFiles: store.imageFiles)
        } catch {
            log.error("cannot put clip on the clipboard: \(String(describing: error), privacy: .public)")
            model.errorMessage = "That clip could not be copied. \(error.localizedDescription)"
            return
        }
        onPasted(clip)
        close()
        guard (target ?? settings.pasteTarget) == .activeApp, Paster.canPasteDirectly else { return }
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
        guard !clips.isEmpty else { return }
        let selection = model.selection
        forgetLastDelete()
        change("delete the clips") { lastDeleted = try $0.delete(clipIDs: clips.map(\.id)) }
        model.selection = movedSelection(from: selection, by: 0, count: model.clips.count) ?? 0
        if let lastDeleted {
            model.undoHint = "Deleted \(lastDeleted.count == 1 ? "1 clip" : "\(lastDeleted.count) clips")    ⌘Z undo"
        }
    }

    private func undoDelete() {
        guard let deleted = lastDeleted else { return }
        lastDeleted = nil
        model.undoHint = nil
        change("bring the clips back") { try $0.restore(deleted) }
    }

    /// After this the last delete cannot be undone, and its image files are removed.
    private func forgetLastDelete() {
        model.undoHint = nil
        guard let deleted = lastDeleted else { return }
        lastDeleted = nil
        do {
            try store.discard(deleted)
        } catch {
            log.error("image files of deleted clips not removed: \(String(describing: error), privacy: .public)")
        }
    }

    private func merge(_ clips: [Clip]) {
        let texts = clips.compactMap(\.editableText)
        guard texts.count > 1 else { return }
        change("merge the clips") { try $0.insert(.text(texts.joined(separator: "\n")), sourceBundleID: nil) }
    }

    private func copyImageText(of clip: Clip) {
        guard let text = clip.imageText, !text.isEmpty else { return }
        // Written without telling the monitor to skip it, so the text is recorded as a new clip.
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        close()
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
        model.editor = .editing(clip)
        model.focusToken += 1
    }

    private func endEditing() {
        model.editor = nil
        model.focusToken += 1
    }

    /// Opens the edit box empty, to type a new clip by hand.
    private func beginComposing() {
        model.naming = nil
        model.editDraft = ""
        model.editError = nil
        model.editor = .composing
        model.focusToken += 1
    }

    private func commitEdit() {
        guard let editor = model.editor else { return }
        guard !model.editDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if editor == .composing { return endEditing() }
            model.editError = "A clip cannot be empty. Delete it instead."
            return
        }
        do {
            switch editor {
            case .composing:
                let clip = try store.add(text: model.editDraft)
                // A clip typed while a category is open belongs in that category.
                if case .category(let id) = model.filter { try store.setCategory(clipIDs: [clip.id], to: id) }
            case .editing(let clip):
                guard model.editDraft != clip.editableText else { return endEditing() }
                try store.updateText(clipID: clip.id, to: model.editDraft)
            }
        } catch {
            log.error("cannot save the clip: \(String(describing: error), privacy: .public)")
            model.editError = error.localizedDescription
            return
        }
        let selection = editor == .composing ? 0 : model.selection
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
        let origin = NSPoint(x: 16 + CGFloat(model.selection) * 40, y: panel.frame.height - 60)
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
        model.nameDraft = switch naming {
        case .new: ""
        case .rename(let category): category.name
        case .renameClip(let clip): clip.title ?? ""
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
        guard let naming = model.naming else { return }
        if case .renameClip(let clip) = naming {
            let selection = model.selection
            change("rename the clip") { try $0.rename(clipID: clip.id, to: name) }
            model.select(at: movedSelection(from: selection, by: 0, count: model.clips.count) ?? 0)
            return endNaming()
        }
        guard !name.isEmpty else { return endNaming() }
        let color = CategoryPalette.colors[model.categories.count % CategoryPalette.colors.count].hex
        change("save the category") { store in
            switch naming {
            case .new(let clips):
                let category = try store.createCategory(name: name, colorHex: color)
                try store.setCategory(clipIDs: clips.map(\.id), to: category.id)
            case .rename(let category):
                try store.renameCategory(id: category.id, to: name)
            case .renameClip:
                break
            }
        }
        endNaming()
    }
}
