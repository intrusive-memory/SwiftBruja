import XCTest

@testable import SwiftBruja

final class BrujaJSONAcceptorTests: XCTestCase {

  // MARK: - Fixtures

  /// The schema Personaje sends: fourteen fields, all nullable.
  private static let personajeSchema = BrujaJSONSchema([
    .string("age"),
    .string("pronouns"),
    .string("occupation"),
    .string("languages"),
    .string("logline"),
    .string("sampleLine"),
    .string("appearance"),
    .string("wardrobe"),
    .string("personality"),
    .string("backstory"),
    .string("arc"),
    .array("relationships", of: .object([.string("with"), .string("nature")])),
    .string("voiceAndSpeech"),
    .array("canonFacts", of: .object([.string("fact"), .string("quote")])),
  ])

  private static let stringKeysBeforeRelationships = [
    "age", "pronouns", "occupation", "languages", "logline", "sampleLine", "appearance",
    "wardrobe", "personality", "backstory", "arc",
  ]

  /// A compact Personaje object. `overrides` replaces the raw JSON text of a value.
  private static func personajeObject(_ overrides: [String: String] = [:]) -> String {
    let keys = stringKeysBeforeRelationships + ["relationships", "voiceAndSpeech", "canonFacts"]
    let members = keys.map { "\"\($0)\":\(overrides[$0] ?? "null")" }
    return "{" + members.joined(separator: ",") + "}"
  }

  private static let fullObject = personajeObject([
    "age": "\"mid-40s\"",
    "pronouns": "\"she/her\"",
    "occupation": "\"Bounty hunter\"",
    "languages": "\"English, some Spanish\"",
    "logline": "\"A hunter who wants out, one job at a time.\"",
    "sampleLine": "\"I don't chase. I wait.\"",
    "appearance": "\"Lean, weathered, a scar over the left eye\"",
    "wardrobe": "\"Duster coat; boots that have seen three deserts\"",
    "personality": "\"Dry, patient, allergic to small talk\"",
    "backstory": "\"Ex-marshal. Left after the Tucson job went wrong.\"",
    "arc": "\"Learns to trust a partner — slowly\"",
    "relationships":
      "[{\"with\":\"MARLOWE\",\"nature\":\"Reluctant partner\"},{\"with\":\"THE JUDGE\",\"nature\":null}]",
    "voiceAndSpeech": "\"Low, clipped, never raises her voice\"",
    "canonFacts": "[{\"fact\":\"Carries a 1911\",\"quote\":\"It was my father's.\"}]",
  ])

  /// Feeds `text` to a fresh Personaje acceptor and stops at the first rejected character.
  private func feed(
    _ text: String, schema: BrujaJSONSchema = BrujaJSONAcceptorTests.personajeSchema
  ) -> (accepted: Int, rejectedAt: Character?, acceptor: BrujaJSONAcceptor) {
    var acceptor = BrujaJSONAcceptor(schema: schema)
    var accepted = 0
    for character in text {
      guard acceptor.advance(character) else { return (accepted, character, acceptor) }
      accepted += 1
    }
    return (accepted, nil, acceptor)
  }

  private func assertAccepted(
    _ text: String, schema: BrujaJSONSchema = BrujaJSONAcceptorTests.personajeSchema,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    let result = feed(text, schema: schema)
    XCTAssertNil(
      result.rejectedAt,
      "rejected after \(result.accepted) characters: \(String(text.prefix(result.accepted)))",
      file: file, line: line)
    XCTAssertTrue(result.acceptor.isComplete, "object did not close", file: file, line: line)
    XCTAssertNoThrow(
      try JSONSerialization.jsonObject(with: Data(text.utf8)), "fixture is not valid JSON",
      file: file, line: line)
  }

  /// Asserts that `prefix` is accepted in full and that `next` is then rejected.
  private func assertRejected(
    _ next: Character, after prefix: String,
    schema: BrujaJSONSchema = BrujaJSONAcceptorTests.personajeSchema,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    let result = feed(prefix, schema: schema)
    XCTAssertNil(
      result.rejectedAt,
      "prefix rejected after \(result.accepted) characters: \(String(prefix.prefix(result.accepted)))",
      file: file, line: line)
    var acceptor = result.acceptor
    let before = acceptor.state
    XCTAssertFalse(
      acceptor.advance(next), "accepted \(next) after \(prefix)", file: file, line: line)
    XCTAssertEqual(
      acceptor.state, before, "a rejected character moved the state", file: file, line: line)
  }

