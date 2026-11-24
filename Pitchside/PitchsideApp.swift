import PitchsideDesign
import PitchsideModel
import SwiftUI

@main
struct PitchsideApp: App {
  @State private var model: AppModel

  init() {
    let store: GameStore
    #if DEBUG
      // `-PitchsideDemo`: a separate folder filled with invented games, for screenshots.
      if ProcessInfo.processInfo.arguments.contains("-PitchsideDemo") {
        store = Demo.store()
      } else {
        store = (try? GameStore.standard()) ?? Demo.scratchStore()
      }
    #else
      store = try! GameStore.standard()
    #endif
    _model = State(initialValue: AppModel(store: store))
  }

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(model)
        .tint(Color.psText)
    }
  }
}

// MARK: - Root and the tab bar

enum Tab: String, CaseIterable {
  case games = "Games"
  case roster = "Roster"
  case stats = "Stats"

  var symbol: String {
    switch self {
    case .games: "line.3.horizontal"
    case .roster: "person"
    case .stats: "chart.bar.xaxis"
    }
  }
}

/// Where a pushed screen goes.
enum Route: Hashable {
  case sheet(UUID)
  case stats(UUID)
}

/// The tab bar is available on Games, the score sheet and Stats. Roster has its own back button.
struct RootView: View {
  @Environment(AppModel.self) private var model
  @State private var tab: Tab = .games
  @State private var gamesPath: [Route] = []
  @State private var statsPath: [Route] = []
  @State private var newGame = false
  @State private var scoring: ScoringSession?
  @State private var engineNotes: [UUID: [RecordWarning]] = [:]
  @State private var resumeProblem: String?

  var body: some View {
    VStack(spacing: 0) {
      Group {
        switch tab {
        case .games:
          NavigationStack(path: $gamesPath) {
            HomeView(
              newGame: { newGame = true },
              carryOn: { game in
                do { scoring = try ScoringSession(model.scorer(for: game)) }
                catch { resumeProblem = String(describing: error) }
              }
            )
            .navigationDestination(for: Route.self) { destination($0, back: "Score sheet") }
          }
        case .roster:
          NavigationStack { RosterView { tab = .games } }
        case .stats:
          NavigationStack(path: $statsPath) {
            StatsTabView().navigationDestination(for: Route.self) { destination($0, back: "Stats") }
          }
        }
      }
      .frame(maxHeight: .infinity)
      if tab != .roster { TabBar(tab: $tab) }
    }
    .background(Color.psGround)
    #if DEBUG
      .onAppear(perform: openForScreenshot)
    #endif
    .alert("Could not reopen the game", isPresented: .constant(resumeProblem != nil)) {
      Button("OK") { resumeProblem = nil }
    } message: { Text(resumeProblem ?? "") }
    .fullScreenCover(isPresented: $newGame) {
      NewGameFlow { scorer in
        newGame = false
        scoring = ScoringSession(scorer)
      }
      .environment(model)
    }
    .fullScreenCover(item: $scoring) { session in
      ScorerView(session: session) {
        model.refresh()
        if session.scorer.state.over {
          engineNotes[session.id] = session.scorer.warnings
          tab = .games
          gamesPath = [.sheet(session.id)]
        }
        scoring = nil
      }
      .environment(model)
    }
  }

  #if DEBUG
    /// `-PitchsideScreen <name>` opens one screen at launch (screenshots of the demo).
    func openForScreenshot() {
      let args = ProcessInfo.processInfo.arguments
      guard let i = args.firstIndex(of: "-PitchsideScreen"), i + 1 < args.count else { return }
      let game = model.finished.first { !$0.isImported }
      switch args[i + 1] {
      case "sheet": if let game { gamesPath = [.sheet(game.id)] }
      case "stats": if let game { gamesPath = [.sheet(game.id), .stats(game.id)] }
      case "imported": if let g = model.finished.first(where: \.isImported) { gamesPath = [.sheet(g.id)] }
      case "roster": tab = .roster
      case "statstab": tab = .stats
      case "teams", "thisgame": newGame = true
      case "scorer": if let g = model.playing { scoring = try? ScoringSession(model.scorer(for: g)) }
      default: break
      }
    }
  #endif

  @ViewBuilder func destination(_ route: Route, back: String) -> some View {
    switch route {
    case .sheet(let id):
      ScoreSheetView(id: id, engineNotes: engineNotes[id] ?? []) { scorer in
        gamesPath = []
        scoring = ScoringSession(scorer)
      }
    case .stats(let id): GameStatsView(id: id, back: back)
    }
  }
}

/// The scorer in a cover: identified so it can be presented as an item.
final class ScoringSession: Identifiable {
  let scorer: LiveScorer
  var id: UUID { scorer.game.id }
  init(_ scorer: LiveScorer) { self.scorer = scorer }
}

/// The design's tab bar: three words with icons; the chosen one is solid ink.
struct TabBar: View {
  @Binding var tab: Tab

  var body: some View {
    HStack(spacing: 8) {
      ForEach(Array(Tab.allCases.enumerated()), id: \.element) { i, t in
        let on = t == tab
        Button {
          tab = t
        } label: {
          VStack(spacing: 2) {
            Image(systemName: t.symbol).font(.system(size: 18, weight: .bold))
            Text(t.rawValue).font(PSFont.body(14, .bold, relativeTo: .footnote))
          }
          .foregroundStyle(on ? Color.psOnSolid : Color.psText)
          .frame(maxWidth: .infinity, minHeight: 52)
          .background(on ? Color.psSolid : .clear, in: RoundedRectangle(cornerRadius: 6))
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(t.rawValue)
        .accessibilityValue("tab, \(i + 1) of \(Tab.allCases.count)")
        .accessibilityAddTraits(on ? [.isSelected] : [])
      }
    }
    .padding(.horizontal, 10)
    .padding(.top, 6)
    .padding(.bottom, 4)
    .background(Color.psGround)
    .overlay(alignment: .top) { Rectangle().fill(Color.psLine).frame(height: 3) }
  }
}
