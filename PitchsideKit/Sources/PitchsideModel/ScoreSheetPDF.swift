import CoreGraphics
import CoreText
import Foundation
import Notation

/// Printable US Letter score sheet. Text stays selectable and wraps across pages,
/// including names and notes supplied by an imported notation file.
public enum ScoreSheetPDF {
  public static func data(for game: Analysis, inProgress: Bool = false) throws -> Data {
    let buffer = NSMutableData()
    var page = CGRect(x: 0, y: 0, width: 612, height: 792)
    let info = [kCGPDFContextTitle: "Kubb score sheet", kCGPDFContextCreator: "Kubb: Pitchside"]
    guard let consumer = CGDataConsumer(data: buffer),
      let context = CGContext(consumer: consumer, mediaBox: &page, info as CFDictionary)
    else { throw CocoaError(.fileWriteUnknown) }

    let margin: CGFloat = 44
    let bottom: CGFloat = 65
    let top = page.height - 81
    let width = page.width - 2 * margin
    var cursor = top
    var pageNumber = 0

    func line(_ text: String, size: CGFloat, bold: Bool = false) -> NSAttributedString {
      let name = bold ? "HelveticaNeue-Bold" : "HelveticaNeue"
      return NSAttributedString(string: text, attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(name as CFString, size, nil)
      ])
    }

    func beginPage() {
      if pageNumber > 0 { context.endPDFPage() }
      context.beginPDFPage(nil)
      pageNumber += 1
      context.textMatrix = .identity
      context.setFillColor(gray: 0.1, alpha: 1)
      context.textPosition = CGPoint(x: margin, y: page.height - 43)
      CTLineDraw(CTLineCreateWithAttributedString(line("KUBB: PITCHSIDE", size: 14, bold: true)), context)
      context.setStrokeColor(gray: 0.16, alpha: 1)
      context.setLineWidth(1.5)
      context.strokeLineSegments(between: [
        CGPoint(x: margin, y: page.height - 54), CGPoint(x: page.width - margin, y: page.height - 54)
      ])
      context.textPosition = CGPoint(x: margin, y: 34)
      CTLineDraw(CTLineCreateWithAttributedString(line("Score sheet  ·  Page \(pageNumber)", size: 11)), context)
      cursor = top
    }

    // Core Text chooses breaks and fallback glyphs for the actual script. A single
    // unusually long name or note may itself span pages.
    func write(_ text: String, size: CGFloat, bold: Bool = false, indent: CGFloat = 0) {
      let value = line(text, size: size, bold: bold)
      let typesetter = CTTypesetterCreateWithAttributedString(value)
      var index = 0
      while index < value.length {
        let count = CTTypesetterSuggestLineBreak(typesetter, index, Double(width - indent))
        guard count > 0 else { break }
        let row = CTTypesetterCreateLine(typesetter, CFRange(location: index, length: count))
        var ascent: CGFloat = 0, descent: CGFloat = 0
        _ = CTLineGetTypographicBounds(row, &ascent, &descent, nil)
        let height = max(size * 1.28, ceil(ascent + descent + 2))
        if cursor - height < bottom { beginPage() }
        context.textPosition = CGPoint(x: margin + indent, y: cursor - ascent)
        CTLineDraw(row, context)
        cursor -= height
        index += count
      }
    }

    beginPage()
    if let winner = game.winner {
      write("\(game.name(winner)) beat \(game.name(winner.other))", size: 24, bold: true)
      write(game.resultDetail, size: 15)
    } else {
      write("\(game.name(.A)) v \(game.name(.B))", size: 24, bold: true)
      write(inProgress ? "Draft · game in progress" : "No result in the file", size: 15)
    }
    let metadata = ["Event", "Location", "Start"].compactMap { game.headers[$0] }
      .filter { !$0.isEmpty }.joined(separator: "  ·  ")
    if !metadata.isEmpty { cursor -= 5; write(metadata, size: 13) }
    cursor -= 17
    write("Turn by turn", size: 18, bold: true)
    if game.rows.isEmpty { write("No throws recorded.", size: 14) }
    for turn in game.rows {
      // Keep a normal two-line turn together when it lies at a page boundary.
      if cursor - 54 < bottom { beginPage() }
      cursor -= 7
      write("Turn \(turn.turn)  ·  \(game.name(turn.team))", size: 15, bold: true)
      write("\(turn.scoringSummary)  ·  \(turn.hits) of \(turn.thrown.count) batons hit", size: 14)
      if let note = turn.note, !note.isEmpty { write(note, size: 13, indent: 12) }
      for warning in turn.warnings { write("Reader note · \(warning)", size: 13, indent: 12) }
    }
    if !game.warnings.isEmpty {
      if cursor - 65 < bottom { beginPage() }
      cursor -= 12
      write("Reader notes", size: 16, bold: true)
      for warning in game.warnings { write(warning, size: 13) }
    }
    context.endPDFPage()
    context.closePDF()
    return buffer as Data
  }
}
