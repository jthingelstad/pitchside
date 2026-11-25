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
  /// Why the engine did not start, if it did not (shown in Games).
  let engineProblem: String?
  @ObservationIgnored private let reader: NotationReader?
  @ObservationIgnored let scorers: ScorerFactory

  private(set) var recoveryProblem: String?
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
    scorers = RecordScorer.Factory(appVersion: app)
    for game in store.games() where store.needsReplay(game) {
      do { _ = try scorers.scorer(for: game, store: store) }
      catch { recoveryProblem = "Could not rebuild a saved game. \(error)" }
    }
    refresh()
  }

  func refresh() {
    let saved = store.games()
    // JavaScriptCore runs when the files change, outside SwiftUI's lazy row layout.
    for game in saved where game.status == .finished {
      guard let text = store.fileText(game.id), reads[game.id]?.text != text else { continue }
      reads[game.id] = (text, try? reader?.read(text))
    }
    games = saved
    roster = store.roster().sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  /// Every unfinished game, newest first.
  var playing: [Game] { games.filter { $0.status == .playing } }
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
    reads[game.id]?.read
  }

  /// Read the last saved throw, including a draft on the pitch, without opening a scorer.
  func playByPlay(_ game: Game, analysis cached: Analysis? = nil) throws -> GameReplay {
    let analysis: Analysis
    if let cached { analysis = cached }
    else if let reader, let text = store.fileText(game.id) { analysis = try reader.read(text).analysis }
    else { throw NotationError.notAGame("The game file could not be read.") }
    let replay = game.isImported ? GameReplay(analysis) : try GameReplay(analysis, journal: store.log(game.id))
    guard !replay.steps.isEmpty else { throw NotationError.notAGame("There are no recorded plays yet.") }
    return replay
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

  /// A new game's draft: the last game's options, empty teams, and the capture a new
  /// game starts with: the turn and where kubbs stand (the design review's call).
  func draft() -> Game {
    let last = games.first { !$0.isImported }
    return Game(options: last?.options ?? GameOptions(), capture: Capture(stand: true))
  }

  func saveDraft(_ game: Game) {
    try? store.save(game)
  }

  func discardDraft(_ game: Game) {
    if store.game(game.id)?.status == .setup { try? store.delete(game.id) }
    refresh()
  }

  /// Starts scoring: the game goes on the pitch and its log starts. The game's start is
  /// now (the file's `Start`).
  func start(_ game: Game) throws -> LiveScorer {
    var game = game
    game.created = .now
    try store.save(game)
    let scorer = try scorers.scorer(for: game, store: store)
    refresh()
    return scorer
  }

  func scorer(for game: Game) throws -> LiveScorer {
    try scorers.scorer(for: game, store: store)
  }
}
