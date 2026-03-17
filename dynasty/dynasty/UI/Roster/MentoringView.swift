import SwiftUI
import SwiftData

// MARK: - Mentoring Pair

struct MentoringPair: Identifiable, Equatable {
    let id: UUID
    let mentorID: UUID
    let menteeID: UUID

    init(mentorID: UUID, menteeID: UUID) {
        self.id = UUID()
        self.mentorID = mentorID
        self.menteeID = menteeID
    }
}

// MARK: - MentoringView

/// Assigns veteran mentors to young players and shows active mentoring pairs.
struct MentoringView: View {

    let career: Career

    @Environment(\.modelContext) private var modelContext

    @State private var players: [Player] = []
    @State private var pairs: [MentoringPair] = []
    @State private var selectedMentor: Player? = nil

    // MARK: - Derived Lists

    private var eligibleMentors: [Player] {
        players
            .filter { isMentorEligible($0) }
            .sorted { $0.mental.leadership > $1.mental.leadership }
    }

    private var eligibleMentees: [Player] {
        players
            .filter { $0.yearsPro <= 2 }
            .sorted { $0.overall > $1.overall }
    }

    /// Mentees eligible to be paired with the selected mentor (same position group, unpaired).
    private var candidateMentees: [Player] {
        guard let mentor = selectedMentor else { return [] }
        return eligibleMentees.filter { mentee in
            !isAlreadyPaired(mentee) && inSamePositionGroup(mentor.position, mentee.position)
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    instructionBanner
                    assignmentSection
                    pairsSection
                }
                .padding(20)
                .frame(maxWidth: 860)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Mentoring")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { loadPlayers() }
    }

    // MARK: - Instruction Banner

