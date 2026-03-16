import SwiftUI
import SwiftData

struct HireCoachView: View {

    let role: CoachRole
    let teamID: UUID

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var candidates: [Coach] = []
    @State private var hiredCoachID: UUID?

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            List {
                Section {
                    ForEach(candidates) { candidate in
                        CandidateRowView(
                            candidate: candidate,
                            isHired: hiredCoachID == candidate.id
                        ) {
                            hire(candidate)
                        }
                    }
                } header: {
                    Text("Available Candidates")
                } footer: {
                    Text("Select a candidate to add them to your coaching staff.")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }
                .listRowBackground(Color.backgroundSecondary)
            }
            .scrollContentBackground(.hidden)
            .listStyle(.insetGrouped)
        }
        .navigationTitle("Hire \(role.displayName)")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            if candidates.isEmpty {
                candidates = CoachCandidateGenerator.generateCandidates(for: role, count: 5)
            }
        }
    }

    // MARK: - Hire Action

    private func hire(_ candidate: Coach) {
        // Remove any existing coach with the same role on this team
        let descriptor = FetchDescriptor<Coach>(
            predicate: #Predicate { $0.teamID == teamID }
        )
        if let existing = try? modelContext.fetch(descriptor) {
            existing.filter { $0.role == role }.forEach { modelContext.delete($0) }
        }

        candidate.teamID = teamID
        modelContext.insert(candidate)
        hiredCoachID = candidate.id

        // Brief delay so the user sees the hire confirmation, then dismiss
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            dismiss()
        }
    }
}

// MARK: - Candidate Row

private struct CandidateRowView: View {
    let candidate: Coach
    let isHired: Bool
    let onHire: () -> Void

    private var keyAttribute: (name: String, value: Int) {
        switch candidate.role {
        case .headCoach, .offensiveCoordinator, .defensiveCoordinator, .specialTeamsCoordinator:
            return ("Play Calling", candidate.playCalling)
        default:
            return ("Development", candidate.playerDevelopment)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Top row: name + hire button
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(candidate.fullName)
                        .font(.headline)
                        .foregroundStyle(Color.textPrimary)

                    HStack(spacing: 6) {
                        Text("Age \(candidate.age)")
                        Text("·")
                        Text("\(candidate.yearsExperience) yr\(candidate.yearsExperience == 1 ? "" : "s") exp")
                    }
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                }

                Spacer()

                Button(action: onHire) {
                    if isHired {
                        Label("Hired", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.success)
                    } else {
                        Text("Hire")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color.backgroundPrimary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.accentGold, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .disabled(isHired)
                .animation(.easeInOut(duration: 0.2), value: isHired)
            }

            // Attributes grid
            HStack(spacing: 0) {
                attributeCell(label: keyAttribute.name, value: keyAttribute.value)
                attributeCell(label: "Reputation",   value: candidate.reputation)
                attributeCell(label: "Adaptability", value: candidate.adaptability)
            }

            // Scheme tags
            HStack(spacing: 6) {
                if let off = candidate.offensiveScheme {
                    schemeTag(off.displayName, color: .accentBlue)
                }
                if let def = candidate.defensiveScheme {
                    schemeTag(def.displayName, color: .danger)
                }
                schemeTag(candidate.personality.displayName, color: .backgroundTertiary)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(candidate.fullName), age \(candidate.age), \(candidate.yearsExperience) years experience")
    }

    private func attributeCell(label: String, value: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 18, weight: .bold).monospacedDigit())
                .foregroundStyle(Color.forRating(value))
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Color.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private func schemeTag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Color.textSecondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(color.opacity(0.3), lineWidth: 0.5)
            )
    }
}

// MARK: - Coach Candidate Generator

enum CoachCandidateGenerator {

    private static let firstNames = [
        "Mike", "Bill", "Andy", "Sean", "Kyle", "Dan", "Matt", "Ron",
        "Tom", "Pete", "John", "Dave", "Greg", "Kevin", "Brian", "Frank",
        "Ray", "Jim", "Paul", "Tony", "Steve", "Wade", "Rick", "Eric"
    ]

    private static let lastNames = [
        "Johnson", "Williams", "Brown", "Davis", "Wilson", "Anderson",
        "Taylor", "Thomas", "Jackson", "Harris", "Martin", "Thompson",
        "White", "Lopez", "Lee", "Walker", "Robinson", "Lewis", "Clark",
        "Young", "Hall", "Allen", "Wright", "Mitchell", "Carter", "Turner"
    ]

    static func generateCandidates(for role: CoachRole, count: Int = 5) -> [Coach] {
        (0..<count).map { _ in generateCandidate(for: role) }
    }

    private static func generateCandidate(for role: CoachRole) -> Coach {
        let firstName = firstNames.randomElement()!
        let lastName  = lastNames.randomElement()!

        // Experience and age vary by role prestige
        let baseExp: Int
        let ageFloor: Int
        switch role {
        case .headCoach:
            baseExp  = Int.random(in: 10...25)
            ageFloor = 42
        case .offensiveCoordinator, .defensiveCoordinator:
            baseExp  = Int.random(in: 6...18)
            ageFloor = 36
        case .specialTeamsCoordinator:
            baseExp  = Int.random(in: 4...15)
            ageFloor = 34
        default:
            baseExp  = Int.random(in: 2...12)
            ageFloor = 30
        }

        let yearsExperience = baseExp
        let age = ageFloor + Int.random(in: 0...15)

        // Attribute generation — skewed toward role's primary skill
        let playCalling: Int
        let playerDev: Int

        switch role {
        case .headCoach:
            playCalling = Int.random(in: 60...92)
            playerDev   = Int.random(in: 55...88)
        case .offensiveCoordinator, .defensiveCoordinator, .specialTeamsCoordinator:
            playCalling = Int.random(in: 65...96)
            playerDev   = Int.random(in: 45...80)
        default:
            playCalling = Int.random(in: 40...75)
            playerDev   = Int.random(in: 60...95)
        }

        let reputation  = Int.random(in: 40...90)
        let adaptability = Int.random(in: 40...85)

        // Scheme assignment
        let offScheme: OffensiveScheme?
        let defScheme: DefensiveScheme?

        switch role {
        case .headCoach:
            offScheme = OffensiveScheme.allCases.randomElement()
            defScheme = DefensiveScheme.allCases.randomElement()
        case .offensiveCoordinator, .qbCoach, .rbCoach, .wrCoach, .olCoach:
            offScheme = OffensiveScheme.allCases.randomElement()
            defScheme = nil
        case .defensiveCoordinator, .dlCoach, .lbCoach, .dbCoach:
            offScheme = nil
            defScheme = DefensiveScheme.allCases.randomElement()
        default:
            offScheme = nil
            defScheme = nil
        }

        let personality = PersonalityArchetype.allCases.randomElement()!

        return Coach(
            firstName: firstName,
            lastName: lastName,
            age: age,
            role: role,
            offensiveScheme: offScheme,
            defensiveScheme: defScheme,
            playCalling: playCalling,
            playerDevelopment: playerDev,
            reputation: reputation,
            adaptability: adaptability,
            personality: personality,
            teamID: nil,
            yearsExperience: yearsExperience
        )
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        HireCoachView(role: .offensiveCoordinator, teamID: UUID())
    }
    .modelContainer(for: Coach.self, inMemory: true)
}
