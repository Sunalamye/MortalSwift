//
//  HandDivision.swift
//  MortalSwift
//
//  手牌拆解：把和了形拆成「n 面子 + 1 雀頭」的所有可能組合
//
//  對應 libriichi 的 `AGARI_TABLE`。原始實作是 9,362 筆的 boomphf 完美雜湊表
//  （`algo/data/agari.bin.gz`），這裡改成執行期直接列舉——
//  boomphf 的序列化格式沒有規格文件，在 Swift 重現只能靠逆向，
//  而錯誤的拆法不會報錯、只會靜默算出錯的役。列舉的正確性可以對拍驗證。
//  詳見 docs/decisions/implementation-notes.md 的 D1。
//

import Foundation

/// 一種拆法
///
/// `pairIndex` / `kotsuIndexes` / `shuntsuIndexes` 都是 `tile14` 的索引，
/// 與 libriichi 的 `Div` 一致（順子記錄的是最小那張牌）。
struct HandDivision {
    var pairIndex: Int
    var kotsuIndexes: [Int]
    var shuntsuIndexes: [Int]

    var hasChitoi = false
    var hasChuuren = false
    var hasIttsuu = false
    var hasRyanpeikou = false
    /// 與 libriichi 相同：有暗槓時這個旗標不完整，`searchYakus` 另有補救路徑
    var hasIpeikou = false
}

enum HandDecomposer {

    /// 把手牌拆成所有可能的和了形
    ///
    /// - Parameter tehai: 34 格的牌數陣列，必須是 3n+2 張且已包含和了牌
    /// - Returns: `tile14` = 手上有的牌（升冪、去重），`divisions` = 所有拆法；
    ///            不是和了形時 `divisions` 為空
    static func decompose(tehai: [Int]) -> (tile14: [Int], divisions: [HandDivision]) {
        let tile14 = (0..<34).filter { tehai[$0] > 0 }
        guard !tile14.isEmpty else { return ([], []) }

        let indexOf = { (tileID: Int) -> Int in
            // tile14 是升冪的，直接二分
            var lo = 0, hi = tile14.count - 1
            while lo <= hi {
                let mid = (lo + hi) / 2
                if tile14[mid] == tileID { return mid }
                if tile14[mid] < tileID { lo = mid + 1 } else { hi = mid - 1 }
            }
            return -1
        }

        var divisions: [HandDivision] = []
        let total = tehai.reduce(0, +)

        // ── 一般形：先定雀頭，其餘全部拆成面子 ─────────────────────
        for pairTile in tile14 where tehai[pairTile] >= 2 {
            var counts = tehai
            counts[pairTile] -= 2

            var kotsu: [Int] = []
            var shuntsu: [Int] = []
            var found: [(kotsu: [Int], shuntsu: [Int])] = []
            enumerate(&counts, from: 0, kotsu: &kotsu, shuntsu: &shuntsu, into: &found)

            for combo in found {
                var div = HandDivision(
                    pairIndex: indexOf(pairTile),
                    kotsuIndexes: combo.kotsu.map(indexOf),
                    shuntsuIndexes: combo.shuntsu.map(indexOf))
                applyFlags(&div, shuntsuTiles: combo.shuntsu,
                           mentsuCount: combo.kotsu.count + combo.shuntsu.count)
                divisions.append(div)
            }
        }

        // 九蓮寶燈是整手牌的性質，不隨拆法變動
        if isChuuren(tehai: tehai, total: total) {
            for i in divisions.indices { divisions[i].hasChuuren = true }
        }

        // ── 七對子：與一般形並存（例如 112233445566 77 兩者皆成立）──
        if total == 14 && tile14.count == 7 && tile14.allSatisfy({ tehai[$0] == 2 }) {
            divisions.append(HandDivision(
                pairIndex: 0,
                kotsuIndexes: [],
                shuntsuIndexes: [],
                hasChitoi: true))
        }

        return (tile14, divisions)
    }

