import SwiftUI

// MARK: Surfaces

extension View {
  public func psCard(fill: Color = .psPlate) -> some View {
    background(fill, in: RoundedRectangle(cornerRadius: 12))
      .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.psLine.opacity(0.38)))
  }

  public func psBox() -> some View {
    background(Color.psInside, in: RoundedRectangle(cornerRadius: 8))
      .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.psLine.opacity(0.45)))
  }
}

// MARK: Text styles

extension Text {
  /// A short label for a group of related controls.
  public func psKick() -> some View {
    font(PSFont.body(15, .semibold, relativeTo: .subheadline))
      .foregroundStyle(Color.psMuted)
  }
  /// Help under a control: Inter 14, muted.
  public func psHelp() -> some View {
    font(PSFont.body(14, relativeTo: .footnote)).foregroundStyle(Color.psMuted)
  }
}

// MARK: Buttons

public struct PSButtonStyle: ButtonStyle {
  public var solid: Bool
  public var minHeight: CGFloat
  @Environment(\.isEnabled) private var isEnabled

  public init(solid: Bool = false, minHeight: CGFloat = 50) {
    self.solid = solid
    self.minHeight = minHeight
  }

  public func makeBody(configuration: Configuration) -> some View {
    let pressed = configuration.isPressed
    configuration.label
      .font(PSFont.body(17, .semibold, relativeTo: .headline))
      .multilineTextAlignment(.center)
      .foregroundStyle(solid ? Color.psOnSolid : Color.psText)
      .padding(.horizontal, 14)
      .padding(.vertical, 6)
      .frame(maxWidth: .infinity, minHeight: minHeight)
      .background(solid ? Color.psSolid : Color.psPlate, in: RoundedRectangle(cornerRadius: 9))
      .overlay {
        if !solid { RoundedRectangle(cornerRadius: 9).strokeBorder(Color.psLine) }
      }
      .opacity(isEnabled ? (pressed ? 0.78 : 1) : 0.52)
      .contentShape(Rectangle())
  }
}

/// A text action with the same minimum target as a filled button.
public struct QuietButtonStyle: ButtonStyle {
  public init() {}
  public func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(PSFont.body(16, .semibold, relativeTo: .headline))
      .foregroundStyle(Color.psSolid)
      .padding(.horizontal, 6)
      .frame(minWidth: 48, minHeight: 48)
      .contentShape(Rectangle())
      .opacity(configuration.isPressed ? 0.6 : 1)
  }
}

extension ButtonStyle where Self == PSButtonStyle {
  public static var ps: PSButtonStyle { PSButtonStyle() }
  public static var psSolid: PSButtonStyle { PSButtonStyle(solid: true) }
}

extension ButtonStyle where Self == QuietButtonStyle {
  public static var quiet: QuietButtonStyle { QuietButtonStyle() }
}

// MARK: Chip

/// A short status on its own surface.
public struct Chip: View {
  let text: String
  public init(_ text: String) { self.text = text }
  public var body: some View {
    Text(text)
      .font(PSFont.body(14, .bold, relativeTo: .footnote))
      .foregroundStyle(Color.psText)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .psBox()
  }
}

// MARK: Segmented

/// `.seg`: a row of choices in one box; the chosen one is solid. Each part is 48 points
/// tall at least. At the largest text sizes the parts stack. VoiceOver reads each as a
/// button: "Grass, selected, 1 of 3".
public struct Segmented<Value: Hashable>: View {
  let label: String
  let options: [(Value, String)]
  @Binding var selection: Value
  @Environment(\.dynamicTypeSize) private var typeSize

  public init(_ label: String, options: [(Value, String)], selection: Binding<Value>) {
    self.label = label
    self.options = options
    self._selection = selection
  }

  public var body: some View {
    let stacked = typeSize >= .accessibility2
    let layout = stacked ? AnyLayout(VStackLayout(spacing: 3)) : AnyLayout(HStackLayout(spacing: 3))
    layout {
      ForEach(Array(options.enumerated()), id: \.offset) { i, option in
        let on = option.0 == selection
        Button {
          selection = option.0
        } label: {
          Text(option.1)
            .font(PSFont.body(15, .bold, relativeTo: .subheadline))
            .multilineTextAlignment(.center)
            .foregroundStyle(on ? Color.psSolid : Color.psMuted)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(on ? Color.psPlate : .clear, in: RoundedRectangle(cornerRadius: 7))
            .overlay { if on { RoundedRectangle(cornerRadius: 7).strokeBorder(Color.psSolid) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.1)
        .accessibilityValue(on ? "selected, \(i + 1) of \(options.count)" : "\(i + 1) of \(options.count)")
        .accessibilityHint(label)
        .accessibilityAddTraits(on ? [.isSelected] : [])
      }
    }
    .padding(3)
    .background(Color.psInside, in: RoundedRectangle(cornerRadius: 9))
    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.psLine.opacity(0.5)))
  }
}

// MARK: Team marker

/// A team's mark: the same rounded square for both sides (the kubb's shape), told apart
/// by colour and by the side's letter, so colour is never the only cue.
public struct TeamMarker: View {
  public enum Side: String, Sendable { case A, B }
  let side: Side
  let size: CGFloat
  let letter: Bool

  public init(_ side: Side, size: CGFloat = 22, letter: Bool = true) {
    self.side = side
    self.size = size
    self.letter = letter
  }

  public static func fill(_ side: Side) -> Color { side == .A ? Tokens.teamA.color : Tokens.teamB.color }
  public static func ink(_ side: Side) -> Color { side == .A ? Tokens.teamAInk.color : Tokens.teamBInk.color }

  public var body: some View {
    RoundedRectangle(cornerRadius: max(3, size / 6))
      .fill(Self.fill(side))
      .overlay(RoundedRectangle(cornerRadius: max(3, size / 6)).strokeBorder(Color.psKubbInk.opacity(0.45), lineWidth: 1))
      .overlay {
        if letter {
          Text(side.rawValue)
            .font(.custom("Inter", fixedSize: max(14, size * 0.62)).weight(.black))
            .foregroundStyle(Self.ink(side))
        }
      }
      .frame(width: size, height: size)
      .accessibilityHidden(true)
  }
}

// MARK: Screen header

public struct ScreenHeader: View {
  let title: String
  let back: String?
  let brand: String?
  let action: (() -> Void)?

  public init(_ title: String, back: String? = nil, brand: String? = nil, action: (() -> Void)? = nil) {
    self.title = title
    self.back = back
    self.brand = brand
    self.action = action
  }

  public var body: some View {
    HStack(spacing: 4) {
      if let back, let action {
        Button(action: action) {
          Image(systemName: "chevron.backward")
            .font(.system(size: 19, weight: .semibold))
            .frame(width: 48, height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back to \(back)")
      }
      Text(title)
        .font(PSFont.display(back == nil ? 32 : 24, relativeTo: back == nil ? .largeTitle : .title2))
        .accessibilityAddTraits(.isHeader)
      Spacer(minLength: 4)
      if let brand {
        Text(brand)
          .font(.custom("LondrinaSolid-Black", size: 22, relativeTo: .headline))
          .foregroundStyle(Color.psSolid)
      }
    }
    .foregroundStyle(Color.psText)
    .padding(.leading, back == nil ? 16 : 2)
    .padding(.trailing, 16)
    .padding(.vertical, 4)
    .frame(minHeight: 56)
    .background(Color.psPlate.ignoresSafeArea(edges: .top))
    .overlay(alignment: .bottom) { Divider() }
  }
}
