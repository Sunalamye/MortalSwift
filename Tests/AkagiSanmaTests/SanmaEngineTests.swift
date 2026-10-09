import XCTest
@testable import AkagiSanma

final class SanmaEngineTests: XCTestCase {
    /// 指定 action id 的 logit，其餘為 0；記錄每次 forward 的輸入。
    final class FakeModel {
        var logits: [Int: Float]
        var calls: [[Float]] = []
        init(_ logits: [Int: Float]) { self.logits = logits }
        func forward(_ obs: [Float]) -> [Float] {
            calls.append(obs)
            return (0..<SanmaActionCodec.count).map { logits[$0] ?? 0 }
        }
    }

    func engine(_ seat: Int, _ fake: FakeModel, _ events: [[String: Any]]) -> SanmaEngine {
        let e = SanmaEngine(seat: seat, forward: fake.forward)
        for ev in [["type": "start_game"]] + events { XCTAssertTrue(e.feed(ev)) }
        return e
    }

    let ownDraw = [Ev.kyoku([Ev.tenpai, Ev.junk, Ev.junk]), Ev.tsumo(0, "9m")]

    func testNoDecisionOffTurn() {
        let fake = FakeModel([:])
        XCTAssertNil(engine(1, fake, ownDraw).decide())
        XCTAssertNil(SanmaEngine(seat: 0, forward: fake.forward).decide())
        XCTAssertTrue(fake.calls.isEmpty)
    }

    func testDiscardDecisionUsesTopLogit() throws {
        let fake = FakeModel([SanmaTiles.index(tid("9m"))!: 5, SanmaTiles.index(tid("E"))!: 3, SanmaActionCodec.riichi: -1])
        let d = try XCTUnwrap(engine(0, fake, ownDraw).decide())
        XCTAssertEqual(d.action, act(.discard, "9m"))
        XCTAssertEqual(d.candidates.map(\.action), [act(.discard, "9m"), act(.discard, "E"), act(.discard, "1p")])
        XCTAssertEqual(d.candidates.count, SanmaEngine.topN)
        XCTAssertFalse(d.forced)
        XCTAssertEqual(d.logits.count, 60)
        XCTAssertEqual(fake.calls.count, 1)
        XCTAssertEqual(fake.calls[0], Ev.play(0, ownDraw).encInput().encode())
    }

    func testRiichiTopRunsSecondStageForDiscard() throws {
        let fake = FakeModel([SanmaActionCodec.riichi: 9, SanmaTiles.index(tid("E"))!: 5, SanmaTiles.index(tid("9m"))!: 1])
        let e = engine(0, fake, ownDraw)
        let d = try XCTUnwrap(e.decide())
        XCTAssertEqual(d.action, SanmaAction(.riichi, tile: tid("9m")))
        XCTAssertEqual(d.candidates.first?.action, d.action)
        XCTAssertEqual(d.candidates.dropFirst().map(\.action.kind), [.discard, .discard])
        XCTAssertEqual(fake.calls.count, 2)
        XCTAssertEqual(e.reachDiscard(), tid("9m"))
        XCTAssertFalse(e.state.players[0].riichiStage, "立直二段只動副本")
    }

    func testReachDiscardNilWhenNotOurTurn() {
        XCTAssertNil(engine(1, FakeModel([:]), ownDraw).reachDiscard())
    }

    func testForcedTsumogiriAfterRiichi() throws {
        let events = ownDraw + [Ev.reach(0), Ev.dahai(0, "9m"), Ev.accepted(0)] + Ev.cycle([(1, "S"), (2, "W")]) + [Ev.tsumo(0, "F")]
        let d = try XCTUnwrap(engine(0, FakeModel([:]), events).decide())
        XCTAssertTrue(d.forced)
        XCTAssertEqual(d.action, act(.discard, "F"))
        XCTAssertEqual(d.candidates.count, 1)
        XCTAssertEqual(d.candidates[0].prob, 1)
    }

    func testAuthorizedGateKeepsDiscardAndPass() throws {
        let window = [Ev.kyoku([Ev.junk, Ev.tenpai, Ev.junk]), Ev.tsumo(0, "E"), Ev.dahai(0, "E")]
        let fake = FakeModel([SanmaActionCodec.agari: 9, SanmaActionCodec.pon: 5])
        let e = engine(1, fake, window)
        XCTAssertEqual(e.decide()?.action, act(.ron, "E"))
        XCTAssertFalse(e.decide()!.forced)

        let pass = try XCTUnwrap(e.decide(authorized: []))
        XCTAssertEqual(pass.action, act(.pass))
        XCTAssertTrue(pass.forced)
        XCTAssertEqual(e.decide(authorized: [.pon])?.action, act(.pon, "E", ["E", "E"]))
        XCTAssertEqual(e.decide(authorized: [.ron, .pon])?.action, act(.ron, "E"))

        let draw = engine(0, FakeModel([SanmaActionCodec.riichi: 9]), ownDraw)
        let d = try XCTUnwrap(draw.decide(authorized: []))
        XCTAssertEqual(d.action.kind, .discard)
        XCTAssertEqual(draw.decide(authorized: [.riichi])?.action.kind, .riichi)
    }

    func testFeedLineAndReset() {
        let e = SanmaEngine(seat: 0, forward: FakeModel([:]).forward)
        XCTAssertTrue(e.feed(line: #"{"type":"start_game"}"#))
        XCTAssertFalse(e.feed(line: "{oops"))
        for ev in ownDraw { e.feed(ev) }
        XCTAssertNotNil(e.decide())
        e.reset()
        XCTAssertEqual(e.seat, 0)
        XCTAssertTrue(e.state.isDone)
        XCTAssertNil(e.decide())
    }

    func testBundledModelPicksALegalAction() throws {
        let e = try SanmaEngine(seat: 0)
        for ev in ownDraw { e.feed(ev) }
        let d = try XCTUnwrap(e.decide())
        let legal = e.state.legalActions()
        XCTAssertTrue(legal.contains { $0.kind == d.action.kind && ($0.kind == .riichi || $0 == d.action) })
        XCTAssertEqual(d.logits.count, 60)
        let mass = d.candidates.map(\.prob).reduce(0, +)
        XCTAssertTrue(mass > 0 && mass <= 1.0001)
    }
}
