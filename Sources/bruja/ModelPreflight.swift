import Foundation
import SwiftAcervo

// MARK: - Model existence preflight

/// Confirms that `modelId` is obtainable before any load or download begins.
///
/// bruja is an on-device tool, so this stays offline-friendly: if the model is
/// already present in the shared App Group container it returns immediately and
/// never touches the network. The App Group identifier itself is resolved by
/// SwiftAcervo from the `bruja` binary's `com.apple.security.application-groups`
/// entitlement (see `cli.entitlements` + `make codesign-cli`) or the
/// `ACERVO_APP_GROUP_ID` env var — there is no API argument for it.
///
/// Only when the model is **not** local do we probe the CDN with a
/// credential-free public manifest read via ``Acervo/availability(slug:url:telemetry:)``.
/// We ignore the returned local-availability state (it will be `.notAvailable`,
/// since the model isn't downloaded); the only thing that matters is whether the
/// manifest resolves, which proves the model is published on the server. A 404
/// means it does not exist there and is a hard stop.
///
/// - Parameter modelId: A model identifier in `org/repo` form
///   (e.g. `mlx-community/Llama-3.2-1B-Instruct-4bit`).
/// - Throws: ``CLIError`` if the model is not published on the CDN or the id is
///   malformed; rethrows other `AcervoError`s (network failures, etc.) so
///   `runCLI` can render them via `humanReadable`.
func ensureModelObtainable(_ modelId: String) async throws {
  // Already present in the shared container — the model is here and loadable,
  // so the server's opinion is irrelevant (and we stay usable offline).
  //
  // Use the LOOSE local probe (`isModelConfigPresent`, a config.json check) and
  // not the strict `isModelAvailable`: the latter additionally requires the
  // byte-equal manifest *cache* file, which older download flows did not write.
  // A model with all weights/tokenizer/config on disk but no cached manifest is
  // fully loadable for inference — the strict check would wrongly force a
  // network probe and block it.
  if Acervo.isModelConfigPresent(modelId) { return }

  do {
    _ = try await Acervo.availability(slug: modelId)
  } catch let error as AcervoError {
    if modelIsNotPublished(error) {
      throw CLIError(
        "Model '\(modelId)' does not exist on the CDN. "
          + "Run `acervo list` to see the published models.")
    }
    if case .urlRequiredForSlug = error {
      throw CLIError(
        "Invalid model ID '\(modelId)'. Expected 'org/repo' "
          + "(e.g., mlx-community/Llama-3.2-1B-Instruct-4bit).")
    }
    // Network or other transport/decoding failure — surface as-is.
    throw error
  }
}

/// Maps the SwiftAcervo error vocabulary for "the server has no such model"
/// onto a single boolean.
///
/// `availability(slug:)` surfaces a missing model as `manifestFetchFailed`; the
/// manifest/download paths use `manifestDownloadFailed`; `modelNotFound` covers
/// the offline-catalog miss. Any non-404 status is a real fault (auth, server
/// error) and is NOT treated as "not published".
private func modelIsNotPublished(_ error: AcervoError) -> Bool {
  switch error {
  case .manifestFetchFailed(_, let status): return status == 404
  case .manifestDownloadFailed(let status): return status == 404
  case .modelNotFound: return true
  default: return false
  }
}
