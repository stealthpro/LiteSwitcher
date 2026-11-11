# AGENTS.md

Guidance for AI coding agents when working in this repository.

## Commands

The Xcode project is `LiteSwitcher.xcodeproj` (one target, one scheme: `LiteSwitcher`). There are no tests or linter.

```sh
# Debug build (Apple Silicon)
xcodebuild -project LiteSwitcher.xcodeproj -scheme LiteSwitcher -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/ls-build build
open /tmp/ls-build/Build/Products/Debug/LiteSwitcher.app

# Release DMG at dist/LiteSwitcher.dmg (not notarized)
./make-dmg.sh
```

`make-dmg.sh` styles the DMG window with `dmgbuild` (`pip3 install dmgbuild`) and falls back to a plain window without it. The background it uses is committed in `dmg/`; regenerate it with `python3 dmg/make-background.py` (`pip3 install pillow`).

The version comes from `MARKETING_VERSION` in `LiteSwitcher.xcodeproj/project.pbxproj` (both build configurations), with `CURRENT_PROJECT_VERSION` as the build number. `Info.plist` is generated from the `INFOPLIST_KEY_*` build settings, so there is no plist file to edit. Settings shows `CFBundleShortVersionString` only, so the build number never appears in the UI.

The app is a menu bar app (`LSUIElement`): no Dock icon and no window. Quit it from its menu bar item or from the button in Settings.

## Constraints

- **Unsandboxed** (`ENABLE_APP_SANDBOX = NO`). The sandbox blocks the global event tap and posted key events.
- **Accessibility only.** The permission is checked at launch (`AppDelegate.startMonitoring`). The event tap does not need Input Monitoring. Permission is tied to the build's signature, so a rebuild can reset it. When the permission is missing at launch, the app waits for it and restarts itself once it is granted (`AppDelegate.relaunchWhenTrusted`).
- **Threading.** Default actor isolation is `MainActor` (Swift 5.0). The event tap callback runs on the main run loop. `KeyInjector` posts events on its own queue, because `CGEvent.post` blocks until the window server accepts the event, and the window server waits on the main-thread tap. Posting from main can freeze all input. Keep any other code that touches the tap or TIS on the main thread.
- **Deployment target macOS 14.0**, required by the two-parameter `onChange` in `SettingsView`.
- **Settings window sizing.** `AppDelegate.showSettings` sets the window height from `NSHostingView.fittingSize` instead of a literal, so a row added to `SettingsView` cannot leave empty space below the last control. `fittingSize` is correct after `layoutSubtreeIfNeeded()` and before the window is shown. Only the width (440) is fixed.
- **Grouped `Form` layout.** On macOS 26 the visible capsule of a `Button` inside a grouped `Form` row is centred in its frame, so an explicit width alone leaves a gap on the right. To right-align the shortcut button, use `.frame(minWidth: 110, alignment: .trailing)`. A button that should be centred in its row needs `HStack { Spacer(); …; Spacer() }`, not `.frame(maxWidth: .infinity)`.

## Behavior

The app converts text typed on one keyboard layout into what the same physical keys produce on the other (`ghbdtn` → `привет`). It never switches automatically. The user presses the hotkey, which defaults to ⌃⌘. A modifier-only shortcut fires when its first key is released, unless another key or modifier was used while holding it.

A press acts on the selection if there is one, otherwise on typed text:

- **Selected text** is converted, and the selection is cleared. Pressing the shortcut again finds nothing to convert and beeps. Each word is converted in the direction its letters belong to, so `привет hello` becomes `ghbdtn руддщ`.
- **Typed text** is the text typed since the last click, Enter, Tab, Escape, navigation key, shortcut, or secure input. A press converts only the last word of it, plus any spaces after that word (`KeyboardMonitor.lastWord`), so `привет мир ` becomes `привет vibe `. The result is remembered so the next press converts it back. Typing after a conversion starts a new phrase, which leaves the converted text unconverted.
- Otherwise the app beeps.

## Architecture

A press flows through `KeyboardMonitor` (event tap, hotkey match, typing buffer) to `AppDelegate.switchLayout()` (chooses selection or typed text), then through `LayoutConverter` (`KeyboardLayout.swift`), then through `KeyInjector` (`TextInput.swift`), which deletes and retypes the text and then selects the target layout.

- `KeyboardMonitor.swift`: owns the tap. Clears the typing buffer on shortcuts, navigation keys, Enter/Tab/Escape, mouse clicks, and secure input. Ignores its own injected events.
- `KeyboardLayout.swift`: reads layouts through TIS and `UCKeyTranslate`, and builds `LayoutConverter`. The converter maps only unmodified and Shift strokes. Option layers are left out because on Cyrillic layouts they hold Latin letters (Option+ф is `d`), which would convert text in both directions. Characters outside both layouts (digits, emoji, Option symbols) pass through unchanged.
- `TextInput.swift`: `KeyInjector` types text and keeps a selection (Shift+Left) when asked. `SelectionReader` reads the selected text through Accessibility.
- `AppDelegate.swift`: menu bar item, permission alert, and conversion orchestration. `main.swift` creates the delegate and runs the application.
- `Hotkey.swift`: the shortcut model. `AppSettings.swift`: preferences stored as JSON in `UserDefaults` under `switchHotkey`, shortcut recording, and `LaunchAtLogin` (`SMAppService`). `SettingsView.swift`: the Settings window — launch-at-login toggle, shortcut recorder with a `Reset` button, the app version, and a Quit button. Escape cancels shortcut recording.

**Loop prevention:** `KeyInjector` tags each posted event with `KeyInjector.marker` in `eventSourceUserData`. `KeyboardMonitor` ignores tagged events, so injected text is never treated as typing.
