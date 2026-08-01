//
//  SPCalculator.swift
//  MortalSwift
//
//  單人麻將期望值推演
//
//  移植自 libriichi `algo/sp/`（其本身是 nekobean 的 C++ mahjong-cpp 的 Rust 移植）。
//
//  算的是：對每一張可打的牌，往後每一巡的**聽牌率、和牌率、期望點數**。
//  這組數字佔 observation 的 ch889–1011，是模型訓練時就有、但先前 Naki 送全 0 的那塊。
//
//  牌的編號沿用 libriichi：0-33 普通牌，34/35/36 為紅五萬/筒/索。
//

import Foundation

// MARK: - 牌編號小工具

enum SPTile {
    static let unknown = 37

    /// 去紅
    @inline(__always)
    static func deaka(_ id: Int) -> Int {
        switch id {
        case 34: return 4
        case 35: return 13
        case 36: return 22
        default: return id
        }
    }

    /// 加紅
    @inline(__always)
    static func akaize(_ id: Int) -> Int {
        switch id {
        case 4: return 34
        case 13: return 35
        case 22: return 36
        default: return id
        }
    }

    /// 寶牌指示牌的下一張
    static func next(_ id: Int) -> Int {
        let t = deaka(id)
        if t < 27 {
            let kind = t / 9, num = t % 9
            return kind * 9 + (num + 1) % 9
        }
        if t < 31 { return 27 + (t - 27 + 1) % 4 }   // 東南西北
        return 31 + (t - 31 + 1) % 3                  // 白發中
    }

    /// 指示牌方向的前一張（用於算裏寶牌機率）
    static func prev(_ id: Int) -> Int {
        let t = deaka(id)
        if t < 27 {
            let kind = t / 9, num = t % 9
            return kind * 9 + (num + 8) % 9
        }
        if t < 31 { return 27 + (t - 27 + 3) % 4 }
        return 31 + (t - 31 + 2) % 3
    }

    /// 打牌優先順位，數字越大越該先打（取自 libriichi 的 DISCARD_PRIORITIES）
    static let discardPriorities: [Int] = [
        6, 5, 4, 3, 2, 3, 4, 5, 6,   // 萬
        6, 5, 4, 3, 2, 3, 4, 5, 6,   // 筒
        6, 5, 4, 3, 2, 3, 4, 5, 6,   // 索
        7, 7, 7, 7, 7, 7, 7,         // 字
        1, 1, 1,                     // 紅五
        0,                           // 未知
    ]

    /// `lhs` 的打牌優先順位是否高於 `rhs`
    static func discardPriorityGreater(_ lhs: Int, _ rhs: Int) -> Bool {
        let l = discardPriorities[lhs], r = discardPriorities[rhs]
        if l != r { return l > r }
        // 同優先順位時，編號小的優先
        return rhs > lhs
    }
}

// MARK: - 推演狀態

/// 手牌與牌山的可變狀態
public struct SPState: Hashable {
    public var tehai: [Int]            // 34
    public var akasInHand: [Bool]      // 3
    public var tilesInWall: [Int]      // 34
    public var akasInWall: [Bool]      // 3

    public init(tehai: [Int], akasInHand: [Bool], tilesSeen: [Int], akasSeen: [Bool]) {
        self.tehai = tehai
        self.akasInHand = akasInHand
        self.tilesInWall = tilesSeen.map { 4 - $0 }
        self.akasInWall = akasSeen.map { !$0 }
    }

    mutating func discard(_ tile: Int) {
        tehai[SPTile.deaka(tile)] -= 1
        if tile >= 34 { akasInHand[tile - 34] = false }
    }

    mutating func undoDiscard(_ tile: Int) {
        tehai[SPTile.deaka(tile)] += 1
        if tile >= 34 { akasInHand[tile - 34] = true }
    }

    mutating func deal(_ tile: Int) {
        tilesInWall[SPTile.deaka(tile)] -= 1
        if tile >= 34 { akasInWall[tile - 34] = false }
        undoDiscard(tile)
    }

    mutating func undoDeal(_ tile: Int) {
        discard(tile)
        tilesInWall[SPTile.deaka(tile)] += 1
        if tile >= 34 { akasInWall[tile - 34] = true }
    }

    var sumLeftTiles: Int { tilesInWall.reduce(0, +) }

