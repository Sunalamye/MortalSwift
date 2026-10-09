import XCTest
@testable import AkagiSanma

final class SanmaTilesTests: XCTestCase {
    func testTile34AndAka() {
        XCTAssertEqual(SanmaTiles.tile34(0), 0)
        XCTAssertEqual(SanmaTiles.tile34(16), 4)
        XCTAssertEqual(SanmaTiles.tile34(52), 13)
        XCTAssertEqual(SanmaTiles.tile34(88), 22)
        XCTAssertEqual(SanmaTiles.tile34(135), 33)
        XCTAssertTrue(SanmaTiles.isAka(16) && SanmaTiles.isAka(52) && SanmaTiles.isAka(88))
        XCTAssertFalse(SanmaTiles.isAka(17) || SanmaTiles.isAka(0))
    }

    func testCompactMapDropsManzu2To8() {
        XCTAssertEqual(SanmaTiles.tile34ToCompact[0], 0)
        for t in 1...7 { XCTAssertNil(SanmaTiles.tile34ToCompact[t]) }
        XCTAssertEqual(SanmaTiles.tile34ToCompact[8], 1)
        XCTAssertEqual(SanmaTiles.tile34ToCompact[9], 2)
        XCTAssertEqual(SanmaTiles.tile34ToCompact[13], 6)
        XCTAssertEqual(SanmaTiles.tile34ToCompact[22], 15)
        XCTAssertEqual(SanmaTiles.tile34ToCompact[33], 26)
        XCTAssertEqual(SanmaTiles.tile34ToCompact.compactMap { $0 }, Array(0..<27))
        XCTAssertEqual(SanmaTiles.index(36), 2)
        XCTAssertNil(SanmaTiles.index(16))
    }

    func testDoraWrap() {
        XCTAssertEqual(SanmaTiles.nextDoraTile34(0), 8)
        XCTAssertEqual(SanmaTiles.nextDoraTile34(8), 0)
        XCTAssertEqual(SanmaTiles.nextDoraTile34(17), 9)
        XCTAssertEqual(SanmaTiles.nextDoraTile34(26), 18)
        XCTAssertEqual(SanmaTiles.nextDoraTile34(30), 27)
        XCTAssertEqual(SanmaTiles.nextDoraTile34(33), 31)
        XCTAssertEqual(SanmaTiles.nextDoraTile34(12), 13)
    }

    func testIndexRejectsOutOfRangeTid() {
        XCTAssertEqual(SanmaTiles.index(135), 26)
        XCTAssertNil(SanmaTiles.index(136))
        XCTAssertNil(SanmaTiles.index(255))
    }

    func testMjaiToTidMatchesRiichienv() {
        let cases: [(String, UInt8?)] = [
            ("1m", 0), ("9m", 32), ("1p", 36), ("5p", 53), ("5pr", 52), ("0p", 52), ("5s", 89), ("5sr", 88),
            ("5m", 17), ("5mr", 16), ("9s", 104), ("E", 108), ("N", 120), ("C", 132), ("4z", 120), ("7z", 132),
            ("8z", nil), ("0z", nil), ("?", nil), ("", nil), ("x1", nil), ("1x", nil),
        ]
        for (s, want) in cases { XCTAssertEqual(SanmaTiles.tid(mjai: s), want, s) }
    }
}
