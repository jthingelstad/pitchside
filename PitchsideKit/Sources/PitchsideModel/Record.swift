import Foundation

// What kubb-engine's record mode (docs/RECORD.md, `kubbCall("record.<name>")`) hands
// back, decoded, and the events Pitchside sends it. Every field is the engine's: the
// scorer screen reads `RecordState.next` and `.allowed` and never keeps its own copy of
// the rules.

/// A position in the notation's pitch frame (pk-kubb-score notation-2.md "The pitch
/// frame"): metres, `across` 0 to 5 from the centre-line stake on Team A's left, `depth`
/// 0 at the centre line to 4 at a baseline, the same in both halves. The engine keeps
/// field kubbs as the one-metre cell a point falls in.
public struct RecordPoint: Codable, Sendable, Hashable {
  public var across: Double
  public var depth: Double
  /// "s" for a kubb that stood from an earlier turn, "p" for this turn's punishment kubb.
  public var mark: String?

  public init(across: Double, depth: Double, mark: String? = nil) {
    self.across = across
    self.depth = depth
    self.mark = mark
  }

  /// The point as an event field.
  public var json: JSONValue {
    var o: [String: JSONValue] = ["across": .number(across), "depth": .number(depth)]
    if let mark { o["mark"] = .string(mark) }
    return .object(o)
  }
}

/// `state` (docs/RECORD.md "State").
public struct RecordState: Decodable, Sendable, Equatable {
  public struct Player: Decodable, Sendable, Equatable {
    /// The id events name (`by`).
    public let id: String
    public let name: String
    /// The prefix the file writes (`k` in `k:3I`).
    public let file: String?
  }
  public struct SideState: Decodable, Sendable, Equatable {
    public let name: String
    public let players: [Player]
    public let base: Int
    public let field: Int
    public let fieldPositions: [RecordPoint]
    public let fieldComplete: Bool
    public let basePositions: [RecordPoint]
    public let baseComplete: Bool
  }
  public struct Inkast: Decodable, Sendable, Equatable {
    public let due: Int
    public let `rethrows`: Int
    public let left: Int
    public let dueAtStart: Int
    public let punish: Int
    public let punishPlaced: Int
    public let rescuable: Int
  }
  public struct Batons: Decodable, Sendable, Equatable {
    public let total: Int
    public let thrown: Int
    public let left: Int
  }
  public struct Advantage: Decodable, Sendable, Equatable {
    public let applies: Bool
    public let observed: Bool?
    public let meters: Int?
  }
  public struct Throwers: Decodable, Sendable, Equatable {
    public struct Count: Decodable, Sendable, Equatable {
      public let id: String
      public let batons: Int
    }
    public let batons: [Count]
    public let cap: Int
    public let distinct: Int
  }
  public struct Next: Decodable, Sendable, Equatable {
    /// "toss", "baton" or "over".
    public let kind: String
    public let rethrow: Bool?
    public let left: Int?
    public let n: Int?
    public let of: Int?
    public let kingShot: Bool?
    /// "field", "base" or "king".
    public let targets: String?
    public let field: Int?
    public let base: Int?
    public let winner: Side?
    public let how: String?
  }
  public struct Switches: Decodable, Sendable, Equatable {
    public let players: Bool
    public let pitch: Bool
    public let lay: Bool
    public let stance: Bool
  }

  public let turn: Int
  /// "inkast", "batons" or "over".
  public let phase: String
  public let over: Bool
  public let winner: Side?
  /// "king", "king toppled early", "king toppled by a thrown kubb", "resigned", "called".
  public let how: String?
  public let events: Int
  public let capture: Switches
  public let king: String
  public let sides: [String: SideState]
  public let attacker: Side?
  public let defender: Side?
  public let inkast: Inkast?
  public let batons: Batons?
  public let advantage: Advantage?
  public let throwers: Throwers?
  public let next: Next
  public let allowed: [String]

  public func side(_ s: Side) -> SideState { sides[s.rawValue]! }
  public func allows(_ type: String) -> Bool { allowed.contains(type) }
}

/// One warning: the engine records what it is told and says where it broke a rule.
public struct RecordWarning: Decodable, Sendable, Hashable {
  /// The event's index in the log (0-based).
  public let event: Int
  public let turn: Int?
  /// rule, order, count, advantage, inkast, phase, position, thrower, rescue, result, ...
  public let code: String
  public let text: String
  /// The event's own `id`.
  public let id: String?
}

