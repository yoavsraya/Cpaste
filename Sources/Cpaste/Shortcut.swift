import AppKit
import Carbon.HIToolbox

struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var keyLabel: String

    static let openDefault = Shortcut(keyCode: UInt32(kVK_ANSI_1), carbonModifiers: UInt32(cmdKey), keyLabel: "1")
    static let nextCategoryDefault = Shortcut(keyCode: UInt32(kVK_RightArrow), carbonModifiers: UInt32(cmdKey), keyLabel: "→")
    static let previousCategoryDefault = Shortcut(keyCode: UInt32(kVK_LeftArrow), carbonModifiers: UInt32(cmdKey), keyLabel: "←")

    var display: String {
        var symbols = ""
        if carbonModifiers & UInt32(controlKey) != 0 { symbols += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { symbols += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { symbols += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { symbols += "⌘" }
        return symbols + keyLabel
    }

    func matches(_ event: NSEvent) -> Bool {
        keyCode == UInt32(event.keyCode) && carbonModifiers == Self.carbonModifiers(of: event.modifierFlags)
    }

    private static func carbonModifiers(of flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        return modifiers
    }
}

extension Shortcut {
    /// Nil unless the key press includes Command, Control, or Option, since a bare key would block normal typing.
    init?(event: NSEvent) {
        guard !event.modifierFlags.isDisjoint(with: [.command, .control, .option]) else { return nil }
        let named: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        ]
        let typed = event.characters(byApplyingModifiers: [])?.uppercased() ?? ""
        let label = named[Int(event.keyCode)] ?? (typed.isEmpty ? "Key \(event.keyCode)" : typed)
        self.init(keyCode: UInt32(event.keyCode), carbonModifiers: Self.carbonModifiers(of: event.modifierFlags), keyLabel: label)
    }
}

/// The key held with a digit to paste a clip by its position in the shelf.
enum QuickPasteModifier: String, CaseIterable {
    case command, option, control

    var label: String {
        switch self {
        case .command: "⌘ Command"
        case .option: "⌥ Option"
        case .control: "⌃ Control"
        }
    }

    var symbol: String { String(label.prefix(1)) }

    var flag: NSEvent.ModifierFlags {
        switch self {
        case .command: .command
        case .option: .option
        case .control: .control
        }
    }

    func isHeld(alone flags: NSEvent.ModifierFlags) -> Bool {
        flags.intersection([.command, .option, .control, .shift]) == flag
    }
}

/// Where Return sends the selected clip.
enum PasteTarget: String, CaseIterable {
    case activeApp, clipboard
}
