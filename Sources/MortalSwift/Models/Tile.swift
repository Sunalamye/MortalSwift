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

// MARK: - Unicode Display

extension Tile {
    /// Unicode 麻將字符
    public var unicode: String {
        switch self {
        case .man(let n, let red):
            if red { return "🀋" }
            return Self.manUnicode[n - 1]
        case .pin(let n, let red):
            if red { return "🀝" }
            return Self.pinUnicode[n - 1]
        case .sou(let n, let red):
            if red { return "🀔" }
            return Self.souUnicode[n - 1]
        case .east: return "🀀"
        case .south: return "🀁"
        case .west: return "🀂"
        case .north: return "🀃"
        case .white: return "🀆"
        case .green: return "🀅"
        case .red: return "🀄"
        case .unknown: return "🀫"
        }
    }

    /// 中文名稱
    public var displayName: String {
        switch self {
        case .man(let n, let red):
            let names = ["一萬", "二萬", "三萬", "四萬", "五萬", "六萬", "七萬", "八萬", "九萬"]
            return red ? "紅\(names[n - 1])" : names[n - 1]
        case .pin(let n, let red):
            let names = ["一筒", "二筒", "三筒", "四筒", "五筒", "六筒", "七筒", "八筒", "九筒"]
            return red ? "紅\(names[n - 1])" : names[n - 1]
        case .sou(let n, let red):
            let names = ["一索", "二索", "三索", "四索", "五索", "六索", "七索", "八索", "九索"]
            return red ? "紅\(names[n - 1])" : names[n - 1]
        case .east: return "東"
        case .south: return "南"
        case .west: return "西"
        case .north: return "北"
        case .white: return "白"
        case .green: return "發"
        case .red: return "中"
        case .unknown: return "?"
        }
    }

    // MARK: - Unicode Tables

    private static let manUnicode = ["🀇", "🀈", "🀉", "🀊", "🀋", "🀌", "🀍", "🀎", "🀏"]
    private static let pinUnicode = ["🀙", "🀚", "🀛", "🀜", "🀝", "🀞", "🀟", "🀠", "🀡"]
    private static let souUnicode = ["🀐", "🀑", "🀒", "🀓", "🀔", "🀕", "🀖", "🀗", "🀘"]

    /// MJAI 字串到 Unicode 的映射表
    public static let mjaiToUnicode: [String: String] = [
        "1m": "🀇", "2m": "🀈", "3m": "🀉", "4m": "🀊", "5m": "🀋",
        "5mr": "🀋", "6m": "🀌", "7m": "🀍", "8m": "🀎", "9m": "🀏",
        "1p": "🀙", "2p": "🀚", "3p": "🀛", "4p": "🀜", "5p": "🀝",
        "5pr": "🀝", "6p": "🀞", "7p": "🀟", "8p": "🀠", "9p": "🀡",
        "1s": "🀐", "2s": "🀑", "3s": "🀒", "4s": "🀓", "5s": "🀔",
        "5sr": "🀔", "6s": "🀕", "7s": "🀖", "8s": "🀗", "9s": "🀘",
        "E": "🀀", "S": "🀁", "W": "🀂", "N": "🀃",
        "P": "🀆", "F": "🀅", "C": "🀄",
        "?": "🀫"
    ]

    /// 中文名稱映射表
    public static let mjaiToDisplayName: [String: String] = [
        "1m": "一萬", "2m": "二萬", "3m": "三萬", "4m": "四萬", "5m": "五萬",
        "5mr": "紅五萬", "6m": "六萬", "7m": "七萬", "8m": "八萬", "9m": "九萬",
        "1p": "一筒", "2p": "二筒", "3p": "三筒", "4p": "四筒", "5p": "五筒",
        "5pr": "紅五筒", "6p": "六筒", "7p": "七筒", "8p": "八筒", "9p": "九筒",
        "1s": "一索", "2s": "二索", "3s": "三索", "4s": "四索", "5s": "五索",
        "5sr": "紅五索", "6s": "六索", "7s": "七索", "8s": "八索", "9s": "九索",
        "E": "東", "S": "南", "W": "西", "N": "北",
        "P": "白", "F": "發", "C": "中",
        "?": "?"
    ]
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

    /// 中文名稱
    public var displayName: String {
        switch self {
        case .east: return "東"
        case .south: return "南"
        case .west: return "西"
        case .north: return "北"
        }
    }

    /// Unicode 字符
    public var unicode: String {
        tile.unicode
    }
}
