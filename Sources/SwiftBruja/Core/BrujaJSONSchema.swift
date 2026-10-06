import Foundation

/// The shape of one JSON object, given at run time.
///
/// A schema is an ordered list of properties. Order matters: constrained
/// generation writes the keys in exactly this order, and every key is written
/// (a property that has no value is written as JSON `null`, which requires the
/// property to be nullable).
///
/// The supported shapes are deliberately narrow: string, integer, number,
/// boolean, an array whose elements all have one kind, and a nested object.
///
/// ```swift
/// let schema = BrujaJSONSchema([
///   .string("age"),
///   .array("relationships", of: .object([.string("with"), .string("nature")])),
/// ])
/// ```
///
/// ## Bounds
///
/// A string can carry a `maxLength` and an array a `maxItems`. Constrained
/// generation enforces both while it writes, so a bounded value always ends.
/// A string or an array with no bound can grow until the token limit runs out.
/// For output that is guaranteed to close, bound every string and every array,
/// including the strings inside array items. A number is always bounded, at
/// ``BrujaJSONAcceptor/maximumNumberDigits`` digits.
///
/// ```swift
/// let schema = BrujaJSONSchema([
///   .string("age", maxLength: 500),
///   .array(
///     "relationships",
///     of: .object([.string("with", maxLength: 200), .string("nature", maxLength: 200)]),
///     maxItems: 8),
///   .array("tags", of: .string(maxLength: 40), maxItems: 8),
/// ])
/// ```
///
/// `maxLength` counts the characters of the JSON text between the quotes, as
/// written, one per Swift `Character`. An escape counts every character it is
/// written with: `\n` counts 2 and `\u00e9` counts 6, although each decodes to
/// one character. The decoded string is therefore never longer than
/// `maxLength`, and it is shorter when the text holds escapes. An escape is
/// only started when the whole of it fits.
///
/// A bound below 1 is a precondition failure.
public struct BrujaJSONSchema: Sendable, Hashable {

  /// The kind of a JSON value.
  public indirect enum Kind: Sendable, Hashable {
    /// A JSON string of any length.
    case string
    /// A JSON string of at most `maxLength` characters, counted in the JSON
    /// text as written (see ``BrujaJSONSchema``). Build it with
    /// ``string(maxLength:)``, which checks the bound.
    case boundedString(maxLength: Int)
    /// A JSON number with no fraction and no exponent.
    case integer
    /// Any JSON number.
    case number
    /// `true` or `false`.
    case boolean
    /// An array whose elements all have the given kind. Elements are never `null`.
    /// With `maxItems` the array holds at most that many elements; `nil` means
    /// any number.
    case array(of: Kind, maxItems: Int? = nil)
    /// A nested object with its own ordered properties.
    case object(BrujaJSONSchema)

    /// A nested object, built from its properties.
    public static func object(_ properties: [Property]) -> Kind {
      .object(BrujaJSONSchema(properties))
    }

    /// A string of at most `maxLength` characters, counted in the JSON text as
    /// written: `\n` counts 2 and `\u00e9` counts 6.
    ///
    /// - Precondition: `maxLength >= 1`.
    public static func string(maxLength: Int) -> Kind {
      precondition(maxLength >= 1, "maxLength must be at least 1, got \(maxLength)")
      return .boundedString(maxLength: maxLength)
    }

    /// Stops the program if this kind, or a kind nested in it, has a bound below 1.
    func checkBounds() {
      switch self {
      case .string, .integer, .number, .boolean:
        break
      case .boundedString(let maxLength):
        precondition(maxLength >= 1, "maxLength must be at least 1, got \(maxLength)")
      case .array(let item, let maxItems):
        if let maxItems {
          precondition(maxItems >= 1, "maxItems must be at least 1, got \(maxItems)")
        }
        item.checkBounds()
      case .object(let schema):
        for property in schema.properties {
          property.kind.checkBounds()
        }
      }
    }
  }

  /// One named property of an object.
  public struct Property: Sendable, Hashable {
    /// The key, unescaped.
    public var name: String

    /// The kind of the value.
    public var kind: Kind

    /// Whether JSON `null` is allowed in place of a value.
    public var isNullable: Bool

    /// - Precondition: every `maxLength` and `maxItems` in `kind` is at least 1.
    public init(_ name: String, _ kind: Kind, nullable: Bool = true) {
      kind.checkBounds()
      self.name = name
      self.kind = kind
      self.isNullable = nullable
    }

    /// A string property. With `maxLength` the value has at most that many
    /// characters, counted in the JSON text as written (`\n` counts 2, `\u00e9`
    /// counts 6); `nil` means any length.
    ///
    /// - Precondition: `maxLength` is `nil` or at least 1.
    public static func string(
      _ name: String, maxLength: Int? = nil, nullable: Bool = true
    ) -> Property {
      Property(name, maxLength.map { .boundedString(maxLength: $0) } ?? .string, nullable: nullable)
    }

    /// An integer property.
    public static func integer(_ name: String, nullable: Bool = true) -> Property {
      Property(name, .integer, nullable: nullable)
    }

    /// A number property.
    public static func number(_ name: String, nullable: Bool = true) -> Property {
      Property(name, .number, nullable: nullable)
    }

    /// A boolean property.
    public static func boolean(_ name: String, nullable: Bool = true) -> Property {
      Property(name, .boolean, nullable: nullable)
    }

    /// An array property whose elements all have the given kind. With `maxItems`
    /// the array holds at most that many elements; `nil` means any number.
    ///
    /// - Precondition: `maxItems` is `nil` or at least 1.
    public static func array(
      _ name: String, of item: Kind, maxItems: Int? = nil, nullable: Bool = true
    ) -> Property {
      Property(name, .array(of: item, maxItems: maxItems), nullable: nullable)
    }

    /// A nested-object property.
    public static func object(
      _ name: String, _ properties: [Property], nullable: Bool = true
    ) -> Property {
      Property(name, .object(properties), nullable: nullable)
    }
  }

  /// The properties, in the order their keys are written.
  public var properties: [Property]

  public init(_ properties: [Property]) {
    self.properties = properties
  }

  public init(properties: [Property]) {
    self.properties = properties
  }
}
