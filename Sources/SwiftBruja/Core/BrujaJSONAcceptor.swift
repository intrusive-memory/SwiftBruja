import Foundation

/// Accepts, one character at a time, exactly the JSON texts that match a
/// ``BrujaJSONSchema``.
///
/// Every key is present, in schema order. Outside strings the only whitespace
/// accepted is one optional space (U+0020) after a `:` and one after a `,`,
/// so both `{"a":1,"b":2}` and `{"a": 1, "b": 2}` are accepted. Two spaces in
/// a row, a tab, a newline, and a space in any other place (after `{` or `[`,
/// before `:`, `,`, `}` or `]`) are rejected. Once the top-level object
/// closes, ``isComplete`` is true and every further character is rejected,
/// a space included.
///
/// The optional space is outside the quotes and is not an item, so it counts
/// toward no bound: it does not use up `maxLength` or `maxItems`.
///
/// The schema has no recursion, so the accepted language is regular and the
/// acceptor is a finite automaton. Its ``State`` is a position in that
/// automaton and nothing else: it never holds the text consumed, and it does
/// not grow with the length of a string, a number, or an array. Two points
/// that accept the same continuations have equal states, so a caller can key a
/// cache on the state.
///
/// Length bounds are not part of the state. A schema's `maxLength` and
/// `maxItems` are enforced with ``Counters`` that the acceptor keeps beside
/// its state: how many more characters the string being written may take, and
/// how many more items each open array may take. At `maxLength` the only
/// character accepted is the closing quote; at `maxItems` the only character
/// accepted after an item is `]`. A string never reaches a point where it
/// cannot close: an escape is accepted only when the whole of it fits, and a
/// nullable string cannot spell `null` with its last character.
///
/// Rules beyond plain JSON:
/// - A nullable string rejects the values `"null"` and `""` at the closing
///   quote. The only way to write "nothing" is JSON `null`. A longer value that
///   starts with `null` (for example `"nullable"`) is legal. The check is on
///   the literal characters; a value spelled with escapes (`"null"`) is
///   not caught.
/// - `\uXXXX` escapes in the surrogate range (`\uD800`–`\uDFFF`) are rejected,
///   so a lone surrogate can never make the text undecodable. Characters
///   outside the BMP are written literally.
/// - Raw control characters inside a string are rejected, as JSON requires.
public struct BrujaJSONAcceptor: Sendable {

  /// A position in the automaton.
  ///
  /// A state is only meaningful to an acceptor built from the same schema as
  /// the acceptor it came from.
  public struct State: Hashable, Sendable {
    fileprivate var node: Int32
    fileprivate var phase: Phase

    fileprivate init(_ node: Int, _ phase: Phase = .none) {
      self.node = Int32(node)
      self.phase = phase
    }
  }

  /// What is left of the schema's length bounds at a point in the text.
  ///
  /// The counters sit beside a ``State``; they are not part of it. For a
  /// schema with no `maxLength` and no `maxItems` they never change.
  public struct Counters: Hashable, Sendable {
    /// Characters the string being written may still take. `Int.max` outside
    /// a bounded string.
    fileprivate var length: Int

    /// For each bounded array of the schema, the items it may still take
    /// after the ones written. `Int.max` while that array is not open.
    fileprivate var items: [Int]

    /// How many more characters the string being written may take, or `nil`
    /// when the position is not inside a string that has a `maxLength`.
    public var remainingLength: Int? {
      length == .max ? nil : length
    }

    /// The fewest items any open array with a `maxItems` may still take, or
    /// `nil` when no such array is open.
    public var fewestRemainingItems: Int? {
      items.filter { $0 != .max }.min()
    }
  }

  /// The current position. Read it to save a position; assign it to go back to one.
  ///
  /// With a bounded schema a position is the state and the ``counters``
  /// together: save and restore both.
  public var state: State

  /// The bound counters at the current position.
  public var counters: Counters

  /// The position before any character has been consumed.
  public let initialState: State

  private let nodes: [Node]

  /// One slot per bounded array, every one closed.
  private let closedItems: [Int]

