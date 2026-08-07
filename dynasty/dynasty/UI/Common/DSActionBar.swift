import SwiftUI

// MARK: - DSActionBar — the commit surface
//
// UI_REDESIGN_VISION §2.5 and P5. Persistent, bottom, `backgroundSecondary` over
// a top hairline with a `DSElevation.bar` lift. **It is the only place a screen
// commits.**
//
// The audit counted six primary-action placements (pinned bottom bar · last item
// in a ScrollView · last List section · inside a header that scrolls away ·
// .toolbar · mid-panel in a side rail) plus two screens with no primary at all.
// The worst of them shipped: draft prep's advance was a 12 pt greyed button
// inside the Big Board's scroll-away header, i.e. the most important control on
// the screen parked where a 350-row list scrolled it out of existence.
//
//   LEFT   an explainer — gold left rule, uppercase 11 pt title, one or two
//          lines with the load-bearing nouns emphasised. A blocked commit swaps
//          the rule to orange and says the reason (§2.12).
//   RIGHT  the fixed button order, always in this sequence and no other:
//          [destructive · vertical rule] [ghost] [secondary] [PRIMARY]
//
// Destructive is separated by a rule and is never adjacent to the primary.

struct DSActionBar: View {

    /// §2.4 `DSExplainerCard`, in its action-bar placement: what committing does
    /// and what it costs.
    struct Explainer: Equatable {
        /// Uppercased by the bar.
        var title: String
        /// One or two lines. Markdown is honoured, so a call site emphasises the
        /// load-bearing nouns with `**…**`.
        var message: String
        /// A blocked commit: orange rule, and the message is the reason.
        var isWarning: Bool = false

        /// The message with its markdown emphasis removed.
        ///
        /// The visible label is a `LocalizedStringKey`, which renders `**…**` as
        /// bold; an accessibility label is a plain `String`, which reads the
        /// asterisks out loud. Every call site that hands this copy to
        /// VoiceOver goes through here.
        static func spoken(_ message: String) -> String {
            message.replacingOccurrences(of: "**", with: "")
        }
    }

    /// One button. `caption` is the second line a ghost uses to say what the
    /// action forfeits.
    struct Action {
        var title: String
        var caption: String?
        var isEnabled: Bool
        var accessibilityLabel: String?
        var handler: () -> Void

        init(
            title: String,
            caption: String? = nil,
            isEnabled: Bool = true,
            accessibilityLabel: String? = nil,
            handler: @escaping () -> Void
        ) {
            self.title = title
            self.caption = caption
            self.isEnabled = isEnabled
            self.accessibilityLabel = accessibilityLabel
            self.handler = handler
        }
    }

    var explainer: Explainer?
    var destructive: Action?
    var ghost: Action?
    var secondary: Action?
    var primary: Action?

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            if let explainer { explainerView(explainer) }
            Spacer(minLength: 12)
            actions
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.backgroundSecondary)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.surfaceBorder).frame(height: 1)
        }
        .dsElevation(.bar)
    }

    // MARK: Explainer

    private func explainerView(_ explainer: Explainer) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Capsule()
                .fill(explainer.isWarning ? Color.alertOrange : Color.accentGold)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text(explainer.title.uppercased())
                    .font(DSType.display(11, .heavy))
                    .tracking(0.7)
                    .foregroundStyle(explainer.isWarning ? Color.alertOrange : Color.accentGold)
                    .lineLimit(1)
                Text(LocalizedStringKey(explainer.message))
                    .font(DSType.text(12, .regular))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 420, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Buttons — one order, everywhere

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: DSSpacing.xs) {
            if let destructive {
                button(destructive, style: .destructive)
                Rectangle()
                    .fill(Color.surfaceBorder)
                    .frame(width: 1, height: 28)
            }
            if let ghost { button(ghost, style: .ghost) }
            if let secondary { button(secondary, style: .secondary) }
            if let primary { button(primary, style: .primary) }
        }
    }

    private enum Kind { case primary, secondary, ghost, destructive }

    @ViewBuilder
    private func button(_ action: Action, style: Kind) -> some View {
        let label = DSActionLabel(title: action.title, caption: action.caption)
        Group {
            switch style {
            case .primary:     Button(action: action.handler) { label }.buttonStyle(.dsPrimary)
            case .secondary:   Button(action: action.handler) { label }.buttonStyle(.dsSecondary)
            case .ghost:       Button(action: action.handler) { label }.buttonStyle(.dsGhost)
            case .destructive: Button(action: action.handler) { label }.buttonStyle(.dsDestructive)
            }
        }
        .disabled(!action.isEnabled)
        .accessibilityLabel(
            action.accessibilityLabel
                ?? [action.title, action.caption].compactMap { $0 }.joined(separator: ". ")
        )
    }
}

