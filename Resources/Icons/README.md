# Cpaste icons

Approved `c↗` artwork, matching the clipboard design prototype:

- `cpaste-app-icon.png`: 1024 × 1024, opaque PNG with a full-canvas background and square corners, ready for macOS icon generation.
- `cpaste-app-icon.svg`: editable vector master of the app icon.
- `cpaste-menu-bar.svg`: black on transparent, with an 18 × 18 viewBox and geometry refined for menu-bar use. Treat it as a template image when integrating it so macOS supplies the tint.

The app icon uses a charcoal mark (`#292A2E`) on a full-canvas pale gray background (`#ECECEF`). Both SVGs use outlined geometry with no font dependencies. The menu-bar drawing is simplified for 18 px and retains its transparent background.

`scripts/make-icon.swift` turns the PNG into `Resources/AppIcon.icns`, in the rounded shape macOS expects. Run it again after changing the artwork. `scripts/build-app.sh` copies the icon file and the menu-bar SVG into the app bundle.
