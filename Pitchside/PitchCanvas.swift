import Notation
import PitchsideDesign
import PitchsideModel
import SwiftUI

/// The pitch as record mode says it stands, drawn from where the scorer watches
/// (`PitchFrame.View`): rough around the 5 by 8 m grass, chalk, six stakes, the half under
/// attack lighter, the advantage line, every kubb standing (both teams' the same square,
/// with the side's letter cue on the chips), the king, the thrower's spot, and each team's
/// chip by its baseline. Taps on kubbs mark them; a tap anywhere else goes to the screen
/// as a point on the pitch.
struct PitchCanvas: View {
  @Bindable var screen: ScorerScreen

  struct Piece: Identifiable {
    enum Kind { case field, base, owed, king }
    let id: String
    let kind: Kind
    let side: Side
    let at: PitchFrame.World
    let target: ScorerScreen.Target?
    let mark: String?
    let label: String
  }

  var body: some View {
    GeometryReader { g in
      let geo = Geo(size: g.size, view: screen.view)
      ZStack(alignment: .topLeading) {
        Color.psRough.contentShape(Rectangle())
          .accessibilityLabel("Pitch position")
          .accessibilityRepresentation { accessibleSpots }

        grass(geo)
        ForEach(Array(screen.fallen.enumerated()), id: \.offset) { i, at in
          let group = screen.fallen.indices.filter { screen.fallen[$0] == at }
          let location = spread(at, index: group.firstIndex(of: i) ?? 0, count: group.count)
          RoundedRectangle(cornerRadius: 3).fill(Color.psKubbRest)
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.psKubbInk, lineWidth: 2))
            .frame(width: 26, height: 12).rotationEffect(.degrees(screen.view.isSideways ? 62 : 28))
            .position(geo.point(location)).accessibilityHidden(true).allowsHitTesting(false)
        }
        ForEach(pieces) { piece in kubb(piece, geo) }
        if screen.isInkast && !screen.placing && !screen.punishPending, screen.positionsOn {
          let ghost = geo.half(screen.defender)
          Circle().strokeBorder(Color.psChalk, style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
            .frame(width: 34, height: 34).position(x: ghost.midX, y: ghost.midY)
            .allowsHitTesting(false).accessibilityHidden(true)
        }
        if let s = screen.stance, screen.stanceOn, !screen.over, !screen.isInkast {
          let p = geo.point(
            PitchFrame.World(x: s.across, y: screen.attacker == .A ? 4 - s.depth : 4 + s.depth))
          Circle().strokeBorder(Color.psChalk, style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
            .frame(width: 40, height: 40)
            .overlay(
              Circle().fill(Color.psKubbRest).frame(width: 16, height: 16)
                .overlay(Circle().strokeBorder(Color.psKubbInk, lineWidth: 2))
            )
            .position(p)
            .allowsHitTesting(false)
            .accessibilityLabel("Throwing spot \(screen.word(s))")
        }
        // Overlapping 48-point hit areas in a drilled group belong to the nearest
        // centre. Each piece also has its own named VoiceOver button below this layer.
        Color.clear.contentShape(Rectangle()).onTapGesture(coordinateSpace: .local) { location in
          let hits = pieces.compactMap { piece -> (ScorerScreen.Target, CGFloat)? in
            guard let target = piece.target else { return nil }
            let centre = geo.point(piece.at)
            let dx = abs(centre.x - location.x)
            let dy = abs(centre.y - location.y)
            return dx <= 24 && dy <= 24 ? (target, dx * dx + dy * dy) : nil
          }
          if let hit = hits.min(by: { $0.1 < $1.1 }) {
            screen.toggle(hit.0)
          } else {
            screen.tap(geo.world(location))
          }
        }.accessibilityHidden(true)
        chip(screen.defender, geo)
        chip(screen.attacker, geo)
        if screen.advantageShown && screen.isBaton && !screen.placing && !screen.punishPending {
          advantage(geo)
        }
      }
    }
    .clipped()
    .accessibilityElement(children: .contain)
    .accessibilityLabel(summary)
    .accessibilityIdentifier("pitch")
  }

