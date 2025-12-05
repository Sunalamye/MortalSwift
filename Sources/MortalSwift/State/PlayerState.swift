//
//  PlayerState.swift
//  MortalSwift
//
//  遊戲狀態管理 - 完全用 Swift 實現
//

import Foundation

/// 玩家遊戲狀態
public final class PlayerState: @unchecked Sendable {

    // MARK: - Constants

    public static let actionSpace = 46
    public static let obsChannels = 1012  // Version 4
    public static let obsWidth = 34

    // MARK: - Identity & Context

    /// 玩家座位 (0-3)
    public let playerId: Int
    /// 模型版本
    public let version: Int

    // MARK: - Round Context

    /// 場風
    public var bakaze: Tile = .east
    /// 自風
    public var jikaze: Tile = .east
    /// 局數 (0-3)
    public var kyoku: Int = 0
    /// 本場
    public var honba: Int = 0
    /// 立直棒數
    public var kyotaku: Int = 0
    /// 分數 (相對座位，index 0 = 自己)
    public var scores: [Int] = [25000, 25000, 25000, 25000]
    /// 排名 (1-4)
    public var rank: Int = 1
    /// 莊家座位 (相對)
    public var oya: Int = 0
    /// 是否為 All Last
    public var isAllLast: Bool = false

    // MARK: - Hand Management

    /// 手牌計數 (34 張，不含紅寶牌)
    public var tehai: [Int] = [Int](repeating: 0, count: 34)
    /// 手中的紅寶牌 [5mr, 5pr, 5sr]
    public var akasInHand: [Bool] = [false, false, false]
    /// 已見的紅寶牌
    public var akasSeen: [Bool] = [false, false, false]

    // MARK: - Kawa (Discard Piles)

    /// 各家的河 (相對座位)
    public var kawa: [[KawaItem]] = [[], [], [], []]
    /// 河概覽 (只有牌)
    public var kawaOverview: [[Tile]] = [[], [], [], []]
    /// 最後的手切牌
    public var lastTedashis: [Sutehai?] = [nil, nil, nil, nil]
    /// 立直宣言牌
    public var riichiSutehais: [Sutehai?] = [nil, nil, nil, nil]

    // MARK: - Melds

    /// 副露概覽 (每個副露是一組牌)
    public var fuuroOverview: [[[Tile]]] = [[], [], [], []]
    /// 暗槓概覽 (每家的暗槓列表)
    public var ankanOverview: [[[Tile]]] = [[], [], [], []]
    /// 吃 (deaka 後的索引)
    public var chis: [Int] = []
    /// 碰 (deaka 後的索引)
    public var pons: [Int] = []
    /// 大明槓 (deaka 後的索引)
    public var minkans: [Int] = []
    /// 暗槓 (deaka 後的索引)
    public var ankans: [Int] = []

    // MARK: - Status Flags

    /// 立直宣言
    public var riichiDeclared: [Bool] = [false, false, false, false]
    /// 立直成立
    public var riichiAccepted: [Bool] = [false, false, false, false]
    /// 當前回合玩家
    public var atTurn: Int = 0
    /// 剩餘牌數
    public var tilesLeft: Int = 70

    // MARK: - Hand Analysis

    /// 向聽數
    public var shanten: Int = 6
    /// 是否門前
    public var isMenzen: Bool = true
    /// 聽牌 (可和的牌)
    public var waits: [Bool] = [Bool](repeating: false, count: 34)
    /// 寶牌係數
    public var doraFactor: [Int] = [Int](repeating: 0, count: 34)
    /// 已見的牌數
    public var tilesSeen: [Int] = [Int](repeating: 0, count: 34)
    /// 禁止打出的牌 (振聽等)
    public var forbiddenTiles: [Bool] = [Bool](repeating: false, count: 34)
    /// 已打過的牌
    public var discardedTiles: [Bool] = [Bool](repeating: false, count: 34)

    // MARK: - Dora

    /// 寶牌指示牌
    public var doraIndicators: [Tile] = []
    /// 持有的寶牌數 (各類)
    public var dorasOwned: [Int] = [0, 0, 0, 0]
    /// 已見的寶牌數
    public var dorasSeen: Int = 0

    // MARK: - Action State

    /// 可用動作
    public var lastCans: ActionCandidate = ActionCandidate()
    /// 可暗槓的牌
    public var ankanCandidates: [Tile] = []
    /// 可加槓的牌
    public var kakanCandidates: [Tile] = []
    /// 可吃的組合
    public var chiCandidates: [[Tile]] = []
    /// 可碰的組合
    public var ponCandidates: [[Tile]] = []

    // MARK: - Special Conditions

    /// 可以 W 立直
    public var canWRiichi: Bool = false
    /// 是 W 立直
    public var isWRiichi: Bool = false
    /// 在嶺上
    public var atRinshan: Bool = false
    /// 一發狀態
    public var atIppatsu: Bool = false
    /// 振聽狀態
    public var atFuriten: Bool = false

    // MARK: - Turn Tracking

    /// 最後自摸的牌
    public var lastSelfTsumo: Tile? = nil
    /// 最後河底牌
    public var lastKawaTile: Tile? = nil
    /// 場上的槓數
    public var kansOnBoard: Int = 0

    // MARK: - Intermediate State

    /// 中間槓選擇
    public var intermediateKan: [Tile] = []
    /// 中間吃碰選擇
    public var intermediateChiPon: ChiPon? = nil
    /// 手牌數 / 3
    public var tehaiLenDiv3: Int = 4

    // MARK: - Initialization

    public init(playerId: Int, version: Int = 4) {
        self.playerId = playerId
        self.version = version
    }

    // MARK: - Reset

