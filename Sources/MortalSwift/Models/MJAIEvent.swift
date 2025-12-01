//
//  MJAIEvent.swift
//  MortalSwift
//
//  MJAI 協議事件的強類型表示
//

import Foundation

// MARK: - MJAIEvent

/// MJAI 協議事件
public enum MJAIEvent: Sendable {
    /// 遊戲開始
    case startGame(StartGameEvent)
    /// 遊戲結束
    case endGame
    /// 局開始
    case startKyoku(StartKyokuEvent)
    /// 局結束
    case endKyoku
    /// 摸牌
    case tsumo(TsumoEvent)
    /// 打牌
    case dahai(DahaiEvent)
    /// 立直宣告
    case reach(ReachEvent)
    /// 立直成立
    case reachAccepted(ReachAcceptedEvent)
    /// 吃
    case chi(ChiEvent)
    /// 碰
    case pon(PonEvent)
    /// 大明槓
    case daiminkan(DaiminkanEvent)
    /// 暗槓
    case ankan(AnkanEvent)
    /// 加槓
    case kakan(KakanEvent)
    /// 新寶牌
    case dora(DoraEvent)
    /// 北抜き (三麻)
    case nukidora(NukidoraEvent)
    /// 和了
    case hora(HoraEvent)
    /// 流局
    case ryukyoku(RyukyokuEvent)
}

// MARK: - Event Structs

public struct StartGameEvent: Codable, Sendable {
    /// 玩家名稱
    public let names: [String]
    /// 遊戲規則 (optional)
    public let rule: GameRule?

    public init(names: [String], rule: GameRule? = nil) {
        self.names = names
        self.rule = rule
    }
}

public struct GameRule: Codable, Sendable {
    /// 是否為三麻
    public let sanma: Bool?
    /// 起始點數
    public let startingPoints: Int?

    public init(sanma: Bool? = nil, startingPoints: Int? = nil) {
        self.sanma = sanma
        self.startingPoints = startingPoints
    }
}

public struct StartKyokuEvent: Codable, Sendable {
    /// 場風 (E/S/W/N)
    public let bakaze: Wind
    /// 局數 (0-3)
    public let kyoku: Int
    /// 本場
    public let honba: Int
    /// 立直棒數
    public let kyotaku: Int
    /// 莊家座位 (0-3)
    public let oya: Int
    /// 寶牌指示牌
    public let doraMarker: Tile
    /// 各家分數
    public let scores: [Int]
    /// 各家手牌
    public let tehais: [[Tile]]

    public init(
        bakaze: Wind,
        kyoku: Int,
        honba: Int,
        kyotaku: Int,
        oya: Int,
        doraMarker: Tile,
        scores: [Int],
        tehais: [[Tile]]
    ) {
        self.bakaze = bakaze
        self.kyoku = kyoku
        self.honba = honba
        self.kyotaku = kyotaku
        self.oya = oya
        self.doraMarker = doraMarker
        self.scores = scores
        self.tehais = tehais
    }
}

public struct TsumoEvent: Codable, Sendable {
    /// 摸牌者座位
    public let actor: Int
    /// 摸到的牌
    public let pai: Tile

    public init(actor: Int, pai: Tile) {
        self.actor = actor
        self.pai = pai
    }
}

public struct DahaiEvent: Codable, Sendable {
    /// 打牌者座位
    public let actor: Int
    /// 打出的牌
    public let pai: Tile
    /// 是否為摸切
    public let tsumogiri: Bool
    /// 是否為立直宣告後打牌
    public let riichi: Bool?

    public init(actor: Int, pai: Tile, tsumogiri: Bool, riichi: Bool? = nil) {
        self.actor = actor
        self.pai = pai
        self.tsumogiri = tsumogiri
        self.riichi = riichi
    }
}

public struct ReachEvent: Codable, Sendable {
    /// 立直者座位
    public let actor: Int

    public init(actor: Int) {
        self.actor = actor
    }
}

public struct ReachAcceptedEvent: Codable, Sendable {
    /// 立直者座位
    public let actor: Int

    public init(actor: Int) {
        self.actor = actor
    }
}

public struct ChiEvent: Codable, Sendable {
    /// 吃牌者座位
    public let actor: Int
    /// 被吃者座位
    public let target: Int
    /// 被吃的牌
    public let pai: Tile
    /// 手中用於吃的兩張牌
    public let consumed: [Tile]

    public init(actor: Int, target: Int, pai: Tile, consumed: [Tile]) {
        self.actor = actor
        self.target = target
        self.pai = pai
        self.consumed = consumed
    }
}

