import SwiftUI

// MARK: - Shared prospect-list controls
//
// ONE control strip, worn by every prospect table.
//
// The Big Board grew these controls first and nothing else inherited them. The
// position chips were hoisted into `ScoutingHubView` (one tap filters the board,
// the film screen and the combine table together), but the column-block picker
// stayed a `private var` on `BigBoardView` — so the combine table shipped as a
// single frozen column set, with no way to ask it "who have I not worked up" or
// "who have I not been in a room with". A user who learned the board's controls
// then found half of them missing one tab to the right.
//
// Everything here takes BINDINGS and owns no state. That is the load-bearing
// rule: the hub keeps THREE deliberately separate filter states — the shared
// position chips, the board's mark filter, and the board's own round / risk
// menu — and folding any two of them behind one control is exactly the bug the
// hub's chip hoist was written to fix. A shared control that owned the
// selection would re-merge them the moment a second list adopted it.

/// The position chip row: All / QB / RB / WR / TE / OL / DL / LB / DB.
///
/// Verbatim the hub's chip bar, extracted so a list that is NOT hosted under it
/// (a pro-day list, a workout list) can wear the same control instead of
/// inventing a fourth position filter.
struct ProspectPositionChips: View {
    @Binding var selection: ProspectPositionFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(ProspectPositionFilter.allCases) { filter in
                    let isSelected = selection == filter
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selection = filter
                        }
                    } label: {
                        Text(filter.label)
                            .font(.system(size: 12, weight: isSelected ? .heavy : .medium))
                            .foregroundStyle(isSelected ? Color.backgroundPrimary : Color.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                isSelected ? Color.accentBlue : Color.backgroundTertiary,
                                in: Capsule()
                            )
                            .overlay(
                                Capsule().strokeBorder(
                                    isSelected ? Color.clear : Color.surfaceBorder,
                                    lineWidth: 1
                                )
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(filter == .all
                                        ? "Show all positions"
                                        : "Filter to \(filter.label)")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
        .mask(
            HStack(spacing: 0) {
                Color.white
                LinearGradient(colors: [.white, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 20)
            }
        )
    }
}

/// The column-block picker: Overview / Work-up / Physical / Mental / Position.
///
/// `modes` is a parameter because not every table can answer every question with
/// the same block — the combine's home block is its drills, the board's is the
/// overview — but the control, the order and the look are one thing everywhere.
struct ProspectModeChips: View {
    @Binding var mode: ProspectAttributeTab
    var modes: [ProspectAttributeTab] = ProspectAttributeTab.allCases
    /// The chrome the strip sits on.
    ///
    /// A parameter because the hosts do not share one background: the board
    /// pins the strip over `backgroundPrimary`, the combine table pins it
    /// inside a `backgroundSecondary` section header, and the two selection
    /// lists pin it against their own `backgroundTertiary` action bar. The
    /// hard-coded primary drew a visible seam across the combine's pinned
    /// header — a strip of a different colour than the column labels directly
    /// under it. Default keeps the board's look.
    var background: Color = .backgroundPrimary

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(modes) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            mode = tab
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 10))
                            Text(tab.label)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .foregroundStyle(mode == tab ? Color.backgroundPrimary : Color.textSecondary)
                        .background(
                            mode == tab ? Color.accentBlue : Color.backgroundTertiary,
                            in: Capsule()
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    mode == tab ? Color.accentBlue : Color.surfaceBorder,
                                    lineWidth: 1
                                )
                        )
                    }
                    .accessibilityLabel("View mode: \(tab.label)")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .background(background)
    }
}

/// The strip a prospect list pins above its column headers.
///
/// `showsPositionChips` is off by default because the three tables the scouting
/// hub hosts already sit under the hub's own chip bar, and two identical chip
/// rows stacked on one screen is a worse bug than the missing control was. A
/// list hosted anywhere else turns it on and passes the same binding.
struct ProspectListControls: View {
    @Binding var positionFilter: ProspectPositionFilter
    @Binding var mode: ProspectAttributeTab
    var modes: [ProspectAttributeTab] = ProspectAttributeTab.allCases
    var showsPositionChips: Bool = false
    /// The chrome the strip sits on. See ``ProspectModeChips/background``.
    /// `CombineResultsView` should pass `Color.backgroundSecondary` — its host
    /// is a pinned section header drawn on secondary, and the primary default
    /// draws a seam straight across it.
    var background: Color = .backgroundPrimary

