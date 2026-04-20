import Foundation
import SwiftAcervo

// MARK: - Bruja Component Registration

/// Register all Bruja-supported model components with SwiftAcervo.
/// This function is called once at module initialization to declare
/// all available models to the Acervo component catalog.
public func registerBrujaComponents() {
  // Register Qwen3-Coder-Next-4bit model
  Acervo.register(qwen3CoderNext4bitDescriptor)
}

// MARK: - Qwen3-Coder-Next-4bit Component

/// Descriptor for Qwen3-Coder-Next-4bit model (32B parameters, 4-bit quantized).
///
/// - Total size: ~41.78 GB
/// - Architecture: Qwen3 (transformer-based autoregressive LLM)
/// - Quantization: 4-bit (reduces memory footprint)
/// - Context length: 4096 tokens
/// - Minimum RAM: 16 GB
/// - Files: config, generation_config, tokenizer, chat template, and 9 model shards
let qwen3CoderNext4bitDescriptor = ComponentDescriptor(
  id: "qwen3-coder-next-4bit",
  type: .languageModel,
  displayName: "Qwen3-Coder-Next (4-bit)",
  repoId: "mlx-community/Qwen3-Coder-Next-4bit",
  files: [
    // Configuration files
    ComponentFile(
      relativePath: "config.json",
      expectedSizeBytes: 22196,
      sha256: "e8e2412abc210311363cad4396e12fc73e8142e81408ca241b2487cc80723a29"
    ),
    ComponentFile(
      relativePath: "generation_config.json",
      expectedSizeBytes: 214,
      sha256: "37a3c1ef63516ca489c575f0db1c0405ddc0c3dbaca9ed987344c966c37aeef5"
    ),
    ComponentFile(
      relativePath: "tokenizer.json",
      expectedSizeBytes: 11_422_650,
      sha256: "be75606093db2094d7cd20f3c2f385c212750648bd6ea4fb2bf507a6a4c55506"
    ),
    ComponentFile(
      relativePath: "tokenizer_config.json",
      expectedSizeBytes: 702,
      sha256: "02222317d2b3586fe0676aaf7455a90fbe4b1e4f256b9f41fba3374357303ae2"
    ),
    ComponentFile(
      relativePath: "chat_template.jinja",
      expectedSizeBytes: 6068,
      sha256: "c79a833039a43602150cce0902403d6e376c50930c1b2a139b2964e1f0c322a0"
    ),
    // Model index (safetensors shard manifest)
    ComponentFile(
      relativePath: "model.safetensors.index.json",
      expectedSizeBytes: 173_450,
      sha256: "4ab1fbfbc6e42a84c6b810745765db249350ab1df1d1cdb0c2841de89e8ca309"
    ),
    // Model shards (9 files totaling ~41.78 GB)
    ComponentFile(
      relativePath: "model-00001-of-00009.safetensors",
      expectedSizeBytes: 5_132_893_190,
      sha256: "fb30a2722004cb427d9dc3b3583a9dc4f94badf68420393324e6ebee4432c96f"
    ),
    ComponentFile(
      relativePath: "model-00002-of-00009.safetensors",
      expectedSizeBytes: 5_257_948_500,
      sha256: "a6b2a95a4bb7463f74951a5565e2504e7f28fe78877bb966378003b0def69038"
    ),
    ComponentFile(
      relativePath: "model-00003-of-00009.safetensors",
      expectedSizeBytes: 5_239_714_716,
      sha256: "0b8e009bd09fb5994d4d188a61e28a90aead48a50d7e0983d3bd7fc3644553d3"
    ),
    ComponentFile(
      relativePath: "model-00004-of-00009.safetensors",
      expectedSizeBytes: 5_261_626_153,
      sha256: "6b34fd01a609db8bd4e445dcc0cc1ef5991550523b4df7e89f59c7d50343e321"
    ),
    ComponentFile(
      relativePath: "model-00005-of-00009.safetensors",
      expectedSizeBytes: 5_257_948_651,
      sha256: "f19b843ee11c5b4c8d56b2a5940033e81ec29013de75d944447754238344621b"
    ),
    ComponentFile(
      relativePath: "model-00006-of-00009.safetensors",
      expectedSizeBytes: 5_239_714_662,
      sha256: "37f9b2ff202e8d58239f1df6acc568cb08e10a324b57c19f21b38ce93608b8c0"
    ),
    ComponentFile(
      relativePath: "model-00007-of-00009.safetensors",
      expectedSizeBytes: 5_257_948_739,
      sha256: "78e4b432212f783db393bc643b9875918fc050c3d3c41a071bf9260449db356a"
    ),
    ComponentFile(
      relativePath: "model-00008-of-00009.safetensors",
      expectedSizeBytes: 5_261_626_157,
      sha256: "3841f088f9ceed8f4024e0c6496677af6b6a32047f762337b6d42232261cb3dc"
    ),
    ComponentFile(
      relativePath: "model-00009-of-00009.safetensors",
      expectedSizeBytes: 2_934_865_732,
      sha256: "933efe2e2f28f97b9b851839c43fca0d6742b26c9ff9df1fd0e427712246553c"
    ),
  ],
  estimatedSizeBytes: 41_780_000_000, // 41.78 GB
  minimumMemoryBytes: 16_000_000_000, // 16 GB RAM
  metadata: [
    "quantization": "4-bit",
    "architecture": "Qwen3",
    "contextLength": "4096",
    "modelId": "mlx-community/Qwen3-Coder-Next-4bit",
    "version": "1.0.0",
  ]
)
