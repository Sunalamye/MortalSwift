import XCTest
@testable import AkagiSanma

final class SanmaObsTests: XCTestCase {
    static func sample() -> SanmaEncInput {
        var e = SanmaEncInput()
        e.hand = [0, 1, 2, 16, 52, 88, 108, 108, 108, 120, 124, 128, 132]
        e.drawnTile = 132
        e.waits = [9, 18]
        e.isTenpai = true
        e.doraIndicators = [0, 108]
        e.seats = (0..<3).map { i in
            var s = SanmaSeat()
            s.discards = [0, 4, 4]
            s.riichiDeclared = i == 1
            s.riichiTile = i == 1 ? 36 : nil
            s.score = 25_000
            s.kitaCount = UInt8(i)
            return s
        }
        e.lastDiscard = 4
        e.seatWind = 1
        e.honba = 2
        e.riichiSticks = 1
        e.turnCount = 7
        return e
    }

    static func varied() -> SanmaEncInput {
        var e = SanmaEncInput()
        e.hand = [32, 33, 36, 40, 53, 54, 89, 92, 96, 124, 125, 126, 135, 134]
        e.drawnTile = 134
        e.doraIndicators = [0, 32, 35, 132, 123]
        func seat(_ d: [UInt8], _ m: [UInt8], _ r: Bool, _ rt: UInt8?, _ score: Int32, _ kita: UInt8) -> SanmaSeat {
            var s = SanmaSeat()
            (s.discards, s.meldTiles, s.riichiDeclared, s.riichiTile, s.score, s.kitaCount) = (d, m, r, rt, score, kita)
            return s
        }
        e.seats = [
            seat([120, 121, 0, 72], [100, 101, 102], true, 72, 300_000, 9),
            seat([1, 2, 3, 52], [12, 108, 109, 110, 111], false, nil, -5_000, 2),
            seat([], [], true, 88, 41_000, 0),
        ]
        e.lastDiscard = 88
        e.roundWind = 1
        e.seatWind = 2
        e.honba = 11
        e.riichiSticks = 3
        e.turnCount = 200
        e.isDealer = true
        e.kyokuIndex = 5
        e.selfRiichi = true
        return e
    }

    func testLayoutConstants() {
        XCTAssertEqual(SanmaEncInput.channels, 37)
        XCTAssertEqual(SanmaEncInput.lastDiscardChannel, 24)
        XCTAssertEqual(SanmaEncInput.channels, SanmaModel.channels)
        XCTAssertEqual(SanmaEncInput().encode()?.count, 37 * 27)
    }

    /// Rust 版同樣會把場風與自風的東（緊湊 20）寫在 25、26 面，所以「全零」輸入只剩這兩格非零。
    func testRejectsWrongSeatCount() {
        var e = SanmaEncInput()
        e.seats = Array(repeating: SanmaSeat(), count: 4)
        XCTAssertNil(e.encode())
        e.seats.removeLast(2)
        XCTAssertNil(e.encode())
    }

    func testZeroInputOnlyMarksEastWinds() throws {
        let buf = try XCTUnwrap(SanmaEncInput().encode())
        let nonzero = buf.indices.filter { buf[$0] != 0 }.map { [$0 / 27, $0 % 27] }
        XCTAssertEqual(nonzero, [[25, 20], [26, 20]])
    }

    func testSingleHandTileHitsThresholdPlanes() throws {
        var e = SanmaEncInput()
        e.hand = [36, 37, 38]
        let buf = try XCTUnwrap(e.encode())
        for ch in 0..<4 {
            XCTAssertEqual(buf[ch * 27 + 2], ch < 3 ? 1 : 0, "threshold plane \(ch)")
        }
        XCTAssertEqual(buf[0..<(4 * 27)].reduce(0, +), 3)
    }

    func testAkaPlaneSkipsMissingRed5m() throws {
        let buf = try XCTUnwrap(Self.sample().encode())
        XCTAssertEqual(buf[4 * 27 + 6], 1)
        XCTAssertEqual(buf[4 * 27 + 15], 1)
        XCTAssertEqual(buf[(4 * 27)..<(5 * 27)].reduce(0, +), 2)
    }

    func testMatchesRustGolden() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "obs_golden_3p", withExtension: "json", subdirectory: "Fixtures"))
        let golden = try JSONDecoder().decode([[Float]].self, from: Data(contentsOf: url))
        for (name, input, expected) in zip3(["sample", "varied", "zero"], [Self.sample(), Self.varied(), SanmaEncInput()], golden) {
            let got = try XCTUnwrap(input.encode())
            let diff = got.indices.filter { got[$0] != expected[$0] }.map { ($0 / 27, $0 % 27, got[$0], expected[$0]) }
            XCTAssertTrue(diff.isEmpty, "\(name): \(diff.prefix(5))")
        }
    }

    private func zip3<A, B, C>(_ a: [A], _ b: [B], _ c: [C]) -> [(A, B, C)] {
        zip(a, zip(b, c)).map { ($0, $1.0, $1.1) }
    }
}
