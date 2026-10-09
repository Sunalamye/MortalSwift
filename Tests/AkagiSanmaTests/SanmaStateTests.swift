import XCTest
@testable import AkagiSanma

enum Ev {
    /// 123p 456p 789p 1s1s EE：雙碰聽 1s／E。
    static let tenpai = ["1p", "2p", "3p", "4p", "5p", "6p", "7p", "8p", "9p", "1s", "1s", "E", "E"]
    /// 全是孤張、無對子、不聽牌。
    static let junk = ["2s", "4s", "6s", "8s", "2p", "4p", "6p", "8p", "1s", "3s", "7s", "9s", "3p"]

    static func kyoku(_ hands: [[String]], oya: Int = 0, scores: [Int] = [35_000, 35_000, 35_000]) -> [String: Any] {
        ["type": "start_kyoku", "bakaze": "E", "kyoku": oya + 1, "honba": 0, "kyoutaku": 0, "oya": oya,
         "scores": scores, "dora_marker": "1s", "tehais": hands]
    }
    static func tsumo(_ a: Int, _ p: String) -> [String: Any] { ["type": "tsumo", "actor": a, "pai": p] }
    static func dahai(_ a: Int, _ p: String) -> [String: Any] { ["type": "dahai", "actor": a, "pai": p, "tsumogiri": false] }
    static func reach(_ a: Int) -> [String: Any] { ["type": "reach", "actor": a] }
    static func accepted(_ a: Int) -> [String: Any] { ["type": "reach_accepted", "actor": a] }
    static func pon(_ a: Int, _ p: String, _ c: [String]) -> [String: Any] { ["type": "pon", "actor": a, "target": 0, "pai": p, "consumed": c] }
    static func kakan(_ a: Int, _ p: String) -> [String: Any] { ["type": "kakan", "actor": a, "pai": p] }
    /// 依序摸切，各家輪流把 `tiles` 打掉。
    static func cycle(_ pairs: [(Int, String)]) -> [[String: Any]] { pairs.flatMap { [tsumo($0.0, $0.1), dahai($0.0, $0.1)] } }

    static func play(_ seat: Int, _ events: [[String: Any]]) -> SanmaState {
        var s = SanmaState(seat: seat)
        XCTAssertTrue(s.apply(["type": "start_game"]))
        for e in events { XCTAssertTrue(s.apply(e), "\(e)") }
        return s
    }
}

func tid(_ s: String) -> UInt8 { SanmaTiles.tid(mjai: s)! }
func act(_ k: SanmaAction.Kind, _ t: String? = nil, _ c: [String] = []) -> SanmaAction {
    SanmaAction(k, tile: t.map(tid), consumed: c.map(tid))
}

final class SanmaStateTests: XCTestCase {
    func testOwnDrawListsEveryDiscardAndRiichi() {
        let s = Ev.play(0, [Ev.kyoku([Ev.tenpai, Ev.junk, Ev.junk]), Ev.tsumo(0, "9m")])
        let legal = s.legalActions()
        XCTAssertEqual(legal.filter { $0.kind == .discard }.compactMap(\.tile), s.players[0].hand)
        XCTAssertEqual(legal.count, 15)
        XCTAssertEqual(legal.last, act(.riichi))
        XCTAssertEqual(s.drawnTile, tid("9m"))
        XCTAssertEqual(s.drawable, 54)
        XCTAssertEqual(Ev.play(1, [Ev.kyoku([Ev.tenpai, Ev.junk, Ev.junk]), Ev.tsumo(0, "9m")]).legalActions(), [])
    }

    func testRiichiNeedsThousandPointsAndClosedHand() {
        let poor = Ev.play(0, [Ev.kyoku([Ev.tenpai, Ev.junk, Ev.junk], scores: [999, 35_000, 35_000]), Ev.tsumo(0, "9m")])
        XCTAssertFalse(poor.legalActions().contains(act(.riichi)))
        let rich = Ev.play(0, [Ev.kyoku([Ev.tenpai, Ev.junk, Ev.junk], scores: [1000, 35_000, 35_000]), Ev.tsumo(0, "9m")])
        XCTAssertTrue(rich.legalActions().contains(act(.riichi)))
        let noTenpai = Ev.play(0, [Ev.kyoku([Ev.junk, Ev.junk, Ev.junk]), Ev.tsumo(0, "9m")])
        XCTAssertFalse(noTenpai.legalActions().contains(act(.riichi)))
    }

