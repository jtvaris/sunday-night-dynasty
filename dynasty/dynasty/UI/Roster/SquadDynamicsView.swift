import SwiftUI
import SwiftData

// MARK: - Squad Dynamics View

struct SquadDynamicsView: View {

    let career: Career

    @Environment(\.modelContext) private var modelContext
    @State private var players: [Player] = []
    @State private var lockerRoomState: LockerRoomState?

    // MARK: - Section Collapse State

    @State private var overviewExpanded        = true
    @State private var personalityExpanded     = true
    @State private var motivationExpanded      = true
    @State private var hierarchyExpanded       = true
    @State private var relationshipsExpanded   = true
    @State private var eventsExpanded          = true

    // MARK: - Computed: Base Data

    private var chemistry: Int    { lockerRoomState?.teamChemistry ?? 50 }
    private var leadership: Int   { lockerRoomState?.leadershipScore ?? 0 }
    private var toxicity: Int     { lockerRoomState?.toxicityScore ?? 0 }
    private var totalPlayers: Int { max(players.count, 1) }

    private var highMorale: Int  { players.filter { LockerRoomEngine.moraleTier($0.morale) == .high   }.count }
    private var medMorale: Int   { players.filter { LockerRoomEngine.moraleTier($0.morale) == .medium }.count }
    private var lowMorale: Int   { players.filter { LockerRoomEngine.moraleTier($0.morale) == .low    }.count }

    // MARK: - Computed: Personality Map

    private struct ArchetypeGroup: Identifiable {
        let archetype: PersonalityArchetype
        let players: [Player]
        var id: PersonalityArchetype { archetype }
        var count: Int { players.count }
    }

    private enum ArchetypeImpact: String {
        case positive = "Positive"
        case neutral  = "Neutral"
        case volatile = "Volatile"
        case negative = "Negative"

        var color: Color {
            switch self {
            case .positive: return Color.success
            case .neutral:  return Color.textSecondary
            case .volatile: return Color.warning
            case .negative: return Color.danger
            }
        }

        var icon: String {
            switch self {
            case .positive: return "arrow.up.circle.fill"
            case .neutral:  return "minus.circle.fill"
            case .volatile: return "bolt.circle.fill"
            case .negative: return "exclamationmark.circle.fill"
            }
        }
    }

    private func archetypeImpact(_ archetype: PersonalityArchetype) -> ArchetypeImpact {
        switch archetype {
        case .teamLeader, .mentor:           return .positive
        case .steadyPerformer,
             .quietProfessional,
             .classClown:                    return .neutral
        case .feelPlayer, .fieryCompetitor:  return .volatile
        case .dramaQueen, .loneWolf:         return .negative
        }
    }

    private var archetypeGroups: [ArchetypeGroup] {
        let grouped = Dictionary(grouping: players, by: { $0.personality.archetype })
        let groups = PersonalityArchetype.allCases.compactMap { archetype -> ArchetypeGroup? in
            guard let members = grouped[archetype], !members.isEmpty else { return nil }
            return ArchetypeGroup(archetype: archetype, players: members)
        }
        // Sort: positive first, volatile/negative last
        let order: [ArchetypeImpact] = [.positive, .neutral, .volatile, .negative]
        return groups.sorted { a, b in
            let ai = order.firstIndex(of: archetypeImpact(a.archetype)) ?? 0
            let bi = order.firstIndex(of: archetypeImpact(b.archetype)) ?? 0
            return ai < bi
        }
    }

    // MARK: - Computed: Motivation Groups

    private struct MotivationGroup: Identifiable {
        let motivation: Motivation
        let players: [Player]
        var id: Motivation { motivation }
        var count: Int { players.count }
        var expiringCount: Int { players.filter { $0.contractYearsRemaining <= 1 }.count }
    }

    private var motivationGroups: [MotivationGroup] {
        let grouped = Dictionary(grouping: players, by: { $0.personality.motivation })
        return Motivation.allCases.compactMap { motivation -> MotivationGroup? in
            guard let members = grouped[motivation], !members.isEmpty else { return nil }
            return MotivationGroup(motivation: motivation, players: members)
        }.sorted { $0.count > $1.count }
    }

