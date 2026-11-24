import Foundation

/// Where the scorer stands to watch, and how a tap on the drawn pitch becomes a position
/// in the notation's frame.
///
/// The pitch's own frame here ("world") is the design's: `x` 0 to 5 metres across, `y` 0
/// at Team A's baseline to 8 at Team B's, the centre line at `y` 4, `x` 0 on Team A's
/// left as Team A stands on its baseline facing the king. The notation's frame
/// (pk-kubb-score notation-2.md "The pitch frame") has its origin at the centre-line
/// stake on Team A's left, which does not move: `across` = `x` in both halves, `depth` =
/// metres from the centre line.
///
/// The screen is the drawn pitch's unit square: `u` 0 (left) to 1 (right), `v` 0 (top) to
/// 1 (bottom).
public enum PitchFrame {
  public static let width = 5.0
  public static let length = 8.0
  public static let centre = 4.0

  public enum View: String, Sendable, CaseIterable, Codable {
    /// Behind Team A's baseline, looking at Team B's: A's baseline at the bottom.
    case behindA
    /// Behind Team B's baseline: B's at the bottom, left and right turned round.
    case behindB
    /// On the sideline at Team A's left: A's baseline on the left, B's on the right.
    case sideline

    /// The view behind a side's baseline.
    public static func behind(_ side: Side) -> View { side == .A ? .behindA : .behindB }

    /// The view switch's order: A, sideline, B.
    public var next: View {
      switch self {
      case .behindA: .sideline
      case .sideline: .behindB
      case .behindB: .behindA
      }
    }

    public var title: String {
      switch self {
      case .behindA: "Behind Team A"
      case .behindB: "Behind Team B"
      case .sideline: "Sideline"
      }
    }

    /// Whether the pitch is drawn lying down (wider than tall).
    public var isSideways: Bool { self == .sideline }
  }

  /// A point on the pitch, in metres.
  public struct World: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) {
      self.x = x
      self.y = y
    }
  }

  /// A point on the drawn pitch, 0 to 1 both ways.
  public struct Screen: Sendable, Equatable {
    public var u: Double
    public var v: Double
    public init(u: Double, v: Double) {
      self.u = u
      self.v = v
    }
  }

  public static func screen(_ p: World, in view: View) -> Screen {
    switch view {
    case .behindA: Screen(u: p.x / width, v: (length - p.y) / length)
    case .behindB: Screen(u: (width - p.x) / width, v: p.y / length)
    case .sideline: Screen(u: p.y / length, v: p.x / width)
    }
  }

  public static func world(_ s: Screen, in view: View) -> World {
    switch view {
    case .behindA: World(x: s.u * width, y: length - s.v * length)
    case .behindB: World(x: width - s.u * width, y: s.v * length)
    case .sideline: World(x: s.v * width, y: s.u * length)
    }
  }

  /// The half a point is in (on the centre line: Team A's).
  public static func half(_ p: World) -> Side { p.y <= centre ? .A : .B }

  /// A point in the notation's frame, for the half it is in; nil off the pitch.
  public static func notation(_ p: World) -> (half: Side, point: RecordPoint)? {
    guard (0...width).contains(p.x), (0...length).contains(p.y) else { return nil }
    let h = half(p)
    return (h, RecordPoint(across: round2(p.x), depth: round2(abs(p.y - centre))))
  }

  /// A point of the notation's frame in a half, back on the pitch.
  public static func world(_ p: RecordPoint, half: Side) -> World {
    World(x: p.across, y: half == .A ? centre - p.depth : centre + p.depth)
  }

  /// A cell's middle (the engine keeps cells), for drawing.
  public static func cellMiddle(_ p: RecordPoint, half: Side) -> World {
    world(RecordPoint(across: p.across + 0.5, depth: min(p.depth + 0.5, 3.5)), half: half)
  }

  /// A stance: where a thrower on `side` stands, in their own half or behind its
  /// baseline (depth up to 9.99 from the centre line). Nil when the point is in the other
  /// half.
  public static func stance(_ p: World, side: Side) -> RecordPoint? {
    let depth = side == .A ? centre - p.y : p.y - centre
    guard depth >= 0, depth <= 9.99 else { return nil }
    return RecordPoint(across: round2(min(max(p.x, 0), width)), depth: round2(depth))
  }

  /// A stance snapped to the baseline or the advantage line when it is within `reach`
  /// metres of one (the design: 0.35 m).
  public static func snap(_ p: RecordPoint, advantageDepth: Double?, reach: Double = 0.35) -> RecordPoint {
    var out = p
    if abs(p.depth - centre) <= reach {
      out.depth = centre
    } else if let a = advantageDepth, abs(p.depth - a) <= reach {
      out.depth = round2(a)
    }
    return out
  }

  static func round2(_ v: Double) -> Double { (v * 100).rounded(.toNearestOrEven) / 100 }
}
