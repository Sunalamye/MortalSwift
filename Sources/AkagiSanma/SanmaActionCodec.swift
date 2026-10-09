import Foundation

/// 對應 riichienv-core `Action`：tile 與 consumed 皆為 136 制 tid。
public struct SanmaAction: Equatable, Sendable {
    public enum Kind: Sendable {
        case discard, chi, pon, daiminkan, ankan, kakan, riichi, ron, tsumo, kyushu, pass, kita
    }

    public var kind: Kind
    public var tile: UInt8?
    public var consumed: [UInt8]

    public init(_ kind: Kind, tile: UInt8? = nil, consumed: [UInt8] = []) {
        self.kind = kind
        self.tile = tile
        self.consumed = consumed.sorted()
    }
}

/// 三麻 60 格動作空間：0–26 捨牌、27 立直、28 碰、29–55 槓、56 和、57 九種九牌、58 pass、59 拔北。
public enum SanmaActionCodec {
    public static let count = 60
    public static let riichi = 27
    public static let pon = 28
    public static let kanBase = 29
    public static let agari = 56
    public static let kyushu = 57
    public static let pass = 58
    public static let kita = 59

    /// 三麻不合法（吃、2m–8m）時回傳 nil。
    public static func index(_ a: SanmaAction) -> Int? {
        switch a.kind {
        case .discard: a.tile.flatMap(SanmaTiles.index)
        case .daiminkan: a.tile.flatMap(SanmaTiles.index).map { kanBase + $0 }
        case .ankan, .kakan: a.consumed.first.flatMap(SanmaTiles.index).map { kanBase + $0 }
        case .chi: nil
        case .pon: pon
        case .riichi: riichi
        case .ron, .tsumo: agari
        case .kyushu: kyushu
        case .pass: pass
        case .kita: kita
        }
    }

    public static func legalMask(_ legal: [SanmaAction]) -> [Bool] {
        var mask = [Bool](repeating: false, count: count)
        for a in legal {
            if let i = index(a) { mask[i] = true }
        }
        return mask
    }

    /// 合法動作依 logit 由高到低排序，每個 action id 只留一筆；prob 為對合法集合的 softmax。
    /// 同 id 的赤五與普通五共用 logit，捨牌時優先普通五，避免白白丟掉寶牌。
    /// 同分依 action id 升冪，所以 `rank(...).first` 即最佳動作。
    public static func rank(_ legal: [SanmaAction], logits: [Float], topN: Int = .max) -> [(action: SanmaAction, prob: Float)] {
        func discardsAka(_ a: SanmaAction) -> Bool { a.kind == .discard && a.tile.map(SanmaTiles.isAka) == true }

        var byId: [Int: SanmaAction] = [:]
        for a in legal {
            guard let i = index(a) else { continue }
            if let kept = byId[i], !(discardsAka(kept) && !discardsAka(a)) { continue }
            byId[i] = a
        }
        let scored = byId.sorted { $0.key < $1.key }.map { (action: $0.value, logit: $0.key < logits.count ? logits[$0.key] : -.infinity) }
        guard let maxLogit = scored.map(\.logit).max() else { return [] }
        let exps = scored.map { exp($0.logit - maxLogit) }
        let sum = exps.reduce(0, +)
        let ranked = zip(scored, exps).enumerated()
            .sorted { $0.element.0.logit != $1.element.0.logit ? $0.element.0.logit > $1.element.0.logit : $0.offset < $1.offset }
            .map { (action: $0.element.0.action, prob: sum > 0 ? $0.element.1 / sum : 0) }
        return Array(ranked.prefix(topN))
    }
}