    var body: some View {
        VStack(spacing: 0) {
            if showsPositionChips {
                ProspectPositionChips(selection: $positionFilter)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 4)
            }
            if !modes.isEmpty {
                ProspectModeChips(mode: $mode, modes: modes, background: background)
            }
        }
        .background(background)
    }
}

// MARK: - Shared table cells
//
// The cell shapes a prospect table's attribute blocks are built from. They
// were private helpers on `BigBoardRowView`; a second table rendering the
// same blocks means one definition or two that drift.
//
// There is deliberately NO revealed-integer cell here: a raw 0-99 attribute
// is generator truth no instrument ever discloses (the #110/#114 fog audit),
// so the shared vocabulary only speaks in fogged measurables and grade bands.

/// A scouted grade BAND over its column label — "B" when the department is
/// certain, "C+/A-" when it is not, "?" when nobody has filed on him.
struct ProspectGradeBandCell: View {
    let grade: GradeRange?
    let label: String

    var body: some View {
        VStack(spacing: 0) {
            if let grade {
                Text(grade.displayText)
                    .font(.system(size: grade.isSingleGrade ? 10 : 8, weight: .bold))
                    .foregroundStyle(PositionGradeCalculator.gradeColorForLetter(grade.midGrade.rawValue))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text("?")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
            }
            Text(label)
                .font(.system(size: 7, weight: .medium))
                .foregroundStyle(Color.textTertiary)
        }
    }
}

/// A yes/no fact about the WORK, drawn dim rather than blank when it has not
/// been done — the hole is the thing the user is scanning for.
struct ProspectWorkTick: View {
    let done: Bool
    var tint: Color = .success

    var body: some View {
        Image(systemName: done ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 11))
            .foregroundStyle(done ? tint : Color.textTertiary.opacity(0.35))
            .accessibilityHidden(true)
    }
}

/// One measurable over its column label.
///
/// A blank cell is two different facts and the cell says which: "?" when nobody
/// has measured him where you could see it, an em-dash when he was there and did
/// not run that drill. The tint carries the other half of the fog — a hard
/// number your own people took reads at full strength, a rounded broadcast
/// figure reads back, matching the "~" the `ProspectFog` helper prefixes.
struct ProspectMeasurableCell: View {
    let value: String?
    let label: String
    let fidelity: ProspectFog.MeasurableFidelity
    var empty: String = "\u{2014}"

    var body: some View {
        VStack(spacing: 0) {
            Text(value ?? empty)
                .font(.system(size: 10, weight: .bold).monospacedDigit())
                .foregroundStyle(
                    value == nil
                        ? Color.textTertiary
                        : (fidelity == .full ? Color.textPrimary : Color.textTertiaryReadable)
                )
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(label)
                .font(.system(size: 7, weight: .medium))
                .foregroundStyle(Color.textTertiary)
        }
        .frame(width: prospectMeasurableWidth, alignment: .center)
    }
}

/// The overall band a table may print for a man, exactly as the Big Board's OVR
/// column reads it: `ProspectFog.read`, accepted only when it came from THIS
/// building's scouts.
///
/// Reading `CollegeProspect.effectiveOverallGrade` straight prints the raw
/// stored range, which is TIGHTER than the department's actual certainty
/// (`ProspectFog.read` widens it by `DraftIntel.scoutConfidence`), and falling
/// through to the media's projected-round band labels the league's guess as work
/// the user paid for. `trueOverall` is never touched on either path.
struct ProspectScoutBandCell: View {
    let prospect: CollegeProspect
    var width: CGFloat = 50
    /// Drawn as the board draws it, with the stock-trajectory chevron.
    var showsTrajectory: Bool = true

