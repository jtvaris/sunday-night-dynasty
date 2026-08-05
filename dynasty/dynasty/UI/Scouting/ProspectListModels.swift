import SwiftUI
import SwiftData

// MARK: - Prospect list models
//
// What survives `ProspectListView`.
//
// The hub used to render the same `[CollegeProspect]` twice: a "Prospects" tab
// and a "Big Board" tab, over one dataset, with the same attribute-mode picker
// declared in one file and re-hosted as `@State` in both. The board is the
// richer surface (tiers, My Board, the compare tray, `.onMove` reordering,
// board-vs-media comparison) and the list was a strictly weaker subset of it,
// so the list is gone and the board absorbed its one unique mode.
//
// These types outlived it because other screens hold them: the attribute mode
// and the position filter are the hub's shared bindings, the market arrow and
// the declaration chip are board-row cells, and the compare sheet is opened
// from both the board and the draft-night pick sheet.

// MARK: - Attribute View Tab

/// Which block of columns a prospect table renders to the right of the name.
enum ProspectAttributeTab: String, CaseIterable, Identifiable {
    case overview, workup, physical, mental, position

    var id: String { rawValue }

    var label: String {
        switch self {
        case .overview: return "Overview"
        case .workup:   return "Work-up"
        case .physical: return "Physical"
        case .mental:   return "Mental"
        case .position: return "Position"
        }
    }

    var icon: String {
        switch self {
        case .overview: return "list.bullet"
        case .workup:   return "checklist"
        case .physical: return "figure.run"
        case .mental:   return "brain.head.profile"
        case .position: return "figure.american.football"
        }
    }
}

// MARK: - Supporting Enums

enum ProspectPositionFilter: String, CaseIterable, Identifiable {
    case all
    case qb, rb, wr, te, ol, dl, lb, db

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .qb:  return "QB"
        case .rb:  return "RB"
        case .wr:  return "WR"
        case .te:  return "TE"
        case .ol:  return "OL"
        case .dl:  return "DL"
        case .lb:  return "LB"
        case .db:  return "DB"
        }
    }

    func matches(_ position: Position) -> Bool {
        switch self {
        case .all: return true
        case .qb:  return position == .QB
        case .rb:  return position == .RB || position == .FB
        case .wr:  return position == .WR
        case .te:  return position == .TE
        case .ol:  return [.LT, .LG, .C, .RG, .RT].contains(position)
        case .dl:  return position == .DE || position == .DT
        case .lb:  return position == .OLB || position == .MLB
        case .db:  return position == .CB || position == .FS || position == .SS
        }
    }
}

enum ProspectSort: String, CaseIterable, Identifiable {
    case draftProjection, scoutedOverall, footballIQ, position, name

    var id: String { rawValue }

    var label: String {
        switch self {
        case .draftProjection: return "Draft Projection"
        case .scoutedOverall:  return "Scouted Overall"
        case .footballIQ:      return "Football IQ"
        case .position:        return "Position"
        case .name:            return "Name"
        }
    }

    var icon: String {
        switch self {
        case .draftProjection: return "list.number"
        case .scoutedOverall:  return "star.fill"
        case .footballIQ:      return "brain.head.profile"
        case .position:        return "rectangle.3.group"
        case .name:            return "textformat"
        }
    }
}

// MARK: - Round / grade formatting

/// The two pure formatters the deleted row view owned, kept because the board
/// row calls both. Free functions on an enum rather than statics on a `View`,
/// so nothing has to instantiate a row to format a round.
enum ProspectRoundFormat {

    /// Maps letter grades to numeric ranks for comparison (higher = better).
    static func gradeRank(_ grade: String) -> Int {
        switch grade {
        case "A+": return 13
        case "A":  return 12
        case "A-": return 11
        case "B+": return 10
        case "B":  return 9
        case "B-": return 8
        case "C+": return 7
        case "C":  return 6
        case "C-": return 5
        case "D+": return 4
        case "D":  return 3
        case "D-": return 2
        case "F":  return 1
        default:   return 0
        }
    }

