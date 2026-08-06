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
                    // #fleet review F19f: VoiceOver had no way to tell which
                    // block was showing — the position chips next door have
                    // carried this trait all along.
                    .accessibilityAddTraits(mode == tab ? .isSelected : [])
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

/// Where one drill result sits inside its POSITION group, as a phrase rather
/// than a rank number.
///
/// Lifted out of `CombineResultsView.tierLabel` so the board, the two selection
/// lists and (in the next pass) the combine table itself all say "Top 10%" in
/// the same green. A raw "87th" is a number the user then has to rank against
/// the other five numbers on the row; the phrase is the read.
///
/// The colours are the top five rungs of the ladder
/// `PositionGradeCalculator.gradeColorForLetter` paints letters on — elite
/// green, green, blue, amber, red — so a man whose 40 reads "Top 10%" in bright
/// green and whose DRILL grade reads "A+" in bright green is not two different
/// scales agreeing by accident. Not the SAME ladder: the letter version has six
/// rungs, splitting the bottom into `alertOrange` for D and `danger` for F,
/// where five percentile bands have nowhere to put a sixth colour.
enum ProspectMeasurableTier {
    /// Maps a 1-99 percentile to its phrase and its colour.
    static func label(for percentile: Int) -> (text: String, color: Color) {
        switch percentile {
        case 90...:    return ("Top 10%", .eliteGreen)
        case 75..<90:  return ("Top 25%", .success)
        case 50..<75:  return ("Above Avg", .accentBlue)
        case 25..<50:  return ("Below Avg", .warning)
        default:       return ("Bottom 25%", .danger)
        }
    }
}

/// One measurable over its column label, and — when the club has earned the
/// precision — where that number sits in his position group.
///
/// A blank cell is two different facts and the cell says which: "?" when nobody
/// has measured him where you could see it, an em-dash when he was there and did
/// not run that drill. The tint carries the other half of the fog — a hard
/// number your own people took reads at full strength, a rounded broadcast
/// figure reads back, matching the "~" the `ProspectFog` helper prefixes.
///
/// ## The percentile and the fog
///
/// `percentile` is `nil` for a broadcast read, and that is not a shortcut — it
/// is `ProspectFog.showsPercentile`, the rule the combine table has always
/// followed. A percentile computed off "~4.5" would be a precise-looking claim
/// built on a number that was rounded to a tenth precisely because the club did
/// not earn the decimals: two men at 4.46 and 4.54 both print "~4.5" and would
/// then be told they tested identically. Attending the combine buys precision,
/// and the percentile is what precision is FOR. A dimmed "~4.5" with the drill
/// label straight under it and no phrase between them is the honest rendering —
/// and the missing line is itself the tell that there is a read here the club
/// has not paid for.
struct ProspectMeasurableCell: View {
    let value: String?
    let label: String
    let fidelity: ProspectFog.MeasurableFidelity
    var empty: String = "\u{2014}"
    /// Position-relative percentile, 1-99. `nil` prints no phrase — either the
    /// host has no peer population or the fog forbids the claim.
    var percentile: Int? = nil
    /// Keeps the phrase's line even when THIS cell has no phrase to put in it.
    ///
    /// The row decides the height, not the cell. A full-fidelity prospect who
    /// simply never ran the shuttle has a percentile for five drills and none
    /// for the sixth, so without this his SHUT cell was two lines beside five
    /// three-line ones and the whole label row stepped. Set from the same test
    /// `ProspectDrillGradeCell.reservesPercentileLine` is set from — the fog
    /// allows percentiles and the host has a pool — so the seven cells of a
    /// Physical block always agree about how tall they are.
    var reservesPercentileLine: Bool = false

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

