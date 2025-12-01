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
        let bot = try MortalBot(playerId: UInt8(seat), version: 4, useBundledModel: false)
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

// MARK: - Action Selection Tests

@Test func testManualActionSelection() async throws {
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

    // Try to select pass action
    let passResponse = await bot.selectActionManually(actionIdx: 45)
    // Pass might not always be valid, so we just check it returns something or nil

    // Try to select a discard action (should work after tsumo)
    let discardResponse = await bot.selectActionManually(actionIdx: 27)  // Discard East
    #expect(discardResponse != nil || passResponse != nil, "At least one action should be valid")
}

// MARK: - Candidates Tests

@Test func testGetCandidates() async throws {
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

    let candidates = await bot.getCandidates()
    #expect(candidates != nil, "Should return candidates JSON")

    if let candidates = candidates {
        #expect(candidates.contains("can_discard"), "Candidates should include can_discard field")
    }
}

// MARK: - Action Enum Tests

@Test func testMahjongActionDescription() {
    #expect(MahjongAction.discard1m.description == "Discard 1m")
    #expect(MahjongAction.riichi.description == "Riichi")
    #expect(MahjongAction.pon.description == "Pon")
    #expect(MahjongAction.hora.description == "Hora (Win)")
    #expect(MahjongAction.pass.description == "Pass")
}

