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
    #expect(document.pageCount == 1)
    #expect(text.contains("Éclat beat Birch Bells"))
    #expect(text.contains("King down in turn 1"))
    #expect(text.contains("5 base kubbs, king"))
    #expect(text.contains("Last observation"))
    #expect(text.contains("Page 1"))
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
