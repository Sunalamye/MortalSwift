//
//  ActionDecoder.swift
//  MortalSwift
//
//  動作解碼器 - 將模型輸出轉換為 MJAI 動作
//

import Foundation

/// 動作解碼器
public struct ActionDecoder {

    /// 將動作索引轉換為 MJAI 動作
    /// - Parameters:
    ///   - actionIdx: 動作索引 (0-45)
    ///   - state: 玩家狀態
    /// - Returns: MJAI 動作
    public static func decode(actionIdx: Int, state: PlayerState) -> MJAIAction? {
        let actor = state.playerId

        // 打牌 (0-36)
        //
        // 34-36 是「打出紅五萬／紅五筒／紅五索」，不是保留格。
        // libriichi 的 46 格動作空間把紅五與普通五當成兩個不同的打牌選項
        // （見 `PlayerState.discardCandidatesAka()`）：手上那張五只有紅五時，
        // mask[4]=0、mask[34]=1。少了 34-36 的分支，就會在「唯一合法動作是
        // 打紅五」的局面回 nil，呼叫端當成不需要動作，bot 靜默停手等到逾時。
        if actionIdx >= PlayerState.ActionIndex.discardStart
            && actionIdx <= PlayerState.ActionIndex.discardAkaEnd {
            guard let tile = discardTile(actionIdx: actionIdx, state: state) else { return nil }

            // 摸切 = 打出去的正是剛摸進來的**那一張**。
            // 必須連紅寶牌一起比：摸紅五卻手切普通五（或反過來）都不是摸切。
            // 只比 deaka 索引會把這兩種情形標成摸切，下游照摸切的位置抽牌，
            // 實際打出去的就不是這張牌。
            let tsumogiri = state.lastSelfTsumo == tile

            return .dahai(DahaiAction(actor: actor, pai: tile, tsumogiri: tsumogiri))
        }

        // 立直 (37)
        if actionIdx == PlayerState.ActionIndex.riichi {
            return .reach(ReachAction(actor: actor))
        }

        // 吃 (38-40)
        if actionIdx >= PlayerState.ActionIndex.chiLow && actionIdx <= PlayerState.ActionIndex.chiHigh {
            guard let targetTile = state.lastKawaTile else { return nil }
            let targetActor = state.toAbsolute(state.lastCans.targetActor)

            // 找到對應的吃組合
            let chiType: ChiType
            switch actionIdx {
            case PlayerState.ActionIndex.chiLow: chiType = .low
            case PlayerState.ActionIndex.chiMid: chiType = .mid
            case PlayerState.ActionIndex.chiHigh: chiType = .high
            default: return nil
            }

            // 從候選中找到匹配的組合
            for consumed in state.chiCandidates {
                if ChiType.from(consumed: consumed, target: targetTile) == chiType {
                    // 處理紅寶牌
                    let finalConsumed = resolveConsumedTiles(consumed, state: state)
                    return .chi(ChiAction(
                        actor: actor,
                        target: targetActor,
                        pai: targetTile,
                        consumed: finalConsumed
                    ))
                }
            }
            return nil
        }

        // 碰 (41)
        if actionIdx == PlayerState.ActionIndex.pon {
            guard let targetTile = state.lastKawaTile else { return nil }
            let targetActor = state.toAbsolute(state.lastCans.targetActor)

            // 取得碰的兩張牌
            let consumed = consumedTiles(tile: targetTile, count: 2, state: state)

            return .pon(PonAction(
                actor: actor,
                target: targetActor,
                pai: targetTile,
                consumed: consumed
            ))
        }

        // 槓 (42)
        if actionIdx == PlayerState.ActionIndex.kan {
            // 根據狀態決定是哪種槓
            if state.lastCans.canDaiminkan {
                // 大明槓
                guard let targetTile = state.lastKawaTile else { return nil }
                let targetActor = state.toAbsolute(state.lastCans.targetActor)
                let consumed = consumedTiles(tile: targetTile, count: 3, state: state)

                return .daiminkan(DaiminkanAction(
                    actor: actor,
                    target: targetActor,
                    pai: targetTile,
                    consumed: consumed
                ))
            } else if state.lastCans.canAnkan && !state.ankanCandidates.isEmpty {
                // 暗槓
                let tile = state.ankanCandidates[0]
                let consumed = consumedTiles(tile: tile, count: 4, state: state)

                return .ankan(AnkanAction(actor: actor, consumed: consumed))
            } else if state.lastCans.canKakan && !state.kakanCandidates.isEmpty {
                // 加槓
                let tile = state.kakanCandidates[0]
                let consumed = getKakanConsumed(tile: tile, state: state)

                return .kakan(KakanAction(actor: actor,
                                          pai: kakanPai(candidate: tile, state: state),
                                          consumed: consumed))
            }
            return nil
        }

        // 和 (43)
        if actionIdx == PlayerState.ActionIndex.hora {
            if state.lastCans.canTsumoAgari {
                // 自摸
                return .hora(HoraAction(
                    actor: actor,
                    target: actor,
                    pai: state.lastSelfTsumo
                ))
            } else if state.lastCans.canRonAgari {
                // 榮和
                let targetActor = state.toAbsolute(state.lastCans.targetActor)
                return .hora(HoraAction(
                    actor: actor,
                    target: targetActor,
                    pai: state.lastKawaTile
                ))
            }
            return nil
        }

        // 流局 (44)
        if actionIdx == PlayerState.ActionIndex.ryukyoku {
            return .ryukyoku(RyukyokuAction(actor: actor))
        }

        // 跳過 (45)
        if actionIdx == PlayerState.ActionIndex.pass {
            return .pass(PassAction(actor: actor))
        }

        return nil
    }

