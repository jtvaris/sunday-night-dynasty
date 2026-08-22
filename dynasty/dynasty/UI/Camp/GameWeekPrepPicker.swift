import SwiftUI
import SwiftData

// MARK: - Game-Week Prep Picker
//
// Per regular-season game week the GM decides how much of the week goes at THIS
// opponent instead of general work.
//
// ## F-69: the preview used to quote a lever that no longer exists
//
// This screen advertised "+20 % audible success" and "+15 % defensive read",
// which were the two halves of the old post-game score multiplier — a
// scoreboard edit worth about +4.2 points of margin a game, applied to the user
// alone because no AI club has ever had an `OpponentPrepWeek` row. D1 deleted
// that and rebuilt prep as a real thing:
//
//   * it is THREADED — `OpponentPrep` composes a `PlaySimulator.Adjustments`
//     delta into the same per-play channel the coaching staff already moves;
//   * it is SHARED — all 32 clubs carry a focus derived from the staff they
//     already employ, so the user's slider is a signed delta on top of his own
//     staff's number rather than a private channel;
//   * it is SMALLER — measured at **+0.8 points of margin** at maximum prep
//     against an average staff, 19 % of what it was.
//
// So the copy was wrong twice over. It quoted percentages of nothing, and it
// described a bonus when the mechanism is a CONTEST: `focus` runs 0…1 with 0.5
// the league-average week, the modifier is `focus − 0.5`, two average staffs
// cancel exactly, and a club with a poor planner is measurably hurt.
//
// The preview below therefore quotes the engine's own constants through
// `OpponentPrep`'s own functions, in the units the simulator consumes —
// percentage points of completion probability and yards per carry — so a number
// on this screen is always a number OF something. The one aggregate figure is
// the measured +0.8, and it is labelled as what it is: a margin measurement at
// maximum prep against an average staff, not a percentage applied to anything.
//
// Note the deliberate silence about the coached path. `LiveGameEngine` still
// runs the old user-only boost as a per-play momentum nudge; that is a known
// remaining asymmetry for a later pass, it is one game in sixteen, and nothing
// written here contradicts it.

struct GameWeekPrepPicker: View {

