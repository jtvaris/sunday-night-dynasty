import SwiftUI
import SwiftData

// MARK: - FreeAgencyView — Wave 1c, the list standard
//
// UI_REDESIGN_VISION §4 puts this screen LAST in Wave 1 and calls it a rebuild
// rather than a conversion, and the reason is visible in what it replaced: the
// old row was a four-deck `VStack` — a main line, a badge line, a rumour line, a
// contract-structure line and a two-column "vs Current Starter" card — roughly
// 140 pt per free agent. Eight men filled an iPad. There was no header row, so
// nothing said what any number meant; the widths were nine inline `frame`s that
// no header could ever agree with; and the row's only tap opened the
// negotiation sheet, so there was no way to READ a free agent before bidding on
// him.
//
// What the rebuild is, precisely:
//
//  1. `DSListRow` at `.scan` — one 44 pt row per man (§2.12: a row is a
//     control), so the list is scannable instead of readable-one-at-a-time.
//  2. A header row built from `DSListColumn`, so header and cell read the same
//     constant. It is hand-rolled out of `DSColumnHeader`'s vocabulary rather
//     than `DSListHeaderRow` because these header cells SORT — the same reason
//     the roster hand-rolls `RosterView.sortableHeader`.
//  3. The row body is a `NavigationLink` into `PlayerDetailView`. Reading a man
//     and bidding on him are two different acts: the push reads, the trailing
//     `OFFER` button bids. The negotiation flow itself is untouched — it is the
//     same `ContractExtensionSheet` with the same arguments.
//  4. `DSEmptyState` replaces the hand-rolled empty block, and it now answers
//     the third beat honestly: an empty list because the market is dry is a
//     different problem from an empty list because the user filtered it down to
//     kickers.
//
// **What the four prose decks became.** Nothing that was a FACT was dropped;
// what was dropped is prose that repeated per row:
//
//   * cap impact % and "cap after" → one `CAP` state slot, tone and value
//   * scheme fit badge              → the sortable `FIT` column
//   * starter comparison            → the sortable `VS ST` column
//   * competition / "Hot" flame     → the sortable `BIDS` column
//   * desired contract length       → the `YRS` column
//   * position need                 → the `NEED` state slot
//   * draft-alternative hint        → ONE screen-level "YOUR PICKS" fact, since
//     the per-row version printed the same first pick on every expensive row
//     regardless of position (§2.13's arithmetic gate: a number that says the
//     same thing on 300 rows is not a per-row number)
//   * "rumour" line and the guaranteed-money guess are gone. The first was
//     flavour derived from the two facts either side of it (motivation, market
//     interest) and the second was an invented 0.5 / 0.35 multiplier that no
//     engine backs — see the report; if either is wanted back it belongs on the
//     detail screen or in the offer sheet, not on 400 list rows.
//
// Two other §P7 corrections landed on the way through: the motivation badge's
// invented purple and the `.orange` "Hot" flame are gone (a category is not a
// status, so motivation is now an uncoloured word), and the gold rail that
// marked every OVR ≥ 75 row is gone (gold has three jobs and "good player" is
// none of them — the `OVR` cell already carries the rating ladder).

// MARK: - Position Filter

private enum FAPositionFilter: String, CaseIterable, Identifiable {
    case all  = "All"
    case qb   = "QB"
    case skill = "Skill"
    case ol   = "OL"
    case dl   = "DL"
    case lb   = "LB"
    case db   = "DB"
    case st   = "ST"

    var id: String { rawValue }

    /// Display label — adds clarification for the "Skill" group.
    var displayLabel: String {
        switch self {
        case .skill: return "Skill (WR/TE/RB)"
        default:     return rawValue
        }
    }

    func matches(_ position: Position) -> Bool {
        switch self {
        case .all:   return true
        case .qb:    return position == .QB
        case .skill: return [.RB, .FB, .WR, .TE].contains(position)
        case .ol:    return [.LT, .LG, .C, .RG, .RT].contains(position)
        case .dl:    return [.DE, .DT].contains(position)
        case .lb:    return [.OLB, .MLB].contains(position)
        case .db:    return [.CB, .FS, .SS].contains(position)
        case .st:    return [.K, .P].contains(position)
        }
    }
}

// MARK: - Sort column
//
// One case per COLUMN, because sorting now lives in the header row rather than
// in a second "Sort:" strip above it. The old strip carried six words that
// named columns the list did not have — a user who tapped "Scheme" had no way
// to see the scheme fit he had just sorted by.

private enum FASortColumn {
    case position
    case name
    case schemeFit
    case age
    case overall
    case vsStarter
    case ask
    case years
    case interest
}

// MARK: - Scheme Fit Level

private enum SchemeFitLevel: String {
    case good = "Good"
    case ok   = "OK"
    case poor = "Poor"

    /// Semantic status at a stated threshold (§P7 rule 2) — this is not a 0–100
    /// rating, so it gets no ladder colour. `ok` is deliberately uncoloured:
    /// "he fits well enough" is not a caution.
    var color: Color {
        switch self {
        case .good: return .success
        case .ok:   return .textSecondary
        case .poor: return .danger
        }
    }

    /// Higher is better, so the header's default descending tap puts the men
    /// who fit the scheme at the top.
    var rank: Int {
        switch self {
        case .good: return 2
        case .ok:   return 1
        case .poor: return 0
        }
    }
}

// MARK: - Position Need Level

private enum NeedLevel: String {
    case high = "High"
    case med  = "Med"
    case low  = "Low"

    var tone: DSStatusPill.Tone {
        switch self {
        case .high: return .bad
        case .med:  return .warn
        case .low:  return .neutral
        }
    }

    var priority: Int {
        switch self {
        case .high: return 3
        case .med:  return 2
        case .low:  return 1
        }
    }
}

// MARK: - FreeAgencyView

struct FreeAgencyView: View {

    let career: Career

    @Environment(\.modelContext) private var modelContext

    /// TRACK B — the same fog port the roster row carries. A rookie who has not
    /// reported to camp shows his scouting BAND where his OVR would be; nobody
    /// else changes. Moved here with the list rebuild rather than left behind:
    /// undrafted rookies land in this pool, and this screen prints an OVR.
    @Environment(\.rookieFog) private var rookieFog

