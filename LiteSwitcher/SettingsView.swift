import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Start on login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            try LaunchAtLogin.setEnabled(enabled)
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            launchAtLogin = LaunchAtLogin.isEnabled
                        }
                    }
                if let loginError {
                    Text(loginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                HStack {
                    Text("Switch layout")
                    Spacer()
                    Button(shortcutLabel) {
                        if settings.isRecordingHotkey {
                            settings.cancelRecordingHotkey()
                        } else {
                            settings.beginRecordingHotkey()
                        }
                    }
                    .frame(minWidth: 110, alignment: .trailing)

                    if settings.hotkey != .defaultShortcut {
                        Button("Reset") { settings.hotkey = .defaultShortcut }
                    }
                }
            } footer: {
                Text("Select text, or place the cursor right after the last word you typed, then press the shortcut. The selection, or that word, is converted to the next keyboard layout and the layout is switched. Press Escape while recording the shortcut to cancel.")
            }

            Section {
                LabeledContent("Version", value: appVersion)
                HStack {
                    Spacer()
                    Button("Quit LiteSwitcher") {
                        NSApp.terminate(nil)
                    }
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
    }

    private var shortcutLabel: String {
        settings.isRecordingHotkey ? "Press shortcut…" : settings.hotkey.displayString
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }
}
