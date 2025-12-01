import Foundation
import CoreML
import CLibRiichi

/// Swift wrapper for the Mortal Mahjong AI Bot
/// Uses libriichi for game state management and Core ML for inference
public actor MortalBot {

    // MARK: - Constants

    public static let actionSpace = 46
    public static let obsChannels = 1012  // For version 4
    public static let obsWidth = 34

    /// Get the URL of the bundled Core ML model
    public nonisolated static var bundledModelURL: URL? {
        #if SWIFT_PACKAGE
        return Bundle.module.url(forResource: "mortal", withExtension: "mlmodelc")
        #else
        return Bundle.main.url(forResource: "mortal", withExtension: "mlmodelc")
            ?? Bundle.main.url(forResource: "mortal", withExtension: "mlpackage")
        #endif
    }

    // MARK: - Properties

    private var rustBot: OpaquePointer?
    private var coreMLModel: MLModel?
    private let playerId: UInt8
    private let version: UInt32

    // Observation buffer
    private var obsBuffer: [Float]
    private var maskBuffer: [UInt8]

    // Last inference results
    private var lastQValues: [Float] = []
    private var lastProbs: [Float] = []
    private var lastSelectedAction: Int = -1
    private var lastMask: [UInt8] = []  // Save mask before committing action

    /// Whether the Core ML model is loaded
    public var hasModel: Bool {
        return coreMLModel != nil
    }

    /// Get the Q-values from the last inference
    public func getLastQValues() -> [Float] {
        return lastQValues
    }

    /// Get the probabilities from the last inference (softmax of Q-values)
    public func getLastProbs() -> [Float] {
        return lastProbs
    }

    /// Get the last selected action index
    public func getLastSelectedAction() -> Int {
        return lastSelectedAction
    }

    /// Get the mask from when the last decision was made (before action commit)
    public func getLastMask() -> [UInt8] {
        return lastMask
    }

    // MARK: - Initialization

    /// Initialize a new MortalBot with the bundled Core ML model
    /// - Parameters:
    ///   - playerId: Player seat (0-3)
    ///   - version: Model version (1-4, typically 4)
    ///   - useBundledModel: If true, automatically loads the bundled Core ML model
    public init(playerId: UInt8, version: UInt32 = 4, useBundledModel: Bool = true) throws {
        guard playerId <= 3 else {
            throw MortalError.invalidPlayerId(playerId)
        }
        guard version >= 1 && version <= 4 else {
            throw MortalError.invalidVersion(version)
        }

        self.playerId = playerId
        self.version = version

        // Get observation shape
        var channels: Int = 0
        var width: Int = 0
        riichi_obs_shape(version, &channels, &width)

        // Allocate buffers
        self.obsBuffer = [Float](repeating: 0, count: channels * width)
        self.maskBuffer = [UInt8](repeating: 0, count: Self.actionSpace)

        // Create Rust bot
        guard let bot = riichi_bot_new(playerId, version) else {
            throw MortalError.failedToCreateBot
        }
        self.rustBot = bot

        // Load Core ML model if provided
        if useBundledModel, let url = Self.bundledModelURL {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            self.coreMLModel = try MLModel(contentsOf: url, configuration: config)
        }
    }

    /// Initialize a new MortalBot
    /// - Parameters:
    ///   - playerId: Player seat (0-3)
    ///   - version: Model version (1-4, typically 4)
    ///   - modelURL: URL to the Core ML model (.mlpackage or .mlmodelc)
    public init(playerId: UInt8, version: UInt32 = 4, modelURL: URL?) throws {
        guard playerId <= 3 else {
            throw MortalError.invalidPlayerId(playerId)
        }
        guard version >= 1 && version <= 4 else {
            throw MortalError.invalidVersion(version)
        }

        self.playerId = playerId
        self.version = version

        // Get observation shape
        var channels: Int = 0
        var width: Int = 0
        riichi_obs_shape(version, &channels, &width)

        // Allocate buffers
        self.obsBuffer = [Float](repeating: 0, count: channels * width)
        self.maskBuffer = [UInt8](repeating: 0, count: Self.actionSpace)

        // Create Rust bot
        guard let bot = riichi_bot_new(playerId, version) else {
            throw MortalError.failedToCreateBot
        }
        self.rustBot = bot

        // Load Core ML model if provided
        if let url = modelURL {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            self.coreMLModel = try MLModel(contentsOf: url, configuration: config)
        }
    }

    deinit {
        if let bot = rustBot {
            riichi_bot_free(bot)
        }
    }

    // MARK: - Public Methods (Typed API)

    /// Process an MJAI event and get the bot's reaction (strongly-typed async version)
    /// - Parameter event: MJAI event
    /// - Returns: Bot action, or nil if no action needed
    public func react(event: MJAIEvent) async throws -> MJAIAction? {
        let jsonString = try event.toJSONString()
        guard let responseJSON = try await react(mjaiEvent: jsonString) else {
            return nil
        }
        return try MJAIAction.fromJSONString(responseJSON)
    }

    /// Process an MJAI event synchronously (strongly-typed version)
    /// - Parameter event: MJAI event
    /// - Returns: Bot action, or nil if no action needed
    public func reactSync(event: MJAIEvent) throws -> MJAIAction? {
        let jsonString = try event.toJSONString()
        guard let responseJSON = try reactSync(mjaiEvent: jsonString) else {
            return nil
        }
        return try MJAIAction.fromJSONString(responseJSON)
    }

    // MARK: - Public Methods (JSON API)

    /// Process an MJAI event and get the bot's reaction (async version for background inference)
    /// - Parameter mjaiEvent: MJAI event as JSON string
    /// - Returns: MJAI response as JSON string, or nil if no action needed
    public func react(mjaiEvent: String) async throws -> String? {
        guard let bot = rustBot else {
            throw MortalError.botNotInitialized
        }

        // Update state and get observation/mask
        let result = mjaiEvent.withCString { cString in
            riichi_bot_update(bot, cString, &obsBuffer, &maskBuffer)
        }

        switch result {
        case RIICHI_ACTION_REQUIRED:
            // Need to make a decision
            // Save the mask BEFORE selecting action, so it can be used for recommendations
            lastMask = maskBuffer

            let actionIdx = try await selectAction()

            // Get the action JSON
            guard let actionJSON = getActionJSON(actionIdx: actionIdx) else {
                throw MortalError.noValidActions
            }

            // NOTE: We do NOT commit the action here. The game will send us
            // confirmation events (dahai, chi, pon, etc.) which will update the state.
            // Committing here would cause duplicate state updates and errors.

            return actionJSON

        case RIICHI_NO_ACTION:
            // No action needed
            return nil

        case RIICHI_ERROR:
            throw MortalError.updateFailed

        default:
            throw MortalError.unknownResult(Int(result.rawValue))
        }
    }

    /// Process an MJAI event synchronously (for compatibility, use async version when possible)
    /// - Parameter mjaiEvent: MJAI event as JSON string
    /// - Returns: MJAI response as JSON string, or nil if no action needed
    public func reactSync(mjaiEvent: String) throws -> String? {
        guard let bot = rustBot else {
            throw MortalError.botNotInitialized
        }

        // Update state and get observation/mask
        let result = mjaiEvent.withCString { cString in
            riichi_bot_update(bot, cString, &obsBuffer, &maskBuffer)
        }

        switch result {
        case RIICHI_ACTION_REQUIRED:
            // Need to make a decision
            // Save the mask BEFORE selecting action, so it can be used for recommendations
            lastMask = maskBuffer

            let actionIdx = try selectActionSync()

            // Get the action JSON
            guard let actionJSON = getActionJSON(actionIdx: actionIdx) else {
                throw MortalError.noValidActions
            }

            return actionJSON

        case RIICHI_NO_ACTION:
            return nil

        case RIICHI_ERROR:
            throw MortalError.updateFailed

        default:
            throw MortalError.unknownResult(Int(result.rawValue))
        }
    }

    /// Get the current observation tensor
    public func getObservation() -> [Float] {
        return obsBuffer
    }

    /// Get the current action mask
    public func getMask() -> [UInt8] {
        return maskBuffer
    }

    /// Get available action candidates as JSON
    public func getCandidates() -> String? {
        guard let bot = rustBot else { return nil }

        guard let cString = riichi_bot_get_candidates(bot) else {
            return nil
        }

        let result = String(cString: cString)
        riichi_string_free(cString)
        return result
    }

    /// Get available action candidates as typed array
    public func getCandidateActions() -> [MJAIAction] {
        guard let json = getCandidates(),
              let data = json.data(using: .utf8),
              let array = try? JSONDecoder().decode([MJAIAction].self, from: data) else {
            return []
        }
        return array
    }

    /// Manually select an action by index
    /// - Parameter actionIdx: Action index (0-45)
    /// - Returns: MJAI response JSON
    public func selectActionManually(actionIdx: Int) -> String? {
        return getActionJSON(actionIdx: actionIdx)
    }

    // MARK: - Private Methods

    /// Select action using Core ML or fallback to greedy (async version - runs inference in background)
    private func selectAction() async throws -> Int {
        // Convert mask to valid action indices
        let validActions = maskBuffer.enumerated().compactMap { idx, valid in
            valid != 0 ? idx : nil
        }

        guard !validActions.isEmpty else {
            throw MortalError.noValidActions
        }

        // If no Core ML model, use first valid action (pass if available, else first)
        guard let model = coreMLModel else {
            // Prefer pass (45) if available
            let action = validActions.contains(45) ? 45 : validActions.first!
            lastSelectedAction = action
            // Set uniform probabilities for valid actions
            lastQValues = [Float](repeating: 0, count: Self.actionSpace)
            lastProbs = [Float](repeating: 0, count: Self.actionSpace)
            let uniformProb = 1.0 / Float(validActions.count)
            for a in validActions {
                lastProbs[a] = uniformProb
            }
            return action
        }

        // Capture values needed for background inference
        let obsCopy = obsBuffer
        let maskCopy = maskBuffer

        // Run Core ML inference in background
        let qValues = try await runInferenceInBackground(model: model, obs: obsCopy, mask: maskCopy)

        // Store Q-values
        lastQValues = qValues

        // Find best valid action (argmax over valid actions)
        var bestAction = validActions.first!
        var bestQ: Float = -.infinity

        for action in validActions {
            let q = lastQValues[action]
            if q > bestQ {
                bestQ = q
                bestAction = action
            }
        }

        lastSelectedAction = bestAction

        // Calculate softmax probabilities for valid actions only
        lastProbs = calculateSoftmax(qValues: lastQValues, validActions: validActions)

        return bestAction
    }

    /// Select action synchronously (for compatibility)
    private func selectActionSync() throws -> Int {
        // Convert mask to valid action indices
        let validActions = maskBuffer.enumerated().compactMap { idx, valid in
            valid != 0 ? idx : nil
        }

        guard !validActions.isEmpty else {
            throw MortalError.noValidActions
        }

        // If no Core ML model, use first valid action (pass if available, else first)
        guard let model = coreMLModel else {
            // Prefer pass (45) if available
            let action = validActions.contains(45) ? 45 : validActions.first!
            lastSelectedAction = action
            // Set uniform probabilities for valid actions
            lastQValues = [Float](repeating: 0, count: Self.actionSpace)
            lastProbs = [Float](repeating: 0, count: Self.actionSpace)
            let uniformProb = 1.0 / Float(validActions.count)
            for a in validActions {
                lastProbs[a] = uniformProb
            }
            return action
        }

        // Prepare input for Core ML
        let obsArray = try MLMultiArray(shape: [1, NSNumber(value: Self.obsChannels), NSNumber(value: Self.obsWidth)], dataType: .float32)
        let maskArray = try MLMultiArray(shape: [1, NSNumber(value: Self.actionSpace)], dataType: .float32)

        // Copy observation data
        for i in 0..<obsBuffer.count {
            obsArray[i] = NSNumber(value: obsBuffer[i])
        }

        // Copy mask data (convert to float)
        for i in 0..<maskBuffer.count {
            maskArray[i] = NSNumber(value: Float(maskBuffer[i]))
        }

        // Create input dictionary
        let input = try MLDictionaryFeatureProvider(dictionary: [
            "obs": obsArray,
            "mask": maskArray
        ])

        // Run inference
        let output = try model.prediction(from: input)

        // Get Q-values
        guard let qValues = output.featureValue(for: "q_values")?.multiArrayValue else {
            throw MortalError.inferenceOutputMissing
        }

        // Store Q-values
        lastQValues = [Float](repeating: 0, count: Self.actionSpace)
        for i in 0..<Self.actionSpace {
            lastQValues[i] = qValues[i].floatValue
        }

        // Find best valid action (argmax over valid actions)
        var bestAction = validActions.first!
        var bestQ: Float = -.infinity

        for action in validActions {
            let q = lastQValues[action]
            if q > bestQ {
                bestQ = q
                bestAction = action
            }
        }

        lastSelectedAction = bestAction

        // Calculate softmax probabilities for valid actions only
        lastProbs = calculateSoftmax(qValues: lastQValues, validActions: validActions)

        return bestAction
    }

    /// Run Core ML inference in background (nonisolated to avoid blocking actor)
    private nonisolated func runInferenceInBackground(model: MLModel, obs: [Float], mask: [UInt8]) async throws -> [Float] {
        try await Task.detached(priority: .userInitiated) {
            // Prepare input for Core ML
            let obsArray = try MLMultiArray(shape: [1, NSNumber(value: Self.obsChannels), NSNumber(value: Self.obsWidth)], dataType: .float32)
            let maskArray = try MLMultiArray(shape: [1, NSNumber(value: Self.actionSpace)], dataType: .float32)

            // Copy observation data
            for i in 0..<obs.count {
                obsArray[i] = NSNumber(value: obs[i])
            }

            // Copy mask data (convert to float)
            for i in 0..<mask.count {
                maskArray[i] = NSNumber(value: Float(mask[i]))
            }

            // Create input dictionary
            let input = try MLDictionaryFeatureProvider(dictionary: [
                "obs": obsArray,
                "mask": maskArray
            ])

            // Run inference (this is the expensive operation)
            let output = try model.prediction(from: input)

            // Get Q-values
            guard let qValuesArray = output.featureValue(for: "q_values")?.multiArrayValue else {
                throw MortalError.inferenceOutputMissing
            }

            // Extract Q-values
            var qValues = [Float](repeating: 0, count: Self.actionSpace)
            for i in 0..<Self.actionSpace {
                qValues[i] = qValuesArray[i].floatValue
            }

            return qValues
        }.value
    }

    /// Calculate softmax probabilities over valid actions
    private func calculateSoftmax(qValues: [Float], validActions: [Int]) -> [Float] {
        var probs = [Float](repeating: 0, count: Self.actionSpace)

        // Get Q-values for valid actions
        let validQ = validActions.map { qValues[$0] }

        // Find max for numerical stability
        let maxQ = validQ.max() ?? 0

        // Calculate exp(q - max) for each valid action
        var expSum: Float = 0
        var expValues = [Float]()
        for q in validQ {
            let expVal = exp(q - maxQ)
            expValues.append(expVal)
            expSum += expVal
        }

        // Normalize to get probabilities
        for (i, action) in validActions.enumerated() {
            probs[action] = expValues[i] / expSum
        }

        return probs
    }

    /// Convert action index to MJAI JSON response
    private func getActionJSON(actionIdx: Int) -> String? {
        guard let bot = rustBot else { return nil }

        guard let cString = riichi_bot_get_action(bot, actionIdx) else {
            return nil
        }

        let result = String(cString: cString)
        riichi_string_free(cString)
        return result
    }
}

