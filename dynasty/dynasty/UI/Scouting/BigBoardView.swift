import SwiftUI

struct BigBoardView: View {
    let career: Career
    let prospects: [CollegeProspect]

    @State private var positionFilter: ProspectPositionFilter = .all
    @State private var boardOrder: [UUID] = []

    // MARK: - Board Prospects
    // Only prospects that have been scouted appear on the big board.

    private var scoutedProspects: [CollegeProspect] {
        prospects.filter { $0.scoutedOverall != nil }
    }

    private var orderedBoard: [CollegeProspect] {
        let filtered: [CollegeProspect]
        if positionFilter == .all {
            filtered = scoutedProspects
        } else {
            filtered = scoutedProspects.filter { positionFilter.matches($0.position) }
        }

        // Maintain saved order, appending any newly scouted prospects at the end.
        var orderedIDs = boardOrder.filter { id in filtered.contains { $0.id == id } }
        let unordered = filtered.filter { !orderedIDs.contains($0.id) }.map { $0.id }
        orderedIDs.append(contentsOf: unordered)

        return orderedIDs.compactMap { id in filtered.first { $0.id == id } }
    }

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            if scoutedProspects.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(Array(orderedBoard.enumerated()), id: \.element.id) { index, prospect in
                        NavigationLink(destination: ProspectDetailView(career: career, prospect: prospect)) {
                            BigBoardRowView(rank: index + 1, prospect: prospect)
                        }
                        .listRowBackground(Color.backgroundSecondary)
                    }
                    .onMove { from, to in
                        var ids = orderedBoard.map { $0.id }
                        ids.move(fromOffsets: from, toOffset: to)
                        boardOrder = ids
                    }
                }
                .scrollContentBackground(.hidden)
                .listStyle(.insetGrouped)
                .environment(\.editMode, .constant(.active))
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                positionPicker
            }
        }
        .onAppear {
            if boardOrder.isEmpty {
                // Default order: by scouted overall descending
                boardOrder = scoutedProspects
                    .sorted { ($0.scoutedOverall ?? 0) > ($1.scoutedOverall ?? 0) }
                    .map { $0.id }
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

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "list.star")
                .font(.system(size: 52))
                .foregroundStyle(Color.textTertiary)

            Text("Big Board Is Empty")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.textPrimary)

            Text("Scout prospects to add them to your draft board.")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Big Board Row View

struct BigBoardRowView: View {
    let rank: Int
    let prospect: CollegeProspect

    var body: some View {
        HStack(spacing: 14) {
            // Rank number
            Text("\(rank)")
                .font(.title3.weight(.heavy).monospacedDigit())
                .foregroundStyle(rankColor)
                .frame(width: 32, alignment: .trailing)

            // Position badge
            Text(prospect.position.rawValue)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 34, height: 26)
                .background(positionColor, in: RoundedRectangle(cornerRadius: 4))

            // Name and college
            VStack(alignment: .leading, spacing: 2) {
                Text(prospect.fullName)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.textPrimary)
                Text(prospect.college)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer()

            // Grade and overall
            VStack(alignment: .trailing, spacing: 3) {
                if let overall = prospect.scoutedOverall {
                    Text("\(overall)")
                        .font(.callout.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.forRating(overall))
                }
                if let grade = prospect.scoutGrade {
                    Text(grade)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentGold)
                }
            }

            // Drag handle (shown because editMode is active)
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(Color.textTertiary)
                .font(.caption)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Helpers

    private var rankColor: Color {
        switch rank {
        case 1:    return .accentGold
        case 2...5: return .textPrimary
        default:   return .textSecondary
        }
    }

    private var positionColor: Color {
        switch prospect.position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }

    private var accessibilityDescription: String {
        let overall = prospect.scoutedOverall.map { "\($0)" } ?? "ungraded"
        return "Rank \(rank), \(prospect.fullName), \(prospect.position.rawValue), \(prospect.college), overall \(overall)"
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        BigBoardView(
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
                    firstName: "Marvin", lastName: "Harrison Jr.",
                    college: "Ohio State", position: .WR,
                    age: 21, height: 75, weight: 209,
                    truePositionAttributes: .wideReceiver(WRAttributes(
                        routeRunning: 91, catching: 93, release: 90, spectacularCatch: 88
                    )),
                    truePersonality: PlayerPersonality(archetype: .quietProfessional, motivation: .winning),
                    scoutedOverall: 91, scoutGrade: "A+", draftProjection: 2
                ),
            ]
        )
    }
}
