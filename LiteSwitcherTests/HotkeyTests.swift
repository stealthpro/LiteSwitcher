import AppKit
import XCTest

final class HotkeyTests: XCTestCase {
    func testDefaultShortcutIsControlCommandWithoutAKey() {
        let hotkey = Hotkey.defaultShortcut
        XCTAssertNil(hotkey.keyCode)
        XCTAssertNil(hotkey.keyName)
        XCTAssertEqual(hotkey.flags, [.control, .command])
        XCTAssertEqual(hotkey.displayString, "⌃⌘")
    }

    func testDisplayStringListsModifiersInAFixedOrder() {
        let hotkey = Hotkey(keyCode: 40, keyName: "K", modifiers: NSEvent.ModifierFlags.shortcutModifiers.rawValue)
        XCTAssertEqual(hotkey.displayString, "⌃⌥⇧⌘K")
    }

    func testDisplayStringShowsOnlyTheKeyWhenThereAreNoModifiers() {
        let hotkey = Hotkey(keyCode: 0, keyName: "A", modifiers: 0)
        XCTAssertEqual(hotkey.displayString, "A")
    }

    func testDisplayStringFallsBackToModifiersWhenThereIsNoKeyName() {
        let hotkey = Hotkey(keyCode: 40, keyName: nil, modifiers: NSEvent.ModifierFlags([.option]).rawValue)
        XCTAssertEqual(hotkey.displayString, "⌥")
    }

    func testCodableRoundTripKeepsEveryField() throws {
        let hotkey = Hotkey(keyCode: 40, keyName: "K", modifiers: NSEvent.ModifierFlags([.control, .command]).rawValue)
        let data = try JSONEncoder().encode(hotkey)
        XCTAssertEqual(try JSONDecoder().decode(Hotkey.self, from: data), hotkey)
    }

    func testCodableRoundTripOfTheModifierOnlyDefault() throws {
        let data = try JSONEncoder().encode(Hotkey.defaultShortcut)
        XCTAssertEqual(try JSONDecoder().decode(Hotkey.self, from: data), .defaultShortcut)
    }

    func testCGEventsKeepOnlyTheShortcutModifiers() {
        XCTAssertEqual(NSEvent.ModifierFlags(cgFlags: []), [])
        XCTAssertEqual(NSEvent.ModifierFlags(cgFlags: [.maskCommand]), [.command])
        XCTAssertEqual(NSEvent.ModifierFlags(cgFlags: [.maskControl]), [.control])
        XCTAssertEqual(NSEvent.ModifierFlags(cgFlags: [.maskAlternate]), [.option])
        XCTAssertEqual(NSEvent.ModifierFlags(cgFlags: [.maskShift]), [.shift])
        XCTAssertEqual(
            NSEvent.ModifierFlags(cgFlags: [.maskCommand, .maskControl, .maskAlternate, .maskShift]),
            NSEvent.ModifierFlags.shortcutModifiers
        )
    }

    func testCGEventsDropCapsLockAndFunction() {
        XCTAssertEqual(NSEvent.ModifierFlags(cgFlags: [.maskCommand, .maskAlphaShift, .maskSecondaryFn]), [.command])
    }

    func testShortcutModifiersAreTheFourThatGetRecorded() {
        XCTAssertEqual(NSEvent.ModifierFlags.shortcutModifiers, [.command, .control, .option, .shift])
    }
}
