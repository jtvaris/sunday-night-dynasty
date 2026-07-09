import SwiftUI
import SwiftData

struct LockerRoomView: View {

    let career: Career

    @Environment(\.modelContext) private var modelContext
    @State private var players: [Player] = []
    @State private var lockerRoomState: LockerRoomState?

    // R25: position-room chemistry, pending choice event & persisted log
    @State private var groupChemistry: [LockerRoomEngine.PositionGroupChemistry] = []
    @State private var pendingEvent: LockerRoomEvent?
    @State private var eventLog: [LockerRoomEvent] = []

    // MARK: - Computed

    private var chemistry: Int {
        lockerRoomState?.teamChemistry ?? 50
    }

    private var leaders: [Player] {
        players
            .filter {
                $0.personality.archetype == .teamLeader ||
                $0.personality.archetype == .mentor ||
                ($0.personality.archetype == .feelPlayer && $0.morale >= 75)
            }
            .sorted { $0.morale > $1.morale }
            .prefix(5)
            .map { $0 }
    }

    private var risks: [Player] {
        players
            .filter {
                ($0.personality.archetype == .dramaQueen ||
                 $0.personality.archetype == .fieryCompetitor) && $0.morale < 50
                || ($0.personality.archetype == .feelPlayer && $0.morale < 45)
            }
            .sorted { $0.morale < $1.morale }
            .prefix(5)
            .map { $0 }
    }

    private var highMorale: Int  { players.filter { LockerRoomEngine.moraleTier($0.morale) == .high }.count }
    private var medMorale: Int   { players.filter { LockerRoomEngine.moraleTier($0.morale) == .medium }.count }
    private var lowMorale: Int   { players.filter { LockerRoomEngine.moraleTier($0.morale) == .low }.count }

    // MARK: - Position Group Breakdown

    private struct PositionGroupSummary: Identifiable {
        let id: String
        let label: String
        let icon: String
        let count: Int
        let avgMorale: Int
        let lowCount: Int

        var moraleColor: Color {
            switch avgMorale {
            case 75...100: return Color.success
            case 45..<75:  return Color.warning
            default:       return Color.danger
            }
        }
    }

    private var positionGroups: [PositionGroupSummary] {
        let groups: [(id: String, label: String, icon: String, positions: Set<Position>)] = [
            ("offense_skill", "Offense - Skill", "figure.american.football", [.QB, .RB, .FB, .WR, .TE]),
            ("offense_line",  "Offensive Line",  "shield.lefthalf.filled",  [.LT, .LG, .C, .RG, .RT]),
            ("defense_front", "Defensive Front", "shield.fill",             [.DE, .DT, .OLB, .MLB]),
            ("defense_back",  "Secondary",       "eye.fill",                [.CB, .FS, .SS]),
            ("special_teams", "Special Teams",   "figure.kickboxing",       [.K, .P])
        ]

        return groups.compactMap { group in
            let groupPlayers = players.filter { group.positions.contains($0.position) }
            guard !groupPlayers.isEmpty else { return nil }
            let avg = groupPlayers.map { $0.morale }.reduce(0, +) / max(groupPlayers.count, 1)
            let low = groupPlayers.filter { LockerRoomEngine.moraleTier($0.morale) == .low }.count
            return PositionGroupSummary(
                id: group.id,
                label: group.label,
                icon: group.icon,
                count: groupPlayers.count,
                avgMorale: avg,
                lowCount: low
            )
        }
    }

