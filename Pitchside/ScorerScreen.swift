import Foundation
import Notation
import Observation
import PitchsideModel

/// The scorer screen's own state: what is marked, where the thrower stands, which view,
/// which panel is open. The game itself is the scorer's (record mode); every choice the
/// screen offers comes from `state.next` and `state.allowed`.
@MainActor @Observable
final class ScorerScreen {
  /// A kubb on the pitch the scorer can tap.
  enum Target: Hashable {
    /// The n-th of the defending half's field kubbs (`fieldPositions`).
    case field(Int)
    /// The n-th of the defending side's base kubbs (`basePositions`).
    case base(Int)
    case king
  }

  /// What shows above the bottom bar besides the prompt. None of these is a dialog.
  enum Panel: Equatable {
    case none
    case rare
    case pick
    case capture
    case note
    case advantage
    case resign
    case call
    case warnings
    case coincident([Target])
  }

  @ObservationIgnored let scorer: LiveScorer
  private(set) var undoAction: ScoreAction?
  private(set) var redoAction: ScoreAction?
  private(set) var state: RecordState
  private(set) var rows: [RecordRow]
  private(set) var playsByTurn: [Int: [String]] = [:]
  private(set) var lastWarnings: [RecordWarning] = []
  private(set) var game: Game

  var view: PitchFrame.View
  var marked: [Target] = []
  var countField = 0
  var countBase = 0
  /// The observed spot for this turn, until moved or the king shot begins.
  var stance: RecordPoint?
  /// Who throws the next baton, when the scorer changed it.
  var pick: String?
  /// Who throws the kubbs in this turn (sticky within the turn).
  var inkastBy: String?
  var panel: Panel = .none
  var placing = false
  var punishLater = false
  var rescueAttempt = false
  var flash: String?
  var noteText = ""
  struct OwedPlace {
    let id: String
    let half: Side
    let turn: Int
    let punishment: Bool
  }
  private(set) var owed: [OwedPlace] = []
  private(set) var placements = FieldPlacements()
  private(set) var fallen: [PitchFrame.World] = []
  var placingHalf: Side { placing ? owed.first?.half ?? defender : defender }
  var problem: String?

  init(scorer: LiveScorer) {
    self.scorer = scorer
    undoAction = scorer.undoAction
    redoAction = scorer.redoAction
    state = scorer.state
    rows = scorer.rows
    game = scorer.game
    view = .behind(scorer.state.attacker ?? scorer.game.options.first)
    restoreContext()
  }

  // MARK: Reading the state

  var attacker: Side { state.attacker ?? state.winner ?? game.options.first }
  var defender: Side { attacker.other }
  var over: Bool { state.over }
  var positionsOn: Bool { state.capture.pitch }
  var playersOn: Bool { state.capture.players }
  var stanceOn: Bool { state.capture.stance }
  var isInkast: Bool { state.next.kind == "toss" }
  var isBaton: Bool { state.next.kind == "baton" && state.next.kingShot != true }
  var isKingShot: Bool { state.next.kind == "baton" && state.next.kingShot == true }
  var punishPending: Bool {
    state.allows("punish") && positionsOn && !punishLater && !isInkast
      && owed.contains { $0.punishment && $0.turn == state.turn }
  }

  func teamName(_ side: Side) -> String { game.team(side).shownName(side) }

  /// Only kubbs without a recorded spot need the count buttons.
  var unplacedFields: Int {
    let side = state.side(defender)
    return positionsOn ? max(0, side.field - side.fieldPositions.count) : side.field
  }
  var unplacedBases: Int {
    let side = state.side(defender)
    return positionsOn && side.baseComplete ? 0 : side.base
  }

  var players: [RecordState.Player] { state.side(attacker).players }

