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

  /// The type the constrained output decodes into. Every key is required to be present
  /// (`decode`, not `decodeIfPresent`), so a missing key fails the decode.
  private struct PersonajeProfile: Decodable {
    struct Relationship: Decodable {
      let with: String?
      let nature: String?
    }
    struct CanonFact: Decodable {
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
}
