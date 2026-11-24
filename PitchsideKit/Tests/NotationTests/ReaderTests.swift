import Foundation
import Testing

@testable import KubbEngine
@testable import Notation
@testable import PitchsideModel

func fixture(_ name: String) throws -> String {
  let url = try #require(Bundle.module.url(forResource: "Fixtures/" + name, withExtension: nil))
  return try String(contentsOf: url, encoding: .utf8)
}

/// The pk-kubb-score checkout beside this repo (its archived games are real people's
/// games and stay out of this repository: tests read them in place, and skip without it).
let pkScore = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  .deletingLastPathComponent().deletingLastPathComponent().appending(path: "pk-kubb-score")

let vendorDir = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  .appending(path: "Sources/Notation/Vendor")

func which(_ tool: String) -> URL? {
  let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
  for dir in path.split(separator: ":") {
    let url = URL(fileURLWithPath: String(dir)).appending(path: tool)
    if FileManager.default.isExecutableFile(atPath: url.path) { return url }
  }
  return nil
}

/// kubb.js's `analyze` under node, on the same vendored file, as JSON.
func nodeAnalyze(_ file: URL) throws -> String {
  let node = try #require(which("node"))
  let script = """
    import { analyze } from \(String(reflecting: vendorDir.appending(path: "kubb.js").absoluteString));
    import { readFileSync } from 'node:fs';
    process.stdout.write(JSON.stringify(analyze(readFileSync(process.argv[1], 'utf8'))));
    """
  let p = Process()
  p.executableURL = node
  p.arguments = ["--input-type=module", "-e", script, file.path]
  let out = Pipe()
  p.standardOutput = out
  try p.run()
  let data = out.fileHandleForReading.readDataToEndOfFile()
  p.waitUntilExit()
  #expect(p.terminationStatus == 0)
  return String(decoding: data, as: UTF8.self)
}

func object(_ json: String) throws -> NSDictionary {
  try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? NSDictionary)
}

@Suite struct ReaderTests {
  @Test func theReaderLoads() throws {
    let reader = try NotationReader()
    #expect(reader.isCanonical("[Notation \"2\"]\n"))
  }

  /// A file the engine wrote (Playdate, invented names): read, scored and canonical.
  @Test func anEngineFileReads() throws {
    let reader = try NotationReader()
    let read = try reader.read(fixture("six-pack-v-full-house.txt"))
    let a = read.analysis
    #expect(read.grammar.ok)
    #expect(a.name(.A) == "Six Pack")
    #expect(a.winner == .B)
    #expect(a.winHow == "king")
    #expect(a.endTurn == 12)
    #expect(a.rows.count == 12)
    #expect(a.players.count == 12)
    #expect(a.players.first { $0.id == "wes" }?.name == "Wes")
    let stats = GameStats(read)
    #expect(stats.side(.B)?.zeroBaseAt != nil)
    #expect(stats.side(.B)?.zeroBaseSpot == GameRead.Figures.Spot(turn: 10, baton: 6))
  }

  /// A game the engine plays now (the vendored engine, computer against computer, invented names)
  /// writes a file the reader reads with no warnings and the grammar accepts.
  @Test func aGameThisEngineWritesReads() throws {
    let engine = try Engine(appVersion: "0.0-test")
    let options = """
      {"mode":"match","seed":7,"cpu":"both",\
      "teams":{"A":{"name":"Mossy Stakes","players":[{"name":"Wren"},{"name":"Tomas"}]},\
      "B":{"name":"Crooked Crowns","players":[{"name":"Ivo"},{"name":"Maren"}]}},\
      "start":{"year":2026,"month":11,"day":21,"hour":14,"min":5}}
      """
    _ = try engine.call("new", json: options)
    var need = try engine.call("need")
    var frames = 0
    while !need.contains(#""kind":"over""#) && frames < 400_000 {
      _ = try engine.call("frame", json: #"{"dt":0.05}"#)
      need = try engine.call("need")
      frames += 1
    }
    struct Over: Decodable {
      struct File: Decodable { let text: String }
      let file: File
    }
    let text = try JSONDecoder().decode(Over.self, from: Data(need.utf8)).file.text
    let reader = try NotationReader()
    let read = try reader.read(text)
    #expect(read.grammar.ok, "\(read.grammar.message ?? "")")
    #expect(read.analysis.warnings.isEmpty, "\(read.analysis.warnings)")
    #expect(read.analysis.turnWarnings == 0)
    #expect(read.analysis.winner != nil)
    #expect(read.analysis.name(.B) == "Crooked Crowns")
    #expect(read.analysis.players.map(\.name).contains("Maren"))
  }

  @Test func kidGamesAreRefused() throws {
    let reader = try NotationReader()
    let kid = """
      [Notation "2"]
      [Rules "Kid rules, 2-4-6"]
      [Base kubbs "3"]
      [Team A "Small Fry"]
      [Team B "Tiny Tots"]

      1. B -
      """
    #expect(throws: NotationError.kidRules) { try reader.read(kid) }
  }

  @Test func notAGameIsSaidPlainly() throws {
    let reader = try NotationReader()
    #expect(throws: NotationError.self) { try reader.read("hello there\n") }
  }

  @Test func canonicalizeReportsTheGrammar() throws {
    let reader = try NotationReader()
    let (text, _) = try reader.canonicalize(fixture("six-pack-v-full-house.txt"))
    #expect(reader.isCanonical(text))
    #expect(throws: NotationError.self) { try reader.canonicalize("1. 3Q?? !!\n[x") }
  }

  /// The reader in JavaScriptCore gives exactly what kubb.js gives under node, for the
  /// engine's file and for every 25th archived real game (read in place from the
  /// pk-kubb-score checkout, never copied here).
  @Test func javaScriptCoreAgreesWithNode() throws {
    guard which("node") != nil else { return }
    let reader = try NotationReader()
    var files = [try #require(Bundle.module.url(forResource: "Fixtures/six-pack-v-full-house.txt", withExtension: nil))]
    let games = pkScore.appending(path: "games")
    if let names = try? FileManager.default.contentsOfDirectory(atPath: games.path) {
      let sorted = names.filter { $0.hasSuffix(".txt") }.sorted()
      #expect(sorted.count >= 75, "expected the archived games in the pk-kubb-score checkout")
      files += stride(from: 0, to: sorted.count, by: 25).map { games.appending(path: sorted[$0]) }
    }
    for file in files {
      let text = try String(contentsOf: file, encoding: .utf8)
      let mine = try object(reader.analyzeJSON(text))
      let theirs = try object(nodeAnalyze(file))
      #expect(mine == theirs, "\(file.lastPathComponent)")
      // And the stats the app shows come through the Swift types unchanged.
      let stats = GameStats(try reader.read(text))
      let nodeStats = try #require(theirs["stats"] as? [String: [String: Any]])
      for side in stats.sides {
        let s = try #require(nodeStats[side.side.rawValue])
        #expect(side.hits == s["hits"] as? Int)
        #expect(side.batons == s["batons"] as? Int)
        #expect(side.effF == s["effF"] as? Int)
        #expect(side.effI == s["effI"] as? Int)
        #expect(side.zeroBaseAt == s["zeroBaseAt"] as? Int)
        #expect(side.hitPct == s["hitPct"] as? Double ?? (s["hitPct"] as? Int).map(Double.init))
      }
    }
  }
}