  /// Who throws next by order: the team's first player for the inkast, then baton n by
  /// n's place in the order. A pick changes it for one throw.
  var thrower: RecordState.Player? {
    let ps = players
    guard !ps.isEmpty else { return nil }
    if let pick, let p = ps.first(where: { $0.id == pick }) { return p }
    if isInkast {
      if let inkastBy, let p = ps.first(where: { $0.id == inkastBy }) { return p }
      return ps[0]
    }
    let thrown = state.batons?.thrown ?? 0
    return ps[thrown % ps.count]
  }

  var markedField: Int { marked.filter { if case .field = $0 { true } else { false } }.count }
  var markedBase: Int { marked.filter { if case .base = $0 { true } else { false } }.count }
  var downCount: Int { markedField + markedBase + countField + countBase }

  /// The line through the field kubb nearest the centre line in the thrower's own half:
  /// its depth (a cell's middle), when the places are known.
  var advantageDepth: Double? {
    if let meters = state.advantage?.meters { return 4 - Double(meters) }
    let own = state.side(attacker)
    guard own.field > 0, own.fieldComplete, !own.fieldPositions.isEmpty else { return nil }
    let observed = placements.aligned(in: attacker, state: state)
    return zip(own.fieldPositions, observed).map { cell, placement in placement?.point.depth ?? cell.depth + 0.5 }.min()
  }

  var advantageShown: Bool {
    guard let a = state.advantage, !over else { return false }
    return a.observed ?? a.applies
  }

  // MARK: The words

  func n(_ count: Int, _ word: String) -> String { "\(count) \(word)\(count == 1 ? "" : "s")" }

  /// The handoff stays visible until the first baton is recorded, including after a resume or undo.
  var firstBatonAfterInkast: Bool {
    state.next.kind == "baton" && state.next.n == 1 && (state.inkast?.dueAtStart ?? 0) > 0
      && !punishPending && !placing
  }

  var scoringAction: String {
    if placing { return "Place kubbs" }
    if punishPending { return "Place punishment kubb" }
    if isInkast {
      let phase = state.next.rethrow == true ? "Rethrow" : "Inkast"
      return "\(phase) · \(state.inkast?.left ?? 0) left"
    }
    let throwNumber = "\(state.next.n ?? 1) of \(state.next.of ?? 6)"
    return isKingShot ? "King shot · \(throwNumber)" : "Baton \(throwNumber)"
  }

  func word(_ p: RecordPoint) -> String { String(format: "%.2f,%.2f", p.across, p.depth) }

  /// One cue for the next pitch input. The record button already names a marked result.
  var scoringHint: String? {
    if let problem { return problem }
    if placing, let next = owed.first {
      return "Turn \(next.turn) · Tap Team \(next.half.rawValue)’s half (\(owed.count) left)."
    }
    if rescueAttempt { return "Failed rescue · Record this kubb’s landing." }
    if let flash { return flash }
    if punishPending { return "Tap where \(teamName(defender)) placed it." }
    if isInkast { return positionsOn ? "Tap where the kubb lands." : nil }
    if isKingShot { return "Throw from the baseline." }
    if downCount > 0 { return nil }
    if stanceOn, let stance { return "Stance \(word(stance)) · Mark fallen kubbs." }
    if stanceOn {
      return positionsOn ? "Tap the throwing spot, then mark fallen kubbs."
                         : "Tap the throwing spot, then count fallen kubbs."
    }
    if !positionsOn { return nil }
    if unplacedFields > 0 || unplacedBases > 0 { return "Tap located kubbs. Count the others below." }
    return state.side(defender).field > 0 ? "Tap fallen field kubbs first." : "Tap fallen kubbs."
  }

  // MARK: Doing

  private func run(_ body: () throws -> Void) {
    do {
      try body()
      problem = nil
    } catch {
      problem = "\(error)"
    }
    refresh()
  }

  private func refresh() {
    undoAction = scorer.undoAction
    redoAction = scorer.redoAction
    state = scorer.state
    rows = scorer.rows
    game = scorer.game
    lastWarnings = scorer.lastWarnings
  }

