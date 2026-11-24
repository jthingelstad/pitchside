import Foundation
import KubbEngine

/// The live scorer over kubb-engine's record mode (docs/RECORD.md).
///
/// The log (`events.jsonl`) is the source of truth. Its lines:
///
///     start   {"setup": {...}}                  the game as record mode takes it
///     record  {"type": "baton", "id": "e7", "time": {...}, ...}   one record event
///     undo    {"id": "e7"}                      the last record event dropped
///     edit    {"replace": "e4", "event": {...}} an earlier event rewritten
///             {"insert": "e4", "event": {...}}  one put in before e4
///             {"remove": "e4"}                  one taken out
///
/// Folding the log gives the record events, which `record.rebuild` turns into the game.
/// Each action is `record.add` (or a rebuild for undo and edits), then a line appended
/// and synced, then `game.txt` rewritten from `want.notation`. The game stays a draft
/// (`playing`) until `state.over`.
public final class RecordScorer: LiveScorer {
  public struct Factory: ScorerFactory {
    public let appVersion: String
    public let zone: TimeZone
    public let clock: @Sendable () -> Date

    public init(appVersion: String, zone: TimeZone = .current, clock: @escaping @Sendable () -> Date = { .now }) {
      self.appVersion = appVersion
      self.zone = zone
      self.clock = clock
    }

    public func scorer(for game: Game, store: GameStore) throws -> LiveScorer {
      try RecordScorer(game: game, store: store, appVersion: appVersion, zone: zone, clock: clock)
    }
  }

  public enum Kind {
    public static let record = "record"
    public static let undo = "undo"
    public static let edit = "edit"
  }

  public private(set) var game: Game
  public private(set) var state: RecordState
  public private(set) var warnings: [RecordWarning] = []
  public private(set) var lastWarnings: [RecordWarning] = []
  public private(set) var rows: [RecordRow] = []
  public private(set) var records: [[String: JSONValue]] = []
  public private(set) var text: String = ""
  /// The setup record mode was given (from the log's start line).
  public let setup: JSONValue

  private let store: GameStore
  private let log: EventLog
  private let engine: Engine
  private let zone: TimeZone
  private let clock: () -> Date
  /// Whether each event gets its `time` (tests replaying a log without times turn it off).
  private let stampTimes: Bool

  public var winner: Side? { state.winner }

  /// Opens the scorer on a game: starts its log if it has none, and rebuilds from it.
  public init(
    game: Game, store: GameStore, appVersion: String, zone: TimeZone = .current,
    clock: @escaping () -> Date = { .now }, setup given: JSONValue? = nil, stampTimes: Bool = true
  ) throws {
    self.game = game
    self.store = store
    self.zone = zone
    self.clock = clock
    self.stampTimes = stampTimes
    log = try store.log(game.id)
    engine = try Engine(appVersion: appVersion)
    let client = "\(appVersion) (\(engine.engineVersion))"
    let savedSetup = log.events.first { $0.kind == GameEvent.Kind.start && $0.payload["setup"] != nil }
    setup = savedSetup?.payload["setup"] ?? given ?? Self.setup(for: game, client: client, zone: zone)
    records = Self.fold(log.events)
    let result = try Self.decode(
      engine.call("record.rebuild", json: Self.args(["game": setup, "events": .array(records.map(JSONValue.object)), "want": Self.want])))
    state = result.state
    take(result)
    if savedSetup == nil {
      try log.append(kind: GameEvent.Kind.start, capture: game.capture, payload: .object(["setup": setup]), at: clock())
    }
    if self.game.status == .setup { self.game.status = .playing }
    keepPlayerKeys()
    try settle()
  }

  // MARK: The setup

  /// The setup record mode takes for a game (docs/RECORD.md "The game"). Players get
  /// explicit ids from their names written in Latin letters first, so names in other
  /// scripts or with accents do not all become `p`.
  public static func setup(for game: Game, client: String, zone: TimeZone) -> JSONValue {
    var teams: [String: JSONValue] = [:]
    for side in Side.allCases {
      let team = game.team(side)
      let players: [JSONValue] = team.players.map { p in
        .object(["name": .string(p.name), "id": .string(playerId(p.name))])
      }
      teams[side.rawValue] = .object(["name": .string(team.shownName(side)), "players": .array(players)])
    }
    var o: [String: JSONValue] = [
      "teams": .object(teams),
      "first": .string(game.options.first.rawValue),
      "opening": .string(game.options.opening.rawValue),
      "surface": .string(game.options.surface.rawValue),
      "wind": .string(game.options.wind.rawValue),
      "client": .string(client),
      "start": time(game.created, zone: zone),
      "capture": .object([
        "players": .bool(game.capture.who), "pitch": .bool(game.capture.stand), "lay": .bool(game.capture.lay),
        "stance": .bool(game.capture.stance),
      ]),
    ]
    if let e = game.event?.trimmingCharacters(in: .whitespaces), !e.isEmpty { o["event"] = .string(e) }
    if let l = game.location?.trimmingCharacters(in: .whitespaces), !l.isEmpty { o["location"] = .string(l) }
    return .object(o)
  }

