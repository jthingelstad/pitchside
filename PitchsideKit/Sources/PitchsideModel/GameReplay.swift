import Foundation
import Notation

public typealias ReplayPlace = TurnRecording.Place

extension ReplayPlace {
  public func world(in side: Side) -> PitchFrame.World {
    let p = RecordPoint(across: across, depth: depth)
    return cell ? PitchFrame.cellMiddle(p, half: side) : PitchFrame.world(p, half: side)
  }

  fileprivate var metreCell: ReplayPlace {
    .init(across: min(4, floor(across)), depth: min(3, floor(depth)), cell: true)
  }

  fileprivate func sameSpot(_ other: ReplayPlace) -> Bool {
    across == other.across && depth == other.depth && cell == other.cell
  }
}

/// Immutable pitch states after each play the journal or notation can distinguish.
public struct GameReplay: Identifiable, Sendable {
  public let id = UUID()
  public let names: [Side: String]
  public private(set) var steps: [Step] = []
  public private(set) var turnStarts: [Int] = []

  public struct Standing: Equatable, Sendable {
    public fileprivate(set) var count = 0
    public fileprivate(set) var places: [ReplayPlace] = []
    public var unknown: Int { count - places.count }

    /// A later located fall establishes that the piece stood there until its baton.
    /// Match as a multiset, refining a metre cell when the file supplies a point.
    fileprivate mutating func confirm(_ evidence: [ReplayPlace]) {
      guard !evidence.isEmpty, evidence.count <= count else { return }
      var unused = places
      var confirmed: [ReplayPlace] = []
      for observed in evidence {
        var p = observed
        p.inferredFromFall = true
        let i = unused.firstIndex { $0.sameSpot(p) } ?? unused.firstIndex {
          ($0.cell || p.cell) && $0.metreCell == p.metreCell
        }
        if let i {
          let old = unused.remove(at: i)
          confirmed.append(old.cell && !p.cell ? p : old)
        } else {
          confirmed.append(p)
        }
      }
      places = confirmed.count + unused.count <= count ? confirmed + unused : confirmed
    }

    /// If both sides of an unlocated hit have a complete layout at matching
    /// precision, their multiset difference identifies the falls by elimination.
    fileprivate func inferredFalls(from before: Standing, number: Int) -> [ReplayPlace] {
      guard number > 0, before.unknown == 0, unknown == 0, before.count - count == number else { return [] }
      var removed = before.places
      for survivor in places {
        guard let i = removed.firstIndex(where: { $0.sameSpot(survivor) }) else { return [] }
        removed.remove(at: i)
      }
      return removed
    }

    fileprivate mutating func fell(_ n: Int, at hits: [ReplayPlace]) {
      guard n > 0 else { return }
      let remaining = max(0, count - n)
      if remaining == 0 {
        self = Standing()
        return
      }
      var missing = n
      for hit in hits.prefix(n) {
        missing -= 1
        if hit.cell {
          let matches = places.indices.filter { places[$0].metreCell == hit }
          guard let first = matches.first else { continue }
          // Where several exact points share this cell, only their remaining
          // number in the cell can be known after a cell-precision fall.
          for i in matches {
            var cell = hit
            cell.inferredFromFall = places[i].inferredFromFall
            places[i] = cell
          }
          places.remove(at: first)
        } else if let i = places.firstIndex(where: { $0.sameSpot(hit) })
          ?? places.firstIndex(where: { $0.cell && $0.metreCell == hit.metreCell }) {
          places.remove(at: i)
        }
      }
      if missing > 0 {
        if let first = places.first, places.count == count - hits.count,
          places.allSatisfy({ $0.sameSpot(first) }) {
          places = Array(places.prefix(remaining))
        } else if let cell = places.first?.metreCell, places.count == count - hits.count,
          places.allSatisfy({ $0.metreCell == cell }) {
          places = Array(repeating: cell, count: remaining)
        } else {
          places = []
        }
      }
      count = remaining
      if places.count > count { places = [] }
    }
  }

  public struct Half: Equatable, Sendable {
    public fileprivate(set) var base = Standing()
    public fileprivate(set) var field = Standing()
  }

  public struct Step: Sendable {
    public let turn: Int
    public let team: Side
    public let phase: String
    public let title: String
    public let token: String
    public let board: [Side: Half]
    public let kingStanding: Bool
    public var falls: [ReplayPlace] = []
    public var inferredFalls: [ReplayPlace] = []
    public var unlocatedFalls = 0
    public var lays: [TurnRecording.Lay] = []
    public var placed: ReplayPlace?
    public var stance: ReplayPlace?
    public var advantage = false
    public var advantageDepth: Double?
    public var note: String?
    public var result: String?
  }

