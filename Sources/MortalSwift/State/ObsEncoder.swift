//
//  ObsEncoder.swift
//  MortalSwift
//
//  觀測編碼器 - 將遊戲狀態轉換為模型輸入張量
//
//  Observation shape: (1012, 34) for version 4
//  Action mask shape: (46,)
//

import Foundation

/// 觀測編碼器
public struct ObsEncoder {

    // MARK: - Constants

    public static let obsChannels = 1012
    public static let obsWidth = 34
    public static let actionSpace = 46

    // MARK: - Encoding

    /// 編碼遊戲狀態為觀測張量
    /// - Parameter state: 玩家狀態
    /// - Returns: (觀測張量, 動作遮罩)
    public static func encode(state: PlayerState) -> (obs: [Float], mask: [UInt8]) {
        var obs = [Float](repeating: 0, count: obsChannels * obsWidth)
        var channel = 0

        // 1. 手牌組成 (7 channels)
        channel = encodeTehai(state: state, obs: &obs, startChannel: channel)

        // 2. 分數 (10 channels)
        channel = encodeScores(state: state, obs: &obs, startChannel: channel)

        // 3. 排名 (4 channels)
        channel = encodeRank(state: state, obs: &obs, startChannel: channel)

        // 4. 局數 (4 channels)
        channel = encodeKyoku(state: state, obs: &obs, startChannel: channel)

        // 5. 本場和立直棒 (variable channels)
        channel = encodeCounters(state: state, obs: &obs, startChannel: channel)

        // 6. 風 (4 channels)
        channel = encodeWinds(state: state, obs: &obs, startChannel: channel)

        // 7. 寶牌 (34 channels)
        channel = encodeDora(state: state, obs: &obs, startChannel: channel)

        // 8. 自家河 (variable channels)
        channel = encodeSelfKawa(state: state, obs: &obs, startChannel: channel)

        // 9. 其他家河 (3 * variable channels)
        for i in 1..<4 {
            channel = encodeOpponentKawa(state: state, playerIdx: i, obs: &obs, startChannel: channel)
        }

        // 10. 副露資訊
        channel = encodeFuuro(state: state, obs: &obs, startChannel: channel)

        // 11. 其他資訊
        channel = encodeOtherInfo(state: state, obs: &obs, startChannel: channel)

        // 確保填滿到 1012 channels
        while channel < obsChannels {
            channel += 1
        }

        // 編碼動作遮罩
        let mask = encodeMask(state: state)

        return (obs, mask)
    }

    // MARK: - Channel Encoders

    /// 編碼手牌 (7 channels)
    /// - 4 channels: 手牌數量 (0-4)
    /// - 3 channels: 紅寶牌
    private static func encodeTehai(state: PlayerState, obs: inout [Float], startChannel: Int) -> Int {
        var ch = startChannel

        // 手牌數量
        for count in 1...4 {
            for idx in 0..<34 {
                if state.tehai[idx] >= count {
                    obs[ch * obsWidth + idx] = 1.0
                }
            }
            ch += 1
        }

        // 紅寶牌
        // 5m (index 4)
        if state.akasInHand[0] {
            obs[ch * obsWidth + 4] = 1.0
        }
        ch += 1

        // 5p (index 13)
        if state.akasInHand[1] {
            obs[ch * obsWidth + 13] = 1.0
        }
        ch += 1

        // 5s (index 22)
        if state.akasInHand[2] {
            obs[ch * obsWidth + 22] = 1.0
        }
        ch += 1

        return ch
    }

