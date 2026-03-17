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
