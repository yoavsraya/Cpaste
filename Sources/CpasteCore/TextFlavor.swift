import Foundation

/// What a text clip looks like, so its card can show it in the most recognisable way.
public enum TextFlavor: Equatable, Sendable {
    case plain
    /// Components from 0 to 1.
    case color(red: Double, green: Double, blue: Double)
    case code
    /// JSON, with the same data laid out one value per line.
    case json(pretty: String)
    case email
    case phone
    case date(Date)
    case address

    public init(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let color = Self.hexColor(trimmed) ?? Self.rgbColor(trimmed) {
            self = color
        } else if let json = Self.json(trimmed) {
            self = json
        } else if Self.isEmail(trimmed) {
            self = .email
        } else if let detected = Self.detected(trimmed) {
            self = detected
        } else if Self.looksLikeCode(trimmed) {
            self = .code
        } else {
            self = .plain
        }
    }

    private static func json(_ text: String) -> TextFlavor? {
        guard text.hasPrefix("{") || text.hasPrefix("["), text.count < 200_000,
              let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let pretty = String(data: data, encoding: .utf8)
        else { return nil }
        return .json(pretty: pretty)
    }

    private static func isEmail(_ text: String) -> Bool {
        text.wholeMatch(of: /[A-Za-z0-9._%+\-]+@[A-Za-z0-9\-]+(\.[A-Za-z0-9\-]+)+/) != nil
    }

    private static let detector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType([.phoneNumber, .date, .address]).rawValue)

    /// A phone number, a date or a postal address, when the whole text is one of them.
    private static func detected(_ text: String) -> TextFlavor? {
        guard text.count <= 200, let detector else { return nil }
        let whole = NSRange(text.startIndex..., in: text)
        guard let match = detector.firstMatch(in: text, range: whole), match.range == whole else { return nil }
        switch match.resultType {
        case .phoneNumber:
            // A bare run of digits is more often an order number than a phone number.
            let digits = text.filter(\.isNumber).count
            let looksDialled = text.hasPrefix("+") || text.hasPrefix("0") || text.contains { " -()".contains($0) }
            return (7...15).contains(digits) && looksDialled && !text.contains(where: \.isLetter) ? .phone : nil
        case .date:
            // "5" or "now" alone are not worth a date card.
            return text.contains(where: \.isNumber) && text.count >= 6 ? match.date.map(TextFlavor.date) : nil
        case .address:
            return .address
        default:
            return nil
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
