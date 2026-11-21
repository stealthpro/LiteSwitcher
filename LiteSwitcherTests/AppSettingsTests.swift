import AppKit
import Carbon.HIToolbox
import XCTest

@MainActor
final class AppSettingsTests: XCTestCase {
    /// A throwaway preferences domain, so the tests never touch the user's own settings.
    private struct TempDefaults {
        let name = "com.av85.LiteSwitcherTests." + UUID().uuidString
        let defaults: UserDefaults

        init() {
            defaults = UserDefaults(suiteName: name)!
            defaults.removePersistentDomain(forName: name)
        }

        func cleanUp() {
            defaults.removePersistentDomain(forName: name)
        }
    }

    private let hotkeyKey = "switchHotkey"

    private func keyDown(_ keyCode: UInt16, _ characters: String, modifiers: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )!
    }

    private func flagsChanged(_ modifiers: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(
            with: .flagsChanged,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 0
        )!
    }

    private func startRecording(_ settings: AppSettings) {
        _ = NSApplication.shared
        settings.beginRecordingHotkey()
        XCTAssertTrue(settings.isRecordingHotkey)
    }

    // MARK: - Stored shortcut

    func testUsesTheDefaultShortcutWhenNothingIsSaved() {
        let temp = TempDefaults()
        defer { temp.cleanUp() }
        XCTAssertEqual(AppSettings(defaults: temp.defaults).hotkey, .defaultShortcut)
    }

    func testRestoresASavedShortcut() throws {
        let temp = TempDefaults()
        defer { temp.cleanUp() }
        let saved = Hotkey(keyCode: 40, keyName: "K", modifiers: NSEvent.ModifierFlags([.control, .command]).rawValue)
        temp.defaults.set(try JSONEncoder().encode(saved), forKey: hotkeyKey)

        XCTAssertEqual(AppSettings(defaults: temp.defaults).hotkey, saved)
    }

    func testFallsBackToTheDefaultWhenTheSavedDataIsCorrupt() {
        let temp = TempDefaults()
        defer { temp.cleanUp() }
        temp.defaults.set(Data("not json".utf8), forKey: hotkeyKey)

        XCTAssertEqual(AppSettings(defaults: temp.defaults).hotkey, .defaultShortcut)
    }

    func testChangingTheShortcutPersistsIt() {
        let temp = TempDefaults()
        defer { temp.cleanUp() }
        let settings = AppSettings(defaults: temp.defaults)
        let changed = Hotkey(keyCode: 1, keyName: "S", modifiers: NSEvent.ModifierFlags([.option]).rawValue)

        settings.hotkey = changed

        XCTAssertEqual(AppSettings(defaults: temp.defaults).hotkey, changed)
    }

    // MARK: - Recording

    func testRecordsAKeyCombinationAndStopsRecording() {
        let temp = TempDefaults()
        defer { temp.cleanUp() }
        let settings = AppSettings(defaults: temp.defaults)
        startRecording(settings)

        XCTAssertNil(settings.record(keyDown(40, "k", modifiers: [.command, .control])))

        XCTAssertEqual(settings.hotkey.keyCode, 40)
        XCTAssertEqual(settings.hotkey.keyName, "K")
        XCTAssertEqual(settings.hotkey.flags, [.command, .control])
        XCTAssertFalse(settings.isRecordingHotkey)
    }

    func testRecordedKeyNameIsUppercased() {
        let temp = TempDefaults()
        defer { temp.cleanUp() }
        let settings = AppSettings(defaults: temp.defaults)
        startRecording(settings)

        _ = settings.record(keyDown(1, "s", modifiers: [.option]))

        XCTAssertEqual(settings.hotkey.keyName, "S")
        XCTAssertEqual(settings.hotkey.displayString, "⌥S")
    }

    func testEscapeCancelsRecordingWithoutChangingTheShortcut() {
        let temp = TempDefaults()
        defer { temp.cleanUp() }
        let settings = AppSettings(defaults: temp.defaults)
        startRecording(settings)

        XCTAssertNil(settings.record(keyDown(UInt16(kVK_Escape), "\u{1B}", modifiers: [])))

        XCTAssertFalse(settings.isRecordingHotkey)
        XCTAssertEqual(settings.hotkey, .defaultShortcut)
    }

    func testAKeyWithoutCommandControlOrOptionIsRejected() {
        let temp = TempDefaults()
        defer { temp.cleanUp() }
        let settings = AppSettings(defaults: temp.defaults)
        startRecording(settings)

        XCTAssertNil(settings.record(keyDown(0, "a", modifiers: [])))

        XCTAssertTrue(settings.isRecordingHotkey, "recording continues so the user can try again")
        XCTAssertEqual(settings.hotkey, .defaultShortcut)
    }

    func testASingleModifierIsNotEnoughForAModifierOnlyShortcut() {
        let temp = TempDefaults()
        defer { temp.cleanUp() }
        let settings = AppSettings(defaults: temp.defaults)
        startRecording(settings)

        _ = settings.record(flagsChanged([.control]))
        _ = settings.record(flagsChanged([]))

        XCTAssertEqual(settings.hotkey, .defaultShortcut)
        XCTAssertTrue(settings.isRecordingHotkey)
    }

    func testTwoModifiersAreRecordedOnRelease() {
        let temp = TempDefaults()
        defer { temp.cleanUp() }
        let settings = AppSettings(defaults: temp.defaults)
        startRecording(settings)

        _ = settings.record(flagsChanged([.control]))
        _ = settings.record(flagsChanged([.control, .command]))
        _ = settings.record(flagsChanged([]))

        XCTAssertNil(settings.hotkey.keyCode)
        XCTAssertNil(settings.hotkey.keyName)
        XCTAssertEqual(settings.hotkey.flags, [.control, .command])
        XCTAssertFalse(settings.isRecordingHotkey)
    }

    func testCancellingWithoutAKeyLeavesTheShortcutAlone() {
        let temp = TempDefaults()
        defer { temp.cleanUp() }
        let settings = AppSettings(defaults: temp.defaults)
        startRecording(settings)

        settings.cancelRecordingHotkey()

        XCTAssertFalse(settings.isRecordingHotkey)
        XCTAssertEqual(settings.hotkey, .defaultShortcut)
    }
}
