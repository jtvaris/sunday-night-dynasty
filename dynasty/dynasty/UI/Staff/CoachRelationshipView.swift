import SwiftUI
import SwiftData

// MARK: - CoachRelationshipView

/// Displays the current HC-GM relationship health when the player is in the `.gm` role.
/// Shows harmony bar, disagreement history, and a deterioration warning when applicable.
struct CoachRelationshipView: View {

    @Bindable var career: Career
    let headCoach: Coach

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            List {
                harmonySection
                disagreementsSection
                preferencesSection
                if isRelationshipDeteriorating {
                    warningSection
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.insetGrouped)
        }
        .navigationTitle("HC-GM Relationship")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    // MARK: - Relationship Data

    private var relationship: CoachRelationshipEngine.HCGMRelationship {
        career.hcGMRelationship
    }

    private var isRelationshipDeteriorating: Bool {
        relationship.harmony < 40 || relationship.publicConflicts >= 2
    }

    // MARK: - Harmony Section

    private var harmonySection: some View {
        Section("Relationship Health") {
            VStack(alignment: .leading, spacing: 12) {

                // Coach identity header
                HStack(spacing: 12) {
                    Text("HC")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.backgroundPrimary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.accentGold, in: RoundedRectangle(cornerRadius: 5))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(headCoach.fullName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                        Text(headCoach.personality.displayName)
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }

                    Spacer()

                    Text("\(relationship.harmony)")
                        .font(.system(size: 28, weight: .bold).monospacedDigit())
                        .foregroundStyle(harmonyColor)
                }

                // Harmony bar
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Harmony")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        Text(harmonyLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(harmonyColor)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.backgroundTertiary)
                                .frame(height: 8)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(harmonyColor)
                                .frame(
                                    width: geo.size.width * CGFloat(relationship.harmony) / 100.0,
                                    height: 8
                                )
                                .animation(.easeInOut(duration: 0.4), value: relationship.harmony)
                        }
                    }
                    .frame(height: 8)
                }
            }
            .padding(.vertical, 6)
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    // MARK: - Disagreements Section

    private var disagreementsSection: some View {
        Section("This Season") {
            LabeledContent("Disagreements") {
                Text("\(relationship.disagreements)")
                    .monospacedDigit()
                    .foregroundStyle(disagreementColor)
            }
            .accessibilityLabel("Disagreements this season, \(relationship.disagreements)")

            LabeledContent("Public Conflicts") {
                HStack(spacing: 4) {
                    if relationship.publicConflicts > 0 {
                        Image(systemName: "exclamationmark.bubble.fill")
                            .font(.caption)
                    }
                    Text("\(relationship.publicConflicts)")
                        .monospacedDigit()
                }
                .foregroundStyle(relationship.publicConflicts > 0 ? Color.danger : Color.textSecondary)
            }
            .accessibilityLabel("Public conflicts this season, \(relationship.publicConflicts)")

            LabeledContent("Owner Concern") {
                Text(ownerConcernLabel)
                    .foregroundStyle(ownerConcernColor)
            }
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    // MARK: - Preferences Section

    private var preferencesSection: some View {
        Section("\(headCoach.firstName)'s Preferences") {
            preferenceRow(
                icon: "arrow.triangle.2.circlepath",
                label: "Scheme Philosophy",
                detail: schemePreferenceDetail,
                concern: headCoach.adaptability < 45
            )

            preferenceRow(
                icon: "person.2.fill",
                label: "Roster Input",
                detail: rosterInputDetail,
                concern: isMeddlingPersonality
            )

            preferenceRow(
                icon: "chart.bar.fill",
                label: "Coaching Style",
                detail: headCoach.personality.displayName,
                concern: false
            )
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    // MARK: - Warning Section

    private var warningSection: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.danger)
                    .font(.title3)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Relationship Deteriorating")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.danger)
                    Text(deteriorationWarningText)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(Color.danger.opacity(0.12))
    }

    // MARK: - Preference Row Helper

    private func preferenceRow(
        icon: String,
        label: String,
        detail: String,
        concern: Bool
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(concern ? Color.warning : Color.accentBlue)
                .frame(width: 20)
            Text(label)
                .foregroundStyle(Color.textPrimary)
            Spacer()
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(concern ? Color.warning : Color.textSecondary)
        }
    }

    // MARK: - Computed Display Helpers

    private var harmonyColor: Color {
        switch relationship.harmony {
        case 75...: return .success
        case 50..<75: return .accentGold
        case 30..<50: return .warning
        default: return .danger
        }
    }

    private var harmonyLabel: String {
        switch relationship.harmony {
        case 80...: return "Strong Partnership"
        case 60..<80: return "Workable Tension"
        case 40..<60: return "Strained"
        case 20..<40: return "Fractured"
        default: return "On the Brink"
        }
    }

    private var disagreementColor: Color {
        switch relationship.disagreements {
        case 0: return .textSecondary
        case 1...2: return .warning
        default: return .danger
        }
    }

    private var ownerConcernLabel: String {
        if relationship.publicConflicts >= 3 || relationship.harmony < 25 {
            return "High"
        } else if relationship.publicConflicts >= 1 || relationship.harmony < 50 {
            return "Moderate"
        } else {
            return "None"
        }
    }

    private var ownerConcernColor: Color {
        switch ownerConcernLabel {
        case "High":     return .danger
        case "Moderate": return .warning
        default:         return .success
        }
    }

    private var schemePreferenceDetail: String {
        if let off = headCoach.offensiveScheme {
            return off.displayName
        } else if let def = headCoach.defensiveScheme {
            return def.displayName
        }
        return headCoach.adaptability >= 60 ? "Flexible" : "No Preference"
    }

    private var rosterInputDetail: String {
        switch headCoach.personality {
        case .loneWolf:        return "High autonomy expected"
        case .fieryCompetitor: return "Opinionated on personnel"
        case .mentor:          return "Collaborative"
        case .quietProfessional, .steadyPerformer: return "Defers to GM"
        default:               return "Moderate input"
        }
    }

    private var isMeddlingPersonality: Bool {
        switch headCoach.personality {
        case .loneWolf, .fieryCompetitor, .dramaQueen: return true
        default: return false
        }
    }

    private var deteriorationWarningText: String {
        if relationship.publicConflicts >= 2 {
            return "Public conflicts between \(headCoach.firstName) and the front office are drawing owner attention. A resolution is needed before this affects the team."
        } else if relationship.harmony < 25 {
            return "The relationship with \(headCoach.firstName) has broken down. Continued disagreements may force a coaching change or damage the franchise's reputation."
        } else {
            return "The HC-GM relationship is under strain. Winning games and avoiding front-office conflicts will help rebuild trust."
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        CoachRelationshipView(
            career: Career(
                playerName: "John Doe",
                role: .gm,
                capMode: .simple
            ),
            headCoach: Coach(
                firstName: "Mike",
                lastName: "Shanahan",
                age: 55,
                role: .headCoach,
                offensiveScheme: .shanahan,
                playCalling: 88,
                playerDevelopment: 72,
                reputation: 84,
                adaptability: 60,
                personality: .fieryCompetitor,
                yearsExperience: 18
            )
        )
    }
    .modelContainer(for: [Career.self, Coach.self], inMemory: true)
}
