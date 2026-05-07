import SwiftUI

/// Negotiation Room sheet (FA Drama A7). User drags sliders to compose an
/// offer; the agent gives live verdicts per element and an overall score.
/// Owner can submit when score is acceptable, or apply the agent's
/// counter-suggestion to converge faster.
struct BiddingRoomSheet: View {
    let playerName: String
    let position: String
    let marketValue: Int          // thousands per year
    let playerLoyalty: Double     // 0...1
    let agentAggression: Double   // 0...1
    let onSubmit: (BiddingRoomEngine.OfferDraft) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var years: Double = 3.0          // 1...7
    @State private var baseSalary: Double = 0       // thousands per year
    @State private var signingBonus: Double = 0     // thousands lump sum
    @State private var guaranteed: Double = 0       // thousands total
    @State private var incentives: Double = 0       // thousands per year
    @State private var feedback: BiddingRoomEngine.AgentFeedback?

    // Slider ceilings (thousands)
    private let baseMax: Double = 50_000
    private let bonusMax: Double = 25_000
    private let guaranteeMax: Double = 50_000
    private let incentivesMax: Double = 5_000

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.md) {
                    headerSection
                    Divider().overlay(Color.surfaceBorder)
                    yearsSlider
                    baseSalarySlider
                    signingBonusSlider
                    guaranteedSlider
                    incentivesSlider
                    if let fb = feedback {
                        agentFeedbackCard(fb)
                    }
                    submitButton
                }
                .padding(DSSpacing.lg)
            }
            .background(Color.backgroundPrimary)
            .navigationTitle("Negotiate Offer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .onChange(of: years) { _, _ in updateFeedback() }
            .onChange(of: baseSalary) { _, _ in updateFeedback() }
            .onChange(of: signingBonus) { _, _ in updateFeedback() }
            .onChange(of: guaranteed) { _, _ in updateFeedback() }
            .onChange(of: incentives) { _, _ in updateFeedback() }
            .onAppear {
                if baseSalary == 0 {
                    baseSalary = min(Double(marketValue), baseMax)
                    signingBonus = min(Double(marketValue) / 2.0, bonusMax)
                    guaranteed = min(Double(marketValue) * 1.5, guaranteeMax)
                }
                updateFeedback()
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(playerName)
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.textPrimary)
            HStack(spacing: DSSpacing.sm) {
                Text(position)
                    .font(.caption.weight(.heavy))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.draftSolidNeutral)
                    .foregroundStyle(Color.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Text("Market: \(formatMoney(marketValue))/yr")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }

    // MARK: - Sliders

    private var yearsSlider: some View {
        sliderRow(
            label: "Years",
            valueText: "\(Int(years)) yr",
            verdict: feedback?.yearsVerdict
        ) {
            Slider(value: $years, in: 1...7, step: 1)
                .tint(Color.accentGold)
        }
    }

    private var baseSalarySlider: some View {
        sliderRow(
            label: "Base Salary / yr",
            valueText: formatMoney(Int(baseSalary)),
            verdict: feedback?.baseVerdict
        ) {
            Slider(value: $baseSalary, in: 500...baseMax, step: 250)
                .tint(Color.accentGold)
        }
    }

    private var signingBonusSlider: some View {
        sliderRow(
            label: "Signing Bonus",
            valueText: formatMoney(Int(signingBonus)),
            verdict: feedback?.bonusVerdict
        ) {
            Slider(value: $signingBonus, in: 0...bonusMax, step: 250)
                .tint(Color.accentGold)
        }
    }

    private var guaranteedSlider: some View {
        sliderRow(
            label: "Guaranteed",
            valueText: formatMoney(Int(guaranteed)),
            verdict: feedback?.guaranteeVerdict
        ) {
            Slider(value: $guaranteed, in: 0...guaranteeMax, step: 250)
                .tint(Color.accentGold)
        }
    }

    private var incentivesSlider: some View {
        sliderRow(
            label: "Incentives / yr",
            valueText: formatMoney(Int(incentives)),
            verdict: nil
        ) {
            Slider(value: $incentives, in: 0...incentivesMax, step: 100)
                .tint(Color.accentGold)
        }
    }

    private func sliderRow<S: View>(
        label: String,
        valueText: String,
        verdict: BiddingRoomEngine.Verdict?,
        @ViewBuilder slider: () -> S
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: DSSpacing.xs) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                if let v = verdict {
                    verdictBadge(v)
                }
                Text(valueText)
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(Color.textPrimary)
            }
            slider()
        }
        .padding(DSSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                .fill(Color.backgroundSecondary)
        )
    }

    private func verdictBadge(_ verdict: BiddingRoomEngine.Verdict) -> some View {
        let (symbol, color): (String, Color) = {
            switch verdict {
            case .great:  return ("checkmark", .success)
            case .fair:   return ("equal",     .warning)
            case .tooLow: return ("xmark",     .danger)
            }
        }()
        return Image(systemName: symbol)
            .font(.caption2.weight(.heavy))
            .foregroundStyle(color)
            .padding(4)
            .background(Circle().fill(color.opacity(0.15)))
    }

    // MARK: - Agent feedback

    private func agentFeedbackCard(_ fb: BiddingRoomEngine.AgentFeedback) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            SectionHeaderText(title: "Agent Says")
            Text("\u{201C}\(fb.agentQuote)\u{201D}")
                .font(.subheadline.italic())
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            // Score bar
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Acceptance")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Text("\(Int(fb.overallScore * 100))%")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.textPrimary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.backgroundTertiary)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(scoreColor(fb.overallScore))
                            .frame(width: max(4, geo.size.width * CGFloat(fb.overallScore)))
                    }
                }
                .frame(height: 6)
            }

            if let counter = fb.counterSuggestion {
                Divider().overlay(Color.surfaceBorder)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Agent Suggests")
                        .font(.caption2.weight(.heavy))
                        .tracking(0.8)
                        .foregroundStyle(Color.draftStealGold)
                    Text("\(counter.years)yr / \(formatMoney(counter.baseSalary)) base / \(formatMoney(counter.signingBonus)) bonus / \(formatMoney(counter.guaranteed)) gtd")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                    Button {
                        applySuggestion(counter)
                    } label: {
                        Text("Apply Suggestion")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.backgroundPrimary)
                            .padding(.horizontal, DSSpacing.sm)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                                    .fill(Color.draftStealGold)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(DSSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.card)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: DSCornerRadius.card)
                        .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                )
        )
    }

    private func scoreColor(_ score: Double) -> Color {
        switch score {
        case 0.85...:    return .success
        case 0.55..<0.85: return .warning
        default:         return .danger
        }
    }

    // MARK: - Submit

    private var submitButton: some View {
        let canSubmit = (feedback?.overallScore ?? 0) >= 0.4
        return Button {
            onSubmit(currentDraft())
            dismiss()
        } label: {
            HStack {
                Image(systemName: "paperplane.fill")
                Text("Submit Offer")
                    .font(.subheadline.weight(.bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DSSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                    .fill(canSubmit ? Color.accentGold : Color.draftSolidNeutral)
            )
            .foregroundStyle(canSubmit ? Color.backgroundPrimary : Color.textTertiary)
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
    }

    // MARK: - Helpers

    private func currentDraft() -> BiddingRoomEngine.OfferDraft {
        BiddingRoomEngine.OfferDraft(
            years: Int(years),
            baseSalary: Int(baseSalary),
            signingBonus: Int(signingBonus),
            guaranteed: Int(guaranteed),
            incentives: Int(incentives)
        )
    }

    private func updateFeedback() {
        feedback = BiddingRoomEngine.evaluateOffer(
            draft: currentDraft(),
            marketValue: marketValue,
            playerLoyalty: playerLoyalty,
            agentAggression: agentAggression
        )
    }

    private func applySuggestion(_ draft: BiddingRoomEngine.OfferDraft) {
        years = Double(draft.years)
        baseSalary = min(Double(draft.baseSalary), baseMax)
        signingBonus = min(Double(draft.signingBonus), bonusMax)
        guaranteed = min(Double(draft.guaranteed), guaranteeMax)
        incentives = min(Double(draft.incentives), incentivesMax)
        updateFeedback()
    }

    private func formatMoney(_ thousands: Int) -> String {
        let millions = Double(thousands) / 1000.0
        if millions >= 1.0 {
            return String(format: "$%.1fM", millions)
        }
        return "$\(thousands)K"
    }
}
