import CLua
import Foundation

// The Kubb Engine behind one door, carried as throwingwood-ios carries it (its
// ThrowingWoodKit/Sources/KubbEngine/Engine.swift, cut to the one engine Pitchside
// carries: no older engines, no neighbours' state).

/// A failed engine call. `call` is the engine's own refusal (`kubbCall`'s
/// `{"error": ...}`); `load` and `lua` are Lua errors outside it.
public enum EngineError: Error, Equatable, CustomStringConvertible {
  case missingSources(String)
  case load(String)
  case call(method: String, message: String)
  case lua(String)

  public var description: String {
    switch self {
    case .missingSources(let what): "engine sources: \(what)"
    case .load(let message): "engine load: \(message)"
    case .call(let method, let message): "\(method): \(message)"
    case .lua(let message): "lua: \(message)"
    }
  }
}

/// The vendored engine's own manifest (`Engine/engine.json`, from the kubb-engine
/// release scripts/vendor-engine.sh copies).
public struct EngineManifest: Decodable, Sendable, Equatable {
  public let name: String
  public let version: String
  /// "core/world.lua" to the file's SHA-256.
  public let files: [String: String]
}

/// kubb-engine (the rules, physics, notation writer and session) in Lua 5.4, behind
/// `call(_:json:)`, the native twin of the engine's `kubbCall` (kubb-engine
/// docs/SESSION.md). Every argument and result is JSON text.
///
/// Each Engine is its own Lua state holding one session. It is not thread safe: use one
/// from one place at a time.
public final class Engine {
  private let state: OpaquePointer
  public let manifest: EngineManifest
  /// The engine's version, as its `engineVersion` call gives it.
  public let engineVersion: String

  /// The tune the session loads (a match will not start without one). Pitchside throws
  /// nothing through the engine's physics today; the pointer's tune is the one every
  /// non-Playdate client uses.
  public static let tune = "pointer"

  /// The label `setClient` gets: the file's `[Scored by "Throwing Wood <label>"]`.
  /// Interim: the engine's writer names Throwing Wood; record mode is to let a host name
  /// itself (AGENTS.md section 5, "The file's labels").
  public static func clientLabel(appVersion: String) -> String { "pitchside \(appVersion)" }

  /// The Location line of a file the engine writes for Pitchside until record mode takes
  /// the real place (the engine accepts letters, digits, spaces, dots, hyphens and pluses).
  public static let location = "Pitchside"

  /// The engine shipped in this package.
  public convenience init(appVersion: String) throws {
    try self.init(directory: Self.bundled(), appVersion: appVersion)
  }

  /// The `Engine` folder in this package's resources.
  public static func bundled() throws -> URL {
    guard let dir = Bundle.module.url(forResource: "Engine", withExtension: nil) else {
      throw EngineError.missingSources("no Engine folder in the bundle")
    }
    return dir
  }

  /// The bundled engine's manifest, read without starting a Lua state.
  public static func bundledManifest() throws -> EngineManifest {
    try manifest(in: bundled())
  }

  static func manifest(in directory: URL) throws -> EngineManifest {
    try JSONDecoder().decode(
      EngineManifest.self, from: Data(contentsOf: directory.appending(path: "engine.json")))
  }

  /// An engine from a folder laid out as `Engine/`: engine.json and the Lua files it
  /// names. `extra` adds modules beside them (a test driver).
  public convenience init(directory: URL, appVersion: String, extra: [String: String] = [:]) throws {
    let manifest: EngineManifest
    do {
      manifest = try Self.manifest(in: directory)
    } catch {
      throw EngineError.missingSources("engine.json: \(error)")
    }
    var sources: [String: String] = extra
    for name in manifest.files.keys {
      guard let text = try? String(contentsOf: directory.appending(path: name), encoding: .utf8) else {
        throw EngineError.missingSources(name)
      }
      sources[String(name.dropLast(4))] = text
    }
    try self.init(sources: sources, manifest: manifest, appVersion: appVersion)
  }

  /// `sources` maps module names as the engine's bundle does ("core/world",
  /// "session/api", "version") to their Lua.
  init(sources: [String: String], manifest: EngineManifest, appVersion: String) throws {
    guard let state = luaL_newstate() else { throw EngineError.load("no memory for a Lua state") }
    do {
      luaL_openlibs(state)
      lua_createtable(state, 0, Int32(sources.count))
      for (name, text) in sources {
        Self.push(state, text)
        lua_setfield(state, -2, name)
      }
      lua_setglobal(state, "__kubbSources")
      try Self.run(state, Self.boot, name: "=boot")
      lua_getglobal(state, "kubbCall")
      let loaded = lua_type(state, -1) == LUA_TFUNCTION
      lua_settop(state, -2)
      if !loaded { throw EngineError.load("session/api did not define kubbCall") }
      let version = try Self.start(state: state, appVersion: appVersion)
      if version != manifest.version {
        throw EngineError.load("the engine says it is \(version), engine.json \(manifest.version)")
      }
      self.engineVersion = version
    } catch {
      lua_close(state)
      throw error
    }
    self.state = state
    self.manifest = manifest
  }

