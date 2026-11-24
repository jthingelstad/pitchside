import Testing

@testable import PitchsideDesign

/// 7:1 (WCAG AAA) for text on the grounds it sits on, light and dark.
@Suite struct ContrastTests {
  static let pairs: [(Token, Token)] = [
    (Tokens.text, Tokens.ground), (Tokens.text, Tokens.plate), (Tokens.text, Tokens.inside),
    (Tokens.text, Tokens.field), (Tokens.text, Tokens.wood), (Tokens.muted, Tokens.ground),
    (Tokens.solid, Tokens.plate), (Tokens.solid, Tokens.ground),
    (Tokens.warn, Tokens.ground), (Tokens.muted, Tokens.inside),
    (Tokens.muted, Tokens.plate), (Tokens.onSolid, Tokens.solid), (Tokens.kubbInk, Tokens.kubb),
    (Tokens.teamAInk, Tokens.teamA), (Tokens.teamBInk, Tokens.teamB),
  ]

  @Test(arguments: 0..<pairs.count) func textReachesSevenToOne(_ i: Int) {
    let (fg, bg) = Self.pairs[i]
    #expect(fg.light.contrast(bg.light) >= 7, "\(fg.name) on \(bg.name), light: \(fg.light.contrast(bg.light))")
    #expect(fg.dark.contrast(bg.dark) >= 7, "\(fg.name) on \(bg.name), dark: \(fg.dark.contrast(bg.dark))")
  }

  @Test func controlOutlinesRemainVisible() {
    #expect(Tokens.line.light.contrast(Tokens.plate.light) >= 3)
    #expect(Tokens.line.dark.contrast(Tokens.plate.dark) >= 3)
  }

  /// The B marker's letter: white on the scoring violet reaches 7:1; the
  /// marker is never the only cue (the team's name sits beside it in text).
  @Test func theVioletLetterIsTheBestItCanBe() {
    let white = Tokens.teamBInk.light.contrast(Tokens.teamB.light)
    let ink = Tokens.text.light.contrast(Tokens.teamB.light)
    #expect(white > ink)
    #expect(white >= 7)
  }
}