  /// Builds the automaton for `schema`.
  ///
  /// - Precondition: every `maxLength` and `maxItems` in `schema` is at least 1.
  public init(schema: BrujaJSONSchema) {
    var compiler = Compiler()
    let start = compiler.compileTopLevel(schema)
    self.nodes = compiler.nodes
    self.closedItems = Array(repeating: .max, count: compiler.boundedArrayCount)
    self.initialState = State(start)
    self.state = State(start)
    self.counters = Counters(length: .max, items: closedItems)
  }

  /// True once the top-level object has closed.
  public var isComplete: Bool {
    isComplete(state)
  }

  /// True if `state` is the position after the top-level object has closed.
  public func isComplete(_ state: State) -> Bool {
    if case .done = nodes[Int(state.node)] { return true }
    return false
  }

  /// Consumes one character.
  ///
  /// - Returns: `true` if the character is legal here. On `false` the state is unchanged.
  @discardableResult
  public mutating func advance(_ character: Character) -> Bool {
    guard let next = step(state, character, &counters) else { return false }
    state = next
    return true
  }

  /// The counters of a position at `state` that has used none of its bounds:
  /// the string being written, if any, has its whole `maxLength` left, and no
  /// array is counted as open.
  ///
  /// These are the most permissive counters `state` can have. Every character
  /// legal at `state` under any counters is legal under these.
  public func unusedCounters(for state: State) -> Counters {
    var result = Counters(length: .max, items: closedItems)
    if case .string(_, let maxLength) = nodes[Int(state.node)] {
      result.length = maxLength
    }
    return result
  }

  /// The state reached from `state` by consuming one character, or `nil` if
  /// the character is not legal there. Does not change the acceptor.
  ///
  /// Bounds are checked as in ``unusedCounters(for:)``: a bound that the
  /// character itself would break is enforced, one that depends on the text
  /// before `state` is not.
  public func state(after character: Character, from state: State) -> State? {
    var counters = unusedCounters(for: state)
    return step(state, character, &counters)
  }

  /// The state reached from `state` by consuming one character, or `nil` if
  /// the character is not legal there. `counters` moves with the state; on
  /// `nil` it is unchanged. Does not change the acceptor.
  public func state(
    after character: Character, from state: State, counters: inout Counters
  ) -> State? {
    step(state, character, &counters)
  }

  /// The state reached from `state` by consuming all of `text`, or `nil` if
  /// any character of it is not legal. Does not change the acceptor.
  ///
  /// Bounds are checked as in ``unusedCounters(for:)``: a string or an array
  /// that `text` itself carries past its bound is rejected, a bound that
  /// depends on the text before `state` is not enforced.
  public func state(after text: String, from state: State) -> State? {
    var current = state
    var counters = unusedCounters(for: state)
    for character in text {
      guard let next = step(current, character, &counters) else { return nil }
      current = next
    }
    return current
  }

  /// Goes back to ``initialState``.
  public mutating func reset() {
    state = initialState
    counters = Counters(length: .max, items: closedItems)
  }

  // MARK: - Automaton

  /// Position inside a string or number. `.none` everywhere else.
  fileprivate enum Phase: UInt8, Hashable, Sendable {
    case none

    // Inside a string. The first five track whether the text so far is a
    // prefix of `null`; they are only entered for a nullable string.
    case stringEmpty
    case stringN
    case stringNu
    case stringNul
    case stringNull
    case stringOther
    case stringEscape
    case stringHex4
    /// After `\ud`: the next digit must be 0–7 (no surrogates).
    case stringHex3NoSurrogate
    case stringHex3
    case stringHex2
    case stringHex1

    // Inside a number.
    case numberMinus
    case numberZero
    case numberInteger
    case numberPoint
    case numberFraction
    case numberExponent
    case numberExponentSign
    case numberExponentDigits
  }

