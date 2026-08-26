import SwiftUI

// MARK: - Workload Dashboard
//
// Heat-map style grid of every active player with their current camp load.
//
// The shipped version was a heat-map with no heat and no map. Three defects,
// all of which this file now fixes:
//
//  * **No heat.** All four states filled at `tint.opacity(0.18)`, so the
//    "healthy" and "under-loaded" cells measured 1.04:1 against each other on
//    a dark page. The entire colour signal lived in a 1 pt stroke. The fill
//    ramps with the load itself now, and the state that means "nothing to see
//    here" recedes onto the flat surface colour instead of borrowing a tint.
//  * **No order.** `ForEach(roster)` walked an unsorted `FetchDescriptor`, so
//    the most-loaded man on the roster was cell 51 of 53 and the eight flagged
//    cells landed at scattered grid positions. It sorts heaviest-first, the
//    rule the sibling table already states in prose (`TrainingPlanView`).
//  * **No magnitude.** Every cell printed a position, a glyph and a surname —
//    comparing two players' load cost two sheet open/dismiss cycles. The load
//    is the cell's hero number now, on the engine's real 0…`burnoutFloor`
//    scale rather than the /100 the sheet used to imply.

struct WorkloadDashboard: View {

    let roster: [Player]

    @State private var selectedPlayer: Player?

