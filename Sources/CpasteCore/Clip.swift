import Foundation

public enum ClipContent: Equatable, Sendable {
    case text(String)
    case link(URL)
    case image(sha256: String, pixelWidth: Int, pixelHeight: Int, byteCount: Int)
    case file(path: String)
}

public enum ClipKind: String, CaseIterable, Sendable {
    case text, link, image, file
}

extension ClipContent {
    public var kind: ClipKind {
        switch self {
        case .text: .text
        case .link: .link
        case .image: .image
        case .file: .file
        }
    }
}

public struct Clip: Equatable, Sendable, Identifiable {
    public let id: Int64
    public let content: ClipContent
    public let contentHash: String
    public let sourceBundleID: String?
    public let copiedAt: Date
    public var lastUsedAt: Date
    public var categoryID: Int64?
    /// The text read from an image clip. Nil for other clips and for images that are not read yet.
    public var imageText: String?
    /// The title of the page a link clip points at, when the browser gave one.
    public var linkTitle: String?
    /// A name the user gave the clip, shown on its card in place of its type.
    public var title: String?
    /// A pinned clip sorts before the others and never expires.
    public var isPinned: Bool
    /// How many times the clip was pasted or copied out of the shelf.
    public var useCount: Int
}

/// The order clips are listed in.
public enum ClipOrder: String, CaseIterable, Sendable {
    /// Pinned clips, then the newest or the manually placed.
    case shelf
    case mostUsed
}

// Named ClipCategory because Foundation re-exports the Objective-C runtime's `Category` type.
public struct ClipCategory: Equatable, Sendable, Identifiable {
    public let id: Int64
    public var name: String
    public var colorHex: String
    public var position: Int
}

public enum ClipFilter: Equatable, Sendable {
    case all
    case category(Int64)
}
