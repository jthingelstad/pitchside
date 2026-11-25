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
        store = Demo.store(reopen: ProcessInfo.processInfo.arguments.contains("-PitchsideReopenDemo"))
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

enum AppSection: String, CaseIterable {
  case games = "Games"
  case roster = "Roster"
  case stats = "Stats"

  var symbol: String {
    switch self {
    case .games: "list.bullet.rectangle"
    case .roster: "person.2"
    case .stats: "chart.bar.xaxis"
    }
  }
}

/// Where a pushed screen goes.
enum Route: Hashable {
  case sheet(UUID)
  case stats(UUID)
}

/// Each section keeps its navigation and unfinished work when the scorer switches tabs.
struct RootView: View {
  @Environment(AppModel.self) private var model
  @State private var tab: AppSection = .games
  @State private var gamesPath: [Route] = []
  @State private var statsPath: [Route] = []
  @State private var newGame = false
  @State private var scoring: ScoringSession?
  @State private var engineNotes: [UUID: [RecordWarning]] = [:]
  @State private var resumeProblem: String?

  var body: some View {
    VStack(spacing: 0) {
      TabView(selection: $tab) {
        SwiftUI.Tab("Games", systemImage: AppSection.games.symbol, value: AppSection.games) {
          games.toolbarVisibility(.hidden, for: .tabBar)
        }
        SwiftUI.Tab("Roster", systemImage: AppSection.roster.symbol, value: AppSection.roster) {
          NavigationStack { RosterView() }.toolbarVisibility(.hidden, for: .tabBar)
        }
        SwiftUI.Tab("Stats", systemImage: AppSection.stats.symbol, value: AppSection.stats) {
          NavigationStack(path: $statsPath) {
            StatsTabView().navigationDestination(for: Route.self) { destination($0, back: "Stats") }
          }
          .toolbarVisibility(.hidden, for: .tabBar)
        }
      }
      TabBar(tab: $tab)
    }
    .background(Color.psGround)
    #if DEBUG
      .onAppear(perform: openForScreenshot)
    #endif
    .alert("Could not reopen the game", isPresented: .constant(resumeProblem != nil)) {
      Button("OK") { resumeProblem = nil }
    } message: { Text(resumeProblem ?? "") }
  }

  @ViewBuilder private var games: some View {
    if let session = scoring {
      ScorerView(session: session) {
        model.refresh()
        if session.scorer.state.over {
          engineNotes[session.id] = session.scorer.warnings
          gamesPath = [.sheet(session.id)]
        }
        scoring = nil
      }.id(session.id)
    } else if newGame {
      NewGameFlow(cancelled: { newGame = false }) { scorer in
        newGame = false
        scoring = ScoringSession(scorer)
      }
    } else {
      NavigationStack(path: $gamesPath) {
        HomeView(newGame: { newGame = true }, carryOn: { game in
          do { scoring = try ScoringSession(model.scorer(for: game)) }
          catch { resumeProblem = String(describing: error) }
        }, openSheet: { gamesPath.append(.sheet($0)) })
        .navigationDestination(for: Route.self) { destination($0, back: "Score sheet") }
      }
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
      case "scorer": if let g = model.playing.first { scoring = try? ScoringSession(model.scorer(for: g)) }
      default: break
      }
    }
  #endif

  @ViewBuilder func destination(_ route: Route, back: String) -> some View {
    switch route {
    case .sheet(let id):
      ScoreSheetView(id: id, engineNotes: engineNotes[id] ?? [], updateNotes: { engineNotes[id] = $0 }) { session in
        tab = .games
        gamesPath = []
        scoring = session
      }
    case .stats(let id): GameStatsView(id: id, back: back)
    }
  }
}

/// The live game or finished timeline currently open in Games.
final class ScoringSession: Identifiable {
  let scorer: LiveScorer
  var id: UUID { scorer.game.id }
  let showTimeline: Bool
  let initialTurn: Int?
  init(_ scorer: LiveScorer, showTimeline: Bool = false, initialTurn: Int? = nil) {
    self.initialTurn = initialTurn
    self.scorer = scorer
    self.showTimeline = showTimeline
  }
}

/// A fixed section switcher with scalable labels and a full-width touch target per tab.
struct TabBar: View {
  @Binding var tab: AppSection

  var body: some View {
    HStack(spacing: 0) {
      ForEach(AppSection.allCases, id: \.self) { section in
        let selected = tab == section
        Button {
          tab = section
        } label: {
          VStack(spacing: 3) {
            Image(systemName: section.symbol)
              .symbolVariant(selected ? .fill : .none)
              .font(.system(size: 19, weight: selected ? .semibold : .regular))
            Text(section.rawValue).font(PSFont.body(14, selected ? .bold : .regular, relativeTo: .footnote))
          }
          .foregroundStyle(selected ? Color.psSolid : Color.psMuted)
          .frame(maxWidth: .infinity, minHeight: 52)
          .overlay(alignment: .top) {
            if selected { Capsule().fill(Color.psSolid).frame(width: 24, height: 2) }
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("section-\(section.rawValue)")
        .accessibilityLabel(section.rawValue)
        .accessibilityValue("Tab")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
      }
    }
    .padding(.top, 3)
    .background(Color.psPlate.ignoresSafeArea(edges: .bottom))
    .overlay(alignment: .top) { Divider() }
  }
}