// MARK: - Error Types

public enum MortalError: Error, LocalizedError {
    case invalidPlayerId(UInt8)
    case invalidVersion(UInt32)
    case failedToCreateBot
    case botNotInitialized
    case updateFailed
    case noValidActions
    case inferenceOutputMissing
    case unknownResult(Int)
    case encodingFailed
    case decodingFailed

    public var errorDescription: String? {
        switch self {
        case .invalidPlayerId(let id):
            return "Invalid player ID: \(id). Must be 0-3."
        case .invalidVersion(let v):
            return "Invalid version: \(v). Must be 1-4."
        case .failedToCreateBot:
            return "Failed to create Rust bot instance."
        case .botNotInitialized:
            return "Bot not initialized."
        case .updateFailed:
            return "Failed to update bot state."
        case .noValidActions:
            return "No valid actions available."
        case .inferenceOutputMissing:
            return "Core ML inference output missing."
        case .unknownResult(let code):
            return "Unknown result code: \(code)."
        case .encodingFailed:
            return "Failed to encode to JSON."
        case .decodingFailed:
            return "Failed to decode from JSON."
        }
    }
}

// MARK: - Action Meanings

public enum MahjongAction: Int, CaseIterable {
    // Discard tiles (0-33)
    case discard1m = 0, discard2m, discard3m, discard4m, discard5m, discard6m, discard7m, discard8m, discard9m
    case discard1p, discard2p, discard3p, discard4p, discard5p, discard6p, discard7p, discard8p, discard9p
    case discard1s, discard2s, discard3s, discard4s, discard5s, discard6s, discard7s, discard8s, discard9s
    case discardEast, discardSouth, discardWest, discardNorth, discardWhite, discardGreen, discardRed
    case unused34, unused35, unused36

