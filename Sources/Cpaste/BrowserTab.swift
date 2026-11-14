import AppKit
import ApplicationServices

/// Reads the title of the page a browser is showing, through the Accessibility permission Cpaste already has for pasting.
@MainActor
enum BrowserTab {
    /// The page title, only when the front window of `app` is showing exactly `url`. A link copied from inside a page gets no title.
    static func title(showing url: URL, in app: NSRunningApplication) -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        // A busy browser must not stall the clipboard poll.
        AXUIElementSetMessagingTimeout(application, 0.15)
        guard let window = element(application, kAXFocusedWindowAttribute),
              let page = webArea(in: window),
              let pageURL = value(page, "AXURL") as? URL, same(pageURL, url)
        else { return nil }
        let title = (value(page, kAXTitleAttribute) as? String) ?? (value(window, kAXTitleAttribute) as? String)
        return title.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
    }

    /// Breadth first, with a cap on elements and on time, because a browser window holds thousands of them.
    private static func webArea(in window: AXUIElement) -> AXUIElement? {
        let deadline = Date().addingTimeInterval(0.25)
        var queue = [window]
        var visited = 0
        while !queue.isEmpty, visited < 300, Date() < deadline {
            let current = queue.removeFirst()
            visited += 1
            if value(current, kAXRoleAttribute) as? String == "AXWebArea" { return current }
            queue.append(contentsOf: (value(current, kAXChildrenAttribute) as? [AXUIElement]) ?? [])
        }
        return nil
    }

    private static func value(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var result: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success ? result : nil
    }

    private static func element(_ parent: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let result = value(parent, attribute), CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }
        return (result as! AXUIElement)
    }

    private static func same(_ a: URL, _ b: URL) -> Bool {
        func normal(_ url: URL) -> String {
            var text = url.absoluteString
            if let fragment = text.firstIndex(of: "#") { text = String(text[..<fragment]) }
            return text.hasSuffix("/") ? String(text.dropLast()) : text
        }
        return normal(a) == normal(b)
    }
}
