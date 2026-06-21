import XCTest

@testable import SwiftBruja

/// Sortie 4 exit-criteria tests for the working-directory confinement guard (R6.1–R6.4).
///
/// Covers all five classification cases plus a tool-boundary rejection:
/// (a) in-cwd path allowed, (b) `..`-escape flagged, (c) absolute-path escape flagged,
/// (d) symlink-escape (a symlink inside cwd resolving outside it) flagged, (e) unresolvable
/// path denied, and a `WriteFileTool` boundary test proving an escaping path is rejected and
/// no file is written.
@available(macOS 26.0, *)
final class PathGuardTests: XCTestCase {

  /// A fresh, real (canonicalized) temp directory we treat as the working directory under test.
  ///
  /// Canonicalized with `realpath(3)` (the same resolution PathGuard uses) so containment
  /// prefix comparisons in the assertions stay honest — `/tmp` and `/var` are symlinks on macOS.
  private func makeWorkdir() throws -> URL {
    let base = FileManager.default.temporaryDirectory
      .appendingPathComponent("bruja-pathguard-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    return URL(fileURLWithPath: realpathString(base.path))
  }

  /// Canonicalize an existing path the same way PathGuard does (realpath(3)).
  private func realpathString(_ path: String) -> String {
    path.withCString { cString -> String in
      guard let resolved = realpath(cString, nil) else { return path }
      defer { free(resolved) }
      return String(cString: resolved)
    }
  }

  // MARK: - (a) in-cwd path allowed (R6.1)

  func testInCwdPathIsAllowed() throws {
    let workdir = try makeWorkdir()
    defer { try? FileManager.default.removeItem(at: workdir) }

    let inside = workdir.appendingPathComponent("subdir/file.txt").path
    let decision = PathGuard.classify(inside, workingDirectory: workdir.path)

    guard case .allowed(let resolved) = decision else {
      return XCTFail("expected .allowed for in-cwd path, got \(decision)")
    }
    XCTAssertTrue(resolved.hasPrefix(workdir.path), "resolved path should live under cwd")
  }

  func testWorkdirItselfIsAllowed() throws {
    let workdir = try makeWorkdir()
    defer { try? FileManager.default.removeItem(at: workdir) }

    let decision = PathGuard.classify(".", workingDirectory: workdir.path)
    guard case .allowed = decision else {
      return XCTFail("expected the cwd itself to be allowed, got \(decision)")
    }
  }

  // MARK: - (b) `..`-escape flagged (R6.2)

  func testDotDotEscapeIsFlagged() throws {
    let workdir = try makeWorkdir()
    defer { try? FileManager.default.removeItem(at: workdir) }

    // workdir/../<sibling> climbs out of the subtree.
    let escaping = workdir.appendingPathComponent("../escapee.txt").path
    let decision = PathGuard.classify(escaping, workingDirectory: workdir.path)

    guard case .escapeRequested = decision else {
      return XCTFail("expected .escapeRequested for `..` escape, got \(decision)")
    }
  }

  // MARK: - (c) absolute-path escape flagged (R6.2)

  func testAbsolutePathEscapeIsFlagged() throws {
    let workdir = try makeWorkdir()
    defer { try? FileManager.default.removeItem(at: workdir) }

    let decision = PathGuard.classify("/etc/hosts", workingDirectory: workdir.path)
    guard case .escapeRequested = decision else {
      return XCTFail("expected .escapeRequested for absolute escape, got \(decision)")
    }
  }

  // MARK: - (d) symlink-escape flagged (R6.2)

  func testSymlinkInsideCwdResolvingOutsideIsFlagged() throws {
    let workdir = try makeWorkdir()
    defer { try? FileManager.default.removeItem(at: workdir) }

    // A real target OUTSIDE the workdir.
    let outsideDir = try makeWorkdir()
    defer { try? FileManager.default.removeItem(at: outsideDir) }
    let outsideFile = outsideDir.appendingPathComponent("secret.txt")
    try "secret".write(to: outsideFile, atomically: true, encoding: .utf8)

    // A symlink INSIDE the workdir pointing AT the outside file.
    let link = workdir.appendingPathComponent("link-to-secret.txt")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outsideFile)

    let decision = PathGuard.classify(link.path, workingDirectory: workdir.path)
    guard case .escapeRequested(let resolved) = decision else {
      return XCTFail("expected .escapeRequested for in-cwd symlink to outside, got \(decision)")
    }
    XCTAssertTrue(
      resolved.hasPrefix(outsideDir.path),
      "the link target (not the link path) should resolve outside cwd")
  }

