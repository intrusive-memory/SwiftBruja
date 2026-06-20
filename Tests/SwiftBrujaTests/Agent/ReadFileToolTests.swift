import XCTest

@testable import SwiftBruja

/// Sortie 1 exit-criteria test for the unified tool foundation.
///
/// Exercises ``ReadFileTool/call(arguments:)`` directly (no model, no inference): a temp file
/// round-trips its content, and a missing path returns a **typed error string** rather than
/// crashing or throwing an uncaught error.
@available(macOS 26.0, *)
final class ReadFileToolTests: XCTestCase {

  private var tmpDir: URL!
  private var previousCwd: String!

  override func setUpWithError() throws {
    try super.setUpWithError()
    tmpDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("BrujaReadFileToolTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    // S4: the PathGuard confines tools to the process cwd subtree. These tests operate inside
    // `tmpDir`, so make it the working directory for each test (the in-cwd case R6.1 permits).
    previousCwd = FileManager.default.currentDirectoryPath
    XCTAssertTrue(FileManager.default.changeCurrentDirectoryPath(tmpDir.path))
  }

  override func tearDownWithError() throws {
    FileManager.default.changeCurrentDirectoryPath(previousCwd)
    try? FileManager.default.removeItem(at: tmpDir)
    try super.tearDownWithError()
  }

  func testReadFileReturnsContent() async throws {
    let fileURL = tmpDir.appendingPathComponent("bruja-readfile-\(UUID().uuidString).txt")
    let content = "hello from sortie one\nline two\n"
    try content.write(to: fileURL, atomically: true, encoding: .utf8)

    let tool = ReadFileTool()
    let result = try await tool.call(arguments: .init(path: fileURL.path))

    XCTAssertTrue(
      result.contains("hello from sortie one"),
      "Expected file content in result, got: \(result)")
    XCTAssertFalse(
      result.hasPrefix(ToolResult.errorPrefix),
      "Successful read must not be an error result")
  }

  func testMissingFileReturnsTypedErrorString() async throws {
    // A missing file *inside* the cwd subtree so it reaches the tool's not-found logic
    // (rather than being short-circuited by the path-escape guard).
    let missingPath = tmpDir.appendingPathComponent("\(UUID().uuidString)/does-not-exist.txt").path

    let tool = ReadFileTool()
    // Must not crash and must not throw — a missing file is reported as a result string.
    let result = try await tool.call(arguments: .init(path: missingPath))

    XCTAssertTrue(
      result.hasPrefix(ToolResult.errorPrefix),
      "Missing file must return a typed error string, got: \(result)")
    XCTAssertTrue(
      result.contains("file not found"),
      "Error string should describe the missing file, got: \(result)")
  }

  func testDirectoryPathReturnsTypedErrorString() async throws {
    // A directory inside the cwd subtree so it reaches the "is a directory" check.
    let dir = tmpDir.appendingPathComponent("a-subdir")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    let tool = ReadFileTool()
    let result = try await tool.call(arguments: .init(path: dir.path))

    XCTAssertTrue(
      result.hasPrefix(ToolResult.errorPrefix),
      "A directory path must return a typed error string, got: \(result)")
  }

  func testRegistryExposesReadFileTool() {
    let tools = ToolRegistry.defaultTools()
    XCTAssertTrue(
      tools.contains { $0.name == "read_file" },
      "ToolRegistry must register read_file")
  }
}
