import SwiftUI
import SwiftData

// Column widths, shared by the header and the row so a label always sits
// over its own cell.
//
// ONE elastic cell, everything after it fixed. That is the Big Board's layout
// and it is what this table was missing: the name column used to be pinned to a
// hard 130 pt, so the table drew itself 866 pt wide and STOPPED — a landscape
// iPad got a third of a screen of dead space to the right of it while
// "Nehemiah Pritchett" printed as "Nehemiah…" and the NEED / PARTIAL chips
// beside the name were cut off the end of their own cell.
//
// Now the name cell is a floor (`nameMin`) followed by a `Spacer`, so:
//
//   * the table fills whatever width it is given, in both orientations;
//   * every column after the gap is fixed AND anchored to the trailing edge,
//     in the pinned header and in each row alike, so they cannot drift out of
//     alignment however wide the name grows;
//   * in landscape the name cell takes its natural width and nothing truncates;
//   * in portrait the slack runs out and the name TEXT gives first — the chips
//     carry `layoutPriority(1)` and are laid out before it.
//
// The widest column set (the drills) still fits a portrait iPad without a
// sideways scroll: 40+32+132+8+40+56+46+38+96+380+16 = 884, plus 16 pt of list
// insets, inside 1024.
private enum CombineW {
    static let mark: CGFloat = 40
    static let rank: CGFloat = 32
    /// A floor, not a width — enough for a short name plus its chips in portrait.
    static let nameMin: CGFloat = 132
    /// The elastic gap. Everything after it is fixed and trailing-anchored.
    static let gap: CGFloat = 8
    static let pos: CGFloat = 40
    static let grade: CGFloat = 56
    static let prod: CGFloat = 46
    static let proj: CGFloat = 38
    static let college: CGFloat = 96

    // Physical block — the combine's own drills, the table's home mode.
    static let forty: CGFloat = 54
    static let bench: CGFloat = 52
    static let vertical: CGFloat = 52
    static let broad: CGFloat = 54
    static let cone: CGFloat = 56
    static let shuttle: CGFloat = 56
    static let drill: CGFloat = 56

    // Overview block. No NEED column: it is already a chip on his name, and a
    // fact printed twice on one row is a column spent on nothing.
    static let age: CGFloat = 30
    static let height: CGFloat = 42
    static let weight: CGFloat = 40
    static let risk: CGFloat = 64

    // Work-up block
    static let reports: CGFloat = 34
    static let tick: CGFloat = 38

    // Mental block
    static let tape: CGFloat = 42
    static let meet: CGFloat = 38
    static let band: CGFloat = 26

    // Position block
    static let skill: CGFloat = 32

    static let chevron: CGFloat = 16
}

/// The combine table.
///
/// It used to be a horizontally scrolling table nested inside a vertical one,
/// with its title bar and its risers/fallers strip pinned above both — three
/// scroll regions on one screen and no way for the hub's header to scroll away
/// with the content. It is a `List` now, like every other prospect surface:
/// the hub header is its first section, and the column headers — with the mode
/// chips above them — are a pinned section header.
///
/// The columns were then FROZEN at 866 pt to fit a portrait iPad, which fixed
/// the sideways scroll by giving a landscape one a third of a screen of dead
/// space instead. They stretch now: see `CombineW` for the one-elastic-cell
/// layout, borrowed off the Big Board, that fills either orientation without a
/// horizontal scroll and without the header drifting off its own columns.
struct CombineResultsView<Header: View>: View {
    let career: Career
    let prospects: [CollegeProspect]

    /// Whether this club's scouting department attended the combine. Drives the
    /// precision of every drill cell below (`ProspectFog.combineFidelity`).
    var scoutsAttended: Bool = false

    /// Cost in thousands of sending the department, shown on the in-tab CTA.
    var tripCost: Int = 0

    /// `nil` outside the combine phase or once the trip has been bought — the
    /// window is one phase wide, exactly like the hub's banner.
    var onSendScouts: (() -> Void)? = nil

    /// `false` when the scouting budget cannot cover `tripCost`.
    var canAffordTrip: Bool = true

    /// Forward exit out of the pre-invite empty state (#128). The one thing a
    /// user standing here in January can actually read is what the declared
    /// class looks like, so the dead end gets a door instead of a full stop.
    var onOpenClassDepth: (() -> Void)? = nil

    /// Shared with the Big Board and the Prospects list — the chips live in
    /// `ScoutingHubView` now, so a filter survives a tab switch.
    @Binding var positionFilter: ProspectPositionFilter

    /// Whether the hub's Insights block is open (#130).
    ///
    /// Two of this screen's blocks are insights rather than table: the title /
    /// invitee-count / fidelity header, and the RISERS / FALLERS rails. Both
    /// used to sit permanently between the hub's four control rows and the first
    /// combine row, which is most of why the user could not find the table. They
    /// fold with the hub's one chevron now.
    ///
    /// The send-scouts CTA is deliberately NOT gated: it is a priced, one-window
    /// offer, and an offer that disappears because a *presentation* preference is
    /// collapsed is the shape of every "the button was not there" report.
    var insightsExpanded: Bool = true

    /// The hub's scroll-away header, rendered as this list's first section.
    let header: () -> Header

    @Environment(\.modelContext) private var modelContext
    @State private var sortColumn: CombineColumn = .rank
    @State private var sortAscending: Bool = true
    /// Which block of columns sits after the identity block — the same control
    /// the Big Board wears, over the same five blocks, so a user who learned it
    /// on the board does not lose it one tab to the right.
    ///
    /// It opens on `.physical` because that is what a combine table IS: the
    /// drills are this screen's home block, where the board's is the overview.
    /// Local `@State` rather than a hub binding on purpose — the hub owns the
    /// position filter because a filter that evaporates on a tab switch was a
    /// bug, but a column block is a reading of THIS table.
    @State private var viewMode: ProspectAttributeTab = .physical
    @State private var mediaPopoverProspectID: UUID?
    @State private var dnpPopoverProspectID: UUID?
    @State private var teamPlayers: [Player] = []
    @ObservedObject private var userGradeStore = UserProspectGradeStore.shared
    @State private var isLoading: Bool = true
    @State private var cachedSortedProspects: [CollegeProspect] = []

    /// Population-based percentile lookup tables.
    /// Key: position, Value: sorted list of drill values for percentile rank lookup.
    @State private var percentilePools: PercentilePools = PercentilePools()

    // MARK: - Filtered & Sorted Data

