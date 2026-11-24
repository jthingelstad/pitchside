import Notation
import PitchsideDesign
import PitchsideModel
import SwiftUI

/// One game's stats, in the Planet Kubb scoresheet's order. The numbers are kubb.js's;
/// "From 8 metres" and the turn of Zero B are Pitchside's own over kubb.js's turns.
struct GameStatsView: View {
  @Environment(AppModel.self) private var model
  let id: UUID
  var back = "Score sheet"

  var body: some View {
    PushedScreen(title: "Game stats", back: back) {
      if let game = model.game(id), let read = model.read(game) {
        let stats = GameStats(read)
        let a = read.analysis
        Text("The scoresheet's stats").psKick()
        VStack(alignment: .leading, spacing: 14) {
          stat("Hit %", "Batons that hit, of batons thrown.") {
            ForEach(stats.sides, id: \.side) { s in
              bar(s.side, s.hits, s.batons, label: "\(s.hits) of \(s.batons) · \(percent(s.hitPct))")
            }
          }
          stat("1st baton efficiency", "Field kubbs felled by the first baton, of kubbs thrown in.") {
            ForEach(stats.sides, id: \.side) { s in
              bar(s.side, s.effF, s.effI, label: "\(s.effF) of \(s.effI) · \(percent(s.efficiency))")
            }
          }
          stat("Zero B @ T#", "The throw that felled the last base kubb.") {
            ForEach(stats.sides, id: \.side) { s in
              line(s.side, zeroB(s, a))
            }
          }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .psCard()

        Text("More from this game").psKick()
        VStack(alignment: .leading, spacing: 14) {
          stat("Rethrows", "Kubbs thrown a second time, of kubbs thrown in.") {
            ForEach(stats.sides, id: \.side) { s in
              let p = a.stats(s.side)?.P ?? 0
              line(
                s.side,
                "\(s.rethrown) of \(s.inkasted)" + (p > 0 ? ", and \(p) punishment \(p == 1 ? "kubb" : "kubbs")" : ""))
            }
          }
          stat("Batons to clear the field", nil) {
            ForEach(stats.sides, id: \.side) { s in line(s.side, clear(s)) }
          }
          stat("From 8 metres", "Batons at a base kubb or the king from the baseline. Worked out by Pitchside from the turns.") {
            ForEach(stats.sides, id: \.side) { s in
              let t = s.fromEight
              line(s.side, t.batons == 0 ? "None thrown" : "\(t.hits) of \(t.batons) · \(percent(t.pct))")
            }
          }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .psBox()

        Text("Hit % by player · needs who threw").psKick()
        if stats.players.isEmpty {
          Text("This game did not record who threw.").font(PSFont.body(16)).foregroundStyle(Color.psText)
        } else {
          ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 10) { playerBoxes(stats, a) }
            VStack(spacing: 10) { playerBoxes(stats, a) }
          }
        }
        Text("One game is a small sample. These add up across games for each saved name.").psHelp()
      } else {
        Text("No turns to count yet.").font(PSFont.body(16))
      }
    }
  }

  func zeroB(_ s: GameStats.SideLine, _ a: Analysis) -> String {
    if let t = s.zeroBaseAt {
      let spot = s.zeroBaseSpot.map { " · turn \($0.turn), baton \($0.baton)" } ?? ""
      return "T\(t)\(spot)"
    }
    let left = a.rows.last?.base[s.side.other.rawValue] ?? a.rules.baseKubbs
    return "Not reached. \(left) base \(left == 1 ? "kubb" : "kubbs") left."
  }

  func clear(_ s: GameStats.SideLine) -> String {
    let turns = s.btc.count + s.uncleared
    if turns == 0 { return "No field kubbs to clear" }
    let avg = s.btcAvg.map { $0.formatted(.number.precision(.fractionLength(0...1))) }
    var text = avg.map { "\($0) on average, " } ?? ""
    text += "\(s.btc.count) of \(turns) \(turns == 1 ? "turn" : "turns") cleared"
    if s.uncleared > 0 { text += ". \(s.uncleared) left kubbs standing" }
    return text
  }

