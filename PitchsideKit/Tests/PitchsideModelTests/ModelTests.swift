import Foundation
import Notation
import Testing

@testable import PitchsideModel

func scratch() throws -> GameStore {
  let dir = FileManager.default.temporaryDirectory.appending(path: "pitchside-tests-\(UUID().uuidString)")
  return try GameStore(root: dir)
}

func sampleGame(_ store: GameStore) throws -> Game {
  let wren = try store.save(name: "Wren")
  let ivo = try store.save(name: "Ivo")
  return Game(
    teams: [
      .A: Team(name: "Mossy Stakes", players: [TeamPlayer(name: "Wren", key: wren.key), TeamPlayer(name: "Tomas")]),
      .B: Team(name: "Crooked Crowns", players: [TeamPlayer(name: "Ivo", key: ivo.key)]),
    ],
    options: GameOptions(opening: .six, surface: .sand, wind: .light, first: .B),
    capture: Capture(who: true, stand: true))
}

@Suite struct RosterTests {
  @Test func namesAreKeptOnceAndKeepTheirKey() throws {
    let store = try scratch()
    let a = try store.save(name: "  Wren ")
    let b = try store.save(name: "wren")
    #expect(a.key == b.key)
    #expect(store.roster().map(\.name) == ["Wren"])
    try store.rename(a.key, to: "Wren B")
    #expect(store.roster().first?.key == a.key)
    #expect(store.roster().first?.name == "Wren B")
    try store.forget(a.key)
    #expect(store.roster().isEmpty)
  }
}

@Suite struct GameTests {
  @Test func gamesRoundTrip() throws {
    let store = try scratch()
    let game = try sampleGame(store)
    try store.save(game)
    let back = try #require(store.game(game.id))
    #expect(back.teams == game.teams)
    #expect(back.options == game.options)
    #expect(back.capture == game.capture)
    #expect(store.games().map(\.id) == [game.id])
  }

  @Test func teamsHoldOneToSix() {
    var team = Team(name: "X")
    #expect(!team.isReady)
    team.players = (1...6).map { TeamPlayer(name: "P\($0)") }
    #expect(team.isReady && team.isFull)
    team.players.append(TeamPlayer(name: "P7"))
    #expect(!team.isReady)
    #expect(Team().shownName(.B) == "Team B")
  }

  @Test func captureRowsMapToTheHeader() {
    var c = Capture()
    #expect(c.headerValue == "turn")
    c.set(.who, true)
    c.set(.stance, true)
    c.set(.turn, false)  // the turn is always recorded
    #expect(c.headerValue == "turn who stance")
    #expect(Capture(headerValue: "turn who stance") == c)
    #expect(Capture.Row.allCases.map(\.glyph) == ["5.", "k:", "@ *", "~", "^"])
  }
}

@Suite struct GameFileTests {
  /// Ids as kubb-engine's notation.assignIds makes them.
  @Test func idsAreTheEnginesIds() {
    #expect(GameFile.assignIds(["Wren", "wren", "Wren", "Anna-Lena  Berg", "Zoë 2", "!!"]) == [
      "wren", "wren_b", "wren_c", "anna_lena_berg", "zo", "p",
    ])
  }

  @Test func headersReadBackAndAreCanonical() throws {
    let store = try scratch()
    let game = try sampleGame(store)
    let zone = try #require(TimeZone(identifier: "America/Chicago"))
    let text = GameFile.headers(for: game, appVersion: "0.1", zone: zone)
    #expect(text.contains(#"[Team A Players "Wren (wren), Tomas (tomas)"]"#))
    #expect(text.contains(#"[Pitchside:capture "turn who stand"]"#))
    #expect(text.contains(#"[Scored by "Kubb: Pitchside 0.1"]"#))
    #expect(text.contains(#"[Opening "6"]"#))
    let reader = try NotationReader()
    #expect(reader.isCanonical(text), "\(text)")
    #expect(GameFile.playerKeys(for: game).count == 2)
  }

  @Test func namesThatWouldSplitTheHeaderAreCleaned() {
    #expect(GameFile.headerName("Kim (the elder), Jr") == "Kim the elder Jr")
  }
}

