import AppKit
import CpasteCore

@MainActor
final class PasteboardMonitor {
    private let pasteboard = NSPasteboard.general
    private let onCapture: (Capture, _ sourceBundleID: String?) -> Void
    private var lastChangeCount: Int
    private var timer: Timer?

    init(onCapture: @escaping (Capture, _ sourceBundleID: String?) -> Void) {
        self.onCapture = onCapture
        lastChangeCount = pasteboard.changeCount
    }

    // AppKit posts no notification when the clipboard changes, so the change count is polled.
    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    /// Call after the app itself writes to the clipboard, so that write is not recorded as a new copy.
    func skipCurrentContents() {
        lastChangeCount = pasteboard.changeCount
    }

    private func poll() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        let types = Set((pasteboard.types ?? []).map(\.rawValue))
        let pasteboard = pasteboard
        guard let capture = classify(types: types, read: { pasteboard.data(forType: .init($0)) }) else { return }
        onCapture(capture, NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    }
}