    func testTsumoIsShapeOnly() {
        let s = Ev.play(0, [Ev.kyoku([Ev.tenpai, Ev.junk, Ev.junk]), Ev.tsumo(0, "1s")])
        XCTAssertEqual(s.legalActions().first, act(.tsumo, "1s"))
        let miss = Ev.play(0, [Ev.kyoku([Ev.tenpai, Ev.junk, Ev.junk]), Ev.tsumo(0, "W")])
        XCTAssertFalse(miss.legalActions().contains { $0.kind == .tsumo })
    }

    func testKyushuAndKitaOnOwnDraw() {
        let hand = ["1m", "9m", "1p", "9p", "1s", "9s", "E", "S", "W", "N", "2p", "3p", "4p"]
        let s = Ev.play(0, [Ev.kyoku([hand, Ev.junk, Ev.junk]), Ev.tsumo(0, "4p")])
        XCTAssertEqual(s.legalActions().filter { $0.kind != .discard }, [act(.kyushu), act(.kita, "N")])

        let eight = ["1m", "9m", "1p", "9p", "1s", "9s", "E", "S", "2p", "3p", "4p", "5p", "6p"]
        let few = Ev.play(0, [Ev.kyoku([eight, Ev.junk, Ev.junk]), Ev.tsumo(0, "7p")])
        XCTAssertFalse(few.legalActions().contains(act(.kyushu)))
        let nine = Ev.play(0, [Ev.kyoku([eight, Ev.junk, Ev.junk]), Ev.tsumo(0, "W")])
        XCTAssertTrue(nine.legalActions().contains(act(.kyushu)))
    }

    func testDiscardOpensRonPonPassWindow() {
        let events = [Ev.kyoku([Ev.junk, Ev.tenpai, Ev.junk]), Ev.tsumo(0, "E"), Ev.dahai(0, "E")]
        let s = Ev.play(1, events)
        XCTAssertEqual(s.legalActions(), [act(.ron, "E"), act(.pon, "E", ["E", "E"]), act(.pass)])
        XCTAssertEqual(s.lastDiscard?.seat, 0)
        XCTAssertEqual(s.lastDiscard?.tile, tid("E"))
        XCTAssertNil(s.drawnTile)
        XCTAssertEqual(s.encInput().lastDiscard, tid("E"))
        XCTAssertEqual(Ev.play(0, events).legalActions(), [])
        XCTAssertEqual(Ev.play(2, events).legalActions(), [])
    }

    func testNoClaimMeansNobodyActs() {
        let s = Ev.play(0, [Ev.kyoku([Ev.junk, Ev.junk, Ev.junk])] + Ev.cycle([(0, "9m")]))
        XCTAssertEqual(s.phase, .act)
        XCTAssertNil(s.currentPlayer)
        XCTAssertEqual(s.legalActions(), [])
    }

    func testFuritenBlocksRonButNotPon() {
        let s = Ev.play(1, [Ev.kyoku([Ev.junk, Ev.tenpai, Ev.junk])] + Ev.cycle([(0, "9s"), (1, "1s"), (2, "S"), (0, "E")]))
        XCTAssertEqual(s.legalActions(), [act(.pon, "E", ["E", "E"]), act(.pass)])
        let same = Ev.play(1, [Ev.kyoku([Ev.junk, Ev.tenpai, Ev.junk])] + Ev.cycle([(0, "9s"), (1, "E"), (2, "S"), (0, "1s")]))
        XCTAssertEqual(same.legalActions(), [act(.pon, "1s", ["1s", "1s"]), act(.pass)])
    }