  /// One record event, with who threw when that is captured.
  private func add(_ event: [String: JSONValue], by: Bool = true) {
    var e = event
    if e["type"] == "toss", rescueAttempt { e["rescueAttempt"] = true }
    if by, playersOn, let t = thrower { e["by"] = .string(t.id) }
    func observed(_ point: JSONValue, in half: Side) -> JSONValue {
      guard let x = point["across"]?.number, let d = point["depth"]?.number else { return point }
      if point["source"] == "tap" { return point }
      return RecordPoint(across: x, depth: d).tap(in: half)
    }
    if let at = e["at"] {
      if let group = at.array {
        e["at"] = .array(group.map { observed($0, in: defender) })
      } else {
        e["at"] = observed(at, in: defender)
      }
    }
    if let spot = e["stance"] { e["stance"] = observed(spot, in: attacker) }
    let before = state
    let oldCount = scorer.records.count
    let turnBefore = state.turn
    run {
      try scorer.add(e)
    }
    guard scorer.records.count > oldCount, let saved = scorer.records.last else { return }
    if saved["type"] == "toss" { rescueAttempt = false }
    rememberPlay(saved, before: before)
    trackPlace(saved, before: before)
    trackFallen(saved, before: before, after: state)
    if state.turn != turnBefore || (!before.over && before.next.kingShot != true && isKingShot) {
      stance = nil
    }
    if state.turn != turnBefore {
      turnDone(turnBefore)
    }
    pick = nil
    marked = []
    countField = 0
    countBase = 0
    if panel == .pick { panel = .none }

  }

  private func turnDone(_ turn: Int) {
    inkastBy = nil
    punishLater = false
    guard !over, let row = rows.last(where: { $0.turn == turn }) else { return }
    var down = 0
    var hits = 0
    for b in row.batons {
      let felled = Self.felled(b.token)
      down += felled
      if felled > 0 { hits += 1 }
    }
    flash = "Turn \(turn) done · \(down) down with \(hits) of \(row.batons.count) batons"
  }

  /// Kubbs a baton token felled: `3F` is 3, `B` is 1, `2FB` is 3, `-` and `=` none.
  static func felled(_ token: String) -> Int {
    var total = 0
    var digits = ""
    for ch in token {
      if ch.isNumber {
        digits.append(ch)
      } else if ch == "F" || ch == "B" {
        total += Int(digits) ?? 1
        digits = ""
      } else {
        digits = ""
      }
    }
    return total
  }

  /// A tap on the pitch where nothing tappable is: a kubb landing, a punishment kubb, a
  /// throwing spot, or a place owed.
  func tap(_ p: PitchFrame.World) {
    flash = nil
    if placing {
      guard let place = owed.first, let at = PitchFrame.notation(p), at.half == place.half,
        let i = scorer.records.firstIndex(where: { $0["id"]?.string == place.id })
      else { return }
      run {
        if place.punishment {
          var event = RecordEvent.punish(at: at.point)
          event["at"] = at.point.tap(in: at.half)
          if i + 1 < scorer.records.count, let next = scorer.records[i + 1]["id"]?.string {
            try scorer.edit(.insert(before: next, event: event))
          } else {
            try scorer.add(event)
          }
        } else {
          var event = scorer.records[i]
          event["at"] = at.point.tap(in: at.half)
          try scorer.edit(.replace(id: place.id, event: event))
        }
      }
      restoreContext()
      placing = !owed.isEmpty
      return
    }
    guard !over else { return }
    if punishPending {
      guard let at = PitchFrame.notation(p), at.half == defender else { return }
      add(RecordEvent.punish(at: at.point), by: false)
      return
    }
    if isInkast {
      guard positionsOn else {
        flash = "Positions are off: use the buttons below"
        return
      }
      if let at = PitchFrame.notation(p), at.half == defender {
        add(RecordEvent.toss(true, at: at.point))
      } else {
        add(RecordEvent.toss(false))
      }
      return
    }
    if stanceOn, let s = PitchFrame.stance(p, side: attacker) {
      stance = PitchFrame.snap(
        s, advantageDepth: advantageShown && !isKingShot ? advantageDepth : nil)
    }
  }

