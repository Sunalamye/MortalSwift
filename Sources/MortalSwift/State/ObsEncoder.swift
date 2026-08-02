//
//  ObsEncoder.swift
//  MortalSwift
//
//  觀測編碼器 - 將遊戲狀態轉換為模型輸入張量
//
//  Observation shape: (1012, 34) for version 4
//  Action mask shape: (46,)
//
//  ⚠️ 這個檔案的 channel 佈局**不是設計出來的，是抄來的**。
//
//  `mortal.mlmodelc` 是固定成品，它訓練時看到的每一個 channel 代表什麼，
//  完全由 libriichi（Mortal 的 Rust 核心）的 `encode_obs` 決定。少算或多算一個
//  channel，就會把其後**每一格**的語意都推移，模型等於在讀一份看不懂的輸入。
//
//  權威定義：docs/reference/libriichi_obs_repr.rs（來源 Equim-chan/Mortal）。
//  改動任何一段之前先讀它，並用 `obsParityAgainstLibRiichi` 對拍驗證。
//

import Foundation

/// 觀測編碼器
public struct ObsEncoder {

    // MARK: - Constants

    public static let obsChannels = 1012
    public static let obsWidth = 34
    public static let actionSpace = 46

    /// 自家河每一項佔的 channel 數
    private static let selfKawaItemChannels = 4
    /// 對家河每一項佔的 channel 數
    private static let kawaItemChannels = 8
    /// 單人期望值表的最大巡目數
    private static let maxNumTurns = 17

    // MARK: - Encoding Context

    /// 一次編碼過程中的寫入游標
    ///
    /// `fill` 寫整列（34 格都是同一個值），`assign` 只寫一格——
    /// 這兩者在 libriichi 裡是不同語意，混用會造成難以察覺的落差。
    private struct Context {
        var obs = [Float](repeating: 0, count: obsChannels * obsWidth)
        var mask = [UInt8](repeating: 0, count: actionSpace)
        var idx = 0

        mutating func fill(_ channel: Int, _ value: Float) {
            guard channel >= 0 && channel < obsChannels else { return }
            let base = channel * obsWidth
            for i in 0..<obsWidth { obs[base + i] = value }
        }

        mutating func assign(_ channel: Int, _ column: Int, _ value: Float) {
            guard channel >= 0 && channel < obsChannels,
                  column >= 0 && column < obsWidth else { return }
            obs[channel * obsWidth + column] = value
        }

        func get(_ channel: Int, _ column: Int) -> Float {
            guard channel >= 0 && channel < obsChannels,
                  column >= 0 && column < obsWidth else { return 0 }
            return obs[channel * obsWidth + column]
        }

        /// 整數編碼（v4 只做 rescale 或 one-hot，不做 rbf）
        mutating func encodeInteger(_ n: Int, cap: Int, oneHot: Bool = false, rescale: Bool = false) {
            let clamped = min(max(0, n), cap)
            if oneHot {
                fill(idx + clamped, 1.0)
                idx += cap + 1
            }
            if rescale {
                fill(idx, Float(clamped) / Float(cap))
                idx += 1
            }
        }

        /// 一組牌的編碼（4 格計數 + 3 格紅五），共 7 channel
        mutating func encodeTileSet<S: Sequence>(_ tiles: S) where S.Element == Tile {
            var counts = [Int](repeating: 0, count: 34)
            for tile in tiles {
                let tid = tile.deaka.index
                guard tid >= 0 else { continue }
                assign(idx + counts[tid], tid, 1.0)
                counts[tid] += 1
                if tile.isRed {
                    fill(idx + 4 + (tile.indexWithAka - 34), 1.0)
                }
            }
            idx += 7
        }
    }

    // MARK: - Encoding

