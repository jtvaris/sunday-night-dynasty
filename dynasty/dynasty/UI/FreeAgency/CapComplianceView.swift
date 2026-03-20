import SwiftUI
import SwiftData

struct CapComplianceView: View {

    let career: Career

    @Environment(\.modelContext) private var modelContext

    @State private var team: Team?
    @State private var players: [Player] = []
    @State private var showCutConfirm: Player?
    @State private var showRestructureConfirm: Player?

    private var isOverCap: Bool {
        guard let team else { return false }
        return team.currentCapUsage > team.salaryCap
    }

    private var capOverage: Int {
        guard let team else { return 0 }
        return max(0, team.currentCapUsage - team.salaryCap)
    }

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            if let team {
                ScrollView {
                    VStack(spacing: 24) {
                        capStatusCard(team: team)
                        rosterListCard(team: team)
                        enterFAButton
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity)
                }
            } else {
                ProgressView()
                    .tint(Color.accentGold)
            }
        }
        .navigationTitle("Roster & Cap Review")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { loadData() }
        .alert("Cut Player?", isPresented: .init(
            get: { showCutConfirm != nil },
            set: { if !$0 { showCutConfirm = nil } }
        )) {
            if let player = showCutConfirm {
                Button("Cut \(player.fullName)", role: .destructive) {
                    cutPlayer(player)
                }
                Button("Cancel", role: .cancel) {}
            }
        } message: {
            if let player = showCutConfirm {
                let savings = player.annualSalary
                Text("Release \(player.fullName) to save \(formatMillions(savings)) in cap space.")
            }
        }
        .alert("Restructure Contract?", isPresented: .init(
            get: { showRestructureConfirm != nil },
            set: { if !$0 { showRestructureConfirm = nil } }
        )) {
            if let player = showRestructureConfirm {
                Button("Restructure") {
                    restructurePlayer(player)
                }
                Button("Cancel", role: .cancel) {}
            }
        } message: {
            if let player = showRestructureConfirm {
                let savings = Int(Double(player.annualSalary) * 0.5)
                Text("Convert \(formatMillions(savings)) of \(player.fullName)'s salary to bonus, saving cap space this year but spreading it to future years.")
            }
        }
    }

    // MARK: - Cap Status Card

    private func capStatusCard(team: Team) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: isOverCap ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(isOverCap ? Color.danger : Color.success)
                    .font(.system(size: 15))
                Text(isOverCap ? "OVER THE CAP" : "Under the Cap")
                    .font(.headline)
                    .foregroundStyle(isOverCap ? Color.danger : Color.success)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider().overlay(Color.surfaceBorder)

            VStack(spacing: 12) {
                // Cap bar
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Cap Usage")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        let pct = team.salaryCap > 0 ? Double(team.currentCapUsage) / Double(team.salaryCap) : 0
                        Text(String(format: "%.1f%%", pct * 100))
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(isOverCap ? Color.danger : Color.success)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.backgroundTertiary)
                                .frame(height: 10)
                            let pct = team.salaryCap > 0 ? Double(team.currentCapUsage) / Double(team.salaryCap) : 0
                            RoundedRectangle(cornerRadius: 5)
                                .fill(isOverCap ? Color.danger : Color.success)
                                .frame(width: geo.size.width * min(pct, 1.0), height: 10)
                        }
                    }
                    .frame(height: 10)
                }

                // Stats
                HStack(spacing: 0) {
                    capStat(label: "Salary Cap", value: formatMillions(team.salaryCap), color: .accentGold)
                    capStat(label: "Used", value: formatMillions(team.currentCapUsage), color: isOverCap ? .danger : .textPrimary)
                    capStat(label: "Available", value: formatMillions(team.availableCap), color: team.availableCap >= 0 ? .success : .danger)
                }

                if isOverCap {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.octagon.fill")
                            .foregroundStyle(Color.danger)
                        Text("You must cut or restructure players to get \(formatMillions(capOverage)) under the cap before entering free agency.")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .background(Color.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.danger.opacity(0.4), lineWidth: 1))
                }
            }
            .padding(16)
        }
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isOverCap ? Color.danger.opacity(0.5) : Color.surfaceBorder, lineWidth: isOverCap ? 2 : 1)
        )
    }

    private func capStat(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .bold).monospacedDigit())
                .foregroundStyle(color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Roster List

    private func rosterListCard(team: Team) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "person.3.fill")
                    .foregroundStyle(Color.accentGold)
                    .font(.system(size: 15))
                Text("Roster — Sorted by Salary")
                    .font(.headline)
                    .foregroundStyle(Color.accentGold)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider().overlay(Color.surfaceBorder)

            // Column headers
            HStack {
                Text("Player")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("OVR")
                    .frame(width: 40)
                Text("Age")
                    .frame(width: 36)
                Text("Salary")
                    .frame(width: 60)
                Text("Actions")
                    .frame(width: 110)
            }
            .font(.caption2.weight(.bold))
            .foregroundStyle(Color.textTertiary)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)

            Divider().overlay(Color.surfaceBorder)

            ForEach(Array(players.enumerated()), id: \.element.id) { index, player in
                playerRow(player: player)

                if index < players.count - 1 {
                    Divider()
                        .overlay(Color.surfaceBorder.opacity(0.5))
                        .padding(.horizontal, 8)
                }
            }
        }
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.surfaceBorder, lineWidth: 1))
    }

    private func playerRow(player: Player) -> some View {
        HStack {
            // Name + position
            HStack(spacing: 6) {
                Text(player.position.rawValue)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                    .frame(width: 26)
                    .padding(.vertical, 2)
                    .background(positionSideColor(player.position), in: RoundedRectangle(cornerRadius: 3))
                Text(player.fullName)
                    .font(.caption)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(player.overall)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.forRating(player.overall))
                .frame(width: 40)

            Text("\(player.age)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Color.textSecondary)
                .frame(width: 36)

            Text(formatMillions(player.annualSalary))
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.textPrimary)
                .frame(width: 60)

            // Actions
            HStack(spacing: 6) {
                Button {
                    showCutConfirm = player
                } label: {
                    Text("Cut")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.danger)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)

                if career.capMode == .realistic {
                    Button {
                        showRestructureConfirm = player
                    } label: {
                        Text("Restruct.")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.accentGold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.accentGold.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 110)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Enter FA Button

    private var enterFAButton: some View {
        VStack(spacing: 8) {
            Button {
                career.freeAgencyStep = FreeAgencyStep.signing.rawValue
                career.freeAgencyRound = 1
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "person.badge.plus")
                        .font(.title3)
                    Text("Enter Free Agency")
                        .font(.headline)
                }
                .foregroundStyle(isOverCap ? Color.textTertiary : Color.backgroundPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(isOverCap ? Color.backgroundTertiary : Color.accentGold, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(isOverCap)

            if isOverCap {
                Text("Must be under the salary cap to enter free agency")
                    .font(.caption)
                    .foregroundStyle(Color.danger)
            }
        }
    }

    // MARK: - Actions

    private func cutPlayer(_ player: Player) {
        guard let team else { return }
        ContractEngine.cutPlayerSimple(player: player, team: team)
        loadData()
    }

    private func restructurePlayer(_ player: Player) {
        // Simplified restructure: halve current year salary, spread savings
        let savings = Int(Double(player.annualSalary) * 0.5)
        player.annualSalary -= savings
        team?.currentCapUsage -= savings
        loadData()
    }

    // MARK: - Helpers

    private func positionSideColor(_ position: Position) -> Color {
        switch position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }

    private func formatMillions(_ thousands: Int) -> String {
        let millions = Double(thousands) / 1000.0
        if millions >= 1.0 {
            return String(format: "$%.1fM", millions)
        } else {
            return "$\(thousands)K"
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let teamID = career.teamID else { return }

        let teamDesc = FetchDescriptor<Team>(predicate: #Predicate { $0.id == teamID })
        team = try? modelContext.fetch(teamDesc).first

        guard let fetchedTeamID = team?.id else { return }
        var playerDesc = FetchDescriptor<Player>(
            predicate: #Predicate { $0.teamID == fetchedTeamID }
        )
        playerDesc.sortBy = [SortDescriptor(\.annualSalary, order: .reverse)]
        players = (try? modelContext.fetch(playerDesc)) ?? []
    }
}
