import AppKit
import CpasteCore
import Observation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class ShelfModel {
    enum Naming: Equatable {
        case new(assignTo: [Clip])
        case rename(ClipCategory)
    }

    var clips: [Clip] = []
    var categories: [ClipCategory] = []
    var selection = 0
    /// Clips picked with Command-click. While it is empty, the clip at `selection` is the only selected one.
    var marked: Set<Int64> = []
    var query = ""
    var filter: ClipFilter = .all
    var naming: Naming?
    var nameDraft = ""
    /// The clip whose text is open in the edit box.
    var editing: Clip?
    var editDraft = ""
    var editError: String?
    var canPasteDirectly = true
    var errorMessage: String?
    /// The clip being dragged inside the shelf, read when it is dropped on a category.
    var draggedClip: Clip?
    /// Bumped whenever keyboard focus should return to the text field in use.
    var focusToken = 0

    var selectedClips: [Clip] {
        if marked.isEmpty { return clips.indices.contains(selection) ? [clips[selection]] : [] }
        return clips.filter { marked.contains($0.id) }
    }

    func isSelected(at index: Int) -> Bool {
        marked.isEmpty ? index == selection : marked.contains(clips[index].id)
    }

    /// The clips an action started on `clip` applies to, which is the whole selection when `clip` is part of it.
    func targets(for clip: Clip) -> [Clip] {
        let selected = selectedClips
        return selected.contains { $0.id == clip.id } ? selected : [clip]
    }

    func select(at index: Int) {
        marked = []
        selection = index
    }

    /// Command-click. Adds the clip to the selection, or takes it out when it is already there.
    func toggleMark(at index: Int) {
        guard clips.indices.contains(index) else { return }
        var ids = Set(selectedClips.map(\.id))
        let id = clips[index].id
        if ids.remove(id) == nil {
            ids.insert(id)
            selection = index
        } else if let remaining = clips.firstIndex(where: { ids.contains($0.id) }) {
            if !ids.contains(clips[selection].id) { selection = remaining }
        } else {
            // The last selected clip cannot be deselected, because the keyboard always needs a clip to act on.
            return
        }
        marked = ids.count > 1 ? ids : []
    }
}

@MainActor
struct ShelfActions {
    var paste: (Clip) -> Void = { _ in }
    var requestDirectPaste: () -> Void = {}
    var reload: () -> Void = {}
    var assign: ([Clip], _ categoryID: Int64?) -> Void = { _, _ in }
    var delete: ([Clip]) -> Void = { _ in }
    var beginNaming: (ShelfModel.Naming) -> Void = { _ in }
    var deleteCategory: (ClipCategory) -> Void = { _ in }
    var recolor: (ClipCategory, _ colorHex: String) -> Void = { _, _ in }
    var beginEditing: (Clip) -> Void = { _ in }
    var commitEdit: () -> Void = {}
    var cancelEdit: () -> Void = {}
    var setPinned: ([Clip], Bool) -> Void = { _, _ in }
}

enum CategoryPalette {
    static let colors: [(name: String, hex: String)] = [
        ("Red", "#F0605D"), ("Blue", "#4C8DF6"), ("Green", "#4CC764"),
        ("Orange", "#F5A623"), ("Purple", "#B46BE0"), ("Teal", "#3CC8C8"),
        ("Pink", "#F06FA8"), ("Yellow", "#E8C53A"), ("Grey", "#8E99A4"),
    ]

    @MainActor static func swatch(hex: String) -> NSImage {
        let image = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            NSColor(Color(hex: hex)).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}

struct ShelfView: View {
    private enum Field { case search, name, editor }

    @Bindable var model: ShelfModel
    let imageFiles: ImageFiles
    let actions: ShelfActions
    @FocusState private var focus: Field?
    @State private var dropTarget: ClipFilter?