  /// A player's id: the name in Latin letters without accents, then the notation's own
  /// `baseId` (the engine makes taken ids unique with `_b`, `_c`).
  public static func playerId(_ name: String) -> String {
    let latin = name.applyingTransform(StringTransform("Any-Latin; Latin-ASCII"), reverse: false) ?? name
    return GameFile.baseId(latin)
  }

  /// `{ year, month, day, hour, min }` in the phone's zone.
  public static func time(_ date: Date, zone: TimeZone) -> JSONValue {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = zone
    let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    return .object([
      "year": .number(Double(c.year!)), "month": .number(Double(c.month!)), "day": .number(Double(c.day!)),
      "hour": .number(Double(c.hour!)), "min": .number(Double(c.minute!)),
    ])
  }

  // MARK: The log

  /// The record events a log comes to.
  public static func fold(_ events: [GameEvent]) -> [[String: JSONValue]] {
    var out: [[String: JSONValue]] = []
    func index(_ id: String?) -> Int? { id.flatMap { id in out.firstIndex { $0["id"]?.string == id } } }
    for e in events {
      switch e.kind {
      case Kind.record:
        if let o = e.payload.object { out.append(o) }
      case Kind.undo:
        if let i = index(e.payload["id"]?.string) { out.remove(at: i) }
      case Kind.edit:
        if let i = index(e.payload["replace"]?.string), let new = e.payload["event"]?.object {
          var event = new
          event["id"] = out[i]["id"]
          if event["time"] == nil { event["time"] = out[i]["time"] }
          out[i] = event
        } else if let i = index(e.payload["insert"]?.string), let new = e.payload["event"]?.object {
          out.insert(new, at: i)
        } else if let i = index(e.payload["remove"]?.string) {
          out.remove(at: i)
        }
      default: break
      }
    }
    return out
  }

  private func nextId() -> String { "e\(log.nextSeq)" }

  // MARK: Actions

  @discardableResult
  public func add(_ event: [String: JSONValue]) throws -> [RecordWarning] {
    var event = event
    event["id"] = .string(nextId())
    if stampTimes, event["time"] == nil { event["time"] = Self.time(clock(), zone: zone) }
    let result = try Self.decode(
      engine.call("record.add", json: Self.args(["event": .object(event), "want": Self.want])))
    do {
      try log.append(kind: Kind.record, capture: game.capture, payload: .object(event), at: clock())
    } catch {
      // Not in the log, so not in the game: back to what the log says.
      try rebuild()
      throw error
    }
    records.append(event)
    take(result)
    lastWarnings = result.added?.warnings ?? []
    try settle()
    return lastWarnings
  }

  public func undo() throws {
    guard let last = records.last else { return }
    try log.append(kind: Kind.undo, capture: game.capture, payload: .object(["id": last["id"] ?? .null]), at: clock())
    records.removeLast()
    take(try Self.decode(engine.call("record.undo", json: Self.args(["want": Self.want]))))
    lastWarnings = []
    try settle()
  }

  public func edit(_ edit: RecordEdit) throws {
    let payload: [String: JSONValue]
    switch edit {
    case .replace(let id, let event): payload = ["replace": .string(id), "event": .object(event)]
    case .insert(let id, var event):
      event["id"] = .string(nextId())
      payload = ["insert": .string(id), "event": .object(event)]
    case .remove(let id): payload = ["remove": .string(id)]
    }
    try log.append(kind: Kind.edit, capture: game.capture, payload: .object(payload), at: clock())
    records = Self.fold(log.events)
    try rebuild()
    lastWarnings = []
    try settle()
  }

  public func preview(_ edit: RecordEdit) throws -> RecordResult {
    var list = records
    switch edit {
    case .replace(let id, var event):
      if let i = list.firstIndex(where: { $0["id"]?.string == id }) {
        event["id"] = list[i]["id"]
        if event["time"] == nil { event["time"] = list[i]["time"] }
        list[i] = event
      }
    case .insert(let id, var event):
      event["id"] = "preview"
      if let i = list.firstIndex(where: { $0["id"]?.string == id }) { list.insert(event, at: i) }
    case .remove(let id):
      list.removeAll { $0["id"]?.string == id }
    }
    return try Self.decode(
      engine.call("record.build", json: Self.args(["game": setup, "events": .array(list.map(JSONValue.object)), "want": Self.want])))
  }