    /// 編碼分數 (8 channels：每位玩家 100k 正規化 + 30k 正規化)
    private static func encodeScores(state: PlayerState, obs: inout [Float], startChannel: Int) -> Int {
        var ch = startChannel

        for i in 0..<4 {
            let score = Float(state.scores[i])

            // 正規化分數 (0-100k)
            let normalizedScore = min(1.0, max(0.0, score / 100000.0))
            for idx in 0..<34 {
                obs[ch * obsWidth + idx] = normalizedScore
            }
            ch += 1

            // 細緻分數 (0-30k 範圍)
            let fineScore = min(1.0, max(0.0, score / 30000.0))
            for idx in 0..<34 {
                obs[ch * obsWidth + idx] = fineScore
            }
            ch += 1
        }

        // 註：這裡原本還多編了 3 個「相對分數差」channel，但 libriichi 沒有這一段
        // （見 docs/reference/libriichi_obs_repr.rs 的 encode_obs：v4 每位玩家只有
        // 100k 正規化與 30k 正規化共 2 個 channel）。多出來的 3 格會讓其後所有
        // channel 整體位移，模型收到的每一格語意都跟訓練時不同。

        return ch
    }

    /// 編碼排名 (4 channels)
    private static func encodeRank(state: PlayerState, obs: inout [Float], startChannel: Int) -> Int {
        var ch = startChannel

        for rank in 1...4 {
            if state.rank == rank {
                for idx in 0..<34 {
                    obs[ch * obsWidth + idx] = 1.0
                }
            }
            ch += 1
        }

        return ch
    }

    /// 編碼局數 (4 channels)
    private static func encodeKyoku(state: PlayerState, obs: inout [Float], startChannel: Int) -> Int {
        var ch = startChannel

        // libriichi 的 state.kyoku 是 0-based（東1 = 0），
        // 而這裡的 state.kyoku 直接取自 MJAI 的 1-based 值，編碼時要先轉換。
        let kyoku0 = max(0, state.kyoku - 1)
        for kyoku in 0..<4 {
            if kyoku0 == kyoku {
                for idx in 0..<34 {
                    obs[ch * obsWidth + idx] = 1.0
                }
            }
            ch += 1
        }

        return ch
    }

    /// 編碼本場和立直棒 (variable channels)
    private static func encodeCounters(state: PlayerState, obs: inout [Float], startChannel: Int) -> Int {
        var ch = startChannel

        // libriichi v4 的 IntegerEncoder 只做 rescale：值 = min(n, cap) / cap，佔 1 個 channel。
        // （`rbf_intervals` 只在 v2/v3 生效，v4 分支完全忽略它——
        //   見 docs/reference/libriichi_obs_repr.rs 的 IntegerEncoder::encode）
        // 本場與立直棒的 cap 都是 10。
        let cap: Float = 10.0

        let honba = min(Float(state.honba), cap) / cap
        for idx in 0..<obsWidth { obs[ch * obsWidth + idx] = honba }
        ch += 1

        let kyotaku = min(Float(state.kyotaku), cap) / cap
        for idx in 0..<obsWidth { obs[ch * obsWidth + idx] = kyotaku }
        ch += 1

        return ch
    }

    /// 編碼風（2 channels：場風、自風各 1）
    ///
    /// libriichi 用的是 `assign(idx, tile_index, 1.0)`——只在該風對應的**牌索引**上打 1，
    /// 不是整列廣播、也不是 4 格 one-hot。原本寫成 4+4 格 one-hot 會多佔 6 個 channel，
    /// 讓其後所有 channel 位移。
    private static func encodeWinds(state: PlayerState, obs: inout [Float], startChannel: Int) -> Int {
        var ch = startChannel

        obs[ch * obsWidth + state.bakaze.index] = 1.0
        ch += 1

        obs[ch * obsWidth + state.jikaze.index] = 1.0
        ch += 1

        // 場風與局數的合成編碼：n = min(場風 - 東, 1) * 4 + 局數，cap = 7，只做 rescale
        let bakazeOffset = min(max(0, state.bakaze.index - Tile.east.index), 1)
        let n = Float(min(bakazeOffset * 4 + max(0, state.kyoku - 1), 7))
        let v = n / 7.0
        for idx in 0..<obsWidth { obs[ch * obsWidth + idx] = v }
        ch += 1

        return ch
    }

