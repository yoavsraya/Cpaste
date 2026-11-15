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
        case renameClip(Clip)

        var placeholder: String {
            switch self {
            case .new, .rename: "Category name"
            case .renameClip: "Clip name"
            }
        }
    }

    var clips: [Clip] = []
    var categories: [ClipCategory] = []
    var selection = 0
    /// Clips picked with Command-click. While it is empty, the clip at `selection` is the only selected one.
    var marked: Set<Int64> = []
    var query = ""
    var filter: ClipFilter = .all
    var cardSize: CardSize = .medium
    var position: ShelfPosition = .bottom

    var cardDimensions: CGSize {
        position == .bottom ? cardSize.card : cardSize.drawerCard
    }
    var kindFilter: ClipKind?
    var appFilter: String?
    var order: ClipOrder = .shelf
    /// Private categories the user has opened since the shelf appeared.
    var unlocked: Set<Int64> = []

    /// The private categories whose clips must not be shown.
    var lockedCategoryIDs: Set<Int64> {
        Set(categories.filter { $0.isPrivate && !unlocked.contains($0.id) }.map(\.id))
    }
    /// The apps offered in the filter menu.
    var sourceApps: [String] = []
    var naming: Naming?
    var nameDraft = ""
    /// What the edit box is open for. Nil while it is closed.
    var editor: Editor?

    enum Editor: Equatable {
        case editing(Clip)
        /// A new clip typed by hand.
        case composing
    }
    var editDraft = ""
    var editError: String?
    /// Shown after a delete, while it can still be undone.
    var undoHint: String?
    var canPasteDirectly = true
    var errorMessage: String?
    /// What is being dragged inside the shelf, read when it is dropped on a category.
    var dragged: Dragged?

    enum Dragged: Equatable {
        case clip(Clip)
        case category(ClipCategory)
    }
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
    var copy: (Clip) -> Void = { _ in }
    var open: (Clip) -> Void = { _ in }
    var requestDirectPaste: () -> Void = {}
    var reload: () -> Void = {}
    var assign: ([Clip], _ categoryID: Int64?) -> Void = { _, _ in }
    var delete: ([Clip]) -> Void = { _ in }
    var beginNaming: (ShelfModel.Naming) -> Void = { _ in }
    var deleteCategory: (ClipCategory) -> Void = { _ in }
    var recolor: (ClipCategory, _ colorHex: String) -> Void = { _, _ in }
    var setPrivate: (ClipCategory, Bool) -> Void = { _, _ in }
    /// Switches the shelf to a category, asking for Touch ID first when it is private and locked.
    var showFilter: (ClipFilter) -> Void = { _ in }
    var setIcon: (ClipCategory, _ icon: String?) -> Void = { _, _ in }
    var beginEditing: (Clip) -> Void = { _ in }
    var commitEdit: () -> Void = {}
    var cancelEdit: () -> Void = {}
    var compose: () -> Void = {}
    var setPinned: ([Clip], Bool) -> Void = { _, _ in }
    var moveCategory: (ClipCategory, _ toPlaceOf: Int64) -> Void = { _, _ in }
    var moveClip: (Clip, _ toPlaceOf: Clip) -> Void = { _, _ in }
    var merge: ([Clip]) -> Void = { _ in }
    var copyImageText: (Clip) -> Void = { _ in }
    /// Opens the large preview of the current selection.
    var showPreview: () -> Void = {}
}

enum CategoryIcons {
    static let all = ["⭐️", "❤️", "🔗", "💼", "🏠", "✈️", "🛒", "💳", "🔑", "📞", "✉️", "📝", "💡", "🎨", "🧑‍💻", "📚", "🎵", "🍽️"]
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
    @State private var cardDropTarget: Int64?

    var body: some View {
        VStack(spacing: 0) {
            if model.position == .bottom { header } else { drawerHeader }
            if model.editor != nil {
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
        .background(VisualEffect(material: .popover))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.primary.opacity(0.14)))
        .onChange(of: model.query) { actions.reload() }
        .onChange(of: model.focusToken, initial: true) {
            focus = model.editor != nil ? .editor : model.naming != nil ? .name : .search
        }
    }

