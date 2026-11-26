import CryptoKit
import Foundation

/// A copy of each finished game's notation file in a folder the scorer sees in Files:
/// iCloud Drive › Pitchside when iCloud Drive is on, else On My iPhone › Pitchside.
///
/// One direction only. The journal under Application Support stays the game; the copy
/// is written from `game.txt` and never read back. The folder holds exactly the
/// finished games scored on this phone: a game appears when it is over, is rewritten
/// when a correction changes its file, goes away when it is deleted in Pitchside or
/// reopened by a correction, and comes back if the scorer deletes it in Files.
/// Files the app did not write are never touched.
///
/// The app's own record of what it wrote (`mirror.json` beside the games) names each
/// copy per place, so names stay put and a move between the two places neither loses
/// nor duplicates a file.
public struct GameMirror: Sendable {
  /// Where the copies go.
  public struct Place: Sendable, Hashable {
    public enum Kind: String, Codable, Sendable { case iCloud = "icloud", local }
    public let kind: Kind
    /// The folder itself (the container's or the app's `Documents`).
    public let folder: URL
    /// For iCloud, which account's container it is: what the app wrote in one
    /// account's folder is never taken as its own in another's.
    public let account: String?
    public init(_ kind: Kind, folder: URL, account: String? = nil) {
      self.kind = kind
      self.folder = folder
      self.account = account
    }
    /// The key of this place's record in `mirror.json`.
    var scope: String { account.map { "\(kind.rawValue):\($0)" } ?? kind.rawValue }
  }

  /// One game to keep a copy of.
  public struct Entry: Sendable, Hashable {
    public let id: UUID
    public let created: Date
    /// The name before the date's prefix and the extension: "Mossy Stakes v Crooked Crowns".
    public let teams: String
    public let text: String
    public init(id: UUID, created: Date, teams: String, text: String) {
      self.id = id
      self.created = created
      self.teams = teams
      self.text = text
    }

    /// The finished games scored on this phone. Not files opened from elsewhere, not
    /// games still on the pitch (their file is a draft until the game is over).
    public static func finished(_ games: [Game], text: (UUID) -> String?) -> [Entry] {
      games.compactMap { game in
        guard game.status == .finished, game.origin == .pitchside, let t = text(game.id) else { return nil }
        let teams = "\(GameMirror.clean(game.team(.A).shownName(.A))) v \(GameMirror.clean(game.team(.B).shownName(.B)))"
        return Entry(id: game.id, created: game.created, teams: teams, text: t)
      }
    }
  }

  /// What one pass did.
  public struct Report: Sendable, Equatable {
    public var place: Place.Kind?
    /// The folder the copies are in.
    public var folder: URL?
    public var written: [String] = []
    public var moved: [String] = []
    public var removed: [String] = []
    public var problems: [String] = []
    public init(_ place: Place? = nil) {
      self.place = place?.kind
      folder = place?.folder
    }
  }

  struct Copy: Codable, Equatable {
    var name: String
    /// The name the copy was given before any collision number: a change means a rename.
    var base: String
    var digest: String
  }
  typealias Index = [String: [UUID: Copy]]

  /// The app's record of what it wrote (in Application Support, never in the folder).
  public let indexURL: URL
  let zone: TimeZone

  public init(index: URL, zone: TimeZone = .current) {
    indexURL = index
    self.zone = zone
  }

  // MARK: Names

