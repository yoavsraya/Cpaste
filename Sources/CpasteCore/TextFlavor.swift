import Foundation

/// What a text clip looks like, so its card can show it in the most recognisable way.
public enum TextFlavor: Equatable, Sendable {
    case plain
    /// Components from 0 to 1.
    case color(red: Double, green: Double, blue: Double)
    case code

    public init(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let color = Self.hexColor(trimmed) ?? Self.rgbColor(trimmed) {
            self = color
        } else if Self.looksLikeCode(trimmed) {
            self = .code
        } else {
            self = .plain
        }
    }

    private static func hexColor(_ text: String) -> TextFlavor? {
        guard text.hasPrefix("#") else { return nil }
        var digits = String(text.dropFirst())
        guard [3, 6, 8].contains(digits.count), digits.allSatisfy(\.isHexDigit) else { return nil }
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        guard let value = UInt32(digits.prefix(6), radix: 16) else { return nil }
        return .color(red: Double(value >> 16 & 0xFF) / 255, green: Double(value >> 8 & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }

    private static func rgbColor(_ text: String) -> TextFlavor? {
        let lowered = text.lowercased()
        guard lowered.hasPrefix("rgb"), lowered.hasSuffix(")"), let open = lowered.firstIndex(of: "(") else { return nil }
        let parts = lowered[lowered.index(after: open)...].dropLast()
            .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" })
            .compactMap { Double($0) }
        guard parts.count >= 3, parts.prefix(3).allSatisfy({ (0...255).contains($0) }) else { return nil }
        return .color(red: parts[0] / 255, green: parts[1] / 255, blue: parts[2] / 255)
    }

    private static let commands: Set<String> = [
        "git", "swift", "npm", "pnpm", "yarn", "npx", "cd", "ls", "curl", "docker", "kubectl", "brew", "python", "python3",
        "pip", "uv", "sudo", "ssh", "cat", "grep", "make", "node", "go", "cargo", "echo", "export", "mkdir", "rm", "cp", "mv",
    ]
    /// Words that open a line of code. They are only counted at the start of a line, since prose uses them too.
    private static let openers = [
        "func ", "let ", "var ", "const ", "import ", "def ", "class ", "return ", "public ", "private ",
        "SELECT ", "INSERT ", "UPDATE ", "if (", "for (", "<", "//",
    ]
    private static let operators = ["=> ", "-> ", "== ", "!= ", "&& ", "|| ", "</", "/>"]

    private static func looksLikeCode(_ text: String) -> Bool {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let first = lines.first else { return false }
        // Every line is a shell command.
        let isCommand: (String) -> Bool = { line in
            line.hasPrefix("./") || line.hasPrefix("$ ") || commands.contains(String(line.prefix { !$0.isWhitespace }))
        }
        if first.contains(" ") || lines.count > 1 || first.hasPrefix("./"), lines.allSatisfy(isCommand) { return true }
        let codeLines = lines.filter { line in
            line.hasSuffix("{") || line.hasSuffix("}") || line.hasSuffix(";") || line.hasSuffix("},")
                || openers.contains { line.hasPrefix($0) } || operators.contains { line.contains($0) }
        }
        // One stray keyword in a paragraph of prose is not code.
        return codeLines.count * 2 >= lines.count && !codeLines.isEmpty && (lines.count > 1 || first.hasSuffix(";") || first.hasSuffix("}"))
    }
}
