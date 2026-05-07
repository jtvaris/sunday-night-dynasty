import SwiftUI
import SwiftData

// MARK: - Game-Week Prep Picker
//
// Per regular-season game week the GM splits prep time between
// "general" (long-term attribute development) and "opponent" (short-term
// audible / read bonuses). Live preview translates the slider to the
// concrete this-week effects. After 3+ consecutive opponent-heavy weeks
// a drift warning surfaces.

struct GameWeekPrepPicker: View {

    let career: Career
    /// Number of consecutive prior weeks where opponentPct >= 70.
    /// Computed by the caller from `OpponentPrepWeek` history.
    let consecutiveOpponentWeeks: Int

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// 0 = pure general, 100 = pure opponent.
    @State private var opponentPct: Double = 50
    @State private var didSave: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.lg) {
                header
                slider
                preview
                if shouldWarnDrift {
                    driftWarning
                }
                Spacer(minLength: DSSpacing.xl)
            }
            .padding(DSSpacing.md)
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("Week \(career.currentWeek) Prep")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(action: save) {
                    Text(didSave ? "Saved" : "Save")
                        .font(.subheadline.weight(.semibold))
                }
                .disabled(didSave)
            }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeaderText(title: "Game-Week Prep")
            Text("Balance long-term player development against this-week opponent prep.")
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var slider: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack {
                Text("General")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.success)
                Spacer()
                Text("\(generalPctInt)% / \(opponentPctInt)%")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                    .monospacedDigit()
                Spacer()
                Text("Opponent")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentGold)
            }
            Slider(
                value: Binding(
                    get: { opponentPct },
                    set: { newValue in
                        opponentPct = newValue
                        didSave = false
                    }
                ),
                in: 0...100,
                step: 1
            )
            .tint(Color.accentGold)
        }
        .padding(DSSpacing.md)
        .cardBackground()
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            SectionHeaderText(title: "This Week's Effects")

            previewRow(
                label: "+\(audibleBoost)%",
                description: "audible success",
                tint: Color.accentGold,
                icon: "waveform"
            )
            previewRow(
                label: "+\(defReadBoost)%",
                description: "defensive read",
                tint: Color.accentGold,
                icon: "eye"
            )
            previewRow(
                label: "+\(devTickPct)%",
                description: "long-term attribute development",
                tint: Color.success,
                icon: "chart.line.uptrend.xyaxis"
            )
        }
    }

    private func previewRow(label: String, description: String, tint: Color, icon: String) -> some View {
        HStack(spacing: DSSpacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 24)
            Text(label)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
                .monospacedDigit()
                .frame(width: 60, alignment: .leading)
            Text(description)
                .font(.subheadline)
                .foregroundStyle(Color.textPrimary)
            Spacer()
        }
        .padding(DSSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                .fill(Color.backgroundSecondary)
        )
    }

    private var driftWarning: some View {
        HStack(spacing: DSSpacing.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.warning)
            Text("Roster development stalling — \(consecutiveOpponentWeeks) consecutive opponent-heavy weeks. Expect -1 OVR drift.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.warning)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DSSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                .fill(Color.warning.opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                .strokeBorder(Color.warning.opacity(0.6), lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private var opponentPctInt: Int { Int(opponentPct.rounded()) }
    private var generalPctInt: Int { 100 - opponentPctInt }

    /// Audible success bonus: full pure-opponent slider gives +20% audibles.
    private var audibleBoost: Int {
        Int((Double(opponentPctInt) / 100.0 * 20.0).rounded())
    }

    /// Defensive read bonus: full pure-opponent slider gives +15%.
    private var defReadBoost: Int {
        Int((Double(opponentPctInt) / 100.0 * 15.0).rounded())
    }

    /// Roughly the share of weekly attribute-tick gains preserved.
    private var devTickPct: Int { generalPctInt }

    private var shouldWarnDrift: Bool {
        consecutiveOpponentWeeks >= 3 && opponentPctInt >= 70
    }

    private func save() {
        guard let teamID = career.teamID else { return }
        let prep = OpponentPrepWeek(
            seasonYear: career.currentSeason,
            weekNumber: career.currentWeek,
            generalPct: generalPctInt,
            opponentPct: opponentPctInt,
            teamID: teamID
        )
        modelContext.insert(prep)
        try? modelContext.save()
        didSave = true
    }
}