    /// 編碼寶牌 (34 channels)
    private static func encodeDora(state: PlayerState, obs: inout [Float], startChannel: Int) -> Int {
        var ch = startChannel

        // 寶牌指示牌
        for indicator in state.doraIndicators {
            let idx = indicator.deaka.index
            if idx >= 0 && idx < 34 {
                obs[ch * obsWidth + idx] = 1.0
            }
        }
        ch += 1

        // 寶牌係數
        for idx in 0..<34 {
            obs[ch * obsWidth + idx] = Float(state.doraFactor[idx])
        }
        ch += 1

        return ch
    }

    /// 編碼自家河 (variable channels)
    private static func encodeSelfKawa(state: PlayerState, obs: inout [Float], startChannel: Int) -> Int {
        var ch = startChannel
        let kawa = state.kawaOverview[0]

        // 最近 6 張打牌 (每張 4 channels)
        let recentCount = min(6, kawa.count)
        for i in 0..<6 {
            if i < recentCount {
                let tile = kawa[kawa.count - 1 - i]
                let idx = tile.deaka.index
                if idx >= 0 && idx < 34 {
                    obs[ch * obsWidth + idx] = 1.0
                }

                // 是否手切
                if i < state.kawa[0].count {
                    let kawaItem = state.kawa[0][state.kawa[0].count - 1 - i]
                    if kawaItem.sutehai.isTedashi {
                        obs[(ch + 1) * obsWidth + idx] = 1.0
                    }
                    // 是否立直宣言牌
                    if kawaItem.sutehai.isRiichi {
                        obs[(ch + 2) * obsWidth + idx] = 1.0
                    }
                    // 時間衰減
                    let decay = 1.0 - Float(i) / 6.0
                    obs[(ch + 3) * obsWidth + idx] = decay
                }
            }
            ch += 4
        }

        // 所有打牌 (18 channels)
        for i in 0..<min(18, kawa.count) {
            let tile = kawa[i]
            let idx = tile.deaka.index
            if idx >= 0 && idx < 34 {
                obs[ch * obsWidth + idx] = 1.0
            }
            ch += 1
        }
        ch += max(0, 18 - kawa.count)

        return ch
    }

    /// 編碼對手河 (variable channels per opponent)
    private static func encodeOpponentKawa(state: PlayerState, playerIdx: Int, obs: inout [Float], startChannel: Int) -> Int {
        var ch = startChannel
        let kawa = state.kawaOverview[playerIdx]

        // 最近 6 張打牌 (每張 4 channels)
        let recentCount = min(6, kawa.count)
        for i in 0..<6 {
            if i < recentCount {
                let tile = kawa[kawa.count - 1 - i]
                let idx = tile.deaka.index
                if idx >= 0 && idx < 34 {
                    obs[ch * obsWidth + idx] = 1.0

                    // 是否手切
                    if i < state.kawa[playerIdx].count {
                        let kawaItem = state.kawa[playerIdx][state.kawa[playerIdx].count - 1 - i]
                        if kawaItem.sutehai.isTedashi {
                            obs[(ch + 1) * obsWidth + idx] = 1.0
                        }
                        // 是否立直宣言牌
                        if kawaItem.sutehai.isRiichi {
                            obs[(ch + 2) * obsWidth + idx] = 1.0
                        }
                    }

                    // 時間衰減
                    let decay = 1.0 - Float(i) / 6.0
                    obs[(ch + 3) * obsWidth + idx] = decay
                }
            }
            ch += 4
        }

        // 所有打牌 (18 channels)
        for i in 0..<min(18, kawa.count) {
            let tile = kawa[i]
            let idx = tile.deaka.index
            if idx >= 0 && idx < 34 {
                obs[ch * obsWidth + idx] = 1.0
            }
            ch += 1
        }
        ch += max(0, 18 - kawa.count)

        // 立直狀態
        if state.riichiAccepted[playerIdx] {
            for idx in 0..<34 {
                obs[ch * obsWidth + idx] = 1.0
            }
        }
        ch += 1

        return ch
    }

