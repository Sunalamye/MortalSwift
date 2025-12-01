//
//  MJAIAction.swift
//  MortalSwift
//
//  MJAI 協議動作的強類型表示 (Bot 回應)
//

import Foundation

// MARK: - MJAIAction

/// Bot 回應動作
public enum MJAIAction: Sendable {
    /// 打牌
    case dahai(DahaiAction)
    /// 立直
    case reach(ReachAction)
    /// 吃
    case chi(ChiAction)
    /// 碰
    case pon(PonAction)
    /// 大明槓
    case daiminkan(DaiminkanAction)
    /// 暗槓
    case ankan(AnkanAction)
    /// 加槓
    case kakan(KakanAction)
    /// 北抜き (三麻)
    case nukidora(NukidoraAction)
    /// 和了
    case hora(HoraAction)
    /// 九種九牌流局
    case ryukyoku(RyukyokuAction)
    /// 跳過 (不動作)
    case pass(PassAction)
}

// MARK: - Action Structs

public struct DahaiAction: Codable, Sendable {
    /// 打牌者座位
    public let actor: Int
    /// 打出的牌
    public let pai: Tile
    /// 是否為摸切
    public let tsumogiri: Bool

    public init(actor: Int, pai: Tile, tsumogiri: Bool) {
        self.actor = actor
        self.pai = pai
        self.tsumogiri = tsumogiri
    }
}

public struct ReachAction: Codable, Sendable {
    /// 立直者座位
    public let actor: Int

    public init(actor: Int) {
        self.actor = actor
    }
}

public struct ChiAction: Codable, Sendable {
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

public struct PonAction: Codable, Sendable {
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

public struct DaiminkanAction: Codable, Sendable {
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

public struct AnkanAction: Codable, Sendable {
    /// 暗槓者座位
    public let actor: Int
    /// 用於暗槓的四張牌
    public let consumed: [Tile]

    public init(actor: Int, consumed: [Tile]) {
        self.actor = actor
        self.consumed = consumed
    }
}

public struct KakanAction: Codable, Sendable {
    /// 加槓者座位
    public let actor: Int
    /// 加槓的牌
    public let pai: Tile
    /// 原碰的牌
    public let consumed: [Tile]

    public init(actor: Int, pai: Tile, consumed: [Tile]) {
        self.actor = actor
        self.pai = pai
        self.consumed = consumed
    }
}

public struct NukidoraAction: Codable, Sendable {
    /// 抜きドラ者座位
    public let actor: Int
    /// 被抜きドラ的牌 (北)
    public let pai: Tile

    public init(actor: Int, pai: Tile) {
        self.actor = actor
        self.pai = pai
    }
}

public struct HoraAction: Codable, Sendable {
    /// 和了者座位
    public let actor: Int
    /// 放銃者座位 (自摸時等於 actor)
    public let target: Int
    /// 和了牌 (optional)
    public let pai: Tile?

    public init(actor: Int, target: Int, pai: Tile? = nil) {
        self.actor = actor
        self.target = target
        self.pai = pai
    }
}

public struct RyukyokuAction: Codable, Sendable {
    /// 流局者座位
    public let actor: Int

    public init(actor: Int) {
        self.actor = actor
    }
}

public struct PassAction: Codable, Sendable {
    /// 跳過者座位
    public let actor: Int

    public init(actor: Int) {
        self.actor = actor
    }
}

// MARK: - Codable

extension MJAIAction: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case actor, target, pai, consumed, tsumogiri
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "dahai":
            let actor = try container.decode(Int.self, forKey: .actor)
            let pai = try container.decode(Tile.self, forKey: .pai)
            let tsumogiri = try container.decodeIfPresent(Bool.self, forKey: .tsumogiri) ?? false
            self = .dahai(DahaiAction(actor: actor, pai: pai, tsumogiri: tsumogiri))

        case "reach":
            let actor = try container.decode(Int.self, forKey: .actor)
            self = .reach(ReachAction(actor: actor))

        case "chi":
            let actor = try container.decode(Int.self, forKey: .actor)
            let target = try container.decode(Int.self, forKey: .target)
            let pai = try container.decode(Tile.self, forKey: .pai)
            let consumed = try container.decode([Tile].self, forKey: .consumed)
            self = .chi(ChiAction(actor: actor, target: target, pai: pai, consumed: consumed))

        case "pon":
            let actor = try container.decode(Int.self, forKey: .actor)
            let target = try container.decode(Int.self, forKey: .target)
            let pai = try container.decode(Tile.self, forKey: .pai)
            let consumed = try container.decode([Tile].self, forKey: .consumed)
            self = .pon(PonAction(actor: actor, target: target, pai: pai, consumed: consumed))

        case "daiminkan":
            let actor = try container.decode(Int.self, forKey: .actor)
            let target = try container.decode(Int.self, forKey: .target)
            let pai = try container.decode(Tile.self, forKey: .pai)
            let consumed = try container.decode([Tile].self, forKey: .consumed)
            self = .daiminkan(DaiminkanAction(actor: actor, target: target, pai: pai, consumed: consumed))

