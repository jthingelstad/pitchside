import SwiftUI

// The shared primitives of ps.css: card, button (plain and solid), quiet button, chip,
// segmented control, kicker, and the team marker. Touch targets are 48 points at least.

// MARK: Card

/// `.card`: a 3-point line, radius 8, a hard 5-point shadow, plate fill.
public struct CardStyle: ViewModifier {
  var fill: Color
  var shadow: CGFloat
  public func body(content: Content) -> some View {
    content
      .background(fill, in: RoundedRectangle(cornerRadius: 8))
      .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.psLine, lineWidth: 3))
      .background(
        RoundedRectangle(cornerRadius: 8).fill(Color.psShade).offset(x: shadow, y: shadow))
  }
}

/// A thin box (2-point line, radius 6, no shadow): the lists inside a screen.
public struct BoxStyle: ViewModifier {
  public func body(content: Content) -> some View {
    content
      .background(Color.psInside, in: RoundedRectangle(cornerRadius: 6))
      .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.psLine, lineWidth: 2))
  }
}

extension View {
  public func psCard(fill: Color = .psPlate, shadow: CGFloat = 5) -> some View {
    modifier(CardStyle(fill: fill, shadow: shadow))
  }
  public func psBox() -> some View { modifier(BoxStyle()) }
}

// MARK: Text styles

extension Text {
  /// `.kick`: Inter bold 14, uppercase, tracked .06em, muted.
  public func psKick() -> some View {
    font(PSFont.body(14, .bold, relativeTo: .subheadline)).tracking(14 * 0.06).textCase(.uppercase)
      .foregroundStyle(Color.psMuted)
  }
  /// Help under a control: Inter 14, muted.
  public func psHelp() -> some View {
    font(PSFont.body(14, relativeTo: .footnote)).foregroundStyle(Color.psMuted)
  }
}

// MARK: Buttons

/// `.btn` (plain) and `.btn.solid`: Londrina 20 uppercase, 3-point line, radius 6, a
/// 3-point shadow that the press takes away.
public struct PSButtonStyle: ButtonStyle {
  public var solid: Bool
  public var minHeight: CGFloat
  @Environment(\.isEnabled) private var isEnabled

  public init(solid: Bool = false, minHeight: CGFloat = 56) {
    self.solid = solid
    self.minHeight = minHeight
  }

  public func makeBody(configuration: Configuration) -> some View {
    let pressed = configuration.isPressed
    configuration.label
      .font(PSFont.display(20, relativeTo: .headline))
      .tracking(0.6)
      .textCase(.uppercase)
      .multilineTextAlignment(.center)
      .foregroundStyle(solid ? Color.psOnSolid : Color.psText)
      .padding(.horizontal, 14)
      .padding(.vertical, 6)
      .frame(maxWidth: .infinity, minHeight: minHeight)
      .background(solid ? Color.psSolid : Color.psPlate, in: RoundedRectangle(cornerRadius: 6))
      .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.psLine, lineWidth: 3))
      .background(
        RoundedRectangle(cornerRadius: 6).fill(Color.psShade).offset(x: pressed ? 0 : 3, y: pressed ? 0 : 3))
      .offset(x: pressed ? 3 : 0, y: pressed ? 3 : 0)
      .opacity(isEnabled ? 1 : 0.55)
      .contentShape(Rectangle())
  }
}

/// `.quiet`: an underlined Londrina 18 word, 48 points tall.
public struct QuietButtonStyle: ButtonStyle {
  public init() {}
  public func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(PSFont.display(18, relativeTo: .headline))
      .tracking(0.5)
      .textCase(.uppercase)
      .underline()
      .foregroundStyle(Color.psText)
      .padding(.horizontal, 6)
      .frame(minHeight: 48)
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

/// `.chip`: Inter bold 14 in a 2-point box.
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
    let layout = stacked ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
    layout {
      ForEach(Array(options.enumerated()), id: \.offset) { i, option in
        let on = option.0 == selection
        Button {
          selection = option.0
        } label: {
          Text(option.1)
            .font(PSFont.body(15, .bold, relativeTo: .subheadline))
            .multilineTextAlignment(.center)
            .foregroundStyle(on ? Color.psOnSolid : Color.psText)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(on ? Color.psSolid : Color.psField)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: stacked ? .top : .leading) {
          if i > 0 {
            Rectangle().fill(Color.psLine).frame(width: stacked ? nil : 3, height: stacked ? 3 : nil)
          }
        }
        .accessibilityLabel(option.1)
        .accessibilityValue(on ? "selected, \(i + 1) of \(options.count)" : "\(i + 1) of \(options.count)")
        .accessibilityHint(label)
        .accessibilityAddTraits(on ? [.isSelected] : [])
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: 6))
    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.psLine, lineWidth: 3))
    .background(RoundedRectangle(cornerRadius: 6).fill(Color.psShade).offset(x: 3, y: 3))
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
      .overlay(RoundedRectangle(cornerRadius: max(3, size / 6)).strokeBorder(Color.psLine, lineWidth: size >= 30 ? 3 : 2))
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

/// The wood header of a screen: a quiet back word on the left, the title on the right
/// (Teams, This game, Score sheet, Stats). Home has its own.
public struct ScreenHeader: View {
  let title: String
  let back: String?
  let action: (() -> Void)?

  public init(_ title: String, back: String? = nil, action: (() -> Void)? = nil) {
    self.title = title
    self.back = back
    self.action = action
  }

  public var body: some View {
    HStack(alignment: .lastTextBaseline) {
      if let back, let action {
        Button(back, action: action).buttonStyle(.quiet)
          .accessibilityLabel("Back to \(back)")
      }
      Spacer(minLength: 8)
      Text(title)
        .font(PSFont.display(34, relativeTo: .largeTitle))
        .foregroundStyle(Color.psText)
        .multilineTextAlignment(.trailing)
        .accessibilityAddTraits(.isHeader)
    }
    .padding(.horizontal, 16)
    .padding(.top, 8)
    .padding(.bottom, 12)
    .frame(maxWidth: .infinity)
    .background(Color.psWood.ignoresSafeArea(edges: .top))
    .overlay(alignment: .bottom) { Rectangle().fill(Color.psLine).frame(height: 3) }
  }
}
