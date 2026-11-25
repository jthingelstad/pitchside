import Foundation
import KubbEngine

/// The live scorer over kubb-engine's record mode (docs/RECORD.md).
///
/// The log (`events.jsonl`) is the source of truth. Its lines:
///
///     start   {"setup": {...}}                  the game as record mode takes it
///     record  {"type": "baton", "id": "e7", "time": {...}, ...}   one record event
///     undo    {"change": 7}                     reverse the last observation or edit
///     redo    {"change": 7}                     reapply the last undone action
///     undo    {"id": "e7"}                      legacy removal of a named observation
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
    public static let redo = "redo"
    public static let edit = "edit"
  }

  public private(set) var game: Game
  public private(set) var state: RecordState
  public private(set) var warnings: [RecordWarning] = []
  public private(set) var lastWarnings: [RecordWarning] = []
  public private(set) var rows: [RecordRow] = []
  private var history: ScoreHistory
  public var records: [[String: JSONValue]] { history.records }
  public var undoAction: ScoreAction? { history.undoAction }
  public var redoAction: ScoreAction? { history.redoAction }
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
    history = ScoreHistory(log.events)
    let result = try Self.decode(
      engine.call("record.rebuild", json: Self.args(["game": setup, "events": .array(history.records.map(JSONValue.object)), "want": Self.want])))
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
    ScoreHistory(events).records
  }

  /// Read a saved sheet’s history controls and rule warnings without opening a writer.
  public static func review(_ log: EventLog) throws -> (history: ScoreHistory, warnings: [RecordWarning]) {
    let history = ScoreHistory(log.events)
    guard let setup = log.events.first(where: { $0.kind == GameEvent.Kind.start && $0.payload["setup"] != nil })?.payload["setup"]
    else { return (history, []) }
    let engine = try Engine(appVersion: "0")
    let result = try decode(engine.call("record.build", json: args([
      "game": setup, "events": .array(history.records.map(JSONValue.object)),
    ])))
    return (history, result.warnings)
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
    history.apply(kind: Kind.record, payload: .object(event), sequence: log.nextSeq - 1)
    take(result)
    lastWarnings = result.added?.warnings ?? []
    try settle()
    return lastWarnings
  }

  public func undo() throws {
    guard let seq = history.undoSequence else { return }
    try commitChange(Kind.undo, payload: .object(["change": .number(Double(seq))]))
  }

  public func redo() throws {
    guard let seq = history.redoSequence else { return }
    try commitChange(Kind.redo, payload: .object(["change": .number(Double(seq))]))
  }

  private func payload(for edit: RecordEdit) throws -> JSONValue {
    let id: String
    let payload: [String: JSONValue]
    switch edit {
    case .replace(let target, let event):
      id = target
      payload = ["replace": .string(id), "event": .object(event)]
    case .insert(let target, var event):
      id = target
      event["id"] = .string(nextId())
      payload = ["insert": .string(id), "event": .object(event)]
    case .remove(let target):
      id = target
      payload = ["remove": .string(id)]
    }
    guard records.contains(where: { $0["id"]?.string == id }) else { throw HistoryError.missingEntry }
    return .object(payload)
  }

  private enum HistoryError: LocalizedError {
    case missingEntry
    var errorDescription: String? { "This observation is no longer in the game." }
  }

  public func edit(_ edit: RecordEdit) throws {
    try commitChange(Kind.edit, payload: payload(for: edit))
  }

  private func commitChange(_ kind: String, payload: JSONValue) throws {
    var next = history
    guard next.apply(kind: kind, payload: payload, sequence: log.nextSeq) else { return }
    let result: RecordResult
    do {
      result = try build("record.rebuild", history: next)
      try log.append(kind: kind, capture: game.capture, payload: payload, at: clock())
    } catch {
      try rebuild()
      throw error
    }
    history = next
    take(result)
    lastWarnings = []
    try settle()
  }

  public func preview(_ edit: RecordEdit) throws -> RecordResult {
    var next = history
    next.apply(kind: Kind.edit, payload: try payload(for: edit), sequence: log.nextSeq)
    return try build("record.build", history: next)
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
    var events: [TimelineEvent] = []
    try Self.walk(setup: setup, records: records) { entry, _ in events.append(entry) }
    let byTurn = Dictionary(grouping: events, by: \.sheetTurn)
    let rowByTurn = Dictionary(rows.map { ($0.turn, $0) }, uniquingKeysWith: { a, _ in a })
    let turns = Set(byTurn.keys).union(rowByTurn.keys).sorted()
    return turns.map { n in
      TimelineTurn(
        turn: n, side: rowByTurn[n]?.side ?? byTurn[n]?.first?.side ?? .A, row: rowByTurn[n], events: byTurn[n] ?? [])
    }
  }

  /// Visit each effective event with the state on either side, without changing the game.
  static func walk(setup: JSONValue, records: [[String: JSONValue]],
                   visit: (TimelineEvent, RecordState) -> Void) throws {
    let scratch = try Engine(appVersion: "0")
    var before = try decode(scratch.call("record.new", json: args(["game": setup]))).state
    var side = before.attacker ?? .A
    for (i, event) in records.enumerated() {
      side = before.attacker ?? side
      let r = try decode(scratch.call("record.add", json: args(["event": .object(event)])))
      let entry = TimelineEvent(id: event["id"]?.string ?? "\(i)", index: i, event: event,
                                turn: before.turn, sheetTurn: !before.over && r.state.over ? r.state.turn : before.turn,
                                side: side, before: before, warnings: r.added?.warnings ?? [])
      visit(entry, r.state)
      before = r.state
    }
  }

  // MARK: Engine plumbing

  static let want: JSONValue = .object(["notation": true, "sheet": true])

  static func args(_ o: [String: JSONValue]) -> String { JSONValue.object(o).json }

  static func decode(_ text: String) throws -> RecordResult {
    try JSONDecoder().decode(RecordResult.self, from: Data(text.utf8))
  }

  private func build(_ call: String, history: ScoreHistory) throws -> RecordResult {
    try Self.decode(engine.call(call, json: Self.args([
      "game": setup, "events": .array(history.records.map(JSONValue.object)), "want": Self.want,
    ])))
  }

  private func rebuild() throws { take(try build("record.rebuild", history: history)) }

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
