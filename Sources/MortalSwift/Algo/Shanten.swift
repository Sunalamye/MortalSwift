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

        var minShanten = 8

        // 遞歸計算
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
        // 剪枝：當前狀態不可能更好
        let currentShanten = calcShantenFromState(mentsu: mentsu, tatsu: tatsu, hasJantou: hasJantou, targetMentsu: targetMentsu)
        if currentShanten >= minShanten {
            return
        }

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
