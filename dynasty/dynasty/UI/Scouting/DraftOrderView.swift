import SwiftUI
import SwiftData

struct DraftOrderView: View {
    let career: Career

    @Environment(\.modelContext) private var modelContext
    @State private var draftPicks: [DraftPick] = []
    @State private var teams: [Team] = []
    @State private var expandedRounds: Set<Int> = [1]
    @State private var isLoading: Bool = true

    // MARK: - Performance caches
    @State private var cachedPicksByRound: [(round: Int, picks: [DraftPick])] = []
    @State private var cachedTeamLookup: [UUID: Team] = [:]
    @State private var cachedAbbreviationLookup: [UUID: String] = [:]
    @State private var cachedUserPickNumbers: Set<Int> = []
    @State private var cachedUserTotalPicks: Int = 0

    private var userTeamID: UUID? { career.teamID }

    private var teamLookup: [UUID: Team] { cachedTeamLookup }

    private var abbreviationLookup: [UUID: String] { cachedAbbreviationLookup }

    /// Group draft picks by round.
    private var picksByRound: [(round: Int, picks: [DraftPick])] { cachedPicksByRound }

    /// User's pick numbers for highlighting.
    private var userPickNumbers: Set<Int> { cachedUserPickNumbers }

    /// Total picks the user has.
    private var userTotalPicks: Int { cachedUserTotalPicks }

