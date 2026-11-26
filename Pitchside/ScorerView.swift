import PitchsideDesign
import PitchsideModel
import SwiftUI

/// The pitch and recording controls stay in place while the scorer reads earlier turns.
struct ScorerView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dynamicTypeSize) private var typeSize
  @State private var replay: GameReplay?
  @State private var screen: ScorerScreen
  @State private var timeline = false
  @State private var viewport = PitchFrame.Viewport()
  @State private var controlsHeight: CGFloat?
  let initialTurn: Int?
  let close: () -> Void

  init(session: ScoringSession, close: @escaping () -> Void) {
    _screen = State(initialValue: ScorerScreen(scorer: session.scorer))
    _timeline = State(initialValue: session.showTimeline)
    initialTurn = session.initialTurn
    self.close = close
  }

  var body: some View {
    Group {
      if let replay {
        NavigationStack {
          ReplayView(replay: replay, back: "Scoring", startAtLast: true) { self.replay = nil }
        }
      } else if timeline {
        TimelineView(screen: screen, initialTurn: initialTurn) {
          if screen.over { close() } else { timeline = false }
        }
      } else {
        GeometryReader { area in
          HStack(spacing: 0) {
            VStack(spacing: 0) {
              header.padding(.horizontal, 8)
              pitch
            }
            .frame(width: area.size.width * 0.46)
            Divider()
            VStack(spacing: 0) {
              if additionalPanel {
                HStack {
                  ScrollView(.horizontal) {
                    Text("Turn \(screen.state.turn)  \(screen.tokens)").font(PSFont.mono())
                  }
                  .scrollIndicators(.hidden)
                  icon("xmark", "Close options") { screen.panel = .none }
                }.padding(.horizontal, 12)
                ScrollView { panel.padding(12) }
              } else {
                TurnHistoryView(screen: screen)
                Divider()
                ScrollView {
                  scoringControls
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { controlsHeight = $0 }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: min(controlsHeight ?? area.size.height, area.size.height * 0.70))
              }
            }
          }
        }
        .preference(key: LivePitchVisible.self, value: !screen.over)
        .foregroundStyle(Color.psText)
        .background(Color.psGround)
      }
    }
    .onChange(of: screen.view) { viewport = .init() }
    .onChange(of: screen.state.turn) { viewport = .init() }
    .onChange(of: screen.over) { _, over in if over { close() } }
  }

  private var pitch: some View {
    PitchCanvas(screen: screen, viewport: $viewport).frame(maxHeight: .infinity)
  }

  private var additionalPanel: Bool { screen.panel != .none && screen.panel != .pick }

  private var scoringControls: some View {
    VStack(spacing: 0) {
      if !screen.over { throwContext }
      prompt
      bottomBar
    }
  }

  var header: some View {
    HStack(spacing: 0) {
      Button(action: close) {
        Label("Games", systemImage: "chevron.backward")
          .font(PSFont.body(15, .medium)).frame(minHeight: 48)
      }
      .buttonStyle(.plain).accessibilityLabel("Back to Games")
      Spacer(minLength: 4)
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
  }

  private var throwContext: some View {
    let handlesKubbs = screen.isInkast || screen.punishPending || screen.placing
    let layout = typeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
      : AnyLayout(HStackLayout(spacing: 10))
    return layout {
      HStack(spacing: 5) {
        TeamMarker(screen.attacker, size: 16)
        Text("Turn \(screen.state.turn)").font(PSFont.body(15, .semibold))
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Turn \(screen.state.turn)")
      .accessibilityValue(screen.teamName(screen.attacker))
      .accessibilityIdentifier("entry-turn")

      if !screen.placing, !screen.punishPending, screen.playersOn, let player = screen.thrower {
        Button {
          screen.panel = screen.panel == .pick ? .none : .pick
        } label: {
          HStack(spacing: 4) {
            Text(player.name).font(PSFont.body(16, .semibold)).lineLimit(2)
            Image(systemName: "chevron.down").font(.footnote)
          }
          .foregroundStyle(Color.psSolid)
          .frame(minWidth: 48, minHeight: 48).contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityLabel("Change who throws").accessibilityValue(player.name)
      } else if !screen.playersOn, !screen.placing, !screen.punishPending {
        Text(screen.teamName(screen.attacker)).font(PSFont.body(15))
          .accessibilityIdentifier("entry-team")
      }

      Text(screen.scoringAction)
        .font(PSFont.body(15, .semibold))
        .padding(.horizontal, 7).padding(.vertical, 3)
        .foregroundStyle(handlesKubbs ? Color.psText : Color.psOnSolid)
        .background(handlesKubbs ? Color.psWood : Color.psSolid, in: RoundedRectangle(cornerRadius: 4))
        .accessibilityIdentifier("entry-action")
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 12).padding(.vertical, 2)
    .fixedSize(horizontal: false, vertical: true)
    .onChange(of: screen.firstBatonAfterInkast) { _, starts in
      if starts { AccessibilityNotification.Announcement("Inkast complete. Throw batons.").post() }
    }
  }

  @ViewBuilder var prompt: some View {
    VStack(alignment: .leading, spacing: 4) {
      if screen.panel == .pick {
        ScrollView(.horizontal) {
          HStack {
            ForEach(screen.players, id: \.id) { p in
              Button(p.name) { screen.choose(p) }
                .buttonStyle(PSButtonStyle(solid: screen.thrower?.id == p.id, minHeight: 48))
                .accessibilityAddTraits(screen.thrower?.id == p.id ? [.isSelected] : [])
            }
          }.padding(.trailing, 4).padding(.bottom, 4)
        }.scrollIndicators(.hidden)
      } else {
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            if screen.firstBatonAfterInkast {
              Label("Inkast complete", systemImage: "checkmark.circle.fill")
                .font(PSFont.body(14, .semibold)).foregroundStyle(Color.psSolid)
            }
            if let hint = screen.scoringHint {
              Text(hint).font(PSFont.body(15))
            }
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
    .padding(.horizontal, 12).frame(maxWidth: .infinity, alignment: .leading)
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
    let layout = typeSize >= .accessibility2
      ? AnyLayout(VStackLayout(spacing: 4))
      : AnyLayout(HStackLayout(spacing: 8))
    return layout {
      if screen.redoAction != nil {
        icon("arrow.uturn.backward", "Undo", action: screen.undo).disabled(screen.undoAction == nil)
        icon("arrow.uturn.forward", "Redo", action: screen.redo)
      } else {
        Button("Undo", action: screen.undo).buttonStyle(.quiet)
          .fixedSize(horizontal: true, vertical: false).disabled(screen.undoAction == nil)
      }
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
    }.padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 4)
  }

  private func icon(
    _ symbol: String, _ label: String, height: CGFloat = 48, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: symbol).font(.system(size: 17, weight: .medium))
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

/// Browse earlier turns independently of the live pitch. Expand a turn for the
/// throwers and outcomes; returning to the latest turn never changes a score.
private struct TurnHistoryView: View {
  @Environment(\.dynamicTypeSize) private var typeSize
  let screen: ScorerScreen
  @State private var expanded: Int?
  @State private var scrolledFromLatest = false

  var body: some View {
    ScrollViewReader { scroll in
      VStack(alignment: .leading, spacing: 0) {
        if let turn = screen.rows.last?.turn, expanded != nil || scrolledFromLatest {
          let latest = screen.history[turn]?.latestThrow
          Button {
            expanded = nil
            scroll.scrollTo(turn, anchor: .top)
          } label: {
            HStack(spacing: 6) {
              Image(systemName: "arrow.up.to.line")
              Text("Latest").font(PSFont.body(14))
              if let latest { Text(verbatim: latest).font(PSFont.mono(14)) }
            }
            .frame(minHeight: 44).contentShape(Rectangle())
          }
          .frame(maxWidth: .infinity, alignment: .trailing)
          .padding(.horizontal, 12)
          .buttonStyle(.plain).foregroundStyle(Color.psSolid)
          .accessibilityLabel("Show latest turn").accessibilityValue(latest ?? "")
        }
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 0) {
            if screen.rows.isEmpty {
              Text("No throws yet.").psHelp().padding(.horizontal, 12)
            }
            ForEach(screen.rows.reversed(), id: \.turn) { row in
              let history = screen.history[row.turn]
              let score = row.displayLine(names: screen.scorecardNames, inkasters: history?.inkasters ?? [])
              let entries = history?.entries ?? []
              let open = expanded == row.turn
              VStack(alignment: .leading, spacing: 0) {
                Button {
                  expanded = open ? nil : row.turn
                  if !open { scroll.scrollTo(row.turn, anchor: .top) }
                } label: {
                  let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 3))
                    : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
                  HStack {
                    layout {
                      Text("Turn \(row.turn)").font(PSFont.body(14, .semibold))
                        .fixedSize(horizontal: true, vertical: false)
                      if !open || entries.isEmpty {
                        Text(verbatim: score).font(PSFont.mono(15))
                          .fixedSize(horizontal: false, vertical: true)
                      }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: open ? "chevron.up" : "chevron.down")
                      .font(.caption).foregroundStyle(Color.psMuted)
                  }
                  .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityIdentifier("history-turn-\(row.turn)")
                .accessibilityLabel("Turn \(row.turn), \(screen.teamName(row.side)), \(score)")
                .accessibilityValue(open ? "Expanded" : "Collapsed")
                if open {
                  ForEach(entries.indices, id: \.self) { index in
                    Text(verbatim: entries[index]).font(PSFont.mono(15))
                      .frame(maxWidth: .infinity, alignment: .leading)
                      .padding(.bottom, 4)
                  }
                }
              }
              .padding(.horizontal, 12)
              .id(row.turn)
              Divider()
            }
          }
        }
        .onScrollGeometryChange(for: Bool.self) {
          $0.contentOffset.y + $0.contentInsets.top > 1
        } action: { _, away in scrolledFromLatest = away }
        .accessibilityIdentifier("turn-history")
      }
    }
  }
}
