import Foundation
import KubbEngine
import Notation
import Observation
import PitchsideModel

/// The app's state: the files on this phone, the notation reader, and the engine's
/// version. One, on the main actor.
@MainActor @Observable
final class AppModel {
  let store: GameStore
  let version: VersionLabel
  /// Why the engine did not start, if it did not (shown on Home; nothing else needs it
  /// until record mode).
  let engineProblem: String?
  @ObservationIgnored private(set) var reader: NotationReader?
  @ObservationIgnored let scorers: ScorerFactory

  private(set) var games: [Game] = []
  private(set) var roster: [SavedName] = []
  @ObservationIgnored private var reads: [UUID: (text: String, read: GameRead?)] = [:]

  init(store: GameStore) {
    self.store = store
    let info = Bundle.main.infoDictionary ?? [:]
    let app = info["CFBundleShortVersionString"] as? String ?? "0.1"
    let build = info["CFBundleVersion"] as? String
    // Boot the engine once to prove it runs here, and show its own version.
    var engineVersion = "?"
    var problem: String?
    do {
      engineVersion = try Engine(appVersion: app).engineVersion
    } catch {
      problem = "\(error)"
      engineVersion = (try? Engine.bundledManifest().version) ?? "?"
    }
    version = VersionLabel(app: app, engine: engineVersion, build: build)
    engineProblem = problem
    reader = try? NotationReader()
    scorers = PlaceholderScorer.Factory(appVersion: app)
    refresh()
  }

  func refresh() {
    games = store.games()
    roster = store.roster().sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  /// The game still on the pitch.
  var playing: Game? { games.first { $0.status == .playing } }
  /// Finished games, newest first.
  var finished: [Game] { games.filter { $0.status == .finished } }

  func game(_ id: UUID) -> Game? { games.first { $0.id == id } ?? store.game(id) }

  // MARK: Files and reading

  /// The game's notation: its file, or for a game on the pitch what its scorer has so far.
  func text(_ game: Game) -> String {
    if let text = store.fileText(game.id) { return text }
    if game.status == .playing, let scorer = try? scorers.scorer(for: game, store: store) {
      return (try? scorer.notation()) ?? ""
    }
    return GameFile.headers(for: game, appVersion: version.app)
  }

  /// The game read by pk-kubb-score's reader (nil when it has no turns yet).
  func read(_ game: Game) -> GameRead? {
    let text = text(game)
    if let cached = reads[game.id], cached.text == text { return cached.read }
    let read = try? reader?.read(text)
    reads[game.id] = (text, read)
    return read
  }

  /// Opens a game file from elsewhere. Throws a refusal the user can read.
  func open(url: URL) throws -> Game {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    let data = try Data(contentsOf: url)
    guard let text = String(data: data, encoding: .utf8) else {
      throw NotationError.notAGame("This file is not text Pitchside can read.")
    }
    guard let reader else { throw NotationError.reader("not loaded") }
    let game = try store.open(fileText: text, named: url.lastPathComponent, reader: reader)
    refresh()
    return game
  }

  func delete(_ game: Game) {
    try? store.delete(game.id)
    reads[game.id] = nil
    refresh()
  }

  // MARK: Roster

  @discardableResult
  func save(name: String) -> SavedName? {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let saved = try? store.save(name: trimmed)
    refresh()
    return saved
  }

  func rename(_ key: UUID, to name: String) {
    try? store.rename(key, to: name)
    refresh()
  }

  func forget(_ key: UUID) {
    try? store.forget(key)
    refresh()
  }

  /// Every saved name's totals across finished games.
  func totals() -> [UUID: NameTotals] {
    NameTotals.across(finished.compactMap { g in read(g).map { (g, $0) } })
  }

  // MARK: A new game

  /// A new game's draft: the last game's options and capture, empty teams.
  func draft() -> Game {
    let last = games.first { !$0.isImported }
    return Game(options: last?.options ?? GameOptions(), capture: last?.capture ?? Capture())
  }

  func saveDraft(_ game: Game) {
    try? store.save(game)
  }

  func discardDraft(_ game: Game) {
    if store.game(game.id)?.status == .setup { try? store.delete(game.id) }
    refresh()
  }

  /// Starts scoring: the game goes on the pitch and its log starts.
  func start(_ game: Game) throws -> LiveScorer {
    var game = game
    game.playerKeys = GameFile.playerKeys(for: game)
    try store.save(game)
    let scorer = try scorers.scorer(for: game, store: store)
    refresh()
    return scorer
  }

  func scorer(for game: Game) throws -> LiveScorer {
    try scorers.scorer(for: game, store: store)
  }
}
