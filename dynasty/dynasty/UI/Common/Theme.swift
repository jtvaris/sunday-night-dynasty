import SwiftUI

// MARK: - Sunday Night Dynasty Color System

extension Color {

    // MARK: Backgrounds
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
    /// Disabled, very subtle `#64748B`
    static let textTertiary = Color(red: 0.392, green: 0.455, blue: 0.545)

    // MARK: Semantic
    /// Good attributes, positive events `#22C55E`
    static let success = Color(red: 0.133, green: 0.773, blue: 0.369)
    /// Caution, moderate `#EAB308`
    static let warning = Color(red: 0.918, green: 0.702, blue: 0.031)
    /// Injuries, bad events, destructive `#EF4444`
    static let danger = Color(red: 0.937, green: 0.267, blue: 0.267)

    // MARK: Surface
    /// Subtle card borders `#1E293B`
    static let surfaceBorder = Color(red: 0.118, green: 0.161, blue: 0.231)
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

// MARK: - Overall Rating Color

extension Color {
    static func forRating(_ value: Int) -> Color {
        switch value {
        case 85...:   return .success
        case 70..<85: return .accentGold
        case 55..<70: return .warning
        default:      return .danger
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

// MARK: - Corner Radius Tokens
//
// Two scales: 8 for inline pills/buttons/chips, 12 for cards. Anything
// else should be a deliberate exception.

enum DSCornerRadius {
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
