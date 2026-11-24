import Foundation
import KubbEngine
import Notation
import Testing

@testable import PitchsideModel

/// kubb-engine v1.1.0's record-mode games (Fixtures/record-games.json): each one's setup,
/// events, and the file and warnings the engine's own `record.build` gave on desktop Lua.
struct RecordFixture: Decodable {
  let name: String
  let setup: JSONValue
  let events: [JSONValue]
  let text: String
  let warnings: [String]
  let winner: Side?
  let how: String?

  static let all: [RecordFixture] = {
    let url = Bundle.module.url(forResource: "Fixtures/record-games", withExtension: "json")!
    return try! JSONDecoder().decode([RecordFixture].self, from: Data(contentsOf: url))
  }()

  static func named(_ name: String) -> RecordFixture { all.first { $0.name == name }! }

  /// The fixture's setup as a Pitchside game, in UTC (the start is a wall-clock time).
  var game: Game {
    let teams = setup["teams"]!.object!
    func team(_ s: String) -> Team {
      let t = teams[s]!
      let players = t["players"]!.array!.map { p in TeamPlayer(name: p.string ?? p["name"]!.string!) }
      return Team(name: t["name"]!.string!, players: players)
    }
    var created = Date(timeIntervalSince1970: 0)
    if let st = setup["start"] {
      var c = DateComponents()
      c.year = Int(st["year"]!.number!)
      c.month = Int(st["month"]!.number!)
      c.day = Int(st["day"]!.number!)
      c.hour = Int(st["hour"]?.number ?? 0)
      c.minute = Int(st["min"]?.number ?? 0)
      var cal = Calendar(identifier: .gregorian)
      cal.timeZone = .gmt
      created = cal.date(from: c)!
    }
    let cap = setup["capture"]?.object ?? [:]
    return Game(
      created: created, teams: [.A: team("A"), .B: team("B")],
      options: GameOptions(
        opening: GameOptions.Opening(rawValue: setup["opening"]?.string ?? "2-4-6")!,
        surface: GameOptions.Surface(rawValue: setup["surface"]?.string ?? "grass")!,
        wind: GameOptions.Wind(rawValue: setup["wind"]?.string ?? "off")!,
        first: Side(rawValue: setup["first"]?.string ?? "A")!),
      capture: Capture(
        who: cap["players"]?.bool ?? false, stand: cap["pitch"]?.bool ?? false, lay: cap["lay"]?.bool ?? false,
        stance: cap["stance"]?.bool ?? false),
      event: setup["event"]?.string, location: setup["location"]?.string)
  }
}

/// A scorer on a fresh store, its times off (the fixtures' events carry their own).
func replay(_ f: RecordFixture, useFixtureSetup: Bool) throws -> (RecordScorer, GameStore) {
  let store = try scratch()
  let game = f.game
  try store.save(game)
  let scorer = try RecordScorer(
    game: game, store: store, appVersion: "0.1", zone: .gmt, setup: useFixtureSetup ? f.setup : nil,
    stampTimes: false)
  for e in f.events { try scorer.add(e.object!) }
  return (scorer, store)
}

@Suite struct RecordBridgeTests {
  /// The worked example (RECORD.md; the canvas's turn 5 `5. k:3I A k:3F d:B o:B k:B d:=
  /// o:K`), its setup made from a Pitchside game, gives the engine's file byte for byte.
  @Test func theWorkedGameIsTheSameFileByteForByte() throws {
    let f = RecordFixture.named("example")
    let (scorer, store) = try replay(f, useFixtureSetup: false)
    #expect(scorer.text == f.text)
    #expect(store.fileText(scorer.game.id) == f.text)
    #expect(Data(scorer.text.utf8) == Data(f.text.utf8))
    #expect(scorer.text.contains("5. k:3I A k:3F d:B o:B k:B d:= o:K\n"))
    #expect(scorer.state.over && scorer.winner == .A && scorer.state.how == "king")
    #expect(store.game(scorer.game.id)?.status == .finished)
    #expect(scorer.warnings.isEmpty)
  }

  /// Every fixture game, replayed through the scorer, gives the engine's file and the
  /// same warnings.
  @Test(arguments: RecordFixture.all.map(\.name))
  func everyFixtureGame(_ name: String) throws {
    let f = RecordFixture.named(name)
    let (scorer, _) = try replay(f, useFixtureSetup: true)
    #expect(Data(scorer.text.utf8) == Data(f.text.utf8))
    #expect(scorer.warnings.map(\.code) == f.warnings)
    #expect(scorer.winner == f.winner)
  }