public struct PonEvent: Codable, Sendable {
    /// 碰牌者座位
    public let actor: Int
    /// 被碰者座位
    public let target: Int
    /// 被碰的牌
    public let pai: Tile
    /// 手中用於碰的兩張牌
    public let consumed: [Tile]

    public init(actor: Int, target: Int, pai: Tile, consumed: [Tile]) {
        self.actor = actor
        self.target = target
        self.pai = pai
        self.consumed = consumed
    }
}

public struct DaiminkanEvent: Codable, Sendable {
    /// 槓牌者座位
    public let actor: Int
    /// 被槓者座位
    public let target: Int
    /// 被槓的牌
    public let pai: Tile
    /// 手中用於槓的三張牌
    public let consumed: [Tile]

    public init(actor: Int, target: Int, pai: Tile, consumed: [Tile]) {
        self.actor = actor
        self.target = target
        self.pai = pai
        self.consumed = consumed
    }
}

public struct AnkanEvent: Codable, Sendable {
    /// 暗槓者座位
    public let actor: Int
    /// 用於暗槓的四張牌
    public let consumed: [Tile]

    public init(actor: Int, consumed: [Tile]) {
        self.actor = actor
        self.consumed = consumed
    }
}

public struct KakanEvent: Codable, Sendable {
    /// 加槓者座位
    public let actor: Int
    /// 加槓的牌
    public let pai: Tile
    /// 原碰的牌 (用於識別是哪組碰)
    public let consumed: [Tile]

    public init(actor: Int, pai: Tile, consumed: [Tile]) {
        self.actor = actor
        self.pai = pai
        self.consumed = consumed
    }
}

public struct DoraEvent: Codable, Sendable {
    /// 新的寶牌指示牌
    public let doraMarker: Tile

    public init(doraMarker: Tile) {
        self.doraMarker = doraMarker
    }
}

public struct NukidoraEvent: Codable, Sendable {
    /// 抜きドラ者座位
    public let actor: Int
    /// 被抜きドラ的牌 (北)
    public let pai: Tile

    public init(actor: Int, pai: Tile) {
        self.actor = actor
        self.pai = pai
    }
}

public struct HoraEvent: Codable, Sendable {
    /// 和了者座位
    public let actor: Int
    /// 放銃者座位 (自摸時等於 actor)
    public let target: Int
    /// 和了牌
    public let pai: Tile?
    /// 點數變動
    public let deltas: [Int]?
    /// 裏寶牌
    public let uraDoras: [Tile]?

    public init(actor: Int, target: Int, pai: Tile? = nil, deltas: [Int]? = nil, uraDoras: [Tile]? = nil) {
        self.actor = actor
        self.target = target
        self.pai = pai
        self.deltas = deltas
        self.uraDoras = uraDoras
    }
}

public struct RyukyokuEvent: Codable, Sendable {
    /// 點數變動
    public let deltas: [Int]?
    /// 流局原因
    public let reason: String?

    public init(deltas: [Int]? = nil, reason: String? = nil) {
        self.deltas = deltas
        self.reason = reason
    }
}

// MARK: - Codable

