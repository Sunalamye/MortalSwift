//
//  StateUpdate.swift
//  MortalSwift
//
//  狀態更新邏輯 - 處理 MJAI 事件
//

import Foundation

// MARK: - State Update Extension

extension PlayerState {

    /// 處理 MJAI 事件並更新狀態
    /// - Parameter event: MJAI 事件
    /// - Returns: 是否需要動作
    public func update(event: MJAIEvent) -> Bool {
        // 清除上一輪的動作狀態
        //
        // intermediateKan / intermediateChiPon **不能**在這裡清：它們要從「我吃碰槓」
        // 一路帶到「我接著打出的那張牌」，中間隔了一個事件。在這裡清等於永遠讀不到。
        // 生命週期由 handleStartKyoku（開局重置）與 handleDahai（取用後清空）負責。
        lastCans = ActionCandidate()

        switch event {
        case .startGame:
            reset()
            return false

        case .endGame:
            return false

        case .startKyoku(let e):
            handleStartKyoku(e)
            return false

        case .endKyoku:
            return false

        case .tsumo(let e):
            return handleTsumo(e)

        case .dahai(let e):
            return handleDahai(e)

        case .reach(let e):
            handleReach(e)
            return false

        case .reachAccepted(let e):
            handleReachAccepted(e)
            return false

        case .chi(let e):
            handleChi(e)
            return false

        case .pon(let e):
            handlePon(e)
            return false

        case .daiminkan(let e):
            handleDaiminkan(e)
            return false

        case .ankan(let e):
            handleAnkan(e)
            return false

        case .kakan(let e):
            handleKakan(e)
            return false

        case .dora(let e):
            handleDora(e)
            return false

        case .nukidora(let e):
            handleNukidora(e)
            return false

        case .hora:
            return false

        case .ryukyoku:
            return false
        }
    }

    // MARK: - Event Handlers

    private func handleStartKyoku(_ event: StartKyokuEvent) {
        // 重置局狀態
        tehai = [Int](repeating: 0, count: 34)
        akasInHand = [false, false, false]
        akasSeen = [false, false, false]

        kawa = [[], [], [], []]
        kawaOverview = [[], [], [], []]
        lastTedashis = [nil, nil, nil, nil]
        riichiSutehais = [nil, nil, nil, nil]

        fuuroOverview = [[], [], [], []]
        ankanOverview = [[], [], [], []]
        chis = []
        pons = []
        minkans = []
        ankans = []

        riichiDeclared = [false, false, false, false]
        riichiAccepted = [false, false, false, false]
        tilesLeft = 70

        doraIndicators = []
        tilesSeen = [Int](repeating: 0, count: 34)
        forbiddenTiles = [Bool](repeating: false, count: 34)
        discardedTiles = [Bool](repeating: false, count: 34)
        keepShantenDiscards = [Bool](repeating: false, count: 34)
        nextShantenDiscards = [Bool](repeating: false, count: 34)
        hasNextShantenDiscard = false

        intermediateKan = []
        intermediateChiPon = nil
        dorasOwned = [0, 0, 0, 0]
        dorasSeen = 0

        lastCans = ActionCandidate()
        ankanCandidates = []
        kakanCandidates = []
        chiCandidates = []
        ponCandidates = []

        canWRiichi = true
        isWRiichi = false
        atRinshan = false
        atIppatsu = false
        atFuriten = false

        lastSelfTsumo = nil
        lastKawaTile = nil
        kansOnBoard = 0

        isMenzen = true
        tehaiLenDiv3 = 4

        // 設置場況
        bakaze = event.bakaze.tile
        kyoku = event.kyoku
        honba = event.honba
        kyotaku = event.kyotaku

        // 計算相對莊家
        oya = toRelative(event.oya)

        // 莊家之前的相對座位在第一輪不打牌，補 nil 讓四家的河對齊輪次
        padKawaAtStart()

        // 計算自風
        let jikazeIndex = (playerId - event.oya + 4) % 4
        jikaze = [Tile.east, .south, .west, .north][jikazeIndex]

        // 設置分數 (轉換為相對座位)
        for i in 0..<4 {
            let absPos = toAbsolute(i)
            scores[i] = event.scores[absPos]
        }

        // 計算排名
        updateRank()

        // 設置手牌
        // 自己的起手牌也算「已見」——libriichi 在配牌時就 witness 過，
        // 少算會讓 tiles_seen 這一格與訓練時的語意不同。
        let myTehai = event.tehais[playerId]
        for tile in myTehai where tile != .unknown {
            addTile(tile)
            markTileSeen(tile)
        }

        // 設置寶牌
        doraIndicators.append(event.doraMarker)
        markTileSeen(event.doraMarker)
        updateDoraFactor()

        // 計算向聽。配牌是 3n+1，此時才算得了等待
        updateShanten()
        updateWaits()

        // 檢查 All Last
        checkAllLast()
    }