    /// 編碼遊戲狀態為觀測張量
    /// - Parameters:
    ///   - state: 玩家狀態
    ///   - atKanSelect: 是否處於「選擇槓哪張」的次級決策
    /// - Returns: (觀測張量, 動作遮罩)
    public static func encode(state: PlayerState, atKanSelect: Bool = false) -> (obs: [Float], mask: [UInt8]) {
        var ctx = Context()
        let cans = state.lastCans

        // ── 手牌 4 + 紅五 3 ────────────────────────────────────────────
        for tid in 0..<34 where state.tehai[tid] > 0 {
            for n in 0..<state.tehai[tid] {
                ctx.assign(ctx.idx + n, tid, 1.0)
            }
        }
        ctx.idx += 4

        for i in 0..<3 where state.akasInHand[i] {
            ctx.fill(ctx.idx + i, 1.0)
        }
        ctx.idx += 3

        // ── 分數：每人 100k / 30k 兩種正規化 ───────────────────────────
        for score in state.scores {
            ctx.fill(ctx.idx, Float(min(max(0, score), 100_000)) / 100_000.0)
            ctx.idx += 1
            ctx.fill(ctx.idx, Float(min(max(0, score), 30_000)) / 30_000.0)
            ctx.idx += 1
        }

        // ── 排名（libriichi 為 0-based，Swift 的 rank 是 1-based）──────
        ctx.fill(ctx.idx + max(0, min(state.rank - 1, 3)), 1.0)
        ctx.idx += 4

        // ── 局數（libriichi 的 kyoku 是 0-based）──────────────────────
        let kyoku0 = max(0, min(state.kyoku - 1, 3))
        ctx.fill(ctx.idx + kyoku0, 1.0)
        ctx.idx += 4

        // ── 本場 / 立直棒：v4 只做 rescale，各 1 格 ────────────────────
        ctx.encodeInteger(state.honba, cap: 10, rescale: true)
        ctx.encodeInteger(state.kyotaku, cap: 10, rescale: true)

        // ── 場風 / 自風：只在該風的牌索引上打點 ───────────────────────
        ctx.assign(ctx.idx, state.bakaze.index, 1.0)
        ctx.assign(ctx.idx + 1, state.jikaze.index, 1.0)
        ctx.idx += 2

        let bakazeOffset = min(max(0, state.bakaze.index - Tile.east.index), 1)
        ctx.encodeInteger(bakazeOffset * 4 + kyoku0, cap: 7, rescale: true)

        // ── 寶牌指示牌（7 channel 的 tile set）─────────────────────────
        ctx.encodeTileSet(state.doraIndicators)

        // ── 河 ────────────────────────────────────────────────────────
        let maxKawaLen = state.kawa.map(\.count).max() ?? 0

        encodeKawaWindow(state.kawa[0], &ctx, itemChannels: selfKawaItemChannels) { item, c in
            encodeSelfKawaItem(item, &c)
        }
        // 自家：時間衰減
        for (turn, item) in state.kawa[0].enumerated() {
            guard let item else { continue }
            let tid = item.sutehai.tile.deaka.index
            ctx.assign(ctx.idx, tid, decay(turn: turn, maxKawaLen: maxKawaLen))
        }
        ctx.idx += 1

        for seat in 1..<4 {
            encodeKawaWindow(state.kawa[seat], &ctx, itemChannels: kawaItemChannels) { item, c in
                encodeOpponentKawaItem(item, &c)
            }
            // 對家：時間衰減 / 手切 / 立直宣言各一格
            for (turn, item) in state.kawa[seat].enumerated() {
                guard let item else { continue }
                let tid = item.sutehai.tile.deaka.index
                let v = decay(turn: turn, maxKawaLen: maxKawaLen)
                ctx.assign(ctx.idx, tid, v)
                if item.sutehai.isTedashi { ctx.assign(ctx.idx + 1, tid, v) }
                if item.sutehai.isRiichi { ctx.assign(ctx.idx + 2, tid, v) }
            }
            ctx.idx += 3
        }

        // ── 剩餘牌數 ──────────────────────────────────────────────────
        ctx.fill(ctx.idx, Float(state.tilesLeft) / 69.0)
        ctx.idx += 1

        // ── 各家持有的寶牌數 / 未見寶牌數 ─────────────────────────────
        let dorasOwned = state.computeDorasOwned()
        for count in dorasOwned {
            ctx.encodeInteger(count, cap: 12, rescale: true)
        }
        let dorasSeen = computeDorasSeen(state: state)
        let dorasUnseen = state.doraIndicators.count * 4 + 3 - dorasSeen
        ctx.encodeInteger(dorasUnseen, cap: 5 * 4 + 3, rescale: true)

        // ── 各家河概覽 ────────────────────────────────────────────────
        for seat in 0..<4 {
            ctx.encodeTileSet(state.kawaOverview[seat])
        }

        // ── 副露：每家 4 組 × 5 channel ───────────────────────────────
        for seat in 0..<4 {
            let melds = state.fuuroOverview[seat]
            for meld in melds.prefix(4) {
                for tile in meld {
                    let tid = tile.deaka.index
                    guard tid >= 0 else { continue }
                    // 同一張牌重覆出現時往下一格疊
                    let slot = (0..<4).first { ctx.get(ctx.idx + $0, tid) == 0 } ?? 3
                    ctx.assign(ctx.idx + slot, tid, 1.0)
                    if tile.isRed { ctx.fill(ctx.idx + 4, 1.0) }
                }
                ctx.idx += 5
            }
            ctx.idx += (4 - min(melds.count, 4)) * 5
        }

        // ── 暗槓 ──────────────────────────────────────────────────────
        for seat in 0..<4 {
            for ankan in state.ankanOverview[seat] {
                if let tile = ankan.first {
                    ctx.assign(ctx.idx, tile.deaka.index, 1.0)
                }
            }
            ctx.idx += 1
        }

        // ── 已見牌 ────────────────────────────────────────────────────
        for tid in 0..<34 {
            ctx.assign(ctx.idx, tid, Float(state.tilesSeen[tid]) / 4.0)
        }
        ctx.idx += 1

        // ── 對家最後手切牌 / 立直宣言牌 ───────────────────────────────
        for seat in 1..<4 {
            encodeSutehaiDetail(state.lastTedashis[seat], &ctx)
        }
        for seat in 1..<4 {
            encodeSutehaiDetail(state.riichiSutehais[seat], &ctx)
        }

        // ── 對家立直狀態 ──────────────────────────────────────────────
        for i in 0..<3 where state.riichiDeclared[i + 1] {
            ctx.fill(ctx.idx + i, 1.0)
        }
        ctx.idx += 3
        for i in 0..<3 where state.riichiAccepted[i + 1] {
            ctx.fill(ctx.idx + i, 1.0)
        }
        ctx.idx += 3

        // ── 聽牌 / 振聽 / 向聽 ────────────────────────────────────────
        for tid in 0..<34 where state.waits[tid] {
            ctx.assign(ctx.idx, tid, 1.0)
        }
        ctx.idx += 1

        if state.atFuriten { ctx.fill(ctx.idx, 1.0) }
        ctx.idx += 1

        // libriichi 的 state.shanten 經過 .max(0)，和了（-1）在這裡編成 0
        ctx.encodeInteger(max(0, state.shanten), cap: 6, oneHot: true)

        if state.riichiAccepted[0] { ctx.fill(ctx.idx, 1.0) }
        ctx.idx += 1

        if atKanSelect { ctx.fill(ctx.idx, 1.0) }
        ctx.idx += 1

        // ── 可回應的那張牌（吃/碰/槓/榮）──────────────────────────────
        if cans.canPass, let tile = state.lastKawaTile {
            let tid = tile.deaka.index
            ctx.assign(ctx.idx, tid, 1.0)
            if tile.isRed { ctx.fill(ctx.idx + 1, 1.0) }
            if tid >= 0 && state.doraFactor[tid] > 0 { ctx.fill(ctx.idx + 2, 1.0) }

            if !atKanSelect {
                ctx.mask[actionSpace - 1] = 1
            } else if cans.canDaiminkan {
                ctx.mask[tid] = 1
            }
        }
        ctx.idx += 3

        // ── 打牌候選 ──────────────────────────────────────────────────
        if cans.canDiscard {
            for (t, ok) in state.discardCandidatesAka().enumerated() where ok {
                let deakaT: Int
                switch t {
                case 34: deakaT = 4
                case 35: deakaT = 13
                case 36: deakaT = 22
                default: deakaT = t
                }
                ctx.assign(ctx.idx, deakaT, 1.0)
                if !atKanSelect { ctx.mask[t] = 1 }
            }
            for tid in 0..<34 where state.keepShantenDiscards[tid] {
                ctx.assign(ctx.idx + 1, tid, 1.0)
            }
            for tid in 0..<34 where state.nextShantenDiscards[tid] {
                ctx.assign(ctx.idx + 2, tid, 1.0)
            }
            // 打了之後無條件聽牌且有役的候選
            if state.shanten <= 1 {
                for (tid, ok) in state.discardCandidatesWithUnconditionalTenpai().enumerated() where ok {
                    ctx.assign(ctx.idx + 3, tid, 1.0)
                }
            }
            if state.riichiDeclared[0] { ctx.fill(ctx.idx + 4, 1.0) }
        }
        ctx.idx += 5

        // ── 各動作可用性 ──────────────────────────────────────────────
        if cans.canRiichi {
            ctx.fill(ctx.idx, 1.0)
            if !atKanSelect { ctx.mask[37] = 1 }
        }
        ctx.idx += 1

        if cans.canChiLow {
            ctx.fill(ctx.idx, 1.0)
            if !atKanSelect { ctx.mask[38] = 1 }
        }
        if cans.canChiMid {
            ctx.fill(ctx.idx + 1, 1.0)
            if !atKanSelect { ctx.mask[39] = 1 }
        }
        if cans.canChiHigh {
            ctx.fill(ctx.idx + 2, 1.0)
            if !atKanSelect { ctx.mask[40] = 1 }
        }
        ctx.idx += 3

        if cans.canPon {
            ctx.fill(ctx.idx, 1.0)
            if !atKanSelect { ctx.mask[41] = 1 }
        }
        ctx.idx += 1

        if cans.canDaiminkan {
            ctx.fill(ctx.idx, 1.0)
            if !atKanSelect { ctx.mask[42] = 1 }
        }
        ctx.idx += 1

        if cans.canAnkan {
            for tile in state.ankanCandidates {
                ctx.assign(ctx.idx, tile.deaka.index, 1.0)
                if atKanSelect { ctx.mask[tile.deaka.index] = 1 }
            }
            if !atKanSelect { ctx.mask[42] = 1 }
        }
        ctx.idx += 1

        if cans.canKakan {
            for tile in state.kakanCandidates {
                ctx.assign(ctx.idx, tile.deaka.index, 1.0)
                if atKanSelect { ctx.mask[tile.deaka.index] = 1 }
            }
            if !atKanSelect { ctx.mask[42] = 1 }
        }
        ctx.idx += 1

        if cans.canAgari {
            ctx.fill(ctx.idx, 1.0)
            if !atKanSelect { ctx.mask[43] = 1 }
        }
        ctx.idx += 1

        if cans.canRyukyoku {
            ctx.fill(ctx.idx, 1.0)
            if !atKanSelect { ctx.mask[44] = 1 }
        }
        ctx.idx += 1

        // ── 單人期望值表 ──────────────────────────────────────────────
        //
        // 對每一張可打的牌，往後每一巡的聽牌率／和牌率／期望值。
        // 算不出來時（牌不夠、已是和了形）整段留 0，與 libriichi 的 Err 分支一致。
        if let table = state.singlePlayerTables(), !table.isEmpty {
            // 最大期望值（表已依期望值排序，取第一筆）
            let maxEV = table[0].expValues.first ?? 0
            encodeEV(maxEV, &ctx)

            if cans.canDiscard {
                // 每張打牌所需的進張；向聽戻し的放在後 34 格
                for candidate in table {
                    let discardTid = SPTile.deaka(candidate.tile)
                    guard discardTid < 34 else { continue }
                    for required in candidate.requiredTiles {
                        let requiredTid = SPTile.deaka(required.tile)
                        let row = candidate.shantenDown
                            ? ctx.idx + 34 + discardTid
                            : ctx.idx + discardTid
                        ctx.assign(row, requiredTid, 1.0)
                    }
                }
                ctx.idx += 2 * 34

                // 進張數最多的那張打牌
                //
                // ⚠️ 已知落差（現有劇本全過，但不是全對）：libriichi 寫的是
                // `max_by(|l, r| l.cmp(r, NotShantenDown))`，而 `Candidate::cmp` 的
                // 次要排序鍵不在 `docs/reference/` 裡，所以「進張數並列時挑哪一張」
                // 還原不出來。實測過的三個並列局面裡，兩個是取第一個、一個是取第二個，
                // 單純換成「取最後一個」反而讓 minimal / aka-discard 對不上。
                // 補回 libriichi 的 `algo/sp` 之前先維持取第一個。
                if let best = table.max(by: { lhs, rhs in
                    if lhs.shantenDown != rhs.shantenDown { return lhs.shantenDown }
                    return lhs.numRequiredTiles < rhs.numRequiredTiles
                }) {
                    ctx.assign(ctx.idx, SPTile.deaka(best.tile), 1.0)
                }
                ctx.idx += 2
            } else {
                ctx.idx += 2 * 34 + 1
                for required in table[0].requiredTiles {
                    ctx.assign(ctx.idx, SPTile.deaka(required.tile), 1.0)
                }
                ctx.idx += 1
            }

            let evScale: Float = maxEV < 1 ? 0 : 1 / maxEV
            encodeSPTable(table, canDiscard: cans.canDiscard, evScale: evScale, &ctx)
        } else {
            // 保留正確的格數：內容缺失只是資訊少，格數錯則是其後全部語意錯位
            ctx.idx += 2                       // 期望值
            ctx.idx += 2 * 34                  // 各打牌所需的進張
            ctx.idx += 2                       // 進張數最多的打牌
            ctx.idx += 3 * maxNumTurns         // 聽牌率 / 和牌率 / 期望值表
        }

        // 用 precondition 而不是 assert：`assert` 在 Release 會被整個編掉，
        // 而這一格正是「Release 才更需要」的檢查——channel 數對不上代表整份張量的
        // 語意都推移了，模型會照著一份看不懂的輸入給出看似正常的機率。
        // 那種錯誤不會自己浮出來，只會表現成「bot 變弱了」。寧可當場停住。
        precondition(ctx.idx == obsChannels, "channel 佈局錯誤：寫到 \(ctx.idx)，應為 \(obsChannels)")

        return (ctx.obs, ctx.mask)
    }