    @State private var allFreeAgents: [Player] = []
    @State private var freeAgentData: [UUID: FreeAgentInfo] = [:]
    @State private var team: Team?
    @State private var teamRoster: [Player] = []
    @State private var teamCoaches: [Coach] = []
    @State private var teamDraftPicks: [DraftPick] = []
    @State private var positionFilter: FAPositionFilter = .all
    @State private var sortColumn: FASortColumn = .overall
    @State private var sortAscending: Bool = false
    @State private var targetedPlayerIDs: Set<UUID> = []
    @State private var isLoading: Bool = true

    /// The ONE sheet on this screen, item-driven.
    ///
    /// It was `@State selectedPlayer` + `@State showNegotiationSheet`, which is
    /// the two-variable shape that has produced silently-dismissing sheets four
    /// times in this codebase. One `.sheet(item:)`, one source of truth: the
    /// player being negotiated with.
    @State private var negotiationTarget: Player?

    // MARK: Derived caches
    //
    // Every one of these used to be recomputed inside the row body, which meant
    // `ContractEngine.estimateMarketValue` ran once per visible row per frame
    // AND `n log n` times inside the sort comparator. They are pure functions of
    // data that only changes at load, so they are computed once at load. No
    // engine call changed; only how often it runs.

    /// Estimated market value per year, in thousands, keyed by player.
    @State private var marketValues: [UUID: Int] = [:]
    /// Scheme fit against the staff's installed scheme. Absent = no coordinator
    /// or no scheme on file, and the column prints an honest dash.
    @State private var schemeFits: [UUID: SchemeFitLevel] = [:]
    /// Best OVR on the roster at each position — the man a signing would have to
    /// beat.
    @State private var starterOVRByPosition: [Position: Int] = [:]
    /// Team needs, in priority order, and the same reads keyed by position group
    /// for the row's `NEED` slot.
    @State private var teamNeeds: [PositionNeed] = []
    @State private var needByGroup: [String: NeedLevel] = [:]

    /// The salary cap to use for market value estimates; updated when team is loaded.
    private var currentSalaryCap: Int {
        team?.salaryCap ?? ContractEngine.openingSalaryCap
    }

    /// Current FA round from career state (1-6).
    private var currentRound: Int {
        max(1, career.freeAgencyRound)
    }

    /// Total FA rounds.
    private let totalRounds = 6