    // MARK: - Computed: Social Hierarchy

    private var teamCaptain: Player? {
        players
            .filter { $0.personality.archetype == .teamLeader || $0.personality.archetype == .mentor }
            .max(by: { $0.mental.leadership < $1.mental.leadership })
        ?? players.max(by: { $0.mental.leadership < $1.mental.leadership })
    }

    private var keyInfluencers: [Player] {
        players
            .filter { $0.id != teamCaptain?.id }
            .sorted { $0.mental.leadership > $1.mental.leadership }
            .prefix(5)
            .map { $0 }
    }

    private var atRiskPlayers: [Player] {
        players
            .filter { player in
                player.morale < 40 ||
                player.personality.archetype == .dramaQueen ||
                (player.personality.archetype == .fieryCompetitor && player.morale < 50)
            }
            .sorted { $0.morale < $1.morale }
            .prefix(6)
            .map { $0 }
    }

    private var isolatedPlayers: [Player] {
        players
            .filter { player in
                player.personality.archetype == .loneWolf ||
                (player.morale < 50 && player.mental.leadership < 50 &&
                 player.personality.archetype != .dramaQueen)
            }
            .sorted { $0.morale < $1.morale }
            .prefix(5)
            .map { $0 }
    }

    // MARK: - Computed: Relationships

    enum RelationshipType: String {
        case mentorship   = "Mentorship"
        case bond         = "Strong Bond"
        case clash        = "Conflict Risk"
        case tension      = "Tension"
    }

    struct PlayerRelationship: Identifiable {
        let id = UUID()
        let playerA: Player
        let playerB: Player
        let type: RelationshipType

        var typeColor: Color {
            switch type {
            case .mentorship: return Color.success
            case .bond:       return Color.accentBlue
            case .clash:      return Color.danger
            case .tension:    return Color.warning
            }
        }

        var typeIcon: String {
            switch type {
            case .mentorship: return "graduationcap.fill"
            case .bond:       return "link"
            case .clash:      return "bolt.fill"
            case .tension:    return "exclamationmark.triangle.fill"
            }
        }
    }