    var body: some View {
        let read = ProspectFog.read(prospect)
        Group {
            if read.source == .scouts, let band = read.band {
                DualGradeDisplay(
                    prospectID: prospect.id,
                    scoutGradeText: band.displayText,
                    scoutGradeColor: PositionGradeCalculator.gradeColorForLetter(band.midGrade.rawValue),
                    trajectory: showsTrajectory ? prospect.stockTrajectory : nil
                )
            } else {
                Text("?")
                    .font(.callout.weight(.bold))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .frame(width: width, alignment: .center)
    }
}

/// The RISK badge, as the board's Overview block draws it.
struct ProspectRiskBadge: View {
    let risk: ProspectRiskLevel

    var body: some View {
        if risk != .unknown {
            HStack(spacing: 2) {
                Image(systemName: risk.icon)
                    .font(.system(size: 8))
                Text(Self.label(risk))
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Self.tint(risk).opacity(0.85), in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))
        } else {
            Text("--")
                .font(.system(size: 9))
                .foregroundStyle(Color.textTertiary)
        }
    }

    static func label(_ risk: ProspectRiskLevel) -> String {
        switch risk {
        case .safePick:    return "Safe"
        case .highCeiling: return "Ceiling"
        case .boomOrBust:  return "Boom/Bust"
        case .unknown:     return "--"
        }
    }

    static func tint(_ risk: ProspectRiskLevel) -> Color {
        switch risk {
        case .boomOrBust:  return .danger
        case .highCeiling: return .accentBlue
        case .safePick:    return .success
        case .unknown:     return .textTertiary
        }
    }
}

/// The position chip the two batch-selection lists wear.
///
/// Deliberately NOT the board's badge: the board tints by side at full strength
/// inside a 36×24 block, the selection lists use the softer 25 % wash. One
/// definition for the two lists that share the look; the board keeps its own.
struct ProspectSelectionPositionBadge: View {
    let position: Position

    var body: some View {
        Text(position.rawValue)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color.textPrimary)
            .frame(width: 32, height: 20)
            .background(RoundedRectangle(cornerRadius: 3).fill(Self.tint(position)))
            .frame(width: 36)
    }

    static func tint(_ position: Position) -> Color {
        switch position.side {
        case .offense:      return Color.accentGold.opacity(0.25)
        case .defense:      return Color.accentBlue.opacity(0.25)
        case .specialTeams: return Color.textTertiary.opacity(0.25)
        }
    }
}

// MARK: - Shared row identity block
//
// Portrait, name, the ONE mark, the user's own grade, and the two public facts
// a prospect row is scanned by: where he played and where the media has him.
//
// The Big Board grew this shape first; the interview and film-study selection
// lists shipped with a strictly poorer version of it (no portrait, no grade
// badge, college and round missing or buried). Extracted rather than copied so
// the third list that wants it does not become a fourth definition.

/// Name column for a prospect row: portrait + name + mark + my grade over
/// college · projected round, with a slot for whatever else the host's row
/// needs to say on that second line.
struct ProspectRowIdentity<Detail: View>: View {
    let prospect: CollegeProspect
    /// The "My: B+" capsule. Off for a host that prints the user's grade in a
    /// column of its own.
    var showsUserGrade: Bool = true
    private let detail: Detail

    init(
        prospect: CollegeProspect,
        showsUserGrade: Bool = true,
        @ViewBuilder detail: () -> Detail
    ) {
        self.prospect = prospect
        self.showsUserGrade = showsUserGrade
        self.detail = detail()
    }

    var body: some View {
        HStack(spacing: 0) {
            // The same portrait the board rows render — 30 pt, which is the
            // content height of a two-line row, so adding it does not change
            // the list's rhythm.
            PersonFaceView(prospect: prospect, size: .small)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(prospect.fullName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)

                    ProspectMarkChip(
                        mark: prospect.userMark,
                        showsNote: !prospect.userMarkNote.isEmpty
                    )

                    if showsUserGrade {
                        UserGradeBadge(prospectID: prospect.id)
                    }
                }

                HStack(spacing: 5) {
                    Text(prospect.college)
                        .font(.system(size: DSType.Size.micro))
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)
                    // The MEDIA's projected round — public information, the same
                    // number the board's PROJ column and the consensus order
                    // read. Never `trueOverall`.
                    if let round = prospect.draftProjection {
                        Text("Rd\(round)")
                            .font(.system(size: DSType.Size.micro, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Color.textTertiary)
                    }
                    detail
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 6)
        }
    }
}

