import Notation

extension Analysis {
  public var resultDetail: String {
    let turn = endTurn.map { "in turn \($0)" } ?? ""
    switch winHow {
    case "king": return "King down \(turn)"
    case let how?: return "Over \(turn) · \(how)"
    case nil: return "Over"
    }
  }
}

extension Analysis.Row {
  public var scoringSummary: String {
    var first: [String] = []
    if inkast > 0 {
      first.append("\(inkast) in")
    }
    let f = thrown.reduce(0) { $0 + ($1.kind == "hit" ? $1.f ?? 0 : 0) }
    let b = thrown.reduce(0) { $0 + ($1.kind == "hit" ? $1.b ?? 0 : 0) }
    var felled: [String] = []
    if f > 0 { felled.append("\(f) field") }
    if b > 0 { felled.append(f == 0 && first.isEmpty ? "\(b) base \(b == 1 ? "kubb" : "kubbs")" : "\(b) base") }
    if thrown.contains(where: { $0.kind == "king" }) { felled.append("king") }
    if felled.isEmpty { felled.append("nothing felled") }
    var parts = first
    if advantage { parts.append("advantage") }
    parts.append(felled.joined(separator: ", "))
    return parts.joined(separator: " · ")
  }
}