  func toggle(_ t: Target) {
    flash = nil
    if t == .king {
      if isKingShot { kingDown() }
      return
    }
    if let i = marked.firstIndex(of: t) {
      marked.remove(at: i)
      return
    }
    if case .base = t, state.side(defender).field > markedField + countField {
      flash = "Field kubbs first"
    }
    marked.append(t)
  }

  /// The big button.
  func primary() {
    flash = nil
    if placing {
      placing = false
      return
    }
    if punishPending {
      punishLater = true
      return
    }
    if isInkast {
      if positionsOn {
        add(RecordEvent.toss(false))
      } else if state.next.rethrow == true {
        add(RecordEvent.toss(true))
      } else {
        recordIn(state.inkast?.due ?? 0)
      }
      return
    }
    if isKingShot {
      kingDown()
      return
    }
    baton()
  }

  /// The second button: 1 OUT / OUT AGAIN with positions off, LATER with them on, MISS
  /// at the king.
  private func recordIn(_ n: Int) {
    for _ in 0..<n {
      add(RecordEvent.toss(true))
      if problem != nil { break }
    }
  }

  func oneIn() {
    panel = .none
    add(RecordEvent.toss(true))
  }

  func second() {
    flash = nil
    if placing, let place = owed.first,
      var event = scorer.records.first(where: { $0["id"]?.string == place.id })
    {
      event["positionWaived"] = true
      run { try scorer.edit(.replace(id: place.id, event: event)) }
      restoreContext()
      placing = !owed.isEmpty
      return
    }
    if isInkast {
      if positionsOn {
        recordIn(state.next.rethrow == true ? state.inkast?.rethrows ?? 0 : state.inkast?.due ?? 0)
      } else {
        add(RecordEvent.toss(false))
      }
    } else if isKingShot {
      add(RecordEvent.baton(stance: stanceOn ? stance : nil))
    }
  }

  var primaryTitle: String {
    if placing { return "Back to scoring" }
    if over { return "Score sheet" }
    if punishPending { return "Place it later" }
    if isInkast {
      if positionsOn { return state.next.rethrow == true ? "Out again" : "Out" }
      if state.next.rethrow == true { return "In" }
      let due = state.inkast?.due ?? 0
      return (state.inkast?.rethrows ?? 0) > 0 ? "\(due) in" : "All \(due) in"
    }
    if isKingShot { return "King down" }
    return downCount > 0 ? "\(downCount) down" : "Miss"
  }

  var secondTitle: String? {
    if placing { return "Leave blank" }
    if over || punishPending { return nil }
    if isInkast {
      return positionsOn ? "Later" : (state.next.rethrow == true ? "Out again" : "1 out")
    }
    if isKingShot { return "Miss" }
    return nil
  }

  func baton(illegal: Bool = false, king: Bool = false) {
    let side = state.side(defender)
    let observed = placements.aligned(in: defender, state: state)
    var fields: [JSONValue] = []
    var bases: [JSONValue] = []
    for target in marked {
      switch target {
      case .field(let i) where side.fieldPositions.indices.contains(i):
        let c = side.fieldPositions[i]
        fields.append(observed[i]?.hit(in: defender) ?? RecordPoint(across: c.across + 0.5, depth: c.depth + 0.5).json)
      case .base(let i) where side.basePositions.indices.contains(i):
        bases.append(RecordPoint(across: side.basePositions[i].across + 0.5, depth: 4).tap(in: defender))
      default: break
      }
    }
    let spots = fields + bases
    let allLocated = countField + countBase == 0
    var event = RecordEvent.baton(
      field: fields.count + countField, base: bases.count + countBase, king: king, illegal: illegal,
      stance: stanceOn ? stance : nil)
    if positionsOn && allLocated && !spots.isEmpty { event["at"] = .array(spots) }
    if !allLocated && !spots.isEmpty {
      // The writer needs a whole felled word. Keep the observed part locally for correction.
      let observedFields =
        fields + Array(repeating: .null, count: countField)
      let observedBases =
        bases + Array(repeating: .null, count: countBase)
      event["knownFelled"] = .array(observedFields + observedBases)
    }
    add(event)
  }

