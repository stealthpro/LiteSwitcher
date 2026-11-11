# LiteSwitcher

LiteSwitcher is a macOS menu bar app that fixes text typed with the wrong keyboard layout. Type `ghbdtn` while the US layout is active, press a shortcut, and it becomes `привет`. It works the other way too.

It never switches layouts or rewrites text on its own. You press the shortcut when you want a conversion.

## Features

- **Convert a selection.** Select text and press the shortcut. The text is converted and the selection is cleared. Each word is converted to the other layout, so mixed-language text converts in both directions.
- **Convert typed text.** With no selection, the shortcut converts the text you typed since your last click, Enter, Tab, Escape, navigation key, or shortcut. The result is remembered, so pressing the shortcut again converts it back.
- **Switch layout.** After each conversion, the app selects the other keyboard layout.
- **Customizable shortcut.** The default is ⌃⌘ (Control + Command). You can record a different shortcut in Settings, including modifier-only shortcuts.
- **Start on login.** Optional, set in Settings.

Conversion maps the keys of one layout to the keys of the next layout in your enabled input sources. Digits, punctuation that is the same on both layouts, emoji, and Option-key symbols pass through unchanged.

## Requirements

- macOS 14.0 or later
- Xcode, to build from source
- Accessibility permission (the app asks for it at first launch)

LiteSwitcher is not sandboxed. The sandbox blocks the global keyboard event tap and posted key events that it needs.

## Install

### Download a build

Download the latest DMG from [Releases](https://github.com/stealthpro/LiteSwitcher/releases/latest), open it, and drag LiteSwitcher into Applications. The build is not notarized, so on another Mac you need to allow it in **System Settings → Privacy & Security** before it opens.

### Build from source

Open `LiteSwitcher.xcodeproj` in Xcode and run the `LiteSwitcher` scheme, or build from the command line:

```sh
xcodebuild -project LiteSwitcher.xcodeproj -scheme LiteSwitcher -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/ls-build build
open /tmp/ls-build/Build/Products/Debug/LiteSwitcher.app
```

To package a release DMG at `dist/LiteSwitcher.dmg`:

```sh
./make-dmg.sh
```

The DMG opens into a styled Finder window (big icons, the app on the left, Applications on the right, and an arrow between them over a custom background). That layout is produced by `dmgbuild` — install it once with `pip3 install dmgbuild`. Without it, `make-dmg.sh` still works but falls back to a plain window. The background artwork lives in `dmg/` (`background.png` and `background@2x.png`) and can be regenerated with `python3 dmg/make-background.py`, which needs Pillow (`pip3 install pillow`).

## Granting Accessibility permission

LiteSwitcher needs Accessibility access to watch keystrokes and insert converted text. On first launch, an alert offers to open System Settings. Enable LiteSwitcher under **Privacy & Security → Accessibility**. The app then restarts itself.

Accessibility permission is tied to the app's code signature. After rebuilding, macOS may revoke it, so you may need to enable it again.

## Usage

1. Type text with the wrong layout active, or select it.
2. Press the shortcut (⌃⌘ by default).
3. To convert typed text back, press it again. A converted selection can't be converted back this way.

The menu bar item shows the app's menu, including Settings and Quit. LiteSwitcher has no Dock icon and no window. The Settings window also shows the app version and has its own Quit button.

## Project layout

| File | Purpose |
| --- | --- |
| `LiteSwitcher/AppDelegate.swift` | Menu bar item, permission alert, and conversion flow |
| `LiteSwitcher/main.swift` | Entry point; creates the app delegate |
| `LiteSwitcher/KeyboardMonitor.swift` | Event tap, shortcut matching, and the typing buffer |
| `LiteSwitcher/KeyboardLayout.swift` | Reads layouts through Text Input Sources and builds the converter |
| `LiteSwitcher/TextInput.swift` | Types replacement text and reads selections through Accessibility |
| `LiteSwitcher/Hotkey.swift` | Shortcut model |
| `LiteSwitcher/AppSettings.swift` | Saved preferences, shortcut recording, and launch-at-login |
| `LiteSwitcher/SettingsView.swift` | Settings window, with the version and a Quit button |
| `make-dmg.sh` | Release build and DMG packaging |
| `dmg/settings.py` | dmgbuild window layout for the installer |
| `dmg/make-background.py` | Draws the installer background (needs Pillow) |

Release builds are written to `dist/`, which is git-ignored.

`AGENTS.md` has more detail on threading and architecture for contributors.

## License

No license has been specified yet.
