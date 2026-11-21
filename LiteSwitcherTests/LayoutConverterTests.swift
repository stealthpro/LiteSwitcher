import XCTest

final class LayoutConverterTests: XCTestCase {
    // A stand-in for two layouts: "a", "b" and "c" sit on the same physical keys as "ф", "и" and "с".
    private let forward: [Character: Character] = ["a": "ф", "b": "и", "c": "с"]
    private let backward: [Character: Character] = ["ф": "a", "и": "b", "с": "c"]

    private var converter: LayoutConverter {
        LayoutConverter(forward: forward, backward: backward)
    }

    func testConvertsALatinWordToCyrillic() {
        XCTAssertEqual(converter.convert("abc"), "фис")
    }

    func testConvertsACyrillicWordToLatin() {
        XCTAssertEqual(converter.convert("фис"), "abc")
    }

    func testConvertsEachWordInTheDirectionItsLettersBelongTo() {
        XCTAssertEqual(converter.convert("abc фис"), "фис abc")
        XCTAssertEqual(converter.convert("фис abc"), "abc фис")
    }

    func testKeepsWhitespaceExactly() {
        XCTAssertEqual(converter.convert("  abc \t фис \n"), "  фис \t abc \n")
        XCTAssertEqual(converter.convert("a  b"), "ф  и")
    }

    func testKeepsTheSpacesAfterAWord() {
        XCTAssertEqual(converter.convert("abc "), "фис ")
        XCTAssertEqual(converter.convert("abc   "), "фис   ")
    }

    func testEmptyTextStaysEmpty() {
        XCTAssertEqual(converter.convert(""), "")
        XCTAssertEqual(converter.convert(" "), " ")
        XCTAssertEqual(converter.convert("\n\t"), "\n\t")
    }

    func testCharactersOutsideBothMapsPassThrough() {
        XCTAssertEqual(converter.convert("a1🙂"), "ф1🙂")
        XCTAssertEqual(converter.convert("🙂"), "🙂")
        XCTAssertEqual(converter.convert("12345"), "12345")
    }

    func testUppercaseIsLeftAloneWhenOnlyLowercaseIsMapped() {
        XCTAssertEqual(converter.convert("ABC"), "ABC")
        XCTAssertEqual(converter.convert("Abc"), "Aис")
    }

    func testAnEvenMixOfBothAlphabetsConvertsForward() {
        // "aф" has one letter in each direction, so the forward map wins.
        XCTAssertEqual(converter.convert("aф"), "фф")
    }

    func testAWordMadeOnlyOfSharedCharactersConvertsForward() {
        // Characters in both maps are counted for neither direction.
        let both: [Character: Character] = ["x": "x"]
        let shared = LayoutConverter(forward: both, backward: both)
        XCTAssertEqual(shared.convert("x"), "x")
    }

    func testIsCaseSensitiveForSeparateMaps() {
        var upperForward = forward
        upperForward["A"] = "Ф"
        let mixed = LayoutConverter(forward: upperForward, backward: backward)
        XCTAssertEqual(mixed.convert("A"), "Ф")
        XCTAssertEqual(mixed.convert("a"), "ф")
    }

    /// The real layouts are only on the machine that has both installed, so this test skips elsewhere.
    func testConvertsTheDocumentedExampleOnTheRealLayouts() throws {
        guard let current = KeyboardLayout.current(), let next = KeyboardLayout.next(after: current) else {
            throw XCTSkip("Needs at least two selectable keyboard layouts")
        }
        let ids = Set([current.id, next.id])
        let russian = ["com.apple.keylayout.Russian", "com.apple.keylayout.RussianWin"]
        guard ids.contains("com.apple.keylayout.ABC"), ids.contains(where: russian.contains) else {
            throw XCTSkip("Needs the U.S. and a Russian layout, found \(ids.sorted())")
        }

        let converter = LayoutConverter(from: current, to: next)
        XCTAssertEqual(converter.convert("ghbdtn"), "привет")
        XCTAssertEqual(converter.convert("привет"), "ghbdtn")
        XCTAssertEqual(converter.convert("привет hello"), "ghbdtn руддщ")
        XCTAssertEqual(converter.convert("ghbdtn "), "привет ")
        XCTAssertEqual(converter.convert("2024"), "2024")
    }

    func testSystemLayoutsAreEnumeratedConsistently() throws {
        guard let current = KeyboardLayout.current() else {
            throw XCTSkip("No keyboard layout to read")
        }
        // With a single layout there is nowhere to convert to; with more, the next one must differ.
        let next = KeyboardLayout.next(after: current)
        if let next {
            XCTAssertNotEqual(next.id, current.id)
        }
    }
}