  /// A team name safe in a file name: no path separators or characters Files and
  /// Windows refuse, no line breaks, no leading dots, at most 40 characters.
  static func clean(_ name: String) -> String {
    let refused = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters).union(.newlines)
    let mapped = name.precomposedStringWithCanonicalMapping.unicodeScalars.map {
      refused.contains($0) ? " " : Character($0)
    }
    var s = String(mapped).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    while s.hasPrefix(".") { s.removeFirst() }
    s = String(s.prefix(40)).trimmingCharacters(in: .whitespaces)
    return s.isEmpty ? "Team" : s
  }

  /// `2026-11-21 1405 Mossy Stakes v Crooked Crowns`: sorts by when it started.
  func base(_ entry: Entry) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = zone
    f.dateFormat = "yyyy-MM-dd HHmm"
    return "\(f.string(from: entry.created)) \(entry.teams)"
  }

  static func digest(_ text: String) -> String {
    SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  // MARK: A pass

  /// Brings `place` in line with `entries`, then takes the app's copies out of each
  /// place in `retiring` (the local folder once iCloud Drive has them). Never throws:
  /// what failed is in the report and is tried again on the next pass.
  @discardableResult
  public func sync(_ entries: [Entry], to place: Place, retiring: [Place] = []) -> Report {
    var report = Report(place)
    var index = loadIndex()
    defer { saveIndex(index, &report) }
    do {
      try FileManager.default.createDirectory(at: place.folder, withIntermediateDirectories: true)
    } catch {
      report.problems.append("The folder could not be made: \(error.localizedDescription)")
      return report
    }
    var mine = index[place.scope] ?? [:]
    let wanted = Set(entries.map(\.id))

    // Games deleted, or reopened by a correction.
    for (id, copy) in mine where !wanted.contains(id) {
      do {
        try remove(place.folder.appending(path: copy.name))
        mine[id] = nil
        report.removed.append(copy.name)
      } catch { report.problems.append("\(copy.name): \(error.localizedDescription)") }
    }

    // Oldest first, so a new game never takes an older one's name.
    for entry in entries.sorted(by: { ($0.created, $0.id.uuidString) < ($1.created, $1.id.uuidString) }) {
      let base = base(entry)
      let digest = Self.digest(entry.text)
      do {
        if let copy = mine[entry.id], copy.base == base {
          let url = place.folder.appending(path: copy.name)
          if copy.digest == digest && exists(url) { continue }
          try write(entry.text, to: url)
          mine[entry.id]?.digest = digest
          report.written.append(copy.name)
        } else {
          let taken = Set(mine.filter { $0.key != entry.id }.values.map { $0.name.lowercased() })
          let name = freeName(base, in: place.folder, taken: taken, text: entry.text)
          let url = place.folder.appending(path: name)
          if let old = mine[entry.id], exists(place.folder.appending(path: old.name)) {
            try move(place.folder.appending(path: old.name), to: url)
            report.moved.append(name)
          }
          if !(exists(url) && (try? String(contentsOf: url, encoding: .utf8)) == entry.text) {
            try write(entry.text, to: url)
            report.written.append(name)
          }
          mine[entry.id] = Copy(name: name, base: base, digest: digest)
        }
      } catch { report.problems.append("\(base): \(error.localizedDescription)") }
    }
    index[place.scope] = mine

    // The other place: its copies go once this place has them.
    for other in retiring where other.scope != place.scope {
      var theirs = index[other.scope] ?? [:]
      for (id, copy) in theirs where mine[id] != nil || !wanted.contains(id) {
        do {
          try remove(other.folder.appending(path: copy.name))
          theirs[id] = nil
          report.removed.append(copy.name)
        } catch { report.problems.append("\(copy.name): \(error.localizedDescription)") }
      }
      index[other.scope] = theirs.isEmpty ? nil : theirs
    }
    return report
  }

  /// `base.txt`, else `base 2.txt`, `base 3.txt`: not a name this place already gave
  /// another game, and not a file someone else put there (another phone's game, the
  /// scorer's own). A file with exactly this text is the same game and is adopted.
  func freeName(_ base: String, in folder: URL, taken: Set<String>, text: String) -> String {
    var n = 1
    while true {
      let name = n == 1 ? "\(base).txt" : "\(base) \(n).txt"
      n += 1
      if taken.contains(name.lowercased()) { continue }
      let url = folder.appending(path: name)
      if !exists(url) { return name }
      if (try? String(contentsOf: url, encoding: .utf8)) == text { return name }
    }
  }

  // MARK: Files, coordinated

  /// Also true for an iCloud file that is in the cloud but not on this phone.
  func exists(_ url: URL) -> Bool {
    let fm = FileManager.default
    if fm.fileExists(atPath: url.path) { return true }
    let placeholder = url.deletingLastPathComponent().appending(path: ".\(url.lastPathComponent).icloud")
    return fm.fileExists(atPath: placeholder.path)
  }

  private func coordinate(_ url: URL, _ options: NSFileCoordinator.WritingOptions, _ work: (URL) throws -> Void)
    throws
  {
    var failure: Error?
    var coordinationError: NSError?
    NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: options, error: &coordinationError) {
      do { try work($0) } catch { failure = error }
    }
    if let e = coordinationError ?? failure { throw e }
  }

  func write(_ text: String, to url: URL) throws {
    try coordinate(url, .forReplacing) { try Data(text.utf8).write(to: $0, options: .atomic) }
  }

  func remove(_ url: URL) throws {
    guard exists(url) else { return }
    try coordinate(url, .forDeleting) { try FileManager.default.removeItem(at: $0) }
  }

  func move(_ from: URL, to: URL) throws {
    var failure: Error?
    var coordinationError: NSError?
    let c = NSFileCoordinator(filePresenter: nil)
    c.coordinate(
      writingItemAt: from, options: .forMoving, writingItemAt: to, options: .forReplacing, error: &coordinationError
    ) { a, b in
      do {
        c.item(at: a, willMoveTo: b)
        try FileManager.default.moveItem(at: a, to: b)
        c.item(at: a, didMoveTo: b)
      } catch { failure = error }
    }
    if let e = coordinationError ?? failure { throw e }
  }

  // MARK: The record

  private struct Stored: Codable {
    var places: [String: [String: Copy]]
  }

  func loadIndex() -> Index {
    guard let data = try? Data(contentsOf: indexURL),
      let stored = try? JSONDecoder().decode(Stored.self, from: data)
    else { return [:] }
    return stored.places.mapValues { copies in
      Dictionary(uniqueKeysWithValues: copies.compactMap { id, c in UUID(uuidString: id).map { ($0, c) } })
    }
  }

  private func saveIndex(_ index: Index, _ report: inout Report) {
    let places = index.mapValues { copies in
      Dictionary(uniqueKeysWithValues: copies.map { ($0.key.uuidString, $0.value) })
    }
    do {
      let e = JSONEncoder()
      e.outputFormatting = [.sortedKeys, .prettyPrinted]
      try FileManager.default.createDirectory(
        at: indexURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try e.encode(Stored(places: places)).write(to: indexURL, options: .atomic)
    } catch { report.problems.append("The record of copies was not saved: \(error.localizedDescription)") }
  }
}

