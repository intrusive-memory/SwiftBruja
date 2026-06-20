import XCTest

@testable import SwiftBruja

/// Sortie 3 exit-criteria tests for the full built-in tool suite.
///
/// Exercises each tool's `call(arguments:)` directly — no model, no inference.
/// Also asserts the shared truncation policy and `ToolRegistry` completeness.
@available(macOS 26.0, *)
final class ToolSuiteTests: XCTestCase {

  // MARK: - Helpers

  private var tmpDir: URL!
  private var previousCwd: String!

  override func setUpWithError() throws {
    try super.setUpWithError()
    tmpDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("BrujaToolSuiteTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    // S4: the PathGuard confines tools to the process cwd subtree. These tool tests operate
    // entirely inside `tmpDir`, so make `tmpDir` the working directory for the duration of each
    // test — exactly the in-cwd usage R6.1 permits without confirmation.
    previousCwd = FileManager.default.currentDirectoryPath
    XCTAssertTrue(
      FileManager.default.changeCurrentDirectoryPath(tmpDir.path),
      "could not chdir into the test working directory")
  }

  override func tearDownWithError() throws {
    FileManager.default.changeCurrentDirectoryPath(previousCwd)
    try? FileManager.default.removeItem(at: tmpDir)
    try super.tearDownWithError()
  }

  private func makeFile(name: String, content: String) throws -> URL {
    let url = tmpDir.appendingPathComponent(name)
    try content.write(to: url, atomically: true, encoding: .utf8)
    return url
  }

  // MARK: - ToolRegistry

  func testRegistryReturnsFullToolSuite() {
    let tools = ToolRegistry.defaultTools()
    let names = tools.map(\.name)

    // Seven tools registered in S1 + S3.
    XCTAssertEqual(tools.count, 7, "ToolRegistry must expose exactly 7 tools; got: \(names)")

    let expectedNames: Set<String> = [
      "read_file", "run_shell", "write_file", "edit_file", "list_dir", "grep", "glob",
    ]
    let registeredNames = Set(names)
    XCTAssertEqual(
      registeredNames, expectedNames,
      "Registered tool names mismatch. Expected \(expectedNames), got \(registeredNames)")
  }

  // MARK: - RunShellTool

  func testRunShellReturnsStdout() async throws {
    let tool = RunShellTool()
    let result = try await tool.call(arguments: .init(command: "echo hello_bruja", workingDirectory: nil))

    XCTAssertTrue(result.contains("hello_bruja"), "Expected stdout in result, got: \(result)")
    XCTAssertTrue(result.contains("exit_code: 0"), "Expected exit_code: 0, got: \(result)")
    XCTAssertFalse(result.hasPrefix(ToolResult.errorPrefix), "Successful command must not be an error result")
  }

  func testRunShellCapturesStderr() async throws {
    let tool = RunShellTool()
    let result = try await tool.call(arguments: .init(command: "echo error_text >&2", workingDirectory: nil))

    XCTAssertTrue(result.contains("error_text"), "Expected stderr content in result, got: \(result)")
  }

  func testRunShellNonZeroExitCode() async throws {
    let tool = RunShellTool()
    let result = try await tool.call(arguments: .init(command: "exit 42", workingDirectory: nil))

    XCTAssertTrue(result.contains("exit_code: 42"), "Expected exit_code: 42, got: \(result)")
  }

  func testRunShellWithWorkingDirectory() async throws {
    let tool = RunShellTool()
    let result = try await tool.call(
      arguments: .init(command: "pwd", workingDirectory: tmpDir.path))

    XCTAssertTrue(result.contains(tmpDir.path), "Expected working directory in pwd output, got: \(result)")
  }

  func testRunShellTruncatesLargeOutput() async throws {
    // Generate output that exceeds the truncation threshold.
    let bigCommand = "python3 -c \"print('x' * \(ToolResult.maxResultCharacters + 1000))\""
    let tool = RunShellTool()
    let result = try await tool.call(arguments: .init(command: bigCommand, workingDirectory: nil))

    XCTAssertTrue(
      result.hasSuffix(ToolResult.truncationMarker),
      "Large output must be truncated with the shared marker; got suffix: \(result.suffix(40))")
    XCTAssertLessThanOrEqual(
      result.count,
      ToolResult.maxResultCharacters + ToolResult.truncationMarker.count,
      "Truncated result must not exceed the policy limit plus the marker length")
  }

  // MARK: - WriteFileTool

  func testWriteFileCreatesFile() async throws {
    let targetURL = tmpDir.appendingPathComponent("write_test.txt")
    let tool = WriteFileTool()
    let result = try await tool.call(
      arguments: .init(path: targetURL.path, content: "written by S3 test"))

    XCTAssertFalse(result.hasPrefix(ToolResult.errorPrefix), "Write must succeed, got: \(result)")

    let onDisk = try String(contentsOf: targetURL, encoding: .utf8)
    XCTAssertEqual(onDisk, "written by S3 test", "On-disk content must match what was written")
  }

  func testWriteFileOverwritesExistingFile() async throws {
    let fileURL = try makeFile(name: "overwrite_test.txt", content: "original")
    let tool = WriteFileTool()
    _ = try await tool.call(arguments: .init(path: fileURL.path, content: "overwritten"))

    let onDisk = try String(contentsOf: fileURL, encoding: .utf8)
    XCTAssertEqual(onDisk, "overwritten")
  }

  func testWriteFileMissingParentReturnsError() async throws {
    let badPath = tmpDir.appendingPathComponent("no_such_dir/file.txt").path
    let tool = WriteFileTool()
    let result = try await tool.call(arguments: .init(path: badPath, content: "x"))

    XCTAssertTrue(
      result.hasPrefix(ToolResult.errorPrefix),
      "Writing to a non-existent parent must return a typed error, got: \(result)")
  }

  // MARK: - EditFileTool

  func testEditFileReplacesString() async throws {
    let fileURL = try makeFile(name: "edit_test.txt", content: "foo bar baz")
    let tool = EditFileTool()
    let result = try await tool.call(
      arguments: .init(path: fileURL.path, oldString: "bar", newString: "REPLACED"))

    XCTAssertFalse(result.hasPrefix(ToolResult.errorPrefix), "Edit must succeed, got: \(result)")

    let onDisk = try String(contentsOf: fileURL, encoding: .utf8)
    XCTAssertEqual(onDisk, "foo REPLACED baz", "Replacement must appear in file, got: \(onDisk)")
  }

  func testEditFileOldStringNotFoundReturnsError() async throws {
    let fileURL = try makeFile(name: "edit_miss.txt", content: "hello world")
    let tool = EditFileTool()
    let result = try await tool.call(
      arguments: .init(path: fileURL.path, oldString: "not_present", newString: "x"))

    XCTAssertTrue(
      result.hasPrefix(ToolResult.errorPrefix),
      "Missing oldString must return a typed error, got: \(result)")
    XCTAssertTrue(result.contains("not found"), "Error must mention 'not found', got: \(result)")
  }

  func testEditFileMissingFileReturnsError() async throws {
    let tool = EditFileTool()
    let result = try await tool.call(
      arguments: .init(
        path: tmpDir.appendingPathComponent("no_such_file.txt").path,
        oldString: "x", newString: "y"))

    XCTAssertTrue(
      result.hasPrefix(ToolResult.errorPrefix),
      "Edit on missing file must return a typed error, got: \(result)")
  }

  // MARK: - ListDirTool

  func testListDirReturnsEntries() async throws {
    try makeFile(name: "alpha.txt", content: "a")
    try makeFile(name: "beta.txt", content: "b")
    let subDir = tmpDir.appendingPathComponent("subdir")
    try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: false)

    let tool = ListDirTool()
    let result = try await tool.call(arguments: .init(path: tmpDir.path))

    XCTAssertFalse(result.hasPrefix(ToolResult.errorPrefix), "listDir must succeed, got: \(result)")
    XCTAssertTrue(result.contains("alpha.txt"), "Must list alpha.txt, got: \(result)")
    XCTAssertTrue(result.contains("beta.txt"), "Must list beta.txt, got: \(result)")
    XCTAssertTrue(result.contains("subdir/"), "Subdirectory must have trailing slash, got: \(result)")
  }