  func stat<C: View>(_ title: String, _ help: String?, @ViewBuilder _ rows: () -> C) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title).font(PSFont.body(18, .bold)).foregroundStyle(Color.psText).accessibilityAddTraits(.isHeader)
      if let help { Text(help).psHelp() }
      rows()
    }
  }

  func line(_ side: Side, _ text: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      TeamMarker(side, size: 20).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 4 }
      Text(text).font(PSFont.body(16)).foregroundStyle(Color.psText)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Side \(side.rawValue): \(text)")
  }

  func bar(_ side: Side, _ n: Int, _ of: Int, label: String) -> some View {
    let fraction = of > 0 ? min(1, Double(n) / Double(of)) : 0
    return ViewThatFits(in: .horizontal) {
      HStack(spacing: 8) {
        TeamMarker(side, size: 20)
        barShape(side, fraction).frame(minWidth: 80)
        // A fixed column for the words keeps the two bars the same length.
        Text(label).font(PSFont.body(16, .bold)).foregroundStyle(Color.psText).fixedSize()
          .frame(minWidth: 132, alignment: .trailing)
      }
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 8) {
          TeamMarker(side, size: 20)
          Text(label).font(PSFont.body(16, .bold)).foregroundStyle(Color.psText)
        }
        barShape(side, fraction)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Side \(side.rawValue): \(label)")
  }

  func barShape(_ side: Side, _ fraction: Double) -> some View {
    GeometryReader { g in
      ZStack(alignment: .leading) {
        Rectangle().fill(Color.psField)
        Rectangle().fill(TeamMarker.fill(side.marker)).frame(width: g.size.width * fraction)
      }
    }
    .frame(height: 18)
    .clipShape(RoundedRectangle(cornerRadius: 4))
    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.psLine, lineWidth: 1))
  }

  @ViewBuilder func playerBoxes(_ stats: GameStats, _ a: Analysis) -> some View {
    ForEach(Side.allCases, id: \.self) { side in
      let players = stats.players.filter { $0.side == side }
      if !players.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
          ForEach(players) { p in
            HStack {
              Text(p.name).font(PSFont.body(16, .bold))
              Spacer(minLength: 6)
              Text("\(p.hits) of \(p.batons)").font(PSFont.body(16))
            }
            .foregroundStyle(Color.psText)
            .accessibilityElement(children: .combine)
          }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .psBox()
        .accessibilityLabel(a.name(side))
      }
    }
  }
}

/// The Stats tab: each saved name across every game it played, then the games.
struct StatsTabView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    let totals = model.totals()
    let named = model.roster.compactMap { n in totals[n.key].map { (n, $0) } }
      .sorted { $0.1.batons > $1.1.batons }
    Screen(title: "Stats") {
      Text("By saved name · every game").psKick()
      if named.isEmpty {
        Text("Score a game with who threw on, and each saved name's batons add up here.")
          .font(PSFont.body(16)).foregroundStyle(Color.psText)
      } else {
        VStack(spacing: 0) {
          HStack {
            Text("Name").frame(maxWidth: .infinity, alignment: .leading)
            Text("Games").frame(minWidth: 56, alignment: .trailing)
            Text("Hit %").frame(minWidth: 96, alignment: .trailing)
          }
          .font(PSFont.body(14, .bold)).foregroundStyle(Color.psMuted)
          .padding(.vertical, 6)
          .accessibilityHidden(true)
          ForEach(named, id: \.0.key) { name, t in
            HStack {
              Text(name.name).font(PSFont.body(16, .bold)).frame(maxWidth: .infinity, alignment: .leading)
              Text("\(t.games)").font(PSFont.body(16)).frame(minWidth: 56, alignment: .trailing)
              Text("\(t.hits)/\(t.batons) · \(percent(t.hitPct))").font(PSFont.body(16))
                .frame(minWidth: 96, alignment: .trailing)
            }
            .foregroundStyle(Color.psText)
            .padding(.vertical, 6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
              "\(name.name): \(t.games) \(t.games == 1 ? "game" : "games"), \(t.hits) of \(t.batons) batons hit, \(percent(t.hitPct))")
          }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .psBox()
      }
      Text("Names count only in games scored here. A file opened from elsewhere counts in its own stats.").psHelp()
      Text("By game").psKick()
      if model.finished.isEmpty { Text("No games yet.").psHelp() }
      ForEach(model.finished.prefix(20)) { game in
        NavigationLink(value: Route.stats(game.id)) {
          VStack(alignment: .leading, spacing: 2) {
            Text(resultTitle(game, model.read(game))).font(PSFont.body(16, .bold))
            Text(resultDetail(game, model.read(game))).font(PSFont.body(14)).foregroundStyle(Color.psMuted)
          }
          .foregroundStyle(Color.psText)
          .padding(.horizontal, 12).padding(.vertical, 8)
          .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
          .psBox()
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
    }
  }
}
