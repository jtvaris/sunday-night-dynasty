import SwiftUI

// MARK: - Sunday Night Dynasty Color System

extension Color {

    // MARK: Backgrounds
    /// The value floor `#060B16` — top chrome, the slat band, full-bleed moments.
    ///
    /// UI_REDESIGN_VISION §2.11. The palette had three background steps and every
    /// one of them was in use as a *card*, so nothing on a screen was ever darker
    /// than the page and the working area read as uniformly grey-blue rather than
    /// lit from within. This is the step below the page: the plate the chrome and
    /// the `DSSlatBand` sit on, and the ink colour a gold fill prints against.
    static let backgroundPlate = Color(red: 0.02353, green: 0.04314, blue: 0.08627)
    /// Deep midnight navy — the night sky over the stadium `#0B1222`
    static let backgroundPrimary = Color(red: 0.043, green: 0.071, blue: 0.133)
    /// Darker card surface `#141E30`
    static let backgroundSecondary = Color(red: 0.078, green: 0.118, blue: 0.188)
    /// Interactive elements hover/pressed `#1C2940`
    static let backgroundTertiary = Color(red: 0.110, green: 0.161, blue: 0.251)

    // MARK: Accents
    /// Stadium lights, primary CTAs, headings accent `#C9A94E`
    static let accentGold = Color(red: 0.788, green: 0.663, blue: 0.306)
    /// Secondary actions, links, info states `#3B82F6`
    static let accentBlue = Color(red: 0.231, green: 0.510, blue: 0.965)

    // MARK: Text
    /// Near-white, easy on eyes `#F1F5F9`
    static let textPrimary = Color(red: 0.945, green: 0.961, blue: 0.976)
    /// Muted labels, captions `#94A3B8`
    static let textSecondary = Color(red: 0.580, green: 0.639, blue: 0.722)
    /// Third-level text — axis ticks, units, meta captions `#8A96A8`
    ///
    /// Was `#64748B`, which measured 3.93 : 1 on `backgroundPrimary`,
    /// 3.51 : 1 on `backgroundSecondary` and 3.06 : 1 on `backgroundTertiary`
    /// — all under the WCAG AA 4.5 : 1 floor. The token is not decorative:
    /// ~1200 call sites hang real information off it (morale axis ranges,
    /// tiebreaker sub-records, "TAP FOR TIEBREAKERS"). Lightened to clear AA
    /// on every surface the app actually paints it on:
    /// primary 6.24 : 1, secondary 5.57 : 1, tertiary 4.87 : 1.
    static let textTertiary = Color(red: 0.541, green: 0.588, blue: 0.659)

    // MARK: Semantic
    /// Good attributes, positive events `#22C55E`
    static let success = Color(red: 0.133, green: 0.773, blue: 0.369)
    /// Caution, moderate `#EAB308`
    static let warning = Color(red: 0.918, green: 0.702, blue: 0.031)
    /// Poor-but-not-failing — the rung between caution and destructive `#F97316`
    ///
    /// Added for the grade ladder: the letter scale has SIX tiers (A+/A/B/C/D/F)
    /// and the palette had five, so `D` and `F` were painted the same red and a
    /// back-end roster player read as undraftable. 6.69 : 1 on
    /// `backgroundPrimary`, clear of the WCAG AA floor.
    static let alertOrange = Color(red: 0.976, green: 0.451, blue: 0.086)
    /// Injuries, bad events, destructive `#EF4444`
    static let danger = Color(red: 0.937, green: 0.267, blue: 0.267)

    // MARK: Surface
    /// Subtle card borders `#1E293B`
    static let surfaceBorder = Color(red: 0.118, green: 0.161, blue: 0.231)

    /// A genuinely disabled control fill `#131C2C` — never dimmed gold.
    ///
    /// UI_REDESIGN_VISION §2.12, and five separate audit findings asking for the
    /// same thing. A disabled gold button at 40 % opacity still reads as the
    /// screen's call to action from two feet away; this does not. Its label is
    /// `textTertiaryReadable #7C8BA1`, which clears AA on it — a disabled label
    /// is still information.
    static let controlDisabled = Color(red: 0.07451, green: 0.10980, blue: 0.17255)
}

