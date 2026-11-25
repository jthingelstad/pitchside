import Foundation
import Testing
@testable import PitchsideModel

@Suite struct ScoreHistoryTests {
  private struct Snapshot: Equatable {
    let events: [[String: JSONValue]]
    let state: RecordState
    let rows: [RecordRow]
    let warnings: [RecordWarning]
    let file: Data

    init(_ scorer: RecordScorer) {
      events = scorer.records
      state = scorer.state
      rows = scorer.rows
      warnings = scorer.warnings
      file = Data(scorer.text.utf8)
    }
  }

  @Test(arguments: RecordFixture.all.map(\.name))
  func everyThrowInBothDirections(_ name: String) throws {
    let fixture = RecordFixture.named(name)
    let store = try scratch(), game = fixture.game
    try store.save(game)
    let s = try RecordScorer(game: game, store: store, appVersion: "test", setup: fixture.setup, stampTimes: false)
    var states = [Snapshot(s)]
    for event in fixture.events {
      try s.add(try #require(event.object))
      states.append(Snapshot(s))
    }
    #expect(Data(s.text.utf8) == Data(fixture.text.utf8))
    for expected in states.dropLast().reversed() {
      try s.undo()
      #expect(Snapshot(s) == expected)
      #expect(store.fileText(game.id).map { Data($0.utf8) } == expected.file)
    }
    #expect(s.undoAction == nil)
    let reopened = try RecordScorer(game: game, store: store, appVersion: "test")
    try reopened.undo()
    for expected in states.dropFirst() {
      try reopened.redo()
      #expect(Snapshot(reopened) == expected)
      #expect(store.fileText(game.id).map { Data($0.utf8) } == expected.file)
      #expect(store.game(game.id)?.status == (expected.state.over ? .finished : .playing))
    }
    #expect(reopened.redoAction == nil)
    #expect(Data(reopened.text.utf8) == Data(fixture.text.utf8))
  }

  @Test(arguments: ["calledOther", "resignOther", "resignWaiting"])
  func resultIsEditableOnItsPrintedTurn(_ name: String) throws {
    let (s, _) = try replay(.named(name), useFixtureSetup: true)
    let rows = try s.timeline()
    let row = try #require(rows.first { $0.turn == s.state.turn })
    let result = try #require(row.events.last)
    #expect(["call", "resign"].contains(result.type))
    #expect(result.turn != result.sheetTurn)
    let ended = Snapshot(s)
    try s.edit(.remove(id: result.id))
    #expect(!s.state.over)
    try s.undo()
    #expect(Snapshot(s) == ended)
  }

  @Test func correctionsSurviveRestartAndBranchOnlyWhenSaved() throws {
    let (s, store) = try replay(.named("example"), useFixtureSetup: true)
    let original = Snapshot(s), event = s.records[1]
    let id = try #require(event["id"]?.string)
    var replacement = event
    replacement["by"] = nil
    let edits: [RecordEdit] = [.replace(id: id, event: replacement),
                               .insert(before: id, event: RecordEvent.baton()), .remove(id: id)]
    var states = [original]
    for edit in edits {
      let preview = try s.preview(edit)
      try s.edit(edit)
      #expect(s.text == preview.notation?.text)
      states.append(Snapshot(s))
    }
    for state in states.dropLast().reversed() {
      #expect(s.undoAction == .correction)
      try s.undo()
      #expect(Snapshot(s) == state)
    }
    let reopened = try RecordScorer(game: s.game, store: store, appVersion: "test")
    for state in states.dropFirst() {
      #expect(reopened.redoAction == .correction)
      try reopened.redo()
      #expect(Snapshot(reopened) == state)
    }
    try reopened.undo()
    let count = try store.log(s.game.id).events.count
    let effective = try #require(reopened.records.first { $0["id"]?.string == id })
    try reopened.edit(.replace(id: id, event: effective))
    _ = try reopened.preview(.remove(id: id))
    #expect(throws: (any Error).self) { try reopened.edit(.remove(id: "missing")) }
    #expect(try store.log(s.game.id).events.count == count)
    #expect(reopened.redoAction == .correction)
    try reopened.edit(.insert(before: id, event: RecordEvent.baton(base: 1)))
    #expect(reopened.redoAction == nil)
    try reopened.undo()
    try reopened.add(RecordEvent.note("Second look"))
    #expect(reopened.redoAction == nil)
  }

  @Test func legacyRemovalKeepsItsTargetAfterEarlierCorrection() throws {
    let (s, store) = try replay(.named("example"), useFixtureSetup: true)
    let first = s.records[0], last = try #require(s.records.last)
    let firstID = try #require(first["id"]?.string)
    let lastID = try #require(last["id"])
    try s.edit(.replace(id: firstID, event: RecordEvent.baton()))
    let edited = Snapshot(s)
    try store.log(s.game.id).append(kind: "undo", capture: s.game.capture, payload: .object(["id": lastID]))
    let opened = try RecordScorer(game: s.game, store: store, appVersion: "test")
    #expect(opened.records == Array(edited.events.dropLast()))
    #expect(!opened.state.over)
    try opened.redo()
    #expect(Snapshot(opened) == edited)
    try opened.undo()
    try opened.undo()
    #expect(opened.records.first == first)
    #expect(opened.records.last?["id"] != lastID)
  }

  /// Compare the incremental fold with a simple oracle that keeps a complete list after
  /// each change. Fixed seeds reproduce any failing sequence of inserts, edits and undos.
  @Test func mixedEditsAgainstSnapshotHistory() {
    typealias Events = [[String: JSONValue]]
    for seed in 1...32 {
      var random = UInt64(seed)
      func pick(_ limit: Int) -> Int {
        random = random &* 6364136223846793005 &+ 1442695040888963407
        return Int((random >> 32) % UInt64(limit))
      }
      var journal: [GameEvent] = []
      var copies: [(sequence: Int, events: Events)] = [(0, [])]
      var cursor = 0, history = ScoreHistory([])
      for seq in 1...128 {
        var events = copies[cursor].events
        let operation = pick(7)
        let kind: String, payload: JSONValue
        if operation < 2 && cursor > 0 {
          kind = "undo"
          payload = .object(["change": .number(Double(copies[cursor].sequence))])
          cursor -= 1
        } else if operation == 2 && cursor + 1 < copies.count {
          cursor += 1
          kind = "redo"
          payload = .object(["change": .number(Double(copies[cursor].sequence))])
        } else {
          var event = RecordEvent.note("Observation \(seq)")
          event["id"] = .string("e\(seq)")
          if events.isEmpty || operation >= 5 {
            kind = "record"
            payload = .object(event)
            events.append(event)
          } else {
            kind = "edit"
            let index = pick(events.count), target = events[index]["id"]!
            switch operation % 3 {
            case 0:
              payload = .object(["remove": target])
              events.remove(at: index)
            case 1:
              payload = .object(["insert": target, "event": .object(event)])
              events.insert(event, at: index)
            default:
              event["id"] = target
              payload = .object(["replace": target, "event": .object(event)])
              events[index] = event
            }
          }
          copies.removeSubrange((cursor + 1)..<copies.endIndex)
          copies.append((seq, events))
          cursor += 1
        }
        journal.append(GameEvent(seq: seq, kind: kind, capture: "turn", payload: payload))
        history.apply(kind: kind, payload: payload, sequence: seq)
        if seq.isMultiple(of: 17) { history = ScoreHistory(journal) }
        #expect(history.records == copies[cursor].events, "seed \(seed), step \(seq)")
        #expect((history.undoAction != nil) == (cursor > 0))
        #expect((history.redoAction != nil) == (cursor + 1 < copies.count))
      }
    }
  }

  @Test func removingOnlyObservationAndStaleWriter() throws {
    let fixture = RecordFixture.named("example"), game = fixture.game, store = try scratch()
    try store.save(game)
    let s = try RecordScorer(game: game, store: store, appVersion: "test", setup: fixture.setup)
    try s.add(RecordEvent.baton())
    let original = Snapshot(s)
    let stale = try RecordScorer(game: game, store: store, appVersion: "test")
    let id = try #require(s.records.first?["id"]?.string)
    try s.edit(.remove(id: id))
    #expect(s.records.isEmpty && s.undoAction == .correction)
    #expect(throws: (any Error).self) { try stale.undo() }
    #expect(Snapshot(stale) == original)
    #expect(store.fileText(game.id) == s.text)
    try s.undo()
    #expect(Snapshot(s) == original)
    try s.redo()
    #expect(s.records.isEmpty)
    try s.undo()
    try s.undo()
    try s.redo()
    #expect(Snapshot(s) == original)
  }
}
