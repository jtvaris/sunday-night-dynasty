import SwiftUI

// MARK: - StatComparisonRow

/// A reusable side-by-side stat bar that shows two teams' values proportionally.
/// The team with the better raw value receives the gold bar; the other gets textTertiary.
struct StatComparisonRow: View {

    let label: String
    let awayValue: String
    let homeValue: String
    /// Raw numeric value for the away team (used to compute proportions and winner).
    let awayRaw: Double
    /// Raw numeric value for the home team (used to compute proportions and winner).
    let homeRaw: Double
    /// When true, a lower raw value is considered better (e.g. turnovers).
    var lowerIsBetter: Bool = false

    // MARK: - Derived

    private var total: Double { awayRaw + homeRaw }

    /// Fraction of the bar belonging to the away team (0–1).
    private var awayFraction: CGFloat {
        guard total > 0 else { return 0.5 }
        return CGFloat(awayRaw / total)
    }

    private var awayIsBetter: Bool {
        if awayRaw == homeRaw { return false }
        return lowerIsBetter ? awayRaw < homeRaw : awayRaw > homeRaw
    }

    private var awayBarColor: Color  { awayIsBetter  ? .accentGold : .textTertiary }
    private var homeBarColor: Color  { !awayIsBetter ? .accentGold : .textTertiary }
    private var awayTextColor: Color { awayIsBetter  ? .accentGold : .textPrimary  }
    private var homeTextColor: Color { !awayIsBetter ? .accentGold : .textPrimary  }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 6) {
            // Centered label
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
                .frame(maxWidth: .infinity, alignment: .center)

            // Values + proportional bar
            HStack(spacing: 8) {
                // Away value (right-aligned)
                Text(awayValue)
                    .font(.system(size: 14, weight: .bold).monospacedDigit())
                    .foregroundStyle(awayTextColor)
                    .frame(width: 48, alignment: .trailing)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                // Proportional bar
                GeometryReader { geo in
                    let totalWidth = geo.size.width
                    let awayWidth  = totalWidth * awayFraction
                    let homeWidth  = totalWidth - awayWidth

                    HStack(spacing: 2) {
                        // Away segment (grows from center left)
                        HStack(spacing: 0) {
                            Spacer(minLength: 0)
                            Capsule()
                                .fill(awayBarColor)
                                .frame(width: max(awayWidth - 1, 0), height: 8)
                        }
                        .frame(width: awayWidth, alignment: .trailing)

                        // Home segment (grows from center right)
                        HStack(spacing: 0) {
                            Capsule()
                                .fill(homeBarColor)
                                .frame(width: max(homeWidth - 1, 0), height: 8)
                            Spacer(minLength: 0)
                        }
                        .frame(width: homeWidth, alignment: .leading)
                    }
                }
                .frame(height: 8)

                // Home value (left-aligned)
                Text(homeValue)
                    .font(.system(size: 14, weight: .bold).monospacedDigit())
                    .foregroundStyle(homeTextColor)
                    .frame(width: 48, alignment: .leading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): away \(awayValue), home \(homeValue)")
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        StatComparisonRow(
            label: "Total Yards",
            awayValue: "347",
            homeValue: "412",
            awayRaw: 347,
            homeRaw: 412
        )
        StatComparisonRow(
            label: "Turnovers",
            awayValue: "2",
            homeValue: "0",
            awayRaw: 2,
            homeRaw: 0,
            lowerIsBetter: true
        )
        StatComparisonRow(
            label: "Time of Possession",
            awayValue: "27:14",
            homeValue: "32:46",
            awayRaw: 1634,
            homeRaw: 1966
        )
    }
    .padding(24)
    .background(Color.backgroundPrimary)
}
