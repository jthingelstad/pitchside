import Notation
import PitchsideDesign
import PitchsideModel
import SwiftUI

extension Side {
  var marker: TeamMarker.Side { self == .A ? .A : .B }
}

extension TeamMarker {
  init(_ side: Notation.Side, size: CGFloat = 22) { self.init(side.marker, size: size) }
}

/// The shared page header remains visible as the content scrolls.
struct Screen<Content: View>: View {
  let title: String
  var back: String?
  var onBack: (() -> Void)?
  @ViewBuilder var content: Content

  var body: some View {
    VStack(spacing: 0) {
      ScreenHeader(title, back: back, action: onBack)
      ScrollView {
        VStack(alignment: .leading, spacing: 16) { content }
          .padding(.horizontal, 16)
          .padding(.top, 16)
          .padding(.bottom, 24)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .scrollDismissesKeyboard(.interactively)
    }
    .background(Color.psGround)
    .toolbar(.hidden, for: .navigationBar)
  }
}

/// A screen pushed in a stack: its back word pops it.
struct PushedScreen<Content: View>: View {
  let title: String
  let back: String
  @ViewBuilder var content: Content
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    Screen(title: title, back: back, onBack: { dismiss() }) { content }
  }
}

/// A team's name with its marker: the marker is never the only cue.
struct TeamLabel: View {
  let side: Side
  let name: String
  var display = false
  var size: CGFloat = 22

  var body: some View {
    HStack(spacing: 8) {
      TeamMarker(side, size: size)
      Text(name)
        .font(display ? PSFont.display(24, relativeTo: .title2) : PSFont.body(16, .bold))
        .foregroundStyle(Color.psText)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(name), side \(side.rawValue)")
  }
}

/// "Sat 21 Nov".
func shortDay(_ date: Date) -> String {
  date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
}

/// What a finished game's row says: "Crooked Crowns beat Mossy Stakes".
func resultTitle(_ game: Game, _ read: GameRead?) -> String {
  guard let a = read?.analysis else {
    return "\(game.team(.A).shownName(.A)) v \(game.team(.B).shownName(.B))"
  }
  if let w = a.winner { return "\(a.name(w)) beat \(a.name(w.other))" }
  return "\(a.name(.A)) v \(a.name(.B))"
}

/// "Sat 21 Nov · 9 turns · turns, who threw" or "... · from Throwing Wood".
func resultDetail(_ game: Game, _ read: GameRead?) -> String {
  var parts = [shortDay(game.created)]
  if let n = read?.analysis.rows.count { parts.append(n == 1 ? "1 turn" : "\(n) turns") }
  if game.isImported {
    if let event = read?.analysis.headers["Event"], event == "Throwing Wood" {
      parts.append("from Throwing Wood")
    } else if let scorer = read?.analysis.headers["Scored by"], scorer.hasPrefix("Kubb: Pitchside") {
      parts.append(game.capture.summary)
    } else {
      parts.append("opened from a file")
    }
  } else {
    parts.append(game.capture.summary)
  }
  return parts.joined(separator: " · ")
}
