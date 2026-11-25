#if DEBUG
  import Foundation
  import Notation
  import PitchsideModel

  /// Invented games for screenshots and trying the app (`-PitchsideDemo`, debug builds
  /// only): a separate folder, refilled at each launch. Every name is made up.
  enum Demo {
    static func scratchStore() -> GameStore {
      try! GameStore(root: FileManager.default.temporaryDirectory.appending(path: "PitchsideScratch"))
    }

    static func store(reopen: Bool = false) -> GameStore {
      let root = FileManager.default.temporaryDirectory.appending(path: "PitchsideDemo")
      if reopen { return try! GameStore(root: root) }
      try? FileManager.default.removeItem(at: root)
      let store = try! GameStore(root: root)
      let names = ["Wren", "Tomas", "Ivo", "Maren", "Kit", "Odile", "Bram", "Linnea", "Lark", "Nell", "Kim", "Dana", "Ole", "Sam", "Lee"]
      var keys: [String: UUID] = [:]
      for n in names { keys[n] = try! store.save(name: n).key }
      func p(_ n: String) -> TeamPlayer { TeamPlayer(name: n, key: keys[n]) }
      let cal = Calendar(identifier: .gregorian)
      func day(_ d: Int, _ h: Int) -> Date {
        cal.date(from: DateComponents(timeZone: .current, year: 2026, month: 11, day: d, hour: h, minute: 5))!
      }

      // Scored here, with who threw.
      var one = Game(
        created: day(21, 14), status: .finished,
        teams: [.A: Team(name: "Mossy Stakes", players: [p("Wren"), p("Tomas")]),
                .B: Team(name: "Crooked Crowns", players: [p("Ivo"), p("Maren")])],
        options: GameOptions(), capture: Capture(who: true))
      one.playerKeys = GameFile.playerKeys(for: one)
      try! store.writeFile(
        GameFile.headers(for: one, appVersion: "0.1", winner: .A, end: day(21, 15)) + "\n" + g1Turns + "\n",
        for: one.id)
      try! store.save(one)

      // Scored here, the turn only.
      let two = Game(
        created: day(21, 11), status: .finished,
        teams: [.A: Team(name: "Birch Batons", players: [p("Kit")]),
                .B: Team(name: "Dizzy Dowels", players: [p("Bram")])],
        options: GameOptions(), capture: Capture())
      try! store.writeFile(
        GameFile.headers(for: two, appVersion: "0.1", winner: .A) + "\n" + g2Turns + "\n", for: two.id)
      try! store.save(two)

      // Opened from a Throwing Wood file.
      var three = try! store.open(fileText: sixPack, named: "six-pack-v-full-house.txt", reader: NotationReader())
      three.created = day(15, 18)
      try! store.save(three)

      // Still on the pitch: the canvas's game (the worked example of kubb-engine's
      // RECORD.md, renamed), stopped where `-PitchsideDemoAt <n>` says.
      let four = Game(
        created: Date.now.addingTimeInterval(-25 * 60), status: .setup,
        teams: [.A: Team(name: "Wobbly Towers", players: [p("Kim"), p("Dana"), p("Ole")]),
                .B: Team(name: "Birch Batons", players: [p("Sam"), p("Lee")])],
        options: GameOptions(wind: .light, first: .A), capture: Capture(who: true, stand: true, stance: true),
        event: "Tumblecone Cup", location: "Lantern Kubb Hollow, Pitch 4")
      try! store.save(four)
      let scorer = try! RecordScorer(game: four, store: store, appVersion: "0.1")
      let args = ProcessInfo.processInfo.arguments
      let at = args.firstIndex(of: "-PitchsideDemoAt").flatMap { args.dropFirst($0 + 1).first }.flatMap(Int.init) ?? 28
      for e in canvasGame.prefix(max(0, at)) { try! scorer.add(e) }
      return store
    }

    /// The worked example's events (kubb-engine tests/fixtures/record/games.lua,
    /// `example`): five turns, the fifth `5. k:3I A k:3F d:B o:B k:B d:= o:K`.
    static var canvasGame: [[String: JSONValue]] {
      func P(_ a: Double, _ d: Double) -> RecordPoint { RecordPoint(across: a, depth: d) }
      typealias E = RecordEvent
      return [
        E.baton(base: 1, by: "kim", at: [P(1.5, 4)], stance: P(2.5, 4)),
        E.baton(base: 1, by: "dana", at: [P(4.5, 4)], stance: P(2.5, 4)),
        E.toss(true, by: "sam", at: P(1.2, 2.4)), E.toss(true, by: "sam", at: P(3.6, 1.1)),
        E.baton(field: 2, by: "sam", at: [P(1.2, 2.4), P(3.6, 1.1)]),
        E.baton(base: 1, by: "lee", at: [P(0.5, 4)]), E.baton(base: 1, by: "sam", at: [P(2.5, 4)]),
        E.baton(by: "lee"),
        E.toss(true, by: "kim", at: P(0.4, 1.5)), E.toss(true, by: "kim", at: P(2.2, 0.6)),
        E.toss(true, by: "kim", at: P(2.8, 0.9)), E.toss(true, by: "kim", at: P(4.1, 2.2)),
        E.baton(field: 2, by: "kim", at: [P(2.2, 0.6), P(2.8, 0.9)]),
        E.baton(field: 1, by: "dana", at: [P(0.4, 1.5)]), E.baton(field: 1, by: "ole", at: [P(4.1, 2.2)]),
        E.baton(by: "kim"), E.baton(by: "dana"), E.baton(by: "ole"),
        E.toss(true, by: "sam", at: P(0.7, 0.8)), E.toss(true, by: "sam", at: P(1.9, 1.2)),
        E.toss(true, by: "lee", at: P(3.4, 1.3)), E.toss(true, by: "lee", at: P(4.4, 0.5)),
        E.baton(field: 1, by: "sam", at: [P(0.7, 0.8)]), E.baton(field: 1, by: "lee", at: [P(1.9, 1.2)]),
        E.baton(field: 1, by: "sam", at: [P(4.4, 0.5)]),
        E.baton(by: "lee"), E.baton(by: "sam"), E.baton(by: "lee"),
        E.toss(true, by: "kim", at: P(1.4, 1.6)), E.toss(true, by: "kim", at: P(2.3, 1.2)),
        E.toss(true, by: "kim", at: P(2.6, 1.7)),
        E.advantage(applies: true),
        E.baton(field: 3, by: "kim", at: [P(1.4, 1.6), P(2.3, 1.2), P(2.6, 1.7)], stance: P(2.6, 1.3)),
        E.baton(base: 1, by: "dana", at: [P(0.5, 4)], stance: P(2.6, 1.3)),
        E.baton(base: 1, by: "ole", at: [P(2.5, 4)], stance: P(2.4, 1.3)),
        E.baton(base: 1, by: "kim", at: [P(3.5, 4)], stance: P(2.6, 1.3)),
        E.baton(by: "dana", stance: P(2.7, 1.3)),
        E.baton(king: true, by: "ole", stance: P(2.5, 4)),
      ]
    }

    static let g1Turns = """
1. wren:B tomas:-
2. ivo:1I ivo:F maren:- ivo:B maren:-
3. wren:2I wren:F tomas:- wren:F tomas:B wren:- tomas:-
4. ivo:3IR ivo:2F maren:- ivo:F maren:B ivo:- maren:-
5. wren:4I wren:2F tomas:F wren:F tomas:B wren:B tomas:B
6. ivo:7I2R ivo:3F maren:2F ivo:F maren:F ivo:- maren:-
7. wren:7I wren:2F tomas:2F wren:2F tomas:F wren:K
"""

    static let g2Turns = """
1. B B
2. 2I F F - -
3. 2I 2F B B B -
4. 5IR 2F F F - F -
5. 5I 3F 2F K
"""

    static let sixPack = """
[Notation "2"]
[Event "Throwing Wood"]
[Location "Playdate"]
[Start "2026-11-23 05:27"]
[End "2026-11-23 05:56"]
[Duration "29m"]
[Surface "Grass"]
[Rules "U.S. Championship 4.0, six from the start"]
[Base kubbs "5"]
[Batons "6"]
[Opening "6"]
[Team A "Six Pack"]
[Team A Players "Wes (wes), Xan (xan), Yara (yara), Zed (zed), Abe (abe), Bea (bea)"]
[Team B "Full House"]
[Team B Players "Cy (cy), Di (di), Eli (eli), Fay (fay), Gus (gus), Hal (hal)"]
[First "Team A"]
[Win "Team B"]
[Scored by "Throwing Wood 0.0.1"]
[Mode "Pass and Play"]

1. wes:- xan:B yara:- zed:- abe:B bea:B
*b - 1.50,4.00 - - 3.50,4.00 0.50,4.00
2. cy:3I2R cy:F di:F eli:- fay:F gus:- hal:-
@a 1.10,1.50 1.40,1.72 1.78,1.88
*a 1.40,1.72 1.10,1.50 - 1.78,1.88 - -
3. wes:3IR wes:- xan:- yara:- zed:F abe:- bea:F
4. cy:2I A cy:F di:F eli:- fay:B gus:- hal:-
5. wes:4IQ wes:- xan:F yara:- xan:- abe:F bea:-
6. cy:2I A di:- cy:F eli:- fay:- gus:- hal:F
7. wes:3IQ wes:F xan:F yara:- zed:- abe:- bea:F
8. cy:3I A cy:F di:F eli:F fay:- gus:B hal:-
9. bea:4I wes:F xan:F yara:- zed:- zed:- bea:F
10. cy:3I A cy:F di:F eli:F fay:B gus:B hal:B
11. wes:6I2R wes:- xan:F yara:- zed:- abe:F bea:-
12. cy:2I A cy:F di:F eli:K X X X
"""
  }
#endif
