import Carbon.HIToolbox

/// An installed keyboard layout (such as US or Russian) that can say which character each key produces.
struct KeyboardLayout {
    let source: TISInputSource
    let id: String
    fileprivate let data: Data

    static func current() -> KeyboardLayout? {
        layout(from: TISCopyCurrentKeyboardInputSource().takeRetainedValue())
    }

    /// The layout after `current` in the user's list of enabled layouts, wrapping around.
    static func next(after current: KeyboardLayout) -> KeyboardLayout? {
        let layouts = available()
        guard layouts.count > 1, let index = layouts.firstIndex(where: { $0.id == current.id }) else { return nil }
        return layouts[(index + 1) % layouts.count]
    }

    func select() {
        TISSelectInputSource(source)
    }

    /// The character produced by a key with the given Carbon modifier state (0x02 = Shift, 0x08 = Option).
    func character(keyCode: UInt16, modifiers: UInt32) -> String? {
        data.withUnsafeBytes { raw -> String? in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var deadKeyState: UInt32 = 0
            var length = 0
            var characters = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(
                layout,
                keyCode,
                UInt16(kUCKeyActionDown),
                modifiers,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysMask),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: characters, count: length)
        }
    }

    private static func available() -> [KeyboardLayout] {
        let filter: [String: Any] = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as Any,
            kTISPropertyInputSourceIsSelectCapable as String: true,
        ]
        let sources = TISCreateInputSourceList(filter as CFDictionary, false)?.takeRetainedValue() as? [TISInputSource]
        return (sources ?? []).compactMap { layout(from: $0) }
    }

    private static func layout(from source: TISInputSource) -> KeyboardLayout? {
        // Input methods such as Japanese or Chinese have no key layout data and are skipped.
        guard let rawData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData),
              let rawID = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(rawData).takeUnretainedValue() as Data
        let id = Unmanaged<CFString>.fromOpaque(rawID).takeUnretainedValue() as String
        return KeyboardLayout(source: source, id: id, data: data)
    }
}

/// Converts text typed on one layout into what the same physical keys produce on the other, in both directions.
/// Each word is converted in the direction its letters belong to, so a selection can mix both layouts.
struct LayoutConverter {
    /// Source characters mapped to target characters, and the reverse.
    private var forward: [Character: Character]
    private var backward: [Character: Character]

    init(from source: KeyboardLayout, to target: KeyboardLayout) {
        forward = Self.map(from: source, to: target)
        backward = Self.map(from: target, to: source)
    }

    /// Words are separated by whitespace, which is kept as it is. Characters outside either layout (digits shared by
    /// both, emoji, etc.) are kept as they are too.
    func convert(_ text: String) -> String {
        var result = ""
        var word = ""
        for character in text {
            if character.isWhitespace {
                result += convertWord(word) + String(character)
                word = ""
            } else {
                word.append(character)
            }
        }
        return result + convertWord(word)
    }

    private func convertWord(_ word: String) -> String {
        // Characters both layouts produce (digits, some punctuation) say nothing about which layout the word is in.
        let forwardLetters = word.filter { forward[$0] != nil && backward[$0] == nil }.count
        let backwardLetters = word.filter { backward[$0] != nil && forward[$0] == nil }.count
        let map = backwardLetters > forwardLetters ? backward : forward
        return String(word.map { map[$0] ?? $0 })
    }

    private static func map(from source: KeyboardLayout, to target: KeyboardLayout) -> [Character: Character] {
        var map: [Character: Character] = [:]
        let targetCharacters = Dictionary(strokes(of: target), uniquingKeysWith: { first, _ in first })
        for (stroke, character) in strokes(of: source) where map[character] == nil {
            map[character] = targetCharacters[stroke]
        }
        return map
    }

    /// A physical key plus modifier state, in the form UCKeyTranslate expects.
    private struct Stroke: Hashable {
        let keyCode: UInt16
        let modifiers: UInt32
    }

    /// Every single character a layout can type without Option, unshifted keys first. Option layers are left out
    /// because on Cyrillic layouts they hold Latin letters (Option+ф is "d"), which would be converted wrongly.
    private static func strokes(of layout: KeyboardLayout) -> [(Stroke, Character)] {
        var result: [(Stroke, Character)] = []
        for keyCode in 0..<UInt16(128) {
            for modifiers in [UInt32(0x00), 0x02] { // none, Shift
                guard let text = layout.character(keyCode: keyCode, modifiers: modifiers),
                      text.count == 1, let character = text.first else { continue }
                result.append((Stroke(keyCode: keyCode, modifiers: modifiers), character))
            }
        }
        return result
    }
}
