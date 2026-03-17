import SwiftUI

// MARK: - Main View

struct GamePlanView: View {

    @Binding var gamePlan: GamePlan

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    previewCard
                    presetButtons
                    offensiveSection
                    defensiveSection
                }
                .padding(20)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Game Plan")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    // MARK: - Preview Card

    private var previewCard: some View {
        VStack(spacing: 14) {
            Text("Current Strategy")
                .font(.headline)
                .foregroundStyle(Color.textPrimary)

            Divider().overlay(Color.surfaceBorder)

            HStack(spacing: 0) {
                summaryColumn(label: "Style", value: gamePlan.styleSummary)
                summaryColumn(label: "Offense", value: runPassDisplayLabel)
                summaryColumn(label: "Defense", value: defenseDisplayLabel)
            }

            // Mini radar-style bar chart of all five settings
            VStack(spacing: 8) {
                ForEach(previewBars, id: \.label) { bar in
                    miniBar(label: bar.label, value: bar.value, color: bar.color)
                }
            }
            .padding(.top, 4)
        }
        .padding(20)
        .cardBackground()
    }

    private var runPassDisplayLabel: String { gamePlan.runPassLabel }

    private var defenseDisplayLabel: String {
        let avg = (gamePlan.defensiveAggression + gamePlan.blitzFrequency) / 2.0
        switch avg {
        case 0.0..<0.3:  return "Soft Zone"
        case 0.3..<0.55: return "Balanced"
        case 0.55..<0.75: return "Aggressive"
        default:         return "Blitz Heavy"
        }
    }

    private struct PreviewBar {
        let label: String
        let value: Double
        let color: Color
    }

    private var previewBars: [PreviewBar] {
        [
            PreviewBar(label: "Off. Aggression",     value: gamePlan.offensiveAggression, color: .accentBlue),
            PreviewBar(label: "Def. Aggression",     value: gamePlan.defensiveAggression, color: .danger),
            PreviewBar(label: "Run ← Pass",          value: gamePlan.runPassRatio,        color: .accentGold),
            PreviewBar(label: "Blitz Frequency",     value: gamePlan.blitzFrequency,      color: .warning),
            PreviewBar(label: "4th Down Aggression", value: gamePlan.fourthDownAggressiveness, color: .success),
        ]
    }

    private func miniBar(label: String, value: Double, color: Color) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .frame(width: 130, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.backgroundTertiary)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: max(4, geo.size.width * value))
                        .animation(.easeInOut(duration: 0.25), value: value)
                }
            }
            .frame(height: 6)

            Text(percentLabel(value))
                .font(.caption.monospacedDigit())
                .foregroundStyle(Color.textTertiary)
                .frame(width: 32, alignment: .trailing)
        }
    }

    // MARK: - Preset Buttons

    private var presetButtons: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Presets")
                .font(.headline)
                .foregroundStyle(Color.textPrimary)

            Divider().overlay(Color.surfaceBorder)

            HStack(spacing: 12) {
                presetButton(label: "Conservative", icon: "shield.fill",    preset: .conservative, color: .accentBlue)
                presetButton(label: "Balanced",     icon: "equal.circle",   preset: .balanced,     color: .accentGold)
                presetButton(label: "Aggressive",   icon: "bolt.fill",      preset: .aggressive,   color: .danger)
            }
        }
        .padding(20)
        .cardBackground()
    }

    private func presetButton(
        label: String,
        icon: String,
        preset: GamePlan,
        color: Color
    ) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                gamePlan = preset
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(color)
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(color.opacity(0.4), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Apply \(label) preset")
    }

    // MARK: - Offensive Section

    private var offensiveSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: "Offense", icon: "football.fill", color: .accentBlue)

            Divider().overlay(Color.surfaceBorder)

            sliderRow(
                label: "Offensive Style",
                leftLabel: "Conservative",
                rightLabel: "Aggressive",
                value: $gamePlan.offensiveAggression,
                color: .accentBlue
            )

            sliderRow(
                label: "Play Calling Mix",
                leftLabel: "Run Heavy",
                rightLabel: "Pass Heavy",
                value: $gamePlan.runPassRatio,
                color: .accentGold
            )

            sliderRow(
                label: "4th Down Decisions",
                leftLabel: "Punt / FG",
                rightLabel: "Go For It",
                value: $gamePlan.fourthDownAggressiveness,
                color: .success
            )
        }
        .padding(20)
        .cardBackground()
    }

    // MARK: - Defensive Section

    private var defensiveSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: "Defense", icon: "shield.lefthalf.filled", color: .danger)

            Divider().overlay(Color.surfaceBorder)

            sliderRow(
                label: "Defensive Style",
                leftLabel: "Soft Zone",
                rightLabel: "Press Man",
                value: $gamePlan.defensiveAggression,
                color: .danger
            )

            sliderRow(
                label: "Blitz Frequency",
                leftLabel: "Coverage",
                rightLabel: "Full Blitz",
                value: $gamePlan.blitzFrequency,
                color: .warning
            )
        }
        .padding(20)
        .cardBackground()
    }

    // MARK: - Slider Row

    private func sliderRow(
        label: String,
        leftLabel: String,
        rightLabel: String,
        value: Binding<Double>,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text(percentLabel(value.wrappedValue))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(color)
            }

            Slider(value: value, in: 0.0...1.0, step: 0.05)
                .tint(color)
                .accessibilityLabel("\(label), \(percentLabel(value.wrappedValue))")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: value.wrappedValue = min(1.0, value.wrappedValue + 0.05)
                    case .decrement: value.wrappedValue = max(0.0, value.wrappedValue - 0.05)
                    @unknown default: break
                    }
                }

            HStack {
                Text(leftLabel)
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                Spacer()
                Text(rightLabel)
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            }
        }
    }

    // MARK: - Section Header

    private func sectionHeader(title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
        }
    }

    // MARK: - Summary Column

    private func summaryColumn(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.accentGold)
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: - Helpers

    private func percentLabel(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var gamePlan: GamePlan = .balanced

    NavigationStack {
        GamePlanView(gamePlan: $gamePlan)
    }
}