  /// The example's file reads back in pk-kubb-score's kubb.js with no warnings.
  @Test func theFileReadsBackClean() throws {
    let (scorer, _) = try replay(RecordFixture.named("example"), useFixtureSetup: false)
    let read = try NotationReader().read(scorer.text)
    #expect(read.analysis.warnings.isEmpty && read.analysis.turnWarnings == 0)
    #expect(read.analysis.winner == .A)
  }
}

@Suite struct RecordLogTests {
  /// Opening the game again rebuilds from the log alone: the same state and file.
  @Test func logRebuildGivesTheSameState() throws {
    let f = RecordFixture.named("example")
    let store = try scratch()
    var game = f.game
    game.created = Date(timeIntervalSince1970: 1_790_000_000)
    try store.save(game)
    let scorer = try RecordScorer(game: game, store: store, appVersion: "0.1", zone: .gmt)
    for e in f.events.prefix(20) { try scorer.add(e.object!) }
    let again = try RecordScorer(game: store.game(game.id)!, store: store, appVersion: "0.1", zone: .gmt)
    #expect(again.state == scorer.state)
    #expect(again.text == scorer.text)
    #expect(again.records == scorer.records)
    #expect(again.rows == scorer.rows)
    // every log line is a record event with its id
    let log = try store.log(game.id)
    #expect(log.events.first?.kind == "start")
    #expect(log.events.dropFirst().allSatisfy { $0.kind == RecordScorer.Kind.record && $0.payload["id"] != nil })
    #expect(Set(scorer.records.compactMap { $0["id"]?.string }).count == 20)
  }

  /// Undo drops the last event (a new log line), and a reopen agrees.
  @Test func undoDropsTheLastEvent() throws {
    let f = RecordFixture.named("example")
    let (scorer, store) = try replay(f, useFixtureSetup: false)
    let before = scorer.text
    try scorer.undo()
    #expect(!scorer.state.over)
    #expect(scorer.state.next.kind == "baton" && scorer.state.next.kingShot == true)
    #expect(scorer.records.count == f.events.count - 1)
    #expect(store.game(scorer.game.id)?.status == .playing)
    let again = try RecordScorer(game: store.game(scorer.game.id)!, store: store, appVersion: "0.1", zone: .gmt)
    #expect(again.state == scorer.state)
    #expect(try store.log(scorer.game.id).events.last?.kind == RecordScorer.Kind.undo)
    try scorer.add(f.events.last!.object!)
    #expect(scorer.text == before)
    // nothing to undo is not an error
    let empty = try RecordScorer(game: f.game, store: try scratch(), appVersion: "0.1")
    try empty.undo()
    #expect(empty.records.isEmpty)
  }

  /// Editing an earlier event rewrites the record events and rebuilds; what came after
  /// changes, and the preview shows it before anything is kept.
  @Test func editingAnEarlierEvent() throws {
    let f = RecordFixture.named("example")
    let (scorer, store) = try replay(f, useFixtureSetup: false)
    // turn 1's second baton (dana's base kubb) was a miss after all
    let id = scorer.records[1]["id"]!.string!
    let edit = RecordEdit.replace(id: id, event: RecordEvent.baton(by: "dana"))
    let preview = try scorer.preview(edit)
    #expect(preview.notation!.text.contains("1. k:B d:-\n"))
    #expect(scorer.text == f.text)  // the preview touched nothing
    try scorer.edit(edit)
    #expect(scorer.text.contains("1. k:B d:-\n"))
    // turn 2 had only one kubb to throw in now; two were recorded: a warning, no refusal
    #expect(!scorer.warnings.isEmpty)
    #expect(scorer.records[1]["id"]?.string == id)
    let again = try RecordScorer(game: store.game(scorer.game.id)!, store: store, appVersion: "0.1", zone: .gmt)
    #expect(again.text == scorer.text)
    // and back
    try scorer.edit(.replace(id: id, event: f.events[1].object!))
    #expect(scorer.text == f.text)
  }

  /// The timeline puts each event in its turn.
  @Test func timelineGroupsEventsByTurn() throws {
    let (scorer, _) = try replay(RecordFixture.named("example"), useFixtureSetup: false)
    let turns = try scorer.timeline()
    #expect(turns.map(\.turn) == [1, 2, 3, 4, 5])
    #expect(turns.map(\.side) == [.A, .B, .A, .B, .A])
    #expect(turns[0].events.count == 2)
    #expect(turns[4].events.map(\.type) == ["toss", "toss", "toss", "advantage"] + Array(repeating: "baton", count: 6))
    #expect(turns[4].row?.line == "5. k:3I A k:3F d:B o:B k:B d:= o:K")
  }