  /// The host's calls before the first `new` or `restore` (kubb-engine docs/SESSION.md
  /// "Starting"): the version, the tune, the client label and location.
  private static func start(state: OpaquePointer, appVersion: String) throws -> String {
    struct Version: Decodable { let version: String }
    func call(_ method: String, _ args: [String: String]) throws -> Data {
      let json = String(decoding: try JSONEncoder().encode(args), as: UTF8.self)
      let text = try callGlobal(state, "kubbCall", [method, json])
      if text.hasPrefix(#"{"error":"#) { throw EngineError.load("\(method): \(text)") }
      return Data(text.utf8)
    }
    let version = try JSONDecoder().decode(Version.self, from: call("engineVersion", [:])).version
    _ = try call("useTune", ["name": tune])
    _ = try call("setClient", ["label": clientLabel(appVersion: appVersion), "location": location])
    return version
  }

  deinit {
    lua_close(state)
  }

  // The engine's import shim (kubb-engine docs/SESSION.md "Loading"), reading the
  // sources table.
  private static let boot = """
    local sources = __kubbSources
    __kubbSources = nil
    function __kubbSource(name) return sources[name] end
    local imported = {}
    function import(name)
      name = name:gsub("%.lua$", "")
      if imported[name] then return nil end
      imported[name] = true
      local s = __kubbSource(name)
      if not s then error("import: no module " .. name, 2) end
      return assert(load(s, "@" .. name))()
    end
    import "session/api"
    """

  /// One engine call: the method's name and its argument as JSON text (empty for none),
  /// the result as JSON text.
  public func call(_ method: String, json: String = "") throws -> String {
    let text = try Self.callGlobal(state, "kubbCall", [method, json])
    if text.hasPrefix(#"{"error":"#) {
      let message =
        (try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])?["error"] as? String
      throw EngineError.call(method: method, message: message ?? text)
    }
    return text
  }

  /// The match's hash (FNV-1a 32 of its snapshot, 8 hex digits).
  public func hash() throws -> String {
    struct Hash: Decodable { let hash: String }
    return try JSONDecoder().decode(Hash.self, from: Data(call("hash").utf8)).hash
  }

  /// Lua's version, as the release this build compiled.
  public var luaVersion: String {
    "Lua \(LUA_VERSION_MAJOR).\(LUA_VERSION_MINOR).\(LUA_VERSION_RELEASE)"
  }

  // MARK: - Lua

  /// Runs a chunk of Lua in this engine's state (tests).
  func run(_ chunk: String, name: String) throws {
    try Self.run(state, chunk, name: name)
  }

  /// Calls a global Lua function with string arguments and one string result (tests).
  func callGlobal(_ function: String, _ args: String...) throws -> String {
    try Self.callGlobal(state, function, args)
  }

  private static func run(_ state: OpaquePointer, _ chunk: String, name: String) throws {
    var chunk = chunk
    let status = chunk.withUTF8 { buf in
      buf.withMemoryRebound(to: CChar.self) {
        luaL_loadbufferx(state, $0.baseAddress, $0.count, name, "t")
      }
    }
    if status != LUA_OK { throw EngineError.load(popError(state)) }
    if lua_pcallk(state, 0, 0, 0, 0, nil) != LUA_OK { throw EngineError.load(popError(state)) }
  }

  private static func callGlobal(_ state: OpaquePointer, _ function: String, _ args: [String]) throws -> String {
    lua_getglobal(state, function)
    for arg in args { push(state, arg) }
    guard lua_pcallk(state, Int32(args.count), 1, 0, 0, nil) == LUA_OK else {
      throw EngineError.lua(popError(state))
    }
    defer { lua_settop(state, -2) }
    var length = 0
    guard let bytes = lua_tolstring(state, -1, &length) else {
      throw EngineError.lua("\(function) returned no text")
    }
    return String(decoding: UnsafeRawBufferPointer(start: bytes, count: length), as: UTF8.self)
  }

  private static func push(_ state: OpaquePointer, _ text: String) {
    var text = text
    text.withUTF8 { buf in
      buf.withMemoryRebound(to: CChar.self) { _ = lua_pushlstring(state, $0.baseAddress, $0.count) }
    }
  }

  private static func popError(_ state: OpaquePointer) -> String {
    defer { lua_settop(state, -2) }
    var length = 0
    guard let bytes = lua_tolstring(state, -1, &length) else { return "(an error that is not text)" }
    return String(decoding: UnsafeRawBufferPointer(start: bytes, count: length), as: UTF8.self)
  }
}

/// What the app calls itself: `<app version> (<engine version>)`, e.g. `0.1 (1.0.0)`,
/// built in this one place (as throwingwood-ios's `VersionLabel`). The build number is a
/// detail line, never in the parentheses.
public struct VersionLabel: Equatable, Sendable {
  public let app: String
  public let engine: String
  public let build: String?

  public init(app: String, engine: String, build: String? = nil) {
    self.app = app
    self.engine = engine
    self.build = build
  }

  /// `0.1 (1.0.0)`.
  public var text: String { "\(app) (\(engine))" }

  /// `build 12`, under `text`.
  public var detail: String? { build.flatMap { $0.isEmpty ? nil : "build \($0)" } }
}
