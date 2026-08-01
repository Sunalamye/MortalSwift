//
//  SinglePlayerTables.swift
//  MortalSwift
//
//  把 PlayerState 接到單人期望值推演
//
//  對應 libriichi `PlayerState::single_player_tables`。
//

import Foundation

extension PlayerState {

    /// 真正的向聽數
    ///
    /// `shanten` 這個欄位存的是 3n+1 手牌的值（見 StateUpdate 的說明），
    /// 在 3n+2 的時點要另外推算才知道現在實際是幾向聽。
    public func realTimeShanten() -> Int {
        if !lastCans.canDiscard {
            // 3n+1，`shanten` 就是準的
            return shanten
        }

        if shanten > 0 {
            // 3n+2 且未聽牌：有能推進的打牌就是 shanten - 1
            return hasNextShantenDiscard ? shanten - 1 : shanten
        }

        if let tsumo = lastSelfTsumo {
            // 3n+2 且摸牌後聽牌
            return waits[tsumo.deaka.index] ? -1 : 0
        }

        // 3n+2 且是吃碰之後。`shanten` 被 clamp 過，實際可能是 0 或 -1，要重算
        return ShantenCalculator.calcAll(tehai: tehai, lenDiv3: tehaiLenDiv3)
    }

    /// 各家持有的寶牌數（含紅五）
    ///
    /// libriichi 是逐張增量維護的；這裡從既有狀態推導，結果相同但不必在每個
    /// 事件處理器裡都記得加減。
    public func computeDorasOwned() -> [Int] {
        var owned = [Int](repeating: 0, count: 4)

        for tid in 0..<34 {
            owned[0] += tehai[tid] * doraFactor[tid]
        }
        owned[0] += akasInHand.filter { $0 }.count

        for seat in 0..<4 {
            for meld in fuuroOverview[seat] {
                for tile in meld {
                    let tid = tile.deaka.index
                    if tid >= 0 { owned[seat] += doraFactor[tid] }
                    if tile.isRed { owned[seat] += 1 }
                }
            }
            for ankan in ankanOverview[seat] {
                if let tile = ankan.first {
                    let tid = tile.deaka.index
                    if tid >= 0 { owned[seat] += 4 * doraFactor[tid] }
                }
            }
        }

        return owned
    }

    /// 單人期望值推演：對每一張可打的牌，算出往後每一巡的聽牌率／和牌率／期望值
    ///
    /// 回傳 nil 代表算不了（牌不夠、已經是和了形等），此時 observation 的
    /// 對應區段留 0——與 libriichi 走 `Err` 分支的行為一致。
    public func singlePlayerTables() -> [SPCandidate]? {
        guard tilesLeft >= 4 else { return nil }

        let curShanten = realTimeShanten()
        guard curShanten >= 0 else { return nil }

        var canDiscard = lastCans.canDiscard
        let tsumosLeft: Int
        let calcHaitei: Bool
        if canDiscard {
            tsumosLeft = tilesLeft / 4
            calcHaitei = tilesLeft % 4 == 0
        } else {
            // 還沒輪到自己摸：先算到下一次自己摸牌時還剩幾張
            let target = toRelative(lastCans.targetActor)
            let atNextTsumo = max(0, tilesLeft - (4 - target))
            tsumosLeft = atNextTsumo / 4
            calcHaitei = atNextTsumo % 4 == 0
        }
        guard tsumosLeft >= 1 else { return nil }

        // 副露（含暗槓）裡的寶牌數 = 自己全部的寶牌 - 手牌裡的 - 紅五
        let numDorasInFuuro: Int
        if isMenzen && ankanOverview[0].isEmpty {
            numDorasInFuuro = 0
        } else {
            let inTehai = doraIndicators.reduce(0) { $0 + tehai[$1.next.deaka.index] }
            let numAkas = akasInHand.filter { $0 }.count
            numDorasInFuuro = max(0, computeDorasOwned()[0] - inTehai - numAkas)
        }

        var workTehai = tehai
        var workAkas = akasInHand

        // 立直成立後摸到不能和的牌：視為那張牌已經打掉了
        let isDiscardAfterRiichi = canDiscard && riichiAccepted[0]
        if isDiscardAfterRiichi, let lastTsumo = lastSelfTsumo {
            workTehai[lastTsumo.deaka.index] -= 1
            switch lastTsumo.indexWithAka {
            case 34: workAkas[0] = false
            case 35: workAkas[1] = false
            case 36: workAkas[2] = false
            default: break
            }
            canDiscard = false
        }

        let calculator = SPCalculator(
            tehaiLenDiv3: tehaiLenDiv3,
            isMenzen: isMenzen,
            chis: chis, pons: pons, minkans: minkans, ankans: ankans,
            bakaze: bakaze.index, jikaze: jikaze.index,
            numDorasInFuuro: numDorasInFuuro,
            doraIndicators: doraIndicators.map { $0.deaka.index },
            calcDoubleRiichi: canDiscard && canWRiichi,
            calcHaitei: calcHaitei,
            preferRiichi: scores[0] >= 1000)

        let state = SPState(
            tehai: workTehai, akasInHand: workAkas,
            tilesSeen: tilesSeen, akasSeen: akasSeen)

        guard var table = calculator.calc(
            state: state, canDiscard: canDiscard,
            tsumosLeft: tsumosLeft, curShanten: curShanten
        ) else { return nil }

        // 立直後那個「假裝打掉」的候選，實際上打的就是剛摸到那張
        if isDiscardAfterRiichi, let lastTsumo = lastSelfTsumo, !table.isEmpty {
            table[0] = SPCandidate(
                tile: lastTsumo.indexWithAka,
                tenpaiProbs: table[0].tenpaiProbs,
                winProbs: table[0].winProbs,
                expValues: table[0].expValues,
                requiredTiles: table[0].requiredTiles,
                numRequiredTiles: table[0].numRequiredTiles,
                shantenDown: table[0].shantenDown)
        }

        return table
    }
}