    func testRedFivePonPairsAndDaiminkan() {
        let hand = ["5pr", "5p", "5p", "1s", "3s", "7s", "9s", "2p", "8p", "E", "S", "W", "C"]
        let s = Ev.play(1, [Ev.kyoku([Ev.junk, hand, Ev.junk]), Ev.tsumo(0, "5p"), Ev.dahai(0, "5p")])
        XCTAssertEqual(s.legalActions(), [
            act(.pon, "5p", ["5pr", "5p"]), act(.pon, "5p", ["5p", "5p"]),
            act(.daiminkan, "5p", ["5pr", "5p", "5p"]), act(.pass),
        ])
    }

    func testKuikaeBlocksPonLeavingOnlySameKind() {
        let s = Ev.play(1, [Ev.kyoku([Ev.junk, ["P", "P", "P"], Ev.junk]), Ev.tsumo(0, "P"), Ev.dahai(0, "P")])
        XCTAssertEqual(s.legalActions(), [act(.daiminkan, "P", ["P", "P", "P"]), act(.pass)])
        let two = Ev.play(1, [Ev.kyoku([Ev.junk, ["P", "P"], Ev.junk]), Ev.tsumo(0, "P"), Ev.dahai(0, "P")])
        // 兩張手牌不能碰；單吊形狀本身已成和，所以只剩 ron（役由 oplist 判）。
        XCTAssertEqual(two.legalActions(), [act(.ron, "P"), act(.pass)])
    }

    func testReachStageThenForcedTsumogiri() {
        var events = [Ev.kyoku([Ev.tenpai, Ev.junk, Ev.junk]), Ev.tsumo(0, "9m"), Ev.reach(0)]
        let stage = Ev.play(0, events)
        XCTAssertTrue(stage.players[0].riichiStage)
        XCTAssertEqual(stage.legalActions(), [act(.discard, "9m")])

        events += [Ev.dahai(0, "9m"), Ev.accepted(0)] + Ev.cycle([(1, "S"), (2, "W")]) + [Ev.tsumo(0, "F")]
        let s = Ev.play(0, events)
        XCTAssertTrue(s.players[0].riichiDeclared)
        XCTAssertFalse(s.players[0].riichiStage)
        XCTAssertEqual(s.players[0].score, 34_000)
        XCTAssertEqual(s.riichiSticks, 1)
        XCTAssertEqual(s.legalActions(), [act(.discard, "F")])
        let e = s.encInput()
        XCTAssertTrue(e.selfRiichi && e.seats[0].riichiDeclared)
        XCTAssertNil(e.seats[0].riichiTile)
        XCTAssertEqual(e.seats[0].score, 34_000)
    }

    func testRiichiDeclaredAllowsOnlyRonOnClaims() {
        let s = Ev.play(1, [Ev.kyoku([Ev.junk, Ev.tenpai, Ev.junk]), Ev.tsumo(0, "S"), Ev.dahai(0, "S"),
                            Ev.tsumo(1, "9m"), Ev.reach(1), Ev.dahai(1, "9m"), Ev.accepted(1)]
                        + Ev.cycle([(2, "W"), (0, "E")]))
        XCTAssertEqual(s.legalActions(), [act(.ron, "E"), act(.pass)])
    }

    func testAnkanAfterRiichiOnlyWhenWaitsUnchanged() {
        func riichiThenDraw(_ hand: [String], _ draw: String) -> SanmaState {
            Ev.play(0, [Ev.kyoku([hand, Ev.junk, Ev.junk]), Ev.tsumo(0, "9m"), Ev.reach(0), Ev.dahai(0, "9m"), Ev.accepted(0)]
                + Ev.cycle([(1, "S"), (2, "W")]) + [Ev.tsumo(0, draw)])
        }
        let keep = riichiThenDraw(["1p", "2p", "3p", "4p", "5p", "6p", "7p", "8p", "9p", "1s", "1s", "1s", "E"], "1s")
        XCTAssertEqual(keep.legalActions(), [act(.discard, "1s"), SanmaState.ankan(18)])
        let change = riichiThenDraw(["1p", "2p", "3p", "4p", "5p", "6p", "7p", "8p", "9p", "1s", "1s", "1s", "2s"], "1s")
        XCTAssertEqual(change.legalActions(), [act(.discard, "1s")])
    }