            // The phrase sits directly under the number it grades, above the
            // drill label: the label is a constant down the column (pure
            // identification, and the block's header is one "COMBINE" span, so
            // it is the ONLY thing naming the column), while the phrase is the
            // signal the eye is hunting. Three 7-10 pt lines stack to ~29 pt,
            // which is inside the 30 pt portrait that already sets the row
            // height — so the percentile costs no vertical space at all.
            if let percentile, value != nil {
                let tier = ProspectMeasurableTier.label(for: percentile)
                Text(tier.text)
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(tier.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            } else if reservesPercentileLine {
                Text(" ")
                    .font(.system(size: 7, weight: .semibold))
                    .accessibilityHidden(true)
            }

            Text(label)
                .font(.system(size: 7, weight: .medium))
                .foregroundStyle(Color.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: prospectMeasurableWidth, alignment: .center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    /// VoiceOver reads the three lines as one sentence — a 7 pt label, a number
    /// and a phrase announced as three separate elements is worse than useless
    /// on a 42 pt column.
    private var accessibilityText: String {
        guard let value else { return "\(label): \(empty == "?" ? "not measured" : "did not run")" }
        guard let percentile else { return "\(label) \(value)" }
        return "\(label) \(value), \(ProspectMeasurableTier.label(for: percentile).text) for his position"
    }
}

/// The POSITION-DRILL grade — the coaches' verdict on the drill session, which
/// is the one thing on the combine card that is a judgement rather than a
/// stopwatch reading.
///
/// Rendered exactly as `CombineResultsView.positionDrillCell` renders it: the
/// fogged letter through `ProspectFog.drillGradeText` (broadcast loses the
/// +/- modifier — you know the tier he tested in, not where inside it he
/// landed), tinted by the ONE grade colour function.
struct ProspectDrillGradeCell: View {
    let grade: String?
    var empty: String = "\u{2014}"
    /// Reserves the blank line its six neighbours spend on a percentile phrase.
    ///
    /// Pure layout, no information: a two-line cell beside six three-line ones
    /// centres half a line high, and the result is a DRILL label sitting above
    /// the 40YD / BENCH / … labels it is meant to be in a row with.
    var reservesPercentileLine: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            Text(grade ?? empty)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(grade.map { PositionGradeCalculator.gradeColorForLetter($0) }
                                 ?? Color.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if reservesPercentileLine {
                Text(" ")
                    .font(.system(size: 7, weight: .semibold))
                    .accessibilityHidden(true)
            }
            Text("DRILL")
                .font(.system(size: 7, weight: .medium))
                .foregroundStyle(Color.textTertiary)
        }
        .frame(width: prospectDrillGradeWidth, alignment: .center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(grade.map { "position drill grade \($0)" } ?? "no position drill grade")
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
/// "~4.5" and "126" are four glyphs where "91" was two — and 38 → 42 now that
/// "Bottom 25%" sets under the number. Deliberately NOT wider than that: the
/// Physical block is seven columns and every point here is seven points off
/// the name column on three different surfaces.
let prospectMeasurableWidth: CGFloat = 42

/// The Pos Drill column that closes the Physical block. Narrower than a drill
/// cell: it prints one letter, never a percentile phrase.
let prospectDrillGradeWidth: CGFloat = 34

/// The leading OVR / GRD band column, when a surface pins the scouted read
/// beside the name instead of at the trailing edge. Matches the board's own
/// 50 pt `ProspectScoutBandCell`.
let prospectScoutBandWidth: CGFloat = 50

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
    /// The peer population the Physical block ranks a drill result against.
    ///
    /// `nil` prints the drill labels and no percentile phrase — a host that has
    /// not handed the block a class cannot honestly say "Top 10%" of anything.
    /// Build it once per screen (`PercentilePools(prospects:)` is a full sort of
    /// the class) and hold it in `@State`, never per row.
    ///
    /// The type lives in `ProspectPercentiles.swift` — one implementation, four
    /// readers. A second percentile implementation would be a second answer to
    /// "what did he run, relative to his position", and the whole point of this
    /// file is that there is one.
    var percentilePools: PercentilePools? = nil
    /// Pins the scouted OVR band as the FIRST column of the block, beside the
    /// name, rather than leaving it at the trailing edge.
    ///
    /// Off by default because a host that already draws its own OVR band would
    /// otherwise print the same band twice on one row. Two hosts do, for reasons
    /// the shared cell cannot cover, and both stay off:
    ///
    /// * the **Big Board** pins a tappable band beside the name — tapping it
    ///   opens the assessment sheet, and the shared cell carries no
    ///   `onGradeTap`;
    /// * the **interview list** pins one at the trailing edge WITH the
    ///   stock-trajectory chevron, which the shared cell deliberately drops.
    ///
    /// `FilmStudySelectionView` draws no OVR column of its own, so it turns this
    /// on and gets the band as the first thing after the name.
    var leadsWithScoutBand: Bool = false
}

// MARK: - Percentile plumbing
//
// One place that turns a prospect's stored measurement into the drill it
// belongs to, so a host does not have to know that `benchPress` is an `Int` on
// a `Double` scale or that the cone and the shuttle are separate pools.

extension ProspectColumnContext {
    /// The percentile for one drill, or `nil` when the fog forbids the claim,
    /// the host has no pool, or the man never ran it.
    ///
    /// `ProspectFog.showsPercentile` is the gate — see the note on
    /// ``ProspectMeasurableCell``. A broadcast read gets the number and nothing
    /// under it.
    func percentile(
        _ value: Double?,
        drill: DrillKind,
        position: Position,
        fidelity: ProspectFog.MeasurableFidelity
    ) -> Int? {
        guard ProspectFog.showsPercentile(fidelity),
              let pools = percentilePools,
              !pools.isEmpty,
              let value
        else { return nil }
        return pools.percentile(value: value, drill: drill, position: position)
    }
}

enum ProspectColumns {

    // MARK: Cells

    /// The mode's column block for one prospect row.
    ///
    /// The scouted band LEADS every block when the host asks for it
    /// (``ProspectColumnContext/leadsWithScoutBand``). It is the column the user
    /// reads first and it used to be pinned at the far trailing edge of every
    /// surface — so in Physical mode the whole row was six raw numbers and the
    /// one verdict that orders the board sat past them. Same column in the same
    /// place in all five modes; nothing about the mode changes what your scouts
    /// think of the man.
    @ViewBuilder
    static func cells(
        for prospect: CollegeProspect,
        mode: ProspectAttributeTab,
        context: ProspectColumnContext = ProspectColumnContext()
    ) -> some View {
        if context.leadsWithScoutBand {
            ProspectScoutBandCell(
                prospect: prospect,
                width: prospectScoutBandWidth,
                showsTrajectory: false
            )
        }
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

    /// The combine card, at the precision this club has paid for — and, when it
    /// has paid for it, where each number sits in his POSITION group.
    ///
    /// Every cell renders through the same `ProspectFog` text helper the combine
    /// table's own drill cells use, so two screens print the same string for the
    /// same man: "4.52" when your people held the watch, "~4.5" when you watched
    /// it on television with everybody else.
    ///
    /// The percentile line is what the combine table has and the board did not:
    /// a bare "4.52" is a number the user has to know the position's distribution
    /// to read, and nobody carries a corner's 40 distribution in his head while
    /// scanning 350 rows. "Top 10%" is the read. It only prints when the host
    /// hands the block a `percentilePools` AND `ProspectFog.showsPercentile`
    /// allows the claim — see ``ProspectMeasurableCell``.
    ///
    /// The block ends on the POSITION DRILL grade, which is the only cell here
    /// that is a judgement rather than a stopwatch reading, and which the board
    /// previously showed nowhere at all — the CMB badge tinted itself off it and
    /// then threw the letter away.
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
                let pos = prospect.position
                // ONE decision for all seven cells: does this row spend a third
                // line on percentiles? Per-cell "do I have a phrase" was not the
                // same question — a man who never ran the shuttle has no phrase
                // there and his SHUT cell came out a line short of its six
                // neighbours, stepping the label row.
                let reservesPercentileLine = ProspectFog.showsPercentile(fidelity)
                    && !(context.percentilePools?.isEmpty ?? true)
                ProspectMeasurableCell(
                    value: ProspectFog.fortyText(prospect.fortyTime, fidelity: fidelity),
                    label: "40YD", fidelity: fidelity,
                    percentile: context.percentile(prospect.fortyTime, drill: .forty,
                                                   position: pos, fidelity: fidelity),
                    reservesPercentileLine: reservesPercentileLine
                )
                ProspectMeasurableCell(
                    value: ProspectFog.benchText(prospect.benchPress, fidelity: fidelity),
                    label: "BENCH", fidelity: fidelity,
                    percentile: context.percentile(prospect.benchPress.map { Double($0) }, drill: .bench,
                                                   position: pos, fidelity: fidelity),
                    reservesPercentileLine: reservesPercentileLine
                )
                ProspectMeasurableCell(
                    value: ProspectFog.verticalText(prospect.verticalJump, fidelity: fidelity, unit: ""),
                    label: "VERT", fidelity: fidelity,
                    percentile: context.percentile(prospect.verticalJump, drill: .vertical,
                                                   position: pos, fidelity: fidelity),
                    reservesPercentileLine: reservesPercentileLine
                )
                ProspectMeasurableCell(
                    value: ProspectFog.broadJumpText(prospect.broadJump, fidelity: fidelity, unit: ""),
                    label: "BROAD", fidelity: fidelity,
                    percentile: context.percentile(prospect.broadJump.map { Double($0) }, drill: .broad,
                                                   position: pos, fidelity: fidelity),
                    reservesPercentileLine: reservesPercentileLine
                )
                ProspectMeasurableCell(
                    value: ProspectFog.agilityText(prospect.coneDrill, fidelity: fidelity),
                    label: "3CONE", fidelity: fidelity,
                    percentile: context.percentile(prospect.coneDrill, drill: .threeCone,
                                                   position: pos, fidelity: fidelity),
                    reservesPercentileLine: reservesPercentileLine
                )
                ProspectMeasurableCell(
                    value: ProspectFog.agilityText(prospect.shuttleTime, fidelity: fidelity),
                    label: "SHUT", fidelity: fidelity,
                    percentile: context.percentile(prospect.shuttleTime, drill: .shuttle,
                                                   position: pos, fidelity: fidelity),
                    reservesPercentileLine: reservesPercentileLine
                )
                ProspectDrillGradeCell(
                    grade: ProspectFog.drillGradeText(prospect.positionDrillGrade, fidelity: fidelity),
                    // Its neighbours grow a third line exactly when the club has
                    // earned percentiles; this keeps the seven labels level.
                    reservesPercentileLine: reservesPercentileLine
                )
            } else {
                // Nothing has put this man in front of a stopwatch you can read:
                // no invite, no pro day, no report of your own. The columns are
                // still drawn — the header spans them either way, and a row that
                // silently loses seven cells walks every label off its column.
                ForEach(prospectMeasurableLabels, id: \.self) { label in
                    ProspectMeasurableCell(value: nil, label: label, fidelity: .broadcast, empty: "?")
                }
                ProspectDrillGradeCell(grade: nil, empty: "?")
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
                ForEach(ProspectFog.mentalKeys, id: \.self) { key in
                    ProspectGradeBandCell(grade: grades?[key], label: key)
                        .frame(width: 26, alignment: .center)
                }
            } else {
                ForEach(0..<ProspectFog.mentalKeys.count, id: \.self) { _ in
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
    // The header widths ARE the cell widths, block for block. They used not to
    // be — the work-up labels ran 34/38/38/38/44 over 32/34/34/34/44 of ticks,
    // 192 pt of header over 178 pt of row — and "deliberately preserved" was a
    // 14 pt drift that walked every label off its column on all three consumers
    // (#fleet review F12). Anything added here keeps the two lists in step.
    //
    // Three blocks are spanned rather than labelled per column: the cells in
    // them print their OWN key under the value (`ProspectMeasurableCell`,
    // `ProspectGradeBandCell`), so a per-column header printed 40YD/BENCH/… and
    // AWR/DEC/… a second time, two labels deep in a 26-38 pt column, both
    // squeezed by `minimumScaleFactor`. `CombineResultsView.mentalHeaders` /
    // `positionHeaders` already span theirs; this matches (#fleet review F11).

    /// The mode's column labels, for a table that pins headers over its rows.
    @ViewBuilder
    static func headers(
        mode: ProspectAttributeTab,
        context: ProspectColumnContext = ProspectColumnContext()
    ) -> some View {
        Group {
            // Mirrors `cells`: the band leads the block when the host pins it
            // there, at the same width, so the label sits over the column.
            if context.leadsWithScoutBand {
                Text("OVR")
                    .frame(width: prospectScoutBandWidth, alignment: .center)
            }
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
                .frame(width: 32, alignment: .center)
                Text("PDAY")
                    .frame(width: 34, alignment: .center)
                Text("VISIT")
                    .frame(width: 34, alignment: .center)
                Text("WORK")
                    .frame(width: 34, alignment: .center)
                Text("FILE")
                    .frame(width: 44, alignment: .center)
            case .physical:
                // ONE span over the six drill cells plus the Pos Drill grade.
                // Each drill cell prints its own 40YD / BENCH / … label under
                // the number — with the percentile phrase stacked BETWEEN the
                // two once the club has earned the precision — and the grade
                // cell prints DRILL, so a per-column header would be a second
                // row of 7 pt labels over the first.
                Text("COMBINE")
                    .frame(
                        width: prospectMeasurableWidth * CGFloat(prospectMeasurableLabels.count)
                            + prospectDrillGradeWidth,
                        alignment: .center
                    )
            case .mental:
                Text("MENTAL BANDS")
                    .frame(width: 26 * CGFloat(ProspectFog.mentalKeys.count), alignment: .center)
            case .position:
                // The keys differ per row (a QB's block is not a corner's), so
                // the header cannot name them — the cells carry their own
                // labels. It used to print four dashes over them.
                Text("POSITION SKILLS")
                    .frame(width: 32 * 4, alignment: .center)
            }
        }
        .font(.system(size: 8, weight: .bold))
        .foregroundStyle(Color.textTertiary)
    }
}

// `prospectMentalKeys` used to live here as a second copy of the eight mental
// keys. It was byte-identical to `ProspectFog.mentalKeys` — the canonical list,
// which sits next to the disclosure logic that feeds it and which
// `CombineResultsView` and the prospect card already read — so the tables read
// that one now (#fleet review F19b).

// `ProspectPositionSkills` used to live here as the per-position key table.
// It had drifted from the engine's writer (`SAc`/`DAc`/`TAK` vs the written
// `SAC`/`DAC`/`TKL`), so every table now reads the canonical
// `ProspectFog.positionSkillKeys(for:)` instead — one table, owned next to
// the disclosure logic it feeds.
