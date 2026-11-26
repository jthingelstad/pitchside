// swift-tools-version: 6.0
import PackageDescription

// Flags that keep the engine's floating point the same as the web's WebAssembly build
// (wasmoon: Lua 5.4 and musl's libm, compiled for wasm), as throwingwood-ios builds it:
// no fused multiply-add (wasm has none), and no compiler built-ins standing in for the
// library's sin, pow, floor and the rest.
let exactFloatingPoint = ["-ffp-contract=off", "-fno-builtin"]

// Textual headers, not prebuilt modules: a module of Apple's math.h would be built
// without the twm_ names (CMusl/include/twm_names.h) and declare the system's sin in
// place of musl's.
let textualHeaders = ["-fno-modules"]

let package = Package(
  name: "PitchsideKit",
  platforms: [.iOS("26.0"), .macOS("15.0")],
  products: [
    .library(name: "KubbEngine", targets: ["KubbEngine"]),
    .library(name: "Notation", targets: ["Notation"]),
    .library(name: "PitchsideModel", targets: ["PitchsideModel"]),
    .library(name: "PitchsideDesign", targets: ["PitchsideDesign"]),
  ],
  targets: [
    // musl 1.2.5's portable C maths, every symbol renamed twm_*: a copy of
    // throwingwood-ios's target (see NOTICE.md; scripts/check-libm.sh proves it).
    .target(
      name: "CMusl",
      exclude: ["NOTICE.md", "COPYRIGHT"],
      cSettings: [
        .headerSearchPath("musl/arch/aarch64"),
        .headerSearchPath("musl/arch/generic"),
        .headerSearchPath("musl/src/include"),
        .headerSearchPath("musl/src/internal"),
        .headerSearchPath("musl/include"),
        .headerSearchPath("config"),
        .unsafeFlags(
          ["-nostdinc", "-std=c99", "-U__FP_FAST_FMA", "-include", "twm_musl.h", "-w"]
            + exactFloatingPoint + textualHeaders),
      ]
    ),
    // Lua 5.4.5 at the commit wasmoon 1.16 ships, unedited; config/twl_config.h points
    // its maths at CMusl and fills in what iOS lacks. A copy of throwingwood-ios's.
    .target(
      name: "CLua",
      dependencies: ["CMusl"],
      exclude: ["NOTICE.md", "LICENSE"],
      cSettings: [
        .define("LUA_USE_POSIX"),
        .headerSearchPath("config"),
        .unsafeFlags(["-include", "twl_config.h", "-w"] + exactFloatingPoint + textualHeaders),
      ]
    ),
    // The Kubb Engine: one kubb-engine release (Engine/, vendored byte for byte by
    // scripts/vendor-engine.sh) behind kubbCall.
    .target(name: "KubbEngine", dependencies: ["CLua"], resources: [.copy("Engine")]),
    // Planet Kubb Notation's own reader (Vendor/, a pk-kubb-score release vendored by
    // scripts/vendor-notation.sh) run in JavaScriptCore.
    .target(
      name: "Notation",
      exclude: ["Vendor/SOURCE", "Vendor/SHA256SUMS", "Vendor/LICENSE-Peggy.txt", "Vendor/README.md"],
      resources: [
        .copy("Vendor/notation-parser.js"), .copy("Vendor/canonical.js"), .copy("Vendor/kubb.js"),
      ]
    ),
    // Pitchside's own model: the roster, teams, a game and its event log, the files on
    // this phone, the score sheet and the stats. ReferenceGames/ is archived games from
    // the same pk-kubb-score release, vendored by scripts/vendor-notation.sh.
    .target(
      name: "PitchsideModel", dependencies: ["Notation", "KubbEngine"],
      resources: [.copy("ReferenceGames")]),
    // The design system from docs/design/canvas/ps.css, light and dark.
    .target(name: "PitchsideDesign"),
    .testTarget(
      name: "KubbEngineTests", dependencies: ["KubbEngine"], resources: [.copy("Fixtures")]),
    .testTarget(
      name: "NotationTests", dependencies: ["Notation", "PitchsideModel", "KubbEngine"],
      resources: [.copy("Fixtures")]),
    .testTarget(
      name: "PitchsideModelTests", dependencies: ["PitchsideModel", "Notation", "KubbEngine"],
      resources: [.copy("Fixtures")]),
    .testTarget(name: "PitchsideDesignTests", dependencies: ["PitchsideDesign"]),
  ]
)
