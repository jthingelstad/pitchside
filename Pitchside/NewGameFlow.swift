import Notation
import PitchsideDesign
import PitchsideModel
import SwiftUI

/// A new game: Teams, then This game, then the scorer. No tab bar; Home is the way out.
struct NewGameFlow: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  let started: (LiveScorer) -> Void
  @State private var game: Game?
  @State private var path: [Step] = []
  @State private var problem: String?

  enum Step: Hashable { case thisGame }

  var body: some View {
    NavigationStack(path: $path) {
      Group {
        if let game = Binding($game) {
          TeamsView(game: game, home: cancel) {
            model.saveDraft(game.wrappedValue)
            path = [.thisGame]
          }
          .navigationDestination(for: Step.self) { _ in
            ThisGameView(game: game) {
              model.saveDraft(game.wrappedValue)
            } start: {
              do { started(try model.start(game.wrappedValue)) }
              catch { problem = String(describing: error) }
            }
          }
        }
      }
    }
    .alert("Could not start scoring", isPresented: .constant(problem != nil)) {
      Button("OK") { problem = nil }
    } message: { Text(problem ?? "") }
    .onAppear {
      if game == nil { game = model.draft() }
      #if DEBUG
        // Screenshots: a filled-in draft (`-PitchsideScreen teams|thisgame`).
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-PitchsideScreen"), i + 1 < args.count,
          ["teams", "thisgame"].contains(args[i + 1])
        {
          let roster = model.roster
          func p(_ n: String) -> TeamPlayer {
            TeamPlayer(name: n, key: roster.first { $0.name == n }?.key)
          }
          game?.teams = [
            .A: Team(name: "Mossy Stakes", players: [p("Wren"), p("Tomas"), p("Kit")]),
            .B: Team(name: "Crooked Crowns", players: [p("Ivo"), p("Maren")]),
          ]
          if args[i + 1] == "thisgame" { path = [.thisGame] }
        }
      #endif
    }
  }

  func cancel() {
    if let game { model.discardDraft(game) }
    dismiss()
  }
}

// MARK: - Teams

struct TeamsView: View {
  @Environment(AppModel.self) private var model
  @Binding var game: Game
  let home: () -> Void
  let next: () -> Void
  /// The side a tapped saved name joins: the last one typed in, else the first not full.
  @State private var active: Side = .A
  @State private var typed: [Side: String] = [:]
  @State private var newName = ""
  @FocusState private var focus: Field?

  enum Field: Hashable { case team(Side), add(Side), newName }

  var body: some View {
    VStack(spacing: 0) {
      Screen(title: "Teams", back: "Home", onBack: home) {
        ForEach(Side.allCases, id: \.self) { side in teamCard(side) }
        savedNames
        Button("Next: this game", action: next)
          .buttonStyle(.psSolid)
          .disabled(!game.isReady)
        if !game.isReady {
          Text("Each team needs one to six players.").psHelp()
        }
      }
    }
  }

