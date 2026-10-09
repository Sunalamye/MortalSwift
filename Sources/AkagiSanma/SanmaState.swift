import Foundation

public struct SanmaMeld: Equatable, Sendable {
    public enum Kind: Sendable { case pon, chi, daiminkan, ankan, kakan }

    public var kind: Kind
    public var tiles: [UInt8]
    public var opened: Bool { kind != .ankan }
}

public struct SanmaPlayer: Equatable, Sendable {
    public var hand: [UInt8] = []
    public var melds: [SanmaMeld] = []
    /// 被叫走的牌仍留在河裡（riichienv 不移除）。
    public var discards: [UInt8] = []
    public var riichiStage = false
    public var riichiDeclared = false
    public var score = 0
    public var kitaCount = 0
    var forbidden: [UInt8] = []
}

/// 對應 riichienv `GameState3P` 的 mjai 重播路徑（`apply_mjai_event`），
/// 加上 native_bot 的 `mjai_compat`（nukidora、4 座位截 3）與搶槓窗口（`chankan.rs`）。
/// `seat` 是決策者，只有搶槓窗口與合法動作列舉依它而定。
public struct SanmaState: Sendable {
    public enum Phase: Sendable { case act, response }

    public let seat: Int
    public private(set) var players = Array(repeating: SanmaPlayer(), count: 3)
    public private(set) var phase = Phase.act
    /// nil 表示沒有人該行動（等下一次摸牌）。
    public private(set) var currentPlayer: Int?
    public private(set) var activePlayers: [Int] = []
    public private(set) var claims: [Int: [SanmaAction]] = [:]
    public private(set) var lastDiscard: (seat: Int, tile: UInt8)?
    public private(set) var drawnTile: UInt8?
    public private(set) var doraIndicators: [UInt8] = []
    public private(set) var roundWind = 0
    public private(set) var oya = 0
    public private(set) var honba = 0
    public private(set) var riichiSticks = 0
    public private(set) var kyokuIndex = 0
    /// 三麻 108 張扣掉配牌 39 張與王牌 14 張。
    public private(set) var drawable = 0
    public private(set) var isDone = true

    public init(seat: Int) {
        self.seat = seat
    }

