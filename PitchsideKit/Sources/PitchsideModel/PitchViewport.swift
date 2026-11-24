import Foundation

extension PitchFrame {
  /// The fitted pitch is a unit rectangle. A viewport only moves that drawing on
  /// screen. Stored observations always go through the original notation frame.
  public struct Viewport: Equatable, Sendable {
    public private(set) var scale = 1.0
    private var left = 0.0
    private var top = 0.0

    public init() {}

    public func rect(fitted: CGRect) -> CGRect {
      CGRect(
        x: fitted.minX + left * fitted.width, y: fitted.minY + top * fitted.height,
        width: scale * fitted.width, height: scale * fitted.height)
    }

    /// Keep the point under the fingers as their midpoint moves. Constrain each
    /// edge to the fitted pitch's margin so the scorer cannot pan the pitch away.
    public mutating func move(from start: Screen, to end: Screen, magnification: Double) {
      let newScale = min(4, max(1, scale * magnification))
      let factor = newScale / scale
      left = min(0, max(1 - newScale, end.u - (start.u - left) * factor))
      top = min(0, max(1 - newScale, end.v - (start.v - top) * factor))
      scale = newScale
    }
  }
}
