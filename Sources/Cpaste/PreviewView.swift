import AppKit
import CpasteCore
import SwiftUI
import UniformTypeIdentifiers

/// The large view of the selected clip, shown next to the shelf while Space is toggled on.
@MainActor
final class PreviewPanel {
    private nonisolated static let maxSize = CGSize(width: 900, height: 640)
    private nonisolated static let gap: CGFloat = 16

    // A plain borderless panel cannot take the keyboard, so the shelf keeps it and a click here does not close the shelf.
    private let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)

    init(model: ShelfModel, imageFiles: ImageFiles) {
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = NSHostingView(rootView: PreviewView(model: model, imageFiles: imageFiles))
    }

    var isVisible: Bool { panel.isVisible }

    /// Fills the part of `visible` the shelf leaves free, up to a comfortable reading size.
    func show(beside shelf: NSRect, in visible: NSRect, position: ShelfPosition, sharingType: NSWindow.SharingType) {
        panel.sharingType = sharingType
        panel.setFrame(Self.frame(beside: shelf, in: visible, position: position), display: true)
        panel.orderFront(nil)
    }

    func hide() {
        panel.orderOut(nil)
    }

    nonisolated static func frame(beside shelf: NSRect, in visible: NSRect, position: ShelfPosition) -> NSRect {
        let free: NSRect
        switch position {
        case .bottom: free = NSRect(x: visible.minX, y: shelf.maxY, width: visible.width, height: visible.maxY - shelf.maxY)
        case .right: free = NSRect(x: visible.minX, y: visible.minY, width: shelf.minX - visible.minX, height: visible.height)
        }
        let width = min(maxSize.width, free.width - 2 * gap)
        let height = min(maxSize.height, free.height - 2 * gap)
        return NSRect(x: free.midX - width / 2, y: free.midY - height / 2, width: width, height: height)
    }
}

struct PreviewView: View {
    /// Past this a text is cut, because laying out a huge text stalls the shelf.
    private static let textLimit = 20_000

    let model: ShelfModel
    let imageFiles: ImageFiles

