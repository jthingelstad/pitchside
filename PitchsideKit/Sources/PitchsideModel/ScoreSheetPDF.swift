import CoreGraphics
import CoreText
import Foundation
import Notation

/// Printable, selectable match report. The app passes the original notation so even
/// extension headers and observations the reader doesn't interpret reach the paper.
public enum ScoreSheetPDF {
  public static func data(for read: GameRead, notation: String, inProgress: Bool = false,
                          annotations: [Int: [String]] = [:]) throws -> Data {
    try render(read.analysis, read: read, source: notation, draft: inProgress, notes: annotations)
  }

  public static func data(for game: Analysis, inProgress: Bool = false) throws -> Data {
    try render(game, read: nil, source: nil, draft: inProgress, notes: [:])
  }

  private static func render(_ game: Analysis, read: GameRead?, source: String?, draft: Bool,
                             notes: [Int: [String]]) throws -> Data {
    let buffer = NSMutableData()
    var page = CGRect(x: 0, y: 0, width: 792, height: 612)
    let info = [kCGPDFContextTitle: "Kubb match report", kCGPDFContextCreator: "Kubb: Pitchside"]
    guard let consumer = CGDataConsumer(data: buffer),
          let context = CGContext(consumer: consumer, mediaBox: &page, info as CFDictionary)
    else { throw CocoaError(.fileWriteUnknown) }
    let paper = ReportPage(context)
    paper.begin("Score sheet")
    paper.paragraph(game.winner.map { "\(game.name($0)) beat \(game.name($0.other))" }
                    ?? "\(game.name(.A)) v \(game.name(.B))", size: 23, bold: true)
    paper.paragraph(game.winner != nil ? game.resultDetail : (draft ? "Draft · game in progress" : "No result in the file"), size: 14)
    paper.paragraph(["Event", "Location", "Start", "Duration", "Surface", "Rules"].compactMap { game.headers[$0] }
      .filter { !$0.isEmpty }.joined(separator: "  ·  "), size: 10)
    paper.space(10)
    worksheet(game, paper: paper)
    paper.heading("At a glance")
    let sides = [game.first, game.first.other]
    for side in sides {
      if let s = game.stats(side) {
        let last = s.zeroBaseAt.map { "throw \($0)" } ?? "not reached"
        paper.paragraph("\(game.name(side))   ·   \(s.hits)/\(s.batons) hits (\(percent(s.hitPct)))   ·   first-baton efficiency \(percent(s.efficiency))   ·   last base \(last)", size: 11)
      }
    }
    let annotated = game.rows.filter { !($0.note ?? "").isEmpty || !(notes[$0.turn] ?? []).isEmpty }
    if !annotated.isEmpty {
      paper.heading("Turn notes")
      for row in annotated {
        let items = [row.note].compactMap { $0 }.filter { !$0.isEmpty } + (notes[row.turn] ?? [])
        for note in items { paper.paragraph("Turn \(row.turn) · \(note)", size: 11) }
      }
    }
    stats(game, read: read, paper: paper)
    PitchDiagramReport.draw(game.rows, on: paper)
    if !game.warnings.isEmpty || game.turnWarnings > 0 {
      paper.heading("Reader notes")
      for warning in game.warnings { paper.paragraph(warning, size: 10) }
      for row in game.rows {
        for warning in row.warnings { paper.paragraph("Turn \(row.turn) · \(warning)", size: 10) }
      }
    }
    if let source {
      paper.begin("Planet Kubb Notation")
      paper.heading("Original game record")
      for line in source.components(separatedBy: .newlines) {
        if line.isEmpty { paper.space(4) } else { paper.paragraph(line, size: 10, mono: true, leading: 1.16) }
      }
    }
    context.endPDFPage()
    context.closePDF()
    return buffer as Data
  }

