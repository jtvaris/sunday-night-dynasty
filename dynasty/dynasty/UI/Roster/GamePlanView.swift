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
    /// #37: forward path into the game. When non-nil (regular season / playoffs
    /// with an unplayed player game this week) a prominent "Start Game" button
    /// is shown so the plan screen is never a navigation dead-end — the plan
    /// auto-saves, so this jumps straight into the coached game.
    var onStartGame: (() -> Void)? = nil
    /// R36: weekly practice play — pick one not-installed play to drill;
    /// it installs into the call sheet for the season after enough weeks.
    /// `nil` hides the card (entry points without a career).
    var practice: PracticeContext?

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
        /// R33: opponent coordinator play-calling personas (scouting intel —
        /// the same personas the live game's AI actually calls with).
        var opponentDCPersona: DCPersona?
        var opponentOCPersona: OCPersona?

        init(
            weekLabel: String? = nil,
            opponentName: String? = nil,
            opponentRecord: String? = nil,
            passDefense: DefenseStrength? = nil,
            runDefense: DefenseStrength? = nil,
            schemeName: String? = nil,
            opponentDCPersona: DCPersona? = nil,
            opponentOCPersona: OCPersona? = nil
        ) {
            self.weekLabel = weekLabel
            self.opponentName = opponentName
            self.opponentRecord = opponentRecord
            self.passDefense = passDefense
            self.runDefense = runDefense
            self.schemeName = schemeName
            self.opponentDCPersona = opponentDCPersona
            self.opponentOCPersona = opponentOCPersona
        }
    }

    /// R36: everything the practice-play card needs. Plain values + a
    /// callback so the career shell owns persistence.
    struct PracticeContext {
        /// The OC's scheme — decides which plays are already installed.
        var scheme: OffensiveScheme?
        /// The play currently being drilled (nil = nothing queued).
        var currentPlay: OffensivePlayCall?
        /// Practice weeks already banked on `currentPlay`.
        var weeksDone: Int
        /// Weeks needed to install (1 with an expert OC, otherwise 2).
        var weeksRequired: Int
        /// Plays already installed through practice this season.
        var installedThisSeason: [OffensivePlayCall]
        /// Persists a new pick (or nil to cancel practice).
        var onSelect: (OffensivePlayCall?) -> Void
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

                    if let onStartGame {
                        startGameButton(action: onStartGame)
                    }

                    if horizontalSizeClass == .regular {
                        HStack(alignment: .top, spacing: DSSpacing.md) {
                            VStack(spacing: DSSpacing.md) {
                                summaryChips
                                presetsCard
                                if practice != nil { practiceCard }
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
                        if practice != nil { practiceCard }
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

    // MARK: - Start Game CTA (#37)

    /// Prominent forward path into the coached game. The plan auto-saves on
    /// every change, so no confirmation is needed — this simply launches.
    private func startGameButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "headset")
                    .font(.headline.weight(.bold))
                Text("Start Game")
                    .font(.headline.weight(.bold))
                Spacer(minLength: 0)
                Image(systemName: "arrow.right")
                    .font(.headline.weight(.bold))
            }
            .foregroundStyle(Color.backgroundPrimary)
            .padding(.horizontal, DSSpacing.lg)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                Color.accentGold,
                in: RoundedRectangle(cornerRadius: DSCornerRadius.card)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Start the game with this plan")
        .accessibilityHint("Your game plan is saved automatically")
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

    // MARK: - Practice Play Card (R36)

    /// The plays NOT yet on the call sheet (scheme playbook + practiced
    /// installs), grouped by category for the picker menu.
    private func practicablePlays(_ practice: PracticeContext) -> [OffensivePlayCall] {
        OffensivePlayCall.allCases.filter { play in
            !play.isSpecial && play != .qbSneak
                && !play.isInPlaybook(of: practice.scheme)
                && !practice.installedThisSeason.contains(play)
        }
    }

    @ViewBuilder
    private var practiceCard: some View {
        if let practice {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                SectionHeaderText(title: "Practice Play of the Week")

                if let play = practice.currentPlay {
                    // Drilling in progress: name, progress line, cancel.
                    HStack(spacing: DSSpacing.sm) {
                        Image(systemName: "figure.strengthtraining.functional")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.accentGold)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Color.accentGold.opacity(0.12)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(play.rawValue)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Color.textPrimary)
                            Text(practiceProgressLine(practice))
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                        Spacer(minLength: 0)
                        Button {
                            practice.onSelect(nil)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(Color.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Cancel practice play")
                    }
                    .padding(.horizontal, DSSpacing.sm)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                            .fill(Color.accentGold.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                                    .strokeBorder(Color.accentGold.opacity(0.5), lineWidth: 1)
                            )
                    )
                } else {
                    // Nothing queued: pick a play to drill.
                    Menu {
                        ForEach(["Run", "Short Pass", "Medium Pass", "Deep Pass"], id: \.self) { category in
                            let plays = practicablePlays(practice).filter { $0.category == category }
                            if !plays.isEmpty {
                                Section(category) {
                                    ForEach(plays, id: \.self) { play in
                                        Button(play.rawValue) { practice.onSelect(play) }
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: DSSpacing.sm) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.accentGold)
                            Text("Choose a play to drill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.textPrimary)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption)
                                .foregroundStyle(Color.textTertiary)
                        }
                        .padding(.horizontal, DSSpacing.sm)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                                .fill(Color.backgroundTertiary.opacity(0.55))
                                .overlay(
                                    RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                                        .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                                )
                        )
                    }
                }

                Text(practice.weeksRequired == 1
                     ? "Your coordinator installs a new play in one practice week."
                     : "Two practice weeks install the play into the call sheet for the season.")
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)

                if !practice.installedThisSeason.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("INSTALLED THIS SEASON")
                            .font(.caption2.weight(.bold))
                            .tracking(0.8)
                            .foregroundStyle(Color.textTertiary)
                        ForEach(practice.installedThisSeason, id: \.self) { play in
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(Color.success)
                                Text(play.rawValue)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.textPrimary)
                            }
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(DSSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground()
        }
    }

    private func practiceProgressLine(_ practice: PracticeContext) -> String {
        let remaining = max(0, practice.weeksRequired - practice.weeksDone)
        if remaining <= 1 { return "Installs after this week's practice" }
        return "\(practice.weeksDone) of \(practice.weeksRequired) practice weeks done"
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

            // R33: coordinator persona intel — how their DC/OC actually call.
            if let dc = context?.opponentDCPersona {
                coordinatorRow(side: "Their DC", persona: dc.displayName,
                               blurb: dc.scoutingBlurb, color: .danger)
            }
            if let oc = context?.opponentOCPersona {
                coordinatorRow(side: "Their OC", persona: oc.displayName,
                               blurb: oc.scoutingBlurb, color: .accentBlue)
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

    /// R33: one coordinator persona line — label, persona chip, scouting blurb.
    private func coordinatorRow(
        side: String,
        persona: String,
        blurb: String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(side)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Text(persona)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(color.opacity(0.12)))
            }
            Text(blurb)
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(side): \(persona). \(blurb)")
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
                schemeName: "West Coast",
                opponentDCPersona: .exotic,
                opponentOCPersona: .groundAndPound
            )
        )
    }
}
