import MLX
import MLXLMCommon
import XCTest

@testable import SwiftBruja

final class BrujaJSONLogitProcessorTests: XCTestCase {

  // MARK: - Fixtures

  private static let schema = BrujaJSONSchema([
    .string("name"),
    .integer("age"),
    .array("tags", of: .string),
    .string("note"),
  ])

  /// A hand-built vocabulary. Index is the token id.
  private static let tokens: [String] = [
    "<|endoftext|>",  // 0, EOS
    "\"]",  // 1
    "\",",  // 2
    "\"}",  // 3
    "\"",  // 4
    "\":",  // 5
    ",",  // 6
    ",\"",  // 7
    ":",  // 8
    "{",  // 9
    "{\"",  // 10
    "}",  // 11
    "[",  // 12
    "]",  // 13
    "name",  // 14
    "age",  // 15
    "tags",  // 16
    "note",  // 17
    "7",  // 18
    "42",  // 19
    "null",  // 20
    "\"null\"",  // 21
    "null\"",  // 22
    "able",  // 23
    "Hunter",  // 24
    " scout",  // 25
    "caf\u{FFFD}",  // 26, a partial UTF-8 sequence
    "",  // 27
    "true",  // 28
    "\n",  // 29
    "-",  // 30
    "<|im_end|>",  // 31, EOS
  ]

  private static let eosTokenIds: Set<Int> = [0, 31]

  private static let vocabulary: [Int: String] = Dictionary(
    uniqueKeysWithValues: tokens.enumerated().map { ($0.offset, $0.element) })

  private static func id(_ text: String) -> Int {
    guard let index = tokens.firstIndex(of: text) else {
      preconditionFailure("no token \(text.debugDescription) in the test vocabulary")
    }
    return index
  }

  /// A processor whose acceptor has already consumed `prefix`.
  private func makeProcessor(
    after prefix: String = "", file: StaticString = #filePath, line: UInt = #line
  ) -> BrujaJSONLogitProcessor {
    var acceptor = BrujaJSONAcceptor(schema: Self.schema)
    if let state = acceptor.state(after: prefix, from: acceptor.initialState) {
      acceptor.state = state
    } else {
      XCTFail("the acceptor rejected the prefix \(prefix)", file: file, line: line)
    }
    return BrujaJSONLogitProcessor(
      acceptor: acceptor, vocabulary: Self.vocabulary, eosTokenIds: Self.eosTokenIds)
  }

  /// Logits of shape `[1, width]`, the shape `TokenIterator` hands a processor.
  private func uniformLogits(width: Int = BrujaJSONLogitProcessorTests.tokens.count) -> MLXArray {
    MLXArray.zeros([1, width])
  }

  /// The processed logits as one row of floats.
  private func processedRow(
    _ processor: BrujaJSONLogitProcessor, logits: MLXArray? = nil
  ) -> [Float] {
    processor.process(logits: logits ?? uniformLogits()).asArray(Float.self)
  }

  /// The ids whose logit is still finite after processing uniform logits.
  private func finiteIds(_ processor: BrujaJSONLogitProcessor, width: Int? = nil) -> [Int] {
    let row = processedRow(processor, logits: uniformLogits(width: width ?? Self.tokens.count))
    return row.indices.filter { row[$0].isFinite }
  }

  private func assertMasked(
    _ text: String, in processor: BrujaJSONLogitProcessor,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    let row = processedRow(processor)
    XCTAssertEqual(
      row[Self.id(text)], -.infinity, "token \(text.debugDescription) is not masked",
      file: file, line: line)
  }

  private func assertAllowed(
    _ text: String, in processor: BrujaJSONLogitProcessor,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    let row = processedRow(processor)
    XCTAssertEqual(
      row[Self.id(text)], 0, "token \(text.debugDescription) is masked", file: file, line: line)
  }

  // MARK: - Greedy generation

  func testGreedySelectionOverUniformLogitsProducesValidJSON() throws {
    var processor = makeProcessor()
    var decoded = ""
    var sampled: [Int] = []
    var reachedEOS = false

    for _ in 0..<200 {
      let row = processedRow(processor)
      // Greedy over uniform logits: the first of the largest values.
      let best = try XCTUnwrap(row.max())
      XCTAssertTrue(best.isFinite, "every token is masked after \(decoded)")
      let token = try XCTUnwrap(row.firstIndex(of: best))

      processor.didSample(token: MLXArray([Int32(token)]))
      sampled.append(token)
      if Self.eosTokenIds.contains(token) {
        reachedEOS = true
        break
      }
      decoded += Self.tokens[token]
    }

    XCTAssertTrue(reachedEOS, "generation did not end in 200 steps: \(decoded)")
    XCTAssertTrue(processor.isComplete)
    XCTAssertEqual(decoded, #"{"name":"]","age":7,"tags":["]"],"note":"]"}"#)

    let object = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: Data(decoded.utf8)) as? [String: Any])
    XCTAssertEqual(Set(object.keys), ["name", "age", "tags", "note"])
    XCTAssertEqual(object["age"] as? Int, 7)

