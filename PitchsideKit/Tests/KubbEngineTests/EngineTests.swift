import CryptoKit
import Foundation
import Testing

@testable import KubbEngine

let testAppVersion = "0.0-test"

func fixture(_ name: String) throws -> String {
  let url = try #require(Bundle.module.url(forResource: "Fixtures/" + name, withExtension: nil))
  return try String(contentsOf: url, encoding: .utf8)
}

@Suite struct EngineTests {
  /// The vendored Lua is what engine.json says, byte for byte (scripts/vendor-engine.sh
  /// check does the same from the shell).
  @Test func vendoredFilesMatchTheManifest() throws {
    let dir = try Engine.bundled()
    let engine = try Engine(appVersion: testAppVersion)
    #expect(engine.manifest.name == "kubb-engine")
    #expect(engine.manifest.files.count > 40)
    for (name, sha) in engine.manifest.files {
      let data = try Data(contentsOf: dir.appending(path: name))
      let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
      #expect(digest == sha, "\(name)")
    }
  }

  /// The engine boots as a host: its version is engine.json's, Lua is 5.4.5, and the
  /// label shows as `<app> (<engine>)`.
  @Test func theEngineStartsAsAHost() throws {
    let engine = try Engine(appVersion: "0.1")
    #expect(engine.engineVersion == engine.manifest.version)
    #expect(engine.engineVersion == (try Engine.bundledManifest().version))
    #expect(engine.luaVersion == "Lua 5.4.5")
    let label = VersionLabel(app: "0.1", engine: engine.engineVersion, build: "3")
    #expect(label.text == "0.1 (\(engine.engineVersion))")
    #expect(label.detail == "build 3")
  }

  /// A computer-against-computer match runs to its end on this engine and writes its game
  /// file with this app's label: the engine runs, maths and all.
  @Test func aMatchPlaysToItsFile() throws {
    let file = try EngineGame.play(seed: 11, maxTurns: 3)
    #expect(file.contains(#"[Notation "2"]"#))
    #expect(file.contains(#"[Scored by "Throwing Wood pitchside 0.0-test"]"#))
    #expect(file.contains(#"[Team A "Mossy Stakes"]"#))
  }

  @Test func refusalsAreErrors() throws {
    let engine = try Engine(appVersion: testAppVersion)
    #expect(throws: EngineError.self) { try engine.call("snapshot") }
    #expect(throws: EngineError.self) { try engine.call("noSuchMethod") }
  }
}

/// Plays a match through the engine's session with invented names and returns the game
/// file the engine writes at the end.
enum EngineGame {
  static func play(seed: Int, maxTurns: Int) throws -> String {
    let engine = try Engine(appVersion: testAppVersion)
    let options = """
      {"mode":"match","seed":\(seed),"cpu":"both","maxTurns":\(maxTurns),\
      "teams":{"A":{"name":"Mossy Stakes","players":["Wren","Tomas"]},\
      "B":{"name":"Crooked Crowns","players":["Ivo","Maren"]}},\
      "start":{"year":2026,"month":11,"day":21,"hour":14,"min":5}}
      """
    _ = try engine.call("new", json: options)
    var need = try engine.call("need")
    var frames = 0
    while !need.contains(#""kind":"over""#) && frames < 200_000 {
      _ = try engine.call("frame", json: #"{"dt":0.05}"#)
      need = try engine.call("need")
      frames += 1
    }
    struct Over: Decodable {
      struct File: Decodable { let text: String }
      let file: File
    }
    return try JSONDecoder().decode(Over.self, from: Data(need.utf8)).file.text
  }
}
