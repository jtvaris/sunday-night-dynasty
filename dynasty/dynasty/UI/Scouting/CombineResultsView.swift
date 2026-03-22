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

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

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
                                    ForEach(Array(sortedProspects.enumerated()), id: \.element.id) { index, prospect in
                                        NavigationLink(destination: ProspectDetailView(career: career, prospect: prospect)) {
                                            combineRow(index: index + 1, prospect: prospect)
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 8)
                                                .background(index % 2 == 0 ? Color.backgroundPrimary : Color.backgroundSecondary.opacity(0.5))
                                        }
                                        .buttonStyle(.plain)

                                        Divider().overlay(Color.surfaceBorder.opacity(0.5))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .onAppear { loadTeamPlayers() }
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
                Text(prospect.preCombineGrade ?? "--")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.textTertiary)
                Image(systemName: isRiser ? "arrow.up" : "arrow.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(isRiser ? Color.success : Color.danger)
                Text(prospect.scoutGrade ?? "--")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isRiser ? Color.success : Color.danger)
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
            sortableHeader("GRD", column: .grade, width: 44)
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
            // Star / watchlist toggle
            Button {
                toggleWatchlist(prospect)
            } label: {
                Image(systemName: prospect.prospectFlag != .none ? "star.fill" : "star")
                    .font(.caption)
                    .foregroundStyle(prospect.prospectFlag != .none ? Color.accentGold : Color.textTertiary)
                    .frame(width: 30)
            }
            .buttonStyle(.plain)

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

            // GRD column
            Text(gradeDisplayText(for: prospect))
                .font(.caption.weight(.bold))
                .foregroundStyle(gradeDisplayColor(for: prospect))
                .frame(width: 44)

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
                      tier: prospect.fortyTime.map { fortyTier($0) }, width: 60,
                      percentile: prospect.fortyTime.map { drillPercentile($0, \.fortyYard, prospect.position) })

            drillCell(value: prospect.benchPress.map { "\($0)" },
                      tier: prospect.benchPress.map { benchTier($0) }, width: 60,
                      percentile: prospect.benchPress.map { drillPercentile(Double($0), \.benchPress, prospect.position) })

            drillCell(value: prospect.verticalJump.map { String(format: "%.1f\"", $0) },
                      tier: prospect.verticalJump.map { verticalTier($0) }, width: 60,
                      percentile: prospect.verticalJump.map { drillPercentile($0, \.verticalJump, prospect.position) })

            drillCell(value: prospect.broadJump.map { "\($0)in" },
                      tier: prospect.broadJump.map { broadTier($0) }, width: 60,
                      percentile: prospect.broadJump.map { drillPercentile(Double($0), \.broadJump, prospect.position) })

            drillCell(value: prospect.coneDrill.map { String(format: "%.2f", $0) },
                      tier: prospect.coneDrill.map { coneTier($0) }, width: 66,
                      percentile: prospect.coneDrill.map { drillPercentile($0, \.threeCone, prospect.position) })

            drillCell(value: prospect.shuttleTime.map { String(format: "%.2f", $0) },
                      tier: prospect.shuttleTime.map { shuttleTier($0) }, width: 66,
                      percentile: prospect.shuttleTime.map { drillPercentile($0, \.shuttle, prospect.position) })

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
                Text("\(pct)th")
                    .font(.system(size: 8, weight: .semibold).monospacedDigit())
                    .foregroundStyle(percentileColor(pct))
            }
        }
        .frame(width: width)
    }

    private func percentileColor(_ pct: Int) -> Color {
        if pct >= 75 { return .success }
        if pct >= 50 { return .accentGold }
        if pct >= 25 { return .textSecondary }
        return .danger
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

    private func drillPercentile(_ value: Double, _ keyPath: KeyPath<CombineBenchmarks.PositionBenchmarks, CombineBenchmarks.DrillBenchmark>, _ position: Position) -> Int {
        let benchmarks = CombineBenchmarks.benchmarks(for: position)
        return CombineBenchmarks.percentile(value: value, benchmark: benchmarks[keyPath: keyPath])
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
