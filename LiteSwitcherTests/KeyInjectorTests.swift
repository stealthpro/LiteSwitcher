import XCTest

final class KeyInjectorTests: XCTestCase {
    func testMarkerIsTheAppTag() {
        XCTAssertEqual(KeyInjector.marker, 0x4C53)
    }

    func testEmptyTextProducesNoChunks() {
        XCTAssertEqual(KeyInjector.chunks(of: ""), [])
    }

    func testShortTextIsASingleChunk() {
        XCTAssertEqual(KeyInjector.chunks(of: "abc"), ["abc"])
        XCTAssertEqual(KeyInjector.chunks(of: String(repeating: "a", count: 16)), [String(repeating: "a", count: 16)])
    }

    func testChunksAreCappedAtSixteenUTF16Units() {
        let chunks = KeyInjector.chunks(of: String(repeating: "a", count: 40))
        XCTAssertEqual(chunks.map(\.count), [16, 16, 8])
        XCTAssertTrue(chunks.allSatisfy { $0.utf16.count <= 16 })
    }

    func testSurrogatePairsAreNotSplit() {
        let emoji = String(repeating: "🙂", count: 9) // two UTF-16 units each
        let chunks = KeyInjector.chunks(of: emoji)
        XCTAssertEqual(chunks.map(\.count), [8, 1])
        XCTAssertEqual(chunks.joined(), emoji)
    }

    func testACharacterIsNeverSplitEvenWhenItIsLongerThanTheLimit() {
        let family = "👨‍👩‍👧‍👦" // one Character, eleven UTF-16 units
        XCTAssertGreaterThan(family.utf16.count, 10)
        let chunks = KeyInjector.chunks(of: family + family + family)
        XCTAssertEqual(chunks, [family, family, family])
    }

    func testJoiningTheChunksReturnsTheInput() {
        for text in ["привет hello 123 🙂", "ghbdtn", "a b c", "\n\n"] {
            XCTAssertEqual(KeyInjector.chunks(of: text).joined(), text)
        }
    }

    func testTheLimitIsRespectedForCyrillicText() {
        let text = String(repeating: "привет", count: 10)
        let chunks = KeyInjector.chunks(of: text)
        XCTAssertTrue(chunks.allSatisfy { $0.utf16.count <= 16 })
        XCTAssertEqual(chunks.joined(), text)
    }
}