    func testAnkanKakanAndKuikaeAfterPon() {
        let quad = Ev.play(0, [Ev.kyoku([["S", "S", "S"] + Ev.junk.prefix(10), Ev.junk, Ev.junk]), Ev.tsumo(0, "S")])
        XCTAssertTrue(quad.legalActions().contains(SanmaState.ankan(28)))

        let hand = ["P", "P", "P", "2s", "4s", "6s", "8s", "2p", "4p", "6p", "8p", "1s", "3s"]
        var events = [Ev.kyoku([hand, Ev.junk, Ev.junk]), Ev.tsumo(0, "9m"), Ev.dahai(0, "9m"), Ev.tsumo(1, "P"), Ev.dahai(1, "P")]
        XCTAssertEqual(Ev.play(0, events).legalActions(), [
            act(.pon, "P", ["P", "P"]), act(.daiminkan, "P", ["P", "P", "P"]), act(.pass),
        ])
        events.append(Ev.pon(0, "P", ["P", "P"]))
        let afterPon = Ev.play(0, events).legalActions()
        XCTAssertEqual(afterPon.count, 10)
        XCTAssertTrue(afterPon.allSatisfy { $0.kind == .discard && $0.tile != tid("P") })

        events += [Ev.dahai(0, "1s")] + Ev.cycle([(1, "9s"), (2, "9s")]) + [Ev.tsumo(0, "3p")]
        let draw = Ev.play(0, events)
        XCTAssertEqual(draw.legalActions().filter { $0.kind != .discard }, [act(.kakan, "P", ["P", "P", "P"])])
        XCTAssertEqual(draw.legalActions().filter { $0.kind == .discard }.count, 11)

        events.append(Ev.kakan(0, "P"))
        let kan = Ev.play(0, events)
        XCTAssertEqual(kan.players[0].melds, [SanmaMeld(kind: .kakan, tiles: [124, 124, 124, 124])])
        XCTAssertFalse(kan.players[0].hand.contains(124))
    }

    func testKakanUpgradesTheMatchingPonOnly() {
        let hand = ["C", "C", "P", "P", "P", "2s", "4s", "6s", "8s", "2p", "4p", "6p", "8p"]
        let s = Ev.play(0, [Ev.kyoku([hand, Ev.junk, Ev.junk])] + Ev.cycle([(0, "9m"), (1, "C")])
            + [Ev.pon(0, "C", ["C", "C"]), Ev.dahai(0, "2s")] + Ev.cycle([(1, "9s"), (2, "P")])
            + [Ev.pon(0, "P", ["P", "P"]), Ev.dahai(0, "4s")] + Ev.cycle([(1, "S"), (2, "W")])
            + [Ev.tsumo(0, "9p"), Ev.kakan(0, "P")])
        XCTAssertEqual(s.players[0].melds, [
            SanmaMeld(kind: .pon, tiles: [132, 132, 132]), SanmaMeld(kind: .kakan, tiles: [124, 124, 124, 124]),
        ])
    }

    func testChankanOpensRonWindowOnlyWhenNotFuriten() {
        let waitP = ["1p", "2p", "3p", "4p", "5p", "6p", "7p", "8p", "9p", "1s", "1s", "1s", "P"]
        let kanner = ["P", "P", "2s", "4s", "6s", "8s", "2p", "4p", "6p", "8p", "3s", "7s", "9s"]
        func events(ownDiscard: String) -> [[String: Any]] {
            [Ev.kyoku([kanner, waitP, Ev.junk])] + Ev.cycle([(0, "9m"), (1, ownDiscard), (2, "P")])
                + [Ev.pon(0, "P", ["P", "P"]), Ev.dahai(0, "2s")] + Ev.cycle([(1, "S"), (2, "C")])
                + [Ev.tsumo(0, "P"), Ev.kakan(0, "P")]
        }
        let s = Ev.play(1, events(ownDiscard: "W"))
        XCTAssertEqual(s.legalActions(), [act(.ron, "P"), act(.pass)])
        XCTAssertEqual(s.lastDiscard?.seat, 0)
        XCTAssertEqual(s.lastDiscard?.tile, 124)
        XCTAssertEqual(s.encInput().drawnTile, 124)
        XCTAssertEqual(Ev.play(2, events(ownDiscard: "W")).legalActions(), [])
        XCTAssertEqual(Ev.play(1, events(ownDiscard: "P")).legalActions(), [])
    }