  private struct ObservedTurn {
    var inkast: [Step] = []
    var tosses = 0
    var skipped = 0
    var showAdvantage = false
    var pitch: [Side: Standing] = [:]
    var batons: [[Int: FieldPlacements.Placement]] = []
    var after: [[Side: Standing]] = []
    private var capture: RecordState.Switches?

    mutating func record(_ entry: TimelineEvent, after state: RecordState, field: inout FieldPlacements) {
      let before = entry.before
      let baton = entry.type == "baton"
      // Record mode freezes capture at the first throw. A later change applies next turn.
      let active = capture ?? before.capture
      if baton || (entry.type == "toss" && before.allows("toss")) { capture = active }
      if baton && batons.isEmpty { pitch = snapshot(before, turn: entry.turn, capture: active, field: field) }
      let hits = field.apply(entry.event, before: before, after: state, capturePitch: active.pitch)
      let fields = snapshot(state, turn: entry.turn, capture: active, field: field)
      if baton {
        batons.append(hits)
        after.append(fields)
      } else if batons.isEmpty {
        pitch = fields
      }
      if let step = GameReplay.inkastStep(entry, after: state, fields: fields, placements: field,
                                          capture: active, throwNumber: tosses + 1) {
        inkast.append(step)
        if entry.type == "toss" { tosses += 1 }
        showAdvantage = false
      } else if baton || state.over {
        showAdvantage = true
        if let left = before.inkast?.left, left > 0 { skipped = left }
      } else if entry.type == "advantage", state.phase == "batons" {
        showAdvantage = true
      }
    }

    private func snapshot(_ state: RecordState, turn: Int, capture: RecordState.Switches,
                          field: FieldPlacements) -> [Side: Standing] {
      var result: [Side: Standing] = [:]
      for half in Side.allCases {
        let side = state.side(half)
        let observed = field.aligned(in: half, state: state)
        let places: [ReplayPlace] = capture.pitch ? zip(side.fieldPositions, observed).map { cell, placement in
          let p = placement?.point ?? cell
          var place = ReplayPlace(across: p.across, depth: p.depth, cell: placement == nil,
                                  mark: placement != nil ? placement?.mark(in: turn) : cell.mark)
          place.tapped = placement != nil
          return place
        } : []
        result[half] = Standing(count: side.field, places: places)
      }
      return result
    }
  }

  /// Use the journal for the order and outcomes of observed tosses. The reader supplies
  /// the turn rows, baton tokens and result, including for games opened from text alone.
  public init(_ a: Analysis, journal: EventLog) throws {
    var turns: [Int: ObservedTurn] = [:]
    var field = FieldPlacements()
    if let setup = journal.events.first(where: { $0.kind == GameEvent.Kind.start })?.payload["setup"] {
      try RecordScorer.walk(setup: setup, records: RecordScorer.fold(journal.events)) { entry, after in
        guard !entry.before.over else { return }
        turns[entry.turn, default: ObservedTurn()].record(entry, after: after, field: &field)
      }
    }
    self.init(a, observations: turns)
  }

  private static func inkastStep(_ entry: TimelineEvent, after: RecordState, fields: [Side: Standing],
                                 placements: FieldPlacements, capture: RecordState.Switches, throwNumber: Int) -> Step? {
    let before = entry.before
    let def = entry.side.other
    let phase: String
    var title: String
    var details: [String] = []
    switch entry.type {
    case "toss" where before.next.kind == "toss":
      phase = "Inkast · throw \(throwNumber)"
      let rethrow = before.next.rethrow == true
      if after.king == "down" { title = "King felled by a kubb" }
      else if entry.event["result"] == "out" { title = rethrow ? "Rethrow out · punishment due" : "Kubb out" }
      else { title = rethrow ? "Rethrow in" : "Kubb in" }
      if capture.players, let id = entry.event["by"]?.string,
         let player = before.side(entry.side).players.first(where: { $0.id == id }) {
        title = "\(player.name) · \(title)"
      }
      if let remaining = after.inkast?.rescuable, let previous = before.inkast?.rescuable, previous > remaining {
        details.append("\(previous - remaining) rescued")
      } else if entry.event["rescueAttempt"] == true && !rethrow,
                after.inkast != nil || (entry.event["rescued"]?.number ?? 0) == 0 {
        details.append("Failed rescue")
      }
      if entry.event["onTop"] == true { details.append("Landed on another kubb") }
    case "punish" where before.allows("punish") && before.inkast?.punishPlaced != after.inkast?.punishPlaced:
      phase = "Inkast · placement"
      title = "Punishment kubb placed"
    default: return nil
    }
    var board: [Side: Half] = [:]
    for half in Side.allCases {
      let side = after.side(half)
      let bases = side.basePositions.map { ReplayPlace(across: $0.across + 0.5, depth: 4) }
      board[half] = Half(base: Standing(count: side.base, places: bases), field: fields[half] ?? Standing())
    }
    var step = Step(turn: entry.turn, team: entry.side, phase: phase, title: title, token: "",
                    board: board, kingStanding: after.king != "down")
    if capture.pitch, let p = placements.aligned(in: def, state: after).compactMap({ $0 }).first(where: { $0.id == entry.id }) {
      var place = ReplayPlace(across: p.point.across, depth: p.point.depth, mark: p.mark(in: entry.turn))
      place.tapped = true
      step.placed = place
    }
    if !details.isEmpty { step.note = details.joined(separator: " · ") }
    return step
  }

