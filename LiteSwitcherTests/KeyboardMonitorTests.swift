import AppKit
import Carbon.HIToolbox
import XCTest

@MainActor
final class KeyboardMonitorTests: XCTestCase {
    // MARK: - Helpers

    private func monitor(_ hotkey: Hotkey = .defaultShortcut) -> KeyboardMonitor {
        let monitor = KeyboardMonitor(hotkey: hotkey)
        monitor.isSecureInputEnabled = { false }
        return monitor
    }

    private func keyDown(_ keyCode: UInt16, _ characters: String = "", flags: CGEventFlags = [], isRepeat: Bool = false) -> CGEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)!
        var units = Array(characters.utf16)
        event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
        event.flags = flags
        event.setIntegerValueField(.keyboardEventAutorepeat, value: isRepeat ? 1 : 0)
        return event
    }

    private func flagsChanged(_ flags: CGEventFlags) -> CGEvent {
        // Only `flags` matters: `handle` is told the event type by its first argument.
        let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!
        event.flags = flags
        return event
    }

    private func type(_ text: String, into monitor: KeyboardMonitor, keyCode: UInt16 = 0, flags: CGEventFlags = []) {
        monitor.trackTyping(keyCode: keyCode, modifiers: NSEvent.ModifierFlags(cgFlags: flags), text: text)
    }

    /// Whether `handle` passed the event on. Comparing to nil avoids mirroring the unmanaged pointer.
    private func passes(_ result: Unmanaged<CGEvent>?) -> Bool {
        result != nil
    }

    /// Runs the main run loop long enough for the queued `onHotkey` callback to run.
    private func drainMainQueue() {
        let deadline = Date().addingTimeInterval(0.2)
        while Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
    }

    // MARK: - Typing buffer

    func testTypingAppendsLetters() {
        let monitor = monitor()
        type("g", into: monitor)
        type("h", into: monitor)
        XCTAssertEqual(monitor.typedWord, "gh")
        XCTAssertEqual(monitor.lastWord, "gh")
    }

    func testSpacesAreKeptSoTrailingSpacesSurviveAConversion() {
        let monitor = monitor()
        type("ghbdtn", into: monitor)
        type(" ", into: monitor)
        XCTAssertEqual(monitor.typedWord, "ghbdtn ")
        XCTAssertEqual(monitor.lastWord, "ghbdtn ")
    }

    func testLastWordIsTheTextAfterTheLastSpace() {
        let monitor = monitor()
        type("привет мир", into: monitor)
        XCTAssertEqual(monitor.lastWord, "мир")
    }

    func testLastWordSkipsLeadingWhitespaceAndIsEmptyWithoutLetters() {
        let monitor = monitor()
        type("   ab", into: monitor)
        XCTAssertEqual(monitor.lastWord, "ab")

        monitor.typedWord = "   "
        XCTAssertEqual(monitor.lastWord, "")

        monitor.typedWord = ""
        XCTAssertEqual(monitor.lastWord, "")
    }

    func testBackspaceRemovesTheLastCharacter() {
        let monitor = monitor()
        type("ab", into: monitor)
        monitor.trackTyping(keyCode: UInt16(kVK_Delete), modifiers: [], text: "")
        XCTAssertEqual(monitor.typedWord, "a")
    }

    func testBackspaceOnAnEmptyBufferStaysEmpty() {
        let monitor = monitor()
        monitor.trackTyping(keyCode: UInt16(kVK_Delete), modifiers: [], text: "")
        XCTAssertEqual(monitor.typedWord, "")
    }

    func testKeysThatMoveTheCursorClearTheBuffer() {
        let keys = [
            kVK_Return, kVK_ANSI_KeypadEnter, kVK_Tab, kVK_Escape, kVK_ForwardDelete,
            kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow,
            kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown,
        ]
        for key in keys {
            let monitor = monitor()
            type("abc", into: monitor)
            monitor.trackTyping(keyCode: UInt16(key), modifiers: [], text: "")
            XCTAssertEqual(monitor.typedWord, "", "key \(key) should clear the buffer")
        }
    }

    func testCommandAndControlClearTheBuffer() {
        for flags: NSEvent.ModifierFlags in [[.command], [.control]] {
            let monitor = monitor()
            type("abc", into: monitor)
            monitor.trackTyping(keyCode: 0, modifiers: flags, text: "c")
            XCTAssertEqual(monitor.typedWord, "", "\(flags) should clear the buffer")
        }
    }

    func testOptionKeepsTypingSoSymbolsAreConverted() {
        let monitor = monitor()
        monitor.trackTyping(keyCode: 2, modifiers: [.option], text: "d")
        XCTAssertEqual(monitor.typedWord, "d")
    }

    func testShiftKeepsTheCharacterTheLayoutProduced() {
        let monitor = monitor()
        monitor.trackTyping(keyCode: 5, modifiers: [.shift], text: "G")
        XCTAssertEqual(monitor.typedWord, "G")
    }

    func testSecureInputClearsTheBuffer() {
        let monitor = monitor()
        monitor.isSecureInputEnabled = { true }
        type("abc", into: monitor)
        type("x", into: monitor)
        XCTAssertEqual(monitor.typedWord, "")
    }

    func testControlCharactersClearTheBuffer() {
        let monitor = monitor()
        type("abc", into: monitor)
        type("\r", into: monitor)
        XCTAssertEqual(monitor.typedWord, "")
    }

    func testADeadKeyThatTypesNothingChangesNothing() {
        let monitor = monitor()
        type("ab", into: monitor)
        type("", into: monitor)
        XCTAssertEqual(monitor.typedWord, "ab")
    }

    func testBufferIsCappedAtAThousandCharacters() {
        let monitor = monitor()
        type(String(repeating: "a", count: 1500), into: monitor)
        XCTAssertEqual(monitor.typedWord.count, 1000)
        XCTAssertEqual(monitor.lastWord, String(repeating: "a", count: 1000))
    }

    func testMouseClickClearsTheBuffer() {
        let monitor = monitor()
        type("abc", into: monitor)
        let click = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: .zero, mouseButton: .left)!
        _ = monitor.handle(.leftMouseDown, click)
        XCTAssertEqual(monitor.typedWord, "")
    }

    func testRememberingAConversionLetsTheNextPressConvertBack() {
        let monitor = monitor()
        type("ghbdtn", into: monitor)
        monitor.rememberConversion("привет")
        XCTAssertEqual(monitor.typedWord, "привет")
        XCTAssertEqual(monitor.lastWord, "привет")
    }

    func testTypingAfterAConversionStartsANewPhrase() {
        let monitor = monitor()
        monitor.rememberConversion("привет")
        type("x", into: monitor)
        XCTAssertEqual(monitor.typedWord, "x")
    }

    // MARK: - Shortcut with a key

    private func commandK() -> Hotkey {
        Hotkey(
            keyCode: 40,
            keyName: "K",
            modifiers: NSEvent.ModifierFlags([.control, .command]).rawValue
        )
    }

    func testShortcutWithAKeyFiresOnceAndIsSwallowed() {
        let monitor = monitor(commandK())
        var fired = 0
        monitor.onHotkey = { fired += 1 }

        let event = keyDown(40, "k", flags: [.maskControl, .maskCommand])
        XCTAssertFalse(passes(monitor.handle(.keyDown, event)), "the shortcut itself must not reach the app")
        drainMainQueue()
        XCTAssertEqual(fired, 1)
        XCTAssertEqual(monitor.typedWord, "")
    }

    func testHoldingTheShortcutFiresOnlyOnce() {
        let monitor = monitor(commandK())
        var fired = 0
        monitor.onHotkey = { fired += 1 }

        let first = keyDown(40, "k", flags: [.maskControl, .maskCommand])
        XCTAssertFalse(passes(monitor.handle(.keyDown, first)))
        drainMainQueue()
        XCTAssertEqual(fired, 1)

        // Key repeat: same key, marked as a repeat by the window server.
        let repeatEvent = keyDown(40, "k", flags: [.maskControl, .maskCommand], isRepeat: true)
        XCTAssertFalse(passes(monitor.handle(.keyDown, repeatEvent)))
        drainMainQueue()
        XCTAssertEqual(fired, 1, "key repeat must not convert over and over")
    }

    func testShortcutWithExtraModifiersIsPassedThrough() {
        let monitor = monitor(commandK())
        var fired = 0
        monitor.onHotkey = { fired += 1 }

        let event = keyDown(40, "k", flags: [.maskControl])
        XCTAssertTrue(passes(monitor.handle(.keyDown, event)))
        drainMainQueue()
        XCTAssertEqual(fired, 0)
    }

    func testShortcutDoesNothingWhileRecordingInSettings() {
        let monitor = monitor(commandK())
        var fired = 0
        monitor.onHotkey = { fired += 1 }
        monitor.isSuspended = true

        let event = keyDown(40, "k", flags: [.maskControl, .maskCommand])
        XCTAssertTrue(passes(monitor.handle(.keyDown, event)))
        drainMainQueue()
        XCTAssertEqual(fired, 0)
    }

    func testInjectedEventsAreNotTreatedAsTyping() {
        let monitor = monitor(commandK())
        var fired = 0
        monitor.onHotkey = { fired += 1 }
        type("ab", into: monitor)

        let injected = keyDown(40, "k", flags: [.maskControl, .maskCommand])
        injected.setIntegerValueField(.eventSourceUserData, value: KeyInjector.marker)
        XCTAssertTrue(passes(monitor.handle(.keyDown, injected)))
        drainMainQueue()
        XCTAssertEqual(fired, 0)
        XCTAssertEqual(monitor.typedWord, "ab")
    }

    // MARK: - Modifier-only shortcut

    func testModifierOnlyShortcutIsRecognisedWhenTheFirstKeyIsReleased() {
        let monitor = monitor()

        XCTAssertFalse(monitor.updateModifierCombo([.control]), "one of the two modifiers is not enough")
        XCTAssertFalse(monitor.updateModifierCombo([.control, .command]), "arming the shortcut does not fire it")
        XCTAssertTrue(monitor.updateModifierCombo([.command]), "releasing Control completes ⌃⌘")
        XCTAssertFalse(monitor.updateModifierCombo([]), "the second release must not fire it again")
    }

    func testModifierOnlyShortcutGoesThroughTheEventTap() {
        let monitor = monitor()
        var fired = 0
        monitor.onHotkey = { fired += 1 }

        _ = monitor.handle(.flagsChanged, flagsChanged([.maskControl]))
        _ = monitor.handle(.flagsChanged, flagsChanged([.maskControl, .maskCommand]))
        _ = monitor.handle(.flagsChanged, flagsChanged([.maskCommand]))
        drainMainQueue()
        XCTAssertEqual(fired, 1)
    }

    func testModifierOnlyShortcutDoesNotFireWhenAKeyWasPressed() {
        let monitor = monitor()
        var fired = 0
        monitor.onHotkey = { fired += 1 }

        _ = monitor.handle(.flagsChanged, flagsChanged([.maskControl]))
        _ = monitor.handle(.flagsChanged, flagsChanged([.maskControl, .maskCommand]))
        _ = monitor.handle(.keyDown, keyDown(0, "x", flags: [.maskControl, .maskCommand]))
        _ = monitor.handle(.flagsChanged, flagsChanged([.maskCommand]))
        drainMainQueue()
        XCTAssertEqual(fired, 0)
    }

    func testModifierOnlyShortcutDoesNotFireWhenAnExtraModifierWasAdded() {
        let monitor = monitor()
        var fired = 0
        monitor.onHotkey = { fired += 1 }

        _ = monitor.handle(.flagsChanged, flagsChanged([.maskControl]))
        _ = monitor.handle(.flagsChanged, flagsChanged([.maskControl, .maskCommand]))
        _ = monitor.handle(.flagsChanged, flagsChanged([.maskControl, .maskCommand, .maskShift]))
        _ = monitor.handle(.flagsChanged, flagsChanged([.maskControl, .maskCommand]))
        drainMainQueue()
        XCTAssertEqual(fired, 0)
    }

    func testModifierOnlyShortcutDoesNothingWhileRecordingInSettings() {
        let monitor = monitor()
        var fired = 0
        monitor.onHotkey = { fired += 1 }
        monitor.isSuspended = true

        _ = monitor.handle(.flagsChanged, flagsChanged([.maskControl]))
        _ = monitor.handle(.flagsChanged, flagsChanged([.maskControl, .maskCommand]))
        _ = monitor.handle(.flagsChanged, flagsChanged([.maskCommand]))
        drainMainQueue()
        XCTAssertEqual(fired, 0)
    }

    func testModifierOnlyShortcutCanFireAgainAfterReleasing() {
        let monitor = monitor()
        var fired = 0
        monitor.onHotkey = { fired += 1 }

        _ = monitor.handle(.flagsChanged, flagsChanged([.maskControl, .maskCommand]))
        _ = monitor.handle(.flagsChanged, flagsChanged([.maskCommand]))
        _ = monitor.handle(.flagsChanged, flagsChanged([]))
        _ = monitor.handle(.flagsChanged, flagsChanged([.maskControl, .maskCommand]))
        _ = monitor.handle(.flagsChanged, flagsChanged([.maskControl]))
        drainMainQueue()
        XCTAssertEqual(fired, 2)
    }

    func testModifierOnlyShortcutIgnoresANonMatchingCombination() {
        let monitor = monitor()
        var fired = 0
        monitor.onHotkey = { fired += 1 }

        XCTAssertFalse(monitor.updateModifierCombo([.option]))
        XCTAssertFalse(monitor.updateModifierCombo([.option, .shift]))
        XCTAssertFalse(monitor.updateModifierCombo([]))
        drainMainQueue()
        XCTAssertEqual(fired, 0)
    }

    func testKeyBasedShortcutIgnoresFlagsChanged() {
        let monitor = monitor(commandK())
        var fired = 0
        monitor.onHotkey = { fired += 1 }

        _ = monitor.handle(.flagsChanged, flagsChanged([.maskControl, .maskCommand]))
        _ = monitor.handle(.flagsChanged, flagsChanged([.maskCommand]))
        drainMainQueue()
        XCTAssertEqual(fired, 0, "a shortcut with a key must not fire from modifiers alone")
    }
}