  // MARK: - Accepted objects

  func testFullValidObjectAccepted() {
    assertAccepted(Self.fullObject)
  }

  func testAllNullObjectAccepted() {
    assertAccepted(Self.personajeObject())
  }

  // MARK: - "Nothing" is JSON null, never a string

  func testNullAsStringValueRejected() {
    // Rejected at the closing quote, not before.
    assertRejected("\"", after: "{\"age\":\"null")
    // The same rule holds inside array elements.
    let prefix = Self.stringKeysBeforeRelationships.map { "\"\($0)\":null" }.joined(separator: ",")
    assertRejected("\"", after: "{" + prefix + ",\"relationships\":[{\"with\":\"null")
  }

  func testEmptyStringValueRejected() {
    assertRejected("\"", after: "{\"age\":\"")
  }

  func testNullableAsStringValueAccepted() {
    assertAccepted(Self.personajeObject(["age": "\"nullable\""]))
    assertAccepted(Self.personajeObject(["age": "\"nul\"", "pronouns": "\"nulls\""]))
  }

  // MARK: - Shape

  func testMissingKeyRejected() {
    // `pronouns` skipped: the key after `age` must be `pronouns`.
    assertRejected("o", after: "{\"age\":null,\"")
    // The object cannot close before the last key.
    assertRejected("}", after: "{\"age\":null")
    // The first key cannot be skipped either.
    assertRejected("p", after: "{\"")
    assertRejected("}", after: "{")
  }

  func testExtraKeyRejected() {
    let complete = Self.personajeObject()
    let beforeClose = String(complete.dropLast())
    // Nothing may follow the last property but the closing brace.
    assertRejected(",", after: beforeClose)
    // An unknown key in the middle is rejected at its first differing character.
    assertRejected("n", after: "{\"age\":null,\"")
    // An unknown key inside an array element.
    let prefix = Self.stringKeysBeforeRelationships.map { "\"\($0)\":null" }.joined(separator: ",")
    assertRejected(
      ",", after: "{" + prefix + ",\"relationships\":[{\"with\":null,\"nature\":null")
  }

  func testWrongShapeRelationshipsAsObjectRejected() {
    let prefix = Self.stringKeysBeforeRelationships.map { "\"\($0)\":null" }.joined(separator: ",")
    let beforeValue = "{" + prefix + ",\"relationships\":"
    assertRejected("{", after: beforeValue)
    assertRejected("\"", after: beforeValue)
    // And a string where the array's element object belongs.
    assertRejected("\"", after: beforeValue + "[")
    // A string property does not take an array or a number.
    assertRejected("[", after: "{\"age\":")
    assertRejected("4", after: "{\"age\":")
  }

  func testAnyCharacterAfterClosingBraceRejected() {
    let complete = Self.personajeObject()
    XCTAssertTrue(feed(complete).acceptor.isComplete)
    for character in ["\n", " ", "}", "{", ",", "\"", "a", "n", "`", "\r\n", "\t"] as [Character] {
      assertRejected(character, after: complete)
    }
  }

  func testIsCompleteOnlyAfterTopLevelObjectCloses() {
    let complete = Self.fullObject
    var acceptor = BrujaJSONAcceptor(schema: Self.personajeSchema)
    XCTAssertFalse(acceptor.isComplete)
    for character in complete.dropLast() {
      XCTAssertTrue(acceptor.advance(character))
      // Nested objects close before the end; none of them completes the acceptor.
      XCTAssertFalse(acceptor.isComplete)
    }
    XCTAssertTrue(acceptor.advance("}"))
    XCTAssertTrue(acceptor.isComplete)
  }

  // MARK: - Strings