    private func handleTsumo(_ event: TsumoEvent) -> Bool {
        let relActor = toRelative(event.actor)
        atTurn = relActor
        tilesLeft -= 1

        // 取消所有人的一發
        for i in 0..<4 {
            if riichiAccepted[i] {
                atIppatsu = false
            }
        }

        if relActor == 0 {
            // 自己摸牌
            lastSelfTsumo = event.pai
            addTile(event.pai)
            markTileSeen(event.pai)

            // 摸牌後**不重算向聽、也不重算 waits**。
            //
            // libriichi 的 `shanten` 一律是「3n+1 手牌」的值（tsumo handler 裡
            // 明寫 "Does not update shanten"），摸牌後的 3n+2 沿用摸牌前那個數字。
            // 這不是偷懶：`update_shanten_discards` 與 `can_riichi` 都拿它當基準比較，
            // 在這裡重算會讓「這張打下去能不能前進向聽」整組判斷失去意義。
            calculateTsumoActions()

            return lastCans.canAct
        } else {
            // 其他人摸牌
            lastSelfTsumo = nil
            return false
        }
    }

    private func handleDahai(_ event: DahaiEvent) -> Bool {
        let relActor = toRelative(event.actor)
        let tile = event.pai

        // 記錄河
        // isDora 指「這張牌本身是寶牌」（doraFactor > 0），不是「這張是寶牌指示牌」。
        // isRiichi 指「這張是立直宣言牌」＝已宣告但尚未成立的那一巡。
        let isRiichiSutehai = riichiDeclared[relActor] && !riichiAccepted[relActor]
        let sutehai = Sutehai(
            tile: tile,
            isDora: doraFactor[tile.deaka.index] > 0,
            isTedashi: !event.tsumogiri,
            isRiichi: isRiichiSutehai
        )
        // 吃／碰／槓掛在**打牌者自己**的這一項上（「我副露之後打出這張」），
        // 不是掛在被吃那家的河上
        let kawaItem = KawaItem(sutehai: sutehai, chiPon: intermediateChiPon, kan: intermediateKan)
        intermediateChiPon = nil
        intermediateKan = []
        kawa[relActor].append(kawaItem)
        kawaOverview[relActor].append(tile)
        if !event.tsumogiri {
            lastTedashis[relActor] = sutehai
        }
        if isRiichiSutehai {
            riichiSutehais[relActor] = sutehai
        }
        lastKawaTile = tile

        // 自己打出的牌在配牌／摸牌時就已經算過「已見」，這裡再算一次會重覆計數
        if relActor != 0 {
            markTileSeen(tile)
        }

        // 紅寶牌
        if tile.isRed {
            switch tile {
            case .man(5, red: true): akasSeen[0] = true
            case .pin(5, red: true): akasSeen[1] = true
            case .sou(5, red: true): akasSeen[2] = true
            default: break
            }
        }

        if relActor == 0 {
            // 自己打牌
            removeTile(tile)
            discardedTiles[tile.deaka.index] = true

            // W 立直失效
            canWRiichi = false

            // 更新向聽
            updateShanten()
            updateWaits()

            // 檢查振聽
            updateFuriten()

            lastSelfTsumo = nil
            return false
        } else {
            // 其他人打牌，檢查可用動作
            calculateDahaiReactions(relActor: relActor, tile: tile)
            return lastCans.canAct
        }
    }

