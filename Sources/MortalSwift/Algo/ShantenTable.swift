//
//  ShantenTable.swift
//  MortalSwift
//
//  查表版向聽計算
//
//  移植自 libriichi `algo/shanten.rs`（其本身是 tomohxx 的
//  shanten-number-calculator 的 Rust 移植）。
//
//  為什麼要查表：遞迴分解版本正確但太慢。單人期望值推演會呼叫它數百萬次，
//  實測開局三向聽的一次 observation 編碼要 75 秒——完全不能用在對局中。
//  查表是 O(1)。
//
//  與 `agari.bin.gz` 不同，這兩張表的格式在 libriichi 原始碼裡完整寫著
//  （`read_table` / `sum_tiles` / `add_suhai` / `add_jihai`），
//  不需要逆向任何東西。而且遞迴版留著當測試的對照組，兩者不一致就會被抓到。
//

import Foundation
import Compression

enum ShantenTable {

    /// 每張表的一列是 10 個 nibble
    private static let entryWidth = 10
    private static let suhaiSize = 1_940_777
    private static let jihaiSize = 78_032

    private static let suhai: [[UInt8]] = load("shanten_suhai", expecting: suhaiSize)
    private static let jihai: [[UInt8]] = load("shanten_jihai", expecting: jihaiSize)

    /// 表是否成功載入。載入失敗時呼叫端要退回遞迴版本。
    static var isAvailable: Bool { suhai.count == suhaiSize && jihai.count == jihaiSize }

    // MARK: - 載入

    private static func load(_ name: String, expecting count: Int) -> [[UInt8]] {
        guard let url = Bundle.module.url(forResource: name, withExtension: "bin.gz"),
              let gz = try? Data(contentsOf: url),
              let raw = gunzip(gz) else {
            return []
        }

        // 每 5 個 byte 拆成 10 個 nibble 成為一列
        var table = [[UInt8]]()
        table.reserveCapacity(count)
        var entry = [UInt8](repeating: 0, count: entryWidth)
        for (i, b) in raw.enumerated() {
            let slot = (i * 2) % entryWidth
            entry[slot] = b & 0b1111
            entry[slot + 1] = (b >> 4) & 0b1111
            if (i + 1) % 5 == 0 {
                table.append(entry)
            }
        }
        return table
    }

    /// 解 gzip：跳過 header 後用 Apple 的 raw DEFLATE 解碼
    private static func gunzip(_ data: Data) -> [UInt8]? {
        let bytes = [UInt8](data)
        // gzip header: magic(2) + method(1) + flags(1) + mtime(4) + xfl(1) + os(1)
        guard bytes.count > 18, bytes[0] == 0x1f, bytes[1] == 0x8b, bytes[2] == 8 else { return nil }
        let flags = bytes[3]
        var offset = 10
        if flags & 0b100 != 0 {                                  // FEXTRA
            guard offset + 2 <= bytes.count else { return nil }
            let xlen = Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
            offset += 2 + xlen
        }
        if flags & 0b1000 != 0 {                                 // FNAME
            while offset < bytes.count && bytes[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0b1_0000 != 0 {                               // FCOMMENT
            while offset < bytes.count && bytes[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0b10 != 0 { offset += 2 }                     // FHCRC
        guard offset < bytes.count - 8 else { return nil }

        // 尾端 4 bytes 是原始大小（mod 2^32）
        let sizeOffset = bytes.count - 4
        let expectedSize = Int(bytes[sizeOffset])
            | (Int(bytes[sizeOffset + 1]) << 8)
            | (Int(bytes[sizeOffset + 2]) << 16)
            | (Int(bytes[sizeOffset + 3]) << 24)
        guard expectedSize > 0 else { return nil }

        let deflateBody = Array(bytes[offset..<(bytes.count - 8)])
        var out = [UInt8](repeating: 0, count: expectedSize)
        let written = out.withUnsafeMutableBufferPointer { dst -> Int in
            deflateBody.withUnsafeBufferPointer { src in
                compression_decode_buffer(
                    dst.baseAddress!, expectedSize,
                    src.baseAddress!, deflateBody.count,
                    nil, COMPRESSION_ZLIB)
            }
        }
        guard written == expectedSize else { return nil }
        return out
    }

    // MARK: - 查表

    /// 把一組牌數編成 5 進位的索引
    @inline(__always)
    private static func sumTiles(_ tehai: [Int], _ range: Range<Int>) -> Int {
        var acc = 0
        for i in range { acc = acc * 5 + tehai[i] }
        return acc
    }

    private static func addSuhai(_ lhs: inout [UInt8], _ index: Int, _ m: Int) {
        let tab = index < suhai.count ? suhai[index] : [UInt8](repeating: 0, count: entryWidth)

        var j = 5 + m
        while j >= 5 {
            var sht = min(lhs[j] &+ tab[0], lhs[0] &+ tab[j])
            var k = 5
            while k < j {
                sht = min(sht, min(lhs[k] &+ tab[j - k], lhs[j - k] &+ tab[k]))
                k += 1
            }
            lhs[j] = sht
            j -= 1
        }

        j = m
        while j >= 0 {
            var sht = lhs[j] &+ tab[0]
            var k = 0
            while k < j {
                sht = min(sht, lhs[k] &+ tab[j - k])
                k += 1
            }
            lhs[j] = sht
            if j == 0 { break }
            j -= 1
        }
    }

    private static func addJihai(_ lhs: inout [UInt8], _ index: Int, _ m: Int) {
        let tab = index < jihai.count ? jihai[index] : [UInt8](repeating: 0, count: entryWidth)

        let j = m + 5
        var sht = min(lhs[j] &+ tab[0], lhs[0] &+ tab[j])
        var k = 5
        while k < j {
            sht = min(sht, min(lhs[k] &+ tab[j - k], lhs[j - k] &+ tab[k]))
            k += 1
        }
        lhs[j] = sht
    }

    /// 一般形向聽數
    static func calcNormal(tehai: [Int], lenDiv3: Int) -> Int {
        var ret = suhai[sumTiles(tehai, 0..<9)]
        addSuhai(&ret, sumTiles(tehai, 9..<18), lenDiv3)
        addSuhai(&ret, sumTiles(tehai, 18..<27), lenDiv3)
        addJihai(&ret, sumTiles(tehai, 27..<34), lenDiv3)
        return Int(ret[5 + lenDiv3]) - 1
    }
}