    /// 可打的牌與打了之後的向聽變化
    func discardTiles(shanten: Int, tehaiLenDiv3: Int) -> [(tile: Int, shantenDiff: Int)] {
        var result: [(Int, Int)] = []
        var work = tehai
        for tid in 0..<34 where tehai[tid] > 0 {
            work[tid] -= 1
            let after = ShantenCalculator.calcAll(tehai: work, lenDiv3: tehaiLenDiv3)
            work[tid] += 1

            // 只剩紅五那一張時，打出去的就是紅五
            var tile = tid
            if tehai[tid] == 1 {
                switch tid {
                case 4 where akasInHand[0]: tile = 34
                case 13 where akasInHand[1]: tile = 35
                case 22 where akasInHand[2]: tile = 36
                default: break
                }
            }
            result.append((tile, after - shanten))
        }
        return result
    }

    /// 可能摸到的牌、剩餘張數與向聽變化
    func drawTiles(shanten: Int, tehaiLenDiv3: Int) -> [(tile: Int, count: Int, shantenDiff: Int)] {
        var result: [(Int, Int, Int)] = []
        var work = tehai
        for tid in 0..<34 where tilesInWall[tid] > 0 {
            let count = tilesInWall[tid]
            work[tid] += 1
            let after = ShantenCalculator.calcAll(tehai: work, lenDiv3: tehaiLenDiv3)
            work[tid] -= 1
            let diff = after - shanten

            let akaSlot: Int? = (tid == 4 && akasInWall[0]) ? 0
                : (tid == 13 && akasInWall[1]) ? 1
                : (tid == 22 && akasInWall[2]) ? 2 : nil

            if akaSlot != nil {
                // 紅五與普通五分開算：點數不同
                if count >= 2 { result.append((tid, count - 1, diff)) }
                result.append((SPTile.akaize(tid), 1, diff))
            } else {
                result.append((tid, count, diff))
            }
        }
        return result
    }

    /// 進張（摸了會前進向聽的牌）
    func requiredTiles(tehaiLenDiv3: Int) -> [(tile: Int, count: Int)] {
        var result: [(Int, Int)] = []
        var work = tehai
        let shanten = ShantenCalculator.calcAll(tehai: work, lenDiv3: tehaiLenDiv3)
        for tid in 0..<34 where tilesInWall[tid] > 0 {
            work[tid] += 1
            let after = ShantenCalculator.calcAll(tehai: work, lenDiv3: tehaiLenDiv3)
            work[tid] -= 1
            if after < shanten { result.append((tid, tilesInWall[tid])) }
        }
        return result
    }
}

// MARK: - 每張打牌的推演結果

public struct SPCandidate {
    /// 打哪張（`SPTile.unknown` 表示不打牌，只算摸牌）
    public let tile: Int
    /// 每一巡的聽牌機率
    public let tenpaiProbs: [Float]
    /// 每一巡的和牌機率
    public let winProbs: [Float]
    /// 每一巡的期望點數
    public let expValues: [Float]
    /// 進張與張數
    public let requiredTiles: [(tile: Int, count: Int)]
    public let numRequiredTiles: Int
    /// 是否為向聽戻し
    public let shantenDown: Bool
}

// MARK: - 推演器

public struct SPCalculator {

    /// 向聽數超過這個值就只算進張，不做機率推演（原始實作的門檻）
    private static let shantenThreshold = 3

    public var tehaiLenDiv3: Int
    public var isMenzen: Bool
    public var chis: [Int]
    public var pons: [Int]
    public var minkans: [Int]
    public var ankans: [Int]
    public var bakaze: Int
    public var jikaze: Int
    /// 副露（含暗槓）裡的寶牌數
    public var numDorasInFuuro: Int
    public var doraIndicators: [Int]
    public var calcDoubleRiichi: Bool
    public var calcHaitei: Bool
    public var preferRiichi: Bool

    public init(
        tehaiLenDiv3: Int, isMenzen: Bool,
        chis: [Int], pons: [Int], minkans: [Int], ankans: [Int],
        bakaze: Int, jikaze: Int,
        numDorasInFuuro: Int, doraIndicators: [Int],
        calcDoubleRiichi: Bool, calcHaitei: Bool, preferRiichi: Bool
    ) {
        self.tehaiLenDiv3 = tehaiLenDiv3
        self.isMenzen = isMenzen
        self.chis = chis
        self.pons = pons
        self.minkans = minkans
        self.ankans = ankans
        self.bakaze = bakaze
        self.jikaze = jikaze
        self.numDorasInFuuro = numDorasInFuuro
        self.doraIndicators = doraIndicators
        self.calcDoubleRiichi = calcDoubleRiichi
        self.calcHaitei = calcHaitei
        self.preferRiichi = preferRiichi
    }

