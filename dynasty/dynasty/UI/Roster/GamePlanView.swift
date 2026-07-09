import SwiftUI

// MARK: - Game Plan View
//
// iPad-first, two-column coaching strategy screen.
//   Left column  — summary chips, presets, opponent scouting panel
//   Right column — Offense / Defense slider cards
// Palette: offense = accentBlue, defense = danger, presets/summary = accentGold.

struct GamePlanView: View {

    @Binding var gamePlan: GamePlan
    var context: Context?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// "Saved ✓" flash shown in the header after any change.
    @State private var showSavedIndicator = false
    @State private var savedFlashID = 0

    // MARK: - Context

    /// Optional situational data supplied by the career shell. Every field is
    /// optional so the view renders cleanly from any entry point.
    struct Context {
        var weekLabel: String?        // "Week 5" / "Wild Card"
        var opponentName: String?     // "Chicago Bears"
        var opponentRecord: String?   // "3-1"
        var passDefense: DefenseStrength?
        var runDefense: DefenseStrength?
        var schemeName: String?       // OC's offensive scheme display name

        init(
            weekLabel: String? = nil,
            opponentName: String? = nil,
            opponentRecord: String? = nil,
            passDefense: DefenseStrength? = nil,
            runDefense: DefenseStrength? = nil,
            schemeName: String? = nil
        ) {
            self.weekLabel = weekLabel
            self.opponentName = opponentName
            self.opponentRecord = opponentRecord
            self.passDefense = passDefense
            self.runDefense = runDefense
            self.schemeName = schemeName
        }
    }

    /// How strong one facet of the opponent's defense is. Colored from the
    /// player's perspective: a weak opponent unit is an opportunity (green).
    enum DefenseStrength: String {
        case weak = "Weak"
        case average = "Average"
        case strong = "Strong"

        var color: Color {
            switch self {
            case .weak:    return .success
            case .average: return .warning
            case .strong:  return .danger
            }
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            ScrollView {
                VStack(spacing: DSSpacing.md) {
                    headerBar

                    if horizontalSizeClass == .regular {
                        HStack(alignment: .top, spacing: DSSpacing.md) {
                            VStack(spacing: DSSpacing.md) {
                                summaryChips
                                presetsCard
                                if hasOpponentData { opponentCard }
                            }
                            .frame(width: 340)

                            VStack(spacing: DSSpacing.md) {
                                offensiveSection
                                defensiveSection
                            }
                            .frame(maxWidth: .infinity)
                        }
                    } else {
                        summaryChips
                        presetsCard
                        if hasOpponentData { opponentCard }
                        offensiveSection
                        defensiveSection
                    }
                }
                .padding(20)
                .frame(maxWidth: 1080)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Game Plan")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onChange(of: gamePlan) { _, _ in
            flashSavedIndicator()
        }
    }

    // MARK: - Header Bar