    private func handleReach(_ event: ReachEvent) {
        let relActor = toRelative(event.actor)
        riichiDeclared[relActor] = true
    }

    private func handleReachAccepted(_ event: ReachAcceptedEvent) {
        let relActor = toRelative(event.actor)
        riichiAccepted[relActor] = true
        // 立直成立時那 1000 點是**從分數扣掉**再變成場上的立直棒，
        // 只加 kyotaku 不扣分會讓分數這幾格一路錯到局末
        scores[relActor] -= 1000
        kyotaku += 1

        // 開啟一發
        if relActor == 0 {
            atIppatsu = true
        }
    }

    private func handleChi(_ event: ChiEvent) {
        let relActor = toRelative(event.actor)

        // 記錄副露
        let meld = [event.pai] + event.consumed
        fuuroOverview[relActor].append(meld)

        // 副露資訊暫存，等 actor 打出下一張時掛到他自己的河項上。
        // 吃一定來自上家，不會跳過任何人，所以不需要補輪次。
        intermediateChiPon = ChiPon(consumed: event.consumed, targetTile: event.pai)
        // 副露亮出來的牌，對所有人都算「已見」
        for tile in event.consumed { markTileSeen(tile) }

        if relActor == 0 {
            // 自己吃
            removeTile(event.consumed[0])
            removeTile(event.consumed[1])
            isMenzen = false

            // 記錄吃的面子
            let minIdx = min(event.consumed[0].deaka.index, event.consumed[1].deaka.index, event.pai.deaka.index)
            chis.append(minIdx)

            tehaiLenDiv3 = max(0, tehaiLenDiv3 - 1)

            // 副露改變了手牌組成，向聽與等待必須立刻重算。
            // 原本只有開局／摸牌／打牌會算，吃碰之後仍沿用副露前的舊值，
            // 導致 mask 與 observation 都是過期的。
            // 同摸牌：副露後是 3n+2，不重算 waits
            updateShanten()

            // 需要打牌
            lastCans.canDiscard = true
            updateShantenDiscards()
        }
    }

    private func handlePon(_ event: PonEvent) {
        let relActor = toRelative(event.actor)

        // 記錄副露
        let meld = [event.pai] + event.consumed
        fuuroOverview[relActor].append(meld)

        intermediateChiPon = ChiPon(consumed: event.consumed, targetTile: event.pai)
        // 副露亮出來的牌，對所有人都算「已見」
        for tile in event.consumed { markTileSeen(tile) }
        padKawaForPonOrDaiminkan(absActor: event.actor, absTarget: event.target)

        if relActor == 0 {
            // 自己碰
            removeTile(event.consumed[0])
            removeTile(event.consumed[1])
            isMenzen = false

            pons.append(event.pai.deaka.index)

            tehaiLenDiv3 = max(0, tehaiLenDiv3 - 1)
            // 同摸牌：副露後是 3n+2，不重算 waits
            updateShanten()

            // 需要打牌
            lastCans.canDiscard = true
            updateShantenDiscards()
        }
    }