    /// 裏寶牌張數的機率分布（表寶牌 2-5 枚時用統計值）
    private static let uradoraProbTable: [[Float]] = [
        [0.639485, 0.327801, 0.0327134, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        [0.406736, 0.42281, 0.147966, 0.021674, 0.0008142, 0, 0, 0, 0, 0, 0, 0, 0],
        [0.257516, 0.406819, 0.246851, 0.0757724, 0.0122266, 0.0008004, 1.43e-5, 0, 0, 0, 0, 0, 0],
        [0.162199, 0.346513, 0.301539, 0.142396, 0.0401276, 0.0066491, 0.0005575, 1.85e-5, 0, 0, 0, 0, 0],
        [0.101768, 0.275319, 0.313742, 0.20189, 0.081774, 0.0215394, 0.0035918, 0.0003607, 1.52e-5, 3e-7, 0, 0, 0],
    ]

    /// 推演
    ///
    /// - Parameters:
    ///   - canDiscard: 手牌是不是 3n+2
    ///   - tsumosLeft: 還能摸幾次，必須在 [1, 17]
    ///   - curShanten: 目前向聽，必須 >= 0
    /// - Returns: 依期望值由高到低排序，index 0 是最佳選擇
    public func calc(
        state initState: SPState, canDiscard: Bool, tsumosLeft: Int, curShanten: Int
    ) -> [SPCandidate]? {
        guard curShanten >= 0, tsumosLeft >= 1, tsumosLeft <= 17 else { return nil }

        var engine = SPEngine(
            sup: self,
            state: initState,
            maxTsumo: tsumosLeft)
        return engine.calc(canDiscard: canDiscard, curShanten: curShanten)
    }

    // MARK: 和了點數

    /// 和了時的點數：[基本, +1飜, +2飜, +3飜]；無役回傳 nil
    ///
    /// 之所以要算到 +3 飜，是因為雙立直、一發、海底最多再加 3 飜。
    fileprivate func score(state: SPState, winTile: Int) -> [Float]? {
        let calc = AgariCalculator(
            tehai: state.tehai, isMenzen: isMenzen,
            chis: chis, pons: pons, minkans: minkans, ankans: ankans,
            bakaze: bakaze, jikaze: jikaze,
            winningTile: SPTile.deaka(winTile), isRon: false)
        let isOya = jikaze == 27

        let additionalYakus = isMenzen ? (preferRiichi ? 2 : 1) : 0
        let numDoras = doraIndicators.reduce(0) { $0 + state.tehai[SPTile.next($1)] }
            + state.akasInHand.filter { $0 }.count
            + numDorasInFuuro

        guard let result = calc.agari(additionalHans: additionalYakus, doras: numDoras) else {
            return nil
        }
        guard case .normal(let fu, let han) = result else {
            let total = Float(result.point(isOya: isOya).tsumoTotal(isOya: isOya))
            return [total, total, total, total]
        }

        var scores = [Float](repeating: 0, count: 4)
        let assumeRiichi = isMenzen && preferRiichi

        if assumeRiichi && doraIndicators.count == 1 {
            // 表寶牌只有一張時精確算裏寶牌
            var nIndicators = [Int](repeating: 0, count: 5)
            var sumIndicators = 0
            for tid in 0..<34 where state.tehai[tid] > 0 {
                let indCount = state.tilesInWall[SPTile.prev(tid)]
                nIndicators[state.tehai[tid]] += indCount
                sumIndicators += indCount
            }

            let nLeft = state.sumLeftTiles
            guard nLeft > 0 else { return nil }
            var uradoraProbs = [Float](repeating: 0, count: 5)
            uradoraProbs[0] = Float(nLeft - sumIndicators) / Float(nLeft)
            for i in 1..<5 { uradoraProbs[i] = Float(nIndicators[i]) / Float(nLeft) }

            for i in 0..<4 {
                for (j, p) in uradoraProbs.enumerated() where p != 0 {
                    let agari = Agari.normal(fu: fu, han: han + i + j)
                    scores[i] += Float(agari.point(isOya: isOya).tsumoTotal(isOya: isOya)) * p
                }
            }
        } else if assumeRiichi && doraIndicators.count > 1 {
            // 表寶牌兩張以上時用統計分布
            let row = Self.uradoraProbTable[min(doraIndicators.count - 1, 4)]
            for i in 0..<4 {
                for (j, p) in row.enumerated() where p != 0 {
                    let agari = Agari.normal(fu: fu, han: han + i + j)
                    scores[i] += Float(agari.point(isOya: isOya).tsumoTotal(isOya: isOya)) * p
                }
            }
        } else {
            for i in 0..<4 {
                let agari = Agari.normal(fu: fu, han: han + i)
                scores[i] = Float(agari.point(isOya: isOya).tsumoTotal(isOya: isOya))
            }
        }

        return scores
    }
}

// MARK: - 推演引擎

/// 一次推演的可變狀態
///
/// 對應 libriichi 的 `SPCalculatorState`。原始實作有「手變」與「向聽戻し」兩條分支，
/// 但 `PlayerState.singlePlayerTables` 的呼叫一律關掉它們，因此這裡不移植——
/// 少寫兩百行沒被走到的路徑，也少兩百行沒被驗證的風險。
private struct SPEngine {
    let sup: SPCalculator
    var state: SPState
    let maxTsumo: Int

