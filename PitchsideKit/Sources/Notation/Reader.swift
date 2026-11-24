import Foundation
import JavaScriptCore

// Planet Kubb Notation's own reader in JavaScriptCore. The three vendored files are ES
// modules; JavaScriptCore's evaluateScript runs classic scripts, so each loads wrapped in
// a function whose exports land on one global `PK`, with its `import`/`export` lines
// taken out as it loads. Nothing else in them changes: every number Pitchside shows is
// kubb.js's (or, where kubb.js has none, Pitchside's own small derivation over kubb.js's
// rows in `pitchsideJS`, said so beside it).

/// What went wrong reading a file.
public enum NotationError: Error, Equatable, CustomStringConvertible {
  /// The reader's files are not in the bundle, or did not load.
  case reader(String)
  /// The file is a Kid rules game: Pitchside scores the full game only.
  case kidRules
  /// Not a game file at all (no turns, or nothing the reader could read).
  case notAGame(String)
  /// The grammar refused it (canonicalize).
  case syntax(message: String, line: Int?, column: Int?)

  public var description: String {
    switch self {
    case .reader(let m): "The notation reader did not start: \(m)"
    case .kidRules:
      "This is a Kid rules game. Pitchside scores the full game only, so it does not open Kid games."
    case .notAGame(let m): m
    case .syntax(let m, let line, _): line.map { "Line \($0): \(m)" } ?? m
    }
  }
}

/// The reader: one JavaScriptCore context with pk-kubb-score's parser, canonical writer
/// and kubb.js loaded. Not thread safe; make one where it is used (it loads in a few
/// milliseconds).
public final class NotationReader {
  private let context: JSContext
  /// The pk-kubb-score release these files are from (Vendor/SOURCE's tag), e.g.
  /// `v2-2026.11`.
  public static let edition = "v2-2026.11"

  public init() throws {
    guard let context = JSContext() else { throw NotationError.reader("no JavaScript context") }
    self.context = context
    var failure: String?
    context.exceptionHandler = { _, value in failure = value?.toString() ?? "an exception" }
    for (name, wrap) in [
      ("notation-parser", Self.wrapParser), ("canonical", Self.wrapCanonical), ("kubb", Self.wrapKubb),
    ] {
      guard let url = Bundle.module.url(forResource: name, withExtension: "js"),
        let text = try? String(contentsOf: url, encoding: .utf8)
      else { throw NotationError.reader("\(name).js is not in the bundle") }
      context.evaluateScript(wrap(text), withSourceURL: URL(string: "pk-kubb-score/\(name).js"))
      if let failure { throw NotationError.reader("\(name).js: \(failure)") }
    }
    context.evaluateScript(Self.pitchsideJS, withSourceURL: URL(string: "pitchside/read.js"))
    if let failure { throw NotationError.reader("read.js: \(failure)") }
    context.exceptionHandler = nil
  }

  // MARK: Reading

  /// A game file read the way pk-kubb-score's site reads it: kubb.js's analysis, the
  /// grammar's verdict, and the few figures Pitchside adds. Refuses Kid rules games.
  public func read(_ text: String) throws -> GameRead {
    let json = try callJSON("read", text)
    let read = try JSONDecoder().decode(GameRead.self, from: Data(json.utf8))
    if read.kid { throw NotationError.kidRules }
    // kubb.js reads leniently and finds a turn in almost any text; a file with no
    // headers that the grammar refuses is not a game file.
    if read.analysis.rows.isEmpty || (read.analysis.headers.isEmpty && !read.grammar.ok) {
      throw NotationError.notAGame("This file is not a Planet Kubb Notation game.")
    }
    return read
  }

  /// kubb.js's `analyze(text)`, as the JSON it returns (for tests that compare it with
  /// node running the same file).
  public func analyzeJSON(_ text: String) throws -> String { try callJSON("analyzeJSON", text) }

  /// canonical.js's `canonicalize(text)`: the canonical text and its reports, or the
  /// grammar's refusal.
  public func canonicalize(_ text: String) throws -> (text: String, reports: [String]) {
    struct Out: Decodable {
      let text: String?
      let reports: [String]?
      let error: String?
      let line: Int?
      let column: Int?
    }
    let out = try JSONDecoder().decode(Out.self, from: Data(callJSON("canonicalize", text).utf8))
    if let error = out.error { throw NotationError.syntax(message: error, line: out.line, column: out.column) }
    return (out.text ?? "", out.reports ?? [])
  }

  /// canonical.js's `isCanonical(text)`.
  public func isCanonical(_ text: String) -> Bool {
    context.objectForKeyedSubscript("PK").invokeMethod("isCanonical", withArguments: [text])?.toBool() ?? false
  }

  private func callJSON(_ method: String, _ text: String) throws -> String {
    var failure: String?
    context.exceptionHandler = { _, value in failure = value?.toString() ?? "an exception" }
    defer { context.exceptionHandler = nil }
    let value = context.objectForKeyedSubscript("PS").invokeMethod(method, withArguments: [text])
    if let failure { throw NotationError.reader("\(method): \(failure)") }
    guard let value, value.isString, let json = value.toString() else {
      throw NotationError.reader("\(method) gave no text")
    }
    return json
  }

  // MARK: Loading the modules as scripts