@Suite struct EventLogTests {
  @Test func appendsSurviveAReopen() throws {
    let store = try scratch()
    let id = UUID()
    let log = try store.log(id)
    try log.append(kind: GameEvent.Kind.start, capture: Capture())
    try log.append(kind: "placeholder", capture: Capture(who: true), payload: .object(["a": .number(1)]))
    let again = try store.log(id)
    #expect(again.events.count == 2)
    #expect(again.events[1].payload == .object(["a": .number(1)]))
    #expect(again.events[1].capture == "turn who")
    #expect(again.events.map(\.seq) == [1, 2])
  }

  /// A crash mid-write leaves a torn last line: it is dropped, and the next append starts
  /// a fresh line.
  @Test func aTornLastLineIsDropped() throws {
    let store = try scratch()
    let id = UUID()
    let log = try store.log(id)
    try log.append(kind: "start", capture: Capture())
    let handle = try FileHandle(forWritingTo: store.logURL(id))
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(#"{"seq":2,"ki"#.utf8))
    try handle.close()
    let reopened = try store.log(id)
    #expect(reopened.events.count == 1)
    try reopened.append(kind: "placeholder", capture: Capture())
    #expect(try store.log(id).events.map(\.seq) == [1, 2])
  }

  @Test func damageInTheMiddleIsAnError() throws {
    let store = try scratch()
    let id = UUID()
    try FileManager.default.createDirectory(
      at: store.logURL(id).deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("nonsense\n{\"seq\":1}\n".utf8).write(to: store.logURL(id))
    #expect(throws: EventLogError.damaged(line: 1)) { try store.log(id) }
  }
}

@Suite struct OpenFileTests {
  let sixPack = """
    [Notation "2"]
    [Surface "Grass"]
    [Rules "U.S. Championship 4.0, 2-4-6"]
    [Team A "Mossy Stakes"]
    [Team A Players "Wren (wren), Tomas (tomas)"]
    [Team B "Crooked Crowns"]
    [Team B Players "Ivo (ivo)"]
    [First "Team A"]

    1. wren:B tomas:-
    2. ivo:1I ivo:F ivo:B ivo:- ivo:-
    3. wren:2I wren:2F tomas:B wren:B tomas:B wren:B wren:K
    """

  @Test func anOpenedFileIsKeptAsAFinishedGame() throws {
    let store = try scratch()
    let reader = try NotationReader()
    let game = try store.open(fileText: sixPack, named: "x.txt", reader: reader)
    #expect(game.status == .finished)
    #expect(game.isImported)
    #expect(game.team(.A).players.map(\.name) == ["Wren", "Tomas"])
    #expect(store.fileText(game.id) == sixPack)
    let stats = GameStats(try reader.read(sixPack))
    let a = try #require(stats.side(.A))
    #expect(a.hits == 7)
    #expect(a.batons == 8)
    #expect(a.zeroBaseAt == 7)
    #expect(a.efficiency == 1)
    #expect(a.zeroBaseSpot == GameRead.Figures.Spot(turn: 3, baton: 5))
    // From the baseline: turn 1's two batons and turn 3's five after the field fell.
    #expect(a.fromEight == GameRead.Figures.Tally(batons: 7, hits: 6))
    #expect(try reader.read(sixPack).analysis.turnWarnings == 0)
  }

  @Test func totalsAddUpAcrossGamesPerSavedName() throws {
    let store = try scratch()
    let reader = try NotationReader()
    let wren = try store.save(name: "Wren")
    var g1 = try store.open(fileText: sixPack, named: "1.txt", reader: reader)
    var g2 = try store.open(fileText: sixPack, named: "2.txt", reader: reader)
    g1.playerKeys = ["wren": wren.key]
    g2.playerKeys = ["wren": wren.key]
    let read = try reader.read(sixPack)
    let totals = NameTotals.across([(g1, read), (g2, read)])
    let w = try #require(totals[wren.key])
    #expect(w.games == 2)
    #expect(w.wins == 2)
    #expect(w.batons == 10)
    #expect(w.hits == 10)
  }

  @Test func kidFilesAreNotKept() throws {
    let store = try scratch()
    let reader = try NotationReader()
    #expect(throws: NotationError.kidRules) {
      try store.open(fileText: "[Rules \"Kid rules, six from the start\"]\n\n1. B\n", named: "k.txt", reader: reader)
    }
    #expect(store.games().isEmpty)
  }
}
