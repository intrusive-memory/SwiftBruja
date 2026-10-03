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
public struct BrujaJSONSchema: Sendable, Hashable {

  /// The kind of a JSON value.
  public indirect enum Kind: Sendable, Hashable {
    /// A JSON string.
    case string
    /// A JSON number with no fraction and no exponent.
    case integer
    /// Any JSON number.
    case number
    /// `true` or `false`.
    case boolean
    /// An array whose elements all have the given kind. Elements are never `null`.
    case array(of: Kind)
    /// A nested object with its own ordered properties.
    case object(BrujaJSONSchema)

    /// A nested object, built from its properties.
    public static func object(_ properties: [Property]) -> Kind {
      .object(BrujaJSONSchema(properties))
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

    public init(_ name: String, _ kind: Kind, nullable: Bool = true) {
      self.name = name
      self.kind = kind
      self.isNullable = nullable
    }

    /// A string property.
    public static func string(_ name: String, nullable: Bool = true) -> Property {
      Property(name, .string, nullable: nullable)
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

    /// An array property whose elements all have the given kind.
    public static func array(_ name: String, of item: Kind, nullable: Bool = true) -> Property {
      Property(name, .array(of: item), nullable: nullable)
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