    func testOwnKakanOpensNoChankan() {
        let hand = ["P", "P", "2s", "4s", "6s", "8s", "2p", "4p", "6p", "8p", "3s", "7s", "9s"]
        let s = Ev.play(0, [Ev.kyoku([hand, Ev.junk, Ev.junk]), Ev.tsumo(0, "9m"), Ev.dahai(0, "9m"),
                            Ev.tsumo(1, "P"), Ev.dahai(1, "P"), Ev.pon(0, "P", ["P", "P"]), Ev.dahai(0, "2s")]
                        + Ev.cycle([(1, "S"), (2, "C")]) + [Ev.tsumo(0, "P"), Ev.kakan(0, "P")])
        XCTAssertEqual(s.phase, .act)
        XCTAssertEqual(s.currentPlayer, 0)
    }

    func testKitaCountsAndOpensRonOnlyWindow() {
        let waitN = ["1p", "2p", "3p", "4p", "5p", "6p", "7p", "8p", "9p", "1s", "1s", "1s", "N"]
        let holder = ["N", "N"] + Ev.junk.prefix(11)
        let base = [Ev.kyoku([holder, waitN, Ev.junk]), Ev.tsumo(0, "9m")]
        XCTAssertEqual(Ev.play(0, base).legalActions().filter { $0.kind == .kita }, [act(.kita, "N"), act(.kita, "N")])

        var s = Ev.play(1, base)
        XCTAssertTrue(s.apply(line: #"{"type":"nukidora","actor":0}"#))
        XCTAssertEqual(s.players[0].kitaCount, 1)
        XCTAssertEqual(s.players[0].hand.filter { $0 == 120 }.count, 1)
        XCTAssertEqual(s.legalActions(), [act(.ron, "N"), act(.pass)])
        XCTAssertNil(s.lastDiscard)
        XCTAssertEqual(s.encInput().seats.map(\.kitaCount), [0, 0, 1])
    }

    func testKitaFromHiddenHandStillCounts() {
        let hidden = Array(repeating: "?", count: 13)
        var s = Ev.play(0, [Ev.kyoku([Ev.junk, hidden, hidden]), Ev.tsumo(1, "?")])
        XCTAssertTrue(s.apply(["type": "kita", "actor": 1]))
        XCTAssertEqual(s.players[1].kitaCount, 1)
        XCTAssertEqual(s.encInput().seats[1].kitaCount, 1)
    }

    func testRejectsKanWithEmptyConsumed() {
        var s = Ev.play(1, [Ev.kyoku([Ev.junk, Ev.tenpai, Ev.junk]), Ev.tsumo(0, "S")])
        XCTAssertFalse(s.apply(["type": "ankan", "actor": 0, "consumed": [String]()]))
        XCTAssertFalse(s.apply(["type": "kan", "actor": 0, "target": 2, "pai": "S", "consumed": [String]()]))
        XCTAssertEqual(s.players[0].melds, [])
        XCTAssertTrue(s.apply(Ev.dahai(0, "E")))
        XCTAssertEqual(s.legalActions(), [act(.ron, "E"), act(.pon, "E", ["E", "E"]), act(.pass)])
    }

    func testHiddenOpponentDrawLeavesNoFakeDrawnTile() {
        let hidden = Array(repeating: "?", count: 13)
        let waitN = ["1p", "2p", "3p", "4p", "5p", "6p", "7p", "8p", "9p", "1s", "1s", "1s", "N"]
        var s = Ev.play(0, [Ev.kyoku([waitN, hidden, hidden]), Ev.tsumo(1, "?")])
        XCTAssertNil(s.drawnTile)
        XCTAssertTrue(s.apply(["type": "kita", "actor": 1]))
        XCTAssertEqual(s.legalActions(), [act(.ron, "N"), act(.pass)])
        XCTAssertNil(s.encInput().drawnTile)
        XCTAssertTrue(s.apply(Ev.tsumo(1, "5pr")))
        XCTAssertEqual(s.drawnTile, 52)
    }

    func testKyokuEndStopsDecisionsAndNextKyokuResets() {
        var s = Ev.play(0, [Ev.kyoku([Ev.tenpai, Ev.junk, Ev.junk]), Ev.tsumo(0, "1s")])
        for type in ["hora", "ryukyoku", "end_kyoku"] {
            var t = s
            XCTAssertTrue(t.apply(["type": type, "actor": 0, "target": 0]))
            XCTAssertTrue(t.isDone)
            XCTAssertEqual(t.legalActions(), [])
        }
        XCTAssertTrue(s.apply(["type": "kita", "actor": 0]))
        XCTAssertTrue(s.apply(Ev.kyoku([Ev.junk, Ev.junk, Ev.junk], oya: 1)))
        XCTAssertFalse(s.isDone)
        XCTAssertEqual(s.players[0].kitaCount, 0)
        XCTAssertEqual(s.players[0].discards, [])
        XCTAssertNil(s.drawnTile)
        XCTAssertNil(s.currentPlayer)
        XCTAssertEqual(s.legalActions(), [])
        XCTAssertTrue(SanmaState(seat: 0).isDone)
    }

    func testParsesLinesLikeMjaiCompat() {
        var s = SanmaState(seat: 0)
        let h = #"["1m","9m","1p","2p","3p","4p","5p","6p","7p","8p","9p","N","N"]"#
        XCTAssertTrue(s.apply(line: #"{"type":"start_game","names":["a","b","c",""]}"#))
        XCTAssertTrue(s.apply(line: """
            {"type":"start_kyoku","bakaze":"S","dora_marker":"1s","kyoku":2,"honba":3,"kyotaku":1,"oya":1,
             "scores":[30000,35000,40000,0],"tehais":[\(h),\(h),\(h),\(h)]}
            """))
        XCTAssertEqual(s.players.map(\.score), [30_000, 35_000, 40_000])
        XCTAssertEqual(s.players[2].hand.count, 13)
        XCTAssertEqual([s.roundWind, s.kyokuIndex, s.honba, s.riichiSticks, s.oya], [1, 1, 3, 1, 1])
        XCTAssertEqual(s.doraIndicators, [72])
        XCTAssertTrue(s.apply(line: #"{"type":"dora","dora_marker":"E"}"#))
        XCTAssertEqual(s.doraIndicators, [72, 108])
        XCTAssertTrue(s.apply(line: #"{"type":"end_game"}"#))

        for bad in ["", "   ", "{oops", #"{"type":"some_future_event"}"#, #"{"type":"tsumo","actor":3,"pai":"1m"}"#,
                    #"{"type":"dahai","actor":0}"#, #"{"type":"start_kyoku","scores":[1,2]}"#, "[1,2]",
                    #"{"type":"reach"}"#, #"{"type":"pon","actor":0,"pai":"N","consumed":["N"]}"#] {
            var t = s
            XCTAssertFalse(t.apply(line: bad), bad)
        }
    }

    func testRejectsEventsMissingFields() {
        var s = Ev.play(0, [Ev.kyoku([Ev.junk, Ev.junk, Ev.junk])])
        for e: [String: Any] in [
            ["type": "reach_accepted"], ["type": "kita"], ["type": "nukidora"], ["type": "dora"],
            ["type": "kan", "actor": 0, "pai": "N"], ["type": "ankan", "actor": 0], ["type": "kakan", "actor": 0],
            ["type": "tsumo", "actor": 0], ["type": "pon", "actor": 0, "consumed": ["N", "N"]],
        ] {
            XCTAssertFalse(s.apply(e), "\(e)")
        }
        XCTAssertFalse(s.apply(["type": "start_kyoku", "kyoku": 1, "honba": 0, "kyoutaku": 0, "oya": 3,
                                "scores": [1, 2, 3], "dora_marker": "1s", "tehais": [[String]]()]))
    }

    func testAdaptRotatesSeatsFromDecider() {
        let s = Ev.play(1, [Ev.kyoku([Ev.junk, Ev.tenpai, Ev.junk], oya: 0, scores: [30_000, 35_000, 40_000])])
        let e = s.encInput()
        XCTAssertEqual(e.seats.map(\.score), [35_000, 40_000, 30_000])
        XCTAssertEqual(e.seatWind, 1)
        XCTAssertFalse(e.isDealer)
        XCTAssertEqual(e.waits, [18, 27])
        XCTAssertTrue(e.isTenpai)
        XCTAssertEqual(e.turnCount, 0)
        XCTAssertEqual(e.doraIndicators, [72])
        XCTAssertNotNil(e.encode())

        let dealer = Ev.play(1, [Ev.kyoku([Ev.junk, Ev.tenpai, Ev.junk], oya: 1)]).encInput()
        XCTAssertEqual(dealer.seatWind, 0)
        XCTAssertTrue(dealer.isDealer)
        XCTAssertEqual(Ev.play(2, [Ev.kyoku([Ev.junk, Ev.junk, Ev.junk], oya: 0)]).encInput().seatWind, 2)

        let drew = Ev.play(1, [Ev.kyoku([Ev.junk, Ev.tenpai, Ev.junk], oya: 1), Ev.tsumo(1, "9m")]).encInput()
        XCTAssertEqual(drew.waits, [])
        XCTAssertFalse(drew.isTenpai)
    }

    func testAdaptCarriesMeldsDiscardsAndKita() {
        let hand = ["P", "P", "N", "2s", "4s", "6s", "8s", "2p", "4p", "6p", "8p", "3s", "7s"]
        let s = Ev.play(2, [Ev.kyoku([hand, Ev.junk, Ev.junk]), Ev.tsumo(0, "9m"), Ev.dahai(0, "9m"),
                            Ev.tsumo(1, "P"), Ev.dahai(1, "P"), Ev.pon(0, "P", ["P", "P"]), Ev.dahai(0, "2s"),
                            Ev.tsumo(1, "N"), ["type": "kita", "actor": 1]])
        let e = s.encInput()
        XCTAssertEqual(e.seats[1].meldTiles, [124, 124, 124])
        XCTAssertEqual(e.seats[1].discards, [tid("9m"), tid("2s")])
        XCTAssertEqual(e.seats[2].discards, [124])
        XCTAssertEqual(e.seats[2].kitaCount, 1)
        XCTAssertEqual(e.lastDiscard, tid("2s"))
    }
}

final class SanmaHandShapeTests: XCTestCase {
    func testWaitsAndAgariSpecialHands() {
        let kokushi13 = ["1m", "9m", "1p", "9p", "1s", "9s", "E", "S", "W", "N", "P", "F", "C"].map(tid)
        XCTAssertEqual(SanmaState.waits(kokushi13, []).count, 13)
        let chiitoi = ["1m", "1m", "9m", "9m", "1p", "1p", "3p", "3p", "5s", "5s", "E", "E", "C"].map(tid)
        XCTAssertEqual(SanmaState.waits(chiitoi, []), [33])
        let fourOfAKind = ["1m", "1m", "1m", "1m", "9m", "9m", "1p", "1p", "3p", "3p", "5s", "5s", "E"].map(tid)
        XCTAssertFalse(SanmaState.waits(fourOfAKind, []).contains(27))
        XCTAssertTrue(SanmaState.completes(chiitoi, [], with: tid("C")))
        XCTAssertFalse(SanmaState.completes(chiitoi, [], with: tid("F")))
        XCTAssertEqual(SanmaState.waits(chiitoi.dropLast(), []), [])
    }

    func testWaitsCountMeldsAsThreeAndKanNormalization() {
        let pon = SanmaMeld(kind: .pon, tiles: [132, 132, 132])
        let kan = SanmaMeld(kind: .daiminkan, tiles: [128, 128, 128, 128])
        let ten = ["1p", "2p", "3p", "4p", "5p", "6p", "7p", "8p", "9p", "E"].map(tid)
        XCTAssertEqual(SanmaState.waits(ten, [pon]), [27])
        XCTAssertEqual(SanmaState.waits(ten, [kan]), [27])
        XCTAssertEqual(SanmaState.counts([128, 128, 128, 128], [kan])[32], 3)
        XCTAssertEqual(SanmaState.counts([128, 128, 128, 128], [pon])[32], 4)
        XCTAssertEqual(SanmaState.counts([128, 128, 128, 128])[32], 4)
        for k in [SanmaMeld.Kind.ankan, .kakan] {
            XCTAssertEqual(SanmaState.counts([128, 128, 128, 128], [SanmaMeld(kind: k, tiles: [128])])[32], 3)
        }
        XCTAssertTrue(SanmaState.completes(ten + [108], [pon], with: 0))
        XCTAssertFalse(SanmaState.completes(ten, [pon], with: 0))
    }

    func testAgariRejectsImpossibleCounts() {
        var c = [Int](repeating: 0, count: 34)
        c[0] = 14
        XCTAssertFalse(SanmaState.isAgari(c))
        c[0] = 5; c[8] = 3; c[9] = 3; c[18] = 3
        XCTAssertFalse(SanmaState.isAgari(c))
        c[0] = 2
        XCTAssertTrue(SanmaState.isAgari(c))
    }

    func testYaochu() {
        XCTAssertEqual((0..<34).filter { SanmaState.isYaochu(UInt8($0 * 4)) }, [0, 8, 9, 17, 18, 26, 27, 28, 29, 30, 31, 32, 33])
    }

    /// 以 riichienv `agari.rs` 的回溯分解當參考，隨機手牌比對 ShantenCalculator 版判定。
    func testAgariMatchesRiichienvDecomposition() {
        var rng = SystemRandomNumberGenerator()
        let pool = [0, 8] + Array(9..<34)
        for _ in 0..<4000 {
            let n = [2, 3, 5, 8, 11, 13, 14, 14, 14].randomElement(using: &rng)!
            var c = [Int](repeating: 0, count: 34)
            while c.reduce(0, +) < n {
                let t = pool.randomElement(using: &rng)!
                if c[t] < 4 { c[t] += 1 }
            }
            XCTAssertEqual(SanmaState.isAgari(c), Self.referenceAgari(c), "\(c)")
        }
    }

    static func referenceAgari(_ c: [Int]) -> Bool {
        let yaochu = [0, 8, 9, 17, 18, 26, 27, 28, 29, 30, 31, 32, 33]
        if yaochu.allSatisfy({ c[$0] >= 1 && c[$0] <= 2 }) && yaochu.filter({ c[$0] == 2 }).count == 1 { return true }
        if c.filter({ $0 == 2 }).count == 7 && c.allSatisfy({ $0 == 0 || $0 == 2 }) { return true }
        func decompose(_ h: inout [Int], _ start: Int) -> Bool {
            guard let i = (start..<34).first(where: { h[$0] > 0 }) else { return true }
            if h[i] >= 3 {
                h[i] -= 3
                defer { h[i] += 3 }
                if decompose(&h, i) { return true }
            }
            if i < 27, i % 9 <= 6, h[i + 1] > 0, h[i + 2] > 0 {
                for d in 0...2 { h[i + d] -= 1 }
                defer { for d in 0...2 { h[i + d] += 1 } }
                if decompose(&h, i) { return true }
            }
            return false
        }
        var h = c
        for i in 0..<34 where h[i] >= 2 {
            h[i] -= 2
            defer { h[i] += 2 }
            if decompose(&h, 0) { return true }
        }
        return false
    }
}