    private var combineInvitees: [CollegeProspect] {
        // Prefer prospects with actual combine measurements so results stay
        // visible after the Combine phase ends (e.g. during Free Agency).
        // Fall back to the invite flag for the pre-results window.
        let withResults = prospects.filter { $0.fortyTime != nil }
        if !withResults.isEmpty {
            // The combine has run. An invitee who did not work out has NO
            // measurements at all (`ScoutingEngine.applyCombineDNP`), so
            // filtering on `fortyTime` alone would delete exactly the prospects
            // the DNP mechanic exists to surface — a first-round talent with an
            // empty card is a scouting decision, not a missing row. Specialists
            // stay out: they never had drills, and a K with six dashes reads as
            // a bug rather than as "kickers do not run the cone".
            let dnps = prospects.filter {
                $0.combineInvite && $0.fortyTime == nil
                    && $0.position != .K && $0.position != .P
            }
            return withResults + dnps
        }
        let invited = prospects.filter { $0.combineInvite }
        if !invited.isEmpty {
            return invited
        }
        // Last-resort fallback: if the game has advanced past the Combine
        // phase but neither combineInvite nor fortyTime data persisted on
        // the draft class (data desync), surface scouted prospects so the
        // tab is at least readable and not a confusing empty state.
        if isPastCombinePhase {
            return prospects.filter { $0.scoutedOverall != nil }
        }
        return []
    }

    /// True when at least one prospect has persisted combine measurements.
    /// Used to keep results visible regardless of the current season phase.
    private var hasResults: Bool {
        prospects.contains { $0.fortyTime != nil }
    }

    /// Whether the league has published an invite list at all.
    ///
    /// #128, case D. `combineInvite` is written by exactly one thing —
    /// `ScoutingEngine.generateCombineResults`, inside `runLeagueCombine` — and
    /// `WeekAdvancer` only runs that inside its `combineResultPhases` window
    /// (combine / free agency / pro days / draft). So in `.reviewRoster` NOBODY
    /// carries an invite: the list does not exist yet, and no amount of scouting
    /// makes one appear. That is not a data desync, and the header must not
    /// report it as "0 of 0 prospects invited" over a class the user has spent
    /// the autumn on — a count of zero out of zero reads as a broken screen.
    private var hasInvitations: Bool {
        prospects.contains { $0.combineInvite }
    }

    /// True when the season has advanced past the Combine phase. Used to
    /// gate the scouted-only fallback so we don't surface a misleading
    /// table during the pre-Combine window.
    private var isPastCombinePhase: Bool {
        switch career.currentPhase {
        case .freeAgency, .proDays, .draft, .otas, .trainingCamp,
             .preseason, .rosterCuts, .regularSeason, .tradeDeadline,
             .playoffs, .proBowl, .superBowl:
            return true
        default:
            return false
        }
    }

    private var filteredProspects: [CollegeProspect] {
        let base = combineInvitees
        if positionFilter == .all { return base }
        return base.filter { positionFilter.matches($0.position) }
    }

    private var sortedProspects: [CollegeProspect] {
        let sorted = filteredProspects.sorted { a, b in
            switch sortColumn {
            case .rank:
                return compare(a.draftProjection ?? 999, b.draftProjection ?? 999)
            case .name:
                return compare(a.lastName, b.lastName)
            case .position:
                return compare(a.position.rawValue, b.position.rawValue)
            case .college:
                return compare(a.college, b.college)
            case .grade:
                // Sort ascending by letter rank (A+ best → F worst). Outer
                // `sortAscending ? sorted : sorted.reversed()` flips direction.
                // Ungraded prospects are pinned to the bottom afterwards.
                let aRank = LetterGrade(rawValue: a.scoutGrade ?? "")?.rank ?? Int.max
                let bRank = LetterGrade(rawValue: b.scoutGrade ?? "")?.rank ?? Int.max
                if aRank == bRank { return compare(a.lastName, b.lastName) }
                return aRank < bRank
            case .production:
                let aTier = a.collegeProductionTier.sortRank
                let bTier = b.collegeProductionTier.sortRank
                if aTier == bTier { return compare(a.lastName, b.lastName) }
                return aTier < bTier
            case .projection:
                return compare(a.draftProjection ?? 999, b.draftProjection ?? 999)
            case .fortyYard:
                return compareOptional(a.fortyTime, b.fortyTime, lowerIsBetter: true)
            case .bench:
                return compareOptional(a.benchPress.map { Double($0) }, b.benchPress.map { Double($0) }, lowerIsBetter: false)
            case .vertical:
                return compareOptional(a.verticalJump, b.verticalJump, lowerIsBetter: false)
            case .broadJump:
                return compareOptional(a.broadJump.map { Double($0) }, b.broadJump.map { Double($0) }, lowerIsBetter: false)
            case .threeCone:
                return compareOptional(a.coneDrill, b.coneDrill, lowerIsBetter: true)
            case .shuttle:
                return compareOptional(a.shuttleTime, b.shuttleTime, lowerIsBetter: true)
            case .positionDrill:
                let aRank = LetterGrade(rawValue: a.positionDrillGrade ?? "F")?.rank ?? 0
                let bRank = LetterGrade(rawValue: b.positionDrillGrade ?? "F")?.rank ?? 0
                return aRank > bRank
            }
        }
        let directional = sortAscending ? sorted : sorted.reversed()
        // For grade column, pin ungraded prospects to the bottom regardless of direction.
        if sortColumn == .grade {
            let graded = directional.filter { $0.scoutGrade != nil }
            let ungraded = directional.filter { $0.scoutGrade == nil }
            return graded + ungraded
        }
        return directional
    }

    // MARK: - Team Needs

    private var teamNeeds: Set<Position> {
        Set(DraftEngine.topTeamNeeds(roster: teamPlayers, limit: 5))
    }

    // MARK: - Combine Risers & Fallers

    private var combineRisers: [CollegeProspect] {
        combineInvitees
            .filter { CombineMovers.improvement(for: $0) > 0 }
            .sorted { CombineMovers.improvement(for: $0) > CombineMovers.improvement(for: $1) }
            .prefix(5).map { $0 }
    }

    private var combineFallers: [CollegeProspect] {
        combineInvitees
            .filter { CombineMovers.improvement(for: $0) < 0 }
            .sorted { CombineMovers.improvement(for: $0) < CombineMovers.improvement(for: $1) }
            .prefix(5).map { $0 }
    }

    private func refreshCachedData() {
        cachedSortedProspects = sortedProspects
    }

