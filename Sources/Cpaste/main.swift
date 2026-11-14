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
    private let updater = UpdaterController()
    private var expiryTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
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
            recognitionQueue.async { TextRecognizer.readPendingImages(in: store) }
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
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
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
        let monitor = PasteboardMonitor { capture, sourceBundleID in
            if let sourceBundleID, settings.ignoredBundleIDs.contains(sourceBundleID) { return }
            // Encoding a large screenshot takes long enough to stall the menu bar, so it runs off the main thread.
            queue.async {
                do {
                    let clip = try store.insert(capture, sourceBundleID: sourceBundleID)
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

    @objc private func checkForUpdates() {
        updater.checkForUpdates()
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

    @objc private func showSettings() {
        if settingsWindow == nil {
            let actions = SettingsActions(
                setShortcutActive: { [weak self] in self?.setShortcutActive($0) ?? false },
                retentionChanged: { [weak self] in self?.expireOldClips() },
                eraseHistory: { [weak self] in self?.eraseHistory() },
                usageSummary: { [weak self] in self?.usageSummary() },
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