  func testListDirOnEmptyDirectoryReturnsMarker() async throws {
    let emptyDir = tmpDir.appendingPathComponent("empty")
    try FileManager.default.createDirectory(at: emptyDir, withIntermediateDirectories: false)

    let tool = ListDirTool()
    let result = try await tool.call(arguments: .init(path: emptyDir.path))

    XCTAssertTrue(result.contains("empty"), "Empty directory should say so, got: \(result)")
  }

  func testListDirOnFileReturnsError() async throws {
    let fileURL = try makeFile(name: "not_a_dir.txt", content: "x")
    let tool = ListDirTool()
    let result = try await tool.call(arguments: .init(path: fileURL.path))

    XCTAssertTrue(
      result.hasPrefix(ToolResult.errorPrefix),
      "Listing a file path must return a typed error, got: \(result)")
  }

  func testListDirMissingPathReturnsError() async throws {
    let tool = ListDirTool()
    let result = try await tool.call(
      arguments: .init(path: tmpDir.appendingPathComponent("no_such_dir").path))

    XCTAssertTrue(
      result.hasPrefix(ToolResult.errorPrefix),
      "Missing path must return a typed error, got: \(result)")
  }

  // MARK: - GrepTool

  func testGrepFindsLiteralMatch() async throws {
    let fileURL = try makeFile(name: "grep_test.txt", content: "line one\nline two\nno match here\n")
    let tool = GrepTool()
    let result = try await tool.call(
      arguments: .init(pattern: "line two", path: fileURL.path, isRegex: false))

    XCTAssertFalse(result.hasPrefix(ToolResult.errorPrefix), "Grep must succeed, got: \(result)")
    XCTAssertTrue(result.contains("line two"), "Result must contain the matched line, got: \(result)")
    XCTAssertFalse(result.contains("no match"), "Non-matching lines must be absent, got: \(result)")
  }