    /// Adaptive rather than a hardcoded 5. Five flexible columns left 73–79 %
    /// of every cell empty on the iPad and pushed 53 men into 11 rows; at this
    /// minimum the whole roster fits on one screen, which is the only reason a
    /// heat-map beats a list.
    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 116), spacing: DSSpacing.xs)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                header
                legend
                grid
            }
            .padding(DSSpacing.md)
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("Workload")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedPlayer) { player in
            playerDetailSheet(for: player)
        }
    }

    // MARK: - Derived roster reads

    /// Heaviest load first, then the thinner margin — the same rule and the
    /// same reason as `TrainingPlanView.displayRoster`: the men this screen
    /// exists to warn about have to be the men the eye lands on first. Load is
    /// what `WorkloadEngine.classify` buckets on, so sorting by it also sorts
    /// by severity: burnt, then heavy, then healthy, then light.
    private var rankedRoster: [Player] {
        roster.sorted { lhs, rhs in
            if lhs.cumulativeLoad != rhs.cumulativeLoad {
                return lhs.cumulativeLoad > rhs.cumulativeLoad
            }
            return lhs.physical.durability < rhs.physical.durability
        }
    }

    /// The load at which a man reads Burnt — the engine's real full scale. The
    /// sheet used to print "42 / 100" against a denominator the camp scheduler
    /// cannot reach, so every reading looked like it had a third of the week
    /// still in hand.
    private var loadFullScale: Int { max(1, WorkloadEngine.burnoutFloor) }

    private func count(of status: WorkloadStatus) -> Int {
        roster.filter { $0.workloadStatus == status }.count
    }

    /// Men whose state actually multiplies their injury probability.
    private var atRiskCount: Int {
        roster.filter { $0.workloadStatus.addsInjuryRisk }.count
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeaderText(title: "Workload Heat-Map")
            // The tile that navigates here prints "X% overloaded"; the screen it
            // opened used to drop that number and tell the user to hunt for
            // "yellow / red flags" that on a normal camp week do not exist —
            // without ever saying that means all-clear rather than not-computed.
            Text(riskSummary)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(riskSummaryTint)
                .fixedSize(horizontal: false, vertical: true)
            Text("Camp load per player, heaviest first. Tap a cell for detail.")
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var riskSummary: String {
        guard !roster.isEmpty else { return "Nobody in camp yet." }
        guard atRiskCount > 0 else {
            return "Nobody is carrying added injury risk this week."
        }
        return "\(atRiskCount) of \(roster.count) players are carrying added injury risk."
    }

    private var riskSummaryTint: Color {
        guard !roster.isEmpty else { return Color.textSecondary }
        return atRiskCount > 0 ? Color.warning : Color.success
    }

    /// The legend doubles as the tally. Four coloured dots against four words
    /// that appeared in no cell was a key to a map the user then had to count
    /// himself; the counts are the reading a 20-season player wants, and worst
    /// first is the order he wants them in.
    private var legend: some View {
        HStack(spacing: DSSpacing.sm) {
            ForEach([WorkloadStatus.burnedOut, .overloaded, .healthy, .underloaded], id: \.self) { status in
                legendChip(for: status)
            }
            Spacer(minLength: 0)
        }
    }

    private func legendChip(for status: WorkloadStatus) -> some View {
        HStack(spacing: 4) {
            Image(systemName: status.symbolName)
                .font(.system(size: DSType.Size.caption))
                .foregroundStyle(tint(for: status))
            Text("\(status.displayLabel) \(count(of: status))")
                .font(DSType.display(DSType.Size.caption, .semibold))
                .foregroundStyle(Color.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count(of: status)) \(status.displayLabel)")
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: DSSpacing.xs) {
            ForEach(rankedRoster, id: \.id) { player in
                cell(for: player)
                    .contentShape(Rectangle())
                    .onTapGesture { selectedPlayer = player }
                    .accessibilityAddTraits(.isButton)
            }
        }
    }

    private func cell(for player: Player) -> some View {
        let status = player.workloadStatus
        let tint = tint(for: status)
        return VStack(alignment: .leading, spacing: 2) {
            // The surname leads. It used to be the smallest and dimmest thing
            // in the cell — 10 pt `textSecondary`, under the design system's own
            // 11 pt floor — while the eye landed first on a 20 pt hyphen and
            // then on a position abbreviation that repeats five times down the
            // grid. The name is the only string that says who this is.
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(player.lastName)
                    .font(DSType.display(DSType.Size.footnote, .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Text(player.position.rawValue)
                    .font(DSType.display(DSType.Size.caption, .bold))
                    .foregroundStyle(Color.textSecondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(player.cumulativeLoad)")
                    .font(DSType.display(DSType.Size.title3, .bold))
                    .foregroundStyle(tint)
                Spacer(minLength: 0)
                Image(systemName: status.symbolName)
                    .font(.system(size: DSType.Size.caption))
                    .foregroundStyle(tint)
                Text(status.displayLabel)
                    .font(DSType.display(DSType.Size.caption, .semibold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, DSSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                .fill(fill(for: player))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                .strokeBorder(strokeTint(for: status), lineWidth: status.addsInjuryRisk ? 1.5 : 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(player.position.rawValue) \(player.lastName), \(status.displayLabel), load \(player.cumulativeLoad) of \(loadFullScale)"
        )
    }

    /// Fill weight ramps with the load, not with the band.
    ///
    /// Two things were wrong with one flat `tint.opacity(0.18)` for all four
    /// states: the healthy and under-loaded fills were indistinguishable at
    /// arm's length, and inside a band the map said nothing at all — a man at
    /// 38 and a man at 63 are both "Healthy" and both painted identically. The
    /// ramp restores the gradient a heat-map is for. `.underloaded` opts out
    /// entirely and sits on the flat surface colour, because "nothing to see
    /// here" has to recede rather than compete for the same attention as a
    /// flagged man.
    private func fill(for player: Player) -> Color {
        let status = player.workloadStatus
        guard status != .underloaded else { return Color.backgroundSecondary }
        let ramp = Double(min(loadFullScale, max(0, player.cumulativeLoad))) / Double(loadFullScale)
        return tint(for: status).opacity(0.18 + 0.30 * ramp)
    }

    /// The stroke used to be the map's whole colour signal, which is why it was
    /// drawn at 0.7 alpha on every cell including the 45 that had nothing to
    /// say. Now that the fill carries the reading, the border is spent where it
    /// still buys something: full weight on the two flagged states, a hairline
    /// on healthy, and the plain surface border on the state that recedes.
    private func strokeTint(for status: WorkloadStatus) -> Color {
        switch status {
        case .underloaded: return Color.surfaceBorder
        case .healthy:     return Color.success.opacity(0.35)
        case .overloaded, .burnedOut: return tint(for: status).opacity(0.9)
        }
    }

    private func tint(for status: WorkloadStatus) -> Color {
        switch status {
        case .underloaded: return Color.textTertiary
        case .healthy:     return Color.success
        case .overloaded:  return Color.warning
        case .burnedOut:   return Color.danger
        }
    }

    // MARK: - Detail sheet

    private func playerDetailSheet(for player: Player) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                HStack(spacing: DSSpacing.sm) {
                    Text(player.position.rawValue)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: DSCornerRadius.tight)
                                .fill(Color.backgroundTertiary)
                        )
                    VStack(alignment: .leading) {
                        Text(player.fullName)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                        Text("OVR \(player.overall) · Age \(player.age)")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                statusRow(
                    label: "Status",
                    value: player.workloadStatus.displayLabel,
                    symbol: player.workloadStatus.symbolName,
                    tint: tint(for: player.workloadStatus)
                )
                statusRow(
                    label: "Camp load",
                    value: "\(player.cumulativeLoad) / \(loadFullScale)",
                    tint: tint(for: player.workloadStatus)
                )
                // "Injury multiplier ×1.6" is an engine term against an unstated
                // baseline. The percentage is derived from the same constant, so
                // the row cannot drift away from what the engine actually rolls.
                statusRow(
                    label: "Injury risk",
                    value: injuryRiskLabel(for: player.workloadStatus),
                    tint: player.workloadStatus.addsInjuryRisk ? Color.warning : Color.success
                )
                if let grade = player.campGrade {
                    VStack(alignment: .leading, spacing: 4) {
                        statusRow(
                            label: "Camp grade",
                            value: grade.displayLabel,
                            // Gold is the screen's primary-action colour — the
                            // Save plan button and the section heads wear it —
                            // and it was applied here unconditionally, so a D
                            // and an A+ were the same pixels and the D read as
                            // a commendation. `Color.forGrade` is the ladder
                            // every other letter in the app goes through.
                            tint: Color.forGrade(grade.displayLabel)
                        )
                        if let placing = gradePlacing(for: grade) {
                            Text(placing)
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                                .padding(.horizontal, DSSpacing.sm)
                        }
                    }
                }

                // The sheet was four read-only rows and a dead half-page: the
                // user tapped a cell after being told flags signal injury risk
                // and was handed numbers with nothing to do about them.
                Text(guidance(for: player.workloadStatus))
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()
            }
            .padding(DSSpacing.md)
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Workload Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { selectedPlayer = nil }
                }
            }
        }
        // `.large` joins `.medium` because the sheet carries a line of guidance
        // now; a Dynamic Type user must be able to grow it rather than lose the
        // sentence that says what to do about the reading.
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func injuryRiskLabel(for status: WorkloadStatus) -> String {
        guard status.addsInjuryRisk else { return "Normal" }
        let extra = Int(((status.injuryMultiplier - 1.0) * 100).rounded())
        return "+\(extra)% while \(status.displayLabel)"
    }

    /// Where the letter sits among the team-mates who also have one.
    ///
    /// A bare letter with no score, no components and no comparison cannot be
    /// checked — nothing distinguishes a 35-point D from a 49-point D, and
    /// `CampGradeEvaluator.scoreFor` is not persisted for the UI to print. The
    /// placing is the honest half: it is computed from the same roster the grid
    /// already holds, and it makes a flat curve visible instead of hiding it.
    private func gradePlacing(for grade: CampGrade) -> String? {
        let graded = roster.compactMap(\.campGrade)
        guard graded.count > 1 else { return nil }
        let beaten = graded.filter { $0.rank < grade.rank }.count
        return "Better than \(beaten) of \(graded.count) graded team-mates."
    }

    private func guidance(for status: WorkloadStatus) -> String {
        switch status {
        case .underloaded:
            return "He is doing less than a normal camp week. There is no penalty for it and no added injury risk — but there is room to work him harder."
        case .healthy:
            return "A normal camp week. He takes the full training gain and carries no added injury risk."
        case .overloaded:
            return "Ease his week off. Every injury roll he faces is 60% more likely to land while he reads Heavy."
        case .burnedOut:
            return "Rest him. Injury rolls are two and a half times more likely to land, and he absorbs only half of the week's training gains."
        }
    }

    private func statusRow(label: String, value: String, symbol: String? = nil, tint: Color) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            if let symbol {
                Image(systemName: symbol)
                    .font(.footnote)
                    .foregroundStyle(tint)
            }
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
        }
        .padding(DSSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                .fill(Color.backgroundSecondary)
        )
        .accessibilityElement(children: .combine)
    }
}
