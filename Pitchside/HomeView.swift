import Notation
import PitchsideDesign
import PitchsideModel
import SwiftUI
import UniformTypeIdentifiers

/// Home: the game still on the pitch, a new game, recent games, and opening a file.
struct HomeView: View {
  @Environment(AppModel.self) private var model
  let newGame: () -> Void
  let carryOn: (Game) -> Void
  let openSheet: (UUID) -> Void
  @State private var importing = false
  @State private var refusal: String?
  @State private var showAllFinished = false

  var body: some View {
    VStack(spacing: 0) {
      ScreenHeader("Games", brand: "Pitchside")
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          if let problem = model.recoveryProblem { Text(problem).psHelp() }
          ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { fileActions.fixedSize(horizontal: true, vertical: false) }
            VStack(spacing: 8) { fileActions }
          }
          if !model.playing.isEmpty {
            Text("In progress").psKick()
            ForEach(model.playing) { game in stillOnThePitch(game) }
          }
          if model.playing.isEmpty && model.finished.isEmpty {
            // A new install: nothing of the scorer's yet, so the reference games lead.
            Text("Recent games").psKick()
            Text("Games you score or open show up here. Until then, start with real games from the Planet Kubb archive.").psHelp()
            if !model.references.isEmpty {
              Text("Reference games").psKick()
              ReferenceList(entries: model.references, route: Route.sheet)
            }
          } else {
            recent
            if !model.references.isEmpty { referenceLink }
          }
          footer
        }
        .padding(16)
      }
    }
    .background(Color.psGround)
    .toolbar(.hidden, for: .navigationBar)
    .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText, .text]) { result in
      switch result {
      case .success(let url):
        do {
          let game = try model.open(url: url)
          openSheet(game.id)
        } catch let error as NotationError {
          refusal = error.description
        } catch {
          refusal = "Pitchside could not read that file."
        }
      case .failure: break
      }
    }
    .fileDialogDefaultDirectory(model.filesFolder)
    .alert("Not opened", isPresented: .constant(refusal != nil), presenting: refusal) { _ in
      Button("OK") { refusal = nil }
    } message: { Text($0) }
  }

  @ViewBuilder var fileActions: some View {
    Button { newGame() } label: { Label("New game", systemImage: "plus") }
      .buttonStyle(PSButtonStyle(solid: model.playing.isEmpty))
      .accessibilityHint("Set up teams and scoring options")
    Button { importing = true } label: { Label("Open file", systemImage: "folder") }
      .buttonStyle(.quiet)
      .accessibilityHint("Open a Planet Kubb Notation text file")
  }

  func stillOnThePitch(_ game: Game) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      ForEach(Side.allCases, id: \.self) { side in
        HStack {
          TeamLabel(side: side, name: game.team(side).shownName(side), display: true)
          Spacer()
          Text(game.team(side).players.count == 1 ? "1 player" : "\(game.team(side).players.count) players")
            .font(PSFont.body(14)).foregroundStyle(Color.psMuted)
        }
      }
      Text("Started \(game.created.formatted(date: .abbreviated, time: .shortened))")
        .font(PSFont.body(15))
        .foregroundStyle(Color.psMuted)
        .fixedSize(horizontal: false, vertical: true)
      Button("Resume scoring") { carryOn(game) }
        .buttonStyle(.psSolid)
        .accessibilityLabel("Resume scoring, \(game.team(.A).shownName(.A)) versus \(game.team(.B).shownName(.B))")
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .psCard()
  }

  /// Once the scorer has games of their own, the collection is one row under them.
  var referenceLink: some View {
    NavigationLink(value: Route.references) {
      HStack(spacing: 8) {
        Image(systemName: "books.vertical").font(.system(size: 18, weight: .semibold))
          .foregroundStyle(Color.psText).accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
          Text("Reference games").font(PSFont.body(16, .bold)).foregroundStyle(Color.psText)
          Text("\(model.references.count) real games from the Planet Kubb archive")
            .font(PSFont.body(14)).foregroundStyle(Color.psMuted)
        }
        .multilineTextAlignment(.leading)
        Spacer(minLength: 4)
        Image(systemName: "chevron.right").font(.system(size: 16, weight: .bold))
          .foregroundStyle(Color.psText).accessibilityHidden(true)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
      .psBox()
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("referenceGames")
    .accessibilityHint("Real games to look through, read only")
    .padding(.top, 8)
  }

  @ViewBuilder var recent: some View {
    Text("Recent games").psKick()
    if model.finished.isEmpty {
      Text("Games you score or open show up here.").psHelp()
    }
    ForEach(showAllFinished ? model.finished[...] : model.finished.prefix(12)) { game in
      let read = model.read(game)
      NavigationLink(value: Route.sheet(game.id)) {
        HStack(spacing: 8) {
          VStack(alignment: .leading, spacing: 2) {
            Text(resultTitle(game, read))
              .font(PSFont.body(16, .bold))
              .foregroundStyle(Color.psText)
            Text(resultDetail(game, read))
              .font(PSFont.body(14))
              .foregroundStyle(Color.psMuted)
          }
          .multilineTextAlignment(.leading)
          Spacer(minLength: 4)
          Image(systemName: "chevron.right").font(.system(size: 16, weight: .bold))
            .foregroundStyle(Color.psText)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .psBox()
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityHint("Opens the score sheet")
      .contextMenu {
        Button("Delete this game", role: .destructive) { model.delete(game) }
      }
    }
    if !showAllFinished && model.finished.count > 12 {
      Button("Show all \(model.finished.count) games") { showAllFinished = true }
        .buttonStyle(.quiet)
    }
  }

  /// The version, and what Pitchside does with data. (Small enough not to need a Settings
  /// screen yet.)
  var footer: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Pitchside \(model.version.text)")
        .font(PSFont.body(14, .bold))
        .foregroundStyle(Color.psMuted)
      if let detail = model.version.detail { Text(detail).psHelp() }
      if let problem = model.engineProblem {
        Text("The engine did not start: \(problem)").font(PSFont.body(14)).foregroundStyle(Color.psWarn)
      }
      Text(privacy).psHelp()
    }
    .accessibilityElement(children: .combine)
    .padding(.top, 8)
  }

  /// What is kept where. Finished games are copied to the scorer's own iCloud Drive
  /// folder (or the phone's, with iCloud Drive off); the roster never leaves the phone.
  var privacy: String {
    let folder = switch model.filesPlace {
    case .iCloud: "iCloud Drive › Pitchside, in your own iCloud"
    case .local: "On My iPhone › Kubb: Pitchside"
    case nil: "a Pitchside folder"
    }
    return "Games are kept on this phone. Each finished game's file, with its team and player names, "
      + "is also in Files under \(folder). The roster stays on this phone. Nothing is sent to us."
  }
}

