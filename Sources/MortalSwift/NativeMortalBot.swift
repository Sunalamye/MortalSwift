//
//  NativeMortalBot.swift
//  MortalSwift
//
//  純 Swift 實現的 Mortal AI Bot，無需 Rust FFI
//

import Foundation
import CoreML

/// 純 Swift 實現的 Mortal 麻雀 AI Bot
public actor NativeMortalBot {

    // MARK: - Constants

    public static let actionSpace = 46
    public static let obsChannels = 1012
    public static let obsWidth = 34

    /// 取得內建 Core ML 模型 URL
    public nonisolated static var bundledModelURL: URL? {
        #if SWIFT_PACKAGE
        return Bundle.module.url(forResource: "mortal", withExtension: "mlmodelc")
        #else
        return Bundle.main.url(forResource: "mortal", withExtension: "mlmodelc")
            ?? Bundle.main.url(forResource: "mortal", withExtension: "mlpackage")
        #endif
    }

    // MARK: - Properties

    /// 玩家狀態
    private let state: PlayerState

    /// Core ML 模型
    private var coreMLModel: MLModel?

    /// 最後的 Q 值
    private var lastQValues: [Float] = []

    /// 最後的機率
    private var lastProbs: [Float] = []

    /// 最後選擇的動作
    private var lastSelectedAction: Int = -1

    /// 最後的遮罩
    private var lastMask: [UInt8] = []

    /// 是否有載入模型
    public var hasModel: Bool {
        coreMLModel != nil
    }

    // MARK: - Initialization

    /// 初始化 Bot
    /// - Parameters:
    ///   - playerId: 玩家座位 (0-3)
    ///   - version: 模型版本 (1-4，通常為 4)
    ///   - useBundledModel: 是否使用內建模型
    public init(playerId: Int, version: Int = 4, useBundledModel: Bool = true) throws {
        guard playerId >= 0 && playerId <= 3 else {
            throw MortalError.invalidPlayerId(UInt8(playerId))
        }
        guard version >= 1 && version <= 4 else {
            throw MortalError.invalidVersion(UInt32(version))
        }

        self.state = PlayerState(playerId: playerId, version: version)

        // 載入 Core ML 模型
        if useBundledModel, let url = Self.bundledModelURL {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            self.coreMLModel = try MLModel(contentsOf: url, configuration: config)
        }
    }

    /// 初始化 Bot 並指定模型 URL
    /// - Parameters:
    ///   - playerId: 玩家座位 (0-3)
    ///   - version: 模型版本 (1-4，通常為 4)
    ///   - modelURL: 模型 URL
    public init(playerId: Int, version: Int = 4, modelURL: URL?) throws {
        guard playerId >= 0 && playerId <= 3 else {
            throw MortalError.invalidPlayerId(UInt8(playerId))
        }
        guard version >= 1 && version <= 4 else {
            throw MortalError.invalidVersion(UInt32(version))
        }

        self.state = PlayerState(playerId: playerId, version: version)

        // 載入 Core ML 模型
        if let url = modelURL {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            self.coreMLModel = try MLModel(contentsOf: url, configuration: config)
        }
    }

    // MARK: - Public API (Typed)

    /// 處理 MJAI 事件並取得 Bot 反應 (非同步)
    /// - Parameter event: MJAI 事件
    /// - Returns: Bot 動作，如果不需要動作則返回 nil
    public func react(event: MJAIEvent) async throws -> MJAIAction? {
        // 更新狀態
        let needsAction = state.update(event: event)

        guard needsAction else { return nil }

        // 編碼觀測
        let (obs, mask) = ObsEncoder.encode(state: state)
        lastMask = mask

        // 選擇動作
        let actionIdx = try await selectAction(obs: obs, mask: mask)

        // 解碼動作
        return ActionDecoder.decode(actionIdx: actionIdx, state: state)
    }

    /// 處理 MJAI 事件並取得 Bot 反應 (同步)
    /// - Parameter event: MJAI 事件
    /// - Returns: Bot 動作，如果不需要動作則返回 nil
    public func reactSync(event: MJAIEvent) throws -> MJAIAction? {
        // 更新狀態
        let needsAction = state.update(event: event)

        guard needsAction else { return nil }

        // 編碼觀測
        let (obs, mask) = ObsEncoder.encode(state: state)
        lastMask = mask

        // 選擇動作
        let actionIdx = try selectActionSync(obs: obs, mask: mask)

        // 解碼動作
        return ActionDecoder.decode(actionIdx: actionIdx, state: state)
    }

    // MARK: - Public API (JSON)

    /// 處理 MJAI 事件 (JSON 格式)
    /// - Parameter mjaiEvent: MJAI 事件 JSON 字串
    /// - Returns: MJAI 回應 JSON 字串
    public func react(mjaiEvent: String) async throws -> String? {
        let event = try MJAIEvent.fromJSONString(mjaiEvent)
        guard let action = try await react(event: event) else {
            return nil
        }
        return try action.toJSONString()
    }

    /// 處理 MJAI 事件 (JSON 格式，同步)
    /// - Parameter mjaiEvent: MJAI 事件 JSON 字串
    /// - Returns: MJAI 回應 JSON 字串
    public func reactSync(mjaiEvent: String) throws -> String? {
        let event = try MJAIEvent.fromJSONString(mjaiEvent)
        guard let action = try reactSync(event: event) else {
            return nil
        }
        return try action.toJSONString()
    }

    // MARK: - Getters

    /// 取得最後的 Q 值
    public func getLastQValues() -> [Float] {
        lastQValues
    }

    /// 取得最後的機率
    public func getLastProbs() -> [Float] {
        lastProbs
    }

    /// 取得最後選擇的動作
    public func getLastSelectedAction() -> Int {
        lastSelectedAction
    }

    /// 取得最後的遮罩
    public func getLastMask() -> [UInt8] {
        lastMask
    }

    /// 取得當前觀測
    public func getObservation() -> [Float] {
        let (obs, _) = ObsEncoder.encode(state: state)
        return obs
    }

    /// 取得當前遮罩
    public func getMask() -> [UInt8] {
        let (_, mask) = ObsEncoder.encode(state: state)
        return mask
    }

    /// 取得可用動作候選
    public func getCandidateActions() -> [MJAIAction] {
        var actions: [MJAIAction] = []

        let mask = getMask()
        for idx in 0..<Self.actionSpace where mask[idx] != 0 {
            if let action = ActionDecoder.decode(actionIdx: idx, state: state) {
                actions.append(action)
            }
        }

        return actions
    }

    // MARK: - Private Methods

    /// 選擇動作 (非同步)
    private func selectAction(obs: [Float], mask: [UInt8]) async throws -> Int {
        // 找出有效動作
        let validActions = mask.enumerated().compactMap { idx, valid in
            valid != 0 ? idx : nil
        }

        guard !validActions.isEmpty else {
            throw MortalError.noValidActions
        }

        // 如果沒有模型，使用簡單策略
        guard let model = coreMLModel else {
            return selectFallbackAction(validActions: validActions)
        }

        // 執行推理
        let qValues = try await runInference(model: model, obs: obs, mask: mask)
        lastQValues = qValues

        // 選擇最佳動作
        let bestAction = selectBestAction(qValues: qValues, validActions: validActions)
        lastSelectedAction = bestAction

        // 計算 softmax 機率
        lastProbs = calculateSoftmax(qValues: qValues, validActions: validActions)

        return bestAction
    }

    /// 選擇動作 (同步)
    private func selectActionSync(obs: [Float], mask: [UInt8]) throws -> Int {
        // 找出有效動作
        let validActions = mask.enumerated().compactMap { idx, valid in
            valid != 0 ? idx : nil
        }

        guard !validActions.isEmpty else {
            throw MortalError.noValidActions
        }

        // 如果沒有模型，使用簡單策略
        guard let model = coreMLModel else {
            return selectFallbackAction(validActions: validActions)
        }

        // 執行推理
        let qValues = try runInferenceSync(model: model, obs: obs, mask: mask)
        lastQValues = qValues

        // 選擇最佳動作
        let bestAction = selectBestAction(qValues: qValues, validActions: validActions)
        lastSelectedAction = bestAction

        // 計算 softmax 機率
        lastProbs = calculateSoftmax(qValues: qValues, validActions: validActions)

        return bestAction
    }

    /// 執行 Core ML 推理 (非同步)
    private nonisolated func runInference(model: MLModel, obs: [Float], mask: [UInt8]) async throws -> [Float] {
        try await Task.detached(priority: .userInitiated) {
            try self.runInferenceSync(model: model, obs: obs, mask: mask)
        }.value
    }

    /// 執行 Core ML 推理 (同步)
    private nonisolated func runInferenceSync(model: MLModel, obs: [Float], mask: [UInt8]) throws -> [Float] {
        // 準備輸入
        let obsArray = try MLMultiArray(
            shape: [1, NSNumber(value: Self.obsChannels), NSNumber(value: Self.obsWidth)],
            dataType: .float32
        )
        let maskArray = try MLMultiArray(
            shape: [1, NSNumber(value: Self.actionSpace)],
            dataType: .float32
        )

        // 複製資料
        for i in 0..<obs.count {
            obsArray[i] = NSNumber(value: obs[i])
        }
        for i in 0..<mask.count {
            maskArray[i] = NSNumber(value: Float(mask[i]))
        }

        // 執行推理
        let input = try MLDictionaryFeatureProvider(dictionary: [
            "obs": obsArray,
            "mask": maskArray
        ])

        let output = try model.prediction(from: input)

        // 取得 Q 值
        guard let qValuesArray = output.featureValue(for: "q_values")?.multiArrayValue else {
            throw MortalError.inferenceOutputMissing
        }

        var qValues = [Float](repeating: 0, count: Self.actionSpace)
        for i in 0..<Self.actionSpace {
            qValues[i] = qValuesArray[i].floatValue
        }

        return qValues
    }

    /// 選擇最佳動作
    private func selectBestAction(qValues: [Float], validActions: [Int]) -> Int {
        var bestAction = validActions.first!
        var bestQ: Float = -.infinity

        for action in validActions {
            let q = qValues[action]
            if q > bestQ {
                bestQ = q
                bestAction = action
            }
        }

        return bestAction
    }

    /// 回退策略 (無模型時使用)
    private func selectFallbackAction(validActions: [Int]) -> Int {
        lastSelectedAction = validActions.contains(PlayerState.ActionIndex.pass)
            ? PlayerState.ActionIndex.pass
            : validActions.first!

        // 設定均勻機率
        lastQValues = [Float](repeating: 0, count: Self.actionSpace)
        lastProbs = [Float](repeating: 0, count: Self.actionSpace)
        let uniformProb = 1.0 / Float(validActions.count)
        for a in validActions {
            lastProbs[a] = uniformProb
        }

        return lastSelectedAction
    }

    /// 計算 softmax 機率
    private func calculateSoftmax(qValues: [Float], validActions: [Int]) -> [Float] {
        var probs = [Float](repeating: 0, count: Self.actionSpace)

        // 取得有效動作的 Q 值
        let validQ = validActions.map { qValues[$0] }

        // 找最大值 (數值穩定性)
        let maxQ = validQ.max() ?? 0

        // 計算 exp(q - max)
        var expSum: Float = 0
        var expValues = [Float]()
        for q in validQ {
            let expVal = exp(q - maxQ)
            expValues.append(expVal)
            expSum += expVal
        }

        // 正規化
        for (i, action) in validActions.enumerated() {
            probs[action] = expValues[i] / expSum
        }

        return probs
    }
}
