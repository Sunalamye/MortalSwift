//
//  AgariCalculator.swift
//  MortalSwift
//
//  和了判定：役種與符計算
//
//  逐段移植自 libriichi `algo/agari.rs`。查表改為執行期列舉（見 HandDivision.swift）。
//
//  牌索引沿用全專案慣例：0-8 萬、9-17 筒、18-26 索、27-33 東南西北白發中。
//

import Foundation

public struct AgariCalculator {

    // MARK: - 輸入

    /// 34 格牌數，必須是 3n+2 且**已包含和了牌**
    public let tehai: [Int]
    /// 等同於 `chis.isEmpty && pons.isEmpty && minkans.isEmpty`
    public let isMenzen: Bool
    /// 吃：記錄順子最小那張
    public let chis: [Int]
    /// 碰
    public let pons: [Int]
    /// 大明槓／加槓
    public let minkans: [Int]
    /// 暗槓
    public let ankans: [Int]

    public let bakaze: Int
    public let jikaze: Int

    /// 和了牌（必須已去紅）
    public let winningTile: Int
    /// 只用於符計算與暗刻相關役的判定，**不用來判斷門前清自摸和**
    public let isRon: Bool

    public init(
        tehai: [Int], isMenzen: Bool,
        chis: [Int] = [], pons: [Int] = [], minkans: [Int] = [], ankans: [Int] = [],
        bakaze: Int, jikaze: Int, winningTile: Int, isRon: Bool
    ) {
        self.tehai = tehai
        self.isMenzen = isMenzen
        self.chis = chis
        self.pons = pons
        self.minkans = minkans
        self.ankans = ankans
        self.bakaze = bakaze
        self.jikaze = jikaze
        self.winningTile = winningTile
        self.isRon = isRon
    }

    // MARK: - 對外介面

    /// 這手牌有沒有役（找到第一個就回傳，不算符）
    public func hasYaku() -> Bool {
        searchYakusImpl(returnIfAny: true) != nil
    }

    /// 找出最高的役組合
    public func searchYakus() -> Agari? {
        searchYakusImpl(returnIfAny: false)
    }

    /// 加上額外飜數與寶牌後的最終結果
    ///
    /// `additionalHans` 包含門前清自摸和、立直、槍槓、嶺上開花、海底摸月、河底撈魚。
    /// 天和／地和不在這裡處理。
    ///
    /// 只有在「無役且 `additionalHans == 0`」時回傳 nil。
    public func agari(additionalHans: Int, doras: Int) -> Agari? {
        if let found = searchYakus() {
            if case .normal(let fu, let han) = found {
                return .normal(fu: fu, han: han + additionalHans + doras)
            }
            return found
        }
        if additionalHans == 0 { return nil }
        if additionalHans + doras >= 5 {
            return .normal(fu: 0, han: additionalHans + doras)
        }

        let (tile14, divisions) = HandDecomposer.decompose(tehai: tehai)
        guard !divisions.isEmpty else { return nil }
        let fu = divisions
            .map { DivWorker(calc: self, tile14: tile14, div: $0).calcFu(hasPinfu: false) }
            .max()
        guard let fu else { return nil }
        return .normal(fu: fu, han: additionalHans + doras)
    }

    // MARK: - 內部

    private func searchYakusImpl(returnIfAny: Bool) -> Agari? {
        // 國士無雙的形狀特殊，不能與其他役組合
        if isMenzen && ShantenCalculator.calcKokushi(tehai: tehai) == -1 {
            return .yakuman(1)
        }

        let (tile14, divisions) = HandDecomposer.decompose(tehai: tehai)
        guard !divisions.isEmpty else { return nil }

        let workers = divisions.map { DivWorker(calc: self, tile14: tile14, div: $0) }
        if returnIfAny {
            for worker in workers {
                if let found = worker.searchYakus(returnIfAny: true) { return found }
            }
            return nil
        }
        return workers.compactMap { $0.searchYakus(returnIfAny: false) }.max()
    }
}

// MARK: - 單一拆法的計算

/// 對應 libriichi 的 `DivWorker`
struct DivWorker {
    let calc: AgariCalculator
    let tile14: [Int]
    let div: HandDivision

    let pairTile: Int
    let menzenKotsu: [Int]
    let menzenShuntsu: [Int]
    /// 和了牌是否應被視為明刻的一部分（見下方說明）
    let winningTileMakesMinkou: Bool