    private var emptyMessage: String {
        if !model.query.isEmpty { return "No clips match “\(model.query)”." }
        if model.kindFilter != nil || model.appFilter != nil { return "No clips match this filter." }
        if model.filter != .all { return "Nothing saved here yet. Drag a clip onto this category, or select one and press ⌘S." }
        return "Nothing copied yet. Copy something and it shows up here."
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search", text: $model.query)
                .textFieldStyle(.plain).focused($focus, equals: .search)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 10).frame(height: 30)
        .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    /// The header of the side drawer, stacked because the drawer is too narrow for one row.
    private var drawerHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                searchField
                filterMenu
                composeButton
            }
            if model.naming != nil {
                namingField
            } else {
                chips
            }
            if let hint = model.undoHint {
                Text(hint).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)
    }

    private var header: some View {
        HStack(spacing: 10) {
            searchField.frame(width: 220)

            filterMenu
            composeButton

            if model.naming != nil {
                namingField
            } else {
                chips
            }
            Spacer(minLength: 8)
            Text(model.undoHint ?? (model.marked.isEmpty
                 ? "space preview    ⌘click select    ⌘S save    ⌘E edit    ⌘P pin    ⌘⌫ delete"
                 : "\(model.marked.count) selected    \(model.marked.count == 2 ? "space compare    " : "")⌘S save    ⌘J merge    ⌘⌫ delete"))
                .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 2)
    }

    private var composeButton: some View {
        Button(action: actions.compose) {
            Image(systemName: "square.and.pencil").font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary).frame(width: 26, height: 30).contentShape(Rectangle())
        }
        .buttonStyle(.plain).help("New clip (⌘N)")
    }

    private var filterMenu: some View {
        let isFiltering = model.kindFilter != nil || model.appFilter != nil || model.order != .shelf
        return Menu {
            Picker("Order", selection: $model.order) {
                Text("Newest first").tag(ClipOrder.shelf)
                Text("Most used first").tag(ClipOrder.mostUsed)
            }
            .pickerStyle(.inline)
            Picker("Type", selection: $model.kindFilter) {
                Text("All types").tag(ClipKind?.none)
                ForEach(ClipKind.allCases, id: \.self) { Text($0.filterTitle).tag(ClipKind?.some($0)) }
            }
            .pickerStyle(.inline)
            Picker("App", selection: $model.appFilter) {
                Text("All apps").tag(String?.none)
                ForEach(model.sourceApps, id: \.self) { Text(SourceApp.name(bundleID: $0)).tag(String?.some($0)) }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isFiltering ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                if isFiltering {
                    Text([model.order == .mostUsed ? "Most used" : nil, model.kindFilter?.filterTitle, model.appFilter.map(SourceApp.name(bundleID:))]
                        .compactMap { $0 }.joined(separator: " · "))
                        .lineLimit(1)
                }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isFiltering ? Color.accentColor : .secondary)
            .padding(.horizontal, 8).frame(height: 30)
            .contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .help("Show only one type of clip, or clips from one app")
        .onChange(of: model.kindFilter) { actions.reload() }
        .onChange(of: model.appFilter) { actions.reload() }
        .onChange(of: model.order) { actions.reload() }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                chip(title: "Clipboard", color: nil, filter: .all)
                ForEach(model.categories) { category in
                    chip(title: [category.icon, category.name].compactMap { $0 }.joined(separator: " "),
                         color: Color(hex: category.colorHex), filter: .category(category.id),
                         lock: !category.isPrivate ? nil : model.unlocked.contains(category.id) ? "lock.open.fill" : "lock.fill")
                        .onDrag {
                            model.dragged = .category(category)
                            return Self.dragProvider(id: category.id)
                        }
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
                            Button(category.isPrivate ? "Make Public…" : "Make Private") {
                                actions.setPrivate(category, !category.isPrivate)
                            }
                            Menu("Icon") {
                                Button("None") { actions.setIcon(category, nil) }
                                ForEach(CategoryIcons.all, id: \.self) { icon in
                                    Button(category.icon == icon ? "\(icon) ✓" : icon) { actions.setIcon(category, icon) }
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

    private func chip(title: String, color: Color?, filter: ClipFilter, lock: String? = nil) -> some View {
        HStack(spacing: 6) {
            if let color {
                Circle().fill(color).frame(width: 10, height: 10)
            } else {
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 12))
            }
            Text(title).font(.system(size: 13, weight: .medium)).lineLimit(1)
            if let lock {
                Image(systemName: lock).font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 11).frame(height: 28)
        .background(model.filter == filter ? Color.primary.opacity(0.15) : .clear, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.accentColor, lineWidth: dropTarget == filter ? 2 : 0))
        .contentShape(Capsule())
        // A tap gesture and not a Button, because a Button takes the mouse press and the chip could not be dragged.
        .onTapGesture { actions.showFilter(filter) }
        .onDrop(of: [.cpasteClip], isTargeted: Binding(
            get: { dropTarget == filter },
            set: { targeted in
                if targeted { dropTarget = filter } else if dropTarget == filter { dropTarget = nil }
            }
        )) { _ in
            defer { model.dragged = nil }
            switch (model.dragged, filter) {
            case (.clip(let clip), .category(let id)): actions.assign(model.targets(for: clip), id)
            case (.clip(let clip), .all): actions.assign(model.targets(for: clip), nil)
            case (.category(let category), .category(let id)): actions.moveCategory(category, id)
            case (.category, .all), (nil, _): return false
            }
            return true
        }
    }

    private var namingField: some View {
        HStack(spacing: 8) {
            TextField(model.naming?.placeholder ?? "", text: $model.nameDraft)
                .textFieldStyle(.plain).focused($focus, equals: .name)
                .font(.system(size: 13))
                .padding(.horizontal, 10).frame(width: 220, height: 30)
                .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor))
            if model.position == .bottom {
                Text("↩ save    esc cancel").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $model.editDraft)
                .font(.system(size: 13)).focused($focus, equals: .editor)
                .scrollContentBackground(.hidden).padding(8)
                .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            HStack(spacing: 10) {
                if let error = model.editError {
                    Text(error).font(.system(size: 11)).foregroundStyle(.red)
                } else {
                    Text(model.editor == .composing ? "Type a new clip    ⌘↩ save    esc cancel" : "⌘↩ save    esc cancel")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
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
            ScrollView(model.position == .bottom ? .horizontal : .vertical, showsIndicators: false) {
                Group {
                    if model.position == .bottom {
                        LazyHStack(spacing: 12) { cardList }
                    } else {
                        LazyVStack(spacing: 10) { cardList }
                    }
                }
                // Room above the cards, so the glow and the lift are not cut by the scroll edge.
                .padding(.horizontal, 16).padding(.bottom, 14).padding(.top, 10)
            }
            .onChange(of: model.selection) { _, selection in
                guard model.clips.indices.contains(selection) else { return }
                withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(model.clips[selection].id, anchor: nil) }
            }
        }
    }

    @ViewBuilder private var cardList: some View {
                    ForEach(Array(model.clips.enumerated()), id: \.element.id) { index, clip in
                        let category = model.categories.first { $0.id == clip.categoryID }
                        ClipCard(clip: clip, category: category, imageFiles: imageFiles, size: model.cardDimensions,
                                 isSelected: model.isSelected(at: index))
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
                                model.dragged = .clip(clip)
                                return dragProvider(for: clip)
                            }
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.accentColor, lineWidth: cardDropTarget == clip.id ? 3 : 0))
                            .onDrop(of: [.cpasteClip], isTargeted: Binding(
                                get: { cardDropTarget == clip.id },
                                set: { targeted in
                                    if targeted { cardDropTarget = clip.id } else if cardDropTarget == clip.id { cardDropTarget = nil }
                                }
                            )) { _ in
                                guard case .clip(let moved) = model.dragged, moved.id != clip.id else { return false }
                                model.dragged = nil
                                actions.moveClip(moved, clip)
                                return true
                            }
                    }
    }

    /// The dragged item itself travels in `model.dragged`, and the provider only marks the drag as one of ours.
    private static func dragProvider(id: Int64) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.cpasteClip.identifier, visibility: .ownProcess) { completion in
            completion(Data("\(id)".utf8), nil)
            return nil
        }
        return provider
    }

    /// A clip also carries its real content, so it can be dropped into another app.
    private func dragProvider(for clip: Clip) -> NSItemProvider {
        let provider = Self.dragProvider(id: clip.id)
        switch clip.content {
        case .text(let string):
            provider.registerObject(string as NSString, visibility: .all)
        case .link(let url):
            provider.registerObject(url as NSURL, visibility: .all)
            provider.registerObject(url.absoluteString as NSString, visibility: .all)
        case .file(let path):
            provider.registerObject(URL(fileURLWithPath: path) as NSURL, visibility: .all)
        case .image(let sha, _, _, _):
            let url = imageFiles.imageURL(sha256: sha)
            provider.suggestedName = clip.title ?? "Image"
            provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
                do {
                    completion(try Data(contentsOf: url), nil)
                } catch {
                    completion(nil, error)
                }
                return nil
            }
        }
        return provider
    }

    @ViewBuilder private func cardMenu(for clip: Clip) -> some View {
        let targets = model.targets(for: clip)
        let many = targets.count > 1
        if !many {
            Button("Paste") { actions.paste(clip) }
            Button("Copy") { actions.copy(clip) }
            Button("Preview") {
                // The preview shows the selection, which a right-click does not move.
                if let index = model.clips.firstIndex(where: { $0.id == clip.id }) { model.select(at: index) }
                actions.showPreview()
            }
            if let title = clip.openTitle {
                Button(title) { actions.open(clip) }
            }
            if !(clip.imageText ?? "").isEmpty {
                Button("Copy Text from Image") { actions.copyImageText(clip) }
            }
            Button("Rename…") { actions.beginNaming(.renameClip(clip)) }
            if clip.isEditable {
                Button("Edit…") { actions.beginEditing(clip) }
            }
        }
        if targets.count == 2, targets.allSatisfy({ $0.content.kind == .text }) {
            Button("Compare") { actions.showPreview() }
        }
        if targets.filter(\.isEditable).count > 1 {
            Button("Merge into One Clip") { actions.merge(targets) }
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
        .background(.primary.opacity(0.08))
    }
}

