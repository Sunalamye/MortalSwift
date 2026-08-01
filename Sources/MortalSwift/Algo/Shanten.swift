//
//  Shanten.swift
//  MortalSwift
//
//  向聽數計算
//
//  向聽數定義:
//  - -1: 和了形
//  - 0: 聽牌
//  - 1-6: 一向聽至六向聽
//

import Foundation

/// 向聽數計算器
public enum ShantenCalculator {

    // MARK: - Public API

    /// 計算一般形向聽數
    /// - Parameters:
    ///   - tehai: 手牌計數陣列 (34 張)
    ///   - lenDiv3: 手牌組數 (0-4，表示可形成的面子數)
    /// - Returns: 向聽數 (-1 到 6)
    public static func calcNormal(tehai: [Int], lenDiv3: Int) -> Int {
        guard tehai.count == 34, lenDiv3 >= 0, lenDiv3 <= 4 else { return 6 }

        let raw = calcNormalCore(tehai: tehai, lenDiv3: lenDiv3)

        // 「宣稱聽牌」要再確認一次進張存不存在。
        //
        // 面子分解本身不管牌是否還有剩：`1111m 333p 222s 444z` 會被拆成
        // 111m/333p/222s/444z 四組面子 + 1m 單騎，形式上是聽牌——但四枚 1m 都在手上，
        // 第五枚摸不到，實際上是一向聽。逐張試進是唯一能排除這種假聽牌的方法。
        //
        // 只對 3n+1 手牌做：3n+2 再加一張就變成 15 張，沒有意義。
        guard raw == 0, tehai.reduce(0, +) == lenDiv3 * 3 + 1 else { return raw }

        for tile in 0..<34 where tehai[tile] < 4 {
            var probe = tehai
            probe[tile] += 1
            if calcNormalCore(tehai: probe, lenDiv3: lenDiv3) == -1 {
                return 0
            }
        }
        return 1
    }

    /// 純面子分解，不檢查進張是否還有剩
    private static func calcNormalCore(tehai: [Int], lenDiv3: Int) -> Int {
        var minShanten = 8

        calcNormalRecursive(
            tehai: tehai,
            suitStart: 0,
            mentsu: 0,
            tatsu: 0,
            hasJantou: false,
            targetMentsu: lenDiv3,
            minShanten: &minShanten
        )

        return minShanten - 1
    }

    /// 計算七對子向聽數
    /// - Parameter tehai: 手牌計數陣列 (34 張)
    /// - Returns: 向聽數 (-1 到 6)
    public static func calcChitoi(tehai: [Int]) -> Int {
        guard tehai.count == 34 else { return 6 }

        var pairs = 0
        var kinds = 0

        for count in tehai where count > 0 {
            kinds += 1
            if count >= 2 {
                pairs += 1
            }
        }

        let redundant = max(0, 7 - kinds)
        return 7 - pairs + redundant - 1
    }

    /// 計算國士無雙向聽數
    /// - Parameter tehai: 手牌計數陣列 (34 張)
    /// - Returns: 向聽數 (-1 到 13)
    public static func calcKokushi(tehai: [Int]) -> Int {
        guard tehai.count == 34 else { return 13 }

        // 幺九牌索引: 1m, 9m, 1p, 9p, 1s, 9s, E, S, W, N, P, F, C
        let yaokyuuIndices = [0, 8, 9, 17, 18, 26, 27, 28, 29, 30, 31, 32, 33]

        var pairs = 0
        var kinds = 0

        for idx in yaokyuuIndices {
            let count = tehai[idx]
            if count > 0 {
                kinds += 1
                if count >= 2 {
                    pairs += 1
                }
            }
        }

        let redundant = pairs > 0 ? 1 : 0
        return 14 - kinds - redundant - 1
    }

    /// 計算綜合向聽數 (一般形、七對子、國士無雙取最小)
    /// - Parameters:
    ///   - tehai: 手牌計數陣列 (34 張)
    ///   - lenDiv3: 手牌組數 (0-4)
    /// - Returns: 向聽數 (-1 到 6)
    public static func calcAll(tehai: [Int], lenDiv3: Int) -> Int {
        var shanten = calcNormal(tehai: tehai, lenDiv3: lenDiv3)

        // 只有完整手牌 (4組) 才計算七對子和國士
        if shanten <= 0 || lenDiv3 < 4 {
            return shanten
        }

        shanten = min(shanten, calcChitoi(tehai: tehai))
        if shanten > 0 {
            shanten = min(shanten, calcKokushi(tehai: tehai))
        }

        return shanten
    }

