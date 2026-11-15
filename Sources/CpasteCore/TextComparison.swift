/// What differs between two texts, for showing them side by side.
public struct TextComparison: Equatable, Sendable {
    public struct Piece: Equatable, Sendable {
        public let text: String
        /// True when the other text has no matching piece at this place.
        public let isChanged: Bool
    }

    public let old: [Piece]
    public let new: [Piece]
    /// What joins the pieces back into the text. Lines are compared, or words when both texts are a single line.
    public let separator: String

    public init(old: String, new: String) {
        let byLine = old.contains(where: \.isNewline) || new.contains(where: \.isNewline)
        separator = byLine ? "\n" : " "
        func pieces(of text: String) -> [String] {
            byLine ? text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
                   : text.split(separator: " ").map(String.init)
        }
        let oldPieces = pieces(of: old), newPieces = pieces(of: new)
        var removed: Set<Int> = [], inserted: Set<Int> = []
        for change in newPieces.difference(from: oldPieces) {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        self.old = oldPieces.enumerated().map { Piece(text: $1, isChanged: removed.contains($0)) }
        self.new = newPieces.enumerated().map { Piece(text: $1, isChanged: inserted.contains($0)) }
    }

    public var isIdentical: Bool {
        !old.contains(where: \.isChanged) && !new.contains(where: \.isChanged)
    }
}