struct ClipCard: View {
    let clip: Clip
    let category: ClipCategory?
    let imageFiles: ImageFiles
    let size: CGSize
    let isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(clip.title ?? kind.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
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
            .background(headerColor)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if let detail {
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    .frame(maxWidth: .infinity).padding(.horizontal, 10).padding(.vertical, 7)
            }
        }
        .frame(width: size.width, height: size.height)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isSelected ? Color.primary.opacity(0.9) : frameColor ?? .primary.opacity(0.12),
                              lineWidth: isSelected || frameColor != nil ? 2 : 1)
        )
        // Drawn as one layer, or the border casts its own glow into the card.
        .compositingGroup()
        // The selected card glows in its own colour, and the card under the mouse rises off the shelf.
        .shadow(color: isSelected ? headerColor.opacity(0.8) : .black.opacity(isHovered ? 0.35 : 0),
                radius: isSelected ? 9 : 7, y: isSelected ? 0 : 5)
        .scaleEffect(isHovered ? 1.025 : 1)
        .offset(y: isHovered ? -2 : 0)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }

    /// A saved clip takes its category's colour for the header and the frame.
    private var frameColor: Color? {
        category.map { Color(hex: $0.colorHex) }
    }

    @ViewBuilder private var content: some View {
        switch clip.content {
        case .text(let string):
            switch flavor {
            case .color(let red, let green, let blue):
                // Black or white text, whichever reads on the swatch.
                let isLight = 0.299 * red + 0.587 * green + 0.114 * blue > 0.6
                Text(string.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(isLight ? Color.black : Color.white)
                    .padding(10).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .background(Color(red: red, green: green, blue: blue))
            case .code:
                Text(string.prefix(600)).font(.system(size: 11.5, design: .monospaced))
                    .padding(9).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                    .padding([.horizontal, .top], 10)
                    .overlay(alignment: .bottom) { fade(for: string, charactersPerLine: (size.width - 38) / 7, lineHeight: 14.5) }
            case .json(let pretty):
                Text(pretty.prefix(600)).font(.system(size: 11.5, design: .monospaced))
                    .padding(9).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                    .padding([.horizontal, .top], 10)
                    .overlay(alignment: .bottom) { fade(for: pretty, charactersPerLine: (size.width - 38) / 7, lineHeight: 14.5) }
            case .email:
                let address = string.trimmingCharacters(in: .whitespacesAndNewlines)
                let parts = address.split(separator: "@", maxSplits: 1)
                badge("envelope.fill", title: String(parts.first ?? ""), subtitle: parts.count > 1 ? "@\(parts[1])" : nil)
            case .phone:
                badge("phone.fill", title: string.trimmingCharacters(in: .whitespacesAndNewlines), subtitle: nil)
            case .date(let date):
                badge("calendar", title: date.formatted(date: .abbreviated, time: .omitted),
                      subtitle: date.formatted(.dateTime.weekday(.wide)) + (Calendar.current.component(.hour, from: date) == 12 && Calendar.current.component(.minute, from: date) == 0 ? "" : " · " + date.formatted(date: .omitted, time: .shortened)))
            case .address:
                badge("mappin.and.ellipse", title: string.trimmingCharacters(in: .whitespacesAndNewlines), subtitle: nil)
            case .plain:
                let isShort = string.count <= 40 && !string.contains(where: \.isNewline)
                Text(string.prefix(400)).font(.system(size: isShort ? 15 : 13, weight: isShort ? .medium : .regular))
                    .padding([.horizontal, .top], 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .overlay(alignment: .bottom) { fade(for: string, charactersPerLine: (size.width - 24) / 6.6, lineHeight: 16.5) }
            }
        case .link(let url):
            let host = url.host.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 } ?? url.absoluteString
            VStack(alignment: .leading, spacing: 3) {
                Text(host.prefix(1).uppercased()).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 26, height: 26).background(headerColor, in: Circle()).padding(.bottom, 6)
                let rest = url.path + (url.query.map { "?\($0)" } ?? "")
                if let title = clip.linkTitle {
                    Text(title).font(.system(size: 14, weight: .semibold)).lineLimit(3)
                    Text(host + (rest.count > 1 ? rest : "")).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Text(host).font(.system(size: 15, weight: .semibold)).lineLimit(2)
                    if rest.count > 1 {
                        Text(rest).font(.system(size: 11.5)).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
        case .file(let path):
            let info = FileInfo.of(path: path)
            VStack(spacing: 5) {
                Image(nsImage: info.icon).resizable().frame(width: 52, height: 52)
                Text((path as NSString).lastPathComponent).font(.system(size: 13, weight: .semibold))
                    .lineLimit(2).multilineTextAlignment(.center)
                Text(info.detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(10).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .image(let sha, _, _, _):
            if let image = Thumbnails.image(at: imageFiles.thumbnailURL(sha256: sha)) {
                // A clear overlay sized by the card, so a wide or tall picture is cropped and never stretches the card.
                Color.clear.overlay(Image(nsImage: image).resizable().scaledToFill()).clipped()
            } else {
                Label("Image file is missing", systemImage: "exclamationmark.triangle").font(.system(size: 12)).padding(12)
            }
        }
    }

    /// A round symbol with one strong line under it, for a clip that is a single known thing such as a phone number.
    private func badge(_ symbol: String, title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 26, height: 26).background(headerColor, in: Circle()).padding(.bottom, 6)
            Text(title).font(.system(size: 15, weight: .semibold)).lineLimit(3)
            if let subtitle {
                Text(subtitle).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(12)
    }

    /// A fade over the last lines of a text that does not fit, saying how much is hidden.
    @ViewBuilder private func fade(for text: String, charactersPerLine: CGFloat, lineHeight: CGFloat) -> some View {
        // An estimate from average character width. A real measurement would need a layout pass per card.
        let wrapped = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .reduce(0) { $0 + max(1, Int((CGFloat($1.count) / charactersPerLine).rounded(.up))) }
        let visible = Int((size.height - 46 - 28 - 12) / lineHeight)
        if wrapped > visible {
            let hidden = wrapped - visible
            Text("+ \(hidden) more \(hidden == 1 ? "line" : "lines")")
                .font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .bottom)
                .background(LinearGradient(colors: [.clear, Color(nsColor: .textBackgroundColor)],
                                           startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.7)))
        }
    }

    private var flavor: TextFlavor {
        if case .text(let string) = clip.content { TextFlavor(string) } else { .plain }
    }

    private var headerColor: Color {
        frameColor ?? SourceApp.color(bundleID: clip.sourceBundleID) ?? kind.color
    }

    private var kind: (title: String, color: Color) {
        switch (clip.content, flavor) {
        case (.text, let flavor): (flavor.title, Color(red: 0.31, green: 0.47, blue: 0.85))
        case (.link, _): ("Link", Color(red: 0.54, green: 0.39, blue: 0.82))
        case (.image, _): ("Image", Color(red: 0.79, green: 0.34, blue: 0.49))
        case (.file, _): ("File", Color(red: 0.25, green: 0.55, blue: 0.50))
        }
    }

    /// The grey line under the content, with the paste count once the clip has been used more than once.
    private var detail: String? {
        guard clip.useCount > 1 else { return contentDetail }
        return [contentDetail, "used \(clip.useCount)×"].compactMap { $0 }.joined(separator: " · ")
    }

    /// Nil when the content already says everything.
    private var contentDetail: String? {
        switch (clip.content, flavor) {
        case (.text, .color), (.text, .email), (.text, .phone), (.text, .address), (.link, _), (.file, _): return nil
        case (.text(let string), .date): return string.trimmingCharacters(in: .whitespacesAndNewlines)
        case (.text, .json(let string)), (.text(let string), .code):
            let lines = string.split(whereSeparator: \.isNewline).count
            return lines == 1 ? "1 line" : "\(lines) lines"
        case (.text(let string), .plain): return "\(string.count) characters"
        case (.image(_, let width, let height, _), _):
            let size = "\(width) × \(height)"
            let words = (clip.imageText ?? "").split(whereSeparator: \.isWhitespace).prefix(4).joined(separator: " ")
            return words.isEmpty ? size : "\(size) · “\(words)”"
        }
    }
}

/// The Finder icon, folder and size of a copied file, cached because cards redraw often.
@MainActor
enum FileInfo {
    private static var cache: [String: (icon: NSImage, detail: String)] = [:]

    static func of(path: String) -> (icon: NSImage, detail: String) {
        if let cached = cache[path] { return cached }
        let folder = ((path as NSString).deletingLastPathComponent as NSString).lastPathComponent
        let detail: String
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        if attributes == nil {
            detail = "\(folder) · file is gone"
        } else if attributes?[.type] as? FileAttributeType == .typeRegular, let bytes = attributes?[.size] as? Int64 {
            detail = "\(folder) · \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))"
        } else {
            // A folder or an app reports the size of its directory entry, which means nothing to the user.
            detail = folder
        }
        let info = (icon: NSWorkspace.shared.icon(forFile: path), detail: detail)
        cache[path] = info
        return info
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
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

extension TextFlavor {
    var title: String {
        switch self {
        case .plain: "Text"
        case .color: "Colour"
        case .code: "Code"
        case .json: "JSON"
        case .email: "Email"
        case .phone: "Phone"
        case .date: "Date"
        case .address: "Address"
        }
    }
}

extension ClipKind {
    var filterTitle: String {
        switch self {
        case .text: "Text"
        case .link: "Links"
        case .image: "Images"
        case .file: "Files"
        }
    }
}

extension Clip {
    var isEditable: Bool {
        switch content {
        case .text, .link: true
        case .image, .file: false
        }
    }

    /// The menu title for opening the clip outside Cpaste. Plain text has nothing to open.
    var openTitle: String? {
        switch content {
        case .text: nil
        case .link: "Open Link"
        case .file: "Show in Finder"
        case .image: "Open Image"
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
    /// A clip or a category dragged inside the shelf. Declared in Info.plist.
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