  func testSymlinkInsideCwdResolvingInsideIsAllowed() throws {
    let workdir = try makeWorkdir()
    defer { try? FileManager.default.removeItem(at: workdir) }

    let realFile = workdir.appendingPathComponent("real.txt")
    try "hi".write(to: realFile, atomically: true, encoding: .utf8)
    let link = workdir.appendingPathComponent("link.txt")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: realFile)

    let decision = PathGuard.classify(link.path, workingDirectory: workdir.path)
    guard case .allowed = decision else {
      return XCTFail("an in-cwd symlink to an in-cwd target should be allowed, got \(decision)")
    }
  }

  // MARK: - (e) unresolvable path denied (R6.2 deny-by-default)

  func testUnresolvableWorkingDirectoryIsDenied() {
    // The confinement root itself cannot be resolved → deny by default.
    let decision = PathGuard.classify(
      "anything.txt",
      workingDirectory: "/nonexistent-\(UUID().uuidString)/no/such/dir")
    guard case .denied = decision else {
      return XCTFail("expected .denied when working directory is unresolvable, got \(decision)")
    }
  }

  // MARK: - run_shell best-effort scan (R6.2 / R6.4)

  func testSuspiciousOutsidePathsDetectsAbsoluteAndDotDot() throws {
    let workdir = try makeWorkdir()
    defer { try? FileManager.default.removeItem(at: workdir) }

    let suspicious = PathGuard.suspiciousOutsidePaths(
      in: "cat /etc/hosts && cat ../escapee.txt && cat ./inside.txt",
      workingDirectory: workdir.path)
    XCTAssertTrue(suspicious.contains("/etc/hosts"), "absolute outside path should be flagged")
    XCTAssertTrue(suspicious.contains("../escapee.txt"), "`..` path should be flagged")
    XCTAssertFalse(suspicious.contains("./inside.txt"), "in-cwd path should not be flagged")
  }

  // MARK: - Tool-boundary rejection (exit criterion)

  func testWriteFileToolRejectsEscapingPathAndDoesNotWrite() async throws {
    let workdir = try makeWorkdir()
    defer { try? FileManager.default.removeItem(at: workdir) }

    // Drive the tool with the process cwd set to our workdir so the guard confines correctly.
    let previousCwd = FileManager.default.currentDirectoryPath
    XCTAssertTrue(FileManager.default.changeCurrentDirectoryPath(workdir.path))
    defer { FileManager.default.changeCurrentDirectoryPath(previousCwd) }

    let outsideDir = try makeWorkdir()
    defer { try? FileManager.default.removeItem(at: outsideDir) }
    let escapingTarget = outsideDir.appendingPathComponent("should-not-exist.txt")

    let tool = WriteFileTool()
    let result = try await tool.call(
      arguments: .init(path: escapingTarget.path, content: "must not be written"))

    XCTAssertTrue(
      result.hasPrefix(ToolResult.errorPrefix),
      "escaping write must return an error-shaped result, got: \(result)")
    XCTAssertTrue(
      result.contains(ToolResult.escapeMarker),
      "escaping write must be marked consent-required, got: \(result)")
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: escapingTarget.path),
      "escaping write must NOT create the file on disk")
  }

  func testWriteFileToolAllowsInCwdPath() async throws {
    let workdir = try makeWorkdir()
    defer { try? FileManager.default.removeItem(at: workdir) }

    let previousCwd = FileManager.default.currentDirectoryPath
    XCTAssertTrue(FileManager.default.changeCurrentDirectoryPath(workdir.path))
    defer { FileManager.default.changeCurrentDirectoryPath(previousCwd) }

    let target = workdir.appendingPathComponent("inside.txt")
    let tool = WriteFileTool()
    let result = try await tool.call(arguments: .init(path: target.path, content: "ok"))

    XCTAssertFalse(
      result.hasPrefix(ToolResult.errorPrefix),
      "in-cwd write must succeed, got: \(result)")
    XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
  }
}
