import SwiftUI

struct ProspectListView: View {
    let career: Career
    let prospects: [CollegeProspect]

    @State private var positionFilter: ProspectPositionFilter = .all
    @State private var sortOrder: ProspectSort = .draftProjection

    // MARK: - Filtered & Sorted Prospects

    private var displayed: [CollegeProspect] {
        let filtered: [CollegeProspect]
        if positionFilter == .all {
            filtered = prospects
        } else {
            filtered = prospects.filter { positionFilter.matches($0.position) }
        }

        switch sortOrder {
        case .draftProjection:
            return filtered.sorted {
                let a = $0.draftProjection ?? Int.max
                let b = $1.draftProjection ?? Int.max
                return a < b
            }
        case .scoutedOverall:
            return filtered.sorted {
                let a = $0.scoutedOverall ?? -1
                let b = $1.scoutedOverall ?? -1
                return a > b
            }
        case .position:
            return filtered.sorted {
                let ai = Position.allCases.firstIndex(of: $0.position) ?? 0
                let bi = Position.allCases.firstIndex(of: $1.position) ?? 0
                if ai != bi { return ai < bi }
                return ($0.scoutedOverall ?? 0) > ($1.scoutedOverall ?? 0)
            }
        case .name:
            return filtered.sorted { $0.lastName < $1.lastName }
        }
    }

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            if displayed.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(displayed) { prospect in
                        NavigationLink(destination: ProspectDetailView(career: career, prospect: prospect)) {
                            ProspectRowView(prospect: prospect)
                        }
                        .listRowBackground(Color.backgroundSecondary)
                    }
                }
                .scrollContentBackground(.hidden)
                .listStyle(.insetGrouped)
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                positionPicker
            }
            ToolbarItem(placement: .primaryAction) {
                sortMenu
            }
        }
    }

    // MARK: - Toolbar

    private var positionPicker: some View {
        Picker("Position", selection: $positionFilter) {
            ForEach(ProspectPositionFilter.allCases) { filter in
                Text(filter.label).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .frame(minWidth: 420)
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort by", selection: $sortOrder) {
                ForEach(ProspectSort.allCases) { sort in
                    Label(sort.label, systemImage: sort.icon).tag(sort)
                }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        .accessibilityLabel("Sort prospects, currently by \(sortOrder.label)")
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(Color.textTertiary)
            Text("No Prospects Found")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
            Text("Prospects who have declared for the draft will appear here.")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Prospect Row View

struct ProspectRowView: View {
    let prospect: CollegeProspect

    private var isScouted: Bool { prospect.scoutedOverall != nil }

    var body: some View {
        HStack(spacing: 12) {
            positionBadge

            VStack(alignment: .leading, spacing: 3) {
                Text(prospect.fullName)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.textPrimary)

                HStack(spacing: 6) {
                    Text(prospect.college)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)

                    Text("·")
                        .foregroundStyle(Color.textTertiary)
                        .font(.caption)

                    Text(heightWeightLabel)
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                overallBadge
                gradeLabel
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Subviews

    private var positionBadge: some View {
        Text(prospect.position.rawValue)
            .font(.caption.weight(.bold))
            .foregroundStyle(Color.textPrimary)
            .frame(width: 36, height: 28)
            .background(positionColor, in: RoundedRectangle(cornerRadius: 4))
    }

    private var overallBadge: some View {
        Group {
            if let overall = prospect.scoutedOverall {
                Text("\(overall)")
                    .font(.callout.weight(.bold).monospacedDigit())
                    .foregroundStyle(Color.forRating(overall))
            } else {
                Text("?")
                    .font(.callout.weight(.bold))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .frame(width: 32, alignment: .trailing)
    }

    private var gradeLabel: some View {
        Group {
            if let grade = prospect.scoutGrade {
                Text(grade)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentGold)
            } else if let proj = prospect.draftProjection {
                Text("Rd \(proj)")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            } else {
                Text("Unscouted")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            }
        }
    }

    // MARK: - Helpers

    private var positionColor: Color {
        switch prospect.position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }

    private var heightWeightLabel: String {
        let feet = prospect.height / 12
        let inches = prospect.height % 12
        return "\(feet)'\(inches)\"  \(prospect.weight) lbs"
    }

    private var accessibilityDescription: String {
        let overall = prospect.scoutedOverall.map { "\($0)" } ?? "unscouted"
        return "\(prospect.fullName), \(prospect.position.rawValue), \(prospect.college), overall \(overall)"
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
    case draftProjection, scoutedOverall, position, name

    var id: String { rawValue }

    var label: String {
        switch self {
        case .draftProjection: return "Draft Projection"
        case .scoutedOverall:  return "Scouted Overall"
        case .position:        return "Position"
        case .name:            return "Name"
        }
    }

    var icon: String {
        switch self {
        case .draftProjection: return "list.number"
        case .scoutedOverall:  return "star.fill"
        case .position:        return "rectangle.3.group"
        case .name:            return "textformat"
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ProspectListView(
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
                    scoutedOverall: 89, scoutGrade: "A", draftProjection: 1
                ),
                CollegeProspect(
                    firstName: "Rome", lastName: "Odunze",
                    college: "Washington", position: .WR,
                    age: 21, height: 75, weight: 215,
                    truePositionAttributes: .wideReceiver(WRAttributes(
                        routeRunning: 85, catching: 88, release: 86, spectacularCatch: 82
                    )),
                    truePersonality: PlayerPersonality(archetype: .quietProfessional, motivation: .winning),
                    draftProjection: 9
                ),
            ]
        )
    }
}
