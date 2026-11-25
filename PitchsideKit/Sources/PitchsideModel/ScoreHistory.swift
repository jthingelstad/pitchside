import Foundation

/// An action a scorer can reverse, for the controls on the pitch and sheet.
public enum ScoreAction: Sendable, Equatable {
  case observation([String: JSONValue])
  case correction
}

public struct ScoreHistory {
  typealias Event = [String: JSONValue]

  private struct Change {
    let sequence: Int
    let id: String
    let before: Event?
    let after: Event?
    let action: ScoreAction
  }

  // A removed observation keeps its place, so undo can put it back between the same
  // neighbours even after older journals have removed or inserted other observations.
  private var order: [String] = []
  private var values: [String: Event] = [:]
  private var applied: [Change] = []
  private var undone: [Change] = []

  public var undoAction: ScoreAction? { applied.last?.action }
  public var redoAction: ScoreAction? { undone.last?.action }
  var undoSequence: Int? { applied.last?.sequence }
  var redoSequence: Int? { undone.last?.sequence }
  var records: [Event] { order.compactMap { values[$0] } }

  public init(_ entries: [GameEvent]) {
    for entry in entries { apply(kind: entry.kind, payload: entry.payload, sequence: entry.seq) }
  }

  @discardableResult
  mutating func apply(kind: String, payload: JSONValue, sequence: Int) -> Bool {
    let change: Change
    switch kind {
    case RecordScorer.Kind.record:
      guard let event = payload.object else { return false }
      let id = event["id"]?.string ?? "legacy-\(sequence)"
      guard values[id] == nil else { return false }
      order.append(id)
      change = Change(sequence: sequence, id: id, before: nil, after: event, action: .observation(event))
    case RecordScorer.Kind.edit:
      if let id = payload["replace"]?.string, let old = values[id], var event = payload["event"]?.object {
        event["id"] = old["id"]
        if event["time"] == nil { event["time"] = old["time"] }
        guard event != old else { return false }
        change = Change(sequence: sequence, id: id, before: old, after: event, action: .correction)
      } else if let anchor = payload["insert"]?.string, values[anchor] != nil,
                let index = order.firstIndex(of: anchor), let event = payload["event"]?.object,
                let id = event["id"]?.string, values[id] == nil {
        order.insert(id, at: index)
        change = Change(sequence: sequence, id: id, before: nil, after: event, action: .correction)
      } else if let id = payload["remove"]?.string, let old = values[id] {
        change = Change(sequence: sequence, id: id, before: old, after: nil, action: .correction)
      } else { return false }
    case RecordScorer.Kind.undo:
      if let target = payload["change"]?.number {
        guard let last = applied.last, Double(last.sequence) == target else { return false }
        applied.removeLast()
        values[last.id] = last.before
        undone.append(last)
      } else {
        // Through build 42, Undo always removed a named observation, even after an
        // unrelated correction. Preserve the historical removal and its edited value.
        guard let id = payload["id"]?.string, let old = values.removeValue(forKey: id) else { return false }
        applied.removeAll { $0.id == id }
        undone.append(Change(sequence: sequence, id: id, before: nil, after: old, action: .observation(old)))
      }
      return true
    case RecordScorer.Kind.redo:
      guard let next = undone.last, payload["change"]?.number == Double(next.sequence) else { return false }
      undone.removeLast()
      values[next.id] = next.after
      applied.append(next)
      return true
    default: return false
    }
    values[change.id] = change.after
    applied.append(change)
    undone.removeAll()
    return true
  }
}
