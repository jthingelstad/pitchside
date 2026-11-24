import SwiftUI
import UIKit

/// UIKit arbitrates taps against navigation before a tap can record an inkast.
struct PitchGestures: UIViewRepresentable {
  var tap: (CGPoint) -> Void
  var move: (CGPoint, CGPoint, CGFloat) -> Void

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  func makeUIView(context: Context) -> UIView {
    let view = UIView()
    view.isMultipleTouchEnabled = true
    view.accessibilityElementsHidden = true
    let coordinator = context.coordinator
    let tap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.tapped))
    let pan = UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.panned))
    let pinch = UIPinchGestureRecognizer(target: coordinator, action: #selector(Coordinator.pinched))
    pan.maximumNumberOfTouches = 1
    pan.delegate = coordinator
    pinch.delegate = coordinator
    tap.require(toFail: pan)
    tap.require(toFail: pinch)
    for gesture in [tap, pan, pinch] { view.addGestureRecognizer(gesture) }
    return view
  }

  func updateUIView(_ view: UIView, context: Context) { context.coordinator.input = self }

  @MainActor final class Coordinator: NSObject, UIGestureRecognizerDelegate {
    var input: PitchGestures
    private var pinchMidpoint: CGPoint?

    init(_ input: PitchGestures) { self.input = input }

    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
      (gestureRecognizer is UIPinchGestureRecognizer && other is UIPanGestureRecognizer)
        || (gestureRecognizer is UIPanGestureRecognizer && other is UIPinchGestureRecognizer)
    }

    @objc func tapped(_ tap: UITapGestureRecognizer) {
      input.tap(tap.location(in: tap.view))
    }

    @objc func panned(_ pan: UIPanGestureRecognizer) {
      let delta = pan.translation(in: pan.view)
      pan.setTranslation(.zero, in: pan.view)
      guard pinchMidpoint == nil, pan.numberOfTouches == 1,
        pan.state == .began || pan.state == .changed else { return }
      let end = pan.location(in: pan.view)
      input.move(CGPoint(x: end.x - delta.x, y: end.y - delta.y), end, 1)
    }

    @objc func pinched(_ pinch: UIPinchGestureRecognizer) {
      guard pinch.state == .began || pinch.state == .changed, pinch.numberOfTouches == 2 else {
        pinchMidpoint = nil
        return
      }
      let midpoint = pinch.location(in: pinch.view)
      input.move(pinchMidpoint ?? midpoint, midpoint, pinch.scale)
      pinchMidpoint = midpoint
      pinch.scale = 1
    }
  }
}
