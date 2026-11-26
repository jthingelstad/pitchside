import PitchsideDesign
import PitchsideModel
import SwiftUI

struct TimelineView: View {
  let screen: ScorerScreen
  let close: () -> Void
  @State private var turns: [TimelineTurn] = []
  @State private var expanded: Int?
  @State private var selected: TimelineEvent?
  @State private var problem: String?

  @State private var focusTurn: Int?

  init(screen: ScorerScreen, initialTurn: Int?, close: @escaping () -> Void) {
    self.screen = screen
    self.close = close
    _expanded = State(initialValue: initialTurn)
    _focusTurn = State(initialValue: initialTurn)
  }

  var body: some View {
    ScrollViewReader { proxy in
      Screen(title: "Timeline", back: screen.over ? "Score sheet" : "Scoring", onBack: close) {
        if selected == nil {
          HStack {
            Button(screen.undoAction == .correction ? "Undo edit" : "Undo") {
              screen.undo()
              load()
            }.buttonStyle(.quiet).disabled(screen.undoAction == nil)
            if let action = screen.redoAction {
              Button(action == .correction ? "Redo edit" : "Redo") {
                screen.redo()
                load()
              }.buttonStyle(.quiet)
            }
          }
        }
        if let message = problem ?? screen.problem { Text(message) }
        if turns.isEmpty { Text("The first observation will appear here.").psHelp() }
        ForEach(turns) { turn in
          VStack(alignment: .leading, spacing: 6) {
            Button {
              selected = nil
              expanded = expanded == turn.turn ? nil : turn.turn
            } label: {
              HStack(spacing: 8) {
                Text("\(turn.turn)").font(PSFont.body(16, .bold))
                TeamMarker(turn.side, size: 20)
                VStack(alignment: .leading, spacing: 4) {
                  Text(screen.teamName(turn.side)).font(PSFont.body(16, .semibold))
                  Text(tokens(turn)).font(PSFont.mono(14))
                }
                Spacer()
                Image(systemName: expanded == turn.turn ? "chevron.up" : "chevron.down")
              }.frame(minHeight: 48).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(
              "Turn \(turn.turn), \(screen.teamName(turn.side)), \(tokens(turn))")
            if turn.events.contains(where: { !$0.warnings.isEmpty }) { Chip("Needs a look") }
            if expanded == turn.turn {
              if selected == nil {
                Button("Add turn note") { screen.noteTurn = turn.turn }.buttonStyle(.quiet)
                FlowLayout(spacing: 6) {
                  ForEach(turn.events) { e in
                    Button {
                      selected = e
                    } label: {
                      Text(shortTitle(e)).font(PSFont.body(14, .bold))
                        .padding(.horizontal, 8).frame(minWidth: 48, minHeight: 48).psBox()
                    }.buttonStyle(.plain).accessibilityLabel(eventTitle(e))
                  }
                }
              }
              if let e = selected, e.sheetTurn == turn.turn {
                ObservationEditor(screen: screen, entry: e) { next in
                  selected = nil
                  load()
                  expanded = next ?? turn.turn
                  focusTurn = next
                }.id(e.id)
              }
            }
          }.padding(.horizontal, 10).padding(.vertical, 5)
            .psCard().id(turn.turn)
        }
      }
      .foregroundStyle(Color.psText)
      .onAppear(perform: load)
      .onChange(of: screen.noteTurn) { _, target in if target == nil { load() } }
      .task(id: focusTurn) {
        guard let turn = focusTurn else { return }
        await Task.yield()
        proxy.scrollTo(turn, anchor: .top)
        focusTurn = nil
      }
    }
  }

  func load() {
    do { turns = try screen.scorer.timeline() } catch { problem = String(describing: error) }
  }

  func tokens(_ turn: TimelineTurn) -> String {
    guard let line = turn.row?.line else { return "Awaiting a throw" }
    return String(
      line.prefix { $0 != "#" }.split(separator: " ").dropFirst().joined(separator: " "))
  }

  func shortTitle(_ e: TimelineEvent) -> String {
    if e.type == "baton" {
      let n = (e.before.batons?.thrown ?? 0) + 1
      let name = e.before.side(e.side).players.first { $0.id == e.event["by"]?.string }?.name
      return [String(n), name, ScorerScreen.label(e.event)].compactMap { $0 }.joined(
        separator: " · ")
    }
    return eventTitle(e)
  }

  func eventTitle(_ e: TimelineEvent) -> String {
    if e.type == "baton" {
      return "Baton \((e.before.batons?.thrown ?? 0) + 1) · \(ScorerScreen.label(e.event))"
    }
    if e.type == "note" { return "# " + (e.event["text"]?.string ?? "") }
    return ScorerScreen.label(e.event).capitalized
  }
}

private struct ObservationEditor: View {
  let screen: ScorerScreen
  let entry: TimelineEvent
  let finished: (Int?) -> Void
  @State private var event: [String: JSONValue]
  @State private var details = false
  @State private var remove = false
  @State private var insert = false
  @State private var preview: RecordResult?
  @State private var problem: String?

