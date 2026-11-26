import CoreGraphics
import Foundation
import Notation

/// All views are from the same sideline, A on the left. Each small pitch isolates
/// one observation so that successive throws into the same group stay legible.
enum PitchDiagramReport {
  private enum Mark { case standing, fall, stance }
  private static let tile: CGFloat = 103

  static func draw(_ rows: [Analysis.Row], on paper: ReportPage) {
    guard !rows.isEmpty else { return }
    let located = rows.contains { hasPositions($0.recording) }
    let section = located ? "Pitch diagrams" : "Turn details"
    func begin() {
      paper.begin(section)
      if located {
        paper.paragraph("A baseline at left, B at right. Dot = standing kubb, cross = fall, triangle = thrower, line = lay. Shading locates a 1 m cell.", size: 10)
        paper.paragraph("Each panel shows its recorded locations. A number counts kubbs at the same spot. A dash means no position was supplied.", size: 10)
      }
      paper.space(4)
    }
    begin()
    for row in rows {
      let r = row.recording
      let drawPitch = hasPositions(r)
      if paper.remaining < (drawPitch ? 115 : 52) { begin() }
      paper.paragraph("Turn \(row.turn) · Team \(row.team.rawValue)", size: 13, bold: true)
      paper.paragraph("\(row.scoringSummary) · \(row.hits) of \(row.thrown.count) batons hit · \(row.fieldLeft) field left", size: 11)
      if drawPitch {
        let depth = r.stances.compactMap { $0?.depth }.max() ?? 4
        let first = Plot(x: paper.left, top: paper.y, side: row.team, depth: depth, paper: paper)
        let hasStart = r.pitch.values.contains { !$0.isEmpty } || !r.lays.isEmpty
        first.frame("Before batons", located: hasStart)
        for (half, places) in r.pitch { first.marks(places, in: half, as: .standing) }
        for lay in r.lays { first.lay(lay, in: row.team.other) }
        for (i, baton) in row.batons.enumerated() {
          if i > 0 && i.isMultiple(of: 6) {
            paper.space(74)
            if paper.remaining < 102 { begin(); paper.paragraph("Turn \(row.turn) continued", size: 13, bold: true) }
          }
          let plot = Plot(x: paper.left + CGFloat(1 + i % 6) * tile, top: paper.y, side: row.team, depth: depth, paper: paper)
          let falls = i < r.falls.count ? r.falls[i] ?? [] : []
          let stance = i < r.stances.count ? r.stances[i] : nil
          let mark = baton.raw.split(separator: ":").last.map(String.init) ?? baton.raw
          let title = mark.count <= 8 ? "Baton \(i + 1) · \(mark)" : "Baton \(i + 1)"
          plot.frame(title, located: !falls.isEmpty || stance != nil, unthrown: baton.kind == "unthrown")
          plot.marks(falls, in: row.team.other, as: .fall)
          if let stance { plot.mark(stance, in: row.team, as: .stance) }
        }
        paper.space(74)
      }
      paper.space(4)
      paper.rule(paper.y)
      paper.space(4)
    }
  }

  private static func hasPositions(_ r: TurnRecording) -> Bool {
    r.pitch.values.contains { !$0.isEmpty } || !r.lays.isEmpty ||
      r.falls.contains { !($0 ?? []).isEmpty } || r.stances.contains { $0 != nil }
  }

  private struct Plot {
    let x: CGFloat
    let top: CGFloat
    let side: Side
    let depth: Double
    let paper: ReportPage
    private var extra: CGFloat { min(6, max(0, depth - 4)) }
    private var scale: CGFloat { 88 / (8 + extra) }
    private var origin: CGPoint { .init(x: x + 6 + (side == .A ? extra * scale : 0), y: top - 45) }
    private var c: CGContext { paper.context }

    func frame(_ name: String, located: Bool, unthrown: Bool = false) {
      paper.label(name, x: x + 5, y: top - 12, size: 9, bold: true)
      guard located else {
        paper.label(unthrown ? "Unthrown" : "—", x: x + 5, y: top - 47, size: 10)
        return
      }
      c.saveGState()
      c.setLineWidth(0.65)
      c.setStrokeColor(gray: 0.56, alpha: 1)
      c.stroke(CGRect(x: origin.x, y: origin.y - 2.5 * scale, width: 8 * scale, height: 5 * scale))
      let mid = origin.x + 4 * scale
      c.setLineDash(phase: 0, lengths: [2, 2])
      c.strokeLineSegments(between: [.init(x: mid, y: origin.y - 2.5 * scale), .init(x: mid, y: origin.y + 2.5 * scale)])
      c.restoreGState()
    }

    private func point(_ p: TurnRecording.Place, _ half: Side) -> CGPoint {
      let w = p.world(in: half)
      return .init(x: origin.x + w.y * scale, y: origin.y + (2.5 - w.x) * scale)
    }

    func lay(_ lay: TurnRecording.Lay, in half: Side) {
      c.saveGState()
      c.setStrokeColor(gray: 0.24, alpha: 1)
      c.setLineWidth(1.3)
      c.strokeLineSegments(between: [point(lay.first, half), point(lay.last, half)])
      c.restoreGState()
    }

    func marks(_ places: [TurnRecording.Place], in half: Side, as kind: Mark) {
      let groups = Dictionary(grouping: places) {
        TurnRecording.Place(across: $0.across, depth: $0.depth, cell: $0.cell)
      }
      for (place, group) in groups {
        mark(place, in: half, as: kind)
        if group.count > 1 {
          let p = point(place, half)
          paper.label("\(group.count)", x: place.cell ? p.x - 2 : min(x + 90, p.x + 3),
                      y: place.cell ? p.y - 2.5 : p.y + 2, size: 7, bold: true)
        }
      }
    }

    func mark(_ place: TurnRecording.Place, in half: Side, as mark: Mark) {
      let p = point(place, half)
      c.saveGState()
      defer { c.restoreGState() }
      if place.cell {
        c.setFillColor(gray: 0.75, alpha: 1)
        c.setStrokeColor(gray: 0.25, alpha: 1)
        c.setLineWidth(0.6)
        let cell = CGRect(x: p.x - scale / 2, y: p.y - scale / 2, width: scale, height: scale)
        c.fill(cell)
        c.stroke(cell)
        return
      }
      c.setFillColor(gray: 0.12, alpha: 1)
      c.setStrokeColor(gray: 0.12, alpha: 1)
      switch mark {
      case .standing:
        c.fillEllipse(in: CGRect(x: p.x - 1.8, y: p.y - 1.8, width: 3.6, height: 3.6))
      case .fall:
        c.setLineWidth(1.1)
        c.strokeLineSegments(between: [.init(x: p.x - 2.2, y: p.y - 2.2), .init(x: p.x + 2.2, y: p.y + 2.2),
                                      .init(x: p.x - 2.2, y: p.y + 2.2), .init(x: p.x + 2.2, y: p.y - 2.2)])
      case .stance:
        c.beginPath()
        c.move(to: .init(x: p.x, y: p.y + 3))
        c.addLine(to: .init(x: p.x - 3, y: p.y - 2.5))
        c.addLine(to: .init(x: p.x + 3, y: p.y - 2.5))
        c.closePath()
        c.fillPath()
      }
    }
  }
}
