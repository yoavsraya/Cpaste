import CryptoKit
import Foundation
import GRDB

public enum ClipStoreError: Error, Equatable, LocalizedError {
    case malformedRow(id: Int64)
    case notEditable
    case duplicateText

    public var errorDescription: String? {
        switch self {
        case .malformedRow(let id): "Clip \(id) is damaged."
        case .notEditable: "Only text and links can be edited."
        case .duplicateText: "Another clip already has this text."
        }
    }
}

public final class ClipStore: Sendable {
    public let imageFiles: ImageFiles
    private let database: DatabaseQueue

    /// Opens, and creates if needed, the store in `directory`.
    public init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        imageFiles = ImageFiles(directory: directory)
        database = try DatabaseQueue(path: directory.appendingPathComponent("cpaste.sqlite").path)
        try Self.migrator.migrate(database)
    }

    /// Stores a capture. Content already in the store is moved to the top instead of duplicated.
    @discardableResult
    public func insert(_ capture: Capture, sourceBundleID: String?, at date: Date = Date()) throws -> Clip {
        let content = try content(for: capture)
        let columns = Columns(content)
        return try database.write { db in
            let row = try Row.fetchOne(db, sql: """
                INSERT INTO clip (kind, text, imageHash, pixelWidth, pixelHeight, byteCount,
                                  contentHash, sourceBundleID, copiedAt, lastUsedAt, position)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, \(Self.frontPosition))
                ON CONFLICT (contentHash) DO UPDATE SET lastUsedAt = excluded.lastUsedAt, position = excluded.position
                RETURNING *
                """, arguments: [
                    columns.kind, columns.text, columns.imageHash, columns.pixelWidth, columns.pixelHeight,
                    columns.byteCount, columns.contentHash, sourceBundleID, date, date,
                ])!
            return try Self.clip(from: row)
        }
    }

    public func recent(limit: Int) throws -> [Clip] {
        try database.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM clip ORDER BY isPinned DESC, position DESC, id DESC LIMIT ?", arguments: [limit])
                .map(Self.clip(from:))
        }
    }

    /// Clips in `filter` whose text has a word starting with every word of `query`, newest first. An empty query matches all.
    /// `kind` and `sourceBundleID` narrow the result to one clip type and one source app.
    public func search(_ query: String, in filter: ClipFilter, kind: ClipKind? = nil, sourceBundleID: String? = nil,
                       limit: Int) throws -> [Clip] {
        var conditions: [String] = []
        var arguments: [(any DatabaseValueConvertible)?] = []
        if let kind {
            conditions.append("kind = ?")
            arguments.append(kind.rawValue)
        }
        if let sourceBundleID {
            conditions.append("sourceBundleID = ?")
            arguments.append(sourceBundleID)
        }
        if case .category(let id) = filter {
            conditions.append("categoryID = ?")
            arguments.append(id)
        }
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // FTS5 rejects a phrase with no letters or digits in it.
            let words = query.split(whereSeparator: \.isWhitespace)
                .filter { $0.contains { $0.isLetter || $0.isNumber } }
            guard !words.isEmpty else { return [] }
            let match = words.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"*" }.joined(separator: " ")
            // Images have no text, so typing "image" is the way to find them.
            let wantsImages = words.count == 1 && words[0].count >= 2 && "image".hasPrefix(words[0].lowercased())
            // A title is short, so it is matched word by word without the index.
            let titleMatch = words.map { _ in "instr(lower(title), lower(?)) > 0" }.joined(separator: " AND ")
            conditions.append("""
                (id IN (SELECT rowid FROM clip_fts WHERE clip_fts MATCH ?)\(wantsImages ? " OR kind = 'image'" : "") \
                OR (title IS NOT NULL AND \(titleMatch)))
                """)
            arguments.append(match)
            arguments.append(contentsOf: words.map { String($0) })
        }
        let filterSQL = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
        arguments.append(limit)
        return try database.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM clip \(filterSQL) ORDER BY isPinned DESC, position DESC, id DESC LIMIT ?",
                             arguments: StatementArguments(arguments))
                .map(Self.clip(from:))
        }
    }

    /// Replaces the text of a text or link clip. The clip becomes a link when the new text is one web address, and text otherwise.
    @discardableResult
    public func updateText(clipID: Int64, to text: String) throws -> Clip {
        let columns = Columns(webLink(from: text).map(ClipContent.link) ?? .text(text))
        return try database.write { db in
            let kind = try String.fetchOne(db, sql: "SELECT kind FROM clip WHERE id = ?", arguments: [clipID])
            guard kind == "text" || kind == "link" else { throw ClipStoreError.notEditable }
            // contentHash is unique, so two clips cannot hold the same text.
            let twin = try Int64.fetchOne(db, sql: "SELECT id FROM clip WHERE contentHash = ? AND id != ?",
                                          arguments: [columns.contentHash, clipID])
            guard twin == nil else { throw ClipStoreError.duplicateText }
            let row = try Row.fetchOne(db, sql: "UPDATE clip SET kind = ?, text = ?, contentHash = ? WHERE id = ? RETURNING *",
                                       arguments: [columns.kind, columns.text, columns.contentHash, clipID])!
            return try Self.clip(from: row)
        }
    }

    /// The apps that clips were copied from, most recently used first.
    public func sourceBundleIDs() throws -> [String] {
        try database.read { db in
            try String.fetchAll(db, sql: """
                SELECT sourceBundleID FROM clip WHERE sourceBundleID IS NOT NULL
                GROUP BY sourceBundleID ORDER BY MAX(lastUsedAt) DESC
                """)
        }
    }

    /// How many clips the store holds and how many bytes its folder takes on disk, images included.
    public func usage() throws -> (clipCount: Int, byteCount: Int) {
        let clipCount = try database.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM clip") ?? 0 }
        let files = FileManager.default.enumerator(at: imageFiles.directory, includingPropertiesForKeys: [.fileSizeKey])
        var byteCount = 0
        while let url = files?.nextObject() as? URL {
            byteCount += try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        }
        return (clipCount, byteCount)
    }

    // MARK: Text inside images

    /// Image clips whose text has not been read yet, newest first.
    public func imagesAwaitingText(limit: Int) throws -> [(clipID: Int64, sha256: String)] {
        try database.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, imageHash FROM clip WHERE kind = 'image' AND text IS NULL ORDER BY lastUsedAt DESC LIMIT ?
                """, arguments: [limit])
                .map { (clipID: $0["id"], sha256: $0["imageHash"]) }
        }
    }

    /// Stores the text read from an image clip, so search finds it. An empty string records that the image has no text.
    public func setImageText(clipID: Int64, to text: String) throws {
        try database.write { db in
            // An image row keeps its recognized text in the `text` column, which the search index already covers.
            try db.execute(sql: "UPDATE clip SET text = ? WHERE id = ? AND kind = 'image'", arguments: [text, clipID])
        }
    }

    /// Deletes the clips in one transaction, so a failure leaves all of them in place.
    public func delete(clipIDs: [Int64]) throws {
        let imageHashes = try database.write { db in
            try clipIDs.compactMap { id in
                try Row.fetchOne(db, sql: "DELETE FROM clip WHERE id = ? RETURNING imageHash", arguments: [id])
                    .flatMap { $0["imageHash"] as String? }
            }
        }
        for imageHash in imageHashes { try imageFiles.remove(sha256: imageHash) }
    }

    // MARK: Categories

    public func categories() throws -> [ClipCategory] {
        try database.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM category ORDER BY position, id").map(Self.category(from:))
        }
    }

    /// Adds a category after the existing ones.
    @discardableResult
    public func createCategory(name: String, colorHex: String) throws -> ClipCategory {
        try database.write { db in
            let row = try Row.fetchOne(db, sql: """
                INSERT INTO category (name, colorHex, position)
                VALUES (?, ?, (SELECT COALESCE(MAX(position), -1) + 1 FROM category))
                RETURNING *
                """, arguments: [name, colorHex])!
            return Self.category(from: row)
        }
    }

    public func renameCategory(id: Int64, to name: String) throws {
        try database.write { db in
            try db.execute(sql: "UPDATE category SET name = ? WHERE id = ?", arguments: [name, id])
        }
    }

    public func recolorCategory(id: Int64, to colorHex: String) throws {
        try database.write { db in
            try db.execute(sql: "UPDATE category SET colorHex = ? WHERE id = ?", arguments: [colorHex, id])
        }
    }

    /// Moves a category into the place of another one, shifting the ones in between.
    public func moveCategory(id: Int64, toPlaceOf targetID: Int64) throws {
        try database.write { db in
            var ids = try Int64.fetchAll(db, sql: "SELECT id FROM category ORDER BY position, id")
            guard let from = ids.firstIndex(of: id), let to = ids.firstIndex(of: targetID), from != to else { return }
            ids.remove(at: from)
            ids.insert(id, at: to)
            for (position, id) in ids.enumerated() {
                try db.execute(sql: "UPDATE category SET position = ? WHERE id = ?", arguments: [position, id])
            }
        }
    }

    /// Deletes a category. Its clips go back to unsaved history.
    public func deleteCategory(id: Int64) throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM category WHERE id = ?", arguments: [id])
        }
    }

    /// Saves a clip to a category, or with nil returns it to unsaved history.
    public func setCategory(clipIDs: [Int64], to categoryID: Int64?) throws {
        try database.write { db in
            for id in clipIDs {
                try db.execute(sql: "UPDATE clip SET categoryID = ? WHERE id = ?", arguments: [categoryID, id])
            }
        }
    }

    /// Gives a clip a name. An empty name removes it.
    public func rename(clipID: Int64, to title: String) throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        try database.write { db in
            try db.execute(sql: "UPDATE clip SET title = ? WHERE id = ?", arguments: [trimmed.isEmpty ? nil : trimmed, clipID])
        }
    }

    /// The sort key that puts a clip in front of every other one. A higher position sorts first.
    private static let frontPosition = "(SELECT COALESCE(MAX(position), 0) + 1 FROM clip)"

    /// Moves a clip into the place of another one. The moved clip becomes pinned or unpinned to match its new neighbours.
    public func moveClip(id: Int64, toPlaceOf targetID: Int64) throws {
        guard id != targetID else { return }
        try database.write { db in
            guard let moved = try Row.fetchOne(db, sql: "SELECT isPinned, position FROM clip WHERE id = ?", arguments: [id]),
                  let target = try Row.fetchOne(db, sql: "SELECT isPinned, position FROM clip WHERE id = ?", arguments: [targetID])
            else { return }
            let targetPinned: Bool = target["isPinned"]
            let targetPosition: Double = target["position"]
            // A clip shown before its target lands just after it, and a clip shown after it lands just before it.
            let movedPinned: Bool = moved["isPinned"]
            let wasBefore = movedPinned == targetPinned ? (moved["position"] as Double) > targetPosition : movedPinned
            let neighbour = try Double.fetchOne(db, sql: """
                SELECT \(wasBefore ? "MAX" : "MIN")(position) FROM clip
                WHERE isPinned = ? AND position \(wasBefore ? "<" : ">") ? AND id != ?
                """, arguments: [targetPinned, targetPosition, id])
            let position = neighbour.map { ($0 + targetPosition) / 2 } ?? targetPosition + (wasBefore ? -1 : 1)
            try db.execute(sql: "UPDATE clip SET position = ?, isPinned = ? WHERE id = ?", arguments: [position, targetPinned, id])
        }
    }

    public func setPinned(clipIDs: [Int64], to isPinned: Bool) throws {
        try database.write { db in
            for id in clipIDs {
                try db.execute(sql: "UPDATE clip SET isPinned = ? WHERE id = ?", arguments: [isPinned, id])
            }
        }
    }

    private static func category(from row: Row) -> ClipCategory {
        ClipCategory(id: row["id"], name: row["name"], colorHex: row["colorHex"], position: row["position"])
    }

    /// Moves a clip to the top after it was pasted.
    public func markUsed(id: Int64, at date: Date = Date()) throws {
        try database.write { db in
            try db.execute(sql: "UPDATE clip SET lastUsedAt = ?, position = \(Self.frontPosition) WHERE id = ?", arguments: [date, id])
        }
    }

    /// Deletes every clip that is neither pinned nor saved in a category. Returns how many were deleted.
    @discardableResult
    public func eraseHistory() throws -> Int {
        try expire(olderThan: .distantFuture)
    }

    /// Deletes clips last used before `cutoff` that are neither pinned nor saved, with their image files. Returns how many were deleted.
    @discardableResult
    public func expire(olderThan cutoff: Date) throws -> Int {
        let expired = try database.write { db in
            try Row.fetchAll(db, sql: """
                DELETE FROM clip WHERE categoryID IS NULL AND isPinned = 0 AND lastUsedAt < ? RETURNING imageHash
                """, arguments: [cutoff])
                .map { $0["imageHash"] as String? }
        }
        for sha in expired.compactMap({ $0 }) {
            try imageFiles.remove(sha256: sha)
        }
        return expired.count
    }

    private func content(for capture: Capture) throws -> ClipContent {
        switch capture {
        case .text(let string): return .text(string)
        case .link(let url): return .link(url)
        case .file(let path): return .file(path: path)
        case .image(let data):
            let stored = try imageFiles.store(data)
            return .image(sha256: stored.sha256, pixelWidth: stored.pixelWidth,
                          pixelHeight: stored.pixelHeight, byteCount: stored.byteCount)
        }
    }

    private struct Columns {
        var kind: String
        var text: String?
        var imageHash: String?
        var pixelWidth: Int?
        var pixelHeight: Int?
        var byteCount: Int?
        var contentHash: String

        init(_ content: ClipContent) {
            switch content {
            case .text(let string): (kind, text) = ("text", string)
            case .link(let url): (kind, text) = ("link", url.absoluteString)
            case .file(let path): (kind, text) = ("file", path)
            case .image(let sha, let width, let height, let bytes):
                kind = "image"
                (imageHash, pixelWidth, pixelHeight, byteCount) = (sha, width, height, bytes)
            }
            contentHash = SHA256.hexDigest(of: Data("\(kind)\u{0}\(text ?? imageHash ?? "")".utf8))
        }
    }

    private static func clip(from row: Row) throws -> Clip {
        let id: Int64 = row["id"]
        let text: String? = row["text"]
        let content: ClipContent
        switch (row["kind"] as String, text, row["imageHash"] as String?) {
        case ("text", let string?, _): content = .text(string)
        case ("link", let string?, _):
            guard let url = URL(string: string) else { throw ClipStoreError.malformedRow(id: id) }
            content = .link(url)
        case ("file", let path?, _): content = .file(path: path)
        case ("image", _, let sha?):
            content = .image(sha256: sha, pixelWidth: row["pixelWidth"], pixelHeight: row["pixelHeight"], byteCount: row["byteCount"])
        default: throw ClipStoreError.malformedRow(id: id)
        }
        return Clip(id: id, content: content, contentHash: row["contentHash"], sourceBundleID: row["sourceBundleID"],
                    copiedAt: row["copiedAt"], lastUsedAt: row["lastUsedAt"], categoryID: row["categoryID"], title: row["title"], isPinned: row["isPinned"])
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "category") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("colorHex", .text).notNull()
                t.column("position", .integer).notNull()
            }
            try db.create(table: "clip") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("kind", .text).notNull()
                t.column("text", .text)
                t.column("imageHash", .text)
                t.column("pixelWidth", .integer)
                t.column("pixelHeight", .integer)
                t.column("byteCount", .integer)
                t.column("contentHash", .text).notNull().unique()
                t.column("sourceBundleID", .text)
                t.column("copiedAt", .datetime).notNull()
                t.column("lastUsedAt", .datetime).notNull().indexed()
                t.column("categoryID", .integer).references("category", onDelete: .setNull)
            }
            try db.create(virtualTable: "clip_fts", using: FTS5()) { t in
                t.synchronize(withTable: "clip")
                t.column("text")
            }
        }
        migrator.registerMigration("v2 pinned clips") { db in
            try db.alter(table: "clip") { t in
                t.add(column: "isPinned", .boolean).notNull().defaults(to: false)
            }
        }
        migrator.registerMigration("v3 clip positions") { db in
            try db.alter(table: "clip") { t in
                t.add(column: "position", .double).notNull().defaults(to: 0)
            }
            // Existing clips keep their order, newest first.
            try db.execute(sql: "UPDATE clip SET position = julianday(lastUsedAt)")
            try db.create(index: "clip_position", on: "clip", columns: ["position"])
        }
        migrator.registerMigration("v4 clip titles") { db in
            try db.alter(table: "clip") { t in
                t.add(column: "title", .text)
            }
        }
        return migrator
    }
}
