import Foundation

public enum ClipContent: Equatable, Sendable {
    case text(String)
    case link(URL)
    case image(sha256: String, pixelWidth: Int, pixelHeight: Int, byteCount: Int)
    case file(path: String)
}

public struct Clip: Equatable, Sendable, Identifiable {
    public let id: Int64
    public let content: ClipContent
    public let contentHash: String
    public let sourceBundleID: String?
    public let copiedAt: Date
    public var lastUsedAt: Date
    public var categoryID: Int64?
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
