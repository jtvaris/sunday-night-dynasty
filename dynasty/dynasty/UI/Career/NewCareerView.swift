import SwiftUI
import SwiftData

struct NewCareerView: View {

    @State private var playerName: String = ""
    @State private var selectedAvatarID: String = "coach_m1"
    @State private var selectedRole: CareerRole = .gmAndHeadCoach
    @State private var selectedCapMode: CapMode = .realistic

    private var isNameValid: Bool {
        !playerName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    // MARK: - Player Info Card
                    cardSection(icon: "person.fill", title: "Player Name") {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Enter your name", text: $playerName)
                                .textInputAutocapitalization(.words)
                                .autocorrectionDisabled()
                                .font(.body)
                                .foregroundStyle(Color.textPrimary)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.backgroundPrimary)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                                )

                            Text("This is how you'll be known around the league.")
                                .font(.caption)
                                .foregroundStyle(Color.textTertiary)
                        }
                    }

                    // MARK: - Avatar Selection Card
                    cardSection(icon: "person.crop.circle.fill", title: "Your Look") {
                        VStack(spacing: 12) {
                            AvatarSelectionView(selectedAvatarID: $selectedAvatarID, avatarSize: 96)
                                .padding(.vertical, 4)

                            if let avatar = CoachAvatars.avatar(for: selectedAvatarID) {
                                Text("\"\(avatar.name)\" — \(avatar.gender == .male ? "Male" : "Female") coach")
                                    .font(.caption)
                                    .foregroundStyle(Color.textTertiary)
                            }
                        }
                    }

                    // MARK: - Role Selection Card
                    cardSection(icon: "briefcase.fill", title: "Career Role") {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Role", selection: $selectedRole) {
                                Text("General Manager").tag(CareerRole.gm)
                                Text("GM & Head Coach").tag(CareerRole.gmAndHeadCoach)
                            }
                            .pickerStyle(.segmented)

                            Group {
                                switch selectedRole {
                                case .gm:
                                    Text("Focus on roster building, trades, the draft, and free agency. You'll hire a head coach to handle game-day decisions.")
                                case .gmAndHeadCoach:
                                    Text("Full control. Manage the roster and make coaching decisions including scheme selection and game-day strategy.")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                        }
                    }

                    // MARK: - Cap Mode Card
                    cardSection(icon: "dollarsign.circle.fill", title: "Salary Cap Mode") {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Salary Cap", selection: $selectedCapMode) {
                                Text("Simple").tag(CapMode.simple)
                                Text("Realistic").tag(CapMode.realistic)
                            }
                            .pickerStyle(.segmented)

                            Group {
                                switch selectedCapMode {
                                case .simple:
                                    Text("Streamlined cap management. Contracts are straightforward annual salaries with no dead cap or restructuring.")
                                case .realistic:
                                    Text("Full NFL salary cap rules including signing bonuses, dead cap, restructures, franchise tags, and cap rollover.")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                        }
                    }

                    // MARK: - Choose Your Team CTA
                    NavigationLink(destination: TeamSelectionView(
                        playerName: playerName,
                        avatarID: selectedAvatarID,
                        selectedRole: selectedRole,
                        selectedCapMode: selectedCapMode
                    )) {
                        HStack(spacing: 10) {
                            Image(systemName: "sportscourt.fill")
                                .font(.body.weight(.semibold))
                            Text("Choose Your Team")
                                .font(.headline)
                        }
                        .foregroundStyle(isNameValid ? Color.backgroundPrimary : Color.textTertiary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(isNameValid ? Color.accentGold : Color.backgroundTertiary)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(isNameValid ? Color.accentGold.opacity(0.6) : Color.surfaceBorder, lineWidth: 1)
                        )
                    }
                    .disabled(!isNameValid)
                    .padding(.top, 4)
                }
                .padding(16)
                .frame(maxWidth: 800)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("New Career")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            // Style segmented controls for dark theme
            UISegmentedControl.appearance().selectedSegmentTintColor = UIColor(Color.accentGold)
            UISegmentedControl.appearance().setTitleTextAttributes(
                [.foregroundColor: UIColor(Color.backgroundPrimary)], for: .selected
            )
            UISegmentedControl.appearance().setTitleTextAttributes(
                [.foregroundColor: UIColor(Color.textSecondary)], for: .normal
            )
            UISegmentedControl.appearance().backgroundColor = UIColor(Color.backgroundPrimary)
        }
    }

    // MARK: - Card Section Builder

    @ViewBuilder
    private func cardSection<Content: View>(
        icon: String,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header with gold icon
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentGold)
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.accentGold)
            }

            content()
        }
        .padding(16)
        .cardBackground()
    }
}

#Preview {
    NavigationStack {
        NewCareerView()
    }
    .modelContainer(for: Career.self, inMemory: true)
}