    private func rebuildPercentilePools() {
        percentilePools = PercentilePools(prospects: combineInvitees)
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
                    Text("Loading Combine Results...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else {
            List {
                // The hub header, as this list's FIRST SECTION — one scroll
                // owner, one gesture (plan §5.4).
                Section {
                    header()
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                if insightsExpanded || onSendScouts != nil {
                    Section {
                        headerBar
                    }
                    .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 10, trailing: 8))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                if combineInvitees.isEmpty {
                    Section {
                        emptyState
                            .frame(minHeight: 240)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    if insightsExpanded, !combineRisers.isEmpty || !combineFallers.isEmpty {
                        Section {
                            risersAndFallersSection
                        }
                        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 10, trailing: 8))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }

                    Section {
                        ForEach(Array(cachedSortedProspects.enumerated()), id: \.element.id) { index, prospect in
                            NavigationLink(destination: ProspectDetailView(career: career, prospect: prospect)) {
                                combineRow(index: index + 1, prospect: prospect)
                            }
                            .listRowInsets(EdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8))
                            .listRowBackground(
                                index % 2 == 0
                                    ? Color.backgroundPrimary
                                    : Color.backgroundSecondary.opacity(0.5)
                            )
                            .accessibilityElement(children: .combine)
                            .accessibilityHint("Tap to view prospect details")
                            .contextMenu {
                                ProspectGradeContextMenu(
                                    prospect: prospect,
                                    onChange: { try? modelContext.save() }
                                )
                            }
                        }
                    } header: {
                        // `.plain` pins section headers, so the column labels
                        // stay over their columns while the table scrolls —
                        // which the old nested-scroll layout never managed. The
                        // mode chips ride along in the same pinned block, which
                        // is where the Big Board keeps them: a control that
                        // scrolls away on a 300-row table is a control the user
                        // has to hunt for.
                        VStack(spacing: 0) {
                            ProspectListControls(
                                positionFilter: $positionFilter,
                                mode: $viewMode,
                                modes: ProspectAttributeTab.allCases,
                                // The hub already draws one chip bar above this
                                // whole tab. Two identical rows stacked would be
                                // a worse bug than the missing control was.
                                showsPositionChips: false,
                                // This strip sits inside a pinned section header
                                // drawn on secondary — the primary default drew
                                // a two-tone seam straight across it (#116).
                                background: Color.backgroundSecondary
                            )

                            Divider().overlay(Color.surfaceBorder)

                            columnHeaders
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                        }
                        .background(Color.backgroundSecondary)
                        // Zeroed so the 8 pt above is the ONLY horizontal inset
                        // on the header, which is exactly the rows' own
                        // `listRowInsets`. A section header otherwise carries the
                        // platform's default margin and the whole label strip
                        // sits a few points off its own columns — invisible while
                        // every column was fixed-width, and a permanent drift now
                        // that the block is anchored to the trailing edge.
                        .listRowInsets(EdgeInsets())
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            } // end else (not loading)
        }
        .task {
            loadTeamPlayers()
            rebuildPercentilePools()
            refreshCachedData()
            isLoading = false
        }
        .onChange(of: positionFilter) { _, _ in refreshCachedData() }
        .onChange(of: sortColumn) { _, _ in refreshCachedData() }
        .onChange(of: sortAscending) { _, _ in refreshCachedData() }
        .onChange(of: viewMode) { _, newMode in
            // Only the Physical block's headers are sort buttons. Leaving a
            // drill sort live under another mode keeps the table ordered by a
            // column that is no longer on screen, with no arrow and no way to
            // clear it — reset to rank instead of sorting by a ghost.
            let drillColumns: Set<CombineColumn> = [
                .fortyYard, .bench, .vertical, .broadJump, .threeCone, .shuttle, .positionDrill
            ]
            if newMode != .physical && drillColumns.contains(sortColumn) {
                sortColumn = .rank
                sortAscending = true
            }
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        VStack(spacing: 12) {
            // #130: the hub's Insights header already prints COMBINE in 14 pt
            // black directly above this, with the fidelity word and the mover
            // counts in its teaser. The full block is the expanded read.
            if insightsExpanded {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("NFL COMBINE RESULTS")
                            .font(.title3.weight(.heavy))
                            .foregroundStyle(Color.textPrimary)

                        Text(inviteeCountText)
                            .font(.caption)
                            .foregroundStyle(combineInvitees.isEmpty ? Color.textTertiaryReadable : Color.accentGold)
                    }

                    Spacer()

                    fidelityChip
                }
            }

            if let onSendScouts {
                sendScoutsCTA(action: onSendScouts)
            }
            // Position filtering moved to the hub's shared chip bar so one tap
            // filters the board, the prospect list and this table together.
        }
    }

    /// The count under the title.
    ///
    /// #128 case D. This used to be an unconditional "\(filtered) of \(invited)
    /// prospects invited", which prints **"0 of 0 prospects invited"** for the
    /// entire pre-combine window — the autumn and the whole of Review Roster —
    /// because no prospect carries `combineInvite` until the league holds the
    /// event (see ``hasInvitations``). A zero-of-zero over a class the user has
    /// scouted 83 % of reads as a screen that has lost its data. It has not; the
    /// list simply does not exist yet, and the honest line says so.
    private var inviteeCountText: String {
        guard !combineInvitees.isEmpty else {
            return "Invitations go out when the combine window opens"
        }
        return "\(filteredProspects.count) of \(combineInvitees.count) prospects invited"
    }

    /// One line telling the user which of the two combine reads he is looking
    /// at, because "~4.5" and "4.53" in the same column would otherwise read as
    /// a formatting bug rather than as a decision he made.
    private var fidelityChip: some View {
        HStack(spacing: 6) {
            Image(systemName: scoutsAttended ? "binoculars.fill" : "tv")
                .font(.caption2)
            Text(scoutsAttended ? "Your scouts on site" : "Broadcast numbers")
                .font(.caption2.weight(.bold))
        }
        .foregroundStyle(scoutsAttended ? Color.success : Color.textTertiary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule().fill((scoutsAttended ? Color.success : Color.textTertiary).opacity(0.12))
        )
        .overlay(
            Capsule().strokeBorder(
                (scoutsAttended ? Color.success : Color.textTertiary).opacity(0.35),
                lineWidth: 1
            )
        )
        .accessibilityLabel(
            scoutsAttended
                ? "Your scouts attended the combine. Full measurements shown."
                : "Televised combine numbers only. Values are approximate."
        )
    }

    private func sendScoutsCTA(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "binoculars.fill")
                    .font(.title3)
                    .foregroundStyle(canAffordTrip ? Color.backgroundPrimary : Color.textTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Send Scouts to the Combine")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(canAffordTrip ? Color.backgroundPrimary : Color.textSecondary)
                    Text(canAffordTrip
                         ? "Exact times and drill grades, plus fresh reports on your board \u{2014} $\(tripCost)K from the scouting budget"
                         : "Not enough scouting budget ($\(tripCost)K needed) \u{2014} reallocate in Owner Relations")
                        .font(.caption)
                        .foregroundStyle(canAffordTrip
                                         ? Color.backgroundPrimary.opacity(0.85)
                                         : Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if canAffordTrip {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.backgroundPrimary)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(canAffordTrip ? Color.accentGold : Color.backgroundTertiary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(canAffordTrip ? Color.clear : Color.surfaceBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!canAffordTrip)
    }

    // MARK: - Risers & Fallers

    private var risersAndFallersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !combineRisers.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundStyle(Color.success)
                            .font(.caption)
                        Text("COMBINE RISERS")
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(Color.success)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(combineRisers) { prospect in
                                riserFallerCard(prospect: prospect, isRiser: true)
                            }
                        }
                    }
                }
            }

            if !combineFallers.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(Color.danger)
                            .font(.caption)
                        Text("COMBINE FALLERS")
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(Color.danger)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(combineFallers) { prospect in
                                riserFallerCard(prospect: prospect, isRiser: false)
                            }
                        }
                    }
                }
            }
        }
    }

    private func riserFallerCard(prospect: CollegeProspect, isRiser: Bool) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(prospect.fullName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)

                Text(prospect.position.rawValue)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.textSecondary)
            }

            VStack(spacing: 1) {
                // New (current) grade on top — prominent
                Text(prospect.scoutGrade ?? "--")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isRiser ? Color.success : Color.danger)
                Image(systemName: isRiser ? "arrow.up" : "arrow.down")
                    .font(.system(size: DSType.Size.micro, weight: .bold))
                    .foregroundStyle(isRiser ? Color.success : Color.danger)
                // Old (pre-combine) grade below — dimmed
                Text(prospect.preCombineGrade ?? "--")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isRiser ? Color.success.opacity(0.3) : Color.danger.opacity(0.3), lineWidth: 1)
                )
        )
    }

    // MARK: - Column Headers

    private var columnHeaders: some View {
        HStack(spacing: 0) {
            // Star column (no sort)
            Text("")
                .frame(width: CombineW.mark)

            sortableHeader("Rank", column: .rank, width: CombineW.rank)
            // The one elastic header. It carries the same floor as the row's
            // name cell and is followed by the same `Spacer`, so the fixed block
            // below lands on the same pixels in the header and in every row.
            sortableHeader("Name", column: .name, minWidth: CombineW.nameMin, alignment: .leading)

            Spacer(minLength: CombineW.gap)

            sortableHeader("Pos", column: .position, width: CombineW.pos)
            sortableHeader("GRD", column: .grade, width: CombineW.grade)
            sortableHeader("PROD", column: .production, width: CombineW.prod)
            sortableHeader("Proj", column: .projection, width: CombineW.proj)
            sortableHeader("College", column: .college, width: CombineW.college, alignment: .leading)

            switch viewMode {
            case .physical: physicalHeaders
            case .overview: overviewHeaders
            case .workup:   workupHeaders
            case .mental:   mentalHeaders
            case .position: positionHeaders
            }

            Spacer().frame(width: CombineW.chevron)
        }
    }

    // MARK: - Mode column headers

    /// The drills. This block is why the screen exists, so it is the one the
    /// table opens on — and it keeps the sortable headers it always had.
    private var physicalHeaders: some View {
        Group {
            sortableHeader("40yd", column: .fortyYard, width: CombineW.forty)
            sortableHeader("Bench", column: .bench, width: CombineW.bench)
            sortableHeader("Vert", column: .vertical, width: CombineW.vertical)
            sortableHeader("Broad", column: .broadJump, width: CombineW.broad)
            sortableHeader("3-Cone", column: .threeCone, width: CombineW.cone)
            sortableHeader("Shuttle", column: .shuttle, width: CombineW.shuttle)
            sortableHeader("Pos Drill", column: .positionDrill, width: CombineW.drill)
        }
    }

    private var overviewHeaders: some View {
        Group {
            staticHeader("AGE", width: CombineW.age)
            staticHeader("HT", width: CombineW.height)
            staticHeader("WT", width: CombineW.weight)
            staticHeader("RISK", width: CombineW.risk)
        }
    }

    /// What the building has DONE on him, in the same five slots the board's
    /// work-up block uses — with the interview in the last one, because the
    /// combine week is when that slot is spent.
    private var workupHeaders: some View {
        Group {
            staticHeader("RPT", width: CombineW.reports)
            staticHeader("PDAY", width: CombineW.tick)
            staticHeader("VISIT", width: CombineW.tick)
            staticHeader("WORK", width: CombineW.tick)
            staticHeader("MEET", width: CombineW.meet)
        }
    }

    private var mentalHeaders: some View {
        Group {
            staticHeader("TAPE", width: CombineW.tape)
            staticHeader("MEET", width: CombineW.meet)
            // ONE span over the eight bands, the way `positionHeaders` spans the
            // skill block. `ProspectGradeBandCell` already prints its own key
            // under the grade, so a per-column header printed AWR/DEC/WRK/… a
            // second time — two labels deep in a 26 pt column, both squeezed by
            // `minimumScaleFactor`, saying the same word twice (#116).
            staticHeader("MENTAL BANDS", width: CombineW.band * CGFloat(ProspectFog.mentalKeys.count))
        }
    }

    private var positionHeaders: some View {
        Group {
            // The four skill keys differ per position (a QB row reads ARM/SAC/
            // MAC/DAC where a CB reads MCV/ZCV/PRS/BSK), so the cells carry
            // their own key labels and the header names the block once instead
            // of printing four dashes over it.
            staticHeader("POSITION SKILLS", width: CombineW.skill * 4)
            sortableHeader("Pos Drill", column: .positionDrill, width: CombineW.drill)
        }
    }

    private func sortableHeader(_ title: String, column: CombineColumn, width: CGFloat, alignment: Alignment = .center) -> some View {
        Button {
            toggleSort(column)
        } label: {
            sortLabel(title, column: column)
                .frame(width: width, alignment: alignment)
        }
        .buttonStyle(.plain)
    }

    /// The flexible variant: a floor rather than a width, for the name column.
    private func sortableHeader(_ title: String, column: CombineColumn, minWidth: CGFloat, alignment: Alignment = .center) -> some View {
        Button {
            toggleSort(column)
        } label: {
            sortLabel(title, column: column)
                .frame(minWidth: minWidth, alignment: alignment)
        }
        .buttonStyle(.plain)
    }

    private func toggleSort(_ column: CombineColumn) {
        if sortColumn == column {
            sortAscending.toggle()
        } else {
            sortColumn = column
            sortAscending = true
        }
    }

    private func sortLabel(_ title: String, column: CombineColumn) -> some View {
        HStack(spacing: 2) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(sortColumn == column ? Color.accentGold : Color.textSecondary)

            if sortColumn == column {
                Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                    .font(.system(size: DSType.Size.micro, weight: .bold))
                    .foregroundStyle(Color.accentGold)
            }
        }
    }

    /// A label over a block the table does not sort on. The drills are sortable
    /// because a stopwatch reading is a ranking; a grade band and a yes/no tick
    /// are not, and a header that looks tappable and does nothing is worse than
    /// a plain one.
    private func staticHeader(_ title: String, width: CGFloat) -> some View {
        Text(title)
            .font(.caption.weight(.bold))
            .foregroundStyle(Color.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: width, alignment: .center)
    }

    // MARK: - Row

    private func combineRow(index: Int, prospect: CollegeProspect) -> some View {
        // An empty cell means two different things now, and the table has to say
        // which: "-" for a drill nobody expected (a QB's bench) and "DNP" for one
        // he chose not to run. Computed once per row — `combineParticipation` is
        // pure, but it is also seven cells' worth of repeat work otherwise.
        let dash = ScoutingEngine.combineParticipation(for: prospect).isDNP ? "DNP" : "--"
        let benchDash = prospect.position == .QB ? "--" : dash
        // How precisely this club is entitled to read the card. Per-prospect,
        // not per-table: a man your scouts already worked out is in full focus
        // even in a year you skipped Indianapolis.
        let fidelity = ProspectFog.combineFidelity(for: prospect, scoutsAttended: scoutsAttended)
        let showsPercentile = ProspectFog.showsPercentile(fidelity)
        return HStack(spacing: 0) {
            // The ONE mark, same control as the board and the prospect list.
            ProspectMarkButton(
                prospect: prospect,
                onChange: { try? modelContext.save() }
            )
            .frame(width: CombineW.mark)

            // Rank
            Text("\(index)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.textSecondary)
                .frame(width: CombineW.rank)

            nameCell(for: prospect)

            // The elastic gap — see `CombineW`. It is what anchors everything
            // below to the trailing edge, in this row and in the pinned header.
            Spacer(minLength: CombineW.gap)

            // Position
            Text(prospect.position.rawValue)
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.textPrimary)
                .frame(width: CombineW.pos - 6, height: 22)
                .background(positionColor(for: prospect), in: RoundedRectangle(cornerRadius: 3))
                .frame(width: CombineW.pos)

            // GRD column - dual grade display with refinement trend arrow
            DualGradeDisplay(
                prospectID: prospect.id,
                scoutGradeText: gradeDisplayText(for: prospect),
                scoutGradeColor: gradeDisplayColor(for: prospect),
                trajectory: prospect.stockTrajectory
            )
            .frame(width: CombineW.grade)

            // PROD column — college production tier
            ProductionTierChip(tier: prospect.collegeProductionTier, width: CombineW.prod, fontSize: 10)

            // Proj column
            Text(projectionDisplayText(for: prospect))
                .font(.caption.weight(.medium).monospacedDigit())
                .foregroundStyle(Color.textSecondary)
                .frame(width: CombineW.proj)

            // College
            Text(prospect.college)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
                .frame(width: CombineW.college, alignment: .leading)

            switch viewMode {
            case .physical:
                physicalCells(prospect: prospect, fidelity: fidelity,
                              showsPercentile: showsPercentile, dash: dash, benchDash: benchDash)
            case .overview:
                overviewCells(prospect: prospect)
            case .workup:
                workupCells(prospect: prospect)
            case .mental:
                mentalCells(prospect: prospect)
            case .position:
                positionCells(prospect: prospect, fidelity: fidelity, dash: dash)
            }

            // Chevron for row navigation
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
                .frame(width: CombineW.chevron)
        }
    }

    // MARK: - Name cell

    /// The name, then everything the row has to SAY about him.
    ///
    /// The chips carry `layoutPriority(1)`, so when the cell is squeezed the
    /// name text is what gives — "Nehemi…" beside an intact PARTIAL badge,
    /// rather than a whole name beside half a badge. That inversion was the
    /// reported bug: the marker chips are the row's only unrepeatable
    /// information, and they were the first thing the old fixed 130 pt cell cut.
    private func nameCell(for prospect: CollegeProspect) -> some View {
        HStack(spacing: 4) {
            Text(prospect.fullName)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)

            nameChips(for: prospect)
                .layoutPriority(1)
        }
        .frame(minWidth: CombineW.nameMin, alignment: .leading)
    }

    private func nameChips(for prospect: CollegeProspect) -> some View {
        HStack(spacing: 4) {
            ProspectMarkChip(mark: prospect.userMark)

            UserGradeBadge(prospectID: prospect.id)

            if prospect.combineMediaMention != nil {
                Image(systemName: "megaphone.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(isNegativeMediaMention(prospect.combineMediaMention!) ? Color.danger : Color.accentGold)
                    .onTapGesture {
                        mediaPopoverProspectID = mediaPopoverProspectID == prospect.id ? nil : prospect.id
                    }
                    .popover(isPresented: Binding(
                        get: { mediaPopoverProspectID == prospect.id },
                        set: { if !$0 { mediaPopoverProspectID = nil } }
                    )) {
                        mediaBubble(prospect.combineMediaMention!)
                    }
                    .accessibilityLabel("Media mention")
                    .accessibilityHint("Tap to view media commentary")
                    .accessibilityAddTraits(.isButton)
            }

            if teamNeeds.contains(prospect.position) {
                Text("NEED")
                    .font(.system(size: DSType.Size.micro, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.danger))
                    .fixedSize()
            }

            // Why this man's card is empty. Tappable rather than always-on
            // text: the reason is a sentence, and the badge alone already
            // answers "is this a bug or a decision".
            if let badge = ScoutingEngine.combineParticipation(for: prospect).badge {
                Text(badge)
                    .font(.system(size: DSType.Size.micro, weight: .heavy))
                    .foregroundStyle(Color.backgroundPrimary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.warning))
                    .fixedSize()
                    .onTapGesture {
                        dnpPopoverProspectID = dnpPopoverProspectID == prospect.id ? nil : prospect.id
                    }
                    .popover(isPresented: Binding(
                        get: { dnpPopoverProspectID == prospect.id },
                        set: { if !$0 { dnpPopoverProspectID = nil } }
                    )) {
                        dnpBubble(for: prospect)
                    }
                    .accessibilityLabel("\(badge): did not complete the combine")
                    .accessibilityHint("Tap for the reason")
                    .accessibilityAddTraits(.isButton)
            }
        }
    }

    // MARK: - Mode cells

    private func physicalCells(
        prospect: CollegeProspect,
        fidelity: ProspectFog.MeasurableFidelity,
        showsPercentile: Bool,
        dash: String,
        benchDash: String
    ) -> some View {
        Group {
            drillCell(value: ProspectFog.fortyText(prospect.fortyTime, fidelity: fidelity),
                      tier: prospect.fortyTime.map { fortyTierForPosition($0, prospect.position) }, width: CombineW.forty,
                      percentile: showsPercentile ? prospect.fortyTime.map { drillPercentile($0, drill: .forty, prospect.position) } : nil,
                      emptyText: dash)

            drillCell(value: ProspectFog.benchText(prospect.benchPress, fidelity: fidelity),
                      tier: prospect.benchPress.map { benchTier($0) }, width: CombineW.bench,
                      percentile: showsPercentile ? prospect.benchPress.map { drillPercentile(Double($0), drill: .bench, prospect.position) } : nil,
                      emptyText: benchDash)

            drillCell(value: ProspectFog.verticalText(prospect.verticalJump, fidelity: fidelity),
                      tier: prospect.verticalJump.map { verticalTier($0) }, width: CombineW.vertical,
                      percentile: showsPercentile ? prospect.verticalJump.map { drillPercentile($0, drill: .vertical, prospect.position) } : nil,
                      emptyText: dash)

            drillCell(value: ProspectFog.broadJumpText(prospect.broadJump, fidelity: fidelity),
                      tier: prospect.broadJump.map { broadTier($0) }, width: CombineW.broad,
                      percentile: showsPercentile ? prospect.broadJump.map { drillPercentile(Double($0), drill: .broad, prospect.position) } : nil,
                      emptyText: dash)

            drillCell(value: ProspectFog.agilityText(prospect.coneDrill, fidelity: fidelity),
                      tier: prospect.coneDrill.map { coneTier($0) }, width: CombineW.cone,
                      percentile: showsPercentile ? prospect.coneDrill.map { drillPercentile($0, drill: .threeCone, prospect.position) } : nil,
                      emptyText: dash)

            drillCell(value: ProspectFog.agilityText(prospect.shuttleTime, fidelity: fidelity),
                      tier: prospect.shuttleTime.map { shuttleTier($0) }, width: CombineW.shuttle,
                      percentile: showsPercentile ? prospect.shuttleTime.map { drillPercentile($0, drill: .shuttle, prospect.position) } : nil,
                      emptyText: dash)

            positionDrillCell(prospect: prospect, fidelity: fidelity, dash: dash)
        }
    }

    /// Position drill grade — a judgement rather than a stopwatch reading, so
    /// the broadcast read gets the tier letter without the modifier.
    private func positionDrillCell(
        prospect: CollegeProspect,
        fidelity: ProspectFog.MeasurableFidelity,
        dash: String
    ) -> some View {
        let drillGrade = ProspectFog.drillGradeText(prospect.positionDrillGrade, fidelity: fidelity)
        return Text(drillGrade ?? dash)
            .font(.caption.weight(.bold))
            .foregroundStyle(drillGrade.map { PositionGradeCalculator.gradeColorForLetter($0) } ?? Color.textTertiary)
            .frame(width: CombineW.drill)
    }

    /// Who he is, in the measurements the week is actually for. NEED is not a
    /// column here because it is already a chip on his name, and RISK is,
    /// because a boom-or-bust label beside a 4.3 is the whole argument.
    private func overviewCells(prospect: CollegeProspect) -> some View {
        Group {
            Text("\(prospect.age)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Color.textSecondary)
                .frame(width: CombineW.age)

            Text(heightText(prospect.height))
                .font(.caption.monospacedDigit())
                .foregroundStyle(Color.textSecondary)
                .frame(width: CombineW.height)

            Text("\(prospect.weight)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Color.textSecondary)
                .frame(width: CombineW.weight)

            riskBadge(for: prospect)
                .frame(width: CombineW.risk)
        }
    }

    /// What the building has DONE on him. Every empty cell is a hole the user
    /// can still pay to close, which is why they are drawn dim rather than
    /// blank — and the last one is the interview, the slot this week is for.
    private func workupCells(prospect: CollegeProspect) -> some View {
        // The RPT cell is a CAP counter — n of three — so it counts the same
        // reports the cap and the price ladder do: the ones this regime bought.
        // Counting `scoutingReports.count` printed 1/3 on every man carrying the
        // inherited "Previous Staff" baseline, i.e. a third of his allowance
        // spent before the user had ordered anything, against a board row and a
        // film surface that both said 0/3 (#122).
        let reports = ScoutEvaluationBudget.chargeableReports(prospect)
        return Group {
            Text("\(reports)/\(ScoutEvaluationBudget.maxReportsPerProspect)")
                .font(.system(size: 10, weight: .bold).monospacedDigit())
                .foregroundStyle(reports == 0
                                 ? Color.textTertiary.opacity(0.5)
                                 : (reports >= 2 ? Color.success : Color.accentBlue))
                .frame(width: CombineW.reports)

            ProspectWorkTick(done: prospect.proDayCompleted, tint: .success)
                .frame(width: CombineW.tick)

            ProspectWorkTick(
                done: career.teamID.map { prospect.top30VisitedByTeams.contains($0) } ?? false,
                tint: .accentGold
            )
            .frame(width: CombineW.tick)

            ProspectWorkTick(done: ScoutingEngine.hasWorkedOutPrivately(prospect), tint: .accentBlue)
                .frame(width: CombineW.tick)

            // The interview, read from the list rather than from two taps deep.
            // A dash here is the prompt: open his card and spend a slot.
            ProspectMeetCell(prospect: prospect, width: CombineW.meet)
        }
    }

    private func mentalCells(prospect: CollegeProspect) -> some View {
        Group {
            ProspectTapeCell(prospect: prospect, width: CombineW.tape)
            ProspectMeetCell(prospect: prospect, width: CombineW.meet)
            ForEach(ProspectFog.mentalKeys, id: \.self) { key in
                ProspectGradeBandCell(grade: prospect.scoutedMentalGrades?[key], label: key)
                    .frame(width: CombineW.band)
            }
        }
    }

    private func positionCells(
        prospect: CollegeProspect,
        fidelity: ProspectFog.MeasurableFidelity,
        dash: String
    ) -> some View {
        // `ProspectFog.positionSkillKeys` is the canonical table, copied from the
        // writer (`ScoutingEngine.generatePositionSkillGrades`). The local list
        // this used to call had drifted — `SAc` / `DAc` for a quarterback, `TAK`
        // for a linebacker, where the engine writes `SAC` / `DAC` / `TKL` — so
        // those cells printed "?" for a fully scouted man no matter how much
        // work the user had bought.
        let keys = Array(ProspectFog.positionSkillKeys(for: prospect).prefix(4))
        return Group {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                ProspectGradeBandCell(grade: prospect.scoutedPositionGrades?[key], label: key)
                    .frame(width: CombineW.skill)
            }
            // Pad to four so a kicker's two columns still leave the drill grade
            // over its own header.
            if keys.count < 4 {
                ForEach(0..<(4 - keys.count), id: \.self) { _ in
                    Spacer().frame(width: CombineW.skill)
                }
            }
            positionDrillCell(prospect: prospect, fidelity: fidelity, dash: dash)
        }
    }

    private func heightText(_ inches: Int) -> String {
        "\(inches / 12)'\(inches % 12)\""
    }

    private func riskBadge(for prospect: CollegeProspect) -> some View {
        let risk = prospect.riskLevel
        let text: String
        let tint: Color
        switch risk {
        case .safePick:    text = "Safe";       tint = .success
        case .highCeiling: text = "Ceiling";    tint = .accentBlue
        case .boomOrBust:  text = "Boom/Bust";  tint = .danger
        case .unknown:     text = "--";         tint = .textTertiary
        }
        return Text(text)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(risk == .unknown ? tint : .white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, risk == .unknown ? 0 : 5)
            .padding(.vertical, risk == .unknown ? 0 : 2)
            .background(
                risk == .unknown
                    ? Color.clear
                    : tint.opacity(0.85),
                in: RoundedRectangle(cornerRadius: DSCornerRadius.tight)
            )
    }

    private func drillCell(
        value: String?, tier: DrillTier?, width: CGFloat,
        percentile: Int? = nil, emptyText: String = "--"
    ) -> some View {
        VStack(spacing: 1) {
            Text(value ?? emptyText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(tier?.color ?? Color.textTertiary)

            if let pct = percentile {
                let tier = tierLabel(for: pct)
                Text(tier.text)
                    .font(.system(size: DSType.Size.micro, weight: .semibold))
                    .foregroundStyle(tier.color)
            }
        }
        .frame(width: width)
    }

    /// Maps a 1-99 percentile to a human-friendly tier label and color.
    /// Tiers are language-friendly and immediately scannable on the combine
    /// results table compared to raw "Nth" rank text.
    private func tierLabel(for percentile: Int) -> (text: String, color: Color) {
        // Aligned with the unified 5-tier color scale (green = best, red = worst).
        switch percentile {
        case 90...:    return ("Top 10%", .eliteGreen)
        case 75..<90:  return ("Top 25%", .success)
        case 50..<75:  return ("Above Avg", .accentBlue)
        case 25..<50:  return ("Below Avg", .warning)
        default:       return ("Bottom 25%", .danger)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "figure.run")
                .font(.system(size: 52))
                .foregroundStyle(Color.textTertiary)

            Text(emptyStateTitle)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.textPrimary)

            Text(emptyStateMessage)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            if !hasInvitations, !hasResults, let onOpenClassDepth {
                Button(action: onOpenClassDepth) {
                    Label("Open Class Depth", systemImage: "chart.bar.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.backgroundPrimary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(Color.accentGold, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateTitle: String {
        if hasResults { return "No Combine Invitees" }
        // #128 case D: the pre-invite window is its own state and it is the
        // COMMON one — the whole autumn and the whole of Review Roster sit in
        // it. It used to print "Combine Not Simulated", which claims a step was
        // skipped when in fact the league has not got there yet.
        if !hasInvitations { return "Invitations Are Not Out Yet" }
        return "Combine Not Simulated"
    }

    private var emptyStateMessage: String {
        if hasResults {
            return "No prospects in this draft class were invited to the Combine."
        }
        if !hasInvitations {
            return "The league picks its ~330 invitees when the combine window opens \u{2014} nobody in this class carries an invite before then. Until it does, the Class Depth tab is the read on what the class actually is."
        }
        return "The invite list is out but the drills have not been run. The combine is held automatically when the Combine phase begins."
    }

    // MARK: - Media Mention Helpers

    private func isNegativeMediaMention(_ mention: String) -> Bool {
        let negativeKeywords = ["disappoint", "concern", "struggled", "slow", "poor", "weak", "dropped", "injury", "flag", "bust"]
        let lower = mention.lowercased()
        return negativeKeywords.contains { lower.contains($0) }
    }

    private func mediaBubble(_ mention: String) -> some View {
        // Stored as "[Stock Riser] He ran a 4.41" — the tag is the bubble's
        // header, not part of the quote.
        let split = ScoutingEngine.splitTaggedMention(mention)
        return VStack(alignment: .leading, spacing: 6) {
            Text(split.category.uppercased())
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(Color.textTertiary)

            Text("\"\(split.headline)\"")
                .font(.caption)
                .foregroundStyle(Color.textPrimary)
                .italic()
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: 260)
        .background(Color.backgroundSecondary)
        .presentationCompactAdaptation(.popover)
    }

    /// The sentence behind a DNP / Partial badge, plus the one line of advice the
    /// mechanic is actually for: the numbers are not gone, they are at the pro day.
    private func dnpBubble(for prospect: CollegeProspect) -> some View {
        let participation = ScoutingEngine.combineParticipation(for: prospect)
        return VStack(alignment: .leading, spacing: 6) {
            Text(participation.badge ?? "DNP")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(Color.warning)

            Text(participation.reason ?? "")
                .font(.caption)
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Send a scout to his pro day to get the missing numbers.")
                .font(.system(size: 10))
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: 260)
        .background(Color.backgroundSecondary)
        .presentationCompactAdaptation(.popover)
    }

    // MARK: - Grade Display

    /// The GRD cell's band — through `ProspectFog`, like the Big Board's OVR
    /// cell and the prospect card's header.
    ///
    /// It read `prospect.effectiveOverallGrade` straight, which is the RAW
    /// stored range: `ProspectFog.read` widens that by `DraftIntel.scoutConfidence`,
    /// so this table was printing "B+" for a man the board two tabs to the left
    /// showed as "B-/A-". One department, one certainty — a screen that looks
    /// surer than your scouts are is the same class of bug as one that shows
    /// numbers they never filed.
    private func scoutBand(for prospect: CollegeProspect) -> GradeRange? {
        let read = ProspectFog.read(prospect)
        return read.source == .scouts ? read.band : nil
    }

    private func gradeDisplayText(for prospect: CollegeProspect) -> String {
        scoutBand(for: prospect)?.displayText ?? "--"
    }

    private func gradeDisplayColor(for prospect: CollegeProspect) -> Color {
        guard let range = scoutBand(for: prospect) else { return Color.textTertiary }
        return PositionGradeCalculator.gradeColorForLetter(range.midGrade.rawValue)
    }

    private func projectionDisplayText(for prospect: CollegeProspect) -> String {
        guard let round = prospect.draftProjection else { return "--" }
        switch round {
        case 1: return "Rd 1"
        case 2: return "Rd 2"
        case 3: return "Rd 3"
        case 4: return "Rd 4"
        case 5: return "Rd 5"
        case 6: return "Rd 6"
        case 7: return "Rd 7"
        default: return "UDFA"
        }
    }

    // MARK: - Load Team Players

    private func loadTeamPlayers() {
        guard let teamID = career.teamID else { return }
        let descriptor = FetchDescriptor<Player>(predicate: #Predicate { $0.teamID == teamID })
        teamPlayers = (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Helpers

    private func positionColor(for prospect: CollegeProspect) -> Color {
        switch prospect.position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }

    // MARK: - Percentile Helper

    /// Population-based percentile within position group.
    /// `value` is the prospect's drill value, `drill` selects which sorted pool to use.
    /// Returns 1-99 where 99 = best in position, 50 = median, 1 = worst.
    /// Identical values produce identical percentiles (uses rank-based with tie handling).
    private func drillPercentile(_ value: Double, drill: DrillKind, _ position: Position) -> Int {
        return percentilePools.percentile(value: value, drill: drill, position: position)
    }

    // MARK: - Sorting Helpers

    private func compare<T: Comparable>(_ a: T, _ b: T) -> Bool { a < b }

    private func compareOptional(_ a: Double?, _ b: Double?, lowerIsBetter: Bool) -> Bool {
        guard let aVal = a else { return false }
        guard let bVal = b else { return true }
        return lowerIsBetter ? aVal < bVal : aVal > bVal
    }

    // MARK: - Drill Tier Thresholds

    private func fortyTier(_ time: Double) -> DrillTier {
        if time < 4.40 { return .elite }
        if time < 4.55 { return .good }
        if time < 4.70 { return .average }
        return .poor
    }

    /// Position-relative 40yd tier coloring. Uses the percentile pool for the
    /// player's position so an OL running 5.05 can be "elite" and a WR running
    /// 4.55 can be "average". Falls back to absolute tier if the pool is empty.
    private func fortyTierForPosition(_ time: Double, _ position: Position) -> DrillTier {
        let pct = percentilePools.percentile(value: time, drill: .forty, position: position)
        // Pools may not be built yet (during initial load) — guard with absolute tier.
        if percentilePools.isEmpty { return fortyTier(time) }
        if pct >= 75 { return .elite }
        if pct >= 50 { return .good }
        if pct >= 25 { return .average }
        return .poor
    }

    private func benchTier(_ reps: Int) -> DrillTier {
        if reps > 30 { return .elite }
        if reps > 22 { return .good }
        if reps > 15 { return .average }
        return .poor
    }

    private func verticalTier(_ inches: Double) -> DrillTier {
        if inches > 38 { return .elite }
        if inches > 34 { return .good }
        if inches > 30 { return .average }
        return .poor
    }

    private func broadTier(_ inches: Int) -> DrillTier {
        if inches > 126 { return .elite }
        if inches > 118 { return .good }
        if inches > 110 { return .average }
        return .poor
    }

    private func coneTier(_ time: Double) -> DrillTier {
        if time < 6.8 { return .elite }
        if time < 7.0 { return .good }
        if time < 7.3 { return .average }
        return .poor
    }

    private func shuttleTier(_ time: Double) -> DrillTier {
        if time < 4.1 { return .elite }
        if time < 4.3 { return .good }
        if time < 4.5 { return .average }
        return .poor
    }
}

// MARK: - Combine movers

/// Who Indianapolis moved, and by how much.
///
/// Lifted out of `CombineResultsView` (#130) because the hub's Insights teaser
/// has to say "5 risers · 2 fallers" while the rails themselves are folded away,
/// and two copies of a grade ladder is exactly how the same event ends up
/// reported two different ways on two rows of one screen.
enum CombineMovers {

    /// Steps up (positive) or down (negative) the letter ladder since the class
    /// opened. `0` when either read is missing — a man with no pre-combine grade
    /// has not moved, he has simply never been graded.
    ///
    /// The ladder itself is `ProspectRoundFormat.gradeRank`, which the Big Board
    /// already sorts and bands on. This screen used to carry a private,
    /// character-for-character identical copy of it.
    static func improvement(for prospect: CollegeProspect) -> Int {
        guard let pre = prospect.preCombineGrade,
              let post = prospect.scoutGrade else { return 0 }
        return ProspectRoundFormat.gradeRank(post) - ProspectRoundFormat.gradeRank(pre)
    }

    /// One pass, both counts — for the collapsed teaser.
    static func counts(in prospects: [CollegeProspect]) -> (risers: Int, fallers: Int) {
        var risers = 0
        var fallers = 0
        for prospect in prospects {
            let move = improvement(for: prospect)
            if move > 0 { risers += 1 } else if move < 0 { fallers += 1 }
        }
        return (risers, fallers)
    }
}

// MARK: - Supporting Types

private enum CombineColumn {
    case rank, name, position, college
    case grade, projection, production
    case fortyYard, bench, vertical, broadJump, threeCone, shuttle
    case positionDrill
}

private enum DrillTier {
    case elite, good, average, poor

    var color: Color {
        switch self {
        case .elite:   return .accentGold
        case .good:    return .success
        case .average: return .textPrimary
        case .poor:    return .warning
        }
    }
}

// MARK: - Population-Based Percentile Pools

/// Identifies a combine drill for percentile lookup.
enum DrillKind: Hashable {
    case forty, bench, vertical, broad, threeCone, shuttle

    /// True if a lower value is better (timed drills).
    var lowerIsBetter: Bool {
        switch self {
        case .forty, .threeCone, .shuttle: return true
        case .bench, .vertical, .broad:    return false
        }
    }
}

/// Percentile pools per (position, drill) computed from the combine invitee population.
/// Same value within the same pool always produces the same percentile.
/// Best in pool ~= 99th percentile, median ~= 50th, worst ~= 1st.
struct PercentilePools {
    /// Sorted (ascending) values per position+drill.
    private var pools: [PoolKey: [Double]]

    private struct PoolKey: Hashable {
        let position: Position
        let drill: DrillKind
    }

    var isEmpty: Bool { pools.isEmpty }

    init() {
        self.pools = [:]
    }

    init(prospects: [CollegeProspect]) {
        var collected: [PoolKey: [Double]] = [:]
        for prospect in prospects {
            let pos = prospect.position
            if let v = prospect.fortyTime {
                collected[PoolKey(position: pos, drill: .forty), default: []].append(v)
            }
            if let v = prospect.benchPress {
                collected[PoolKey(position: pos, drill: .bench), default: []].append(Double(v))
            }
            if let v = prospect.verticalJump {
                collected[PoolKey(position: pos, drill: .vertical), default: []].append(v)
            }
            if let v = prospect.broadJump {
                collected[PoolKey(position: pos, drill: .broad), default: []].append(Double(v))
            }
            if let v = prospect.coneDrill {
                collected[PoolKey(position: pos, drill: .threeCone), default: []].append(v)
            }
            if let v = prospect.shuttleTime {
                collected[PoolKey(position: pos, drill: .shuttle), default: []].append(v)
            }
        }
        // Sort each pool ascending for binary-search percentile.
        for key in collected.keys {
            collected[key]?.sort()
        }
        self.pools = collected
    }

    /// Population-based percentile for `value` within position+drill pool.
    /// Returns 1-99 with ties producing the same percentile.
    /// - Best value in pool ~= 99
    /// - Median ~= 50
    /// - Worst value ~= 1
    func percentile(value: Double, drill: DrillKind, position: Position) -> Int {
        let key = PoolKey(position: position, drill: drill)
        guard let pool = pools[key], !pool.isEmpty else { return 50 }
        let n = pool.count
        if n == 1 { return 99 }

        // Count strictly worse (so all ties get the same percentile).
        let countWorse: Int
        if drill.lowerIsBetter {
            // Worse = larger value
            countWorse = pool.filter { $0 > value }.count
        } else {
            countWorse = pool.filter { $0 < value }.count
        }

        // Map [0, n-1] → [1, 99]; best (countWorse == n-1) → 99, worst → 1.
        // Use rank-fraction so two prospects with the same value get the same percentile.
        let pct = Int(round(Double(countWorse) / Double(n - 1) * 98.0)) + 1
        return max(1, min(99, pct))
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        CombineResultsView(
            career: Career(playerName: "John Doe", role: .gm, capMode: .simple),
            prospects: [
                CollegeProspect(
                    firstName: "Caleb", lastName: "Williams",
                    college: "USC", position: .QB,
                    age: 21, height: 74, weight: 214,
                    truePositionAttributes: .quarterback(QBAttributes(
                        armStrength: 92, accuracyShort: 88, accuracyMid: 90,
                        accuracyDeep: 85, pocketPresence: 87, scrambling: 78
                    )),
                    truePersonality: PlayerPersonality(archetype: .fieryCompetitor, motivation: .winning),
                    fortyTime: 4.62, benchPress: 18, verticalJump: 33.5,
                    broadJump: 118, shuttleTime: 4.24, coneDrill: 6.87,
                    combineInvite: true,
                    draftProjection: 1
                ),
                CollegeProspect(
                    firstName: "Marvin", lastName: "Harrison Jr.",
                    college: "Ohio State", position: .WR,
                    age: 21, height: 75, weight: 209,
                    truePositionAttributes: .wideReceiver(WRAttributes(
                        routeRunning: 91, catching: 93, release: 90, spectacularCatch: 88
                    )),
                    truePersonality: PlayerPersonality(archetype: .quietProfessional, motivation: .winning),
                    fortyTime: 4.38, benchPress: 14, verticalJump: 39.0,
                    broadJump: 128, shuttleTime: 4.05, coneDrill: 6.72,
                    combineInvite: true,
                    draftProjection: 1
                ),
            ],
            positionFilter: .constant(.all),
            header: { EmptyView() }
        )
    }
}
