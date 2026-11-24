import Notation
import PitchsideDesign
import PitchsideModel
import SwiftUI

/// The score sheet: the result, turn by turn, and the Planet Kubb Notation file to copy
/// or share. Everything on it is the reader's (kubb.js) reading of the file.
struct ScoreSheetView: View {
  @Environment(AppModel.self) private var model
  let id: UUID
  @State private var copied = false

  var body: some View {
    PushedScreen(title: "Score sheet", back: "Home") {
      if let game = model.game(id) {
        let text = model.text(game)
        let read = model.read(game)
        result(game, read)
        if let read {
          Text("Turn by turn").psKick()
          turns(read.analysis)
          Text("Right column: batons that hit, of batons thrown.").psHelp()
          if read.analysis.turnWarnings + read.analysis.warnings.count > 0 { readerNotes(read.analysis) }
        }
        Text("Planet Kubb Notation").psKick()
        Text(text)
          .font(PSFont.mono(14))
          .foregroundStyle(Color.psText)
          .textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
          .padding(14)
          .frame(maxWidth: .infinity, alignment: .leading)
          .psCard(fill: .psInside, shadow: 0)
          .accessibilityLabel("The game file")
        actions(game, text, read)
      } else {
        Text("This game is gone.").font(PSFont.body(16))
      }
    }
  }

  @ViewBuilder func result(_ game: Game, _ read: GameRead?) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      if let a = read?.analysis, let w = a.winner {
        Text(kick(a)).psKick()
        HStack(spacing: 10) {
          TeamMarker(w, size: 26)
          Text("\(a.name(w)) win").font(PSFont.display(28, relativeTo: .title)).foregroundStyle(Color.psText)
        }
        .accessibilityElement(children: .combine)
        HStack(alignment: .top, spacing: 8) {
          TeamMarker(w.other, size: 22).padding(.top, 1)
          Text(overLine(a, w)).font(PSFont.body(16)).foregroundStyle(Color.psText)
        }
        .accessibilityElement(children: .combine)
      } else {
        Text(game.status == .playing ? "Still on the pitch" : "No result in the file").psKick()
        Text("\(game.team(.A).shownName(.A)) v \(game.team(.B).shownName(.B))")
          .font(PSFont.display(26, relativeTo: .title)).foregroundStyle(Color.psText)
        if game.status == .playing {
          Text("No turns yet: the scorer is a placeholder until record mode.")
            .font(PSFont.body(16)).foregroundStyle(Color.psText)
        }
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .psCard()
  }

  func kick(_ a: Analysis) -> String {
    let turn = a.endTurn.map { "in turn \($0)" } ?? ""
    switch a.winHow {
    case "king": return "King down \(turn)"
    case let how?: return "Over \(turn) · \(how)"
    case nil: return "Over"
    }
  }

  func overLine(_ a: Analysis, _ w: Side) -> String {
    guard a.winHow == "king", let left = a.winnerBaseStanding else { return "over \(a.name(w.other))" }
    if left == 0 { return "over \(a.name(w.other)), who had felled all their base kubbs" }
    return "over \(a.name(w.other)), who still had \(left) base \(left == 1 ? "kubb" : "kubbs") to fell"
  }

  func turns(_ a: Analysis) -> some View {
    VStack(spacing: 0) {
      ForEach(a.rows, id: \.turn) { row in
        HStack(spacing: 10) {
          Text("\(row.turn)").font(PSFont.body(16, .bold)).frame(minWidth: 24, alignment: .leading)
          TeamMarker(row.team, size: 20)
          Text(summary(row)).font(PSFont.body(16)).frame(maxWidth: .infinity, alignment: .leading)
          Text("\(row.hits) of \(row.thrown.count)").font(PSFont.body(16, .bold))
        }
        .foregroundStyle(Color.psText)
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
          "Turn \(row.turn), \(a.name(row.team)): \(summary(row)). \(row.hits) of \(row.thrown.count) batons hit.")
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .psBox()
  }

  /// "3 in · 3 field, 1 base", "1 base kubb", "4 in, 1 punishment · 3 field".
  func summary(_ row: Analysis.Row) -> String {
    var first: [String] = []
    if row.inkast > 0 {
      first.append("\(row.inkast) in")
    }
    let thrown = row.thrown
    let f = thrown.reduce(0) { $0 + ($1.kind == "hit" ? $1.f ?? 0 : 0) }
    let b = thrown.reduce(0) { $0 + ($1.kind == "hit" ? $1.b ?? 0 : 0) }
    var felled: [String] = []
    if f > 0 { felled.append("\(f) field") }
    if b > 0 { felled.append(f == 0 && first.isEmpty ? "\(b) base \(b == 1 ? "kubb" : "kubbs")" : "\(b) base") }
    if thrown.contains(where: { $0.kind == "king" }) { felled.append("king") }
    if felled.isEmpty { felled.append("nothing felled") }
    var parts = first
    if row.advantage { parts.append("advantage") }
    parts.append(felled.joined(separator: ", "))
    return parts.joined(separator: " · ")
  }

  func readerNotes(_ a: Analysis) -> some View {
    DisclosureGroup {
      VStack(alignment: .leading, spacing: 6) {
        ForEach(Array(a.warnings.enumerated()), id: \.offset) { Text($0.element) }
        ForEach(a.rows.filter { !$0.warnings.isEmpty }, id: \.turn) { row in
          ForEach(Array(row.warnings.enumerated()), id: \.offset) { Text("Turn \(row.turn): \($0.element)") }
        }
      }
      .font(PSFont.body(14))
      .foregroundStyle(Color.psText)
      .padding(.top, 6)
    } label: {
      let n = a.warnings.count + a.turnWarnings
      Text("The reader noted \(n) \(n == 1 ? "thing" : "things") in this file")
        .font(PSFont.body(15, .bold)).foregroundStyle(Color.psText)
    }
    .tint(Color.psText)
    .padding(12)
    .psBox()
  }

  @ViewBuilder func actions(_ game: Game, _ text: String, _ read: GameRead?) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Button("Watch in Throwing Wood") {}
        .buttonStyle(.ps)
        .disabled(true)
        .accessibilityHint("Not yet: Throwing Wood cannot show a real game yet.")
      Text("Not yet: Throwing Wood cannot replay a real game until record mode.").psHelp()
    }
    HStack(spacing: 10) {
      Button(copied ? "Copied" : "Copy") {
        UIPasteboard.general.string = text
        copied = true
      }
      .buttonStyle(.ps)
      .frame(maxWidth: 96)
      .accessibilityHint("Copies the game file's text")
      ShareLink(item: shareFile(game, text)) { Text("Share the .txt") }
        .buttonStyle(.psSolid)
      NavigationLink(value: Route.stats(game.id)) { Text("Stats") }
        .buttonStyle(.ps)
        .frame(maxWidth: 96)
        .disabled(read == nil)
    }
  }

  /// The file under a readable name in the temporary folder, for the share sheet.
  func shareFile(_ game: Game, _ text: String) -> URL {
    let name: String
    if case .file(let original) = game.origin, original.hasSuffix(".txt") { name = original } else {
      name = GameFile.fileName(for: game)
    }
    let url = FileManager.default.temporaryDirectory.appending(path: name)
    try? Data(text.utf8).write(to: url, options: .atomic)
    return url
  }
}