    init(calc: AgariCalculator, tile14: [Int], div: HandDivision) {
        self.calc = calc
        self.tile14 = tile14
        self.div = div
        let kotsu = div.kotsuIndexes.map { tile14[$0] }
        let shuntsu = div.shuntsuIndexes.map { tile14[$0] }
        self.pairTile = div.hasChitoi ? (tile14.first ?? 0) : tile14[div.pairIndex]
        self.menzenKotsu = kotsu
        self.menzenShuntsu = shuntsu

        // 和了牌能不能塞進順子？能就一定塞順子。
        //
        // 順子最多只加 2 符（嵌張／邊張）且不帶額外役；把和了牌拿去讓暗刻變明刻
        // 反而至少少 2 符、還可能失去三暗刻。所以只有在沒有順子能容納它時，
        // 才承認它形成明刻。
        if !calc.isRon || !kotsu.contains(calc.winningTile) {
            self.winningTileMakesMinkou = false
        } else if calc.winningTile >= 27 {
            // 字牌榮和且成刻子 → 必為明刻
            self.winningTileMakesMinkou = true
        } else {
            let kind = calc.winningTile / 9
            let num = calc.winningTile % 9
            let low = kind * 9 + max(0, num - 2)
            let high = kind * 9 + min(num, 6)
            self.winningTileMakesMinkou = !(low...high).contains { shuntsu.contains($0) }
        }
    }

    // MARK: 集合

    private var chitoiPairs: [Int] { Array(tile14.prefix(7)) }
    private var allKotsuAndKantsu: [Int] { menzenKotsu + calc.pons + calc.minkans + calc.ankans }
    private var allShuntsu: [Int] { menzenShuntsu + calc.chis }
    private var allMentsu: [Int] { allKotsuAndKantsu + allShuntsu }

    private static func isYaokyuu(_ tile: Int) -> Bool {
        tile >= 27 || tile % 9 == 0 || tile % 9 == 8
    }

    // MARK: 符

    func calcFu(hasPinfu: Bool) -> Int {
        if div.hasChitoi { return 25 }
        var fu = 20

        for tile in menzenKotsu {
            // menzenKotsu 通常是暗刻，除非和了牌讓它變成明刻
            let isMinkou = winningTileMakesMinkou && tile == calc.winningTile
            let yaokyuu = Self.isYaokyuu(tile)
            switch (isMinkou, yaokyuu) {
            case (false, true): fu += 8
            case (false, false), (true, true): fu += 4
            case (true, false): fu += 2
            }
        }
        for tile in calc.pons { fu += Self.isYaokyuu(tile) ? 4 : 2 }
        for tile in calc.ankans { fu += Self.isYaokyuu(tile) ? 32 : 16 }
        for tile in calc.minkans { fu += Self.isYaokyuu(tile) ? 16 : 8 }

        if pairTile >= 31 {
            // 三元牌雀頭
            fu += 2
        } else {
            // 天鳳規則：連風牌是 4 符
            if pairTile == calc.bakaze { fu += 2 }
            if pairTile == calc.jikaze { fu += 2 }
        }

        if fu == 20 {
            if !calc.isMenzen { return 30 }
            if hasPinfu { return calc.isRon ? 30 : 20 }
            return calc.isRon ? 40 : 30
        }

        if !calc.isRon {
            fu += 2                     // 自摸
        } else if calc.isMenzen {
            fu += 10                    // 門前加符
        }

        if !winningTileMakesMinkou {
            if pairTile == calc.winningTile {
                fu += 2                 // 單騎
            } else {
                let isKanchanPenchan = menzenShuntsu.contains { s in
                    s + 1 == calc.winningTile
                        || (s % 9 == 0 && s + 2 == calc.winningTile)
                        || (s % 9 == 6 && s == calc.winningTile)
                }
                if isKanchanPenchan { fu += 2 }
            }
        }

        return ((fu - 1) / 10 + 1) * 10
    }

    // MARK: 役

