import SwiftUI
import SwiftData

struct CombineResultsView: View {
    let career: Career
    let prospects: [CollegeProspect]

    @Environment(\.modelContext) private var modelContext
    @State private var positionFilter: ProspectPositionFilter = .all
    @State private var sortColumn: CombineColumn = .rank
    @State private var sortAscending: Bool = true
    @State private var mediaPopoverProspectID: UUID?
    @State private var teamPlayers: [Player] = []
    @ObservedObject private var userGradeStore = UserProspectGradeStore.shared
    @State private var isLoading: Bool = true
    @State private var cachedSortedProspects: [CollegeProspect] = []

    /// Population-based percentile lookup tables.
    /// Key: position, Value: sorted list of drill values for percentile rank lookup.
    @State private var percentilePools: PercentilePools = PercentilePools()

    // MARK: - Filtered & Sorted Data

    private var combineInvitees: [CollegeProspect] {
        prospects.filter { $0.combineInvite }
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
                return compare(gradeDisplayText(for: b), gradeDisplayText(for: a))
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
        return sortAscending ? sorted : sorted.reversed()
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
            }

            Picker("Position", selection: $positionFilter) {
                ForEach(ProspectPositionFilter.allCases) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .pickerStyle(.segmented)
        }
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
        HStack(spacing: 0) {
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
            }
            .frame(width: 140, alignment: .leading)

            // Position
            Text(prospect.position.rawValue)
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 34, height: 22)
                .background(positionColor(for: prospect), in: RoundedRectangle(cornerRadius: 3))
                .frame(width: 44)

            // GRD column - dual grade display
            DualGradeDisplay(
                prospectID: prospect.id,
                scoutGradeText: gradeDisplayText(for: prospect),
                scoutGradeColor: gradeDisplayColor(for: prospect)
            )
            .frame(width: 54)

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

            drillCell(value: prospect.fortyTime.map { String(format: "%.2f", $0) },
                      tier: prospect.fortyTime.map { fortyTierForPosition($0, prospect.position) }, width: 60,
                      percentile: prospect.fortyTime.map { drillPercentile($0, drill: .forty, prospect.position) })

            drillCell(value: prospect.benchPress.map { "\($0)" },
                      tier: prospect.benchPress.map { benchTier($0) }, width: 60,
                      percentile: prospect.benchPress.map { drillPercentile(Double($0), drill: .bench, prospect.position) })

            drillCell(value: prospect.verticalJump.map { String(format: "%.1f\"", $0) },
                      tier: prospect.verticalJump.map { verticalTier($0) }, width: 60,
                      percentile: prospect.verticalJump.map { drillPercentile($0, drill: .vertical, prospect.position) })

            drillCell(value: prospect.broadJump.map { "\($0)in" },
                      tier: prospect.broadJump.map { broadTier($0) }, width: 60,
                      percentile: prospect.broadJump.map { drillPercentile(Double($0), drill: .broad, prospect.position) })

            drillCell(value: prospect.coneDrill.map { String(format: "%.2f", $0) },
                      tier: prospect.coneDrill.map { coneTier($0) }, width: 66,
                      percentile: prospect.coneDrill.map { drillPercentile($0, drill: .threeCone, prospect.position) })

            drillCell(value: prospect.shuttleTime.map { String(format: "%.2f", $0) },
                      tier: prospect.shuttleTime.map { shuttleTier($0) }, width: 66,
                      percentile: prospect.shuttleTime.map { drillPercentile($0, drill: .shuttle, prospect.position) })

            // Position drill grade
            Text(prospect.positionDrillGrade ?? "--")
                .font(.caption.weight(.bold))
                .foregroundStyle(prospect.positionDrillGrade.map { PositionGradeCalculator.gradeColorForLetter($0) } ?? Color.textTertiary)
                .frame(width: 66)

            // Chevron for row navigation
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
                .frame(width: 20)
        }
    }

    private func drillCell(value: String?, tier: DrillTier?, width: CGFloat, percentile: Int? = nil) -> some View {
        VStack(spacing: 1) {
            Text(value ?? "--")
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
        switch percentile {
        case 90...:    return ("Top 10%", .accentGold)
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

            Text("No Combine Results Yet")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.textPrimary)

            Text("Combine results will be available during the Combine phase.")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Media Mention Helpers

    private func isNegativeMediaMention(_ mention: String) -> Bool {
        let negativeKeywords = ["disappoint", "concern", "struggled", "slow", "poor", "weak", "dropped", "injury", "flag", "bust"]
        let lower = mention.lowercased()
        return negativeKeywords.contains { lower.contains($0) }
    }

    private func mediaBubble(_ mention: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MEDIA")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(Color.textTertiary)

            Text("\"\(mention)\"")
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

    // MARK: - Grade Display

    private func gradeDisplayText(for prospect: CollegeProspect) -> String {
        if let gradeRange = prospect.scoutedOverallGrade {
            return gradeRange.displayText
        }
        return prospect.scoutGrade ?? "--"
    }

    private func gradeDisplayColor(for prospect: CollegeProspect) -> Color {
        if let gradeRange = prospect.scoutedOverallGrade {
            return PositionGradeCalculator.gradeColorForLetter(gradeRange.midGrade.rawValue)
        }
        if let grade = prospect.scoutGrade {
            return PositionGradeCalculator.gradeColorForLetter(grade)
        }
        return Color.textTertiary
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
    case grade, projection
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
            ]
        )
    }
}