  fileprivate enum Node: Sendable {
    /// Exactly this character, then `next`.
    case literal(Character, next: Int)
    /// The first character of a value picks the branch.
    case value([Character: State])
    /// Inside a string value; the phase says where. `maxLength` is `Int.max`
    /// for a string with no bound.
    case string(next: Int, maxLength: Int)
    /// Inside a number value; the phase says where.
    case number(integerOnly: Bool, next: Int)
    /// Just after `[`: either `]` or the first element. `slot` is the array's
    /// index in `Counters.items`, or -1 for an array with no bound.
    case arrayOpen(item: Int, next: Int, slot: Int, maxItems: Int)
    /// Just after an element: either `,` and another element, or `]`.
    case arrayAfterItem(item: Int, next: Int, slot: Int)
    /// One space, or nothing, then `next`. Sits after every `:` and every `,`
    /// outside a string.
    case optionalSpace(next: Int)
    /// The top-level object has closed.
    case done
  }

  /// One transition. `counters` moves with the state; when the character is
  /// rejected, `counters` is left as it was.
  private func step(_ state: State, _ character: Character, _ counters: inout Counters) -> State? {
    switch nodes[Int(state.node)] {
    case .literal(let expected, let next):
      return character == expected ? State(next) : nil

    case .value(let branches):
      guard let target = branches[character] else { return nil }
      // An opening quote: the string starts with its whole length left.
      if case .string(_, let maxLength) = nodes[Int(target.node)] {
        counters.length = maxLength
      }
      return target

    case .string(let next, _):
      return stepString(state, character, next: next, &counters)

    case .number(let integerOnly, let next):
      return stepNumber(state, character, integerOnly: integerOnly, next: next, &counters)

    case .arrayOpen(let item, let next, let slot, let maxItems):
      if character == "]" { return State(next) }
      guard let first = step(State(item), character, &counters) else { return nil }
      // The first item has started.
      if slot >= 0 { counters.items[slot] = maxItems - 1 }
      return first

    case .arrayAfterItem(let item, let next, let slot):
      if character == "," {
        if slot >= 0 {
          // At `maxItems` the only way on is `]`.
          let left = counters.items[slot]
          guard left >= 1 else { return nil }
          if left != .max { counters.items[slot] = left - 1 }
        }
        return State(item)
      }
      if character == "]" {
        if slot >= 0 { counters.items[slot] = .max }
        return State(next)
      }
      return nil

    case .optionalSpace(let next):
      // Why one space is accepted here. Cause of the always-null first value
      // (Sortie 6C): Qwen2.5-7B-Instruct-4bit writes `: ` after an object's
      // first key, and when the acceptor took the compact form only, the mask
      // removed both tokens the model wanted and left `null` as the best of
      // what remained. Measured at temperature 0 on an excerpt that reads
      // "INES VALCARCE, 52", at the step straight after the first key's colon
      // (the ten highest logits before the mask, then after it):
      //
      //   step=3 pre=[" \"":33.91 " ":33.31 " null":24.14 " {\"":22.86
      //     "5":17.83 " [\"":16.34 " \"\'":16.09 "null":15.70 " \"\",":14.51
      //     " \"-":14.49] post=["null":15.70 "\"path":11.10 "\"d":9.58
      //     "\"use":9.33 "\"A":8.64 "\"L":8.38 "\"And":8.38 "\"in":8.32
      //     "\"a":8.30 "\"log":8.23]
      //
      // Space-then-quote led at 33.91; after the mask `null` won at 15.70 over
      // a quote glued to an unrelated word at 11.10. With the space accepted,
      // the same step keeps post=[" \"":33.91 " ":33.31 " null":24.14 ...] and
      // the value comes out as "52". The cause is the position, not the
      // field: with another field first, that field was the null one and the
      // age, second, was "52"; from the second value on the model copies the
      // compact form it has already written. Dropping the "Use null ..."
      // sentence from the default system prompt changed nothing (`null`
      // 15.09 against 11.51).
      //
      // The space leads to `next`, which is not this node, so a second space
      // is tested there and rejected: whitespace cannot repeat. Without the
      // space the character belongs to `next`. The counters are not touched.
      if character == " " { return State(next) }
      return step(State(next), character, &counters)

    case .done:
      return nil
    }
  }