  private static func worksheet(_ game: Analysis, paper: ReportPage) {
    let first = game.first
    let sides = [first, first.other]
    let teams = sides.map { side in
      let names = game.headers["Team \(side.rawValue) Players"]
      return ["\(side == first ? "Opening" : "Answering") team · \(game.name(side))", names]
        .compactMap { $0 }.joined(separator: "\n")
    }
    paper.row(teams, widths: [362, 362], size: 12, bold: true)
    let widths: [CGFloat] = [32, 34, 68, 38, 38, 38, 38, 38, 38]
    let heads = ["Turn", "Adv", "Inkast", "1", "2", "3", "4", "5", "6"]
    func labels() { paper.row(heads + heads, widths: widths + widths, size: 9, bold: true, shaded: true) }
    labels()
    let groups = sides.map { side in game.rows.filter { $0.team == side } }
    func marks(_ rows: [Analysis.Row], _ i: Int) -> [String] {
      guard i < rows.count else { return Array(repeating: "", count: 9) }
      let r = rows[i]
      let batons = r.batons.map(\.raw)
      // A nonstandard file can have more than six batons. Keep the overflow in order.
      let slots = (0..<6).map { n in
        if n == 5 && batons.count > 6 { return batons.dropFirst(5).joined(separator: " ") }
        return n < batons.count ? batons[n] : ""
      }
      let adv = r.advantageMarked?.raw ?? (r.advantage ? "A*" : "")
      return ["\(r.turn)", adv, r.recording.inkasts.joined(separator: " ")] + slots
    }
    for i in 0..<max(groups[0].count, groups[1].count) {
      if paper.remaining < 26 { paper.begin(); labels() }
      var cleared: Set<Int> = []
      var unused: Set<Int> = []
      for (half, rows) in groups.enumerated() where i < rows.count {
        let r = rows[i]
        let offset = half * 9 + 3
        if let n = r.btc, (1...6).contains(n) { cleared.insert(offset + n - 1) }
        let opening = game.rules.opening
        let allowance = r.turn > 0 && r.turn <= opening.count ? opening[r.turn - 1] : game.rules.batons
        for j in 0..<6 {
          if j >= allowance && j >= r.batons.count || (j < r.batons.count && r.batons[j].kind == "unthrown") {
            unused.insert(offset + j)
          }
        }
      }
      paper.row(marks(groups[0], i) + marks(groups[1], i), widths: widths + widths, size: 10,
                mono: true, cleared: cleared, unused: unused)
    }
    if game.rows.isEmpty { paper.paragraph("No throws recorded.", size: 11) }
    paper.space(6)
    paper.paragraph("Heavy rule = field cleared after that baton. Hatching = no baton thrown.", size: 10)
    paper.paragraph("I  inkast     A  advantage (* inferred)     F  field     B  base     K  king     -  miss     X  unthrown", size: 10)
  }

  private static func stats(_ game: Analysis, read: GameRead?, paper: ReportPage) {
    paper.begin("Game stats")
    paper.heading("Team comparison")
    let sides = [game.first, game.first.other]
    let widths: [CGFloat] = [244, 240, 240]
    func header() {
      paper.row(["", game.name(sides[0]), game.name(sides[1])], widths: widths, size: 12, bold: true, shaded: true)
    }
    header()
    func metric(_ label: String, _ value: (Side, Analysis.SideStats) -> String) {
      if paper.remaining < 25 { paper.begin(); header() }
      paper.row([label] + sides.map { side in game.stats(side).map { value(side, $0) } ?? "—" }, widths: widths)
    }
    metric("Batons hit / thrown") { _, s in "\(s.hits) / \(s.batons)    \(percent(s.hitPct))" }
    metric("Field / base / kings felled") { _, s in "\(s.field) / \(s.base) / \(s.kings)" }
    metric("First-baton efficiency") { _, s in "\(s.effF) / \(s.effI)    \(percent(s.efficiency))" }
    metric("Last base felled") { side, s in
      guard let n = s.zeroBaseAt else { return "Not reached" }
      let spot = read?.figures(side).zeroBase
      return "Throw \(n)" + (spot.map { " · turn \($0.turn), baton \($0.baton)" } ?? "")
    }
    metric("Rethrows / kubbs thrown in") { _, s in "\(s.R) / \(s.I + s.Y)    \(percent(s.rethrowPct))" }
    metric("Punishments / rescues / failed rescues") { _, s in "\(s.P) / \(s.Q) / \(s.Y)" }
    metric("Field cleared / turns with field kubbs") { _, s in
      let avg = s.btcAvg.map { String(format: " · %.1f batons per clear", $0) } ?? ""
      return "\(s.btc.count) / \(s.btc.count + s.uncleared)" + avg
    }
    metric("Misses / missed king shots / illegal king hits") { _, s in "\(s.misses) / \(s.kingMisses) / \(s.illegal)" }
    metric("Longest hit / miss streak") { _, s in "\(s.hotStreak) / \(s.coldStreak)" }
    metric("Kubbs resting on another kubb") { _, s in "\(s.N)" }
    metric("Best blast") { _, s in "\(s.bestBlast)" }
    metric("Advantage turns · batons hit / thrown") { _, s in "\(s.advTurns) · \(s.advHits) / \(s.advBatons)" }
    if let read {
      metric("From 8 metres · hits / attempts") { side, _ in
        let t = read.figures(side).from8
        return "\(t.hits) / \(t.batons)    \(percent(t.pct))"
      }
    }
    paper.heading("Player stats")
    if game.players.isEmpty { paper.paragraph("No individual throws were attributed in this file.", size: 11) }
    else {
      let playerWidths: [CGFloat] = [214, 190, 84, 68, 56, 56, 56]
      func playersHeader() {
        paper.row(["Player", "Team", "Hits / throws", "Hit %", "Field", "Base", "Kings"],
                  widths: playerWidths, bold: true, shaded: true)
      }
      playersHeader()
      for side in sides {
        for p in game.players where p.side == side {
          if paper.remaining < 25 { paper.begin(); playersHeader() }
          paper.row([p.name ?? p.id, game.name(side), "\(p.hits) / \(p.batons)", percent(p.hitPct),
                     "\(p.field)", "\(p.base)", "\(p.kings)"], widths: playerWidths)
        }
      }
      paper.paragraph("Player totals use recorded throwers and Throwing Wood’s named solo sides.", size: 10)
    }
  }
}