    /// `tsumoProbTable[i][j]` = 有效牌 i+1 張時，第 j 巡摸到的機率
    let tsumoProbTable: [[Float]]
    /// `notTsumoProbTable[i][j]` = 有效牌共 i 張時，到第 j-1 巡都沒摸到的機率
    let notTsumoProbTable: [[Float]]

    struct Values {
        var tenpaiProbs: [Float]
        var winProbs: [Float]
        var expValues: [Float]
    }

    /// 依向聽分層的記憶表
    var drawCache: [[SPState: Values]]
    var discardCache: [[SPState: Values]]

    init(sup: SPCalculator, state: SPState, maxTsumo: Int) {
        self.sup = sup
        self.state = state
        self.maxTsumo = maxTsumo

        let nLeft = state.sumLeftTiles
        var tsumo = [[Float]](repeating: [Float](repeating: 0, count: maxTsumo), count: 4)
        for i in 0..<4 {
            for j in 0..<maxTsumo where nLeft - j > 0 {
                tsumo[i][j] = Float(i + 1) / Float(nLeft - j)
            }
        }
        self.tsumoProbTable = tsumo

        // 列數要蓋到「所有剩牌都是有效牌」的極端情形
        let maxRows = 34 * 4 - 1 - 13 + 1
        var notTsumo = [[Float]](repeating: [Float](repeating: 0, count: maxTsumo), count: maxRows)
        for i in 0...min(nLeft, maxRows - 1) {
            notTsumo[i][0] = 1
            let bound = min(maxTsumo - 1, nLeft - i)
            for j in 0..<bound where nLeft - j > 0 {
                notTsumo[i][j + 1] = notTsumo[i][j] * Float(nLeft - i - j) / Float(nLeft - j)
            }
        }
        self.notTsumoProbTable = notTsumo

        self.drawCache = Array(repeating: [:], count: 5)
        self.discardCache = Array(repeating: [:], count: 5)
    }

    private var zeroValues: Values {
        Values(
            tenpaiProbs: [Float](repeating: 0, count: maxTsumo),
            winProbs: [Float](repeating: 0, count: maxTsumo),
            expValues: [Float](repeating: 0, count: maxTsumo))
    }

    // MARK: 入口

    mutating func calc(canDiscard: Bool, curShanten: Int) -> [SPCandidate] {
        var candidates: [SPCandidate]
        if curShanten <= 3 {
            candidates = canDiscard ? analyzeDiscard(shanten: curShanten) : analyzeDraw(shanten: curShanten)
            // 依期望值由高到低
            candidates.sort { lhs, rhs in compare(lhs, rhs, by: .ev) }
        } else {
            // 四向聽以上只算進張
            candidates = canDiscard ? analyzeDiscardSimple(shanten: curShanten) : analyzeDrawSimple()
            candidates.sort { lhs, rhs in compare(lhs, rhs, by: .notShantenDown) }
        }
        return candidates
    }

    // MARK: 分析

