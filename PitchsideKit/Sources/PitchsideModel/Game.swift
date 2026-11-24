import Foundation
import Notation

@_exported import enum Notation.Side

/// A name typed once and kept on this phone only (Roster). Its `key` is permanent: a
/// renamed name keeps its key, and history and stats point at the key.
public struct SavedName: Codable, Sendable, Hashable, Identifiable {
  public let key: UUID
  public var name: String
  public var added: Date

  public var id: UUID { key }

  public init(key: UUID = UUID(), name: String, added: Date = .now) {
    self.key = key
    self.name = name
    self.added = added
  }
}

/// A player on a team, in throwing order: a typed name, and the saved name it came from
/// (or was saved as), if any.
public struct TeamPlayer: Codable, Sendable, Hashable {
  public var name: String
  public var key: UUID?

  public init(name: String, key: UUID? = nil) {
    self.name = name
    self.key = key
  }
}

/// One side's team: its name and 1 to 6 players in throwing order.
public struct Team: Codable, Sendable, Hashable {
  public static let most = 6

  public var name: String
  public var players: [TeamPlayer]

  public init(name: String = "", players: [TeamPlayer] = []) {
    self.name = name
    self.players = players
  }

  /// The team's name, or "Team A" when none was typed.
  public func shownName(_ side: Side) -> String {
    let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return n.isEmpty ? "Team \(side.rawValue)" : n
  }

  public var isFull: Bool { players.count >= Self.most }
  public var isReady: Bool { (1...Self.most).contains(players.count) }
}

/// The match's switches: Throwing Wood's own (kubb-engine `newMatch` options of the same
/// names). No rules presets and no Kid game.
public struct GameOptions: Codable, Sendable, Hashable {
  public enum Opening: String, Codable, Sendable, CaseIterable {
    /// 2 batons in turn 1, 4 in turn 2, then 6 (the engine's `"2-4-6"`).
    case twoFourSix = "2-4-6"
    /// Six batons from the first turn (`"six"`).
    case six
    public var title: String { self == .twoFourSix ? "2-4-6" : "Six batons" }
  }
  public enum Surface: String, Codable, Sendable, CaseIterable {
    case grass, sand, snow
    public var title: String { rawValue.capitalized }
  }
  public enum Wind: String, Codable, Sendable, CaseIterable {
    case off, light, strong
    public var title: String { self == .off ? "Off" : rawValue.capitalized }
  }

  public var opening: Opening
  public var surface: Surface
  public var wind: Wind
  public var first: Side

  public init(opening: Opening = .twoFourSix, surface: Surface = .grass, wind: Wind = .off, first: Side = .A) {
    self.opening = opening
    self.surface = surface
    self.wind = wind
    self.first = first
  }

  /// The engine's `newMatch` options for these switches (kubb-engine docs/SESSION.md).
  public var engineOptions: [String: String] {
    ["opening": opening.rawValue, "surface": surface.rawValue, "wind": wind.rawValue, "first": first.rawValue]
  }
}

/// What to record: independent rows, each a line or token of Planet Kubb Notation,
/// changeable between turns. The turn itself (inkast and batons) is always recorded.
public struct Capture: Codable, Sendable, Hashable {
  /// Who threw each baton and kubb (`k:` prefixes).
  public var who: Bool
  /// Where kubbs stand (`@` pitch lines and `*` felled lines).
  public var stand: Bool
  /// How kubbs lay before they were raised (`~` lines).
  public var lay: Bool
  /// Where batons are thrown from (`^` lines).
  public var stance: Bool

  public init(who: Bool = false, stand: Bool = false, lay: Bool = false, stance: Bool = false) {
    self.who = who
    self.stand = stand
    self.lay = lay
    self.stance = stance
  }

  /// One row of "What to record".
  public enum Row: String, CaseIterable, Sendable, Codable {
    case turn, who, stand, lay, stance