    func searchYakus(returnIfAny: Bool) -> Agari? {
        var han = 0
        var yakuman = 0

        let hasPinfu = menzenShuntsu.count == 4
            && pairTile < 31
            && pairTile != calc.bakaze
            && pairTile != calc.jikaze
            && menzenShuntsu.contains { s in
                let num = s % 9 + 1
                return (num <= 6 && s == calc.winningTile)
                    || (num >= 2 && s + 2 == calc.winningTile)
            }

        func result() -> Agari? {
            if yakuman > 0 { return .yakuman(yakuman) }
            guard han > 0 else { return nil }
            let fu = (returnIfAny || han >= 5) ? 0 : calcFu(hasPinfu: hasPinfu)
            return .normal(fu: fu, han: han)
        }
        // 只要問「有沒有役」，累到第一個就可以收工
        var earlyReturn: Agari?
        func checkEarly() -> Bool {
            if returnIfAny { earlyReturn = result(); return true }
            return false
        }

        if hasPinfu { han += 1; if checkEarly() { return earlyReturn } }
        if div.hasChitoi { han += 2; if checkEarly() { return earlyReturn } }
        if div.hasRyanpeikou { han += 3; if checkEarly() { return earlyReturn } }
        if div.hasChuuren { yakuman += 1; if checkEarly() { return earlyReturn } }

        // ── 断幺九 ────────────────────────────────────────────────
        let hasTanyao: Bool
        if div.hasChitoi {
            hasTanyao = chitoiPairs.allSatisfy { t in
                t < 27 && t % 9 > 0 && t % 9 < 8
            }
        } else {
            hasTanyao = allShuntsu.allSatisfy { s in
                let num = s % 9
                return num > 0 && num < 6
            } && (allKotsuAndKantsu + [pairTile]).allSatisfy { k in
                k < 27 && k % 9 > 0 && k % 9 < 8
            }
        }
        if hasTanyao { han += 1; if checkEarly() { return earlyReturn } }

        // ── 対々和 ────────────────────────────────────────────────
        let hasToitoi = !div.hasChitoi && menzenShuntsu.isEmpty && calc.chis.isEmpty
        if hasToitoi { han += 2; if checkEarly() { return earlyReturn } }

        // ── 字一色 / 混一色 / 清一色 ──────────────────────────────
        var isouKind: Int?
        var hasJihaiInIsou = false
        var isChinitsuOrHonitsu = true
        let isouSource = div.hasChitoi ? chitoiPairs : allMentsu + [pairTile]
        for m in isouSource {
            let kind = m / 9
            if kind >= 3 {
                hasJihaiInIsou = true
                continue
            }
            if let prev = isouKind {
                if prev != kind { isChinitsuOrHonitsu = false; break }
            } else {
                isouKind = kind
            }
        }
        if isouKind == nil {
            yakuman += 1                                   // 字一色
            if checkEarly() { return earlyReturn }
        } else if isChinitsuOrHonitsu {
            han += (hasJihaiInIsou ? 2 : 5) + (calc.isMenzen ? 1 : 0)
            if checkEarly() { return earlyReturn }
        }

        if !div.hasChitoi {
            // ── 一盃口 ────────────────────────────────────────────
            if div.hasIpeikou {
                han += 1; if checkEarly() { return earlyReturn }
            } else if !calc.ankans.isEmpty && calc.isMenzen && menzenShuntsu.count >= 2 {
                // 有暗槓時 div 的旗標不完整，這裡直接重算
                var marks = [0, 0, 0]
                var found = false
                for t in menzenShuntsu {
                    let kind = t / 9
                    let num = t % 9
                    if (marks[kind] >> num) & 1 == 1 { found = true; break }
                    marks[kind] |= 1 << num
                }
                if found { han += 1; if checkEarly() { return earlyReturn } }
            }

            // ── 一気通貫 ──────────────────────────────────────────
            if calc.isMenzen && div.hasIttsuu {
                han += 2; if checkEarly() { return earlyReturn }
            } else if calc.chis.isEmpty && div.hasIttsuu {
                han += 1; if checkEarly() { return earlyReturn }
            } else if menzenShuntsu.count + calc.chis.count >= 3 {
                var kinds = [0, 0, 0]
                for s in allShuntsu {
                    let kind = s / 9
                    switch s % 9 {
                    case 0: kinds[kind] |= 0b001
                    case 3: kinds[kind] |= 0b010
                    case 6: kinds[kind] |= 0b100
                    default: break
                    }
                }
                if kinds.contains(0b111) { han += 1; if checkEarly() { return earlyReturn } }
            }

            // ── 三色同順 / 三色同刻 ───────────────────────────────
            var sCounter = [Int](repeating: 0, count: 9)
            for s in allShuntsu { sCounter[s % 9] |= 1 << (s / 9) }
            if sCounter.contains(0b111) {
                han += calc.isMenzen ? 2 : 1
                if checkEarly() { return earlyReturn }
            } else {
                var kCounter = [Int](repeating: 0, count: 9)
                for k in allKotsuAndKantsu where k < 27 { kCounter[k % 9] |= 1 << (k / 9) }
                if kCounter.contains(0b111) { han += 2; if checkEarly() { return earlyReturn } }
            }

            // ── 四暗刻 / 三暗刻 ───────────────────────────────────
            let ankousCount = calc.ankans.count + menzenKotsu.count
                - (winningTileMakesMinkou ? 1 : 0)
            if ankousCount == 4 {
                yakuman += 1; if checkEarly() { return earlyReturn }
            } else if ankousCount == 3 {
                han += 2; if checkEarly() { return earlyReturn }
            }

            // ── 四槓子 / 三槓子 ───────────────────────────────────
            let kansCount = calc.ankans.count + calc.minkans.count
            if kansCount == 4 {
                yakuman += 1; if checkEarly() { return earlyReturn }
            } else if kansCount == 3 {
                han += 2; if checkEarly() { return earlyReturn }
            }

            // ── 緑一色 ────────────────────────────────────────────
            // 2s=19 3s=20 4s=21 6s=23 8s=25 發=32；順子只可能是 234s
            let greenTiles: Set<Int> = [19, 20, 21, 23, 25, 32]
            let hasRyuisou = (allKotsuAndKantsu + [pairTile]).allSatisfy { greenTiles.contains($0) }
                && allShuntsu.allSatisfy { $0 == 19 }
            if hasRyuisou { yakuman += 1; if checkEarly() { return earlyReturn } }

            if !hasTanyao {
                // ── 役牌 + 大小三元四喜 ───────────────────────────
                var hasJihai = [Bool](repeating: false, count: 7)
                for k in allKotsuAndKantsu where k >= 27 { hasJihai[k - 27] = true }

                if hasJihai[calc.bakaze - 27] { han += 1; if checkEarly() { return earlyReturn } }
                if hasJihai[calc.jikaze - 27] { han += 1; if checkEarly() { return earlyReturn } }

                let saneins = (4..<7).filter { hasJihai[$0] }.count
                if saneins > 0 {
                    han += saneins
                    if checkEarly() { return earlyReturn }
                    if saneins == 3 {
                        yakuman += 1                        // 大三元
                        if checkEarly() { return earlyReturn }
                    } else if saneins == 2 && pairTile >= 31 {
                        han += 2                            // 小三元
                        if checkEarly() { return earlyReturn }
                    }
                }

                let winds = (0..<4).filter { hasJihai[$0] }.count
                if winds == 4 {
                    yakuman += 1                            // 大四喜
                    if checkEarly() { return earlyReturn }
                } else if winds == 3 && (27...30).contains(pairTile) {
                    yakuman += 1                            // 小四喜
                    if checkEarly() { return earlyReturn }
                }
            }
        }

        // ── 混老頭 / 清老頭 / 混全帯幺九 / 純全帯幺九 ─────────────
        if !hasTanyao {
            var hasJihai = false
            func isYaokyuuTracking(_ k: Int) -> Bool {
                if k >= 27 { hasJihai = true; return true }
                let num = k % 9
                return num == 0 || num == 8
            }
            let source = div.hasChitoi ? chitoiPairs : allKotsuAndKantsu + [pairTile]
            let allYaokyuu = source.allSatisfy(isYaokyuuTracking)

            if allYaokyuu {
                if div.hasChitoi || hasToitoi {
                    if hasJihai {
                        han += 2                            // 混老頭
                    } else {
                        yakuman += 1                        // 清老頭
                    }
                    if checkEarly() { return earlyReturn }
                } else {
                    let isJunchanOrChanta = allShuntsu.allSatisfy { s in
                        let num = s % 9
                        return num == 0 || num == 6
                    }
                    if isJunchanOrChanta {
                        han += (hasJihai ? 1 : 2) + (calc.isMenzen ? 1 : 0)
                        if checkEarly() { return earlyReturn }
                    }
                }
            }
        }

        return result()
    }
}
