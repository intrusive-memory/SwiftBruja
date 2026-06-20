import Foundation

/// `PathGuard` — the working-directory confinement guard (R6.1–R6.4).
///
/// Classifies a candidate filesystem path as either *inside the cwd subtree* (allowed to
/// run without per-action confirmation, R6.1) or *escaping the cwd subtree* (the one hard
/// gate, R6.2 — routed to the consent flow that lands in Sortie 6/7). When a path cannot be
/// resolved safely, the guard **denies by default** (R6.2) rather than silently allowing.
///
/// ## Resolution model
///
/// The guard fully canonicalizes both the working directory and the candidate path before
/// comparing them, so the classification is robust against:
/// - `..` traversal (`cwd/../etc/passwd`),
/// - absolute paths that point elsewhere (`/etc/passwd`),
/// - **symlinks inside the cwd that resolve outside it** — the link *target* is resolved,
///   not just the link path, so a symlink within cwd pointing at `/tmp` is classified as an
///   escape.
///
/// Because a candidate may not exist yet (e.g. a `write_file` target whose file is not on
/// disk), the guard resolves the **deepest existing ancestor** with `realpath(3)` (which
/// follows symlinks) and then appends the remaining, not-yet-existing path components with
/// `..` normalization applied. If that synthesized path lands inside the resolved cwd it is
/// allowed; otherwise it is an escape. If even the ancestor walk cannot find a real anchor
/// (e.g. the working directory itself is unresolvable), the guard denies.
///
/// ## Concurrency / TOCTOU caveat
///
/// This is a check-then-use guard: there is an unavoidable TOCTOU window between the moment
/// `classify` resolves a path and the moment the tool actually touches disk. A symlink could
/// in principle be swapped in that window. For this POC the guard is a *guardrail, not a
/// sandbox* (R6.4); a hardened build would re-validate against an O_NOFOLLOW-opened fd. The
/// caveat is documented honestly here rather than hidden.
public enum PathGuard {

  /// The outcome of classifying a candidate path against the working-directory subtree.
  public enum Decision: Sendable, Equatable {
    /// The path resolves to a location inside the cwd subtree — allowed without confirmation (R6.1).
    /// Carries the fully resolved absolute path.
    case allowed(resolved: String)

    /// The path resolves *outside* the cwd subtree — an escape that requires explicit user
    /// consent (R6.2). The consent UI itself lands in Sortie 6/7; for now tools surface this
    /// as a typed result indicating consent is required. Carries the resolved path (best
    /// available) for the audit echo.
    case escapeRequested(resolved: String)

    /// The path could not be resolved safely (parent missing, resolution failed, etc.).
    /// Deny-by-default (R6.2): never silently allowed.
    case denied(reason: String)
  }

  /// Classify `candidatePath` against `workingDirectory` (defaults to the process cwd).
  ///
  /// - Parameters:
  ///   - candidatePath: The raw path supplied to a tool. Tilde (`~`) is expanded here so the
  ///     guard sees the same path the tool will act on.
  ///   - workingDirectory: The confinement root. Defaults to the process current directory.
  /// - Returns: A ``Decision`` the calling tool acts on.
  public static func classify(
    _ candidatePath: String,
    workingDirectory: String = FileManager.default.currentDirectoryPath
  ) -> Decision {
    // 1. Resolve the confinement root. If we can't canonicalize the cwd itself, we cannot
    //    safely confine anything — deny by default.
    guard let resolvedRoot = canonicalize(workingDirectory) else {
      return .denied(reason: "working directory could not be resolved: \(workingDirectory)")
    }

    // 2. Expand tilde and make the candidate absolute relative to the working directory.
    let expanded = NSString(string: candidatePath).expandingTildeInPath
    let absoluteCandidate: String
    if expanded.hasPrefix("/") {
      absoluteCandidate = expanded
    } else {
      absoluteCandidate = (resolvedRoot as NSString).appendingPathComponent(expanded)
    }

    // 3. Canonicalize the candidate, fully resolving symlinks even when the leaf does not
    //    exist yet. A nil result means the path could not be resolved safely → deny.
    guard let resolvedCandidate = canonicalizeAllowingMissingLeaf(absoluteCandidate) else {
      return .denied(reason: "path could not be resolved safely: \(candidatePath)")
    }

    // 4. Subtree containment test on the canonicalized paths.
    if isInside(resolvedCandidate, root: resolvedRoot) {
      return .allowed(resolved: resolvedCandidate)
    } else {
      return .escapeRequested(resolved: resolvedCandidate)
    }
  }