    /// The notation it writes, shown beside the row.
    public var glyph: String {
      switch self {
      case .turn: "5."
      case .who: "k:"
      case .stand: "@ *"
      case .lay: "~"
      case .stance: "^"
      }
    }
    public var title: String {
      switch self {
      case .turn: "The turn"
      case .who: "Who threw"
      case .stand: "Where kubbs stand"
      case .lay: "How kubbs lay"
      case .stance: "Where batons are thrown from"
      }
    }
    public var detail: String {
      switch self {
      case .turn: "Kubbs thrown in and what each baton felled."
      case .who: "Names fill in by order. Tap only to change one."
      case .stand: "Tap where each kubb lands. Felled kubbs come free."
      case .lay: "Drag along each kubb before it is raised."
      case .stance: "Tap the thrower's spot. It sticks until they move."
      }
    }
    /// The word in the `[Pitchside:capture "..."]` header.
    public var word: String { rawValue }
  }

  public func isOn(_ row: Row) -> Bool {
    switch row {
    case .turn: true
    case .who: who
    case .stand: stand
    case .lay: lay
    case .stance: stance
    }
  }

  public mutating func set(_ row: Row, _ on: Bool) {
    switch row {
    case .turn: break
    case .who: who = on
    case .stand: stand = on
    case .lay: lay = on
    case .stance: stance = on
    }
  }

  /// The rows that are on, in order: `turn who stand`.
  public var words: [String] { Row.allCases.filter(isOn).map(\.word) }

  /// The file header's value: `turn who stand`.
  public var headerValue: String { words.joined(separator: " ") }

  /// Reads a header value back; unknown words are ignored.
  public init(headerValue: String) {
    let words = Set(headerValue.split(separator: " ").map(String.init))
    self.init(
      who: words.contains("who"), stand: words.contains("stand"), lay: words.contains("lay"),
      stance: words.contains("stance"))
  }

  /// The words for a games list: "turns, who threw".
  public var summary: String {
    var parts = ["turns"]
    if who { parts.append("who threw") }
    if stand { parts.append("where kubbs stand") }
    if lay { parts.append("how they lay") }
    if stance { parts.append("throwing spots") }
    return parts.joined(separator: ", ")
  }
}

/// One game: its teams, options and capture, where it came from and how far it got. The
/// events are in its log (EventLog), not here; the game file is beside it.
public struct Game: Codable, Sendable, Hashable, Identifiable {
  public enum Origin: Codable, Sendable, Hashable {
    /// Scored on this phone.
    case pitchside
    /// Opened from a file (its name).
    case file(String)
  }
  public enum Status: String, Codable, Sendable {
    /// Teams and options being chosen.
    case setup
    /// Being scored ("Still on the pitch").
    case playing
    /// Over: the game file is final.
    case finished
  }

  public let id: UUID
  public var created: Date
  public var updated: Date
  public var origin: Origin
  public var status: Status
  public var teams: [Side: Team]
  public var options: GameOptions
  public var capture: Capture
  /// The file's player ids to saved-name keys, for stats across games. Filled when a
  /// Pitchside game writes its file.
  public var playerKeys: [String: UUID]

  public init(
    id: UUID = UUID(), created: Date = .now, origin: Origin = .pitchside, status: Status = .setup,
    teams: [Side: Team] = [.A: Team(), .B: Team()], options: GameOptions = GameOptions(),
    capture: Capture = Capture(), playerKeys: [String: UUID] = [:]
  ) {
    self.id = id
    self.created = created
    self.updated = created
    self.origin = origin
    self.status = status
    self.teams = teams
    self.options = options
    self.capture = capture
    self.playerKeys = playerKeys
  }

  public func team(_ side: Side) -> Team { teams[side] ?? Team() }

  public var isReady: Bool { team(.A).isReady && team(.B).isReady }

  public var isImported: Bool {
    if case .file = origin { return true }
    return false
  }
}
