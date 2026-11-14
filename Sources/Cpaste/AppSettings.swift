import CpasteCore
import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {
    static let defaultIgnoredBundleIDs = ["com.1password.1password", "com.apple.Passwords", "com.apple.keychainaccess"]

    var openShortcut: Shortcut {
        didSet { save(openShortcut, for: Key.openShortcut) }
    }
    var nextCategoryShortcut: Shortcut {
        didSet { save(nextCategoryShortcut, for: Key.nextCategoryShortcut) }
    }
    var previousCategoryShortcut: Shortcut {
        didSet { save(previousCategoryShortcut, for: Key.previousCategoryShortcut) }
    }
    var quickPasteModifier: QuickPasteModifier {
        didSet { defaults.set(quickPasteModifier.rawValue, forKey: Key.quickPasteModifier) }
    }
    var pasteTarget: PasteTarget {
        didSet { defaults.set(pasteTarget.rawValue, forKey: Key.pasteTarget) }
    }
    /// False until the welcome window has been shown once.
    var hasSeenWelcome: Bool {
        didSet { defaults.set(hasSeenWelcome, forKey: Key.hasSeenWelcome) }
    }
    var cardSize: CardSize {
        didSet { defaults.set(cardSize.rawValue, forKey: Key.cardSize) }
    }
    var showsDuringScreenSharing: Bool {
        didSet { defaults.set(showsDuringScreenSharing, forKey: Key.showsDuringScreenSharing) }
    }
    var retention: Retention {
        didSet { defaults.set(retention.rawValue, forKey: Key.retention) }
    }
    var ignoredBundleIDs: [String] {
        didSet { defaults.set(ignoredBundleIDs, forKey: Key.ignoredBundleIDs) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func shortcut(_ key: String, default fallback: Shortcut) -> Shortcut {
            defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) } ?? fallback
        }
        openShortcut = shortcut(Key.openShortcut, default: .openDefault)
        nextCategoryShortcut = shortcut(Key.nextCategoryShortcut, default: .nextCategoryDefault)
        previousCategoryShortcut = shortcut(Key.previousCategoryShortcut, default: .previousCategoryDefault)
        quickPasteModifier = defaults.string(forKey: Key.quickPasteModifier).flatMap(QuickPasteModifier.init(rawValue:)) ?? .command
        pasteTarget = defaults.string(forKey: Key.pasteTarget).flatMap(PasteTarget.init(rawValue:)) ?? .activeApp
        hasSeenWelcome = defaults.bool(forKey: Key.hasSeenWelcome)
        cardSize = defaults.string(forKey: Key.cardSize).flatMap(CardSize.init(rawValue:)) ?? .medium
        showsDuringScreenSharing = defaults.object(forKey: Key.showsDuringScreenSharing) as? Bool ?? true
        retention = defaults.string(forKey: Key.retention).flatMap(Retention.init(rawValue:)) ?? .month
        ignoredBundleIDs = defaults.stringArray(forKey: Key.ignoredBundleIDs) ?? Self.defaultIgnoredBundleIDs
    }

    func resetShortcuts() {
        openShortcut = .openDefault
        nextCategoryShortcut = .nextCategoryDefault
        previousCategoryShortcut = .previousCategoryDefault
        quickPasteModifier = .command
    }

    private func save(_ shortcut: Shortcut, for key: String) {
        defaults.set(try? JSONEncoder().encode(shortcut), forKey: key)
    }

    private enum Key {
        static let openShortcut = "openShortcut"
        static let nextCategoryShortcut = "nextCategoryShortcut"
        static let previousCategoryShortcut = "previousCategoryShortcut"
        static let quickPasteModifier = "quickPasteModifier"
        static let pasteTarget = "pasteTarget"
        static let cardSize = "cardSize"
        static let hasSeenWelcome = "hasSeenWelcome"
        static let showsDuringScreenSharing = "showsDuringScreenSharing"
        static let retention = "retention"
        static let ignoredBundleIDs = "ignoredBundleIDs"
    }
}
