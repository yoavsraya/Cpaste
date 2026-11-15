<img src="Resources/Icons/cpaste-app-icon.png" width="96" alt="Cpaste icon">

# Cpaste

Cpaste remembers everything you copy on your Mac, so you can paste it again later.

Press **Cmd+1** and a shelf slides up with your recent copies, text and images. Pick one and press Return to paste it.

![Cpaste in use: moving between clips, searching, opening a category, selecting several clips and typing a new one](docs/demo.gif)

- It is free.
- Everything stays on your Mac. Cpaste has no account. The only time it goes online is to ask GitHub whether a newer version exists, and you can turn that off.
- It works on macOS 14 or later.

## Install

1. Open the [Releases page](https://github.com/yoavsraya/Cpaste/releases/latest) and download `Cpaste.zip`.
2. Double-click the zip. You get `Cpaste.app`.
3. Drag `Cpaste.app` into your **Applications** folder.
4. Double-click Cpaste to open it. macOS shows a warning and refuses, because the app does not come from the App Store. This is expected.
5. Open **System Settings**, then **Privacy & Security**. Scroll down until you see a line about Cpaste, and click **Open Anyway**. You only do this once.
6. Look at the top right of your screen. A small clipboard icon is now in the menu bar. That is Cpaste. It has no icon in the Dock.

## One more step, so Cpaste can paste for you

1. Press **Cmd+1**. The shelf opens.
2. Click **Allow…** at the bottom of the shelf.
3. macOS opens the **Accessibility** settings. Turn the switch next to Cpaste on.

If you skip this, Cpaste still works. Pressing Return then copies the clip, and you press Cmd+V yourself.

## How to use it

Copy things the way you always do. Cpaste records them in the background.

| You want to | Do this |
|---|---|
| Open or close the shelf | **Cmd+1** |
| Move between clips | **Left** and **Right** arrows |
| Paste the selected clip | **Return**, or double-click it |
| Paste the 2nd to 9th clip directly | **Cmd+2** to **Cmd+9** |
| Find an old clip | Just start typing |
| Find a screenshot | Type `image` |
| Copy a clip without pasting it | **Cmd+C** |
| Open a link, show a file in Finder, or open an image | **Cmd+O** |
| Use a clip in another app | Drag its card out of the shelf |
| Type a new clip by hand | **Cmd+N**, the pencil button, or **New Clip…** in the menu-bar menu |
| Give a clip a name | **Cmd+R**, or right-click and choose **Rename…** |
| Edit the text of a clip | **Cmd+E**, then **Cmd+Return** to save |
| Pin a clip to the front | **Cmd+P** |
| Show only one type, or one app, or your most used clips | The filter button next to the search field |
| Find a screenshot by its text | Type a word that appears in it |
| Select several clips | **Cmd+click** each one |
| Delete the selected clips | **Cmd+Delete** |
| Move between categories | **Cmd+Right** and **Cmd+Left**, or **Tab** |
| Undo a delete | **Cmd+Z**, while the shelf is still open |
| Merge the selected clips into one | **Cmd+J** |
| Copy the words out of an image | **Shift+Cmd+C** |
| Stop recording for a while | Menu-bar icon, **Pause Recording** |
| Close | **Esc** |

### Keep clips forever with categories

Cpaste deletes clips after one month. To keep a clip, put it in a category.

1. Click **+** at the top of the shelf and type a name, for example `Useful Links`.
2. Drag a clip onto the category. You can also select the clip and press **Cmd+S**.

To save or delete many clips at once, hold **Cmd** and click each one. Then drag any of them onto a category, press **Cmd+S**, or press **Cmd+Delete**.

A clip in a category is never deleted automatically. Click a category to see only its clips, or press **Tab** to move through the categories. Each category has a colour, and its clips get a header and frame in that colour so you can spot them. Other clips take the colour of the app they were copied from, so Chrome clips are red and WhatsApp clips are green. Right-click a category to rename it, change its colour, or delete it. Drag a clip back onto **Clipboard** to take it out of its category. Drag a category onto another one to change their order.

Drag a clip onto another clip to move it there. A new copy still lands at the front.

Right-click a category to give it an emoji icon, or to make it **private**. A private category shows a lock, and its clips stay hidden, also from search, until you unlock it with Touch ID or your Mac password. It stays unlocked for one minute, so closing and reopening the shelf in that time needs no second Touch ID.

A pinned clip stays at the front and is never deleted automatically, even outside a category.

### Settings

Click the Cpaste icon in the menu bar and choose **Settings…**.

**General**
- **Status** shows at a glance whether recording, pasting, updates and the history are working.
- **Open at login** starts Cpaste whenever you turn on your Mac.
- **Paste items** chooses what Return does. *To active app* pastes for you. *To clipboard* only copies the clip, and you press Cmd+V yourself.
- **Position** puts the shelf along the bottom of the screen, or as a drawer on the right side with the clips in a column.
- **Card size** makes the cards small, medium or large.
- **Keep history** sets how long clips outside a category are kept, from one day to forever.
- **History size** shows how many clips you have and how much disk they use.
- **Export…** and **Import…** save every category with its clips to one file and read it back, to move them to another Mac or share them. Copied files and private categories are left out.
- **Erase History…** deletes every clip that is not pinned or in a category.

**Privacy**
- **Show during screen sharing** can be turned off, so the shelf is left out of screen shares and recordings.
- **Ignored applications** lists apps whose copies are never saved. 1Password, Apple Passwords and Keychain Access are on the list from the start.

**Shortcuts**
- Change the shortcut that opens Cpaste, and the ones that move between categories (Cmd+Right and Cmd+Left).
- **Quick paste** picks the key you hold with a number to paste by position. Choose Option to get Option+1 to Option+9.
- **Reset shortcuts to default…** puts everything back.

## Questions

**Is anything I copy sent anywhere?**
No. Your history is a folder on your Mac at `~/Library/Application Support/Cpaste/`. Nothing you copy leaves it.

**How do I get new versions?**
Cpaste checks once a day and shows **Update to Cpaste…** in its menu-bar menu when a new version is out. Click it, then **Install Update**. You can also choose **Check for Updates…** at any time. To stop the daily check, open Settings, General, and turn off **Check for updates automatically**. The check asks GitHub for a small list of versions and sends nothing about you.

**How do I erase my history?**
Open Settings and click **Erase History…**. Clips in a category stay. To remove everything, quit Cpaste and delete that folder.

**Cmd+1 does something else in my browser.**
Cpaste takes over Cmd+1 everywhere. Pick a different shortcut in Settings if you want it back.

**How do I remove Cpaste?**
Quit it, drag `Cpaste.app` to the Trash, and delete the history folder above.

## License

Cpaste is free to use, copy, and change for any **noncommercial** purpose. You may not sell it or use it to make money. The full terms are the [PolyForm Noncommercial License 1.0.0](LICENSE.md).

Copyright 2026 Yoav Sraya.

## For developers

You need Xcode 26 or later.

```bash
swift test                 # run the tests
CPASTE_RENDER=1 swift test # also draw the shelf and settings into build/*.png
./scripts/build-app.sh     # build build/Cpaste.app
./scripts/package.sh       # build dist/Cpaste.zip
./scripts/release.sh 0.1.6 notes.md   # publish a release and add it to the update feed
```

If `swift test` cannot find the `Testing` module, your Mac is using the Command Line Tools instead of Xcode. Run `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` first.

`build-app.sh` signs the app with a certificate named `Cpaste Dev` from your keychain. If you do not have one, run `CPASTE_SIGN_IDENTITY=- ./scripts/build-app.sh` to sign without a certificate. macOS then asks for the Accessibility permission again after each rebuild.

The code is in two parts. `Sources/CpasteCore` stores and searches clips and has no user interface. `Sources/Cpaste` is the menu-bar app and the shelf. Design notes are in `docs/superpowers/`.
