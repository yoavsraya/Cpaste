import AppKit
import CpasteCore
import Observation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class ShelfModel {
    enum Naming: Equatable {
        case new(assignTo: Clip?)
        case rename(ClipCategory)
    }

    var clips: [Clip] = []
    var categories: [ClipCategory] = []
    var selection = 0
    var query = ""
    var filter: ClipFilter = .all
    var naming: Naming?
    var nameDraft = ""
    var canPasteDirectly = true
    var errorMessage: String?
    /// The clip being dragged inside the shelf, read when it is dropped on a category.
    var draggedClip: Clip?
    /// Bumped whenever keyboard focus should return to the text field in use.
    var focusToken = 0
}

@MainActor
struct ShelfActions {
    var paste: (Clip) -> Void = { _ in }
    var requestDirectPaste: () -> Void = {}
    var reload: () -> Void = {}
    var assign: (Clip, _ categoryID: Int64?) -> Void = { _, _ in }
    var delete: (Clip) -> Void = { _ in }
    var beginNaming: (ShelfModel.Naming) -> Void = { _ in }
    var deleteCategory: (ClipCategory) -> Void = { _ in }
    var recolor: (ClipCategory, _ colorHex: String) -> Void = { _, _ in }
}

enum CategoryPalette {
    static let colors: [(name: String, hex: String)] = [
        ("Red", "#F0605D"), ("Blue", "#4C8DF6"), ("Green", "#4CC764"),
        ("Orange", "#F5A623"), ("Purple", "#B46BE0"), ("Teal", "#3CC8C8"),
        ("Pink", "#F06FA8"), ("Yellow", "#E8C53A"), ("Grey", "#8E99A4"),
    ]
}

struct ShelfView: View {
    private enum Field { case search, name }

    @Bindable var model: ShelfModel
    let imageFiles: ImageFiles
    let actions: ShelfActions
    @FocusState private var focus: Field?
    @State private var dropTarget: ClipFilter?

    var body: some View {
        VStack(spacing: 0) {
            header
            if let message = model.errorMessage {
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
        .onChange(of: model.focusToken, initial: true) { focus = model.naming == nil ? .search : .name }
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
            Text("drag onto a category or ⌘S to save    ⌘⌫ delete    ⇥ next category")
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
                                        Label(color.name, systemImage: category.colorHex == color.hex ? "checkmark" : "circle.fill")
                                    }
                                }
                            }
                            Button("Delete category", role: .destructive) { actions.deleteCategory(category) }
                        }
                }
                Button { actions.beginNaming(.new(assignTo: nil)) } label: {
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
            case .category(let id): actions.assign(clip, id)
            case .all: actions.assign(clip, nil)
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

    private var cards: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(Array(model.clips.enumerated()), id: \.element.id) { index, clip in
                        let category = model.categories.first { $0.id == clip.categoryID }
                        ClipCard(clip: clip, category: category, imageFiles: imageFiles, isSelected: index == model.selection)
                            .id(clip.id)
                            .onTapGesture(count: 2) { actions.paste(clip) }
                            .onTapGesture { model.selection = index }
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
        Button("Paste") { actions.paste(clip) }
        Menu("Save to") {
            ForEach(model.categories) { category in
                Button(category.name) { actions.assign(clip, category.id) }
            }
            Button("New category…") { actions.beginNaming(.new(assignTo: clip)) }
        }
        if clip.categoryID != nil {
            Button("Remove from category") { actions.assign(clip, nil) }
        }
        Divider()
        Button("Delete", role: .destructive) { actions.delete(clip) }
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
                    Text(kind.title).font(.system(size: 14, weight: .semibold))
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
            .background(frameColor ?? kind.color)

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
            if let image = NSImage(contentsOf: imageFiles.thumbnailURL(sha256: sha)) {
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

    static func name(bundleID: String) -> String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { FileManager.default.displayName(atPath: $0.path) } ?? bundleID
    }
}

struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
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
