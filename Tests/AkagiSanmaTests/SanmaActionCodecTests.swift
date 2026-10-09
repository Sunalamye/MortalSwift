import XCTest
@testable import AkagiSanma

/// 翻譯自 action_codec.rs 測試；原測試多為四麻，改成三麻等價案例（5m 不存在，赤五案例改用 5p）。
final class SanmaActionCodecTests: XCTestCase {
    typealias A = SanmaAction

    func testIndices() {
        XCTAssertEqual(SanmaActionCodec.index(A(.discard, tile: 36)), 2)
        XCTAssertEqual(SanmaActionCodec.index(A(.discard, tile: 88)), 15)
        XCTAssertNil(SanmaActionCodec.index(A(.discard, tile: 4)))
        XCTAssertNil(SanmaActionCodec.index(A(.chi, tile: 0, consumed: [4, 8])))
        XCTAssertEqual(SanmaActionCodec.index(A(.riichi)), 27)
        XCTAssertEqual(SanmaActionCodec.index(A(.pon, tile: 36, consumed: [37, 38])), 28)
        XCTAssertEqual(SanmaActionCodec.index(A(.daiminkan, tile: 135, consumed: [132, 133, 134])), 29 + 26)
        XCTAssertEqual(SanmaActionCodec.index(A(.ankan, consumed: [35, 32, 33, 34])), 29 + 1)
        XCTAssertEqual(SanmaActionCodec.index(A(.kakan, tile: 39, consumed: [36, 37, 38, 39])), 29 + 2)
        XCTAssertEqual(SanmaActionCodec.index(A(.ron, tile: 0)), 56)
        XCTAssertEqual(SanmaActionCodec.index(A(.tsumo)), 56)
        XCTAssertEqual(SanmaActionCodec.index(A(.kyushu)), 57)
        XCTAssertEqual(SanmaActionCodec.index(A(.pass)), 58)
        XCTAssertEqual(SanmaActionCodec.index(A(.kita, tile: 120)), 59)
    }

    func testMaskAndPick() {
        let legal = [A(.discard, tile: 0), A(.pon, tile: 36, consumed: [37, 38]), A(.pass)]
        let mask = SanmaActionCodec.legalMask(legal)
        XCTAssertEqual(mask.count, 60)
        XCTAssertEqual(mask.indices.filter { mask[$0] }, [0, 28, 58])

        var logits = [Float](repeating: 0, count: 60)
        logits[28] = 5
        XCTAssertEqual(SanmaActionCodec.rank(legal, logits: logits).first?.action.kind, .pon)
    }

    func testRankOrdersByLogitAndNormalizesOverLegal() {
        let legal = [A(.discard, tile: 0), A(.pon, tile: 36, consumed: [37, 38]), A(.pass)]
        var logits = [Float](repeating: 0, count: 60)
        logits[0] = 1; logits[28] = 3; logits[58] = 2
        let ranked = SanmaActionCodec.rank(legal, logits: logits, topN: 3)
        XCTAssertEqual(ranked.map(\.action.kind), [.pon, .pass, .discard])
        XCTAssertTrue(ranked[0].prob > ranked[1].prob && ranked[1].prob > ranked[2].prob)
        XCTAssertEqual(ranked.map(\.prob).reduce(0, +), 1, accuracy: 1e-5)
    }

    func testTopNTruncates() {
        let legal = [A(.discard, tile: 0), A(.discard, tile: 36), A(.discard, tile: 40)]
        let logits = [Float](repeating: 0, count: 60)
        XCTAssertEqual(SanmaActionCodec.rank(legal, logits: logits, topN: 2).count, 2)
        XCTAssertTrue(SanmaActionCodec.rank([], logits: logits, topN: 3).isEmpty)
    }

    func testDiscardFivePrefersPlainCopyOverRed() {
        let aka = A(.discard, tile: 52), plain = A(.discard, tile: 53), other = A(.discard, tile: 0)
        var logits = [Float](repeating: 0, count: 60)
        logits[6] = 3; logits[0] = 1
        XCTAssertEqual(SanmaActionCodec.rank([aka, plain, other], logits: logits).first?.action.tile, 53)
        XCTAssertEqual(SanmaActionCodec.rank([plain, aka, other], logits: logits).first?.action.tile, 53)
    }

    func testLoneRedFiveIsStillDiscardable() {
        var logits = [Float](repeating: 0, count: 60)
        logits[15] = 5
        let ranked = SanmaActionCodec.rank([A(.discard, tile: 88), A(.discard, tile: 0)], logits: logits)
        XCTAssertEqual(ranked.first?.action.tile, 88)
    }

    func testCandidatesAreDeduplicatedPerActionId() {
        let legal = [A(.discard, tile: 108), A(.discard, tile: 109), A(.discard, tile: 110), A(.discard, tile: 0)]
        var logits = [Float](repeating: 0, count: 60)
        logits[20] = 2; logits[0] = 1
        let ranked = SanmaActionCodec.rank(legal, logits: logits, topN: 3)
        XCTAssertEqual(ranked.count, 2)
        XCTAssertEqual(ranked[0].action.tile, 108)
        XCTAssertEqual(ranked[0].prob, 0.7310586, accuracy: 1e-5)
        XCTAssertEqual(ranked.map(\.prob).reduce(0, +), 1, accuracy: 1e-5)
    }

    func testTieBreaksOnLowestActionId() {
        let legal = [A(.pass), A(.pon, tile: 36, consumed: [37, 38])]
        let ranked = SanmaActionCodec.rank(legal, logits: [Float](repeating: 0, count: 60), topN: 2)
        XCTAssertEqual(ranked.map(\.action.kind), [.pon, .pass])
    }
}