        case "ankan":
            let actor = try container.decode(Int.self, forKey: .actor)
            let consumed = try container.decode([Tile].self, forKey: .consumed)
            self = .ankan(AnkanAction(actor: actor, consumed: consumed))

        case "kakan":
            let actor = try container.decode(Int.self, forKey: .actor)
            let pai = try container.decode(Tile.self, forKey: .pai)
            let consumed = try container.decode([Tile].self, forKey: .consumed)
            self = .kakan(KakanAction(actor: actor, pai: pai, consumed: consumed))

        case "nukidora":
            let actor = try container.decode(Int.self, forKey: .actor)
            let pai = try container.decode(Tile.self, forKey: .pai)
            self = .nukidora(NukidoraAction(actor: actor, pai: pai))

        case "hora":
            let actor = try container.decode(Int.self, forKey: .actor)
            let target = try container.decode(Int.self, forKey: .target)
            let pai = try container.decodeIfPresent(Tile.self, forKey: .pai)
            self = .hora(HoraAction(actor: actor, target: target, pai: pai))

        case "ryukyoku":
            let actor = try container.decode(Int.self, forKey: .actor)
            self = .ryukyoku(RyukyokuAction(actor: actor))

        case "none":
            let actor = try container.decode(Int.self, forKey: .actor)
            self = .pass(PassAction(actor: actor))

        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown action type: \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .dahai(let action):
            try container.encode("dahai", forKey: .type)
            try container.encode(action.actor, forKey: .actor)
            try container.encode(action.pai, forKey: .pai)
            try container.encode(action.tsumogiri, forKey: .tsumogiri)

        case .reach(let action):
            try container.encode("reach", forKey: .type)
            try container.encode(action.actor, forKey: .actor)

        case .chi(let action):
            try container.encode("chi", forKey: .type)
            try container.encode(action.actor, forKey: .actor)
            try container.encode(action.target, forKey: .target)
            try container.encode(action.pai, forKey: .pai)
            try container.encode(action.consumed, forKey: .consumed)

        case .pon(let action):
            try container.encode("pon", forKey: .type)
            try container.encode(action.actor, forKey: .actor)
            try container.encode(action.target, forKey: .target)
            try container.encode(action.pai, forKey: .pai)
            try container.encode(action.consumed, forKey: .consumed)

        case .daiminkan(let action):
            try container.encode("daiminkan", forKey: .type)
            try container.encode(action.actor, forKey: .actor)
            try container.encode(action.target, forKey: .target)
            try container.encode(action.pai, forKey: .pai)
            try container.encode(action.consumed, forKey: .consumed)

        case .ankan(let action):
            try container.encode("ankan", forKey: .type)
            try container.encode(action.actor, forKey: .actor)
            try container.encode(action.consumed, forKey: .consumed)

        case .kakan(let action):
            try container.encode("kakan", forKey: .type)
            try container.encode(action.actor, forKey: .actor)
            try container.encode(action.pai, forKey: .pai)
            try container.encode(action.consumed, forKey: .consumed)

        case .nukidora(let action):
            try container.encode("nukidora", forKey: .type)
            try container.encode(action.actor, forKey: .actor)
            try container.encode(action.pai, forKey: .pai)

        case .hora(let action):
            try container.encode("hora", forKey: .type)
            try container.encode(action.actor, forKey: .actor)
            try container.encode(action.target, forKey: .target)
            try container.encodeIfPresent(action.pai, forKey: .pai)

        case .ryukyoku(let action):
            try container.encode("ryukyoku", forKey: .type)
            try container.encode(action.actor, forKey: .actor)

        case .pass(let action):
            try container.encode("none", forKey: .type)
            try container.encode(action.actor, forKey: .actor)
        }
    }
}

// MARK: - Convenience

extension MJAIAction {
    /// 動作類型名稱
    public var typeName: String {
        switch self {
        case .dahai: return "dahai"
        case .reach: return "reach"
        case .chi: return "chi"
        case .pon: return "pon"
        case .daiminkan: return "daiminkan"
        case .ankan: return "ankan"
        case .kakan: return "kakan"
        case .nukidora: return "nukidora"
        case .hora: return "hora"
        case .ryukyoku: return "ryukyoku"
        case .pass: return "none"
        }
    }

    /// 動作者座位
    public var actor: Int {
        switch self {
        case .dahai(let a): return a.actor
        case .reach(let a): return a.actor
        case .chi(let a): return a.actor
        case .pon(let a): return a.actor
        case .daiminkan(let a): return a.actor
        case .ankan(let a): return a.actor
        case .kakan(let a): return a.actor
        case .nukidora(let a): return a.actor
        case .hora(let a): return a.actor
        case .ryukyoku(let a): return a.actor
        case .pass(let a): return a.actor
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
    public static func fromJSONString(_ json: String) throws -> MJAIAction {
        guard let data = json.data(using: .utf8) else {
            throw MortalError.decodingFailed
        }
        let decoder = JSONDecoder()
        return try decoder.decode(MJAIAction.self, from: data)
    }
}

// MARK: - ActionIndex

extension MJAIAction {
    /// 從 action index 和 JSON 字串解析 (用於從 Rust FFI 轉換)
    public static func fromActionJSON(_ json: String) throws -> MJAIAction {
        return try fromJSONString(json)
    }
}