/// Runs the mirror off the main thread, one pass at a time, always with the latest
/// games: a request while a pass runs replaces any request still waiting. Asking never
/// waits, so a slow or failing iCloud never touches scoring.
public final class GameMirrorService: @unchecked Sendable {
  private let mirror: GameMirror
  private let local: URL
  private let cloud: @Sendable () -> GameMirror.Place?
  private let done: @Sendable (GameMirror.Report) -> Void
  private let queue = DispatchQueue(label: "com.throwingwood.pitchside.mirror", qos: .utility)
  private let lock = NSLock()
  private var pending: [GameMirror.Entry]?
  private var running = false

  /// `cloud` finds the iCloud place or nil (it may block: it runs on the mirror's
  /// queue); `local` is the app's own Documents folder; `done` hears each pass.
  public init(
    mirror: GameMirror, local: URL, cloud: @escaping @Sendable () -> GameMirror.Place?,
    done: @escaping @Sendable (GameMirror.Report) -> Void = { _ in }
  ) {
    self.mirror = mirror
    self.local = local
    self.cloud = cloud
    self.done = done
  }

  /// The iCloud Drive folder of the app's first ubiquity container, or nil when iCloud
  /// Drive is off, signed out, or the build has no iCloud entitlement (the simulator's
  /// unsigned builds). Blocks: never call it on the main thread.
  @Sendable public static func iCloudDocuments() -> GameMirror.Place? {
    let fm = FileManager.default
    guard let token = fm.ubiquityIdentityToken,
      let container = fm.url(forUbiquityContainerIdentifier: nil)
    else { return nil }
    return GameMirror.Place(
      .iCloud, folder: container.appending(path: "Documents", directoryHint: .isDirectory), account: account(token))
  }

  /// A short, stable name for the signed-in iCloud account: a digest of its archived
  /// identity token (Apple's documented way to compare accounts across launches).
  /// Should the archive ever change, the cost is small: a copy whose text matches is
  /// adopted rather than duplicated.
  static func account(_ token: any NSCoding & NSCopying & NSObjectProtocol) -> String {
    guard let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: false) else {
      return "unknown"
    }
    return String(GameMirror.digest(data.base64EncodedString()).prefix(16))
  }

  /// The app's own Documents folder (On My iPhone › Pitchside with file sharing on).
  public static func localDocuments() throws -> URL {
    try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
  }

  public func update(_ entries: [GameMirror.Entry]) {
    let start: Bool = lock.withLock {
      pending = entries
      if running { return false }
      running = true
      return true
    }
    if start { queue.async { self.drain() } }
  }

  /// Waits for the passes asked for so far (tests).
  public func wait() { queue.sync {} }

  private func drain() {
    while true {
      let next: [GameMirror.Entry]? = lock.withLock {
        let p = pending
        pending = nil
        if p == nil { running = false }
        return p
      }
      guard let entries = next else { return }
      let localPlace = GameMirror.Place(.local, folder: local)
      let report: GameMirror.Report
      if let place = cloud() {
        report = mirror.sync(entries, to: place, retiring: [localPlace])
      } else {
        report = mirror.sync(entries, to: localPlace)
      }
      done(report)
    }
  }
}