    /// Maps a projected draft round (1-7) to a display label.
    /// Note: `draftProjection` stores a round number (1-7), not a pick number.
    static func projectedRoundText(for round: Int?) -> String {
        guard let round = round else { return "UDFA" }
        switch round {
        case 1...7: return "Rd \(round)"
        default:    return "UDFA"
        }
    }
}

// MARK: - Market arrow (task #78)

/// How far the MEDIA has moved a prospect since the class was generated.
///
/// The board already had one arrow — `stockTrajectory` / the pre-combine grade
/// diff — but that one is YOUR scouts changing their mind. This is the other
/// half of the same picture and it is the half a GM actually trades on: the
/// consensus is a separate opinion now (`CollegeProspect.consensusErrorStored`),
/// it moves all spring on the Senior Bowl, the combine, four mocks and the
/// pro-day circuit, and a man whose public round has slid two rounds while your
/// own grade held is exactly the man you want at the price the room is asking.
///
/// Renders nothing at all when the market has not moved him, so a board full of
/// arrows means something.
struct ProspectMarketArrow: View {
    let prospect: CollegeProspect
    var font: Font = .system(size: 9, weight: .heavy)

    var body: some View {
        if let move = prospect.marketMove, move != 0 {
            Text("\(move > 0 ? "\u{25B2}" : "\u{25BC}")\(abs(move))")
                .font(font)
                .foregroundStyle(move > 0 ? Color.accentBlue : Color.warning)
                .lineLimit(1)
                .accessibilityLabel(
                    move > 0
                        ? "media board has him up \(abs(move)) rounds since the class opened"
                        : "media board has him down \(abs(move)) rounds since the class opened"
                )
        }
    }
}

// MARK: - Declaration chip (task #78, finding S11)

/// Whether an underclassman is even in this draft.
///
/// `isDeclaringForDraft` carries a model default of `true`, so from September to
/// January every board in the game showed all ~175 underclassmen as locks — and
/// roughly 100 of them never come out. The chip shows the PUBLIC read
/// (`CollegeProspect.declarationLikelihood`, built from class year and college
/// production, never from the hidden rating) until the window closes in January,
/// and the decision itself after.
struct ProspectDeclarationChip: View {
    let prospect: CollegeProspect

    var body: some View {
        switch prospect.declarationStatus {
        case .undecided:
            if let likelihood = prospect.declarationLikelihood {
                chip(likelihood.shortLabel, likelihood.color)
                    .accessibilityLabel("declaration \(likelihood.rawValue)")
            }
        case .withdrawn:
            chip("OUT", Color.danger)
                .accessibilityLabel("withdrew from the draft")
        case .declared:
            EmptyView()
        }
    }

    private func chip(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 7, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(color.opacity(0.55), lineWidth: 0.5)
            )
    }
}

// MARK: - Prospect Compare Sheet

/// Side-by-side comparison of two to four prospects.
///
/// ## Two things were wrong with the old sheet
///
/// It printed a **"Physical (True)"** section straight off
/// `prospect.truePhysical` — speed 91, strength 78, durability 44 — for men the
/// user had never scouted. Every other surface in the game runs its numbers
/// through `ProspectFog`; this one handed over the generator's own attribute
/// block, which made the compare tool the cheapest scouting in the build. It
/// leaked the header too, printing `scoutedOverall` as a bare number where the
/// rest of the game shows a grade band.
///
/// It also capped at two. A draft board is a series of "which of these three do
/// I take" questions, and a two-way compare answers none of them.
///
/// Everything here now comes from the same two legitimate sources as the rest
/// of the draft UI: the user's own scouting (grade bands, mental / position
/// grade ranges) and public combine measurables, at the fidelity
/// `ProspectFog.combineFidelity` allows.
struct ProspectCompareSheet: View {
    /// Four columns is the cap: a fifth does not fit a portrait iPad, and a
    /// five-way compare is not a decision anybody actually makes.
    static let maxProspects = 4

