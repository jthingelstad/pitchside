import Notation
import PitchsideDesign
import PitchsideModel
import SwiftUI

/// The live scorer's screen, as a placeholder: the design's frame (team band, turn
/// header, baton bar, the pitch, the prompt, the bottom bar) drawn from a static pitch,
/// talking only to `LiveScorer`. Record mode brings the taps. No tab bar.
struct ScorerView: View {
  @Environment(AppModel.self) private var model
  let session: ScoringSession
  let close: () -> Void
  @State private var capture: Capture
  @State private var editingCapture = false
  @State private var undone = 0

  init(session: ScoringSession, close: @escaping () -> Void) {
    self.session = session
    self.close = close
    _capture = State(initialValue: session.scorer.game.capture)
  }

  var scorer: LiveScorer { session.scorer }
  var game: Game { scorer.game }
  var thrower: Side { game.options.first }

  var body: some View {
    VStack(spacing: 0) {
      VStack(spacing: 8) {
        placeholderBanner
        header
        batonBar
      }
      .padding(.horizontal, 12)
      .padding(.top, 6)
      .padding(.bottom, 10)
      PitchView(thrower: thrower, teams: [.A: game.team(.A).shownName(.A), .B: game.team(.B).shownName(.B)])
        .frame(maxHeight: .infinity)
      prompt
      bottomBar
    }
    .background(TeamMarker.fill(thrower.marker).ignoresSafeArea())
    .sheet(isPresented: $editingCapture) { captureSheet }
  }

  var placeholderBanner: some View {
    Text("Placeholder scorer · record mode is not built yet")
      .font(PSFont.body(14, .bold, relativeTo: .footnote))
      .foregroundStyle(Color.psOnSolid)
      .padding(.horizontal, 10)
      .padding(.vertical, 4)
      .frame(maxWidth: .infinity)
      .background(Color.psSolid, in: RoundedRectangle(cornerRadius: 6))
      .accessibilityAddTraits(.isStaticText)
  }

  var header: some View {
    HStack(spacing: 12) {
      TeamMarker(thrower, size: 46)
      VStack(alignment: .leading, spacing: 2) {
        Text(scorer.prompt.kick).font(PSFont.body(15, .bold, relativeTo: .subheadline))
        Text(game.team(thrower).shownName(thrower)).font(PSFont.display(26, relativeTo: .title2))
      }
      .foregroundStyle(Color.psText)
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement(children: .combine)
      IconPlate(symbol: "arrow.triangle.2.circlepath", enabled: false)
        .accessibilityLabel("Change the view, not built yet")
    }
    .padding(12)
    .psCard()
  }

  var batons: Int { game.options.opening == .six ? 6 : 2 }

  var batonBar: some View {
    HStack(spacing: 6) {
      Text("1.").font(PSFont.mono(16).weight(.bold))
      Spacer()
      ForEach(0..<batons, id: \.self) { _ in
        Capsule().fill(Color.psKubb).overlay(Capsule().strokeBorder(Color.psKubbInk, lineWidth: 2))
          .frame(width: 11, height: 24)
      }
      Text("\(batons) left").font(PSFont.body(15, .bold)).padding(.leading, 4)
    }
    .foregroundStyle(Color.psText)
    .padding(.horizontal, 12)
    .frame(minHeight: 40)
    .background(Color.psPlate, in: RoundedRectangle(cornerRadius: 6))
    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.psLine, lineWidth: 2))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Turn 1, \(batons) batons left")
  }

  var prompt: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text("Turn 1 · \(game.team(thrower).shownName(thrower))").psKick()
        Text(scorer.prompt.text).font(PSFont.body(16, .medium)).foregroundStyle(Color.psText)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement(children: .combine)
      IconPlate(symbol: "camera", enabled: false)
        .accessibilityLabel("Photo, not built yet")
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(Color.psGround)
    .overlay(alignment: .top) { Rectangle().fill(Color.psLine).frame(height: 3) }
  }

  var bottomBar: some View {
    HStack(spacing: 8) {
      Button {
        try? scorer.undo()
        undone += 1
      } label: {
        Label("Undo", systemImage: "arrow.uturn.backward").labelStyle(.titleAndIcon)
      }
      .buttonStyle(PSButtonStyle(minHeight: 64))
      .frame(width: 104)
      .accessibilityHint("Logs an undo; there is nothing to undo yet")
      Button("Out") {}
        .buttonStyle(PSButtonStyle(minHeight: 64))
        .disabled(true)
        .accessibilityHint("Comes with record mode")
      Button("Later") {}
        .buttonStyle(PSButtonStyle(minHeight: 64))
        .frame(width: 92)
        .disabled(true)
        .accessibilityHint("Comes with record mode")
      Menu {
        Button("What to record", systemImage: "list.bullet") { editingCapture = true }
          .disabled(!scorer.canChangeCapture)
        Button("Back to Home (the game stays on the pitch)", systemImage: "house", action: close)
      } label: {
        Image(systemName: "ellipsis").font(.system(size: 22, weight: .heavy))
          .frame(width: 56, height: 64)
          .foregroundStyle(Color.psText)
          .background(Color.psPlate, in: RoundedRectangle(cornerRadius: 6))
          .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.psLine, lineWidth: 3))
          .background(RoundedRectangle(cornerRadius: 6).fill(Color.psShade).offset(x: 3, y: 3))
      }
      .accessibilityLabel("More")
    }
    .padding(.horizontal, 12)
    .padding(.top, 10)
    .padding(.bottom, 8)
    .background(TeamMarker.fill(thrower.marker))
  }

  var captureSheet: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 10) {
          Text("What to record").psKick()
          ForEach(Capture.Row.allCases, id: \.self) { row in
            CaptureRowButton(row: row, on: capture.isOn(row)) {
              capture.set(row, !capture.isOn(row))
              try? scorer.setCapture(capture)
            }
          }
          Text("Changes start with the next turn. The file says what was recorded.").psHelp()
          Button("Done") { editingCapture = false }.buttonStyle(.psSolid)
        }
        .padding(16)
      }
      .background(Color.psGround)
    }
  }
}