  public init(_ a: Analysis) { self.init(a, observations: [:]) }

  private init(_ a: Analysis, observations: [Int: ObservedTurn]) {
    names = [.A: a.name(.A), .B: a.name(.B)]
    var setup = Half()
    setup.base.count = a.rules.baseKubbs
    if setup.base.count == 5 {
      setup.base.places = (0..<5).map { .init(across: Double($0) + 0.5, depth: 4) }
    }
    var board: [Side: Half] = [.A: setup, .B: setup]
    var king = true

    for row in a.rows {
      if let end = a.endTurn, row.turn > end { break }
      let att = row.team, def = att.other
      let rec = row.recording
      let words = row.batons.enumerated().map { i, baton -> ([ReplayPlace], [ReplayPlace]) in
        guard baton.isThrown, baton.kind == "hit" else { return ([], []) }
        let f = baton.f ?? 0
        let hits = i < rec.falls.count ? rec.falls[i] ?? [] : []
        let complete = f <= hits.count && hits.count - f == (baton.b ?? 0)
        let local = observations[row.turn]?.batons
        let selected = local.flatMap { $0.indices.contains(i) ? $0[i] : nil } ?? [:]
        var located: [ReplayPlace] = selected.keys.sorted().compactMap { slot in
          guard slot < f, let p = selected[slot]?.point else { return nil }
          var place = ReplayPlace(across: p.across, depth: p.depth)
          place.tapped = true
          return place
        }
        guard complete else { return (located, []) }
        // The notation writer sorts falls by cell. The journal keeps selection order.
        let fields = hits.prefix(f).map { cell in
          guard let index = located.firstIndex(where: { $0.metreCell == cell.metreCell }) else { return cell }
          return located.remove(at: index)
        }
        return (fields, Array(hits.dropFirst(f)))
      }
      var futureField = ArraySlice(words.flatMap(\.0))
      var futureBase = ArraySlice(words.flatMap(\.1))
      func frame(_ phase: String, _ title: String, _ token: String = "") -> Step {
        Step(turn: row.turn, team: att, phase: phase, title: title, token: token, board: board, kingStanding: king)
      }

      turnStarts.append(steps.count)
      let observedTurn = observations[row.turn]
      let inkast = observedTurn?.inkast ?? []
      steps.append(contentsOf: inkast)
      if let own = rec.pitch[att], own.count == board[att]?.field.count {
        board[att, default: Half()].field.places = own
      }
      if let own = observedTurn?.pitch[att], own.places.contains(where: \.tapped), own.count == board[att]?.field.count {
        board[att]?.field.places = own.places
      }
      if !rec.lays.isEmpty {
        let carried = max(0, row.startField - row.inkast)
        let positions = rec.pitch[def]?.filter { $0.mark == "s" } ?? []
        board[def, default: Half()].field = Standing(count: carried, places: positions.count <= carried ? positions : [])
        var lay = frame("Inkast", "Before the kubbs were raised")
        lay.lays = rec.lays
        steps.append(lay)
      }
      var target = board[def, default: Half()]
      target.field.count = row.startField
      if let observed = observedTurn?.pitch[def], observed.places.contains(where: \.tapped), observed.count == row.startField {
        target.field.places = observed.places
      } else if let pitch = rec.pitch[def], pitch.count == row.startField {
        target.field.places = pitch
      } else {
        // An inkast can move kubbs left over on the receiving half. Without a
        // fresh pitch line, only this turn’s located falls confirm their spots.
        if row.inkast > 0 || (row.ink?.Q ?? 0) > 0 || target.field.places.count > row.startField {
          target.field.places = []
        }
        target.field.confirm(Array(futureField))
      }
      target.base.confirm(Array(futureBase))
      board[def] = target
      if row.ink?.E == true { king = false }
      let hasInkast = row.inkastRecorded || row.inkast > 0
      if inkast.isEmpty {
        steps.append(frame(hasInkast ? "Inkast" : (row.turn == 1 ? "Opening pitch" : "Start of turn"),
                           hasInkast ? Self.inkastTitle(row) : "\(a.name(att)) to throw",
                           rec.inkasts.joined(separator: " ")))
      } else if let skipped = observedTurn?.skipped, skipped > 0 {
        steps.append(frame("Inkast", "\(skipped) unrecorded \(skipped == 1 ? "throw" : "throws") counted in"))
      }

      var line: Double?
      if row.advantage && king && (inkast.isEmpty || observedTurn?.showAdvantage == true) {
        let own = board[att, default: Half()].field
        if let m = rec.advantageMeters, (0...4).contains(m) { line = 4 - m }
        else if own.unknown == 0, own.places.allSatisfy({ !$0.cell }) { line = own.places.map(\.depth).min() }
        var advantage = frame(row.advantageMarked == nil ? "Advantage (inferred)" : "Advantage", "\(a.name(att)) has the advantage", row.advantageMarked?.raw ?? "")
        advantage.advantage = true
        advantage.advantageDepth = line
        steps.append(advantage)
      }
      var number = 0
      for (i, b) in row.batons.enumerated() {
        guard king, b.void != true, b.kind != "unthrown" else { continue }
        if b.kind == "win" || b.kind == "resign" {
          steps.append(frame("Game over", b.kind == "resign" ? "\(a.name(att)) resigned" : "Game called for \(a.name(att))", b.raw))
          break
        }
        guard b.isThrown else { continue }
        number += 1
        let (fields, bases) = words[i]
        futureField = futureField.dropFirst(fields.count)
        futureBase = futureBase.dropFirst(bases.count)
        let f = b.f ?? 0, base = b.b ?? 0
        let before = target
        if b.kind == "hit" {
          target.field.fell(f, at: fields)
          target.base.fell(base, at: bases)
          if f > 0 { target.field.confirm(Array(futureField)) }
          if base > 0 { target.base.confirm(Array(futureBase)) }
          if let layouts = observations[row.turn]?.after, layouts.indices.contains(i),
             let surviving = layouts[i][def], surviving.places.contains(where: \.tapped), surviving.count == target.field.count {
            target.field.places = surviving.places
          }
          board[def] = target
        }
        if b.kind == "king" || b.kind == "illegalking" || b.e == true { king = false }
        var title = Self.outcome(b)
        if let id = b.player {
          let name = a.players.first { $0.id == id && $0.side == att }?.name ?? id
          title = "\(name) · \(title)"
        }
        var step = frame("Baton \(number)", title, b.raw)
        step.falls = fields + bases
        if step.falls.isEmpty {
          step.inferredFalls = target.field.inferredFalls(from: before.field, number: f)
            + target.base.inferredFalls(from: before.base, number: base)
        }
        let (total, overflow) = f.addingReportingOverflow(base)
        step.unlocatedFalls = (overflow ? Int.max : total) - step.falls.count - step.inferredFalls.count
        step.stance = i < rec.stances.count ? rec.stances[i] : nil
        step.advantage = row.advantage && !["king", "kingmiss"].contains(b.kind)
        step.advantageDepth = step.advantage ? line : nil
        steps.append(step)
      }
      if let note = row.note, !note.isEmpty {
        let last = steps.count - 1
        steps[last].note = [steps[last].note, note].compactMap { $0 }.joined(separator: " · ")
      }
    }
    if let w = a.winner, !steps.isEmpty {
      steps[steps.count - 1].result = "\(a.name(w)) won · \(a.resultDetail)"
    }
  }