    let career: Career
    let prospects: [CollegeProspect]
    /// Scheme fit per prospect id, computed by the calling screen (it owns the
    /// coordinator lookup).
    var schemeFits: [UUID: String] = [:]
    /// "vs Starter" line per prospect id.
    var starterComparisons: [UUID: String] = [:]
    let onDismiss: () -> Void

    private var columns: [CollegeProspect] {
        Array(prospects.prefix(Self.maxProspects))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    headerRow
                    compareSection(title: "Overview", rows: overviewRows)
                    compareSection(title: "Measurables", rows: measurableRows)
                    compareSection(title: "Mental Grades", rows: mentalRows)
                    compareSection(title: "Position Skills", rows: positionRows)
                    compareSection(title: "Scouting", rows: scoutingRows)
                    fogFootnote
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Compare \(columns.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { onDismiss() }
                        .foregroundStyle(Color.accentGold)
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(columns) { prospect in
                prospectHeaderColumn(prospect: prospect)
            }
        }
    }

    private func prospectHeaderColumn(prospect: CollegeProspect) -> some View {
        VStack(spacing: 4) {
            Text(prospect.position.rawValue)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.textPrimary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(positionColor(for: prospect), in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))
            Text(prospect.fullName)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
            Text(prospect.college)
                .font(.caption2)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            ProspectMarkChip(mark: prospect.userMark)

            // The grade the user is entitled to, not the number the engine
            // knows: gold when it is his own scouts' read, grey when it is
            // only the media's projected round.
            let read = ProspectFog.read(prospect)
            VStack(spacing: 1) {
                Text(read.text)
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(read.source.tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(read.source.label.uppercased())
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Color.textTertiary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(read.accessibilityText)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 10))
    }

