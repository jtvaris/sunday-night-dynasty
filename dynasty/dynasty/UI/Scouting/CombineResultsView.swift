import SwiftUI
import SwiftData

struct CombineResultsView: View {
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

    /// Shared with the Big Board and the Prospects list — the chips live in
    /// `ScoutingHubView` now, so a filter survives a tab switch.
    @Binding var positionFilter: ProspectPositionFilter

    @Environment(\.modelContext) private var modelContext
    @State private var sortColumn: CombineColumn = .rank
    @State private var sortAscending: Bool = true
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

    /// True when at least one prospect has been scouted but no combine
    /// measurements exist — used to drive a "needs simulation" empty state.
    private var hasScoutedOnly: Bool {
        !hasResults
            && !prospects.contains { $0.combineInvite }
            && prospects.contains { $0.scoutedOverall != nil }
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
            .filter { gradeImprovement(for: $0) > 0 }
            .sorted { gradeImprovement(for: $0) > gradeImprovement(for: $1) }
            .prefix(5).map { $0 }
    }

    private var combineFallers: [CollegeProspect] {
        combineInvitees
            .filter { gradeImprovement(for: $0) < 0 }
            .sorted { gradeImprovement(for: $0) < gradeImprovement(for: $1) }
            .prefix(5).map { $0 }
    }

    private func gradeImprovement(for prospect: CollegeProspect) -> Int {
        guard let pre = prospect.preCombineGrade,
              let post = prospect.scoutGrade else { return 0 }
        return gradeRank(post) - gradeRank(pre)
    }