  func testEscapedQuotesAndUnicodeEscapesAccepted() {
    assertAccepted(
      Self.personajeObject([
        "age": #""she said \"no\" twice""#,
        "pronouns": #""café é—A""#,
        "occupation": #""\\ \/ \b \f \n \r \t""#,
        "languages": #""\"""#,
        "logline": "\"café — 日本語 👍🏽\"",
      ]))
  }

  func testMalformedEscapesRejected() {
    assertRejected("x", after: #"{"age":"\"#)
    assertRejected("g", after: #"{"age":"\u00"#)
    assertRejected("\"", after: #"{"age":"\u00e"#)
    // Surrogate escapes are not allowed; a lone one would not decode.
    assertRejected("8", after: #"{"age":"\ud"#)
    assertRejected("c", after: #"{"age":"\uD"#)
    // `퟿` is the last scalar below the surrogate range.
    XCTAssertNil(feed(#"{"age":"퟿""#).rejectedAt)
  }

  func testRawControlCharactersInStringRejected() {
    assertRejected("\n", after: "{\"age\":\"a")
    assertRejected("\t", after: "{\"age\":\"a")
    assertRejected("\r\n", after: "{\"age\":\"a")
  }

  func testQuoteWithCombiningMarkIsNotStringContent() {
    // One Character, two scalars: a quote carrying a combining acute accent.
    let character: Character = "\"\u{301}"
    XCTAssertEqual(character.unicodeScalars.count, 2)
    assertRejected(character, after: "{\"age\":\"a")
  }

  func testOptionalWhitespaceRejected() {
    assertRejected(" ", after: "{")
    assertRejected(" ", after: "{\"age\"")
    assertRejected(" ", after: "{\"age\":")
    assertRejected(" ", after: "{\"age\":null")
    assertRejected("\n", after: "{\"age\":null,")
  }

  // MARK: - State

  func testStateInsideStringDoesNotGrowWithText() {
    let short = feed("{\"age\":\"abcde")
    let long = feed("{\"age\":\"abcdefghij")
    XCTAssertNil(short.rejectedAt)
    XCTAssertNil(long.rejectedAt)
    XCTAssertEqual(short.acceptor.state, long.acceptor.state)
    XCTAssertEqual(short.acceptor.state.hashValue, long.acceptor.state.hashValue)
  }

  func testStatesThatAcceptDifferentContinuationsDiffer() {
    // After `null` the closing quote is illegal; after `nulls` it is legal.
    XCTAssertNotEqual(
      feed("{\"age\":\"null").acceptor.state, feed("{\"age\":\"nulls").acceptor.state)
    // Same text, different property: what follows the closing quote differs.
    XCTAssertNotEqual(
      feed("{\"age\":\"abc").acceptor.state,
      feed("{\"age\":null,\"pronouns\":\"abc").acceptor.state)
  }

  func testStateDoesNotGrowWithArrayLength() {
    let prefix =
      "{"
      + Self.stringKeysBeforeRelationships.map { "\"\($0)\":null" }.joined(separator: ",")
      + ",\"relationships\":["
    let element = "{\"with\":\"A\",\"nature\":\"B\"}"
    let one = feed(prefix + element)
    let three = feed(prefix + [element, element, element].joined(separator: ","))
    XCTAssertNil(one.rejectedAt)
    XCTAssertNil(three.rejectedAt)
    XCTAssertEqual(one.acceptor.state, three.acceptor.state)
  }

  func testStateCanBeSavedAndRestored() {
    var acceptor = BrujaJSONAcceptor(schema: Self.personajeSchema)
    XCTAssertEqual(acceptor.state, acceptor.initialState)
    for character in "{\"age\":" { XCTAssertTrue(acceptor.advance(character)) }
    let saved = acceptor.state

    for character in "\"forty\"" { XCTAssertTrue(acceptor.advance(character)) }
    XCTAssertNotEqual(acceptor.state, saved)

    acceptor.state = saved
    for character in "null,\"pronouns\"" { XCTAssertTrue(acceptor.advance(character)) }

    acceptor.reset()
    XCTAssertEqual(acceptor.state, acceptor.initialState)
    XCTAssertTrue(acceptor.advance("{"))
  }

  func testNonMutatingStateAfterText() {
    let acceptor = BrujaJSONAcceptor(schema: Self.personajeSchema)
    let start = acceptor.initialState
    // A token that spans structural boundaries.
    let afterKey = acceptor.state(after: "{\"age\":", from: start)
    XCTAssertNotNil(afterKey)
    XCTAssertNil(acceptor.state(after: "{\"age\": ", from: start))
    XCTAssertNil(acceptor.state(after: "{\"pronouns\":", from: start))
    XCTAssertEqual(acceptor.state, start, "the non-mutating query moved the acceptor")

    let complete = acceptor.state(after: Self.fullObject, from: start)
    XCTAssertEqual(complete.map(acceptor.isComplete), true)
    XCTAssertEqual(afterKey.map(acceptor.isComplete), false)
  }

  // MARK: - Other shapes the schema type can describe

  private static let mixedSchema = BrujaJSONSchema([
    .integer("count", nullable: false),
    .number("score"),
    .boolean("alive"),
    .array("tags", of: .string),
    .array("levels", of: .integer),
    .object("home", [.string("city", nullable: false), .number("lat")]),
  ])

  func testMixedKindsAccepted() {
    let valid = [
      #"{"count":0,"score":-1.5e+10,"alive":true,"tags":["a","b"],"levels":[1,20,-3],"home":{"city":"","lat":0.25}}"#,
      #"{"count":-42,"score":null,"alive":false,"tags":[],"levels":[],"home":null}"#,
      #"{"count":7,"score":3E2,"alive":null,"tags":null,"levels":null,"home":{"city":"null","lat":null}}"#,
    ]
    for text in valid {
      assertAccepted(text, schema: Self.mixedSchema)
    }
  }

  func testMixedKindsRejected() {
    let schema = Self.mixedSchema
    // A non-nullable property does not take null.
    assertRejected("n", after: #"{"count":"#, schema: schema)
    // An integer takes no fraction, no exponent, no leading zero.
    assertRejected(".", after: #"{"count":1"#, schema: schema)
    assertRejected("e", after: #"{"count":1"#, schema: schema)
    assertRejected("1", after: #"{"count":0"#, schema: schema)
    // A number needs a digit after the sign, the point and the exponent mark.
    assertRejected(",", after: #"{"count":1,"score":-"#, schema: schema)
    assertRejected(",", after: #"{"count":1,"score":1."#, schema: schema)
    assertRejected(",", after: #"{"count":1,"score":1e"#, schema: schema)
    // Booleans are spelled out exactly.
    assertRejected("T", after: #"{"count":1,"score":1,"alive":"#, schema: schema)
    assertRejected("u", after: #"{"count":1,"score":1,"alive":t"#, schema: schema)
    // Array elements are never null, and there is no trailing comma.
    assertRejected("n", after: #"{"count":1,"score":1,"alive":true,"tags":["#, schema: schema)
    assertRejected("]", after: #"{"count":1,"score":1,"alive":true,"tags":["a","#, schema: schema)
    assertRejected(
      "\"", after: #"{"count":1,"score":1,"alive":true,"tags":[],"levels":["#, schema: schema)
  }

  func testEmptySchemaAcceptsOnlyEmptyObject() {
    let schema = BrujaJSONSchema([])
    assertAccepted("{}", schema: schema)
    assertRejected("\"", after: "{", schema: schema)
  }

  func testKeyNeedingEscapeIsWrittenEscaped() {
    let schema = BrujaJSONSchema([.string("a\"b")])
    assertAccepted(#"{"a\"b":"x"}"#, schema: schema)
  }

  func testSchemaIsAValueType() {
    var schema = Self.personajeSchema
    XCTAssertEqual(schema.properties.count, 14)
    XCTAssertEqual(schema.properties.map(\.name).first, "age")
    XCTAssertTrue(schema.properties.allSatisfy(\.isNullable))
    schema.properties.removeLast()
    XCTAssertNotEqual(schema, Self.personajeSchema)
    XCTAssertEqual(
      BrujaJSONSchema(properties: [BrujaJSONSchema.Property("x", .boolean, nullable: false)]),
      BrujaJSONSchema([.boolean("x", nullable: false)]))
  }
}