  private static func inkastTitle(_ row: Analysis.Row) -> String {
    var parts = ["\(row.inkast) \(row.inkast == 1 ? "kubb" : "kubbs") thrown in"]
    if !row.inkastRecorded { parts[0] += " (inferred)" }
    if let k = row.ink {
      for (n, name) in [(k.R, "rethrow"), (k.P, "punishment"), (k.Q, "rescue"),
                        (k.Y, "failed rescue"), (k.N, "neighbour")] where n > 0 {
        parts.append("\(n) \(name)\(n == 1 ? "" : "s")")
      }
      if k.E { parts.append("king down") }
    }
    return parts.joined(separator: " · ")
  }

  private static func outcome(_ b: Analysis.Baton) -> String {
    switch b.kind {
    case "hit":
      var parts: [String] = []
      if let n = b.f, n > 0 { parts.append("\(n) field") }
      if let n = b.b, n > 0 { parts.append("\(n) base") }
      if b.e == true { parts.append("king felled early") }
      return parts.joined(separator: " + ") + (b.e == true ? "" : " down")
    case "miss": return "Miss"
    case "kingmiss": return "King shot missed"
    case "king": return "King down"
    case "illegal": return "Illegal throw"
    case "illegalking": return "King felled early"
    default: return b.raw
    }
  }
}