    private var keyRelationships: [PlayerRelationship] {
        var relationships: [PlayerRelationship] = []

        // Mentor pairs: mentor/teamLeader with high leadership -> younger players
        let mentors = players.filter {
            ($0.personality.archetype == .mentor || $0.personality.archetype == .teamLeader)
            && $0.mental.leadership >= 70
        }
        let rookies = players.filter { $0.yearsPro <= 2 }.prefix(4)
        for mentor in mentors.prefix(3) {
            if let target = rookies.first(where: { $0.id != mentor.id }) {
                relationships.append(PlayerRelationship(playerA: mentor, playerB: target, type: .mentorship))
            }
        }

        // Personality clashes: dramaQueen + fieryCompetitor pairings
        let dramaQueens   = players.filter { $0.personality.archetype == .dramaQueen }
        let fieryOnes     = players.filter { $0.personality.archetype == .fieryCompetitor }
        for dq in dramaQueens.prefix(2) {
            if let fc = fieryOnes.first(where: { $0.id != dq.id }) {
                relationships.append(PlayerRelationship(playerA: dq, playerB: fc, type: .clash))
            }
        }

        // Lone wolf tension with team leaders
        let loneWolves  = players.filter { $0.personality.archetype == .loneWolf }
        let teamLeaders = players.filter { $0.personality.archetype == .teamLeader }
        for lw in loneWolves.prefix(2) {
            if let tl = teamLeaders.first {
                relationships.append(PlayerRelationship(playerA: lw, playerB: tl, type: .tension))
            }
        }

        // Compatible bonds: players sharing the same motivation with compatible archetypes
        let grouped = Dictionary(grouping: players, by: { $0.personality.motivation })
        for (_, group) in grouped {
            let compatible = group.filter {
                $0.personality.archetype == .teamLeader ||
                $0.personality.archetype == .steadyPerformer ||
                $0.personality.archetype == .quietProfessional ||
                $0.personality.archetype == .mentor
            }
            if compatible.count >= 2 {
                relationships.append(
                    PlayerRelationship(
                        playerA: compatible[0],
                        playerB: compatible[1],
                        type: .bond
                    )
                )
            }
        }

        // Deduplicate: keep at most 10, alternating clash/positive
        return Array(
            relationships
                .filter { $0.playerA.id != $0.playerB.id }
                .prefix(10)
        )
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    overviewSection
                    personalityMapSection
                    motivationSection
                    hierarchySection
                    relationshipsSection
                    eventsSection
                }
                .padding(20)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Squad Dynamics")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { loadData() }
    }

    // MARK: - Section Header Builder

    private func sectionHeader(
        icon: String,
        iconColor: Color = Color.accentGold,
        title: String,
        subtitle: String? = nil,
        isExpanded: Binding<Bool>
    ) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                isExpanded.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Color.accentGold)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                Spacer()
                Image(systemName: isExpanded.wrappedValue ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Section 1: Team Overview

    private var overviewSection: some View {
        VStack(spacing: 0) {
            sectionHeader(
                icon: "waveform.path.ecg",
                title: "Team Overview",
                subtitle: "Chemistry, leadership balance & morale spread",
                isExpanded: $overviewExpanded
            )
            .padding(20)

            if overviewExpanded {
                Divider().overlay(Color.surfaceBorder)
                overviewContent
                    .padding(20)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .cardBackground()
    }

    private var overviewContent: some View {
        VStack(spacing: 20) {

            // --- Chemistry Bar (large & prominent) ---
            VStack(spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Team Chemistry")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                        Text(LockerRoomEngine.chemistryLabel(chemistry))
                            .font(.caption)
                            .foregroundStyle(chemistryColor(chemistry))
                    }
                    Spacer()
                    Text("\(chemistry)")
                        .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(chemistryColor(chemistry))
                    Text("/ 100")
                        .font(.title3)
                        .foregroundStyle(Color.textTertiary)
                        .padding(.bottom, 4)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.backgroundTertiary)
                            .frame(height: 22)
                        RoundedRectangle(cornerRadius: 10)
                            .fill(
                                LinearGradient(
                                    colors: [chemistryColor(chemistry).opacity(0.6), chemistryColor(chemistry)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * CGFloat(chemistry) / 100.0, height: 22)
                            .animation(.easeInOut(duration: 0.6), value: chemistry)
                    }
                }
                .frame(height: 22)
            }

            Divider().overlay(Color.surfaceBorder)

            // --- Leadership vs Toxicity Comparison Bar ---
            VStack(spacing: 10) {
                HStack {
                    Text("Leadership vs Toxicity")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    let net = leadership - toxicity
                    Text(net >= 0 ? "+\(net) Net" : "\(net) Net")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(net >= 0 ? Color.success : Color.danger)
                }
                let total = max(leadership + toxicity, 1)
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        if leadership > 0 {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.success)
                                .frame(width: geo.size.width * CGFloat(leadership) / CGFloat(total))
                        }
                        if toxicity > 0 {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.danger)
                                .frame(width: geo.size.width * CGFloat(toxicity) / CGFloat(total))
                        }
                        if leadership == 0 && toxicity == 0 {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.backgroundTertiary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 14)
                }
                .frame(height: 14)
                HStack {
                    Label("\(leadership) Leadership", systemImage: "arrow.up.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.success)
                    Spacer()
                    Label("\(toxicity) Toxicity", systemImage: "arrow.down.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.danger)
                }
            }

            Divider().overlay(Color.surfaceBorder)

            // --- Morale Distribution Segmented Bar ---
            VStack(spacing: 10) {
                HStack {
                    Text("Morale Distribution")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Text("\(players.count) players")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        if highMorale > 0 {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.success)
                                .frame(width: geo.size.width * CGFloat(highMorale) / CGFloat(totalPlayers))
                        }
                        if medMorale > 0 {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.warning)
                                .frame(width: geo.size.width * CGFloat(medMorale) / CGFloat(totalPlayers))
                        }
                        if lowMorale > 0 {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.danger)
                                .frame(width: geo.size.width * CGFloat(lowMorale) / CGFloat(totalPlayers))
                        }
                    }
                    .frame(height: 14)
                }
                .frame(height: 14)
                HStack(spacing: 0) {
                    moraleStatPill(label: "High",   count: highMorale, color: Color.success)
                    moraleStatPill(label: "Medium", count: medMorale,  color: Color.warning)
                    moraleStatPill(label: "Low",    count: lowMorale,  color: Color.danger)
                }
            }
        }
    }

    private func moraleStatPill(label: String, count: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(Color.textPrimary)
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            Text("\(totalPlayers > 0 ? Int(Double(count) / Double(totalPlayers) * 100) : 0)%")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Section 2: Personality Map

    private var personalityMapSection: some View {
        VStack(spacing: 0) {
            sectionHeader(
                icon: "person.3.fill",
                title: "Personality Map",
                subtitle: "Player archetypes grouped by locker room impact",
                isExpanded: $personalityExpanded
            )
            .padding(20)

            if personalityExpanded {
                Divider().overlay(Color.surfaceBorder)
                personalityMapContent
                    .padding(20)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .cardBackground()
    }

    private var personalityMapContent: some View {
        VStack(spacing: 12) {
            if archetypeGroups.isEmpty {
                emptyStateText("No personality data available.")
            } else {
                ForEach(archetypeGroups) { group in
                    archetypeGroupCard(group)
                }
            }
        }
    }

    private func archetypeGroupCard(_ group: ArchetypeGroup) -> some View {
        let impact = archetypeImpact(group.archetype)
        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: impact.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(impact.color)
                Text(group.archetype.displayName + "s")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text("\(group.count) player\(group.count == 1 ? "" : "s")")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.textSecondary)
                impactBadge(impact)
            }
            // Player name list
            let sorted = group.players.sorted { $0.mental.leadership > $1.mental.leadership }
            FlowLayout(spacing: 6) {
                ForEach(sorted) { player in
                    Text(player.fullName)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.backgroundTertiary)
                                .overlay(Capsule().strokeBorder(impact.color.opacity(0.3), lineWidth: 1))
                        )
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.backgroundTertiary.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(impact.color.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private func impactBadge(_ impact: ArchetypeImpact) -> some View {
        Text(impact.rawValue)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(impact.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(impact.color.opacity(0.15))
            )
    }

    // MARK: - Section 3: Motivation Groups

    private var motivationSection: some View {
        VStack(spacing: 0) {
            sectionHeader(
                icon: "flame.fill",
                title: "Motivation Groups",
                subtitle: "What drives your players — and where tensions may arise",
                isExpanded: $motivationExpanded
            )
            .padding(20)

            if motivationExpanded {
                Divider().overlay(Color.surfaceBorder)
                motivationContent
                    .padding(20)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .cardBackground()
    }

    private var motivationContent: some View {
        VStack(spacing: 12) {
            if motivationGroups.isEmpty {
                emptyStateText("No motivation data available.")
            } else {
                ForEach(motivationGroups) { group in
                    motivationGroupRow(group)
                }
            }
        }
    }

    private func motivationGroupRow(_ group: MotivationGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: motivationIcon(group.motivation))
                    .font(.system(size: 14))
                    .foregroundStyle(motivationColor(group.motivation))
                    .frame(width: 20)
                Text(group.motivation.rawValue)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text("\(group.count)")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(motivationColor(group.motivation))
                Text("player\(group.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            // Mini motivation bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.backgroundTertiary)
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(motivationColor(group.motivation))
                        .frame(
                            width: geo.size.width * CGFloat(group.count) / CGFloat(totalPlayers),
                            height: 6
                        )
                }
            }
            .frame(height: 6)

            // Risk insight for Money-motivated players on expiring contracts
            if let insight = motivationInsight(group) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.warning)
                    Text(insight)
                        .font(.caption)
                        .foregroundStyle(Color.warning)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.warning.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.warning.opacity(0.25), lineWidth: 1)
                        )
                )
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.backgroundTertiary.opacity(0.5))
        )
    }

    private func motivationInsight(_ group: MotivationGroup) -> String? {
        switch group.motivation {
        case .money:
            let expiring = group.expiringCount
            guard expiring > 0 else { return nil }
            let noun = expiring == 1 ? "player" : "players"
            return "\(expiring) \(noun) motivated by Money \(expiring == 1 ? "is" : "are") on expiring contracts — holdout risk."
        case .winning:
            let lowMoraleWinners = group.players.filter { $0.morale < 45 }.count
            guard lowMoraleWinners > 0 else { return nil }
            return "\(lowMoraleWinners) winning-motivated player\(lowMoraleWinners == 1 ? "" : "s") have low morale — losing is hurting the room."
        case .stats:
            let benchPlayers = group.players.filter { $0.morale < 50 }.count
            guard benchPlayers > 0 else { return nil }
            return "\(benchPlayers) stats-motivated player\(benchPlayers == 1 ? "" : "s") may be unhappy with their role."
        case .loyalty, .fame:
            return nil
        }
    }

    private func motivationIcon(_ motivation: Motivation) -> String {
        switch motivation {
        case .money:   return "dollarsign.circle.fill"
        case .winning: return "trophy.fill"
        case .stats:   return "chart.bar.fill"
        case .loyalty: return "heart.fill"
        case .fame:    return "star.fill"
        }
    }

    private func motivationColor(_ motivation: Motivation) -> Color {
        switch motivation {
        case .money:   return Color.accentGold
        case .winning: return Color.success
        case .stats:   return Color.accentBlue
        case .loyalty: return Color(red: 0.85, green: 0.35, blue: 0.85)
        case .fame:    return Color(red: 0.98, green: 0.55, blue: 0.20)
        }
    }

    // MARK: - Section 4: Social Hierarchy

    private var hierarchySection: some View {
        VStack(spacing: 0) {
            sectionHeader(
                icon: "crown.fill",
                title: "Social Hierarchy",
                subtitle: "Captain, influencers, at-risk players & isolated members",
                isExpanded: $hierarchyExpanded
            )
            .padding(20)

            if hierarchyExpanded {
                Divider().overlay(Color.surfaceBorder)
                hierarchyContent
                    .padding(20)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .cardBackground()
    }

    private var hierarchyContent: some View {
        VStack(spacing: 16) {

            // --- Team Captain ---
            VStack(alignment: .leading, spacing: 8) {
                Label("Team Captain", systemImage: "crown.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentGold)
                if let captain = teamCaptain {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.accentGold.opacity(0.15))
                                .frame(width: 44, height: 44)
                            Text(initials(captain.fullName))
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color.accentGold)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(captain.fullName)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Color.textPrimary)
                            HStack(spacing: 6) {
                                Text(captain.position.rawValue)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(Color.accentGold)
                                Text("·")
                                    .foregroundStyle(Color.textTertiary)
                                Text(captain.personality.archetype.displayName)
                                    .font(.caption)
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text("Leadership")
                                .font(.caption2)
                                .foregroundStyle(Color.textTertiary)
                            Text("\(captain.mental.leadership)")
                                .font(.title3.weight(.bold).monospacedDigit())
                                .foregroundStyle(Color.accentGold)
                        }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.accentGold.opacity(0.07))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Color.accentGold.opacity(0.3), lineWidth: 1)
                            )
                    )
                } else {
                    emptyStateText("No clear captain has emerged.")
                }
            }

            Divider().overlay(Color.surfaceBorder)

            // --- Key Influencers ---
            VStack(alignment: .leading, spacing: 8) {
                Label("Key Influencers", systemImage: "person.2.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentBlue)
                if keyInfluencers.isEmpty {
                    emptyStateText("No standout influencers.")
                } else {
                    VStack(spacing: 6) {
                        ForEach(Array(keyInfluencers.enumerated()), id: \.element.id) { index, player in
                            influencerRow(player: player, rank: index + 1)
                        }
                    }
                }
            }

            Divider().overlay(Color.surfaceBorder)

            // --- At Risk ---
            VStack(alignment: .leading, spacing: 8) {
                Label("At Risk", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.danger)
                if atRiskPlayers.isEmpty {
                    emptyStateText("No at-risk players detected.")
                } else {
                    VStack(spacing: 6) {
                        ForEach(atRiskPlayers) { player in
                            atRiskRow(player)
                        }
                    }
                }
            }

            Divider().overlay(Color.surfaceBorder)

            // --- Isolated ---
            VStack(alignment: .leading, spacing: 8) {
                Label("Isolated / Lone Wolves", systemImage: "person.fill.questionmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                if isolatedPlayers.isEmpty {
                    emptyStateText("No isolated players — solid cohesion.")
                } else {
                    VStack(spacing: 6) {
                        ForEach(isolatedPlayers) { player in
                            isolatedRow(player)
                        }
                    }
                }
            }
        }
    }

    private func influencerRow(player: Player, rank: Int) -> some View {
        HStack(spacing: 10) {
            Text("\(rank)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(Color.textTertiary)
                .frame(width: 16)
            Text(player.fullName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.textPrimary)
            Text(player.position.rawValue)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.accentGold)
            Text(player.personality.archetype.displayName)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text("\(player.mental.leadership)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(Color.accentBlue)
            Image(systemName: "bolt.fill")
                .font(.caption2)
                .foregroundStyle(Color.accentBlue.opacity(0.6))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.backgroundTertiary.opacity(0.5))
        )
    }

    private func atRiskRow(_ player: Player) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(moraleColor(player.morale))
                .frame(width: 8, height: 8)
            Text(player.fullName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.textPrimary)
            Text(player.position.rawValue)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.accentGold)
            Spacer()
            Text("Morale \(player.morale)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(moraleColor(player.morale))
            riskReasonBadge(player)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.danger.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.danger.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private func riskReasonBadge(_ player: Player) -> some View {
        let label: String = {
            if player.morale < 40 { return "Low Morale" }
            if player.personality.archetype == .dramaQueen { return "Drama" }
            if player.personality.archetype == .fieryCompetitor { return "Volatile" }
            return "Watch"
        }()
        return Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.danger)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.danger.opacity(0.15)))
    }

    private func isolatedRow(_ player: Player) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "person.fill")
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
            Text(player.fullName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.textPrimary)
            Text(player.position.rawValue)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.accentGold)
            Spacer()
            Text(player.personality.archetype.displayName)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.backgroundTertiary.opacity(0.4))
        )
    }

    // MARK: - Section 5: Relationships Matrix

    private var relationshipsSection: some View {
        VStack(spacing: 0) {
            sectionHeader(
                icon: "arrow.left.arrow.right",
                title: "Key Relationships",
                subtitle: "Mentor bonds, personality clashes & chemistry pairs",
                isExpanded: $relationshipsExpanded
            )
            .padding(20)

            if relationshipsExpanded {
                Divider().overlay(Color.surfaceBorder)
                relationshipsContent
                    .padding(20)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .cardBackground()
    }

    private var relationshipsContent: some View {
        VStack(spacing: 10) {
            if keyRelationships.isEmpty {
                emptyStateText("No notable player relationships detected yet.")
            } else {
                ForEach(keyRelationships) { rel in
                    relationshipRow(rel)
                }
            }
        }
    }

    private func relationshipRow(_ rel: PlayerRelationship) -> some View {
        HStack(spacing: 12) {
            // Type badge
            HStack(spacing: 5) {
                Image(systemName: rel.typeIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(rel.typeColor)
                Text(rel.type.rawValue)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(rel.typeColor)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(rel.typeColor.opacity(0.12))
                    .overlay(Capsule().strokeBorder(rel.typeColor.opacity(0.3), lineWidth: 1))
            )
            .frame(minWidth: 120, alignment: .leading)

            // Players
            HStack(spacing: 6) {
                Text(rel.playerA.fullName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Image(systemName: "arrow.left.arrow.right")
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
                Text(rel.playerB.fullName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.backgroundTertiary.opacity(0.5))
        )
    }

    // MARK: - Section 6: Recent Events

    private var eventsSection: some View {
        VStack(spacing: 0) {
            sectionHeader(
                icon: "text.bubble.fill",
                iconColor: Color.accentBlue,
                title: "Recent Locker Room Events",
                subtitle: "Latest activity affecting team chemistry",
                isExpanded: $eventsExpanded
            )
            .padding(20)

            if eventsExpanded {
                Divider().overlay(Color.surfaceBorder)
                eventsContent
                    .padding(20)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .cardBackground()
    }

    private var eventsContent: some View {
        let events = lockerRoomState?.recentEvents ?? []
        return Group {
            if events.isEmpty {
                emptyStateText("Nothing notable happening in the locker room.")
            } else {
                VStack(spacing: 0) {
                    ForEach(events.indices, id: \.self) { index in
                        HStack(alignment: .top, spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color.accentBlue.opacity(0.15))
                                    .frame(width: 28, height: 28)
                                Image(systemName: eventIcon(events[index]))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color.accentBlue)
                            }
                            .padding(.top, 2)
                            Text(events[index])
                                .font(.subheadline)
                                .foregroundStyle(Color.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 10)
                        if index < events.count - 1 {
                            Divider().overlay(Color.surfaceBorder.opacity(0.5))
                        }
                    }
                }
            }
        }
    }

    private func eventIcon(_ event: String) -> String {
        let lower = event.lowercased()
        if lower.contains("drama") || lower.contains("tension") { return "exclamationmark.triangle.fill" }
        if lower.contains("mentor") || lower.contains("trust")  { return "graduationcap.fill" }
        if lower.contains("energy") || lower.contains("lift")   { return "bolt.fill" }
        if lower.contains("bond") || lower.contains("locat")    { return "link" }
        return "text.bubble.fill"
    }

    // MARK: - Shared Helpers

    private func emptyStateText(_ message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(Color.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
    }

    private func chemistryColor(_ value: Int) -> Color {
        switch value {
        case 75...100: return Color.success
        case 55..<75:  return Color.accentGold
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

    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ")
        return parts.prefix(2).compactMap { $0.first.map(String.init) }.joined()
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let teamID = career.teamID else { return }
        let descriptor = FetchDescriptor<Player>(predicate: #Predicate { $0.teamID == teamID })
        players = (try? modelContext.fetch(descriptor)) ?? []
        lockerRoomState = LockerRoomEngine.calculateChemistry(players: players)
    }
}

// MARK: - Flow Layout (wrapping tag cloud)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        let height = rows.map { $0.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0 }.reduce(0) { $0 + $1 + spacing }
        return CGSize(width: proposal.width ?? 0, height: max(0, height - spacing))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            for subview in row {
                let size = subview.sizeThatFits(.unspecified)
                subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
                x += size.width + spacing
            }
            y += rowHeight + spacing
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[LayoutSubview]] {
        var rows: [[LayoutSubview]] = [[]]
        var rowWidth: CGFloat = 0
        let maxWidth = proposal.width ?? 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth && rowWidth > 0 {
                rows.append([])
                rowWidth = 0
            }
            rows[rows.count - 1].append(subview)
            rowWidth += size.width + spacing
        }
        return rows
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SquadDynamicsView(career: Career(
            playerName: "Coach Smith",
            role: .gm,
            capMode: .simple
        ))
    }
    .modelContainer(for: [Career.self, Player.self], inMemory: true)
}