    private func handleDaiminkan(_ event: DaiminkanEvent) {
        let relActor = toRelative(event.actor)

        // 記錄副露
        let meld = [event.pai] + event.consumed
        fuuroOverview[relActor].append(meld)

        intermediateKan.append(event.pai)
        for tile in event.consumed { markTileSeen(tile) }
        padKawaForPonOrDaiminkan(absActor: event.actor, absTarget: event.target)

        kansOnBoard += 1

        if relActor == 0 {
            // 自己大明槓
            removeTile(event.consumed[0])
            removeTile(event.consumed[1])
            removeTile(event.consumed[2])
            isMenzen = false

            minkans.append(event.pai.deaka.index)

            // 大明槓吃掉手上 3 張再補嶺上 1 張，手牌淨少一組。
            // 吃／碰有做這件事，槓卻漏了，導致之後的向聽都用錯的組數在算。
            tehaiLenDiv3 = max(0, tehaiLenDiv3 - 1)
            updateShanten()
            updateWaits()

            // 嶺上狀態
            atRinshan = true
        }
    }

    private func handleAnkan(_ event: AnkanEvent) {
        let relActor = toRelative(event.actor)

        // 記錄暗槓
        ankanOverview[relActor].append(event.consumed.map { $0.deaka })

        intermediateKan.append(event.consumed[0])
        for tile in event.consumed { markTileSeen(tile) }

        kansOnBoard += 1

        if relActor == 0 {
            // 自己暗槓
            for tile in event.consumed {
                removeTile(tile)
            }

            let idx = event.consumed[0].deaka.index
            ankans.append(idx)

            // 暗槓吃掉手上 4 張再補嶺上 1 張，手牌同樣淨少一組
            tehaiLenDiv3 = max(0, tehaiLenDiv3 - 1)
            updateShanten()
            updateWaits()

            // 嶺上狀態
            atRinshan = true
        }
    }

    private func handleKakan(_ event: KakanEvent) {
        let relActor = toRelative(event.actor)

        intermediateKan.append(event.pai)
        markTileSeen(event.pai)

        // 更新副露
        if relActor == 0 {
            removeTile(event.pai)

            // 更新碰為槓
            if let idx = pons.firstIndex(of: event.pai.deaka.index) {
                pons.remove(at: idx)
                minkans.append(event.pai.deaka.index)
            }

            // 加槓：手上少 1 張、補嶺上 1 張，組數不變（碰時已扣過），
            // 但手牌組成變了，向聽與等待仍要重算
            updateShanten()
            updateWaits()

            // 嶺上狀態
            atRinshan = true
        }

        kansOnBoard += 1
    }

    private func handleDora(_ event: DoraEvent) {
        doraIndicators.append(event.doraMarker)
        updateDoraFactor()
    }

    private func handleNukidora(_ event: NukidoraEvent) {
        let relActor = toRelative(event.actor)
        markTileSeen(event.pai)

        if relActor == 0 {
            removeTile(event.pai)
        }
    }

    // MARK: - Action Calculation

    private func calculateTsumoActions() {
        lastCans = ActionCandidate()
        lastCans.canDiscard = true
        if !riichiAccepted[0] {
            updateShantenDiscards()
        }

        // 檢查自摸：摸到的牌在等待裡就是和了形。
        //
        // 振聽**只限制榮和**，不限制自摸——這是麻將規則，不是實作選擇。
        // 原本寫成 `shanten == -1 && !atFuriten`，會讓振聽狀態下的自摸消失，
        // 是實測漏和的成因之一。
        if let tsumo = lastSelfTsumo, waits[tsumo.deaka.index] {
            // 門前清自摸和 / 立直 / 海底摸月 / 嶺上開花 / 天地和 → 必定有役
            if isMenzen || riichiAccepted[0] || tilesLeft == 0 || atRinshan || canWRiichi {
                lastCans.canTsumoAgari = true
            } else {
                // 副露手要真的有役才能和
                lastCans.canTsumoAgari = AgariCalculator(
                    tehai: tehai, isMenzen: isMenzen,
                    chis: chis, pons: pons, minkans: minkans, ankans: ankans,
                    bakaze: bakaze.index, jikaze: jikaze.index,
                    winningTile: tsumo.deaka.index, isRon: false
                ).hasYaku()
            }
        }

        // 檢查暗槓
        calculateAnkanCandidates()
        if !ankanCandidates.isEmpty {
            lastCans.canAnkan = true
        }

        // 檢查加槓
        calculateKakanCandidates()
        if !kakanCandidates.isEmpty {
            lastCans.canKakan = true
        }

        // 檢查立直
        if canDeclareRiichi() {
            lastCans.canRiichi = true
        }

        // 檢查九種九牌
        if canDeclareRyukyoku() {
            lastCans.canRyukyoku = true
        }
    }

