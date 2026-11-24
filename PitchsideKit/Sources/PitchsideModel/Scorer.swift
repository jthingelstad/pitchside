import Foundation

// The seam for the live scorer. Record mode (kubb-engine, being built now) will give the
// engine a way to take a real game's events and say what can happen next; the scorer
// that drives it implements `LiveScorer`, and the app's scorer screen talks only to this
// protocol. Until then `PlaceholderScorer` stands in: it keeps the log and the file's
// headers and records nothing of the game itself.
//
// The rules every scorer keeps (AGENTS.md section 3):
// - the log is the source of truth: `record` appends to the EventLog (synced to disk)
//   before anything else changes, and a scorer opened on a game rebuilds its state from
//   the log alone;
// - undo and edits are new events, never changes to earlier ones;
// - capture rows change only between turns (`canChangeCapture`).

/// What the scorer screen shows above its buttons: a small kicker and the ask.
public struct ScorerPrompt: Sendable, Equatable {
  /// "Turn 5 · inkast · 3 to throw".
  public var kick: String
  /// "Tap where each kubb lands".
  public var text: String

  public init(kick: String, text: String) {
    self.kick = kick
    self.text = text
  }
}

/// The live scorer, as the scorer screen sees it.
public protocol LiveScorer: AnyObject {
  /// The game being scored (teams, options, capture as now).
  var game: Game { get }
  /// The events so far.
  var events: [GameEvent] { get }
  /// What to ask for next.
  var prompt: ScorerPrompt { get }
  /// The winner, once the game is over.
  var winner: Side? { get }
  /// Whether the capture rows may change now (between turns only).
  var canChangeCapture: Bool { get }

  /// Records one event the scorer entered: appended to the log and synced, then applied.
  /// A scorer refuses (throws) what the game cannot take now, and nothing is logged.
  func record(kind: String, payload: JSONValue) throws
  /// Undoes the last thing entered, as a new event.
  func undo() throws
  /// Changes what is recorded from the next turn on.
  func setCapture(_ capture: Capture) throws
  /// The game file so far: headers and every turn entered.
  func notation() throws -> String
}

/// Makes the scorer for a game; the app holds one. Record mode's factory replaces
/// `PlaceholderScorer.Factory`.
public protocol ScorerFactory {
  func scorer(for game: Game, store: GameStore) throws -> LiveScorer
}

/// The stand-in scorer: it starts the log and keeps capture changes, writes the file's
/// headers, and has no turns. Marked as a placeholder wherever it shows.
public final class PlaceholderScorer: LiveScorer {
  public struct Factory: ScorerFactory {
    public let appVersion: String
    public init(appVersion: String) { self.appVersion = appVersion }
    public func scorer(for game: Game, store: GameStore) throws -> LiveScorer {
      try PlaceholderScorer(game: game, store: store, appVersion: appVersion)
    }
  }

  public private(set) var game: Game
  private let store: GameStore
  private let log: EventLog
  private let appVersion: String

  public var events: [GameEvent] { log.events }
  public private(set) var winner: Side?
  public var canChangeCapture: Bool { true }

  public var prompt: ScorerPrompt {
    let first = game.team(game.options.first).shownName(game.options.first)
    return ScorerPrompt(
      kick: "Turn 1 · inkast · placeholder", text: "\(first) throw first. Scoring arrives with record mode.")
  }

  /// Opens the scorer on a game, starting its log if it has none and rebuilding from it
  /// if it has.
  public init(game: Game, store: GameStore, appVersion: String) throws {
    self.game = game
    self.store = store
    self.appVersion = appVersion
    self.log = try store.log(game.id)
    if log.events.isEmpty {
      try log.append(kind: GameEvent.Kind.start, capture: game.capture)
    }
    replay()
    if self.game.status == .setup {
      self.game.status = .playing
      try store.save(self.game)
    }
  }

  /// State from the log alone.
  private func replay() {
    for event in log.events {
      switch event.kind {
      case GameEvent.Kind.capture: game.capture = Capture(headerValue: event.capture)
      case GameEvent.Kind.end:
        if case .object(let o) = event.payload, case .string(let s) = o["winner"] { winner = Side(rawValue: s) }
      default: break
      }
    }
  }

  public func record(kind: String, payload: JSONValue) throws {
    try log.append(kind: kind, capture: game.capture, payload: payload)
    if kind == GameEvent.Kind.end, case .object(let o) = payload, case .string(let s) = o["winner"] {
      winner = Side(rawValue: s)
    }
  }

  public func undo() throws {
    try log.append(kind: "undo", capture: game.capture)
  }

  public func setCapture(_ capture: Capture) throws {
    guard canChangeCapture else { return }
    try log.append(kind: GameEvent.Kind.capture, capture: capture)
    game.capture = capture
    try store.save(game)
  }

  /// Every capture row on at some point in the game.
  var captureEver: Capture {
    var ever = Capture(who: false)
    for event in log.events {
      let c = Capture(headerValue: event.capture)
      for row in Capture.Row.allCases where c.isOn(row) { ever.set(row, true) }
    }
    return ever
  }

  public func notation() throws -> String {
    GameFile.headers(for: game, appVersion: appVersion, captureEver: captureEver, winner: winner)
  }
}
