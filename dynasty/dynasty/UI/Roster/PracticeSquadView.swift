import SwiftUI
import SwiftData

// MARK: - Practice Squad View
//
// The 16-man squad and the league-wide poach board (TODO §5.1).
//
// Two tabs because the mechanic has two halves and they are opposites: OUR
// squad is a thing to protect (promote a man before a rival signs him, cut one
// to make room), and THEIR squads are a thing to raid. Both actions are the
// same transaction underneath — a signing to our active 53 — which is why they
// share one action row and one confirmation.

struct PracticeSquadView: View {

    let career: Career

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var allPlayersUnscoped: [Player]
    @Query private var allTeamsUnscoped: [Team]

    @State private var tab: SquadTab = .own
    @State private var confirming: Player? = nil
    @State private var banner: String? = nil

    private enum SquadTab: String, CaseIterable, Identifiable {
        case own
        case league

        var id: String { rawValue }

        var label: String {
            switch self {
            case .own:    return "Our Squad"
            case .league: return "League Squads"
            }
        }
    }

    // MARK: - Scoped data

    // `@Query` cannot take a runtime predicate built from a stored property, so
    // the store-wide result is narrowed to THIS save here — otherwise the board
    // would list another career's practice squads.
    private var allPlayers: [Player] { allPlayersUnscoped.filter { $0.careerID == career.id } }
    private var allTeams: [Team] { allTeamsUnscoped.filter { $0.careerID == career.id } }

    private var teamsByID: [UUID: Team] {
        Dictionary(allTeams.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private var ourTeam: Team? {
        guard let teamID = career.teamID else { return nil }
        return teamsByID[teamID]
    }

    private var ourSquad: [Player] {
        guard let teamID = career.teamID else { return [] }
        return PracticeSquadEngine.squad(of: teamID, in: allPlayers)
    }

    private var leagueBoard: [Player] {
        PracticeSquadEngine.leagueSquad(excluding: career.teamID, in: allPlayers)
    }

    private var activeRosterCount: Int {
        guard let teamID = career.teamID else { return 0 }
        return PracticeSquadEngine.activeRoster(of: teamID, in: allPlayers).count
    }

    /// A signing always ends with 53 men, so the only true blocker is money —
    /// a full roster makes a corresponding move instead of refusing.
    private var canSign: Bool {
        guard let team = ourTeam else { return false }
        return career.capMode == .sandbox || team.availableCap >= PracticeSquadEngine.poachSalary
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()

                VStack(spacing: 0) {
                    summaryBar

                    Picker("Squad", selection: $tab) {
                        ForEach(SquadTab.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, DSSpacing.md)
                    .padding(.vertical, DSSpacing.xs)

                    if let banner {
                        Text(banner)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.success)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, DSSpacing.md)
                            .padding(.bottom, DSSpacing.xxs)
                    }

                    list
                }
            }
            .navigationTitle("Practice Squad")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                confirming.map { signPrompt(for: $0) } ?? "",
                isPresented: Binding(
                    get: { confirming != nil },
                    set: { if !$0 { confirming = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let player = confirming {
                    Button(isOurs(player) ? "Promote to active roster" : "Sign to active roster") {
                        sign(player)
                    }
                }
                Button("Cancel", role: .cancel) { confirming = nil }
            }
        }
    }

    // MARK: - Summary

    private var summaryBar: some View {
        HStack(spacing: DSSpacing.lg) {
            summaryStat(
                "Squad",
                "\(ourSquad.count)/\(PracticeSquadEngine.squadSize)",
                tint: ourSquad.count < PracticeSquadEngine.squadSize ? Color.warning : Color.textPrimary
            )
            summaryStat(
                "Active",
                "\(activeRosterCount)/\(PracticeSquadEngine.activeRosterCeiling)",
                tint: .textPrimary
            )
            summaryStat(
                "Signing cost",
                "$\(PracticeSquadEngine.poachSalary)K",
                tint: canSign ? Color.textSecondary : Color.danger
            )
            Spacer()
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
        .background(Color.backgroundSecondary)
    }

    private func summaryStat(_ title: String, _ value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.textSecondary)
            Text(value)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(tint)
        }
    }

    // MARK: - List

    @ViewBuilder
    private var list: some View {
        let rows = tab == .own ? ourSquad : leagueBoard
        if rows.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: DSSpacing.xs) {
                    if tab == .league {
                        Text("Any club may sign another club's practice-squad player straight to its 53. There is no compensation and the losing club cannot refuse.")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, DSSpacing.xxs)
                    }
                    ForEach(rows, id: \.id) { player in
                        row(player)
                    }
                }
                .padding(DSSpacing.md)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: DSSpacing.sm) {
            Image(systemName: "person.3.sequence.fill")
                .font(.system(size: 34))
                .foregroundStyle(Color.textSecondary.opacity(0.5))
            Text(tab == .own
                 ? "No practice squad yet. Squads are stocked on cutdown day, at the end of the preseason."
                 : "No other club is carrying a practice squad right now.")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DSSpacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(_ player: Player) -> some View {
        HStack(spacing: DSSpacing.sm) {
            Text(player.position.rawValue)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 38, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(player.fullName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text(subtitle(for: player))
                    .font(.caption2)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: DSSpacing.xs)

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(player.overall)")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(Color.textPrimary)
                Text("POT \(player.assessedPotential ?? "—")")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textSecondary)
            }

            Button {
                confirming = player
            } label: {
                Text(isOurs(player) ? "Promote" : "Sign")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, DSSpacing.sm)
                    .padding(.vertical, 6)
                    .background(
                        canSign ? Color.accentGold : Color.textSecondary.opacity(0.3),
                        in: RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                    )
                    .foregroundStyle(canSign ? Color.black : Color.textSecondary)
            }
            .buttonStyle(.plain)
            .disabled(!canSign)
        }
        .padding(DSSpacing.sm)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: DSCornerRadius.card))
    }

    private func subtitle(for player: Player) -> String {
        var parts: [String] = ["\(player.age) yrs", "\(player.yearsPro) yr pro"]
        if !isOurs(player), let clubID = player.practiceSquadTeamID,
           let club = teamsByID[clubID] {
            parts.insert(club.abbreviation, at: 0)
        }
        if player.isInjured { parts.append("injured") }
        return parts.joined(separator: " · ")
    }

    private func isOurs(_ player: Player) -> Bool {
        player.practiceSquadTeamID == career.teamID
    }

    private func signPrompt(for player: Player) -> String {
        isOurs(player)
            ? "Promote \(player.fullName) to the active roster?"
            : "Sign \(player.fullName) off \(teamsByID[player.practiceSquadTeamID ?? UUID()]?.abbreviation ?? "their")'s practice squad?"
    }

    // MARK: - Actions

    private func sign(_ player: Player) {
        defer { confirming = nil }
        guard let team = ourTeam else { return }
        let wasOurs = isOurs(player)
        let name = player.fullName

        guard PracticeSquadEngine.signToActiveRoster(
            player,
            to: team,
            allPlayers: allPlayers,
            capMode: career.capMode,
            // In-season corresponding move — priced on the game checks still to
            // come, same rule as every other release screen (#26 / #68).
            leagueYearRemaining: CapManagementEngine.leagueYearRemaining(
                phase: career.currentPhase,
                week: career.currentWeek
            )
        ) else {
            banner = "No room — free up cap space first."
            return
        }
        try? modelContext.save()
        banner = wasOurs
            ? "\(name) promoted to the active roster."
            : "\(name) signed to the active roster."
    }
}
