import Foundation

/// A side of the pitch, as the notation names them.
public enum Side: String, Codable, CodingKeyRepresentable, Sendable, CaseIterable, Hashable {
  case A, B
  public var other: Side { self == .A ? .B : .A }
}

/// One file read: kubb.js's analysis, Pitchside's few added figures, and the grammar's
/// verdict on the text.
public struct GameRead: Decodable, Sendable {
  public let analysis: Analysis
  public let figures: [String: Figures]
  public let grammar: Grammar
  /// Whether the text is already canonical (canonical.js's `isCanonical`).
  public let canonical: Bool
  /// A Kid rules game (the reader refuses these).
  public let kid: Bool

  public func figures(_ side: Side) -> Figures {
    figures[side.rawValue] ?? Figures(zeroBase: nil, from8: .init(batons: 0, hits: 0))
  }

  /// Pitchside's own figures for a side (not kubb.js's; see Reader.swift).
  public struct Figures: Decodable, Sendable, Equatable {
    public struct Spot: Decodable, Sendable, Equatable {
      public let turn: Int
      public let baton: Int
      public init(turn: Int, baton: Int) {
        self.turn = turn
        self.baton = baton
      }
    }
    public struct Tally: Decodable, Sendable, Equatable {
      public let batons: Int
      public let hits: Int
      public init(batons: Int, hits: Int) {
        self.batons = batons
        self.hits = hits
      }
      public var pct: Double? { batons > 0 ? Double(hits) / Double(batons) : nil }
    }
    /// The turn and baton where the side's base kubbs were all down.
    public let zeroBase: Spot?
    /// Batons from the baseline at base kubbs and the king.
    public let from8: Tally
  }

  /// The grammar's strict reading (notation-parser.js): kubb.js reads leniently and
  /// warns; the grammar says whether the file is valid notation at all.
  public struct Grammar: Decodable, Sendable, Equatable {
    public let ok: Bool
    public let message: String?
    public let line: Int?
    public let column: Int?
  }
}

/// kubb.js's `analyze(text)`, the fields Pitchside shows. Names and meanings are
/// kubb.js's own.
public struct Analysis: Decodable, Sendable {
  public let headers: [String: String]
  public let rules: Rules
  public let teamName: [String: String]
  public let first: Side
  public let firstSource: String
  public let winner: Side?
  public let winHow: String?
  public let endTurn: Int?
  public let rows: [Row]
  public let stats: [String: SideStats]
  public let players: [Player]
  public let warnings: [String]
  public let turnWarnings: Int

  public func name(_ side: Side) -> String { teamName[side.rawValue] ?? "Team \(side.rawValue)" }
  public func stats(_ side: Side) -> SideStats? { stats[side.rawValue] }

  public struct Rules: Decodable, Sendable, Equatable {
    public let baseKubbs: Int
    public let batons: Int
    public let opening: [Int]
  }

  public struct Row: Decodable, Sendable {
    public let turn: Int
    public let team: Side
    /// Kubbs thrown in the inkast (recorded or worked out).
    public let inkast: Int
    public let inkastRecorded: Bool
    public let advantage: Bool
    public let startField: Int
    public let startBase: Int
    public let knocked: Int
    /// Batons to clear the field this turn (nil: not cleared; 0: none to clear).
    public let btc: Int?
    public let fieldLeft: Int
    /// Base kubbs standing on each side after the turn ("A", "B").
    public let base: [String: Int]
    public let batons: [Baton]
    public let note: String?
    public let warnings: [String]
    public let source: String?

    /// Batons thrown (not unthrown, not a W or G mark).
    public var thrown: [Baton] { batons.filter(\.isThrown) }
    public var hits: Int { thrown.filter(\.isHit).count }
  }

  public struct Baton: Decodable, Sendable {
    /// kubb.js's kinds: hit, miss, king, kingmiss, illegalking, unthrown, win, resign.
    public let kind: String
    public let f: Int?
    public let b: Int?
    public let e: Bool?
    public let player: String?
    public let void: Bool?

    public var isThrown: Bool { void != true && !["unthrown", "win", "resign"].contains(kind) }
    public var isHit: Bool { (kind == "hit" && e != true) || kind == "king" }
  }

  public struct SideStats: Decodable, Sendable {
    public let turns: Int
    public let batons: Int
    public let hits: Int
    public let field: Int
    public let base: Int
    public let kings: Int
    public let I: Int
    public let R: Int
    public let P: Int
    public let Y: Int
    public let Q: Int
    public let N: Int
    public let effF: Int
    public let effI: Int
    /// The team's throw number when its opponent's base reached zero (the scoresheet's
    /// "Zero B @ T#").
    public let zeroBaseAt: Int?
    public let btc: [Int]
    public let uncleared: Int
    public let advTurns: Int
    public let advBatons: Int
    public let advHits: Int
    public let bestBlast: Int
    public let hitPct: Double?
    /// Sum of field kubbs felled by each turn's first baton over sum of kubbs thrown in
    /// (the scoresheet's "1st baton efficiency").
    public let efficiency: Double?
    public let rethrowPct: Double?
    public let btcAvg: Double?
    public let advHitPct: Double?
  }

  public struct Player: Decodable, Sendable, Identifiable {
    public let id: String
    public let name: String?
    public let side: Side
    public let batons: Int
    public let hits: Int
    public let field: Int
    public let base: Int
    public let kings: Int
    public let hitPct: Double?
  }
}

extension Analysis {
  /// The winner's own base kubbs still standing at the end: how far the loser got.
  public var winnerBaseStanding: Int? {
    guard let winner, let last = rows.last else { return nil }
    return last.base[winner.rawValue]
  }
}