    // MARK: - 單人期望值表

    /// 期望值編成兩格：100k 與 30k 兩種正規化
    private static func encodeEV(_ value: Float, _ ctx: inout Context) {
        ctx.fill(ctx.idx, min(max(value, 0), 100_000) / 100_000)
        ctx.fill(ctx.idx + 1, min(max(value, 0), 30_000) / 30_000)
        ctx.idx += 2
    }

    /// 聽牌率 / 和牌率 / 期望值各 17 巡，共 51 格
    private static func encodeSPTable(
        _ table: [SPCandidate], canDiscard: Bool, evScale: Float, _ ctx: inout Context
    ) {
        // 機率根本沒算（向聽 >= 4）或全為 0 時什麼都不寫
        guard let first = table.first, (first.tenpaiProbs.first ?? 0) > 0 else {
            ctx.idx += 3 * maxNumTurns
            return
        }

        func write(_ turn: Int, _ tenpai: Float, _ win: Float, _ ev: Float, tile: Int?) {
            guard turn < maxNumTurns else { return }
            let evClamped = min(ev * evScale, 1)
            if let tile {
                ctx.assign(ctx.idx + turn, tile, tenpai)
                ctx.assign(ctx.idx + turn + maxNumTurns, tile, win)
                ctx.assign(ctx.idx + turn + 2 * maxNumTurns, tile, evClamped)
            } else {
                ctx.fill(ctx.idx + turn, tenpai)
                ctx.fill(ctx.idx + turn + maxNumTurns, win)
                ctx.fill(ctx.idx + turn + 2 * maxNumTurns, evClamped)
            }
        }

        if canDiscard {
            for candidate in table {
                let tid = SPTile.deaka(candidate.tile)
                guard tid < 34 else { continue }
                for turn in 0..<candidate.tenpaiProbs.count {
                    guard candidate.tenpaiProbs[turn] > 0 else { break }
                    write(turn, candidate.tenpaiProbs[turn],
                          candidate.winProbs[turn], candidate.expValues[turn], tile: tid)
                }
            }
        } else {
            for turn in 0..<first.tenpaiProbs.count {
                guard first.tenpaiProbs[turn] > 0 else { break }
                write(turn, first.tenpaiProbs[turn],
                      first.winProbs[turn], first.expValues[turn], tile: nil)
            }
        }
        ctx.idx += 3 * maxNumTurns
    }