    var body: some View {
        VStack(spacing: 0) {
            header
            if model.editing != nil {
                editor
            } else if let message = model.errorMessage {
                notice(message)
            } else if model.clips.isEmpty {
                notice(emptyMessage)
            } else {
                cards
            }
            if !model.canPasteDirectly {
                permissionBar
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VisualEffect())
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.14)))
        .environment(\.colorScheme, .dark)
        .onChange(of: model.query) { actions.reload() }
        .onChange(of: model.focusToken, initial: true) {
            focus = model.editing != nil ? .editor : model.naming != nil ? .name : .search
        }
    }

    private var emptyMessage: String {
        if !model.query.isEmpty { return "No clips match “\(model.query)”." }
        if model.filter != .all { return "Nothing saved here yet. Drag a clip onto this category, or select one and press ⌘S." }
        return "Nothing copied yet. Copy something and it shows up here."
    }

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search", text: $model.query)
                    .textFieldStyle(.plain).focused($focus, equals: .search)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 10).frame(width: 220, height: 30)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

            if model.naming != nil {
                namingField
            } else {
                chips
            }
            Spacer(minLength: 8)
            Text(model.marked.isEmpty
                 ? "⌘click to select more    drag onto a category or ⌘S to save    ⌘⌫ delete"
                 : "\(model.marked.count) selected    drag onto a category or ⌘S to save    ⌘⌫ delete")
                .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                chip(title: "Clipboard", color: nil, filter: .all)
                ForEach(model.categories) { category in
                    chip(title: category.name, color: Color(hex: category.colorHex), filter: .category(category.id))
                        .contextMenu {
                            Button("Rename…") { actions.beginNaming(.rename(category)) }
                            Menu("Colour") {
                                ForEach(CategoryPalette.colors, id: \.hex) { color in
                                    Button {
                                        actions.recolor(category, color.hex)
                                    } label: {
                                        // A menu draws symbols as one-colour templates, so the swatch is a real image.
                                        Label {
                                            Text(category.colorHex == color.hex ? "\(color.name) ✓" : color.name)
                                        } icon: {
                                            Image(nsImage: CategoryPalette.swatch(hex: color.hex))
                                        }
                                    }
                                }
                            }
                            Button("Delete category", role: .destructive) { actions.deleteCategory(category) }
                        }
                }
                Button { actions.beginNaming(.new(assignTo: [])) } label: {
                    Image(systemName: "plus").font(.system(size: 13, weight: .medium)).frame(width: 28, height: 28)
                }
                .buttonStyle(.plain).help("New category")
            }
        }
    }

    private func chip(title: String, color: Color?, filter: ClipFilter) -> some View {
        Button {
            model.filter = filter
            actions.reload()
        } label: {
            HStack(spacing: 6) {
                if let color {
                    Circle().fill(color).frame(width: 10, height: 10)
                } else {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 12))
                }
                Text(title).font(.system(size: 13, weight: .medium)).lineLimit(1)
            }
            .padding(.horizontal, 11).frame(height: 28)
            .background(model.filter == filter ? .white.opacity(0.15) : .clear, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.accentColor, lineWidth: dropTarget == filter ? 2 : 0))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onDrop(of: [.cpasteClip], isTargeted: Binding(
            get: { dropTarget == filter },
            set: { targeted in
                if targeted { dropTarget = filter } else if dropTarget == filter { dropTarget = nil }
            }
        )) { _ in
            guard let clip = model.draggedClip else { return false }
            model.draggedClip = nil
            switch filter {
            case .category(let id): actions.assign(model.targets(for: clip), id)
            case .all: actions.assign(model.targets(for: clip), nil)
            }
            return true
        }
    }

    private var namingField: some View {
        HStack(spacing: 8) {
            TextField("Category name", text: $model.nameDraft)
                .textFieldStyle(.plain).focused($focus, equals: .name)
                .font(.system(size: 13))
                .padding(.horizontal, 10).frame(width: 220, height: 30)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor))
            Text("↩ save    esc cancel").font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $model.editDraft)
                .font(.system(size: 13)).focused($focus, equals: .editor)
                .scrollContentBackground(.hidden).padding(8)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            HStack(spacing: 10) {
                if let error = model.editError {
                    Text(error).font(.system(size: 11)).foregroundStyle(.red)
                } else {
                    Text("⌘↩ save    esc cancel").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", action: actions.cancelEdit)
                Button("Save", action: actions.commitEdit).buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 14).padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var cards: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(Array(model.clips.enumerated()), id: \.element.id) { index, clip in
                        let category = model.categories.first { $0.id == clip.categoryID }
                        ClipCard(clip: clip, category: category, imageFiles: imageFiles, isSelected: model.isSelected(at: index))
                            .id(clip.id)
                            .onTapGesture {
                                if NSEvent.modifierFlags.contains(.command) { model.toggleMark(at: index) } else { model.select(at: index) }
                            }
                            // Simultaneous, because an exclusive double-click makes every single click wait out the double-click interval.
                            .simultaneousGesture(TapGesture(count: 2).onEnded {
                                if !NSEvent.modifierFlags.contains(.command) { actions.paste(clip) }
                            })
                            .contextMenu { cardMenu(for: clip) }
                            .onDrag {
                                model.draggedClip = clip
                                let provider = NSItemProvider()
                                provider.registerDataRepresentation(forTypeIdentifier: UTType.cpasteClip.identifier, visibility: .ownProcess) { completion in
                                    completion(Data("\(clip.id)".utf8), nil)
                                    return nil
                                }
                                return provider
                            }
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 14).padding(.top, 4)
            }
            .onChange(of: model.selection) { _, selection in
                guard model.clips.indices.contains(selection) else { return }
                withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(model.clips[selection].id, anchor: nil) }
            }
        }
    }

    @ViewBuilder private func cardMenu(for clip: Clip) -> some View {
        let targets = model.targets(for: clip)
        let many = targets.count > 1
        if !many {
            Button("Paste") { actions.paste(clip) }
            if clip.isEditable {
                Button("Edit…") { actions.beginEditing(clip) }
            }
        }
        Menu(many ? "Save \(targets.count) clips to" : "Save to") {
            ForEach(model.categories) { category in
                Button(category.name) { actions.assign(targets, category.id) }
            }
            Button("New category…") { actions.beginNaming(.new(assignTo: targets)) }
        }
        let allPinned = targets.allSatisfy(\.isPinned)
        Button(allPinned ? "Unpin" : "Pin to the front") { actions.setPinned(targets, !allPinned) }
        if targets.contains(where: { $0.categoryID != nil }) {
            Button("Remove from category") { actions.assign(targets, nil) }
        }
        Divider()
        Button(many ? "Delete \(targets.count) clips" : "Delete", role: .destructive) { actions.delete(targets) }
    }

    private func notice(_ text: String) -> some View {
        Text(text).font(.system(size: 13)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var permissionBar: some View {
        HStack(spacing: 10) {
            Text("Return copies the clip, then you press ⌘V. Allow Cpaste under Accessibility and Return pastes for you.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Button("Allow…", action: actions.requestDirectPaste).controlSize(.small)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.25))
    }
}

struct ClipCard: View {
    let clip: Clip
    let category: ClipCategory?
    let imageFiles: ImageFiles
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(kind.title).font(.system(size: 14, weight: .semibold))
                        if clip.isPinned {
                            Image(systemName: "pin.fill").font(.system(size: 10))
                        }
                    }
                    Text(clip.lastUsedAt, format: .relative(presentation: .named))
                        .font(.system(size: 11)).opacity(0.85)
                }
                Spacer()
                if let icon = SourceApp.icon(bundleID: clip.sourceBundleID) {
                    Image(nsImage: icon).resizable().frame(width: 30, height: 30)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12).frame(height: 46)
            .background(frameColor ?? SourceApp.color(bundleID: clip.sourceBundleID) ?? kind.color)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(12)

            HStack(spacing: 5) {
                if let category {
                    Circle().fill(Color(hex: category.colorHex)).frame(width: 7, height: 7)
                }
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity).padding(.horizontal, 10).padding(.bottom, 9)
        }
        .frame(width: 216, height: 208)
        .background(Color(white: 0.11))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isSelected ? Color.white : frameColor ?? .white.opacity(0.08),
                              lineWidth: isSelected ? 3 : frameColor == nil ? 1 : 2)
        )
    }

    /// A saved clip takes its category's colour for the header and the frame.
    private var frameColor: Color? {
        category.map { Color(hex: $0.colorHex) }
    }

    @ViewBuilder private var content: some View {
        switch clip.content {
        case .text(let string):
            Text(string.prefix(400)).font(.system(size: 13)).foregroundStyle(.primary)
        case .link(let url):
            Text(url.absoluteString).font(.system(size: 13)).foregroundStyle(.primary).underline()
        case .file(let path):
            Label((path as NSString).lastPathComponent, systemImage: "doc").font(.system(size: 13))
        case .image(let sha, _, _, _):
            if let image = Thumbnails.image(at: imageFiles.thumbnailURL(sha256: sha)) {
                Image(nsImage: image).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Label("Image file is missing", systemImage: "exclamationmark.triangle").font(.system(size: 12))
            }
        }
    }

    private var kind: (title: String, color: Color) {
        switch clip.content {
        case .text: ("Text", Color(red: 0.31, green: 0.47, blue: 0.85))
        case .link: ("Link", Color(red: 0.54, green: 0.39, blue: 0.82))
        case .image: ("Image", Color(red: 0.79, green: 0.34, blue: 0.49))
        case .file: ("File", Color(red: 0.25, green: 0.55, blue: 0.50))
        }
    }

    private var detail: String {
        switch clip.content {
        case .text(let string): "\(string.count) characters"
        case .link(let url): url.host ?? "link"
        case .file(let path): (path as NSString).deletingLastPathComponent
        case .image(_, let width, let height, _): "\(width) × \(height)"
        }
    }
}

