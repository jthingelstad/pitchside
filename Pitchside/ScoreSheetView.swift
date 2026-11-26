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
  var back = "Games"
  var openSession: ((ScoringSession) -> Void)? = nil
  @State private var problem: String?
  @State private var history: ScoreHistory?
  @State private var engineNotes: [RecordWarning] = []
  @State private var copied = false
  @State private var pdf: URL?
  @State private var noteTurn: Int?
  @State private var replay: GameReplay?

  var body: some View {
    PushedScreen(title: "Score sheet", back: back) {
      if let game = model.game(id) {
        let text = model.text(game)
        let read = model.read(game)
        result(game, read)
        if game.isReference, let entry = model.reference(id) { ReferenceCreditCard(entry: entry) }
        if let read {
          ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { reviewActions(read).fixedSize(horizontal: true, vertical: false) }
            VStack(spacing: 8) { reviewActions(read) }
          }
          Button("Score sheet PDF") {
            do {
              let directory = FileManager.default.temporaryDirectory
                .appending(path: "Score sheets").appending(path: game.id.uuidString)
              try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
              let file = directory.appending(path: GameFile.fileName(for: game))
                .deletingPathExtension().appendingPathExtension("pdf")
              try ScoreSheetPDF.data(for: read, notation: text, inProgress: game.status == .playing, annotations: game.importedTurnNotes ?? [:])
                .write(to: file, options: .atomic)
              pdf = file
            } catch { problem = "Could not create the score sheet. \(error.localizedDescription)" }
          }
          .buttonStyle(.ps)
          .accessibilityHint("Preview, print or share the score sheet")
        }
        if !engineNotes.isEmpty {
          DisclosureGroup("Scorer notes (\(engineNotes.count))") {
            ForEach(engineNotes, id: \.self) { note in
              Text(note.text).font(PSFont.body(15)).frame(maxWidth: .infinity, alignment: .leading)
            }
          }.padding(12).frame(minHeight: 48).psBox()
        }
        if let history {
          Button("Edit timeline") { openTurn(nil, game: game) }.buttonStyle(.ps)
          if let action = history.undoAction {
            Button(action == .correction ? "Undo edit" : "Undo last event") {
              changeHistory(game, undoing: true)
            }.buttonStyle(.quiet)
          }
          if let action = history.redoAction {
            Button(action == .correction ? "Redo edit" : "Redo last event") {
              changeHistory(game, undoing: false)
            }.buttonStyle(.quiet)
          }
        }
        if let read {
          Text("Turn by turn").psKick()
          turns(read.analysis, game: game)
          Text("Right column: batons that hit, of batons thrown.").psHelp()
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
    .turnNoteEditor(turn: $noteTurn) { turn, text in
      guard var game = model.game(id), game.isImported, !game.isReference else { throw CocoaError(.fileNoSuchFile) }
      var notes = game.importedTurnNotes ?? [:]
      notes[turn, default: []].append(text)
      game.importedTurnNotes = notes
      try model.store.save(game)
      model.refresh()
    }
    .quickLookPreview($pdf)
    .onAppear(perform: loadHistory)
  }

  private func loadHistory() {
    history = nil
    engineNotes = []
    guard openSession != nil, let game = model.game(id), !game.isImported,
      FileManager.default.fileExists(atPath: model.store.logURL(id).path) else { return }
    do {
      let review = try RecordScorer.review(model.store.log(id))
      history = review.history
      engineNotes = review.warnings
    }
    catch { problem = error.localizedDescription }
  }

  private func openTurn(_ turn: Int?, game: Game) {
    do { try openSession?(ScoringSession(model.scorer(for: game), showTimeline: true, initialTurn: turn)) }
    catch { problem = error.localizedDescription }
  }

  private func changeHistory(_ game: Game, undoing: Bool) {
    do {
      let scorer = try model.scorer(for: game)
      if undoing { try scorer.undo() } else { try scorer.redo() }
      model.refresh()
      loadHistory()
      if !scorer.state.over { openSession?(ScoringSession(scorer)) }
    } catch { problem = error.localizedDescription }
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

  func turns(_ a: Analysis, game: Game) -> some View {
    VStack(spacing: 0) {
      ForEach(a.rows, id: \.turn) { row in
        let content = HStack(spacing: 10) {
          Text("\(row.turn)").font(PSFont.body(16, .bold)).frame(minWidth: 24, alignment: .leading)
          TeamMarker(row.team, size: 20)
          Text(row.scoringSummary).font(PSFont.body(16)).frame(maxWidth: .infinity, alignment: .leading)
          Text("\(row.hits) of \(row.thrown.count)").font(PSFont.body(16, .bold))
          if history != nil { Image(systemName: "chevron.right").accessibilityHidden(true) }
        }.foregroundStyle(Color.psText)
          .frame(minHeight: 48).contentShape(Rectangle())
        let summary = "Turn \(row.turn), \(a.name(row.team)): \(row.scoringSummary). \(row.hits) of \(row.thrown.count) batons hit."
        if history != nil {
          Button { openTurn(row.turn, game: game) } label: { content }
            .buttonStyle(.plain).accessibilityLabel(summary).accessibilityHint("Edit this turn")
            .accessibilityIdentifier("editTurn\(row.turn)")
        } else {
          if game.isImported && !game.isReference {
            Button { noteTurn = row.turn } label: {
              HStack {
                content
                Image(systemName: "square.and.pencil").accessibilityHidden(true)
              }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(summary).accessibilityHint("Add a turn note")
              .accessibilityIdentifier("annotateTurn\(row.turn)")
          } else {
            content.accessibilityElement(children: .ignore).accessibilityLabel(summary)
          }
        }
        let notes = [row.note].compactMap { $0 }.filter { !$0.isEmpty } + (game.importedTurnNotes?[row.turn] ?? [])
        ForEach(Array(notes.enumerated()), id: \.offset) { _, text in
          Text(verbatim: text).font(PSFont.body(14)).frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 34).padding(.bottom, 6)
        }
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
    Button {
      guard let game = model.game(id) else { return }
      do { replay = try model.playByPlay(game, analysis: read.analysis) }
      catch {
        problem = "Showing positions from the game file. \(error.localizedDescription)"
        let fileReplay = GameReplay(read.analysis)
        if !fileReplay.steps.isEmpty { replay = fileReplay }
      }
    } label: {
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
    switch game.origin {
    case .file(let original) where original.hasSuffix(".txt"), .reference(let original): name = original
    default:
      name = GameFile.fileName(for: game)
    }
    let url = FileManager.default.temporaryDirectory.appending(path: name)
    try? Data(text.utf8).write(to: url, options: .atomic)
    return url
  }
}

/// Bind the editor to a specific turn, including while the live scorer is on a later turn.
extension View {
  func turnNoteEditor(turn: Binding<Int?>, save: @escaping (Int, String) throws -> Void) -> some View {
    modifier(TurnNoteEditor(turn: turn, save: save))
  }
}

private struct TurnNoteEditor: ViewModifier {
  @Binding var turn: Int?
  let save: (Int, String) throws -> Void
  @State private var draft = ""
  @State private var error: String?
  @FocusState private var editing: Bool

  func body(content: Content) -> some View {
    content.sheet(isPresented: Binding(get: { turn != nil }, set: { if !$0 { turn = nil } }),
                  onDismiss: { draft = ""; error = nil }) {
      if let turn {
        NavigationStack {
          Form {
            TextField("Turn note", text: $draft, axis: .vertical).focused($editing)
            if let error { Text(error).foregroundStyle(.red) }
          }
          .navigationTitle("Note for turn \(turn)").navigationBarTitleDisplayMode(.inline)
          .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { self.turn = nil } }
            ToolbarItem(placement: .confirmationAction) {
              Button("Save note") {
                do {
                  try save(turn, draft.trimmingCharacters(in: .whitespacesAndNewlines))
                  self.turn = nil
                } catch { self.error = error.localizedDescription }
              }.disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
          }
          .onAppear { editing = true }
        }
      }
    }
  }
}

/// Who a reference game belongs to: the event, day and place, who scored it, and where it
/// was published, from the file's own headers. Shown on its sheet.
struct ReferenceCreditCard: View {
  let entry: ReferenceEntry

  var body: some View {
    let credit = entry.credit
    let a = entry.read.analysis
    VStack(alignment: .leading, spacing: 8) {
      Text("Reference game").psKick()
      Text("A real game from the Planet Kubb archive. Read only, and not counted in your stats.")
        .font(PSFont.body(15)).foregroundStyle(Color.psText)
        .fixedSize(horizontal: false, vertical: true)
      VStack(alignment: .leading, spacing: 4) {
        row("Event", credit.event)
        row("Date", credit.date.map { archiveDay($0) ?? $0 })
        row("Place", credit.location)
        row("Teams", "\(a.name(.A)) v \(a.name(.B))")
        row("Scored by", credit.scoredBy)
        if credit.enteredBy != credit.scoredBy { row("Entered by", credit.enteredBy) }
        row("Source", credit.source.map { _ in "Planet Kubb wiki" })
      }
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 8) { links(credit).fixedSize(horizontal: true, vertical: false) }
        VStack(alignment: .leading, spacing: 8) { links(credit) }
      }
      Text(ReferenceGames.terms).psHelp()
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .psBox()
    .accessibilityIdentifier("referenceCredit")
  }

  @ViewBuilder private func row(_ label: String, _ value: String?) -> some View {
    if let value {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(label).font(PSFont.body(14, .bold)).foregroundStyle(Color.psMuted).frame(width: 84, alignment: .leading)
        Text(verbatim: value).font(PSFont.body(15)).foregroundStyle(Color.psText)
          .fixedSize(horizontal: false, vertical: true)
      }
      .accessibilityElement(children: .combine)
    }
  }

  @ViewBuilder private func links(_ credit: ReferenceCredit) -> some View {
    Link(destination: entry.reference.archiveURL) { Label("Archive file", systemImage: "safari") }
      .buttonStyle(.quiet)
      .accessibilityHint("Opens this game's file in the Planet Kubb archive on GitHub")
    if let video = credit.videoLink {
      Link(destination: video) {
        Label(credit.videoSeconds != nil ? "Video from \(credit.videoOffset!)" : "Video", systemImage: "play.rectangle")
      }
      .buttonStyle(.quiet)
      .accessibilityHint("Opens the video the game was scored from")
    }
  }
}