/// The reference games, read only: real games from the Planet Kubb archive. Reached from
/// Games; never mixed into the scorer's own list.
struct ReferenceGamesView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    PushedScreen(title: "Reference games", back: "Games") {
      Text("Real games scored at tournaments from 2011 to 2015 and kept in the Planet Kubb archive. Each opens its score sheet, play by play and stats. They are read only and never count in your stats.").psHelp()
      ReferenceList(entries: model.references, route: Route.reference)
      Text(ReferenceGames.terms).psHelp()
    }
  }
}

/// One row per reference game: the result, the event and day, and why it is here.
struct ReferenceList: View {
  let entries: [ReferenceEntry]
  let route: (UUID) -> Route

  var body: some View {
    ForEach(entries) { entry in
      NavigationLink(value: route(entry.id)) {
        HStack(spacing: 8) {
          VStack(alignment: .leading, spacing: 3) {
            Text(resultTitle(entry.game, entry.read))
              .font(PSFont.body(16, .bold)).foregroundStyle(Color.psText)
            Text(referenceDetail(entry))
              .font(PSFont.body(14)).foregroundStyle(Color.psMuted)
            Text(entry.reference.why)
              .font(PSFont.body(14)).foregroundStyle(Color.psText)
          }
          .multilineTextAlignment(.leading)
          .fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 4)
          Image(systemName: "chevron.right").font(.system(size: 16, weight: .bold))
            .foregroundStyle(Color.psText).accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .psBox()
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityHint("Opens the score sheet")
    }
  }
}

/// "US National Kubb Championship 2012 · 15 Jul 2012 · 20 turns".
func referenceDetail(_ entry: ReferenceEntry) -> String {
  let credit = entry.credit
  var parts: [String] = []
  if let event = credit.event { parts.append(event) }
  if let day = credit.date.flatMap(archiveDay) { parts.append(day) }
  let n = entry.read.analysis.rows.count
  parts.append(n == 1 ? "1 turn" : "\(n) turns")
  return parts.joined(separator: " · ")
}

/// An archive date, `2012-07-15`, as "15 Jul 2012".
func archiveDay(_ text: String) -> String? {
  // The archive writes local calendar days; read and show them in one zone so the day
  // never shifts.
  let utc = TimeZone(identifier: "UTC")!
  let f = DateFormatter()
  f.locale = Locale(identifier: "en_US_POSIX")
  f.timeZone = utc
  f.dateFormat = "yyyy-MM-dd"
  guard let date = f.date(from: text) else { return nil }
  var style = Date.FormatStyle.dateTime.day().month(.abbreviated).year()
  style.timeZone = utc
  return date.formatted(style)
}
