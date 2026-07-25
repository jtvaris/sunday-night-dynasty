import SwiftUI

// MARK: - Design-System Tokens (Presentation Layer)
//
// The second layer on top of the raw primitives in `Theme.swift`. Where
// `Theme.swift` names *what a color is* (`accentGold`, `success`, …), this file
// names *what a token means* (`chipKey`, `statusOffense`, …) and adds the
// systematic **type** and **elevation** scales the broadcast HUD reads from.
//
// Kept in its own file (rather than folded into `Theme.swift`) so the primitive
// palette and the semantic/typographic system can evolve independently — the
// presentation-polish lanes each own a distinct surface, and the tokens are the
// shared contract between them.
//
// Nothing here changes engine behavior; it is purely how the same simulated
// result is dressed. The midnight-navy + stadium-gold identity is preserved —
// every semantic alias resolves to an existing primitive; the only *new* raw
// values are the two contrast-remedial text colors, which exist solely to clear
// WCAG AA where a legacy primitive failed.

// MARK: - Contrast-Remedial Primitives
//
// Two new raw colors added because their legacy counterparts fail WCAG AA (4.5:1
// for normal text) on the card surface `backgroundSecondary #141E30`. Ratios
// below were measured against `#141E30` with the accesslint WCAG checker.

extension Color {
    /// Readable muted-label color — replaces `textTertiary #64748B` (**3.51:1**,
    /// fails AA) for any *text* role. `#7C8BA1` → **4.82:1** on the card surface,
    /// **5.40:1** on the darker `backgroundPrimary #0B1222` feed surface. Keep
    /// `textTertiary` only for non-text roles (hairlines, disabled fills).
    static let textTertiaryReadable = Color(red: 0.48627, green: 0.54510, blue: 0.63137) // #7C8BA1

    /// Red for destructive/alarm *text* — `danger #EF4444` (~3.4:1) is too dim to
    /// read as words on the dark surfaces. `#F87171` → **6.03:1** on the card,
    /// **6.76:1** on the feed. Use for red text only; keep `danger #EF4444` for
    /// fills, bars, and icon glyphs (where the 3:1 UI-component threshold applies).
    static let dangerText = Color(red: 0.97255, green: 0.44314, blue: 0.44314) // #F87171
}

// MARK: - Semantic Color Aliases
//
// Meaning-named handles onto the primitives. Consumers reference these so a
// future palette shift happens in one place and every surface follows.

extension Color {
    // Possession / unit status — a green "you have the ball" vs a cool "they do".
    // Never alarm-red: a defensive series is not a danger state.
    /// Your team is on offense (has the ball).
    static let statusOffense = Color.success
    /// The opponent has the ball / your unit is defending — cool, not red.
    static let statusDefense = Color.accentBlue

    // Situation chips — the one *key* chip (down & distance) is gold; everything
    // else is a neutral chip whose status rides in a small colored leading dot.
    /// The single highest-priority situational chip (down & distance).
    static let chipKey = Color.accentGold
    /// Informational accent for neutral chips (field position dot, etc.).
    static let chipInfo = Color.accentBlue

    /// Primary call-to-action tint (SNAP / Continue / commit buttons).
    static let ctaPrimary = Color.accentGold

    // X&O play-diagram ink — consumed by the diagram surface (PlayDiagramView).
    // Defined here so route/motion/blitz strokes share one vocabulary.
    /// Base diagram stroke / player ink.
    static let diagramInk = Color.textPrimary
    /// Pre-snap motion path.
    static let diagramMotion = Color.accentBlue
    /// Blitz / pressure arrow.
    static let diagramBlitz = Color.danger
}

// MARK: - Type Scale (DSType)
//
// A skip-step scale from a 9 pt tracked overline up to the 34 pt monospaced
// game clock — the scoreboard's dominant anchor. Skip-step (rather than a dense
// 1-pt ramp) so each level reads as a distinct tier of the hierarchy. Replaces
// scattered raw `.system(size:)` calls on the HUD surfaces.
//
// Hierarchy note: the **clock** is the largest step (34 mono), and the team
// **score** sits one step below (30 mono), so the centered clock reads as the
// single dominant anchor — the plan's "clock the single dominant anchor" ruling,
// realized by putting the clock at the top of the scale rather than the score.

enum DSType {
    /// 9 pt black — tracked micro-labels: stakes/weather badges, overlines.
    static let overline = Font.system(size: 9, weight: .black)
    /// 11 pt semibold — captions, secondary meta.
    static let caption = Font.system(size: 11, weight: .semibold)
    /// 13 pt bold — chips, team abbreviation, secondary feed lines.
    static let label = Font.system(size: 13, weight: .bold)
    /// 14 pt bold — action-button titles, quarter label.
    static let action = Font.system(size: 14, weight: .bold)
    /// 15 pt semibold — body copy, result banner, the latest feed line.
    static let body = Font.system(size: 15, weight: .semibold)
    /// 20 pt bold — section titles.
    static let title = Font.system(size: 20, weight: .bold)
    /// 30 pt black mono — team score; one step below the clock anchor.
    static let score = Font.system(size: 30, weight: .black).monospacedDigit()
    /// 34 pt heavy mono — the game clock: the dominant scoreboard anchor.
    static let clock = Font.system(size: 34, weight: .heavy).monospacedDigit()
}

// MARK: - Elevation (DSElevation)
//
// Navy-tinted shadows — never pure black. A pure-black shadow on the midnight
// field reads as a hard charcoal cut-out ("flat charcoal pills"); a deep-navy
// shadow lets pills and the HUD block lift off the background like broadcast
// chrome while staying inside the night identity.

enum DSElevation {
    /// Deep-navy shadow base (`#04080F`) — the "never pure black" tint.
    static let shadowTint = Color(red: 0.01569, green: 0.03137, blue: 0.05882)

    /// A single elevation step (color already carries its own opacity). The
    /// presets live here so a `.dsElevation(.chip)` leading-dot call resolves.
    struct Shadow {
        let color: Color
        let radius: CGFloat
        let y: CGFloat

        /// Subtle lift for pills / chips / action buttons.
        static let chip = Shadow(color: DSElevation.shadowTint.opacity(0.40), radius: 3, y: 1)
        /// Card / lower-third lift (result banner).
        static let card = Shadow(color: DSElevation.shadowTint.opacity(0.50), radius: 10, y: 4)
        /// The HUD block lifting off the field.
        static let bar = Shadow(color: DSElevation.shadowTint.opacity(0.55), radius: 14, y: 6)
    }
}

extension View {
    /// Applies a navy-tinted `DSElevation` step.
    func dsElevation(_ step: DSElevation.Shadow) -> some View {
        shadow(color: step.color, radius: step.radius, x: 0, y: step.y)
    }
}
