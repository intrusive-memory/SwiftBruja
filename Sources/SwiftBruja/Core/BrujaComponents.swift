import Foundation
import SwiftAcervo

// MARK: - Bruja Component Registration

/// Register all Bruja-supported model components with SwiftAcervo.
/// Called once at module load to declare available models to the Acervo catalog.
///
/// Descriptors are registered bare (no file list). Acervo fetches the CDN manifest
/// on first use (`ensureComponentReady` / `downloadComponent`) and populates file
/// paths, per-file sizes, and SHA-256 digests from the authoritative manifest.
public func registerBrujaComponents() {
  Acervo.register(qwen3CoderNext4bitDescriptor)
}

// MARK: - Qwen3-Coder-Next-4bit Component

/// Descriptor for Qwen3-Coder-Next-4bit (Qwen3 32B, 4-bit quantized).
///
/// File list, per-file sizes, and total download size are derived from the CDN
/// manifest on first hydration — not declared here. See SwiftAcervo's USAGE.md
/// for the manifest-first contract.
let qwen3CoderNext4bitDescriptor = ComponentDescriptor(
  id: "qwen3-coder-next-4bit",
  type: .languageModel,
  displayName: "Qwen3-Coder-Next (4-bit)",
  repoId: "mlx-community/Qwen3-Coder-Next-4bit",
  minimumMemoryBytes: 16_000_000_000,
  metadata: [
    "quantization": "4-bit",
    "architecture": "Qwen3",
    "contextLength": "4096",
  ]
)
