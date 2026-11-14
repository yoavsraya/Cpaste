import AppKit
import Carbon.HIToolbox

struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var keyLabel: String

    static let openDefault = Shortcut(keyCode: UInt32(kVK_ANSI_1), carbonModifiers: UInt32(cmdKey), keyLabel: "1")

    var display: String {
        var symbols = ""
        if carbonModifiers & UInt32(controlKey) != 0 { symbols += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { symbols += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { symbols += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { symbols += "⌘" }
        return symbols + keyLabel
    }

}

extension Shortcut {
    /// Nil unless the key press includes Command, Control, or Option, since a bare key would block normal typing.
    init?(event: NSEvent) {
        let flags = event.modifierFlags
        guard !flags.isDisjoint(with: [.command, .control, .option]) else { return nil }
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        let named: [Int: String] = [kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫"]
        let typed = event.characters(byApplyingModifiers: [])?.uppercased() ?? ""
        let label = named[Int(event.keyCode)] ?? (typed.isEmpty ? "Key \(event.keyCode)" : typed)
        self.init(keyCode: UInt32(event.keyCode), carbonModifiers: modifiers, keyLabel: label)
    }
}