    private mutating func analyzeDiscard(shanten: Int) -> [SPCandidate] {
        var candidates: [SPCandidate] = []
        for (tile, shantenDiff) in state.discardTiles(shanten: shanten, tehaiLenDiv3: sup.tehaiLenDiv3)
        where shantenDiff == 0 {
            state.discard(tile)
            let required = state.requiredTiles(tehaiLenDiv3: sup.tehaiLenDiv3)
            let values = draw(shanten: shanten)
            state.undoDiscard(tile)

            // 已經聽牌時聽牌機率恆為 1
            let tenpai = shanten == 0
                ? [Float](repeating: 1, count: maxTsumo)
                : values.tenpaiProbs

            candidates.append(makeCandidate(
                tile: tile, tenpai: tenpai, win: values.winProbs, ev: values.expValues,
                required: required, shantenDown: false))
        }
        return candidates
    }

    private mutating func analyzeDraw(shanten: Int) -> [SPCandidate] {
        let required = state.requiredTiles(tehaiLenDiv3: sup.tehaiLenDiv3)
        let values = draw(shanten: shanten)
        let tenpai = shanten == 0
            ? [Float](repeating: 1, count: maxTsumo)
            : values.tenpaiProbs
        return [makeCandidate(
            tile: SPTile.unknown, tenpai: tenpai, win: values.winProbs, ev: values.expValues,
            required: required, shantenDown: false)]
    }

    private mutating func analyzeDiscardSimple(shanten: Int) -> [SPCandidate] {
        var candidates: [SPCandidate] = []
        for (tile, shantenDiff) in state.discardTiles(shanten: shanten, tehaiLenDiv3: sup.tehaiLenDiv3) {
            state.discard(tile)
            let required = state.requiredTiles(tehaiLenDiv3: sup.tehaiLenDiv3)
            state.undoDiscard(tile)
            candidates.append(makeCandidate(
                tile: tile,
                tenpai: [], win: [], ev: [],
                required: required, shantenDown: shantenDiff == 1))
        }
        return candidates
    }

    private mutating func analyzeDrawSimple() -> [SPCandidate] {
        let required = state.requiredTiles(tehaiLenDiv3: sup.tehaiLenDiv3)
        return [makeCandidate(
            tile: SPTile.unknown, tenpai: [], win: [], ev: [],
            required: required, shantenDown: false)]
    }

    private func makeCandidate(
        tile: Int, tenpai: [Float], win: [Float], ev: [Float],
        required: [(tile: Int, count: Int)], shantenDown: Bool
    ) -> SPCandidate {
        SPCandidate(
            tile: tile,
            tenpaiProbs: tenpai.map { min(max($0, 0), 1) },
            winProbs: win.map { min(max($0, 0), 1) },
            expValues: ev.map { max($0, 0) },
            requiredTiles: required,
            numRequiredTiles: required.reduce(0) { $0 + $1.count },
            shantenDown: shantenDown)
    }

    // MARK: 遞迴：摸牌

    private mutating func draw(shanten: Int) -> Values {
        if let cached = drawCache[shanten][state] { return cached }
        let values = drawSlow(shanten: shanten)
        drawCache[shanten][state] = values
        return values
    }

    private mutating func drawSlow(shanten: Int) -> Values {
        var result = zeroValues
        let drawTiles = state.drawTiles(shanten: shanten, tehaiLenDiv3: sup.tehaiLenDiv3)
        let sumRequired = drawTiles.filter { $0.shantenDiff == -1 }.reduce(0) { $0 + $1.count }
        let notTsumoProbs = notTsumoProbTable[min(sumRequired, notTsumoProbTable.count - 1)]

        for (tile, count, shantenDiff) in drawTiles where shantenDiff == -1 {
            state.deal(tile)

            var nextValues: Values?
            var scores: [Float]?
            if shanten > 0 {
                nextValues = discard(shanten: shanten - 1)
            } else if let s = sup.score(state: state, winTile: tile) {
                scores = s
            } else {
                state.undoDeal(tile)
                continue    // 無役，這張牌不算和了
            }
            state.undoDeal(tile)

            let tsumoProbs = tsumoProbTable[min(count, 4) - 1]

            for i in 0..<maxTsumo {
                let m = notTsumoProbs[i]
                // notTsumoProbs 單調遞減，一旦為 0 後面全是 0
                if m == 0 { break }

                for j in i..<maxTsumo {
                    let n = notTsumoProbs[j]
                    if n == 0 { break }
                    // 目前在第 i 巡的前提下，第 j 巡摸到有效牌的機率
                    let prob = tsumoProbs[j] * n / m

                    if let scores {
                        let assumeRiichi = sup.isMenzen && sup.preferRiichi
                        // 第 0 巡聽牌 → 雙立直；聽牌後立刻和 → 一發；最後一巡和 → 海底
                        let winDoubleRiichi = assumeRiichi && sup.calcDoubleRiichi && i == 0
                        let winIppatsu = assumeRiichi && j == i
                        let winHaitei = sup.calcHaitei && j == maxTsumo - 1
                        let hanPlus = (winDoubleRiichi ? 1 : 0)
                            + (winIppatsu ? 1 : 0) + (winHaitei ? 1 : 0)

                        result.winProbs[i] += prob
                        result.expValues[i] += prob * scores[hanPlus]
                    } else if let nextValues {
                        if shanten == 1 {
                            // 一向聽：摸到就聽牌
                            result.tenpaiProbs[i] += prob
                        }
                        if j < maxTsumo - 1 {
                            if shanten > 1 {
                                result.tenpaiProbs[i] += prob * nextValues.tenpaiProbs[j + 1]
                            }
                            result.winProbs[i] += prob * nextValues.winProbs[j + 1]
                            result.expValues[i] += prob * nextValues.expValues[j + 1]
                        }
                    }
                }
            }
        }

        return result
    }