/// A 52-point square icon button drawn like the design's small plates. Disabled ones
/// (the view switch and the photo, which come later) say so to VoiceOver.
struct IconPlate: View {
  let symbol: String
  var enabled = true
  var action: () -> Void = {}

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol).font(.system(size: 20, weight: .bold))
        .foregroundStyle(Color.psText)
        .frame(width: 52, height: 52)
        .background(Color.psPlate, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.psLine, lineWidth: 3))
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.psShade).offset(x: 3, y: 3))
        .opacity(enabled ? 1 : 0.55)
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
  }
}

/// The pitch as the design draws it from behind the thrower's baseline: rough around a
/// 5 by 8 m grass rectangle, a chalk outline, the centre line, six stakes, the king, and
/// five base kubbs on each baseline. The far half (where kubbs are thrown in) is lighter.
/// Static until record mode says what stands.
struct PitchView: View {
  let thrower: Side
  let teams: [Side: String]

  var body: some View {
    GeometryReader { g in
      let chipRoom: CGFloat = 40
      let h = max(100, g.size.height - chipRoom * 2)
      let w = min(g.size.width - 64, h * 5 / 8)
      let height = w * 8 / 5
      let x0 = (g.size.width - w) / 2
      let y0 = (g.size.height - height) / 2
      let unit = w / 5
      let kubb = max(16, unit * 0.36)
      ZStack(alignment: .topLeading) {
        Color.psRough
        // The grass, the far half lighter (the half kubbs are thrown into).
        Rectangle().fill(Color.psGrass).frame(width: w, height: height).offset(x: x0, y: y0)
        Rectangle().fill(Color.white.opacity(0.18)).frame(width: w, height: height / 2).offset(x: x0, y: y0)
        Rectangle().strokeBorder(Color.psChalk, lineWidth: 3).frame(width: w, height: height).offset(x: x0, y: y0)
        Rectangle().fill(Color.psChalk).frame(width: w, height: 2).offset(x: x0, y: y0 + height / 2 - 1)
        // Stakes: the four corners and both ends of the centre line.
        ForEach(0..<6, id: \.self) { i in
          let sx = x0 + (i % 2 == 0 ? 0 : w)
          let sy = y0 + CGFloat(i / 2) * height / 2
          RoundedRectangle(cornerRadius: 2).fill(Color.psKubb)
            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Color.psKubbInk, lineWidth: 1.5))
            .frame(width: 10, height: 10)
            .offset(x: sx - 5, y: sy - 5)
        }
        // Base kubbs: five on each baseline, 1 m apart.
        ForEach(0..<10, id: \.self) { i in
          let bx = x0 + unit * (CGFloat(i % 5) + 0.5)
          let by = i < 5 ? y0 + kubb / 2 : y0 + height - kubb / 2
          RoundedRectangle(cornerRadius: 3).fill(Color.psKubbRest)
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.psKubbInk, lineWidth: 2))
            .frame(width: kubb, height: kubb)
            .offset(x: bx - kubb / 2, y: by - kubb / 2)
        }
        // The king.
        RoundedRectangle(cornerRadius: 3).fill(Color.psKubb)
          .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.psKubbInk, lineWidth: 3))
          .overlay(Text("K").font(.custom("Inter", fixedSize: 16).weight(.black)).foregroundStyle(Color.psKubbInk))
          .frame(width: kubb * 1.5, height: kubb * 1.5)
          .offset(x: x0 + w / 2 - kubb * 0.75, y: y0 + height / 2 - kubb * 0.75)
        // Each team's chip by its baseline: the far team at the top.
        chip(thrower.other, standing: 5).position(x: g.size.width / 2, y: y0 - 18)
        chip(thrower, standing: 5).position(x: g.size.width / 2, y: y0 + height + 18)
      }
    }
    .clipped()
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      "The pitch from behind \(teams[thrower] ?? "")'s baseline: five base kubbs on each baseline and the king in the middle.")
  }

  func chip(_ side: Side, standing: Int) -> some View {
    HStack(spacing: 6) {
      TeamMarker(side, size: 18)
      Text("\(teams[side] ?? "") · \(standing) standing").font(PSFont.body(14, .bold))
    }
    .foregroundStyle(Color.psText)
    .padding(.horizontal, 8)
    .padding(.vertical, 3)
    .background(Color.psPlate, in: RoundedRectangle(cornerRadius: 6))
    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.psLine, lineWidth: 2))
    .fixedSize()
  }
}