    // MARK: - Kawa Helpers

    /// 時間衰減：越接近最新一輪越接近 1
    private static func decay(turn: Int, maxKawaLen: Int) -> Float {
        exp(-0.2 * Float(maxKawaLen - 1 - turn))
    }

    /// 河的「開頭 6 項」與「結尾 18 項（由新到舊）」兩個視窗
    private static func encodeKawaWindow(
        _ kawa: [KawaItem?],
        _ ctx: inout Context,
        itemChannels: Int,
        encodeItem: (KawaItem?, inout Context) -> Void
    ) {
        for item in kawa.prefix(6) { encodeItem(item, &ctx) }
        ctx.idx += (6 - min(kawa.count, 6)) * itemChannels

        for item in kawa.reversed().prefix(18) { encodeItem(item, &ctx) }
        ctx.idx += (18 - min(kawa.count, 18)) * itemChannels
    }

    private static func encodeSelfKawaItem(_ item: KawaItem?, _ ctx: inout Context) {
        if let item {
            for kan in item.kan {
                ctx.assign(ctx.idx, kan.deaka.index, 1.0)
            }
            let sutehai = item.sutehai
            ctx.assign(ctx.idx + 1, sutehai.tile.deaka.index, 1.0)
            if sutehai.tile.isRed { ctx.fill(ctx.idx + 2, 1.0) }
            if sutehai.isDora { ctx.fill(ctx.idx + 3, 1.0) }
        }
        ctx.idx += selfKawaItemChannels
    }

