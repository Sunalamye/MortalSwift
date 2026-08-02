// MortalSwift - Pure Swift Mortal Mahjong AI
//
// This package provides a Swift interface to the Mortal AI engine,
// using pure Swift for game state management and Core ML for inference.

import Foundation

/// Library version
public let MortalSwiftVersion = "0.5.1"

/// `NativeMortalBot` 的相容別名
///
/// `MortalBot` 曾經是一個獨立的型別（走 Rust FFI 的 `MortalBot.swift`），
/// 純 Swift 版接手之後那個檔案就靠 `Package.swift` 的 `exclude` 排在編譯外。
/// 那個 exclude 是承重的——檔案一旦被編進來，`MortalBot` 這個名字會同時是
/// actor 與 typealias，整包編不過。與其留一個「刪掉 exclude 就爆炸」的陷阱，
/// 不如把檔案刪掉，讓這個別名成為 `MortalBot` 唯一的定義。
public typealias MortalBot = NativeMortalBot