    private func refreshCaches() {
        cachedTeamLookup = Dictionary(uniqueKeysWithValues: teams.map { ($0.id, $0) })
        cachedAbbreviationLookup = Dictionary(uniqueKeysWithValues: teams.map { ($0.id, $0.abbreviation) })
        let grouped = Dictionary(grouping: draftPicks) { $0.round }
        cachedPicksByRound = grouped.keys.sorted().compactMap { round in
            guard let picks = grouped[round] else { return nil }
            return (round: round, picks: picks.sorted { $0.pickNumber < $1.pickNumber })
        }
        cachedUserPickNumbers = Set(draftPicks.filter { $0.currentTeamID == userTeamID }.map { $0.pickNumber })
        cachedUserTotalPicks = draftPicks.filter { $0.currentTeamID == userTeamID && !$0.isComplete }.count
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
                    Text("Loading Draft Order...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else {
            VStack(spacing: 0) {
                headerBar
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                // User picks summary
                userPicksSummary
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)

                Divider().overlay(Color.surfaceBorder)

                if draftPicks.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(picksByRound, id: \.round) { roundGroup in
                            Section(isExpanded: Binding(
                                get: { expandedRounds.contains(roundGroup.round) },
                                set: { isExpanded in
                                    if isExpanded {
                                        expandedRounds.insert(roundGroup.round)
                                    } else {
                                        expandedRounds.remove(roundGroup.round)
                                    }
                                }
                            )) {
                                ForEach(roundGroup.picks) { pick in
                                    draftPickRow(pick: pick, in: roundGroup.round)
                                        .listRowBackground(
                                            pick.currentTeamID == userTeamID
                                                ? Color.accentGold.opacity(0.08)
                                                : Color.backgroundSecondary
                                        )
                                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                }
                            } header: {
                                roundHeader(round: roundGroup.round, pickCount: roundGroup.picks.count)
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.sidebar)
                }
            }
            } // end else (not loading)
        }
        .task {
            loadData()
            refreshCaches()
            isLoading = false
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("DRAFT ORDER")
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(Color.textPrimary)

                Text("Season \(String(career.currentSeason)) \u{2022} \(draftPicks.count) total picks")
                    .font(.caption)
                    .foregroundStyle(Color.accentGold)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("Your Picks: \(userTotalPicks)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.accentGold)
                Text("7 rounds")
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
            }
        }
    }

    // MARK: - User Picks Summary

    private var userPicksSummary: some View {
        let userPicks = draftPicks
            .filter { $0.currentTeamID == userTeamID && !$0.isComplete }
            .sorted { $0.pickNumber < $1.pickNumber }

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(userPicks) { pick in
                    VStack(spacing: 2) {
                        Text("#\(pick.pickNumber)")
                            .font(.system(size: 14, weight: .heavy).monospacedDigit())
                            .foregroundStyle(Color.accentGold)

                        Text("Rd \(pick.round)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.textSecondary)

                        if pick.originalTeamID != pick.currentTeamID,
                           let origAbbr = abbreviationLookup[pick.originalTeamID] {
                            Text("via \(origAbbr)")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(Color.accentBlue)
                        }
                    }
                    .frame(width: 52, height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.backgroundSecondary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.accentGold, lineWidth: 2)
                            )
                    )
                }
            }
        }
    }

    // MARK: - Round Header

    private func roundHeader(round: Int, pickCount: Int) -> some View {
        HStack {
            Text(roundName(round).uppercased())
                .font(.caption.weight(.heavy))
                .foregroundStyle(round <= 3 ? Color.accentGold : Color.textSecondary)

            Spacer()

            Text("\(pickCount) picks")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.textTertiary)
        }
    }

    // MARK: - Draft Pick Row

    private func draftPickRow(pick: DraftPick, in round: Int) -> some View {
        let isUserPick = pick.currentTeamID == userTeamID
        let isTraded = pick.originalTeamID != pick.currentTeamID
        let team = teamLookup[pick.currentTeamID]
        let originalTeam = teamLookup[pick.originalTeamID]

        return HStack(spacing: 10) {
            // Pick number with value indicator
            VStack(spacing: 1) {
                Text("\(pick.pickNumber)")
                    .font(.system(size: 16, weight: .heavy).monospacedDigit())
                    .foregroundStyle(isUserPick ? Color.accentGold : Color.textPrimary)

                // Pick value indicator
                pickValueDot(pickNumber: pick.pickNumber)
            }
            .frame(width: 36)

            // Team info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(team?.abbreviation ?? "???")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(isUserPick ? Color.accentGold : Color.textPrimary)
                        .frame(width: 38, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.backgroundPrimary)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .strokeBorder(
                                            isUserPick ? Color.accentGold : Color.surfaceBorder,
                                            lineWidth: isUserPick ? 2 : 1
                                        )
                                )
                        )

                    if let team {
                        Text(team.fullName)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                    }

                    if isUserPick {
                        Text("YOUR PICK")
                            .font(.system(size: 7, weight: .heavy))
                            .foregroundStyle(Color.backgroundPrimary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.accentGold, in: Capsule())
                    }
                }

                HStack(spacing: 8) {
                    // Record
                    if let team {
                        Text(team.record)
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Color.textSecondary)
                    }

                    // Trade info
                    if isTraded, let origAbbr = originalTeam?.abbreviation, let currentAbbr = team?.abbreviation {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.left.arrow.right")
                                .font(.system(size: 8))
                                .foregroundStyle(Color.accentBlue)
                            Text("Originally: \(origAbbr) \u{2192} \(currentAbbr)")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Color.accentBlue)
                        }
                    }

                    // Already picked info
                    if pick.isComplete, let playerName = pick.playerName, let pos = pick.playerPosition {
                        HStack(spacing: 3) {
                            Text(pos)
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Color.textPrimary)
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: 2))
                            Text(playerName)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                }
            }

            Spacer()

            // Pick value label
            Text(pickValueLabel(pickNumber: pick.pickNumber))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(pickValueColor(pickNumber: pick.pickNumber))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(pickValueColor(pickNumber: pick.pickNumber).opacity(0.12))
                )

            // Trade pick button (user's picks only, placeholder)
            if isUserPick && !pick.isComplete {
                Image(systemName: "arrow.left.arrow.right.circle")
                    .font(.body)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(.vertical, 2)
        .overlay(
            isUserPick
                ? RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.accentGold.opacity(0.4), lineWidth: 1.5)
                    .padding(-4)
                : nil
        )
    }

    // MARK: - Pick Value Helpers

    private func pickValueDot(pickNumber: Int) -> some View {
        HStack(spacing: 1) {
            let dots = pickValueDotCount(pickNumber: pickNumber)
            ForEach(0..<dots, id: \.self) { _ in
                Circle()
                    .fill(pickValueColor(pickNumber: pickNumber))
                    .frame(width: 4, height: 4)
            }
        }
    }

    private func pickValueDotCount(pickNumber: Int) -> Int {
        switch pickNumber {
        case 1...10:  return 4
        case 11...32: return 3
        case 33...64: return 2
        default:      return 1
        }
    }

    private func pickValueLabel(pickNumber: Int) -> String {
        switch pickNumber {
        case 1...5:    return "Elite"
        case 6...10:   return "Premium"
        case 11...32:  return "High"
        case 33...64:  return "Mid"
        case 65...100: return "Avg"
        default:       return "Low"
        }
    }

    private func pickValueColor(pickNumber: Int) -> Color {
        switch pickNumber {
        case 1...10:   return .accentGold
        case 11...32:  return .success
        case 33...64:  return .accentBlue
        case 65...100: return .textSecondary
        default:       return .textTertiary
        }
    }

    // MARK: - Round Name

    private func roundName(_ round: Int) -> String {
        switch round {
        case 1: return "First Round"
        case 2: return "Second Round"
        case 3: return "Third Round"
        case 4: return "Fourth Round"
        case 5: return "Fifth Round"
        case 6: return "Sixth Round"
        case 7: return "Seventh Round"
        default: return "Round \(round)"
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "list.number")
                .font(.system(size: 52))
                .foregroundStyle(Color.textTertiary)

            Text("No Draft Picks Available")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.textPrimary)

            Text("Draft picks will be generated when the season begins.")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data Loading

    private func loadData() {
        let pickDesc = FetchDescriptor<DraftPick>(
            predicate: #Predicate { $0.seasonYear == 0 || $0.seasonYear >= 0 },
            sortBy: [SortDescriptor(\.pickNumber)]
        )
        draftPicks = (try? modelContext.fetch(pickDesc)) ?? []

        // Filter to current season's picks if we have season info
        let currentYear = career.currentSeason
        let seasonPicks = draftPicks.filter { $0.seasonYear == currentYear }
        if !seasonPicks.isEmpty {
            draftPicks = seasonPicks
        }

        let teamDesc = FetchDescriptor<Team>()
        teams = (try? modelContext.fetch(teamDesc)) ?? []
    }
}