    private func calculateDahaiReactions(relActor: Int, tile: Tile) {
        lastCans = ActionCandidate()
        lastCans.targetActor = relActor

        // 如果已立直，只能榮和
        if riichiAccepted[0] {
            if canRon(tile: tile) {
                lastCans.canRonAgari = true
            }
            return
        }

        // 檢查榮和
        if canRon(tile: tile) {
            lastCans.canRonAgari = true
        }

        // 只能從上家吃
        if relActor == 3 {
            calculateChiCandidates(tile: tile)
            if !chiCandidates.isEmpty {
                lastCans.canChiLow = chiCandidates.contains { ChiType.from(consumed: $0, target: tile) == .low }
                lastCans.canChiMid = chiCandidates.contains { ChiType.from(consumed: $0, target: tile) == .mid }
                lastCans.canChiHigh = chiCandidates.contains { ChiType.from(consumed: $0, target: tile) == .high }
            }
        }

        // 檢查碰
        calculatePonCandidates(tile: tile)
        if !ponCandidates.isEmpty {
            lastCans.canPon = true
        }

        // 檢查大明槓
        if tehai[tile.deaka.index] >= 3 {
            lastCans.canDaiminkan = true
        }
    }

    // MARK: - Kawa 輪次對齊

    /// 開局時，相對座位在莊家之前的人第一輪不打牌，補一個 nil 佔位
    private func padKawaAtStart() {
        for rel in 0..<oya {
            kawa[rel].append(nil)
        }
    }

    /// 碰／大明槓會跳過 target 與 actor 之間的玩家，替他們補一個 nil 佔位
    private func padKawaForPonOrDaiminkan(absActor: Int, absTarget: Int) {
        var i = (absTarget + 1) % 4
        while i != absActor {
            kawa[toRelative(i)].append(nil)
            i = (i + 1) % 4
        }
    }

    // MARK: - 打牌候選

    /// 逐張試打，分類成「向聽前進」與「向聽不變」
    ///
    /// 必須在手牌為 3n+2（可打牌）時呼叫。
    func updateShantenDiscards() {
        nextShantenDiscards = [Bool](repeating: false, count: 34)
        keepShantenDiscards = [Bool](repeating: false, count: 34)
        hasNextShantenDiscard = false

        var work = tehai
        for tid in 0..<34 where tehai[tid] > 0 {
            work[tid] -= 1
            let after = ShantenCalculator.calcAll(tehai: work, lenDiv3: tehaiLenDiv3)
            work[tid] += 1

            if after < shanten {
                nextShantenDiscards[tid] = true
                hasNextShantenDiscard = true
            } else if after == shanten {
                keepShantenDiscards[tid] = true
            }
        }
    }

    /// 可打出的牌（含紅五，索引 0-36）
    ///
    /// 立直成立後只能摸切；宣告立直但尚未成立時只能打不破壞聽牌的那些。
    public func discardCandidatesAka() -> [Bool] {
        var ret = [Bool](repeating: false, count: 37)

        if riichiAccepted[0] {
            if let tsumo = lastSelfTsumo {
                ret[tsumo.indexWithAka] = true
            }
            return ret
        }

        for tid in 0..<34 where tehai[tid] > 0 {
            if riichiDeclared[0] {
                ret[tid] = shanten == 1 ? nextShantenDiscards[tid] : keepShantenDiscards[tid]
            } else {
                ret[tid] = !forbiddenTiles[tid]
            }
        }

        applyAkaToCandidates(&ret)
        return ret
    }

