import PitchsideDesign
import PitchsideModel
import SwiftUI

/// The band, pitch and thumb controls stay in place through every turn.
struct ScorerView: View {
  @Environment(AppModel.self) private var model
  @State private var replay: GameReplay?
  @State private var screen: ScorerScreen
  @State private var timeline = false
  @State private var viewport = PitchFrame.Viewport()
  let close: () -> Void

  init(session: ScoringSession, close: @escaping () -> Void) {
    _screen = State(initialValue: ScorerScreen(scorer: session.scorer))
    _timeline = State(initialValue: session.showTimeline)
    self.close = close
  }

  var body: some View {
    Group {
      if let replay {
        NavigationStack {
          ReplayView(replay: replay, back: "Scoring", startAtLast: true) { self.replay = nil }
        }
      } else if timeline {
        TimelineView(screen: screen) {
          if screen.over { close() } else { timeline = false }
        }
      } else {
        VStack(spacing: 0) {
          VStack(spacing: 0) {
            header
            batonBar
          }
          .padding(.horizontal, 12).padding(.bottom, 4)
          .background(Color.psPlate.ignoresSafeArea(edges: .top))
          PitchCanvas(screen: screen, viewport: $viewport)
            .frame(maxHeight: .infinity)
            .overlay(alignment: .bottom) {
              if screen.panel != .none && screen.panel != .pick {
                GeometryReader { geo in
                  VStack {
                    Spacer(minLength: 0)
                    ScrollView { panel.padding(12) }
                      .scrollBounceBehavior(.basedOnSize)
                      .fixedSize(horizontal: false, vertical: true)
                      .frame(maxHeight: geo.size.height)
                      .background(Color.psGround)
                      .overlay(alignment: .top) { Divider().overlay(Color.psLine) }
                  }
                }
              }
            }
          prompt
          bottomBar
        }
        .foregroundStyle(Color.psText)
        .background(Color.psGround)
      }
    }
    .onChange(of: screen.view) { viewport = .init() }
    .onChange(of: screen.state.turn) { viewport = .init() }
    .onChange(of: screen.over) { _, over in if over { close() } }
  }