  private func stepString(
    _ state: State, _ character: Character, next: Int, _ counters: inout Counters
  ) -> State? {
    // Characters this string may still take; `Int.max` when it has no bound.
    let left = counters.length

    /// Counts the character against the bound and moves to `phase`.
    func take(_ phase: Phase) -> State {
      if left != .max { counters.length = left - 1 }
      var result = state
      result.phase = phase
      return result
    }

    switch state.phase {
    case .stringEmpty, .stringN, .stringNu, .stringNul, .stringNull, .stringOther:
      if character == "\"" {
        // `""` and `"null"` are rejected here, at the closing quote.
        if state.phase == .stringEmpty || state.phase == .stringNull { return nil }
        counters.length = .max
        return State(next)
      }
      // At `maxLength` the closing quote is the only way on.
      guard left >= 1 else { return nil }
      if character == "\\" {
        // An escape is at least two characters; it must fit whole.
        return left >= 2 ? take(.stringEscape) : nil
      }
      guard Self.isStringContent(character) else { return nil }
      switch (state.phase, character) {
      case (.stringEmpty, "n"): return take(.stringN)
      case (.stringN, "u"): return take(.stringNu)
      case (.stringNu, "l"): return take(.stringNul)
      case (.stringNul, "l"):
        // `null` cannot close, so it must leave room for one more character.
        return left >= 2 ? take(.stringNull) : nil
      default: return take(.stringOther)
      }

    case .stringEscape:
      guard left >= 1 else { return nil }
      switch character {
      case "\"", "\\", "/", "b", "f", "n", "r", "t": return take(.stringOther)
      case "u":
        // `u` and its four hex digits must fit whole.
        return left >= 5 ? take(.stringHex4) : nil
      default: return nil
      }

    case .stringHex4:
      guard left >= 1, Self.isHexDigit(character) else { return nil }
      return take(character == "d" || character == "D" ? .stringHex3NoSurrogate : .stringHex3)

    case .stringHex3NoSurrogate:
      guard left >= 1, let ascii = character.asciiValue, (0x30...0x37).contains(ascii) else {
        return nil
      }
      return take(.stringHex2)

    case .stringHex3:
      return left >= 1 && Self.isHexDigit(character) ? take(.stringHex2) : nil

    case .stringHex2:
      return left >= 1 && Self.isHexDigit(character) ? take(.stringHex1) : nil

    case .stringHex1:
      return left >= 1 && Self.isHexDigit(character) ? take(.stringOther) : nil

    default:
      return nil
    }
  }

  private func stepNumber(
    _ state: State, _ character: Character, integerOnly: Bool, next: Int,
    _ counters: inout Counters
  ) -> State? {
    func at(_ phase: Phase) -> State {
      var result = state
      result.phase = phase
      return result
    }
    // A number has no closing character: it ends when the next character
    // belongs to whatever follows it.
    func end() -> State? { step(State(next), character, &counters) }

    let isDigit = Self.isDigit(character)
    let isExponentMark = !integerOnly && (character == "e" || character == "E")

    switch state.phase {
    case .numberMinus:
      guard isDigit else { return nil }
      return at(character == "0" ? .numberZero : .numberInteger)

    case .numberZero:
      if !integerOnly && character == "." { return at(.numberPoint) }
      if isExponentMark { return at(.numberExponent) }
      // A leading zero cannot be followed by another digit.
      return isDigit ? nil : end()

    case .numberInteger:
      if isDigit { return state }
      if !integerOnly && character == "." { return at(.numberPoint) }
      if isExponentMark { return at(.numberExponent) }
      return end()

    case .numberPoint:
      return isDigit ? at(.numberFraction) : nil

    case .numberFraction:
      if isDigit { return state }
      if isExponentMark { return at(.numberExponent) }
      return end()

    case .numberExponent:
      if character == "+" || character == "-" { return at(.numberExponentSign) }
      return isDigit ? at(.numberExponentDigits) : nil

    case .numberExponentSign:
      return isDigit ? at(.numberExponentDigits) : nil

    case .numberExponentDigits:
      return isDigit ? state : end()

    default:
      return nil
    }
  }

  // MARK: - Character classes

  /// A character that may appear unescaped inside a string. Every scalar of
  /// the character is checked, so a quote or backslash carrying a combining
  /// mark is not let through as content.
  private static func isStringContent(_ character: Character) -> Bool {
    for scalar in character.unicodeScalars {
      if scalar.value < 0x20 || scalar == "\"" || scalar == "\\" { return false }
    }
    return true
  }

