import Foundation

// The seam for the live scorer: the scorer screen and the timeline talk only to
// `LiveScorer`. `RecordScorer` (RecordScorer.swift) is the one that scores, over
// kubb-engine's record mode.
//
// The rules every scorer keeps (AGENTS.md section 3):
// - the log is the source of truth: an action goes to the engine and is appended to the
//   EventLog (synced to disk) before the screen moves on, and a scorer opened on a game
//   rebuilds its state from the log alone;
// - undo and edits are new lines in the log, never changes to earlier ones: the record
//   events the engine sees are the log folded (an undo drops the last one, an edit
//   replaces, inserts or removes one);
// - the engine records what it is told and warns; the scorer never refuses a throw.

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

/// An edit to an earlier event, as the log keeps it.
public enum RecordEdit: Sendable, Equatable {
  /// The event with this id becomes `event` (keeping its id and time).
  case replace(id: String, event: [String: JSONValue])
  /// `event` goes in just before the event with this id.
  case insert(before: String, event: [String: JSONValue])
  /// The event with this id goes.
  case remove(id: String)
}

/// The live scorer, as the scorer screen and the timeline see it.
public protocol LiveScorer: AnyObject {
  /// The game being scored (teams, options, capture as now).
  var game: Game { get }
  /// The engine's state now.
  var state: RecordState { get }
  /// Every warning the game has (the engine's, as of the last rebuild or add).
  var warnings: [RecordWarning] { get }
  /// The warnings the last action raised (the chip; never a block).
  var lastWarnings: [RecordWarning] { get }
  /// The score sheet's rows so far.
  var rows: [RecordRow] { get }
  /// The record events the engine holds, in order, each with its `id`.
  var records: [[String: JSONValue]] { get }
  /// What to ask for next.
  var prompt: ScorerPrompt { get }
  /// The winner, once the game is over.
  var winner: Side? { get }
  /// Whether a capture change applies to the turn now (it has nothing in it yet);
  /// otherwise it starts with the next turn.
  var captureAppliesNow: Bool { get }

  /// Records one event: the engine takes it, then it is appended to the log and synced.
  /// Returns the warnings it raised.
  @discardableResult func add(_ event: [String: JSONValue]) throws -> [RecordWarning]
  var undoAction: ScoreAction? { get }
  var redoAction: ScoreAction? { get }
  /// Reverse or restore the last scoring action, including a timeline correction.
  func undo() throws
  func redo() throws
  /// Rewrites the record events (an edit) and rebuilds.
  func edit(_ edit: RecordEdit) throws
  /// What the game would be after an edit, touching nothing.
  func preview(_ edit: RecordEdit) throws -> RecordResult
  /// Changes what is recorded (a `capture` event).
  func setCapture(_ capture: Capture) throws
  /// The game file so far.
  func notation() throws -> String
  /// The turns, each with the events that made it, for the timeline.
  func timeline() throws -> [TimelineTurn]
}

/// Makes the scorer for a game; the app holds one.
public protocol ScorerFactory {
  func scorer(for game: Game, store: GameStore) throws -> LiveScorer
}

/// One event on the timeline.
public struct TimelineEvent: Sendable, Identifiable, Equatable {
  public let id: String
  /// Its place among the record events (0-based).
  public let index: Int
  public let event: [String: JSONValue]
  /// The turn in progress when the observation was made.
  public let turn: Int
  /// The sheet row where the engine wrote it. A call or resignation can move to the other side’s row.
  public let sheetTurn: Int
  public let side: Side
  /// The context of this observation, before applying it.
  public let before: RecordState
  /// The thrower's inkast word immediately after this toss, when the sheet recorded one.
  public let inkastMark: String?
  /// The warnings it raised.
  public let warnings: [RecordWarning]

  public var type: String { event["type"]?.string ?? "" }
}

/// One turn on the timeline: its row (when the file writes it) and its events.
public struct TimelineTurn: Sendable, Identifiable, Equatable {
  public let turn: Int
  public let side: Side
  public let row: RecordRow?
  public let events: [TimelineEvent]
  public var id: Int { turn }

  /// The turn's batons, in order.
  public var batons: [TimelineEvent] { events.filter { $0.type == "baton" } }
}
