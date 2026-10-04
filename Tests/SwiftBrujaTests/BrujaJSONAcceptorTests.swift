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

  func testWhitespaceOtherThanTheOptionalSpaceRejected() {
    assertRejected(" ", after: "{")
    assertRejected(" ", after: "{\"age\"")
    assertRejected(" ", after: "{\"age\":null")
    assertRejected("\n", after: "{\"age\":null,")
    // Only U+0020 is the optional space.
    for character in ["\n", "\t", "\r\n", "\u{A0}"] as [Character] {
      assertRejected(character, after: "{\"age\":")
      assertRejected(character, after: "{\"age\":null,")
    }
    // No space after `[`, before `]`, or before the `}` of an item or of the object.
    let prefix =
      "{"
      + Self.stringKeysBeforeRelationships.map { "\"\($0)\":null" }.joined(separator: ",")
      + ",\"relationships\":"
    assertRejected(" ", after: prefix + "[")
    assertRejected(" ", after: prefix + "[{\"with\":null,\"nature\":null")
    assertRejected(" ", after: prefix + "[{\"with\":null,\"nature\":null}")
    assertRejected(" ", after: String(Self.personajeObject().dropLast()))
  }

  // MARK: - One optional space after `:` and `,`

  /// `text` with one space after every `:` and `,` that is outside a string.
  private static func spaced(_ text: String) -> String {
    var result = ""
    var inString = false
    var escaped = false
    for character in text {
      result.append(character)
      if inString {
        if escaped {
          escaped = false
        } else if character == "\\" {
          escaped = true
        } else if character == "\"" {
          inString = false
        }
      } else if character == "\"" {
        inString = true
      } else if character == ":" || character == "," {
        result.append(" ")
      }
    }
    return result
  }

  func testOneSpaceAfterColonAndCommaAccepted() {
    XCTAssertEqual(Self.spaced(#"{"a":"x:y,z","b":[1,2]}"#), #"{"a": "x:y,z", "b": [1, 2]}"#)
    assertAccepted(Self.spaced(Self.fullObject))
    assertAccepted(Self.spaced(Self.personajeObject()))
    // Each space is optional on its own: the two forms mix freely.
    assertAccepted(Self.personajeObject(["age": " \"52\"", "pronouns": " null"]))
    for text in [
      #"{"count": 0, "score": -1.5, "alive": true, "tags": ["a", "b"], "levels": [1, 20, -3], "home": {"city": "", "lat": 0.25}}"#,
      #"{"count": 7,"score":null, "alive": null,"tags":["a","b", "c"],"levels":[],"home": null}"#,
    ] {
      assertAccepted(text, schema: Self.mixedSchema)
    }
  }

  func testSecondSpaceAfterColonOrCommaRejected() {
    assertRejected(" ", after: "{\"age\": ")
    assertRejected(" ", after: "{\"age\": null, ")
    let schema = Self.mixedSchema
    // After a number that the comma ended, and between array items.
    assertRejected(" ", after: #"{"count": 1, "#, schema: schema)
    assertRejected(" ", after: #"{"count":1,"score":1,"alive":true,"tags":["a", "#, schema: schema)
    assertRejected(
      " ", after: #"{"count":1,"score":1,"alive":true,"tags":[],"levels":[1, "#, schema: schema)
    // The space is not a value: something must still follow it.
    assertRejected(",", after: "{\"age\": ")
    assertRejected("}", after: "{\"age\": null, ")
    assertRejected("]", after: #"{"count":1,"score":1,"alive":true,"tags":["a", "#, schema: schema)
  }

  func testNothingAcceptedAfterClosingBraceOfSpacedObject() {
    let complete = Self.spaced(Self.personajeObject())
    XCTAssertTrue(feed(complete).acceptor.isComplete)
    for character in [" ", "\n", ",", "}", "\"", "n"] as [Character] {
      assertRejected(character, after: complete)
    }
  }

  func testOptionalSpaceDoesNotChangeTheStateItLeadsTo() {
    // With or without the space, the same position: the state holds no trace of it.
    XCTAssertEqual(
      feed("{\"age\": \"abc").acceptor.state, feed("{\"age\":\"abc").acceptor.state)
    XCTAssertEqual(
      feed("{\"age\":null, \"pronouns\"").acceptor.state,
      feed("{\"age\":null,\"pronouns\"").acceptor.state)
    XCTAssertEqual(
      feed("{\"age\": null, \"pronouns\": ").acceptor.state,
      feed("{\"age\":null,\"pronouns\": ").acceptor.state)
    // Before the space and after it are different positions: only one takes a space.
    XCTAssertNotEqual(feed("{\"age\":").acceptor.state, feed("{\"age\": ").acceptor.state)
  }

  func testOptionalSpaceCountsTowardNoBound() {
    let schema = Self.boundedSchema
    // A string of exactly `maxLength` and arrays of exactly `maxItems`, spaced.
    assertAccepted(
      #"{"name": "abcde", "tags": ["a", "b", "c"], "pairs": [{"with": "abcd", "nature": "abcdef"}, {"with": "wxyz", "nature": null}]}"#,
      schema: schema)
    assertRejected("f", after: #"{"name": "abcde"#, schema: schema)
    assertRejected(",", after: #"{"name": null, "tags": ["a", "b", "c""#, schema: schema)
    // The counters read the same with the spaces as without.
    XCTAssertEqual(
      feed(#"{"name": "a"#, schema: schema).acceptor.counters,
      feed(#"{"name":"a"#, schema: schema).acceptor.counters)
    XCTAssertEqual(feed(#"{"name": "a"#, schema: schema).acceptor.counters.remainingLength, 4)
    XCTAssertEqual(
      feed(#"{"name": null, "tags": ["a", "b""#, schema: schema).acceptor.counters,
      feed(#"{"name":null,"tags":["a","b""#, schema: schema).acceptor.counters)
    XCTAssertEqual(
      feed(#"{"name": null, "tags": ["a", "#, schema: schema).acceptor.counters
        .fewestRemainingItems, 1)
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
    XCTAssertNotNil(acceptor.state(after: "{\"age\": ", from: start))
    XCTAssertNil(acceptor.state(after: "{\"age\":  ", from: start))
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

  // MARK: - Length bounds

  /// One bounded string, one bounded array of bounded strings, one bounded
  /// array of objects whose strings are bounded.
  private static let boundedSchema = BrujaJSONSchema([
    .string("name", maxLength: 5),
    .array("tags", of: .string(maxLength: 3), maxItems: 3),
    .array(
      "pairs", of: .object([.string("with", maxLength: 4), .string("nature", maxLength: 6)]),
      maxItems: 2),
  ])

  func testStringOfExactlyMaxLengthAccepted() {
    assertAccepted(#"{"name":"abcde","tags":null,"pairs":null}"#, schema: Self.boundedSchema)
    // Shorter is fine too.
    assertAccepted(#"{"name":"a","tags":null,"pairs":null}"#, schema: Self.boundedSchema)
  }

  func testStringOneCharacterOverMaxLengthRejected() {
    assertRejected("f", after: #"{"name":"abcde"#, schema: Self.boundedSchema)
    // At the bound nothing but the closing quote is accepted.
    for character in [" ", "\\", "é", ",", "}", "👍🏽"] as [Character] {
      assertRejected(character, after: #"{"name":"abcde"#, schema: Self.boundedSchema)
    }
    XCTAssertNil(feed(#"{"name":"abcde""#, schema: Self.boundedSchema).rejectedAt)
  }

  func testArrayOfExactlyMaxItemsAccepted() {
    assertAccepted(#"{"name":null,"tags":["a","b","c"],"pairs":null}"#, schema: Self.boundedSchema)
    assertAccepted(#"{"name":null,"tags":[],"pairs":null}"#, schema: Self.boundedSchema)
    assertAccepted(#"{"name":null,"tags":["a"],"pairs":null}"#, schema: Self.boundedSchema)
  }

  func testArrayOneItemOverMaxItemsRejected() {
    let full = #"{"name":null,"tags":["a","b","c""#
    assertRejected(",", after: full, schema: Self.boundedSchema)
    // After the last item nothing but `]` is accepted.
    for character in ["\"", "}", "[", "a"] as [Character] {
      assertRejected(character, after: full, schema: Self.boundedSchema)
    }
    XCTAssertNil(feed(full + "]", schema: Self.boundedSchema).rejectedAt)
    // Below the bound the comma is still legal.
    XCTAssertNil(feed(#"{"name":null,"tags":["a","b","#, schema: Self.boundedSchema).rejectedAt)
  }

  func testBoundedStringInsideArrayItemEnforced() {
    let open = #"{"name":null,"tags":null,"pairs":[{"with":""#
    assertRejected("e", after: open + "abcd", schema: Self.boundedSchema)
    // Each string of the item has its own bound.
    let second = open + #"abcd","nature":""#
    XCTAssertNil(feed(second + "abcdef", schema: Self.boundedSchema).rejectedAt)
    assertRejected("g", after: second + "abcdef", schema: Self.boundedSchema)
    // The bound starts again in the next item.
    let nextItem = second + #"abcdef"},{"with":""#
    XCTAssertNil(feed(nextItem + "wxyz", schema: Self.boundedSchema).rejectedAt)
    assertRejected("!", after: nextItem + "wxyz", schema: Self.boundedSchema)
    assertAccepted(
      #"{"name":null,"tags":null,"pairs":[{"with":"abcd","nature":"abcdef"},{"with":"wxyz","nature":null}]}"#,
      schema: Self.boundedSchema)
    // A string that is itself the array item.
    assertRejected("d", after: #"{"name":null,"tags":["abc"#, schema: Self.boundedSchema)
    assertRejected("d", after: #"{"name":null,"tags":["a","abc"#, schema: Self.boundedSchema)
  }

  func testSchemaWithNoBoundsAcceptsTenThousandCharacterString() {
    let long = String(repeating: "a", count: 10_000)
    XCTAssertEqual(long.count, 10_000)
    assertAccepted(Self.personajeObject(["backstory": "\"\(long)\""]))
    // And inside an array item.
    assertAccepted(
      Self.personajeObject(["relationships": "[{\"with\":\"\(long)\",\"nature\":null}]"]))
  }

  func testArrayItemsOverMaxItemsRejectedForObjectItems() {
    let item = #"{"with":"a","nature":null}"#
    let full = #"{"name":null,"tags":null,"pairs":["# + item + "," + item
    assertRejected(",", after: full, schema: Self.boundedSchema)
    assertAccepted(full + "]}", schema: Self.boundedSchema)
  }

  func testMaxLengthCountsEscapesAsWritten() {
    let schema = BrujaJSONSchema([.string("s", maxLength: 6)])
    // `\n` is two characters of JSON text: three of them fill the bound.
    assertAccepted(#"{"s":"\n\n\n"}"#, schema: schema)
    assertRejected("a", after: #"{"s":"\n\n\n"#, schema: schema)
    // `\u00e9` is six characters of JSON text and one decoded character.
    assertAccepted(#"{"s":"\u00e9"}"#, schema: schema)
    assertRejected("a", after: #"{"s":"\u00e9"#, schema: schema)
    // Written literally, the same letter counts one.
    assertAccepted("{\"s\":\"éééééé\"}", schema: schema)
    assertRejected("é", after: "{\"s\":\"éééééé", schema: schema)
  }

  func testEscapeThatDoesNotFitIsRejectedAtTheBackslash() {
    let schema = BrujaJSONSchema([.string("s", maxLength: 6)])
    // One character left: no escape fits.
    assertRejected("\\", after: #"{"s":"abcde"#, schema: schema)
    // Two left: a short escape fits, `\u` and its four digits do not.
    assertAccepted(#"{"s":"abcd\n"}"#, schema: schema)
    assertRejected("u", after: #"{"s":"abcd\"#, schema: schema)
    assertRejected("u", after: #"{"s":"a\"#, schema: schema)
    // After a rejected `u` the string can still finish.
    assertAccepted(#"{"s":"a\\bcd"}"#, schema: schema)
  }

  func testNullableStringCannotSpellNullWithItsLastCharacter() {
    // `"null"` cannot close, so at a bound of four the last `l` is refused.
    let four = BrujaJSONSchema([.string("s", maxLength: 4)])
    assertRejected("l", after: #"{"s":"nul"#, schema: four)
    assertAccepted(#"{"s":"nul"}"#, schema: four)
    assertAccepted(#"{"s":"nulx"}"#, schema: four)
    // With room for one more character, `null` is content like any other.
    let five = BrujaJSONSchema([.string("s", maxLength: 5)])
    assertAccepted(#"{"s":"nulls"}"#, schema: five)
    // A string that is not nullable may be exactly `null`.
    assertAccepted(
      #"{"s":"null"}"#, schema: BrujaJSONSchema([.string("s", maxLength: 4, nullable: false)]))
  }

  func testBoundCountersAreNotPartOfTheState() {
    let short = feed(#"{"name":"a"#, schema: Self.boundedSchema)
    let long = feed(#"{"name":"abcde"#, schema: Self.boundedSchema)
    XCTAssertEqual(short.acceptor.state, long.acceptor.state)
    XCTAssertNotEqual(short.acceptor.counters, long.acceptor.counters)
    XCTAssertEqual(short.acceptor.counters.remainingLength, 4)
    XCTAssertEqual(long.acceptor.counters.remainingLength, 0)

    let one = feed(#"{"name":null,"tags":["a""#, schema: Self.boundedSchema)
    let three = feed(#"{"name":null,"tags":["a","b","c""#, schema: Self.boundedSchema)
    XCTAssertEqual(one.acceptor.state, three.acceptor.state)
    XCTAssertEqual(one.acceptor.counters.fewestRemainingItems, 2)
    XCTAssertEqual(three.acceptor.counters.fewestRemainingItems, 0)

    // Outside a bounded string and a bounded array there is nothing to count.
    let outside = feed(#"{"name":"abc","tags":["a"],"#, schema: Self.boundedSchema)
    XCTAssertNil(outside.acceptor.counters.remainingLength)
    XCTAssertNil(outside.acceptor.counters.fewestRemainingItems)
    XCTAssertNil(feed("{\"age\":\"abc").acceptor.counters.remainingLength)
  }

  func testItemCountStartsAgainForAnArrayInsideAnArray() {
    let schema = BrujaJSONSchema([
      .array("rows", of: .array(of: .integer, maxItems: 2), maxItems: 2)
    ])
    assertAccepted(#"{"rows":[[1,2],[3,4]]}"#, schema: schema)
    assertRejected(",", after: #"{"rows":[[1,2"#, schema: schema)
    assertRejected(",", after: #"{"rows":[[1,2],[3,4"#, schema: schema)
    assertRejected(",", after: #"{"rows":[[1,2],[3,4]"#, schema: schema)
    // The inner count is the fewest left while the inner array is open.
    XCTAssertEqual(
      feed(#"{"rows":[[1,2"#, schema: schema).acceptor.counters.fewestRemainingItems, 0)
    XCTAssertEqual(
      feed(#"{"rows":[[1,2]"#, schema: schema).acceptor.counters.fewestRemainingItems, 1)
  }

  func testNonMutatingStateAfterTextEnforcesBoundsInsideTheText() {
    let acceptor = BrujaJSONAcceptor(schema: Self.boundedSchema)
    let start = acceptor.initialState
    XCTAssertNotNil(acceptor.state(after: #"{"name":"abcde""#, from: start))
    XCTAssertNil(acceptor.state(after: #"{"name":"abcdef"#, from: start))
    XCTAssertNil(acceptor.state(after: #"{"name":null,"tags":["a","b","c","#, from: start))
  }

  func testResetClearsTheCounters() {
    var acceptor = feed(#"{"name":"abcde"#, schema: Self.boundedSchema).acceptor
    let fresh = BrujaJSONAcceptor(schema: Self.boundedSchema)
    XCTAssertNotEqual(acceptor.counters, fresh.counters)
    acceptor.reset()
    XCTAssertEqual(acceptor.counters, fresh.counters)
    XCTAssertEqual(acceptor.state, fresh.state)
  }

  func testBoundedFactoriesBuildTheBoundedKinds() {
    XCTAssertEqual(
      BrujaJSONSchema.Property.string("a", maxLength: 7).kind, .boundedString(maxLength: 7))
    XCTAssertEqual(BrujaJSONSchema.Kind.string(maxLength: 7), .boundedString(maxLength: 7))
    XCTAssertEqual(BrujaJSONSchema.Property.string("a").kind, .string)
    XCTAssertEqual(
      BrujaJSONSchema.Property.array("a", of: .string, maxItems: 3).kind,
      .array(of: .string, maxItems: 3))
    XCTAssertEqual(
      BrujaJSONSchema.Property.array("a", of: .string).kind, .array(of: .string, maxItems: nil))
  }
}