extension MJAIEvent: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        // StartGame
        case names, rule
        // StartKyoku
        case bakaze, kyoku, honba, kyotaku, oya
        case doraMarker = "dora_marker"
        case scores, tehais
        // Tsumo/Dahai
        case actor, pai, tsumogiri, riichi
        // Chi/Pon/Kan
        case target, consumed
        // Hora
        case deltas
        case uraDoras = "ura_doras"
        // Ryukyoku
        case reason
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "start_game":
            let names = try container.decode([String].self, forKey: .names)
            let rule = try container.decodeIfPresent(GameRule.self, forKey: .rule)
            self = .startGame(StartGameEvent(names: names, rule: rule))

        case "end_game":
            self = .endGame

        case "start_kyoku":
            let bakazeStr = try container.decode(String.self, forKey: .bakaze)
            guard let bakaze = Wind(rawValue: bakazeStr) else {
                throw DecodingError.dataCorruptedError(forKey: .bakaze, in: container, debugDescription: "Invalid wind")
            }
            let kyoku = try container.decode(Int.self, forKey: .kyoku)
            let honba = try container.decode(Int.self, forKey: .honba)
            let kyotaku = try container.decode(Int.self, forKey: .kyotaku)
            let oya = try container.decode(Int.self, forKey: .oya)
            let doraMarker = try container.decode(Tile.self, forKey: .doraMarker)
            let scores = try container.decode([Int].self, forKey: .scores)
            let tehais = try container.decode([[Tile]].self, forKey: .tehais)
            self = .startKyoku(StartKyokuEvent(
                bakaze: bakaze, kyoku: kyoku, honba: honba, kyotaku: kyotaku,
                oya: oya, doraMarker: doraMarker, scores: scores, tehais: tehais
            ))

        case "end_kyoku":
            self = .endKyoku

        case "tsumo":
            let actor = try container.decode(Int.self, forKey: .actor)
            let pai = try container.decode(Tile.self, forKey: .pai)
            self = .tsumo(TsumoEvent(actor: actor, pai: pai))

        case "dahai":
            let actor = try container.decode(Int.self, forKey: .actor)
            let pai = try container.decode(Tile.self, forKey: .pai)
            let tsumogiri = try container.decodeIfPresent(Bool.self, forKey: .tsumogiri) ?? false
            let riichi = try container.decodeIfPresent(Bool.self, forKey: .riichi)
            self = .dahai(DahaiEvent(actor: actor, pai: pai, tsumogiri: tsumogiri, riichi: riichi))

        case "reach":
            let actor = try container.decode(Int.self, forKey: .actor)
            self = .reach(ReachEvent(actor: actor))

        case "reach_accepted":
            let actor = try container.decode(Int.self, forKey: .actor)
            self = .reachAccepted(ReachAcceptedEvent(actor: actor))

        case "chi":
            let actor = try container.decode(Int.self, forKey: .actor)
            let target = try container.decode(Int.self, forKey: .target)
            let pai = try container.decode(Tile.self, forKey: .pai)
            let consumed = try container.decode([Tile].self, forKey: .consumed)
            self = .chi(ChiEvent(actor: actor, target: target, pai: pai, consumed: consumed))

        case "pon":
            let actor = try container.decode(Int.self, forKey: .actor)
            let target = try container.decode(Int.self, forKey: .target)
            let pai = try container.decode(Tile.self, forKey: .pai)
            let consumed = try container.decode([Tile].self, forKey: .consumed)
            self = .pon(PonEvent(actor: actor, target: target, pai: pai, consumed: consumed))

        case "daiminkan":
            let actor = try container.decode(Int.self, forKey: .actor)
            let target = try container.decode(Int.self, forKey: .target)
            let pai = try container.decode(Tile.self, forKey: .pai)
            let consumed = try container.decode([Tile].self, forKey: .consumed)
            self = .daiminkan(DaiminkanEvent(actor: actor, target: target, pai: pai, consumed: consumed))

        case "ankan":
            let actor = try container.decode(Int.self, forKey: .actor)
            let consumed = try container.decode([Tile].self, forKey: .consumed)
            self = .ankan(AnkanEvent(actor: actor, consumed: consumed))

        case "kakan":
            let actor = try container.decode(Int.self, forKey: .actor)
            let pai = try container.decode(Tile.self, forKey: .pai)
            let consumed = try container.decode([Tile].self, forKey: .consumed)
            self = .kakan(KakanEvent(actor: actor, pai: pai, consumed: consumed))

        case "dora":
            let doraMarker = try container.decode(Tile.self, forKey: .doraMarker)
            self = .dora(DoraEvent(doraMarker: doraMarker))

        case "nukidora":
            let actor = try container.decode(Int.self, forKey: .actor)
            let pai = try container.decode(Tile.self, forKey: .pai)
            self = .nukidora(NukidoraEvent(actor: actor, pai: pai))

        case "hora":
            let actor = try container.decode(Int.self, forKey: .actor)
            let target = try container.decode(Int.self, forKey: .target)
            let pai = try container.decodeIfPresent(Tile.self, forKey: .pai)
            let deltas = try container.decodeIfPresent([Int].self, forKey: .deltas)
            let uraDoras = try container.decodeIfPresent([Tile].self, forKey: .uraDoras)
            self = .hora(HoraEvent(actor: actor, target: target, pai: pai, deltas: deltas, uraDoras: uraDoras))

        case "ryukyoku":
            let deltas = try container.decodeIfPresent([Int].self, forKey: .deltas)
            let reason = try container.decodeIfPresent(String.self, forKey: .reason)
            self = .ryukyoku(RyukyokuEvent(deltas: deltas, reason: reason))

        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown event type: \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .startGame(let event):
            try container.encode("start_game", forKey: .type)
            try container.encode(event.names, forKey: .names)
            try container.encodeIfPresent(event.rule, forKey: .rule)

        case .endGame:
            try container.encode("end_game", forKey: .type)

        case .startKyoku(let event):
            try container.encode("start_kyoku", forKey: .type)
            try container.encode(event.bakaze.rawValue, forKey: .bakaze)
            try container.encode(event.kyoku, forKey: .kyoku)
            try container.encode(event.honba, forKey: .honba)
            try container.encode(event.kyotaku, forKey: .kyotaku)
            try container.encode(event.oya, forKey: .oya)
            try container.encode(event.doraMarker, forKey: .doraMarker)
            try container.encode(event.scores, forKey: .scores)
            try container.encode(event.tehais, forKey: .tehais)

        case .endKyoku:
            try container.encode("end_kyoku", forKey: .type)

        case .tsumo(let event):
            try container.encode("tsumo", forKey: .type)
            try container.encode(event.actor, forKey: .actor)
            try container.encode(event.pai, forKey: .pai)

        case .dahai(let event):
            try container.encode("dahai", forKey: .type)
            try container.encode(event.actor, forKey: .actor)
            try container.encode(event.pai, forKey: .pai)
            try container.encode(event.tsumogiri, forKey: .tsumogiri)
            try container.encodeIfPresent(event.riichi, forKey: .riichi)

        case .reach(let event):
            try container.encode("reach", forKey: .type)
            try container.encode(event.actor, forKey: .actor)

        case .reachAccepted(let event):
            try container.encode("reach_accepted", forKey: .type)
            try container.encode(event.actor, forKey: .actor)

        case .chi(let event):
            try container.encode("chi", forKey: .type)
            try container.encode(event.actor, forKey: .actor)
            try container.encode(event.target, forKey: .target)
            try container.encode(event.pai, forKey: .pai)
            try container.encode(event.consumed, forKey: .consumed)

        case .pon(let event):
            try container.encode("pon", forKey: .type)
            try container.encode(event.actor, forKey: .actor)
            try container.encode(event.target, forKey: .target)
            try container.encode(event.pai, forKey: .pai)
            try container.encode(event.consumed, forKey: .consumed)

        case .daiminkan(let event):
            try container.encode("daiminkan", forKey: .type)
            try container.encode(event.actor, forKey: .actor)
            try container.encode(event.target, forKey: .target)
            try container.encode(event.pai, forKey: .pai)
            try container.encode(event.consumed, forKey: .consumed)

        case .ankan(let event):
            try container.encode("ankan", forKey: .type)
            try container.encode(event.actor, forKey: .actor)
            try container.encode(event.consumed, forKey: .consumed)

        case .kakan(let event):
            try container.encode("kakan", forKey: .type)
            try container.encode(event.actor, forKey: .actor)
            try container.encode(event.pai, forKey: .pai)
            try container.encode(event.consumed, forKey: .consumed)

        case .dora(let event):
            try container.encode("dora", forKey: .type)
            try container.encode(event.doraMarker, forKey: .doraMarker)

        case .nukidora(let event):
            try container.encode("nukidora", forKey: .type)
            try container.encode(event.actor, forKey: .actor)
            try container.encode(event.pai, forKey: .pai)

        case .hora(let event):
            try container.encode("hora", forKey: .type)
            try container.encode(event.actor, forKey: .actor)
            try container.encode(event.target, forKey: .target)
            try container.encodeIfPresent(event.pai, forKey: .pai)
            try container.encodeIfPresent(event.deltas, forKey: .deltas)
            try container.encodeIfPresent(event.uraDoras, forKey: .uraDoras)

        case .ryukyoku(let event):
            try container.encode("ryukyoku", forKey: .type)
            try container.encodeIfPresent(event.deltas, forKey: .deltas)
            try container.encodeIfPresent(event.reason, forKey: .reason)
        }
    }
}