    // MARK: 遞迴：打牌

    private mutating func discard(shanten: Int) -> Values {
        if let cached = discardCache[shanten][state] { return cached }
        let values = discardSlow(shanten: shanten)
        discardCache[shanten][state] = values
        return values
    }

    /// 假設之後每一巡都會選期望值最大的那張打
    private mutating func discardSlow(shanten: Int) -> Values {
        var best = Values(
            tenpaiProbs: [Float](repeating: -.greatestFiniteMagnitude, count: maxTsumo),
            winProbs: [Float](repeating: -.greatestFiniteMagnitude, count: maxTsumo),
            expValues: [Float](repeating: -.greatestFiniteMagnitude, count: maxTsumo))
        var bestTiles = [Int](repeating: SPTile.unknown, count: maxTsumo)
        var bestKeys = [Int](repeating: Int.min, count: maxTsumo)

        for (tile, shantenDiff) in state.discardTiles(shanten: shanten, tehaiLenDiv3: sup.tehaiLenDiv3)
        where shantenDiff == 0 {
            state.discard(tile)
            let values = draw(shanten: shanten)
            state.undoDiscard(tile)

            for i in 0..<maxTsumo {
                // 期望值取整數比較：小數點以下的差異視為相同
                let key = Int(values.expValues[i])
                if key > bestKeys[i]
                    || (key == bestKeys[i] && SPTile.discardPriorityGreater(tile, bestTiles[i])) {
                    best.tenpaiProbs[i] = values.tenpaiProbs[i]
                    best.winProbs[i] = values.winProbs[i]
                    best.expValues[i] = values.expValues[i]
                    bestKeys[i] = key
                    bestTiles[i] = tile
                }
            }
        }

        return best
    }

    // MARK: 排序

    enum SortColumn { case ev, winProb, tenpaiProb, notShantenDown, numRequiredTiles, discardPriority }

    /// `lhs` 是否排在 `rhs` 前面（由好到壞）
    private func compare(_ lhs: SPCandidate, _ rhs: SPCandidate, by column: SortColumn) -> Bool {
        if lhs.tile == rhs.tile { return false }
        switch column {
        case .ev:
            let l = lhs.expValues.first ?? 0, r = rhs.expValues.first ?? 0
            if l != r { return l > r }
            return compare(lhs, rhs, by: .winProb)
        case .winProb:
            let l = lhs.winProbs.first ?? 0, r = rhs.winProbs.first ?? 0
            if l != r { return l > r }
            return compare(lhs, rhs, by: .tenpaiProb)
        case .tenpaiProb:
            let l = lhs.tenpaiProbs.first ?? 0, r = rhs.tenpaiProbs.first ?? 0
            if l != r { return l > r }
            return compare(lhs, rhs, by: .notShantenDown)
        case .notShantenDown:
            if lhs.shantenDown != rhs.shantenDown { return !lhs.shantenDown }
            return compare(lhs, rhs, by: .numRequiredTiles)
        case .numRequiredTiles:
            if lhs.numRequiredTiles != rhs.numRequiredTiles {
                return lhs.numRequiredTiles > rhs.numRequiredTiles
            }
            return compare(lhs, rhs, by: .discardPriority)
        case .discardPriority:
            return SPTile.discardPriorityGreater(lhs.tile, rhs.tile)
        }
    }
}
