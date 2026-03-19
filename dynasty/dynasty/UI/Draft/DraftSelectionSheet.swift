import SwiftUI
import SwiftData

// MARK: - Sort Option

private enum DraftSelectionSort: String, CaseIterable, Identifiable {
    case overall    = "Overall"
    case projection = "Projection"
    case position   = "Position"
    case grade      = "Grade"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overall:    return "star.fill"
        case .projection: return "list.number"
        case .position:   return "rectangle.3.group"
        case .grade:      return "checkmark.seal.fill"
        }
    }
}

// MARK: - DraftSelectionSheet

/// Presented as a sheet when it is the player's turn to pick.
struct DraftSelectionSheet: View {

    let career: Career
    let availableProspects: [CollegeProspect]
    let pickNumber: Int
    let round: Int
    let teamNeeds: [Position]
    let teamCoaches: [Coach]
    let onDraft: (CollegeProspect) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var positionFilter: ProspectPositionFilter = .all
    @State private var sortOption: DraftSelectionSort = .overall
    @State private var selectedProspect: CollegeProspect?
    @State private var showConfirmation = false

    // MARK: - Filtered Prospects

    private var filtered: [CollegeProspect] {
        var result = availableProspects

        if !searchText.isEmpty {
            result = result.filter {
                $0.fullName.localizedCaseInsensitiveContains(searchText) ||
                $0.college.localizedCaseInsensitiveContains(searchText) ||
                $0.position.rawValue.localizedCaseInsensitiveContains(searchText)
            }
        }

        if positionFilter != .all {
            result = result.filter { positionFilter.matches($0.position) }
        }

        switch sortOption {
        case .overall:
            return result.sorted { ($0.scoutedOverall ?? -1) > ($1.scoutedOverall ?? -1) }
        case .projection:
            return result.sorted {
                ($0.draftProjection ?? Int.max) < ($1.draftProjection ?? Int.max)
            }
        case .position:
            return result.sorted {
                let ai = Position.allCases.firstIndex(of: $0.position) ?? 0
                let bi = Position.allCases.firstIndex(of: $1.position) ?? 0
                if ai != bi { return ai < bi }
                return ($0.scoutedOverall ?? 0) > ($1.scoutedOverall ?? 0)
            }
        case .grade:
            return result.sorted {
                let ag = gradeOrder($0.scoutGrade)
                let bg = gradeOrder($1.scoutGrade)
                return ag < bg
            }
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()

                VStack(spacing: 0) {
                    pickHeader
                    teamNeedsBar
                    filterBar
                    sortBar
                    prospectList
                }
            }
            .navigationTitle("Your Pick")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    sortMenu
                }
            }
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search prospects..."
            )
            .alert("Draft \(selectedProspect?.fullName ?? "")?", isPresented: $showConfirmation) {
                Button("Draft", role: .none) {
                    if let prospect = selectedProspect {
                        onDraft(prospect)
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let p = selectedProspect {
                    Text("\(p.position.rawValue) from \(p.college)\(p.scoutedOverall.map { " — \($0) OVR" } ?? "")")
                }
            }
        }
    }

    // MARK: - Pick Header

    private var pickHeader: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("ON THE CLOCK")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Color.accentGold)
                    .tracking(1.5)
                Text("Round \(round)  ·  Pick \(pickNumber)")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(filtered.count)")
                    .font(.title3.weight(.heavy).monospacedDigit())
                    .foregroundStyle(Color.textPrimary)
                Text("Available")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(Color.backgroundSecondary)
        .overlay(
            Rectangle()
                .fill(Color.accentGold.opacity(0.6))
                .frame(height: 2),
            alignment: .bottom
        )
    }

    // MARK: - Team Needs Bar

    private var teamNeedsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Text("Needs:")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.accentGold)

                ForEach(teamNeedPositions, id: \.self) { position in
                    Text(position.rawValue)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.accentGold.opacity(0.12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(Color.accentGold.opacity(0.3), lineWidth: 1)
                                )
                        )
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
        .background(Color.backgroundSecondary)
        .overlay(
            Rectangle()
                .fill(Color.surfaceBorder)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    /// Top 5 team needs passed in from DraftView.
    private var teamNeedPositions: [Position] {
        Array(teamNeeds.prefix(5))
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ProspectPositionFilter.allCases) { filter in
                    filterChip(filter)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .background(Color.backgroundSecondary)
        .overlay(
            Rectangle()
                .fill(Color.surfaceBorder)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    private func filterChip(_ filter: ProspectPositionFilter) -> some View {
        Button {
            positionFilter = filter
        } label: {
            Text(filter.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(positionFilter == filter ? Color.backgroundPrimary : Color.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(positionFilter == filter ? Color.accentGold : Color.backgroundTertiary)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sort Bar

    private var sortBar: some View {
        HStack(spacing: 0) {
            Text("Sort:")
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
                .padding(.leading, 20)

            ForEach(DraftSelectionSort.allCases) { option in
                Button {
                    sortOption = option
                } label: {
                    Text(option.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(sortOption == option ? Color.accentGold : Color.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .background(Color.backgroundSecondary)
        .overlay(
            Rectangle()
                .fill(Color.surfaceBorder)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort by", selection: $sortOption) {
                ForEach(DraftSelectionSort.allCases) { sort in
                    Label(sort.rawValue, systemImage: sort.icon).tag(sort)
                }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
    }

    // MARK: - Prospect List

    private var prospectList: some View {
        Group {
            if filtered.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "person.slash")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.textTertiary)
                    Text("No Prospects Match")
                        .font(.headline)
                        .foregroundStyle(Color.textSecondary)
                    Text("Adjust your filter or search.")
                        .font(.subheadline)
                        .foregroundStyle(Color.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filtered) { prospect in
                        prospectRow(prospect)
                            .listRowBackground(Color.backgroundSecondary)
                            .listRowSeparatorTint(Color.surfaceBorder)
                    }
                }
                .scrollContentBackground(.hidden)
                .listStyle(.plain)
            }
        }
    }

    private func prospectRow(_ prospect: CollegeProspect) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Position badge
                Text(prospect.position.rawValue)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                    .frame(width: 36, height: 28)
                    .background(positionColor(prospect.position), in: RoundedRectangle(cornerRadius: 4))

                // Name + college
                VStack(alignment: .leading, spacing: 2) {
                    Text(prospect.fullName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(prospect.college)
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                        if let proj = prospect.draftProjection {
                            Text("Rd \(proj)")
                                .font(.caption)
                                .foregroundStyle(Color.textTertiary)
                        }
                    }
                }

                Spacer()

                // Value indicator + Scheme fit
                VStack(alignment: .trailing, spacing: 3) {
                    valueIndicatorBadge(for: prospect)
                    schemeFitBadge(for: prospect)
                }

                // Grade & overall
                VStack(alignment: .trailing, spacing: 3) {
                    if let overall = prospect.scoutedOverall {
                        Text("\(overall)")
                            .font(.callout.weight(.bold).monospacedDigit())
                            .foregroundStyle(Color.forRating(overall))
                    } else {
                        Text("?")
                            .font(.callout.weight(.bold))
                            .foregroundStyle(Color.textTertiary)
                    }
                    if let grade = prospect.scoutGrade {
                        Text(grade)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentGold)
                    }
                }
                .frame(minWidth: 36)

                // Detail / Draft buttons
                HStack(spacing: 8) {
                    NavigationLink {
                        ProspectDetailView(career: career, prospect: prospect)
                    } label: {
                        Text("View")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentBlue)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.accentBlue.opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        selectedProspect = prospect
                        showConfirmation = true
                    } label: {
                        Text("Draft")
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(Color.backgroundPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.accentGold)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    // MARK: - Value / Scheme Fit Indicators

    /// Shows REACH / VALUE / STEAL based on prospect's mock draft pick vs current pick.
    @ViewBuilder
    private func valueIndicatorBadge(for prospect: CollegeProspect) -> some View {
        let result = computeValueIndicator(for: prospect)
        if let result {
            Text(result.label)
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(result.color)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(result.color.opacity(0.15))
                )
        }
    }

    private func computeValueIndicator(for prospect: CollegeProspect) -> (label: String, color: Color)? {
        if let mockPick = prospect.mockDraftPickNumber {
            let delta = mockPick - pickNumber
            if delta >= 10 { return ("STEAL", .success) }
            if delta <= -10 { return ("REACH", .danger) }
            return ("VALUE", .accentGold)
        } else if let projRound = prospect.draftProjection {
            let currentRound = ((pickNumber - 1) / 32) + 1
            let delta = projRound - currentRound
            if delta >= 1 { return ("STEAL", .success) }
            if delta <= -1 { return ("REACH", .danger) }
            return ("VALUE", .accentGold)
        }
        return nil
    }

    /// Shows Good/Fair/Poor scheme fit based on team's coordinators.
    @ViewBuilder
    private func schemeFitBadge(for prospect: CollegeProspect) -> some View {
        if prospect.scoutedOverall != nil, let fit = evaluateSchemeFit(for: prospect) {
            Text(fit)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(schemeFitColor(fit))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(schemeFitColor(fit).opacity(0.15))
                )
        }
    }

    private func evaluateSchemeFit(for prospect: CollegeProspect) -> String? {
        let oc = teamCoaches.first(where: { $0.role == .offensiveCoordinator })
        let dc = teamCoaches.first(where: { $0.role == .defensiveCoordinator })

        if prospect.position.side == .offense, let scheme = oc?.offensiveScheme {
            return schemeFitLabel(offensiveScore(prospect, scheme: scheme))
        } else if prospect.position.side == .defense, let scheme = dc?.defensiveScheme {
            return schemeFitLabel(defensiveScore(prospect, scheme: scheme))
        }
        return nil
    }

    private func offensiveScore(_ prospect: CollegeProspect, scheme: OffensiveScheme) -> Int {
        let phys = prospect.truePhysical
        switch prospect.truePositionAttributes {
        case .quarterback(let qb):
            switch scheme {
            case .airRaid, .spread: return (qb.accuracyShort + qb.accuracyDeep + qb.armStrength) / 3
            case .westCoast, .proPassing: return (qb.accuracyShort + qb.accuracyMid + qb.pocketPresence) / 3
            case .powerRun, .shanahan: return (qb.pocketPresence + qb.scrambling + phys.strength) / 3
            case .rpo, .option: return (qb.scrambling + phys.speed + qb.accuracyShort) / 3
            }
        case .wideReceiver(let wr):
            switch scheme {
            case .airRaid, .spread: return (wr.routeRunning + wr.catching + phys.speed) / 3
            case .westCoast, .proPassing: return (wr.routeRunning + wr.catching + wr.release) / 3
            default: return (wr.routeRunning + wr.catching) / 2
            }
        case .runningBack(let rb):
            switch scheme {
            case .powerRun: return (rb.breakTackle + rb.vision + phys.strength) / 3
            case .shanahan: return (rb.vision + rb.elusiveness + phys.speed) / 3
            default: return (rb.vision + rb.elusiveness) / 2
            }
        case .offensiveLine(let ol):
            switch scheme {
            case .powerRun: return (ol.runBlock + ol.anchor + phys.strength) / 3
            case .airRaid, .proPassing, .westCoast: return (ol.passBlock + ol.anchor + phys.strength) / 3
            default: return (ol.runBlock + ol.passBlock) / 2
            }
        case .tightEnd(let te):
            switch scheme {
            case .airRaid, .spread, .westCoast: return (te.catching + te.routeRunning + te.speed) / 3
            case .powerRun, .shanahan: return (te.blocking + te.speed + phys.strength) / 3
            default: return (te.catching + te.blocking) / 2
            }
        default: return 65
        }
    }

    private func defensiveScore(_ prospect: CollegeProspect, scheme: DefensiveScheme) -> Int {
        let phys = prospect.truePhysical
        switch prospect.truePositionAttributes {
        case .defensiveBack(let db):
            switch scheme {
            case .pressMan: return (db.manCoverage + db.press + phys.speed) / 3
            case .cover3, .tampa2: return (db.zoneCoverage + db.ballSkills + phys.speed) / 3
            case .multiple, .hybrid: return (db.manCoverage + db.zoneCoverage + db.press) / 3
            default: return (db.manCoverage + db.zoneCoverage) / 2
            }
        case .linebacker(let lb):
            switch scheme {
            case .base34: return (lb.tackling + lb.blitzing + phys.strength) / 3
            case .base43: return (lb.tackling + lb.zoneCoverage + phys.speed) / 3
            case .tampa2, .cover3: return (lb.zoneCoverage + phys.speed + lb.tackling) / 3
            default: return (lb.tackling + lb.zoneCoverage) / 2
            }
        case .defensiveLine(let dl):
            switch scheme {
            case .base43: return (dl.passRush + dl.powerMoves + phys.strength) / 3
            case .base34: return (dl.blockShedding + dl.powerMoves + phys.strength) / 3
            case .multiple, .hybrid: return (dl.passRush + dl.finesseMoves + phys.agility) / 3
            default: return (dl.passRush + dl.blockShedding) / 2
            }
        default: return 65
        }
    }

    private func schemeFitLabel(_ score: Int) -> String {
        switch score {
        case 75...: return "Good"
        case 55..<75: return "Fair"
        default: return "Poor"
        }
    }

    private func schemeFitColor(_ fit: String) -> Color {
        switch fit {
        case "Good": return .success
        case "Fair": return .warning
        default: return .danger
        }
    }

    // MARK: - Helpers

    private func positionColor(_ position: Position) -> Color {
        switch position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }

    private func gradeOrder(_ grade: String?) -> Int {
        switch grade {
        case "A+": return 0
        case "A":  return 1
        case "A-": return 2
        case "B+": return 3
        case "B":  return 4
        case "B-": return 5
        case "C+": return 6
        case "C":  return 7
        default:   return 8
        }
    }
}

// MARK: - Preview

#Preview {
    let career = Career(playerName: "John Doe", role: .gm, capMode: .simple)
    let prospects: [CollegeProspect] = [
        CollegeProspect(
            firstName: "Caleb", lastName: "Williams",
            college: "USC", position: .QB,
            age: 21, height: 74, weight: 214,
            truePositionAttributes: .quarterback(QBAttributes(
                armStrength: 92, accuracyShort: 88, accuracyMid: 90,
                accuracyDeep: 85, pocketPresence: 87, scrambling: 78
            )),
            truePersonality: PlayerPersonality(archetype: .fieryCompetitor, motivation: .winning),
            scoutedOverall: 89, scoutGrade: "A", draftProjection: 1
        ),
        CollegeProspect(
            firstName: "Marvin", lastName: "Harrison Jr.",
            college: "Ohio State", position: .WR,
            age: 21, height: 75, weight: 209,
            truePositionAttributes: .wideReceiver(WRAttributes(
                routeRunning: 91, catching: 93, release: 90, spectacularCatch: 88
            )),
            truePersonality: PlayerPersonality(archetype: .quietProfessional, motivation: .winning),
            scoutedOverall: 91, scoutGrade: "A+", draftProjection: 1
        ),
    ]

    DraftSelectionSheet(
        career: career,
        availableProspects: prospects,
        pickNumber: 1,
        round: 1,
        teamNeeds: [.CB, .DE, .SS],
        teamCoaches: [],
        onDraft: { _ in }
    )
    .modelContainer(for: [Career.self, CollegeProspect.self], inMemory: true)
}
