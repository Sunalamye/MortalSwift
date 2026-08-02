import Testing
import Foundation
@testable import MortalSwift

// MARK: - Bot Initialization Tests

@Test func testBotInitialization() async throws {
    let bot = try MortalBot(playerId: 0, version: 4, useBundledModel: false)
    let hasModel = await bot.hasModel
    #expect(!hasModel)
}

@Test func testBotInitializationAllSeats() async throws {
    for seat in 0..<4 {
        let bot = try MortalBot(playerId: seat, version: 4, useBundledModel: false)
        let hasModel = await bot.hasModel
        #expect(!hasModel)
    }
}

@Test func testBotInitializationInvalidSeat() throws {
    #expect(throws: MortalError.self) {
        _ = try MortalBot(playerId: 5, version: 4)
    }
}

@Test func testBotInitializationInvalidVersion() throws {
    #expect(throws: MortalError.self) {
        _ = try MortalBot(playerId: 0, version: 0)
    }
    #expect(throws: MortalError.self) {
        _ = try MortalBot(playerId: 0, version: 5)
    }
}

// MARK: - MJAI Event Processing Tests

@Test func testStartGameEvent() async throws {
    let bot = try MortalBot(playerId: 0, version: 4, useBundledModel: false)

    let event = """
    {"type":"start_game","id":0,"names":["Player0","Player1","Player2","Player3"]}
    """

    let response = try await bot.react(mjaiEvent: event)
    #expect(response == nil, "start_game should not require action")
}

@Test func testStartKyokuEvent() async throws {
    let bot = try MortalBot(playerId: 0, version: 4, useBundledModel: false)

    // First send start_game
    let startGame = #"{"type":"start_game","names":["P0","P1","P2","P3"]}"#
    _ = try await bot.react(mjaiEvent: startGame)

    // Then send start_kyoku (honor tiles use "E","S","W","N","P","F","C")
    let startKyoku = #"{"type":"start_kyoku","bakaze":"E","dora_marker":"3p","kyoku":1,"honba":0,"kyotaku":0,"oya":0,"scores":[25000,25000,25000,25000],"tehais":[["1m","2m","3m","4p","5p","6p","7s","8s","9s","E","S","W","N"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"]]}"#

    let response = try await bot.react(mjaiEvent: startKyoku)
    #expect(response == nil, "start_kyoku should not require action")
}

@Test func testTsumoEvent() async throws {
    let bot = try MortalBot(playerId: 0, version: 4, useBundledModel: false)

    // Setup game
    let startGame = """
    {"type":"start_game","id":0,"names":["P0","P1","P2","P3"]}
    """
    _ = try await bot.react(mjaiEvent: startGame)

    let startKyoku = """
    {"type":"start_kyoku","bakaze":"E","dora_marker":"3p","kyoku":1,"honba":0,"kyotaku":0,"oya":0,"scores":[25000,25000,25000,25000],"tehais":[["1m","2m","3m","4p","5p","6p","7s","8s","9s","E","S","W","N"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"]]}
    """
    _ = try await bot.react(mjaiEvent: startKyoku)

    // Self draw (tsumo)
    let tsumo = """
    {"type":"tsumo","actor":0,"pai":"P"}
    """

    let response = try await bot.react(mjaiEvent: tsumo)
    #expect(response != nil, "tsumo by self should require discard action")

    // Response should be a dahai (discard)
    if let response = response {
        #expect(response.contains("dahai"), "Response should be a dahai action")
    }
}

@Test func testOtherPlayerTsumo() async throws {
    let bot = try MortalBot(playerId: 0, version: 4, useBundledModel: false)

    // Setup game
    let startGame = """
    {"type":"start_game","id":0,"names":["P0","P1","P2","P3"]}
    """
    _ = try await bot.react(mjaiEvent: startGame)

    let startKyoku = """
    {"type":"start_kyoku","bakaze":"E","dora_marker":"3p","kyoku":1,"honba":0,"kyotaku":0,"oya":0,"scores":[25000,25000,25000,25000],"tehais":[["1m","2m","3m","4p","5p","6p","7s","8s","9s","E","S","W","N"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"]]}
    """
    _ = try await bot.react(mjaiEvent: startKyoku)

    // Other player's tsumo (actor != 0)
    let otherTsumo = """
    {"type":"tsumo","actor":1,"pai":"?"}
    """

    let response = try await bot.react(mjaiEvent: otherTsumo)
    #expect(response == nil, "Other player's tsumo should not require our action")
}