@Test func testMahjongActionRawValues() {
    #expect(MahjongAction.discard1m.rawValue == 0)
    #expect(MahjongAction.riichi.rawValue == 37)
    #expect(MahjongAction.chiLow.rawValue == 38)
    #expect(MahjongAction.pon.rawValue == 41)
    #expect(MahjongAction.kan.rawValue == 42)
    #expect(MahjongAction.hora.rawValue == 43)
    #expect(MahjongAction.pass.rawValue == 45)
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

    let _ = try await bot.react(mjaiEvent: #"{"type":"dahai","actor":1,"pai":"3m","tsumogiri":false}"#)
    // We might be able to call (chi/pon) or pass

    print("Game flow test completed successfully")
}

// MARK: - Error Handling Tests

@Test func testInvalidJSON() async throws {
    let bot = try MortalBot(playerId: 0, version: 4, useBundledModel: false)

    do {
        _ = try await bot.react(mjaiEvent: "not valid json")
        #expect(Bool(false), "Should have thrown an error")
    } catch {
        #expect(error is MortalError)
    }
}

@Test func testEmptyJSON() async throws {
    let bot = try MortalBot(playerId: 0, version: 4, useBundledModel: false)

    do {
        _ = try await bot.react(mjaiEvent: "{}")
        #expect(Bool(false), "Should have thrown an error")
    } catch {
        #expect(error is MortalError)
    }
}

// MARK: - Core ML Integration Tests

@Test func testBundledModelURL() {
    let url = MortalBot.bundledModelURL
    #expect(url != nil, "Bundled model URL should be available")
}

@Test func testBotWithBundledModel() async throws {
    let bot = try MortalBot(playerId: 0, version: 4, useBundledModel: true)
    let hasModel = await bot.hasModel
    #expect(hasModel, "Bot should have Core ML model loaded")
}

@Test func testBotWithoutModel() async throws {
    let bot = try MortalBot(playerId: 0, version: 4, useBundledModel: false)
    let hasModel = await bot.hasModel
    #expect(!hasModel, "Bot should not have Core ML model")
}

@Test func testCoreMLInference() async throws {
    let bot = try MortalBot(playerId: 0, version: 4, useBundledModel: true)

    // Skip if model not available
    let hasModel = await bot.hasModel
    guard hasModel else {
        print("Skipping Core ML test - model not available")
        return
    }

    // Setup game
    _ = try await bot.react(mjaiEvent: #"{"type":"start_game","id":0,"names":["P0","P1","P2","P3"]}"#)
    _ = try await bot.react(mjaiEvent: #"{"type":"start_kyoku","bakaze":"E","dora_marker":"5s","kyoku":1,"honba":0,"kyotaku":0,"oya":0,"scores":[25000,25000,25000,25000],"tehais":[["1m","9m","1p","9p","1s","9s","E","S","W","N","P","F","C"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"]]}"#)

    // Tsumo - should trigger AI decision
    let response = try await bot.react(mjaiEvent: #"{"type":"tsumo","actor":0,"pai":"2m"}"#)
    #expect(response != nil, "Core ML should return an action")

    if let response = response {
        // AI can respond with dahai (discard) or reach (riichi)
        let isValidAction = response.contains("dahai") || response.contains("reach")
        #expect(isValidAction, "Response should be a valid action (dahai or reach)")
        print("Core ML inference result: \(response)")
    }
}

@Test func testCoreMLMultipleTurns() async throws {
    let bot = try MortalBot(playerId: 0, version: 4, useBundledModel: true)

    let hasModel = await bot.hasModel
    guard hasModel else {
        print("Skipping Core ML test - model not available")
        return
    }

    // Start game
    _ = try await bot.react(mjaiEvent: #"{"type":"start_game","id":0,"names":["P0","P1","P2","P3"]}"#)
    _ = try await bot.react(mjaiEvent: #"{"type":"start_kyoku","bakaze":"E","dora_marker":"3p","kyoku":1,"honba":0,"kyotaku":0,"oya":0,"scores":[25000,25000,25000,25000],"tehais":[["1m","2m","3m","4p","5p","6p","7s","8s","9s","E","S","W","N"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"],["?","?","?","?","?","?","?","?","?","?","?","?","?"]]}"#)

    // Multiple turns
    for i in 0..<3 {
        // Our tsumo
        let tsumoResponse = try await bot.react(mjaiEvent: #"{"type":"tsumo","actor":0,"pai":"P"}"#)
        #expect(tsumoResponse != nil, "Turn \(i): Should return action after tsumo")

        // Simulate our discard
        _ = try await bot.react(mjaiEvent: #"{"type":"dahai","actor":0,"pai":"P","tsumogiri":true}"#)

        // Other players' turns
        _ = try await bot.react(mjaiEvent: #"{"type":"tsumo","actor":1,"pai":"?"}"#)
        _ = try await bot.react(mjaiEvent: #"{"type":"dahai","actor":1,"pai":"1m","tsumogiri":true}"#)
        _ = try await bot.react(mjaiEvent: #"{"type":"tsumo","actor":2,"pai":"?"}"#)
        _ = try await bot.react(mjaiEvent: #"{"type":"dahai","actor":2,"pai":"2m","tsumogiri":true}"#)
        _ = try await bot.react(mjaiEvent: #"{"type":"tsumo","actor":3,"pai":"?"}"#)
        _ = try await bot.react(mjaiEvent: #"{"type":"dahai","actor":3,"pai":"3m","tsumogiri":true}"#)
    }

    print("Multiple turns test completed successfully")
}

// MARK: - Tile Tests

@Test func testTileFromMjaiString() {
    // 數牌
    #expect(Tile(mjaiString: "1m") == .man(1))
    #expect(Tile(mjaiString: "5m") == .man(5))
    #expect(Tile(mjaiString: "9m") == .man(9))
    #expect(Tile(mjaiString: "1p") == .pin(1))
    #expect(Tile(mjaiString: "5p") == .pin(5))
    #expect(Tile(mjaiString: "1s") == .sou(1))
    #expect(Tile(mjaiString: "9s") == .sou(9))

    // 紅寶牌
    #expect(Tile(mjaiString: "5mr") == .man(5, red: true))
    #expect(Tile(mjaiString: "5pr") == .pin(5, red: true))
    #expect(Tile(mjaiString: "5sr") == .sou(5, red: true))

    // 字牌
    #expect(Tile(mjaiString: "E") == .east)
    #expect(Tile(mjaiString: "S") == .south)
    #expect(Tile(mjaiString: "W") == .west)
    #expect(Tile(mjaiString: "N") == .north)
    #expect(Tile(mjaiString: "P") == .white)
    #expect(Tile(mjaiString: "F") == .green)
    #expect(Tile(mjaiString: "C") == .red)
}

@Test func testTileToMjaiString() {
    #expect(Tile.man(1).mjaiString == "1m")
    #expect(Tile.man(5, red: true).mjaiString == "5mr")
    #expect(Tile.pin(5).mjaiString == "5p")
    #expect(Tile.sou(9).mjaiString == "9s")
    #expect(Tile.east.mjaiString == "E")
    #expect(Tile.white.mjaiString == "P")
    #expect(Tile.green.mjaiString == "F")
    #expect(Tile.red.mjaiString == "C")
}

@Test func testTileFromMajsoulString() {
    // 紅寶牌用 0 表示
    #expect(Tile(majsoulString: "0m") == .man(5, red: true))
    #expect(Tile(majsoulString: "0p") == .pin(5, red: true))
    #expect(Tile(majsoulString: "0s") == .sou(5, red: true))

    // 一般數牌
    #expect(Tile(majsoulString: "1m") == .man(1))
    #expect(Tile(majsoulString: "5p") == .pin(5))

    // 字牌用 z 表示
    #expect(Tile(majsoulString: "1z") == .east)
    #expect(Tile(majsoulString: "2z") == .south)
    #expect(Tile(majsoulString: "3z") == .west)
    #expect(Tile(majsoulString: "4z") == .north)
    #expect(Tile(majsoulString: "5z") == .white)
    #expect(Tile(majsoulString: "6z") == .green)
    #expect(Tile(majsoulString: "7z") == .red)
}

@Test func testTileIndex() {
    #expect(Tile.man(1).index == 0)
    #expect(Tile.man(9).index == 8)
    #expect(Tile.pin(1).index == 9)
    #expect(Tile.sou(1).index == 18)
    #expect(Tile.east.index == 27)
    #expect(Tile.red.index == 33)
}

@Test func testTileFromIndex() {
    #expect(Tile.fromIndex(0) == .man(1))
    #expect(Tile.fromIndex(8) == .man(9))
    #expect(Tile.fromIndex(9) == .pin(1))
    #expect(Tile.fromIndex(27) == .east)
    #expect(Tile.fromIndex(33) == .red)
    #expect(Tile.fromIndex(34) == nil)
}

@Test func testTileProperties() {
    #expect(Tile.man(5, red: true).isRed == true)
    #expect(Tile.man(5).isRed == false)
    #expect(Tile.east.isHonor == true)
    #expect(Tile.man(1).isHonor == false)
    #expect(Tile.east.isWind == true)
    #expect(Tile.white.isWind == false)
    #expect(Tile.white.isDragon == true)
    #expect(Tile.east.isDragon == false)
}

@Test func testTileCodable() throws {
    let tile = Tile.man(5, red: true)
    let encoded = try JSONEncoder().encode(tile)
    let decoded = try JSONDecoder().decode(Tile.self, from: encoded)
    #expect(decoded == tile)

    // 解碼字串
    let json = "\"5mr\""
    let tileFromJson = try JSONDecoder().decode(Tile.self, from: json.data(using: .utf8)!)
    #expect(tileFromJson == .man(5, red: true))
}

// MARK: - Wind Tests

@Test func testWind() {
    #expect(Wind.east.rawValue == "E")
    #expect(Wind.south.rawValue == "S")
    #expect(Wind(rawValue: "E") == .east)
    #expect(Wind.east.tile == .east)
    #expect(Wind.fromIndex(0) == .east)
    #expect(Wind.fromIndex(3) == .north)
}

// MARK: - MJAIEvent Tests

@Test func testMJAIEventTsumoCodable() throws {
    let event = MJAIEvent.tsumo(TsumoEvent(actor: 0, pai: .man(5)))
    let json = try event.toJSONString()
    #expect(json.contains("\"type\":\"tsumo\""))
    #expect(json.contains("\"actor\":0"))
    #expect(json.contains("\"pai\":\"5m\""))

    let decoded = try MJAIEvent.fromJSONString(json)
    if case .tsumo(let e) = decoded {
        #expect(e.actor == 0)
        #expect(e.pai == .man(5))
    } else {
        #expect(Bool(false), "Should decode as tsumo event")
    }
}

@Test func testMJAIEventDahaiCodable() throws {
    let event = MJAIEvent.dahai(DahaiEvent(actor: 0, pai: .east, tsumogiri: true, riichi: nil))
    let json = try event.toJSONString()
    #expect(json.contains("\"type\":\"dahai\""))

    let decoded = try MJAIEvent.fromJSONString(json)
    if case .dahai(let e) = decoded {
        #expect(e.actor == 0)
        #expect(e.pai == .east)
        #expect(e.tsumogiri == true)
    } else {
        #expect(Bool(false), "Should decode as dahai event")
    }
}

@Test func testMJAIEventStartKyokuCodable() throws {
    let event = MJAIEvent.startKyoku(StartKyokuEvent(
        bakaze: .east,
        kyoku: 1,
        honba: 0,
        kyotaku: 0,
        oya: 0,
        doraMarker: .pin(3),
        scores: [25000, 25000, 25000, 25000],
        tehais: [
            [.man(1), .man(2), .man(3)],
            [.unknown, .unknown, .unknown],
            [.unknown, .unknown, .unknown],
            [.unknown, .unknown, .unknown]
        ]
    ))

    let json = try event.toJSONString()
    #expect(json.contains("\"type\":\"start_kyoku\""))
    #expect(json.contains("\"bakaze\":\"E\""))

    let decoded = try MJAIEvent.fromJSONString(json)
    if case .startKyoku(let e) = decoded {
        #expect(e.bakaze == .east)
        #expect(e.kyoku == 1)
        #expect(e.doraMarker == .pin(3))
    } else {
        #expect(Bool(false), "Should decode as start_kyoku event")
    }
}

@Test func testMJAIEventChiCodable() throws {
    let event = MJAIEvent.chi(ChiEvent(
        actor: 0,
        target: 3,
        pai: .man(3),
        consumed: [.man(1), .man(2)]
    ))

    let json = try event.toJSONString()
    let decoded = try MJAIEvent.fromJSONString(json)

    if case .chi(let e) = decoded {
        #expect(e.actor == 0)
        #expect(e.target == 3)
        #expect(e.pai == .man(3))
        #expect(e.consumed.count == 2)
    } else {
        #expect(Bool(false), "Should decode as chi event")
    }
}

@Test func testMJAIEventTypeName() {
    #expect(MJAIEvent.tsumo(TsumoEvent(actor: 0, pai: .man(1))).typeName == "tsumo")
    #expect(MJAIEvent.dahai(DahaiEvent(actor: 0, pai: .man(1), tsumogiri: false)).typeName == "dahai")
    #expect(MJAIEvent.endGame.typeName == "end_game")
    #expect(MJAIEvent.endKyoku.typeName == "end_kyoku")
}

// MARK: - MJAIAction Tests

@Test func testMJAIActionDahaiCodable() throws {
    let action = MJAIAction.dahai(DahaiAction(actor: 0, pai: .man(5, red: true), tsumogiri: true))
    let json = try action.toJSONString()
    #expect(json.contains("\"type\":\"dahai\""))
    #expect(json.contains("\"pai\":\"5mr\""))

    let decoded = try MJAIAction.fromJSONString(json)
    if case .dahai(let a) = decoded {
        #expect(a.actor == 0)
        #expect(a.pai == .man(5, red: true))
        #expect(a.tsumogiri == true)
    } else {
        #expect(Bool(false), "Should decode as dahai action")
    }
}

@Test func testMJAIActionReachCodable() throws {
    let action = MJAIAction.reach(ReachAction(actor: 0))
    let json = try action.toJSONString()
    #expect(json.contains("\"type\":\"reach\""))

    let decoded = try MJAIAction.fromJSONString(json)
    if case .reach(let a) = decoded {
        #expect(a.actor == 0)
    } else {
        #expect(Bool(false), "Should decode as reach action")
    }
}

@Test func testMJAIActionPassCodable() throws {
    let action = MJAIAction.pass(PassAction(actor: 0))
    let json = try action.toJSONString()
    #expect(json.contains("\"type\":\"none\""))

    let decoded = try MJAIAction.fromJSONString(json)
    if case .pass(let a) = decoded {
        #expect(a.actor == 0)
    } else {
        #expect(Bool(false), "Should decode as pass action")
    }
}

@Test func testMJAIActionTypeName() {
    #expect(MJAIAction.dahai(DahaiAction(actor: 0, pai: .man(1), tsumogiri: false)).typeName == "dahai")
    #expect(MJAIAction.reach(ReachAction(actor: 0)).typeName == "reach")
    #expect(MJAIAction.pass(PassAction(actor: 0)).typeName == "none")
    #expect(MJAIAction.hora(HoraAction(actor: 0, target: 1)).typeName == "hora")
}

@Test func testMJAIActionActor() {
    #expect(MJAIAction.dahai(DahaiAction(actor: 2, pai: .man(1), tsumogiri: false)).actor == 2)
    #expect(MJAIAction.reach(ReachAction(actor: 1)).actor == 1)
    #expect(MJAIAction.pass(PassAction(actor: 3)).actor == 3)
}

// MARK: - Typed API Tests

@Test func testTypedReactAPI() async throws {
    let bot = try MortalBot(playerId: 0, version: 4, useBundledModel: false)

    // Start game with typed event
    let startGame = MJAIEvent.startGame(StartGameEvent(names: ["P0", "P1", "P2", "P3"]))
    let response1 = try await bot.react(event: startGame)
    #expect(response1 == nil, "start_game should not require action")

    // Start kyoku with typed event
    let startKyoku = MJAIEvent.startKyoku(StartKyokuEvent(
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
    ))
    let response2 = try await bot.react(event: startKyoku)
    #expect(response2 == nil, "start_kyoku should not require action")

    // Tsumo with typed event
    let tsumo = MJAIEvent.tsumo(TsumoEvent(actor: 0, pai: .white))
    let response3 = try await bot.react(event: tsumo)
    #expect(response3 != nil, "tsumo by self should require action")

    // Verify response is a valid action type
    if let action = response3 {
        switch action {
        case .dahai(let a):
            #expect(a.actor == 0, "Actor should be 0")
            print("Typed API: Bot chose to discard \(a.pai)")
        case .reach(let a):
            #expect(a.actor == 0, "Actor should be 0")
            print("Typed API: Bot chose riichi")
        default:
            #expect(Bool(false), "Unexpected action type: \(action.typeName)")
        }
    }
}

@Test func testTypedReactSyncAPI() async throws {
    let bot = try MortalBot(playerId: 0, version: 4, useBundledModel: false)

    // Start game
    let startGame = MJAIEvent.startGame(StartGameEvent(names: ["P0", "P1", "P2", "P3"]))
    _ = try await bot.reactSync(event: startGame)

    // Start kyoku
    let startKyoku = MJAIEvent.startKyoku(StartKyokuEvent(
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
    ))
    _ = try await bot.reactSync(event: startKyoku)

    // Tsumo
    let tsumo = MJAIEvent.tsumo(TsumoEvent(actor: 0, pai: .white))
    let response = try await bot.reactSync(event: tsumo)
    #expect(response != nil, "tsumo by self should require action")
}

@Test func testTypedAPIWithCoreML() async throws {
    let bot = try MortalBot(playerId: 0, version: 4, useBundledModel: true)

    let hasModel = await bot.hasModel
    guard hasModel else {
        print("Skipping typed API Core ML test - model not available")
        return
    }

    // Setup with typed events
    _ = try await bot.react(event: .startGame(StartGameEvent(names: ["P0", "P1", "P2", "P3"])))
    _ = try await bot.react(event: .startKyoku(StartKyokuEvent(
        bakaze: .east,
        kyoku: 1,
        honba: 0,
        kyotaku: 0,
        oya: 0,
        doraMarker: .sou(5),
        scores: [25000, 25000, 25000, 25000],
        tehais: [
            [.man(1), .man(9), .pin(1), .pin(9), .sou(1), .sou(9), .east, .south, .west, .north, .white, .green, .red],
            [.unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown],
            [.unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown],
            [.unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown, .unknown]
        ]
    )))

    // AI decision
    let action = try await bot.react(event: .tsumo(TsumoEvent(actor: 0, pai: .man(2))))
    #expect(action != nil, "Core ML should return action")

    if let action = action {
        print("Typed API Core ML result: \(action.typeName)")
        switch action {
        case .dahai(let a):
            print("  Discard: \(a.pai), tsumogiri: \(a.tsumogiri)")
        case .reach:
            print("  Riichi declared")
        default:
            break
        }
    }
}