    /// Inter-column gap in the trailing block. Non-zero for the same reason the
    /// roster's is: the header is right-anchored against the same edge, and at
    /// spacing 0 the labels drift left of the numbers they label.
    private static let columnGap: CGFloat = 6
    /// The trailing `OFFER` button. Reserved in the header so the last data
    /// column still sits over its own label.
    private static let offerColumn: CGFloat = 56
    /// Row insets, mirrored by the pinned header so each label sits over its
    /// own column.
    private static let rowLeadingInset: CGFloat = 8
    private static let rowTrailingInset: CGFloat = 16

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            if isLoading {
                VStack(spacing: DSSpacing.sm) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(1.5)
                        .tint(Color.accentBlue)
                    Text("Loading Free Agency\u{2026}")
                        .font(DSType.text(14, .regular, prose: true))
                        .foregroundStyle(Color.textSecondary)
                }
            } else {
                // Filtered and sorted ONCE per body pass, then threaded down.
                // The band prints the count, the header only exists when there
                // are rows to label, and the list draws them — three readers of
                // one 400-element sort, not three sorts.
                let rows = filteredAndSorted
                VStack(spacing: 0) {
                    statusBand(rowCount: rows.count)
                    needsStrip
                    positionLenses
                    if !rows.isEmpty {
                        columnHeaders
                            .padding(.leading, Self.rowLeadingInset)
                            .padding(.trailing, Self.rowTrailingInset)
                            .padding(.vertical, 3)
                            .background(Color.backgroundPrimary)
                        Divider().overlay(Color.surfaceBorder)
                    }
                    playerList(rows)
                    if !targetedPlayerIDs.isEmpty {
                        targetsSummaryBar
                    }
                }
            }
        }
        .navigationTitle("Free Agency")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            loadData()
            isLoading = false
        }
        // ONE sheet on this screen. See `negotiationTarget`.
        .sheet(item: $negotiationTarget) { player in
            if let team {
                NavigationStack {
                    ContractExtensionSheet(
                        player: player,
                        team: team,
                        capMode: career.capMode
                    )
                }
            }
        }
    }

    // MARK: - Status Band
    //
    // The round indicator and the cap banner were two stacked bands saying four
    // numbers between them. One band, four facts, one type voice — and the
    // fourth fact ("YOUR PICKS") is the draft-alternative hint, promoted out of
    // the rows to the one place where it is true exactly once.

    private func statusBand(rowCount: Int) -> some View {
        HStack(alignment: .center, spacing: DSSpacing.lg) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: DSSpacing.xxs) {
                    Text(FreeAgencyStep.roundLabel(currentRound).uppercased())
                        .font(DSType.display(13, .heavy))
                        .tracking(0.6)
                        .foregroundStyle(Color.textPrimary)
                    Text("of \(totalRounds)")
                        .font(DSType.display(13, .semibold))
                        .foregroundStyle(Color.textTertiary)
                }
                roundDots
            }

            Spacer(minLength: DSSpacing.sm)

            bandMetric(
                "Cap Space",
                value: formatMillions(team?.availableCap ?? 0),
                tint: (team?.availableCap ?? 0) >= 0 ? Color.success : Color.danger
            )
            bandMetric(
                "Available",
                value: formattedCount(rowCount),
                tint: Color.textPrimary
            )
            bandMetric(
                "Your Picks",
                value: draftCapitalSummary,
                tint: Color.textSecondary
            )
        }
        .padding(.horizontal, DSSpacing.lg)
        .padding(.vertical, DSSpacing.sm)
        .background(Color.backgroundSecondary)
        .overlay(
            Rectangle()
                .fill(Color.surfaceBorder)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    private func bandMetric(_ label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(label.uppercased())
                .font(DSType.display(11, .heavy))
                .tracking(0.5)
                .foregroundStyle(Color.textTertiary)
            Text(value)
                .font(DSType.display(17, .heavy))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private var roundDots: some View {
        HStack(spacing: 4) {
            ForEach(1...totalRounds, id: \.self) { round in
                Circle()
                    .fill(round <= currentRound ? Color.accentBlue : Color.backgroundTertiary)
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Round \(currentRound) of \(totalRounds)")
    }

    /// The draft capital this year, said once. Empty when the user holds no
    /// picks — an absent line rather than "Rd —".
    private var draftCapitalSummary: String {
        let rounds = teamDraftPicks
            .filter { !$0.isComplete }
            .map(\.round)
            .sorted()
        guard !rounds.isEmpty else { return "None" }
        return rounds.prefix(4).map { "Rd \($0)" }.joined(separator: " \u{00B7} ")
    }

    // MARK: - Needs Strip

    @ViewBuilder
    private var needsStrip: some View {
        if !teamNeeds.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DSSpacing.xxs) {
                    Text("NEEDS")
                        .font(DSType.display(11, .heavy))
                        .tracking(0.6)
                        .foregroundStyle(Color.textSecondary)
                    // The bespoke need chip is gone: a need level is a state at
                    // a stated threshold, which is exactly what `DSStatusPill`
                    // is, and the row's own `NEED` slot now speaks the same
                    // three words in the same three tones.
                    ForEach(teamNeeds.prefix(6)) { need in
                        DSStatusPill(
                            label: need.position,
                            tone: need.level.tone,
                            value: need.level.rawValue,
                            showsDot: false,
                            spokenLabel: "\(need.position): \(need.level.rawValue) need"
                        )
                    }
                }
                .padding(.horizontal, DSSpacing.lg)
                .padding(.vertical, DSSpacing.xs)
            }
            .background(Color.backgroundSecondary)
            .overlay(
                Rectangle()
                    .fill(Color.surfaceBorder)
                    .frame(height: 1),
                alignment: .bottom
            )
        }
    }

    // MARK: - Position Lenses
    //
    // §2.2's one control style. The screen shipped its own 30 pt capsule with
    // its own selected fill; `DSLensTabs` is the capsule the vision sanctions,
    // measured at 44 pt, with `accentBlue` as the one selected fill.

    private var positionLenses: some View {
        DSLensTabs(
            selection: $positionFilter,
            lenses: FAPositionFilter.allCases,
            label: { $0.displayLabel },
            title: "Position"
        )
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.xxs)
        .background(Color.backgroundSecondary)
        .overlay(
            Rectangle()
                .fill(Color.surfaceBorder)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    // MARK: - Column Headers
    //
    // Built from `DSListColumn`, in the row's own anatomy order, with the two
    // leading gutters (the target star, the portrait) RESERVED rather than
    // labelled — the header-drift bug documented twice in this codebase.

    private var columnHeaders: some View {
        HStack(spacing: 0) {
            // The leading star button: unlabelled, but present on every row.
            Color.clear.frame(width: DSListColumn.leadingAction, height: 1)

            sortHeader("POS", column: .position, width: DSListColumn.position)

            // The portrait slot.
            Color.clear.frame(width: DSListColumn.scanPortrait, height: 1)

            sortHeader("NAME", column: .name, width: nil, alignment: .leading)
                .frame(minWidth: DSListColumn.identityMin, alignment: .leading)
                .padding(.leading, DSListColumn.identityGap)

            Spacer(minLength: 2)

            HStack(spacing: Self.columnGap) {
                sortHeader("FIT",    column: .schemeFit,   width: DSListColumn.label)
                sortHeader("AGE",    column: .age,         width: DSListColumn.age)
                headerLabel("TRD",   width: DSListColumn.glyph)
                sortHeader("OVR",    column: .overall,     width: DSListColumn.ovr)
                sortHeader("VS ST",  column: .vsStarter,   width: DSListColumn.meet)
                sortHeader("ASK/YR", column: .ask, width: DSListColumn.money)
                sortHeader("YRS",    column: .years,       width: DSListColumn.tight)
                sortHeader("BIDS",   column: .interest,    width: DSListColumn.meet)
            }

            // The row's disclosure gutter and the OFFER button: reserved, not
            // labelled, so `BIDS` stays over its own numbers.
            Color.clear.frame(width: DSListColumn.affordance, height: 1)
            Color.clear.frame(width: Self.offerColumn, height: 1)
        }
        .font(DSType.display(11, .heavy))
        .foregroundStyle(Color.textTertiary)
        .textCase(.uppercase)
    }

    private func headerLabel(_ title: String, width: CGFloat) -> some View {
        Text(title)
            .tracking(0.6)
            .dsColumn(width)
            .foregroundStyle(Color.textTertiary)
    }

    /// A sortable header cell. Same behaviour as the roster's, deliberately: a
    /// new column starts descending (best first), and tapping the active column
    /// flips it.
    private func sortHeader(
        _ title: String,
        column: FASortColumn,
        width: CGFloat?,
        alignment: Alignment = .center
    ) -> some View {
        let isActive = sortColumn == column
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if isActive {
                    sortAscending.toggle()
                } else {
                    sortColumn = column
                    sortAscending = false
                }
            }
        } label: {
            HStack(spacing: 2) {
                Text(title)
                    .tracking(0.6)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if isActive {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                }
            }
            .frame(width: width, alignment: alignment)
            .frame(minHeight: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isActive ? Color.accentBlue : Color.textTertiary)
        .accessibilityLabel("Sort by \(title)")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    // MARK: - Player List

    @ViewBuilder
    private func playerList(_ rows: [Player]) -> some View {
        if rows.isEmpty {
            DSEmptyState(
                density: .scan,
                icon: "person.slash",
                title: positionFilter == .all
                    ? "No Free Agents Left"
                    : "No \(positionFilter.rawValue) Free Agents",
                message: emptyStateMessage,
                actions: positionFilter == .all
                    ? []
                    : [
                        .init(
                            title: "Show All Positions",
                            systemImage: "line.3.horizontal.decrease.circle",
                            isPrimary: true
                        ) {
                            positionFilter = .all
                        }
                    ]
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(rows) { player in
                    freeAgentRow(player)
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
        }
    }

    private var emptyStateMessage: String {
        if positionFilter == .all {
            return "Every unsigned veteran has come off the board. New names arrive when contracts expire at the end of the season."
        }
        return "Nobody left unsigned fits the \(positionFilter.displayLabel) filter. Widen it to see who is still on the market."
    }

    // MARK: - Free Agent Row
    //
    // Leading action, row, trailing action — the same three-part shape the Big
    // Board ships (mark button · `NavigationLink` · film-study button), because
    // a row that both READS and BIDS needs two targets and only one of them can
    // be the whole row.

    private func freeAgentRow(_ player: Player) -> some View {
        HStack(spacing: 0) {
            targetButton(for: player)

            NavigationLink(destination: PlayerDetailView(player: player)) {
                listRow(for: player)
            }

            offerButton(for: player)
        }
        .listRowBackground(Color.backgroundSecondary)
        .listRowSeparatorTint(Color.surfaceBorder)
        .listRowInsets(
            EdgeInsets(
                top: 0,
                leading: Self.rowLeadingInset,
                bottom: 0,
                trailing: Self.rowTrailingInset
            )
        )
    }

    private func listRow(for player: Player) -> some View {
        DSListRow(
            density: .scan,
            // No rank slot: a free-agent market is filtered and re-sorted eight
            // ways, so a "#3" would mean something different after every tap.
            badge: DSRowBadge(
                text: player.position.rawValue,
                tint: positionColor(player.position),
                accessibilityLabel: "\(player.position.rawValue), \(player.position.side.rawValue)"
            ),
            // The row DRAWS its own chevron rather than relying on the List to
            // add one. `DSListRow`'s `.none` is for a link that IS the whole
            // row (the roster); this link is one of three views in the row's
            // `HStack`, which is the Big Board's shape — and the board proves
            // the List adds nothing in that shape, because its header reserves
            // exactly `DSListColumn.affordance` for a handle the row draws
            // itself and its columns line up. Same 22 pt, reserved on both
            // sides, whoever draws it.
            affordance: .disclosure
        ) {
            // Portrait (30 pt) inside the 36 pt slot the header reserves.
            PersonFaceView(player: player, size: .small)
                .padding(.leading, DSListColumn.identityGap)
        } identity: {
            identityBlock(for: player)
        } columns: {
            Spacer(minLength: 2)

            HStack(spacing: Self.columnGap) {
                fitCell(for: player)
                ageCell(for: player)
                trendCell(for: player)
                ovrCell(for: player)
                vsStarterCell(for: player)
                moneyCell(for: player)
                yearsCell(for: player)
                bidsCell(for: player)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText(for: player))
    }

    // MARK: Identity block

    /// Name line, then the two reserved state slots.
    ///
    /// `DSListRow` owns the identity SLOT; the screen owns what goes in it. The
    /// slot set is chosen ONCE for this list and never per row: `NEED` (does he
    /// fill a hole in this roster) and `CAP` (can this building afford him). An
    /// unset `NEED` is a dimmed dashed word, so what the user scans down the
    /// column is the gap.
    private func identityBlock(for player: Player) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: DSSpacing.xxs) {
                Text(player.fullName)
                    .font(DSType.text(DSListDensity.scan.nameSize, .semibold, prose: true))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)

                // What he is chasing. A category, not a status, so it carries
                // no colour — the old badge invented a purple for "Fame" and
                // spent gold on "Winning" (§P7, §P5).
                Text(motivationLabel(player.personality.motivation))
                    .font(DSType.display(11, .semibold))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }

            DSStateSlotRow(slots: [needSlot(for: player), capSlot(for: player)])
        }
    }

    private func needSlot(for player: Player) -> DSStateSlot {
        guard let level = needByGroup[positionGroupName(player.position)] else {
            return DSStateSlot(
                label: "NEED",
                tone: .empty,
                spokenLabel: "Not a position of need"
            )
        }
        return DSStateSlot(
            label: "NEED",
            tone: level.tone,
            value: level.rawValue,
            spokenLabel: "\(level.rawValue) need at \(positionGroupName(player.position))"
        )
    }

    /// What signing him at the estimate does to the cap — the old row's two
    /// separate reads ("8% of cap" and "Cap after: $12.1M") in one slot, so the
    /// two can never disagree.
    private func capSlot(for player: Player) -> DSStateSlot {
        let asking = askingPrice(for: player)
        let cap = currentSalaryCap
        let pct = cap > 0 ? Int((Double(asking) / Double(cap) * 100).rounded()) : 0

        if let team, team.availableCap - asking < 0 {
            let over = asking - team.availableCap
            return DSStateSlot(
                label: "CAP",
                tone: .bad,
                value: "OVER",
                spokenLabel: "Signing him at the estimate puts you \(formatMillions(over)) over the cap"
            )
        }

        let tone: DSStatusPill.Tone
        switch pct {
        case 12...:  tone = .warn
        case 7..<12: tone = .neutral
        default:     tone = .ok
        }
        return DSStateSlot(
            label: "CAP",
            tone: tone,
            value: pct <= 0 ? "<1%" : "\(pct)%",
            spokenLabel: "Uses \(pct) percent of the salary cap"
        )
    }

    // MARK: Columns

    private func fitCell(for player: Player) -> some View {
        Group {
            if let fit = schemeFits[player.id] {
                Text(fit.rawValue)
                    .font(DSType.display(11, .heavy))
                    .foregroundStyle(fit.color)
            } else {
                Text("\u{2014}")
                    .font(DSType.display(11, .semibold))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .dsColumn(DSListColumn.label)
        .accessibilityLabel(
            schemeFits[player.id].map { "Scheme fit \($0.rawValue)" }
                ?? "Scheme fit unknown \u{2014} no coordinator scheme on file"
        )
    }

    private func ageCell(for player: Player) -> some View {
        Text("\(player.age)")
            .font(DSType.display(13, .semibold))
            .foregroundStyle(Color.textSecondary)
            .dsColumn(DSListColumn.age)
            .accessibilityLabel("Age \(player.age)")
    }

    /// Where he is on his own age curve. Reserved on every row — an absent
    /// arrow is drawn as a hidden one, so the column cannot shift.
    private func trendCell(for player: Player) -> some View {
        Group {
            if let trend = ageTrend(for: player) {
                Image(systemName: trend.iconName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(trend.color)
            } else {
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .bold))
                    .hidden()
            }
        }
        .dsColumn(DSListColumn.glyph)
        .accessibilityLabel(ageTrend(for: player)?.spoken ?? "At his peak")
    }

    /// The OVR cell, fog-aware. A rookie who has not reported to camp shows the
    /// band your scouts gave him, never an exact number.
    @ViewBuilder
    private func ovrCell(for player: Player) -> some View {
        if rookieFog.isFogged(player) {
            RookieBandChip(player: player, font: DSType.display(11, .heavy))
                .dsColumn(DSListColumn.ovr)
        } else {
            Text("\(player.overall)")
                .font(DSType.display(15, .heavy))
                .foregroundStyle(Color.forRating(player.overall))
                .dsColumn(DSListColumn.ovr)
                .accessibilityLabel("Overall \(player.overall)")
        }
    }

    /// What he is against the man currently playing that spot. `NEW` means the
    /// roster has nobody there at all, which is the strongest read on the row.
    private func vsStarterCell(for player: Player) -> some View {
        Group {
            if let starterOVR = starterOVRByPosition[player.position] {
                let diff = player.overall - starterOVR
                Text(diff > 0 ? "+\(diff)" : "\(diff)")
                    .font(DSType.display(13, .heavy))
                    .foregroundStyle(starterDiffColor(diff))
            } else {
                Text("NEW")
                    .font(DSType.display(11, .heavy))
                    .foregroundStyle(Color.accentBlue)
            }
        }
        .dsColumn(DSListColumn.meet)
        .accessibilityLabel(vsStarterSpoken(for: player))
    }

    private func moneyCell(for player: Player) -> some View {
        Text(formatMillions(askingPrice(for: player)))
            .font(DSType.display(13, .heavy))
            .foregroundStyle(Color.textPrimary)
            .dsColumn(DSListColumn.money)
            .accessibilityLabel("Asking \(formatMillions(askingPrice(for: player))) per year")
    }

    private func yearsCell(for player: Player) -> some View {
        Group {
            if let years = freeAgentData[player.id]?.desiredYears {
                Text("\(years)y")
                    .font(DSType.display(13, .semibold))
                    .foregroundStyle(Color.textSecondary)
            } else {
                Text("\u{2014}")
                    .font(DSType.display(11, .semibold))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .dsColumn(DSListColumn.tight)
        .accessibilityLabel(
            freeAgentData[player.id].map { "Wants \($0.desiredYears) years" } ?? "Contract length unknown"
        )
    }

    /// How many clubs are in on him. The old row said this three times — a
    /// flame, a sentence and a rumour line — in one column now, with the
    /// threshold tones the sentence used.
    private func bidsCell(for player: Player) -> some View {
        Group {
            if let interest = freeAgentData[player.id]?.marketInterest {
                Text("\(interest)")
                    .font(DSType.display(13, .heavy))
                    .foregroundStyle(interestColor(interest))
            } else {
                Text("\u{2014}")
                    .font(DSType.display(11, .semibold))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .dsColumn(DSListColumn.meet)
        .accessibilityLabel(
            freeAgentData[player.id].map { info in
                info.marketInterest >= 7
                    ? "\(info.marketInterest) teams interested \u{2014} bidding war"
                    : "\(info.marketInterest) team\(info.marketInterest == 1 ? "" : "s") interested"
            } ?? "Market interest unknown"
        )
    }

    // MARK: Row actions

    /// The leading target star — the one row action that lives OUTSIDE the row
    /// anatomy, in `DSListColumn.leadingAction`'s 44 pt.
    private func targetButton(for player: Player) -> some View {
        let isTargeted = targetedPlayerIDs.contains(player.id)
        return Button {
            toggleTarget(player.id)
        } label: {
            Image(systemName: isTargeted ? "star.fill" : "star")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isTargeted ? Color.accentGold : Color.textTertiary)
                .frame(width: DSListColumn.leadingAction, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isTargeted ? "Untarget \(player.fullName)" : "Target \(player.fullName)")
    }

    /// The trailing bid. Secondary styling on purpose: P5 gives gold to the one
    /// primary commit on a screen, and a market with four hundred rows cannot
    /// have four hundred of them. The commit itself is inside the sheet.
    private func offerButton(for player: Player) -> some View {
        Button {
            negotiationTarget = player
        } label: {
            Text("OFFER")
                .font(DSType.display(11, .heavy))
                .tracking(0.5)
                .foregroundStyle(team == nil ? Color.textTertiary : Color.textPrimary)
                .frame(width: Self.offerColumn - DSSpacing.xxs, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                        .fill(Color.backgroundTertiary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                        .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                )
                // 44 pt measured, even though the painted chip is 32 (§2.12).
                .frame(width: Self.offerColumn, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(team == nil)
        .accessibilityLabel("Open contract negotiation with \(player.fullName)")
    }

    // MARK: - Targets Summary Bar

    private var targetsSummaryBar: some View {
        let targeted = allFreeAgents.filter { targetedPlayerIDs.contains($0.id) }
        let totalSalary = targeted.reduce(0) { $0 + askingPrice(for: $1) }
        let capRemaining = (team?.availableCap ?? 0) - totalSalary

        return HStack(spacing: DSSpacing.sm) {
            Image(systemName: "star.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.accentGold)

            Text("\(targeted.count) target\(targeted.count == 1 ? "" : "s") selected")
                .font(DSType.text(13, .semibold, prose: true))
                .foregroundStyle(Color.textPrimary)

            Text("\u{00B7}")
                .foregroundStyle(Color.textTertiary)

            Text("~\(formatMillions(totalSalary))/yr")
                .font(DSType.display(13, .heavy))
                .foregroundStyle(Color.textPrimary)

            Text("\u{00B7}")
                .foregroundStyle(Color.textTertiary)

            Text("Cap remaining: \(formatMillions(capRemaining))")
                .font(DSType.display(13, .heavy))
                .foregroundStyle(capRemaining >= 0 ? Color.success : Color.danger)

            Spacer()

            Button {
                targetedPlayerIDs.removeAll()
            } label: {
                Text("Clear")
                    .font(DSType.text(13, .semibold))
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, DSSpacing.sm)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DSSpacing.lg)
        .padding(.vertical, DSSpacing.xxs)
        .background(Color.backgroundSecondary)
        .overlay(
            Rectangle()
                .fill(Color.surfaceBorder)
                .frame(height: 1),
            alignment: .top
        )
    }

    // MARK: - Filtering & Sorting
    //
    // One ascending pass, reversed when the header says descending, so every
    // column flips the same way and no comparator carries a hidden direction.

    private var filteredAndSorted: [Player] {
        let filtered = allFreeAgents.filter { positionFilter.matches($0.position) }
        let ascending: [Player]

        switch sortColumn {
        case .position:
            ascending = filtered.sorted { $0.position.rawValue < $1.position.rawValue }
        case .name:
            ascending = filtered.sorted {
                $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending
            }
        case .schemeFit:
            ascending = filtered.sorted {
                (schemeFits[$0.id]?.rank ?? -1) < (schemeFits[$1.id]?.rank ?? -1)
            }
        case .age:
            ascending = filtered.sorted { $0.age < $1.age }
        case .overall:
            ascending = filtered.sorted { $0.overall < $1.overall }
        case .vsStarter:
            ascending = filtered.sorted { starterDiff(for: $0) < starterDiff(for: $1) }
        case .ask:
            ascending = filtered.sorted { askingPrice(for: $0) < askingPrice(for: $1) }
        case .years:
            ascending = filtered.sorted {
                (freeAgentData[$0.id]?.desiredYears ?? 0) < (freeAgentData[$1.id]?.desiredYears ?? 0)
            }
        case .interest:
            ascending = filtered.sorted {
                (freeAgentData[$0.id]?.marketInterest ?? 0) < (freeAgentData[$1.id]?.marketInterest ?? 0)
            }
        }

        return sortAscending ? ascending : ascending.reversed()
    }

    // MARK: - Loading

    private func loadData() {
        // Load free agents: contractYearsRemaining == 0 and no team
        // `teamID == nil` is the one team predicate that does NOT scope a
        // fetch to one save — the other career's ~400 unsigned free agents look
        // exactly like this career's.
        let cid = career.id
        // Four `&&` clauses tip `#Predicate` into an unbounded type-check, so
        // the cheap-but-selective trio runs in SQL and `isRetired` is filtered
        // on the (already tiny) result.
        var descriptor = FetchDescriptor<Player>(
            predicate: #Predicate<Player> { player in
                player.careerID == cid
                    && player.contractYearsRemaining == 0
                    && player.teamID == nil
            }
        )
        descriptor.sortBy = [SortDescriptor(\Player.annualSalary, order: .reverse)]
        allFreeAgents = ((try? modelContext.fetch(descriptor)) ?? []).filter { !$0.isRetired }

        // Load player's team for cap info
        guard let teamID = career.teamID else {
            rebuildCaches()
            return
        }
        let teamDescriptor = FetchDescriptor<Team>(predicate: #Predicate { $0.id == teamID })
        team = try? modelContext.fetch(teamDescriptor).first

        // Load team roster for starter comparison
        let rosterDescriptor = FetchDescriptor<Player>(predicate: #Predicate { $0.teamID == teamID })
        teamRoster = (try? modelContext.fetch(rosterDescriptor)) ?? []

        // Load team coaches for scheme fit
        let coachDescriptor = FetchDescriptor<Coach>(predicate: #Predicate { $0.teamID == teamID })
        teamCoaches = (try? modelContext.fetch(coachDescriptor)) ?? []

        // Load team draft picks — one screen-level "YOUR PICKS" read.
        let currentSeason = career.currentSeason
        let pickDescriptor = FetchDescriptor<DraftPick>(
            predicate: #Predicate { $0.currentTeamID == teamID && $0.seasonYear == currentSeason && $0.isComplete == false }
        )
        teamDraftPicks = (try? modelContext.fetch(pickDescriptor)) ?? []

        // Generate FA market data
        let cap = team?.salaryCap ?? ContractEngine.openingSalaryCap
        let market = FreeAgencyEngine.generateFreeAgentMarket(allPlayers: allFreeAgents, salaryCap: cap)
        for fa in market {
            freeAgentData[fa.player.id] = FreeAgentInfo(
                askingPrice: fa.askingPrice,
                desiredYears: fa.desiredYears,
                marketInterest: fa.marketInterest
            )
        }

        rebuildCaches()
    }

    /// Everything the rows and the sorts read, computed once.
    ///
    /// These are the same functions the old row body called — the change is
    /// that `estimateMarketValue` and the scheme-fit switch now run once per
    /// player instead of once per player per frame plus `n log n` times inside
    /// every sort.
    private func rebuildCaches() {
        let cap = currentSalaryCap

        var values: [UUID: Int] = [:]
        var fits: [UUID: SchemeFitLevel] = [:]
        values.reserveCapacity(allFreeAgents.count)
        for player in allFreeAgents {
            values[player.id] = ContractEngine.estimateMarketValue(player: player, salaryCap: cap)
            if let fit = computeSchemeFit(for: player) {
                fits[player.id] = fit
            }
        }
        marketValues = values
        schemeFits = fits

        var starters: [Position: Int] = [:]
        for player in teamRoster {
            starters[player.position] = max(starters[player.position] ?? 0, player.overall)
        }
        starterOVRByPosition = starters

        teamNeeds = computeTeamNeeds()
        needByGroup = Dictionary(
            teamNeeds.map { ($0.position, $0.level) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// What his agent is asking, per year, in thousands.
    ///
    /// The old row printed `ContractEngine.estimateMarketValue` — the ladder
    /// price for his rating, which is NOT the number the agent walks into the
    /// room with. `FreeAgencyEngine.generateFreeAgentMarket` prices him off
    /// `agentDemand`, that is what FA Weekly quotes, and that is what a
    /// settlement is drawn against. One man with two prices on two screens is
    /// §2.13's arithmetic gate, so the column reads the ASK; the ladder price
    /// stays as the fallback for anyone the market pass filtered out.
    private func askingPrice(for player: Player) -> Int {
        if let ask = freeAgentData[player.id]?.askingPrice { return ask }
        return marketValues[player.id]
            ?? ContractEngine.estimateMarketValue(player: player, salaryCap: currentSalaryCap)
    }

    /// OVR above the incumbent. No incumbent counts as the full OVR, which puts
    /// "nobody plays this position" at the top of a descending `VS ST` sort —
    /// which is where it belongs.
    private func starterDiff(for player: Player) -> Int {
        player.overall - (starterOVRByPosition[player.position] ?? 0)
    }

    private func starterDiffColor(_ diff: Int) -> Color {
        if diff > 2 { return .success }
        if diff < -2 { return .danger }
        return .textSecondary
    }

    private func vsStarterSpoken(for player: Player) -> String {
        guard let starterOVR = starterOVRByPosition[player.position] else {
            return "No \(player.position.rawValue) on the roster \u{2014} immediate starter"
        }
        let diff = player.overall - starterOVR
        if diff > 2 { return "\(diff) points better than your starter" }
        if diff < -2 { return "\(-diff) points worse than your starter" }
        return "Level with your starter"
    }

    /// A count of rival clubs under the `BIDS` header, not a rating — P7 rule 2,
    /// status at a stated threshold. The sign is inverted on purpose (P7 rule 3):
    /// more bidders is worse news for the user, so a crowded market is `.bad`,
    /// and the VoiceOver label below says "bidding war" in words.
    private func interestColor(_ interest: Int) -> Color {
        if interest >= 7 { return .forStatus(.bad) }  // bidding war
        if interest >= 5 { return .forStatus(.warn) } // contested
        return .forStatus(.neutral)                   // quiet market
    }

    // MARK: - Scheme Fit

    private func computeSchemeFit(for player: Player) -> SchemeFitLevel? {
        let position = player.position

        // Determine team's scheme from coaching staff
        if position.side == .offense {
            guard let oc = teamCoaches.first(where: { $0.role == .offensiveCoordinator }),
                  let scheme = oc.offensiveScheme else { return nil }
            let score = evaluatePlayerOffensiveFit(player: player, scheme: scheme)
            return schemeFitFromScore(score)
        } else if position.side == .defense {
            guard let dc = teamCoaches.first(where: { $0.role == .defensiveCoordinator }),
                  let scheme = dc.defensiveScheme else { return nil }
            let score = evaluatePlayerDefensiveFit(player: player, scheme: scheme)
            return schemeFitFromScore(score)
        }
        return nil
    }

    private func evaluatePlayerOffensiveFit(player: Player, scheme: OffensiveScheme) -> Int {
        var score = 0
        let physical = player.physical

        switch player.positionAttributes {
        case .quarterback(let qb):
            switch scheme {
            case .airRaid, .spread:
                score = (qb.accuracyShort + qb.accuracyDeep + qb.armStrength) / 3
            case .westCoast, .proPassing:
                score = (qb.accuracyShort + qb.accuracyMid + qb.pocketPresence) / 3
            case .powerRun, .shanahan:
                score = (qb.pocketPresence + qb.scrambling + physical.strength) / 3
            case .rpo, .option:
                score = (qb.scrambling + physical.speed + qb.accuracyShort) / 3
            }
        case .wideReceiver(let wr):
            switch scheme {
            case .airRaid, .spread:
                score = (wr.routeRunning + wr.catching + physical.speed) / 3
            case .westCoast, .proPassing:
                score = (wr.routeRunning + wr.catching + wr.release) / 3
            case .powerRun, .shanahan:
                score = (physical.strength + wr.release + physical.speed) / 3
            default:
                score = (wr.routeRunning + wr.catching) / 2
            }
        case .runningBack(let rb):
            switch scheme {
            case .powerRun:
                score = (rb.breakTackle + rb.vision + physical.strength) / 3
            case .shanahan:
                score = (rb.vision + rb.elusiveness + physical.speed) / 3
            case .westCoast, .spread:
                score = (rb.receiving + rb.elusiveness + rb.vision) / 3
            default:
                score = (rb.vision + rb.elusiveness) / 2
            }
        case .offensiveLine(let ol):
            switch scheme {
            case .powerRun:
                score = (ol.runBlock + ol.anchor + physical.strength) / 3
            case .airRaid, .proPassing, .westCoast:
                score = (ol.passBlock + ol.anchor + physical.strength) / 3
            case .shanahan:
                score = (ol.pull + ol.runBlock + physical.agility) / 3
            default:
                score = (ol.runBlock + ol.passBlock) / 2
            }
        case .tightEnd(let te):
            switch scheme {
            case .airRaid, .spread, .westCoast:
                score = (te.catching + te.routeRunning + te.speed) / 3
            case .powerRun, .shanahan:
                score = (te.blocking + te.speed + physical.strength) / 3
            default:
                score = (te.catching + te.blocking) / 2
            }
        default:
            score = 65
        }
        return score
    }

    private func evaluatePlayerDefensiveFit(player: Player, scheme: DefensiveScheme) -> Int {
        var score = 0
        let physical = player.physical

        switch player.positionAttributes {
        case .defensiveBack(let db):
            switch scheme {
            case .pressMan:
                score = (db.manCoverage + db.press + physical.speed) / 3
            case .cover3, .tampa2:
                score = (db.zoneCoverage + db.ballSkills + physical.speed) / 3
            case .multiple, .hybrid:
                score = (db.manCoverage + db.zoneCoverage + db.press) / 3
            default:
                score = (db.manCoverage + db.zoneCoverage) / 2
            }
        case .linebacker(let lb):
            switch scheme {
            case .base34:
                score = (lb.tackling + lb.blitzing + physical.strength) / 3
            case .base43:
                score = (lb.tackling + lb.zoneCoverage + physical.speed) / 3
            case .tampa2:
                score = (lb.zoneCoverage + physical.speed + lb.tackling) / 3
            case .cover3:
                score = (lb.zoneCoverage + lb.tackling + physical.speed) / 3
            default:
                score = (lb.tackling + lb.zoneCoverage) / 2
            }
        case .defensiveLine(let dl):
            switch scheme {
            case .base43:
                score = (dl.passRush + dl.powerMoves + physical.strength) / 3
            case .base34:
                score = (dl.blockShedding + dl.powerMoves + physical.strength) / 3
            case .multiple, .hybrid:
                score = (dl.passRush + dl.finesseMoves + physical.agility) / 3
            default:
                score = (dl.passRush + dl.blockShedding) / 2
            }
        default:
            score = 65
        }
        return score
    }

    private func schemeFitFromScore(_ score: Int) -> SchemeFitLevel {
        switch score {
        case 75...:   return .good
        case 55..<75: return .ok
        default:      return .poor
        }
    }

    // MARK: - Age Trend

    private struct AgeTrend {
        let iconName: String
        let color: Color
        let spoken: String
    }

    /// Where he sits on his position's age curve. Semantic status at a stated
    /// threshold, never the rating ladder — an age is not a 0–100 rating (§P7).
    private func ageTrend(for player: Player) -> AgeTrend? {
        let peak = player.position.peakAgeRange
        if player.age > peak.upperBound {
            return AgeTrend(iconName: "arrow.down.right", color: .danger, spoken: "Past his peak years")
        } else if player.age < peak.lowerBound {
            return AgeTrend(iconName: "arrow.up.right", color: .success, spoken: "Still rising toward his peak")
        } else if player.age >= peak.upperBound - 1 {
            return AgeTrend(iconName: "arrow.right", color: .alertOrange, spoken: "At the end of his peak years")
        }
        return nil
    }

    // MARK: - Team Needs

    private struct PositionNeed: Identifiable {
        let position: String
        let level: NeedLevel

        var id: String { position }
    }

    private func computeTeamNeeds() -> [PositionNeed] {
        guard !teamRoster.isEmpty else { return [] }

        // Define ideal roster counts per position group
        let idealCounts: [(label: String, positions: [Position], ideal: Int)] = [
            ("QB", [.QB], 2),
            ("RB", [.RB, .FB], 3),
            ("WR", [.WR], 4),
            ("TE", [.TE], 2),
            ("OL", [.LT, .LG, .C, .RG, .RT], 8),
            ("DL", [.DE, .DT], 6),
            ("LB", [.OLB, .MLB], 5),
            ("DB", [.CB, .FS, .SS], 7),
        ]

        var needs: [PositionNeed] = []

        for group in idealCounts {
            let count = teamRoster.filter { group.positions.contains($0.position) }.count
            let bestOVR = teamRoster
                .filter { group.positions.contains($0.position) }
                .map(\.overall)
                .max() ?? 0

            let deficit = group.ideal - count
            let qualityIssue = bestOVR < 70

            if deficit >= 2 || (deficit >= 1 && qualityIssue) {
                needs.append(PositionNeed(position: group.label, level: .high))
            } else if deficit >= 1 || qualityIssue {
                needs.append(PositionNeed(position: group.label, level: .med))
            } else if bestOVR < 78 {
                needs.append(PositionNeed(position: group.label, level: .low))
            }
        }

        // Sort by priority
        return needs.sorted { $0.level.priority > $1.level.priority }
    }

    // MARK: - Target Toggle

    private func toggleTarget(_ playerID: UUID) {
        if targetedPlayerIDs.contains(playerID) {
            targetedPlayerIDs.remove(playerID)
        } else {
            targetedPlayerIDs.insert(playerID)
        }
    }

    // MARK: - Formatting Helpers

    private func positionColor(_ position: Position) -> Color {
        switch position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }

    private func motivationLabel(_ motivation: Motivation) -> String {
        switch motivation {
        case .money:   return "Money"
        case .fame:    return "Fame"
        case .winning: return "Winning"
        case .loyalty: return "Loyalty"
        case .stats:   return "Stats"
        }
    }

    private func formatMillions(_ thousands: Int) -> String {
        let millions = Double(thousands) / 1000.0
        if millions >= 1.0 {
            return String(format: "$%.1fM", millions)
        } else {
            return "$\(thousands)K"
        }
    }

    /// Format count with comma grouping.
    private func formattedCount(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    /// The position GROUP a need is keyed by. The needs table and the row slot
    /// read the same function, so a row can never claim a need the strip above
    /// it does not list.
    private func positionGroupName(_ position: Position) -> String {
        switch position {
        case .QB: return "QB"
        case .RB, .FB: return "RB"
        case .WR: return "WR"
        case .TE: return "TE"
        case .LT, .LG, .C, .RG, .RT: return "OL"
        case .DE, .DT: return "DL"
        case .OLB, .MLB: return "LB"
        case .CB, .FS, .SS: return "DB"
        case .K, .P: return "ST"
        }
    }

    private func accessibilityText(for player: Player) -> String {
        var parts: [String] = [
            player.fullName,
            player.position.rawValue,
            "age \(player.age)",
        ]
        if !rookieFog.isFogged(player) {
            parts.append("overall \(player.overall)")
        }
        parts.append("asking \(formatMillions(askingPrice(for: player))) per year")
        if let info = freeAgentData[player.id] {
            parts.append("wants \(info.desiredYears) years")
            parts.append("\(info.marketInterest) team\(info.marketInterest == 1 ? "" : "s") interested")
        }
        if let fit = schemeFits[player.id] {
            parts.append("\(fit.rawValue) scheme fit")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Free Agent Info Cache

private struct FreeAgentInfo {
    let askingPrice: Int
    let desiredYears: Int
    let marketInterest: Int
}

// MARK: - Preview

#Preview {
    NavigationStack {
        FreeAgencyView(career: Career(
            playerName: "Coach",
            role: .gm,
            capMode: .simple
        ))
    }
    .modelContainer(for: [Career.self, Player.self, Team.self, Coach.self, DraftPick.self], inMemory: true)
}
