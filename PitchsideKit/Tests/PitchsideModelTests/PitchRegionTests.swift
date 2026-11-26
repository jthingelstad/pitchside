import Foundation
import Testing

@testable import PitchsideModel

/// The live scorer frames the half the action lands in.
struct PitchRegionTests {
  /// The pitch pane of the landscape scorer on an iPhone 17, in points.
  let pane = CGSize(width: 345, height: 334)

  @Test(arguments: PitchFrame.View.allCases)
  func aFramedHalfIsAtLeastHalfAgainAsLargeAsTheWholePitch(view: PitchFrame.View) {
    let whole = PitchFrame.Region.whole(in: view).pointsPerMetre(in: pane, view: view)
    for side in Side.allCases {
      let half = PitchFrame.Region.half(side).pointsPerMetre(in: pane, view: view)
      #expect(half >= whole * 1.5, "\(view) \(side): \(half) against \(whole)")
    }
  }

  @Test(arguments: PitchFrame.View.allCases)
  func aFramedHalfKeepsItsLinesTheKingAndTheirTouchAreasInThePane(view: PitchFrame.View) {
    for side in Side.allCases {
      let region = PitchFrame.Region.half(side)
      let fit = region.fit(in: pane, view: view)
      let unit = region.pointsPerMetre(in: pane, view: view)
      func onScreen(_ p: PitchFrame.World) -> CGPoint {
        let s = PitchFrame.screen(p, in: view)
        return CGPoint(x: fit.minX + s.u * fit.width, y: fit.minY + s.v * fit.height)
      }
      // Every base kubb and the king keep a 48-point touch area inside the pane; the
      // corner stakes keep the whole chalk line in it.
      let inner = CGRect(origin: .zero, size: pane).insetBy(dx: 24, dy: 24)
      let pitch = CGRect(origin: .zero, size: pane).insetBy(dx: 2, dy: 2)
      let baseline = side == .A ? 0.12 : 7.88
      for x in [0.5, 1.5, 2.5, 3.5, 4.5] {
        #expect(inner.contains(onScreen(.init(x: x, y: baseline))))
      }
      #expect(inner.contains(onScreen(.init(x: 2.5, y: 4))))
      for x in [0.0, 5.0] {
        for y in [side == .A ? 0.0 : 8.0, 4.0] { #expect(pitch.contains(onScreen(.init(x: x, y: y)))) }
      }
      // A 48-point button on the king stays inside the pane with room to spare.
      #expect(unit * PitchFrame.Region.centreMargin > 48)
    }
  }

  @Test func theWholePitchKeepsItsEarlierFit() {
    let fit = PitchFrame.Region.whole(in: .behindA).fit(in: pane, view: .behindA)
    let width = min(pane.width - 68, (pane.height - 68) * 5 / 8)
    #expect(abs(fit.width - width) < 1e-9)
    #expect(abs(fit.midX - pane.width / 2) < 1e-9 && abs(fit.midY - pane.height / 2) < 1e-9)
  }

  @Test(arguments: PitchFrame.View.allCases)
  func theTwoHalvesAreOneSlideApart(view: PitchFrame.View) {
    let a = PitchFrame.Region.half(.A).fit(in: pane, view: view)
    let b = PitchFrame.Region.half(.B).fit(in: pane, view: view)
    #expect(abs(a.width - b.width) < 1e-9 && abs(a.height - b.height) < 1e-9)
    #expect(a.origin != b.origin)
  }

  @Test func aStanceBehindTheBaselineWidensTheWholePitch() {
    let whole = PitchFrame.Region.whole(in: .behindA)
    let wider = whole.including(.init(x: 2.5, y: -1.5))
    #expect(wider.minY == -1.5 && wider.maxY == 8)
    #expect(whole.including(nil) == whole)
  }
}
