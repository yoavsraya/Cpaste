import Foundation

/// What the clipboard held at one change, before it is stored.
public enum Capture: Equatable, Sendable {
    case text(String)
    case link(URL)
    case image(Data)
    case file(path: String)
}

public enum PasteboardType {
    public static let concealed = "org.nspasteboard.ConcealedType"
    public static let transient = "org.nspasteboard.TransientType"
    public static let fileURL = "public.file-url"
    public static let text = "public.utf8-plain-text"
    public static let png = "public.png"
    public static let tiff = "public.tiff"
}

public func classify(types: Set<String>, read: (String) -> Data?) -> Capture? {
    if types.contains(PasteboardType.concealed) || types.contains(PasteboardType.transient) {
        return nil
    }
    // A file copied in Finder also carries its name as text and its icon as an image, so the file wins.
    if let string = readString(PasteboardType.fileURL, types, read),
       let url = URL(string: string), url.isFileURL {
        return .file(path: url.path)
    }
    // Office apps attach a rendered image to every text copy, so non-empty text wins over an image.
    if let string = readString(PasteboardType.text, types, read),
       !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return webLink(from: string).map(Capture.link) ?? .text(string)
    }
    for type in [PasteboardType.png, PasteboardType.tiff] where types.contains(type) {
        if let data = read(type), !data.isEmpty {
            return .image(data)
        }
    }
    return nil
}

private func readString(_ type: String, _ types: Set<String>, _ read: (String) -> Data?) -> String? {
    guard types.contains(type), let data = read(type) else { return nil }
    return String(data: data, encoding: .utf8)
}

private func webLink(from string: String) -> URL? {
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
          let url = URL(string: trimmed),
          let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
          url.host != nil
    else { return nil }
    return url
}