  /// A rule breach is recorded as thrown and only warns.
  @Test func aRuleBreachOnlyWarns() throws {
    let store = try scratch()
    let game = RecordFixture.named("example").game
    let scorer = try RecordScorer(game: game, store: store, appVersion: "0.1")
    // the king felled in turn 1 with every kubb standing
    let w = try scorer.add(RecordEvent.baton(king: true, by: "kim"))
    #expect(w.map(\.code) == ["rule"])
    #expect(scorer.lastWarnings == w)
    #expect(scorer.state.over && scorer.winner == .B && scorer.state.how == "king toppled early")
  }
}

@Suite struct CaptureSwitchTests {
  /// Each switch, alone, from the start: what the file writes for it.
  @Test(arguments: [
    (Capture(), "turns", ["1. B B", "5. 3I A 3F B B B = K"], ["k:", "@", "^", "*"]),
    (Capture(who: true), "players", ["1. k:B d:B"], ["@", "^", "*"]),
    (Capture(stand: true), "pitch", ["@a 3,1s", "*b 1,3 4,3"], ["k:", "^"]),
    (Capture(stance: true), "stance", ["^a 2.50,4.00 2.50,4.00"], ["k:", "@", "*"]),
    (Capture(lay: true), "turns", ["1. B B"], ["~", "k:"]),
  ])
  func eachSwitch(_ capture: Capture, header: String, has: [String], hasNot: [String]) throws {
    let f = RecordFixture.named("example")
    let store = try scratch()
    var game = f.game
    game.capture = capture
    try store.save(game)
    let scorer = try RecordScorer(game: game, store: store, appVersion: "0.1", zone: .gmt, stampTimes: false)
    for e in f.events { try scorer.add(e.object!) }
    #expect(scorer.text.contains(#"[Pitchside:capture "\#(header)"]"#))
    for line in has { #expect(scorer.text.contains(line), "\(line)") }
    let body = scorer.text.components(separatedBy: "\n\n").last!
    for token in hasNot { #expect(!body.contains(token), "\(token)") }
    #expect(try NotationReader().read(scorer.text).analysis.warnings.isEmpty)
  }

  /// A switch changed between turns starts with the turn that has nothing in it yet.
  @Test func changingBetweenTurns() throws {
    let f = RecordFixture.named("example")
    let store = try scratch()
    let game = f.game
    try store.save(game)
    let scorer = try RecordScorer(game: game, store: store, appVersion: "0.1", zone: .gmt, stampTimes: false)
    for e in f.events.prefix(2) { try scorer.add(e.object!) }  // turn 1 done
    #expect(scorer.captureAppliesNow)
    try scorer.setCapture(Capture(who: false, stand: true, stance: true))
    for e in f.events.dropFirst(2) { try scorer.add(e.object!) }
    #expect(scorer.text.contains("1. k:B d:B\n"))
    #expect(scorer.text.contains("2. 2I 2F B B -\n"))
    #expect(store.game(game.id)?.capture == Capture(who: false, stand: true, stance: true))
    #expect(try NotationReader().read(scorer.text).analysis.warnings.isEmpty)
  }

  /// Names in other scripts and with accents keep ids of their own.
  @Test func playerIdsDoNotCollapse() throws {
    #expect(RecordScorer.playerId("Åsa") == "asa")
    #expect(RecordScorer.playerId("Øyvind") == "oyvind")
    #expect(RecordScorer.playerId("Дмитрий") != "p")
    #expect(RecordScorer.playerId("さくら") != "p")
    let store = try scratch()
    let game = Game(
      teams: [
        .A: Team(name: "Ängar", players: [TeamPlayer(name: "Дмитрий"), TeamPlayer(name: "さくら")]),
        .B: Team(name: "Fjäll", players: [TeamPlayer(name: "Åsa"), TeamPlayer(name: "Asa")]),
      ])
    let scorer = try RecordScorer(game: game, store: store, appVersion: "0.1")
    let ids = (scorer.state.side(.A).players + scorer.state.side(.B).players).map(\.id)
    #expect(Set(ids).count == 4)
    #expect(!ids.contains("p"))
  }
}

@Suite struct PitchFrameTests {
  typealias W = PitchFrame.World

  /// A world point goes to the screen and back in every view.
  @Test(arguments: PitchFrame.View.allCases)
  func roundTrip(_ view: PitchFrame.View) {
    for p in [W(x: 0, y: 0), W(x: 5, y: 8), W(x: 1.4, y: 5.6), W(x: 3.9, y: 2.1)] {
      let back = PitchFrame.world(PitchFrame.screen(p, in: view), in: view)
      #expect(abs(back.x - p.x) < 1e-9 && abs(back.y - p.y) < 1e-9)
    }
  }

  /// Where the corners land: Team A's left centre-line stake (the notation's origin) and
  /// the baselines, in each view.
  @Test func corners() {
    let origin = W(x: 0, y: 4)
    #expect(PitchFrame.screen(origin, in: .behindA) == .init(u: 0, v: 0.5))
    #expect(PitchFrame.screen(origin, in: .behindB) == .init(u: 1, v: 0.5))
    #expect(PitchFrame.screen(origin, in: .sideline) == .init(u: 0.5, v: 0))
    // Team A's baseline: the bottom from behind A, the top from behind B, the left side-on
    #expect(PitchFrame.screen(W(x: 2.5, y: 0), in: .behindA).v == 1)
    #expect(PitchFrame.screen(W(x: 2.5, y: 0), in: .behindB).v == 0)
    #expect(PitchFrame.screen(W(x: 2.5, y: 0), in: .sideline).u == 0)
  }

  /// A tap becomes the notation's frame: the same kubb in Team B's half, tapped in each
  /// view, is the same across and depth (the origin does not move with the view).
  @Test func tapsMapToTheNotationFrame() {
    let kubb = RecordPoint(across: 1.4, depth: 1.6)
    let w = PitchFrame.world(kubb, half: .B)
    #expect(w == W(x: 1.4, y: 5.6))
    for view in PitchFrame.View.allCases {
      let tap = PitchFrame.screen(w, in: view)
      let n = PitchFrame.notation(PitchFrame.world(tap, in: view))!
      #expect(n.half == .B)
      #expect(abs(n.point.across - 1.4) < 1e-9 && abs(n.point.depth - 1.6) < 1e-9)
    }
    // the screen positions differ: from behind A it is left of centre and up; from
    // behind B right of centre and down; side-on, right of the centre line and up
    let fromA = PitchFrame.screen(w, in: .behindA)
    #expect(abs(fromA.u - 0.28) < 1e-9 && abs(fromA.v - 0.3) < 1e-9)
    #expect(PitchFrame.screen(w, in: .behindB).u > 0.5)
    #expect(PitchFrame.screen(w, in: .sideline).u > 0.5)
    // Team A's half
    let a = PitchFrame.notation(W(x: 4.1, y: 1.8))!
    #expect(a.half == .A && a.point == RecordPoint(across: 4.1, depth: 2.2))
    #expect(PitchFrame.notation(W(x: 5.2, y: 1)) == nil)
  }

  /// A stance is in the thrower's own half and snaps to the baseline or the advantage
  /// line.
  @Test func stances() {
    let s = PitchFrame.stance(W(x: 2.6, y: 2.7), side: .A)!
    #expect(s == RecordPoint(across: 2.6, depth: 1.3))
    #expect(PitchFrame.stance(W(x: 2.6, y: 5), side: .A) == nil)
    #expect(PitchFrame.stance(W(x: 2.6, y: 8.2), side: .B) == RecordPoint(across: 2.6, depth: 4.2))
    #expect(PitchFrame.snap(RecordPoint(across: 2.5, depth: 3.8), advantageDepth: nil).depth == 4)
    #expect(PitchFrame.snap(RecordPoint(across: 2.5, depth: 1.5), advantageDepth: 1.3).depth == 1.3)
    #expect(PitchFrame.snap(RecordPoint(across: 2.5, depth: 2.2), advantageDepth: 1.3).depth == 2.2)
  }
}

@Suite struct JournalRecoveryTests {
  @Test func interruptedUTF8AndLegacySetup() throws {
    let store = try scratch()
    let game = try sampleGame(store)
    let legacy = try store.log(game.id)
    try legacy.append(kind: "start", capture: game.capture)
    let handle = try FileHandle(forWritingTo: legacy.url)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data([123, 34, 0xf0, 0x9f]))
    try handle.close()
    let scorer = try RecordScorer(game: game, store: store, appVersion: "0.1")
    try scorer.add(RecordEvent.baton())
    let bytes = try Data(contentsOf: legacy.url)
    let line = try JSONDecoder().decode(JSONValue.self, from: Data(bytes.split(separator: 10).last!))
    #expect(line["type"] == "baton" && line["id"] != nil)
    let reopened = try RecordScorer(game: game, store: store, appVersion: "0.2")
    #expect(reopened.text == scorer.text)
    #expect(reopened.setup == scorer.setup)
  }
}
