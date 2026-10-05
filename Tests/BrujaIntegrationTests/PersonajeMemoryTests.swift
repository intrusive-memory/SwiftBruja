import Foundation
import MLX
import MLXLMCommon
import SwiftAcervo
import XCTest

@testable import SwiftBruja

/// Peak-memory measurement harness for long prompts on Personaje's default model (BR-P3).
///
/// This class MEASURES and PRINTS. It makes no claim about how large the figures may be; the
/// only checks are that the harness itself worked (the prompt has the size asked for, the
/// counters returned something).
///
/// "Peak" is MLX's `Memory.peakMemory` (decision OQ-3). The process physical footprint is
/// printed beside it for context only.
///
/// Like `PersonajeAcceptanceTests`, the class skips when the default model is not reachable
/// from the test process. Run it through `make test-personaje-memory`, which uses the
/// unsandboxed `xcrun xctest` host with `ACERVO_APP_GROUP_ID` set.
///
/// **Requirements:** Apple Silicon and the default model present in the
/// `group.intrusive-memory.models` App Group container.
final class PersonajeMemoryTests: XCTestCase {

  /// Personaje's default model. This is NOT `BrujaModelManager.defaultModel`.
  static let defaultModelId = "mlx-community/Qwen2.5-7B-Instruct-4bit"

  /// The App Group container the models are downloaded into. SwiftAcervo resolves the
  /// shared-models directory from `ACERVO_APP_GROUP_ID` first.
  private let appGroupId = "group.intrusive-memory.models"

  override func setUp() {
    super.setUp()
    setenv("ACERVO_APP_GROUP_ID", appGroupId, 1)
  }

  /// Skips the calling test unless `modelId` is on disk and readable from this process.
  private func skipUnlessModelPresent(_ modelId: String) throws {
    try XCTSkipUnless(
      Acervo.isModelConfigPresent(modelId),
      "Model '\(modelId)' is not reachable from this test process at "
        + "\(Acervo.sharedModelsDirectory.path). Run via the unsandboxed host "
        + "(`make test-personaje-memory`); the sandboxed `xcodebuild test` runner cannot read "
        + "the App Group container."
    )
  }

  // MARK: - Synthetic prompt

  /// Plain English sentences the synthetic prompt cycles through.
  private static let sentences = [
    "The ferry left the harbor a little after nine in the morning.",
    "Marta kept the shop open late because the rain would not stop.",
    "Nobody on the street could remember who had planted the old lemon tree.",
    "He counted the coins twice and put them back in the tin box.",
    "The teacher wrote the date on the board and waited for the room to settle.",
    "By the time the bread was ready, the neighbors had already gone home.",
    "She folded the letter, then unfolded it and read the last line again.",
    "The dog slept under the table while the two brothers argued about the map.",
  ]

  /// Counts the tokens of `text` as the model's tokenizer sees the raw string: no special
  /// tokens and no chat template.
  private static func tokenCount(_ text: String, _ tokenizer: any Tokenizer) -> Int {
    tokenizer.encode(text: text, addSpecialTokens: false).count
  }

  /// Builds a prompt of about `target` tokens by repeating plain English sentences.
  ///
  /// The returned count is the tokenizer's count of the prompt string itself, BEFORE the chat
  /// template is applied. The model sees slightly more: `Bruja.queryWithMetadata` wraps the
  /// prompt in the chat template and adds a system prompt.
  ///
  /// Whole sentences are added until the count reaches the target, so the result overshoots by
  /// at most one sentence (about 15 tokens), well inside 2% of any target used here.
  private static func syntheticPrompt(
    targetTokens target: Int, tokenizer: any Tokenizer
  ) -> (text: String, tokens: Int) {
    // Size one pass through the sentence list, then jump close to the target in one step.
    let cycle = sentences.joined(separator: " ")
    let cycleTokens = max(1, tokenCount(cycle + " ", tokenizer))
    let wholeCycles = max(0, target / cycleTokens - 1)

    var parts = Array(repeating: cycle, count: wholeCycles)
    var text = parts.joined(separator: " ")
    var tokens = text.isEmpty ? 0 : tokenCount(text, tokenizer)

    var next = 0
    while tokens < target {
      parts.append(sentences[next % sentences.count])
      next += 1
      text = parts.joined(separator: " ")
      tokens = tokenCount(text, tokenizer)
    }
    return (text, tokens)
  }

  // MARK: - Process footprint

