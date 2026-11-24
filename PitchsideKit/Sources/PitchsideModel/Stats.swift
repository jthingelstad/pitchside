import Foundation
import Notation

/// The stats of one game, in the Planet Kubb scoresheet's order. Every number is
/// kubb.js's except where noted (`fromEight`, `zeroBaseSpot`: Pitchside's own, from
/// kubb.js's rows; Reader.swift says how).
public struct GameStats: Sendable {
  public struct SideLine: Sendable {
    public let side: Side
    public let name: String
    /// Hit %: hits over batons thrown.
    public let hitPct: Double?
    public let hits: Int
    public let batons: Int
    /// 1st baton efficiency: field kubbs felled by each turn's first baton over the
    /// kubbs thrown in (sum F@1 / sum I).
    public let efficiency: Double?
    public let effF: Int
    public let effI: Int
    /// Zero B @ T#: the team's throw number when the other side's base was down.
    public let zeroBaseAt: Int?
    /// Where that was: turn and baton of the turn (Pitchside's own).
    public let zeroBaseSpot: GameRead.Figures.Spot?
    /// Rethrows over kubbs thrown in.
    public let rethrowPct: Double?
    public let rethrown: Int
    public let inkasted: Int
    /// Batons to clear the field, per turn that had field kubbs to clear.
    public let btc: [Int]
    public let btcAvg: Double?
    public let uncleared: Int
    /// From 8 metres: base kubbs and the king from the baseline (Pitchside's own).
    public let fromEight: GameRead.Figures.Tally
  }

  public struct PlayerLine: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let side: Side
    public let batons: Int
    public let hits: Int
    public let hitPct: Double?
  }

  public let sides: [SideLine]
  public let players: [PlayerLine]
  public let turns: Int

  public init(_ read: GameRead) {
    let a = read.analysis
    sides = Side.allCases.compactMap { side in
      guard let s = a.stats(side) else { return nil }
      return SideLine(
        side: side, name: a.name(side), hitPct: s.hitPct, hits: s.hits, batons: s.batons,
        efficiency: s.efficiency, effF: s.effF, effI: s.effI, zeroBaseAt: s.zeroBaseAt,
        zeroBaseSpot: read.figures(side).zeroBase, rethrowPct: s.rethrowPct, rethrown: s.R, inkasted: s.I + s.Y,
        btc: s.btc, btcAvg: s.btcAvg, uncleared: s.uncleared, fromEight: read.figures(side).from8)
    }
    players = a.players.map {
      PlayerLine(id: $0.id, name: $0.name ?? $0.id, side: $0.side, batons: $0.batons, hits: $0.hits, hitPct: $0.hitPct)
    }
    turns = a.rows.count
  }

  public func side(_ side: Side) -> SideLine? { sides.first { $0.side == side } }
}

/// One saved name's batons across the games it played (Pitchside's own games, where the
/// file's player ids point at saved names).
public struct NameTotals: Sendable, Equatable {
  public var games = 0
  public var wins = 0
  public var batons = 0
  public var hits = 0
  public var field = 0
  public var base = 0
  public var kings = 0
  public var hitPct: Double? { batons > 0 ? Double(hits) / Double(batons) : nil }

  public init() {}

  /// Totals by saved-name key over finished games and their files read.
  public static func across(_ games: [(Game, GameRead)]) -> [UUID: NameTotals] {
    var out: [UUID: NameTotals] = [:]
    for (game, read) in games {
      var seen = Set<UUID>()
      for p in read.analysis.players {
        guard let key = game.playerKeys[p.id] else { continue }
        var t = out[key] ?? NameTotals()
        if seen.insert(key).inserted {
          t.games += 1
          if read.analysis.winner == p.side { t.wins += 1 }
        }
        t.batons += p.batons
        t.hits += p.hits
        t.field += p.field
        t.base += p.base
        t.kings += p.kings
        out[key] = t
      }
    }
    return out
  }
}

/// Percent as the sheet writes it: `42%`, or `-` for none.
public func percent(_ value: Double?) -> String {
  guard let value else { return "-" }
  return "\(Int((value * 100).rounded()))%"
}
