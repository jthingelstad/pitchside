import Foundation

/// Refines the engine's standing cells with the placements actually observed on this phone.
/// An ID belongs to a standing placement. A rethrow or a new inkast establishes a new one.
public struct FieldPlacements: Sendable {
  public struct Placement: Equatable, Sendable {
    public let id: String
    public let point: RecordPoint
    let turn: Int
    let initialMark: String?

    public func mark(in currentTurn: Int) -> String? { turn < currentTurn ? "s" : initialMark }

    public func hit(in half: Side) -> JSONValue {
      point.tap(in: half, placementID: id)
    }
  }

  private var observed: [Side: [Placement]] = [:]
  public init() {}

  private static func point(_ value: JSONValue?) -> RecordPoint? {
    guard let x = value?["across"]?.number, let y = value?["depth"]?.number,
      (0...5).contains(x), (0...4).contains(y) else { return nil }
    return RecordPoint(across: x, depth: y)
  }

  /// Aligned with the engine's fieldPositions array, including slots only known to a cell.
  public func aligned(in half: Side, state: RecordState) -> [Placement?] {
    var available = observed[half] ?? []
    return state.side(half).fieldPositions.map { p in
      guard let i = available.firstIndex(where: { $0.point.metreCell == p.metreCell })
      else { return nil }
      return available.remove(at: i)
    }
  }

  /// The return value identifies individual field falls by their slot in the baton event.
  @discardableResult public mutating func apply(_ event: [String: JSONValue], before: RecordState,
                                              after: RecordState) -> [Int: Placement] {
    guard !before.over, let defender = before.defender else { return [:] }
    let type = event["type"]?.string
    let half = type == "pitch" ? event["half"]?.string.flatMap(Side.init(rawValue:)) : defender
    guard let half else { return [:] }
    let oldCells = before.side(half).fieldPositions.map(\.metreCell)
    let newCells = after.side(half).fieldPositions.map(\.metreCell)
    var known = observed[half] ?? []
    let id = event["id"]?.string
    var falls: [Int: Placement] = [:]

    if type == "pitch" {
      guard let id, let values = event["at"]?.array else { return [:] }
      let points = values.compactMap { Self.point($0) }
      guard points.count == values.count, points.count == before.side(half).field,
        points.map(\.metreCell) == newCells else { return [:] }
      observed[half] = before.capture.pitch ? points.enumerated().map { index, point in
        Placement(id: "\(id)/\(index)", point: point, turn: before.turn,
                  initialMark: half == before.attacker ? "s" : values[index]["mark"]?.string)
      } : []
      return [:]
    }

    // A rescue can remove an old placement and add a new one in the very same cell.
    let rescue = type == "toss" && before.allows("toss") && (before.inkast?.rescuable ?? 0) > 0
      && (event["rescued"]?.number ?? 0) > 0
    if rescue {
      let affected = event["rescuedAt"]?.array?.compactMap { Self.point($0).map(\.metreCell) }
      known.removeAll { affected?.contains($0.point.metreCell) ?? true }
    }
    let fieldLoss = before.side(half).field - after.side(half).field
    if type == "baton", fieldLoss > 0, event["field"]?.number == Double(fieldLoss),
      let hits = event["at"]?.array ?? event["knownFelled"]?.array {
      for (i, value) in hits.prefix(fieldLoss).enumerated() {
        guard let point = Self.point(value) else { continue }
        let cell = point.metreCell
        let sameCell = known.filter { $0.point.metreCell == cell }
        // Earlier builds wrote a cell centre with no reference. It only identifies a
        // placement when there was a single candidate in that cell.
        let hit: Placement?
        if let ref = value["placement"]?.string {
          hit = sameCell.first { $0.id == ref }
        } else {
          hit = before.side(half).fieldComplete && oldCells.filter { $0 == cell }.count == 1 ? sameCell.first : nil
        }
        if let hit {
          falls[i] = hit
          known.removeAll { $0.id == hit.id }
        }
      }
    }
    for cell in Set(oldCells) {
      let oldCount = oldCells.filter { $0 == cell }.count
      let newCount = newCells.filter { $0 == cell }.count
      let identified = falls.values.filter { $0.point.metreCell == cell }.count
      if newCount < oldCount - identified {
        // A cell lost an unidentified piece. Any of its remaining points could be wrong.
        known.removeAll { $0.point.metreCell == cell }
      }
    }
    if before.capture.pitch, let id, let point = Self.point(event["at"]),
      (type == "toss" && event["result"] == "in" && event["king"] != true && before.allows("toss"))
        || (type == "punish" && before.allows("punish")) {
      let cell = point.metreCell
      let count = newCells.filter { $0 == cell }.count
      if count > oldCells.filter({ $0 == cell }).count || (rescue && count > 0) {
        known.append(Placement(id: id, point: point, turn: before.turn, initialMark: type == "punish" ? "p" : nil))
      }
    }
    observed[half] = known
    return falls
  }
}
