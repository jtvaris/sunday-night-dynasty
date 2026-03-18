import SwiftUI
import SwiftData

struct NewCareerView: View {

    @State private var playerName: String = ""
    @State private var selectedAvatarID: String = "coach_m1"
    @State private var selectedCoachingStyle: CoachingStyle = .tactician
    @State private var selectedRole: CareerRole = .gmAndHeadCoach
    @State private var selectedCapMode: CapMode = .realistic
    @State private var currentStep = 1
    @State private var showNameError = false

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isLandscape: Bool {
        verticalSizeClass == .compact
    }

    private var isNameValid: Bool {
        !playerName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            Image("BgCoachStadium2")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()
                .opacity(0.2)

            LinearGradient(
                colors: [Color.backgroundPrimary.opacity(0.85), Color.backgroundPrimary.opacity(0.5), Color.backgroundPrimary.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - Step Indicator
                stepIndicator

                // MARK: - Page Content
                if currentStep == 1 {
                    page1Content(isLandscape: isLandscape)
                } else {
                    page2Content(isLandscape: isLandscape)
                }
            }
        }
        .navigationTitle(currentStep == 1 ? "Your Career" : "Your Identity")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
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

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            Text("Step \(currentStep) of 2")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)

            HStack(spacing: 6) {
                Circle()
                    .fill(Color.accentGold)
                    .frame(width: 8, height: 8)
                Circle()
                    .fill(currentStep == 2 ? Color.accentGold : Color.backgroundTertiary)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Page 1: Your Career

    @ViewBuilder
    private func page1Content(isLandscape: Bool) -> some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 20)

                    VStack(spacing: 20) {
                        if isLandscape {
                            nameSection
                            HStack(alignment: .top, spacing: 16) {
                                roleSection
                                capModeSection
                            }
                        } else {
                            nameSection
                            roleSection
                            capModeSection
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: 800)
                    .frame(maxWidth: .infinity)

                    Spacer(minLength: 20)

                    // Next button
                    nextButton
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                        .frame(maxWidth: 800)
                        .frame(maxWidth: .infinity)
                }
                .frame(minHeight: geometry.size.height)
            }
        }
    }

    // MARK: - Page 2: Your Identity

    @ViewBuilder
    private func page2Content(isLandscape: Bool) -> some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 20)

                    VStack(spacing: 20) {
                        if isLandscape {
                            HStack(alignment: .top, spacing: 16) {
                                coachingStyleSection
                                avatarSection
                            }
                        } else {
                            coachingStyleSection
                            avatarSection
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: 800)
                    .frame(maxWidth: .infinity)

                    Spacer(minLength: 20)

                    // Bottom buttons
                    VStack(spacing: 12) {
                        chooseTeamButton
                        backButton
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .frame(maxWidth: 800)
                    .frame(maxWidth: .infinity)
                }
                .frame(minHeight: geometry.size.height)
            }
        }
    }

    // MARK: - Section Views

    private var nameSection: some View {
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
                            .strokeBorder(showNameError && !isNameValid ? Color.red : Color.surfaceBorder, lineWidth: 1)
                    )

                if showNameError && !isNameValid {
                    Text("Please enter your name to continue.")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    Text("This is how you'll be known around the league.")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }
            }
        }
    }

    private var roleSection: some View {
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
                        Text("Focus on roster building, trades, the draft, and free agency. Hire a head coach for schemes and game-day playcalling.")
                    case .gmAndHeadCoach:
                        Text("Total control. Build your roster AND call the plays — schemes, game-day strategy, and staff decisions are all yours.")
                    }
                }
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
            }
        }
    }

    private var capModeSection: some View {
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
                        Text("Straightforward annual salaries. No dead cap, no restructuring, no rollover — just build your team.")
                    case .realistic:
                        Text("Full NFL rules: signing bonuses, dead cap, restructures, franchise tags, and cap rollover. Every dollar counts.")
                    }
                }
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
            }
        }
    }

    private var coachingStyleSection: some View {
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
    }

    private var avatarSection: some View {
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
    }

    // MARK: - Buttons

    private var nextButton: some View {
        Button {
            if isNameValid {
                withAnimation(.easeInOut(duration: 0.3)) {
                    currentStep = 2
                    showNameError = false
                }
            } else {
                showNameError = true
            }
        } label: {
            HStack(spacing: 10) {
                Text("Next")
                    .font(.headline)
                Image(systemName: "arrow.right")
                    .font(.body.weight(.semibold))
            }
            .foregroundStyle(Color.backgroundPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accentGold)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentGold.opacity(0.6), lineWidth: 1)
            )
        }
        .padding(.top, 4)
    }

    private var chooseTeamButton: some View {
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
                Image(systemName: "arrow.right")
                    .font(.body.weight(.semibold))
            }
            .foregroundStyle(Color.backgroundPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accentGold)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentGold.opacity(0.6), lineWidth: 1)
            )
        }
        .padding(.top, 4)
    }

    private var backButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.3)) {
                currentStep = 1
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.left")
                    .font(.body.weight(.semibold))
                Text("Back")
                    .font(.headline)
            }
            .foregroundStyle(Color.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
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
            ZStack {
                Circle()
                    .fill(isSelected ? Color.accentGold.opacity(0.2) : Color.backgroundTertiary)
                    .frame(width: 44, height: 44)
                Image(systemName: style.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentGold : Color.textSecondary)
            }

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

            VStack(spacing: 2) {
                Text("+\(style.bonusValue)")
                    .font(.system(size: 14, weight: .bold).monospacedDigit())
                    .foregroundStyle(isSelected ? Color.accentGold : Color.textTertiary)
                Text(style.bonusAttribute)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentGold.opacity(0.8) : Color.textTertiary)
                    .lineLimit(1)
            }
            .frame(width: 70)
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
