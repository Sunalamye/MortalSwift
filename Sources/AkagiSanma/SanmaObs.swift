/// Akagi 自訂的三麻觀測編碼（非 riichienv `Observation::encode`），輸出 channel-major `[37 × 27]`。
/// 座位一律相對：index 0 是決策者，之後依序為下家、對家。
public struct SanmaSeat: Equatable, Sendable {
    public var discards: [UInt8] = []
    public var meldTiles: [UInt8] = []
    public var riichiDeclared = false
    public var riichiTile: UInt8?
    public var score: Int32 = 0
    public var kitaCount: UInt8 = 0

    public init() {}
}

public struct SanmaEncInput: Equatable, Sendable {
    public static let players = 3
    /// 自家 9 面 + 每家 5 組 + 全域 10 面 + 每家拔北 1 組 = 9 + 15 + 10 + 3 = 37。
    public static let channels = 9 + 5 * players + 10 + players
    public static let lastDiscardChannel = 9 + 5 * players

    public var hand: [UInt8] = []
    public var drawnTile: UInt8?
    /// 聽牌待牌，tile34。
    public var waits: [UInt8] = []
    public var isTenpai = false
    public var doraIndicators: [UInt8] = []
    public var seats: [SanmaSeat] = Array(repeating: SanmaSeat(), count: players)
    public var lastDiscard: UInt8?
    /// 0=東 1=南 2=西 3=北。
    public var roundWind: UInt8 = 0
    public var seatWind: UInt8 = 0
    public var honba: UInt8 = 0
    public var riichiSticks: UInt32 = 0
    public var turnCount: UInt32 = 0
    public var isDealer = false
    public var kyokuIndex: UInt8 = 0
    public var selfRiichi = false

    public init() {}

    /// `seats` 不是正好 3 家時回傳 nil。
    public func encode() -> [Float]? {
        guard seats.count == Self.players else { return nil }
        let t = SanmaTiles.count
        var buf = [Float](repeating: 0, count: Self.channels * t)
        var ch = 0

        func set(_ tid: UInt8?, _ v: Float = 1) {
            if let tid, let i = SanmaTiles.index(tid) { buf[ch * t + i] = v }
        }
        func add(_ tids: [UInt8]) {
            for tid in tids { if let i = SanmaTiles.index(tid) { buf[ch * t + i] += 0.25 } }
        }
        func fill(_ v: Float) {
            for i in 0..<t { buf[ch * t + i] = v }
        }
        func perSeat(_ body: (SanmaSeat) -> Void) {
            for seat in seats { body(seat); ch += 1 }
        }

        var counts = [UInt8](repeating: 0, count: t)
        for tid in hand { if let i = SanmaTiles.index(tid) { counts[i] += 1 } }
        for threshold in 1...4 {
            for i in 0..<t where counts[i] >= threshold { buf[ch * t + i] = 1 }
            ch += 1
        }
        for tid in hand where SanmaTiles.isAka(tid) { set(tid) }
        ch += 1
        set(drawnTile); ch += 1
        for w in waits where w < 34 { set(w * 4) }
        ch += 1
        add(doraIndicators); ch += 1
        add(doraIndicators.map { UInt8(SanmaTiles.nextDoraTile34(SanmaTiles.tile34($0)) * 4) }); ch += 1

        perSeat { add($0.discards) }
        perSeat { add($0.meldTiles) }
        perSeat { if $0.riichiDeclared { fill(1) } }
        perSeat { set($0.riichiTile) }
        // 夾在 [0, 4] 讓抽取端能用無號 u8 儲存。
        perSeat { fill(min(max(Float($0.score) / 50_000, 0), 4)) }

        assert(ch == Self.lastDiscardChannel)
        set(lastDiscard); ch += 1
        set((27 + min(roundWind, 3)) * 4); ch += 1
        set((27 + min(seatWind, 3)) * 4); ch += 1
        for v in [
            min(Float(honba) / 4, 2), min(Float(riichiSticks) / 4, 2), min(Float(turnCount) / 70, 1),
            isTenpai ? 1 : 0, isDealer ? 1 : 0, min(Float(kyokuIndex) / 8, 1), selfRiichi ? 1 : 0,
        ] as [Float] { fill(v); ch += 1 }
        perSeat { fill(min(Float($0.kitaCount) / 4, 1)) }

        assert(ch == Self.channels)
        return buf
    }
}