    /// 重置為新局狀態
    public func reset() {
        bakaze = .east
        jikaze = .east
        kyoku = 0
        honba = 0
        kyotaku = 0
        scores = [25000, 25000, 25000, 25000]
        rank = 1
        oya = 0
        isAllLast = false

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
        atTurn = 0
        tilesLeft = 70

        shanten = 6
        isMenzen = true
        waits = [Bool](repeating: false, count: 34)
        doraFactor = [Int](repeating: 0, count: 34)
        tilesSeen = [Int](repeating: 0, count: 34)
        forbiddenTiles = [Bool](repeating: false, count: 34)
        discardedTiles = [Bool](repeating: false, count: 34)

        doraIndicators = []
        dorasOwned = [0, 0, 0, 0]
        dorasSeen = 0

        lastCans = ActionCandidate()
        ankanCandidates = []
        kakanCandidates = []
        chiCandidates = []
        ponCandidates = []

        canWRiichi = false
        isWRiichi = false
        atRinshan = false
        atIppatsu = false
        atFuriten = false

        lastSelfTsumo = nil
        lastKawaTile = nil
        kansOnBoard = 0

        intermediateKan = []
        intermediateChiPon = nil
        tehaiLenDiv3 = 4
    }

    // MARK: - Hand Operations

    /// 加入一張牌到手牌
    public func addTile(_ tile: Tile) {
        let idx = tile.deaka.index
        guard idx >= 0 && idx < 34 else { return }

        tehai[idx] += 1

        // 記錄紅寶牌
        if tile.isRed {
            switch tile {
            case .man(5, red: true): akasInHand[0] = true
            case .pin(5, red: true): akasInHand[1] = true
            case .sou(5, red: true): akasInHand[2] = true
            default: break
            }
        }
    }

    /// 從手牌移除一張牌
    public func removeTile(_ tile: Tile) {
        let idx = tile.deaka.index
        guard idx >= 0 && idx < 34, tehai[idx] > 0 else { return }

        tehai[idx] -= 1

        // 處理紅寶牌
        if tile.isRed {
            switch tile {
            case .man(5, red: true): akasInHand[0] = false
            case .pin(5, red: true): akasInHand[1] = false
            case .sou(5, red: true): akasInHand[2] = false
            default: break
            }
        }
    }

    /// 獲取手牌列表 (包含紅寶牌資訊)
    public func getHandTiles() -> [Tile] {
        var tiles: [Tile] = []

        for idx in 0..<34 {
            guard let baseTile = Tile.fromIndex(idx) else { continue }
            var count = tehai[idx]

            // 處理 5 的紅寶牌
            if idx == 4 && akasInHand[0] && count > 0 {  // 5m
                tiles.append(.man(5, red: true))
                count -= 1
            }
            if idx == 13 && akasInHand[1] && count > 0 {  // 5p
                tiles.append(.pin(5, red: true))
                count -= 1
            }
            if idx == 22 && akasInHand[2] && count > 0 {  // 5s
                tiles.append(.sou(5, red: true))
                count -= 1
            }

            for _ in 0..<count {
                tiles.append(baseTile)
            }
        }

        return tiles
    }

    /// 計算手牌總數
    public func getHandCount() -> Int {
        tehai.reduce(0, +)
    }

    // MARK: - Dora Calculation

    /// 計算寶牌
    public func updateDoraFactor() {
        doraFactor = [Int](repeating: 0, count: 34)

        for indicator in doraIndicators {
            let doraTile = indicator.next
            let idx = doraTile.deaka.index
            if idx >= 0 && idx < 34 {
                doraFactor[idx] += 1
            }
        }
    }

    /// 計算持有的寶牌數
    public func countOwnedDoras() -> Int {
        var count = 0
        for idx in 0..<34 {
            count += tehai[idx] * doraFactor[idx]
        }
        // 紅寶牌
        if akasInHand[0] { count += 1 }
        if akasInHand[1] { count += 1 }
        if akasInHand[2] { count += 1 }
        return count
    }

    // MARK: - Shanten Calculation

    /// 更新向聽數
    public func updateShanten() {
        shanten = ShantenCalculator.calcAll(tehai: tehai, lenDiv3: tehaiLenDiv3)
    }

    /// 計算聽牌
    public func updateWaits() {
        waits = [Bool](repeating: false, count: 34)

        guard shanten == 0 else { return }

        // 嘗試加入每張牌看是否能和
        for idx in 0..<34 {
            guard tehai[idx] < 4 else { continue }

            var testTehai = tehai
            testTehai[idx] += 1

            let newShanten = ShantenCalculator.calcAll(tehai: testTehai, lenDiv3: tehaiLenDiv3)
            if newShanten == -1 {
                waits[idx] = true
            }
        }
    }

    // MARK: - Relative Position

    /// 將絕對座位轉換為相對座位
    public func toRelative(_ seat: Int) -> Int {
        return (seat - playerId + 4) % 4
    }

    /// 將相對座位轉換為絕對座位
    public func toAbsolute(_ relative: Int) -> Int {
        return (relative + playerId) % 4
    }
}

// MARK: - Constants

public extension PlayerState {
    /// 動作索引常量
    enum ActionIndex {
        // 0-33: 打牌
        public static let discardStart = 0
        public static let discardEnd = 33

        // 34-36: 保留 (3麻用)
        public static let reserved34 = 34
        public static let reserved35 = 35
        public static let reserved36 = 36

        // 37: 立直
        public static let riichi = 37

        // 38-40: 吃
        public static let chiLow = 38
        public static let chiMid = 39
        public static let chiHigh = 40

        // 41: 碰
        public static let pon = 41

        // 42: 槓
        public static let kan = 42

        // 43: 和
        public static let hora = 43

        // 44: 流局
        public static let ryukyoku = 44

        // 45: 跳過
        public static let pass = 45
    }
}
