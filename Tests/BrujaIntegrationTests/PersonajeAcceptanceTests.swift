import Foundation
import SwiftAcervo
import XCTest

@testable import SwiftBruja

/// Acceptance tests for what Personaje needs from SwiftBruja (BR-P1 … BR-P4).
///
/// Every test here drives real MLX inference against Personaje's default model, so the class
/// skips when that model is not reachable from the test process. Under the SANDBOXED
/// `xcodebuild test` host the App Group container is unreadable and the tests skip; run them
/// through `make test-personaje`, which uses the unsandboxed `xcrun xctest` host with
/// `ACERVO_APP_GROUP_ID` set.
///
/// **Requirements:** Apple Silicon and the default model present in the
/// `group.intrusive-memory.models` App Group container.
final class PersonajeAcceptanceTests: XCTestCase {

  /// Personaje's default model. This is NOT `BrujaModelManager.defaultModel`.
  static let defaultModelId = "mlx-community/Qwen2.5-7B-Instruct-4bit"

  /// The App Group container the models are downloaded into. SwiftAcervo resolves the
  /// shared-models directory from `ACERVO_APP_GROUP_ID` first.
  private let appGroupId = "group.intrusive-memory.models"

  override func setUp() {
    super.setUp()
    setenv("ACERVO_APP_GROUP_ID", appGroupId, 1)
  }

  /// Skips the calling test unless `modelId` is on disk and readable from this process.
  func skipUnlessModelPresent(_ modelId: String = PersonajeAcceptanceTests.defaultModelId) throws {
    try XCTSkipUnless(
      Acervo.isModelConfigPresent(modelId),
      "Model '\(modelId)' is not reachable from this test process at "
        + "\(Acervo.sharedModelsDirectory.path). Run via the unsandboxed host "
        + "(`make test-personaje`); the sandboxed `xcodebuild test` runner cannot read the "
        + "App Group container."
    )
  }

  // MARK: - BR-P4: the default model answers through Bruja

  func testDefaultModelAnswersThroughBruja() async throws {
    let modelId = Self.defaultModelId
    try skipUnlessModelPresent(modelId)

    let result = try await Bruja.queryWithMetadata(
      "Reply with the single word: ready",
      model: modelId,
      maxTokens: 16
    )

    print("PersonajeAcceptanceTests default-model response: \(result.response)")
    XCTAssertFalse(
      result.response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      "Expected a non-empty response from \(modelId)"
    )
  }

  // MARK: - BR-P1: schema-constrained output

  /// The schema Personaje sends: fourteen fields, all nullable except `age`, with Personaje's bounds: 500
  /// characters for a top-level string, 200 for a string inside an array item, 8 items per array.
  private static let personajeSchema = BrujaJSONSchema([
    .string("age", maxLength: 500, nullable: false),
    .string("pronouns", maxLength: 500),
    .string("occupation", maxLength: 500),
    .string("languages", maxLength: 500),
    .string("logline", maxLength: 500),
    .string("sampleLine", maxLength: 500),
    .string("appearance", maxLength: 500),
    .string("wardrobe", maxLength: 500),
    .string("personality", maxLength: 500),
    .string("backstory", maxLength: 500),
    .string("arc", maxLength: 500),
    .array(
      "relationships",
      of: .object([.string("with", maxLength: 200), .string("nature", maxLength: 200)]),
      maxItems: 8),
    .string("voiceAndSpeech", maxLength: 500),
    .array(
      "canonFacts",
      of: .object([.string("fact", maxLength: 200), .string("quote", maxLength: 200)]),
      maxItems: 8),
  ])

  /// The type the constrained output decodes into. Every key is required to be present
  /// (`decode`, not `decodeIfPresent`), so a missing key fails the decode.
  private struct PersonajeProfile: Decodable {
    struct Relationship: Decodable, Equatable {
      let with: String?
      let nature: String?
    }
    struct CanonFact: Decodable, Equatable {
      let fact: String?
      let quote: String?
    }

    let age: String?
    let pronouns: String?
    let occupation: String?
    let languages: String?
    let logline: String?
    let sampleLine: String?
    let appearance: String?
    let wardrobe: String?
    let personality: String?
    let backstory: String?
    let arc: String?
    let relationships: [Relationship]?
    let voiceAndSpeech: String?
    let canonFacts: [CanonFact]?

