import AppKit
import CpasteCore
import os
import SwiftUI

let log = Logger(subsystem: "local.cpaste.app", category: "app")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private let storeQueue = DispatchQueue(label: "local.cpaste.store")
    private let recognitionQueue = DispatchQueue(label: "local.cpaste.recognition", qos: .utility)
    private var statusItem: NSStatusItem?
    private var openMenuItem: NSMenuItem?
    private var store: ClipStore?
    private var monitor: PasteboardMonitor?
    private var panel: PanelController?
    private var hotKey: HotKey?
    private var settingsWindow: NSWindow?
    private var welcomeWindow: NSWindow?
    private var updateMenuItem: NSMenuItem?
    private var pauseMenuItem: NSMenuItem?
    private var resumeTimer: Timer?
    private let updater = UpdaterController()
    private var expiryTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyAppearance()
        installStatusItem()
        do {
            let directory = try FileManager.default
                .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("Cpaste")
            let store = try ClipStore(directory: directory)
            self.store = store
            startMonitoring(into: store)
            startPanel(over: store)
            startExpiry()
            recognitionQueue.async {
                do {
                    let removed = try store.removeOrphanedImages()
                    if removed > 0 { log.notice("removed \(removed) image files no clip uses") }
                } catch {
                    log.error("unused image files not removed: \(String(describing: error), privacy: .public)")
                }
                TextRecognizer.readPendingImages(in: store)
            }
            if !settings.hasSeenWelcome { showWelcome() }
            updater.onAvailableVersionChange = { [weak self] version in
                self?.updateMenuItem?.title = version.map { "Update to Cpaste \($0)…" } ?? "Check for Updates…"
            }
            updater.start()
            updateMenuItem?.isHidden = !updater.isActive
            log.notice("recording clipboard into \(directory.path, privacy: .public)")
        } catch {
            log.fault("cannot open the clip store: \(String(describing: error), privacy: .public)")
            let alert = NSAlert(error: error)
            alert.messageText = "Cpaste cannot open its history"
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Self.menuBarIcon()
        let menu = NSMenu()
        openMenuItem = menu.addItem(withTitle: "Open Cpaste", action: #selector(togglePanel), keyEquivalent: "")
        menu.addItem(withTitle: "New Clip…", action: #selector(newClip), keyEquivalent: "n")
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        let pause = menu.addItem(withTitle: "Pause Recording", action: nil, keyEquivalent: "")
        pause.submenu = NSMenu()
        pauseMenuItem = pause
        rebuildPauseMenu()
        updateMenuItem = menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Cpaste", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    /// The Cpaste mark from the app bundle. A run outside the bundle, such as `swift run`, has no resources and gets a system symbol.
    private static func menuBarIcon() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "cpaste-menu-bar", withExtension: "svg"),
              let icon = NSImage(contentsOf: url)
        else {
            log.error("menu-bar icon is missing from the app bundle")
            return NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Cpaste")
        }
        icon.size = NSSize(width: 18, height: 18)
        icon.isTemplate = true
        icon.accessibilityDescription = "Cpaste"
        return icon
    }

    private func startMonitoring(into store: ClipStore) {
        let queue = storeQueue
        let recognitionQueue = recognitionQueue
        let settings = settings
        let monitor = PasteboardMonitor { capture, sourceBundleID, linkTitle in
            if let sourceBundleID, settings.ignoredBundleIDs.contains(sourceBundleID) { return }
            // Encoding a large screenshot takes long enough to stall the menu bar, so it runs off the main thread.
            queue.async {
                do {
                    let clip = try store.insert(capture, sourceBundleID: sourceBundleID, linkTitle: linkTitle)
                    if case .image = clip.content {
                        recognitionQueue.async { TextRecognizer.readPendingImages(in: store) }
                    }
                } catch {
                    log.error("capture not stored: \(String(describing: error), privacy: .public)")
                }
            }
        }
        monitor.start()
        self.monitor = monitor
    }

    private func startPanel(over store: ClipStore) {
        let queue = storeQueue
        panel = PanelController(store: store, settings: settings) { [weak self] clip in
            self?.monitor?.skipCurrentContents()
            queue.async {
                do {
                    try store.markUsed(id: clip.id)
                } catch {
                    log.error("pasted clip not moved to the top: \(String(describing: error), privacy: .public)")
                }
            }
        }
        hotKey = HotKey { [weak self] in self?.togglePanel() }
        _ = setShortcutActive(true)
    }

    private func setShortcutActive(_ active: Bool) -> Bool {
        guard active else {
            hotKey?.unregister()
            return true
        }
        let registered = hotKey?.register(settings.openShortcut) ?? false
        openMenuItem?.title = "Open Cpaste  \(settings.openShortcut.display)"
        log.notice("shortcut \(self.settings.openShortcut.display, privacy: .public) registered: \(registered)")
        return registered
    }

    private func startExpiry() {
        expireOldClips()
        expiryTimer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.expireOldClips() }
        }
    }

    private func expireOldClips() {
        guard let store, let cutoff = settings.retention.cutoff(from: Date()) else { return }
        storeQueue.async {
            do {
                let count = try store.expire(olderThan: cutoff)
                if count > 0 { log.notice("expired \(count) clips") }
            } catch {
                log.error("expiry failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func eraseHistory() {
        guard let store else { return }
        // Synchronous, so the history size shown next to the button is already the new one.
        storeQueue.sync {
            do {
                let count = try store.eraseHistory()
                log.notice("erased \(count) clips")
            } catch {
                log.error("history not erased: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func exportCategories() -> String? {
        guard let store else { return nil }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Cpaste categories.cpaste"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            try store.exportArchive().write(to: url, options: .atomic)
            return "Exported to \(url.lastPathComponent)."
        } catch {
            log.error("export failed: \(String(describing: error), privacy: .public)")
            return "The export failed. \(error.localizedDescription)"
        }
    }

    private func importCategories() -> String? {
        guard let store else { return nil }
        let panel = NSOpenPanel()
        panel.message = "Choose a file exported from Cpaste."
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            let count = try store.importArchive(try Data(contentsOf: url))
            recognitionQueue.async { TextRecognizer.readPendingImages(in: store) }
            return "Imported \(count == 1 ? "1 clip" : "\(count) clips") from \(url.lastPathComponent)."
        } catch {
            log.error("import failed: \(String(describing: error), privacy: .public)")
            return "The import failed. \(error.localizedDescription)"
        }
    }

    private func health() -> [HealthItem] {
        var items: [HealthItem] = []
        if monitor == nil || store == nil {
            items.append(HealthItem(title: "Recording", detail: "Not running. Quit and reopen Cpaste.", isHealthy: false))
        } else if monitor?.isPaused == true {
            items.append(HealthItem(title: "Recording", detail: "Paused from the menu bar", isHealthy: false))
        } else {
            items.append(HealthItem(title: "Recording", detail: "On", isHealthy: true))
        }

        if settings.pasteTarget == .clipboard {
            items.append(HealthItem(title: "Pasting", detail: "Copies only, as you chose", isHealthy: true))
        } else if Paster.canPasteDirectly {
            items.append(HealthItem(title: "Pasting", detail: "Allowed to paste for you", isHealthy: true))
        } else {
            items.append(HealthItem(title: "Pasting", detail: "Needs the Accessibility permission", isHealthy: false))
        }

        if !updater.isActive {
            items.append(HealthItem(title: "Updates", detail: "Not available in this build", isHealthy: false))
        } else if !updater.checksAutomatically {
            items.append(HealthItem(title: "Updates", detail: "Automatic checks are off", isHealthy: false))
        } else {
            let last = updater.lastCheck.map { "Last checked \($0.formatted(.relative(presentation: .named)))" } ?? "Not checked yet"
            items.append(HealthItem(title: "Updates", detail: last, isHealthy: true))
        }

        do {
            let usage = try store?.usage()
            let unread = try store?.imagesAwaitingText(limit: 1000).count ?? 0
            items.append(HealthItem(title: "History", detail: usage == nil ? "Not open" : "Readable", isHealthy: usage != nil))
            items.append(HealthItem(title: "Text in images", detail: unread == 0 ? "All images read" : "\(unread) still to read",
                                    isHealthy: unread == 0))
        } catch {
            items.append(HealthItem(title: "History", detail: "Cannot be read. \(error.localizedDescription)", isHealthy: false))
        }
        return items
    }

    private func usageSummary() -> String? {
        do {
            guard let usage = try store?.usage() else { return nil }
            let size = ByteCountFormatter.string(fromByteCount: Int64(usage.byteCount), countStyle: .file)
            return "\(usage.clipCount) \(usage.clipCount == 1 ? "clip" : "clips"), \(size) on disk"
        } catch {
            log.error("history size not read: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    // MARK: Pausing

    private func rebuildPauseMenu() {
        guard let item = pauseMenuItem, let menu = item.submenu else { return }
        let isPaused = monitor?.isPaused ?? false
        menu.removeAllItems()
        if isPaused {
            item.title = resumeTimer.map { "Recording Paused until \($0.fireDate.formatted(date: .omitted, time: .shortened))" } ?? "Recording Paused"
            menu.addItem(withTitle: "Resume Recording", action: #selector(resumeRecording), keyEquivalent: "")
        } else {
            item.title = "Pause Recording"
            for (title, minutes) in [("For 5 Minutes", 5), ("For 1 Hour", 60), ("Until I Resume", 0)] {
                menu.addItem(withTitle: title, action: #selector(pauseRecording(_:)), keyEquivalent: "").tag = minutes
            }
        }
        // A dimmed icon shows at a glance that copies are not being recorded.
        statusItem?.button?.appearsDisabled = isPaused
    }

    @objc private func pauseRecording(_ sender: NSMenuItem) {
        monitor?.isPaused = true
        resumeTimer?.invalidate()
        resumeTimer = sender.tag == 0 ? nil : Timer.scheduledTimer(withTimeInterval: Double(sender.tag) * 60, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.resumeRecording() }
        }
        log.notice("recording paused for \(sender.tag) minutes, 0 meaning until resumed")
        rebuildPauseMenu()
    }

    @objc private func resumeRecording() {
        monitor?.isPaused = false
        resumeTimer?.invalidate()
        resumeTimer = nil
        log.notice("recording resumed")
        rebuildPauseMenu()
    }

    @objc private func checkForUpdates() {
        updater.checkForUpdates()
    }

    @objc private func newClip() {
        panel?.compose()
    }

    @objc private func togglePanel() {
        panel?.toggle()
    }

    private func showWelcome() {
        settings.hasSeenWelcome = true
        let view = WelcomeView(openShortcut: settings.openShortcut.display) { [weak self] in
            self?.welcomeWindow?.close()
            self?.welcomeWindow = nil
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Welcome to Cpaste"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.center()
        welcomeWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func applyAppearance() {
        NSApp.appearance = switch settings.appearance {
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        case .system: nil
        }
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let actions = SettingsActions(
                setShortcutActive: { [weak self] in self?.setShortcutActive($0) ?? false },
                retentionChanged: { [weak self] in self?.expireOldClips() },
                appearanceChanged: { [weak self] in self?.applyAppearance() },
                eraseHistory: { [weak self] in self?.eraseHistory() },
                usageSummary: { [weak self] in self?.usageSummary() },
                exportCategories: { [weak self] in self?.exportCategories() },
                importCategories: { [weak self] in self?.importCategories() },
                health: { [weak self] in self?.health() ?? [] },
                updater: updater.isActive ? updater : nil
            )
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(settings: settings, actions: actions)))
            window.title = "Cpaste Settings"
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            // The sidebar runs under the title bar, as in System Settings.
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
