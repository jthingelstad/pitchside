import Foundation

/// Pitchside's own lines of a game file until record mode writes the file (kubb-engine's
/// notation writer, with this app's turns). Today it writes the headers a Pitchside game
/// knows before its first turn, in the canonical order, so a game started here already
/// has a file anyone can read. The turns come from the scorer (`LiveScorer.notation`).
public enum GameFile {
  /// The app's name in `[Scored by "..."]`.
  public static func scoredBy(appVersion: String) -> String { "Kubb: Pitchside \(appVersion)" }

  /// The header Pitchside adds: the capture rows that were on (`turn who stand`). If they
  /// changed during the game, the value is every row that was on at some point, and each
  /// event in the log says which were on when it was written.
  public static let captureKey = "Pitchside:capture"

  /// A player's id in the file, as kubb-engine's `notation.assignIds` makes it
  /// (`notation.baseId`): the name lowercased, runs of spaces and hyphens to one `_`,
  /// anything not a-z or `_` dropped, no doubled or end underscores, `p` if nothing is
  /// left; a taken id gets `_b`, `_c`, ... (letters only, so the grammar accepts it).
  public static func baseId(_ name: String) -> String {
    var s = ""
    var gap = false
    for ch in name.lowercased() {
      if ch.isWhitespace || ch == "-" { gap = true; continue }
      if gap { s.append("_"); gap = false }
      if ch == "_" || ("a"..."z").contains(ch) { s.append(ch) }
    }
    while s.contains("__") { s = s.replacingOccurrences(of: "__", with: "_") }
    s = s.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    return s.isEmpty ? "p" : s
  }

  public static func assignIds(_ names: [String]) -> [String] {
    let letters = Array("bcdefghijklmnopqrstuvwxyz")
    var taken = Set<String>()
    return names.map { name in
      let base = baseId(name)
      var id = base
      var i = 1
      while taken.contains(id) {
        var suffix = ""
        var n = i
        repeat {
          suffix = String(letters[(n - 1) % letters.count]) + suffix
          n = (n - 1) / letters.count
        } while n != 0
        id = base + "_" + suffix
        i += 1
      }
      taken.insert(id)
      return id
    }
  }

  /// A name as the `Team A Players` header can carry it: commas and parentheses split
  /// that header, so they are left out.
  public static func headerName(_ name: String) -> String {
    let cleaned = name.filter { !",()\"\\[]".contains($0) }
    return cleaned.split(whereSeparator: \.isWhitespace).joined(separator: " ")
  }

  static func quote(_ value: String) -> String {
    "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
  }

  static func stamp(_ date: Date, in zone: TimeZone) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = zone
    f.dateFormat = "yyyy-MM-dd HH:mm"
    return f.string(from: date)
  }

  /// The file ids of each side's players, in throwing order (ids are unique across the
  /// whole game, Team A first, as the engine assigns them).
  public static func ids(for game: Game) -> [Side: [String]] {
    let a = game.team(.A).players.map(\.name)
    let b = game.team(.B).players.map(\.name)
    let all = assignIds(a + b)
    return [.A: Array(all.prefix(a.count)), .B: Array(all.dropFirst(a.count))]
  }

  /// The ids to saved-name keys, for `Game.playerKeys`.
  public static func playerKeys(for game: Game) -> [String: UUID] {
    let ids = ids(for: game)
    var keys: [String: UUID] = [:]
    for side in Side.allCases {
      for (id, player) in zip(ids[side] ?? [], game.team(side).players) {
        if let key = player.key { keys[id] = key }
      }
    }
    return keys
  }

  /// The headers of a Pitchside game, canonical order (pk-kubb-score's KEYS; the
  /// app's own key sorts after them).
  public static func headers(
    for game: Game, appVersion: String, captureEver: Capture? = nil, winner: Side? = nil, end: Date? = nil,
    zone: TimeZone = .current
  ) -> String {
    let ids = ids(for: game)
    let six = game.options.opening == .six
    var lines: [(String, String)] = [
      ("Notation", "2"),
      ("Start", stamp(game.created, in: zone)),
    ]
    if let end { lines.append(("End", stamp(end, in: zone))) }
    lines += [
      ("Surface", game.options.surface.title),
      ("Rules", six ? "U.S. Championship 4.0, six from the start" : "U.S. Championship 4.0, 2-4-6"),
      ("Base kubbs", "5"),
      ("Batons", "6"),
      ("Opening", six ? "6" : "2-4-6"),
    ]
    for side in Side.allCases {
      let team = game.team(side)
      lines.append(("Team \(side.rawValue)", headerName(team.shownName(side))))
      let players = zip(team.players, ids[side] ?? []).map { "\(headerName($0.name)) (\($1))" }
      if !players.isEmpty { lines.append(("Team \(side.rawValue) Players", players.joined(separator: ", "))) }
    }
    lines.append(("First", "Team \(game.options.first.rawValue)"))
    if let winner { lines.append(("Win", "Team \(winner.rawValue)")) }
    lines.append(("Scored by", scoredBy(appVersion: appVersion)))
    lines.append((captureKey, (captureEver ?? game.capture).headerValue))
    return lines.map { "[\($0) \(quote($1))]" }.joined(separator: "\n") + "\n"
  }

  /// A file name for the game: `2026-11-21-1405-birch-batons-v-pine-kings.txt`.
  public static func fileName(for game: Game, zone: TimeZone = .current) -> String {
    func slug(_ s: String) -> String {
      let lowered = s.lowercased().map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" }
      let slug = String(lowered).split(separator: "-").joined(separator: "-")
      return String(slug.prefix(80))
    }
    let when = stamp(game.created, in: zone).replacingOccurrences(of: " ", with: "-").replacingOccurrences(
      of: ":", with: "")
    let a = slug(game.team(.A).shownName(.A))
    let b = slug(game.team(.B).shownName(.B))
    return "\(when)-\(a.isEmpty ? "team-a" : a)-v-\(b.isEmpty ? "team-b" : b).txt"
  }
}