  /// VoiceOver can select the same one-metre cells a sighted scorer taps.
  @ViewBuilder var accessibleSpots: some View {
    let placing = screen.placing || screen.punishPending || (screen.isInkast && screen.positionsOn)
    if placing || (screen.stanceOn && !screen.isInkast) {
      let side = placing ? screen.placingHalf : screen.attacker
      ForEach(0..<5) { x in
        ForEach(0..<(placing ? 4 : 5), id: \.self) { d in
          Button("Team \(side.rawValue), across \(x), depth \(d)") {
            let point = RecordPoint(
              across: Double(x) + 0.5, depth: placing ? Double(d) + 0.5 : Double(d))
            screen.tap(PitchFrame.world(point, half: side))
          }
        }
      }
    }
  }

  // MARK: Geometry

  /// The drawn pitch's rectangle in the canvas, and the map both ways.
  struct Geo {
    let rect: CGRect
    let view: PitchFrame.View
    let unit: CGFloat

    init(size: CGSize, view: PitchFrame.View) {
      self.view = view
      let pad: CGFloat = view.isSideways ? 20 : 34
      let room = CGSize(
        width: max(100, size.width - pad * 2), height: max(100, size.height - pad * 2))
      let aspect: CGFloat = view.isSideways ? 8 / 5 : 5 / 8
      var w = room.width
      var h = w / aspect
      if h > room.height {
        h = room.height
        w = h * aspect
      }
      rect = CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
      unit = view.isSideways ? w / 8 : w / 5
    }

    func point(_ p: PitchFrame.World) -> CGPoint {
      let s = PitchFrame.screen(p, in: view)
      return CGPoint(x: rect.minX + s.u * rect.width, y: rect.minY + s.v * rect.height)
    }

    func world(_ p: CGPoint) -> PitchFrame.World {
      PitchFrame.world(
        PitchFrame.Screen(u: (p.x - rect.minX) / rect.width, v: (p.y - rect.minY) / rect.height),
        in: view)
    }