    var body: some View {
        Group {
            if let pair = comparedPair {
                comparison(of: pair.old, and: pair.new)
            } else if model.clips.indices.contains(model.selection) {
                let clip = model.clips[model.selection]
                VStack(spacing: 0) {
                    header(for: clip)
                    Divider()
                    content(of: clip).frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    Text(footer(for: clip)).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                        .padding(.horizontal, 16).padding(.vertical, 9)
                }
            } else {
                Text("No clip selected").foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VisualEffect(material: .popover))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// The two selected clips, older first, when exactly two are selected and both are text.
    private var comparedPair: (old: Clip, new: Clip)? {
        let clips = model.selectedClips.sorted { $0.copiedAt < $1.copiedAt }
        guard clips.count == 2, case .text = clips[0].content, case .text = clips[1].content else { return nil }
        return (clips[0], clips[1])
    }

    private func comparison(of old: Clip, and new: Clip) -> some View {
        let result = TextComparison(old: comparable(old), new: comparable(new))
        let changed = result.old.filter(\.isChanged).count + result.new.filter(\.isChanged).count
        let unit = result.separator == "\n" ? "lines" : "words"
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                header(for: old, hint: "older")
                Divider()
                header(for: new, hint: "newer · Space or Esc to close")
            }
            .frame(height: 46)
            Divider()
            ScrollView {
                HStack(alignment: .top, spacing: 0) {
                    side(result.old, separator: result.separator, mark: .red)
                    Divider()
                    side(result.new, separator: result.separator, mark: .green)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            Text(result.isIdentical ? "The two clips are the same" : "\(changed) \(unit) differ")
                .font(.system(size: 11.5)).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.vertical, 9)
        }
    }

    /// JSON is compared in its laid-out form, so a change shows as one line and not as the whole clip.
    private func comparable(_ clip: Clip) -> String {
        guard case .text(let string) = clip.content else { return "" }
        if case .json(let pretty) = TextFlavor(string) { return String(pretty.prefix(Self.textLimit)) }
        return String(string.prefix(Self.textLimit))
    }

    private func side(_ pieces: [TextComparison.Piece], separator: String, mark: Color) -> some View {
        var text = AttributedString()
        for (index, piece) in pieces.enumerated() {
            // An empty line still needs something to carry the mark.
            var part = AttributedString(piece.isChanged && piece.text.isEmpty ? " " : piece.text)
            if piece.isChanged { part.backgroundColor = mark.opacity(0.32) }
            text += part
            if index < pieces.count - 1 { text += AttributedString(separator) }
        }
        return Text(text).font(.system(size: 13, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
    }

    private func header(for clip: Clip, hint: String = "Space or Esc to close") -> some View {
        HStack(spacing: 10) {
            if let icon = SourceApp.icon(bundleID: clip.sourceBundleID) {
                Image(nsImage: icon).resizable().frame(width: 26, height: 26)
            }
            Text(clip.title ?? kindTitle(of: clip)).font(.system(size: 15, weight: .semibold)).lineLimit(1)
            Spacer()
            Text(hint).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.horizontal, 16).frame(height: 46)
    }

    @ViewBuilder private func content(of clip: Clip) -> some View {
        switch clip.content {
        case .text(let string):
            switch TextFlavor(string) {
            case .json(let pretty): text(pretty, design: .monospaced)
            case .code: text(string, design: .monospaced)
            case .color(let red, let green, let blue):
                VStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(red: red, green: green, blue: blue))
                        .frame(width: 220, height: 220)
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.primary.opacity(0.15)))
                    Text(string.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(.system(size: 20, weight: .medium, design: .monospaced))
                }
            default: text(string, design: .default)
            }
        case .link(let url):
            VStack(spacing: 10) {
                if let title = clip.linkTitle {
                    Text(title).font(.system(size: 22, weight: .semibold)).multilineTextAlignment(.center)
                }
                Text(url.absoluteString).font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(clip.linkTitle == nil ? .primary : .secondary).multilineTextAlignment(.center)
            }
            .padding(28)
        case .image(let sha, _, _, _):
            picture(at: imageFiles.imageURL(sha256: sha)) {
                Label("Image file is missing", systemImage: "exclamationmark.triangle")
            }
        case .file(let path):
            let url = URL(fileURLWithPath: path)
            let isPicture = UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) ?? false
            if isPicture {
                picture(at: url) { fileSummary(path) }
            } else {
                fileSummary(path)
            }
        }
    }

    private func text(_ string: String, design: Font.Design) -> some View {
        let isShort = string.count <= 200 && string.split(whereSeparator: \.isNewline).count <= 3
        return ScrollView {
            Text(string.prefix(Self.textLimit))
                .font(.system(size: isShort ? 24 : 14, design: design))
                .multilineTextAlignment(isShort ? .center : .leading)
                .frame(maxWidth: .infinity, alignment: isShort ? .center : .leading)
                .padding(isShort ? 40 : 18)
        }
    }

    @ViewBuilder private func picture(at url: URL, @ViewBuilder missing: () -> some View) -> some View {
        if let image = Thumbnails.image(at: url) {
            Image(nsImage: image).resizable().scaledToFit().padding(14)
        } else {
            missing()
        }
    }

    private func fileSummary(_ path: String) -> some View {
        VStack(spacing: 10) {
            Image(nsImage: FileInfo.of(path: path).icon).resizable().frame(width: 128, height: 128)
            Text((path as NSString).lastPathComponent).font(.system(size: 20, weight: .semibold)).multilineTextAlignment(.center)
            Text((path as NSString).abbreviatingWithTildeInPath).font(.system(size: 12.5)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
    }

    private func kindTitle(of clip: Clip) -> String {
        switch clip.content {
        case .text(let string): TextFlavor(string).title
        case .link: "Link"
        case .image: "Image"
        case .file: "File"
        }
    }

    private func footer(for clip: Clip) -> String {
        var parts: [String] = []
        switch clip.content {
        case .text(let string):
            let words = string.split(whereSeparator: \.isWhitespace).count
            parts.append("\(string.count) characters · \(words) \(words == 1 ? "word" : "words")")
            if string.count > Self.textLimit { parts.append("showing the first \(Self.textLimit)") }
        case .image(_, let width, let height, let bytes):
            parts.append("\(width) × \(height) · \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))")
        case .file(let path):
            parts.append(FileInfo.of(path: path).detail)
        case .link:
            break
        }
        if let bundleID = clip.sourceBundleID { parts.append(SourceApp.name(bundleID: bundleID)) }
        parts.append("copied " + clip.copiedAt.formatted(date: .abbreviated, time: .shortened))
        return parts.joined(separator: " · ")
    }
}
