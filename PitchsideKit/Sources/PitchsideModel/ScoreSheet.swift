import Notation

extension Analysis {
  public var resultDetail: String {
    let turn = endTurn.map { " in turn \($0)" } ?? ""
    switch winHow {
    case "king": return "King down" + turn
    case "resigned (G)": return "Resignation" + turn
    case "called (W)": return "Game called" + turn
    case "illegal king": return "King felled early" + turn
    case "illegal king (inkast)": return "A thrown kubb felled the king" + turn
    case "illegal king (kubb hit the king)": return "A felled kubb knocked over the king" + turn
    case "Win header": return "Winner recorded in the file header"
    case let how?: return "Over" + turn + " · " + how
    case nil: return "Over" + turn
    }
  }
}

extension Analysis.Row {
  public var scoringSummary: String {
    var first: [String] = []
    if inkast > 0 {
      first.append("\(inkast) in")
    }
    if let ink {
      for (count, singular, plural) in [
        (ink.R, "rethrow", "rethrows"), (ink.P, "punishment", "punishments"),
        (ink.Q, "rescue", "rescues"), (ink.Y, "failed rescue", "failed rescues"),
        (ink.N, "rested on another kubb", "rested on another kubb"),
      ] where count > 0 {
        first.append("\(count) \(count == 1 ? singular : plural)")
      }
      if ink.E { first.append("king felled during inkast") }
    }
    let f = thrown.reduce(0) { $0 + ($1.kind == "hit" ? $1.f ?? 0 : 0) }
    let b = thrown.reduce(0) { $0 + ($1.kind == "hit" ? $1.b ?? 0 : 0) }
    var felled: [String] = []
    if f > 0 { felled.append("\(f) field") }
    if b > 0 { felled.append(f == 0 && first.isEmpty ? "\(b) base \(b == 1 ? "kubb" : "kubbs")" : "\(b) base") }
    if thrown.contains(where: { $0.kind == "king" }) { felled.append("king") }
    if thrown.contains(where: { $0.kind == "illegalking" || $0.e == true }) {
      felled.append("king felled early")
    }
    let misses = thrown.filter { $0.kind == "kingmiss" }.count
    if misses > 0 { felled.append(misses == 1 ? "missed king shot" : "\(misses) missed king shots") }
    let illegal = thrown.filter { $0.kind == "illegal" }.count
    if illegal > 0 { felled.append(illegal == 1 ? "illegal throw" : "\(illegal) illegal throws") }
    if batons.contains(where: { $0.kind == "resign" && $0.void != true }) { felled.append("resigned") }
    if batons.contains(where: { $0.kind == "win" && $0.void != true }) { felled.append("game called") }
    if felled.isEmpty && ink?.E != true { felled.append("nothing felled") }
    var parts = first.isEmpty ? [] : [first.joined(separator: ", ")]
    if advantage { parts.append("advantage") }
    if !felled.isEmpty { parts.append(felled.joined(separator: ", ")) }
    return parts.joined(separator: " · ")
  }
}
