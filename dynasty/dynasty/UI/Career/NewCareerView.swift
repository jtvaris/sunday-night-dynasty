import SwiftUI
import SwiftData

struct NewCareerView: View {

    @State private var playerName: String = ""
    @State private var selectedAvatarID: String = "coach_m1"
    @State private var selectedCoachingStyle: CoachingStyle = .tactician
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

                    // MARK: - Coaching Style Card
                    cardSection(icon: "gamecontroller.fill", title: "Coaching Style") {
                        VStack(spacing: 10) {
                            ForEach(CoachingStyle.allCases, id: \.self) { style in
                                CoachingStyleCard(
                                    style: style,
                                    isSelected: selectedCoachingStyle == style
                                )
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.3)) {
                                        selectedCoachingStyle = style
                                    }
                                }
                            }
                        }
                    }

                    // MARK: - Avatar Selection Card
                    cardSection(icon: "person.crop.circle.fill", title: "Your Look") {
                        VStack(spacing: 12) {
                            AvatarSelectionView(selectedAvatarID: $selectedAvatarID, avatarSize: 72)
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
                        coachingStyle: selectedCoachingStyle,
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

// MARK: - Coaching Style Card

private struct CoachingStyleCard: View {
    let style: CoachingStyle
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            // Icon
            ZStack {
                Circle()
                    .fill(isSelected ? Color.accentGold.opacity(0.2) : Color.backgroundTertiary)
                    .frame(width: 44, height: 44)
                Image(systemName: style.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentGold : Color.textSecondary)
            }

            // Text
            VStack(alignment: .leading, spacing: 3) {
                Text(style.displayName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(isSelected ? Color.accentGold : Color.textPrimary)

                Text(style.description)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 4)

            // Bonus badge
            VStack(spacing: 2) {
                Text("+\(style.bonusValue)")
                    .font(.system(size: 14, weight: .bold).monospacedDigit())
                    .foregroundStyle(isSelected ? Color.accentGold : Color.textTertiary)
                Text(style.bonusAttribute)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentGold.opacity(0.8) : Color.textTertiary)
                    .lineLimit(1)
            }
            .frame(width: 60)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.accentGold.opacity(0.08) : Color.backgroundPrimary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isSelected ? Color.accentGold : Color.surfaceBorder,
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(style.displayName), \(style.description), plus \(style.bonusValue) \(style.bonusAttribute)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview {
    NavigationStack {
        NewCareerView()
    }
    .modelContainer(for: Career.self, inMemory: true)
}