/// Absolute geometry is in points on a landscape US Letter page. Text and table
/// cells wrap and paginate even when one imported name or note fills several pages.
final class ReportPage {
  let context: CGContext
  let left: CGFloat = 34
  let width: CGFloat = 724
  private(set) var y: CGFloat = 0
  var remaining: CGFloat { y - 45 }
  private var number = 0
  private var section = ""
  init(_ context: CGContext) { self.context = context }

  private func lines(_ text: String, width: CGFloat, size: CGFloat, bold: Bool, mono: Bool) -> [CTLine] {
    let face = mono ? "Menlo" : (bold ? "HelveticaNeue-Bold" : "HelveticaNeue")
    let font = CTFontCreateWithName(face as CFString, size, nil)
    let attributes = [NSAttributedString.Key(kCTFontAttributeName as String): font]
    return text.components(separatedBy: .newlines).flatMap { part -> [CTLine] in
      let string = NSAttributedString(string: part, attributes: attributes)
      let typesetter = CTTypesetterCreateWithAttributedString(string)
      var at = 0
      var result: [CTLine] = []
      if string.length == 0 { return [CTLineCreateWithAttributedString(string)] }
      while at < string.length {
        var count = CTTypesetterSuggestLineBreak(typesetter, at, Double(width))
        if count == 0 {
          count = (part as NSString).rangeOfComposedCharacterSequence(at: at).length
        }
        result.append(CTTypesetterCreateLine(typesetter, CFRange(location: at, length: count)))
        at += count
      }
      return result
    }
  }

  func label(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat, bold: Bool = false) {
    if let line = lines(text, width: width, size: size, bold: bold, mono: false).first { draw(line, x, y) }
  }

  private func draw(_ line: CTLine, _ x: CGFloat, _ y: CGFloat) {
    context.textPosition = CGPoint(x: x, y: y)
    CTLineDraw(line, context)
  }

  func begin(_ name: String? = nil) {
    if number > 0 { context.endPDFPage() }
    context.beginPDFPage(nil)
    context.textMatrix = .identity
    context.setFillColor(gray: 0.1, alpha: 1)
    number += 1
    if let name { section = name }
    label("KUBB: PITCHSIDE", x: left, y: 578, size: 11, bold: true)
    label(section, x: left + 520, y: 578, size: 11)
    rule(568)
    label("Score sheet · Page \(number)", x: left, y: 22, size: 9)
    y = 551
  }

  func rule(_ at: CGFloat) {
    context.setStrokeColor(gray: 0.65, alpha: 1)
    context.setLineWidth(0.55)
    context.strokeLineSegments(between: [CGPoint(x: left, y: at), CGPoint(x: left + width, y: at)])
  }

  func space(_ amount: CGFloat) { y -= amount }
  func require(_ amount: CGFloat) { if remaining < amount { begin() } }
  func heading(_ text: String) {
    require(60)
    space(6)
    paragraph(text, size: 17, bold: true)
    space(3)
  }

  func paragraph(_ text: String, size: CGFloat, bold: Bool = false, mono: Bool = false, leading: CGFloat = 1.4) {
    for line in lines(text, width: width, size: size, bold: bold, mono: mono) {
      require(size * leading)
      draw(line, left, y - size)
      space(size * leading)
    }
  }

  func row(_ cells: [String], widths: [CGFloat], size: CGFloat = 11, bold: Bool = false,
           mono: Bool = false, shaded: Bool = false, cleared: Set<Int> = [], unused: Set<Int> = []) {
    let columns = zip(cells, widths).map { lines($0, width: $1 - 8, size: size, bold: bold, mono: mono) }
    let height = size * 1.35
    let count = columns.map(\.count).max() ?? 1
    require(min(480, CGFloat(count) * height + 6))
    space(3)
    for i in 0..<count {
      require(height)
      if shaded {
        context.saveGState()
        context.setFillColor(gray: 0.92, alpha: 1)
        context.fill(CGRect(x: left, y: y - height, width: width, height: height))
        context.restoreGState()
      }
      var x = left
      for (j, pair) in zip(columns, widths).enumerated() {
        let (column, w) = pair
        if unused.contains(j) {
          context.saveGState()
          context.clip(to: CGRect(x: x, y: y - height, width: w, height: height))
          context.setStrokeColor(gray: 0.82, alpha: 1)
          context.setLineWidth(0.5)
          for start in stride(from: x - height, to: x + w, by: 5) {
            context.strokeLineSegments(between: [CGPoint(x: start, y: y - height), CGPoint(x: start + height, y: y)])
          }
          context.restoreGState()
        }
        if cleared.contains(j) {
          context.saveGState()
          context.setStrokeColor(red: 0.12, green: 0.34, blue: 0.24, alpha: 1)
          context.setLineWidth(2)
          context.strokeLineSegments(between: [CGPoint(x: x + w - 1, y: y), CGPoint(x: x + w - 1, y: y - height)])
          context.restoreGState()
        }
        if column.indices.contains(i) { draw(column[i], x + 4, y - size) }
        x += w
      }
      space(height)
    }
    space(3)
    rule(y)
  }
}