    // The text also satisfies a fresh acceptor, character by character.
    let acceptor = BrujaJSONAcceptor(schema: Self.schema)
    let end = try XCTUnwrap(acceptor.state(after: decoded, from: acceptor.initialState))
    XCTAssertTrue(acceptor.isComplete(end))

    // Tokens that span a structural boundary were used, not just avoided.
    XCTAssertTrue(sampled.contains(Self.id("\",")))
    XCTAssertTrue(sampled.contains(Self.id("\"}")))
  }

  // MARK: - Completion and EOS

  func testAfterCompletionOnlyEOSLogitsAreFinite() {
    let processor = makeProcessor(after: #"{"name":null,"age":null,"tags":null,"note":null}"#)
    XCTAssertTrue(processor.isComplete)
    XCTAssertEqual(finiteIds(processor), [0, 31])
  }

  func testEOSIsMaskedBeforeCompletion() {
    for prefix in ["", #"{"name":"Hunter"#, #"{"name":null,"age":7,"tags":[],"note":null"#] {
      let processor = makeProcessor(after: prefix)
      let finite = finiteIds(processor)
      XCTAssertFalse(finite.isEmpty, "nothing is allowed after \(prefix)")
      XCTAssertFalse(finite.contains(0), "EOS 0 is allowed after \(prefix)")
      XCTAssertFalse(finite.contains(31), "EOS 31 is allowed after \(prefix)")
    }
  }

  func testEOSAfterCompletionLeavesTheStateComplete() {
    var processor = makeProcessor(after: #"{"name":null,"age":null,"tags":null,"note":null}"#)
    processor.didSample(token: MLXArray([Int32(31)]))
    XCTAssertTrue(processor.isComplete)
    XCTAssertEqual(finiteIds(processor), [0, 31])
  }

  // MARK: - The "null" string

  func testTokenThatWouldWriteNullAsAStringValueIsMasked() {
    // At the start of the value: JSON null is allowed, the string "null" is not.
    let atValue = makeProcessor(after: #"{"name":"#)
    assertMasked("\"null\"", in: atValue)
    assertAllowed("null", in: atValue)
    assertAllowed("\"", in: atValue)

    // Just inside the opening quote: `null` is content so far, `null"` would close on it.
    let insideEmpty = makeProcessor(after: #"{"name":""#)
    assertMasked("null\"", in: insideEmpty)
    assertMasked("\"", in: insideEmpty)
    assertMasked("\",", in: insideEmpty)
    assertAllowed("null", in: insideEmpty)

    // After the content `null`: no closing token is allowed, more content is.
    let afterNull = makeProcessor(after: #"{"name":"null"#)
    assertMasked("\"", in: afterNull)
    assertMasked("\",", in: afterNull)
    assertAllowed("able", in: afterNull)

    // `"nullable"` may close.
    assertAllowed("\",", in: makeProcessor(after: #"{"name":"nullable"#))
  }

  // MARK: - Tokens that are always masked

  func testReplacementCharacterTokenIsMaskedInsideAStringValue() {
    let processor = makeProcessor(after: #"{"name":"Hunter"#)
    assertMasked("caf\u{FFFD}", in: processor)
    // Ordinary content in the same state is allowed, so the mask is not blanket.
    assertAllowed(" scout", in: processor)
    assertAllowed("true", in: processor)
  }

  func testEmptyAndControlCharacterTokensAreMaskedInsideAStringValue() {
    let processor = makeProcessor(after: #"{"name":"Hunter"#)
    assertMasked("", in: processor)
    assertMasked("\n", in: processor)
  }

  func testLogitColumnsWithoutAVocabularyEntryAreMasked() {
    let width = Self.tokens.count + 8
    let finite = finiteIds(makeProcessor(after: #"{"name":"Hunter"#), width: width)
    XCTAssertFalse(finite.isEmpty)
    XCTAssertTrue(finite.allSatisfy { $0 < Self.tokens.count })
  }

  // MARK: - Tokens across a structural boundary

  func testTokensThatSpanAStructuralBoundary() {
    let start = makeProcessor()
    XCTAssertEqual(finiteIds(start), [Self.id("{"), Self.id("{\"")])

    let afterKey = makeProcessor(after: #"{"name"#)
    XCTAssertEqual(finiteIds(afterKey), [Self.id("\""), Self.id("\":")])

    // `name` is followed by a comma: `",` closes it, `"}` and `"]` do not.
    let inFirstValue = makeProcessor(after: #"{"name":"Hunter"#)
    assertAllowed("\",", in: inFirstValue)
    assertAllowed("\"", in: inFirstValue)
    assertMasked("\"}", in: inFirstValue)
    assertMasked("\"]", in: inFirstValue)

    // `note` is last: only `"}` or a bare quote closes it.
    let inLastValue = makeProcessor(after: #"{"name":null,"age":7,"tags":[],"note":"x"#)
    assertAllowed("\"}", in: inLastValue)
    assertMasked("\",", in: inLastValue)

    // A number ends at the comma; `,"` carries on into the next key.
    let inNumber = makeProcessor(after: #"{"name":null,"age":7"#)
    XCTAssertEqual(
      finiteIds(inNumber), [Self.id(","), Self.id(",\""), Self.id("7"), Self.id("42")])
  }

  // MARK: - Logit values

  func testAllowedLogitsKeepTheirValues() {
    let processor = makeProcessor(after: #"{"name"#)
    let input = (0..<Self.tokens.count).map { Float($0) * 0.5 - 3 }
    let row = processedRow(processor, logits: MLXArray(input).reshaped([1, input.count]))

    for index in row.indices {
      if index == Self.id("\"") || index == Self.id("\":") {
        XCTAssertEqual(row[index], input[index])
      } else {
        XCTAssertEqual(row[index], -.infinity)
      }
    }
  }

  func testProcessKeepsShapeAndDType() {
    let processor = makeProcessor()
    let logits = MLXArray.zeros([1, Self.tokens.count], dtype: .float16)
    let processed = processor.process(logits: logits)
    XCTAssertEqual(processed.shape, [1, Self.tokens.count])
    XCTAssertEqual(processed.dtype, .float16)
  }

  // MARK: - didSample

  func testDidSampleAdvancesTheAcceptor() {
    var processor = makeProcessor()
    let acceptor = BrujaJSONAcceptor(schema: Self.schema)

    processor.didSample(token: MLXArray([Int32(Self.id("{\""))]))
    XCTAssertEqual(
      processor.acceptor.state, acceptor.state(after: "{\"", from: acceptor.initialState))

    processor.didSample(token: MLXArray([Int32(Self.id("name"))]))
    processor.didSample(token: MLXArray([Int32(Self.id("\":"))]))
    XCTAssertEqual(
      processor.acceptor.state, acceptor.state(after: #"{"name":"#, from: acceptor.initialState))
  }

  func testDidSampleOfAMaskedTokenLeavesTheStateUnchanged() {
    var processor = makeProcessor(after: #"{"name":"Hunter"#)
    let before = processor.acceptor.state

    for text in ["caf\u{FFFD}", "", "\n", "\"}", "<|im_end|>"] {
      processor.didSample(token: MLXArray([Int32(Self.id(text))]))
      XCTAssertEqual(processor.acceptor.state, before, "\(text.debugDescription) moved the state")
    }
    processor.didSample(token: MLXArray([Int32(9999)]))
    XCTAssertEqual(processor.acceptor.state, before)
  }

  // MARK: - Mask cache

  func testMaskIsCachedPerAcceptorState() {
    var processor = makeProcessor(after: #"{"name":"Hunter"#)
    XCTAssertEqual(processor.vocabularyScanCount, 0)

    let first = processedRow(processor)
    XCTAssertEqual(processor.vocabularyScanCount, 1)

    // Same state again: no rescan.
    XCTAssertEqual(processedRow(processor), first)
    XCTAssertEqual(processor.vocabularyScanCount, 1)

    // More string content is the same acceptor state, so the mask is reused.
    processor.didSample(token: MLXArray([Int32(Self.id(" scout"))]))
    XCTAssertEqual(processedRow(processor), first)
    XCTAssertEqual(processor.vocabularyScanCount, 1)

    // A copy shares the cache.
    let copy = processor
    XCTAssertEqual(processedRow(copy), first)
    XCTAssertEqual(processor.vocabularyScanCount, 1)

    // A new state is scanned once.
    processor.didSample(token: MLXArray([Int32(Self.id("\","))]))
    XCTAssertNotEqual(processedRow(processor), first)
    XCTAssertEqual(processor.vocabularyScanCount, 2)
    _ = processedRow(processor)
    XCTAssertEqual(processor.vocabularyScanCount, 2)

    // A different logit width rebuilds the array, not the scan.
    _ = finiteIds(processor, width: Self.tokens.count + 4)
    XCTAssertEqual(processor.vocabularyScanCount, 2)
  }
}
