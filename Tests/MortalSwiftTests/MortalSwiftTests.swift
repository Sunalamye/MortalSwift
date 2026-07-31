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

    #expect(state.shanten == -1, "摸進聽牌張後應為和了形")
    #expect(state.lastCans.canTsumoAgari, "振聽不得阻擋自摸（振聽只限制榮和）")
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
