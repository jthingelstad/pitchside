import Foundation

/// Positions and tokens retained by the notation reader for a turn.
public struct TurnRecording: Decodable, Sendable {
  public struct Place: Decodable, Equatable, Hashable, Sendable {
    public let across: Double
    public let depth: Double
    public let cell: Bool
    public let mark: String?
    /// Set by replay when a later fall supplies a standing location.
    public var inferredFromFall = false
    /// Added by Pitchside when a local journal supplies an approximate tap.
    public var tapped = false

    private enum CodingKeys: String, CodingKey { case across, depth, cell, mark }

    public init(across: Double, depth: Double, cell: Bool = false, mark: String? = nil) {
      self.across = across
      self.depth = depth
      self.cell = cell
      self.mark = mark
    }

    public var label: String {
      if cell { return "cell \(Int(across)),\(Int(depth))" }
      return String(format: "%.2f,%.2f", locale: Locale(identifier: "en_US_POSIX"), across, depth)
    }
  }

  public struct Lay: Decodable, Sendable, Equatable {
    public let first: Place
    public let last: Place
  }

  public let inkasts: [String]
  public let pitch: [Side: [Place]]
  public let lays: [Lay]
  public let stances: [Place?]
  public let falls: [[Place]?]
  public let advantageMeters: Double?
}