    // MARK: - Helper Methods

    /// 打牌索引 → 實際打出的那一張牌
    ///
    /// - 0-33：普通牌；索引 4/13/22（五萬/五筒/五索）在「手上那張五只有紅五」時
    ///   回紅五。這格的 mask 在那種情況下本來就是 0，之所以還是給牌而不是回 nil，
    ///   是因為呼叫端若忽略 mask 硬選了這格，打出紅五仍是合法且唯一可能的解讀，
    ///   比回 nil 讓 bot 停手好。
    /// - 34-36：紅五萬／紅五筒／紅五索；手上沒有對應紅五就是無效索引。
    private static func discardTile(actionIdx: Int, state: PlayerState) -> Tile? {
        switch actionIdx {
        case PlayerState.ActionIndex.akaDiscardMan5:
            return akaTile(normal: 4, slot: 0, aka: .man(5, red: true), state: state)
        case PlayerState.ActionIndex.akaDiscardPin5:
            return akaTile(normal: 13, slot: 1, aka: .pin(5, red: true), state: state)
        case PlayerState.ActionIndex.akaDiscardSou5:
            return akaTile(normal: 22, slot: 2, aka: .sou(5, red: true), state: state)
        default:
            break
        }

        // 確認手中有這張牌
        guard let baseTile = Tile.fromIndex(actionIdx), state.tehai[actionIdx] > 0 else {
            return nil
        }

        if let aka = akaTriples.first(where: { $0.index == actionIdx }),
           state.akasInHand[aka.slot], state.tehai[actionIdx] == 1 {
            return aka.tile
        }
        return baseTile
    }

    /// 紅五格的取牌：手上真的有那張紅五才算數
    private static func akaTile(normal: Int, slot: Int, aka: Tile, state: PlayerState) -> Tile? {
        guard state.akasInHand[slot], state.tehai[normal] > 0 else { return nil }
        return aka
    }

    /// 紅五三元組：(普通索引, `akasInHand` slot, 紅五牌)
    private static let akaTriples: [(index: Int, slot: Int, tile: Tile)] = [
        (4, 0, .man(5, red: true)),
        (13, 1, .pin(5, red: true)),
        (22, 2, .sou(5, red: true)),
    ]

    /// 解析吃牌的具體牌張（手上有紅五就用紅五）
    private static func resolveConsumedTiles(_ consumed: [Tile], state: PlayerState) -> [Tile] {
        consumed.map { tile in
            guard let aka = akaTriples.first(where: { $0.index == tile.deaka.index }),
                  state.akasInHand[aka.slot] else { return tile }
            return aka.tile
        }
    }

    /// 碰（2 張）／大明槓（3 張）／暗槓（4 張）從手上出的牌：手上有紅五就用掉它
    private static func consumedTiles(tile: Tile, count: Int, state: PlayerState) -> [Tile] {
        let idx = tile.deaka.index
        var tiles = [Tile](repeating: Tile.fromIndex(idx) ?? tile.deaka, count: count)
        if let aka = akaTriples.first(where: { $0.index == idx }),
           state.akasInHand[aka.slot], state.tehai[idx] >= count {
            tiles[0] = aka.tile
        }
        return tiles
    }

    /// 加槓的 consumed 是**原碰那三張**——含不含紅五是碰當下的事實，
    /// 記在 `fuuroOverview`，不能拿現在的手牌重算
    private static func getKakanConsumed(tile: Tile, state: PlayerState) -> [Tile] {
        let idx = tile.deaka.index
        if let meld = state.fuuroOverview[0].first(where: { meld in
            meld.count == 3 && meld.allSatisfy { $0.deaka.index == idx }
        }) {
            return meld
        }
        return [Tile](repeating: Tile.fromIndex(idx) ?? tile.deaka, count: 3)
    }

    /// 加槓宣告的牌＝手上剩的那一張：紅五旗標還亮著它就是紅五。
    /// 宣告成普通五會讓 `handleKakan` 移錯牌、`akasInHand` 殘留
    private static func kakanPai(candidate: Tile, state: PlayerState) -> Tile {
        guard let aka = akaTriples.first(where: { $0.index == candidate.deaka.index }),
              state.akasInHand[aka.slot] else { return candidate }
        return aka.tile
    }
}