extension ProspectRowIdentity where Detail == EmptyView {
    init(prospect: CollegeProspect, showsUserGrade: Bool = true) {
        self.init(prospect: prospect, showsUserGrade: showsUserGrade) { EmptyView() }
    }
}

// MARK: - Shared column vocabulary
//
// ONE definition of the five column blocks the mode chips switch between.
//
// They were `private var`s on `BigBoardRowView`, which is why the two batch
// selection lists shipped with a frozen five-column set and no way to ask a
// list "who have I not worked up" or "what did he run". Everything here is
// rendered from the same fogged accessors the board used: `ProspectFog` for
// measurables, flag disclosure and the position-skill key table, scouted grade
// BANDS for mental and position, and nothing anywhere that touches
// `truePhysical` / `trueMental` / `trueOverall`.
//
// They are `@ViewBuilder` statics rather than a `View` struct on purpose: a
// block has to flatten into its host's `HStack` as N sibling columns, which is
// what the board's inline `switch` did. Wrapping them in a view type would make
// the whole block one child and re-flow every board row.

/// The Physical block's six columns — the COMBINE CARD, in the order the week
/// runs the drills.
///
/// It used to be SPD / STR / AGI / ACC / STA / DUR read straight off
/// `prospect.truePhysical`: the generator's own attribute block, printed as raw
/// 40-99 numbers, gated on nothing but "has a 40 time on file". No instrument in
/// this game reveals `truePhysical`. What the combine reveals is MEASUREMENTS,
/// and `ProspectFog.combineFidelity` decides how precisely this club may read
/// them.
///
/// Strength, stamina and durability have no fog-safe source at all — nobody
/// measures a man's durability in front of thirty-two clubs — so they are gone
/// rather than approximated off the truth. The bench press is the strength
/// column the week actually produces.
let prospectMeasurableLabels = ["40YD", "BENCH", "VERT", "BROAD", "3CONE", "SHUT"]

/// One drill column. Wider than the 32 pt attribute cells it replaced because
/// "~4.5" and "126" are four glyphs where "91" was two.
let prospectMeasurableWidth: CGFloat = 38

/// What a column block needs that lives on the HOST rather than on the prospect.
///
/// Every field is optional or defaulted, because the three tables know different
/// amounts: the board has coordinators and a roster, the film-study order screen
/// has neither. A host that cannot answer a column says so (`knows…` false →
/// the cell prints an em-dash) rather than letting the block invent a default.
struct ProspectColumnContext {
    /// The host's scheme-fit verdict, or `nil` for a man its coordinators have
    /// no opinion on.
    var schemeFit: String? = nil
    /// `false` when the host has no coordinators loaded at all. The FIT cell
    /// then prints "\u{2014}" instead of the board's "Fair" default, which
    /// would otherwise be a fabricated verdict.
    var knowsSchemeFit: Bool = true
    /// "High" / "Med" / "Set".
    var needLevel: String = "Set"
    /// `false` when the host has no roster loaded.
    var knowsNeeds: Bool = true
    /// Drops RISK out of the Overview block for a host that pins risk in its own
    /// always-visible trailing block, so the fact is not printed twice.
    var includesRisk: Bool = true
    /// The user's own club — the only team whose Top-30 visit tells him anything.
    var userTeamID: UUID? = nil
    /// Whether the department went to Indianapolis. `nil` lets
    /// `ProspectFog.combineFidelity` fall back to the career-scoped flag, which
    /// is what a screen that does not thread the decision through its
    /// initialiser wants — passing a hard `false` there would DOWN-grade a club
    /// that did send its scouts to broadcast precision.
    var scoutsSentToCombine: Bool? = nil
    /// Reports on file, when the host already caches the number per prospect.
    /// `nil` reads it off the prospect (the board's behaviour). Supplying it
    /// keeps a list whose own RPTS column uses a cached count from printing two
    /// different numbers for the same man on the same row.
    var reportCount: Int? = nil
}

enum ProspectColumns {

    // MARK: Cells