  public func setCapture(_ capture: Capture) throws {
    try add(RecordEvent.capture(capture))
  }

  public var captureAppliesNow: Bool {
    !state.over && rows.last?.turn != state.turn
  }

  public func notation() throws -> String { text }

  // MARK: The timeline

  public func timeline() throws -> [TimelineTurn] {
    // A second engine, so the held game is not touched: each event added in turn, the
    // turn it went into read before it.
    let scratch = try Engine(appVersion: "0")
    var before = try Self.decode(scratch.call("record.new", json: Self.args(["game": setup]))).state
    var events: [TimelineEvent] = []
    var turnSide: [Int: Side] = [:]
    for (i, e) in records.enumerated() {
      let turn = before.turn
      let side = before.attacker ?? (before.over ? (turnSide[turn] ?? .A) : .A)
      turnSide[turn] = turnSide[turn] ?? side
      let r = try Self.decode(scratch.call("record.add", json: Self.args(["event": .object(e)])))
      events.append(
        TimelineEvent(
          id: e["id"]?.string ?? "\(i)", index: i, event: e, turn: turn, side: turnSide[turn]!,
          before: before, warnings: r.added?.warnings ?? []))
      before = r.state
    }
    let byTurn = Dictionary(grouping: events, by: \.turn)
    let rowByTurn = Dictionary(rows.map { ($0.turn, $0) }, uniquingKeysWith: { a, _ in a })
    let turns = Set(byTurn.keys).union(rowByTurn.keys).sorted()
    return turns.map { n in
      TimelineTurn(
        turn: n, side: rowByTurn[n]?.side ?? turnSide[n] ?? .A, row: rowByTurn[n], events: byTurn[n] ?? [])
    }
  }

  // MARK: Engine plumbing

  static let want: JSONValue = .object(["notation": true, "sheet": true])

  static func args(_ o: [String: JSONValue]) -> String { JSONValue.object(o).json }

  static func decode(_ text: String) throws -> RecordResult {
    try JSONDecoder().decode(RecordResult.self, from: Data(text.utf8))
  }

  private func rebuild() throws {
    take(
      try Self.decode(
        engine.call(
          "record.rebuild",
          json: Self.args(["game": setup, "events": .array(records.map(JSONValue.object)), "want": Self.want]))))
  }

  private func take(_ r: RecordResult) {
    state = r.state
    warnings = r.warnings
    if let n = r.notation { text = n.text }
    if let s = r.sheet { rows = s.rows }
  }

  /// The file, and the game's status, after every change.
  private func settle() throws {
    try store.writeFile(text, for: game.id)
    let status: Game.Status = state.over ? .finished : .playing
    let capture = Capture(
      who: state.capture.players, stand: state.capture.pitch, lay: state.capture.lay, stance: state.capture.stance)
    if status != game.status || capture != game.capture {
      game.status = status
      game.capture = capture
    }
    try store.save(game)
  }

  /// The file's player ids (the prefixes kubb.js reads) to saved-name keys.
  private func keepPlayerKeys() {
    var keys: [String: UUID] = [:]
    for side in Side.allCases {
      for (p, tp) in zip(state.side(side).players, game.team(side).players) {
        if let key = tp.key { keys[p.file ?? p.id] = key }
      }
    }
    game.playerKeys = keys
  }

  // MARK: The prompt

  public var prompt: ScorerPrompt {
    let n = state.next
    switch n.kind {
    case "toss":
      let left = n.left ?? 0
      return ScorerPrompt(
        kick: "Turn \(state.turn) · inkast · \(left) to throw",
        text: n.rethrow == true ? "A rethrow. In, or out again?" : "Kubbs thrown in: all in, or say which went out.")
    case "baton":
      let k = n.kingShot == true ? " · king" : ""
      return ScorerPrompt(
        kick: "Turn \(state.turn) · baton \(n.n ?? 1) of \(n.of ?? 6)\(k)",
        text: n.kingShot == true ? "The king shot." : "What did this baton fell?")
    default:
      let w = state.winner.map { game.team($0).shownName($0) } ?? "Nobody"
      return ScorerPrompt(kick: "Game over", text: "\(w) win.")
    }
  }
}