  func teamCard(_ side: Side) -> some View {
    let team = game.team(side)
    return VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .bottom, spacing: 10) {
        TeamMarker(side, size: 34).padding(.bottom, 9)
        VStack(alignment: .leading, spacing: 4) {
          Text("Side \(side.rawValue) · team name").psKick()
          TextField("Team \(side.rawValue)", text: teamName(side))
            .font(PSFont.display(24, relativeTo: .title2))
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .submitLabel(.next)
            .focused($focus, equals: .team(side))
            .padding(.horizontal, 10)
            .frame(minHeight: 52)
            .background(Color.psField, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.psLine, lineWidth: 3))
            .accessibilityLabel("Side \(side.rawValue) team name")
            .onSubmit { focus = .add(side) }
        }
      }
      ForEach(Array(team.players.enumerated()), id: \.offset) { i, player in
        playerRow(side, i, player)
      }
      if !team.isFull { addRow(side, number: team.players.count + 1) }
    }
    .padding(14)
    .psCard()
  }

  func teamName(_ side: Side) -> Binding<String> {
    Binding(get: { game.team(side).name }, set: { game.teams[side, default: Team()].name = $0 })
  }

  func playerRow(_ side: Side, _ i: Int, _ player: TeamPlayer) -> some View {
    let count = game.team(side).players.count
    return HStack(spacing: 12) {
      Text("\(i + 1)").font(PSFont.body(16, .bold)).frame(minWidth: 18).accessibilityHidden(true)
      Text(player.name).font(PSFont.body(17, .bold)).frame(maxWidth: .infinity, alignment: .leading)
      Menu {
        if i > 0 { Button("Throw earlier") { move(side, i, i - 1) } }
        if i < count - 1 { Button("Throw later") { move(side, i, i + 1) } }
        if let other = Optional(side.other), !game.team(other).isFull {
          Button("Move to \(game.team(other).shownName(other))") { switchSide(side, i) }
        }
        Button("Take off the team", role: .destructive) { remove(side, i) }
      } label: {
        Image(systemName: "equal").font(.system(size: 22, weight: .heavy))
          .frame(width: 48, height: 48)
          .contentShape(Rectangle())
      }
      .accessibilityLabel("Order and remove \(player.name)")
    }
    .foregroundStyle(Color.psText)
    .padding(.leading, 12)
    .frame(minHeight: 52)
    .background(Color.psField, in: RoundedRectangle(cornerRadius: 6))
    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.psLine, lineWidth: 2))
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(i + 1), \(player.name)")
    .accessibilityActions {
      if i > 0 { Button("Throw earlier") { move(side, i, i - 1) } }
      if i < count - 1 { Button("Throw later") { move(side, i, i + 1) } }
      Button("Take off the team") { remove(side, i) }
    }
  }

  func addRow(_ side: Side, number: Int) -> some View {
    HStack(spacing: 12) {
      Text("\(number)").font(PSFont.body(16, .bold)).frame(minWidth: 18).accessibilityHidden(true)
      TextField(
        "Type a name, or tap one below",
        text: Binding(get: { typed[side] ?? "" }, set: { typed[side] = $0; active = side })
      )
      .font(PSFont.body(17, .bold))
      .textInputAutocapitalization(.words)
      .autocorrectionDisabled()
      .submitLabel(.done)
      .focused($focus, equals: .add(side))
      .onSubmit { addTyped(side) }
      .accessibilityLabel("Player \(number) of \(game.team(side).shownName(side))")
    }
    .foregroundStyle(Color.psText)
    .padding(.horizontal, 12)
    .frame(minHeight: 52)
    .background(Color.psInside, in: RoundedRectangle(cornerRadius: 6))
    .overlay(
      RoundedRectangle(cornerRadius: 6).strokeBorder(
        Color.psLine, style: StrokeStyle(lineWidth: 2, dash: [5, 4])))
    .onTapGesture { active = side }
  }

  @ViewBuilder var savedNames: some View {
    let playing = Set(Side.allCases.flatMap { game.team($0).players.compactMap(\.key) })
    let free = model.roster.filter { !playing.contains($0.key) }
    let target = targetSide
    Text("Saved names · kept on this phone only").psKick()
    if let target {
      Text("A tap adds to \(game.team(target).shownName(target)).").psHelp()
    }
    FlowLayout(spacing: 10) {
      ForEach(free) { name in
        Button(name.name) { add(TeamPlayer(name: name.name, key: name.key), to: target) }
          .buttonStyle(PSButtonStyle(minHeight: 48))
          .fixedSize()
          .disabled(target == nil)
          .accessibilityHint(target.map { "Adds to \(game.team($0).shownName($0))" } ?? "Both teams are full")
      }
    }
    let names = Side.allCases.flatMap { game.team($0).players.map(\.name) }
    if !names.isEmpty {
      Chip("\(names.joined(separator: ", ")) \(names.count == 1 ? "is" : "are") playing")
    }
    Text("New name").font(PSFont.body(15, .bold)).foregroundStyle(Color.psText)
    HStack(spacing: 10) {
      TextField("First name", text: $newName)
        .font(PSFont.body(17))
        .textInputAutocapitalization(.words)
        .autocorrectionDisabled()
        .focused($focus, equals: .newName)
        .padding(.horizontal, 12)
        .frame(minHeight: 52)
        .background(Color.psField, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.psLine, lineWidth: 3))
        .onSubmit(addNew)
        .accessibilityLabel("New name")
      Button("Add", action: addNew).buttonStyle(PSButtonStyle()).frame(width: 92)
        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
    }
  }

  /// The side a saved name joins.
  var targetSide: Side? {
    if !game.team(active).isFull { return active }
    return Side.allCases.first { !game.team($0).isFull }
  }

  func addTyped(_ side: Side) {
    let text = (typed[side] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    let saved = model.save(name: text)
    add(TeamPlayer(name: saved?.name ?? text, key: saved?.key), to: side)
    typed[side] = ""
    if !game.team(side).isFull { focus = .add(side) }
  }

  func addNew() {
    guard let saved = model.save(name: newName) else { return }
    newName = ""
    add(TeamPlayer(name: saved.name, key: saved.key), to: targetSide)
  }

  func add(_ player: TeamPlayer, to side: Side?) {
    guard let side, !game.team(side).isFull else { return }
    if let key = player.key, Side.allCases.contains(where: { game.team($0).players.contains { $0.key == key } }) {
      return
    }
    game.teams[side, default: Team()].players.append(player)
    active = side
  }

  func move(_ side: Side, _ from: Int, _ to: Int) {
    game.teams[side, default: Team()].players.swapAt(from, to)
  }

  func remove(_ side: Side, _ i: Int) {
    game.teams[side, default: Team()].players.remove(at: i)
  }

  func switchSide(_ side: Side, _ i: Int) {
    let player = game.teams[side, default: Team()].players.remove(at: i)
    game.teams[side.other, default: Team()].players.append(player)
  }
}