  init(screen: ScorerScreen, entry: TimelineEvent, finished: @escaping (Int?) -> Void) {
    self.screen = screen
    self.entry = entry
    self.finished = finished
    _event = State(initialValue: entry.event)
  }

  var edit: RecordEdit {
    if remove { return .remove(id: entry.id) }
    if insert { return .insert(before: entry.id, event: event) }
    return .replace(id: entry.id, event: event)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(
        insert
          ? "Insert before this observation"
          : "\(entry.type == "baton" ? "Baton \((entry.before.batons?.thrown ?? 0) + 1)" : "Recorded") · \(ScorerScreen.label(entry.event))"
      ).psKick()
      ForEach(entry.warnings, id: \.self) { Text($0.text).psHelp() }
      if !remove {
        controls
        if details || event["type"] != "baton",
          ["baton", "toss"].contains(event["type"]?.string ?? ""), entry.before.capture.players
        {
          Menu {
            Button("Unknown") { event["by"] = nil }
            ForEach(entry.before.side(entry.side).players, id: \.id) { player in
              Button(player.name) { event["by"] = .string(player.id) }
            }
          } label: {
            Text(
              "Thrower · "
                + (entry.before.side(entry.side).players.first { $0.id == event["by"]?.string }?
                  .name ?? "Unknown"))
          }.frame(minHeight: 48).accessibilityLabel("Edit thrower")
        }
      }
      if let p = preview {
        let impacts = consequences(p)
        if !impacts.isEmpty {
          VStack(alignment: .leading, spacing: 6) {
            Text("This changes what came after").psKick()
            Text(impacts[0].text).font(PSFont.body(15)).fixedSize(horizontal: false, vertical: true)
            if impacts.count > 1 {
              DisclosureGroup("See affected throws") {
                ForEach(Array(impacts.dropFirst().enumerated()), id: \.offset) { _, impact in
                  Text(impact.text).font(PSFont.body(15)).frame(
                    maxWidth: .infinity, alignment: .leading)
                }
              }.font(PSFont.body(15, .bold)).frame(minHeight: 48)
            }
          }.padding(10).psBox().overlay(
            RoundedRectangle(cornerRadius: 6).strokeBorder(Color.psWarn, lineWidth: 3))
        }
        HStack {
          Button("Keep original") { finished(nil) }.buttonStyle(.ps)
          Button(impacts.first.map { "Change, review turn \($0.turn)" } ?? "Save change") {
            do {
              try screen.scorer.edit(edit)
              screen.reload()
              finished(impacts.first?.turn)
            } catch { problem = String(describing: error) }
          }.buttonStyle(.psSolid)
        }
      } else {
        Button("Cancel edit") { finished(nil) }.buttonStyle(.quiet)
        Menu("Other edits") {
          Button("Insert a kubb thrown in before this") {
            insert = true
            event = RecordEvent.toss(true)
          }
          Button("Insert a baton before this") {
            insert = true
            event = RecordEvent.baton()
          }
          Button("Remove this observation") { remove = true }
        }.buttonStyle(.quiet)
      }
      if let problem { Text(problem).psHelp() }
    }
    .onChange(of: event) { updatePreview() }
    .onChange(of: remove) { updatePreview() }
    .onChange(of: insert) { updatePreview() }
  }

