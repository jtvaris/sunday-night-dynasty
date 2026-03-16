import SwiftUI
import SwiftData

struct CoachDetailView: View {

    let coach: Coach
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showFireConfirmation = false

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            List {
                overviewSection
                attributesSection
                personalitySection
                schemeSection
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
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    // MARK: - Attributes Section

    private var attributesSection: some View {
        Section("Coaching Attributes") {
            AttributeRow(name: "Play Calling",        value: coach.playCalling)
            AttributeRow(name: "Player Development",  value: coach.playerDevelopment)
            AttributeRow(name: "Reputation",          value: coach.reputation)
            AttributeRow(name: "Adaptability",        value: coach.adaptability)
        }
        .listRowBackground(Color.backgroundSecondary)
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