  private static func isDigit(_ character: Character) -> Bool {
    guard let ascii = character.asciiValue else { return false }
    return (0x30...0x39).contains(ascii)
  }

  private static func isHexDigit(_ character: Character) -> Bool {
    guard let ascii = character.asciiValue else { return false }
    return (0x30...0x39).contains(ascii) || (0x41...0x46).contains(ascii)
      || (0x61...0x66).contains(ascii)
  }

  // MARK: - Compiler

  /// Turns a schema into the node table. Every value is compiled with the node
  /// that follows it, so no stack is needed at run time.
  private struct Compiler {
    var nodes: [Node] = []

    /// How many arrays with a `maxItems` have been compiled. Each one owns a
    /// slot in `Counters.items`.
    var boundedArrayCount = 0

    mutating func append(_ node: Node) -> Int {
      nodes.append(node)
      return nodes.count - 1
    }

    mutating func compileTopLevel(_ schema: BrujaJSONSchema) -> Int {
      let done = append(.done)
      let body = compileObjectBody(schema, next: done)
      return append(.literal("{", next: body))
    }

    /// Nodes that accept `text` and then continue at `next`.
    mutating func chain(_ text: String, next: Int) -> Int {
      var next = next
      for character in text.reversed() {
        next = append(.literal(character, next: next))
      }
      return next
    }

    /// Everything after the `{` of an object, through its `}`.
    mutating func compileObjectBody(_ schema: BrujaJSONSchema, next: Int) -> Int {
      var after = append(.literal("}", next: next))
      for (index, property) in schema.properties.enumerated().reversed() {
        let value = compileValue(property.kind, nullable: property.isNullable, next: after)
        let key = chain(
          Self.quoted(property.name) + ":", next: append(.optionalSpace(next: value)))
        after = index > 0 ? append(.literal(",", next: append(.optionalSpace(next: key)))) : key
      }
      return after
    }

    mutating func compileValue(_ kind: BrujaJSONSchema.Kind, nullable: Bool, next: Int) -> Int {
      var branches: [Character: State] = [:]
      if nullable {
        branches["n"] = State(chain("ull", next: next))
      }

      kind.checkBounds()

      switch kind {
      case .string, .boundedString:
        var maxLength = Int.max
        if case .boundedString(let bound) = kind { maxLength = bound }
        let string = append(.string(next: next, maxLength: maxLength))
        branches["\""] = State(string, nullable ? .stringEmpty : .stringOther)

      case .integer, .number:
        let number = append(.number(integerOnly: kind == .integer, next: next))
        branches["-"] = State(number, .numberMinus)
        branches["0"] = State(number, .numberZero)
        for digit in "123456789" {
          branches[digit] = State(number, .numberInteger)
        }

      case .boolean:
        branches["t"] = State(chain("rue", next: next))
        branches["f"] = State(chain("alse", next: next))

      case .array(let itemKind, let maxItems):
        var slot = -1
        if maxItems != nil {
          slot = boundedArrayCount
          boundedArrayCount += 1
        }
        // The element and the node after it point at each other, so the
        // second is reserved first and filled in after.
        let afterItem = append(.done)
        let item = compileValue(itemKind, nullable: false, next: afterItem)
        // After a comma the next item may have one space before it; the
        // first item, straight after `[`, may not.
        let spacedItem = append(.optionalSpace(next: item))
        nodes[afterItem] = .arrayAfterItem(item: spacedItem, next: next, slot: slot)
        branches["["] = State(
          append(.arrayOpen(item: item, next: next, slot: slot, maxItems: maxItems ?? .max)))

      case .object(let schema):
        branches["{"] = State(compileObjectBody(schema, next: next))
      }

      return append(.value(branches))
    }

    /// `name` as a JSON string literal, with the quotes.
    static func quoted(_ name: String) -> String {
      var result = "\""
      for scalar in name.unicodeScalars {
        switch scalar {
        case "\"": result += "\\\""
        case "\\": result += "\\\\"
        case _ where scalar.value < 0x20:
          let hex = String(scalar.value, radix: 16)
          result += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
        default: result.unicodeScalars.append(scalar)
        }
      }
      return result + "\""
    }
  }
}
