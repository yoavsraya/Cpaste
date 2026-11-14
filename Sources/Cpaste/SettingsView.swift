import AppKit
import Carbon.HIToolbox
import CpasteCore
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct SettingsActions {
    /// Turns the global shortcut off while a new one is being typed, and back on afterwards. Returns false if the system refused it.
    var setShortcutActive: (Bool) -> Bool = { _ in true }
    var retentionChanged: () -> Void = {}
    var eraseHistory: () -> Void = {}
    /// A line such as "214 clips, 38 MB on disk", or nil when the store cannot be read.
    var usageSummary: () -> String? = { nil }
    /// Each asks for a file, does the work, and returns a line to show, or nil when the user cancelled.
    var exportCategories: () -> String? = { nil }
    var importCategories: () -> String? = { nil }
    /// Nil in builds that cannot update themselves.
    var updater: UpdaterController?
}

struct SettingsView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case general, privacy, shortcuts

        var id: Self { self }

        var title: String {
            switch self {
            case .general: "General"
            case .privacy: "Privacy"
            case .shortcuts: "Shortcuts"
            }
        }

        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .privacy: "hand.raised"
            case .shortcuts: "keyboard"
            }
        }
    }

    @Bindable var settings: AppSettings
    let actions: SettingsActions
    @State var pane: Pane = .general

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                Text(pane.title).font(.title2.weight(.semibold))
                    .padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 2)
                switch pane {
                case .general: GeneralPane(settings: settings, actions: actions)
                case .privacy: PrivacyPane(settings: settings)
                case .shortcuts: ShortcutsPane(settings: settings, actions: actions)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 760, height: 640)
        .ignoresSafeArea()
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Pane.allCases) { item in
                Button { pane = item } label: {
                    Label(item.title, systemImage: item.symbol)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(pane == item ? .white : .primary)
                        .padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                        .background(pane == item ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            Spacer()
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Cpaste").font(.system(size: 13, weight: .semibold))
                    Text("Version \(Self.version)").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 6)
        }
        // The top padding clears the window's close button.
        .padding(.horizontal, 12).padding(.top, 52).padding(.bottom, 16)
        .frame(width: 200)
        .background(VisualEffect(material: .sidebar))
    }

    fileprivate static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}

private struct Caption: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

private struct GeneralPane: View {
    @Bindable var settings: AppSettings
    let actions: SettingsActions
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var canPasteDirectly = Paster.canPasteDirectly
    @State private var isConfirmingErase = false
    @State private var usage: String?
    @State private var checksForUpdates = false
    @State private var transferResult: String?

