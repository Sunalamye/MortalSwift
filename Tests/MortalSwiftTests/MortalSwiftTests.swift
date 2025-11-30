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
