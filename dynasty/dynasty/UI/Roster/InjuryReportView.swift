import SwiftUI
import SwiftData

/// R28: Team injury report — every current injury with rehab trajectory and
/// return estimate, pending "rush back vs. hold out" decisions, and players
/// in their post-early-return risk window. Presented as a sheet from the
/// Roster screen.
struct InjuryReportView: View {
    let players: [Player]
    let career: Career?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var headTrainer: Coach? = nil
    /// Local mirror so the list refreshes immediately after a decision.
    @State private var decisions: [ReturnDecision] = []
    @State private var confirmingRushBack: ReturnDecision? = nil

    // MARK: - Derived

    private var injuredPlayers: [Player] {
        players.filter { $0.isInjured }
            .sorted { $0.injuryWeeksRemaining < $1.injuryWeeksRemaining }
    }

    private var rushBackPlayers: [Player] {
        players.filter { !$0.isInjured && $0.rushBackWeeksRemaining > 0 }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()
                List {
                    if !decisions.isEmpty {
                        returnDecisionSection
                    }
                    currentInjuriesSection
                    if !rushBackPlayers.isEmpty {
                        elevatedRiskSection
                    }
                    medicalStaffFooter
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Injury Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Rush \(confirmingRushBack?.playerName ?? "player") back?",
                isPresented: Binding(
                    get: { confirmingRushBack != nil },
                    set: { if !$0 { confirmingRushBack = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Rush back — play this week", role: .destructive) {
                    if let decision = confirmingRushBack {
                        rushBack(decision)
                    }
                    confirmingRushBack = nil
                }
                Button("Cancel", role: .cancel) { confirmingRushBack = nil }
            } message: {
                Text("He returns immediately, but carries elevated re-injury risk and a conditioning dip for the next 2 weeks.")
            }
        }
        .task {
            // Drop decisions whose player has already healed or left the team
            // (e.g. recovered during playoff weeks), persisting the cleanup.
            let stored = career?.pendingReturnDecisions ?? []
            decisions = stored.filter { decision in
                players.contains { $0.id == decision.playerID && $0.isInjured }
            }
            if decisions.count != stored.count, let career {
                career.pendingReturnDecisions = decisions
                try? modelContext.save()
            }
            if let teamID = career?.teamID {
                let descriptor = FetchDescriptor<Coach>(
                    predicate: #Predicate { $0.teamID == teamID }
                )
                let coaches = (try? modelContext.fetch(descriptor)) ?? []
                headTrainer = coaches.first { $0.role == .headTrainer }
            }
        }
    }

    // MARK: - Return Decisions

    private var returnDecisionSection: some View {
        Section {
            ForEach(decisions) { decision in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .foregroundStyle(Color.accentGold)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(decision.playerName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.textPrimary)
                            Text("\(decision.injuryTypeRaw) — 1 week from full clearance")
                                .font(.caption2)
                                .foregroundStyle(Color.textTertiary)
                        }
                        Spacer()
                    }
                    HStack(spacing: 10) {
                        Button {
                            confirmingRushBack = decision
                        } label: {
                            Label("Rush Back", systemImage: "hare.fill")
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .foregroundStyle(Color.backgroundPrimary)
                                .background(Color.warning, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Returns this week with elevated re-injury risk")

                        Button {
                            holdOut(decision)
                        } label: {
                            Label("Hold Out (Safe)", systemImage: "shield.fill")
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .foregroundStyle(Color.textPrimary)
                                .background(Color.backgroundTertiary, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Completes rehab normally, back next week")
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Return Decisions")
        } footer: {
            Text("Doing nothing is always safe — the player finishes rehab on the normal schedule.")
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    // MARK: - Current Injuries

    private var currentInjuriesSection: some View {
        Section("Current Injuries (\(injuredPlayers.count))") {
            if injuredPlayers.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.success)
                    Text("Fully healthy roster")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.success)
                }
            } else {
                ForEach(injuredPlayers) { player in
                    injuryRow(player)
                }
            }
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    private func injuryRow(_ player: Player) -> some View {
        let repeatCount = player.injuryType.map { player.priorInjuryCount(of: $0) } ?? 0
        return HStack(spacing: 10) {
            Text(player.position.rawValue)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 32, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(player.fullName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    if repeatCount >= 2 {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 8, weight: .bold))
                            Text("x\(repeatCount)")
                                .font(.system(size: 9, weight: .bold).monospacedDigit())
                        }
                        .foregroundStyle(Color.warning)
                        .accessibilityLabel("Recurring injury, \(repeatCount) times")
                    }
                }
                Text(player.injuryType?.rawValue ?? "Injury")
                    .font(.caption2)
                    .foregroundStyle(Color.danger)
                if let rehab = player.rehabStatus {
                    HStack(spacing: 3) {
                        Image(systemName: rehab.icon)
                            .font(.system(size: 8))
                        Text(rehab.displayName)
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(rehabColor(rehab))
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(player.injuryWeeksRemaining) wk\(player.injuryWeeksRemaining == 1 ? "" : "s")")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(Color.danger)
                Text("of \(player.injuryWeeksOriginal)")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(player.fullName), \(player.injuryType?.rawValue ?? "injured"), \(player.injuryWeeksRemaining) of \(player.injuryWeeksOriginal) weeks remaining, \(player.rehabStatus?.displayName ?? "")")
    }

    // MARK: - Elevated Risk

    private var elevatedRiskSection: some View {
        Section {
            ForEach(rushBackPlayers) { player in
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .foregroundStyle(Color.warning)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.fullName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                        Text("Returned early — elevated re-injury risk")
                            .font(.caption2)
                            .foregroundStyle(Color.warning)
                    }
                    Spacer()
                    Text("\(player.rushBackWeeksRemaining) wk\(player.rushBackWeeksRemaining == 1 ? "" : "s")")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.warning)
                }
            }
        } header: {
            Text("Elevated Risk")
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    // MARK: - Medical Staff Footer

    private var medicalStaffFooter: some View {
        Section {
            if let trainer = headTrainer {
                HStack(spacing: 8) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .foregroundStyle(Color.accentBlue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Head Trainer: \(trainer.fullName)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                        Text("Rehab quality \(trainer.playerDevelopment) — shifts weekly rehab odds toward faster, safer recoveries")
                            .font(.caption2)
                            .foregroundStyle(Color.textTertiary)
                    }
                    Spacer()
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .foregroundStyle(Color.textTertiary)
                    Text("No head trainer on staff — hire one to speed rehab and reduce setbacks.")
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                }
            }
        } header: {
            Text("Medical Staff")
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    // MARK: - Actions

    private func rushBack(_ decision: ReturnDecision) {
        guard let player = players.first(where: { $0.id == decision.playerID }) else {
            removeDecision(decision)
            return
        }
        MedicalEngine.rushBack(player: player)
        removeDecision(decision)
    }

    private func holdOut(_ decision: ReturnDecision) {
        // Safe path — normal recovery continues; just consume the decision.
        removeDecision(decision)
    }

    private func removeDecision(_ decision: ReturnDecision) {
        decisions.removeAll { $0.id == decision.id }
        if let career {
            var pending = career.pendingReturnDecisions
            pending.removeAll { $0.id == decision.id }
            career.pendingReturnDecisions = pending
        }
        try? modelContext.save()
    }

    private func rehabColor(_ status: RehabStatus) -> Color {
        switch status {
        case .aheadOfSchedule: return .success
        case .onTrack:         return .textSecondary
        case .setback:         return .warning
        }
    }
}
