import SwiftUI
import SwiftData

// MARK: - Draft class depth
//
// WHAT THE JANUARY TASK LANDS ON.
//
// "Read the Senior Bowl & declaration reports" used to deep-link into the
// Combine tab, and in `.reviewRoster` the combine has not been held: no prospect
// carries `combineInvite` (the flag is stamped by `ScoutingEngine
// .generateCombineResults`, which only runs once the combine window opens), so
// the screen the REQUIRED-adjacent task handed the user read "Combine Not
// Simulated \u{2014} 0 of 0 prospects invited" over a class he had already scouted
// 83 % of. The task's own copy promises "the class is not the one you scouted in
// the autumn"; the screen underneath it said nothing at all.
//
// This is the screen that sentence describes. It answers the two questions a GM
// actually asks in January, and nothing else:
//
//   1. WHAT CHANGED — who declared, who went back to school, and who the Senior
//      Bowl week moved. That is the header block.
//   2. WHERE IS THE TALENT — per position group, how deep the DECLARED pool is
//      by projected-round tier, measured against a league-typical intake, with
//      the club's own hole at that position printed beside it.
//
// ## Fog discipline
//
// Every number on this screen is public information or the user's own work.
// The tiers come off `draftProjection` (the media's projected round) refined by
// `DraftIntel.publicBoardRanks`, whose comparator reads only the mock slot, the
// projected round, the combine invite and college production. The names are
// ordered by that same media board, never by a grade. A name's read is
// `ProspectFog.read`, and it prints a BAND only when the read came from this
// building's scouts \u{2014} otherwise it prints the media's round, which is all a man
// nobody has filed on is worth. `trueOverall` / `truePhysical` appear nowhere,
// including in the sorts.
//
// ## Why the depth baseline is not a number invented here
//
// "Deep" and "thin" are only meaningful against an expectation, and the game
// already owns one: `DraftClassBuilder.PositionGroup.classShare` is the blueprint
// every generated class is allocated from, and `drawGroupStrengths` is what makes
// one class corner-heavy and the next one thin at tackle. Reading the blueprint
// back means this screen's verdict tracks the generator instead of drifting from
// it the first time a share is re-tuned.

// MARK: - Groups

/// The nine groups this screen counts by.
///
/// Eight of them ARE the hub's position chips \u{2014} same membership, same order \u{2014}
/// so a chip tap narrows this screen to exactly the rows the board would show.
/// The ninth is the specialists: `ProspectPositionFilter` has no K/P case, and
/// inventing one here would either mean a tenth chip on every prospect table or
/// a group whose row disagreed with the chip above it. Instead the specialists
/// are a row the chips cannot reach, drawn only under "All" \u{2014} a kicker class is
/// worth one line a year and nothing scans a board for it.
enum ClassDepthGroup: String, CaseIterable, Identifiable {
    case qb, rb, wr, te, ol, dl, lb, db, specialists

    var id: String { rawValue }

    /// The hub chip that selects this group, or `nil` for the specialists.
    var chip: ProspectPositionFilter? {
        switch self {
        case .qb:          return .qb
        case .rb:          return .rb
        case .wr:          return .wr
        case .te:          return .te
        case .ol:          return .ol
        case .dl:          return .dl
        case .lb:          return .lb
        case .db:          return .db
        case .specialists: return nil
        }
    }

    var label: String {
        switch self {
        case .specialists: return "K/P"
        default:           return chip?.label ?? rawValue.uppercased()
        }
    }

    /// The long form, for the row's accessibility sentence.
    var longLabel: String {
        switch self {
        case .qb:          return "Quarterbacks"
        case .rb:          return "Running backs"
        case .wr:          return "Receivers"
        case .te:          return "Tight ends"
        case .ol:          return "Offensive line"
        case .dl:          return "Defensive line"
        case .lb:          return "Linebackers"
        case .db:          return "Defensive backs"
        case .specialists: return "Kickers and punters"
        }
    }

    /// Membership. Delegated to the chip wherever there is one, so this screen
    /// and the board can never disagree about who is an edge rusher.
    func matches(_ position: Position) -> Bool {
        if let chip { return chip.matches(position) }
        return position == .K || position == .P
    }