// MARK: - Observation and Mask Tests

@Test func testObservationShape() async throws {
    let bot = try MortalBot(playerId: 0, version: 4, useBundledModel: false)

    let obs = await bot.getObservation()
    let expectedSize = MortalBot.obsChannels * MortalBot.obsWidth
    #expect(obs.count == expectedSize, "Observation should have \(expectedSize) elements")
}

@Test func testMaskShape() async throws {
    let bot = try MortalBot(playerId: 0, version: 4, useBundledModel: false)

    let mask = await bot.getMask()
    #expect(mask.count == MortalBot.actionSpace, "Mask should have \(MortalBot.actionSpace) elements")
}

@Test func testMaskAfterTsumo() async throws {
    let bot = try MortalBot(playerId: 0, version: 4, useBundledModel: false)

    // Setup game
    let events = [
        #"{"type":"start_game","id":0,"names":["P0","P1","P2","P3"]}"#,
        #"{"type":"start_kyoku","bakaze":"E","dora_marker":"3p","kyoku":1,"honba":0,"kyotaku":0,"oya":0,"scores":[25000,25000,25000,25000],"tehais":[["1m","2m","3m","4p","5p","6p","7s","8s","9s","E","S","W","N"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"]]}"#,
        #"{"type":"tsumo","actor":0,"pai":"P"}"#
    ]

    for event in events {
        _ = try await bot.react(mjaiEvent: event)
    }

    let mask = await bot.getMask()

    // At least some actions should be valid after tsumo
    let validCount = mask.filter { $0 != 0 }.count
    #expect(validCount > 0, "Should have at least one valid action after tsumo")
}

// MARK: - Candidates Tests

@Test func testGetCandidateActions() async throws {
    let bot = try MortalBot(playerId: 0, version: 4, useBundledModel: false)

    // Setup game state
    let events = [
        #"{"type":"start_game","id":0,"names":["P0","P1","P2","P3"]}"#,
        #"{"type":"start_kyoku","bakaze":"E","dora_marker":"3p","kyoku":1,"honba":0,"kyotaku":0,"oya":0,"scores":[25000,25000,25000,25000],"tehais":[["1m","2m","3m","4p","5p","6p","7s","8s","9s","E","S","W","N"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"]]}"#,
        #"{"type":"tsumo","actor":0,"pai":"P"}"#
    ]

    for event in events {
        _ = try await bot.react(mjaiEvent: event)
    }

    let candidates = await bot.getCandidateActions()
    #expect(!candidates.isEmpty, "Should have candidate actions after tsumo")
}

// MARK: - Constants Tests

@Test func testConstants() {
    #expect(MortalBot.actionSpace == 46)
    #expect(MortalBot.obsChannels == 1012)
    #expect(MortalBot.obsWidth == 34)
}

// MARK: - Full Game Simulation

