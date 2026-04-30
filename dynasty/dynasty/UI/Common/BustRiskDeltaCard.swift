// BustRiskDeltaCard.swift
//
// Reusable "before -> after" delta card pattern for decision-support displays.
//
// Originated from InterviewSelectionView's bust-risk row (e.g. "50% -> 40%
// after interview"), which is the strongest decision-support pattern in the
// scouting flow. This component generalises that pattern so it can be reused
// across the app for any before/after comparison where lower-is-better OR
// higher-is-better.
//
// Recommended usage sites (replicate the pattern):
//   - ProspectDetailView interview/scouting section: bust risk before/after
//     interview (already wired in `bustRiskDeltaCard` helper there).
//   - CombineResultsView "Standout / Stock Faller" cards: rating delta
//     (rating_before -> rating_after).
//   - Any other decision-support card where a before/after delta is the
//     core piece of information the user needs.

import SwiftUI

/// A compact card showing a "before -> after" percentage or rating delta with
/// a colour-coded direction indicator. Designed to sit inline inside a list
/// row, or as a standalone chip in a stack.
struct BustRiskDeltaCard: View {

    /// Whether a higher value is "better" (e.g. rating) or "worse" (e.g. risk).
    enum DeltaDirection {
        /// Lower values are better (e.g. bust risk, fumble rate).
        case lowerIsBetter
        /// Higher values are better (e.g. OVR rating, projected stat).
        case higherIsBetter
    }

    let label: String
    let before: Int
    let after: Int
    /// Optional unit suffix (e.g. "%" for risk, "" for raw rating).
    var unit: String = "%"
    var direction: DeltaDirection = .lowerIsBetter
    /// Optional trailing context label (e.g. "after interview", "post-combine").
    var trailingContext: String? = nil
    /// Optional SF Symbol overriding the auto-selected one.
    var iconOverride: String? = nil
    /// When true, renders a slightly larger card variant with rounded background.
    var prominent: Bool = false

    private var improved: Bool {
        switch direction {
        case .lowerIsBetter:  return after < before
        case .higherIsBetter: return after > before
        }
    }

    private var unchanged: Bool { before == after }

    private var deltaColor: Color {
        if unchanged { return .textSecondary }
        return improved ? .success : .danger
    }

    private var icon: String {
        if let iconOverride { return iconOverride }
        if unchanged { return "equal.circle" }
        switch direction {
        case .lowerIsBetter:
            return improved ? "chart.line.downtrend.xyaxis" : "chart.line.uptrend.xyaxis"
        case .higherIsBetter:
            return improved ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: prominent ? 12 : 10))
                .foregroundStyle(deltaColor)

            Text("\(label):")
                .font(.system(size: prominent ? 12 : 11, weight: .semibold))
                .foregroundStyle(Color.textSecondary)

            Text("\(before)\(unit)")
                .font(.system(size: prominent ? 13 : 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.textSecondary)

            Image(systemName: "arrow.right")
                .font(.system(size: prominent ? 10 : 8))
                .foregroundStyle(Color.textTertiary)

            Text("\(after)\(unit)")
                .font(.system(size: prominent ? 14 : 12, weight: .bold).monospacedDigit())
                .foregroundStyle(deltaColor)

            if let trailingContext {
                Text(trailingContext)
                    .font(.system(size: prominent ? 11 : 10, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(.horizontal, prominent ? 10 : 0)
        .padding(.vertical, prominent ? 6 : 0)
        .background(
            Group {
                if prominent {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(deltaColor.opacity(0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(deltaColor.opacity(0.25))
                        )
                }
            }
        )
    }
}

#if DEBUG
#Preview("Bust Risk Delta") {
    VStack(alignment: .leading, spacing: 12) {
        BustRiskDeltaCard(label: "Bust risk", before: 50, after: 40,
                          trailingContext: "after interview")
        BustRiskDeltaCard(label: "Bust risk", before: 30, after: 45,
                          trailingContext: "after interview")
        BustRiskDeltaCard(label: "OVR", before: 72, after: 78,
                          unit: "", direction: .higherIsBetter,
                          trailingContext: "post-combine", prominent: true)
        BustRiskDeltaCard(label: "Rating", before: 75, after: 70,
                          unit: "", direction: .higherIsBetter,
                          trailingContext: "stock faller", prominent: true)
    }
    .padding()
    .background(Color.backgroundPrimary)
}
#endif
