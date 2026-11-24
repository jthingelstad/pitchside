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
  @State private var importing = false
  @State private var refusal: String?
  @State private var opened: UUID?

  var body: some View {
    VStack(spacing: 0) {
      header
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          if let problem = model.recoveryProblem { Text(problem).psHelp() }
          if let game = model.playing { stillOnThePitch(game) }
          Button("New game", action: newGame)
            .buttonStyle(.ps)
            .accessibilityHint("Teams, then this game's switches")
          recent
          Button("Open a game file") { importing = true }
            .buttonStyle(.quiet)
            .accessibilityHint("A Planet Kubb Notation text file")
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
          opened = game.id
        } catch let error as NotationError {
          refusal = error.description
        } catch {
          refusal = "Pitchside could not read that file."
        }
      case .failure: break
      }
    }
    .alert("Not opened", isPresented: .constant(refusal != nil), presenting: refusal) { _ in
      Button("OK") { refusal = nil }
    } message: { Text($0) }
    .navigationDestination(item: $opened) { ScoreSheetView(id: $0) }
  }

  var header: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Kubb")
        .font(PSFont.body(14, .bold, relativeTo: .subheadline)).tracking(0.84).textCase(.uppercase)
        .foregroundStyle(Color.psText)
      Text("Pitchside")
        .font(PSFont.display(42, relativeTo: .largeTitle))
        .foregroundStyle(Color.psText)
        .accessibilityAddTraits(.isHeader)
      Text("Score a real game, throw by throw.")
        .font(PSFont.body(16))
        .foregroundStyle(Color.psText)
    }
    .accessibilityElement(children: .combine)
    .padding(.horizontal, 16)
    .padding(.top, 24)
    .padding(.bottom, 14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.psWood.ignoresSafeArea(edges: .top))
    .overlay(alignment: .bottom) { Rectangle().fill(Color.psLine).frame(height: 3) }
  }

  func stillOnThePitch(_ game: Game) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Still on the pitch").psKick()
      ForEach(Side.allCases, id: \.self) { side in
        HStack {
          TeamLabel(side: side, name: game.team(side).shownName(side), display: true)
          Spacer()
          Text(game.team(side).players.count == 1 ? "1 player" : "\(game.team(side).players.count) players")
            .font(PSFont.body(15, .bold))
            .foregroundStyle(Color.psText)
        }
      }
      Text("Started \(game.created.formatted(date: .omitted, time: .shortened)). \(firstLine(game))")
        .font(PSFont.body(16))
        .foregroundStyle(Color.psText)
        .fixedSize(horizontal: false, vertical: true)
      Button("Carry on") { carryOn(game) }
        .buttonStyle(.psSolid)
        .accessibilityHint("Back to the scorer")
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .psCard()
  }

  func firstLine(_ game: Game) -> String {
    let first = game.options.first
    return "\(game.team(first).shownName(first)) throw first."
  }

  @ViewBuilder var recent: some View {
    Text("Recent games").psKick()
    if model.finished.isEmpty {
      Text("Games you score or open show up here.").psHelp()
    }
    ForEach(model.finished.prefix(12)) { game in
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
      Text("Games and names stay on this phone. Pitchside sends nothing anywhere.").psHelp()
    }
    .accessibilityElement(children: .combine)
    .padding(.top, 8)
  }
}
