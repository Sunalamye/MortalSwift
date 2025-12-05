//
//  MortalError.swift
//  MortalSwift
//
//  Error types for MortalSwift
//

import Foundation

/// Errors that can occur in MortalSwift
public enum MortalError: Error, LocalizedError {
    case invalidPlayerId(UInt8)
    case invalidVersion(UInt32)
    case encodingFailed
    case decodingFailed
    case noValidActions
    case inferenceOutputMissing
    case modelNotLoaded
    case invalidTile(String)

    public var errorDescription: String? {
        switch self {
        case .invalidPlayerId(let id):
            return "Invalid player ID: \(id). Must be 0-3."
        case .invalidVersion(let version):
            return "Invalid model version: \(version). Must be 1-4."
        case .encodingFailed:
            return "Failed to encode to JSON."
        case .decodingFailed:
            return "Failed to decode from JSON."
        case .noValidActions:
            return "No valid actions available."
        case .inferenceOutputMissing:
            return "Model inference output is missing."
        case .modelNotLoaded:
            return "Core ML model is not loaded."
        case .invalidTile(let tile):
            return "Invalid tile: \(tile)"
        }
    }
}
