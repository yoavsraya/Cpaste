import AppKit
import Carbon.HIToolbox
import CpasteCore
import SwiftUI
import Testing
@testable import Cpaste

/// Keeps its values in memory, because a real suite leaves a plist in ~/Library/Preferences after every test run.
private final class MemoryDefaults: UserDefaults {
    private var values: [String: Any] = [:]

    override func object(forKey defaultName: String) -> Any? { values[defaultName] }
    override func set(_ value: Any?, forKey defaultName: String) { values[defaultName] = value }
    override func removeObject(forKey defaultName: String) { values[defaultName] = nil }
}

@MainActor
private func freshDefaults() -> UserDefaults {
    MemoryDefaults(suiteName: "cpaste-tests")!
}

private func keyDown(_ keyCode: Int, _ flags: NSEvent.ModifierFlags) -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                     characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: UInt16(keyCode))!
}

@MainActor
@Test func settingsSurviveARelaunch() {
    let defaults = freshDefaults()
    let settings = AppSettings(defaults: defaults)
    #expect(settings.pasteTarget == .activeApp)
    #expect(!settings.hasSeenWelcome)
    settings.hasSeenWelcome = true
    #expect(settings.showsDuringScreenSharing)
    #expect(settings.ignoredBundleIDs.contains("com.apple.keychainaccess"))
    settings.pasteTarget = .clipboard
    settings.cardSize = .large
    settings.shelfPosition = .right
    settings.showsDuringScreenSharing = false
    settings.quickPasteModifier = .option
    settings.nextCategoryShortcut = Shortcut(keyCode: UInt32(kVK_ANSI_K), carbonModifiers: UInt32(cmdKey), keyLabel: "K")

    let relaunched = AppSettings(defaults: defaults)
    #expect(relaunched.pasteTarget == .clipboard)
    #expect(relaunched.cardSize == .large)
    #expect(relaunched.shelfPosition == .right)
    #expect(relaunched.hasSeenWelcome)
    #expect(!relaunched.showsDuringScreenSharing)
    #expect(relaunched.quickPasteModifier == .option)
    #expect(relaunched.nextCategoryShortcut.display == "⌘K")
}

@MainActor
@Test func resettingShortcutsRestoresEveryDefault() {
    let settings = AppSettings(defaults: freshDefaults())
    settings.openShortcut = Shortcut(keyCode: UInt32(kVK_ANSI_V), carbonModifiers: UInt32(cmdKey | shiftKey), keyLabel: "V")
    settings.quickPasteModifier = .control
    settings.resetShortcuts()
    #expect(settings.openShortcut == .openDefault)
    #expect(settings.nextCategoryShortcut.display == "⌘→")
    #expect(settings.previousCategoryShortcut.display == "⌘←")
    #expect(settings.quickPasteModifier == .command)
}

@Test func aShortcutMatchesOnlyItsOwnKeyAndModifiers() {
    let next = Shortcut.nextCategoryDefault
    // Arrow keys always carry the function and numeric-pad flags, which must not break the match.
    #expect(next.matches(keyDown(kVK_RightArrow, [.command, .function, .numericPad])))
    #expect(!next.matches(keyDown(kVK_RightArrow, [.function, .numericPad])))
    #expect(!next.matches(keyDown(kVK_RightArrow, [.command, .shift])))
    #expect(!next.matches(keyDown(kVK_LeftArrow, .command)))
}

@Test func recordingAnArrowShortcutLabelsItWithAnArrow() throws {
    let shortcut = try #require(Shortcut(event: keyDown(kVK_LeftArrow, [.option, .function, .numericPad])))
    #expect(shortcut.display == "⌥←")
    #expect(Shortcut(event: keyDown(kVK_LeftArrow, [.function, .numericPad])) == nil)
}

@Test func quickPasteNeedsItsModifierAlone() {
    #expect(QuickPasteModifier.option.isHeld(alone: [.option]))
    #expect(!QuickPasteModifier.option.isHeld(alone: [.option, .command]))
    #expect(!QuickPasteModifier.option.isHeld(alone: [.command]))
}

@Test func erasingHistoryKeepsSavedClips() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cpaste-erase-\(UUID().uuidString)")
    let store = try ClipStore(directory: directory)
    let kept = try store.insert(.text("keep me"), sourceBundleID: nil)
    try store.insert(.text("erase me"), sourceBundleID: nil)
    let category = try store.createCategory(name: "Work", colorHex: "#4CC764")
    try store.setCategory(clipIDs: [kept.id], to: category.id)
    #expect(try store.eraseHistory() == 1)
    #expect(try store.search("", in: .all, limit: 10).map(\.id) == [kept.id])
}

/// Draws the welcome window off screen into `build/welcome.png`.
@MainActor
@Test(.enabled(if: rendersPreviews)) func welcomeRenders() throws {
    let host = NSHostingView(rootView: WelcomeView(openShortcut: "⌘1", close: {})
        .background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .dark))
    host.frame = NSRect(origin: .zero, size: host.fittingSize)
    let window = NSWindow(contentRect: host.frame, styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: .darkAqua)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../../build/welcome.png").standardizedFileURL
    try #require(bitmap.representation(using: .png, properties: [:])).write(to: output)
}

/// Draws each settings pane off screen into `build/settings-<pane>.png`, so the layout can be reviewed without the running app.
@MainActor
@Test(.enabled(if: rendersPreviews), arguments: SettingsView.Pane.allCases)
func settingsPaneRenders(pane: SettingsView.Pane) async throws {
    var actions = SettingsActions()
    actions.health = {
        [HealthItem(title: "Recording", detail: "On", isHealthy: true),
         HealthItem(title: "Pasting", detail: "Needs the Accessibility permission", isHealthy: false),
         HealthItem(title: "Updates", detail: "Last checked 2 hours ago", isHealthy: true)]
    }
    let view = SettingsView(settings: AppSettings(defaults: freshDefaults()), actions: actions, pane: pane)
        .environment(\.colorScheme, .dark)
    let host = NSHostingView(rootView: view)
    host.frame = NSRect(x: 0, y: 0, width: 760, height: 640)
    let window = NSWindow(contentRect: host.frame, styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: .darkAqua)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(400))

    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../../build/settings-\(pane.rawValue).png").standardizedFileURL
    try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
    try png.write(to: output)
    #expect(png.count > 10_000)
}
