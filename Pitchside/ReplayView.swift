import Notation
import PitchsideDesign
import PitchsideModel
import SwiftUI

struct ReplayView: View {
  let replay: GameReplay
  let back: String
  let close: (() -> Void)?
  @Environment(\.dismiss) private var dismiss
  @State private var index = 0
  @State private var details = false
  @State private var view = PitchFrame.View.behindA
  @State private var viewport = PitchFrame.Viewport()

  init(replay: GameReplay, back: String = "Score sheet", startAtLast: Bool = false, close: (() -> Void)? = nil) {
    self.replay = replay
    self.back = back
    self.close = close
    _index = State(initialValue: startAtLast ? max(0, replay.steps.count - 1) : 0)
  }

  private var step: GameReplay.Step { replay.steps[index] }

  private var zoomFocus: PitchFrame.World {
    let half = step.team.other
    if let placed = step.placed { return placed.world(in: half) }
    let fallen = step.falls + step.inferredFalls
    let sites = fallen.isEmpty ? (step.board[half]?.field.places ?? []) : fallen
    guard !sites.isEmpty else { return .init(x: 2.5, y: half == .A ? 2 : 6) }
    let points = sites.map { $0.world(in: half) }
    return .init(x: points.map(\.x).reduce(0, +) / Double(points.count),
                 y: points.map(\.y).reduce(0, +) / Double(points.count))
  }