    var tint: Color {
        switch self {
        case .qb, .rb, .wr, .te, .ol: return .accentBlue
        case .dl, .lb, .db:           return .danger
        case .specialists:            return .accentGold
        }
    }

    /// Share of a league-typical class this group takes, read straight off the
    /// generator's own blueprint.
    ///
    /// `DraftClassBuilder.PositionGroup` reports counts at ITS group level (the
    /// NFL reference reports them that way) and splits them across member
    /// positions afterwards \u{2014} `edge` is 57 % defensive end and 43 % outside
    /// linebacker, and those two halves land in two different groups here. So the
    /// share is accumulated per member position rather than per builder group,
    /// which is the only mapping that gets the DL / LB split right.
    ///
    /// Not normalised: the caller divides by the sum over all nine groups, which
    /// is the same total whichever way it is walked (every drafted position
    /// belongs to exactly one group here).
    var leagueShare: Double {
        var total = 0.0
        for builderGroup in DraftClassBuilder.PositionGroup.allCases {
            for (position, weight) in builderGroup.memberWeights where matches(position) {
                total += builderGroup.classShare * weight
            }
        }
        return total
    }
}

// MARK: - Tiers

/// The four bands this screen counts a class in.
///
/// Derived from `draftProjection` \u{2014} the MEDIA's projected round, which is public
/// by construction and therefore fog-safe without any further test. The one
/// refinement is the top tier: a round is a blunt instrument (the whole reason
/// `ProspectFog.consensusBand` opens a round to five grades), and "round one" on
/// its own says nothing about whether a class has a man worth trading up for. So
/// a blue chip is a round-one projection that ALSO sits inside the media board's
/// first half-round \u{2014} `DraftIntel.publicBoardRanks`, whose comparator reads the
/// mock slot, the projected round, the combine invite and college production and
/// nothing else.
enum ClassDepthTier: String, CaseIterable, Identifiable {
    case blueChip, roundOneTwo, roundThreeFive, lateUDFA

    var id: String { rawValue }

    /// Board slots that count as the top of round one.
    static let blueChipBoardSlots = 16

    var label: String {
        switch self {
        case .blueChip:       return "Blue chip"
        case .roundOneTwo:    return "Rd 1-2"
        case .roundThreeFive: return "Rd 3-5"
        case .lateUDFA:       return "Late + UDFA"
        }
    }

    var tint: Color {
        switch self {
        case .blueChip:       return .accentGold
        case .roundOneTwo:    return .accentBlue
        case .roundThreeFive: return .success
        case .lateUDFA:       return .textTertiaryReadable
        }
    }

    /// Whether the tier counts toward the pool the depth verdict measures.
    ///
    /// The late / undrafted tail is roughly constant filler \u{2014} every class has a
    /// hundred of them at every position \u{2014} so counting it would flatten every
    /// verdict toward "average". Depth is a claim about DRAFTABLE bodies.
    var isDraftable: Bool { self != .lateUDFA }

    /// The tier a prospect's public read puts him in.
    static func of(round: Int?, boardRank: Int?) -> ClassDepthTier {
        guard let round, round >= 1 else { return .lateUDFA }
        switch round {
        case 1:
            if let boardRank, boardRank <= blueChipBoardSlots { return .blueChip }
            return .roundOneTwo
        case 2:       return .roundOneTwo
        case 3, 4, 5: return .roundThreeFive
        default:      return .lateUDFA
        }
    }
}

/// The four counts for one group, kept as named fields rather than a dictionary
/// so nothing renders a tier by index and gets the order wrong.
struct ClassDepthTierCounts {
    var blueChip = 0
    var roundOneTwo = 0
    var roundThreeFive = 0
    var lateUDFA = 0

    var draftable: Int { blueChip + roundOneTwo + roundThreeFive }
    var total: Int { draftable + lateUDFA }

    mutating func add(_ tier: ClassDepthTier) {
        switch tier {
        case .blueChip:       blueChip += 1
        case .roundOneTwo:    roundOneTwo += 1
        case .roundThreeFive: roundThreeFive += 1
        case .lateUDFA:       lateUDFA += 1
        }
    }

