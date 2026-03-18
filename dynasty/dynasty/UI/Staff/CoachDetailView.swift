import SwiftUI
import SwiftData

struct CoachDetailView: View {

    let coach: Coach
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var allCoaches: [Coach]
    @Query private var allCareers: [Career]

    @State private var showFireConfirmation = false

    /// Deterministic avatar ID derived from the coach's name.
    private var coachAvatarID: String {
        let allIDs = CoachAvatars.all.map { $0.id }
        let hash = abs(coach.fullName.hashValue)
        return allIDs[hash % allIDs.count]
    }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    /// The head coach on the same team (nil if this coach IS the HC or no team).
    private var headCoach: Coach? {
        guard coach.role != .headCoach,
              let teamID = coach.teamID else { return nil }
        return allCoaches.first { $0.role == .headCoach && $0.teamID == teamID }
    }

    /// The active career (used for coaching style context).
    private var career: Career? {
        allCareers.first
    }

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            // Subtle locker room background
            GeometryReader { geo in
                Image("BgLockerRoom")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .opacity(0.08)
            }
            .ignoresSafeArea()

            List {
                avatarSection
                overviewSection
                attributesSection
                personalitySection
                schemeSection
                schemeFitSection
                destructiveSection
            }
            .scrollContentBackground(.hidden)
            .listStyle(.insetGrouped)
        }
        .navigationTitle(coach.fullName)
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .alert("Fire \(coach.fullName)?", isPresented: $showFireConfirmation) {
            Button("Fire Coach", role: .destructive) {
                fireCoach()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove \(coach.firstName) from your coaching staff. This action cannot be undone.")
        }
    }

    // MARK: - Avatar Section

    private var avatarSection: some View {
        Section {
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    CoachAvatarImageView(avatarID: coachAvatarID, size: 96)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.accentGold, lineWidth: 2)
                        )
                    Text(coach.role.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentGold)
                }
                Spacer()
            }
            .padding(.vertical, 8)
        }
        .listRowBackground(Color.clear)
    }

    // MARK: - Overview Section

    private var overviewSection: some View {
        Section("Overview") {
            LabeledContent("Role") {
                Text(coach.role.displayName)
                    .foregroundStyle(Color.textPrimary)
            }
            LabeledContent("Age") {
                Text("\(coach.age)")
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
            }
            LabeledContent("Experience") {
                Text(experienceLabel)
                    .foregroundStyle(Color.textSecondary)
            }
            LabeledContent("Salary") {
                Text("$\(coach.salary)K/yr")
                    .monospacedDigit()
                    .foregroundStyle(Color.accentGold)
            }
            if !coach.background.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Background")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                    Text(coach.background)
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    // MARK: - Attributes Section (2-column grid on iPad)

    private var attributesSection: some View {
        Section("Coaching Attributes") {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                attributeCell(name: "Play Calling",        value: coach.playCalling)
                attributeCell(name: "Player Development",  value: coach.playerDevelopment)
                attributeCell(name: "Reputation",          value: coach.reputation)
                attributeCell(name: "Adaptability",        value: coach.adaptability)
                attributeCell(name: "Game Planning",       value: coach.gamePlanning)
                attributeCell(name: "Scouting Ability",    value: coach.scoutingAbility)
                attributeCell(name: "Recruiting",          value: coach.recruiting)
                attributeCell(name: "Motivation",          value: coach.motivation)
                attributeCell(name: "Discipline",          value: coach.discipline)
                attributeCell(name: "Media Handling",      value: coach.mediaHandling)
                attributeCell(name: "Contract Negotiation", value: coach.contractNegotiation)
                attributeCell(name: "Morale Influence",    value: coach.moraleInfluence)
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    /// A single attribute cell for the 2-column grid with color-coded value and tier label.
    private func attributeCell(name: String, value: Int) -> some View {
        HStack(spacing: 4) {
            Text(name)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 2)
            Text("\(value)")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(attributeColor(value))
            Text(attributeTierLabel(value))
                .font(.caption2.weight(.medium))
                .foregroundStyle(attributeColor(value))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(value), \(attributeTierLabel(value))")
    }

    // MARK: - Personality Section

    private var personalitySection: some View {
        Section("Personality") {
            LabeledContent("Archetype") {
                Text(coach.personality.displayName)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    // MARK: - Scheme Section

    @ViewBuilder
    private var schemeSection: some View {
        let hasScheme = coach.offensiveScheme != nil || coach.defensiveScheme != nil
        if hasScheme {
            Section("Scheme") {
                if let offScheme = coach.offensiveScheme {
                    LabeledContent("Offensive Scheme") {
                        Text(offScheme.displayName)
                            .foregroundStyle(Color.accentBlue)
                    }
                }
                if let defScheme = coach.defensiveScheme {
                    LabeledContent("Defensive Scheme") {
                        Text(defScheme.displayName)
                            .foregroundStyle(Color.danger)
                    }
                }
            }
            .listRowBackground(Color.backgroundSecondary)
        }
    }

    // MARK: - Scheme Fit / HC Compatibility Section

    @ViewBuilder
    private var schemeFitSection: some View {
        // Only show for non-HC coaches who share a team with an HC
        if coach.role != .headCoach {
            Section("Scheme Fit") {
                if let hc = headCoach {
                    let analysis = analyzeCompatibility(with: hc)

                    // Overall fit
                    LabeledContent("HC Compatibility") {
                        Text(analysis.overallLabel)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(analysis.overallColor)
                    }

                    // Coaching style context
                    if let style = career?.coachingStyle {
                        LabeledContent("HC Style") {
                            Text(style.displayName)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }

                    // Complementary strengths
                    if !analysis.complements.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Complements HC")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.green)
                            Text(analysis.complements.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }

                    // Redundant overlaps
                    if !analysis.redundancies.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Redundant with HC")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.accentGold)
                            Text(analysis.redundancies.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }

                    // Weak areas
                    if !analysis.weaknesses.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Shared Weaknesses")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                            Text(analysis.weaknesses.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                } else {
                    Text("No Head Coach on staff to compare against.")
                        .font(.subheadline)
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .listRowBackground(Color.backgroundSecondary)
        }
    }

    // MARK: - Destructive Section

    private var destructiveSection: some View {
        Section {
            Button(role: .destructive) {
                showFireConfirmation = true
            } label: {
                HStack {
                    Spacer()
                    Label("Fire Coach", systemImage: "person.fill.xmark")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                }
            }
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    // MARK: - Helpers

    private var experienceLabel: String {
        switch coach.yearsExperience {
        case 0:      return "No experience"
        case 1:      return "1 year"
        default:     return "\(coach.yearsExperience) years"
        }
    }

    /// Color-codes attribute values based on tier thresholds.
    private func attributeColor(_ value: Int) -> Color {
        if value >= 80 { return .green }
        if value >= 60 { return Color.accentGold }
        if value >= 50 { return .orange }
        return .red
    }

    /// Human-readable tier label for an attribute value.
    private func attributeTierLabel(_ value: Int) -> String {
        if value >= 90 { return "Elite" }
        if value >= 80 { return "Great" }
        if value >= 70 { return "Good" }
        if value >= 60 { return "Average" }
        if value >= 50 { return "Below Avg" }
        return "Poor"
    }

    // MARK: - Compatibility Analysis

    private struct CompatibilityAnalysis {
        var complements: [String]
        var redundancies: [String]
        var weaknesses: [String]
        var overallLabel: String
        var overallColor: Color
    }

    /// Named attribute pair for comparison.
    private struct AttributePair {
        let name: String
        let coachValue: Int
        let hcValue: Int
    }

    /// Compares this coach's attributes against the HC to find complements, redundancies, and weaknesses.
    private func analyzeCompatibility(with hc: Coach) -> CompatibilityAnalysis {
        let pairs: [AttributePair] = [
            .init(name: "Play Calling",        coachValue: coach.playCalling,        hcValue: hc.playCalling),
            .init(name: "Player Dev",          coachValue: coach.playerDevelopment,  hcValue: hc.playerDevelopment),
            .init(name: "Game Planning",       coachValue: coach.gamePlanning,       hcValue: hc.gamePlanning),
            .init(name: "Scouting",            coachValue: coach.scoutingAbility,    hcValue: hc.scoutingAbility),
            .init(name: "Recruiting",          coachValue: coach.recruiting,         hcValue: hc.recruiting),
            .init(name: "Motivation",          coachValue: coach.motivation,         hcValue: hc.motivation),
            .init(name: "Discipline",          coachValue: coach.discipline,         hcValue: hc.discipline),
            .init(name: "Adaptability",        coachValue: coach.adaptability,       hcValue: hc.adaptability),
            .init(name: "Morale Influence",    coachValue: coach.moraleInfluence,    hcValue: hc.moraleInfluence),
        ]

        var complements: [String] = []
        var redundancies: [String] = []
        var weaknesses: [String] = []

        for pair in pairs {
            let coachStrong = pair.coachValue >= 75
            let hcWeak = pair.hcValue < 60
            let hcStrong = pair.hcValue >= 75
            let bothWeak = pair.coachValue < 60 && pair.hcValue < 60

            if coachStrong && hcWeak {
                // Coach is strong where HC is weak -> complements
                complements.append(pair.name)
            } else if coachStrong && hcStrong {
                // Both are strong -> redundant
                redundancies.append(pair.name)
            } else if bothWeak {
                // Both are weak -> shared weakness
                weaknesses.append(pair.name)
            }
        }

        // Determine overall label
        let overallLabel: String
        let overallColor: Color
        if complements.count >= 3 && weaknesses.isEmpty {
            overallLabel = "Excellent Fit"
            overallColor = .green
        } else if complements.count > redundancies.count && weaknesses.count <= 1 {
            overallLabel = "Good Fit"
            overallColor = .green
        } else if redundancies.count > complements.count {
            overallLabel = "Redundant"
            overallColor = Color.accentGold
        } else if weaknesses.count >= 2 {
            overallLabel = "Poor Fit"
            overallColor = .orange
        } else {
            overallLabel = "Neutral"
            overallColor = Color.textSecondary
        }

        return CompatibilityAnalysis(
            complements: complements,
            redundancies: redundancies,
            weaknesses: weaknesses,
            overallLabel: overallLabel,
            overallColor: overallColor
        )
    }

    private func fireCoach() {
        coach.teamID = nil
        dismiss()
    }
}


// MARK: - Preview

#Preview {
    NavigationStack {
        CoachDetailView(coach: Coach(
            firstName: "Bill",
            lastName: "Parcells",
            age: 62,
            role: .headCoach,
            offensiveScheme: .proPassing,
            defensiveScheme: .base43,
            playCalling: 91,
            playerDevelopment: 78,
            reputation: 88,
            adaptability: 72,
            personality: .fieryCompetitor,
            yearsExperience: 20
        ))
    }
    .modelContainer(for: Coach.self, inMemory: true)
}