// MARK: - Card Background Modifier

struct CardBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.backgroundSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                    )
            )
    }
}

extension View {
    func cardBackground() -> some View {
        modifier(CardBackgroundModifier())
    }
}

// MARK: - Overall Rating Color (5-tier scale)
//
// Unified rating palette used across the entire app. Stay consistent with
// `Color.ratingTier(_:)` and the named accessors below so badge colors,
// position grades, and assessment chips all read the same.
//
//   90+   Elite    bright green  → eliteGreen
//   80–89 Good     green         → success
//   70–79 Solid    blue          → accentBlue
//   60–69 Average  yellow        → warning
//   <60   Poor     red           → danger

extension Color {
    /// Brighter, more saturated green reserved for the elite (90+) tier.
    /// `#5BE08A`
    static let eliteGreen = Color(red: 0.357, green: 0.878, blue: 0.541)

    /// Five-tier color for a rating value.
    ///
    /// `scale` says which numeric scale the value lives on so a percentage and
    /// an OVR can never disagree about the same number — see ``RatingScale``.
    static func forRating(_ value: Int, scale: RatingScale = .absolute) -> Color {
        forRatingTier(RatingTier(value: value, scale: scale))
    }

    /// Five-tier color for a position-group / roster-evaluation tier.
    /// Aligned with the OVR scale so chips and badges share semantics.
    static func forRatingTier(_ tier: RatingTier) -> Color {
        switch tier {
        case .elite:   return .eliteGreen
        case .good:    return .success
        case .solid:   return .accentBlue
        case .average: return .warning
        case .poor:    return .danger
        }
    }
}

/// Which numeric scale a value handed to ``Color/forRating(_:scale:)`` lives on.
///
/// Both cases deliberately share the same band edges. The bug this exists to
/// stop was scheme familiarity 62 % painting green on one screen while a 62 OVR
/// painted yellow on the next — two bespoke colour ladders for the same digits.
/// Declaring the scale at the call site keeps the intent readable, and leaves
/// exactly one place to retune percentages should they ever need to diverge.
enum RatingScale {
    /// 0–99 player / team / attribute rating. The app default.
    case absolute
    /// 0–100 percentage — scheme familiarity, snap share, completion.
    case percent
}

/// Five-tier rating bucket. Keep aligned with `Color.forRating(_:scale:)`.
enum RatingTier {
    case elite, good, solid, average, poor

    init(ovr: Int) {
        switch ovr {
        case 90...:   self = .elite
        case 80..<90: self = .good
        case 70..<80: self = .solid
        case 60..<70: self = .average
        default:      self = .poor
        }
    }

    /// Bucket for a value on an explicit scale. Percentages map onto the OVR
    /// ladder unchanged — that shared mapping is the whole point.
    init(value: Int, scale: RatingScale) {
        switch scale {
        case .absolute: self.init(ovr: value)
        case .percent:  self.init(ovr: min(value, 99))
        }
    }
}

// MARK: - Spacing Scale
//
// Standardized spacing tokens. Prefer these over magic numbers so vertical
// rhythm stays consistent across views.

enum DSSpacing {
    /// 4 — micro spacing inside chips / tight clusters
    static let xxs: CGFloat = 4
    /// 8 — between tightly related elements (label + value)
    static let xs: CGFloat = 8
    /// 12 — default inner spacing inside cards
    static let sm: CGFloat = 12
    /// 16 — between cards in a stack, between paragraphs
    static let md: CGFloat = 16
    /// 24 — between major sections
    static let lg: CGFloat = 24
    /// 32 — top of screen / hero spacing
    static let xl: CGFloat = 32
}

// MARK: - Content Measure Tokens
//
// How wide the content column is allowed to grow on an iPad. Screens used to
// pick their own number — 720, 760, 800, 820, 860, 900, 1080, 1200 all shipped
// — which is why a picker and the cards under it kept landing on different
// centre lines. Three steps instead: pick the one that matches what the screen
// shows, not a number.