    private var instructionBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: "person.2.wave.2.fill")
                .font(.title2)
                .foregroundStyle(Color.accentGold)

            VStack(alignment: .leading, spacing: 4) {
                Text("Assign Veteran Mentors")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                Text("Select a mentor to see compatible young players at the same position group. Active pairs apply +1-3 mental attribute bonuses during offseason development.")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .cardBackground()
    }

    // MARK: - Assignment Section

    private var assignmentSection: some View {
        HStack(alignment: .top, spacing: 16) {
            mentorsColumn
            menteesColumn
        }
    }

    // MARK: - Mentors Column

    private var mentorsColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            columnHeader(
                icon: "star.fill",
                title: "Eligible Mentors",
                subtitle: "\(eligibleMentors.count) available",
                iconColor: .accentGold
            )

            if eligibleMentors.isEmpty {
                emptyStateText("No eligible mentors. Veterans need .mentor or .teamLeader archetype with leadership > 70.")
            } else {
                VStack(spacing: 8) {
                    ForEach(eligibleMentors) { mentor in
                        mentorCard(mentor)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cardBackground()
    }

    private func mentorCard(_ mentor: Player) -> some View {
        let isSelected = selectedMentor?.id == mentor.id
        let currentMentee = activeMenteeFor(mentor)

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedMentor = isSelected ? nil : mentor
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    positionBadge(mentor.position)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(mentor.fullName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                        HStack(spacing: 6) {
                            Text("Age \(mentor.age)")
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                            Text("·")
                                .foregroundStyle(Color.textTertiary)
                            Text("\(mentor.yearsPro) yr pro")
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }

                    Spacer()

                    archetypeBadge(mentor.personality.archetype)
                }

                // Leadership bar
                HStack(spacing: 6) {
                    Image(systemName: "bolt.heart.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.accentGold)
                    Text("Leadership")
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                    Spacer()
                    Text("\(mentor.mental.leadership)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color.forRating(mentor.mental.leadership))
                }

                // Current mentee indicator
                if let mentee = currentMentee {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.success)
                        Text("Mentoring \(mentee.fullName)")
                            .font(.caption2)
                            .foregroundStyle(Color.success)
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentGold.opacity(0.12) : Color.backgroundTertiary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(isSelected ? Color.accentGold : Color.clear, lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(mentor.fullName), \(mentor.position.rawValue), leadership \(mentor.mental.leadership)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Mentees Column

    private var menteesColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            columnHeader(
                icon: "figure.walk.arrival",
                title: selectedMentor != nil ? "Compatible Mentees" : "Young Players",
                subtitle: selectedMentor != nil
                    ? "\(candidateMentees.count) at \(selectedMentor!.position.rawValue) group"
                    : "\(eligibleMentees.count) eligible (≤ 2 yrs pro)",
                iconColor: .accentBlue
            )

            if selectedMentor == nil {
                allMenteesPreview
            } else if candidateMentees.isEmpty {
                emptyStateText("No compatible young players at this position group, or all are already paired.")
            } else {
                VStack(spacing: 8) {
                    ForEach(candidateMentees) { mentee in
                        menteeCard(mentee, forMentor: selectedMentor!)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cardBackground()
    }

    private var allMenteesPreview: some View {
        VStack(spacing: 8) {
            Text("Select a mentor to assign a mentee")
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 4)

            ForEach(eligibleMentees.prefix(6)) { mentee in
                menteePreviewRow(mentee)
            }

            if eligibleMentees.count > 6 {
                Text("+\(eligibleMentees.count - 6) more young players")
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
            }
        }
    }

    private func menteePreviewRow(_ mentee: Player) -> some View {
        HStack(spacing: 8) {
            positionBadge(mentee.position)
            Text(mentee.fullName)
                .font(.subheadline)
                .foregroundStyle(isAlreadyPaired(mentee) ? Color.textTertiary : Color.textPrimary)
            Spacer()
            if isAlreadyPaired(mentee) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.success)
            }
            Text("\(mentee.overall) OVR")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.forRating(mentee.overall))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func menteeCard(_ mentee: Player, forMentor mentor: Player) -> some View {
        let matchQuality = positionMatchQuality(mentor.position, mentee.position)

        return Button {
            assignPair(mentor: mentor, mentee: mentee)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    positionBadge(mentee.position)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(mentee.fullName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                        HStack(spacing: 6) {
                            Text(mentee.yearsPro == 0 ? "Rookie" : "\(mentee.yearsPro) yr pro")
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                            Text("·")
                                .foregroundStyle(Color.textTertiary)
                            Text("Age \(mentee.age)")
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }

                    Spacer()

                    Text("\(mentee.overall)")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.forRating(mentee.overall))
                }

                HStack(spacing: 6) {
                    matchQualityBadge(matchQuality)
                    Spacer()
                    expectedBenefitLabel(mentor: mentor)
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Color.accentGold)
                        .font(.subheadline)
                }
            }
            .padding(12)
            .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.accentGold.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Assign \(mentor.fullName) to mentor \(mentee.fullName). Tap to confirm.")
    }

    // MARK: - Pairs Section

    private var pairsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            columnHeader(
                icon: "arrow.triangle.2.circlepath",
                title: "Active Mentoring Pairs",
                subtitle: "\(pairs.count) pair\(pairs.count == 1 ? "" : "s") assigned",
                iconColor: .success
            )

            if pairs.isEmpty {
                emptyStateText("No active pairs. Select a mentor above to assign mentees.")
            } else {
                VStack(spacing: 8) {
                    ForEach(pairs) { pair in
                        pairRow(pair)
                    }
                }
            }
        }
        .padding(16)
        .cardBackground()
    }

    private func pairRow(_ pair: MentoringPair) -> some View {
        guard
            let mentor = player(for: pair.mentorID),
            let mentee = player(for: pair.menteeID)
        else { return AnyView(EmptyView()) }

        let matchQuality = positionMatchQuality(mentor.position, mentee.position)

        return AnyView(
            HStack(spacing: 12) {
                // Mentor
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        positionBadge(mentor.position)
                        Text(mentor.fullName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                    }
                    Text("Mentor · Ldr \(mentor.mental.leadership)")
                        .font(.caption2)
                        .foregroundStyle(Color.accentGold)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Arrow
                VStack(spacing: 2) {
                    Image(systemName: "arrow.right")
                        .foregroundStyle(Color.success)
                        .font(.caption.weight(.semibold))
                    matchQualityBadge(matchQuality)
                }

                // Mentee
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(mentee.fullName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                        positionBadge(mentee.position)
                    }
                    Text("Mentee · \(mentee.yearsPro == 0 ? "Rookie" : "\(mentee.yearsPro) yr")")
                        .font(.caption2)
                        .foregroundStyle(Color.accentBlue)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)

                // Remove
                Button(role: .destructive) {
                    removePair(pair)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.danger.opacity(0.7))
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove mentoring pair")
            }
            .padding(12)
            .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: 10))
        )
    }

    // MARK: - Shared Subviews

    private func columnHeader(icon: String, title: String, subtitle: String, iconColor: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
        }
    }

    private func emptyStateText(_ message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(Color.textTertiary)
            .multilineTextAlignment(.center)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
    }

    private func positionBadge(_ position: Position) -> some View {
        Text(position.rawValue)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(Color.textPrimary)
            .frame(width: 28)
            .padding(.vertical, 3)
            .background(positionSideColor(position), in: RoundedRectangle(cornerRadius: 3))
    }

    private func archetypeBadge(_ archetype: PersonalityArchetype) -> some View {
        Text(archetypeShortLabel(archetype))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(archetypeColor(archetype))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(archetypeColor(archetype).opacity(0.15), in: Capsule())
    }

    private func matchQualityBadge(_ quality: PositionMatchQuality) -> some View {
        Text(quality.label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(quality.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(quality.color.opacity(0.15), in: Capsule())
    }

    private func expectedBenefitLabel(mentor: Player) -> some View {
        let baseMentorBonus = Double(mentor.mental.leadership - 1) / 98.0
        let bonusPoints = max(1, min(3, Int((baseMentorBonus * 3.0).rounded())))
        return Text("+\(bonusPoints) mental attr.")
            .font(.caption2)
            .foregroundStyle(Color.success)
    }

    // MARK: - Actions

    private func assignPair(mentor: Player, mentee: Player) {
        // Remove any existing pairing for this mentee
        pairs.removeAll { $0.menteeID == mentee.id }

        let newPair = MentoringPair(mentorID: mentor.id, menteeID: mentee.id)
        withAnimation(.easeInOut(duration: 0.25)) {
            pairs.append(newPair)
            selectedMentor = nil
        }
    }

    private func removePair(_ pair: MentoringPair) {
        withAnimation(.easeInOut(duration: 0.2)) {
            pairs.removeAll { $0.id == pair.id }
        }
    }

    // MARK: - Helpers

    private func loadPlayers() {
        guard let teamID = career.teamID else { return }
        let descriptor = FetchDescriptor<Player>(predicate: #Predicate { $0.teamID == teamID })
        players = (try? modelContext.fetch(descriptor)) ?? []
    }

    private func isMentorEligible(_ player: Player) -> Bool {
        (player.personality.archetype == .mentor || player.personality.archetype == .teamLeader)
            && player.mental.leadership > 70
    }

    private func isAlreadyPaired(_ mentee: Player) -> Bool {
        pairs.contains { $0.menteeID == mentee.id }
    }

    private func activeMenteeFor(_ mentor: Player) -> Player? {
        guard let pair = pairs.first(where: { $0.mentorID == mentor.id }) else { return nil }
        return player(for: pair.menteeID)
    }

    private func player(for id: UUID) -> Player? {
        players.first { $0.id == id }
    }

    private func positionSideColor(_ position: Position) -> Color {
        switch position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }

    private func archetypeShortLabel(_ archetype: PersonalityArchetype) -> String {
        switch archetype {
        case .mentor:        return "Mentor"
        case .teamLeader:    return "Leader"
        default:             return archetype.displayName
        }
    }

    private func archetypeColor(_ archetype: PersonalityArchetype) -> Color {
        switch archetype {
        case .mentor:        return .accentGold
        case .teamLeader:    return .success
        default:             return .accentBlue
        }
    }

    private func inSamePositionGroup(_ a: Position, _ b: Position) -> Bool {
        positionGroup(a) == positionGroup(b)
    }

    private func positionGroup(_ position: Position) -> Int {
        switch position {
        case .QB:                    return 0
        case .RB, .FB:               return 1
        case .WR, .TE:               return 2
        case .LT, .LG, .C, .RG, .RT: return 3
        case .DE, .DT:               return 4
        case .OLB, .MLB:             return 5
        case .CB, .FS, .SS:          return 6
        case .K, .P:                 return 7
        }
    }

    private func positionMatchQuality(_ mentor: Position, _ mentee: Position) -> PositionMatchQuality {
        if mentor == mentee             { return .natural }
        if inSamePositionGroup(mentor, mentee) { return .accomplished }
        if mentor.side == mentee.side   { return .competent }
        return .limited
    }
}

// MARK: - Position Match Quality

enum PositionMatchQuality {
    case natural
    case accomplished
    case competent
    case limited

    var label: String {
        switch self {
        case .natural:      return "Natural"
        case .accomplished: return "Accomplished"
        case .competent:    return "Competent"
        case .limited:      return "Limited"
        }
    }

    var color: Color {
        switch self {
        case .natural:      return .success
        case .accomplished: return .accentGold
        case .competent:    return .warning
        case .limited:      return .textTertiary
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        MentoringView(
            career: Career(playerName: "Coach Smith", role: .gm, capMode: .simple)
        )
    }
    .modelContainer(for: [Career.self, Player.self], inMemory: true)
}
