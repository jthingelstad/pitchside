import Foundation

/// Any JSON value, kept as it came: an event's payload is the scorer's to define (record
/// mode, kubb-engine), so the log stores it without reading it.
public enum JSONValue: Codable, Sendable, Hashable {
  case null
  case bool(Bool)
  case number(Double)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])

  public init(from decoder: Decoder) throws {
    let c = try decoder.singleValueContainer()
    if c.decodeNil() { self = .null }
    else if let b = try? c.decode(Bool.self) { self = .bool(b) }
    else if let n = try? c.decode(Double.self) { self = .number(n) }
    else if let s = try? c.decode(String.self) { self = .string(s) }
    else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
    else { self = .object(try c.decode([String: JSONValue].self)) }
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.singleValueContainer()
    switch self {
    case .null: try c.encodeNil()
    case .bool(let b): try c.encode(b)
    case .number(let n): try c.encode(n)
    case .string(let s): try c.encode(s)
    case .array(let a): try c.encode(a)
    case .object(let o): try c.encode(o)
    }
  }

  /// Parses JSON text (an engine call's result) into a value.
  public init(json: String) throws {
    self = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
  }

  /// The value as compact JSON text, keys sorted.
  public var json: String {
    let e = JSONEncoder()
    e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return (try? String(decoding: e.encode(self), as: UTF8.self)) ?? "null"
  }
}

/// One entry in a game's append-only log. `kind` and `payload` belong to the scorer that
/// wrote it; the log's own fields are the sequence number, the time and the capture rows
/// that were on when it was written.
public struct GameEvent: Codable, Sendable, Hashable {
  /// Kinds the app itself writes. A scorer adds its own (record mode's actions).
  public enum Kind {
    /// The game started (teams, options and capture are in the game's own file).
    public static let start = "start"
    /// The capture rows changed between turns (payload: `{"capture": "turn who"}`).
    public static let capture = "capture"
    /// A placeholder event, until record mode defines the scorer's events.
    public static let placeholder = "placeholder"
    /// The game ended (payload: `{"winner": "A"}` or `{"resigned": "B"}`).
    public static let end = "end"
  }

  /// 1, 2, 3, ... with no gaps: the order of the log.
  public let seq: Int
  public let at: Date
  public let kind: String
  /// The capture rows on when the event was written (`turn who`).
  public let capture: String
  public let payload: JSONValue

  public init(seq: Int, at: Date = .now, kind: String, capture: String, payload: JSONValue = .null) {
    self.seq = seq
    self.at = at
    self.kind = kind
    self.capture = capture
    self.payload = payload
  }
}

public enum EventLogError: Error, Equatable {
  /// A line of the file is not an event. The events before it are kept.
  case damaged(line: Int)
  /// The log's sequence has a gap or repeat.
  case outOfOrder(line: Int)
}

/// A game's event log: one JSON object per line (JSON Lines), appended and synced to
/// disk after every event. Never rewritten: undo and edits are new events.
public final class EventLog {
  public let url: URL
  public private(set) var events: [GameEvent]
  private var committedBytes: UInt64 = 0
  private var fileBytes: UInt64 = 0

  /// A recorded throw is the door's JSON object, with journal metadata alongside it.
  /// Start and correction entries retain the original scaffold envelope.
  private struct Metadata: Codable {
    let seq: Int
    let at: Date
    let capture: String
  }

  private static func decodeLine(_ data: Data) throws -> GameEvent {
    var object = try decoder.decode([String: JSONValue].self, from: data)
    if let metadata = object.removeValue(forKey: "_log") {
      let m = try decoder.decode(Metadata.self, from: encoder.encode(metadata))
      return GameEvent(seq: m.seq, at: m.at, kind: "record", capture: m.capture, payload: .object(object))
    }
    return try decoder.decode(GameEvent.self, from: data)
  }

  private static func encodeLine(_ event: GameEvent) throws -> Data {
    if event.kind == "record", var object = event.payload.object {
      let m = Metadata(seq: event.seq, at: event.at, capture: event.capture)
      object["_log"] = try decoder.decode(JSONValue.self, from: encoder.encode(m))
      return try encoder.encode(object)
    }
    return try encoder.encode(event)
  }

  private static let encoder: JSONEncoder = {
    let e = JSONEncoder()
    e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    e.dateEncodingStrategy = .iso8601
    return e
  }()
  private static let decoder: JSONDecoder = {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601
    return d
  }()

  /// Opens (or starts) the log at `url`. A last line cut short by a crash mid-write is
  /// dropped; any other damage throws.
  public init(url: URL) throws {
    self.url = url
    events = []
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    let bytes = try Data(contentsOf: url)
    fileBytes = UInt64(bytes.count)
    var start = bytes.startIndex
    while let newline = bytes[start...].firstIndex(of: 0x0A) {
      let number = events.count + 1
      guard let event = try? Self.decodeLine(bytes[start..<newline]) else {
        throw EventLogError.damaged(line: number)
      }
      guard event.seq == number else { throw EventLogError.outOfOrder(line: number) }
      events.append(event)
      start = newline + 1
    }
    committedBytes = UInt64(start)
  }

  /// The next event's sequence number.
  public var nextSeq: Int { events.count + 1 }

  /// Appends one event and syncs the file before returning.
  @discardableResult
  public func append(kind: String, capture: Capture, payload: JSONValue = .null, at: Date = .now) throws
    -> GameEvent
  {
    let event = GameEvent(seq: nextSeq, at: at, kind: kind, capture: capture.headerValue, payload: payload)
    var line = try Self.encodeLine(event)
    line.append(0x0A)
    let fm = FileManager.default
    if !fm.fileExists(atPath: url.path) {
      try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      guard fm.createFile(atPath: url.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
    }
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    let end = try handle.seekToEnd()
    guard end == fileBytes else { throw EventLogError.outOfOrder(line: nextSeq) }
    if end != committedBytes { try handle.truncate(atOffset: committedBytes) }
    do {
      try handle.write(contentsOf: line)
      try handle.synchronize()
    } catch {
      try handle.truncate(atOffset: committedBytes)
      try handle.synchronize()
      fileBytes = committedBytes
      throw error
    }
    committedBytes += UInt64(line.count)
    fileBytes = committedBytes
    events.append(event)
    return event
  }
}
