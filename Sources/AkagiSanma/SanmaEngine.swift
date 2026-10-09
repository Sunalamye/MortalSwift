public struct SanmaDecision {
    /// 立直時 `tile` 是第二段預測的宣言捨牌。
    public var action: SanmaAction
    /// 依機率排序的前 `SanmaEngine.topN` 個動作，`action` 即第一筆；機率是對合法集合的 softmax。
    public var candidates: [(action: SanmaAction, prob: Float)]
    /// 實體合法動作只有一個。
    public var forced: Bool
    public var logits: [Float]
}

/// 對應 native_bot `Engine`（三麻）：餵 mjai 事件、在決策點跑模型挑合法動作。
/// 不套用自己的決策，自家動作要等事件回送再 `feed`。
public final class SanmaEngine {
    public static let topN = 3

    public private(set) var state: SanmaState
    private let forward: ([Float]) -> [Float]

    public init(seat: Int, forward: @escaping ([Float]) -> [Float]) {
        state = SanmaState(seat: seat)
        self.forward = forward
    }

    public convenience init(seat: Int, model: SanmaModel) {
        self.init(seat: seat, forward: model.forward)
    }

    public convenience init(seat: Int) throws {
        self.init(seat: seat, model: try .bundled())
    }

    public var seat: Int { state.seat }

    public func reset() {
        state = SanmaState(seat: seat)
    }

    @discardableResult
    public func feed(_ event: [String: Any]) -> Bool { state.apply(event) }

    @discardableResult
    public func feed(line: String) -> Bool { state.apply(line: line) }

    /// 不是本家的決策點時回傳 nil。
    public func decide() -> SanmaDecision? { decide(state.legalActions()) }

    /// oplist 授權閘：只保留授權類別的動作；捨牌與 pass 永遠保留。`forced` 依閘後的動作數。
    public func decide(authorized: Set<SanmaAction.Kind>) -> SanmaDecision? {
        decide(state.legalActions().filter { $0.kind == .discard || $0.kind == .pass || authorized.contains($0.kind) })
    }

    /// 現在宣告立直時會打的牌：在副本上套用 reach 再推論一次（`predict_reach_discard_3p`）。
    public func reachDiscard() -> UInt8? {
        var clone = state
        clone.apply(["type": "reach", "actor": seat])
        let legal = clone.legalActions()
        guard !legal.isEmpty, let obs = clone.encInput().encode() else { return nil }
        return SanmaActionCodec.rank(legal, logits: forward(obs), topN: 1).first?.action.tile
    }

    private func decide(_ legal: [SanmaAction]) -> SanmaDecision? {
        guard !legal.isEmpty, let obs = state.encInput().encode() else { return nil }
        let logits = forward(obs)
        var ranked = SanmaActionCodec.rank(legal, logits: logits, topN: Self.topN)
        // mjai 的 reach 必須帶捨牌，預測不到就退回次佳動作。
        if ranked.first?.action.kind == .riichi {
            if let t = reachDiscard() {
                ranked[0].action.tile = t
            } else {
                ranked.removeAll { $0.action.kind == .riichi }
            }
        }
        guard let top = ranked.first else { return nil }
        return SanmaDecision(action: top.action, candidates: ranked, forced: legal.count == 1, logits: logits)
    }
}