enum DSLayout {
    /// 720 — the default reading column: one stack of cards, a form, a list,
    /// a message. Anything wider makes body text uncomfortable to scan.
    static let contentMeasure: CGFloat = 720
    /// 900 — dense content that needs the room: multi-column tables, standings,
    /// two-up card rows, the press-conference transcript.
    static let wideMeasure: CGFloat = 900
    /// 1200 — full-bleed grids that want the whole iPad (team selection, the
    /// game plan board). Effectively "no column", capped so a Mac window or a
    /// future larger display does not stretch it forever.
    static let gridMeasure: CGFloat = 1200
}

// MARK: - Corner Radius Tokens
//
// Three steps: `tight` for elements small enough that 8 would round them into a
// blob, `inline` for pills/buttons/chips, and `card` for containers. Anything
// else is a deliberate exception — `tools/lint/design_tokens.py` counts the
// off-scale literals.
//
// There is deliberately no `pill` step. A "fully rounded" token was declared in
// the first pass of task #70 and never landed on a single call site, because the
// literals it was meant to absorb (16 / 18 / 20 on chips of varying height) are
// NOT all fake pills — converting them is a visual change per site, not a
// codemod. Use `Capsule()`, which says the same thing without a magic number.

enum DSCornerRadius {
    /// 4 — micro elements: meter caps, swatches, 14–26 pt badge boxes. At this
    /// size `inline` (8) eats the whole corner and the rectangle reads round.
    static let tight: CGFloat = 4
    /// 8 — buttons, pills, chips, small inline rectangles
    static let inline: CGFloat = 8
    /// 12 — cards, sheets, containers
    static let card: CGFloat = 12
}

// MARK: - Draft Day Tokens

extension Color {
    /// Urgent clock — last 30 s of the on-the-clock countdown
    static let draftClockUrgent = Color(red: 0.949, green: 0.227, blue: 0.227)
    /// Steal banner accent / gem badge gold (slightly warmer than accentGold)
    static let draftStealGold = Color(red: 1.0, green: 0.792, blue: 0.298)
    /// Reach indicator background
    static let draftReachRed = Color(red: 0.706, green: 0.157, blue: 0.157)
    /// Solid pick / neutral chip background
    static let draftSolidNeutral = Color(red: 0.227, green: 0.282, blue: 0.380)
}

enum DraftAnimation {
    static let bannerIn: Double = 0.35
    static let bannerOut: Double = 0.25
    static let pickReveal: Double = 0.6
    static let toastIn: Double = 0.30
    static let toastDwell: Double = 2.0
    static let clockTickInterval: Double = 1.0
}

// MARK: - UIKit Appearance
//
// SwiftUI's `.pickerStyle(.segmented)` is a wrapped `UISegmentedControl`, and
// the only way to recolor it is the UIKit appearance proxy. That proxy applies
// at *view-creation* time, so calling it from a view's `.onAppear` — as several
// screens used to — lands one frame too late and the control renders in the
// stock iOS grey before snapping to the app palette (or never, if the view
// never re-creates it). Applying it once at launch fixes every segmented
// control in the app, including screens that never knew to ask.

enum DSAppearance {

    /// Applies app-wide UIKit appearance overrides. Call once, at app launch,
    /// before any UI is built.
    static func apply() {
        let control = UISegmentedControl.appearance()
        control.selectedSegmentTintColor = UIColor(Color.accentBlue)
        control.backgroundColor = UIColor(Color.backgroundSecondary)
        control.setTitleTextAttributes(
            [.foregroundColor: UIColor(Color.backgroundPrimary),
             .font: UIFont.systemFont(ofSize: 14, weight: .semibold)],
            for: .selected
        )
        control.setTitleTextAttributes(
            [.foregroundColor: UIColor(Color.textSecondary),
             .font: UIFont.systemFont(ofSize: 14, weight: .medium)],
            for: .normal
        )
    }
}

// MARK: - Section Header

/// Uniform section header — uppercase, semibold, accent gold, tracked.
/// Use across views to keep section titles consistent.
struct SectionHeaderText: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(1.2)
            .foregroundStyle(Color.accentGold)
    }
}