    // MARK: - 面子列舉

    /// 遞迴列舉：每次都拿「還剩的最小那張牌」，試刻子與順子兩條路
    ///
    /// 固定從最小張開始消耗，同一種拆法只會被走到一次，不會重複。
    private static func enumerate(
        _ counts: inout [Int],
        from: Int,
        kotsu: inout [Int],
        shuntsu: inout [Int],
        into results: inout [(kotsu: [Int], shuntsu: [Int])]
    ) {
        var i = from
        while i < 34 && counts[i] == 0 { i += 1 }
        if i == 34 {
            results.append((kotsu, shuntsu))
            return
        }

        // 刻子
        if counts[i] >= 3 {
            counts[i] -= 3
            kotsu.append(i)
            enumerate(&counts, from: i, kotsu: &kotsu, shuntsu: &shuntsu, into: &results)
            kotsu.removeLast()
            counts[i] += 3
        }

        // 順子（字牌沒有順子，且不能跨花色）
        if i < 27 && i % 9 <= 6 && counts[i + 1] > 0 && counts[i + 2] > 0 {
            counts[i] -= 1
            counts[i + 1] -= 1
            counts[i + 2] -= 1
            shuntsu.append(i)
            enumerate(&counts, from: i, kotsu: &kotsu, shuntsu: &shuntsu, into: &results)
            shuntsu.removeLast()
            counts[i] += 1
            counts[i + 1] += 1
            counts[i + 2] += 1
        }

        // 兩條路都走不通 → 這個分支不是和了形，不記錄
    }

    // MARK: - 拆法層級的旗標

    private static func applyFlags(_ div: inout HandDivision, shuntsuTiles: [Int], mentsuCount: Int) {
        // 一盃口 / 二盃口：相同順子成對
        let sorted = shuntsuTiles.sorted()
        var duplicatePairs = 0
        var idx = 0
        while idx + 1 < sorted.count {
            if sorted[idx] == sorted[idx + 1] {
                duplicatePairs += 1
                idx += 2
            } else {
                idx += 1
            }
        }
        div.hasRyanpeikou = sorted.count == 4 && duplicatePairs == 2

        // 一盃口只在「4 面子都在手上」時成立，也就是門前 14 張。
        //
        // 這條限制是從 libriichi 的行為反推的：它的表對不足 14 張的形狀
        // 一律不設這個旗標（原始碼註解說 "sound but not complete, broken if
        // there is any ankan"）。理由是牌數不足 14 代表有副露，而一盃口要門前——
        // 寧可漏判也不能誤判。有暗槓時（同樣不足 14 但仍門前）由
        // searchYakus 的補救路徑處理。
        //
        // 二盃口取代一盃口，兩者不同時計入。
        div.hasIpeikou = duplicatePairs >= 1 && !div.hasRyanpeikou && mentsuCount == 4

        // 一氣通貫：同一花色的 123 / 456 / 789
        let shuntsuSet = Set(shuntsuTiles)
        div.hasIttsuu = (0..<3).contains { kind in
            shuntsuSet.contains(kind * 9) &&
            shuntsuSet.contains(kind * 9 + 3) &&
            shuntsuSet.contains(kind * 9 + 6)
        }
    }

    /// 九蓮寶燈：同一花色的 1112345678999 再加任一張同花色牌
    private static func isChuuren(tehai: [Int], total: Int) -> Bool {
        guard total == 14 else { return false }
        for kind in 0..<3 {
            let base = kind * 9
            // 其他花色與字牌都必須是空的
            let onlyThisSuit = (0..<34).allSatisfy { t in
                (t >= base && t < base + 9) || tehai[t] == 0
            }
            guard onlyThisSuit else { continue }
            guard tehai[base] >= 3, tehai[base + 8] >= 3 else { continue }
            guard (1...7).allSatisfy({ tehai[base + $0] >= 1 }) else { continue }
            return true
        }
        return false
    }
}
