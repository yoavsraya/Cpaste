import AppKit
import SwiftUI

/// Shown once, on the first launch, to explain the shortcut and the one permission Cpaste asks for.
struct WelcomeView: View {
    let openShortcut: String
    let close: () -> Void
    @State private var canPasteDirectly = Paster.canPasteDirectly

    var body: some View {
        VStack(spacing: 22) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 84, height: 84)
            VStack(spacing: 6) {
                Text("Welcome to Cpaste").font(.system(size: 24, weight: .semibold))
                Text("Everything you copy is kept on this Mac, ready to paste again.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 16) {
                step("keyboard", "Press \(openShortcut) anywhere",
                     "The shelf opens with your recent copies. Use the arrow keys and press Return to paste.")
                step("folder", "Keep clips in categories",
                     "Drag a clip onto a category and it is never deleted. Everything else is cleared after a month.")
                step("menubar.rectangle", "Cpaste lives in the menu bar",
                     "Click its icon for Settings, where you can change the shortcut and choose apps to ignore.")
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: canPasteDirectly ? "checkmark.circle.fill" : "hand.raised")
                        .font(.system(size: 20)).frame(width: 28)
                        .foregroundStyle(canPasteDirectly ? Color.green : Color.accentColor)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(canPasteDirectly ? "Cpaste can paste for you" : "Let Cpaste paste for you")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Pasting into other apps needs the Accessibility permission. Without it, Return copies the clip and you press ⌘V.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        if !canPasteDirectly {
                            Button("Allow in System Settings…", action: Paster.requestDirectPaste).padding(.top, 4)
                        }
                    }
                }
            }
            Button(action: close) {
                Text("Start using Cpaste").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 36).padding(.top, 44).padding(.bottom, 28)
        .frame(width: 480)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            canPasteDirectly = Paster.canPasteDirectly
        }
    }

    private func step(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 20)).frame(width: 28).foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