    enum CodingKeys: String, CodingKey, CaseIterable {
      case age, pronouns, occupation, languages, logline, sampleLine, appearance, wardrobe
      case personality, backstory, arc, relationships, voiceAndSpeech, canonFacts
    }

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      for key in CodingKeys.allCases where !container.contains(key) {
        throw DecodingError.keyNotFound(
          key, .init(codingPath: decoder.codingPath, debugDescription: "missing \(key.rawValue)"))
      }
      age = try container.decode(String?.self, forKey: .age)
      pronouns = try container.decode(String?.self, forKey: .pronouns)
      occupation = try container.decode(String?.self, forKey: .occupation)
      languages = try container.decode(String?.self, forKey: .languages)
      logline = try container.decode(String?.self, forKey: .logline)
      sampleLine = try container.decode(String?.self, forKey: .sampleLine)
      appearance = try container.decode(String?.self, forKey: .appearance)
      wardrobe = try container.decode(String?.self, forKey: .wardrobe)
      personality = try container.decode(String?.self, forKey: .personality)
      backstory = try container.decode(String?.self, forKey: .backstory)
      arc = try container.decode(String?.self, forKey: .arc)
      relationships = try container.decode([Relationship]?.self, forKey: .relationships)
      voiceAndSpeech = try container.decode(String?.self, forKey: .voiceAndSpeech)
      canonFacts = try container.decode([CanonFact]?.self, forKey: .canonFacts)
    }
  }

  /// An invented screenplay excerpt, about 200 words.
  private static let excerpt = """
    INT. HARBOR MASTER'S OFFICE - NIGHT

    Rain hammers the tin roof. INES VALCARCE, 52, harbor master of Puerto Quieto, sits behind a \
    desk buried in tide charts. Her grey wool coat is still buttoned to the throat, and a brass \
    whistle hangs from a cord around her neck. She speaks slowly, in a low voice, and never \
    finishes a sentence she does not have to.

    TOMAS REY, her nephew, a deckhand of twenty, drips in the doorway.

    TOMAS
    The Marisol never came back, tia. Three days now.

    INES
    I know what day it is.

    She unrolls a chart and pins it flat with a coffee tin.

    INES (CONT'D)
    Your father read the water better than any man here. He taught me. Then the water took him \
    anyway.

    TOMAS
    So we do nothing?

    INES
    We wait for the tide. I have not lost a boat in eleven years, and I will not start tonight.

    She switches to Galician under her breath, a prayer or a curse, then lifts the radio handset. \
    Her left hand, missing two fingers, steadies the dial.

    INES (CONT'D)
    Captain Duarte owes me a favor. Tonight he pays it.

    Tomas watches her, afraid of her and proud of her in equal measure.
    """

  func testConstrainedQueryOnDefaultModel() async throws {
    let modelId = Self.defaultModelId
    try skipUnlessModelPresent(modelId)

    let prompt = """
      Fill in a character profile for INES VALCARCE from the screenplay excerpt below. Use only \
      what the excerpt says or clearly implies. Write null for a field the excerpt gives no \
      evidence for.

      Fields: age, pronouns, occupation, languages, logline (one sentence), sampleLine (a line \
      she says), appearance, wardrobe, personality, backstory, arc, relationships (a list of \
      {with, nature}), voiceAndSpeech, canonFacts (a list of {fact, quote}).

      EXCERPT:
      \(Self.excerpt)
      """

    let start = Date()
    let output = try await BrujaQuery.generateConstrained(
      prompt,
      schema: Self.personajeSchema,
      model: modelId,
      temperature: 0,
      maxTokens: 2048,
      system: nil
    )
    let wall = Date().timeIntervalSince(start)

    print("PersonajeAcceptanceTests constrained raw output: \(output.text)")
    print(
      String(
        format:
          "PersonajeAcceptanceTests constrained stats: promptTokens=%d generatedTokens=%d "
          + "vocabularySeconds=%.2f generationSeconds=%.2f wallSeconds=%.2f tokensPerSecond=%.2f",
        output.promptTokens, output.generatedTokens, output.vocabularySeconds,
        output.generationSeconds, wall,
        Double(output.generatedTokens) / max(output.generationSeconds, 0.001)))

    XCTAssertEqual(output.text.first, "{", "The raw output must start the object")
    XCTAssertEqual(output.text.last, "}", "The raw output must end on the closing brace")

    let profile = try BrujaQuery.decodeConstrained(output.text, as: PersonajeProfile.self)
    XCTAssertNotNil(profile.occupation, "The excerpt states her occupation")
    XCTAssertTrue(
      profile.age?.contains("52") ?? false,
      "The excerpt reads \"INES VALCARCE, 52\"; decoded age was \(profile.age ?? "null")")
  }

  func testConstrainedQueryThroughPublicAPI() async throws {
    let modelId = Self.defaultModelId
    try skipUnlessModelPresent(modelId)

    struct Pair: Decodable {
      let age: String?
      let occupation: String?
    }

    let pair = try await Bruja.query(
      "Give the age and occupation of the character in this line: "
        + "INES VALCARCE, 52, harbor master of Puerto Quieto, sits behind a desk.",
      schema: BrujaJSONSchema([.string("age"), .string("occupation")]),
      as: Pair.self,
      model: modelId,
      temperature: 0,
      maxTokens: 128
    )
    print(
      "PersonajeAcceptanceTests public constrained: age=\(pair.age ?? "null") "
        + "occupation=\(pair.occupation ?? "null")")
    XCTAssertNotNil(pair.occupation, "The line states her occupation")

    do {
      _ = try await Bruja.query(
        "Describe the sea at length.",
        schema: BrujaJSONSchema([.string("description", nullable: false)]),
        as: [String: String].self,
        model: modelId,
        temperature: 0,
        maxTokens: 6
      )
      XCTFail("Six tokens cannot close the object; expected structuredOutputTruncated")
    } catch BrujaError.structuredOutputTruncated(let tokenLimit) {
      XCTAssertEqual(tokenLimit, 6)
    }
  }

  func testVocabularyTableRoundTrips() async throws {
    let modelId = Self.defaultModelId
    try skipUnlessModelPresent(modelId)

    // Fifty words.
    let sentence =
      "When the tide went out past the broken pier, Ines counted 11 boats, wrote \"all home\" "
      + "in the ledger, and told her nephew: wait here, keep the lamp lit, and do not answer "
      + "the radio unless Captain Duarte calls twice; then she walked slowly out into the cold rain alone."
    XCTAssertEqual(sentence.split(separator: " ").count, 50)

    let container = try await Bruja.loadModel(modelId)
    let tokenizer = await container.tokenizer

    let start = Date()
    let table = try await BrujaModelManager.shared.vocabularyTable(for: modelId)
    let buildSeconds = Date().timeIntervalSince(start)

    let ids = tokenizer.encode(text: sentence, addSpecialTokens: false)
    XCTAssertFalse(ids.isEmpty)

    let missing = ids.filter { table[$0] == nil }
    XCTAssertTrue(missing.isEmpty, "Token ids missing from the vocabulary table: \(missing)")

    let joined = ids.map { table[$0] ?? "" }.joined()
    let decoded = tokenizer.decode(tokenIds: ids, skipSpecialTokens: false)
    XCTAssertEqual(joined, decoded)
    XCTAssertEqual(joined, sentence)

    let partial = table.values.filter { $0.unicodeScalars.contains("\u{FFFD}") }.count
    let empty = table.values.filter(\.isEmpty).count
    print(
      String(
        format:
          "PersonajeAcceptanceTests vocabulary table: entries=%d maxId=%d buildSeconds=%.2f "
          + "sentenceTokens=%d partialUTF8Entries=%d emptyEntries=%d",
        table.count, table.keys.max() ?? -1, buildSeconds, ids.count, partial, empty))
  }

  // MARK: - Fixture loader and the nine Personaje prompts

  /// `Fixtures/Personaje/`, found relative to this source file (three directories up).
  private static func fixtureDirectory(file: StaticString = #filePath) -> URL {
    URL(fileURLWithPath: "\(file)")
      .deletingLastPathComponent()  // BrujaIntegrationTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // package root
      .appendingPathComponent("Fixtures/Personaje", isDirectory: true)
  }

  /// The nine prompt files, sorted by name. A missing directory is a failure, not a skip.
  private func loadPrompts() throws -> [(name: String, text: String)] {
    let dir = Self.fixtureDirectory()
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else {
      XCTFail("Fixture directory is missing: \(dir.path)")
      throw CocoaError(.fileNoSuchFile)
    }
    let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
      .filter { $0.hasSuffix(".txt") }
      .sorted()
    return try names.map {
      ($0, try String(contentsOf: dir.appendingPathComponent($0), encoding: .utf8))
    }
  }

  /// Builds a schema from `schema.json`, taking key order from each `propertyOrder` array.
  private func loadSchema() throws -> BrujaJSONSchema {
    let url = Self.fixtureDirectory().appendingPathComponent("schema.json")
    let data = try Data(contentsOf: url)
    let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    return try Self.objectSchema(root)
  }

  private static func objectSchema(_ node: [String: Any]) throws -> BrujaJSONSchema {
    let properties = try XCTUnwrap(node["properties"] as? [String: [String: Any]])
    let order = try XCTUnwrap(node["propertyOrder"] as? [String])
    XCTAssertEqual(Set(order), Set(properties.keys), "propertyOrder must name every property")
    return BrujaJSONSchema(
      try order.map { name in
        let spec = try XCTUnwrap(properties[name])
        let (kind, nullable) = try kind(of: spec)
        return BrujaJSONSchema.Property(name, kind, nullable: nullable)
      })
  }

  private static func kind(of spec: [String: Any]) throws -> (BrujaJSONSchema.Kind, Bool) {
    var types: [String]
    if let list = spec["type"] as? [String] {
      types = list
    } else {
      types = [try XCTUnwrap(spec["type"] as? String)]
    }
    let nullable = types.contains("null")
    types.removeAll { $0 == "null" }
    let type = try XCTUnwrap(types.first)
    switch type {
    case "string":
      if let maxLength = spec["maxLength"] as? Int {
        return (.string(maxLength: maxLength), nullable)
      }
      return (.string, nullable)
    case "integer": return (.integer, nullable)
    case "number": return (.number, nullable)
    case "boolean": return (.boolean, nullable)
    case "array":
      let items = try XCTUnwrap(spec["items"] as? [String: Any])
      return (
        .array(of: try kind(of: items).0, maxItems: spec["maxItems"] as? Int), nullable
      )
    case "object": return (.object(try objectSchema(spec)), nullable)
    default:
      XCTFail("Unsupported schema type \(type)")
      throw CocoaError(.coderInvalidValue)
    }
  }

  /// The longest run of the same word in `text`. Words are split on whitespace, lowercased,
  /// and stripped of punctuation; a word that is all punctuation is dropped.
  private static func maxWordRun(in text: String) -> Int {
    var longest = 0
    var run = 0
    var previous: String?
    for piece in text.split(whereSeparator: \.isWhitespace) {
      let word = String(piece.lowercased().filter { $0.isLetter || $0.isNumber })
      if word.isEmpty { continue }
      run = word == previous ? run + 1 : 1
      previous = word
      longest = max(longest, run)
    }
    return longest
  }

  /// How many items of `items` are equal to an earlier item.
  private static func duplicateItems<Item: Equatable>(in items: [Item]) -> Int {
    items.indices.filter { index in items[..<index].contains(items[index]) }.count
  }

  /// Runs one prompt, asserts the invariants, prints a stats line, returns the null count,
  /// the decoded `age`, the longest run of one word in any string and the number of array
  /// items that repeat an earlier item of the same array.
  @discardableResult
  private func runPrompt(_ name: String, _ prompt: String, schema: BrujaJSONSchema) async throws
    -> (nulls: Int, age: String?, maxWordRun: Int, duplicateItems: Int)
  {
    let start = Date()
    let output = try await BrujaQuery.generateConstrained(
      prompt, schema: schema, model: Self.defaultModelId, temperature: 0.3, maxTokens: 4096,
      system: nil)
    let wall = Date().timeIntervalSince(start)

    XCTAssertEqual(output.text.last, "}", "\(name): raw output must end on the closing brace")
    let profile = try BrujaQuery.decodeConstrained(output.text, as: PersonajeProfile.self)

    let strings: [(String, String?)] = [
      ("age", profile.age), ("pronouns", profile.pronouns), ("occupation", profile.occupation),
      ("languages", profile.languages), ("logline", profile.logline),
      ("sampleLine", profile.sampleLine), ("appearance", profile.appearance),
      ("wardrobe", profile.wardrobe), ("personality", profile.personality),
      ("backstory", profile.backstory), ("arc", profile.arc),
      ("voiceAndSpeech", profile.voiceAndSpeech),
    ]
    for (field, value) in strings {
      XCTAssertNotEqual(value, "null", "\(name): \(field) is the string \"null\"")
    }
    for r in profile.relationships ?? [] {
      XCTAssertNotEqual(r.with, "null", "\(name): relationships.with is the string \"null\"")
      XCTAssertNotEqual(r.nature, "null", "\(name): relationships.nature is the string \"null\"")
    }
    for f in profile.canonFacts ?? [] {
      XCTAssertNotEqual(f.fact, "null", "\(name): canonFacts.fact is the string \"null\"")
      XCTAssertNotEqual(f.quote, "null", "\(name): canonFacts.quote is the string \"null\"")
    }

    for (field, value) in strings {
      XCTAssertLessThanOrEqual(
        value?.count ?? 0, 500, "\(name): \(field) exceeds 500 characters")
    }
    let relationships = profile.relationships ?? []
    let canonFacts = profile.canonFacts ?? []
    XCTAssertLessThanOrEqual(relationships.count, 8, "\(name): relationships exceeds 8 items")
    XCTAssertLessThanOrEqual(canonFacts.count, 8, "\(name): canonFacts exceeds 8 items")
    for r in relationships {
      XCTAssertLessThanOrEqual(r.with?.count ?? 0, 200, "\(name): relationships.with > 200")
      XCTAssertLessThanOrEqual(r.nature?.count ?? 0, 200, "\(name): relationships.nature > 200")
    }
    for f in canonFacts {
      XCTAssertLessThanOrEqual(f.fact?.count ?? 0, 200, "\(name): canonFacts.fact > 200")
      XCTAssertLessThanOrEqual(f.quote?.count ?? 0, 200, "\(name): canonFacts.quote > 200")
    }

    let nulls =
      strings.filter { $0.1 == nil }.count + (profile.relationships == nil ? 1 : 0)
      + (profile.canonFacts == nil ? 1 : 0)
    let allStrings: [String] =
      strings.compactMap { $0.1 }
      + relationships.flatMap { [$0.with, $0.nature].compactMap { $0 } }
      + canonFacts.flatMap { [$0.fact, $0.quote].compactMap { $0 } }
    let maxWordRun = allStrings.map(Self.maxWordRun(in:)).max() ?? 0
    let duplicateItems =
      Self.duplicateItems(in: relationships) + Self.duplicateItems(in: canonFacts)
    print(
      String(
        format:
          "PersonajeAcceptanceTests prompt: file=%@ promptTokens=%d generatedTokens=%d "
          + "wallSeconds=%.1f nullFields=%d/14 age=%@ maxWordRun=%d duplicateItems=%d",
        name, output.promptTokens, output.generatedTokens, wall, nulls,
        profile.age ?? "null", maxWordRun, duplicateItems))
    print("PersonajeAcceptanceTests raw \(name): \(output.text)")
    return (nulls, profile.age, maxWordRun, duplicateItems)
  }

  func testNinePromptsDecode() async throws {
    try skipUnlessModelPresent()
    let prompts = try loadPrompts()
    XCTAssertEqual(prompts.count, 9, "Expected nine prompt files")
    let schema = try loadSchema()
    XCTAssertEqual(schema.properties.count, 14)
    for (name, text) in prompts {
      let result = try await runPrompt(name, text, schema: schema)
      let age = result.age
      XCTAssertNotNil(age, "\(name): age must not be null")
      let trimmed = (age ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      let hasDigit = trimmed.contains { $0.isNumber }
      XCTAssertTrue(
        hasDigit || ["child", "adult", "older adult"].contains(trimmed),
        "\(name): age \"\(age ?? "null")\" is neither a stated age nor child/adult/older adult")
      XCTAssertLessThan(
        result.maxWordRun, 5, "\(name): a string repeats one word \(result.maxWordRun) times")
      XCTAssertEqual(result.duplicateItems, 0, "\(name): an array repeats an item")
    }
  }

  func testHunterQuery() async throws {
    try skipUnlessModelPresent()
    let prompts = try loadPrompts()
    let hunter = try XCTUnwrap(prompts.first { $0.name == "01-HUNTER-major.txt" })
    try await runPrompt(hunter.name, hunter.text, schema: try loadSchema())
  }
}
