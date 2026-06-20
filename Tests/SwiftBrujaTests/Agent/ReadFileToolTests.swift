import XCTest

@testable import SwiftBruja

/// Sortie 1 exit-criteria test for the unified tool foundation.
///
/// Exercises ``ReadFileTool/call(arguments:)`` directly (no model, no inference): a temp file
/// round-trips its content, and a missing path returns a **typed error string** rather than
/// crashing or throwing an uncaught error.
@available(macOS 26.0, *)
final class ReadFileToolTests: XCTestCase {

  func testReadFileReturnsContent() async throws {
    let tmpDir = FileManager.default.temporaryDirectory
    let fileURL = tmpDir.appendingPathComponent("bruja-readfile-\(UUID().uuidString).txt")
    let content = "hello from sortie one\nline two\n"
    try content.write(to: fileURL, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: fileURL) }

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
    let missingPath = "/nonexistent/\(UUID().uuidString)/does-not-exist.txt"

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
    let tmpDir = FileManager.default.temporaryDirectory

    let tool = ReadFileTool()
    let result = try await tool.call(arguments: .init(path: tmpDir.path))

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
