import CryptoKit
import Foundation
import GRDB

public enum ClipStoreError: Error {
    case malformedRow(id: Int64)
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
                                  contentHash, sourceBundleID, copiedAt, lastUsedAt)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT (contentHash) DO UPDATE SET lastUsedAt = excluded.lastUsedAt
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
            try Row.fetchAll(db, sql: "SELECT * FROM clip ORDER BY lastUsedAt DESC, id DESC LIMIT ?", arguments: [limit])
                .map(Self.clip(from:))
        }
    }

    /// Clips in `filter` whose text has a word starting with every word of `query`, newest first. An empty query matches all.
    public func search(_ query: String, in filter: ClipFilter, limit: Int) throws -> [Clip] {
        var conditions: [String] = []
        var arguments: [(any DatabaseValueConvertible)?] = []
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
            conditions.append("(id IN (SELECT rowid FROM clip_fts WHERE clip_fts MATCH ?)\(wantsImages ? " OR kind = 'image'" : ""))")
            arguments.append(match)
        }
        let filterSQL = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
        arguments.append(limit)
        return try database.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM clip \(filterSQL) ORDER BY lastUsedAt DESC, id DESC LIMIT ?",
                             arguments: StatementArguments(arguments))
                .map(Self.clip(from:))
        }
    }

    public func delete(clipID: Int64) throws {
        let imageHash = try database.write { db in
            try Row.fetchOne(db, sql: "DELETE FROM clip WHERE id = ? RETURNING imageHash", arguments: [clipID])
                .flatMap { $0["imageHash"] as String? }
        }
        if let imageHash { try imageFiles.remove(sha256: imageHash) }
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

    /// Deletes a category. Its clips go back to unsaved history.
    public func deleteCategory(id: Int64) throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM category WHERE id = ?", arguments: [id])
        }
    }

    /// Saves a clip to a category, or with nil returns it to unsaved history.
    public func setCategory(clipID: Int64, to categoryID: Int64?) throws {
        try database.write { db in
            try db.execute(sql: "UPDATE clip SET categoryID = ? WHERE id = ?", arguments: [categoryID, clipID])
        }
    }

    private static func category(from row: Row) -> ClipCategory {
        ClipCategory(id: row["id"], name: row["name"], colorHex: row["colorHex"], position: row["position"])
    }

    /// Moves a clip to the top after it was pasted.
    public func markUsed(id: Int64, at date: Date = Date()) throws {
        try database.write { db in
            try db.execute(sql: "UPDATE clip SET lastUsedAt = ? WHERE id = ?", arguments: [date, id])
        }
    }

    /// Deletes unsaved clips last used before `cutoff`, with their image files. Returns how many were deleted.
    @discardableResult
    public func expire(olderThan cutoff: Date) throws -> Int {
        let expired = try database.write { db in
            try Row.fetchAll(db, sql: """
                DELETE FROM clip WHERE categoryID IS NULL AND lastUsedAt < ? RETURNING imageHash
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
                    copiedAt: row["copiedAt"], lastUsedAt: row["lastUsedAt"], categoryID: row["categoryID"])
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
        return migrator
    }
}
