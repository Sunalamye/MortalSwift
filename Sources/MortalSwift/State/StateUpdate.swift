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
        lastCans = ActionCandidate()
        intermediateKan = []
        intermediateChiPon = nil

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
        let myTehai = event.tehais[playerId]
        for tile in myTehai where tile != .unknown {
            addTile(tile)
        }

        // 設置寶牌
        doraIndicators.append(event.doraMarker)
        updateDoraFactor()

        // 計算向聽
        updateShanten()

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

            // 更新向聽
            updateShanten()
            updateWaits()

            // 計算可用動作
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
        let isDora = isDoraIndicator(tile)
        let sutehai = Sutehai(
            tile: tile,
            isDora: isDora,
            isTedashi: !event.tsumogiri,
            isRiichi: event.riichi ?? false
        )
        let kawaItem = KawaItem(sutehai: sutehai)
        kawa[relActor].append(kawaItem)
        kawaOverview[relActor].append(tile)
        lastTedashis[relActor] = sutehai
        lastKawaTile = tile

        markTileSeen(tile)

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

            // 重置立直後的狀態
            if riichiDeclared[0] && !riichiAccepted[0] {
                riichiSutehais[0] = sutehai
            }

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
        kyotaku += 1

        // 開啟一發
        if relActor == 0 {
            atIppatsu = true
        }
    }

    private func handleChi(_ event: ChiEvent) {
        let relActor = toRelative(event.actor)
        let relTarget = toRelative(event.target)

        // 記錄副露
        let meld = [event.pai] + event.consumed
        fuuroOverview[relActor].append(meld)

        // 更新河 (被吃的牌)
        if let lastItem = kawa[relTarget].last {
            let chiPon = ChiPon(consumed: event.consumed, targetTile: event.pai)
            let newItem = KawaItem(sutehai: lastItem.sutehai, chiPon: chiPon, kan: lastItem.kan)
            kawa[relTarget][kawa[relTarget].count - 1] = newItem
        }

        if relActor == 0 {
            // 自己吃
            removeTile(event.consumed[0])
            removeTile(event.consumed[1])
            isMenzen = false

            // 記錄吃的面子
            let minIdx = min(event.consumed[0].deaka.index, event.consumed[1].deaka.index, event.pai.deaka.index)
            chis.append(minIdx)

            tehaiLenDiv3 = max(0, tehaiLenDiv3 - 1)

            // 需要打牌
            lastCans.canDiscard = true
        }
    }

    private func handlePon(_ event: PonEvent) {
        let relActor = toRelative(event.actor)
        let relTarget = toRelative(event.target)

        // 記錄副露
        let meld = [event.pai] + event.consumed
        fuuroOverview[relActor].append(meld)

        // 更新河
        if let lastItem = kawa[relTarget].last {
            let chiPon = ChiPon(consumed: event.consumed, targetTile: event.pai)
            let newItem = KawaItem(sutehai: lastItem.sutehai, chiPon: chiPon, kan: lastItem.kan)
            kawa[relTarget][kawa[relTarget].count - 1] = newItem
        }

        if relActor == 0 {
            // 自己碰
            removeTile(event.consumed[0])
            removeTile(event.consumed[1])
            isMenzen = false

            pons.append(event.pai.deaka.index)

            tehaiLenDiv3 = max(0, tehaiLenDiv3 - 1)

            // 需要打牌
            lastCans.canDiscard = true
        }
    }

    private func handleDaiminkan(_ event: DaiminkanEvent) {
        let relActor = toRelative(event.actor)
        let relTarget = toRelative(event.target)

        // 記錄副露
        let meld = [event.pai] + event.consumed
        fuuroOverview[relActor].append(meld)

        // 更新河
        if let lastItem = kawa[relTarget].last {
            let newItem = KawaItem(sutehai: lastItem.sutehai, chiPon: lastItem.chiPon, kan: meld)
            kawa[relTarget][kawa[relTarget].count - 1] = newItem
        }

        kansOnBoard += 1

        if relActor == 0 {
            // 自己大明槓
            removeTile(event.consumed[0])
            removeTile(event.consumed[1])
            removeTile(event.consumed[2])
            isMenzen = false

            minkans.append(event.pai.deaka.index)

            // 嶺上狀態
            atRinshan = true
        }
    }

    private func handleAnkan(_ event: AnkanEvent) {
        let relActor = toRelative(event.actor)

        // 記錄暗槓
        ankanOverview[relActor].append(event.consumed.map { $0.deaka })

        kansOnBoard += 1

        if relActor == 0 {
            // 自己暗槓
            for tile in event.consumed {
                removeTile(tile)
            }

            let idx = event.consumed[0].deaka.index
            ankans.append(idx)

            // 嶺上狀態
            atRinshan = true
        }
    }

    private func handleKakan(_ event: KakanEvent) {
        let relActor = toRelative(event.actor)

        // 更新副露
        if relActor == 0 {
            removeTile(event.pai)

            // 更新碰為槓
            if let idx = pons.firstIndex(of: event.pai.deaka.index) {
                pons.remove(at: idx)
                minkans.append(event.pai.deaka.index)
            }

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

        // 檢查自摸
        if shanten == -1 && !atFuriten {
            lastCans.canTsumoAgari = true
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
        return shanten == 0
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