    var body: some View {
        Form {
            if let updater = actions.updater {
                Section {
                    Toggle(isOn: $checksForUpdates) {
                        Text("Check for updates automatically")
                        Caption("Once a day, Cpaste asks GitHub whether a newer version exists. Nothing about you or your clips is sent.")
                    }
                    .onChange(of: checksForUpdates) { _, enabled in updater.checksAutomatically = enabled }
                    LabeledContent("Version \(SettingsView.version)") {
                        Button("Check Now", action: updater.checkForUpdates)
                    }
                }
            }
            Section {
                Toggle("Open at login", isOn: $opensAtLogin)
                    .onChange(of: opensAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch {
                            loginError = "macOS did not change the login setting. \(error.localizedDescription)"
                        }
                    }
                if let loginError {
                    Text(loginError).font(.callout).foregroundStyle(.red)
                }
            }
            Section("Shelf") {
                Picker("Position", selection: $settings.shelfPosition) {
                    ForEach(ShelfPosition.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Picker("Card size", selection: $settings.cardSize) {
                    ForEach(CardSize.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section("Paste items") {
                target(.activeApp, title: "To active app",
                       caption: "Return pastes the selected clip straight into the app you are using.")
                target(.clipboard, title: "To clipboard",
                       caption: "Return copies the selected clip, and you paste it yourself with ⌘V.")
                if settings.pasteTarget == .activeApp, !canPasteDirectly {
                    HStack {
                        Label("Cpaste needs the Accessibility permission to paste for you.", systemImage: "exclamationmark.triangle")
                            .font(.callout).foregroundStyle(.orange)
                        Spacer()
                        Button("Allow…", action: Paster.requestDirectPaste)
                    }
                }
            }
            Section("Keep history") {
                Picker("Keep history", selection: $settings.retention) {
                    ForEach(Retention.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
                .onChange(of: settings.retention) { actions.retentionChanged() }
                if let usage {
                    LabeledContent("History size", value: usage)
                }
                HStack(alignment: .firstTextBaseline) {
                    Caption("Older clips are deleted, with their images. Pinned clips and clips in a category are kept forever.")
                    Spacer()
                    Button("Erase History…") { isConfirmingErase = true }
                }
            }
            Section("Categories") {
                HStack {
                    Caption(transferResult ?? "Save every category and its clips to one file, to move them to another Mac or share them.")
                    Spacer()
                    Button("Export…") { transferResult = actions.exportCategories() ?? transferResult }
                    Button("Import…") {
                        transferResult = actions.importCategories() ?? transferResult
                        usage = actions.usageSummary()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            usage = actions.usageSummary()
            checksForUpdates = actions.updater?.checksAutomatically ?? false
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            canPasteDirectly = Paster.canPasteDirectly
            usage = actions.usageSummary()
        }
        .confirmationDialog("Erase the clipboard history?", isPresented: $isConfirmingErase) {
            Button("Erase History", role: .destructive) {
                actions.eraseHistory()
                usage = actions.usageSummary()
            }
        } message: {
            Text("Every clip that is not pinned or in a category is deleted, with its image. This cannot be undone.")
        }
    }

    private func target(_ target: PasteTarget, title: String, caption: String) -> some View {
        Button { settings.pasteTarget = target } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: settings.pasteTarget == target ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(settings.pasteTarget == target ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Caption(caption)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct PrivacyPane: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settings.showsDuringScreenSharing) {
                    Text("Show during screen sharing")
                    Caption("When this is off, the shelf is left out of screen shares, recordings and screenshots.")
                }
            }
            Section {
                Label {
                    Text("Passwords are never saved")
                    Caption("Cpaste skips anything a password manager marks as confidential or temporary.")
                } icon: {
                    Image(systemName: "lock.shield").foregroundStyle(.green)
                }
            }
            Section {
                ForEach(settings.ignoredBundleIDs, id: \.self) { bundleID in
                    HStack(spacing: 10) {
                        if let icon = SourceApp.icon(bundleID: bundleID) {
                            Image(nsImage: icon).resizable().frame(width: 26, height: 26)
                        } else {
                            Image(systemName: "app.dashed").font(.system(size: 20)).frame(width: 26, height: 26)
                        }
                        Text(SourceApp.name(bundleID: bundleID))
                        Spacer()
                        Button {
                            settings.ignoredBundleIDs.removeAll { $0 == bundleID }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless).help("Stop ignoring this app")
                    }
                }
                Button("Add app…", action: addApp)
            } header: {
                Text("Ignored applications")
            } footer: {
                Caption("Copies made while one of these apps is in front are not saved.")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for bundleID in panel.urls.compactMap({ Bundle(url: $0)?.bundleIdentifier })
        where !settings.ignoredBundleIDs.contains(bundleID) {
            settings.ignoredBundleIDs.append(bundleID)
        }
    }
}

private struct ShortcutsPane: View {
    @Bindable var settings: AppSettings
    let actions: SettingsActions
    @State private var isConfirmingReset = false

    var body: some View {
        Form {
            Section {
                recorder("Open Cpaste", $settings.openShortcut, reportsRefusal: true)
            }
            Section {
                recorder("Show next category", $settings.nextCategoryShortcut)
                recorder("Show previous category", $settings.previousCategoryShortcut)
            }
            Section {
                LabeledContent("Quick paste") {
                    HStack(spacing: 6) {
                        Picker("Quick paste key", selection: $settings.quickPasteModifier) {
                            ForEach(QuickPasteModifier.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        .labelsHidden().fixedSize()
                        Text("+ 1…9").foregroundStyle(.secondary)
                    }
                }
                if settings.openShortcut.display.hasPrefix(settings.quickPasteModifier.symbol),
                   settings.openShortcut.display.count == 2, Int(settings.openShortcut.keyLabel) != nil {
                    Caption("\(settings.openShortcut.display) opens and closes Cpaste, so it cannot also paste clip \(settings.openShortcut.keyLabel).")
                }
            }
            Section("In the shelf") {
                LabeledContent("Move between clips", value: "←  →")
                LabeledContent("Paste the selected clip", value: "↩")
                LabeledContent("Select several clips", value: "⌘click")
                LabeledContent("Save to a category", value: "⌘S, or drag onto it")
                LabeledContent("Copy without pasting", value: "⌘C")
                LabeledContent("Open a link, file or image", value: "⌘O")
                LabeledContent("Rename a clip", value: "⌘R")
                LabeledContent("Edit the text of a clip", value: "⌘E")
                LabeledContent("Pin or unpin", value: "⌘P")
                LabeledContent("Merge the selected clips into one", value: "⌘J")
                LabeledContent("Copy the text in an image", value: "⇧⌘C")
                LabeledContent("Delete", value: "⌘⌫")
                LabeledContent("Undo a delete", value: "⌘Z")
                LabeledContent("Next category", value: "⇥")
                LabeledContent("Clear the search, then close", value: "esc")
            }
            Section {
                HStack {
                    Spacer()
                    Button("Reset shortcuts to default…") { isConfirmingReset = true }
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Reset all shortcuts to their defaults?", isPresented: $isConfirmingReset) {
            Button("Reset Shortcuts") {
                settings.resetShortcuts()
                _ = actions.setShortcutActive(true)
            }
        }
    }

    private func recorder(_ title: String, _ shortcut: Binding<Shortcut>, reportsRefusal: Bool = false) -> some View {
        LabeledContent(title) {
            ShortcutRecorder(shortcut: shortcut, setShortcutActive: actions.setShortcutActive, reportsRefusal: reportsRefusal)
        }
    }
}

private struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut
    let setShortcutActive: (Bool) -> Bool
    /// Only the global shortcut can be refused by macOS.
    let reportsRefusal: Bool
    @State private var isRecording = false
    @State private var wasRefused = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            if wasRefused {
                Text("macOS refused this shortcut").font(.callout).foregroundStyle(.red)
            }
            Button { isRecording ? stop() : start() } label: {
                Text(isRecording ? "Type shortcut, esc cancels" : shortcut.display)
                    .font(.system(size: 13, weight: .medium, design: isRecording ? .default : .rounded))
                    .frame(minWidth: 96)
            }
        }
        .onDisappear { if isRecording { stop() } }
    }

    private func start() {
        isRecording = true
        // The global shortcut is off while recording, so pressing it lands here and not in the shelf.
        _ = setShortcutActive(false)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if Int(event.keyCode) == kVK_Escape {
                stop()
            } else if let recorded = Shortcut(event: event) {
                shortcut = recorded
                stop()
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        let registered = setShortcutActive(true)
        wasRefused = reportsRefusal && !registered
    }
}
