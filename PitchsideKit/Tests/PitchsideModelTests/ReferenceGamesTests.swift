import CryptoKit
import Foundation
import Notation
import PDFKit
import PitchsideModel
import Testing

/// The reference games: archived Planet Kubb games bundled unmodified from pk-kubb-score's
/// pinned tag (scripts/vendor-notation.sh), shown read only beside the scorer's games.
@Suite struct ReferenceGamesTests {
  /// The pk-kubb-score checkout beside this repo, if there is one.
  private let pkScore = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().appending(path: "pk-kubb-score")

  private func sha(_ text: String) -> String {
    SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  @Test func atLeastTwelveListedGamesAreBundled() throws {
    let games = ReferenceGames.all()
    #expect(games.count >= 12)
    #expect(Set(games.map(\.id)).count == games.count)
    #expect(Set(games.map(\.file)).count == games.count)
    for game in games {
      #expect(!game.why.isEmpty, "\(game.file) says why it was chosen")
      #expect(ReferenceGame.id(for: game.file) == game.id, "the id is stable")
    }
    let folder = try #require(ReferenceGames.folder)
    let bundled = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".txt") }
    #expect(Set(bundled) == Set(games.map(\.file)), "every bundled file is listed, and every listed file bundled")
  }

  /// The bundle holds what SHA256SUMS records, and (with the checkout there) exactly what
  /// the tag's games/ has, byte for byte.
  @Test func bundledFilesMatchTheTag() throws {
    let folder = try #require(ReferenceGames.folder)
    let sums = try String(contentsOf: folder.appending(path: "SHA256SUMS"), encoding: .utf8)
    var recorded: [String: String] = [:]
    for line in sums.split(separator: "\n") {
      let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
      if parts.count == 2 { recorded[parts[1]] = parts[0] }
    }
    let games = ReferenceGames.all()
    #expect(recorded.count == games.count)
    for game in games { #expect(recorded[game.file] == sha(game.text), "\(game.file) is unmodified") }

    guard FileManager.default.fileExists(atPath: pkScore.appending(path: ".git").path) else { return }
    let source = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appending(path: "Sources/Notation/Vendor/SOURCE")
    let commit = try String(contentsOf: source, encoding: .utf8).split(separator: "\n")[1]
    for game in games {
      let git = Process()
      git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
      git.arguments = ["-C", pkScore.path, "cat-file", "blob", "\(commit):games/\(game.file)"]
      let out = Pipe()
      git.standardOutput = out
      git.standardError = Pipe()
      try git.run()
      let data = out.fileHandleForReading.readDataToEndOfFile()
      git.waitUntilExit()
      #expect(git.terminationStatus == 0, "\(game.file) is in the tag's games/")
      #expect(data == Data(game.text.utf8), "\(game.file) matches the tag")
    }
  }

  /// Every game reads cleanly through the vendored reader and opens everything an opened
  /// file gets: the sheet, play by play, the stats and the printable PDF.
  @Test func everyGameReadsWithoutWarnings() throws {
    let reader = try NotationReader()
    for reference in ReferenceGames.all() {
      let read = try reader.read(reference.text)
      let a = read.analysis
      #expect(read.grammar.ok, "\(reference.file): \(read.grammar.message ?? "")")
      #expect(a.warnings.isEmpty && a.turnWarnings == 0, "\(reference.file): \(a.warnings)")
      #expect(a.winner != nil, "\(reference.file) has a result")
      #expect(!a.rows.isEmpty)
      #expect(!GameReplay(a).steps.isEmpty, "\(reference.file) has a play by play")
      #expect(GameStats(read).sides.count == 2)
      let pdf = try #require(PDFDocument(data: ScoreSheetPDF.data(for: read, notation: reference.text)))
      #expect(pdf.pageCount >= 2)

      let credit = ReferenceCredit(headers: a.headers)
      #expect(credit.event != nil, "\(reference.file) names its event")
      #expect(credit.date != nil, "\(reference.file) has a date")
      #expect(credit.source?.host == "wiki.planetkubb.com", "\(reference.file) links its wiki page")
    }
  }

  /// The collection is read from the bundle only: making its games writes nothing to the
  /// store, and its players never count under a saved name.
  @Test func neverTouchesTheStoreOrCrossGameStats() throws {
    let store = try scratch()
    let reader = try NotationReader()
    let own = try sampleGame(store)
    try store.save(own)
    let roster = store.roster()
    func files() -> [String] {
      (FileManager.default.subpaths(atPath: store.root.path) ?? []).sorted()
    }
    let before = files()
    var pairs: [(Game, GameRead)] = []
    for reference in ReferenceGames.all() {
      let read = try reader.read(reference.text)
      let game = ReferenceGames.game(reference, read: read)
      #expect(game.isReference && game.isImported)
      #expect(game.status == .finished)
      #expect(game.playerKeys.isEmpty)
      #expect(game.id == reference.id)
      #expect(store.game(game.id) == nil)
      pairs.append((game, read))
    }
    #expect(files() == before)
    #expect(store.games().map(\.id) == [own.id])
    #expect(store.roster() == roster)
    #expect(NameTotals.across(pairs).isEmpty)
  }
}
