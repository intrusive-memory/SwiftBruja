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

  // MARK: - Length bounds

  /// Every string and every array is bounded. No key starts with the filler letter.
  private static let boundedSchema = BrujaJSONSchema([
    .string("name", maxLength: 5),
    .array("tags", of: .string(maxLength: 3), maxItems: 4),
    .array(
      "note", of: .object([.string("name", maxLength: 2), .string("tags", maxLength: 7)]),
      maxItems: 3),
  ])

  /// The fake vocabulary plus a one-letter filler token.
  private static let fillerId = tokens.count
  private static let fillerVocabulary: [Int: String] = vocabulary.merging([fillerId: "z"]) { $1 }

  /// A processor for `schema` whose acceptor has consumed `prefix`, counters included.
  private func makeBoundedProcessor(
    schema: BrujaJSONSchema = BrujaJSONLogitProcessorTests.boundedSchema,
    vocabulary: [Int: String] = BrujaJSONLogitProcessorTests.fillerVocabulary,
    after prefix: String = "", file: StaticString = #filePath, line: UInt = #line
  ) -> BrujaJSONLogitProcessor {
    var acceptor = BrujaJSONAcceptor(schema: schema)
    for character in prefix {
      XCTAssertTrue(
        acceptor.advance(character), "the acceptor rejected \(character) of the prefix \(prefix)",
        file: file, line: line)
    }
    return BrujaJSONLogitProcessor(
      acceptor: acceptor, vocabulary: vocabulary, eosTokenIds: Self.eosTokenIds)
  }

  /// Every string in a parsed JSON value, with the key path that leads to it.
  private func strings(in value: Any, at path: String = "") -> [(path: String, value: String)] {
    if let string = value as? String { return [(path, string)] }
    if let array = value as? [Any] {
      return array.flatMap { strings(in: $0, at: path + "[]") }
    }
    if let object = value as? [String: Any] {
      return object.flatMap { strings(in: $0.value, at: path + "." + $0.key) }
    }
    return []
  }

  func testFillerPreferringSelectionCompletesWithinBounds() throws {
    var processor = makeBoundedProcessor()
    let width = Self.tokens.count + 1

    // The filler first, always. After it, whatever keeps a value going: open
    // an array, an object or a string, or add another item. Closing an array,
    // `null` and EOS are only taken when nothing else is left.
    let preference =
      [Self.fillerId] + ["[", "{\"", "{", "\"", ",\"", ",", ":"].map(Self.id)

    var decoded = ""
    var reachedEOS = false
    var fillerCount = 0
    for _ in 0..<400 {
      let row = processedRow(processor, logits: uniformLogits(width: width))
      let finite = row.indices.filter { row[$0].isFinite }
      XCTAssertFalse(finite.isEmpty, "every token is masked after \(decoded)")
      let token = try XCTUnwrap(preference.first { finite.contains($0) } ?? finite.first)

      processor.didSample(token: MLXArray([Int32(token)]))
      if Self.eosTokenIds.contains(token) {
        reachedEOS = true
        break
      }
      if token == Self.fillerId { fillerCount += 1 }
      decoded += try XCTUnwrap(Self.fillerVocabulary[token])
    }

    XCTAssertTrue(reachedEOS, "generation did not end in 400 steps: \(decoded)")
    XCTAssertTrue(processor.isComplete)
    XCTAssertEqual(
      decoded,
      #"{"name":"zzzzz","tags":["zzz","zzz","zzz","zzz"],"note":["#
        + #"{"name":"zz","tags":"zzzzzzz"},{"name":"zz","tags":"zzzzzzz"},"#
        + #"{"name":"zz","tags":"zzzzzzz"}]}"#)
    // The filler was taken every time it was on offer: every string is full.
    XCTAssertEqual(fillerCount, 5 + 4 * 3 + 3 * (2 + 7))

    let object = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: Data(decoded.utf8)) as? [String: Any])

    // No string is longer than its bound.
    let bounds = [".name": 5, ".tags[]": 3, ".note[].name": 2, ".note[].tags": 7]
    let found = strings(in: object)
    XCTAssertEqual(found.count, 1 + 4 + 3 * 2)
    for (path, value) in found {
      let bound = try XCTUnwrap(bounds[path], "no bound listed for \(path)")
      XCTAssertLessThanOrEqual(value.count, bound, "\(path) is longer than its bound: \(value)")
    }

    // No array is longer than its item count.
    let tags = try XCTUnwrap(object["tags"] as? [Any])
    XCTAssertLessThanOrEqual(tags.count, 4)
    let note = try XCTUnwrap(object["note"] as? [Any])
    XCTAssertLessThanOrEqual(note.count, 3)

    // The text also satisfies a fresh acceptor, character by character.
    var acceptor = BrujaJSONAcceptor(schema: Self.boundedSchema)
    for character in decoded {
      XCTAssertTrue(acceptor.advance(character))
    }
    XCTAssertTrue(acceptor.isComplete)
  }

  func testTokenThatWouldCarryAStringPastItsBoundIsMasked() {
    let schema = BrujaJSONSchema([.string("name", maxLength: 8), .string("note", maxLength: 8)])

    // Six characters written, two left.
    let nearBound = makeBoundedProcessor(schema: schema, after: #"{"name":"Hunter"#)
    assertMasked(" scout", in: nearBound)
    assertMasked("able", in: nearBound)
    assertMasked("Hunter", in: nearBound)
    assertAllowed("42", in: nearBound)
    assertAllowed("7", in: nearBound)
    assertAllowed("\",", in: nearBound)
    assertAllowed("\"", in: nearBound)

    // At the bound only the tokens that close the string are left.
    let atBound = makeBoundedProcessor(schema: schema, after: #"{"name":"Hunter42"#)
    XCTAssertEqual(finiteIds(atBound), [Self.id("\","), Self.id("\"")])

    // Far from the bound the same tokens are allowed.
    let early = makeBoundedProcessor(schema: schema, after: #"{"name":"7"#)
    assertAllowed(" scout", in: early)
    assertAllowed("able", in: early)
  }

  func testTokenThatSpansIntoABoundedStringIsMaskedWhenItOverflowsIt() {
    // `"null"` aside, the vocabulary has no token that opens a string and
    // fills it, so add one.
    let opener = Self.tokens.count
    let vocabulary = Self.vocabulary.merging([opener: "\"Hunter"]) { $1 }

    let tight = makeBoundedProcessor(
      schema: BrujaJSONSchema([.string("name", maxLength: 5)]), vocabulary: vocabulary,
      after: #"{"name":"#)
    XCTAssertFalse(finiteIds(tight, width: opener + 1).contains(opener))

    let roomy = makeBoundedProcessor(
      schema: BrujaJSONSchema([.string("name", maxLength: 6)]), vocabulary: vocabulary,
      after: #"{"name":"#)
    XCTAssertTrue(finiteIds(roomy, width: opener + 1).contains(opener))
  }

  func testTokenThatWouldCarryAnArrayPastItsItemCountIsMasked() {
    let schema = BrujaJSONSchema([.array("tags", of: .string, maxItems: 2)])

    // Inside the first item: `",` closes it and starts the second.
    let inFirst = makeBoundedProcessor(schema: schema, after: #"{"tags":["a"#)
    assertAllowed("\",", in: inFirst)
    assertAllowed("\"]", in: inFirst)
    // A comma that is string content is not an item.
    assertAllowed(",", in: inFirst)

    // Inside the last item: `",` would start a third.
    let inLast = makeBoundedProcessor(schema: schema, after: #"{"tags":["a","b"#)
    assertMasked("\",", in: inLast)
    assertAllowed("\"]", in: inLast)
    assertAllowed("\"", in: inLast)
    assertAllowed(",", in: inLast)
    assertAllowed(",\"", in: inLast)

    // After the last item only `]` is left.
    let afterLast = makeBoundedProcessor(schema: schema, after: #"{"tags":["a","b""#)
    XCTAssertEqual(finiteIds(afterLast), [Self.id("]")])

    // After the first item the comma tokens are still there.
    let afterFirst = makeBoundedProcessor(schema: schema, after: #"{"tags":["a""#)
    XCTAssertEqual(finiteIds(afterFirst), [Self.id(","), Self.id(",\""), Self.id("]")])
  }

  func testBoundFilterDoesNotRescanTheVocabulary() {
    // Every item of the array is written in the same acceptor state.
    let schema = BrujaJSONSchema([.array("tags", of: .string(maxLength: 8))])
    var processor = makeBoundedProcessor(schema: schema, after: #"{"tags":["7"#)

    let early = processedRow(processor)
    XCTAssertEqual(processor.vocabularyScanCount, 1)
    XCTAssertEqual(early[Self.id("able")], 0)
    XCTAssertEqual(early[Self.id(" scout")], 0)

    // Same state, nearer the bound: the mask narrows, the vocabulary is not scanned again.
    processor.didSample(token: MLXArray([Int32(Self.id("able"))]))
    processor.didSample(token: MLXArray([Int32(Self.id("7"))]))
    let near = processedRow(processor)
    XCTAssertNotEqual(near, early)
    XCTAssertEqual(near[Self.id("able")], -.infinity)
    XCTAssertEqual(near[Self.id("42")], 0)
    XCTAssertEqual(processor.vocabularyScanCount, 1)

    processor.didSample(token: MLXArray([Int32(Self.id("42"))]))
    XCTAssertEqual(finiteIds(processor), [Self.id("\"]"), Self.id("\","), Self.id("\"")])
    XCTAssertEqual(processor.vocabularyScanCount, 1)

    // The narrowed mask did not replace the cached one: the same state in the
    // next item, with its bound hardly used, gets the wide mask back.
    let state = processor.acceptor.state
    processor.didSample(token: MLXArray([Int32(Self.id("\","))]))
    processor.didSample(token: MLXArray([Int32(Self.id("\""))]))
    processor.didSample(token: MLXArray([Int32(Self.id("7"))]))
    XCTAssertEqual(processor.acceptor.state, state)
    XCTAssertEqual(processedRow(processor), early)
    XCTAssertEqual(processor.vocabularyScanCount, 1)
  }

  // MARK: - Repetition penalty

  /// A processor with a repetition penalty whose acceptor has consumed `prefix`.
  private func makePenalisedProcessor(
    after prefix: String, penalty: Float = 1.5, file: StaticString = #filePath, line: UInt = #line
  ) -> BrujaJSONLogitProcessor {
    var acceptor = BrujaJSONAcceptor(schema: Self.schema)
    if let state = acceptor.state(after: prefix, from: acceptor.initialState) {
      acceptor.state = state
    } else {
      XCTFail("the acceptor rejected the prefix \(prefix)", file: file, line: line)
    }
    return BrujaJSONLogitProcessor(
      acceptor: acceptor, vocabulary: Self.vocabulary, eosTokenIds: Self.eosTokenIds,
      repetitionContext: RepetitionContext(repetitionPenalty: penalty, repetitionContextSize: 64))
  }

  func testMaskedTokenStaysMaskedWithTheRepetitionPenaltyOn() {
    // `",` is legal at the end of the value, is sampled, and is then both in the
    // penalty's context and illegal at the start of the next key.
    var processor = makePenalisedProcessor(after: #"{"name":"Hunter"#)
    let sampled = Self.id("\",")
    processor.didSample(token: MLXArray([Int32(sampled)]))

    for value: Float in [3, -3] {
      let logits = MLXArray([Float](repeating: value, count: Self.tokens.count))
        .reshaped([1, Self.tokens.count])
      let row = processedRow(processor, logits: logits)
      XCTAssertEqual(row[sampled], -.infinity, "the sampled token is not masked at \(value)")
      // Every token the mask alone rejects is still rejected.
      XCTAssertEqual(
        row.indices.filter { row[$0].isFinite },
        finiteIds(makeProcessor(after: #"{"name":"Hunter","#)),
        "the penalty changed the mask at \(value)")
    }

    // The prompt reaches the penalty too, and a masked prompt token stays masked.
    var prompted = makePenalisedProcessor(after: #"{"name":"Hunter"#)
    prompted.prompt(MLXArray([Int32(Self.id("\"}")), Int32(Self.id(" scout"))]))
    let row = processedRow(
      prompted,
      logits: MLXArray([Float](repeating: 3, count: Self.tokens.count))
        .reshaped([1, Self.tokens.count]))
    XCTAssertEqual(row[Self.id("\"}")], -.infinity)
    XCTAssertEqual(row[Self.id(" scout")], 2, accuracy: 1e-5)
    XCTAssertEqual(row[Self.id("able")], 3)
  }

  func testJustSampledTokenEndsLowerThanAnEqualAllowedToken() {
    // Inside a string, ` scout` and `able` are both legal before and after ` scout`.
    var processor = makePenalisedProcessor(after: #"{"name":"Hunter"#)
    let sampled = Self.id(" scout")
    let other = Self.id("able")

    for value: Float in [3, -3] {
      let logits = MLXArray([Float](repeating: value, count: Self.tokens.count))
        .reshaped([1, Self.tokens.count])
      let before = processedRow(processor, logits: logits)
      XCTAssertEqual(before[sampled], value)
      XCTAssertEqual(before[other], value)
    }

    processor.didSample(token: MLXArray([Int32(sampled)]))

    for value: Float in [3, -3] {
      let logits = MLXArray([Float](repeating: value, count: Self.tokens.count))
        .reshaped([1, Self.tokens.count])
      let after = processedRow(processor, logits: logits)
      XCTAssertTrue(after[sampled].isFinite)
      XCTAssertEqual(after[other], value, "the token that was not sampled moved at \(value)")
      XCTAssertLessThan(after[sampled], after[other], "no penalty at \(value)")
    }

    // With no repetition context the two stay equal.
    var plain = makeProcessor(after: #"{"name":"Hunter"#)
    plain.didSample(token: MLXArray([Int32(sampled)]))
    let row = processedRow(
      plain,
      logits: MLXArray([Float](repeating: 3, count: Self.tokens.count))
        .reshaped([1, Self.tokens.count]))
    XCTAssertEqual(row[sampled], row[other])
  }

  func testDidSampleOfATokenPastTheBoundLeavesThePositionUnchanged() {
    let schema = BrujaJSONSchema([.string("name", maxLength: 8)])
    var processor = makeBoundedProcessor(schema: schema, after: #"{"name":"Hunter"#)
    let state = processor.acceptor.state
    let counters = processor.acceptor.counters

    processor.didSample(token: MLXArray([Int32(Self.id(" scout"))]))
    XCTAssertEqual(processor.acceptor.state, state)
    XCTAssertEqual(processor.acceptor.counters, counters)

    processor.didSample(token: MLXArray([Int32(Self.id("42"))]))
    XCTAssertEqual(processor.acceptor.counters.remainingLength, 0)
  }
}
