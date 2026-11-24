import SwiftUI

#if canImport(UIKit)
  import UIKit
#elseif canImport(AppKit)
  import AppKit
#endif

// Pitchside's tokens, from docs/design/canvas/ps.css (".ps" light, ".ps.dark"):
// Throwing Wood's woodcut, tuned for a tool. Every colour has a light and a dark value
// and follows the system's appearance.

/// A colour as 0xRRGGBB.
public struct Hex: Sendable, Equatable {
  public let rgb: UInt32
  public init(_ rgb: UInt32) { self.rgb = rgb }

  var r: Double { Double((rgb >> 16) & 0xFF) / 255 }
  var g: Double { Double((rgb >> 8) & 0xFF) / 255 }
  var b: Double { Double(rgb & 0xFF) / 255 }

  /// WCAG relative luminance.
  public var luminance: Double {
    func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
  }

  /// WCAG contrast ratio, 1 to 21.
  public func contrast(_ other: Hex) -> Double {
    let (l1, l2) = (luminance, other.luminance)
    return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
  }
}

/// One token: its light and dark values.
public struct Token: Sendable, Equatable {
  public let name: String
  public let light: Hex
  public let dark: Hex

  public var color: Color {
    #if canImport(UIKit)
      Color(
        uiColor: UIColor { $0.userInterfaceStyle == .dark ? Self.ui(dark) : Self.ui(light) })
    #else
      Color(
        nsColor: NSColor(name: nil) {
          $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? Self.ns(dark) : Self.ns(light)
        })
    #endif
  }

  #if canImport(UIKit)
    static func ui(_ h: Hex) -> UIColor { UIColor(red: h.r, green: h.g, blue: h.b, alpha: 1) }
  #else
    static func ns(_ h: Hex) -> NSColor { NSColor(srgbRed: h.r, green: h.g, blue: h.b, alpha: 1) }
  #endif
}

public enum Tokens {
  public static let text = Token(name: "text", light: Hex(0x16130F), dark: Hex(0xF7F0DE))
  public static let ground = Token(name: "ground", light: Hex(0xF7F0DE), dark: Hex(0x16130F))
  public static let plate = Token(name: "plate", light: Hex(0xF7F0DE), dark: Hex(0x262019))
  public static let inside = Token(name: "inside", light: Hex(0xFBF6EA), dark: Hex(0x332B20))
  public static let field = Token(name: "field", light: Hex(0xFFFFFF), dark: Hex(0x3D3426))
  public static let line = Token(name: "line", light: Hex(0x16130F), dark: Hex(0xF7F0DE))
  public static let shade = Token(name: "shade", light: Hex(0x16130F), dark: Hex(0x000000))
  public static let solid = Token(name: "solid", light: Hex(0x16130F), dark: Hex(0xF7F0DE))
  public static let onSolid = Token(name: "on-solid", light: Hex(0xF7F0DE), dark: Hex(0x16130F))
  public static let muted = Token(name: "muted", light: Hex(0x5B4A2C), dark: Hex(0xDCCBA4))
  public static let warn = Token(name: "warn", light: Hex(0xCC3A30), dark: Hex(0xFF8A7D))
  public static let wood = Token(name: "wood", light: Hex(0xECD09A), dark: Hex(0x5B4A2C))
  public static let kubb = Token(name: "kubb", light: Hex(0xECD09A), dark: Hex(0xECD09A))
  public static let kubbRest = Token(name: "kubb-rest", light: Hex(0xC79A58), dark: Hex(0xA37F48))
  public static let grass = Token(name: "grass", light: Hex(0x4F9A3B), dark: Hex(0x2C5A22))
  public static let rough = Token(name: "rough", light: Hex(0x3D7F2C), dark: Hex(0x1F4218))
  public static let chalk = Token(name: "chalk", light: Hex(0xFBF6EA), dark: Hex(0xF7F0DE))
  /// The ink a kubb or the king is outlined and lettered in: always dark, on wood.
  public static let kubbInk = Token(name: "kubb-ink", light: Hex(0x16130F), dark: Hex(0x16130F))
  /// Team A, marigold; Team B, violet (Throwing Wood's team colours). Same in dark.
  public static let teamA = Token(name: "team-a", light: Hex(0xF2B705), dark: Hex(0xF2B705))
  public static let teamB = Token(name: "team-b", light: Hex(0x80399D), dark: Hex(0x80399D))
  /// The letter on a team marker: ink on marigold, white on violet.
  public static let teamAInk = Token(name: "team-a-ink", light: Hex(0x16130F), dark: Hex(0x16130F))
  public static let teamBInk = Token(name: "team-b-ink", light: Hex(0xFFFFFF), dark: Hex(0xFFFFFF))

  public static let all: [Token] = [
    text, ground, plate, inside, field, line, shade, solid, onSolid, muted, warn, wood, kubb, kubbRest, grass,
    rough, chalk, kubbInk, teamA, teamB, teamAInk, teamBInk,
  ]
}

extension Color {
  public static let psText = Tokens.text.color
  public static let psGround = Tokens.ground.color
  public static let psPlate = Tokens.plate.color
  public static let psInside = Tokens.inside.color
  public static let psField = Tokens.field.color
  public static let psLine = Tokens.line.color
  public static let psShade = Tokens.shade.color
  public static let psSolid = Tokens.solid.color
  public static let psOnSolid = Tokens.onSolid.color
  public static let psMuted = Tokens.muted.color
  public static let psWarn = Tokens.warn.color
  public static let psWood = Tokens.wood.color
  public static let psKubb = Tokens.kubb.color
  public static let psKubbRest = Tokens.kubbRest.color
  public static let psGrass = Tokens.grass.color
  public static let psRough = Tokens.rough.color
  public static let psChalk = Tokens.chalk.color
  public static let psKubbInk = Tokens.kubbInk.color
}

// MARK: - Type

/// Inter (body) and Londrina Solid Black (display), registered by the app (Info.plist
/// UIAppFonts). Every size scales with Dynamic Type from its text style; nothing is set
/// under 14 points.
public enum PSFont {
  public static func body(_ size: CGFloat, _ weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body)
    -> Font
  {
    .custom("Inter", size: max(size, 14), relativeTo: style).weight(weight)
  }

  public static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
    .custom("LondrinaSolid-Black", size: max(size, 14), relativeTo: style)
  }

  public static func mono(_ size: CGFloat = 14, relativeTo style: Font.TextStyle = .callout) -> Font {
    .custom("Menlo", size: max(size, 14), relativeTo: style)
  }
}