@MainActor
enum SourceApp {
    private static var icons: [String: NSImage] = [:]

    static func icon(bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let cached = icons[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icons[bundleID] = icon
        return icon
    }

    private static var colors: [String: Color?] = [:]

    /// The header colour for clips copied from this app, taken from its icon.
    static func color(bundleID: String?) -> Color? {
        guard let bundleID else { return nil }
        if let cached = colors[bundleID] { return cached }
        let color = icon(bundleID: bundleID).flatMap(IconColor.dominant(of:)).map { Color(nsColor: $0) }
        colors[bundleID] = color
        return color
    }

    static func name(bundleID: String) -> String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { FileManager.default.displayName(atPath: $0.path) } ?? bundleID
    }
}

@MainActor
enum Thumbnails {
    private static let cache = NSCache<NSURL, NSImage>()

    /// Cached because a card redraws on every selection change, and reading the file each time stalls the shelf.
    static func image(at url: URL) -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        guard let image = NSImage(contentsOf: url) else { return nil }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}

struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

extension Clip {
    var isEditable: Bool {
        switch content {
        case .text, .link: true
        case .image, .file: false
        }
    }

    var editableText: String? {
        switch content {
        case .text(let string): string
        case .link(let url): url.absoluteString
        case .image, .file: nil
        }
    }
}

extension UTType {
    /// A clip dragged inside the shelf. Declared in Info.plist.
    static let cpasteClip = UTType(exportedAs: "local.cpaste.clip")
}

extension Color {
    /// A colour from "#RRGGBB". Anything else gives grey.
    init(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
            self = .gray
            return
        }
        self.init(red: Double(value >> 16 & 0xFF) / 255, green: Double(value >> 8 & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}
