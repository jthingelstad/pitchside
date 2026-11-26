import Foundation

extension PitchFrame {
  /// The part of the pitch a drawing fits to its pane, in world metres, with a padding in
  /// points around it. The whole pitch keeps its original padding. A half is the 5 by 4 m
  /// half with room outside its lines for the base kubbs, the team's label and "out"
  /// taps, and a metre past the centre line so the king and the kubbs beside the line
  /// keep their whole touch area.
  public struct Region: Equatable, Sendable {
    public var minX: Double
    public var maxX: Double
    public var minY: Double
    public var maxY: Double
    public var pad: Double

    public init(minX: Double, maxX: Double, minY: Double, maxY: Double, pad: Double) {
      self.minX = minX
      self.maxX = maxX
      self.minY = minY
      self.maxY = maxY
      self.pad = pad
    }

    /// Metres of rough kept outside each sideline of a framed half.
    public static let sideMargin = 0.33
    /// Metres kept behind the framed half's baseline.
    public static let baselineMargin = 0.55
    /// Metres of the other half kept beyond the centre line.
    public static let centreMargin = 1.0
    /// Points of padding around a framed half.
    public static let halfPad = 3.0

    public static func whole(in view: View) -> Region {
      Region(minX: 0, maxX: width, minY: 0, maxY: length, pad: view.isSideways ? 20 : 34)
    }

    public static func half(_ side: Side) -> Region {
      let minY = side == .A ? -baselineMargin : centre - centreMargin
      let maxY = side == .A ? centre + centreMargin : length + baselineMargin
      return Region(
        minX: -sideMargin, maxX: width + sideMargin, minY: minY, maxY: maxY, pad: halfPad)
    }

    /// The region grown to include a point, such as a stance behind a baseline.
    public func including(_ p: World?) -> Region {
      guard let p else { return self }
      return Region(
        minX: min(minX, p.x), maxX: max(maxX, p.x), minY: min(minY, p.y), maxY: max(maxY, p.y),
        pad: pad)
    }

    /// Where the whole 5 by 8 m pitch lies on screen when this region fits `size`, centred.
    /// Parts of the pitch outside the region fall outside the pane.
    public func fit(in size: CGSize, view: View) -> CGRect {
      let room = CGSize(
        width: max(100, size.width - pad * 2), height: max(100, size.height - pad * 2))
      // The pitch drawn wide or tall: its width over its height on screen.
      let aspect = view.isSideways ? length / width : width / length
      let corners = [
        World(x: minX, y: minY), World(x: maxX, y: minY), World(x: minX, y: maxY),
        World(x: maxX, y: maxY),
      ].map { PitchFrame.screen($0, in: view) }
      let u0 = corners.map(\.u).min()!, u1 = corners.map(\.u).max()!
      let v0 = corners.map(\.v).min()!, v1 = corners.map(\.v).max()!
      let w = min(room.width / (u1 - u0), room.height * aspect / (v1 - v0))
      let h = w / aspect
      return CGRect(
        x: (size.width - w * (u1 - u0)) / 2 - u0 * w,
        y: (size.height - h * (v1 - v0)) / 2 - v0 * h, width: w, height: h)
    }

    /// Points per metre when this region fits `size`.
    public func pointsPerMetre(in size: CGSize, view: View) -> Double {
      fit(in: size, view: view).width / (view.isSideways ? length : width)
    }
  }
}
