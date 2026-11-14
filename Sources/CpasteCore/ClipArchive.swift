import Foundation
import GRDB

/// The categories and their clips in one file, for moving them to another Mac or sharing them.
public struct ClipArchive: Codable, Equatable, Sendable {
    public static let currentFormat = 1

    public var format = ClipArchive.currentFormat
    public var categories: [Category]

    public struct Category: Codable, Equatable, Sendable {
        public var name: String
        public var colorHex: String
        public var clips: [Item]
    }

    public struct Item: Codable, Equatable, Sendable {
        public var kind: ClipKind
        /// The text, the web address or the file path. Nil for an image.
        public var text: String?
        /// The PNG bytes of an image clip.
        public var image: Data?
        public var title: String?
        public var isPinned: Bool
        public var sourceBundleID: String?
    }
}

public enum ClipArchiveError: Error, LocalizedError {
    case unreadable
    case newerFormat(Int)

    public var errorDescription: String? {
        switch self {
        case .unreadable: "This is not a Cpaste export file."
        case .newerFormat(let format): "This file was made by a newer Cpaste (format \(format)). Update Cpaste and try again."
        }
    }
}

extension ClipKind: Codable {}

extension ClipStore {
    /// Every category with the clips saved in it, in shelf order.
    public func exportArchive() throws -> Data {
        let categories = try self.categories().map { category in
            ClipArchive.Category(name: category.name, colorHex: category.colorHex, clips: try search("", in: .category(category.id), limit: .max).map { clip in
                var item = ClipArchive.Item(kind: clip.content.kind, title: clip.title, isPinned: clip.isPinned, sourceBundleID: clip.sourceBundleID)
                switch clip.content {
                case .text(let string): item.text = string
                case .link(let url): item.text = url.absoluteString
                case .file(let path): item.text = path
                case .image(let sha, _, _, _): item.image = try Data(contentsOf: imageFiles.imageURL(sha256: sha))
                }
                return item
            })
        }
        return try JSONEncoder().encode(ClipArchive(categories: categories))
    }

    /// Adds the clips of an export file. A category with the same name is reused, and a clip already in the store is moved into it.
    /// Returns how many clips were read from the file.
    @discardableResult
    public func importArchive(_ data: Data) throws -> Int {
        guard let archive = try? JSONDecoder().decode(ClipArchive.self, from: data) else { throw ClipArchiveError.unreadable }
        guard archive.format <= ClipArchive.currentFormat else { throw ClipArchiveError.newerFormat(archive.format) }
        var existing = Dictionary(try categories().map { ($0.name, $0.id) }, uniquingKeysWith: { first, _ in first })
        var count = 0
        for category in archive.categories {
            let categoryID = try existing[category.name] ?? createCategory(name: category.name, colorHex: category.colorHex).id
            existing[category.name] = categoryID
            // Reversed, because each insert goes to the front and the file lists the front clip first.
            for item in category.clips.reversed() {
                guard let capture = item.capture else { continue }
                let clip = try insert(capture, sourceBundleID: item.sourceBundleID)
                try setCategory(clipIDs: [clip.id], to: categoryID)
                if let title = item.title { try rename(clipID: clip.id, to: title) }
                if item.isPinned { try setPinned(clipIDs: [clip.id], to: true) }
                count += 1
            }
        }
        return count
    }
}

extension ClipArchive.Item {
    init(kind: ClipKind, title: String?, isPinned: Bool, sourceBundleID: String?) {
        self.init(kind: kind, text: nil, image: nil, title: title, isPinned: isPinned, sourceBundleID: sourceBundleID)
    }

    /// Nil when the item lacks the data its kind needs.
    var capture: Capture? {
        switch kind {
        case .text: text.map(Capture.text)
        case .link: text.flatMap(URL.init(string:)).map(Capture.link)
        case .file: text.map(Capture.file(path:))
        case .image: image.map(Capture.image)
        }
    }
}