    func count(_ tier: ClassDepthTier) -> Int {
        switch tier {
        case .blueChip:       return blueChip
        case .roundOneTwo:    return roundOneTwo
        case .roundThreeFive: return roundThreeFive
        case .lateUDFA:       return lateUDFA
        }
    }
}

/// How this group's draftable pool compares with a league-typical intake.
enum ClassDepthVerdict: String {
    case thin, average, deep

    var label: String {
        switch self {
        case .thin:    return "THIN"
        case .average: return "AVERAGE"
        case .deep:    return "DEEP"
        }
    }

    var tint: Color {
        switch self {
        case .thin:    return .warning
        case .average: return .textSecondary
        case .deep:    return .success
        }
    }

    /// Cut points on `draftable / league-typical`. Wide enough that ordinary
    /// class-to-class noise reads as "average" \u{2014} `DraftClassBuilder
    /// .drawGroupStrengths` draws a group's strength from a normal centred on
    /// 1.0 with a 0.15-0.18 sigma, so \u{00B1}15 % is roughly one standard deviation
    /// and a verdict either side of it is a real signal rather than a rounding.
    static func of(ratio: Double) -> ClassDepthVerdict {
        if ratio >= 1.15 { return .deep }
        if ratio <= 0.85 { return .thin }
        return .average
    }
}

/// What the top of this group looks like, said WITHOUT counts. The row never
/// prints how many draftable men a group carries \u{2014} a media projection is not
/// precise enough to justify a number, and an exact count would hand the user
/// a draft-strategy table nobody in a real building gets before the combine.
/// Depth and top-end quality as words is the honest resolution.
enum ClassDepthTopEnd {
    case strong, fair, weak, empty

    var phrase: String {
        switch self {
        case .strong: return "Strong at the top"
        case .fair:   return "Fair at the top"
        case .weak:   return "Weak at the top"
        case .empty:  return "No top-end talent"
        }
    }

    var tint: Color {
        switch self {
        case .strong:       return .success
        case .fair:         return .textSecondary
        case .weak, .empty: return .warning
        }
    }

    /// `expectedTop` is the early-round bodies a league-typical class carries at
    /// this group, scaled to THIS class's size \u{2014} so a kicker group is not
    /// called weak for lacking the blue chip it never has.
    static func of(topCount: Int, blueChips: Int, expectedTop: Double) -> ClassDepthTopEnd {
        guard expectedTop >= 0.5 else { return topCount >= 1 ? .strong : .fair }
        guard topCount > 0 else { return .empty }
        let ratio = Double(topCount) / expectedTop
        if ratio >= 1.15, blueChips >= 1 { return .strong }
        if ratio <= 0.6 { return .weak }
        return .fair
    }
}

// MARK: - Row models
//
// Everything the list draws is built ONCE, in `.task`, and held as `@State`.
// The build walks a ~350-man class four times (board sort, group bucketing,
// need ranking, Senior Bowl scan) and this screen sits under the hub's process
// chrome, which re-evaluates on every `@State` touch in the whole hub.

/// One position group's row.
struct ClassDepthRow: Identifiable {
    let group: ClassDepthGroup
    let counts: ClassDepthTierCounts
    /// Draftable bodies a league-typical class would carry at this group, given
    /// how big THIS class's draftable pool is.
    let expectedDraftable: Double
    let verdict: ClassDepthVerdict
    let topEnd: ClassDepthTopEnd
    /// "High" / "Med" / "Set" \u{2014} the board's need vocabulary, off the deficit read.
    let needLevel: String
    /// The two or three men the MEDIA has highest in this group.
    let top: [CollegeProspect]

    var id: String { group.rawValue }
}

/// What the January window did to the class.
struct ClassDeclarationSummary {
    /// Men in this draft.
    var declared = 0
    /// Of those, the underclassmen \u{2014} the ones who did not have to be here.
    var earlyEntries = 0
    /// Underclassmen who went back to school.
    var withdrew = 0
    /// Whether the January window has been held at all. Before it runs, every
    /// underclassman carries the model's `isDeclaringForDraft` default of `true`,
    /// so ~100 men who will never come out are sitting on the board as locks —
    /// which is what the header has to say instead of calling them early entries.
    var windowHeld = false
    /// Whether Mobile has been played \u{2014} i.e. whether any prospect carries a
    /// `.seniorBowl` report.
    var seniorBowlHeld = false
    /// How many men the week filed on.
    var seniorBowlReports = 0
}