    let career: Career
    /// Number of consecutive prior weeks where opponentPct >= 70.
    /// Computed by the caller from `OpponentPrepWeek` history.
    let consecutiveOpponentWeeks: Int

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// The staff whose game planning sets this club's baseline focus. `@Query`
    /// cannot take a runtime predicate from a stored property, so the store-wide
    /// result is narrowed to this save and this club here.
    @Query private var allCoachesUnscoped: [Coach]

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
            Text("How much of this week goes at Sunday's opponent instead of general work. **50 % is a league-average week** \u{2014} prep is a contest, so what it buys depends on what the other staff did.")
                .font(DSType.text(DSType.Size.footnote, .regular, prose: true))
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
        let offense = OpponentPrep.offenseEdge(focus: weekFocus)
        let defense = OpponentPrep.defenseEdge(focus: weekFocus)
        return VStack(alignment: .leading, spacing: DSSpacing.sm) {
            SectionHeaderText(title: "This Week's Effects")

            Text(baselineLine)
                .font(DSType.text(DSType.Size.footnote, .regular, prose: true))
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            previewRow(
                label: signedPoints(offense.completion * 100.0),
                description: "completion probability, our offense",
                tint: edgeTint(offense.completion),
                icon: "waveform"
            )
            previewRow(
                label: signedYards(offense.run),
                description: "yards per carry, our offense",
                tint: edgeTint(offense.run),
                icon: "figure.run"
            )
            previewRow(
                label: signedPoints(defense.completion * 100.0),
                description: "completion probability, their offense",
                tint: edgeTint(-defense.completion),
                icon: "eye"
            )
            previewRow(
                label: signedYards(defense.run),
                description: "yards per carry, their offense",
                tint: edgeTint(-defense.run),
                icon: "shield.lefthalf.filled"
            )

            Text(Self.magnitudeNote)
                .font(DSType.text(DSType.Size.caption, .regular, prose: true))
                .foregroundStyle(Color.textTertiaryReadable)
                .fixedSize(horizontal: false, vertical: true)

            Text(Self.generalEndNote)
                .font(DSType.text(DSType.Size.caption, .regular, prose: true))
                .foregroundStyle(Color.textTertiaryReadable)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// What the club's own staff brings before the slider is touched, and where
    /// the slider has put the week. Prep is a contest, so the baseline is the
    /// first thing the user needs and the screen never showed it.
    private var baselineLine: String {
        let staff = OpponentPrep.staffFocus(gamePlanning: staffGamePlanning)
        let staffWord: String
        if staff > OpponentPrep.neutralFocus + 0.02 {
            staffWord = "prepares better than the league before you touch anything"
        } else if staff < OpponentPrep.neutralFocus - 0.02 {
            staffWord = "prepares worse than the league before you touch anything"
        } else {
            staffWord = "prepares at the league average"
        }
        let delta = weekFocus - OpponentPrep.neutralFocus
        let standing: String
        if delta > 0.02 {
            standing = "This week you are ahead of an average staff."
        } else if delta < -0.02 {
            standing = "This week you are behind an average staff."
        } else {
            standing = "This week you are level with an average staff \u{2014} the effects below cancel."
        }
        return "Your staff \(staffWord). \(standing)"
    }

    /// The one aggregate number on the screen, and what it is a number OF.
    static let magnitudeNote =
        "Measured: a maximum-prep week against an average staff is worth about **eight tenths of a point of margin**. That is a margin measurement, not a percentage applied to anything \u{2014} and against a better-prepared staff it is less."

    /// F-69, the other half of this screen. `generalPct` is written to the row
    /// and read by nothing: the general end carries no development bonus in any
    /// engine path, and this screen used to advertise one as a percentage. What
    /// sliding left actually does is prepare less than the league.
    static let generalEndNote =
        "There is no development bonus on the General end \u{2014} nothing in the engine reads it. Sliding left means preparing less at this opponent than the league does, and the numbers above go negative."

    private func edgeTint(_ value: Double) -> Color {
        if abs(value) < 0.0001 { return .textTertiaryReadable }
        return value > 0 ? .success : .dangerText
    }

    /// Percentage POINTS of completion probability — the unit the simulator
    /// consumes, rather than a percentage of an unnamed baseline.
    private func signedPoints(_ value: Double) -> String {
        String(format: "%@%.1f pt", value >= 0 ? "+" : "\u{2212}", abs(value))
    }

    private func signedYards(_ value: Double) -> String {
        String(format: "%@%.2f yd", value >= 0 ? "+" : "\u{2212}", abs(value))
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
            // F-69: this warned about "-1 OVR drift", which was F-15's dead
            // channel — the penalty landed on `physical.stamina`, and stamina has
            // zero occurrences in any simulator file. D1 routed it into focus
            // instead, so the cost is real now and it is the same cost the rows
            // above already show. Say what it actually takes.
            Text("\(consecutiveOpponentWeeks) straight opponent-heavy weeks. The staff is stale on everything else: \(driftWeeksCharged) of them are being charged back at \(driftFocusPct) points of focus each, which is already in the numbers above.")
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

    /// This club's `gamePlanning` rating, or `nil` for a staff with no head
    /// coach on file — which `OpponentPrep.staffFocus` reads as exactly neutral,
    /// the same way `GameSimulator` does.
    private var staffGamePlanning: Double? {
        guard let teamID = career.teamID else { return nil }
        let staff = allCoachesUnscoped.filter {
            $0.careerID == career.id && $0.teamID == teamID
        }
        return CoachingModifiers.ratings(from: staff).gamePlanning
    }

    /// Where this week actually lands on the 0…1 focus scale.
    ///
    /// Composed exactly as `WeekAdvancer` composes it: the staff's own baseline,
    /// plus the slider as a SIGNED delta around the neutral 0.5, minus the drift
    /// the streak has already spent. Reading the same three terms through the
    /// same functions is what keeps this preview and the simulator from telling
    /// the user two different stories (§2.13, the arithmetic gate).
    private var weekFocus: Double {
        let slider = Double(opponentPctInt) / 100.0
        let drift = Double(
            -OpponentPrepEngine.driftPenalty(consecutiveOpponentWeeks: consecutiveOpponentWeeks)
        ) * OpponentPrep.driftFocusPerWeek
        return OpponentPrep.clampFocus(
            OpponentPrep.staffFocus(gamePlanning: staffGamePlanning)
                + (slider - OpponentPrep.neutralFocus)
                - drift
        )
    }

    /// Weeks of the streak the engine is actually charging, read from the same
    /// function `WeekAdvancer` reads.
    private var driftWeeksCharged: Int {
        -OpponentPrepEngine.driftPenalty(consecutiveOpponentWeeks: consecutiveOpponentWeeks)
    }

    /// `driftFocusPerWeek` on the same 0-100 scale the rest of the screen speaks.
    private var driftFocusPct: Int {
        Int((OpponentPrep.driftFocusPerWeek * 100).rounded())
    }

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
        prep.careerID = career.id
        modelContext.insert(prep)
        try? modelContext.save()
        didSave = true
    }
}