  @ViewBuilder var controls: some View {
    switch event["type"]?.string {
    case "baton":
      HStack {
        ForEach(["Miss", "1 field", "1 base"], id: \.self) { title in
          Button(title) {
            outcome(field: title == "1 field" ? 1 : 0, base: title == "1 base" ? 1 : 0)
          }
          .buttonStyle(PSButtonStyle(minHeight: 48))
        }
      }
      if preview == nil {
        Button(details ? "Fewer options" : "More options") { details.toggle() }.buttonStyle(.quiet)
      }
      if details {
        HStack {
          Menu("Field · \(number("field"))") { countChoices("field") }
          Menu("Base · \(number("base"))") { countChoices("base") }
          Menu("Result") {
            Button("King fell") { event["king"] = true }
            Button("Illegal throw") { event["illegal"] = true }
          }
        }.buttonStyle(.quiet)
      }
      if details && entry.before.capture.stance {
        positionEditor("Throwing spot", half: entry.side, value: event["stance"], stance: true) {
          event["stance"] = $0
        }
      }
      if details && entry.before.capture.pitch {
        let total = number("field") + number("base")
        ForEach(0..<total, id: \.self) { i in
          let values = event["at"]?.array ?? event["knownFelled"]?.array ?? []
          let title = i < number("field") ? "Felled field kubb" : "Felled base kubb"
          positionEditor(
            "\(title) · \(i + 1)", half: entry.side.other,
            value: i < values.count ? values[i] : nil
          ) { point in
            var updated = values
            while updated.count < total { updated.append(.null) }
            updated[i] = point ?? .null
            let complete = !updated.contains(.null)
            event["at"] = complete ? .array(updated) : nil
            event["knownFelled"] =
              !complete && updated.contains(where: { $0 != .null }) ? .array(updated) : nil
          }
        }
      }
    case "toss":
      Segmented(
        "Where the kubb landed", options: [("in", "In"), ("out", "Out")],
        selection: Binding(
          get: { event["result"]?.string ?? "in" },
          set: { result in
            event["result"] = .string(result)
            if result == "out" { event["at"] = nil }
          }))
      DisclosureGroup("Throw details") {
        Toggle("Rested on another kubb", isOn: bool("onTop")).frame(minHeight: 48)
        Toggle("Attempted a rescue", isOn: bool("rescueAttempt")).frame(minHeight: 48)
        Toggle("Felled the king", isOn: bool("king")).frame(minHeight: 48)
      }.frame(minHeight: 48)
    case "note":
      TextField(
        "Turn note",
        text: Binding(get: { event["text"]?.string ?? "" }, set: { event["text"] = .string($0) })
      )
      .textFieldStyle(.roundedBorder).frame(minHeight: 48)
    case "advantage":
      Segmented(
        "Observed advantage line", options: [(false, "Baseline"), (true, "Advantage")],
        selection: bool("applies"))
      if event["applies"] == true {
        Menu("Distance · " + (event["meters"]?.number.map { "\(Int($0)) m" } ?? "unknown")) {
          Button("Unknown") { event["meters"] = nil }
          ForEach(0...4, id: \.self) { n in
            Button("\(n) m") { event["meters"] = .number(Double(n)) }
          }
        }.buttonStyle(.quiet)
      }
    case "call", "resign":
      let key = event["type"] == "call" ? "winner" : "side"
      Segmented(
        "Team for this result", options: Side.allCases.map { ($0.rawValue, screen.teamName($0)) },
        selection: Binding(
          get: { event[key]?.string ?? entry.side.rawValue }, set: { event[key] = .string($0) }))
    case "capture":
      ForEach(
        [("players", "Who threw"), ("pitch", "Where kubbs stand"), ("stance", "Throwing spots")],
        id: \.0
      ) { key, title in
        Toggle(title, isOn: bool(key)).frame(minHeight: 48)
      }
    default: EmptyView()
    }
    if event["type"] == "punish"
      || (event["type"] == "toss" && event["result"] != "out" && entry.before.capture.pitch)
    {
      positionEditor("Standing spot", half: entry.side.other, value: event["at"]) {
        event["at"] = $0
      }
    }
  }