    private var fogFootnote: some View {
        Text("Gold values are your own scouting. Grey values are public \u{2014} the media's projected round and whatever the broadcast showed at the combine. A \"?\" is work nobody in your building has done yet.")
            .font(.caption2)
            .foregroundStyle(Color.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }

    // MARK: - Section

    private func compareSection(title: String, rows: [CompareRow]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.heavy))
                .foregroundStyle(Color.accentBlue)
            VStack(spacing: 4) {
                ForEach(rows) { row in
                    compareRowView(row: row)
                }
            }
            .padding(8)
            .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func compareRowView(row: CompareRow) -> some View {
        HStack(spacing: 6) {
            Text(row.label)
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(Color.textTertiary)
                .frame(width: 66, alignment: .leading)
            ForEach(Array(row.values.enumerated()), id: \.offset) { index, value in
                Text(value)
                    .font(.caption.monospacedDigit())
                    .fontWeight(row.bestIndices.contains(index) ? .heavy : .medium)
                    .foregroundStyle(row.bestIndices.contains(index) ? Color.success : Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.label): \(row.values.joined(separator: ", "))")
    }

    // MARK: - Rows

    private struct CompareRow: Identifiable {
        let id = UUID()
        let label: String
        let values: [String]
        /// Columns to highlight. Empty when the row has no "better".
        var bestIndices: Set<Int> = []
    }

    /// Builds a row from a per-prospect value plus an optional score used to
    /// pick the winners. `nil` scores never win, so an unknown never beats a
    /// known — the highlight can no longer leak "the one you haven't scouted
    /// is the good one".
    private func row(
        _ label: String,
        _ text: (CollegeProspect) -> String,
        score: ((CollegeProspect) -> Int?)? = nil,
        higherIsBetter: Bool = true
    ) -> CompareRow {
        let values = columns.map(text)
        guard let score else { return CompareRow(label: label, values: values) }
        let scores = columns.map(score)
        let known = scores.compactMap { $0 }
        guard known.count >= 2 else { return CompareRow(label: label, values: values) }
        guard let best = higherIsBetter ? known.max() : known.min() else {
            return CompareRow(label: label, values: values)
        }
        // A row where everybody ties has no winner to point at.
        guard known.contains(where: { $0 != best }) else {
            return CompareRow(label: label, values: values)
        }
        var winners: Set<Int> = []
        for (index, value) in scores.enumerated() where value == best { winners.insert(index) }
        return CompareRow(label: label, values: values, bestIndices: winners)
    }

    private var overviewRows: [CompareRow] {
        [
            row("AGE", { "\($0.age)" }, score: { $0.age }, higherIsBetter: false),
            row("HT", { heightString($0.height) }),
            row("WT", { "\($0.weight)" }),
            row("PROD",
                { $0.collegeProductionTier.displayName },
                score: { -$0.collegeProductionTier.sortRank }),
            row("PROJ RD", { $0.draftProjection.map { "Rd \($0)" } ?? "\u{2014}" },
                score: { $0.draftProjection }, higherIsBetter: false),
            row("MY MARK", { $0.isMarked ? $0.userMark.label : "\u{2014}" },
                score: { prospect -> Int? in
                    guard prospect.isMarked else { return nil }
                    return -prospect.userMark.sortRank
                }),
            row("FIT", { schemeFits[$0.id] ?? "\u{2014}" },
                score: { schemeFits[$0.id].map { fit in fit == "Good" ? 2 : (fit == "Fair" ? 1 : 0) } }),
            row("RISK", { riskString($0.riskLevel) }),
            row("vs STARTER", { starterComparisons[$0.id] ?? "\u{2014}" })
        ]
    }

    /// Height, weight and the combine card — public the moment a man runs in
    /// front of thirty-two clubs, and only then. This replaced the old
    /// "Physical (True)" block, which read the generator's attributes directly.
    private var measurableRows: [CompareRow] {
        func measurable(
            _ label: String,
            _ text: @escaping (CollegeProspect, ProspectFog.MeasurableFidelity) -> String?,
            score: ((CollegeProspect) -> Int?)? = nil,
            higherIsBetter: Bool = true
        ) -> CompareRow {
            row(
                label,
                { prospect in
                    guard ProspectFog.showsMeasurables(prospect) else { return "?" }
                    let fidelity = ProspectFog.combineFidelity(for: prospect)
                    return text(prospect, fidelity) ?? "\u{2014}"
                },
                score: score.map { scorer in
                    { prospect in ProspectFog.showsMeasurables(prospect) ? scorer(prospect) : nil }
                },
                higherIsBetter: higherIsBetter
            )
        }

        return [
            measurable("40 YD", { ProspectFog.fortyText($0.fortyTime, fidelity: $1) },
                       score: { $0.fortyTime.map { Int($0 * 100) } }, higherIsBetter: false),
            measurable("BENCH", { ProspectFog.benchText($0.benchPress, fidelity: $1) },
                       score: { $0.benchPress }),
            measurable("VERT", { ProspectFog.verticalText($0.verticalJump, fidelity: $1) },
                       score: { $0.verticalJump.map { Int($0 * 10) } }),
            measurable("BROAD", { ProspectFog.broadJumpText($0.broadJump, fidelity: $1) },
                       score: { $0.broadJump }),
            measurable("3-CONE", { ProspectFog.agilityText($0.coneDrill, fidelity: $1) },
                       score: { $0.coneDrill.map { Int($0 * 100) } }, higherIsBetter: false),
            measurable("SHUTTLE", { ProspectFog.agilityText($0.shuttleTime, fidelity: $1) },
                       score: { $0.shuttleTime.map { Int($0 * 100) } }, higherIsBetter: false),
            measurable("DRILL", { ProspectFog.drillGradeText($0.positionDrillGrade, fidelity: $1) },
                       score: { $0.positionDrillGrade.flatMap { LetterGrade(rawValue: $0)?.rank } })
        ]
    }

    private var mentalRows: [CompareRow] {
        let keys = ["AWR", "DEC", "WRK", "CLT", "COA", "LDR", "LRN", "CMP"]
        var rows = keys.map { key in
            row(
                key,
                { $0.scoutedMentalGrades?[key]?.displayText ?? "?" },
                score: { $0.scoutedMentalGrades?[key]?.midGrade.rank }
            )
        }
        // TAPE and MEET are two instruments answering two questions, so they are
        // two rows here exactly as they are two columns on the board.
        rows.insert(
            row(
                "MEET IQ",
                { ProspectFog.meetRead($0).text },
                score: { prospect in
                    let read = ProspectFog.meetRead(prospect)
                    return read.source == .none ? nil : read.rank
                }
            ),
            at: 0
        )
        rows.insert(
            row(
                "TAPE IQ",
                { ProspectFog.tapeRead($0).text },
                score: { prospect in
                    let read = ProspectFog.tapeRead(prospect)
                    return read.source == .none ? nil : read.rank
                }
            ),
            at: 0
        )
        return rows
    }

    private var positionRows: [CompareRow] {
        // Only meaningful when every column shares a position.
        let positions = Set(columns.map(\.position))
        guard positions.count == 1, let first = columns.first else {
            return [CompareRow(label: "NOTE", values: columns.map { $0.position.rawValue })]
        }
        return positionSkillKeys(for: first).map { key in
            row(
                key,
                { $0.scoutedPositionGrades?[key]?.displayText ?? "?" },
                score: { $0.scoutedPositionGrades?[key]?.midGrade.rank }
            )
        }
    }

    private var scoutingRows: [CompareRow] {
        [
            row("REPORTS", { "\($0.scoutReportCount)" }, score: { $0.scoutReportCount }),
            row("INTERVIEW", { $0.interviewCompleted ? "Yes" : "No" },
                score: { $0.interviewCompleted ? 1 : 0 }),
            row("PRO DAY", { $0.proDayCompleted ? "Yes" : "No" },
                score: { $0.proDayCompleted ? 1 : 0 }),
            row("COMBINE", { $0.combineInvite ? "Invited" : "\u{2014}" }),
            row("FLAGS", { flagSummary(for: $0) })
        ]
    }

    // MARK: - Helpers

    /// Medical / character flags at the disclosure the user has earned. Never
    /// the contents here — the compare sheet is a scan, and the file itself
    /// lives on the prospect card.
    private func flagSummary(for prospect: CollegeProspect) -> String {
        let total = (prospect.medicalConcerns?.count ?? 0) + (prospect.redFlags?.count ?? 0)
        switch ProspectFog.flagDisclosure(for: prospect, userTeamID: career.teamID) {
        case .hidden: return "?"
        case .count:  return total == 0 ? "None" : "\(total) on file"
        case .full:   return total == 0 ? "Clean" : "\(total)"
        }
    }

    private func positionSkillKeys(for prospect: CollegeProspect) -> [String] {
        switch prospect.truePositionAttributes {
        case .quarterback:    return ["ARM", "SAc", "DAc", "PKT"]
        case .wideReceiver:   return ["RTE", "CTH", "RLS", "SPC"]
        case .runningBack:    return ["VIS", "ELU", "BTK", "RCV"]
        case .tightEnd:       return ["BLK", "CTH", "RTE", "SPD"]
        case .offensiveLine:  return ["RBK", "PBK", "PUL", "ANC"]
        case .defensiveLine:  return ["PRU", "BSH", "PWR", "FIN"]
        case .linebacker:     return ["TAK", "ZCV", "MCV", "BLZ"]
        case .defensiveBack:  return ["MCV", "ZCV", "PRS", "BSK"]
        case .kicking:        return ["PWR", "ACC"]
        }
    }

    private func heightString(_ inches: Int) -> String {
        let ft = inches / 12
        let inch = inches % 12
        return "\(ft)'\(inch)\""
    }

    private func riskString(_ risk: ProspectRiskLevel) -> String {
        switch risk {
        case .safePick:    return "Safe"
        case .highCeiling: return "Ceiling"
        case .boomOrBust:  return "Boom/Bust"
        case .unknown:     return "?"
        }
    }

    private func positionColor(for prospect: CollegeProspect) -> Color {
        switch prospect.position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }
}
