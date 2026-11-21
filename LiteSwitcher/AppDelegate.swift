import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let settings = AppSettings()
    private lazy var monitor = KeyboardMonitor(hotkey: settings.hotkey)
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var subscriptions = Set<AnyCancellable>()
    private var permissionTimer: Timer?
    /// The last converter that was built. Building one translates every key of both layouts, which is wasted
    /// work when the same pair is used again.
    private var cachedConverter: (source: String, target: String, converter: LayoutConverter)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings.$hotkey
            .sink { [weak self] in self?.monitor.hotkey = $0 }
            .store(in: &subscriptions)
        settings.$isRecordingHotkey
            .sink { [weak self] recording in
                guard let self else { return }
                self.monitor.isSuspended = recording
                // Keys pressed while recording are not typing, so they must not end up in the remembered word.
                if recording { self.monitor.typedWord = "" }
            }
            .store(in: &subscriptions)
        monitor.onHotkey = { [weak self] in self?.switchLayout() }

        setUpStatusItem()
        startMonitoring()
    }

    /// Converts the typed word, or the selection, to the other keyboard layout.
    private func switchLayout() {
        guard let source = KeyboardLayout.current(),
              let target = KeyboardLayout.next(after: source) else {
            NSSound.beep()
            return
        }
        let converter = converter(from: source, to: target)
        let word = monitor.lastWord

        // Typed text is checked first even though a selection takes precedence in principle: a selection can only
        // exist when nothing was typed, because selecting needs a click or a key that clears the buffer. Asking
        // Accessibility only when there is no typed word keeps the common press off the slow path.
        if !word.isEmpty {
            let converted = converter.convert(word)
            // Keep the converted word, so pressing the shortcut again converts it back.
            monitor.rememberConversion(converted)
            KeyInjector.replace(deleting: word.count, with: converted) { target.select() }
        } else if let selection = SelectionReader.selectedText(), !selection.isEmpty {
            monitor.typedWord = ""
            // Replaces the selection, leaving the cursor at its end with nothing selected.
            KeyInjector.replace(deleting: 0, with: converter.convert(selection)) { target.select() }
        } else {
            NSSound.beep()
        }
    }

    private func converter(from source: KeyboardLayout, to target: KeyboardLayout) -> LayoutConverter {
        if let cached = cachedConverter, cached.source == source.id, cached.target == target.id {
            return cached.converter
        }
        let converter = LayoutConverter(from: source, to: target)
        cachedConverter = (source.id, target.id, converter)
        return converter
    }

    private func startMonitoring() {
        // Accessibility lets us watch key presses through the event tap, read selections, and type text.
        // No system prompt here: showPermissionAlert explains the step and opens the same settings pane.
        let trusted = AXIsProcessTrusted()
        if !monitor.start() || !trusted {
            if !trusted { relaunchWhenTrusted() }
            showPermissionAlert()
        }
    }

    /// macOS applies an Accessibility grant only to processes started after it, so this one can't use the event tap.
    /// Watch for the grant, then restart the app.
    private func relaunchWhenTrusted() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard AXIsProcessTrusted() else { return }
                timer.invalidate()
                self?.relaunch()
            }
        }
        // Common modes, so the watch keeps running while the permission alert is open.
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer
    }

    /// Starts a helper that waits for this process to exit, then opens the app again.
    private func relaunch() {
        let script = "while kill -0 \"$1\" 2>/dev/null; do sleep 0.1; done; open \"$2\""
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = ["-c", script, "sh", String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundlePath]
        try? helper.run()
        NSApp.abortModal() // ends the permission alert if it is still open
        NSApp.terminate(nil)
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "LiteSwitcher needs permissions"
        alert.informativeText = "Allow LiteSwitcher under Accessibility in System Settings → Privacy & Security. The app restarts by itself once it is allowed."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "LiteSwitcher")

        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit LiteSwitcher", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let hostingView = NSHostingView(rootView: SettingsView(settings: settings))
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 440, height: 300),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.contentView = hostingView
            window.title = "LiteSwitcher"
            window.isReleasedWhenClosed = false
            window.delegate = self
            // Size the window to the SwiftUI content, so there is no empty space below the last control.
            hostingView.layoutSubtreeIfNeeded()
            let fitted = hostingView.fittingSize
            if fitted.height > 1 {
                window.setContentSize(NSSize(width: 440, height: fitted.height))
            }
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// Closing Settings while recording would leave the shortcut suspended and the app deaf to it, so stop recording.
    func windowWillClose(_ notification: Notification) {
        settings.cancelRecordingHotkey()
    }
}