    // MARK: - Private Methods

    /// 遞歸計算一般形向聽
    private static func calcNormalRecursive(
        tehai: [Int],
        suitStart: Int,
        mentsu: Int,
        tatsu: Int,
        hasJantou: Bool,
        targetMentsu: Int,
        minShanten: inout Int
    ) {
        // 剪枝必須用**下界**（樂觀估計），不能用當前值。
        //
        // 原本寫的是 `if calcShantenFromState(...) >= minShanten { return }`，
        // 但 calcShantenFromState 隨著遞迴取到更多面子／搭子只會遞減，
        // 也就是它是該子樹的**上界**而非下界，拿來剪枝會砍掉仍可能更好的分支。
        //
        // 更糟的是根節點就會中招：target=4 時初始值為 4*2-0-0+1 = 9，
        // 而 minShanten 初值 8，`9 >= 8` 成立 → 整個遞迴一次都沒跑，
        // 任何手牌都回傳 8-1 = 7。（單純調大初值不能解決，深層節點仍會誤剪。）
        //
        // 正確下界：剩餘的牌可能湊成面子，**也**可能湊成搭子——兩者都會降低向聽。
        // 只算面子不算搭子的版本不是下界：例如剩 2s3s4s5s6s（5 張）時它只算得出
        // 「1 組面子」，但實際是「1 面子 + 1 搭子」，估出來的值比真值高，
        // 於是這個分支會被誤剪，聽牌被算成一向聽。
        //
        // 枚舉「拿 a 組面子、剩下盡量湊搭子」的所有切法取最小，才是真正的樂觀估計。
        var remaining = 0
        for i in suitStart..<34 { remaining += tehai[i] }

        let maxExtraMentsu = min(targetMentsu - mentsu, remaining / 3)
        var lowerBound = Int.max
        if maxExtraMentsu >= 0 {
            for extraMentsu in 0...max(0, maxExtraMentsu) {
                let leftover = remaining - extraMentsu * 3
                let extraTatsu = min(targetMentsu - mentsu - extraMentsu, leftover / 2)
                lowerBound = min(lowerBound, calcShantenFromState(
                    mentsu: mentsu + extraMentsu,
                    tatsu: tatsu + max(0, extraTatsu),
                    hasJantou: true,
                    targetMentsu: targetMentsu))
            }
        }
        if lowerBound >= minShanten {
            return
        }

        let currentShanten = calcShantenFromState(
            mentsu: mentsu, tatsu: tatsu, hasJantou: hasJantou, targetMentsu: targetMentsu)

        // 找到下一個有牌的位置
        var pos = suitStart
        while pos < 34 && tehai[pos] == 0 {
            pos += 1
        }

        if pos >= 34 {
            // 沒有更多牌了，計算向聽數
            minShanten = min(minShanten, currentShanten)
            return
        }

        var mutableTehai = tehai

        // 處理字牌 (只能刻子和對子)
        if pos >= 27 {
            // 不取
            calcNormalRecursive(tehai: mutableTehai, suitStart: pos + 1, mentsu: mentsu, tatsu: tatsu, hasJantou: hasJantou, targetMentsu: targetMentsu, minShanten: &minShanten)

            // 取刻子
            if mutableTehai[pos] >= 3 {
                mutableTehai[pos] -= 3
                calcNormalRecursive(tehai: mutableTehai, suitStart: pos, mentsu: mentsu + 1, tatsu: tatsu, hasJantou: hasJantou, targetMentsu: targetMentsu, minShanten: &minShanten)
                mutableTehai[pos] += 3
            }

            // 取對子作為雀頭或搭子
            if mutableTehai[pos] >= 2 {
                mutableTehai[pos] -= 2
                if !hasJantou {
                    calcNormalRecursive(tehai: mutableTehai, suitStart: pos + 1, mentsu: mentsu, tatsu: tatsu, hasJantou: true, targetMentsu: targetMentsu, minShanten: &minShanten)
                } else {
                    calcNormalRecursive(tehai: mutableTehai, suitStart: pos + 1, mentsu: mentsu, tatsu: tatsu + 1, hasJantou: hasJantou, targetMentsu: targetMentsu, minShanten: &minShanten)
                }
                mutableTehai[pos] += 2
            }

            return
        }

        // 處理數牌
        let suitBase = (pos / 9) * 9
        let num = pos - suitBase  // 0-8

        // 不取這張牌
        calcNormalRecursive(tehai: mutableTehai, suitStart: pos + 1, mentsu: mentsu, tatsu: tatsu, hasJantou: hasJantou, targetMentsu: targetMentsu, minShanten: &minShanten)

        // 取刻子
        if mutableTehai[pos] >= 3 {
            mutableTehai[pos] -= 3
            calcNormalRecursive(tehai: mutableTehai, suitStart: pos, mentsu: mentsu + 1, tatsu: tatsu, hasJantou: hasJantou, targetMentsu: targetMentsu, minShanten: &minShanten)
            mutableTehai[pos] += 3
        }

        // 取順子 (只能是數牌，且不能跨花色)
        if num <= 6 && pos + 2 < suitBase + 9 {
            if mutableTehai[pos] >= 1 && mutableTehai[pos + 1] >= 1 && mutableTehai[pos + 2] >= 1 {
                mutableTehai[pos] -= 1
                mutableTehai[pos + 1] -= 1
                mutableTehai[pos + 2] -= 1
                calcNormalRecursive(tehai: mutableTehai, suitStart: pos, mentsu: mentsu + 1, tatsu: tatsu, hasJantou: hasJantou, targetMentsu: targetMentsu, minShanten: &minShanten)
                mutableTehai[pos] += 1
                mutableTehai[pos + 1] += 1
                mutableTehai[pos + 2] += 1
            }
        }

        // 取對子
        if mutableTehai[pos] >= 2 {
            mutableTehai[pos] -= 2
            if !hasJantou {
                calcNormalRecursive(tehai: mutableTehai, suitStart: pos + 1, mentsu: mentsu, tatsu: tatsu, hasJantou: true, targetMentsu: targetMentsu, minShanten: &minShanten)
            } else {
                calcNormalRecursive(tehai: mutableTehai, suitStart: pos + 1, mentsu: mentsu, tatsu: tatsu + 1, hasJantou: hasJantou, targetMentsu: targetMentsu, minShanten: &minShanten)
            }
            mutableTehai[pos] += 2
        }

        // 取兩面搭子
        if num <= 7 && pos + 1 < suitBase + 9 {
            if mutableTehai[pos] >= 1 && mutableTehai[pos + 1] >= 1 {
                mutableTehai[pos] -= 1
                mutableTehai[pos + 1] -= 1
                calcNormalRecursive(tehai: mutableTehai, suitStart: pos + 1, mentsu: mentsu, tatsu: tatsu + 1, hasJantou: hasJantou, targetMentsu: targetMentsu, minShanten: &minShanten)
                mutableTehai[pos] += 1
                mutableTehai[pos + 1] += 1
            }
        }

        // 取嵌張搭子
        if num <= 6 && pos + 2 < suitBase + 9 {
            if mutableTehai[pos] >= 1 && mutableTehai[pos + 2] >= 1 {
                mutableTehai[pos] -= 1
                mutableTehai[pos + 2] -= 1
                calcNormalRecursive(tehai: mutableTehai, suitStart: pos + 1, mentsu: mentsu, tatsu: tatsu + 1, hasJantou: hasJantou, targetMentsu: targetMentsu, minShanten: &minShanten)
                mutableTehai[pos] += 1
                mutableTehai[pos + 2] += 1
            }
        }
    }

    /// 從狀態計算向聽數
    private static func calcShantenFromState(mentsu: Int, tatsu: Int, hasJantou: Bool, targetMentsu: Int) -> Int {
        // 向聽數 = (需要的面子數 - 已有面子數) * 2 - 搭子數 - 雀頭數 + 1
        // 但搭子最多用到 (需要面子數 - 已有面子數) 個
        let neededMentsu = targetMentsu - mentsu
        let usableTatsu = min(tatsu, neededMentsu)
        let jantouValue = hasJantou ? 1 : 0

        return neededMentsu * 2 - usableTatsu - jantouValue + 1
    }
}