  var header: some View {
    HStack(spacing: 6) {
      icon("chevron.backward", "Back to Games", action: close)
      VStack(alignment: .leading, spacing: 1) {
        HStack(spacing: 5) {
          TeamMarker(screen.attacker, size: 18)
          Text(screen.header).font(PSFont.body(14, .semibold)).foregroundStyle(Color.psMuted)
        }
        if screen.playersOn, let player = screen.thrower, !screen.over {
          HStack(spacing: 8) {
            Button {
              screen.panel = screen.panel == .pick ? .none : .pick
            } label: {
              HStack(spacing: 4) {
                Text(player.name).font(PSFont.display(24))
                Image(systemName: "chevron.down").font(.system(size: 14, weight: .bold))
              }.padding(.horizontal, 8).padding(.vertical, 2).psBox()
                .frame(minWidth: 48, minHeight: 48).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel("Change who throws")
            .accessibilityValue(player.name)
            Text(screen.teamName(screen.attacker)).font(PSFont.body(14, .semibold)).lineLimit(2)
          }
        } else {
          Text(screen.teamName(screen.attacker)).font(PSFont.display(26)).lineLimit(2)
        }
      }.frame(maxWidth: .infinity, alignment: .leading)
      HStack(spacing: 4) {
        icon(
          viewport.scale == 1 ? "plus.magnifyingglass" : "arrow.down.right.and.arrow.up.left",
          viewport.scale == 1 ? "Zoom in on pitch" : "Fit whole pitch"
        ) {
          if viewport.scale == 1 {
            let focus = PitchFrame.screen(.init(x: 2.5, y: screen.defender == .A ? 2 : 6), in: screen.view)
            viewport.move(from: focus, to: .init(u: 0.5, v: 0.5), magnification: 2)
          } else {
            viewport = .init()
          }
        }
        .accessibilityValue("\(Int((viewport.scale * 100).rounded())) percent")
        icon("rectangle.2.swap", "Change view", action: screen.nextView)
          .accessibilityValue(screen.view.title)
      }
    }
    .padding(.vertical, 4).frame(minHeight: 60)
  }

  var batonBar: some View {
    HStack(spacing: 5) {
      ScrollView(.horizontal) {
        Text("\(screen.state.turn). \(screen.tokens)").font(PSFont.mono(15).weight(.bold))
      }.scrollIndicators(.hidden).defaultScrollAnchor(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
      ForEach(0..<screen.batonsLeft, id: \.self) { _ in
        Capsule().fill(Color.psKubb).overlay(Capsule().strokeBorder(Color.psKubbInk, lineWidth: 2))
          .frame(width: 10, height: 22)
      }
      Text("\(screen.batonsLeft) left").font(PSFont.body(14, .bold))
    }
    .frame(minHeight: 32)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      "Turn \(screen.state.turn), \(screen.tokens), \(screen.batonsLeft) batons left")
  }

  @ViewBuilder var prompt: some View {
    VStack(alignment: .leading, spacing: 4) {
      if screen.panel == .pick {
        Text(
          screen.isInkast
            ? "Who throws the kubbs in?" : "Who throws baton \(screen.state.next.n ?? 1)?"
        ).psKick()
        ScrollView(.horizontal) {
          HStack {
            ForEach(screen.players, id: \.id) { p in
              Button(p.name) { screen.choose(p) }
                .buttonStyle(PSButtonStyle(solid: screen.thrower?.id == p.id, minHeight: 48))
            }
          }.padding(.trailing, 4).padding(.bottom, 4)
        }.scrollIndicators(.hidden)
      } else {
        HStack {
          VStack(alignment: .leading, spacing: 3) {
            Text(screen.kick).psKick()
            Text(screen.problem ?? screen.text).font(PSFont.body(16, .semibold))
          }.frame(maxWidth: .infinity, alignment: .leading)
          if !screen.owed.isEmpty && !screen.placing {
            Button("Place \(screen.owed.count)") {
              screen.placing = true
              screen.panel = .none
            }
            .buttonStyle(.quiet)
          }
          if !screen.lastWarnings.isEmpty {
            Button {
              screen.panel = screen.panel == .warnings ? .none : .warnings
            } label: {
              Chip("Rule note").frame(minHeight: 48)
            }.buttonStyle(.plain).accessibilityLabel("Read engine warning")
          }
        }
        if screen.isBaton && (screen.unplacedFields > 0 || screen.unplacedBases > 0)
          && !screen.punishPending && !screen.placing
        {
          HStack {
            if screen.unplacedFields > 0 {
              countButton("field", count: $screen.countField, total: screen.unplacedFields)
            }
            if screen.unplacedBases > 0 {
              countButton("base", count: $screen.countBase, total: screen.unplacedBases)
            }
          }
        }
      }
    }
    .padding(.horizontal, 12).padding(.vertical, 8).frame(maxWidth: .infinity, minHeight: 72)
    .background(Color.psGround)
    .overlay(alignment: .top) { Divider() }
  }

  func countButton(_ kind: String, count: Binding<Int>, total: Int) -> some View {
    Button("\(count.wrappedValue) \(kind) +") {
      count.wrappedValue = (count.wrappedValue + 1) % (total + 1)
    }
    .buttonStyle(PSButtonStyle(minHeight: 48)).accessibilityLabel("Count \(kind) kubbs")
    .accessibilityValue("\(count.wrappedValue)").accessibilityHint(
      "Adds one. After \(total), returns to zero.")
  }

  var bottomBar: some View {
    HStack(spacing: 8) {
      Button("Undo") {
        screen.panel = .none
        screen.undo()
      }.buttonStyle(.quiet).fixedSize(horizontal: true, vertical: false)
      Button(screen.primaryTitle) {
        screen.panel = .none
        if screen.over { close() } else { screen.primary() }
      }.buttonStyle(
        PSButtonStyle(
          solid: !(screen.positionsOn && screen.isInkast) && !screen.placing, minHeight: 52))
      if let second = screen.secondTitle {
        Button(second) {
          screen.panel = .none
          screen.second()
        }
        .buttonStyle(PSButtonStyle(minHeight: 52)).fixedSize(horizontal: true, vertical: false)
      }
      icon("ellipsis", "More", height: 52) {
        screen.panel = screen.panel == .none ? .rare : .none
      }
    }.padding(.horizontal, 12).padding(.top, 3).padding(.bottom, 8)
  }

  private func icon(
    _ symbol: String, _ label: String, height: CGFloat = 48, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: symbol).font(.system(size: 20, weight: .medium))
        .frame(width: 48, height: height).contentShape(Rectangle())
    }.buttonStyle(.plain).accessibilityLabel(label)
  }

  @ViewBuilder var panel: some View {
    @Bindable var s = screen
    VStack(alignment: .leading, spacing: 8) {
      switch screen.panel {
      case .coincident(let targets):
        Text("Which kubb fell?").psKick()
        ForEach(targets, id: \.self) { target in
          let title = switch target {
          case .field(let i): "Field kubb \(i + 1)"
          case .base(let i): "Base kubb \(i + 1)"
          case .king: "King"
          }
          Button(screen.marked.contains(target) ? "\(title) · marked" : title) {
            screen.panel = .none
            screen.toggle(target)
          }
        }
        Button("Cancel") { screen.panel = .none }
      case .rare:
        Text("More").psKick()
        LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 8) {
          if screen.isInkast && screen.state.allows("toss") {
            Button(
              screen.rescueAttempt ? "Cancel rescue mark" : "Failed rescue",
              action: screen.failedRescue)
            if !screen.positionsOn && screen.state.next.rethrow != true {
              Button("One kubb in", action: screen.oneIn)
            }
          }
          if !screen.isInkast && screen.state.allows("baton") {
            Button("Illegal throw", action: screen.illegal)
          }
          if !screen.over && !screen.isKingShot {
            Button("King hit early", action: screen.kingEarly)
          }
          if screen.state.allows("advantage") {
            Button("Advantage line") { screen.panel = .advantage }
          }
          if screen.state.allows("resign") { Button("Resign") { screen.panel = .resign } }
          if screen.state.allows("call") { Button("Game called") { screen.panel = .call } }
          if screen.state.allows("note") { Button("Add a note") { screen.panel = .note } }
          if screen.scorer.captureAppliesNow && screen.state.allows("capture") {
            Button("What to record") { screen.panel = .capture }
          }
          if !screen.rows.isEmpty {
            Button("Play by play") {
              screen.panel = .none
              do { replay = try model.playByPlay(screen.game) }
              catch { screen.problem = error.localizedDescription }
            }
          }
          Button("Timeline") {
            screen.panel = .none
            timeline = true
          }
        }
      case .capture:
        Text("What to record · turn \(screen.state.turn)").psKick()
        ForEach(Capture.Row.allCases, id: \.self) { row in
          CaptureRowButton(row: row, on: screen.game.capture.isOn(row)) {
            var capture = screen.game.capture
            capture.set(row, !capture.isOn(row))
            screen.setCapture(capture)
          }
        }
        Button("Done") { screen.panel = .none }
      case .advantage:
        Text("Where was the line used?").psKick()
        Button("Baseline") { screen.observeLine(applies: false) }
        Button("Advantage · distance unknown") { screen.observeLine(applies: true) }
        HStack {
          ForEach(1...4, id: \.self) { m in
            Button("\(m) m") { screen.observeLine(applies: true, meters: m) }
              .accessibilityLabel("\(m) metres from the baseline")
          }
        }
      case .note:
        TextField("Turn note", text: $s.noteText).textFieldStyle(.roundedBorder)
          .frame(minHeight: 48).accessibilityLabel("Turn note").onSubmit(screen.saveNote)
        Button("Save note", action: screen.saveNote)
      case .call, .resign:
        Text(screen.panel == .call ? "Which team won?" : "Which team resigned?").psKick()
        ForEach(Side.allCases, id: \.self) { side in
          Button(screen.teamName(side)) {
            if screen.panel == .call { screen.call(side) } else { screen.resign(side) }
          }
        }
      case .warnings:
        ForEach(screen.lastWarnings, id: \.self) { Text($0.text).font(PSFont.body(16)) }
        Button("Done") { screen.panel = .none }
      default: EmptyView()
      }
    }.buttonStyle(PSButtonStyle(minHeight: 48))
  }
}