    /// 解析一行 mjai JSON；空行、壞 JSON、不認得的事件回傳 false。
    @discardableResult
    public mutating func apply(line: String) -> Bool {
        guard let data = line.data(using: .utf8),
              let event = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return false }
        return apply(event)
    }

    /// 缺必要欄位或 actor 不在 0...2 時不套用並回傳 false。
    @discardableResult
    public mutating func apply(_ e: [String: Any]) -> Bool {
        // riichienv 把解析失敗的牌當成 tid 0。
        func tile(_ key: String) -> UInt8? { (e[key] as? String).map { SanmaTiles.tid(mjai: $0) ?? 0 } }
        func tiles(_ key: String) -> [UInt8]? { (e[key] as? [String])?.map { SanmaTiles.tid(mjai: $0) ?? 0 } }
        let actor = (e["actor"] as? Int).flatMap { (0..<3).contains($0) ? $0 : nil }

        switch e["type"] as? String {
        case "start_game":
            currentPlayer = nil
            activePlayers = []
        case "start_kyoku":
            guard let kyoku = e["kyoku"] as? Int, let honba = e["honba"] as? Int,
                  let sticks = (e["kyoutaku"] ?? e["kyotaku"]) as? Int,
                  let oya = e["oya"] as? Int, (0..<3).contains(oya),
                  let scores = e["scores"] as? [Int], scores.count >= 3,
                  let dora = tile("dora_marker"), let tehais = e["tehais"] as? [[String]]
            else { return false }
            roundWind = ["S": 1, "W": 2, "N": 3][e["bakaze"] as? String ?? ""] ?? 0
            self.oya = oya
            kyokuIndex = max(kyoku - 1, 0)
            self.honba = honba
            riichiSticks = sticks
            currentPlayer = nil
            isDone = false
            phase = .act
            activePlayers = []
            lastDiscard = nil
            claims = [:]
            drawnTile = nil
            drawable = 108 - 39 - 14
            doraIndicators = [dora]
            players = (0..<3).map { i in
                var p = SanmaPlayer()
                p.score = scores[i]
                p.hand = i < tehais.count ? tehais[i].map { SanmaTiles.tid(mjai: $0) ?? 0 }.sorted() : []
                return p
            }
        case "tsumo":
            guard let a = actor, let pai = e["pai"] as? String else { return false }
            let t = SanmaTiles.tid(mjai: pai)
            players[a].hand.append(t ?? 0)
            players[a].hand.sort()
            players[a].forbidden = []
            currentPlayer = a
            // 他家摸牌是 `?` 時不留假 1m 在摸牌面（Rust 會留 tid 0，訓練資料是全知牌譜）。
            drawnTile = t
            drawable = max(drawable - 1, 0)
            phase = .act
            activePlayers = [a]
        case "dahai":
            guard let a = actor, let t = tile("pai") else { return false }
            remove([t], from: a)
            players[a].discards.append(t)
            if players[a].riichiStage {
                players[a].riichiDeclared = true
                players[a].riichiStage = false
            }
            lastDiscard = (a, t)
            drawnTile = nil
            openClaims(from: a, tile: t, ronOnly: false)
        case let type? where type == "pon" || type == "chi":
            guard let a = actor, let t = tile("pai"), let c = tiles("consumed"), c.count >= 2 else { return false }
            remove(Array(c.prefix(2)), from: a)
            players[a].melds.append(SanmaMeld(kind: type == "pon" ? .pon : .chi, tiles: [t] + c.prefix(2)))
            if type == "pon" { players[a].forbidden = [t] }
            drawnTile = nil
            take(a)
        case "kan", "daiminkan":
            guard let a = actor, let t = tile("pai"), let c = tiles("consumed"), !c.isEmpty else { return false }
            remove(c, from: a)
            players[a].melds.append(SanmaMeld(kind: .daiminkan, tiles: [t] + c))
            take(a)
        case "ankan":
            guard let a = actor, let c = tiles("consumed"), !c.isEmpty else { return false }
            remove(c, from: a)
            players[a].melds.append(SanmaMeld(kind: .ankan, tiles: c))
            take(a)
        case "kakan":
            guard let a = actor, let t = tile("pai") else { return false }
            remove([t], from: a)
            if let i = players[a].melds.firstIndex(where: { $0.kind == .pon && $0.tiles[0] / 4 == t / 4 }) {
                players[a].melds[i].kind = .kakan
                players[a].melds[i].tiles.append(t)
            }
            take(a)
            openChankan(actor: a, tile: t)
        case "reach":
            guard let a = actor else { return false }
            players[a].riichiStage = true
        case "reach_accepted":
            guard let a = actor else { return false }
            players[a].riichiDeclared = true
            players[a].score -= 1000
            riichiSticks += 1
        case "dora":
            guard let t = tile("dora_marker") else { return false }
            doraIndicators.append(t)
        case "kita", "nukidora":
            guard let a = actor else { return false }
            let north = players[a].hand.first { $0 / 4 == 30 } ?? 120
            remove([north], from: a)
            players[a].kitaCount += 1
            openClaims(from: a, tile: north, ronOnly: true)
        case "hora", "ryukyoku", "end_kyoku":
            isDone = true
        case "end_game":
            break
        default:
            return false
        }
        return true
    }

    private mutating func remove(_ tiles: [UInt8], from seat: Int) {
        for t in tiles {
            if let i = players[seat].hand.firstIndex(of: t) { players[seat].hand.remove(at: i) }
        }
    }

    private mutating func take(_ seat: Int) {
        currentPlayer = seat
        phase = .act
        activePlayers = [seat]
    }

    private mutating func openClaims(from actor: Int, tile: UInt8, ronOnly: Bool) {
        claims = [:]
        for i in 0..<3 where i != actor {
            let c = claimActions(for: i, tile: tile).filter { !ronOnly || $0.kind == .ron }
            if !c.isEmpty { claims[i] = c }
        }
        activePlayers = claims.keys.sorted()
        phase = activePlayers.isEmpty ? .act : .response
        currentPlayer = activePlayers.isEmpty ? nil : actor
    }

    /// 他家加槓的牌讓本家成和且非振聽時，開 ron 窗口並把該牌當成最後捨牌（`chankan.rs`）。
    /// 搶槓本身是役，所以形狀成和即等同 Rust 的有役判定。
    private mutating func openChankan(actor: Int, tile: UInt8) {
        let me = players[seat]
        let waits = Self.waits(me.hand, me.melds)
        guard actor != seat, !isDone,
              !me.discards.contains(where: { waits.contains($0 / 4) }),
              Self.completes(me.hand, me.melds, with: tile)
        else { return }
        claims[seat] = [SanmaAction(.ron, tile: tile)]
        phase = .response
        activePlayers = [seat]
        lastDiscard = (actor, tile)
    }
}