// MARK: - View

/// The draft class, by position, at the depth the user is entitled to see.
struct ClassDepthView: View {
    let career: Career
    /// The DECLARED class, exactly as the hub filtered it. Re-filtered on the
    /// way in anyway: this screen's whole claim is "these are the men who are
    /// actually in the draft", and it must hold if it is ever hosted elsewhere.
    let prospects: [CollegeProspect]
    /// The club's roster, for the need column. Handed down rather than fetched
    /// so the hub's one fetch serves every tab.
    let teamRoster: [Player]
    /// The hub's shared position chips. Selecting one narrows this screen to
    /// that group, exactly as it narrows the board.
    @Binding var positionFilter: ProspectPositionFilter
    /// Whether the hub's Insights block is open (#130).
    ///
    /// The declaration header — declared / early entries / returned / Senior Bowl
    /// reports, plus the sentence that reads them — is this surface's insight: a
    /// once-a-January orientation over a screen whose actual content is the nine
    /// depth bars. It folds with the hub's chevron so the bars start at the top
    /// on every visit after the first.
    var insightsExpanded: Bool = true
    /// Hands the user to the Big Board with the group already filtered. The
    /// depth read is a scan; the board is where he works.
    var onOpenBoard: (() -> Void)? = nil

    @State private var isLoading = true
    @State private var rows: [ClassDepthRow] = []
    @State private var summary = ClassDeclarationSummary()
    @State private var standouts: [CollegeProspect] = []