    /// 打出後「無條件聽牌且有役」的候選（含紅五，索引 0-36）
    ///
    /// 對應 libriichi 的 `discard_candidates_with_unconditional_tenpai_aka`。
    /// 「無條件」的意思是：打了這張之後，**任何**可能進的和了牌都真的能和——
    /// 不振聽、而且有役。只要有一張進張會造成振聽，這張打牌就不算數。
    public func discardCandidatesWithUnconditionalTenpaiAka() -> [Bool] {
        var ret = [Bool](repeating: false, count: 37)

        // 海底、或根本到不了聽牌
        if tilesLeft == 0 || shanten > 1 || (shanten == 1 && !hasNextShantenDiscard) {
            return ret
        }

        if let tsumo = lastSelfTsumo {
            if waits[tsumo.deaka.index] {
                // 已經是和了形，打任何一張都會振聽
                return ret
            }
            if riichiAccepted[0] {
                // 立直後只能摸切；振聽是永久的
                if !atFuriten { ret[tsumo.indexWithAka] = true }
                return ret
            }
        } else if ShantenCalculator.calcAll(tehai: tehai, lenDiv3: tehaiLenDiv3) == -1 {
            // 吃碰之後的打牌，同上
            return ret
        }

        let tenpaiDiscards = shanten == 1 ? nextShantenDiscards : keepShantenDiscards

        for discard in 0..<34 where tenpaiDiscards[discard] && !forbiddenTiles[discard] {
            var after = tehai
            after[discard] -= 1

            for tsumo in 0..<34 {
                if tsumo == discard || after[tsumo] == 4 { continue }

                var complete = after
                complete[tsumo] += 1
                guard ShantenCalculator.calcAll(tehai: complete, lenDiv3: tehaiLenDiv3) == -1 else {
                    continue
                }

                // 振聽：這張進張自己打過，整個打牌選項作廢
                if discardedTiles[tsumo] {
                    ret[discard] = false
                    break
                }

                // 必須放在振聽檢查之後
                if tilesSeen[tsumo] == 4 || ret[discard] { continue }

                ret[discard] = AgariCalculator(
                    tehai: complete, isMenzen: isMenzen,
                    chis: chis, pons: pons, minkans: minkans, ankans: ankans,
                    bakaze: bakaze.index, jikaze: jikaze.index,
                    winningTile: tsumo, isRon: true
                ).hasYaku()
            }
        }

        applyAkaToCandidates(&ret)
        return ret
    }

    /// 折回 34 格（紅五併入普通五）
    public func discardCandidatesWithUnconditionalTenpai() -> [Bool] {
        let full = discardCandidatesWithUnconditionalTenpaiAka()
        var ret = Array(full[0..<34])
        ret[4] = ret[4] || full[34]
        ret[13] = ret[13] || full[35]
        ret[22] = ret[22] || full[36]
        return ret
    }

    /// 手上有紅五時，紅五與普通五是兩個不同的打牌選項
    private func applyAkaToCandidates(_ ret: inout [Bool]) {
        for (normal, aka, slot) in [(4, 34, 0), (13, 35, 1), (22, 36, 2)]
        where ret[normal] && akasInHand[slot] {
            ret[aka] = true
            ret[normal] = tehai[normal] > 1
        }
    }

    // MARK: - Helper Methods

    private func markTileSeen(_ tile: Tile) {
        let idx = tile.deaka.index
        if idx >= 0 && idx < 34 {
            tilesSeen[idx] += 1
        }
    }

    private func isDoraIndicator(_ tile: Tile) -> Bool {
        let doraTile = tile.next
        return doraFactor[doraTile.deaka.index] > 0
    }

