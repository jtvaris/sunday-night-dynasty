import SwiftUI

/// R24 — War Room 2.0.
///
/// Player-facing draft intelligence built ONLY from scouted/public data:
/// - Pick status: your last pick + next turn indicator.
/// - Best Available: top-10 remaining by YOUR scout grade with a team-needs
///   filter, stock-trend arrows, and a SLEEPER tag when your scouts like a
///   prospect clearly more than the public consensus. The hidden true OVR is
///   never read here.
/// - Draft capital (Jimmy Johnson points) and a live trade radar.
struct WarRoomPanel: View {
    @ObservedObject var coordinator: DraftDayCoordinator
    @State private var needsOnly = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                pickStatusCard
                bestAvailableCard
                pickValueCard
                scoutChatterCard
                tradeRadarCard
            }
            .padding(DSSpacing.md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.backgroundSecondary)
    }

    // MARK: - Pick status (last pick + next turn)

    private var pickStatusCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            SectionHeaderText(title: "Your Picks")
            if coordinator.isUserOnClock {
                Label("YOU'RE ON THE CLOCK", systemImage: "timer")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(Color.draftClockUrgent)
            } else if let next = nextUserPick() {
                let away = coordinator.picksUntilUserPick
                HStack {
                    Text("Next: R\(next.round) · #\(next.pickNumber)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Text(away == 1 ? "1 pick away" : "\(away) picks away")
                        .font(.caption.monospaced())
                        .foregroundStyle(away <= 3 ? Color.accentGold : Color.textSecondary)
                }
            } else {
                Text("No picks remaining")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            }
            if let last = lastUserPick {
                HStack(spacing: 4) {
                    Text("Last: #\(last.pickNumber)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(Color.textSecondary)
                    Text("\(last.position.rawValue) \(last.playerName)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text(last.grade.rawValue)
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(Color.accentGold)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.sm)
        .cardBackground()
    }

    private var lastUserPick: PickResult? {
        coordinator.allPickResults.last { $0.isUserPick || $0.ownerOverride }
    }

    // MARK: - Best available (scouted data only)

    private var bestAvailableCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack {
                SectionHeaderText(title: "Best Available")
                Spacer()
                Button {
                    needsOnly.toggle()
                } label: {
                    Text("NEEDS")
                        .font(.caption2.weight(.heavy))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(needsOnly ? Color.draftStealGold.opacity(0.3) : Color.backgroundTertiary)
                        .foregroundStyle(needsOnly ? Color.draftStealGold : Color.textSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            }
            let rows = bestAvailable
            if rows.isEmpty {
                Text(needsOnly ? "No graded prospects left at need positions." : "No graded prospects remaining.")
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
            }
            ForEach(rows, id: \.id) { prospect in
                bestAvailableRow(prospect)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.sm)
        .cardBackground()
    }

    /// Remaining prospects ranked by the user's scout grade (midpoint of the
    /// scouted grade range). Unscouted prospects sink to the bottom and never
    /// reveal anything they shouldn't.
    private var scoutRankedProspects: [CollegeProspect] {
        coordinator.availableProspects.sorted { a, b in
            let gradeA = a.effectiveOverallGrade?.midGrade.rank ?? 0
            let gradeB = b.effectiveOverallGrade?.midGrade.rank ?? 0
            if gradeA != gradeB { return gradeA > gradeB }
            return (coordinator.publicBoardRanks[a.id] ?? 999) <
                   (coordinator.publicBoardRanks[b.id] ?? 999)
        }
    }

    private var bestAvailable: [CollegeProspect] {
        let ranked = scoutRankedProspects
        let filtered = needsOnly
            ? ranked.filter { (coordinator.teamNeedScores[$0.position] ?? 0) >= 0.5 }
            : ranked
        return Array(filtered.prefix(10))
    }

    /// SLEEPER: your scouts grade the prospect clearly higher than the public
    /// consensus AND his stock is rising. Both signals are scouted/public —
    /// the hidden OVR never leaks.
    private func isSleeper(_ prospect: CollegeProspect, scoutRank: Int) -> Bool {
        guard let grade = prospect.effectiveOverallGrade,
              grade.midGrade.rank >= LetterGrade.bMinus.rank,
              prospect.stockTrajectory == .rising,
              let publicRank = coordinator.publicBoardRanks[prospect.id] else { return false }
        return publicRank - scoutRank >= 12
    }

    private func bestAvailableRow(_ prospect: CollegeProspect) -> some View {
        let scoutRank = (scoutRankedProspects.firstIndex { $0.id == prospect.id } ?? 998) + 1
        let need = coordinator.teamNeedScores[prospect.position] ?? 0
        let trend = prospect.stockTrajectory

        return HStack(spacing: DSSpacing.xs) {
            Text(prospect.overallGradeDisplay)
                .font(.caption2.monospaced().weight(.heavy))
                .foregroundStyle(Color.accentGold)
                .frame(width: 44, alignment: .leading)
            Text(prospect.position.rawValue)
                .font(.caption2.weight(.bold))
                .foregroundStyle(need >= 0.7 ? Color.draftStealGold : Color.textSecondary)
                .frame(width: 28, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(prospect.firstName.prefix(1)). \(prospect.lastName)")
                    .font(.caption)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                if isSleeper(prospect, scoutRank: scoutRank) {
                    Text("SLEEPER")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(Color.success)
                }
            }
            Spacer()
            if trend == .rising || trend == .falling {
                Image(systemName: trend.icon)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(trend.color)
            }
            if let publicRank = coordinator.publicBoardRanks[prospect.id] {
                Text("BB \(publicRank)")
                    .font(.system(size: 9).monospaced())
                    .foregroundStyle(Color.textTertiary)
                    .frame(width: 44, alignment: .trailing)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Draft capital

    private var pickValueCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            SectionHeaderText(title: "Your Draft Capital")
            ForEach(userRemainingPicks, id: \.id) { pick in
                HStack {
                    Text("Rd \(pick.round) · #\(pick.pickNumber)")
                        .font(.caption.monospaced())
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Text("\(PickValueChart.points(forPick: pick.pickNumber)) pts")
                        .font(.caption.monospaced().weight(.bold))
                        .foregroundStyle(Color.accentGold)
                }
            }
            Divider().overlay(Color.surfaceBorder).padding(.vertical, 2)
            HStack {
                Text("Total")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text("\(userTotalValue()) pts")
                    .font(.caption.monospaced().weight(.heavy))
                    .foregroundStyle(Color.draftStealGold)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.sm)
        .cardBackground()
    }

    // MARK: - Scout chatter

    private var scoutChatterCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            SectionHeaderText(title: "Scout Chatter")
            Text(scoutChatter)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.sm)
        .cardBackground()
    }

    private var scoutChatter: String {
        if coordinator.isUserOnClock {
            let topNeed = coordinator.teamNeedScores.max { $0.value < $1.value }?.key.rawValue ?? "depth"
            return "You're on the clock. Need: \(topNeed). Best available is sitting on the board — take the value or trade down for capital."
        }
        if let result = coordinator.lastPickResult {
            switch result.grade {
            case .stealAPlus, .hofTrack:
                return "\(result.teamAbbrev) just stole \(result.playerName) at #\(result.pickNumber). The board is shifting."
            case .reach, .bigReach:
                return "\(result.teamAbbrev) reached on \(result.playerName) at #\(result.pickNumber). Better names still on the board."
            default:
                return "\(result.teamAbbrev) goes \(result.position.rawValue) with \(result.playerName) at #\(result.pickNumber)."
            }
        }
        let picksAway = coordinator.picksUntilUserPick
        if picksAway > 0 && picksAway <= 3 {
            return "Get ready — your pick comes up in \(picksAway). Targets you've starred should still be on the board."
        }
        return "Scout team is monitoring AI selections — flag anything unusual."
    }

    // MARK: - Trade radar (live since R24)

    private var tradeRadarCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            SectionHeaderText(title: "Trade Radar")
            if let offer = coordinator.pendingPickOffer {
                Label("\(offer.partnerAbbreviation) offer on the table", systemImage: "phone.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.draftStealGold)
                Text(offer.motive)
                    .font(.caption2)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                let partners = radarPartners
                if partners.isEmpty {
                    Text("Phones are quiet. Interest picks up when top prospects slide toward your pick.")
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(partners, id: \.self) { line in
                        Label(line, systemImage: "dot.radiowaves.left.and.right")
                            .font(.caption2)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.sm)
        .cardBackground()
    }

    /// Up to two teams picking soon after the user whose top needs match the
    /// top of the public board — likely trade-down partners.
    private var radarPartners: [String] {
        guard let next = nextUserPick() else { return [] }
        let topBoardPositions: [Position] = coordinator.availableProspects
            .sorted { (coordinator.publicBoardRanks[$0.id] ?? 999) < (coordinator.publicBoardRanks[$1.id] ?? 999) }
            .prefix(8)
            .map(\.position)

        var seen = Set<UUID>()
        var lines: [String] = []
        for pick in coordinator.picks.dropFirst(coordinator.currentPickIndex) where !pick.isComplete {
            guard lines.count < 2 else { break }
            guard pick.currentTeamID != coordinator.userTeamID,
                  pick.pickNumber > next.pickNumber,
                  pick.pickNumber <= next.pickNumber + 18,
                  !seen.contains(pick.currentTeamID) else { continue }
            seen.insert(pick.currentTeamID)
            guard seen.count <= 6 else { break }   // cap the roster-need scans
            let roster = coordinator.rosters[pick.currentTeamID] ?? []
            let needs = DraftEngine.topTeamNeeds(roster: roster, limit: 3)
            guard let match = topBoardPositions.first(where: { needs.contains($0) }),
                  let team = coordinator.teamsByID[pick.currentTeamID] else { continue }
            lines.append("\(team.abbreviation) (#\(pick.pickNumber)) eyeing \(match.rawValue) — possible partner")
        }
        return lines
    }

    // MARK: - Helpers

    private var userRemainingPicks: [DraftPick] {
        guard let teamID = coordinator.userTeamID else { return [] }
        return coordinator.picks
            .dropFirst(coordinator.currentPickIndex)
            .filter { $0.currentTeamID == teamID }
            .map { $0 }
    }

    private func nextUserPick() -> DraftPick? {
        guard let teamID = coordinator.userTeamID else { return nil }
        return coordinator.picks
            .dropFirst(coordinator.currentPickIndex)
            .first { $0.currentTeamID == teamID }
    }

    private func userTotalValue() -> Int {
        guard let teamID = coordinator.userTeamID else { return 0 }
        return coordinator.picks
            .dropFirst(coordinator.currentPickIndex)
            .filter { $0.currentTeamID == teamID }
            .reduce(0) { $0 + PickValueChart.points(forPick: $1.pickNumber) }
    }
}