/// Lays children in rows, wrapping (saved names).
struct FlowLayout: Layout {
  var spacing: CGFloat = 8

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let width = proposal.width ?? 320
    var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0
    for s in subviews {
      let size = s.sizeThatFits(.unspecified)
      if x > 0 && x + size.width > width { x = 0; y += line + spacing; line = 0 }
      x += size.width + spacing
      line = max(line, size.height)
    }
    return CGSize(width: width, height: y + line)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
    for s in subviews {
      let size = s.sizeThatFits(.unspecified)
      if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += line + spacing; line = 0 }
      s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
      x += size.width + spacing
      line = max(line, size.height)
    }
  }
}

// MARK: - This game

struct ThisGameView: View {
  @Binding var game: Game
  let save: () -> Void
  let start: () -> Void
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    Screen(title: "This game", back: "Teams", onBack: { dismiss() }) {
      section("Opening · the same switches as Throwing Wood") {
        Segmented(
          "Opening", options: GameOptions.Opening.allCases.map { ($0, $0.title) },
          selection: $game.options.opening)
      }
      section("Surface") {
        Segmented(
          "Surface", options: GameOptions.Surface.allCases.map { ($0, $0.title) },
          selection: $game.options.surface)
      }
      section("Wind today") {
        Segmented(
          "Wind today", options: GameOptions.Wind.allCases.map { ($0, $0.title) }, selection: $game.options.wind)
      }
      section("Who throws first") {
        Segmented(
          "Who throws first", options: Side.allCases.map { ($0, game.team($0).shownName($0)) },
          selection: $game.options.first)
      }
      section("Event and place · optional, in the file's header") {
        textField("Event, like Fall Open, pool 2", text: optional(\.event), label: "Event")
        textField("Place or pitch number", text: optional(\.location), label: "Location")
      }
      Text("What to record").psKick()
      VStack(spacing: 10) {
        ForEach(Capture.Row.allCases, id: \.self) { row in captureRow(row) }
      }
      Text("Pitchside only asks for what is on, and the file says what was recorded. Change it between turns.")
        .psHelp()
      Button("Start scoring", action: start).buttonStyle(.psSolid)
    }
    .onChange(of: game) { save() }
  }

  func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title).psKick()
      content()
    }
  }

  /// An optional text of the game as a field's text (empty is none). The engine takes
  /// at most 120 bytes.
  func optional(_ key: WritableKeyPath<Game, String?>) -> Binding<String> {
    Binding(
      get: { game[keyPath: key] ?? "" },
      set: { v in
        var t = v
        while t.utf8.count > 120 { t.removeLast() }
        game[keyPath: key] = t.isEmpty ? nil : t
      })
  }

  func textField(_ prompt: String, text: Binding<String>, label: String) -> some View {
    TextField(prompt, text: text)
      .font(PSFont.body(17))
      .textInputAutocapitalization(.words)
      .autocorrectionDisabled()
      .padding(.horizontal, 12)
      .frame(minHeight: 52)
      .background(Color.psField, in: RoundedRectangle(cornerRadius: 6))
      .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.psLine, lineWidth: 3))
      .foregroundStyle(Color.psText)
      .accessibilityLabel(label)
  }

  func captureRow(_ row: Capture.Row) -> some View {
    CaptureRowButton(row: row, on: game.capture.isOn(row)) {
      game.capture.set(row, !game.capture.isOn(row))
    }
  }
}

/// One row of "What to record": its notation, title and what it asks of the scorer; on
/// rows are solid.
struct CaptureRowButton: View {
  let row: Capture.Row
  let on: Bool
  let toggle: () -> Void

  var body: some View {
    let always = row == .turn
    let reserved = row == .lay
    Button(action: toggle) {
      HStack(alignment: .center, spacing: 12) {
        Text(row.glyph)
          .font(PSFont.mono(17, relativeTo: .headline).weight(.bold))
          .frame(minWidth: 40, alignment: .leading)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
          Text(row.title).font(PSFont.body(17, .bold))
          Text(row.detail).font(PSFont.body(15))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
        Text(always ? "Always" : reserved ? "Later" : on ? "On" : "Off")
          .font(PSFont.body(14, .heavy)).textCase(.uppercase)
      }
      .foregroundStyle(on ? Color.psOnSolid : Color.psText)
      .padding(14)
      .frame(maxWidth: .infinity, minHeight: 64)
      .background(on ? Color.psSolid : Color.psPlate, in: RoundedRectangle(cornerRadius: 6))
      .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.psLine, lineWidth: 3))
      .background(RoundedRectangle(cornerRadius: 6).fill(Color.psShade).offset(x: 3, y: 3))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    // Not `.disabled`: that greys the always-on row below 7:1. It just takes no taps.
    .disabled(always || reserved)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(row.title). \(row.detail)")
    .accessibilityValue(always ? "always recorded" : reserved ? "unavailable" : on ? "on" : "off")
    .accessibilityAddTraits(always ? [] : [.isToggle])
  }
}
