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
// Two new raw colors added because a *dimmed* or too-saturated counterpart fails
// WCAG AA (4.5:1 for normal text) on the card surface `backgroundSecondary
// #141E30`. Ratios below were measured against `#141E30` with the accesslint
// WCAG checker. Note these are floors for previously-failing roles, not the
// brightest muted text available — see each token's note.

extension Color {
    /// Readable muted-label color for *dimmed* text — the replacement for
    /// `textTertiary.opacity(0.5…0.6)`, which drops well under AA. `#7C8BA1` →
    /// **4.82:1** on the card surface `#141E30`, **5.39:1** on the darker
    /// `backgroundPrimary #0B1222` feed surface.
    ///
    /// ⚠️ This token is **darker** than plain `Color.textTertiary` (`#8A96A8`,
    /// 5.56:1 / 6.23:1 — lightened in 65ab875, it no longer is the old `#64748B`
    /// that failed AA). Never swap a plain `textTertiary` label to this token:
    /// that *lowers* contrast by ~14%. Reach for it only where the site was
    /// carrying an opacity modifier that has to go away.
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

    // MARK: App-Wide Size Ladder
    //
    // The `Font` presets below dress the *broadcast HUD*: they carry a weight
    // baked in, which is exactly right for a surface with eight roles and no
    // exceptions. The rest of the app cannot use them — a roster cell needs
    // `.monospacedDigit()`, a badge needs `.heavy`, a stat needs `.black`, and
    // baking one weight per step would force a preset per (size × weight) pair.
    //
    // So the ladder is published twice: as the finished `Font` presets for the
    // HUD, and as bare point sizes here for everything else. A call site keeps
    // its own weight and design and only borrows the step:
    //
    //     .font(.system(size: DSType.Size.micro, weight: .heavy))
    //
    // The steps are *derived*, not invented — an audit of every
    // `.system(size:)` literal in the app found 38 distinct sizes, and these
    // ten are the ones that actually carry the hierarchy (each is among the
    // most-used values at its tier). Anything off this ladder is design debt;
    // `tools/lint/design_tokens.py` counts it and reports the delta.
    //
    // `micro` is a floor as much as a step. The same audit found 1357 literals
    // under 12 pt, including a long tail at 5–8 pt — sizes at which a badge is
    // a smudge rather than a word. Nothing informational should go below it.
    //
    // Known gap: `label` (13), `action` (14), `body` (15), `title` (20),
    // `score` (30) and `clock` (34) predate this ladder and stay pinned to
    // their shipped values — the HUD was tuned by eye and re-basing it is a
    // visual change, not a token change. They are the one sanctioned exception.

    enum Size {
        /// 10 — the legibility floor: dense table cells, badge and chip
        /// captions, the "OVR"/"AGE" sub-labels under a stat. Never go under
        /// this for text a player is expected to read.
        static let micro: CGFloat = 10
        /// 11 — captions, secondary meta, column headers.
        static let caption: CGFloat = 11
        /// 12 — footnotes, supporting lines under a title.
        static let footnote: CGFloat = 12
        /// 14 — body copy and the default for list-row primary text.
        static let body: CGFloat = 14
        /// 16 — callouts, card titles, emphasised values.
        static let callout: CGFloat = 16
        /// 18 — sub-section titles.
        static let title3: CGFloat = 18
        /// 22 — section titles, sheet headers.
        static let title2: CGFloat = 22
        /// 28 — screen titles, the big number on a summary tile.
        static let title1: CGFloat = 28
        /// 36 — display figures: final scores, headline stats.
        static let display: CGFloat = 36
        /// 48 — hero numerals on a full-bleed moment (draft pick, result card).
        static let hero: CGFloat = 48
    }

    // MARK: The two voices (UI_REDESIGN_VISION §2.10)
    //
    // One face at nine weights is the single biggest reason the app read as a
    // dashboard rather than as a sports product, while the shipped HUD had
    // already committed to a display voice (`clock` 34 heavy mono, `score` 30
    // black mono). Two voices, no third:
    //
    //   display  SF Pro CONDENSED, always tabular — scoreboard numerals, team
    //            codes, screen idents, section heads, band labels, table cells.
    //            UPPERCASE at the call site, tracking ≈ +0.06 em, NEVER below 11.
    //   text     SF Pro Text — prose, player names, chip captions, button
    //            titles. Sentence case, NEVER above 18.
    //
    // **The floor is enforced on the leaf, not on the container.** Iteration 2 of
    // the vision wrote the 11 pt rule as a container rule and 57 of 62 second-line
    // values fell straight through it, which is why `max`/`min` live inside these
    // two functions rather than in a comment above them.

    /// Display voice — condensed, tabular, clamped to the 11 pt floor.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        Font.system(size: max(size, 11), weight: weight).width(.condensed).monospacedDigit()
    }

    /// Text voice — SF Pro Text, clamped to the 18 pt ceiling. `prose` opts out
    /// of tabular figures; everything else lines up.
    static func text(_ size: CGFloat, _ weight: Font.Weight = .regular, prose: Bool = false) -> Font {
        let font = Font.system(size: min(size, 18), weight: weight)
        return prose ? font : font.monospacedDigit()
    }

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

        /// No lift. A step rather than a conditional modifier, so a call site
        /// can pick an elevation in an expression without branching the view
        /// tree (and losing its identity across the branch).
        static let none = Shadow(color: .clear, radius: 0, y: 0)
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