    /// A half of the pitch as a rectangle on screen.
    func half(_ side: Side) -> CGRect {
      let a = point(PitchFrame.World(x: 0, y: side == .A ? 0 : 4))
      let b = point(PitchFrame.World(x: 5, y: side == .A ? 4 : 8))
      return CGRect(
        x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
  }

  // MARK: Drawing

  func grass(_ geo: Geo) -> some View {
    let r = geo.rect
    let target = screen.over ? nil : screen.placingHalf
    let c1 = geo.point(.init(x: 0, y: 4))
    let c2 = geo.point(.init(x: 5, y: 4))
    return ZStack(alignment: .topLeading) {
      Rectangle().fill(Color.psGrass).frame(width: r.width, height: r.height).offset(
        x: r.minX, y: r.minY)
      if let target {
        let h = geo.half(target)
        Rectangle().fill(
          Color.white.opacity(
            screen.isInkast || screen.placing || screen.punishPending ? 0.22 : 0.12)
        )
        .frame(width: h.width, height: h.height).offset(x: h.minX, y: h.minY)
        if screen.isInkast || screen.placing || screen.punishPending {
          Rectangle().strokeBorder(Color.psChalk, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
            .frame(width: h.width, height: h.height).offset(x: h.minX, y: h.minY)
        }
      }
      Rectangle().strokeBorder(Color.psChalk, lineWidth: 3).frame(width: r.width, height: r.height)
        .offset(x: r.minX, y: r.minY)
      Path { p in
        p.move(to: c1)
        p.addLine(to: c2)
      }
      .stroke(Color.psChalk, lineWidth: 2)
      ForEach(0..<6, id: \.self) { i in
        let s = geo.point(.init(x: i % 2 == 0 ? 0 : 5, y: Double(i / 2) * 4))
        RoundedRectangle(cornerRadius: 2).fill(Color.psKubb)
          .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Color.psKubbInk, lineWidth: 1.5))
          .frame(width: 10, height: 10)
          .position(s)
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  func advantage(_ geo: Geo) -> some View {
    let half = geo.half(screen.attacker)
    return ZStack(alignment: .topLeading) {
      if let depth = screen.advantageDepth {
        let y = screen.attacker == .A ? 4 - depth : 4 + depth
        let a = geo.point(.init(x: 0, y: y))
        let b = geo.point(.init(x: 5, y: y))
        Path { p in
          p.move(to: a)
          p.addLine(to: b)
        }
        .stroke(Color.psChalk, style: StrokeStyle(lineWidth: 3, dash: [9, 6]))
        Chip("Advantage line").fixedSize()
          .position(
            x: geo.view.isSideways ? a.x : geo.rect.minX + 65,
            y: geo.view.isSideways ? geo.rect.maxY + 16 : a.y + 16)
      } else {
        Chip("Advantage in use").fixedSize().position(x: half.midX, y: half.midY)
      }
    }.allowsHitTesting(false)
  }

  func chip(_ side: Side, _ geo: Geo) -> some View {
    let s = screen.state.side(side)
    let base = geo.point(.init(x: 2.5, y: side == .A ? 0 : 8))
    let out: CGFloat = 18
    let pos: CGPoint
    if geo.view.isSideways {
      pos = CGPoint(
        x: geo.rect.minX + geo.rect.width * (side == .A ? 0.24 : 0.76), y: geo.rect.minY - out)
    } else {
      pos = CGPoint(x: base.x, y: base.y + (base.y < geo.rect.midY ? -out : out))
    }
    return HStack(spacing: 6) {
      TeamMarker(side, size: 18)
      Text(
        geo.view.isSideways
          ? "\(screen.teamName(side)) · \(s.base + s.field)"
          : "\(screen.teamName(side)) · \(s.base + s.field) standing"
      )
      .font(PSFont.body(14, .bold)).lineLimit(2)
    }
    .foregroundStyle(Color.psText)
    .padding(.horizontal, 8)
    .padding(.vertical, 3)
    .background(Color.psPlate, in: RoundedRectangle(cornerRadius: 6))
    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.psLine, lineWidth: 2))
    .fixedSize(horizontal: false, vertical: true)
    .frame(maxWidth: geo.view.isSideways ? geo.rect.width * 0.5 : geo.rect.width)
    .position(pos)
    .allowsHitTesting(false)
  }

  /// Separate pieces sharing a metre cell, including pieces this baton just felled.
  private func spread(_ at: PitchFrame.World, index: Int, count: Int) -> PitchFrame.World {
    guard count > 1 else { return at }
    let angle = Double.pi / 3 + 2 * Double.pi * Double(index) / Double(count)
    return .init(x: at.x + 0.34 * cos(angle), y: at.y + 0.34 * sin(angle))
  }

  /// Every kubb to draw.
  var pieces: [Piece] {
    var out: [Piece] = []
    let st = screen.state
    for side in Side.allCases {
      let s = st.side(side)
      let isTarget = side == screen.defender && !screen.over
      // base kubbs on the baseline
      if s.baseComplete {
        for (i, c) in s.basePositions.enumerated() {
          let w = PitchFrame.World(x: c.across + 0.5, y: side == .A ? 0.12 : 7.88)
          out.append(
            Piece(
              id: "b\(side)\(i)", kind: .base, side: side, at: w,
              target: isTarget && screen.positionsOn && screen.isBaton && !screen.placing
                && !screen.punishPending ? .base(i) : nil, mark: nil,
              label: "Team \(side.rawValue) base kubb at across \(Int(c.across))"))
        }
      } else {
        for i in 0..<s.base {
          let x = 5.0 * (Double(i) + 0.5) / Double(max(s.base, 1))
          out.append(
            Piece(
              id: "b\(side)\(i)", kind: .base, side: side,
              at: .init(x: x, y: side == .A ? 0.12 : 7.88), target: nil,
              mark: nil, label: "Team \(side.rawValue) base kubb, place not recorded"))
        }
      }
      // field kubbs in this side's half: several in one cell are spread out
      var seen: [String: Int] = [:]
      for (i, c) in s.fieldPositions.enumerated() where screen.positionsOn {
        let key = "\(c.across),\(c.depth)"
        let k = seen[key, default: 0]
        seen[key] = k + 1
        let middle = PitchFrame.cellMiddle(c, half: side)
        let group = s.fieldPositions.filter { $0.across == c.across && $0.depth == c.depth }.count
        let w = spread(middle, index: k, count: group)
        out.append(
          Piece(
            id: "f\(side)\(i)", kind: .field, side: side, at: w,
            target: isTarget && screen.positionsOn && screen.isBaton && !screen.placing
              && !screen.punishPending ? .field(i) : nil, mark: c.mark,
            label:
              "Field kubb in Team \(side.rawValue)'s half, across \(Int(c.across)), depth \(Int(c.depth))"
              + (c.mark == "p" ? ", the punishment kubb" : "")))
      }
      // kubbs whose place is owed
      let owed = screen.positionsOn ? max(0, s.field - s.fieldPositions.count) : 0
      for i in 0..<owed {
        let x = 5.0 * (Double(i) + 0.5) / Double(owed)
        out.append(
          Piece(
            id: "o\(side)\(i)", kind: .owed, side: side, at: .init(x: x, y: side == .A ? 2 : 6),
            target: nil,
            mark: nil, label: "A field kubb in Team \(side.rawValue)'s half, its place not recorded"
          ))
      }
      if !screen.positionsOn {
        for i in 0..<s.field {
          let x = 5.0 * (Double(i) + 0.5) / Double(s.field)
          out.append(
            Piece(
              id: "n\(side)\(i)", kind: .field, side: side, at: .init(x: x, y: side == .A ? 2 : 6),
              target: nil,
              mark: nil, label: "A field kubb in Team \(side.rawValue)'s half"))
        }
      }
    }
    if st.king == "standing" {
      out.append(
        Piece(
          id: "king", kind: .king, side: .A, at: .init(x: 2.5, y: 4),
          target: screen.isKingShot ? .king : nil,
          mark: nil, label: "The king"))
    }
    return out
  }

  @ViewBuilder func kubb(_ piece: Piece, _ geo: Geo) -> some View {
    let p = geo.point(piece.at)
    let size = max(20, geo.unit * 0.42)
    let marked = piece.target.map { screen.marked.contains($0) } ?? false
    let isTarget =
      piece.target != nil
      && (piece.kind != .base || screen.state.next.targets == "base"
        || screen.markedField + screen.countField >= (screen.state.next.field ?? 0))
    let shape = RoundedRectangle(cornerRadius: 4)
    let drawn = Group {
      switch piece.kind {
      case .king:
        shape.fill(Color.psKubb)
          .overlay(shape.strokeBorder(Color.psKubbInk, lineWidth: 3))
          .overlay(
            Text("K").font(.custom("Inter", fixedSize: 15).weight(.black)).foregroundStyle(
              Color.psKubbInk)
          )
          .frame(
            width: size * (screen.isKingShot ? 1.5 : 1.25),
            height: size * (screen.isKingShot ? 1.5 : 1.25)
          )
          .background(screen.isKingShot ? shape.fill(Color.psChalk).padding(-4) : nil)
      case .owed:
        shape.fill(Color.psInside).overlay(
          shape.strokeBorder(Color.psLine, style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
        )
        .overlay(Text("?").font(PSFont.body(14, .heavy)).foregroundStyle(Color.psText))
        .frame(width: size, height: size)
      default:
        shape.fill(marked ? Color.psKubbInk : TeamMarker.fill(piece.side.marker))
          .overlay(shape.strokeBorder(Color.psKubbInk, lineWidth: isTarget ? 3 : 2))
          .overlay {
            if marked {
              Image(systemName: "checkmark").font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Color.psKubb)
            } else {
              Text(piece.side.rawValue).font(PSFont.body(14, .heavy))
                .foregroundStyle(TeamMarker.ink(piece.side.marker))
            }
          }
          .frame(width: isTarget ? size * 1.15 : size, height: isTarget ? size * 1.15 : size)
          .background {
            if piece.kind == .field && screen.positionsOn {
              Circle().strokeBorder(Color.psChalk, style: StrokeStyle(lineWidth: 2, dash: [2, 3]))
                .frame(width: size + 18, height: size + 18)
            }
          }
          .background(
            isTarget ? shape.fill(Color.psShade).offset(x: 2, y: 2) : nil)
      }
    }
    if let target = piece.target {
      Button {
        screen.toggle(target)
      } label: {
        drawn.frame(width: 48, height: 48).contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .position(p)
      .accessibilityIdentifier(piece.id)
      .accessibilityLabel(piece.label)
      .accessibilityValue(marked ? "marked down" : "standing")
      .accessibilityHint(
        piece.kind == .king ? "Tap if the king fell" : "Tap if this baton knocked it over")
    } else {
      drawn.position(p)
        .allowsHitTesting(false)
        .accessibilityLabel(piece.label)
    }
  }

  var summary: String {
    let s = screen.state
    let a = s.side(.A)
    let b = s.side(.B)
    return
      "The pitch, \(screen.view.title.lowercased()). \(screen.teamName(.A)): \(a.base) base and \(a.field) field kubbs standing. \(screen.teamName(.B)): \(b.base) base and \(b.field) field kubbs standing."
  }
}
