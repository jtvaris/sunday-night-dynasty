import SwiftUI
import SwiftData

struct MockDraftView: View {
    let career: Career
    let prospects: [CollegeProspect]

    @Environment(\.modelContext) private var modelContext
    @State private var teams: [Team] = []

    private var mockDraft: [ScoutingEngine.MockDraftPick] {
        WeekAdvancer.currentMockDraft
    }

    private var userTeamAbbreviation: String? {
        teams.first { $0.id == career.teamID }?.abbreviation
    }

    /// Prospects the user has scouted (on their big board).
    private var scoutedProspects: [UUID: CollegeProspect] {
        Dictionary(uniqueKeysWithValues: prospects.filter { $0.scoutedOverall != nil }.map { ($0.id, $0) })
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

                if mockDraft.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(mockDraft, id: \.pickNumber) { pick in
                            let prospect = prospects.first { $0.id == pick.prospectID }
                            let isUserPick = pick.teamAbbreviation == userTeamAbbreviation

                            mockDraftRow(pick: pick, prospect: prospect, isUserPick: isUserPick)
                                .listRowBackground(
                                    isUserPick
                                        ? Color.accentGold.opacity(0.1)
                                        : Color.backgroundSecondary
                                )
                        }

                        Section {
                            HStack {
                                Image(systemName: "info.circle")
                                    .foregroundStyle(Color.textTertiary)
                                    .font(.caption)
                                Text("Mock drafts are projections and may not reflect actual draft results.")
                                    .font(.caption)
                                    .foregroundStyle(Color.textTertiary)
                            }
                        }
                        .listRowBackground(Color.backgroundPrimary)
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.insetGrouped)
                }
            }
        }
        .task { loadTeams() }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("MEDIA MOCK DRAFT")
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(Color.textPrimary)

                Text("Season \(career.currentSeason) \u{2022} Week \(career.currentWeek)")
                    .font(.caption)
                    .foregroundStyle(Color.accentGold)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("First Round")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                Text("\(mockDraft.count) picks")
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
            }
        }
    }

    // MARK: - Row

    private func mockDraftRow(pick: ScoutingEngine.MockDraftPick, prospect: CollegeProspect?, isUserPick: Bool) -> some View {
        HStack(spacing: 14) {
            // Pick number
            Text("\(pick.pickNumber)")
                .font(.title3.weight(.heavy).monospacedDigit())
                .foregroundStyle(isUserPick ? Color.accentGold : Color.textSecondary)
                .frame(width: 32, alignment: .trailing)

            // Team abbreviation
            Text(pick.teamAbbreviation)
                .font(.caption.weight(.bold))
                .foregroundStyle(isUserPick ? Color.accentGold : Color.textPrimary)
                .frame(width: 44, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.backgroundPrimary)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isUserPick ? Color.accentGold : Color.surfaceBorder, lineWidth: isUserPick ? 2 : 1)
                        )
                )

            // Prospect info
            if let prospect {
                VStack(alignment: .leading, spacing: 2) {
                    Text(prospect.fullName)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color.textPrimary)

                    HStack(spacing: 6) {
                        Text(prospect.position.rawValue)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.textPrimary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(positionColor(for: prospect), in: RoundedRectangle(cornerRadius: 3))

                        Text(prospect.college)
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            } else {
                Text("Unknown Prospect")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.textTertiary)
            }

            Spacer()

            // Scouted grade vs mock (if on user's big board)
            if let prospect, let scoutedOverall = scoutedProspects[prospect.id]?.scoutedOverall {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(scoutedOverall)")
                        .font(.callout.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.forRating(scoutedOverall))
                    Text("Your Grade")
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                }
            }

            // Expert confidence
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(expertConfidence(for: pick.pickNumber))%")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(confidenceColor(for: pick.pickNumber))
                Text("Confidence")
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
            }
            .frame(width: 72)
        }
        .padding(.vertical, 4)
        .overlay(
            isUserPick
                ? RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentGold, lineWidth: 1.5)
                    .padding(-4)
                : nil
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(pick: pick, prospect: prospect, isUserPick: isUserPick))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 52))
                .foregroundStyle(Color.textTertiary)

            Text("No Mock Draft Available")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.textPrimary)

            Text("The first mock draft will be generated at midseason (Week 9).")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func positionColor(for prospect: CollegeProspect) -> Color {
        switch prospect.position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }

    /// Deterministic "expert confidence" seeded by pick number so it stays stable.
    private func expertConfidence(for pickNumber: Int) -> Int {
        // Higher picks get higher base confidence, with per-pick variance
        let base: Int
        switch pickNumber {
        case 1...5:   base = 78
        case 6...10:  base = 65
        case 11...20: base = 52
        default:      base = 40
        }
        // Use pick number as seed for stable pseudo-random offset
        let offset = ((pickNumber * 7 + 13) % 21) - 10  // range -10...10
        return max(25, min(95, base + offset))
    }

    private func confidenceColor(for pickNumber: Int) -> Color {
        let confidence = expertConfidence(for: pickNumber)
        if confidence >= 70 { return .success }
        if confidence >= 50 { return .accentGold }
        return .textSecondary
    }

    private func loadTeams() {
        let desc = FetchDescriptor<Team>()
        teams = (try? modelContext.fetch(desc)) ?? []
    }

    private func accessibilityLabel(pick: ScoutingEngine.MockDraftPick, prospect: CollegeProspect?, isUserPick: Bool) -> String {
        let name = prospect?.fullName ?? "Unknown"
        let pos = prospect?.position.rawValue ?? ""
        let team = isUserPick ? "\(pick.teamAbbreviation) (your team)" : pick.teamAbbreviation
        return "Pick \(pick.pickNumber), \(team), \(name) \(pos), confidence \(expertConfidence(for: pick.pickNumber)) percent"
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        MockDraftView(
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
                    scoutedOverall: 89, scoutGrade: "A",
                    draftProjection: 1,
                    mockDraftPickNumber: 1, mockDraftTeam: "CHI"
                ),
            ]
        )
    }
    .modelContainer(for: [Career.self, Team.self, CollegeProspect.self], inMemory: true)
}