/// The two-line button label. One line is the common case; the second is how a
/// ghost states what it forfeits without a tooltip nobody can reach.
private struct DSActionLabel: View {
    let title: String
    let caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(DSType.text(14, .semibold))
                .lineLimit(1)
            if let caption, !caption.isEmpty {
                Text(caption)
                    .font(DSType.display(11, .semibold))
                    .opacity(0.75)
                    .lineLimit(2)
                    .frame(maxWidth: 210, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - The one ButtonStyle set (§2.8)
//
// Four styles replacing the three hand-copied gold recipes and their two corner
// radii. **Disabled is a genuinely disabled grey** — `#131C2C` fill over a
// `#7C8BA1` label, the latter still clearing AA because a disabled label is
// still information — never dimmed gold. Five separate audit findings ask for
// exactly this.
//
// Interactive objects look raised (§2.12): a vertical gradient plus a
// `DSElevation` shadow, so a button can never be mistaken for a status chip and
// a status chip can never be mistaken for a button.

private struct DSButtonChrome: View {
    @Environment(\.isEnabled) private var isEnabled

    let configuration: ButtonStyleConfiguration
    let fill: AnyShapeStyle
    let ink: Color
    let border: Color
    let lifted: Bool

    var body: some View {
        configuration.label
            .font(DSType.text(14, .semibold))
            .foregroundStyle(isEnabled ? ink : Color.textTertiaryReadable)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                    .fill(isEnabled ? fill : AnyShapeStyle(Color.controlDisabled))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                    .strokeBorder(isEnabled ? border : Color.surfaceBorder, lineWidth: 1)
            )
            .dsElevation(lifted && isEnabled && !configuration.isPressed ? .chip : .none)
            .offset(y: configuration.isPressed ? 1 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

struct DSPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        DSButtonChrome(
            configuration: configuration,
            fill: AnyShapeStyle(
                LinearGradient(
                    colors: [Color.accentGold, Color.accentGold.opacity(0.86)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            ),
            ink: .backgroundPlate,
            border: .clear,
            lifted: true
        )
    }
}

struct DSSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        DSButtonChrome(
            configuration: configuration,
            fill: AnyShapeStyle(Color.backgroundTertiary),
            ink: .textPrimary,
            border: .surfaceBorder,
            lifted: true
        )
    }
}

struct DSGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        DSButtonChrome(
            configuration: configuration,
            fill: AnyShapeStyle(Color.clear),
            ink: .textSecondary,
            border: .surfaceBorder,
            lifted: false
        )
    }
}

struct DSDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        DSButtonChrome(
            configuration: configuration,
            fill: AnyShapeStyle(Color.clear),
            ink: .dangerText,
            border: .dangerText.opacity(0.5),
            lifted: false
        )
    }
}

extension ButtonStyle where Self == DSPrimaryButtonStyle {
    /// The one gold fill on a screen.
    static var dsPrimary: DSPrimaryButtonStyle { DSPrimaryButtonStyle() }
}

extension ButtonStyle where Self == DSSecondaryButtonStyle {
    static var dsSecondary: DSSecondaryButtonStyle { DSSecondaryButtonStyle() }
}

extension ButtonStyle where Self == DSGhostButtonStyle {
    static var dsGhost: DSGhostButtonStyle { DSGhostButtonStyle() }
}

extension ButtonStyle where Self == DSDestructiveButtonStyle {
    static var dsDestructive: DSDestructiveButtonStyle { DSDestructiveButtonStyle() }
}

// MARK: - Preview

#Preview {
    ZStack(alignment: .bottom) {
        Color.backgroundPrimary.ignoresSafeArea()
        DSActionBar(
            explainer: .init(
                title: "Advance \u{2014} Pro Day Focus",
                message: "Closes **Film Study** and spends **1 of 6** scouting weeks left in the spring."
            ),
            ghost: .init(
                title: "Skip this stage",
                caption: "Your board stays the media's board.",
                handler: {}
            ),
            primary: .init(title: "Advance \u{2014} Pro Day Focus", handler: {})
        )
    }
}