  // MARK: - Canonicalization

  /// Fully canonicalize an **existing** path with `realpath(3)` (resolves `..` and symlinks).
  /// Returns `nil` if the path does not exist or cannot be resolved.
  private static func canonicalize(_ path: String) -> String? {
    return path.withCString { cString -> String? in
      guard let resolved = realpath(cString, nil) else { return nil }
      defer { free(resolved) }
      return String(cString: resolved)
    }
  }

  /// Canonicalize a candidate that may not fully exist on disk.
  ///
  /// Resolves the **deepest existing ancestor** via `realpath` (following any symlinks in the
  /// existing portion — this is what catches an in-cwd symlink whose target is outside cwd),
  /// then re-attaches the remaining, not-yet-existing components and standardizes `..`/`.`.
  ///
  /// Returns `nil` only when no real anchor can be found (e.g. nothing in the chain up to the
  /// filesystem root resolves), which the caller treats as deny-by-default.
  private static func canonicalizeAllowingMissingLeaf(_ absolutePath: String) -> String? {
    // Fast path: the whole thing exists → realpath it directly.
    if let resolved = canonicalize(absolutePath) {
      return resolved
    }

    // Walk up to the deepest ancestor that *does* resolve.
    var components = (absolutePath as NSString).pathComponents
    // Drop a redundant leading "/" component so we can rejoin cleanly.
    if components.first == "/" {
      components.removeFirst()
    }

    var trailing: [String] = []
    while !components.isEmpty {
      let candidate = "/" + components.joined(separator: "/")
      if let resolvedAncestor = canonicalize(candidate) {
        // Re-attach the not-yet-existing tail and normalize `..`/`.`.
        let rejoined = (resolvedAncestor as NSString)
          .appendingPathComponent(trailing.joined(separator: "/"))
        return (rejoined as NSString).standardizingPath
      }
      // Move the last component into the trailing (unresolved) tail and try the shorter prefix.
      trailing.insert(components.removeLast(), at: 0)
    }

    // Even "/" did not resolve — cannot anchor safely.
    return nil
  }

  // MARK: - Containment

  /// True when `candidate` is the `root` itself or lives within its subtree.
  ///
  /// Both arguments must already be canonicalized absolute paths. The comparison is on path
  /// boundaries (component-aware) so `/work` does not falsely "contain" `/work-other`.
  private static func isInside(_ candidate: String, root: String) -> Bool {
    if candidate == root { return true }
    let rootWithSep = root.hasSuffix("/") ? root : root + "/"
    return candidate.hasPrefix(rootWithSep)
  }

  // MARK: - run_shell best-effort outside-path detection (R6.2 / R6.4)

  /// Best-effort scan of a `run_shell` command string for tokens that appear to reference paths
  /// **outside** the cwd subtree (absolute paths or `..` traversal).
  ///
  /// **BEST-EFFORT ONLY (R6.4).** A shell command can still `cd` elsewhere, build paths via
  /// variable expansion, or use globbing/command-substitution that this static scan cannot see.
  /// This is a *guardrail to surface a warning*, not a sandbox. It never blocks execution by
  /// itself — it returns the suspicious tokens so the caller can flag/echo them.
  ///
  /// - Parameters:
  ///   - command: The raw shell command string.
  ///   - workingDirectory: The confinement root (defaults to the process cwd).
  /// - Returns: The list of suspicious tokens that resolve outside the cwd subtree. Empty when
  ///   nothing suspicious was detected.
  public static func suspiciousOutsidePaths(
    in command: String,
    workingDirectory: String = FileManager.default.currentDirectoryPath
  ) -> [String] {
    // Tokenize on whitespace and a few shell separators. Crude on purpose — this is best-effort.
    let separators = CharacterSet(charactersIn: " \t\n;|&()<>\"'`=")
    let tokens = command
      .components(separatedBy: separators)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }

    var suspicious: [String] = []
    for token in tokens {
      // Only consider tokens that look like paths: absolute, parent-relative, or tilde.
      let looksLikePath =
        token.hasPrefix("/")
        || token.hasPrefix("..")
        || token.contains("/..")
        || token.hasPrefix("~")
      guard looksLikePath else { continue }

      switch classify(token, workingDirectory: workingDirectory) {
      case .allowed:
        continue
      case .escapeRequested, .denied:
        suspicious.append(token)
      }
    }
    return suspicious
  }
}
