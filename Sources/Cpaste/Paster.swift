import AppKit
import Carbon.HIToolbox
import CpasteCore

@MainActor
enum Paster {
    static var canPasteDirectly: Bool { AXIsProcessTrusted() }

    /// Shows the system dialog that sends the user to the Accessibility settings.
    static func requestDirectPaste() {
        // The value of kAXTrustedCheckOptionPrompt, which Swift 6 rejects as an unsafe global.
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func write(_ clip: Clip, imageFiles: ImageFiles, to pasteboard: NSPasteboard = .general) throws {
        pasteboard.clearContents()
        switch clip.content {
        case .text(let string):
            pasteboard.setString(string, forType: .string)
        case .link(let url):
            pasteboard.setString(url.absoluteString, forType: .string)
        case .file(let path):
            pasteboard.writeObjects([URL(fileURLWithPath: path) as NSURL])
        case .image(let sha, _, _, _):
            let png = try Data(contentsOf: imageFiles.imageURL(sha256: sha))
            let item = NSPasteboardItem()
            item.setData(png, forType: .png)
            // Some apps only accept TIFF from the clipboard.
            if let tiff = NSImage(data: png)?.tiffRepresentation {
                item.setData(tiff, forType: .tiff)
            }
            pasteboard.writeObjects([item])
        }
    }

    /// Presses Command-V in the frontmost app. Does nothing without the Accessibility permission.
    static func sendCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: keyDown)
            event?.flags = .maskCommand
            event?.post(tap: .cgAnnotatedSessionEventTap)
        }
    }
}