    private func updateRank() {
        let myScore = scores[0]
        rank = 1
        for i in 1..<4 {
            if scores[i] > myScore {
                rank += 1
            }
        }
    }

    private func checkAllLast() {
        // 南4局或以上
        isAllLast = (bakaze == .south && kyoku >= 3)
    }

    private func updateFuriten() {
        // 檢查同巡振聽和立直後振聽
        for idx in 0..<34 where waits[idx] && discardedTiles[idx] {
            atFuriten = true
            return
        }
    }

    private func canDeclareRiichi() -> Bool {
        guard isMenzen && !riichiDeclared[0] && tilesLeft >= 4 && scores[0] >= 1000 else {
            return false
        }
        // libriichi：向聽 0，或一向聽但存在能推進到聽牌的打牌
        return shanten == 0 || (shanten == 1 && hasNextShantenDiscard)
    }

    private func canDeclareRyukyoku() -> Bool {
        // 第一巡且有九種以上幺九牌
        guard canWRiichi else { return false }

        var yaokyuuCount = 0
        let yaokyuuIndices = [0, 8, 9, 17, 18, 26, 27, 28, 29, 30, 31, 32, 33]
        for idx in yaokyuuIndices where tehai[idx] > 0 {
            yaokyuuCount += 1
        }

        return yaokyuuCount >= 9
    }

    private func canRon(tile: Tile) -> Bool {
        guard !atFuriten else { return false }

        let idx = tile.deaka.index
        return waits[idx]
    }

    private func calculateAnkanCandidates() {
        ankanCandidates = []
        guard isMenzen || !riichiAccepted[0] else { return }

        for idx in 0..<34 where tehai[idx] >= 4 {
            if let tile = Tile.fromIndex(idx) {
                ankanCandidates.append(tile)
            }
        }
    }

    private func calculateKakanCandidates() {
        kakanCandidates = []
        guard !riichiAccepted[0] else { return }

        for ponIdx in pons {
            if tehai[ponIdx] >= 1 {
                if let tile = Tile.fromIndex(ponIdx) {
                    kakanCandidates.append(tile)
                }
            }
        }
    }

    private func calculateChiCandidates(tile: Tile) {
        chiCandidates = []

        guard !tile.isHonor else { return }

        let idx = tile.deaka.index
        let suitBase = (idx / 9) * 9
        let num = idx - suitBase  // 0-8

        // 左搭 (tile 是最右)
        if num >= 2 {
            let left2 = suitBase + num - 2
            let left1 = suitBase + num - 1
            if tehai[left2] >= 1 && tehai[left1] >= 1 {
                if let t1 = Tile.fromIndex(left2), let t2 = Tile.fromIndex(left1) {
                    chiCandidates.append([t1, t2])
                }
            }
        }

        // 嵌張 (tile 是中間)
        if num >= 1 && num <= 7 {
            let left = suitBase + num - 1
            let right = suitBase + num + 1
            if tehai[left] >= 1 && tehai[right] >= 1 {
                if let t1 = Tile.fromIndex(left), let t2 = Tile.fromIndex(right) {
                    chiCandidates.append([t1, t2])
                }
            }
        }

        // 右搭 (tile 是最左)
        if num <= 6 {
            let right1 = suitBase + num + 1
            let right2 = suitBase + num + 2
            if tehai[right1] >= 1 && tehai[right2] >= 1 {
                if let t1 = Tile.fromIndex(right1), let t2 = Tile.fromIndex(right2) {
                    chiCandidates.append([t1, t2])
                }
            }
        }
    }

    private func calculatePonCandidates(tile: Tile) {
        ponCandidates = []

        let idx = tile.deaka.index
        if tehai[idx] >= 2 {
            // 根據手中紅寶牌決定碰的組合
            ponCandidates.append([tile.deaka, tile.deaka])
        }
    }
}
