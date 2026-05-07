import SwiftUI
import SwiftData

// MARK: - Voluntary Workout Prompt
//
// Weekly request dialog (modal sheet). The GM picks one of four
// workout flavors — voluntary OTAs / mandatory minicamp / Saturday
// film / off-day practice — or skips the week. Each card shows the
// scheme bonus, locker-room delta, and injury-risk boost up front.

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
                        Text("Submit")
                            .font(.subheadline.weight(.semibold))
                    }
                    .disabled(selected == nil)
                }
            }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeaderText(title: "Week \(career.currentWeek) — Pick One")
            Text("Choose how the team will train this week. Each option has different scheme, locker-room, and injury implications.")
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

                HStack(spacing: DSSpacing.sm) {
                    statChip(label: "Scheme", value: "+\(cfg.schemeBonus)", tint: cfg.schemeBonus > 0 ? Color.success : Color.textSecondary)
                    statChip(label: "LR", value: signed(cfg.lrDelta), tint: cfg.lrDelta >= 0 ? Color.success : Color.danger)
                    statChip(label: "Inj", value: "+\(cfg.injuryRiskBoost)%", tint: cfg.injuryRiskBoost > 0 ? Color.warning : Color.textSecondary)
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

    /// Local config — mirrors the canonical `VoluntaryWorkoutEngine.config(for:)`
    /// values so the UI is usable even before the engine is wired in.
    private struct Config {
        let schemeBonus: Int
        let lrDelta: Int
        let injuryRiskBoost: Int
        let participationPct: Int
    }

    private func config(for type: VoluntaryWorkoutType) -> Config {
        switch type {
        case .voluntaryOTAs:
            return Config(schemeBonus: 3, lrDelta: 2, injuryRiskBoost: 0, participationPct: 70)
        case .mandatoryMinicamp:
            return Config(schemeBonus: 5, lrDelta: -5, injuryRiskBoost: 2, participationPct: 95)
        case .saturdayFilm:
            return Config(schemeBonus: 1, lrDelta: 0, injuryRiskBoost: 0, participationPct: 40)
        case .offDayPractice:
            return Config(schemeBonus: 4, lrDelta: -2, injuryRiskBoost: 4, participationPct: 80)
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
        value >= 0 ? "+\(value)" : "\(value)"
    }

    // MARK: - Submit

    private func submit() {
        guard let teamID = career.teamID, let type = selected else { return }
        let cfg = config(for: type)
        let workout = VoluntaryWorkout(
            seasonYear: career.currentSeason,
            weekNumber: career.currentWeek,
            typeRaw: type.rawValue,
            participationPct: cfg.participationPct,
            schemeBonus: cfg.schemeBonus,
            lockerRoomDelta: cfg.lrDelta,
            injuryRiskBoost: cfg.injuryRiskBoost,
            teamID: teamID
        )
        modelContext.insert(workout)
        try? modelContext.save()
        dismiss()
    }
}
