import SwiftUI

/// A single completed draft pick row shown in the draft board scroll view.
struct DraftPickCard: View {

    let pick: DraftPick
    let isPlayerTeam: Bool

    var body: some View {
        HStack(spacing: 12) {

            // MARK: Pick Number Circle
            ZStack {
                Circle()
                    .fill(isPlayerTeam ? Color.accentGold : Color.backgroundTertiary)
                    .frame(width: 40, height: 40)
                Text("\(pick.pickNumber)")
                    .font(.system(size: 13, weight: .heavy).monospacedDigit())
                    .foregroundStyle(isPlayerTeam ? Color.backgroundPrimary : Color.textSecondary)
            }

            // MARK: Round Badge
            Text("R\(pick.round)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.textTertiary)
                .frame(width: 24)

            // MARK: Team Abbreviation
            Text(pick.teamAbbreviation ?? "???")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(isPlayerTeam ? Color.accentGold : Color.textPrimary)
                .frame(width: 38, alignment: .leading)

            // MARK: Player Info
            VStack(alignment: .leading, spacing: 2) {
                Text(pick.playerName ?? "—")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)

                if let pos = pick.playerPosition, let college = pick.playerCollege {
                    HStack(spacing: 6) {
                        Text(pos)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.textPrimary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(positionColor(pos), in: RoundedRectangle(cornerRadius: 3))

                        Text(college)
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            // MARK: Scout Grade Badge
            if let grade = pick.scoutGrade {
                Text(grade)
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(gradeColor(grade))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(gradeColor(grade).opacity(0.15))
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isPlayerTeam ? Color.accentGold.opacity(0.08) : Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            isPlayerTeam ? Color.accentGold.opacity(0.5) : Color.surfaceBorder,
                            lineWidth: isPlayerTeam ? 1.5 : 1
                        )
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Helpers

    private func positionColor(_ pos: String) -> Color {
        let offensePositions = ["QB","RB","FB","WR","TE","LT","LG","C","RG","RT"]
        let defensePositions = ["DE","DT","OLB","MLB","CB","FS","SS"]
        if offensePositions.contains(pos) { return .accentBlue }
        if defensePositions.contains(pos) { return .danger }
        return .accentGold
    }

    private func gradeColor(_ grade: String) -> Color {
        switch grade {
        case "A+", "A":   return .success
        case "A-", "B+":  return .accentGold
        case "B", "B-":   return .warning
        default:          return .textSecondary
        }
    }

    private var accessibilityDescription: String {
        let player = pick.playerName ?? "unknown player"
        let team = pick.teamAbbreviation ?? "unknown team"
        return "Pick \(pick.pickNumber), Round \(pick.round), \(team) selects \(player)"
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 8) {
        DraftPickCard(
            pick: DraftPick(
                seasonYear: 2026, round: 1, pickNumber: 1,
                originalTeamID: UUID(), currentTeamID: UUID(),
                playerName: "Caleb Williams",
                playerPosition: "QB", playerCollege: "USC",
                scoutGrade: "A+", teamAbbreviation: "CHI"
            ),
            isPlayerTeam: true
        )
        DraftPickCard(
            pick: DraftPick(
                seasonYear: 2026, round: 1, pickNumber: 2,
                originalTeamID: UUID(), currentTeamID: UUID(),
                playerName: "Jayden Daniels",
                playerPosition: "QB", playerCollege: "LSU",
                scoutGrade: "A", teamAbbreviation: "WAS"
            ),
            isPlayerTeam: false
        )
        DraftPickCard(
            pick: DraftPick(
                seasonYear: 2026, round: 1, pickNumber: 3,
                originalTeamID: UUID(), currentTeamID: UUID(),
                playerName: "Marvin Harrison Jr.",
                playerPosition: "WR", playerCollege: "Ohio State",
                scoutGrade: "A+", teamAbbreviation: "NE"
            ),
            isPlayerTeam: false
        )
    }
    .padding()
    .background(Color.backgroundPrimary)
}
