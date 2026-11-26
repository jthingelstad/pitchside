import Notation
import PitchsideDesign
import PitchsideModel
import SwiftUI

/// The drawn pitch's rectangle in the canvas, and the map both ways.
struct PitchGeometry {
  let size: CGSize
  let fitted: CGRect
  let rect: CGRect
  let view: PitchFrame.View
  let unit: CGFloat

  init(size: CGSize, view: PitchFrame.View, viewport: PitchFrame.Viewport, including spot: PitchFrame.World? = nil) {
    self.init(
      size: size, view: view, viewport: viewport,
      region: PitchFrame.Region.whole(in: view).including(spot))
  }

  /// Fit `region` (the whole pitch, or the half the live scorer frames) to the pane.
  init(size: CGSize, view: PitchFrame.View, viewport: PitchFrame.Viewport, region: PitchFrame.Region) {
    self.size = size
    self.view = view
    fitted = region.fit(in: size, view: view)
    rect = viewport.rect(fitted: fitted)
    // Markers keep their readable size as zoom separates the kubb centres.
    unit = view.isSideways ? fitted.width / 8 : fitted.width / 5
  }

  func fittedPoint(_ p: CGPoint) -> PitchFrame.Screen {
    .init(u: (p.x - fitted.minX) / fitted.width, v: (p.y - fitted.minY) / fitted.height)
  }

  func point(_ p: PitchFrame.World) -> CGPoint {
    let s = PitchFrame.screen(p, in: view)
    return CGPoint(x: rect.minX + s.u * rect.width, y: rect.minY + s.v * rect.height)
  }

  func world(_ p: CGPoint) -> PitchFrame.World {
    PitchFrame.world(
      PitchFrame.Screen(u: (p.x - rect.minX) / rect.width, v: (p.y - rect.minY) / rect.height),
      in: view)
  }

  /// A half of the pitch as a rectangle on screen.
  func half(_ side: Side) -> CGRect {
    let a = point(PitchFrame.World(x: 0, y: side == .A ? 0 : 4))
    let b = point(PitchFrame.World(x: 5, y: side == .A ? 4 : 8))
    return CGRect(
      x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
  }
}

struct PitchGround: View {
  let geo: PitchGeometry
  let target: Side?
  var placing = false

  var body: some View {
    let r = geo.rect
    let c1 = geo.point(.init(x: 0, y: 4))
    let c2 = geo.point(.init(x: 5, y: 4))
    return ZStack(alignment: .topLeading) {
      Rectangle().fill(Color.psGrass).frame(width: r.width, height: r.height).offset(
        x: r.minX, y: r.minY)
      if let target {
        let h = geo.half(target)
        Rectangle().fill(
          Color.white.opacity(
            placing ? 0.22 : 0.12)
        )
        .frame(width: h.width, height: h.height).offset(x: h.minX, y: h.minY)
        if placing {
          Rectangle().strokeBorder(Color.psChalk, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
            .frame(width: h.width, height: h.height).offset(x: h.minX, y: h.minY)
        }
      }
      Rectangle().strokeBorder(Color.psChalk, lineWidth: 3).frame(width: r.width, height: r.height)
        .offset(x: r.minX, y: r.minY)
      Path { p in
        p.move(to: c1)
        p.addLine(to: c2)
      }
      .stroke(Color.psChalk, lineWidth: 2)
      ForEach(0..<6, id: \.self) { i in
        let s = geo.point(.init(x: i % 2 == 0 ? 0 : 5, y: Double(i / 2) * 4))
        RoundedRectangle(cornerRadius: 2).fill(Color.psKubb)
          .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Color.psKubbInk, lineWidth: 1.5))
          .frame(width: 10, height: 10)
          .position(s)
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}
