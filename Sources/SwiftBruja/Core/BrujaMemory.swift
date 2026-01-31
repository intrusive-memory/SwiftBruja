import Foundation
import MLX

/// Memory management utilities for model loading and token generation
public enum BrujaMemory {

    /// Returns estimated available memory (total physical minus MLX active memory)
    public static func availableMemory() -> UInt64 {
        let total = ProcessInfo.processInfo.physicalMemory
        let active = GPU.activeMemory
        return total > active ? total - UInt64(active) : 0
    }

    /// Recommends a maxTokens value based on available memory after accounting for model size
    public static func recommendedMaxTokens(modelSizeBytes: Int64) -> Int {
        let available = availableMemory()
        return tokensForAvailableMemory(available, modelSizeBytes: modelSizeBytes)
    }

    /// Pure logic for token recommendation given a known available memory value.
    public static func tokensForAvailableMemory(_ available: UInt64, modelSizeBytes: Int64) -> Int {
        let afterModel = available > UInt64(modelSizeBytes) ? available - UInt64(modelSizeBytes) : 0
        let afterModelGB = Double(afterModel) / (1024 * 1024 * 1024)

        let tokens: Int
        switch afterModelGB {
        case ...8:
            tokens = 512
        case 8..<16:
            tokens = 2048
        case 16..<32:
            tokens = 4096
        default:
            tokens = 8192
        }
        return max(tokens, 4096)
    }

    /// Validates that there is sufficient memory to load a model of the given size
    ///
    /// Throws `BrujaError.insufficientMemory` if the model size exceeds 80% of available memory,
    /// leaving headroom for KV-cache and OS.
    public static func validateMemoryForModel(sizeBytes: Int64) throws {
        let available = availableMemory()
        let maxAllowed = Double(available) * 0.8
        if Double(sizeBytes) > maxAllowed {
            throw BrujaError.insufficientMemory(
                available: available,
                required: UInt64(sizeBytes)
            )
        }
    }
}