    /// The rows the chips leave visible. See ``ClassDepthGroup`` for why a
    /// selected chip hides the specialists rather than showing them empty.
    private var visibleRows: [ClassDepthRow] {
        guard positionFilter != .all else { return rows }
        return rows.filter { $0.group.chip == positionFilter }
    }

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(1.5)
                        .tint(Color.accentGold)
                    Text("Reading the class...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else if rows.isEmpty {
                emptyState
            } else {
                List {
                    if insightsExpanded {
                        Section {
                            declarationCard
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                        .listRowBackground(Color.backgroundSecondary)
                    }

                    if !standouts.isEmpty {
                        Section {
                            ForEach(standouts) { prospect in
                                standoutRow(prospect)
                            }
                        } header: {
                            sectionHeader(
                                "Senior Bowl risers",
                                systemImage: "arrow.up.forward.circle.fill",
                                tint: .success
                            )
                        }
                        .listRowBackground(Color.backgroundSecondary)
                    }

                    Section {
                        ForEach(visibleRows) { row in
                            groupRow(row)
                        }
                    } header: {
                        sectionHeader(
                            positionFilter == .all
                                ? "Depth by position"
                                : "Depth \u{2014} \(positionFilter.label)",
                            systemImage: "chart.bar.fill",
                            tint: .accentBlue
                        )
                    } footer: {
                        footnote
                    }
                    .listRowBackground(Color.backgroundSecondary)
                }
                .scrollContentBackground(.hidden)
                .listStyle(.insetGrouped)
            }
        }
        .task {
            rebuild()
            isLoading = false
        }
        // The hub reloads the class after a sheet dismiss (a combine trip files
        // reports on the board), and the count is the cheapest proof the array
        // it handed down is a different one.
        .onChange(of: prospects.count) { _, _ in rebuild() }
    }

    // MARK: - Declarations & Senior Bowl

    private var declarationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(String(career.currentSeason)) DRAFT CLASS")
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(Color.textPrimary)
                Spacer(minLength: 0)
                Text("\(summary.declared) declared")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(Color.accentGold)
            }

            HStack(spacing: 8) {
                summaryTile(
                    value: "\(summary.earlyEntries)",
                    // Before the window closes, an underclassman on the board is
                    // not an early entry — he is a man who has not decided, and
                    // `isDeclaringForDraft` says otherwise only because it
                    // defaults to `true`. The label says which of the two it is.
                    label: summary.windowHeld ? "early entries" : "underclassmen, undecided",
                    tint: .accentBlue
                )
                summaryTile(
                    value: "\(summary.withdrew)",
                    label: "returned to school",
                    tint: summary.withdrew > 0 ? .warning : .textTertiaryReadable
                )
                summaryTile(
                    value: summary.seniorBowlHeld ? "\(summary.seniorBowlReports)" : "\u{2014}",
                    label: "Senior Bowl reports",
                    tint: summary.seniorBowlHeld ? .success : .textTertiaryReadable
                )
            }

            Text(headlineSentence)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
    }

    /// The sentence the January task promises, said with this class's numbers.
    private var headlineSentence: String {
        guard summary.windowHeld else {
            return "The declaration window has not been held yet \u{2014} every underclassman on this board is still a maybe."
        }
        var sentence = "\(summary.withdrew) underclassmen went back to school and \(summary.earlyEntries) came out early."
        if summary.seniorBowlHeld {
            sentence += " Mobile filed \(summary.seniorBowlReports) fresh reports on top of it."
        }
        sentence += " This is not the class you scouted in the autumn."
        return sentence
    }

    private func summaryTile(value: String, label: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 20, weight: .black).monospacedDigit())
                .foregroundStyle(tint)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.textTertiaryReadable)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }

    /// One Senior Bowl riser: who he is, and what the week did to his round.
    private func standoutRow(_ prospect: CollegeProspect) -> some View {
        HStack(spacing: 8) {
            ProspectRowIdentity(prospect: prospect, showsUserGrade: false) {
                ProspectMarketArrow(prospect: prospect)
            }
            readCell(for: prospect)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Position rows

    private func groupRow(_ row: ClassDepthRow) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            groupHeadline(row)
            depthBar(row)
            tierLegend(row)
            topNames(row)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            // A depth read is a scan; the board is where the work happens. The
            // tap sets the SHARED chip, so the board opens already narrowed to
            // the group the user was looking at.
            guard let chip = row.group.chip else { return }
            positionFilter = chip
            onOpenBoard?()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText(row))
        .accessibilityHint(row.group.chip == nil ? "" : "Opens the Big Board filtered to this group")
    }

    private func groupHeadline(_ row: ClassDepthRow) -> some View {
        HStack(spacing: 8) {
            Text(row.group.label)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 38, height: 22)
                .background(
                    row.group.tint.opacity(0.25),
                    in: RoundedRectangle(cornerRadius: DSCornerRadius.tight)
                )

            Text(row.topEnd.phrase)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(row.topEnd.tint)

            Spacer(minLength: 0)

            chip(row.verdict.label, tint: row.verdict.tint)
            needChip(row.needLevel)
        }
    }

    private func tierLegend(_ row: ClassDepthRow) -> some View {
        HStack(spacing: 10) {
            ForEach(ClassDepthTier.allCases) { tier in
                tierKey(tier, present: row.counts.count(tier) > 0)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func topNames(_ row: ClassDepthRow) -> some View {
        if row.top.isEmpty {
            Text("Nobody in this group is projected to be drafted.")
                .font(.system(size: 10))
                .foregroundStyle(Color.textTertiaryReadable)
        } else {
            VStack(spacing: 3) {
                ForEach(row.top) { prospect in
                    topNameRow(prospect)
                }
            }
        }
    }

    /// Width of every depth track, so the league-typical tick lines up down the
    /// whole column and the rows can be compared by eye.
    private static let barTrack: CGFloat = 168
    /// The track runs to 1.5\u{00D7} a league-typical intake, which puts the tick at a
    /// constant two thirds of every row and leaves a genuinely deep class
    /// somewhere to grow into instead of pinning it at the end.
    private static let barHeadroom: Double = 1.5

    private func depthBar(_ row: ClassDepthRow) -> some View {
        let track = Self.barTrack
        let ceiling = max(1.0, row.expectedDraftable * Self.barHeadroom)
        let filled = min(track, CGFloat(Double(row.counts.draftable) / ceiling) * track)
        let draftable = max(1, row.counts.draftable)
        func segment(_ count: Int) -> CGFloat {
            guard row.counts.draftable > 0 else { return 0 }
            return filled * CGFloat(Double(count) / Double(draftable))
        }
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.backgroundTertiary)
                .frame(width: track, height: 8)

            HStack(spacing: 0) {
                Rectangle()
                    .fill(ClassDepthTier.blueChip.tint)
                    .frame(width: segment(row.counts.blueChip))
                Rectangle()
                    .fill(ClassDepthTier.roundOneTwo.tint)
                    .frame(width: segment(row.counts.roundOneTwo))
                Rectangle()
                    .fill(ClassDepthTier.roundThreeFive.tint)
                    .frame(width: segment(row.counts.roundThreeFive))
            }
            .frame(height: 8)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            // Where a league-typical class would have reached.
            Rectangle()
                .fill(Color.textPrimary.opacity(0.75))
                .frame(width: 1.5, height: 14)
                .offset(x: track / CGFloat(Self.barHeadroom))
        }
        .frame(width: track, height: 14, alignment: .leading)
        .accessibilityHidden(true)
    }

    /// Colour key for the bar's segments \u{2014} presence only, never a count. A dim
    /// dot says "this class has nobody in that band", which is a scouting read;
    /// a number would be a spreadsheet the media board can't actually back.
    private func tierKey(_ tier: ClassDepthTier, present: Bool) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(present ? tier.tint : tier.tint.opacity(0.25))
                .frame(width: 6, height: 6)
            Text(tier.label)
                .font(.system(size: 9))
                .foregroundStyle(present ? Color.textSecondary : Color.textTertiaryReadable)
                .lineLimit(1)
        }
        .accessibilityHidden(true)
    }

    /// One of the men the media has highest in this group.
    private func topNameRow(_ prospect: CollegeProspect) -> some View {
        HStack(spacing: 6) {
            ProspectSelectionPositionBadge(position: prospect.position)

            Text(prospect.fullName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)

            Text(prospect.college)
                .font(.system(size: DSType.Size.micro))
                .foregroundStyle(Color.textTertiaryReadable)
                .lineLimit(1)

            ProspectMarketArrow(prospect: prospect)

            Spacer(minLength: 4)

            readCell(for: prospect)
        }
    }

    /// The one cell every name on this screen is measured by.
    ///
    /// A BAND only when the read is this building's own \u{2014} `ProspectFog.read`
    /// falls back to the media's projected-round band for anybody unscouted, and
    /// printing that as a letter would label the league's guess as work the user
    /// paid for. Unscouted men get the round itself, in grey, which is exactly
    /// what the media has said about them and no more.
    private func readCell(for prospect: CollegeProspect) -> some View {
        let read = ProspectFog.read(prospect)
        let isScouted = read.source == .scouts
        return Text(isScouted ? read.text : ProspectRoundFormat.projectedRoundText(for: prospect.draftProjection))
            .font(.system(size: 11, weight: .heavy))
            .foregroundStyle(isScouted ? Color.accentGold : Color.textTertiaryReadable)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: 52, alignment: .trailing)
            .accessibilityLabel(
                isScouted
                    ? read.accessibilityText
                    : "media projection \(ProspectRoundFormat.projectedRoundText(for: prospect.draftProjection))"
            )
    }

    // MARK: - Small parts

    private func chip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(tint.opacity(0.5), lineWidth: 1)
            )
    }

    private func needChip(_ level: String) -> some View {
        let tint: Color = level == "High" ? .danger : (level == "Med" ? .warning : .success)
        return HStack(spacing: 3) {
            Text("NEED")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Color.textTertiaryReadable)
            Text(level.uppercased())
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(tint)
        }
    }

    private func sectionHeader(_ title: String, systemImage: String, tint: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.bold))
            .foregroundStyle(tint)
            .textCase(nil)
    }

    private var footnote: some View {
        Text("Tiers are the MEDIA's projected round \u{2014} public information, and blunt on purpose. Gold grades are your own scouts; a grey \"Rd n\" is a man nobody in your building has filed on. The tick on each bar is what a league-typical class carries at that position.")
            .font(.caption2)
            .foregroundStyle(Color.textTertiaryReadable)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.3.sequence")
                .font(.system(size: 48))
                .foregroundStyle(Color.textTertiary)
            Text("No Draft Class Yet")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
            Text("The college class goes on the board in week \(TaskGenerator.draftClassOnBoardWeek) of the regular season.")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func accessibilityText(_ row: ClassDepthRow) -> String {
        var parts = ["\(row.group.longLabel): \(row.verdict.label.lowercased()) class"]
        parts.append(row.topEnd.phrase.lowercased())
        parts.append(row.needLevel == "Set" ? "your roster is stocked here" : "\(row.needLevel) need on your roster")
        return parts.joined(separator: ". ")
    }

    // MARK: - Build
    //
    // ONE pass, off ONE media board.

    private func rebuild() {
        let declared = prospects.filter(\.isDeclaringForDraft)
        guard !declared.isEmpty else {
            rows = []
            standouts = []
            summary = ClassDeclarationSummary()
            return
        }

        // The MEDIA board, computed pure over the declared class. `publicBoardRanks`
        // reads the mock slot, the projected round, the combine invite and college
        // production \u{2014} nothing of the user's own, and nothing hidden \u{2014} so it is
        // legal both as the blue-chip cut and as the order the names are taken in.
        let boardRank = DraftIntel.publicBoardRanks(for: declared)

        // The club's actual holes, ranked once. `teamNeedDeficits`, NOT
        // `topTeamNeeds`: the latter ranks by positional VALUE and hands back
        // {QB, DE, CB, WR, LT} for every full roster in the league, so a depth
        // screen built on it would stamp NEED on a group the Big Board calls
        // "Set" one tab away (#fleet review F3).
        var needRank: [Position: Int] = [:]
        for (index, position) in DraftEngine.teamNeedDeficits(roster: teamRoster, limit: 5).enumerated() {
            needRank[position] = index
        }

        // Bucket the class once. `ClassDepthGroup.matches` is exclusive and total
        // over the drafted positions, so every declared man lands in exactly one.
        var counts: [ClassDepthGroup: ClassDepthTierCounts] = [:]
        var members: [ClassDepthGroup: [CollegeProspect]] = [:]
        for prospect in declared {
            guard let group = ClassDepthGroup.allCases.first(where: { $0.matches(prospect.position) }) else { continue }
            let tier = ClassDepthTier.of(
                round: prospect.draftProjection,
                boardRank: boardRank[prospect.id]
            )
            counts[group, default: ClassDepthTierCounts()].add(tier)
            members[group, default: []].append(prospect)
        }

        let totalDraftable = counts.values.reduce(0) { $0 + $1.draftable }
        let totalTopEnd = counts.values.reduce(0) { $0 + $1.blueChip + $1.roundOneTwo }
        let shareTotal = ClassDepthGroup.allCases.reduce(0.0) { $0 + $1.leagueShare }

        rows = ClassDepthGroup.allCases.map { group in
            let tierCounts = counts[group] ?? ClassDepthTierCounts()
            let expected = shareTotal > 0
                ? Double(totalDraftable) * group.leagueShare / shareTotal
                : 0
            let pool = (members[group] ?? []).sorted {
                (boardRank[$0.id] ?? Int.max) < (boardRank[$1.id] ?? Int.max)
            }
            // Only men the media has inside the draft get named: a top-three
            // that is three seventh-round projections is not a top three, it is
            // a group with nobody in it, and the row already says so.
            let named = pool.filter { ($0.draftProjection ?? 9) <= 7 }.prefix(3)
            // A group's need is its BEST-ranked hole: the deficit read is
            // per-position, and "we are short a right guard" is a hole in the
            // offensive line whichever seat it sits in. Same vocabulary as the
            // interview room's NEED column \u{2014} the top two are High, the rest of
            // the five are Med, everything else is Set.
            let level: String = {
                guard let best = needRank
                    .filter({ group.matches($0.key) })
                    .map(\.value)
                    .min() else { return "Set" }
                return best < 2 ? "High" : "Med"
            }()
            let ratio = expected >= 1.0 ? Double(tierCounts.draftable) / expected : 1.0
            // The group's fair share of the class's early-round bodies: the same
            // league-share split the depth tick uses, applied to the top end.
            let expectedTop = totalDraftable > 0
                ? expected * Double(totalTopEnd) / Double(totalDraftable)
                : 0
            return ClassDepthRow(
                group: group,
                counts: tierCounts,
                expectedDraftable: expected,
                verdict: ClassDepthVerdict.of(ratio: ratio),
                topEnd: ClassDepthTopEnd.of(
                    topCount: tierCounts.blueChip + tierCounts.roundOneTwo,
                    blueChips: tierCounts.blueChip,
                    expectedTop: expectedTop
                ),
                needLevel: level,
                top: Array(named)
            )
        }

        summary = buildSummary(declared: declared)
        standouts = buildStandouts(declared: declared, boardRank: boardRank)
    }

    /// The declaration window's arithmetic.
    ///
    /// The withdrawn men are by construction NOT in the hub's list \u{2014} it filters
    /// on `isDeclaringForDraft`, which is exactly the flag they lost \u{2014} so the one
    /// number that needs the raw pool is read from the class store the hub itself
    /// loaded from. Everything else comes off the declared array the rest of the
    /// hub agrees with.
    private func buildSummary(declared: [CollegeProspect]) -> ClassDeclarationSummary {
        var result = ClassDeclarationSummary()
        // Off the SAME array the rows below are counted from, so the header and
        // the depth bars can never describe two different classes.
        result.declared = declared.count
        result.earlyEntries = declared.filter(\.isUnderclassman).count

        let pool = WeekAdvancer.currentDraftClass
        // `declarationStatus`, NOT `!isDeclaringForDraft`. `DraftDayCoordinator`
        // clears that flag on every man who comes off the board on draft night
        // ("consumed from future UDFA pools"), so counting it would report a
        // hundred drafted rookies as men who went back to school the moment the
        // draft ran. It never touches the status string, which stays what the
        // January window wrote.
        result.withdrew = pool.filter { $0.declarationStatus == .withdrawn }.count
        // The window's own idempotency test (`ScoutingEngine.generateDeclarations`
        // step 0): before it runs, `isDeclaringForDraft` carries the model default
        // of `true` for the entire class, and that pass is the only thing that
        // ever sets an underclassman to `false`. A generation-time
        // `declarationStatusRaw` check would NOT work here — `DraftClassBuilder
        // .assignDeclarationWindow` stamps every senior `.declared` in September.
        result.windowHeld = result.withdrew > 0
            || pool.contains { $0.isUnderclassman && !$0.isDeclaringForDraft }

        let reports = declared.reduce(0) { total, prospect in
            total + prospect.scoutingReports.filter { $0.phase == .seniorBowl }.count
        }
        result.seniorBowlReports = reports
        result.seniorBowlHeld = reports > 0
        return result
    }

    /// Who Mobile went well for.
    ///
    /// Two public signals, in order. The sharp one is `marketMove` \u{2014} the media
    /// has moved him up a round since the class opened, which after the January
    /// hook is the Senior Bowl's own `applyProjectionDrift` and nothing else. The
    /// blunt one is the week's own verdict, which `ScoutingEngine.runSeniorBowl`
    /// writes into the report's `productionNotes` for the eighteen practice
    /// winners. Neither reads a grade, so the list cannot leak the board.
    private func buildStandouts(
        declared: [CollegeProspect],
        boardRank: [UUID: Int]
    ) -> [CollegeProspect] {
        let attended = declared.filter { prospect in
            prospect.scoutingReports.contains { $0.phase == .seniorBowl }
        }
        guard !attended.isEmpty else { return [] }

        func wonTheWeek(_ prospect: CollegeProspect) -> Bool {
            prospect.scoutingReports.contains {
                $0.phase == .seniorBowl && ($0.productionNotes ?? "").contains("practice winner")
            }
        }

        let movers = attended
            .filter { ($0.marketMove ?? 0) > 0 }
            .sorted { lhs, rhs in
                let lhsMove = lhs.marketMove ?? 0
                let rhsMove = rhs.marketMove ?? 0
                if lhsMove != rhsMove { return lhsMove > rhsMove }
                return (boardRank[lhs.id] ?? Int.max) < (boardRank[rhs.id] ?? Int.max)
            }
        // `applyProjectionDrift` moves at most ten pairs a week, so the practice
        // winners the market has not yet re-priced fill the list out. Ordered by
        // the media board, which is the only ordering this screen is allowed.
        let winners = attended
            .filter { wonTheWeek($0) && ($0.marketMove ?? 0) <= 0 }
            .sorted { (boardRank[$0.id] ?? Int.max) < (boardRank[$1.id] ?? Int.max) }
        return Array((movers + winners).prefix(5))
    }
}
