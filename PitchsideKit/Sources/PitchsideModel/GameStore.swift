import Foundation
import Notation

/// Pitchside's files on this phone, in one folder (Application Support/Pitchside by
/// default; tests pass their own). Plain files, no database, no network:
///
///     roster.json              the saved names
///     games/<uuid>/game.json   a game: teams, options, capture, status
///     games/<uuid>/events.jsonl  its append-only event log (EventLog)
///     games/<uuid>/game.txt    its Planet Kubb Notation file (opened, or regenerated after every action)
///     mirror.json              the copies of finished games written where Files shows them (GameMirror)
///
/// Not thread safe: use one from one place (the app's main actor).
public final class GameStore {
  public let root: URL
  private let fm = FileManager.default

  private static let encoder: JSONEncoder = {
    let e = JSONEncoder()
    e.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
    e.dateEncodingStrategy = .iso8601
    return e
  }()
  private static let decoder: JSONDecoder = {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601
    return d
  }()

  public init(root: URL) throws {
    self.root = root
    try fm.createDirectory(at: root.appending(path: "games"), withIntermediateDirectories: true)
  }

  /// The app's own folder.
  public static func standard() throws -> GameStore {
    let base = try FileManager.default.url(
      for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    return try GameStore(root: base.appending(path: "Pitchside"))
  }

  // MARK: Roster

  private var rosterURL: URL { root.appending(path: "roster.json") }

  public func roster() -> [SavedName] {
    guard let data = try? Data(contentsOf: rosterURL) else { return [] }
    return (try? Self.decoder.decode([SavedName].self, from: data)) ?? []
  }

  public func saveRoster(_ names: [SavedName]) throws {
    try Self.encoder.encode(names).write(to: rosterURL, options: .atomic)
  }

  /// Adds a typed name to the roster, or returns the saved one with the same name
  /// (ignoring case and spaces at the ends).
  @discardableResult
  public func save(name: String) throws -> SavedName {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    var names = roster()
    if let same = names.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) { return same }
    let saved = SavedName(name: trimmed)
    names.append(saved)
    try saveRoster(names)
    return saved
  }

  public func rename(_ key: UUID, to name: String) throws {
    var names = roster()
    guard let i = names.firstIndex(where: { $0.key == key }) else { return }
    names[i].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    try saveRoster(names)
  }

  /// Forgets a saved name. Games keep the name they were played with.
  public func forget(_ key: UUID) throws {
    try saveRoster(roster().filter { $0.key != key })
  }

  // MARK: Games

  func folder(_ id: UUID) -> URL { root.appending(path: "games/\(id.uuidString)") }
  public func logURL(_ id: UUID) -> URL { folder(id).appending(path: "events.jsonl") }
  public func fileURL(_ id: UUID) -> URL { folder(id).appending(path: "game.txt") }

  /// Every game, newest first.
  public func games() -> [Game] {
    let dirs = (try? fm.contentsOfDirectory(at: root.appending(path: "games"), includingPropertiesForKeys: nil)) ?? []
    return dirs.compactMap { dir in
      guard let data = try? Data(contentsOf: dir.appending(path: "game.json")) else { return nil }
      return try? Self.decoder.decode(Game.self, from: data)
    }.sorted { $0.created > $1.created }
  }

  public func game(_ id: UUID) -> Game? {
    guard let data = try? Data(contentsOf: folder(id).appending(path: "game.json")) else { return nil }
    return try? Self.decoder.decode(Game.self, from: data)
  }

  /// A crash after syncing an observation can leave one or both derived files behind it.
  public func needsReplay(_ game: Game) -> Bool {
    guard !game.isImported else { return false }
    func changed(_ url: URL) -> Date? {
      try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
    guard let logged = changed(logURL(game.id)) else { return false }
    let files = [fileURL(game.id), folder(game.id).appending(path: "game.json")]
    return files.contains { (changed($0) ?? .distantPast) < logged }
  }

  /// Writes the game's own file (teams, options, capture, status).
  public func save(_ game: Game) throws {
    var game = game
    game.updated = .now
    try fm.createDirectory(at: folder(game.id), withIntermediateDirectories: true)
    try Self.encoder.encode(game).write(to: folder(game.id).appending(path: "game.json"), options: .atomic)
  }

  /// The game still on the pitch, if any (the newest game being scored).
  public func playing() -> Game? { games().first { $0.status == .playing } }

  public func log(_ id: UUID) throws -> EventLog { try EventLog(url: logURL(id)) }

  /// The game's notation file, if it has one.
  public func fileText(_ id: UUID) -> String? { try? String(contentsOf: fileURL(id), encoding: .utf8) }

  public func writeFile(_ text: String, for id: UUID) throws {
    try fm.createDirectory(at: folder(id), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: fileURL(id), options: .atomic)
  }

  /// Keeps a game file opened from elsewhere as a finished game of its own. Throws the
  /// reader's refusal (a Kid game, or no turns) before keeping anything.
  public func open(fileText text: String, named name: String, reader: NotationReader) throws -> Game {
    let read = try reader.read(text)
    let game = Self.game(from: read, origin: .file(name))
    try writeFile(text, for: game.id)
    try save(game)
    return game
  }

  /// A finished game as a file describes it: its teams, options and capture. Nothing is
  /// saved; `open` keeps it, reference games stay in the bundle.
  public static func game(from read: GameRead, origin: Game.Origin, id: UUID = UUID()) -> Game {
    let a = read.analysis
    var teams: [Side: Team] = [:]
    for side in Side.allCases {
      let players = a.players.filter { $0.side == side }.map { TeamPlayer(name: $0.name ?? $0.id) }
      teams[side] = Team(name: a.name(side), players: players)
    }
    let created = start(a.headers["Start"] ?? a.headers["Event date"]) ?? .now
    var options = GameOptions(first: a.first)
    if a.rules.opening.first == 6 || a.headers["Rules"]?.contains("six from the start") == true { options.opening = .six }
    if let s = a.headers["Surface"].flatMap({ GameOptions.Surface(rawValue: $0.lowercased()) }) { options.surface = s }
    let capture = a.headers[GameFile.captureKey].map(Capture.init(headerValue:)) ?? Capture(who: !a.players.isEmpty)
    return Game(
      id: id, created: created, origin: origin, status: .finished, teams: teams, options: options,
      capture: capture, playerKeys: [:], event: a.headers["Event"], location: a.headers["Location"])
  }

  public func delete(_ id: UUID) throws {
    if fm.fileExists(atPath: folder(id).path) { try fm.removeItem(at: folder(id)) }
  }

  static func start(_ text: String?) -> Date? {
    guard let text else { return nil }
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    for format in ["yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
      f.dateFormat = format
      if let d = f.date(from: String(text.prefix(format.count))) { return d }
    }
    return nil
  }
}
