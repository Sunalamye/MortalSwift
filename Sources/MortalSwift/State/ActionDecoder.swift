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
            let consumed = getPonConsumed(tile: targetTile, state: state)

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
                let consumed = getDaiminkanConsumed(tile: targetTile, state: state)

                return .daiminkan(DaiminkanAction(
                    actor: actor,
                    target: targetActor,
                    pai: targetTile,
                    consumed: consumed
                ))
            } else if state.lastCans.canAnkan && !state.ankanCandidates.isEmpty {
                // 暗槓
                let tile = state.ankanCandidates[0]
                let consumed = getAnkanConsumed(tile: tile, state: state)

                return .ankan(AnkanAction(actor: actor, consumed: consumed))
            } else if state.lastCans.canKakan && !state.kakanCandidates.isEmpty {
                // 加槓
                let tile = state.kakanCandidates[0]
                let consumed = getKakanConsumed(tile: tile, state: state)

                return .kakan(KakanAction(actor: actor, pai: tile, consumed: consumed))
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

        switch actionIdx {
        case 4 where state.akasInHand[0] && state.tehai[4] == 1:
            return .man(5, red: true)
        case 13 where state.akasInHand[1] && state.tehai[13] == 1:
            return .pin(5, red: true)
        case 22 where state.akasInHand[2] && state.tehai[22] == 1:
            return .sou(5, red: true)
        default:
            return baseTile
        }
    }

    /// 紅五格的取牌：手上真的有那張紅五才算數
    private static func akaTile(normal: Int, slot: Int, aka: Tile, state: PlayerState) -> Tile? {
        guard state.akasInHand[slot], state.tehai[normal] > 0 else { return nil }
        return aka
    }

    /// 解析吃牌的具體牌張 (考慮紅寶牌)
    private static func resolveConsumedTiles(_ consumed: [Tile], state: PlayerState) -> [Tile] {
        var result: [Tile] = []

        for tile in consumed {
            let idx = tile.deaka.index

            // 檢查是否應該使用紅寶牌
            var usedRed = false
            if idx == 4 && state.akasInHand[0] {
                // 5萬
                result.append(.man(5, red: true))
                usedRed = true
            } else if idx == 13 && state.akasInHand[1] {
                // 5筒
                result.append(.pin(5, red: true))
                usedRed = true
            } else if idx == 22 && state.akasInHand[2] {
                // 5索
                result.append(.sou(5, red: true))
                usedRed = true
            }

            if !usedRed {
                result.append(tile)
            }
        }

        return result
    }

    /// 取得碰牌的兩張牌
    private static func getPonConsumed(tile: Tile, state: PlayerState) -> [Tile] {
        let idx = tile.deaka.index
        var consumed: [Tile] = []

        // 檢查紅寶牌
        var hasAka = false
        switch idx {
        case 4: hasAka = state.akasInHand[0]
        case 13: hasAka = state.akasInHand[1]
        case 22: hasAka = state.akasInHand[2]
        default: break
        }

        if hasAka && state.tehai[idx] >= 2 {
            // 用一張紅五和一張普通五
            switch idx {
            case 4:
                consumed = [.man(5, red: true), .man(5)]
            case 13:
                consumed = [.pin(5, red: true), .pin(5)]
            case 22:
                consumed = [.sou(5, red: true), .sou(5)]
            default:
                break
            }
        } else {
            // 用兩張普通牌
            let baseTile = Tile.fromIndex(idx) ?? tile.deaka
            consumed = [baseTile, baseTile]
        }

        return consumed
    }

    /// 取得大明槓的三張牌
    private static func getDaiminkanConsumed(tile: Tile, state: PlayerState) -> [Tile] {
        let idx = tile.deaka.index
        var consumed: [Tile] = []

        let baseTile = Tile.fromIndex(idx) ?? tile.deaka

        // 檢查紅寶牌
        var hasAka = false
        switch idx {
        case 4: hasAka = state.akasInHand[0]
        case 13: hasAka = state.akasInHand[1]
        case 22: hasAka = state.akasInHand[2]
        default: break
        }

        if hasAka {
            switch idx {
            case 4:
                consumed = [.man(5, red: true), .man(5), .man(5)]
            case 13:
                consumed = [.pin(5, red: true), .pin(5), .pin(5)]
            case 22:
                consumed = [.sou(5, red: true), .sou(5), .sou(5)]
            default:
                break
            }
        } else {
            consumed = [baseTile, baseTile, baseTile]
        }

        return consumed
    }

    /// 取得暗槓的四張牌
    private static func getAnkanConsumed(tile: Tile, state: PlayerState) -> [Tile] {
        let idx = tile.deaka.index
        var consumed: [Tile] = []

        let baseTile = Tile.fromIndex(idx) ?? tile.deaka

        // 檢查紅寶牌
        var hasAka = false
        switch idx {
        case 4: hasAka = state.akasInHand[0]
        case 13: hasAka = state.akasInHand[1]
        case 22: hasAka = state.akasInHand[2]
        default: break
        }

        if hasAka {
            switch idx {
            case 4:
                consumed = [.man(5, red: true), .man(5), .man(5), .man(5)]
            case 13:
                consumed = [.pin(5, red: true), .pin(5), .pin(5), .pin(5)]
            case 22:
                consumed = [.sou(5, red: true), .sou(5), .sou(5), .sou(5)]
            default:
                break
            }
        } else {
            consumed = [baseTile, baseTile, baseTile, baseTile]
        }

        return consumed
    }

    /// 取得加槓的原碰牌
    private static func getKakanConsumed(tile: Tile, state: PlayerState) -> [Tile] {
        // 加槓需要返回原來碰的三張牌
        let idx = tile.deaka.index
        let baseTile = Tile.fromIndex(idx) ?? tile.deaka

        // 簡化處理：返回三張一樣的牌
        return [baseTile, baseTile, baseTile]
    }
}