  /// The process physical footprint in bytes (`task_vm_info.phys_footprint`), or 0 if the
  /// kernel call fails.
  private static func physicalFootprintBytes() -> UInt64 {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(
      MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let status = withUnsafeMutablePointer(to: &info) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
      }
    }
    return status == KERN_SUCCESS ? info.phys_footprint : 0
  }

  // MARK: - BR-P3: report peak memory

  /// Prints one `PEAK` line per prompt size. Measures only.
  ///
  /// The model is loaded before the first reset of the peak counter, so both figures on each
  /// line include the model weights.
  func testReportPeakMemory() async throws {
    let modelId = Self.defaultModelId
    try skipUnlessModelPresent(modelId)

    let container = try await Bruja.loadModel(modelId)
    let tokenizer = await container.tokenizer

    for target in [5_000, 15_000] {
      let prompt = Self.syntheticPrompt(targetTokens: target, tokenizer: tokenizer)
      XCTAssertEqual(
        Double(prompt.tokens), Double(target), accuracy: Double(target) * 0.02,
        "The synthetic prompt must be within 2% of \(target) tokens")

      // The setter ignores its value and calls `mlx_reset_peak_memory()`.
      Memory.peakMemory = 0

      let start = Date()
      let result = try await Bruja.queryWithMetadata(
        prompt.text + "\n\nIn one short paragraph, say what the text above is about.",
        model: modelId,
        maxTokens: 256
      )
      let seconds = Date().timeIntervalSince(start)

      let peak = Memory.peakMemory
      let footprint = Self.physicalFootprintBytes()
      let snapshot = Memory.snapshot()

      // `tokens` is the synthetic prompt's size as the tokenizer counts it, before the short
      // closing instruction and before the chat template is applied.
      //
      // Each line is one `print` call with a leading newline, so it starts at the beginning of
      // a line even when XCTest's own output is interleaved.
      print("\nPEAK tokens=\(prompt.tokens) mlx_bytes=\(peak) footprint_bytes=\(footprint)")
      print(
        "\nPEAKDETAIL tokens=\(prompt.tokens) target=\(target) "
          + "mlx_active_bytes=\(snapshot.activeMemory) mlx_cache_bytes=\(snapshot.cacheMemory) "
          + "seconds=\(String(format: "%.1f", seconds)) response_chars=\(result.response.count)")
      fflush(stdout)

      XCTAssertGreaterThan(peak, 0, "MLX reported no peak memory")
      XCTAssertGreaterThan(footprint, 0, "task_info returned no physical footprint")
    }
  }

  // MARK: - BR-P3: unload releases memory

  /// After unload, MLX active memory is back within 256 MB of its value before the load (OQ-4).
  func testUnloadReleasesMemory() async throws {
    let modelId = Self.defaultModelId
    try skipUnlessModelPresent(modelId)

    // Other tests in this class leave the model loaded.
    await Bruja.unloadAllModels()
    let startBytes = Memory.activeMemory

    // The container is not kept in a local, so nothing here holds it past the query.
    _ = try await Bruja.query(
      "Reply with one short sentence about the sea.", model: modelId, maxTokens: 32)
    let loadedBytes = Memory.activeMemory

    await Bruja.unloadModel(modelId)
    let afterBytes = Memory.activeMemory
    let cacheAfterBytes = Memory.cacheMemory

    print(
      "\nUNLOAD start_bytes=\(startBytes) loaded_bytes=\(loadedBytes) "
        + "after_bytes=\(afterBytes) cache_after_bytes=\(cacheAfterBytes)")
    fflush(stdout)

    XCTAssertGreaterThan(loadedBytes, startBytes, "Loading the model did not raise active memory")
    XCTAssertLessThanOrEqual(
      afterBytes, startBytes + 256 * 1024 * 1024,
      "Active memory did not return to within 256 MB of its pre-load value")
  }

  /// A model that was unloaded loads again on the next query and answers.
  func testReloadAfterUnloadAnswers() async throws {
    let modelId = Self.defaultModelId
    try skipUnlessModelPresent(modelId)

    await Bruja.unloadAllModels()
    let first = try await Bruja.query(
      "Reply with one short sentence about the sea.", model: modelId, maxTokens: 32)
    XCTAssertFalse(first.isEmpty, "First response was empty")

    await Bruja.unloadModel(modelId)

    let second = try await Bruja.query(
      "Reply with one short sentence about the sea.", model: modelId, maxTokens: 32)
    XCTAssertFalse(
      second.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      "Response after unload and reload was empty")
  }
}