  var body: some View {
    VStack(spacing: 0) {
      ScreenHeader("Play by play", back: back) { if let close { close() } else { dismiss() } }
      HStack(spacing: 8) {
        Menu {
          ForEach(replay.turnStarts, id: \.self) { i in
            Button("Turn \(replay.steps[i].turn)") { index = i }
          }
          Button("Last play") { index = replay.steps.count - 1 }
        } label: {
          Label("Turn \(step.turn)", systemImage: "chevron.up.chevron.down")
            .font(PSFont.body(16, .bold)).padding(.horizontal, 8).frame(minHeight: 48).psBox()
        }.accessibilityLabel("Jump to turn").accessibilityValue("Turn \(step.turn)")
        TeamLabel(side: step.team, name: replay.names[step.team] ?? step.team.rawValue)
          .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
        icon(viewport.scale == 1 ? "plus.magnifyingglass" : "arrow.down.right.and.arrow.up.left",
             viewport.scale == 1 ? "Zoom in on pitch" : "Fit whole pitch") {
          if viewport.scale == 1 {
            viewport.move(from: PitchFrame.screen(zoomFocus, in: view), to: .init(u: 0.5, v: 0.5), magnification: 3)
          } else { viewport = .init() }
        }
        icon("rectangle.2.swap", "Change view") { view = view.next; viewport = .init() }
          .accessibilityValue(view.title)
      }.padding(.horizontal, 10).padding(.vertical, 6)
      pitch
      HStack(spacing: 12) {
        ForEach(Side.allCases, id: \.self) { side in
          if let h = step.board[side] {
            HStack(spacing: 5) {
              TeamMarker(side, size: 18)
              Text("\(h.base.count) base · \(h.field.count) field").font(PSFont.body(14, .bold))
            }.frame(maxWidth: .infinity)
          }
        }
      }.padding(.vertical, 6).background(Color.psInside)
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text(step.phase).psKick()
          if step.placed != nil { Text("○ placed this play").psHelp() }
          if !step.inferredFalls.isEmpty { Text("× inferred falls").psHelp() }
          else if !step.falls.isEmpty { Text("× fell this play").psHelp() }
          Spacer()
          if !step.token.isEmpty { Text(step.token).font(PSFont.mono(14)).lineLimit(1) }
        }
        Text(step.title).font(PSFont.display(24))
        if let result = step.result { Text(result).font(PSFont.body(16, .bold)) }
        if let note = step.note, !note.isEmpty { Text(note).font(PSFont.body(15)).lineLimit(2) }
        let missing = step.board.values.reduce(0) { $0 + $1.field.unknown + $1.base.unknown }
        if missing > 0 || step.unlocatedFalls > 0 {
          Text([missing > 0 ? "\(missing) standing without a known spot" : nil,
                step.unlocatedFalls > 0 ? "\(step.unlocatedFalls) down without a recorded spot" : nil]
            .compactMap { $0 }.joined(separator: " · ")).psHelp()
        }
        if step.board.values.contains(where: { ($0.field.places + $0.base.places).contains(where: \.inferredFromFall) }) {
          Text("Some standing spots are inferred from later falls.").psHelp()
        }
        if step.advantage && step.advantageDepth == nil {
          Text("Advantage · distance unknown").psHelp()
        }
      }
      .padding(12).frame(maxWidth: .infinity, alignment: .leading)
      .overlay(alignment: .top) { Divider() }
      HStack(spacing: 8) {
        Button("Previous") { index = max(0, index - 1) }.buttonStyle(.ps).disabled(index == 0)
        Button("Details") { details = true }.buttonStyle(.quiet)
        Button("Next") { index = min(replay.steps.count - 1, index + 1) }.buttonStyle(.psSolid).disabled(index + 1 == replay.steps.count)
      }
      .padding(.horizontal, 12).padding(.bottom, 6)
    }
    .background(Color.psGround).foregroundStyle(Color.psText)
    .onChange(of: step.turn) { viewport = .init() }
    .toolbar(.hidden, for: .navigationBar)
    .navigationDestination(isPresented: $details) {
      Screen(title: "Pitch details", back: "Play by play", onBack: { details = false }) {
        Text("Turn \(step.turn) · \(step.phase)").psKick()
        Text(step.title).font(PSFont.display(24))
        if !step.token.isEmpty { Text(step.token).font(PSFont.mono(15)) }
        if step.advantage {
          if let depth = step.advantageDepth {
            Text("Advantage line · \((4 - depth).formatted()) m from the baseline")
          } else {
            Text("Advantage line · distance unknown")
          }
        }
        if let note = step.note, !note.isEmpty { Text(note) }
        if let placed = step.placed { Text("Placed in Team \(step.team.other.rawValue)’s half · \(locations([placed]))") }
        if !step.falls.isEmpty { Text("Felled in Team \(step.team.other.rawValue)’s half · \(locations(step.falls))") }
        if !step.inferredFalls.isEmpty { Text("Inferred falls in Team \(step.team.other.rawValue)’s half · \(locations(step.inferredFalls))") }
        if step.unlocatedFalls > 0 { Text("\(step.unlocatedFalls) fall positions unrecorded") }
        if let stance = step.stance { Text("Throwing spot · Team \(step.team.rawValue) · \(stance.label)") }
        ForEach(step.lays.indices, id: \.self) { i in
          Text("Lay \(i + 1) · \(step.lays[i].first.label) / \(step.lays[i].last.label)")
        }
        ForEach(Side.allCases, id: \.self) { side in
          if let half = step.board[side] {
            TeamLabel(side: side, name: replay.names[side] ?? side.rawValue)
            Text(standing("Base", half.base))
            Text(standing("Field", half.field))
          }
        }
        Text(step.kingStanding ? "King standing" : "King down")
        Text("Coordinates are across the pitch and depth from the centre line, in metres.").psHelp()
      }.font(PSFont.body(16))
    }
  }

  private func standing(_ kind: String, _ group: GameReplay.Standing) -> String {
    var parts = ["\(kind) · \(group.count) standing"]
    if !group.places.isEmpty { parts.append(locations(group.places)) }
    if group.unknown > 0 { parts.append("\(group.unknown) unknown") }
    return parts.joined(separator: "\n")
  }

  private func locations(_ places: [ReplayPlace]) -> String {
    places.map { p in
      p.label + (p.tapped ? " (tapped)" : "") + (p.inferredFromFall ? " (from a later fall)" : "") + (p.mark == "p" ? " (punishment)" : p.mark == "s" ? " (carried over)" : "")
    }.joined(separator: " · ")
  }

  private func icon(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol).frame(width: 48, height: 48).psBox()
    }.buttonStyle(.plain).accessibilityLabel(label)
  }

  private var pitch: some View {
    GeometryReader { g in
      let geo = PitchGeometry(size: g.size, view: view, viewport: viewport, including: step.stance?.world(in: step.team))
      ZStack(alignment: .topLeading) {
        Color.psRough
        PitchGround(geo: geo, target: step.team.other)
          .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
        Canvas { ctx, _ in
          func point(_ p: ReplayPlace, _ side: Side) -> CGPoint { geo.point(p.world(in: side)) }
          func stroke(_ a: CGPoint, _ b: CGPoint, _ color: Color, width: CGFloat, dashed: Bool = false) {
            var path = Path()
            path.move(to: a)
            path.addLine(to: b)
            ctx.stroke(path, with: .color(color), style: .init(lineWidth: width, dash: dashed ? [6, 4] : []))
          }
          func marker(_ p: CGPoint, _ letter: String, fill: Color, ink: Color, size: CGFloat, fallen: Bool = false) {
            let rect = CGRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size)
            let shape = Path(roundedRect: rect, cornerRadius: 2)
            ctx.fill(shape, with: .color(fill))
            ctx.stroke(shape, with: .color(Color.psKubbInk), lineWidth: 2)
            if fallen {
              stroke(CGPoint(x: rect.minX+3, y: rect.minY+3), CGPoint(x: rect.maxX-3, y: rect.maxY-3), ink, width: 2)
              stroke(CGPoint(x: rect.maxX-3, y: rect.minY+3), CGPoint(x: rect.minX+3, y: rect.maxY-3), ink, width: 2)
            } else {
              ctx.draw(Text(letter).font(PSFont.body(14, .heavy)).foregroundColor(ink), at: p)
            }
          }
          if let depth = step.advantageDepth {
            stroke(point(.init(across: 0, depth: depth), step.team), point(.init(across: 5, depth: depth), step.team),
                   .psChalk, width: 3, dashed: true)
          }
          for side in Side.allCases {
            guard let half = step.board[side] else { continue }
            for group in [half.base, half.field] {
              let groups = Dictionary(grouping: group.places, by: { $0.label })
              for key in groups.keys.sorted() {
                guard let entries = groups[key], let place = entries.first else { continue }
                let p = point(place, side)
                if place.cell {
                  let unit = geo.unit * viewport.scale
                  ctx.stroke(Path(CGRect(x: p.x - unit/2, y: p.y - unit/2, width: unit, height: unit)),
                             with: .color(.psChalk), style: .init(lineWidth: 1.5, dash: [4, 4]))
                }
                marker(p, entries.count > 1 ? "\(entries.count)" : side.rawValue,
                       fill: TeamMarker.fill(side.marker), ink: TeamMarker.ink(side.marker), size: 18)
              }
            }
          }
          for lay in step.lays {
            stroke(point(lay.first, step.team.other), point(lay.last, step.team.other), .psKubbInk, width: 7)
            stroke(point(lay.first, step.team.other), point(lay.last, step.team.other), .psKubb, width: 3)
          }
          for p in step.falls + step.inferredFalls {
            marker(point(p, step.team.other), "", fill: .psKubbInk, ink: .psKubb, size: 16, fallen: true)
          }
          marker(geo.point(.init(x: 2.5, y: 4)), "K", fill: .psKubb, ink: .psKubbInk, size: 23, fallen: !step.kingStanding)
          let highlight = step.placed.map { point($0, step.team.other) } ?? step.stance.map { point($0, step.team) }
          if let p = highlight {
            let radius: CGFloat = step.placed == nil ? 10 : 15
            let ring = Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: 2 * radius, height: 2 * radius))
            ctx.stroke(ring, with: .color(.psKubbInk), lineWidth: 5)
            ctx.stroke(ring, with: .color(.psChalk), lineWidth: 2)
          }
        }.accessibilityHidden(true)
        PitchGestures(tap: { _ in }, move: { a, b, scale in
          viewport.move(from: geo.fittedPoint(a), to: geo.fittedPoint(b), magnification: scale)
        }).accessibilityHidden(true)
      }
      .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
    }
    .clipped()
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Pitch, \(view.title). " + Side.allCases.map { side in
      let h = step.board[side]
      return "Team \(side.rawValue), \(h?.base.count ?? 0) base, \(h?.field.count ?? 0) field standing."
    }.joined(separator: " "))
    .accessibilityHint("Open Details for positions")
    .accessibilityIdentifier("replayPitch")
  }
}
