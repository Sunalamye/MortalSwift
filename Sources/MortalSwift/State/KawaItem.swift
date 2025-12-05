//
//  KawaItem.swift
//  MortalSwift
//
//  河 (牌河) 相關結構
//

import Foundation

/// 捨牌資訊
public struct Sutehai: Sendable, Equatable {
    /// 捨出的牌
    public let tile: Tile
    /// 是否為寶牌 (只計算表寶牌)
    public let isDora: Bool
    /// 是否為手切 (非摸切)
    public let isTedashi: Bool
    /// 是否為立直宣言牌
    public let isRiichi: Bool

    public init(tile: Tile, isDora: Bool = false, isTedashi: Bool = true, isRiichi: Bool = false) {
        self.tile = tile
        self.isDora = isDora
        self.isTedashi = isTedashi
        self.isRiichi = isRiichi
    }
}

/// 吃碰資訊
public struct ChiPon: Sendable, Equatable {
    /// 手中用於吃/碰的兩張牌
    public let consumed: [Tile]
    /// 被吃/碰的牌
    public let targetTile: Tile

    public init(consumed: [Tile], targetTile: Tile) {
        self.consumed = consumed
        self.targetTile = targetTile
    }
}

/// 河中的一項 (包含捨牌和可能的副露資訊)
public struct KawaItem: Sendable, Equatable {
    /// 吃碰資訊 (如果這張牌被吃/碰了)
    public let chiPon: ChiPon?
    /// 槓的牌 (如果這張牌之前有槓)
    public let kan: [Tile]
    /// 捨牌本身
    public let sutehai: Sutehai

    public init(sutehai: Sutehai, chiPon: ChiPon? = nil, kan: [Tile] = []) {
        self.sutehai = sutehai
        self.chiPon = chiPon
        self.kan = kan
    }
}
