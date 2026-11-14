# Cpaste design

Cpaste is a Mac-only clipboard manager for one person. It records every copy, text and images, and lets you search, file clips into categories, and paste from a panel that opens on Cmd+1. It replaces a paid subscription to Paste. It runs on one Mac with no account, no server, and no network access.

UI options for the panel are in `ui-options.html` next to this file, published at https://claude.ai/artifact/3DdARfiaNCMWEB1QrsKgrw. The panel uses the bottom shelf layout, option A.

## What the app does

- Records each new clipboard item with the app it came from and the time.
- Handles plain text, links, images, and copied files. A link is text that parses as a URL. A copied file is stored as its path.
- Opens a floating panel on Cmd+1 over the current app. The shortcut is configurable.
- Left and right arrows move the selection. Return pastes the selected clip into the app you came from. Cmd+2 to Cmd+9 paste by position while the panel is open. Cmd+1 closes it.
- Cmd+click adds a clip to the selection or takes it out. Save, drag to a category, and delete act on every selected clip. Return still pastes one clip.
- Typing filters clips by their text. A clip matches when it has a word starting with each word typed. Images match the word "image".
- Categories hold saved clips. Dragging a clip onto a category saves it there, and so does Cmd+S. Dragging it onto Clipboard returns it to history. A saved clip is drawn with its header and frame in the category colour, and the colour is chosen from a fixed list. An unsaved clip takes its header colour from the icon of the app it was copied from, and falls back to a colour per clip type when the icon is grey. A clip belongs to at most one category.
- Unsaved history expires after 30 days by default. Saved clips never expire.
- Copying something already in history moves the existing clip to the top instead of adding a duplicate.
- Skips items that password managers mark as concealed or transient (`org.nspasteboard.ConcealedType`, `org.nspasteboard.TransientType`).
- Settings choose whether Return pastes into the active app or only copies, whether the shelf shows in screen shares, the shortcuts for the next and previous category, and the key for paste by position. Erase History deletes every unsaved clip.
- Cmd+E opens the text of a text or link clip in an edit box. An edit that matches another clip is refused.
- Clips sort by a manual position, which a new copy or a paste sets to the front. Dragging a clip onto another moves it there, and into or out of the pinned group.
- A pinned clip sorts first and never expires. Categories are reordered by dragging one onto another.
- Text inside image clips is read on the Mac with Apple's Vision framework and added to the search index. Hebrew is not supported by Vision.
- A filter menu narrows the shelf to one clip type or one source app.
- Lives in the menu bar with no Dock icon. Starts at login when the setting is on.

## What it leaves out

- iPhone app and any sync between devices.
- Rich text fidelity. A copy from a styled document pastes back as plain text in version 1.
- Paste stack, shared pinboards, and text transformations.

## Storage

No server. The app does need local storage, because history must survive a restart. That storage is one SQLite file plus a folder of images, both under `~/Library/Application Support/Cpaste/`. SQLite is a library inside the app, so nothing is installed or run separately.

- `cpaste.sqlite` holds clips and categories. An FTS5 index over clip text serves search.
- `images/<sha256>.png` holds each image at full size. `thumbs/<sha256>.jpg` holds a thumbnail no larger than 400 px.
- Deleting the folder resets the app. Copying the folder to another Mac moves the history.

### Data shape

```swift
enum ClipContent {
    case text(String)
    case link(URL)
    case image(sha256: String, pixelWidth: Int, pixelHeight: Int, byteCount: Int)
    case file(path: String)
}

struct Clip {
    let id: Int64
    let content: ClipContent
    let contentHash: String        // dedupe key, unique
    let sourceBundleID: String?    // "com.google.Chrome"
    let copiedAt: Date
    var lastUsedAt: Date           // sort key, bumped on recopy and on paste
    var categoryID: Int64?         // nil means unsaved history
}

struct ClipCategory {     // `Category` collides with an Objective-C runtime type
    let id: Int64
    var name: String               // "Useful Links", "מספרים חשובים", "Work"
    var colorHex: String
    var position: Int
}
```

The enum makes a clip with both text and an image unrepresentable. The unique `contentHash` makes the capture step idempotent, so a crash and restart cannot create duplicates.

## Components

| Component | Job | Depends on |
|---|---|---|
| `PasteboardMonitor` | Polls `NSPasteboard.general.changeCount` every 300 ms and emits a `ClipContent` for each change. Ignores the app's own writes. | AppKit |
| `ClipStore` | Insert with dedupe, search, list by category, save to category, expire old history. | GRDB, SQLite |
| `ImageFiles` | Writes the PNG and the thumbnail, deletes them when the clip expires. | Filesystem |
| `HotKey` | Registers the global shortcut. | Carbon `RegisterEventHotKey` |
| `PanelController` | Shows a non-activating `NSPanel`, so the previous app keeps keyboard focus for the paste. | AppKit |
| `PanelView` | The chosen layout, drawn in SwiftUI from a list of clips. | `ClipStore` |
| `Paster` | Puts the clip on the clipboard and posts Cmd+V to the previous app. | Accessibility permission |
| `SettingsView` | Shortcut, history length, launch at login, ignored apps. | `SMAppService` |

`ClipStore` and the content classifier are pure and take no AppKit types, so unit tests cover them without a running app.

## Permissions

- **Accessibility.** Posting Cmd+V into another app needs it. Without it the app still puts the clip on the clipboard and tells the user to press Cmd+V.
- **Clipboard reading.** macOS 26 has a per-app setting for reading the clipboard without a user paste action. Phase 1 of the plan confirms the built app can read in the background.

## Sharing it with a friend

The app is a single `Cpaste.app` in a zip. Two facts shape this.

- Without a paid Apple Developer ID (99 USD per year) the app cannot be notarized. A friend's Mac blocks the first launch, and they approve it once under System Settings, Privacy & Security, Open Anyway.
- The app is signed with a self-signed certificate that stays the same across builds. macOS ties the Accessibility grant to the signature, so a stable signature keeps the grant after an update. This is inferred from how the permission system identifies apps and is checked in phase 5.

## Facts measured on this Mac

Measured on macOS 26.5.1 with Swift 6.3.3, from a command-line probe in the session scratchpad.

- Reading `NSPasteboard.general` returned its types and content in 0.4 ms with no prompt. The clipboard held an image in both PNG and TIFF form.
- `RegisterEventHotKey` for Cmd+1 returned status 0, which is success.
- `AXIsProcessTrusted()` returned false, so the Accessibility grant is a real first-run step.
- `swift test` failed with `no such module 'Testing'` and `xcodebuild` is absent. Only the Command Line Tools are installed. Full Xcode is required.

## Panel layout

The panel is the bottom shelf, option A in `ui-options.html`. It spans the bottom of the screen with the search field and categories on top and a horizontal row of cards below. Left and right arrows move the selection. Chosen on 2026-11-14 over the side drawer (C) because cards show more text and larger image thumbnails, and it matches the existing Cmd+1 habit. `PanelView` is the only component a different layout would change.