    /// Top issues — surfaces the most concerning chemistry/morale problems.
    private var topIssues: [String] {
        var issues: [(String, Int)] = []

        // Issue 1: Toxic personalities with low morale (highest priority)
        let toxicLowMorale = players.filter {
            ($0.personality.archetype == .dramaQueen || $0.personality.archetype == .fieryCompetitor)
            && $0.morale < 50
        }
        if !toxicLowMorale.isEmpty {
            let names = toxicLowMorale.prefix(2).map { $0.fullName }.joined(separator: ", ")
            issues.append((
                "\(toxicLowMorale.count) toxic personalit\(toxicLowMorale.count == 1 ? "y" : "ies") frustrated (\(names))",
                100 - (toxicLowMorale.first?.morale ?? 0)
            ))
        }

        // Issue 2: Star players (top 25% by overall) with low morale
        let sortedByOverall = players.sorted { $0.overall > $1.overall }
        let starCount = max(1, players.count / 4)
        let stars = Array(sortedByOverall.prefix(starCount))
        let unhappyStars = stars.filter { $0.morale < 50 }
        if !unhappyStars.isEmpty {
            let names = unhappyStars.prefix(2).map { $0.fullName }.joined(separator: ", ")
            issues.append((
                "\(unhappyStars.count) star player\(unhappyStars.count == 1 ? "" : "s") unhappy (\(names))",
                90 - (unhappyStars.first?.morale ?? 0)
            ))
        }

        // Issue 3: Position group with widespread low morale
        let troubledGroups = positionGroups
            .filter { $0.lowCount >= 2 || ($0.count > 0 && $0.avgMorale < 50) }
            .sorted { $0.avgMorale < $1.avgMorale }
        if let worst = troubledGroups.first {
            issues.append((
                "\(worst.label) morale low (avg \(worst.avgMorale))",
                80 - worst.avgMorale
            ))
        }

        // Issue 4: Net negative leadership/toxicity
        if let state = lockerRoomState, state.toxicityScore > state.leadershipScore {
            let gap = state.toxicityScore - state.leadershipScore
            issues.append((
                "Toxicity outweighs leadership (-\(gap))",
                60 + gap
            ))
        }

        // Issue 5: Fall-through if nothing else surfaced
        if issues.isEmpty && lowMorale > 0 {
            issues.append(("\(lowMorale) player\(lowMorale == 1 ? "" : "s") with low morale", lowMorale))
        }

        return issues.sorted { $0.1 > $1.1 }.prefix(3).map { $0.0 }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    if pendingEvent != nil {
                        pendingEventCard
                    }
                    squadDynamicsLink
                    chemistryCard
                    if chemistry < 60 {
                        topIssuesCard
                    }
                    moraleDistributionCard
                    positionGroupCard
                    dynamicsCard
                    leadersCard
                    risksCard
                    eventsCard
                }
                .padding(20)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Locker Room")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { loadData() }
    }

    // MARK: - Squad Dynamics Link

    private var squadDynamicsLink: some View {
        NavigationLink(destination: SquadDynamicsView(career: career)) {
            HStack(spacing: 12) {
                Image(systemName: "person.3.sequence.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.accentBlue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Squad Dynamics")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text("Personality map, hierarchy & relationships")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
                Text("View Full Squad Dynamics")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentBlue)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .cardBackground()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pending Event Card (R25)

    /// An open locker-room situation waiting for the coach's call.
    /// Ignoring it for a week auto-applies the passive option.
    private var pendingEventCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.bubble.fill")
                    .foregroundStyle(Color.warning)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pendingEvent?.title ?? "")
                        .font(.headline)
                        .foregroundStyle(Color.textPrimary)
                    Text("Week \(pendingEvent?.week ?? 0) - needs your response")
                        .font(.caption)
                        .foregroundStyle(Color.warning)
                }
                Spacer()
            }

            Text(pendingEvent?.detail ?? "")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider().overlay(Color.surfaceBorder)

            ForEach(pendingEvent?.options ?? []) { option in
                Button {
                    resolvePendingEvent(with: option)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(option.label)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                            moraleDeltaPill(label: "Them", value: option.targetMoraleDelta)
                            moraleDeltaPill(label: "Team", value: option.teamMoraleDelta)
                        }
                        Text(option.detail)
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.backgroundTertiary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(Color.warning.opacity(0.35), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }

            Text("If you don't respond this week, the situation resolves itself.")
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.warning.opacity(0.4), lineWidth: 1)
                )
        )
    }

    private func moraleDeltaPill(label: String, value: Int) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
            Text(value > 0 ? "+\(value)" : "\(value)")
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(value > 0 ? Color.success : (value < 0 ? Color.danger : Color.textTertiary))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.backgroundPrimary.opacity(0.6)))
    }

    private func resolvePendingEvent(with option: LockerRoomEventOption) {
        guard let event = pendingEvent else { return }
        let resolved = LockerRoomEngine.resolve(event: event, option: option, players: players)
        WeekAdvancer.appendLockerRoomLog(resolved, career: career)
        career.pendingLockerRoomEvent = nil
        try? modelContext.save()
        withAnimation(.easeInOut(duration: 0.3)) {
            loadData()
        }
    }

    // MARK: - Mentorships & Conflicts Card (R25)

    private var activeMentorships: [LockerRoomEngine.Mentorship] {
        groupChemistry.flatMap { $0.mentorships }
    }

    private var activeConflicts: [LockerRoomEngine.GroupConflict] {
        groupChemistry.flatMap { $0.conflicts }
    }

    private var dynamicsCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "person.line.dotted.person.fill")
                    .foregroundStyle(Color.accentBlue)
                Text("Mentorships & Conflicts")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
            }

            Divider().overlay(Color.surfaceBorder)

            if activeMentorships.isEmpty && activeConflicts.isEmpty {
                Text("No active mentorships or conflicts in the position rooms.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                ForEach(activeMentorships) { pairing in
                    HStack(spacing: 10) {
                        Image(systemName: "graduationcap.fill")
                            .font(.caption)
                            .foregroundStyle(Color.success)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(pairing.mentor.fullName) → \(pairing.protege.fullName)")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.textPrimary)
                            Text("\(pairing.mentor.position.rawValue) room - protege develops faster (+10% XP)")
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                        Spacer()
                        Text("Mentorship")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.success)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.success.opacity(0.15)))
                    }
                    .padding(.vertical, 4)
                }
                ForEach(activeConflicts) { conflict in
                    HStack(spacing: 10) {
                        Image(systemName: "bolt.fill")
                            .font(.caption)
                            .foregroundStyle(Color.danger)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(conflict.playerA.fullName) × \(conflict.playerB.fullName)")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.textPrimary)
                            Text(conflict.reason.rawValue)
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                        Spacer()
                        Text("Conflict Risk")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.danger)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.danger.opacity(0.15)))
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(20)
        .cardBackground()
    }

    // MARK: - Chemistry Card

    private var chemistryCard: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "heart.fill")
                    .foregroundStyle(chemistryColor(chemistry))
                Text("Team Chemistry")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text(LockerRoomEngine.chemistryLabel(chemistry))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(chemistryColor(chemistry))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.backgroundTertiary)
                        .frame(height: 16)
                    RoundedRectangle(cornerRadius: 8)
                        .fill(chemistryColor(chemistry))
                        .frame(width: geo.size.width * CGFloat(chemistry) / 100.0, height: 16)
                        .animation(.easeInOut(duration: 0.5), value: chemistry)
                }
            }
            .frame(height: 16)

            HStack {
                Text("0")
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
                Spacer()
                Text("\(chemistry) / 100")
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Text("100")
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
            }

            if let state = lockerRoomState {
                Divider().overlay(Color.surfaceBorder)

                HStack(spacing: 0) {
                    chemStatColumn(
                        label: "Leadership",
                        value: "+\(state.leadershipScore)",
                        color: Color.success
                    )
                    chemStatColumn(
                        label: "Toxicity",
                        value: "-\(state.toxicityScore)",
                        color: Color.danger
                    )
                    chemStatColumn(
                        label: "Net",
                        value: "\(state.leadershipScore - state.toxicityScore > 0 ? "+" : "")\(state.leadershipScore - state.toxicityScore)",
                        color: state.leadershipScore >= state.toxicityScore ? Color.success : Color.danger
                    )
                }
            }
        }
        .padding(20)
        .cardBackground()
    }

    private func chemStatColumn(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Morale Distribution Card

    private var moraleDistributionCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(Color.textSecondary)
                Text("Morale Distribution")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text("\(players.count) players")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            Divider().overlay(Color.surfaceBorder)

            HStack(spacing: 0) {
                moraleColumn(
                    label: "High",
                    count: highMorale,
                    total: max(players.count, 1),
                    color: Color.success,
                    icon: "arrow.up.circle.fill"
                )
                moraleColumn(
                    label: "Medium",
                    count: medMorale,
                    total: max(players.count, 1),
                    color: Color.warning,
                    icon: "minus.circle.fill"
                )
                moraleColumn(
                    label: "Low",
                    count: lowMorale,
                    total: max(players.count, 1),
                    color: Color.danger,
                    icon: "arrow.down.circle.fill"
                )
            }

            // Stacked bar
            GeometryReader { geo in
                HStack(spacing: 2) {
                    let total = max(players.count, 1)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.success)
                        .frame(width: geo.size.width * CGFloat(highMorale) / CGFloat(total))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.warning)
                        .frame(width: geo.size.width * CGFloat(medMorale) / CGFloat(total))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.danger)
                        .frame(width: geo.size.width * CGFloat(lowMorale) / CGFloat(total))
                }
                .frame(height: 10)
            }
            .frame(height: 10)

            // Axis labels — clarify what the morale tiers mean
            HStack {
                axisTick(label: "Low", range: "0-44", color: Color.danger)
                Spacer()
                axisTick(label: "Medium", range: "45-74", color: Color.warning)
                Spacer()
                axisTick(label: "High", range: "75-100", color: Color.success)
            }
            .padding(.top, 2)
        }
        .padding(20)
        .cardBackground()
    }

    private func axisTick(label: String, range: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(label) \(range)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Color.textTertiary)
        }
    }

    // MARK: - Top Issues Card (only shown when chemistry < 60)

    private var topIssuesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.octagon.fill")
                    .foregroundStyle(Color.danger)
                Text("Top Issues")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text("Chemistry \(chemistry)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.danger)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(Color.danger.opacity(0.15))
                    )
            }

            Divider().overlay(Color.surfaceBorder)

            let issues = topIssues
            if issues.isEmpty {
                Text("Chemistry is fragile but no specific hotspots identified yet.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            } else {
                ForEach(Array(issues.enumerated()), id: \.offset) { index, issue in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(Color.danger)
                            .frame(width: 18, height: 18)
                            .background(
                                Circle().fill(Color.danger.opacity(0.15))
                            )
                        Text(issue)
                            .font(.subheadline)
                            .foregroundStyle(Color.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.danger.opacity(0.3), lineWidth: 1)
                )
        )
    }

    // MARK: - Position Group Card

    private var positionGroupCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "person.2.fill")
                    .foregroundStyle(Color.textSecondary)
                Text("Position Group Morale")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
            }

            Divider().overlay(Color.surfaceBorder)

            let groups = positionGroups
            if groups.isEmpty {
                Text("No players on the roster.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            } else {
                ForEach(groups) { group in
                    positionGroupRow(group: group)
                    if group.id != groups.last?.id {
                        Divider().overlay(Color.surfaceBorder.opacity(0.5))
                    }
                }
            }
        }
        .padding(20)
        .cardBackground()
    }

    /// R25: good/neutral/tense verdict for a position room, from the engine.
    private func chemistryState(forGroupID id: String) -> LockerRoomEngine.GroupChemistryState? {
        groupChemistry.first { $0.id == id }?.state
    }

    private func chemistryStateColor(_ state: LockerRoomEngine.GroupChemistryState) -> Color {
        switch state {
        case .good:    return Color.success
        case .neutral: return Color.textSecondary
        case .tense:   return Color.danger
        }
    }

    private func positionGroupRow(group: PositionGroupSummary) -> some View {
        HStack(spacing: 12) {
            Image(systemName: group.icon)
                .font(.subheadline)
                .foregroundStyle(group.moraleColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(group.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text("\(group.count) player\(group.count == 1 ? "" : "s")\(group.lowCount > 0 ? " - \(group.lowCount) low morale" : "")")
                    .font(.caption)
                    .foregroundStyle(group.lowCount > 0 ? Color.danger : Color.textTertiary)
            }

            // R25: chemistry verdict badge (good / neutral / tense)
            if let state = chemistryState(forGroupID: group.id) {
                Text(state.rawValue)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(chemistryStateColor(state))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(chemistryStateColor(state).opacity(0.15)))
            }

            Spacer()

            // Mini bar showing avg morale
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(group.avgMorale)")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(group.moraleColor)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.backgroundTertiary)
                        .frame(width: 60, height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(group.moraleColor)
                        .frame(width: 60 * CGFloat(group.avgMorale) / 100.0, height: 4)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func moraleColumn(label: String, count: Int, total: Int, color: Color, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.title3)
            Text("\(count)")
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(Color.textPrimary)
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
            Text("\(total > 0 ? Int(Double(count) / Double(total) * 100) : 0)%")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Leaders Card

    private var leadersCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "star.fill")
                    .foregroundStyle(Color.accentGold)
                Text("Chemistry Leaders")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
            }

            Divider().overlay(Color.surfaceBorder)

            if leaders.isEmpty {
                Text("No standout chemistry leaders right now.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                ForEach(leaders) { player in
                    playerChemistryRow(player: player, isPositive: true)
                }
            }
        }
        .padding(20)
        .cardBackground()
    }

    // MARK: - Risks Card

    private var risksCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.danger)
                Text("Chemistry Risks")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
            }

            Divider().overlay(Color.surfaceBorder)

            if risks.isEmpty {
                Text("No active chemistry risks detected.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                ForEach(risks) { player in
                    playerChemistryRow(player: player, isPositive: false)
                }
            }
        }
        .padding(20)
        .cardBackground()
    }

    private func playerChemistryRow(player: Player, isPositive: Bool) -> some View {
        HStack(spacing: 12) {
            // Morale indicator dot
            Circle()
                .fill(moraleColor(player.morale))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(player.fullName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.textPrimary)
                HStack(spacing: 6) {
                    Text(player.position.rawValue)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.textSecondary)
                    Text("·")
                        .foregroundStyle(Color.textTertiary)
                    Text(player.personality.archetype.displayName)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("Morale \(player.morale)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(moraleColor(player.morale))
                Text(player.personality.motivation.rawValue)
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Events Log Card

    private var eventsCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "text.bubble.fill")
                    .foregroundStyle(Color.accentBlue)
                Text("Recent Events")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
            }

            Divider().overlay(Color.surfaceBorder)

            // R25: persisted locker-room happenings first (with week stamps),
            // falling back to the live chemistry notes when the log is empty.
            if !eventLog.isEmpty {
                ForEach(Array(eventLog.enumerated()), id: \.element.id) { index, event in
                    logEntryRow(event)
                    if index < eventLog.count - 1 {
                        Divider().overlay(Color.surfaceBorder.opacity(0.5))
                    }
                }
            } else {
                let events = lockerRoomState?.recentEvents ?? []
                if events.isEmpty {
                    Text("Nothing notable happening in the locker room.")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                } else {
                    ForEach(events.indices, id: \.self) { index in
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(Color.accentBlue.opacity(0.6))
                                .frame(width: 6, height: 6)
                                .padding(.top, 6)
                            Text(events[index])
                                .font(.subheadline)
                                .foregroundStyle(Color.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if index < events.count - 1 {
                            Divider().overlay(Color.surfaceBorder.opacity(0.5))
                        }
                    }
                }
            }
        }
        .padding(20)
        .cardBackground()
    }

    private func logEntryRow(_ event: LockerRoomEvent) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("W\(event.week)")
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(Color.accentBlue)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.accentBlue.opacity(0.12)))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text(event.resolutionSummary ?? event.detail)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private func chemistryColor(_ value: Int) -> Color {
        switch value {
        case 90...100: return Color.accentGold
        case 75..<90:  return Color.success
        case 55..<75:  return Color.accentBlue
        case 40..<55:  return Color.warning
        default:       return Color.danger
        }
    }

    private func moraleColor(_ value: Int) -> Color {
        switch value {
        case 75...100: return Color.success
        case 45..<75:  return Color.warning
        default:       return Color.danger
        }
    }

    private func loadData() {
        guard let teamID = career.teamID else { return }
        let descriptor = FetchDescriptor<Player>(predicate: #Predicate { $0.teamID == teamID })
        players = (try? modelContext.fetch(descriptor)) ?? []
        lockerRoomState = LockerRoomEngine.calculateChemistry(players: players)

        // R25: position-room chemistry, pending choice event & persisted log
        groupChemistry = LockerRoomEngine.positionGroupChemistry(players: players)
        let pending = career.pendingLockerRoomEvent
        pendingEvent = (pending?.requiresResponse == true) ? pending : nil
        eventLog = career.lockerRoomLog
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        LockerRoomView(career: Career(
            playerName: "Coach Smith",
            role: .gm,
            capMode: .simple
        ))
    }
    .modelContainer(for: [Career.self, Player.self], inMemory: true)
}