  private func positionEditor(
    _ title: String, half: Side, value: JSONValue?, stance: Bool = false,
    set: @escaping (JSONValue?) -> Void
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("\(title) · Team \(half.rawValue)’s half").psHelp()
      GeometryReader { geo in
        ZStack {
          Color.psGrass
          if let x = value?["across"]?.number, let y = value?["depth"]?.number {
            TeamMarker(half, size: 22)
              .position(x: geo.size.width * x / 5, y: geo.size.height * max(0, 1 - y / 4))
          }
        }.contentShape(Rectangle()).onTapGesture(coordinateSpace: .local) { p in
          let x = min(5, max(0, 5 * p.x / geo.size.width))
          let y = min(4, max(0, 4 * (1 - p.y / geo.size.height)))
          var spot = RecordPoint(
            across: (x * 100).rounded(.toNearestOrEven) / 100,
            depth: (y * 100).rounded(.toNearestOrEven) / 100)
          if stance {
            let depth = entry.before.advantage?.meters.map { 4 - Double($0) }
            spot = PitchFrame.snap(spot, advantageDepth: depth)
          }
          set(spot.tap(in: half))
        }.accessibilityRepresentation {
          Menu(title) {
            ForEach(0..<5) { x in
              Menu("Across \(x) metres") {
                ForEach(0..<(stance ? 5 : 4), id: \.self) { d in
                  Button("Depth \(d) metres") {
                    set(
                      RecordPoint(
                        across: Double(x) + 0.5,
                        depth: Double(d) + (stance ? 0 : 0.5)
                      ).tap(in: half))
                  }
                }
              }
            }
          }
        }
      }.frame(height: 110)
      if value != nil && value != .null {
        Button("Leave \(title.lowercased()) blank") { set(nil) }.buttonStyle(.quiet)
      }
    }
  }

  func bool(_ key: String) -> Binding<Bool> {
    Binding(get: { event[key]?.bool ?? false }, set: { event[key] = .bool($0) })
  }

  func number(_ key: String) -> Int { Int(event[key]?.number ?? 0) }

  func countChoices(_ key: String) -> some View {
    ForEach(0...10, id: \.self) { n in
      Button("\(n)") {
        outcome(
          field: key == "field" ? n : number("field"), base: key == "base" ? n : number("base"))
      }
    }
  }

  func outcome(field: Int, base: Int) {
    if field != number("field") || base != number("base") {
      event["at"] = nil
      event["knownFelled"] = nil
    }
    event["field"] = field == 0 ? nil : .number(Double(field))
    event["base"] = base == 0 ? nil : .number(Double(base))
    event["illegal"] = nil
    event["king"] = nil
  }

  func updatePreview() {
    guard remove || insert || event != entry.event else {
      preview = nil
      return
    }
    do {
      preview = try screen.scorer.preview(edit)
      problem = nil
    } catch {
      preview = nil
      problem = String(describing: error)
    }
  }

  struct Impact {
    let turn: Int
    let text: String
  }

  func consequences(_ result: RecordResult) -> [Impact] {
    let before = screen.scorer
    let after = result.sheet?.rows ?? []
    let numbers = Set(before.rows.map(\.turn) + after.map(\.turn)).sorted()
    var changes: [Impact] = []
    for turn in numbers where turn >= min(entry.turn, entry.sheetTurn) {
      let old = before.rows.first { $0.turn == turn }
      let new = after.first { $0.turn == turn }
      if turn > entry.turn && old != new {
        let oldLine = old?.line ?? "no turn"
        let newLine = new?.line ?? "no turn"
        let detail =
          oldLine == newLine ? "The recorded positions change." : "\(oldLine)\nBecomes \(newLine)"
        changes.append(Impact(turn: turn, text: "Turn \(turn) · \(detail)"))
      } else if turn == entry.turn {
        let n = (entry.before.batons?.thrown ?? 0) + (entry.type == "baton" ? 1 : 0)
        let oldTail = (old?.batons ?? []).dropFirst(n).map(\.token)
        let newTail = (new?.batons ?? []).dropFirst(n).map(\.token)
        if oldTail != newTail {
          changes.append(
            Impact(
              turn: turn,
              text:
                "Later batons in turn \(turn) change from \(oldTail.joined(separator: " ")) to \(newTail.joined(separator: " "))."
            ))
        }
      }
    }
    for w in result.warnings
    where !before.warnings.contains(where: { $0.id == w.id && $0.text == w.text }) {
      changes.append(
        Impact(turn: w.turn ?? entry.turn, text: "Turn \(w.turn ?? entry.turn) · \(w.text)"))
    }
    let s = result.state
    if s.inkast?.dueAtStart != before.state.inkast?.dueAtStart
      || s.advantage?.applies != before.state.advantage?.applies,
      let ink = s.inkast
    {
      let was = before.state.inkast?.dueAtStart ?? 0
      changes.insert(
        Impact(
          turn: s.turn,
          text:
            "Turn \(s.turn) would have \(ink.dueAtStart) kubbs to throw in, \(s.advantage?.applies == true ? "with" : "without") an advantage line. It was scored with \(was)\(before.state.advantage?.applies == true ? " and an advantage line" : " from the baseline")."
        ), at: 0)
    }
    if s.winner != before.state.winner || s.over != before.state.over {
      changes.insert(
        Impact(
          turn: s.turn,
          text: s.winner.map { "\(screen.teamName($0)) would win." }
            ?? "The game would still be on the pitch."), at: 0)
    }
    return changes
  }
}
