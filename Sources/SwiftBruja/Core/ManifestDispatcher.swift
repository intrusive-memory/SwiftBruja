import Foundation
import SwiftAcervo

// MARK: - Manifest Dispatcher

/// Dispatch a manifest fetch for a Bruja ID (component or raw repoId).
///
/// If `id` is a registered Bruja component (e.g., `"qwen3-coder-next-4bit"`), the
/// component-aware CDN overload is used (`Acervo.fetchManifest(forComponent:)`).
/// Otherwise, the raw-repoId overload is used (`Acervo.fetchManifest(for:)`).
///
/// This is a pure free function — no state, no actor, no class.
///
/// - Parameter id: A registered component ID or a raw HuggingFace model ID.
/// - Returns: The `CDNManifest` for the given ID.
/// - Throws: `AcervoError` for network, decoding, or integrity failures.
public func fetchManifestForBrujaId(_ id: String) async throws -> CDNManifest {
  if BrujaModelManager.component(for: id) != nil {
    return try await Acervo.fetchManifest(forComponent: id)
  } else {
    return try await Acervo.fetchManifest(for: id)
  }
}
