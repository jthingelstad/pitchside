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
    let text = try String(contentsOf: url, encoding: .utf8)
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    for (i, line) in lines.enumerated() where !line.isEmpty {
      guard let event = try? Self.decoder.decode(GameEvent.self, from: Data(line.utf8)) else {
        // Only the very last line can be a torn write (no newline after it).
        if i == lines.count - 1 && !text.hasSuffix("\n") { break }
        throw EventLogError.damaged(line: i + 1)
      }
      guard event.seq == events.count + 1 else { throw EventLogError.outOfOrder(line: i + 1) }
      events.append(event)
    }
  }

  /// The next event's sequence number.
  public var nextSeq: Int { events.count + 1 }

  /// Appends one event and syncs the file before returning.
  @discardableResult
  public func append(kind: String, capture: Capture, payload: JSONValue = .null, at: Date = .now) throws
    -> GameEvent
  {
    let event = GameEvent(seq: nextSeq, at: at, kind: kind, capture: capture.headerValue, payload: payload)
    var line = try Self.encoder.encode(event)
    line.append(0x0A)
    let fm = FileManager.default
    if !fm.fileExists(atPath: url.path) {
      try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      guard fm.createFile(atPath: url.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
    }
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    // A torn last line from an earlier crash: start on a fresh line.
    let end = try handle.seekToEnd()
    if end > 0 {
      let read = try FileHandle(forReadingFrom: url)
      try read.seek(toOffset: end - 1)
      let last = try read.read(upToCount: 1)
      try read.close()
      if last != Data([0x0A]) {
        try handle.truncate(atOffset: Self.lastGoodEnd(url))
        try handle.seekToEnd()
      }
    }
    try handle.write(contentsOf: line)
    try handle.synchronize()
    events.append(event)
    return event
  }

  /// The byte offset just past the last newline.
  private static func lastGoodEnd(_ url: URL) throws -> UInt64 {
    let data = try Data(contentsOf: url)
    guard let i = data.lastIndex(of: 0x0A) else { return 0 }
    return UInt64(i + 1)
  }
}