/// One row of the score sheet (`sheet.rows`): a turn.
public struct RecordRow: Decodable, Sendable, Equatable {
  public struct Baton: Decodable, Sendable, Equatable {
    public let token: String
    public let by: String?
    public let stance: String?
  }
  public let turn: Int
  public let side: Side
  /// The turn's line: `5. k:3I A k:3F d:B o:B k:B d:= o:K`.
  public let line: String
  /// Its position lines (`@a`, `^a`, `*b`).
  public let lines: [String]
  public let inkastRecorded: Bool
  public let advantage: Bool
  public let batons: [Baton]
  public let notes: [String]
}

/// `result`: what every record call but `options` and `events` returns.
public struct RecordResult: Decodable, Sendable {
  public struct Text: Decodable, Sendable {
    public let text: String
    public let name: String
  }
  public struct Sheet: Decodable, Sendable {
    public let rows: [RecordRow]
  }
  public struct Added: Decodable, Sendable {
    public let index: Int
    public let warnings: [RecordWarning]
  }
  public let state: RecordState
  public let warnings: [RecordWarning]
  public let notation: Text?
  public let sheet: Sheet?
  public let added: Added?
}

/// The events Pitchside sends (docs/RECORD.md "Events"), as JSON objects. The scorer
/// adds each one's `id` and `time`.
public enum RecordEvent {
  public static func toss(
    _ result: Bool, by: String? = nil, at: RecordPoint? = nil, onTop: Bool = false, rescueAttempt: Bool = false,
    rescued: Int = 0, rescuedAt: [RecordPoint]? = nil, king: Bool = false
  ) -> [String: JSONValue] {
    var e: [String: JSONValue] = ["type": "toss", "result": .string(result ? "in" : "out")]
    if let by { e["by"] = .string(by) }
    if let at { e["at"] = at.json }
    if onTop { e["onTop"] = true }
    if rescueAttempt { e["rescueAttempt"] = true }
    if rescued > 0 { e["rescued"] = .number(Double(rescued)) }
    if let rescuedAt { e["rescuedAt"] = .array(rescuedAt.map(\.json)) }
    if king { e["king"] = true }
    return e
  }

  public static func baton(
    field: Int = 0, base: Int = 0, king: Bool = false, illegal: Bool = false, by: String? = nil,
    at: [RecordPoint]? = nil, stance: RecordPoint? = nil
  ) -> [String: JSONValue] {
    var e: [String: JSONValue] = ["type": "baton"]
    if field > 0 { e["field"] = .number(Double(field)) }
    if base > 0 { e["base"] = .number(Double(base)) }
    if king { e["king"] = true }
    if illegal { e["illegal"] = true }
    if let by { e["by"] = .string(by) }
    if let at, !at.isEmpty { e["at"] = .array(at.map(\.json)) }
    if let stance { e["stance"] = stance.json }
    return e
  }

  public static func punish(at: RecordPoint) -> [String: JSONValue] { ["type": "punish", "at": at.json] }

  public static func pitch(half: Side, at: [RecordPoint]) -> [String: JSONValue] {
    ["type": "pitch", "half": .string(half.rawValue), "at": .array(at.map(\.json))]
  }

  public static func advantage(applies: Bool) -> [String: JSONValue] {
    ["type": "advantage", "applies": .bool(applies)]
  }

  public static func resign(_ side: Side) -> [String: JSONValue] { ["type": "resign", "side": .string(side.rawValue)] }

  public static func call(winner: Side) -> [String: JSONValue] { ["type": "call", "winner": .string(winner.rawValue)] }

  public static func capture(_ c: Capture) -> [String: JSONValue] {
    ["type": "capture", "players": .bool(c.who), "pitch": .bool(c.stand), "lay": .bool(c.lay), "stance": .bool(c.stance)]
  }

  public static func note(_ text: String) -> [String: JSONValue] { ["type": "note", "text": .string(text)] }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByBooleanLiteral {
  public init(stringLiteral value: String) { self = .string(value) }
  public init(booleanLiteral value: Bool) { self = .bool(value) }

  public subscript(key: String) -> JSONValue? {
    if case .object(let o) = self { return o[key] }
    return nil
  }
  public var string: String? {
    if case .string(let s) = self { return s }
    return nil
  }
  public var number: Double? {
    if case .number(let n) = self { return n }
    return nil
  }
  public var bool: Bool? {
    if case .bool(let b) = self { return b }
    return nil
  }
  public var array: [JSONValue]? {
    if case .array(let a) = self { return a }
    return nil
  }
  public var object: [String: JSONValue]? {
    if case .object(let o) = self { return o }
    return nil
  }
}
