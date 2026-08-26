import SwiftUI
import SwiftData

// MARK: - Voluntary Workout Prompt
//
// Weekly request dialog (modal sheet). The GM picks one of four
// workout flavors — voluntary OTAs / mandatory minicamp / Saturday
// film / off-day practice — or skips the week. Each card shows the
// scheme bonus, locker-room delta, injury-risk boost and expected
// attendance up front.

struct VoluntaryWorkoutPrompt: View {

    let career: Career

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var selected: VoluntaryWorkoutType?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.md) {
                    header
                    ForEach(VoluntaryWorkoutType.allCases, id: \.self) { type in
                        workoutCard(for: type)
                    }
                }
                .padding(DSSpacing.md)
            }
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Workout Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip this week") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: submit) {
                        // A greyed "Submit" beside an enabled "Skip this week"
                        // reads as "the only live control is the escape hatch".
                        // The disabled state names what it is waiting for.
                        Text(selected == nil ? "Pick an option" : "Submit")
                            .font(.subheadline.weight(.semibold))
                    }
                    .disabled(selected == nil)
                }
            }
        }
        // Four cards do not fit the default sheet height: the cut fell through
        // the middle of Off-Day Practice — the option with the injury cost —
        // hiding its chip row with nothing on screen to say the list continued.
        .presentationDetents([.large])
    }

    // MARK: - Subviews

    /// `career.currentWeek` is the raw calendar counter, and only
    /// `startNewSeason` resets it — so a July training camp prompt headed
    /// "Week 21" claims a week of a seventeen-game season that does not exist.
    /// Outside the regular season the phase is the week the player is living in.
    private var headerTitle: String {
        switch career.currentPhase {
        case .regularSeason, .tradeDeadline, .playoffs:
            return "Week \(career.currentWeek) — Pick One"
        default:
            return "\(career.currentPhase.displayName) — Pick One"
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeaderText(title: headerTitle)
            Text("Choose how the team will train this week. Scheme familiarity (0–100, best scheme only) and injury load move for the men who show up; the locker-room swing lands on the whole roster.")
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func workoutCard(for type: VoluntaryWorkoutType) -> some View {
        let isSelected = (selected == type)
        let cfg = config(for: type)
        return Button {
            selected = type
        } label: {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                HStack {
                    Image(systemName: icon(for: type))
                        .foregroundStyle(Color.accentGold)
                        .font(.title3)
                    Text(title(for: type))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentGold)
                            .font(.title3)
                    }
                }
                Text(blurb(for: type))
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                // All four numbers are deltas, so a zero reads as "±0" rather
                // than "+0": "Inj +0%" was being read as no injury risk at all
                // instead of no change to it. Attendance is the figure that
                // actually separates these four options and it used to be
                // computed here and never shown — "~" because the engine rolls
                // it per man off archetype and work ethic, so the base rate is
                // the most the card can promise.
                HStack(spacing: DSSpacing.sm) {
                    statChip(label: "Scheme Fam", value: signed(cfg.schemeBonus), tint: cfg.schemeBonus > 0 ? Color.success : Color.textSecondary)
                    statChip(label: "Locker Room", value: signed(cfg.lrDelta), tint: cfg.lrDelta > 0 ? Color.success : (cfg.lrDelta < 0 ? Color.danger : Color.textSecondary))
                    statChip(label: "Injury Risk", value: cfg.injuryRiskBoost > 0 ? "+\(cfg.injuryRiskBoost)%" : "±0%", tint: cfg.injuryRiskBoost > 0 ? Color.warning : Color.textSecondary)
                    statChip(label: "Attend", value: "~\(cfg.participationPct)%", tint: Color.textPrimary)
                }
            }
            .padding(DSSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DSCornerRadius.card)
                    .fill(isSelected ? Color.accentGold.opacity(0.12) : Color.backgroundSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DSCornerRadius.card)
                    .strokeBorder(isSelected ? Color.accentGold : Color.surfaceBorder, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func statChip(label: String, value: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                .fill(Color.backgroundTertiary)
        )
    }

    // MARK: - Per-type metadata

    private struct Config {
        let schemeBonus: Int
        let lrDelta: Int
        let injuryRiskBoost: Int
        let participationPct: Int
    }

    /// The three numbers on a card come from the engine that spends them. They
    /// used to be hand-mirrored here, and the off-day card had drifted to
    /// +4 scheme / −2 LR / +4% against the engine's +2 / −3 / +3% — a card
    /// promising double the scheme gain and half the morale hit, for an effect
    /// `VoluntaryWorkoutEngine.apply` recomputes from its own config anyway.
    private func config(for type: VoluntaryWorkoutType) -> Config {
        let engine = VoluntaryWorkoutEngine.config(for: type)
        return Config(
            schemeBonus: engine.schemeBonus,
            lrDelta: engine.lrDelta,
            injuryRiskBoost: engine.injuryRiskBoost,
            participationPct: baseParticipationPct(for: type)
        )
    }

    /// Attendance is the one number with nothing to read: the engine's base
    /// rates are a local table inside `participation(type:roster:)`. These are
    /// the same rates as a percentage — off-day practice included, which stood
    /// at 80 here against the engine's 0.55.
    private func baseParticipationPct(for type: VoluntaryWorkoutType) -> Int {
        switch type {
        case .voluntaryOTAs:     return 70
        case .mandatoryMinicamp: return 95
        case .saturdayFilm:      return 40
        case .offDayPractice:    return 55
        }
    }

    private func title(for type: VoluntaryWorkoutType) -> String {
        switch type {
        case .voluntaryOTAs:     return "Voluntary OTAs"
        case .mandatoryMinicamp: return "Mandatory Minicamp"
        case .saturdayFilm:      return "Saturday Film"
        case .offDayPractice:    return "Off-Day Practice"
        }
    }

    private func blurb(for type: VoluntaryWorkoutType) -> String {
        switch type {
        case .voluntaryOTAs:     return "Gentle on-field session. Optional attendance. Scheme + light LR bump."
        case .mandatoryMinicamp: return "Compulsory; near-full participation. Big scheme gain but locker-room hit."
        case .saturdayFilm:      return "Light film session for whoever shows. Small scheme bump only for attendees."
        case .offDayPractice:    return "Intensive — adds fatigue and injury risk for a sharper edge."
        }
    }

    private func icon(for type: VoluntaryWorkoutType) -> String {
        switch type {
        case .voluntaryOTAs:     return "figure.run"
        case .mandatoryMinicamp: return "exclamationmark.triangle"
        case .saturdayFilm:      return "film"
        case .offDayPractice:    return "flame"
        }
    }

    private func signed(_ value: Int) -> String {
        if value == 0 { return "±0" }
        return value > 0 ? "+\(value)" : "\(value)"
    }

    // MARK: - Submit

    /// Books the workout AND runs it.
    ///
    /// **The gap this closes.** This screen used to insert a `VoluntaryWorkout`
    /// row and stop there: `VoluntaryWorkoutEngine.apply` had no call site
    /// anywhere in the tree, and neither did `participation`. Every card on this
    /// prompt advertised a scheme bump, a locker-room cost and an injury-risk
    /// trade — and choosing one changed nothing about any player. The row was a
    /// receipt for work that never happened.
    ///
    /// Three things now happen in the order they have to:
    ///
    /// 1. **Attendance is rolled against the actual roster**, not read off a
    ///    per-type constant. `participation` walks every man's archetype and
    ///    work ethic, so a locker room full of divas really does turn up thinner
    ///    for voluntary work than one full of workhorses — which is the whole
    ///    premise the cards are sold on.
    /// 2. The row is written with THAT number, so the ledger records what
    ///    happened rather than what was advertised.
    /// 3. `apply` spends it: scheme familiarity to the men who showed, hidden
    ///    load to the men who showed for the hard sessions, and the locker-room
    ///    delta across everyone, attendees and skippers alike.
    private func submit() {
        guard let teamID = career.teamID, let type = selected else { return }

        // The user's club only. A workout the coach called moves his own room.
        let descriptor = FetchDescriptor<Player>(
            predicate: #Predicate<Player> { $0.teamID == teamID }
        )
        let roster = (try? modelContext.fetch(descriptor)) ?? []

        let cfg = config(for: type)
        let attendance = VoluntaryWorkoutEngine.participation(type: type, roster: roster)
        let workout = VoluntaryWorkout(
            seasonYear: career.currentSeason,
            weekNumber: career.currentWeek,
            typeRaw: type.rawValue,
            participationPct: attendance,
            schemeBonus: cfg.schemeBonus,
            lockerRoomDelta: cfg.lrDelta,
            injuryRiskBoost: cfg.injuryRiskBoost,
            teamID: teamID
        )
        workout.careerID = career.id
        modelContext.insert(workout)
        VoluntaryWorkoutEngine.apply(
            workout: workout,
            roster: roster,
            modelContext: modelContext
        )
        try? modelContext.save()
        dismiss()
    }
}
