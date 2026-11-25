import Foundation
import Notation
import Testing

@testable import PitchsideModel

@Suite struct FieldPlacementTests {
  let points = [RecordPoint(across: 2.14, depth: 0.18), RecordPoint(across: 2.41, depth: 0.42),
                RecordPoint(across: 2.72, depth: 0.69)]

  func cluster(_ points: [RecordPoint]) throws -> (RecordScorer, GameStore, FieldPlacements) {
    let f = RecordFixture.named("example")
    let store = try scratch()
    try store.save(f.game)
    let s = try RecordScorer(game: f.game, store: store, appVersion: "test", setup: f.setup, stampTimes: false)
    var field = FieldPlacements()
    func add(_ event: [String: JSONValue]) throws {
      let before = s.state
      try s.add(event)
      field.apply(try #require(s.records.last), before: before, after: s.state)
    }
    try add(RecordEvent.baton(base: 3, at: (0..<3).map { RecordPoint(across: Double($0) + 0.5, depth: 4) }))
    try add(RecordEvent.baton())
    for p in points { try add(RecordEvent.toss(true, at: p)) }
    return (s, store, field)
  }

  @Test func selectedPlacementSurvivesReopenReplayUndoAndCorrection() throws {
    let (s, store, positions) = try cluster(points)
    let half = try #require(s.state.defender)
    let placements = positions.aligned(in: half, state: s.state).compactMap { $0 }
    #expect(placements.map(\.point) == points)
    var hit = RecordEvent.baton(field: 1)
    hit["at"] = .array([placements[1].hit(in: half)])
    try s.add(hit)
    let eventID = try #require(s.records.last?["id"]?.string)
    let reopened = try RecordScorer(game: s.game, store: store, appVersion: "test")
    #expect(reopened.records.last?["at"]?.array?.first?["placement"]?.string == placements[1].id)
    func shots() throws -> (GameReplay.Step, GameReplay.Step) {
      let analysis = try NotationReader().read(reopened.text).analysis
      let replay = try GameReplay(analysis, journal: store.log(s.game.id))
      return (try #require(replay.steps.first { $0.turn == 2 && $0.phase == "Inkast" }),
              try #require(replay.steps.first { $0.turn == 2 && $0.phase == "Baton 1" }))
    }
    let (standing, down) = try shots()
    #expect(standing.board[half]?.field.places.map(\.across) == points.map(\.across))
    #expect(down.falls.map(\.across) == [points[1].across])
    #expect(down.falls.first?.tapped == true)
    #expect(down.board[half]?.field.places.map(\.depth) == [points[0].depth, points[2].depth])
    try reopened.add(RecordEvent.call(winner: half.other))
    let exported = try NotationReader().read(reopened.text).analysis
    #expect(exported.warnings.isEmpty && exported.turnWarnings == 0, "\(exported.warnings) \(exported.rows.flatMap(\.warnings))")
    let imported = try #require(GameReplay(exported).steps.first { $0.turn == 2 && $0.phase == "Baton 1" })
    #expect(imported.falls.first?.cell == true)
    try reopened.undo()
    hit["at"] = .array([placements[0].hit(in: half)])
    try reopened.edit(.replace(id: eventID, event: hit))
    #expect(try shots().1.board[half]?.field.places.map(\.depth) == [points[1].depth, points[2].depth])
    try reopened.undo()
    try reopened.add(RecordEvent.baton())
    #expect(try shots().1.board[half]?.field.places.map(\.depth) == points.map(\.depth))
  }

  @Test func oldAmbiguousHitLosesPointPrecisionOnlyInItsCell() throws {
    let far = RecordPoint(across: 5, depth: 4)
    let (s, _, initial) = try cluster([points[0], points[1], far])
    var positions = initial
    let before = s.state, half = try #require(s.state.defender)
    try s.add(RecordEvent.baton(field: 1, at: [RecordPoint(across: 2.5, depth: 0.5)]))
    let hits = positions.apply(try #require(s.records.last), before: before, after: s.state)
    #expect(hits.isEmpty)
    let survivors = positions.aligned(in: half, state: s.state)
    #expect(survivors.count == 2)
    #expect(survivors.compactMap { $0?.point } == [far])
  }

  @Test func sortedFelledWordKeepsBothTheCellAndTheTappedKubb() throws {
    let right = RecordPoint(across: 4.72, depth: 2.27)
    let (s, store, initial) = try cluster([points[0], points[1], right])
    var positions = initial
    let before = s.state, half = try #require(before.defender)
    let leftCell = RecordPoint(across: 2.5, depth: 0.5)
    try s.add(RecordEvent.baton(field: 1, at: [leftCell]))
    positions.apply(try #require(s.records.last), before: before, after: s.state)
    let identified = try #require(positions.aligned(in: half, state: s.state).compactMap { $0 }.first)
    var hit = RecordEvent.baton(field: 2)
    // The scorer chose the right-hand kubb first. The writer sorts the left cell first.
    hit["at"] = .array([identified.hit(in: half), leftCell.tap(in: half)])
    try s.add(hit)
    let analysis = try NotationReader().read(s.text).analysis
    let replay = try GameReplay(analysis, journal: store.log(s.game.id))
    let falls = try #require(replay.steps.last?.falls)
    #expect(falls.map(\.across) == [2, right.across])
    #expect(falls.map(\.cell) == [true, false])
    #expect(falls.map(\.tapped) == [false, true])
  }

  @Test func aNewPitchSurveyReplacesTheOldPlacementIDs() throws {
    let (s, _, initial) = try cluster(points)
    var positions = initial
    let before = s.state, half = try #require(s.state.defender)
    let old = positions.aligned(in: half, state: before).compactMap { $0 }
    let survey = [points[2], points[1], points[0]]
    try s.add(RecordEvent.pitch(half: half, at: survey))
    positions.apply(try #require(s.records.last), before: before, after: s.state)
    let current = positions.aligned(in: half, state: s.state).compactMap { $0 }
    #expect(current.map(\.point) == survey)
    #expect(Set(old.map(\.id)).isDisjoint(with: current.map(\.id)))
    // A stale reference after a timeline correction cannot identify a new occupant.
    var hit = RecordEvent.baton(field: 1)
    hit["at"] = .array([old[1].hit(in: half)])
    let surveyed = s.state
    try s.add(hit)
    let actual = positions.apply(try #require(s.records.last), before: surveyed, after: s.state)
    #expect(actual.isEmpty)
    #expect(positions.aligned(in: half, state: s.state).allSatisfy { $0 == nil })
  }

  @Test func correctingAnEarlierTapMovesItsIdentifiedFallWithinTheCell() throws {
    let (s, store, positions) = try cluster(points)
    let half = try #require(s.state.defender)
    let p = try #require(positions.aligned(in: half, state: s.state)[1])
    var hit = RecordEvent.baton(field: 1)
    hit["at"] = .array([p.hit(in: half)])
    try s.add(hit)
    let corrected = RecordPoint(across: 2.55, depth: 0.31)
    try s.edit(.replace(id: p.id, event: RecordEvent.toss(true, at: corrected)))
    let analysis = try NotationReader().read(s.text).analysis
    let replay = try GameReplay(analysis, journal: store.log(s.game.id))
    let fall = try #require(replay.steps.last?.falls.first)
    #expect(fall.across == corrected.across && fall.depth == corrected.depth)
    #expect(replay.steps.last?.board[half]?.field.places.map(\.depth) == [points[0].depth, points[2].depth])
  }

  @Test func coincidentPlacementsHaveDistinctReferencesAndAnIllegalHitKeepsThem() throws {
    let (s, _, initial) = try cluster([points[0], points[0], points[0]])
    var positions = initial
    let half = try #require(s.state.defender)
    let standing = positions.aligned(in: half, state: s.state).compactMap { $0 }
    #expect(Set(standing.map(\.id)).count == 3)
    var hit = RecordEvent.baton(field: 1, illegal: true)
    hit["at"] = .array([standing[1].hit(in: half)])
    func apply(_ event: [String: JSONValue]) throws {
      let before = s.state
      try s.add(event)
      positions.apply(try #require(s.records.last), before: before, after: s.state)
    }
    try apply(hit)
    #expect(positions.aligned(in: half, state: s.state).compactMap { $0 } == standing)
    hit["illegal"] = nil
    try apply(hit)
    #expect(positions.aligned(in: half, state: s.state).compactMap { $0 } == [standing[0], standing[2]])
  }
}
