import Foundation
import Testing

@testable import KubbEngine

// kubb-engine's golden matches, played here and compared hash by hash with the corpus
// its reference platform (wasmoon: Lua and musl's maths in WebAssembly) recorded, as
// throwingwood-ios's GoldenTests do. Equal hashes mean this phone's engine is the web's,
// bit for bit, so a game scored here can later be shown on the same engine.

struct Corpus: Decodable {
  struct Winner: Decodable, Equatable {
    let winner: String
    let turns: Int
    let thrown: Int
    let hits: Int
  }
  struct Action: Decodable, Equatable {
    let type: String
    let hash: String
  }
  struct Match: Decodable {
    let name: String
    let start: String
    let turns: Int
    let winner: Winner
    let actions: [Action]
  }
  let version: String
  let tune: String
  let matches: [Match]

  static let shared: Corpus = {
    let url = Bundle.module.url(forResource: "Fixtures/golden/hashes", withExtension: "json")!
    return try! JSONDecoder().decode(Corpus.self, from: Data(contentsOf: url))
  }()
}

struct MathProbe: Decodable {
  struct Probe: Decodable {
    let fn: String
    let args: [String]
    let bits: String
  }
  let probes: [Probe]
}

func drivingEngine() throws -> Engine {
  let engine = try Engine(
    directory: Engine.bundled(), appVersion: testAppVersion,
    extra: ["tests/golden/drive": fixture("golden/drive.lua"), "test/probe": fixture("probe.lua")])
  try engine.run(
    """
    import "tests/golden/drive"
    import "test/probe"
    function goldenMatch(i)
      local m = tw.golden.matches()[tonumber(i)]
      return tw.web.json.encode(tw.golden.play(m))
    end
    """, name: "=test")
  return engine
}

@Suite struct GoldenTests {
  @Test func corpusIsForTheVendoredEngine() throws {
    let engine = try Engine(appVersion: testAppVersion)
    #expect(Corpus.shared.version == engine.engineVersion, "run scripts/vendor-engine.sh sync")
    #expect(Corpus.shared.tune == Engine.tune)
    #expect(Corpus.shared.matches.count > 10)
  }

  /// The maths: arguments where Apple's libm and musl's differ in the last bit give the
  /// web's answers here.
  @Test func mathIsTheWebsMath() throws {
    let engine = try drivingEngine()
    let probe = try JSONDecoder().decode(MathProbe.self, from: Data(fixture("math-probe.json").utf8))
    let cases = probe.probes.map { [$0.fn] + $0.args }
    let text = try engine.callGlobal("mathProbe", String(decoding: JSONEncoder().encode(cases), as: UTF8.self))
    let got = try JSONDecoder().decode([String].self, from: Data(text.utf8))
    #expect(got.count == probe.probes.count)
    for (p, bits) in zip(probe.probes, got) {
      #expect(bits == p.bits, "\(p.fn)(\(p.args.joined(separator: ", ")))")
    }
  }

  @Test(arguments: 0..<21) func matchPlaysAsOnTheReference(_ index: Int) throws {
    let corpus = Corpus.shared
    let want = try #require(corpus.matches.indices.contains(index) ? corpus.matches[index] : nil)
    let engine = try drivingEngine()
    let text = try engine.callGlobal("goldenMatch", String(index + 1))
    struct Played: Decodable {
      let name: String
      let start: String
      let turns: Int?
      let winner: Corpus.Winner?
      let actions: [Corpus.Action]
    }
    let got = try JSONDecoder().decode(Played.self, from: Data(text.utf8))
    #expect(got.name == want.name)
    let agree = zip(got.actions, want.actions).prefix { $0 == $1 }.count
    if got.actions.count != want.actions.count || agree != want.actions.count {
      Issue.record(
        "\(want.name) leaves the corpus at action \(agree + 1): \(agree) of \(want.actions.count) agree")
    }
    #expect(got.turns == want.turns)
    #expect(got.winner == want.winner)
  }
}
