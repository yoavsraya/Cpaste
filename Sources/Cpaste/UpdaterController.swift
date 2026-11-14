import AppKit
import Sparkle

/// Checks the release feed for a newer Cpaste and installs it. Does nothing outside a release build of the app bundle.
@MainActor
final class UpdaterController: NSObject, @preconcurrency SPUStandardUserDriverDelegate {
    private var controller: SPUStandardUpdaterController?
    /// Called with the version of an update that is waiting, and with nil once it is installed or dismissed.
    var onAvailableVersionChange: (String?) -> Void = { _ in }

    var isActive: Bool { controller != nil }

    var checksAutomatically: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    func start() {
        // `swift run` and the tests have no Info.plist feed, and Sparkle refuses to start without one.
        guard controller == nil, Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else {
            log.notice("updates are off: this build has no update feed")
            return
        }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        log.notice("updates are on, automatic checks: \(self.checksAutomatically)")
    }

    func checkForUpdates() {
        // A menu-bar app has no window in front, so the update window would open behind the current app.
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }

    // MARK: SPUStandardUserDriverDelegate

    // A menu-bar app must not throw a window at the user for a background check, so the menu shows the update instead.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if !handleShowingUpdate {
            log.notice("update \(update.displayVersionString, privacy: .public) is available")
            onAvailableVersionChange(update.displayVersionString)
        }
    }

    func standardUserDriverWillFinishUpdateSession() {
        onAvailableVersionChange(nil)
    }
}