    private static func encodeOpponentKawaItem(_ item: KawaItem?, _ ctx: inout Context) {
        if let item {
            if let chiPon = item.chiPon, chiPon.consumed.count >= 2 {
                let a = chiPon.consumed[0].deaka.index
                let b = chiPon.consumed[1].deaka.index
                ctx.assign(ctx.idx, min(a, b), 1.0)
                ctx.assign(ctx.idx + 1, max(a, b), 1.0)
            }
            for kan in item.kan {
                ctx.assign(ctx.idx + 2, kan.deaka.index, 1.0)
            }
            let sutehai = item.sutehai
            ctx.assign(ctx.idx + 3, sutehai.tile.deaka.index, 1.0)
            if sutehai.tile.isRed { ctx.fill(ctx.idx + 4, 1.0) }
            if sutehai.isDora { ctx.fill(ctx.idx + 5, 1.0) }
            if sutehai.isTedashi { ctx.fill(ctx.idx + 6, 1.0) }
            if sutehai.isRiichi { ctx.fill(ctx.idx + 7, 1.0) }
        }
        ctx.idx += kawaItemChannels
    }

    /// 捨牌細節：牌 / 是否紅五 / 是否寶牌，共 3 channel
    private static func encodeSutehaiDetail(_ sutehai: Sutehai?, _ ctx: inout Context) {
        if let sutehai {
            ctx.assign(ctx.idx, sutehai.tile.deaka.index, 1.0)
            if sutehai.tile.isRed { ctx.fill(ctx.idx + 1, 1.0) }
            if sutehai.isDora { ctx.fill(ctx.idx + 2, 1.0) }
        }
        ctx.idx += 3
    }

    // MARK: - Dora Accounting

    // 「各家持有的寶牌數」只有一份實作：`PlayerState.computeDorasOwned()`
    //（見 SinglePlayerTables.swift）。這裡原本有一份逐行相同的私有複本，
    // 兩邊都是 observation 與單人期望值推演的輸入——同一個數字算兩次，
    // 只要有一邊被改（例如補上加槓的第 4 張），obs 與 SP 表就會對不起來，
    // 而且不會有任何測試失敗來提醒。

    /// 已見的寶牌數（含紅五）
    private static func computeDorasSeen(state: PlayerState) -> Int {
        var seen = 0
        for tid in 0..<34 {
            seen += state.tilesSeen[tid] * state.doraFactor[tid]
        }
        seen += state.akasSeen.filter { $0 }.count
        return seen
    }
}
