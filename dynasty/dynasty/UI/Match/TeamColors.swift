import UIKit

// MARK: - Team Colors

/// Primary uniform colors for the 32 franchises, keyed by team abbreviation.
/// Used to tint 3D player markers and end zones in the match view. Teams the
/// palette doesn't know fall back to a readable navy/silver pair.
/// (UIKit counterpart of the SwiftUI `TeamColors` used by team selection.)
enum MatchTeamColors {

    static func primary(for abbreviation: String) -> UIColor {
        palette[abbreviation]?.0 ?? UIColor(red: 0.15, green: 0.22, blue: 0.40, alpha: 1)
    }

    /// Secondary color — used when both teams' primaries are too similar.
    static func secondary(for abbreviation: String) -> UIColor {
        palette[abbreviation]?.1 ?? UIColor(white: 0.82, alpha: 1)
    }

    /// Returns a pair of visually distinct uniform colors for a matchup.
    /// Each side falls back to its secondary when the primary would vanish
    /// into the field grass (e.g. Packers dark green), and the away side
    /// swaps when the two picks are too similar to tell apart.
    static func matchup(home: String, away: String) -> (home: UIColor, away: UIColor) {
        var h = fieldSafePrimary(for: home)
        var a = fieldSafePrimary(for: away)
        if areSimilar(h, a) {
            a = secondary(for: away)
            if areSimilar(h, a) { h = secondary(for: home) }
        }
        return (h, a)
    }

    /// Grass tones the player markers must never blend into.
    private static let grass = UIColor(red: 0.15, green: 0.45, blue: 0.15, alpha: 1)

    private static func fieldSafePrimary(for abbreviation: String) -> UIColor {
        let p = primary(for: abbreviation)
        return (areSimilar(p, grass) || isVeryDark(p)) ? secondary(for: abbreviation) : p
    }

    private static func isVeryDark(_ color: UIColor) -> Bool {
        var (r, g, b, a): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (0.299 * r + 0.587 * g + 0.114 * b) < 0.16
    }

    // MARK: - Palette

    private static let palette: [String: (UIColor, UIColor)] = [
        "ARI": (rgb(151, 35, 63), rgb(255, 182, 18)),
        "ATL": (rgb(167, 25, 48), rgb(0, 0, 0)),
        "BAL": (rgb(26, 25, 95), rgb(158, 124, 12)),
        "BUF": (rgb(0, 51, 141), rgb(198, 12, 48)),
        "CAR": (rgb(0, 133, 202), rgb(16, 24, 32)),
        "CHI": (rgb(11, 22, 42), rgb(200, 56, 3)),
        "CIN": (rgb(251, 79, 20), rgb(0, 0, 0)),
        "CLE": (rgb(49, 29, 0), rgb(255, 60, 0)),
        "DAL": (rgb(0, 53, 148), rgb(134, 147, 151)),
        "DEN": (rgb(251, 79, 20), rgb(0, 34, 68)),
        "DET": (rgb(0, 118, 182), rgb(176, 183, 188)),
        "GB":  (rgb(24, 48, 40), rgb(255, 184, 28)),
        "HOU": (rgb(3, 32, 47), rgb(167, 25, 48)),
        "IND": (rgb(0, 44, 95), rgb(162, 170, 173)),
        "JAX": (rgb(0, 103, 120), rgb(215, 162, 42)),
        "KC":  (rgb(227, 24, 55), rgb(255, 184, 28)),
        "LAC": (rgb(0, 128, 198), rgb(255, 194, 14)),
        "LAR": (rgb(0, 53, 148), rgb(255, 163, 0)),
        "LV":  (rgb(20, 20, 20), rgb(165, 172, 175)),
        "MIA": (rgb(0, 142, 151), rgb(252, 76, 2)),
        "MIN": (rgb(79, 38, 131), rgb(255, 198, 47)),
        "NE":  (rgb(0, 34, 68), rgb(198, 12, 48)),
        "NO":  (rgb(211, 188, 141), rgb(16, 24, 31)),
        "NYG": (rgb(1, 35, 82), rgb(163, 13, 45)),
        "NYJ": (rgb(18, 87, 64), rgb(255, 255, 255)),
        "PHI": (rgb(0, 76, 84), rgb(165, 172, 175)),
        "PIT": (rgb(16, 24, 32), rgb(255, 182, 18)),
        "SEA": (rgb(0, 34, 68), rgb(105, 190, 40)),
        "SF":  (rgb(170, 0, 0), rgb(173, 153, 93)),
        "TB":  (rgb(213, 10, 10), rgb(52, 48, 43)),
        "TEN": (rgb(12, 35, 64), rgb(75, 146, 219)),
        "WAS": (rgb(90, 20, 20), rgb(255, 182, 18)),
    ]

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> UIColor {
        UIColor(red: r / 255, green: g / 255, blue: b / 255, alpha: 1)
    }

    /// Rough perceptual similarity check so e.g. NE @ DAL doesn't render
    /// two near-identical navy squads.
    private static func areSimilar(_ a: UIColor, _ b: UIColor) -> Bool {
        var (r1, g1, b1, r2, g2, b2): (CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0, 0, 0)
        var alpha: CGFloat = 0
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &alpha)
        b.getRed(&r2, green: &g2, blue: &b2, alpha: &alpha)
        let distance = abs(r1 - r2) + abs(g1 - g2) + abs(b1 - b2)
        return distance < 0.55
    }
}
