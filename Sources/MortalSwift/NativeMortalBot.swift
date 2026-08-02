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

    /// observation 快取：對同一個狀態版本只算一次 encode
    private var cachedEncoding: (revision: Int, obs: [Float], mask: [UInt8])?

    /// 真正跑過幾次完整 encode（快取命中不計）
    private var encodeCount = 0

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

    // MARK: - Observation Cache

    /// 取得當前狀態的 (obs, mask)；同一個狀態版本只真的算一次
    ///
    /// 為什麼要快取：`getObservation` / `getMask` / `getCandidateActions` 原本各自
    /// 呼叫一次 `ObsEncoder.encode`，而 encode 裡的單人期望值 DP 是整條路徑最貴的
    /// 一段（Debug 最壞情況 1.2–1.5 秒）。呼叫端一次 UI 更新會連著問遮罩、問候選、
    /// 再問一次遮罩，等於把同一份計算重跑三次——延遲是純粹浪費的，因為狀態根本沒動。
    ///
    /// 失效判準是 `state.revision`，只有 `PlayerState.update(event:)` 會推進它。
    /// 這個 actor 是 `state` 的唯一持有者且不對外交出參考，所以「沒有新事件 ⇒ 狀態
    /// 沒變 ⇒ 張量沒變」在這裡成立。
    ///
    /// 快取只涵蓋 `atKanSelect == false`。次級決策（選槓哪張）的張量不同，
    /// 而且目前沒有呼叫端會連問，多存一份反而是多一個會走味的狀態。
    private func currentEncoding() -> (obs: [Float], mask: [UInt8]) {
        if let cached = cachedEncoding, cached.revision == state.revision {
            return (cached.obs, cached.mask)
        }
        let encoded = ObsEncoder.encode(state: state)
        encodeCount += 1
        cachedEncoding = (revision: state.revision, obs: encoded.obs, mask: encoded.mask)
        return encoded
    }

    /// 至今真正跑過幾次完整 encode（快取命中不計）
    ///
    /// 對外公開是為了讓測試能證明「同一個狀態連問遮罩與候選動作只算一次」——
    /// 這種效能性質沒有計數器就只能靠碼錶量，量出來的數字又會隨機器浮動。
    public func getEncodeCount() -> Int {
        encodeCount
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
        let (obs, mask) = currentEncoding()
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
        let (obs, mask) = currentEncoding()
        lastMask = mask

        // 選擇動作
        let actionIdx = try selectActionSync(obs: obs, mask: mask)

        // 解碼動作
        return ActionDecoder.decode(actionIdx: actionIdx, state: state)
    }

    /// 對**當前狀態**直接跑一次推論，不需要事件觸發。
    ///
    /// 為什麼需要這個：MJAI 協定在自己吃／碰／槓之後**不會再送事件**要你打牌，
    /// 所以 `react` 沒有機會被呼叫，`lastProbs` 停留在副露前那一次的結果。
    /// 但手牌已經變了——呼叫端若拿舊機率或退回均勻分布，等於那一手完全沒有模型參與。
    ///
    /// 這個方法把狀態編碼後直接送進模型，更新 `lastQValues` / `lastProbs` / `lastMask`，
    /// 並回傳模型選中的動作。沒有合法動作時回傳 nil。
    ///
    /// - Returns: 模型選中的動作；沒有合法動作時 nil
    @discardableResult
    public func inferCurrentState() async throws -> MJAIAction? {
        let (obs, mask) = currentEncoding()
        guard mask.contains(where: { $0 != 0 }) else { return nil }
        lastMask = mask

        let actionIdx = try await selectAction(obs: obs, mask: mask)
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
        currentEncoding().obs
    }

    /// 取得當前遮罩
    public func getMask() -> [UInt8] {
        currentEncoding().mask
    }

    /// 取得可用動作候選
    public func getCandidateActions() -> [MJAIAction] {
        var actions: [MJAIAction] = []

        let mask = currentEncoding().mask
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
        //
        // 原本是逐格 `obsArray[i] = NSNumber(value:)`，等於為 1012×34 = 34,408 個
        // float 各配一個 NSNumber 再走一次 MLMultiArray 的 subscript。那是純粹的
        // 搬運成本，跟數值無關。輸入是上面剛配出來的連續 float32 緩衝區，
        // 整塊 memcpy 進去結果位元相同。
        try Self.copyFloats(obs, into: obsArray)
        try Self.copyFloats(mask.map(Float.init), into: maskArray)

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

    /// 把 Float 陣列整塊搬進 MLMultiArray
    ///
    /// ⚠️ 只能用在**這個檔案自己用 `MLMultiArray(shape:dataType: .float32)` 配出來的**
    /// 陣列：那種配置保證是連續的 float32，才可以無視 strides 直接 memcpy。
    /// 外來的 MLMultiArray 可能有非連續 strides 或別的 dataType，照這樣搬會寫壞記憶體，
    /// 所以下面的 guard 是防線不是裝飾——不符合就丟錯，不要退化成「搬一半」。
    ///
    /// internal 而非 private：memcpy 換掉逐格裝箱的前提是「搬進去的每一格都一樣」，
    /// 這件事要能被直接驗（`memcpyIntoMLMultiArrayIsFaithful`），不能只靠
    /// 「模型看起來還會給合理答案」推論。
    nonisolated static func copyFloats(_ values: [Float], into array: MLMultiArray) throws {
        guard array.dataType == .float32, array.count == values.count else {
            throw MortalError.inferenceInputShapeMismatch(expected: array.count, got: values.count)
        }
        guard !values.isEmpty else { return }
        values.withUnsafeBytes { src in
            // src.baseAddress 在非空陣列上必為非 nil
            array.dataPointer.copyMemory(from: src.baseAddress!, byteCount: src.count)
        }
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
