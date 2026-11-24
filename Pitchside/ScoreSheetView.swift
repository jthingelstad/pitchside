import Notation
import PitchsideDesign
import PitchsideModel
import QuickLook
import SwiftUI

/// The score sheet: the result, turn by turn, and the Planet Kubb Notation file to copy
/// or share. Everything on it is the reader's (kubb.js) reading of the file.
struct ScoreSheetView: View {
  @Environment(AppModel.self) private var model
  let id: UUID
  var engineNotes: [RecordWarning] = []
  var openSession: ((ScoringSession) -> Void)? = nil
  @State private var problem: String?
  @State private var copied = false
  @State private var pdf: URL?
  @State private var replay: GameReplay?

  var body: some View {
    PushedScreen(title: "Score sheet", back: "Games") {
      if let game = model.game(id) {
        let text = model.text(game)
        let read = model.read(game)
        result(game, read)
        if let read {
          ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { reviewActions(read).fixedSize(horizontal: true, vertical: false) }
            VStack(spacing: 8) { reviewActions(read) }
          }
        }
        if !engineNotes.isEmpty {
          DisclosureGroup("Scorer notes (\(engineNotes.count))") {
            ForEach(engineNotes, id: \.self) { note in
              Text(note.text).font(PSFont.body(15)).frame(maxWidth: .infinity, alignment: .leading)
            }
          }.padding(12).frame(minHeight: 48).psBox()
        }
        if let openSession, !game.isImported, FileManager.default.fileExists(atPath: model.store.logURL(id).path) {
          Button("Edit timeline") {
            do {
              let scorer = try model.scorer(for: game)
              openSession(ScoringSession(scorer, showTimeline: true))
            } catch { problem = String(describing: error) }
          }.buttonStyle(.ps)
          Button("Undo last event") {
            do {
              let scorer = try model.scorer(for: game)
              try scorer.undo()
              model.refresh()
              openSession(ScoringSession(scorer))
            } catch { problem = String(describing: error) }
          }.buttonStyle(.quiet)
        }
        if let read {
          Text("Turn by turn").psKick()
          turns(read.analysis)
          Text("Right column: batons that hit, of batons thrown.").psHelp()
          Button("Score sheet PDF") {
            do {
              let directory = FileManager.default.temporaryDirectory
                .appending(path: "Score sheets").appending(path: game.id.uuidString)
              try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
              let file = directory.appending(path: GameFile.fileName(for: game))
                .deletingPathExtension().appendingPathExtension("pdf")
              try ScoreSheetPDF.data(for: read.analysis, inProgress: game.status == .playing)
                .write(to: file, options: .atomic)
              pdf = file
            } catch { problem = "Could not create the score sheet. \(error.localizedDescription)" }
          }
          .buttonStyle(.ps)
          .accessibilityHint("Preview, print or share the score sheet")
          if read.analysis.turnWarnings + read.analysis.warnings.count > 0 { readerNotes(read.analysis) }
        }
        if let problem { Text(problem).psHelp() }
        Text("Planet Kubb Notation").psKick()
        Text(text)
          .font(PSFont.mono(14))
          .foregroundStyle(Color.psText)
          .textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
          .padding(14)
          .frame(maxWidth: .infinity, alignment: .leading)
          .psCard(fill: .psInside)
          .accessibilityLabel("The game file").accessibilityValue(text)
        actions(game, text)
      } else {
        Text("This game is gone.").font(PSFont.body(16))
      }
    }
    .navigationDestination(isPresented: Binding(
      get: { replay != nil }, set: { if !$0 { replay = nil } }
    )) {
      if let replay { ReplayView(replay: replay) }
    }
    .quickLookPreview($pdf)
  }

  @ViewBuilder func result(_ game: Game, _ read: GameRead?) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      if let a = read?.analysis, let w = a.winner {
        Text("Result").psKick()
        HStack(spacing: 10) {
          TeamMarker(w, size: 26)
          Text("\(a.name(w)) beat \(a.name(w.other))").font(PSFont.display(28, relativeTo: .title)).foregroundStyle(Color.psText)
        }
        .accessibilityElement(children: .combine)
        HStack(alignment: .top, spacing: 8) {
          Text(a.resultDetail).font(PSFont.body(16)).foregroundStyle(Color.psText)
        }
        .accessibilityElement(children: .combine)
      } else {
        Text(game.status == .playing ? "Still on the pitch" : "No result in the file").psKick()
        Text("\(game.team(.A).shownName(.A)) v \(game.team(.B).shownName(.B))")
          .font(PSFont.display(26, relativeTo: .title)).foregroundStyle(Color.psText)
        if game.status == .playing {
          Text("Draft · scoring in progress.")
            .font(PSFont.body(16)).foregroundStyle(Color.psText)
        }
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .psCard()
  }

  func turns(_ a: Analysis) -> some View {
    VStack(spacing: 0) {
      ForEach(a.rows, id: \.turn) { row in
        HStack(spacing: 10) {
          Text("\(row.turn)").font(PSFont.body(16, .bold)).frame(minWidth: 24, alignment: .leading)
          TeamMarker(row.team, size: 20)
          Text(row.scoringSummary).font(PSFont.body(16)).frame(maxWidth: .infinity, alignment: .leading)
          Text("\(row.hits) of \(row.thrown.count)").font(PSFont.body(16, .bold))
        }
        .foregroundStyle(Color.psText)
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
          "Turn \(row.turn), \(a.name(row.team)): \(row.scoringSummary). \(row.hits) of \(row.thrown.count) batons hit.")
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .psBox()
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

  @ViewBuilder private func reviewActions(_ read: GameRead) -> some View {
    Button { replay = GameReplay(read.analysis) } label: {
      Label("Play by play", systemImage: "rectangle.stack")
    }
    .buttonStyle(.ps)
    .accessibilityHint("Step through the game on the pitch")
    NavigationLink(value: Route.stats(id)) {
      Label("Game stats", systemImage: "chart.bar")
    }
    .buttonStyle(.ps)
  }

  @ViewBuilder func actions(_ game: Game, _ text: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Button("Watch in Throwing Wood") {}
        .buttonStyle(.ps)
        .disabled(true)
        .accessibilityHint("Not yet: Throwing Wood cannot show a real game yet.")
      Text("Real-game replay is planned for Throwing Wood.").psHelp()
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