    // Actions
    case riichi = 37
    case chiLow, chiMid, chiHigh
    case pon
    case kan
    case hora
    case ryukyoku
    case pass

    public var description: String {
        switch self {
        case .discard1m: return "Discard 1m"
        case .discard2m: return "Discard 2m"
        case .discard3m: return "Discard 3m"
        case .discard4m: return "Discard 4m"
        case .discard5m: return "Discard 5m"
        case .discard6m: return "Discard 6m"
        case .discard7m: return "Discard 7m"
        case .discard8m: return "Discard 8m"
        case .discard9m: return "Discard 9m"
        case .discard1p: return "Discard 1p"
        case .discard2p: return "Discard 2p"
        case .discard3p: return "Discard 3p"
        case .discard4p: return "Discard 4p"
        case .discard5p: return "Discard 5p"
        case .discard6p: return "Discard 6p"
        case .discard7p: return "Discard 7p"
        case .discard8p: return "Discard 8p"
        case .discard9p: return "Discard 9p"
        case .discard1s: return "Discard 1s"
        case .discard2s: return "Discard 2s"
        case .discard3s: return "Discard 3s"
        case .discard4s: return "Discard 4s"
        case .discard5s: return "Discard 5s"
        case .discard6s: return "Discard 6s"
        case .discard7s: return "Discard 7s"
        case .discard8s: return "Discard 8s"
        case .discard9s: return "Discard 9s"
        case .discardEast: return "Discard East"
        case .discardSouth: return "Discard South"
        case .discardWest: return "Discard West"
        case .discardNorth: return "Discard North"
        case .discardWhite: return "Discard White"
        case .discardGreen: return "Discard Green"
        case .discardRed: return "Discard Red"
        case .unused34, .unused35, .unused36: return "Unused"
        case .riichi: return "Riichi"
        case .chiLow: return "Chi (low)"
        case .chiMid: return "Chi (mid)"
        case .chiHigh: return "Chi (high)"
        case .pon: return "Pon"
        case .kan: return "Kan"
        case .hora: return "Hora (Win)"
        case .ryukyoku: return "Ryukyoku (Draw)"
        case .pass: return "Pass"
        }
    }
}
