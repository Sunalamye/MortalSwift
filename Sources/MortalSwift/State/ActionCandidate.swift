//
//  ActionCandidate.swift
//  MortalSwift
//
//  可用動作候選
//

import Foundation

/// 可用動作候選
public struct ActionCandidate: Sendable, Equatable {
    /// 可以打牌
    public var canDiscard: Bool = false
    /// 可以吃 (低位)
    public var canChiLow: Bool = false
    /// 可以吃 (中位)
    public var canChiMid: Bool = false
    /// 可以吃 (高位)
    public var canChiHigh: Bool = false
    /// 可以碰
    public var canPon: Bool = false
    /// 可以大明槓
    public var canDaiminkan: Bool = false
    /// 可以加槓
    public var canKakan: Bool = false
    /// 可以暗槓
    public var canAnkan: Bool = false
    /// 可以立直
    public var canRiichi: Bool = false
    /// 可以自摸
    public var canTsumoAgari: Bool = false
    /// 可以榮和
    public var canRonAgari: Bool = false
    /// 可以流局 (九種九牌)
    public var canRyukyoku: Bool = false
    /// 目標玩家 (相對座位)
    public var targetActor: Int = 0

    public init() {}

    /// 可以吃 (任意位置)
    public var canChi: Bool {
        canChiLow || canChiMid || canChiHigh
    }

    /// 可以槓 (任意種類)
    public var canKan: Bool {
        canDaiminkan || canKakan || canAnkan
    }

    /// 可以和 (自摸或榮和)
    public var canAgari: Bool {
        canTsumoAgari || canRonAgari
    }

    /// 可以跳過 (有吃碰槓榮機會時)
    public var canPass: Bool {
        canChi || canPon || canDaiminkan || canRonAgari
    }

    /// 有任何可用動作
    public var canAct: Bool {
        canDiscard || canChi || canPon || canKan || canRiichi || canAgari || canRyukyoku
    }
}

/// 吃的類型
public enum ChiType: Sendable {
    /// 吃的牌在順子最小位置 (e.g., 吃 2，用 34)
    case low
    /// 吃的牌在順子中間位置 (e.g., 吃 3，用 24)
    case mid
    /// 吃的牌在順子最大位置 (e.g., 吃 4，用 23)
    case high

    /// 根據手牌和被吃的牌判斷吃的類型
    public static func from(consumed: [Tile], target: Tile) -> ChiType {
        guard consumed.count == 2 else { return .mid }

        let a = consumed[0].deaka.index
        let b = consumed[1].deaka.index
        let minIdx = min(a, b)
        let maxIdx = max(a, b)
        let targetIdx = target.deaka.index

        if targetIdx < minIdx {
            return .low
        } else if targetIdx < maxIdx {
            return .mid
        } else {
            return .high
        }
    }
}
