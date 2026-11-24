import Foundation
import Notation
import PitchsideModel
import Testing

@Suite struct ReplayTests {
  private func replay(_ turns: String) throws -> GameReplay {
    GameReplay(try NotationReader().read("[Notation \"2\"]\n[First \"Team B\"]\n\n" + turns).analysis)
  }

  @Test(arguments: RecordFixture.all.map(\.name))
  func everyBatonAgreesWithTheScoresheet(fixture: String) throws {
    try Self.verifyFrames(RecordFixture.named(fixture).text)
  }

  static func verifyFrames(_ text: String) throws {
    let a = try NotationReader().read(text).analysis
    let game = GameReplay(a)
    for row in a.rows where row.turn <= (a.endTurn ?? Int.max) {
      let plays = game.steps.filter { $0.turn == row.turn }
      let batons = plays.filter { $0.phase.hasPrefix("Baton ") }
      #expect(batons.map(\.token) == row.thrown.map(\.raw))
      var f = row.startField, b = row.startBase, n = 0
      for (i, recorded) in row.batons.enumerated() where recorded.isThrown {
        guard n < batons.count else { break }
        let step = batons[n]
        n += 1
        f = max(0, f - (recorded.f ?? 0))
        b = max(0, b - (recorded.b ?? 0))
        #expect(step.board[row.team.other]?.field.count == f)
        #expect(step.board[row.team.other]?.base.count == b)
        let falls = i < row.recording.falls.count ? row.recording.falls[i] ?? [] : []
        #expect(step.falls == falls)
        for half in step.board.values {
          #expect(half.field.unknown >= 0 && half.base.unknown >= 0)
        }
      }
      let end = try #require(plays.last)
      #expect(end.board[row.team.other]?.field.count == row.fieldLeft)
      for side in Side.allCases { #expect(end.board[side]?.base.count == row.base[side.rawValue]) }
    }
  }

  @Test func laysStancesMixedFallsAndBacktracking() throws {
    let game = try replay("""
      1. B B
      *a 0.50,4.00 3.50,4.00
      2. 2I 2FB = K X X
      @b 2.12,0.28 2.18,0.24
      ~b 2.12,0.28/2.16,0.20 2.18,0.24/2.25,0.22
      ^a 2.21,4.42 - - - -
      *b 2.12,0.28+2.18,0.24+1.50,4.00 - - - -
      """)
    #expect(game.turnStarts.count == 2)
    let turn = Array(game.steps[game.turnStarts[1]...])
    #expect(turn.map(\.phase) == ["Inkast", "Inkast", "Baton 1", "Baton 2", "Baton 3"])
    #expect(turn[0].lays.first?.last.depth == 0.20)
    #expect(turn[1].board[.B]?.field.places.count == 2)
    #expect(turn[2].board[.B]?.field.count == 0)
    #expect(turn[2].board[.B]?.base.count == 4)
    #expect(turn[2].falls.map(\.across) == [2.12, 2.18, 1.50])
    #expect(turn[2].stance?.depth == 4.42)
    #expect(turn[3].kingStanding && turn[3].title == "King shot missed")
    #expect(!turn[4].kingStanding && turn[4].result != nil)
    #expect(game.steps[0].team == .B && game.steps[0].board[.A]?.base.count == 5)
  }

  @Test func anUnlocatedFallKeepsOnlyCertainSurvivors() throws {
    let game = try replay("""
      1. 3B
      2. 3I F F -
      @b 1.12,0.64 2.14,1.58 3.16,2.46
      *b - 2.14,1.58 -
      """)
    let first = try #require(game.steps.first { $0.turn == 2 && $0.phase == "Baton 1" })
    #expect(first.board[.B]?.field.count == 2)
    #expect(first.board[.B]?.field.places.map(\.across) == [2.14])
    #expect(first.board[.B]?.field.unknown == 1 && first.unlocatedFalls == 1)
    #expect(game.steps.last?.board[.B]?.field.unknown == 1)
    #expect(game.steps.first { $0.turn == 1 && $0.phase == "Baton 1" }?.board[.A]?.base.unknown == 2)
  }

  @Test func missingPitchLineAndRepeatedCell() throws {
    let game = try replay("""
      1. 3B
      2. 3I 2F F G X X
      *b 2x3,0 3,0 - - -
      """)
    let start = game.steps[game.turnStarts[1]]
    #expect(start.board[.B]?.field.places.count == 3)
    #expect(start.board[.B]?.field.places.allSatisfy(\.cell) == true)
    #expect(start.board[.B]?.field.places.allSatisfy(\.inferredFromFall) == true)
    let first = game.steps[game.turnStarts[1] + 1]
    #expect(first.board[.B]?.field.places.count == 1)
    #expect(first.board[.B]?.field.places.first?.world(in: .B) == .init(x: 3.5, y: 4.5))
    #expect(game.steps.last?.token == "G")
    #expect(game.steps.last?.kingStanding == true)
  }

  @Test func aCellPrecisionFallAmongPointsPreservesOnlyTheCell() throws {
    let game = try replay("""
      1. 3B
      2. 3I F -
      @b 1.18,0.02 1.24,0.08 4.62,0.82
      *b 1,0 -
      """)
    let pieces = try #require(game.steps.last?.board[.B]?.field.places)
    #expect(pieces.count == 2)
    #expect(pieces.contains { $0.cell && $0.across == 1 })
    #expect(pieces.contains { !$0.cell && $0.across == 4.62 })
  }

  @Test func terminalMarkersAndPostgameTokens() throws {
    for (turns, king, token) in [
      ("1. E - X", false, "E"), ("1. 2FE X", false, "2FE"),
      ("1. IE X X", false, "IE"), ("1. - W X", true, "W"),
      ("1. Z G X X", true, "G")
    ] {
      let game = try replay(turns)
      #expect(game.steps.last?.token == token)
      #expect(game.steps.last?.kingStanding == king)
      #expect(game.steps.last?.result != nil)
    }
  }
}
