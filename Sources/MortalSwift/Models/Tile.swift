//
//  Tile.swift
//  MortalSwift
//
//  麻將牌的強類型表示
//

import Foundation

// MARK: - Tile

/// 麻將牌
public enum Tile: Hashable, Sendable {
    /// 萬子 (1-9)
    case man(Int, red: Bool = false)
    /// 筒子 (1-9)
    case pin(Int, red: Bool = false)
    /// 索子 (1-9)
    case sou(Int, red: Bool = false)
    /// 東
    case east
    /// 南
    case south
    /// 西
    case west
    /// 北
    case north
    /// 白
    case white
    /// 發
    case green
    /// 中
    case red
    /// 未知牌 (其他玩家的暗牌)
    case unknown

    /// 是否為紅寶牌
    public var isRed: Bool {
        switch self {
        case .man(5, red: true), .pin(5, red: true), .sou(5, red: true):
            return true
        default:
            return false
        }
    }

    /// 是否為字牌
    public var isHonor: Bool {
        switch self {
        case .east, .south, .west, .north, .white, .green, .red:
            return true
        default:
            return false
        }
    }

    /// 是否為風牌
    public var isWind: Bool {
        switch self {
        case .east, .south, .west, .north:
            return true
        default:
            return false
        }
    }

    /// 是否為三元牌
    public var isDragon: Bool {
        switch self {
        case .white, .green, .red:
            return true
        default:
            return false
        }
    }

    /// 牌的索引 (0-33)，用於 action space
    public var index: Int {
        switch self {
        case .man(let n, _): return n - 1        // 0-8
        case .pin(let n, _): return n + 8        // 9-17
        case .sou(let n, _): return n + 17       // 18-26
        case .east: return 27
        case .south: return 28
        case .west: return 29
        case .north: return 30
        case .white: return 31
        case .green: return 32
        case .red: return 33
        case .unknown: return -1
        }
    }

    /// 從索引創建牌 (不含紅寶牌資訊)
    public static func fromIndex(_ index: Int) -> Tile? {
        switch index {
        case 0...8: return .man(index + 1)
        case 9...17: return .pin(index - 8)
        case 18...26: return .sou(index - 17)
        case 27: return .east
        case 28: return .south
        case 29: return .west
        case 30: return .north
        case 31: return .white
        case 32: return .green
        case 33: return .red
        default: return nil
        }
    }
}

// MARK: - MJAI String Conversion

extension Tile {
    /// MJAI 格式字串 (e.g., "5mr", "1p", "E")
    public var mjaiString: String {
        switch self {
        case .man(let n, let red):
            return red ? "5mr" : "\(n)m"
        case .pin(let n, let red):
            return red ? "5pr" : "\(n)p"
        case .sou(let n, let red):
            return red ? "5sr" : "\(n)s"
        case .east: return "E"
        case .south: return "S"
        case .west: return "W"
        case .north: return "N"
        case .white: return "P"
        case .green: return "F"
        case .red: return "C"
        case .unknown: return "?"
        }
    }

    /// 從 MJAI 格式字串解析
    public init?(mjaiString: String) {
        let s = mjaiString.trimmingCharacters(in: .whitespaces)

        // 字牌
        switch s {
        case "E": self = .east; return
        case "S": self = .south; return
        case "W": self = .west; return
        case "N": self = .north; return
        case "P": self = .white; return
        case "F": self = .green; return
        case "C": self = .red; return
        case "?": self = .unknown; return
        default: break
        }

        // 數牌
        guard s.count >= 2 else { return nil }

        let isRed = s.hasSuffix("r")
        let base = isRed ? String(s.dropLast()) : s

        guard let numChar = base.first,
              let num = Int(String(numChar)),
              (1...9).contains(num) else {
            return nil
        }

        let suit = base.dropFirst()
        switch suit {
        case "m":
            self = .man(num, red: isRed && num == 5)
        case "p":
            self = .pin(num, red: isRed && num == 5)
        case "s":
            self = .sou(num, red: isRed && num == 5)
        default:
            return nil
        }
    }

    /// 從雀魂格式解析 (0m=紅5萬, 1z-7z=字牌)
    public init?(majsoulString: String) {
        let s = majsoulString.trimmingCharacters(in: .whitespaces)

        guard s.count >= 2 else { return nil }

        guard let numChar = s.first,
              let num = Int(String(numChar)) else {
            return nil
        }

        let suit = s.dropFirst()
        switch suit {
        case "m":
            if num == 0 {
                self = .man(5, red: true)
            } else if (1...9).contains(num) {
                self = .man(num)
            } else {
                return nil
            }
        case "p":
            if num == 0 {
                self = .pin(5, red: true)
            } else if (1...9).contains(num) {
                self = .pin(num)
            } else {
                return nil
            }
        case "s":
            if num == 0 {
                self = .sou(5, red: true)
            } else if (1...9).contains(num) {
                self = .sou(num)
            } else {
                return nil
            }
        case "z":
            switch num {
            case 1: self = .east
            case 2: self = .south
            case 3: self = .west
            case 4: self = .north
            case 5: self = .white
            case 6: self = .green
            case 7: self = .red
            default: return nil
            }
        default:
            return nil
        }
    }
}

// MARK: - Codable

extension Tile: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let tile = Tile(mjaiString: string) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid tile string: \(string)"
            )
        }
        self = tile
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(mjaiString)
    }
}

// MARK: - CustomStringConvertible

extension Tile: CustomStringConvertible {
    public var description: String {
        mjaiString
    }
}

// MARK: - Wind

/// 風牌方位
public enum Wind: String, Codable, Sendable, CaseIterable {
    case east = "E"
    case south = "S"
    case west = "W"
    case north = "N"

    public var tile: Tile {
        switch self {
        case .east: return .east
        case .south: return .south
        case .west: return .west
        case .north: return .north
        }
    }

    public var index: Int {
        switch self {
        case .east: return 0
        case .south: return 1
        case .west: return 2
        case .north: return 3
        }
    }

    public static func fromIndex(_ index: Int) -> Wind? {
        switch index {
        case 0: return .east
        case 1: return .south
        case 2: return .west
        case 3: return .north
        default: return nil
        }
    }
}
