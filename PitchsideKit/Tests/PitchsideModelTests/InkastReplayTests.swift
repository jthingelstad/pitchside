import Foundation
import Notation
import PitchsideModel
import Testing

@Suite struct InkastReplayTests {
  @Test func rethrowAdvancesThePitchOnceAndUndoRestoresTheDraft() throws {
    let f = RecordFixture.named("example")
    let store = try scratch()
    let game = f.game
    try store.save(game)
    let scorer = try RecordScorer(game: game, store: store, appVersion: "test", setup: f.setup, stampTimes: false)
    let half = Side.A
    let left = RecordPoint(across: 2.12, depth: 0.28), right = RecordPoint(across: 2.42, depth: 0.31)
    try scorer.add(RecordEvent.baton(base: 2))
    try scorer.add(RecordEvent.baton())
    try scorer.add(RecordEvent.toss(true, at: left))
    try scorer.add(RecordEvent.toss(false))
    let reader = try NotationReader()
    func plays() throws -> [GameReplay.Step] {
      let analysis = try reader.read(scorer.text).analysis
      return try GameReplay(analysis, journal: store.log(game.id)).steps.filter { $0.turn == 2 }
    }
    let draft = try plays()
    #expect(draft.map(\.title) == ["Kubb in", "Kubb out"])
    #expect(draft.map { $0.board[half]?.field.count } == [1, 1])
    #expect(draft.last?.placed == nil)
    try scorer.add(RecordEvent.toss(true, at: right))
    try scorer.add(RecordEvent.baton(field: 1, at: [right]))
    let turn = try plays()
    #expect(turn.map(\.title) == ["Kubb in", "Kubb out", "Rethrow in", "1 field down"])
    #expect(turn.map { $0.board[half]?.field.count } == [1, 1, 2, 1])
    try #require(turn.count == 4)
    #expect(turn[2].board[half]?.field.places.map(\.across) == [left.across, right.across])
    #expect(turn[2].placed?.across == right.across && turn[2].placed?.tapped == true)
    let imported = GameReplay(try reader.read(scorer.text).analysis).steps.filter { $0.turn == 2 }
    #expect(imported.map(\.phase) == ["Inkast", "Baton 1"])
    try scorer.undo()
    try scorer.undo()
    let restored = try plays()
    #expect(restored.map(\.title) == draft.map(\.title))
    #expect(restored.map(\.board) == draft.map(\.board))
  }

  @Test func captureSetForNextTurnKeepsThisThrowsPlayerAndSpot() throws {
    let f = RecordFixture.named("example")
    let store = try scratch()
    let game = f.game
    try store.save(game)
    let scorer = try RecordScorer(game: game, store: store, appVersion: "test", setup: f.setup, stampTimes: false)
    try scorer.add(RecordEvent.baton(base: 2))
    try scorer.add(RecordEvent.baton())
    let half = try #require(scorer.state.attacker)
    let player = try #require(scorer.state.side(half).players.first)
    try scorer.add(RecordEvent.toss(false, by: player.id))
    try scorer.add(["type": "capture", "players": false, "pitch": false])
    let point = RecordPoint(across: 3.15, depth: 0.25)
    try scorer.add(RecordEvent.toss(true, by: player.id, at: point))
    // A placement without a punishment due is recorded as a warning only.
    try scorer.add(RecordEvent.punish(at: point))
    let analysis = try NotationReader().read(scorer.text).analysis
    let steps = try GameReplay(analysis, journal: store.log(game.id)).steps.filter { $0.turn == 2 }
    #expect(steps.map(\.title) == ["\(player.name) · Kubb out", "\(player.name) · Kubb in"])
    #expect(steps.last?.placed?.across == point.across)
  }

  /// Compare each replay frame against the live engine at the instant the event was entered.
  @Test(arguments: RecordFixture.all.map(\.name))
  func everyObservedInkastMatchesItsLivePitch(fixture: String) throws {
    let f = RecordFixture.named(fixture)
    let store = try scratch()
    let game = f.game
    try store.save(game)
    let scorer = try RecordScorer(game: game, store: store, appVersion: "test", setup: f.setup, stampTimes: false)
    var expected: [(kind: String, turn: Int, state: RecordState)] = []
    for raw in f.events {
      let event = try #require(raw.object)
      let before = scorer.state
      try scorer.add(event)
      let after = scorer.state
      if (raw["type"] == "toss" && before.phase == "inkast")
          || (raw["type"] == "punish" && (after.inkast?.punishPlaced ?? 0) > (before.inkast?.punishPlaced ?? 0)) {
        expected.append((raw["type"]?.string ?? "", before.turn, after))
      }
    }
    let analysis = try NotationReader().read(scorer.text).analysis
    let replay = try GameReplay(analysis, journal: store.log(game.id))
    let inkast = replay.steps.filter { $0.phase.hasPrefix("Inkast · ") }
    #expect(inkast.count == expected.count)
    for (step, event) in zip(inkast, expected) {
      #expect(step.turn == event.turn)
      #expect(step.kingStanding == (event.state.king == "standing"))
      #expect((step.phase == "Inkast · placement") == (event.kind == "punish"))
      for side in Side.allCases {
        let live = event.state.side(side)
        let rendered = try #require(step.board[side])
        #expect(rendered.base.count == live.base && rendered.field.count == live.field)
        #expect(rendered.field.places.count == (event.state.capture.pitch ? live.fieldPositions.count : 0))
      }
    }
    if fixture == "called" {
      #expect(inkast.contains { $0.placed?.mark == "p" })
      #expect(inkast.contains { $0.note?.contains("Failed rescue") == true })
      #expect(inkast.contains { $0.note?.contains("rescued") == true })
    }
    if fixture == "skipped" { #expect(replay.steps.contains { $0.title.contains("unrecorded") }) }
  }
}