    /// The mode's column block for one prospect row.
    @ViewBuilder
    static func cells(
        for prospect: CollegeProspect,
        mode: ProspectAttributeTab,
        context: ProspectColumnContext = ProspectColumnContext()
    ) -> some View {
        switch mode {
        case .overview: overviewCells(prospect, context)
        case .workup:   workupCells(prospect, context)
        case .physical: physicalCells(prospect, context)
        case .mental:   mentalCells(prospect)
        case .position: positionCells(prospect)
        }
    }

    @ViewBuilder
    private static func overviewCells(
        _ prospect: CollegeProspect,
        _ context: ProspectColumnContext
    ) -> some View {
        Group {
            // Age is public biography, not a scouted attribute.
            Text("\(prospect.age)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Color.textSecondary)
                .frame(width: 28, alignment: .center)

            // College production — what he did on Saturdays, in public.
            ProductionTierChip(tier: prospect.collegeProductionTier, width: 46)

            schemeFitCell(prospect, context)
                .frame(width: 32, alignment: .center)

            needCell(context)
                .frame(width: 32, alignment: .center)

            if context.includesRisk {
                ProspectRiskBadge(risk: prospect.riskLevel)
                    .frame(width: 64, alignment: .center)
            }
        }
    }

    @ViewBuilder
    private static func schemeFitCell(
        _ prospect: CollegeProspect,
        _ context: ProspectColumnContext
    ) -> some View {
        if let fit = context.schemeFit {
            let color: Color = fit == "Good" ? .success : (fit == "Fair" ? .warning : .danger)
            Text(fit)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(color)
        } else if !context.knowsSchemeFit {
            // No coordinators on this screen: say nothing rather than "Fair".
            Text("\u{2014}")
                .font(.system(size: 9))
                .foregroundStyle(Color.textTertiary)
        } else if prospect.position.side == .specialTeams {
            Text("N/A")
                .font(.system(size: 8))
                .foregroundStyle(Color.textTertiary)
        } else {
            Text("Fair")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.warning)
        }
    }

