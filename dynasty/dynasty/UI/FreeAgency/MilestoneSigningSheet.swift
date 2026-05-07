import SwiftUI

/// Modal sheet shown when an FA player is chasing a career milestone (HOF push,
/// comeback, last-chance, etc.). Surfaces the milestone-driven signing terms
/// from `MilestoneTracker` (FA Drama brief, Phase 5 UI).
struct MilestoneSigningSheet: View {
    let playerName: String
    let position: String
    let age: Int
    let milestone: FAMilestone
    let onSign: (Int, Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedYears: Int

    private let yearRange: ClosedRange<Int>
    private let salaryMultiplier: Double

    init(playerName: String, position: String, age: Int, milestone: FAMilestone,
         onSign: @escaping (Int, Double) -> Void) {
        self.playerName = playerName
        self.position = position
        self.age = age
        self.milestone = milestone
        self.onSign = onSign
        let range = MilestoneTracker.milestoneRequiredYears(milestone: milestone)
        self.yearRange = range
        self.salaryMultiplier = MilestoneTracker.milestoneSalaryMultiplier(milestone: milestone)
        self._selectedYears = State(initialValue: range.lowerBound)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: DSSpacing.lg) {
                headerCard
                milestoneCard
                requirementsCard
                yearsPicker
                Spacer()
                signButton
            }
            .padding(DSSpacing.lg)
            .background(Color.backgroundPrimary)
            .navigationTitle("Special Signing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var headerCard: some View {
        HStack(spacing: DSSpacing.sm) {
            Image(systemName: "trophy.fill")
                .font(.largeTitle)
                .foregroundStyle(Color.draftStealGold)
            VStack(alignment: .leading, spacing: 2) {
                Text(playerName)
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(Color.textPrimary)
                Text("\(position) · Age \(age)")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
        }
    }

    private var milestoneCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(milestone.displayTitle)
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.draftStealGold)
            Text(milestone.displayBody)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
        }
        .padding(DSSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DSCornerRadius.card)
            .fill(Color.draftStealGold.opacity(0.10))
            .overlay(RoundedRectangle(cornerRadius: DSCornerRadius.card)
                .strokeBorder(Color.draftStealGold, lineWidth: 1.5)))
    }

    private var requirementsCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text("REQUIREMENTS")
                .font(.caption.weight(.heavy)).tracking(1)
                .foregroundStyle(Color.accentGold)
            HStack {
                Text("Contract Length")
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Text("\(yearRange.lowerBound) - \(yearRange.upperBound) years")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
            }
            HStack {
                Text("Salary Multiplier")
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Text("\(String(format: "%.0f", salaryMultiplier * 100))%")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
            }
        }
        .padding(DSSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DSCornerRadius.card)
            .fill(Color.backgroundSecondary))
    }

    private var yearsPicker: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text("YEARS: \(selectedYears)")
                .font(.caption.weight(.heavy)).tracking(1)
                .foregroundStyle(Color.accentGold)
            HStack(spacing: 6) {
                ForEach(Array(yearRange), id: \.self) { yr in
                    Button("\(yr)") { selectedYears = yr }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(selectedYears == yr ? Color.backgroundPrimary : Color.textSecondary)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(selectedYears == yr ? Color.draftStealGold : Color.backgroundTertiary,
                                    in: RoundedRectangle(cornerRadius: DSCornerRadius.inline))
                }
            }
        }
    }

    private var signButton: some View {
        Button {
            onSign(selectedYears, salaryMultiplier)
            dismiss()
        } label: {
            Text("Sign \(playerName)")
                .font(.headline)
                .foregroundStyle(Color.backgroundPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.draftStealGold, in: RoundedRectangle(cornerRadius: DSCornerRadius.card))
        }
        .buttonStyle(.plain)
    }
}

extension FAMilestone {
    var displayTitle: String {
        switch self {
        case .oneSackFromHistoric: return "1 Sack from History"
        case .approaching1000Yards: return "1000-Yard Push"
        case .lastChance: return "Last Chance"
        case .comeback: return "Comeback Bid"
        case .proBowlPush: return "Pro Bowl / HOF Push"
        }
    }
    var displayBody: String {
        switch self {
        case .oneSackFromHistoric: return "This veteran is one sack from a historic career milestone. Wants a starter role to get there."
        case .approaching1000Yards: return "Looking for the carries to hit a career rushing milestone. Demands #1 RB role."
        case .lastChance: return "33+ year old proving they can still play. Will accept a 1-year prove-it deal."
        case .comeback: return "Returning from retirement. Wants championship contender + meaningful role."
        case .proBowlPush: return "One Pro Bowl from likely HOF lock. Needs starter role + competitive team."
        }
    }
}
