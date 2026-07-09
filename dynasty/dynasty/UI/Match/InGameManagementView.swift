import SwiftUI

// MARK: - In-Game Management View

/// Football Manager -style mid-game squad sheet for the PLAYER's team:
/// live stats, fatigue, matchup record, and form for every man on the field,
/// with bench substitutions that land at the next whistle. Presented from
/// ``CoachedGameView``'s situation strip ("Manage").
///
/// Substitutions are queued in ``LiveGameEngine`` (`substitute`) and applied
/// at the next dead ball; until then the row shows a pending chip. The AI
/// opponent is never shown and never substitutes.
struct InGameManagementView: View {

    @ObservedObject var engine: LiveGameEngine
    /// The coached team's abbreviation, for the header.
    let teamAbbr: String
    /// True while a play animation is running — substitutions are locked.
    let subsDisabled: Bool

    @Environment(\.dismiss) private var dismiss

    /// Offense/Defense unit toggle.
    @State private var showingOffense = true
    /// Field player whose bench candidates are expanded inline.
    @State private var expandedPlayerID: UUID?
    /// Candidate swap awaiting the coach's confirmation.
    @State private var pendingConfirm: SubCandidate?

    /// A tapped bench candidate paired with the man he would replace.
    struct SubCandidate: Identifiable {
        var id: UUID { benchPlayer.id }
        let benchPlayer: SimPlayer
        let fieldPlayer: SimPlayer
    }

