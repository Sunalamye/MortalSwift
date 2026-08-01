//
//  Point.swift
//  MortalSwift
//
//  和了點數換算
//
//  移植自 libriichi `algo/point.rs`。
//
//  原始實作是一張 40 行的 (符, 飜) → 點數對照表，但它自己的測試
//  （`mod test::table`）證明那張表等同於下面這個通式。這裡採用通式：
//  同樣的結果、少掉抄錯一格的風險。
//

import Foundation

/// 和了點數
public struct Point: Sendable, Equatable {
    /// 榮和時放銃者支付
    public let ron: Int
    /// 自摸時每位子家支付
    public let tsumoKo: Int
    /// 自摸時莊家支付（自己是莊家時為 0）
    public let tsumoOya: Int

    public init(ron: Int, tsumoKo: Int, tsumoOya: Int) {
        self.ron = ron
        self.tsumoKo = tsumoKo
        self.tsumoOya = tsumoOya
    }

    /// 依符與飜計算點數
    public static func calc(isOya: Bool, fu: Int, han: Int) -> Point {
        let base: Int
        switch han {
        case 13...: base = 8000          // 役滿
        case 11...12: base = 6000        // 三倍滿
        case 8...10: base = 4000         // 倍滿
        case 6...7: base = 3000          // 跳滿
        case 5: base = 2000              // 滿貫
        default:
            // 符 × 2^(2+飜)，上限為滿貫
            base = min(fu * (1 << (2 + han)), 2000)
        }

        // 點數一律進位到百位
        func round100(_ multiplier: Int) -> Int {
            (base * multiplier + 99) / 100 * 100
        }

        if isOya {
            return Point(ron: round100(6), tsumoKo: round100(2), tsumoOya: 0)
        } else {
            return Point(ron: round100(4), tsumoKo: round100(1), tsumoOya: round100(2))
        }
    }

    /// 役滿（`count` 為幾倍役滿）
    public static func yakuman(isOya: Bool, count: Int) -> Point {
        if isOya {
            return Point(ron: 48000 * count, tsumoKo: 16000 * count, tsumoOya: 0)
        } else {
            return Point(ron: 32000 * count, tsumoKo: 8000 * count, tsumoOya: 16000 * count)
        }
    }

    /// 自摸時的總收入
    public func tsumoTotal(isOya: Bool) -> Int {
        isOya ? tsumoKo * 3 : tsumoKo * 2 + tsumoOya
    }
}

/// 和了結果：一般役或役滿
public enum Agari: Sendable, Equatable, Comparable {
    /// 飜數超過 4 時 `fu` 可能是 0（用不到）
    case normal(fu: Int, han: Int)
    /// 幾倍役滿
    case yakuman(Int)

    /// 換算成點數
    public func point(isOya: Bool) -> Point {
        switch self {
        case .normal(let fu, let han):
            return Point.calc(isOya: isOya, fu: fu, han: han)
        case .yakuman(let count):
            return Point.yakuman(isOya: isOya, count: count)
        }
    }

    /// 比較用的「役滿倍數」——一般役視為 0
    private var yakumanCount: Int {
        if case .yakuman(let n) = self { return n }
        return 0
    }

    /// 排序：先比役滿倍數，再比飜，最後比符
    ///
    /// 對應 libriichi 的 `impl Ord for Agari`——同飜時符大者勝。
    public static func < (lhs: Agari, rhs: Agari) -> Bool {
        let (lc, rc) = (lhs.yakumanCount, rhs.yakumanCount)
        if lc != rc { return lc < rc }
        if lc > 0 { return false }   // 兩者都是役滿且倍數相同

        guard case .normal(let lfu, let lhan) = lhs,
              case .normal(let rfu, let rhan) = rhs else { return false }
        if lhan != rhan { return lhan < rhan }
        return lfu < rfu
    }
}
