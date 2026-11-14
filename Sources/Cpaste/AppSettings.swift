import CpasteCore
import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {
    static let defaultIgnoredBundleIDs = ["com.1password.1password", "com.apple.Passwords"]

    var openShortcut: Shortcut {
        didSet { defaults.set(try? JSONEncoder().encode(openShortcut), forKey: Key.openShortcut) }
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
        openShortcut = defaults.data(forKey: Key.openShortcut)
            .flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) } ?? .openDefault
        retention = defaults.string(forKey: Key.retention).flatMap(Retention.init(rawValue:)) ?? .month
        ignoredBundleIDs = defaults.stringArray(forKey: Key.ignoredBundleIDs) ?? Self.defaultIgnoredBundleIDs
    }

    private enum Key {
        static let openShortcut = "openShortcut"
        static let retention = "retention"
        static let ignoredBundleIDs = "ignoredBundleIDs"
    }
}
