import Foundation
import Notation
import PDFKit
import PitchsideModel
import Testing

@Suite struct ScoreSheetPDFTests {
  private let header = """
    [Notation "2"]
    [Team A "Éclat"]
    [Team B "Birch Bells"]
    [First "Team A"]

    """

  @Test func printableGameKeepsResultAndFinalTurn() throws {
    let turns = "1. 5B K # Last observation"
    let analysis = try NotationReader().read(header + "\n" + turns).analysis
    let document = try #require(PDFDocument(data: ScoreSheetPDF.data(for: analysis)))
    let text = try #require(document.string)
    #expect(document.pageCount >= 2)
    #expect(text.contains("Éclat beat Birch Bells"))
    #expect(text.contains("King down in turn 1"))
    #expect(text.contains("5 base kubbs, king"))
    #expect(text.contains("Last observation"))
    #expect(text.contains("Page 1"))
  }

  @Test func importedFileKeepsCoordinatesStatsAndSeparateTurnNotes() throws {
    let store = try scratch()
    let reader = try NotationReader()
    let file = header + """
      [Scored by "Throwing Wood 1.0"]
      [Team A Players "Ren (ren)"]

      1. B -
      *b 0.50,4.00 -
      2. I F G
      @a 2,1
      """
    var game = try store.open(fileText: file, named: "game.txt", reader: reader)
    game.importedTurnNotes = [2: ["A tight group"]]
    try store.save(game)
    let reopened = try #require(store.game(game.id))
    let original = try #require(store.fileText(game.id))
    #expect(original == file)
    let read = try reader.read(original)
    #expect(read.analysis.players.first(where: { $0.name == "Ren" })?.batons == 2)
    let report = try ScoreSheetPDF.data(for: read, notation: original, annotations: reopened.importedTurnNotes ?? [:])
    let pdf = try #require(PDFDocument(data: report))
    let text = try #require(pdf.string)
    for expected in ["Team comparison", "From 8 metres", "Player stats", "Turn 2 · A tight group",
                     "Pitch diagrams", "Original game record", "*b 0.50,4.00 -"] {
      #expect(text.contains(expected))
    }
  }

  @Test func notesOnEarlierAndFinalTurnsSurviveReopenAndUndo() throws {
    let (scorer, store) = try replay(RecordFixture.named("example"), useFixtureSetup: true)
    let original = try scorer.notation()
    let last = scorer.state.turn
    try scorer.annotate(turn: 2, text: "Earlier turn")
    try scorer.annotate(turn: 2, text: "Second observation")
    try scorer.annotate(turn: last, text: "On the final turn")
    let reopened = try RecordScorer(game: scorer.game, store: store, appVersion: "0.1")
    #expect(reopened.rows.first(where: { $0.turn == 2 })?.notes.suffix(2) == ["Earlier turn", "Second observation"])
    #expect(reopened.rows.last?.notes.last == "On the final turn")
    #expect(reopened.state.over)
    for _ in 1...3 { try reopened.undo() }
    #expect(try reopened.notation() == original)
  }

  @Test func scoreSheetDescribesRareObservations() throws {
    let reader = try NotationReader()
    let game = try reader.read(header + "\n1. B -\n2. IRP Z E").analysis
    let turn = try #require(game.rows.last)
    #expect(turn.scoringSummary.contains("1 rethrow, 1 punishment"))
    #expect(turn.scoringSummary.contains("illegal throw"))
    #expect(turn.scoringSummary.contains("king felled early"))
    #expect(game.resultDetail == "King felled early in turn 2")
    for (tokens, words) in [("5B = K", "missed king shot"), ("G", "resigned"), ("W", "game called")] {
      let row = try #require(reader.read(header + "\n1. " + tokens).analysis.rows.first)
      #expect(row.scoringSummary.contains(words))
    }
  }

  @Test func longGameAndLongNotePaginateWithoutDroppingThrows() throws {
    let longNote = String(repeating: "Lichen glimmer ", count: 650) + "End of observation"
    let turns = (1...40).map { number in
      "\(number). - - # " + (number == 13 ? longNote : "Observation \(number).")
    }
    let analysis = try NotationReader().read(header + "\n" + turns.joined(separator: "\n")).analysis
    let pdf = try #require(PDFDocument(data: ScoreSheetPDF.data(for: analysis, inProgress: true)))
    #expect(pdf.pageCount > 2)
    let text = try #require(pdf.string)
    #expect(text.contains("Draft · game in progress"))
    #expect(text.contains("End of observation"))
    #expect(text.components(separatedBy: "Lichen").count == 651)
    #expect(!text.contains(" beat "))
    let words = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    for n in 1...40 { #expect(words.contains("Turn \(n) ")) }
    for n in 1...pdf.pageCount {
      let page = try #require(pdf.page(at: n - 1)?.string)
      #expect(page.contains("Page \(n)"))
      #expect(page.contains("KUBB: PITCHSIDE"))
    }
  }
}