  func kingDown() {
    add(RecordEvent.baton(king: true, stance: stanceOn ? stance : nil))
  }

  func undo() { changeHistory(undoAction, undoing: true) }
  func redo() { changeHistory(redoAction, undoing: false) }

  private func changeHistory(_ action: ScoreAction?, undoing: Bool) {
    guard let action else { return }
    do {
      if undoing { try scorer.undo() } else { try scorer.redo() }
      problem = nil
      panel = .none
      reload()
      let label: String
      switch action {
      case .observation(let event): label = Self.label(event)
      case .correction: label = "the edit"
      }
      flash = (undoing ? "Undone: " : "Redone: ") + label
    } catch { problem = error.localizedDescription }
  }

  /// A record event in a few words, for "Undone: ...".
  static func label(_ e: [String: JSONValue]) -> String {
    switch e["type"]?.string {
    case "toss":
      if e["king"]?.bool == true { return "the king knocked over" }
      return e["result"]?.string == "out" ? "a kubb out" : "a kubb in"
    case "baton":
      if e["illegal"]?.bool == true { return "an illegal throw" }
      if e["king"]?.bool == true { return "king down" }
      let n = Int(e["field"]?.number ?? 0) + Int(e["base"]?.number ?? 0)
      return n == 0 ? "a miss" : "\(n) down"
    case "punish": return "the punishment kubb's place"
    case "advantage": return "the advantage line"
    case "resign": return "the resignation"
    case "call": return "the call"
    case "capture": return "what to record"
    case "note": return "the note"
    default: return "the last entry"
    }
  }

  func nextView() {
    view = view.next
  }

  // The rare events.

  func illegal() {
    panel = .none
    if isInkast {
      flash = "Illegal throws are for batons"
      return
    }
    baton(illegal: true)
    if flash == nil { flash = "Illegal throw · counted as a miss" }
  }

  func kingEarly() {
    panel = .none
    if isInkast { add(RecordEvent.toss(true, king: true)) } else { baton(king: true) }
  }

  func failedRescue() {
    panel = .none
    rescueAttempt.toggle()
  }

  func resign(_ side: Side) {
    panel = .none
    add(RecordEvent.resign(side), by: false)
  }

  func call(_ winner: Side) {
    panel = .none
    add(RecordEvent.call(winner: winner), by: false)
  }

  func saveNote() {
    let t = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
    panel = .none
    guard !t.isEmpty else { return }
    add(RecordEvent.note(t), by: false)
    noteText = ""
    flash = "Noted"
  }

  func observeLine(applies: Bool, meters: Int? = nil) {
    var e = RecordEvent.advantage(applies: applies)
    if let meters { e["meters"] = .number(Double(meters)) }
    panel = .none
    add(e, by: false)
  }

  func setCapture(_ c: Capture) {
    run { try scorer.setCapture(c) }
  }

  func choose(_ player: RecordState.Player) {
    if isInkast { inkastBy = player.id } else { pick = player.id }
    panel = .none
  }

  /// After an edit from the timeline.
  func reload() {
    marked = []
    countField = 0
    countBase = 0
    placing = false
    refresh()
    restoreContext()
  }

  private func trackPlace(_ event: [String: JSONValue], before: RecordState) {
    guard let id = event["id"]?.string, let half = before.defender, before.capture.pitch else {
      return
    }
    if event["type"] == "punish", before.allows("punish"),
      let i = owed.firstIndex(where: { $0.turn == before.turn && $0.punishment })
    {
      owed.remove(at: i)
    } else if event["type"] == "toss", before.next.kind == "toss", event["king"] != true,
      event["positionWaived"] != true
    {
      let punishment = event["result"] == "out" && before.next.rethrow == true
      if punishment || (event["result"] == "in" && event["at"] == nil) {
        owed.append(OwedPlace(id: id, half: half, turn: before.turn, punishment: punishment))
      }
    }
  }