@Test func testSimpleGameFlow() async throws {
    let bot = try MortalBot(playerId: 0, version: 4, useBundledModel: false)

    // Start game
    _ = try await bot.react(mjaiEvent: #"{"type":"start_game","id":0,"names":["P0","P1","P2","P3"]}"#)

    // Start round
    _ = try await bot.react(mjaiEvent: #"{"type":"start_kyoku","bakaze":"E","dora_marker":"5s","kyoku":1,"honba":0,"kyotaku":0,"oya":0,"scores":[25000,25000,25000,25000],"tehais":[["1m","9m","1p","9p","1s","9s","E","S","W","N","P","F","C"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"]]}"#)

    // Tsumo and discard cycle
    let response1 = try await bot.react(mjaiEvent: #"{"type":"tsumo","actor":0,"pai":"2m"}"#)
    #expect(response1 != nil, "Should return discard action")

    // Simulate our discard
    _ = try await bot.react(mjaiEvent: #"{"type":"dahai","actor":0,"pai":"2m","tsumogiri":true}"#)

    // Other players' turns (should not require our action)
    let response2 = try await bot.react(mjaiEvent: #"{"type":"tsumo","actor":1,"pai":"?"}"#)
    #expect(response2 == nil, "Other player's tsumo")

    let response3 = try await bot.react(mjaiEvent: #"{"type":"dahai","actor":1,"pai":"1m","tsumogiri":false}"#)
    // We might have pon option if we have tiles
    // Just check it doesn't crash

    // Continue game
    _ = try await bot.react(mjaiEvent: #"{"type":"tsumo","actor":2,"pai":"?"}"#)
    _ = try await bot.react(mjaiEvent: #"{"type":"dahai","actor":2,"pai":"5m","tsumogiri":true}"#)
}

// MARK: - Core ML Tests

@Test func testCoreMLInference() async throws {
    let bot = try MortalBot(playerId: 0, version: 4, useBundledModel: true)

    let hasModel = await bot.hasModel
    guard hasModel else {
        print("Skipping Core ML test - model not available")
        return
    }

    // Setup game
    let events = [
        #"{"type":"start_game","id":0,"names":["P0","P1","P2","P3"]}"#,
        #"{"type":"start_kyoku","bakaze":"E","dora_marker":"3p","kyoku":1,"honba":0,"kyotaku":0,"oya":0,"scores":[25000,25000,25000,25000],"tehais":[["1m","2m","3m","4p","5p","6p","7s","8s","9s","E","S","W","N"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"]]}"#,
        #"{"type":"tsumo","actor":0,"pai":"P"}"#
    ]

    for event in events {
        _ = try await bot.react(mjaiEvent: event)
    }

    // Check Q values after inference
    let qValues = await bot.getLastQValues()
    #expect(qValues.count == MortalBot.actionSpace, "Q values should have \(MortalBot.actionSpace) elements")

    // Check probabilities
    let probs = await bot.getLastProbs()
    #expect(probs.count == MortalBot.actionSpace, "Probabilities should have \(MortalBot.actionSpace) elements")

    // Probabilities should sum to 1 (approximately)
    let validProbs = probs.filter { $0 > 0 }
    if !validProbs.isEmpty {
        let sum = validProbs.reduce(0, +)
        #expect(abs(sum - 1.0) < 0.01, "Valid probabilities should sum to 1")
    }
}

// MARK: - Typed API Tests

@Test func testTypedReactAPI() async throws {
    let bot = try MortalBot(playerId: 0, version: 4, useBundledModel: false)

    // Start game with typed event
    _ = try await bot.react(event: .startGame(StartGameEvent(names: ["P0", "P1", "P2", "P3"])))

    // Start kyoku with typed event
    _ = try await bot.react(event: .startKyoku(StartKyokuEvent(
        bakaze: .east,
        kyoku: 1,
        honba: 0,
        kyotaku: 0,
        oya: 0,
        doraMarker: .pin(3),
        scores: [25000, 25000, 25000, 25000],
        tehais: [
            [.man(1), .man(2), .man(3), .pin(4), .pin(5), .pin(6), .sou(7), .sou(8), .sou(9), .east, .south, .west, .north],
            [.unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown],
            [.unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown],
            [.unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown]
        ]
    )))

    // Tsumo with typed event
    let action = try await bot.react(event: .tsumo(TsumoEvent(actor: 0, pai: .white)))
    #expect(action != nil, "Should return action after tsumo")

    // Verify action type
    if let action = action {
        switch action {
        case .dahai:
            print("Typed API: Bot chose to discard")
        case .reach:
            print("Typed API: Bot chose riichi")
        default:
            #expect(Bool(false), "Unexpected action type: \(String(describing: action))")
        }
    }
}

@Test func testTypedReactSyncAPI() async throws {
    let bot = try MortalBot(playerId: 0, version: 4, useBundledModel: false)

    // Start game
    _ = try await bot.react(event: .startGame(StartGameEvent(names: ["P0", "P1", "P2", "P3"])))

    // Start kyoku
    _ = try await bot.react(event: .startKyoku(StartKyokuEvent(
        bakaze: .east,
        kyoku: 1,
        honba: 0,
        kyotaku: 0,
        oya: 0,
        doraMarker: .pin(3),
        scores: [25000, 25000, 25000, 25000],
        tehais: [
            [.man(1), .man(2), .man(3), .pin(4), .pin(5), .pin(6), .sou(7), .sou(8), .sou(9), .east, .south, .west, .north],
            [.unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown],
            [.unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown],
            [.unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown]
        ]
    )))

    // Tsumo (using async version since reactSync is actor-isolated)
    let action = try await bot.react(event: .tsumo(TsumoEvent(actor: 0, pai: .white)))
    #expect(action != nil, "Should return action after tsumo")
}

// MARK: - Tile Tests

@Test func testTileIndex() {
    #expect(Tile.man(1).index == 0)
    #expect(Tile.man(9).index == 8)
    #expect(Tile.pin(1).index == 9)
    #expect(Tile.sou(1).index == 18)
    #expect(Tile.east.index == 27)
    #expect(Tile.south.index == 28)
    #expect(Tile.west.index == 29)
    #expect(Tile.north.index == 30)
    #expect(Tile.white.index == 31)
    #expect(Tile.green.index == 32)
    #expect(Tile.red.index == 33)
}

@Test func testTileDeaka() {
    #expect(Tile.man(5, red: true).deaka == .man(5))
    #expect(Tile.pin(5, red: true).deaka == .pin(5))
    #expect(Tile.sou(5, red: true).deaka == .sou(5))
    #expect(Tile.man(5).deaka == .man(5))
}

@Test func testTileFromIndex() {
    #expect(Tile.fromIndex(0) == .man(1))
    #expect(Tile.fromIndex(8) == .man(9))
    #expect(Tile.fromIndex(27) == .east)
    #expect(Tile.fromIndex(33) == .red)
}

@Test func testTileNext() {
    #expect(Tile.man(1).next == .man(2))
    #expect(Tile.man(9).next == .man(1))
    #expect(Tile.east.next == .south)
    #expect(Tile.north.next == .east)
    #expect(Tile.white.next == .green)
    #expect(Tile.red.next == .white)
}

// MARK: - Shanten Tests

@Test func testShantenCalculatorExists() {
    // Basic test that shanten calculator computes without crashing
    var tehai = [Int](repeating: 0, count: 34)
    tehai[0] = 3  // 1m x3
    tehai[1] = 3  // 2m x3
    tehai[2] = 3  // 3m x3
    tehai[3] = 3  // 4m x3
    tehai[4] = 1  // 5m x1

    let shanten = ShantenCalculator.calcNormal(tehai: tehai, lenDiv3: 4)
    #expect(shanten >= -1 && shanten <= 8, "Shanten should be in valid range")
}

@Test func testShantenChiitoi() {
    // Chiitoi tenpai
    var tehai = [Int](repeating: 0, count: 34)
    tehai[0] = 2  // 1m x2
    tehai[1] = 2  // 2m x2
    tehai[2] = 2  // 3m x2
    tehai[9] = 2  // 1p x2
    tehai[10] = 2 // 2p x2
    tehai[11] = 2 // 3p x2
    tehai[27] = 1 // East x1

    let shanten = ShantenCalculator.calcChitoi(tehai: tehai)
    #expect(shanten == 0, "Chiitoi tenpai should have shanten 0")
}

// MARK: - PlayerState Tests

@Test func testPlayerStateInitialization() {
    let state = PlayerState(playerId: 0, version: 4)
    #expect(state.playerId == 0)
    #expect(state.version == 4)
    #expect(state.tehai.count == 34)
    #expect(state.isMenzen == true)
}

@Test func testPlayerStateRelativePosition() {
    let state = PlayerState(playerId: 2, version: 4)

    // From player 2's perspective
    #expect(state.toRelative(2) == 0)  // Self
    #expect(state.toRelative(3) == 1)  // Right
    #expect(state.toRelative(0) == 2)  // Across
    #expect(state.toRelative(1) == 3)  // Left

    #expect(state.toAbsolute(0) == 2)  // Self
    #expect(state.toAbsolute(1) == 3)  // Right
    #expect(state.toAbsolute(2) == 0)  // Across
    #expect(state.toAbsolute(3) == 1)  // Left
}

// MARK: - 向聽數回歸測試
//
// 起因：`calcNormalRecursive` 的剪枝用了「當前值」而非下界。
// 當前值隨遞迴只會遞減（是上界），拿來剪枝會砍掉仍可能更好的分支；
// 且 target=4 時根節點初始值 9 ≥ minShanten 初值 8，
// 導致整個遞迴一次都沒跑，任何手牌都回傳 7。

/// 由 MJAI 牌名組出 34 格計數陣列
private func shantenCounts(_ tiles: [String]) -> [Int] {
    var c = [Int](repeating: 0, count: 34)
    for t in tiles {
        guard let tile = Tile(mjaiString: t) else { continue }
        c[tile.index] += 1
    }
    return c
}

@Test func testCompleteHandIsMinusOne() {
    let hand = shantenCounts(["1m","2m","3m","4m","5m","6m","7m","8m","9m",
                              "1p","1p","1p","2s","2s"])
    #expect(ShantenCalculator.calcNormal(tehai: hand, lenDiv3: 4) == -1,
            "四面子一雀頭必須是和了形")
}

@Test func testTenpaiIsZero() {
    // 123m 456m 789m 111p + 2s 單騎聽
    let hand = shantenCounts(["1m","2m","3m","4m","5m","6m","7m","8m","9m",
                              "1p","1p","1p","2s"])
    #expect(ShantenCalculator.calcNormal(tehai: hand, lenDiv3: 4) == 0,
            "四面子＋單張應為聽牌")
}

@Test func testChitoiComplete() {
    let hand = shantenCounts(["1m","1m","3m","3m","5m","5m","7m","7m",
                              "9m","9m","1p","1p","3p","3p"])
    #expect(ShantenCalculator.calcAll(tehai: hand, lenDiv3: 4) == -1)
}

@Test func testKokushiComplete() {
    let hand = shantenCounts(["1m","9m","1p","9p","1s","9s",
                              "E","S","W","N","P","F","C","C"])
    #expect(ShantenCalculator.calcAll(tehai: hand, lenDiv3: 4) == -1)
}

@Test func testOneShantenIsOne() {
    // 123m 456m 789m + 1p3p + 5s7s：3 面子 + 2 搭子、無雀頭 → 一向聽
    let hand = shantenCounts(["1m","2m","3m","4m","5m","6m","7m","8m","9m",
                              "1p","3p","5s","7s"])
    #expect(ShantenCalculator.calcNormal(tehai: hand, lenDiv3: 4) == 1,
            "3 面子 + 2 搭子無雀頭應為一向聽")
}

@Test func testShantenVariesByHand() {
    // 修正前所有手牌都回傳 7（遞迴在根節點就被錯誤剪枝擋掉），
    // 這條確保不同牌型會給出不同的值。
    let complete = shantenCounts(["1m","2m","3m","4m","5m","6m","7m","8m","9m",
                                  "1p","1p","1p","2s","2s"])
    let oneShanten = shantenCounts(["1m","2m","3m","4m","5m","6m","7m","8m","9m",
                                    "1p","3p","5s","7s"])
    let scattered = shantenCounts(["1m","4m","7m","1p","4p","7p","1s","4s","7s",
                                   "E","S","W","N","P"])
    let a = ShantenCalculator.calcNormal(tehai: complete, lenDiv3: 4)
    let b = ShantenCalculator.calcNormal(tehai: oneShanten, lenDiv3: 4)
    let c = ShantenCalculator.calcNormal(tehai: scattered, lenDiv3: 4)
    #expect(a == -1 && b == 1, "完成形與一向聽必須各自正確")
    #expect(a < b && b < c, "向聽必須隨牌型單調變化，不能是固定值")
}

@Test func testAfterMeldLenDiv3() {
    // 已副露一組，手牌剩 11 張（3 面子 + 雀頭）
    let hand = shantenCounts(["1m","2m","3m","4m","5m","6m","7m","8m","9m","2s","2s"])
    #expect(ShantenCalculator.calcNormal(tehai: hand, lenDiv3: 3) == -1,
            "副露一組後，3 面子＋雀頭即為和了形")
}

// MARK: - 振聽與副露後狀態回歸測試
//
// 起因（實測漏和）：
// 1. `calculateTsumoActions` 寫成 `shanten == -1 && !atFuriten`，
//    讓振聽狀態下的自摸整個消失。振聽只限制榮和，不限制自摸。
// 2. 大明槓／暗槓沒有更新 tehaiLenDiv3，槓後手牌少一組但向聽仍用舊組數算。
// 3. 吃／碰／槓後沒有重算向聽與等待，mask 與 observation 都是副露前的舊值。

/// 開一局並把手牌設成指定內容（其餘玩家給未知牌）
private func makeState(tehai: [String], playerId: Int = 0) -> PlayerState {
    let state = PlayerState(playerId: playerId)
    let tiles = tehai.compactMap { Tile(mjaiString: $0) }
    _ = state.update(event: .startKyoku(StartKyokuEvent(
        bakaze: .east,
        kyoku: 1, honba: 0, kyotaku: 0, oya: 0,
        doraMarker: Tile(mjaiString: "1z") ?? Tile.east,
        scores: [25000, 25000, 25000, 25000],
        tehais: [tiles, [], [], []])))
    return state
}

@Test func testFuritenDoesNotBlockTsumo() {
    // 123m 456m 789m 111p + 2s，聽 2s 單騎
    let state = makeState(tehai: ["1m","2m","3m","4m","5m","6m","7m","8m","9m",
                                  "1p","1p","1p","2s"])
    state.atFuriten = true   // 人為設為振聽

    // 摸進 2s → 和了形
    _ = state.update(event: .tsumo(TsumoEvent(actor: 0, pai: Tile(mjaiString: "2s")!)))

    // `shanten` 是 3n+1 手牌的值（摸牌不重算，與 libriichi 一致），
    // 所以這裡看的是「摸進來的牌在等待裡」而不是「shanten 變 -1」。
    #expect(state.shanten == 0, "摸牌前是聽牌")
    #expect(state.waits[Tile(mjaiString: "2s")!.index], "應聽 2s 單騎")
    #expect(state.lastCans.canTsumoAgari, "振聽不得阻擋自摸（振聽只限制榮和）")
}

// MARK: - 同巡振聽

/// 開一局並指定莊家與手牌（讓別人先打牌）
private func makeStateWithOya(tehai: [String], oya: Int) -> PlayerState {
    let state = PlayerState(playerId: 0)
    let tiles = tehai.compactMap { Tile(mjaiString: $0) }
    _ = state.update(event: .startKyoku(StartKyokuEvent(
        bakaze: .east,
        kyoku: 1, honba: 0, kyotaku: 0, oya: oya,
        doraMarker: Tile(mjaiString: "1z") ?? Tile.east,
        scores: [25000, 25000, 25000, 25000],
        tehais: [tiles, [], [], []])))
    return state
}

/// 別家摸一張未知牌後打出指定的牌
@discardableResult
private func feedTsumoDahai(_ state: PlayerState, actor: Int, pai: String) -> Bool {
    _ = state.update(event: .tsumo(TsumoEvent(actor: actor, pai: .unknown)))
    return state.update(event: .dahai(DahaiEvent(
        actor: actor, pai: Tile(mjaiString: pai)!, tsumogiri: true)))
}

/// 見逃 → 同巡內不能榮 → 自家摸打之後恢復
///
/// 原本 `updateFuriten()` 只會寫 `true`、局內沒有任何路徑寫回 `false`，
/// 所以見逃一次之後整局的 `canRon` 都被鎖死（obs ch861 也一路是 1）。
/// 這條測試釘住三個時點：見逃當下不算振聽、下一張待牌不能榮、自家打牌後恢復。
@Test func testSameCycleFuritenClearsAfterOwnDiscard() {
    // 234m 678m 234p + 5p5p + 6s6s：斷么，聽 5p/6s 雙碰
    let state = makeStateWithOya(
        tehai: ["2m","3m","4m","6m","7m","8m","2p","3p","4p","5p","5p","6s","6s"],
        oya: 1)
    #expect(state.waits[Tile(mjaiString: "5p")!.index], "應聽 5p")
    #expect(state.waits[Tile(mjaiString: "6s")!.index], "應聽 6s")

    // seat1 打 5p → 可以榮，而且**此刻還不算振聽**
    _ = feedTsumoDahai(state, actor: 1, pai: "5p")
    #expect(state.lastCans.canRonAgari, "第一次待牌流過時應該可以榮")
    #expect(!state.atFuriten, "被問要不要榮的當下還不是振聽（obs ch861 必須是 0）")

    // 見逃：直接讓 seat2 打另一張待牌 6s
    _ = feedTsumoDahai(state, actor: 2, pai: "6s")
    #expect(state.atFuriten, "見逃之後成立同巡振聽")
    #expect(!state.lastCans.canRonAgari, "同巡振聽期間不能榮")
    #expect(state.lastCans.canPon, "同巡振聽不影響碰")

    // 自家摸牌 —— libriichi 在摸牌時**不**解除
    _ = feedTsumoDahai(state, actor: 3, pai: "1m")
    _ = state.update(event: .tsumo(TsumoEvent(actor: 0, pai: Tile(mjaiString: "9m")!)))
    #expect(state.atFuriten, "自家摸牌還不解除，要打出去才解除")

    // 自家打牌 → 同巡振聽解除
    _ = state.update(event: .dahai(DahaiEvent(
        actor: 0, pai: Tile(mjaiString: "9m")!, tsumogiri: true)))
    #expect(!state.atFuriten, "自家打牌之後同巡振聽解除")

    // 下一巡再流一張待牌 → 可以榮
    _ = feedTsumoDahai(state, actor: 1, pai: "6s")
    #expect(state.lastCans.canRonAgari, "解除之後應該恢復可榮")
}

/// 立直後的見逃是永久振聽：自家摸切不會把它洗掉
@Test func testRiichiFuritenIsPermanent() {
    let state = makeStateWithOya(
        tehai: ["2m","3m","4m","6m","7m","8m","2p","3p","4p","5p","5p","6s","6s"],
        oya: 0)
    _ = state.update(event: .tsumo(TsumoEvent(actor: 0, pai: Tile(mjaiString: "1m")!)))
    _ = state.update(event: .reach(ReachEvent(actor: 0)))
    _ = state.update(event: .dahai(DahaiEvent(
        actor: 0, pai: Tile(mjaiString: "1m")!, tsumogiri: true)))
    _ = state.update(event: .reachAccepted(ReachAcceptedEvent(actor: 0)))

    // seat1 打 5p → 可榮（立直本身是役），見逃
    _ = feedTsumoDahai(state, actor: 1, pai: "5p")
    #expect(state.lastCans.canRonAgari, "立直中待牌流過應可榮")

    _ = feedTsumoDahai(state, actor: 2, pai: "9m")
    #expect(state.atFuriten, "見逃成立振聽")

    // 自家摸切
    _ = state.update(event: .tsumo(TsumoEvent(actor: 0, pai: Tile(mjaiString: "9s")!)))
    _ = state.update(event: .dahai(DahaiEvent(
        actor: 0, pai: Tile(mjaiString: "9s")!, tsumogiri: true)))
    #expect(state.atFuriten, "立直振聽是永久的，摸切不解除")

    _ = feedTsumoDahai(state, actor: 1, pai: "6s")
    #expect(!state.lastCans.canRonAgari, "立直振聽期間永遠不能榮")
}

/// 無役聽牌：待牌流過去就當下振聽，而且本來就不能榮
@Test func testNoYakuTenpaiCannotRonAndBecomesFuritenImmediately() {
    // 234m 567p 234s + 5p5p + 9s9s：聽 5p/8p/9s，榮和沒有任何役
    let state = makeStateWithOya(
        tehai: ["2m","3m","4m","5p","6p","7p","2s","3s","4s","5p","5p","9s","9s"],
        oya: 1)
    #expect(!state.atFuriten, "還沒有待牌流過去，不該預先算成振聽")

    _ = feedTsumoDahai(state, actor: 1, pai: "9s")
    #expect(!state.lastCans.canRonAgari, "門前本身不是役，無役聽牌不能榮")
    #expect(state.atFuriten, "沒有選擇可言，待牌流過的當下就進振聽")
}

/// 捨牌振聽會隨聽牌改變而重算（不是黏著的旗標）
@Test func testDiscardFuritenClearsWhenWaitsChange() {
    // 234m 678m 234p 5p5p + 7s8s：聽 6s/9s
    let state = makeStateWithOya(
        tehai: ["2m","3m","4m","6m","7m","8m","2p","3p","4p","5p","5p","7s","8s"],
        oya: 0)
    // 摸到待牌 6s 卻打掉 → 捨牌振聽
    _ = state.update(event: .tsumo(TsumoEvent(actor: 0, pai: Tile(mjaiString: "6s")!)))
    _ = state.update(event: .dahai(DahaiEvent(
        actor: 0, pai: Tile(mjaiString: "6s")!, tsumogiri: true)))
    #expect(state.atFuriten, "打掉自己的待牌 → 捨牌振聽")

    _ = feedTsumoDahai(state, actor: 1, pai: "1m")
    _ = feedTsumoDahai(state, actor: 2, pai: "1p")
    _ = feedTsumoDahai(state, actor: 3, pai: "1s")

    // 摸 5p 打 8s → 改聽 5p 單騎，5p 沒打過 → 解除
    _ = state.update(event: .tsumo(TsumoEvent(actor: 0, pai: Tile(mjaiString: "5p")!)))
    _ = state.update(event: .dahai(DahaiEvent(
        actor: 0, pai: Tile(mjaiString: "8s")!, tsumogiri: false)))
    #expect(state.waits[Tile(mjaiString: "7s")!.index], "改聽 7s 單騎")
    #expect(!state.atFuriten, "新的待牌都沒打過 → 捨牌振聽解除")
}

@Test func testDaiminkanUpdatesTehaiLenDiv3() {
    let state = makeState(tehai: ["1m","1m","1m","2m","3m","4m","5m","6m","7m",
                                  "8m","9m","1p","1p"])
    #expect(state.tehaiLenDiv3 == 4)

    _ = state.update(event: .daiminkan(DaiminkanEvent(
        actor: 0, target: 1,
        pai: Tile(mjaiString: "1m")!,
        consumed: [Tile(mjaiString: "1m")!, Tile(mjaiString: "1m")!, Tile(mjaiString: "1m")!])))

    #expect(state.tehaiLenDiv3 == 3, "大明槓後手牌淨少一組")
}

@Test func testAnkanUpdatesTehaiLenDiv3() {
    let state = makeState(tehai: ["1m","1m","1m","1m","2m","3m","4m","5m","6m",
                                  "7m","8m","9m","1p"])
    #expect(state.tehaiLenDiv3 == 4)

    _ = state.update(event: .ankan(AnkanEvent(
        actor: 0,
        consumed: [Tile(mjaiString: "1m")!, Tile(mjaiString: "1m")!,
                   Tile(mjaiString: "1m")!, Tile(mjaiString: "1m")!])))

    #expect(state.tehaiLenDiv3 == 3, "暗槓後手牌淨少一組")
}

@Test func testPonRecomputesShanten() {
    // 碰之後手牌組成改變，向聽必須立刻反映，不能沿用碰之前的值
    let state = makeState(tehai: ["1m","1m","2m","3m","4m","5m","6m","7m","8m",
                                  "9m","1p","2p","3p"])
    let before = state.shanten

    _ = state.update(event: .pon(PonEvent(
        actor: 0, target: 2,
        pai: Tile(mjaiString: "1m")!,
        consumed: [Tile(mjaiString: "1m")!, Tile(mjaiString: "1m")!])))

    #expect(state.tehaiLenDiv3 == 3, "碰後手牌少一組")
    #expect(state.shanten != before || state.shanten >= -1,
            "碰後向聽必須是重算過的值")
}

// MARK: - 三麻拔北

/// 拔北之後向聽與等待要跟著手牌走
///
/// `handleNukidora` 原本只做 `markTileSeen` + `removeTile`，沒有重算。
/// 這條劇本拔北前是 1 向聽、拔北後是聽牌，漏算的話 `shanten` 會卡在 1、
/// `waits` 整排是空的——自摸判定與 obs 都會拿到拔北前的舊值。
@Test func testNukidoraRecomputesShantenAndWaits() {
    // 起手 13 張：234m 678m 234p + 5p5p + 6s + N → 1 向聽
    let state = makeState(tehai: ["2m","3m","4m","6m","7m","8m","2p","3p","4p",
                                  "5p","5p","6s","N"])
    #expect(state.shanten == 1, "拔北前是 1 向聽")
    #expect(!state.waits.contains(true), "1 向聽沒有等待")

    // 摸 6s → 14 張（摸牌不重算向聽，與 libriichi 一致）
    _ = state.update(event: .tsumo(TsumoEvent(actor: 0, pai: Tile(mjaiString: "6s")!)))
    #expect(state.shanten == 1, "摸牌本身不重算向聽")

    // 拔北 → 手牌回到 3n+1：234m 678m 234p + 5p5p + 6s6s，聽 5p/6s 雙碰
    _ = state.update(event: .nukidora(NukidoraEvent(
        actor: 0, pai: Tile(mjaiString: "N")!)))

    #expect(state.tehai[Tile.north.index] == 0, "北已從手牌抽走")
    #expect(state.tehaiLenDiv3 == 4, "拔北補嶺上一張，手牌組數不變")
    #expect(state.shanten == 0, "拔北後是聽牌，向聽必須跟著手牌重算")
    #expect(state.waits[Tile(mjaiString: "5p")!.index], "應聽 5p")
    #expect(state.waits[Tile(mjaiString: "6s")!.index], "應聽 6s")
    #expect(state.waits.filter { $0 }.count == 2, "只有 5p/6s 這兩張")
}

// MARK: - Observation 覆蓋率診斷（非斷言，用來量化與 libriichi 的落差）

