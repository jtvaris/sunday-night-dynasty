import SwiftUI

/// Aikajananäkymä: active + converted FA visits, sorted by start time.
/// Highlights the user's own visits with a gold "YOUR VISIT" tag.
struct VisitTimelineView: View {
    let visits: [FAVisit]
    let playerNames: [UUID: String]      // playerID → display name
    let teamAbbrevs: [UUID: String]      // teamID → abbreviation
    let userTeamID: UUID?
    let currentDay: Int

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            SectionHeaderText(title: "Visit Schedule")
            if filteredVisits.isEmpty {
                Text("No visits scheduled. Schedule a visit from the Bidding Room.")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DSSpacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                            .fill(Color.backgroundSecondary)
                    )
            } else {
                LazyVStack(spacing: DSSpacing.xs) {
                    ForEach(filteredVisits, id: \.id) { visit in
                        visitRow(visit)
                    }
                }
            }
        }
    }

    private var filteredVisits: [FAVisit] {
        visits
            .filter { $0.status == .active || $0.status == .converted }
            .sorted { $0.startedAt < $1.startedAt }
    }

    private func visitRow(_ visit: FAVisit) -> some View {
        HStack(spacing: DSSpacing.sm) {
            statusDot(visit.status)
            VStack(alignment: .leading, spacing: 2) {
                Text(playerNames[visit.playerID] ?? "Unknown")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text("\(teamAbbrevs[visit.teamID] ?? "—") \u{00B7} \(timeUntil(visit.expiresAt))")
                    .font(.caption2)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            if visit.teamID == userTeamID {
                Text("YOUR VISIT")
                    .font(.caption2.weight(.heavy))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.draftStealGold.opacity(0.2))
                    .foregroundStyle(Color.draftStealGold)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            } else if visit.status == .converted {
                Text("SIGNED")
                    .font(.caption2.weight(.heavy))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.success.opacity(0.2))
                    .foregroundStyle(Color.success)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
        }
        .padding(DSSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                .fill(Color.backgroundTertiary)
        )
    }

    private func statusDot(_ status: FAVisitStatus) -> some View {
        Circle()
            .fill(statusColor(status))
            .frame(width: 8, height: 8)
    }

    private func statusColor(_ status: FAVisitStatus) -> Color {
        switch status {
        case .active:    return .draftStealGold
        case .converted: return .success
        case .expired:   return .textTertiary
        case .cancelled: return .danger
        }
    }

    private func timeUntil(_ date: Date) -> String {
        let interval = date.timeIntervalSinceNow
        if interval <= 0 { return "EXPIRED" }
        let hours = Int(interval) / 3600
        if hours <= 0 {
            let minutes = max(1, Int(interval) / 60)
            return "\(minutes)m remaining"
        }
        return "\(hours)h remaining"
    }
}