    @ViewBuilder
    private static func needCell(_ context: ProspectColumnContext) -> some View {
        if !context.knowsNeeds {
            Text("\u{2014}")
                .font(.system(size: 9))
                .foregroundStyle(Color.textTertiary)
        } else {
            switch context.needLevel {
            case "High":
                Text("High")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.danger)
            case "Med":
                Text("Med")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.warning)
            default:
                Text("Set")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Color.success)
            }
        }
    }

    /// Five facts about the WORK, not about the player: reports filed, pro day
    /// attended, facility visit hosted, private workout run, and how far open
    /// the medical / character file is.
    ///
    /// Every cell is a hole the user can still pay to close, which is why an
    /// empty one is drawn dim rather than left blank — the question this block
    /// answers is "who have I not done the work on".
    @ViewBuilder
    private static func workupCells(
        _ prospect: CollegeProspect,
        _ context: ProspectColumnContext
    ) -> some View {
        let filed = context.reportCount ?? prospect.scoutingReports.count
        Group {
            Text("\(filed)/\(ScoutEvaluationBudget.maxReportsPerProspect)")
                .font(.system(size: 10, weight: .bold).monospacedDigit())
                .foregroundStyle(filed == 0
                                 ? Color.textTertiary.opacity(0.5)
                                 : (filed >= 2 ? Color.success : Color.accentBlue))
                .frame(width: 32, alignment: .center)

            ProspectWorkTick(done: prospect.proDayCompleted, tint: .success)
                .frame(width: 34, alignment: .center)

            ProspectWorkTick(
                done: context.userTeamID.map { prospect.top30VisitedByTeams.contains($0) } ?? false,
                tint: .accentGold
            )
            .frame(width: 34, alignment: .center)

            // A private workout files a `.personalWorkout` report — that filed
            // report IS the record of it, so the column reads the same thing
            // `ScoutingEngine.conductPersonalWorkout` writes, through the same
            // predicate the workout gate uses.
            ProspectWorkTick(done: ScoutingEngine.hasWorkedOutPrivately(prospect), tint: .accentBlue)
                .frame(width: 34, alignment: .center)

            flagFileCell(prospect, context)
                .frame(width: 44, alignment: .center)
        }
    }

    /// How far open the medical / character file is, at the disclosure the user
    /// has earned. Never its contents — that lives on the prospect card.
    private static func flagFileCell(
        _ prospect: CollegeProspect,
        _ context: ProspectColumnContext
    ) -> some View {
        let total = (prospect.medicalConcerns?.count ?? 0) + (prospect.redFlags?.count ?? 0)
        let disclosure = ProspectFog.flagDisclosure(for: prospect, userTeamID: context.userTeamID)
        let text: String
        let tint: Color
        switch disclosure {
        case .hidden:
            text = "?"
            tint = Color.textTertiary.opacity(0.5)
        case .count:
            text = total == 0 ? "\u{2014}" : "\(total)?"
            tint = total == 0 ? Color.textTertiary : Color.warning
        case .full:
            text = total == 0 ? "CLEAN" : "\(total)"
            tint = total == 0 ? Color.success : Color.danger
        }
        return Text(text)
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    /// The combine card, at the precision this club has paid for.
    ///
    /// Every cell renders through the same `ProspectFog` text helper the combine
    /// table's own drill cells use, so two screens print the same string for the
    /// same man: "4.52" when your people held the watch, "~4.5" when you watched
    /// it on television with everybody else.
    @ViewBuilder
    private static func physicalCells(
        _ prospect: CollegeProspect,
        _ context: ProspectColumnContext
    ) -> some View {
        Group {
            if ProspectFog.showsMeasurables(prospect) {
                let fidelity = context.scoutsSentToCombine.map {
                    ProspectFog.combineFidelity(for: prospect, scoutsAttended: $0)
                } ?? ProspectFog.combineFidelity(for: prospect)
                ProspectMeasurableCell(value: ProspectFog.fortyText(prospect.fortyTime, fidelity: fidelity),
                                       label: "40YD", fidelity: fidelity)
                ProspectMeasurableCell(value: ProspectFog.benchText(prospect.benchPress, fidelity: fidelity),
                                       label: "BENCH", fidelity: fidelity)
                ProspectMeasurableCell(value: ProspectFog.verticalText(prospect.verticalJump, fidelity: fidelity, unit: ""),
                                       label: "VERT", fidelity: fidelity)
                ProspectMeasurableCell(value: ProspectFog.broadJumpText(prospect.broadJump, fidelity: fidelity, unit: ""),
                                       label: "BROAD", fidelity: fidelity)
                ProspectMeasurableCell(value: ProspectFog.agilityText(prospect.coneDrill, fidelity: fidelity),
                                       label: "3CONE", fidelity: fidelity)
                ProspectMeasurableCell(value: ProspectFog.agilityText(prospect.shuttleTime, fidelity: fidelity),
                                       label: "SHUT", fidelity: fidelity)
            } else {
                // Nothing has put this man in front of a stopwatch you can read:
                // no invite, no pro day, no report of your own.
                ForEach(prospectMeasurableLabels, id: \.self) { label in
                    ProspectMeasurableCell(value: nil, label: label, fidelity: .broadcast, empty: "?")
                }
            }
        }
    }

    /// The eight mental grade BANDS an interview and filed tape write.
    ///
    /// An interview writes mental grade bands without touching `scoutedOverall`,
    /// so this block follows the grades rather than the overall read.
    @ViewBuilder
    private static func mentalCells(_ prospect: CollegeProspect) -> some View {
        let grades = prospect.scoutedMentalGrades
        let hasRead = prospect.scoutedOverall != nil || !(grades ?? [:]).isEmpty
        Group {
            if hasRead {
                // 8 columns (LRN + CMP added) — widths 26 so the row fits.
                ForEach(prospectMentalKeys, id: \.self) { key in
                    ProspectGradeBandCell(grade: grades?[key], label: key)
                        .frame(width: 26, alignment: .center)
                }
            } else {
                ForEach(0..<8, id: \.self) { _ in
                    Text("--")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.textTertiary)
                        .frame(width: 26, alignment: .center)
                }
            }
        }
    }

    /// The first four of this man's position-skill keys, as scouted BANDS.
    ///
    /// `ProspectFog.positionSkillKeys(for:)` is the canonical table, copied from
    /// the writer (`ScoutingEngine.generatePositionSkillGrades`). Four columns is
    /// a row's budget; a quarterback's canonical block is six keys long, so the
    /// tables show the first four and his card carries the rest.
    @ViewBuilder
    private static func positionCells(_ prospect: CollegeProspect) -> some View {
        Group {
            if prospect.scoutedOverall != nil {
                let keys = Array(ProspectFog.positionSkillKeys(for: prospect).prefix(4))
                ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                    ProspectGradeBandCell(grade: prospect.scoutedPositionGrades?[key], label: key)
                        .frame(width: 32, alignment: .center)
                }
                if keys.count < 4 {
                    ForEach(0..<(4 - keys.count), id: \.self) { _ in
                        Spacer().frame(width: 32)
                    }
                }
            } else {
                ForEach(0..<4, id: \.self) { _ in
                    Text("--")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.textTertiary)
                        .frame(width: 32, alignment: .center)
                }
            }
        }
    }

    // MARK: Headers
    //
    // The header widths are NOT always the cell widths — the work-up block's
    // labels are a couple of points wider than its ticks, which is how the board
    // shipped and is deliberately preserved so no board row re-flows here.

    /// The mode's column labels, for a table that pins headers over its rows.
    @ViewBuilder
    static func headers(
        mode: ProspectAttributeTab,
        context: ProspectColumnContext = ProspectColumnContext()
    ) -> some View {
        Group {
            switch mode {
            case .overview:
                Text("AGE")
                    .frame(width: 28, alignment: .center)
                HStack(spacing: 2) {
                    Text("PROD")
                    InfoTooltipButton(
                        text: "College production tier — ELI elite, AA above average, AVG average, BA below average. Production is a real but imperfect signal: workout warriors under-produce, and system players over-produce against weak competition.",
                        size: 9
                    )
                }
                .frame(width: 46, alignment: .center)
                Text("FIT")
                    .frame(width: 32, alignment: .center)
                Text("NEED")
                    .frame(width: 32, alignment: .center)
                if context.includesRisk {
                    Text("RISK")
                        .frame(width: 64, alignment: .center)
                }
            case .workup:
                HStack(spacing: 2) {
                    Text("RPT")
                    InfoTooltipButton(
                        text: "Scouting reports on file, out of the three a prospect can carry. Each one narrows his grade band.",
                        size: 9
                    )
                }
                .frame(width: 34, alignment: .center)
                Text("PDAY")
                    .frame(width: 38, alignment: .center)
                Text("VISIT")
                    .frame(width: 38, alignment: .center)
                Text("WORK")
                    .frame(width: 38, alignment: .center)
                Text("FILE")
                    .frame(width: 44, alignment: .center)
            case .physical:
                ForEach(prospectMeasurableLabels, id: \.self) { label in
                    Text(label)
                        .frame(width: prospectMeasurableWidth, alignment: .center)
                }
            case .mental:
                ForEach(prospectMentalKeys, id: \.self) { key in
                    Text(key)
                        .frame(width: 26, alignment: .center)
                }
            case .position:
                // The keys differ per row (a QB's block is not a corner's), so
                // the header cannot name them — the cells carry their own labels.
                ForEach(0..<4, id: \.self) { _ in
                    Text("--")
                        .frame(width: 32, alignment: .center)
                }
            }
        }
        .font(.system(size: 8, weight: .bold))
        .foregroundStyle(Color.textTertiary)
    }
}

/// The eight mental keys, in the order every table prints them. CMP is
/// competitiveness, the fighter mentality.
let prospectMentalKeys = ["AWR", "DEC", "WRK", "CLT", "COA", "LDR", "LRN", "CMP"]

// `ProspectPositionSkills` used to live here as the per-position key table.
// It had drifted from the engine's writer (`SAc`/`DAc`/`TAK` vs the written
// `SAC`/`DAC`/`TKL`), so every table now reads the canonical
// `ProspectFog.positionSkillKeys(for:)` instead — one table, owned next to
// the disclosure logic it feeds.