  /// The parser ends with `export { peg$allowedStartRules as StartRules, ... };`.
  static func wrapParser(_ text: String) -> String {
    let body = text.range(of: "\nexport {", options: .backwards).map { String(text[..<$0.lowerBound]) } ?? text
    return """
      var PK = globalThis.PK || (globalThis.PK = {});
      (function () {
      \(body)
      PK.parse = peg$parse; PK.SyntaxError = peg$SyntaxError; PK.StartRules = peg$allowedStartRules;
      })();
      """
  }

  /// canonical.js imports `parse` and exports `canonicalize` and `isCanonical`.
  static func wrapCanonical(_ text: String) -> String {
    """
    (function () {
    const parse = PK.parse;
    \(stripModule(text))
    PK.canonicalize = canonicalize; PK.isCanonical = isCanonical;
    })();
    """
  }

  /// kubb.js imports nothing and exports `parseGame`, `playerNames` and `analyze`.
  static func wrapKubb(_ text: String) -> String {
    """
    (function () {
    \(stripModule(text))
    PK.parseGame = parseGame; PK.playerNames = playerNames; PK.analyze = analyze;
    })();
    """
  }

  /// Drops `import ... from '...';` lines and the `export` keyword before declarations.
  static func stripModule(_ text: String) -> String {
    text.split(separator: "\n", omittingEmptySubsequences: false).compactMap { line -> Substring? in
      if line.hasPrefix("import ") { return nil }
      if line.hasPrefix("export ") { return line.dropFirst("export ".count) }
      return line
    }.joined(separator: "\n")
  }

  // Pitchside's own figures over kubb.js's analysis, for the stats kubb.js does not give:
  //
  // - zeroBase: where a side's base reached zero, as turn and baton of that turn (kubb.js
  //   gives the team's throw number, `stats.zeroBaseAt`, the scoresheet's "T#").
  // - from8: batons at base kubbs and the king from the baseline: every thrown baton in a
  //   turn with no advantage once the field kubbs are down (a turn with an advantage
  //   throws from the advantage line). Hits are batons that fell a base kubb or the king.
  //
  // Kid games: the engine writes `[Rules "Kid rules, ..."]`.
  static let pitchsideJS = #"""
    var PS = (function () {
      function figures(a) {
        var out = { A: { zeroBase: null, from8: { batons: 0, hits: 0 } },
                    B: { zeroBase: null, from8: { batons: 0, hits: 0 } } };
        a.rows.forEach(function (r) {
          var side = out[r.team];
          var field = r.startField, base = r.startBase, n = 0;
          r.batons.forEach(function (b) {
            if (b.void || b.kind === 'unthrown' || b.kind === 'win' || b.kind === 'resign') return;
            n++;
            var atBase = field === 0;
            if (atBase && !r.advantage) {
              side.from8.batons++;
              if ((b.kind === 'hit' && b.b > 0 && !b.e) || b.kind === 'king') side.from8.hits++;
            }
            if (b.kind === 'hit') {
              field = Math.max(0, field - (b.f || 0));
              if (b.b) {
                base = Math.max(0, base - b.b);
                if (base === 0 && side.zeroBase === null) side.zeroBase = { turn: r.turn, baton: n };
              }
            }
          });
        });
        return out;
      }
      // Keep the released reader's token alignment, side and precision, including
      // null entries for batons whose stance or fall positions were not written.
      function recording(row, turn) {
        const def = row.team === 'A' ? 'b' : 'a';
        function line(mark, half) { return row.lines.find(l => l.mark === mark && l.half === half); }
        function places(entries, precision) {
          return entries.flatMap(e => Array.from({length: e.count}, () => ({
            across: e.at[0], depth: e.at[1], cell: precision === 'cell', mark: e.mark || null
          })));
        }
        const pitch = {};
        for (const half of ['a','b']) {
          const l = line('@', half);
          if (l) pitch[half.toUpperCase()] = places(l.entries, l.precision);
        }
        const lay = line('~', def), stance = line('^', row.team.toLowerCase()), fell = line('*', def);
        const point = xy => ({across: xy[0], depth: xy[1], cell: false});
        return { pitch, inkasts: turn.inkasts.map(k => k.raw),
          advantageMeters: row.advantageMarked && row.advantageMarked.meters,
          lays: lay ? lay.entries.map(e => ({first: point(e.ends[0]), last: point(e.ends[1])})) : [],
          stances: stance ? stance.entries.map(xy => xy && point(xy)) : [],
          falls: fell ? fell.entries.map(word => word && places(word, fell.precision)) : []
        };
      }
      function grammar(text) {
        try { PK.parse(text); return { ok: true }; }
        catch (e) {
          var l = e.location && e.location.start;
          return { ok: false, message: String(e.message), line: l ? l.line : null, column: l ? l.column : null };
        }
      }
      return {
        read: function (text) {
          var a = PK.analyze(text);
          const turns = PK.parseGame(text).turns;
          a.rows.forEach((r, i) => { r.recording = recording(r, turns[i]); });
          var rules = a.headers['Rules'] || '';
          return JSON.stringify({
            analysis: a,
            figures: figures(a),
            grammar: grammar(text),
            canonical: PK.isCanonical(text),
            kid: /^\s*kid\b/i.test(rules)
          });
        },
        analyzeJSON: function (text) { return JSON.stringify(PK.analyze(text)); },
        canonicalize: function (text) {
          try { return JSON.stringify(PK.canonicalize(text)); }
          catch (e) {
            var l = e.location && e.location.start;
            return JSON.stringify({ error: String(e.message), line: l ? l.line : null, column: l ? l.column : null });
          }
        }
      };
    })();
    """#
}
