import SwiftUI
import SwiftData

struct CoachDetailView: View {

    let coach: Coach
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var allCoaches: [Coach]
    @Query private var allCareers: [Career]

    @State private var showFireConfirmation = false
    @State private var showExtendAlert = false
    @State private var showPromoteSheet = false
    @State private var showDemoteAlert = false
    @State private var selectedPromotionRole: CoachRole?
    @State private var showPromoteConfirmation = false

    /// Available promotion targets, filtered by career role constraints.
    private var availablePromotionTargets: [CoachRole] {
        var targets = coach.role.promotionTargets
        // If promoting to HC, only allow if career role is .gm (not .gmAndHeadCoach)
        if let career = career, career.role == .gmAndHeadCoach {
            targets = targets.filter { $0 != .headCoach }
        }
        return targets
    }

    /// Coach overall rating (average of 12 attributes).
    private var coachOverallRating: Int {
        let sum = coach.playCalling + coach.playerDevelopment + coach.gamePlanning
            + coach.scoutingAbility + coach.recruiting + coach.motivation
            + coach.discipline + coach.adaptability + coach.mediaHandling
            + coach.contractNegotiation + coach.moraleInfluence + coach.reputation
        return sum / 12
    }

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
                developmentSection
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
        // Fix #53: Extend contract alert
        .alert("Extend \(coach.fullName)'s Contract?", isPresented: $showExtendAlert) {
            Button("Extend 2 Years") {
                extendContract()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will offer \(coach.firstName) a 2-year contract extension at their current salary of $\(coach.salary)K/yr.")
        }
        // Promote: role picker sheet
        .sheet(isPresented: $showPromoteSheet) {
            promoteRolePickerSheet
        }
        // Promote: confirmation alert after role selection
        .alert("Promote \(coach.fullName)?", isPresented: $showPromoteConfirmation) {
            if let targetRole = selectedPromotionRole {
                Button("Promote to \(targetRole.displayName)") {
                    promoteCoach(to: targetRole)
                }
            }
            Button("Cancel", role: .cancel) {
                selectedPromotionRole = nil
            }
        } message: {
            if let targetRole = selectedPromotionRole {
                let newSalary = Int(Double(coach.salary) * 1.2)
                Text("This will promote \(coach.firstName) from \(coach.role.displayName) to \(targetRole.displayName). Salary will increase to $\(newSalary)K/yr.")
            }
        }
        // Demote: confirmation alert
        .alert("Demote \(coach.fullName)?", isPresented: $showDemoteAlert) {
            Button("Demote", role: .destructive) {
                demoteCoach()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Demoting will reduce morale and reputation by 10. Continue?")
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

    // MARK: - Development Section

    private var developmentSection: some View {
        Section("Development") {
            // Fuzzy potential label
            let label = coach.potentialLabel(seasonsOnTeam: 2) // TODO: calculate actual seasons
            LabeledContent("Potential") {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(potentialLabelColor(label))
            }

            // Trajectory
            LabeledContent("Trajectory") {
                let trajectory = coachTrajectory
                Text(trajectory.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(trajectory.color)
            }

            // Attribute ceiling
            LabeledContent("Attribute Ceiling") {
                Text("\(coach.attributeCeiling)")
                    .monospacedDigit()
                    .foregroundStyle(Color.forRating(coach.attributeCeiling))
            }

            // Adjustment period
            if coach.isInAdjustmentPeriod {
                LabeledContent("Status") {
                    Text("Adjusting to Role")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.orange)
                }
            }

            // Mentorship origin
            if coach.mentorCoachID != nil, let origin = coach.mentorshipOrigin {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mentorship")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                    Text(origin)
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    /// Color for the fuzzy potential label.
    private func potentialLabelColor(_ label: String) -> Color {
        switch label {
        case "Elite Ceiling":   return Color.accentGold
        case "High Ceiling":    return .green
        case "Solid Ceiling":   return Color.accentBlue
        case "Limited Upside":  return .orange
        case "Low Ceiling":     return .red
        default:                return Color.textSecondary
        }
    }

    /// Trajectory based on age and rating vs ceiling.
    private var coachTrajectory: (label: String, color: Color) {
        if coach.age >= 55 {
            return ("Declining", .red)
        } else if coach.age < 50 && coachOverallRating < coach.attributeCeiling - 5 {
            return ("Improving", .green)
        } else {
            return ("Plateaued", .orange)
        }
    }

    // MARK: - Promote Role Picker Sheet

    private var promoteRolePickerSheet: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()

                List {
                    Section("Select New Role") {
                        ForEach(availablePromotionTargets, id: \.self) { targetRole in
                            Button {
                                selectedPromotionRole = targetRole
                                showPromoteSheet = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    showPromoteConfirmation = true
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Text(targetRole.abbreviation)
                                        .font(.system(size: 12, weight: .black))
                                        .foregroundStyle(Color.backgroundPrimary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.accentGold, in: RoundedRectangle(cornerRadius: 4))

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(targetRole.displayName)
                                            .font(.subheadline.weight(.bold))
                                            .foregroundStyle(Color.textPrimary)
                                        let newSalary = Int(Double(coach.salary) * 1.2)
                                        Text("Salary: $\(coach.salary)K → $\(newSalary)K/yr")
                                            .font(.caption)
                                            .foregroundStyle(Color.textSecondary)
                                    }

                                    Spacer()

                                    Image(systemName: "arrow.up.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(Color.accentBlue)
                                }
                            }
                        }
                    }
                    .listRowBackground(Color.backgroundSecondary)
                }
                .scrollContentBackground(.hidden)
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Promote \(coach.firstName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showPromoteSheet = false }
                }
            }
        }
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

    // MARK: - Management Actions Section (Fix #53)

    private var destructiveSection: some View {
        Section("Management") {
            // Extend Contract
            Button {
                showExtendAlert = true
            } label: {
                HStack {
                    Spacer()
                    Label("Extend Contract", systemImage: "doc.text.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentGold)
                    Spacer()
                }
            }

            // Promote (if applicable)
            if !availablePromotionTargets.isEmpty {
                Button {
                    if availablePromotionTargets.count == 1 {
                        // Single target: skip sheet, go straight to confirmation
                        selectedPromotionRole = availablePromotionTargets.first
                        showPromoteConfirmation = true
                    } else {
                        showPromoteSheet = true
                    }
                } label: {
                    HStack {
                        Spacer()
                        Label("Promote", systemImage: "arrow.up.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.accentBlue)
                        Spacer()
                    }
                }
            }

            // Demote (if applicable)
            if !coach.role.demotionTargets.isEmpty {
                Button {
                    showDemoteAlert = true
                } label: {
                    HStack {
                        Spacer()
                        Label("Demote", systemImage: "arrow.down.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.orange)
                        Spacer()
                    }
                }
            }

            // Fire Coach
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

    /// Fix #64: Color-codes attribute values like Player Detail (green 80+, gold 70+, orange 60+, red below).
    private func attributeColor(_ value: Int) -> Color {
        Color.forRating(value)
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

    /// Extend the coach's contract (placeholder: just saves context to confirm action).
    private func extendContract() {
        // TODO: Implement full contract length tracking. For now, save context to acknowledge.
        try? modelContext.save()
    }

    /// Promote the coach to the selected target role.
    private func promoteCoach(to targetRole: CoachRole) {
        coach.role = targetRole
        // Salary bump for promotion (~20%)
        coach.salary = Int(Double(coach.salary) * 1.2)
        // Mark as promoted this season (triggers adjustment period)
        coach.promotedInSeason = career?.currentSeason ?? 1
        try? modelContext.save()
        selectedPromotionRole = nil
    }

    /// Demote the coach to the first available demotion target.
    private func demoteCoach() {
        guard let targetRole = coach.role.demotionTargets.first else { return }
        coach.role = targetRole
        // Reduce reputation by 10
        coach.reputation = max(1, coach.reputation - 10)
        try? modelContext.save()
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