// MARK: - Convenience

extension MJAIEvent {
    /// 事件類型名稱
    public var typeName: String {
        switch self {
        case .startGame: return "start_game"
        case .endGame: return "end_game"
        case .startKyoku: return "start_kyoku"
        case .endKyoku: return "end_kyoku"
        case .tsumo: return "tsumo"
        case .dahai: return "dahai"
        case .reach: return "reach"
        case .reachAccepted: return "reach_accepted"
        case .chi: return "chi"
        case .pon: return "pon"
        case .daiminkan: return "daiminkan"
        case .ankan: return "ankan"
        case .kakan: return "kakan"
        case .dora: return "dora"
        case .nukidora: return "nukidora"
        case .hora: return "hora"
        case .ryukyoku: return "ryukyoku"
        }
    }

    /// 轉換為 JSON 字串
    public func toJSONString() throws -> String {
        let encoder = JSONEncoder()
        let data = try encoder.encode(self)
        guard let string = String(data: data, encoding: .utf8) else {
            throw MortalError.encodingFailed
        }
        return string
    }

    /// 從 JSON 字串解析
    public static func fromJSONString(_ json: String) throws -> MJAIEvent {
        guard let data = json.data(using: .utf8) else {
            throw MortalError.decodingFailed
        }
        let decoder = JSONDecoder()
        return try decoder.decode(MJAIEvent.self, from: data)
    }
}