    /// "Week N · vs OPP" + OC scheme badge + auto-save indicator.
    private var headerBar: some View {
        HStack(spacing: DSSpacing.sm) {
            if let situation = situationLine {
                Text(situation)
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
            }

            if let scheme = context?.schemeName {
                HStack(spacing: 4) {
                    Image(systemName: "book.closed.fill")
                        .font(.caption2)
                    Text(scheme)
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(Color.accentGold)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color.accentGold.opacity(0.10))
                        .overlay(Capsule().strokeBorder(Color.accentGold.opacity(0.45), lineWidth: 1))
                )
                .accessibilityLabel("Offensive scheme: \(scheme)")
            }

            Spacer()

            // Auto-save flash
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                Text("Saved")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.success)
            .opacity(showSavedIndicator ? 1 : 0)
            .animation(.easeInOut(duration: 0.25), value: showSavedIndicator)
            .accessibilityHidden(!showSavedIndicator)
        }
        .padding(.horizontal, 4)
    }

    private var situationLine: String? {
        let week = context?.weekLabel
        let opponent = context?.opponentName.map { "vs \($0)" }
        let parts = [week, opponent].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func flashSavedIndicator() {
        savedFlashID += 1
        let flashID = savedFlashID
        showSavedIndicator = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            // Only hide if no newer change re-triggered the flash.
            if flashID == savedFlashID {
                showSavedIndicator = false
            }
        }
    }

    // MARK: - Summary Chips

    /// Three at-a-glance chips: overall style, offensive identity, defensive identity.
    private var summaryChips: some View {
        HStack(spacing: DSSpacing.xs) {
            summaryChip(label: "Style", value: gamePlan.styleSummary)
            summaryChip(label: "Offense", value: gamePlan.runPassLabel)
            summaryChip(label: "Defense", value: defenseDisplayLabel)
        }
    }

    private func summaryChip(label: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.footnote.weight(.bold))
                .foregroundStyle(Color.accentGold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                        .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private var defenseDisplayLabel: String {
        let avg = (gamePlan.defensiveAggression + gamePlan.blitzFrequency) / 2.0
        switch avg {
        case 0.0..<0.3:  return "Soft Zone"
        case 0.3..<0.55: return "Balanced"
        case 0.55..<0.75: return "Aggressive"
        default:         return "Blitz Heavy"
        }
    }

    // MARK: - Presets Card

    private struct PresetInfo {
        let label: String
        let icon: String
        let plan: GamePlan
        let description: String
    }

    private var presets: [PresetInfo] {
        [
            PresetInfo(
                label: "Conservative",
                icon: "shield.fill",
                plan: .conservative,
                description: "Protect the ball, lean on the run, punt on 4th."
            ),
            PresetInfo(
                label: "Balanced",
                icon: "equal.circle.fill",
                plan: .balanced,
                description: "Even mix — take what the defense gives you."
            ),
            PresetInfo(
                label: "Aggressive",
                icon: "bolt.fill",
                plan: .aggressive,
                description: "Chase big plays, blitz often, go for it on 4th."
            ),
        ]
    }

    private var presetsCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            SectionHeaderText(title: "Presets")

            VStack(spacing: DSSpacing.xs) {
                ForEach(presets, id: \.label) { preset in
                    presetRow(preset)
                }
            }
        }
        .padding(DSSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    private func presetRow(_ preset: PresetInfo) -> some View {
        let isActive = gamePlan.matches(preset.plan)

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                gamePlan = preset.plan
            }
        } label: {
            HStack(spacing: DSSpacing.sm) {
                Image(systemName: preset.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.accentGold)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.accentGold.opacity(0.12)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text(preset.description)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)

                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentGold)
                }
            }
            .padding(.horizontal, DSSpacing.sm)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                    .fill(isActive ? Color.accentGold.opacity(0.10) : Color.backgroundTertiary.opacity(0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                            .strokeBorder(
                                isActive ? Color.accentGold : Color.surfaceBorder,
                                lineWidth: isActive ? 1.5 : 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Apply \(preset.label) preset\(isActive ? ", currently active" : "")")
    }

    // MARK: - Opponent Card

    private var hasOpponentData: Bool {
        context?.opponentName != nil
    }

    private var opponentCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            SectionHeaderText(title: "Scouting Report")

            HStack(alignment: .firstTextBaseline) {
                Text(context?.opponentName ?? "")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                if let record = context?.opponentRecord {
                    Text(record)
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                }
            }

            if let passD = context?.passDefense {
                defenseRow(label: "Pass Defense", strength: passD)
            }
            if let runD = context?.runDefense {
                defenseRow(label: "Run Defense", strength: runD)
            }

            if let tip = opponentTip {
                Text(tip)
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                    .padding(.top, 2)
            }
        }
        .padding(DSSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    private func defenseRow(label: String, strength: DefenseStrength) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(strength.rawValue)
                .font(.caption.weight(.bold))
                .foregroundStyle(strength.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(strength.color.opacity(0.12)))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(strength.rawValue)")
    }

    /// One-line coaching suggestion derived from the opponent's weak spots.
    private var opponentTip: String? {
        let passD = context?.passDefense
        let runD = context?.runDefense
        switch (passD, runD) {
        case (.weak, .strong), (.weak, .average):
            return "Their secondary is the soft spot — consider leaning pass."
        case (.strong, .weak), (.average, .weak):
            return "Their front seven can be run on — consider leaning run."
        case (.weak, .weak):
            return "Weak on both levels — press your advantage."
        case (.strong, .strong):
            return "Stout defense — protect the ball and win field position."
        default:
            return nil
        }
    }

    // MARK: - Offensive Section

    private var offensiveSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            sectionHeader(title: "Offense", icon: "football.fill", color: .accentBlue)

            Divider().overlay(Color.surfaceBorder)

            sliderRow(
                label: "Offensive Style",
                leftLabel: "Conservative",
                rightLabel: "Aggressive",
                riskReward: "Shots downfield open up — sacks and turnovers follow.",
                value: $gamePlan.offensiveAggression,
                color: .accentBlue
            )

            sliderRow(
                label: "Play Calling Mix",
                leftLabel: "Run Heavy",
                rightLabel: "Pass Heavy",
                riskReward: "Passing gains chunks fast — running protects the ball and clock.",
                value: $gamePlan.runPassRatio,
                color: .accentBlue
            )

            sliderRow(
                label: "4th Down Decisions",
                leftLabel: "Punt / FG",
                rightLabel: "Go For It",
                riskReward: "More TDs on the table — more turnovers on downs.",
                value: $gamePlan.fourthDownAggressiveness,
                color: .accentBlue
            )
        }
        .padding(DSSpacing.md + 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    // MARK: - Defensive Section

    private var defensiveSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            sectionHeader(title: "Defense", icon: "shield.lefthalf.filled", color: .danger)

            Divider().overlay(Color.surfaceBorder)

            sliderRow(
                label: "Defensive Style",
                leftLabel: "Soft Zone",
                rightLabel: "Press Man",
                riskReward: "Press coverage forces mistakes — beaten corners give up big plays.",
                value: $gamePlan.defensiveAggression,
                color: .danger
            )

            sliderRow(
                label: "Blitz Frequency",
                leftLabel: "Coverage",
                rightLabel: "Full Blitz",
                riskReward: "More sacks and hurried throws — open field behind the rush.",
                value: $gamePlan.blitzFrequency,
                color: .danger
            )
        }
        .padding(DSSpacing.md + 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    // MARK: - Slider Row

    private func sliderRow(
        label: String,
        leftLabel: String,
        rightLabel: String,
        riskReward: String,
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
                    .font(.subheadline.monospacedDigit().weight(.semibold))
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

            Text(riskReward)
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
                .italic()
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

    // MARK: - Helpers

    private func percentLabel(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var gamePlan: GamePlan = .balanced

    NavigationStack {
        GamePlanView(
            gamePlan: $gamePlan,
            context: GamePlanView.Context(
                weekLabel: "Week 5",
                opponentName: "Chicago Bears",
                opponentRecord: "3-1",
                passDefense: .weak,
                runDefense: .strong,
                schemeName: "West Coast"
            )
        )
    }
}
