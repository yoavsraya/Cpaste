import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct StoredImage: Equatable, Sendable {
    public let sha256: String
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let byteCount: Int
}

public enum ImageFilesError: Error {
    case undecodable
    case writeFailed(URL)
}

public struct ImageFiles: Sendable {
    public static let thumbnailMaxPixels = 400
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func imageURL(sha256: String) -> URL {
        directory.appendingPathComponent("images/\(sha256).png")
    }

    public func thumbnailURL(sha256: String) -> URL {
        directory.appendingPathComponent("thumbs/\(sha256).jpg")
    }

    public func store(_ data: Data) throws -> StoredImage {
        let sha = SHA256.hexDigest(of: data)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw ImageFilesError.undecodable }

        let full = imageURL(sha256: sha)
        let thumb = thumbnailURL(sha256: sha)
        let files = FileManager.default
        if !files.fileExists(atPath: full.path) {
            try write(image, to: full, as: .png)
        }
        if !files.fileExists(atPath: thumb.path) {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: Self.thumbnailMaxPixels,
            ]
            guard let small = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                throw ImageFilesError.undecodable
            }
            try write(small, to: thumb, as: .jpeg)
        }
        let byteCount = try full.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        return StoredImage(sha256: sha, pixelWidth: image.width, pixelHeight: image.height, byteCount: byteCount)
    }

    public func remove(sha256: String) throws {
        for url in [imageURL(sha256: sha256), thumbnailURL(sha256: sha256)]
        where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func write(_ image: CGImage, to url: URL, as type: UTType) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw ImageFilesError.writeFailed(url)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ImageFilesError.writeFailed(url) }
    }
}

extension SHA256 {
    static func hexDigest(of data: Data) -> String {
        hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