    /// 編碼副露資訊
    private static func encodeFuuro(state: PlayerState, obs: inout [Float], startChannel: Int) -> Int {
        var ch = startChannel

        // 各家副露
        for playerIdx in 0..<4 {
            // 副露牌
            for meld in state.fuuroOverview[playerIdx] {
                for tile in meld {
                    let idx = tile.deaka.index
                    if idx >= 0 && idx < 34 {
                        obs[ch * obsWidth + idx] = 1.0
                    }
                }
            }
            ch += 1

            // 暗槓
            for ankan in state.ankanOverview[playerIdx] {
                if let tile = ankan.first {
                    let idx = tile.deaka.index
                    if idx >= 0 && idx < 34 {
                        obs[ch * obsWidth + idx] = 1.0
                    }
                }
            }
            ch += 1
        }

        return ch
    }

    /// 編碼其他資訊
    private static func encodeOtherInfo(state: PlayerState, obs: inout [Float], startChannel: Int) -> Int {
        var ch = startChannel

        // 剩餘牌數
        let tilesLeftNorm = Float(state.tilesLeft) / 70.0
        for idx in 0..<34 {
            obs[ch * obsWidth + idx] = tilesLeftNorm
        }
        ch += 1

        // 向聽數
        let shantenNorm = Float(max(0, state.shanten + 1)) / 7.0
        for idx in 0..<34 {
            obs[ch * obsWidth + idx] = min(1.0, shantenNorm)
        }
        ch += 1

        // 是否門前
        if state.isMenzen {
            for idx in 0..<34 {
                obs[ch * obsWidth + idx] = 1.0
            }
        }
        ch += 1

        // 自家立直
        if state.riichiAccepted[0] {
            for idx in 0..<34 {
                obs[ch * obsWidth + idx] = 1.0
            }
        }
        ch += 1

        // 一發狀態
        if state.atIppatsu {
            for idx in 0..<34 {
                obs[ch * obsWidth + idx] = 1.0
            }
        }
        ch += 1

        // 已見牌
        for idx in 0..<34 {
            obs[ch * obsWidth + idx] = Float(state.tilesSeen[idx]) / 4.0
        }
        ch += 1

        // 聽牌
        for idx in 0..<34 {
            if state.waits[idx] {
                obs[ch * obsWidth + idx] = 1.0
            }
        }
        ch += 1

        // 振聽
        if state.atFuriten {
            for idx in 0..<34 {
                obs[ch * obsWidth + idx] = 1.0
            }
        }
        ch += 1

        return ch
    }

    // MARK: - Mask Encoding

    /// 編碼動作遮罩
    private static func encodeMask(state: PlayerState) -> [UInt8] {
        var mask = [UInt8](repeating: 0, count: actionSpace)
        let cans = state.lastCans

        // 打牌 (0-33)
        if cans.canDiscard {
            for idx in 0..<34 {
                if state.tehai[idx] > 0 {
                    // 檢查是否禁止打出
                    if !state.forbiddenTiles[idx] {
                        mask[idx] = 1
                    }
                }
            }
        }

        // 立直 (37)
        if cans.canRiichi {
            mask[PlayerState.ActionIndex.riichi] = 1
        }

        // 吃 (38-40)
        if cans.canChiLow {
            mask[PlayerState.ActionIndex.chiLow] = 1
        }
        if cans.canChiMid {
            mask[PlayerState.ActionIndex.chiMid] = 1
        }
        if cans.canChiHigh {
            mask[PlayerState.ActionIndex.chiHigh] = 1
        }

        // 碰 (41)
        if cans.canPon {
            mask[PlayerState.ActionIndex.pon] = 1
        }

        // 槓 (42)
        if cans.canKan {
            mask[PlayerState.ActionIndex.kan] = 1
        }

        // 和 (43)
        if cans.canAgari {
            mask[PlayerState.ActionIndex.hora] = 1
        }

        // 流局 (44)
        if cans.canRyukyoku {
            mask[PlayerState.ActionIndex.ryukyoku] = 1
        }

        // 跳過 (45)
        if cans.canPass {
            mask[PlayerState.ActionIndex.pass] = 1
        }

        return mask
    }
}