  /// Only draw lying pieces the engine actually removed from known cells.
  private func trackFallen(_ event: [String: JSONValue], before: RecordState, after: RecordState) {
    let hits = placements.apply(event, before: before, after: after)
    guard before.turn == after.turn else {
      fallen = []
      return
    }
    guard before.capture.pitch, event["type"] == "baton", let half = before.defender else { return }
    let old = before.side(half)
    let new = after.side(half)
    var known = hits.keys.sorted().compactMap { hits[$0]?.point }
    fallen.append(contentsOf: known.map { PitchFrame.world($0, half: half) })
    func removed(_ standing: [RecordPoint], remaining: [RecordPoint], base: Bool) {
      var cells = remaining
      for cell in standing {
        if let i = cells.firstIndex(where: { $0.across == cell.across && $0.depth == cell.depth }) {
          cells.remove(at: i)
        } else if !base, let i = known.firstIndex(where: { $0.metreCell == cell.metreCell }) {
          known.remove(at: i)
        } else {
          let point = RecordPoint(across: cell.across + 0.5, depth: base ? 3.9 : cell.depth + 0.5)
          fallen.append(PitchFrame.world(point, half: half))
        }
      }
    }
    if old.fieldComplete && new.fieldComplete {
      removed(old.fieldPositions, remaining: new.fieldPositions, base: false)
    }
    if old.baseComplete && new.baseComplete {
      removed(old.basePositions, remaining: new.basePositions, base: true)
    }
  }

  /// Short descriptions for the live turn log. Rebuild on reopen or correction and
  /// append from the same accepted record used for the pitch after an ordinary throw.
  private func rememberPlay(_ event: [String: JSONValue], before: RecordState) {
    let action: String
    switch event["type"]?.string {
    case "baton": action = "Baton \(before.next.n ?? 1)"
    case "toss": action = before.next.rethrow == true ? "Rethrow" : "Inkast"
    case "punish": action = "Placement"
    case "note":
      if let text = event["text"]?.string { playsByTurn[before.turn, default: []].append(text) }
      return
    default: return
    }
    let player = before.attacker.flatMap { before.side($0).players.first { $0.id == event["by"]?.string } }
    let line = [action, player?.name, Self.label(event)].compactMap { $0 }.joined(separator: " · ")
    playsByTurn[before.turn, default: []].append(line)
  }

  private func restoreContext() {
    playsByTurn = [:]
    placements = FieldPlacements()
    fallen = []
    owed = []
    pick = nil
    rescueAttempt = false
    inkastBy = nil
    punishLater = false
    stance = nil
    do {
      let events = try scorer.timeline().flatMap(\.events).sorted { $0.index < $1.index }
      for (i, entry) in events.enumerated() {
        rememberPlay(entry.event, before: entry.before)
        trackPlace(entry.event, before: entry.before)
        let after = i + 1 < events.count ? events[i + 1].before : state
        trackFallen(entry.event, before: entry.before, after: after)
        guard entry.turn == state.turn else { continue }
        if entry.type == "toss" { inkastBy = entry.event["by"]?.string }
        if entry.type == "baton", entry.before.next.kingShot == state.next.kingShot,
          let spot = entry.event["stance"], let x = spot["across"]?.number,
          let d = spot["depth"]?.number {
          stance = RecordPoint(across: x, depth: d)
        }
      }
    } catch { problem = String(describing: error) }
  }

  // MARK: Turn notation

  /// This turn's tokens so far, without the turn number.
  var tokens: String {
    guard let row = rows.last(where: { $0.turn == state.turn }) else { return "" }
    let line = row.line.split(separator: "#").first.map(String.init) ?? row.line
    return line.split(separator: " ").dropFirst().joined(separator: " ")
  }

}