  func testGrepReturnsNoMatchMessage() async throws {
    let fileURL = try makeFile(name: "grep_empty.txt", content: "apple banana cherry\n")
    let tool = GrepTool()
    let result = try await tool.call(
      arguments: .init(pattern: "durian", path: fileURL.path, isRegex: false))

    XCTAssertFalse(result.hasPrefix(ToolResult.errorPrefix))
    XCTAssertTrue(result.contains("no matches"), "Must report no matches, got: \(result)")
  }

  func testGrepRegexMode() async throws {
    let fileURL = try makeFile(
      name: "grep_regex.txt", content: "foo123\nbar456\nbaz\n")
    let tool = GrepTool()
    let result = try await tool.call(
      arguments: .init(pattern: "\\d+", path: fileURL.path, isRegex: true))

    XCTAssertTrue(result.contains("foo123") || result.contains("bar456"),
      "Regex match must find numeric suffixes, got: \(result)")
    XCTAssertFalse(result.contains("baz"), "Non-matching line must be absent, got: \(result)")
  }

  func testGrepMissingPathReturnsError() async throws {
    let tool = GrepTool()
    let result = try await tool.call(
      arguments: .init(pattern: "x", path: "/nonexistent/\(UUID().uuidString)", isRegex: false))

    XCTAssertTrue(
      result.hasPrefix(ToolResult.errorPrefix),
      "Missing path must return a typed error, got: \(result)")
  }

  // MARK: - GlobTool

  func testGlobMatchesSwiftFiles() async throws {
    try makeFile(name: "Main.swift", content: "")
    try makeFile(name: "Helper.swift", content: "")
    try makeFile(name: "README.md", content: "")

    let tool = GlobTool()
    let result = try await tool.call(
      arguments: .init(pattern: "*.swift", basePath: tmpDir.path))

    XCTAssertFalse(result.hasPrefix(ToolResult.errorPrefix), "Glob must succeed, got: \(result)")
    XCTAssertTrue(result.contains("Main.swift"), "Must find Main.swift, got: \(result)")
    XCTAssertTrue(result.contains("Helper.swift"), "Must find Helper.swift, got: \(result)")
    XCTAssertFalse(result.contains("README.md"), "Must not match README.md for *.swift, got: \(result)")
  }

  func testGlobNoMatchReturnsMessage() async throws {
    try makeFile(name: "only.txt", content: "")
    let tool = GlobTool()
    let result = try await tool.call(
      arguments: .init(pattern: "*.swift", basePath: tmpDir.path))

    XCTAssertFalse(result.hasPrefix(ToolResult.errorPrefix))
    XCTAssertTrue(result.contains("no files matched"), "Must report no matches, got: \(result)")
  }

  func testGlobMissingBasePathReturnsError() async throws {
    let tool = GlobTool()
    let result = try await tool.call(
      arguments: .init(pattern: "*.swift", basePath: "/nonexistent/\(UUID().uuidString)"))

    XCTAssertTrue(
      result.hasPrefix(ToolResult.errorPrefix),
      "Missing base path must return a typed error, got: \(result)")
  }

  func testGlobBasePathIsFileReturnsError() async throws {
    let fileURL = try makeFile(name: "not_a_dir.swift", content: "")
    let tool = GlobTool()
    let result = try await tool.call(
      arguments: .init(pattern: "*.swift", basePath: fileURL.path))

    XCTAssertTrue(
      result.hasPrefix(ToolResult.errorPrefix),
      "File path as basePath must return a typed error, got: \(result)")
  }

  // MARK: - Truncation policy (R4.5)

  func testToolResultTruncationPolicy() {
    // Build a string just over the policy threshold.
    let overLimit = String(repeating: "A", count: ToolResult.maxResultCharacters + 1)
    let result = ToolResult.ok(overLimit)

    XCTAssertTrue(
      result.hasSuffix(ToolResult.truncationMarker),
      "Output exceeding the threshold must end with the truncation marker")
    XCTAssertLessThanOrEqual(
      result.count,
      ToolResult.maxResultCharacters + ToolResult.truncationMarker.count,
      "Truncated result must not exceed the policy limit plus the marker length")
  }

  func testToolResultUnderLimitIsNotTruncated() {
    let underLimit = String(repeating: "B", count: ToolResult.maxResultCharacters)
    let result = ToolResult.ok(underLimit)

    XCTAssertFalse(
      result.hasSuffix(ToolResult.truncationMarker),
      "Output at or under the threshold must not be truncated")
    XCTAssertEqual(result.count, ToolResult.maxResultCharacters)
  }
}