    // MARK: Body

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 14) {
                    header
                    unitPicker
                    if !engine.pendingSubstitutions.isEmpty { pendingCard }
                    if subsDisabled && !engine.isGameOver { playLiveNote }
                    unitSections
                }
                .padding(16)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
        }
        .overlay(alignment: .topTrailing) { closeButton }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .confirmationDialog(
            "Substitution",
            isPresented: Binding(
                get: { pendingConfirm != nil },
                set: { if !$0 { pendingConfirm = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingConfirm
        ) { candidate in
            Button("Sub \(candidate.benchPlayer.shortName) in for \(candidate.fieldPlayer.shortName)") {
                if engine.substitute(
                    benchPlayerID: candidate.benchPlayer.id,
                    forFieldPlayerID: candidate.fieldPlayer.id
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) { expandedPlayerID = nil }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The swap happens at the next whistle.")
        }
    }

    // MARK: Header & Chrome

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.accentGold)
            Text("SQUAD MANAGEMENT · \(teamAbbr)")
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(Color.textSecondary)
                .tracking(1.6)
            Spacer()
        }
        .padding(.top, 6)
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 30, height: 30)
                .background(Color.backgroundTertiary, in: Circle())
        }
        .buttonStyle(.plain)
        .padding(14)
    }

    private var unitPicker: some View {
        HStack(spacing: 6) {
            unitTab("Offense", isOn: showingOffense) { showingOffense = true }
            unitTab("Defense", isOn: !showingOffense) { showingOffense = false }
        }
    }

    private func unitTab(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { action() }
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isOn ? Color.backgroundPrimary : Color.textSecondary)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(isOn ? Color.accentGold : Color.backgroundTertiary, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Queued swaps waiting for the whistle, each cancellable.
    private var pendingCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("PENDING · AT NEXT WHISTLE", icon: "clock.fill", tint: .warning)
            ForEach(engine.pendingSubstitutions) { sub in
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.warning)
                    Text("\(sub.benchName) in for \(sub.fieldName)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        engine.cancelSubstitution(sub.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.warning.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(Color.warning.opacity(0.35), lineWidth: 1)
                )
            }
        }
        .padding(16)
        .cardBackground()
    }

    /// Shown while a play is being animated — no subs until the whistle.
    private var playLiveNote: some View {
        HStack(spacing: 8) {
            ProgressView()
                .tint(Color.accentGold)
                .scaleEffect(0.7)
            Text("Play is live — substitutions unlock at the whistle.")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.backgroundTertiary.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Unit Sections

    private var currentUnit: FieldUnit {
        showingOffense ? engine.playerOffenseUnit : engine.playerDefenseUnit
    }

    /// Natural section order per unit; stray groups (emergency fallback
    /// picks) are appended so nobody on the field is ever hidden.
    private var groupOrder: [LineupGroup] {
        showingOffense
            ? [.quarterbacks, .backfield, .receivers, .tightEnds, .offensiveLine]
            : [.defensiveLine, .linebackers, .secondary]
    }

    @ViewBuilder
    private var unitSections: some View {
        let unit = currentUnit
        let ordered = groupOrder + LineupGroup.allCases.filter { !groupOrder.contains($0) }
        ForEach(ordered) { group in
            let members = unit.players.filter { LineupGroup(of: $0.position) == group }
            if !members.isEmpty {
                groupCard(group: group, members: members)
            }
        }
    }

    private func groupCard(group: LineupGroup, members: [SimPlayer]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(group.sectionTitle, icon: showingOffense ? "figure.american.football" : "shield.fill",
                         tint: .accentGold)
            VStack(spacing: 4) {
                ForEach(members, id: \.id) { player in
                    fieldPlayerRow(player)
                    if expandedPlayerID == player.id {
                        benchList(for: player)
                    }
                }
            }
        }
        .padding(14)
        .cardBackground()
    }

    // MARK: Field Player Row

    private func fieldPlayerRow(_ player: SimPlayer) -> some View {
        let line = engine.liveLine(for: player.id)
        let pending = engine.pendingSubstitutions.first { $0.fieldPlayerID == player.id }
        let isExpanded = expandedPlayerID == player.id
        return Button {
            guard !subsDisabled, !engine.isGameOver else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                expandedPlayerID = isExpanded ? nil : player.id
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("#\(player.displayNumber)")
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                        .foregroundStyle(Color.textTertiary)
                        .frame(width: 32, alignment: .leading)
                    Text(player.shortName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    positionTag(player.position.rawValue)
                    Spacer(minLength: 6)
                    if let line {
                        formArrow(morale: line.morale, fatigue: line.fatigue)
                        matchupTag(wins: line.matchupWins, losses: line.matchupLosses)
                        fatigueBar(line.fatigue)
                    }
                    Text("\(player.overall)")
                        .font(.system(size: 13, weight: .black).monospacedDigit())
                        .foregroundStyle(Color.textPrimary)
                        .frame(width: 28, alignment: .trailing)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(subsDisabled ? Color.textTertiary.opacity(0.35) : Color.textTertiary)
                }
                HStack(spacing: 8) {
                    Text(statLineText(line))
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if let pending {
                        pendingChip("Sub at next whistle: \(pending.benchName) in")
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 40)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                isExpanded ? Color.backgroundTertiary.opacity(0.55) : Color.clear,
                in: RoundedRectangle(cornerRadius: 9)
            )
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }

    private func statLineText(_ line: LiveGameEngine.LivePlayerLine?) -> String {
        guard let line, !line.statLine.isEmpty else { return "No stats yet" }
        return line.statLine
    }

    // MARK: Bench Candidates

    @ViewBuilder
    private func benchList(for fieldPlayer: SimPlayer) -> some View {
        let group = LineupGroup(of: fieldPlayer.position)
        let candidates = engine.benchPlayers(forHome: engine.playerTeamIsHome, position: group)
        VStack(spacing: 4) {
            if candidates.isEmpty {
                Text("No healthy substitutes in this group.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 16)
                    .padding(.vertical, 4)
            } else {
                ForEach(candidates, id: \.id) { candidate in
                    benchCandidateRow(candidate, fieldPlayer: fieldPlayer)
                }
            }
        }
        .padding(.leading, 28)
        .transition(.opacity)
    }

    private func benchCandidateRow(_ candidate: SimPlayer, fieldPlayer: SimPlayer) -> some View {
        let line = engine.liveLine(for: candidate.id)
        return Button {
            guard !subsDisabled else { return }
            pendingConfirm = SubCandidate(benchPlayer: candidate, fieldPlayer: fieldPlayer)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(subsDisabled ? Color.textTertiary : Color.success)
                Text("#\(candidate.displayNumber)")
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color.textTertiary)
                    .frame(width: 32, alignment: .leading)
                Text(candidate.shortName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                positionTag(candidate.position.rawValue)
                Spacer(minLength: 6)
                if let line { fatigueBar(line.fatigue) }
                Text("\(candidate.overall)")
                    .font(.system(size: 12, weight: .black).monospacedDigit())
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 28, alignment: .trailing)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.backgroundTertiary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(subsDisabled)
    }

    // MARK: Bits

    /// Fatigue meter, 0 (fresh) to 100 (gassed): green under 40, amber to 69,
    /// red from 70 up — the same line the auto-rotation reacts to.
    private func fatigueBar(_ fatigue: Int) -> some View {
        let fraction = min(1.0, max(0.0, Double(fatigue) / 100.0))
        let color: Color = fatigue >= 70 ? .danger : (fatigue >= 40 ? .warning : .success)
        return ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.backgroundTertiary)
                .frame(width: 52, height: 5)
            Capsule()
                .fill(color)
                .frame(width: max(3, 52 * fraction), height: 5)
        }
    }

    /// Form arrow from the morale + freshness composite: up = flying,
    /// down = struggling, flat otherwise.
    private func formArrow(morale: Int, fatigue: Int) -> some View {
        let composite = (morale + (100 - fatigue)) / 2
        let symbol: String
        let tint: Color
        if composite >= 65 {
            symbol = "arrow.up.right"; tint = .success
        } else if composite <= 45 {
            symbol = "arrow.down.right"; tint = .danger
        } else {
            symbol = "arrow.right"; tint = .textSecondary
        }
        return Image(systemName: symbol)
            .font(.system(size: 11, weight: .black))
            .foregroundStyle(tint)
    }

    /// Individual matchup record this game, e.g. "3-1".
    private func matchupTag(wins: Int, losses: Int) -> some View {
        Text("\(wins)-\(losses)")
            .font(.system(size: 11, weight: .bold).monospacedDigit())
            .foregroundStyle(wins + losses == 0 ? Color.textTertiary
                             : (wins >= losses ? Color.success : Color.danger))
            .frame(width: 30)
    }

    private func positionTag(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .black))
            .foregroundStyle(Color.textTertiary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.backgroundTertiary, in: Capsule())
    }

    private func pendingChip(_ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "clock.fill")
                .font(.system(size: 8, weight: .bold))
            Text(text)
                .font(.system(size: 10, weight: .bold))
                .lineLimit(1)
        }
        .foregroundStyle(Color.warning)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.warning.opacity(0.14), in: Capsule())
    }

    private func sectionTitle(_ text: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(Color.textTertiary)
                .tracking(1.5)
        }
    }
}
