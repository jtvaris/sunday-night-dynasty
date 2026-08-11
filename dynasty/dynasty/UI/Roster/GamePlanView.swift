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

    /// Sliders the recommended preset just moved — highlighted for a couple of
    /// seconds so the plan doesn't silently rewrite itself under the coach.
    @State private var highlightedSliders: Set<PlanSlider> = []
    @State private var highlightFlashID = 0

    /// The five game-plan dials, used to name what a preset changed.
    enum PlanSlider: String, CaseIterable {
        case offensiveAggression
        case runPassRatio
        case fourthDown
        case defensiveAggression
        case blitzFrequency

        var shortLabel: String {
            switch self {
            case .offensiveAggression: return "Off. Style"
            case .runPassRatio:        return "Play Mix"
            case .fourthDown:          return "4th Down"
            case .defensiveAggression: return "Def. Style"
            case .blitzFrequency:      return "Blitz"
            }
        }
    }

    // MARK: - Context

    /// Optional situational data supplied by the career shell. Every field is
    /// optional so the view renders cleanly from any entry point.
    struct Context {
        var weekLabel: String?        // "Week 5" / "Wild Card"
        var opponentName: String?     // "Chicago Ironworks"
        var opponentRecord: String?   // "3-1"
        var passDefense: DefenseStrength?
        var runDefense: DefenseStrength?
        var schemeName: String?       // OC's offensive scheme display name
        /// R33: opponent coordinator play-calling personas (scouting intel —
        /// the same personas the live game's AI actually calls with).
        var opponentDCPersona: DCPersona?
        var opponentOCPersona: OCPersona?

        /// Round 4 (§6a): the user team's key skill players' pre-game mental
        /// lines for the "Mental Readiness" panel — temperament tag, morale,
        /// and (for ego stars) a feed-the-star reminder. Defaults empty so
        /// entry points without a career simply hide the panel; the career
        /// shell fills it. No new persisted data — every field is derived
        /// live from the roster.
        var keyPlayerMentals: [MentalReadout] = []

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

    /// Round 4 (§6a): one key skill player's pre-game mental line. The career
    /// shell derives `temperament`/`isEgoStar` through the very same
    /// `SimPlayer` the engine reads (zero drift), so the panel needs no roster
    /// access or duplicated thresholds of its own.
    struct MentalReadout: Identifiable {
        let id: UUID
        let name: String
        let position: Position
        let temperament: MentalTemperament
        /// Locker-room morale, 1…100 (same scale as `Player.morale`).
        let morale: Int
        /// A me-first star at a touch position — earns the feed-him hint.
        let isEgoStar: Bool
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
                        // Mental Readiness rides in the RIGHT column under the
                        // Defense card. The two slider cards are short, so the
                        // right column used to bottom out ~320pt above the left
                        // one — a stranded void beside a scrolling list.
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
                                if hasMentalData { mentalReadinessCard }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    } else {
                        summaryChips
                        presetsCard
                        if practice != nil { practiceCard }
                        if hasOpponentData { opponentCard }
                        if hasMentalData { mentalReadinessCard }
                        offensiveSection
                        defensiveSection
                    }
                }
                .padding(20)
                .frame(maxWidth: DSLayout.gridMeasure)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Game Plan")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onChange(of: gamePlan) { _, _ in
            flashSavedIndicator()
        }
        // Setting the plan is the last thing before kickoff, so this screen
        // gets the pregame score rather than the front-office bed.
        .onAppear {
            MusicDirector.shared.pushOverride(.gameday)
        }
        .onDisappear {
            MusicDirector.shared.clearOverride(.gameday)
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
                if let recommendation {
                    recommendedPresetRow(recommendation)
                }
            }
        }
        .padding(DSSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    // MARK: - Recommended Preset

    /// A game plan the staff derives from THIS week's scouting report, plus the
    /// reasons behind it.
    ///
    /// Everything here comes from data already printed on the screen — the two
    /// defense grades and the two coordinator personas — so the card can never
    /// recommend something the scouting panel above it contradicts.
    struct Recommendation {
        let opponentName: String
        let plan: GamePlan
        /// One short clause per input that moved a slider, e.g. "weak secondary
        /// — lean pass".
        let reasons: [String]
        /// Which dials this plan would move away from the current one.
        let changedSliders: Set<PlanSlider>
    }

    private var recommendation: Recommendation? {
        guard let opponent = context?.opponentName else { return nil }
        let passD = context?.passDefense
        let runD = context?.runDefense
        let dc = context?.opponentDCPersona
        let oc = context?.opponentOCPersona
        // Nothing scouted = nothing to recommend; a "recommendation" built from
        // four nils is just the Balanced preset wearing the opponent's name.
        guard passD != nil || runD != nil || dc != nil || oc != nil else { return nil }

        var plan = GamePlan.balanced
        var reasons: [String] = []

        // --- Their pass defense decides how much we throw ---
        switch passD {
        case .weak:
            plan.runPassRatio += 0.18
            plan.offensiveAggression += 0.12
            reasons.append("Weak secondary — lean pass and take shots")
        case .strong:
            plan.runPassRatio -= 0.12
            plan.offensiveAggression -= 0.08
            reasons.append("Strong secondary — fewer throws into coverage")
        case .average, nil:
            break
        }

        // --- Their run defense decides how much we hand it off ---
        switch runD {
        case .weak:
            plan.runPassRatio -= 0.18
            plan.offensiveAggression -= 0.05
            reasons.append("Soft front seven — run at them and shorten the game")
        case .strong:
            plan.runPassRatio += 0.10
            reasons.append("Stout front — the run is not there")
        case .average, nil:
            break
        }

        // --- Both levels soft: press it. Both stout: protect the ball. ---
        if passD == .weak && runD == .weak {
            plan.fourthDownAggressiveness += 0.20
            plan.offensiveAggression += 0.05
            reasons.append("Weak on both levels — stay on the field on 4th")
        } else if passD == .strong && runD == .strong {
            plan.fourthDownAggressiveness -= 0.20
            reasons.append("No soft spot — win field position, punt on 4th")
        }

        // --- Their DC: how much risk the 4th-down sheet can carry ---
        switch dc {
        case .exotic:
            plan.fourthDownAggressiveness -= 0.20
            plan.offensiveAggression -= 0.05
            reasons.append("Exotic DC — don't hand him a 4th-down look")
        case .aggressive:
            plan.offensiveAggression -= 0.05
            plan.runPassRatio += 0.05
            reasons.append("Blitz-happy DC — get the ball out quick")
        case .conservative:
            plan.fourthDownAggressiveness += 0.10
            reasons.append("Conservative DC — he'll bend before he breaks")
        case .balanced, nil:
            break
        }

        // --- Their OC: what our defense has to stop ---
        switch oc {
        case .groundAndPound:
            plan.defensiveAggression += 0.10
            plan.blitzFrequency += 0.12
            reasons.append("Run-first OC — crowd the box")
        case .airRaid:
            plan.blitzFrequency += 0.15
            plan.defensiveAggression -= 0.10
            reasons.append("Air Raid OC — pressure him, keep it in front")
        case .westCoast:
            plan.defensiveAggression += 0.15
            plan.blitzFrequency -= 0.05
            reasons.append("Timing passer — press and break the rhythm")
        case .balanced, nil:
            break
        }

        plan = Self.snapped(plan)

        var changed: Set<PlanSlider> = []
        if !approxEqual(plan.offensiveAggression, gamePlan.offensiveAggression) { changed.insert(.offensiveAggression) }
        if !approxEqual(plan.runPassRatio, gamePlan.runPassRatio) { changed.insert(.runPassRatio) }
        if !approxEqual(plan.fourthDownAggressiveness, gamePlan.fourthDownAggressiveness) { changed.insert(.fourthDown) }
        if !approxEqual(plan.defensiveAggression, gamePlan.defensiveAggression) { changed.insert(.defensiveAggression) }
        if !approxEqual(plan.blitzFrequency, gamePlan.blitzFrequency) { changed.insert(.blitzFrequency) }

        return Recommendation(
            opponentName: opponent,
            plan: plan,
            reasons: reasons,
            changedSliders: changed
        )
    }

    /// Clamps every dial into the usable band and rounds to the slider's own
    /// 0.05 step, so applying a preset and then nudging a slider by hand does
    /// not jump the value.
    private static func snapped(_ plan: GamePlan) -> GamePlan {
        func snap(_ value: Double) -> Double {
            let clamped = min(0.95, max(0.05, value))
            return (clamped * 20).rounded() / 20
        }
        return GamePlan(
            offensiveAggression: snap(plan.offensiveAggression),
            defensiveAggression: snap(plan.defensiveAggression),
            runPassRatio: snap(plan.runPassRatio),
            blitzFrequency: snap(plan.blitzFrequency),
            fourthDownAggressiveness: snap(plan.fourthDownAggressiveness)
        )
    }

    private func approxEqual(_ a: Double, _ b: Double) -> Bool { abs(a - b) <= 0.01 }

    private func recommendedPresetRow(_ recommendation: Recommendation) -> some View {
        let isActive = gamePlan.matches(recommendation.plan)

        return Button {
            let moved = recommendation.changedSliders
            withAnimation(.easeInOut(duration: 0.25)) {
                gamePlan = recommendation.plan
            }
            flashHighlight(moved)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: DSSpacing.sm) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.eliteGreen)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.eliteGreen.opacity(0.12)))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Recommended vs \(recommendation.opponentName)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(isActive
                             ? "Your plan already matches the staff's read."
                             : "Built from this week's scouting report.")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer(minLength: 0)

                    if isActive {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.eliteGreen)
                    }
                }

                ForEach(recommendation.reasons, id: \.self) { reason in
                    HStack(alignment: .top, spacing: 5) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.system(size: DSType.Size.micro, weight: .bold))
                            .foregroundStyle(Color.eliteGreen.opacity(0.8))
                            .padding(.top, 3)
                        Text(reason)
                            .font(.caption2)
                            .foregroundStyle(Color.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                }

                if !isActive && !recommendation.changedSliders.isEmpty {
                    HStack(spacing: 4) {
                        Text("MOVES")
                            .font(.system(size: DSType.Size.micro, weight: .bold))
                            .tracking(0.6)
                            .foregroundStyle(Color.textTertiary)
                        ForEach(PlanSlider.allCases.filter { recommendation.changedSliders.contains($0) }, id: \.self) { slider in
                            Text(slider.shortLabel)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.eliteGreen)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.eliteGreen.opacity(0.12)))
                        }
                    }
                }
            }
            .padding(.horizontal, DSSpacing.sm)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                    .fill(isActive ? Color.eliteGreen.opacity(0.10) : Color.backgroundTertiary.opacity(0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                            .strokeBorder(
                                isActive ? Color.eliteGreen : Color.eliteGreen.opacity(0.45),
                                lineWidth: isActive ? 1.5 : 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Apply the recommended plan against \(recommendation.opponentName)\(isActive ? ", currently active" : "")")
        .accessibilityHint(recommendation.reasons.joined(separator: ". "))
    }

    /// Marks the sliders a preset just moved, clearing after a beat.
    private func flashHighlight(_ sliders: Set<PlanSlider>) {
        guard !sliders.isEmpty else { return }
        highlightFlashID += 1
        let flashID = highlightFlashID
        withAnimation(.easeInOut(duration: 0.25)) { highlightedSliders = sliders }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
            if flashID == highlightFlashID {
                withAnimation(.easeOut(duration: 0.4)) { highlightedSliders = [] }
            }
        }
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
                        // The catalog's own tab order — the picker gained
                        // Screen / Play Action / RPO with the playbook
                        // expansion, and a hardcoded list here would have
                        // silently hidden 12 practicable plays.
                        ForEach(OffensivePlayCall.categories, id: \.self) { category in
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

    // MARK: - Mental Readiness Panel (Round 4 §6a)

    private var hasMentalData: Bool {
        !(context?.keyPlayerMentals.isEmpty ?? true)
    }

    /// Pre-game read on the key skill players' heads — temperament tag, morale
    /// bar, and a feed-the-star nudge for ego-driven stars — sitting beside the
    /// scouting report so the coach walks in knowing who is dialed in and who
    /// needs managing. Every value is derived live from the roster through the
    /// same `SimPlayer` the engine reads, so it stays in lockstep with the
    /// hot/cold model and adds no persisted state.
    private var mentalReadinessCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            SectionHeaderText(title: "Mental Readiness")

            ForEach(context?.keyPlayerMentals ?? []) { readout in
                mentalRow(readout)
            }
        }
        .padding(DSSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    private func mentalRow(_ readout: MentalReadout) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(readout.position.rawValue)
                    .font(.caption2.monospaced().weight(.bold))
                    .foregroundStyle(Color.textTertiary)
                    .frame(width: 26, alignment: .leading)
                Text(readout.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 6)
                temperamentChip(readout.temperament)
            }
            moraleBar(readout.morale)
            if readout.isEgoStar {
                HStack(spacing: 4) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: DSType.Size.micro, weight: .bold))
                    Text("Get him the ball early")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(Color.accentGold)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The static temperament tag chip — crown for the ego star, bolt for the
    /// streaky rider, seal for the unflappable pro, a muted mark for steady.
    /// Mirrors the icon language of the in-game Coach's Board badge.
    private func temperamentChip(_ temperament: MentalTemperament) -> some View {
        let label: LocalizedStringKey
        let icon: String
        let color: Color
        switch temperament {
        case .egoDriven:   (label, icon, color) = ("Ego-Driven", "crown.fill", .accentGold)
        case .streaky:     (label, icon, color) = ("Streaky", "bolt.fill", .warning)
        case .unflappable: (label, icon, color) = ("Unflappable", "checkmark.seal.fill", .accentBlue)
        case .neutral:     (label, icon, color) = ("Steady", "equal.circle", .textTertiary)
        }
        return HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: DSType.Size.micro, weight: .bold))
            Text(label)
                .font(.system(size: 9, weight: .bold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.12)))
    }

    /// A thin morale bar reusing the locker-room colour buckets (75+ green,
    /// 45+ amber, else red) with the numeric value trailing.
    private func moraleBar(_ morale: Int) -> some View {
        let fraction = min(1.0, max(0.0, Double(morale) / 100.0))
        let color: Color = morale >= 75 ? .success : (morale >= 45 ? .warning : .danger)
        return HStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.backgroundTertiary)
                    Capsule().fill(color)
                        .frame(width: max(3, geo.size.width * fraction))
                }
            }
            .frame(height: 5)
            Text("\(morale)")
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 24, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Morale \(morale) of 100")
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
                color: .accentBlue,
                slider: .offensiveAggression
            )

            sliderRow(
                label: "Play Calling Mix",
                leftLabel: "Run Heavy",
                rightLabel: "Pass Heavy",
                riskReward: "Passing gains chunks fast — running protects the ball and clock.",
                value: $gamePlan.runPassRatio,
                color: .accentBlue,
                slider: .runPassRatio
            )

            sliderRow(
                label: "4th Down Decisions",
                leftLabel: "Punt / FG",
                rightLabel: "Go For It",
                riskReward: "More TDs on the table — more turnovers on downs.",
                value: $gamePlan.fourthDownAggressiveness,
                color: .accentBlue,
                slider: .fourthDown
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
                color: .danger,
                slider: .defensiveAggression
            )

            sliderRow(
                label: "Blitz Frequency",
                leftLabel: "Coverage",
                rightLabel: "Full Blitz",
                riskReward: "More sacks and hurried throws — open field behind the rush.",
                value: $gamePlan.blitzFrequency,
                color: .danger,
                slider: .blitzFrequency
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
        color: Color,
        slider: PlanSlider
    ) -> some View {
        let isHighlighted = highlightedSliders.contains(slider)

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                if isHighlighted {
                    Text("ADJUSTED")
                        .font(.system(size: DSType.Size.micro, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(Color.eliteGreen)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.eliteGreen.opacity(0.15)))
                        .transition(.opacity.combined(with: .scale))
                }
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
        .padding(.horizontal, isHighlighted ? 8 : 0)
        .padding(.vertical, isHighlighted ? 6 : 0)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                .fill(Color.eliteGreen.opacity(isHighlighted ? 0.07 : 0))
                .overlay(
                    RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                        .strokeBorder(Color.eliteGreen.opacity(isHighlighted ? 0.4 : 0), lineWidth: 1)
                )
        )
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
                opponentName: "Chicago Ironworks",
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
