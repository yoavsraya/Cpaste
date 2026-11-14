import AppKit
import Carbon.HIToolbox
import CpasteCore
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var settings: AppSettings
    /// Turns the global shortcut off while a new one is being typed, and back on afterwards. Returns false if the system refused it.
    let setShortcutActive: (Bool) -> Bool
    let onRetentionChange: () -> Void

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            shortcuts.tabItem { Label("Shortcuts", systemImage: "keyboard") }
            ignoredApps.tabItem { Label("Ignored apps", systemImage: "eye.slash") }
        }
        .frame(width: 520, height: 440)
    }

    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    private var general: some View {
        Form {
            Toggle("Open Cpaste at login", isOn: $opensAtLogin)
                .onChange(of: opensAtLogin) { _, enabled in
                    do {
                        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        loginError = nil
                    } catch {
                        loginError = "macOS did not change the login setting. \(error.localizedDescription)"
                    }
                }
            if let loginError {
                Text(loginError).font(.footnote).foregroundStyle(.red)
            }
            Picker("Keep history for", selection: $settings.retention) {
                ForEach(Retention.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .onChange(of: settings.retention) { onRetentionChange() }
            Text("Older clips are deleted, with their images. A shorter setting deletes right away and cannot be undone.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private var shortcuts: some View {
        Form {
            Section("Everywhere") {
                LabeledContent("Open Cpaste") {
                    ShortcutRecorder(shortcut: $settings.openShortcut, setShortcutActive: setShortcutActive)
                }
            }
            Section("While the shelf is open") {
                LabeledContent("Move between clips", value: "←  →")
                LabeledContent("Paste the selected clip", value: "↩")
                LabeledContent("Paste by position", value: "⌘2 – ⌘9")
                LabeledContent("Next or previous category", value: "⇥   ⇧⇥")
                LabeledContent("Select several clips", value: "⌘click")
                LabeledContent("Save the selected clips to a category", value: "⌘S, or drag them onto the category")
                LabeledContent("Delete the selected clips", value: "⌘⌫")
                LabeledContent("Clear the search", value: "esc")
                LabeledContent("Close", value: "esc")
            }
        }
        .formStyle(.grouped)
    }

    private var ignoredApps: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Copies made while one of these apps is in front are not recorded.")
                .font(.callout).foregroundStyle(.secondary)
            List {
                ForEach(settings.ignoredBundleIDs, id: \.self) { bundleID in
                    HStack {
                        if let icon = SourceApp.icon(bundleID: bundleID) {
                            Image(nsImage: icon).resizable().frame(width: 22, height: 22)
                        }
                        Text(SourceApp.name(bundleID: bundleID))
                        Spacer()
                        Button("Remove") { settings.ignoredBundleIDs.removeAll { $0 == bundleID } }
                            .controlSize(.small)
                    }
                }
            }
            .listStyle(.bordered)
            Button("Add app…", action: addApp)
        }
        .padding(20)
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

private struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut
    let setShortcutActive: (Bool) -> Bool
    @State private var isRecording = false
    @State private var wasRefused = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            if wasRefused {
                Text("macOS refused this shortcut").font(.footnote).foregroundStyle(.red)
            }
            Button(isRecording ? "Type the new shortcut, esc to cancel" : shortcut.display) {
                isRecording ? stop() : start()
            }
        }
        .onDisappear { if isRecording { stop() } }
    }

    private func start() {
        isRecording = true
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
        wasRefused = !setShortcutActive(true)
    }
}