    private func gradeRank(_ grade: String) -> Int {
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
            VStack(spacing: 0) {
                headerBar
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                Divider()
                    .overlay(Color.surfaceBorder)

                if combineInvitees.isEmpty {
                    emptyState
                } else {
                    // Risers & Fallers section
                    if !combineRisers.isEmpty || !combineFallers.isEmpty {
                        risersAndFallersSection
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)

                        Divider().overlay(Color.surfaceBorder)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        VStack(spacing: 0) {
                            columnHeaders
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Color.backgroundSecondary)

                            Divider().overlay(Color.surfaceBorder)

                            ScrollView(.vertical, showsIndicators: true) {
                                LazyVStack(spacing: 0) {
                                    ForEach(Array(cachedSortedProspects.enumerated()), id: \.element.id) { index, prospect in
                                        NavigationLink(destination: ProspectDetailView(career: career, prospect: prospect)) {
                                            combineRow(index: index + 1, prospect: prospect)
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 8)
                                                .background(index % 2 == 0 ? Color.backgroundPrimary : Color.backgroundSecondary.opacity(0.5))
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityElement(children: .combine)
                                        .accessibilityHint("Tap to view prospect details")
                                        .contextMenu {
                                            ProspectGradeContextMenu(prospectID: prospect.id)
                                        }

                                        Divider().overlay(Color.surfaceBorder.opacity(0.5))
                                    }
                                }
                            }
                        }
                    }
                }
            }
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
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("NFL COMBINE RESULTS")
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(Color.textPrimary)

                    Text("\(filteredProspects.count) of \(combineInvitees.count) prospects invited")
                        .font(.caption)
                        .foregroundStyle(Color.accentGold)
                }

                Spacer()

                fidelityChip
            }

            if let onSendScouts {
                sendScoutsCTA(action: onSendScouts)
            }
            // Position filtering moved to the hub's shared chip bar so one tap
            // filters the board, the prospect list and this table together.
        }
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
                    .font(.system(size: 8, weight: .bold))
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
                .frame(width: 30)

            sortableHeader("Rank", column: .rank, width: 42)
            sortableHeader("Name", column: .name, width: 140, alignment: .leading)
            sortableHeader("Pos", column: .position, width: 44)
            sortableHeader("GRD", column: .grade, width: 54)
            sortableHeader("PROD", column: .production, width: 52)
            sortableHeader("Proj", column: .projection, width: 44)
            sortableHeader("College", column: .college, width: 110, alignment: .leading)
            sortableHeader("40yd", column: .fortyYard, width: 60)
            sortableHeader("Bench", column: .bench, width: 60)
            sortableHeader("Vert", column: .vertical, width: 60)
            sortableHeader("Broad", column: .broadJump, width: 60)
            sortableHeader("3-Cone", column: .threeCone, width: 66)
            sortableHeader("Shuttle", column: .shuttle, width: 66)
            sortableHeader("Pos Drill", column: .positionDrill, width: 66)
        }
    }

    private func sortableHeader(_ title: String, column: CombineColumn, width: CGFloat, alignment: Alignment = .center) -> some View {
        Button {
            if sortColumn == column {
                sortAscending.toggle()
            } else {
                sortColumn = column
                sortAscending = true
            }
        } label: {
            HStack(spacing: 2) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(sortColumn == column ? Color.accentGold : Color.textSecondary)

                if sortColumn == column {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.accentGold)
                }
            }
            .frame(width: width, alignment: alignment)
        }
        .buttonStyle(.plain)
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
            // Star toggle using UserProspectGradeStore
            ProspectStarButton(prospectID: prospect.id)
                .frame(width: 44)

            // Rank
            Text("\(index)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.textSecondary)
                .frame(width: 42)

            // Name + media mention + NEED badge
            HStack(spacing: 4) {
                Text(prospect.fullName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)

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
                        .font(.system(size: 7, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.danger))
                }

                // Why this man's card is empty. Tappable rather than always-on
                // text: the reason is a sentence, the column is 140 pt wide, and
                // the badge alone already answers "is this a bug or a decision".
                if let badge = ScoutingEngine.combineParticipation(for: prospect).badge {
                    Text(badge)
                        .font(.system(size: 7, weight: .heavy))
                        .foregroundStyle(Color.backgroundPrimary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.warning))
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
            .frame(width: 140, alignment: .leading)

            // Position
            Text(prospect.position.rawValue)
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 34, height: 22)
                .background(positionColor(for: prospect), in: RoundedRectangle(cornerRadius: 3))
                .frame(width: 44)

            // GRD column - dual grade display with refinement trend arrow
            DualGradeDisplay(
                prospectID: prospect.id,
                scoutGradeText: gradeDisplayText(for: prospect),
                scoutGradeColor: gradeDisplayColor(for: prospect),
                trajectory: prospect.stockTrajectory
            )
            .frame(width: 64)

            // PROD column — college production tier
            ProductionTierChip(tier: prospect.collegeProductionTier, width: 52, fontSize: 10)

            // Proj column
            Text(projectionDisplayText(for: prospect))
                .font(.caption.weight(.medium).monospacedDigit())
                .foregroundStyle(Color.textSecondary)
                .frame(width: 44)

            // College
            Text(prospect.college)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
                .frame(width: 110, alignment: .leading)

            drillCell(value: ProspectFog.fortyText(prospect.fortyTime, fidelity: fidelity),
                      tier: prospect.fortyTime.map { fortyTierForPosition($0, prospect.position) }, width: 60,
                      percentile: showsPercentile ? prospect.fortyTime.map { drillPercentile($0, drill: .forty, prospect.position) } : nil,
                      emptyText: dash)

            drillCell(value: ProspectFog.benchText(prospect.benchPress, fidelity: fidelity),
                      tier: prospect.benchPress.map { benchTier($0) }, width: 60,
                      percentile: showsPercentile ? prospect.benchPress.map { drillPercentile(Double($0), drill: .bench, prospect.position) } : nil,
                      emptyText: benchDash)

            drillCell(value: ProspectFog.verticalText(prospect.verticalJump, fidelity: fidelity),
                      tier: prospect.verticalJump.map { verticalTier($0) }, width: 60,
                      percentile: showsPercentile ? prospect.verticalJump.map { drillPercentile($0, drill: .vertical, prospect.position) } : nil,
                      emptyText: dash)

            drillCell(value: ProspectFog.broadJumpText(prospect.broadJump, fidelity: fidelity),
                      tier: prospect.broadJump.map { broadTier($0) }, width: 60,
                      percentile: showsPercentile ? prospect.broadJump.map { drillPercentile(Double($0), drill: .broad, prospect.position) } : nil,
                      emptyText: dash)

            drillCell(value: ProspectFog.agilityText(prospect.coneDrill, fidelity: fidelity),
                      tier: prospect.coneDrill.map { coneTier($0) }, width: 66,
                      percentile: showsPercentile ? prospect.coneDrill.map { drillPercentile($0, drill: .threeCone, prospect.position) } : nil,
                      emptyText: dash)

            drillCell(value: ProspectFog.agilityText(prospect.shuttleTime, fidelity: fidelity),
                      tier: prospect.shuttleTime.map { shuttleTier($0) }, width: 66,
                      percentile: showsPercentile ? prospect.shuttleTime.map { drillPercentile($0, drill: .shuttle, prospect.position) } : nil,
                      emptyText: dash)

            // Position drill grade — a judgement rather than a stopwatch reading,
            // so the broadcast read gets the tier letter without the modifier.
            let drillGrade = ProspectFog.drillGradeText(prospect.positionDrillGrade, fidelity: fidelity)
            Text(drillGrade ?? dash)
                .font(.caption.weight(.bold))
                .foregroundStyle(drillGrade.map { PositionGradeCalculator.gradeColorForLetter($0) } ?? Color.textTertiary)
                .frame(width: 66)

            // Chevron for row navigation
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
                .frame(width: 20)
        }
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
                    .font(.system(size: 8, weight: .semibold))
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateTitle: String {
        if hasResults { return "No Combine Invitees" }
        if hasScoutedOnly { return "Combine Not Simulated" }
        return "No Combine Results Yet"
    }

    private var emptyStateMessage: String {
        if hasResults {
            return "No prospects in this draft class were invited to the Combine."
        }
        if hasScoutedOnly {
            return "The combine has not been held for this draft class yet. It runs automatically when the Combine phase begins."
        }
        return "The combine runs when the Combine phase begins \u{2014} results stay here through the draft."
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

    private func gradeDisplayText(for prospect: CollegeProspect) -> String {
        // Single source of truth — same as Big Board, prospect detail, and any
        // other list. `effectiveOverallGrade` covers all fallbacks.
        prospect.effectiveOverallGrade?.displayText ?? "--"
    }

    private func gradeDisplayColor(for prospect: CollegeProspect) -> Color {
        guard let range = prospect.effectiveOverallGrade else { return Color.textTertiary }
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

    // MARK: - Watchlist Toggle

    private func toggleWatchlist(_ prospect: CollegeProspect) {
        if prospect.prospectFlag == .none {
            prospect.prospectFlag = .mustHave
        } else {
            prospect.prospectFlag = .none
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
            positionFilter: .constant(.all)
        )
    }
}
