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

            GeometryReader { geo in
                Image("BgCoachStadium2")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .opacity(0.2)
            }
            .ignoresSafeArea()

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

    // MARK: - Step Indicator (#98: larger progress bar)

    private var stepIndicator: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("Step \(currentStep) of 2")
                    .font(.callout.weight(.bold))
                    .foregroundStyle(Color.textPrimary)

                Spacer()

                Text(currentStep == 1 ? "Your Career" : "Your Identity")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.surfaceBorder)
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.accentGold)
                        .frame(width: geo.size.width * (currentStep == 1 ? 0.5 : 1.0), height: 6)
                        .animation(.easeInOut(duration: 0.3), value: currentStep)
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    // MARK: - Page 1: Your Career (#97: wider content, more vertical space)

    @ViewBuilder
    private func page1Content(isLandscape: Bool) -> some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 12)

                    VStack(spacing: 24) {
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
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)

                    Spacer(minLength: 16)

                    // Next button
                    nextButton
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
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
                    Spacer(minLength: 12)

                    VStack(spacing: 16) {
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
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)

                    Spacer(minLength: 8)

                    // Bottom buttons — always visible
                    VStack(spacing: 8) {
                        chooseTeamButton
                        backButton
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
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
                    .font(.title3)
                    .foregroundStyle(Color.textPrimary)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.backgroundPrimary)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(showNameError && !isNameValid ? Color.danger : Color.surfaceBorder, lineWidth: 1)
                    )

                if showNameError && !isNameValid {
                    Text("Please enter your name to continue.")
                        .font(.subheadline)
                        .foregroundStyle(Color.danger)
                } else {
                    // #99: larger explanation text with better contrast
                    Text("This is how you'll be known around the league.")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
    }

    // #100, #102: Role section with comparison bullet points
    private var roleSection: some View {
        cardSection(icon: "briefcase.fill", title: "Career Role") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Role", selection: $selectedRole) {
                    Text("General Manager").tag(CareerRole.gm)
                    Text("GM & Head Coach").tag(CareerRole.gmAndHeadCoach)
                }
                .pickerStyle(.segmented)

                // Role comparison
                VStack(alignment: .leading, spacing: 10) {
                    roleComparisonRow(
                        action: "Build roster, trades & draft",
                        gmAvailable: true,
                        gmhcAvailable: true
                    )
                    roleComparisonRow(
                        action: "Free agency & contracts",
                        gmAvailable: true,
                        gmhcAvailable: true
                    )
                    roleComparisonRow(
                        action: "Hire & fire head coach",
                        gmAvailable: true,
                        gmhcAvailable: false
                    )
                    roleComparisonRow(
                        action: "Set offensive/defensive schemes",
                        gmAvailable: false,
                        gmhcAvailable: true
                    )
                    roleComparisonRow(
                        action: "Game-day play calling",
                        gmAvailable: false,
                        gmhcAvailable: true
                    )
                    roleComparisonRow(
                        action: "Manage coaching staff",
                        gmAvailable: false,
                        gmhcAvailable: true
                    )
                }

                Group {
                    switch selectedRole {
                    case .gm:
                        Text("Focus on roster building and let your head coach handle game day.")
                    case .gmAndHeadCoach:
                        Text("Total control over every decision, from the roster to the play sheet.")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
            }
        }
    }

    // #103, #101: Cap mode section with feature checklist
    private var capModeSection: some View {
        cardSection(icon: "dollarsign.circle.fill", title: "Salary Cap Mode") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Salary Cap", selection: $selectedCapMode) {
                    Text("Simple").tag(CapMode.simple)
                    Text("Realistic").tag(CapMode.realistic)
                }
                .pickerStyle(.segmented)

                // Feature checklist comparison
                VStack(alignment: .leading, spacing: 10) {
                    capFeatureRow(feature: "Annual salary cap", simple: true, realistic: true)
                    capFeatureRow(feature: "Signing bonuses", simple: false, realistic: true)
                    capFeatureRow(feature: "Dead cap penalties", simple: false, realistic: true)
                    capFeatureRow(feature: "Contract restructures", simple: false, realistic: true)
                    capFeatureRow(feature: "Franchise tags", simple: false, realistic: true)
                    capFeatureRow(feature: "Cap rollover", simple: false, realistic: true)
                }

                Group {
                    switch selectedCapMode {
                    case .simple:
                        Text("Great for new players. Straightforward salaries, no hidden penalties.")
                    case .realistic:
                        Text("Full NFL cap rules. Every dollar and bonus structure matters.")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
            }
        }
    }

    // #106, #107, #111: Coaching style with gameplay effects and beginner tag
    private var coachingStyleSection: some View {
        cardSection(icon: "gamecontroller.fill", title: "Coaching Style") {
            VStack(spacing: 6) {
                ForEach(CoachingStyle.allCases, id: \.self) { style in
                    CoachingStyleCard(
                        style: style,
                        isSelected: selectedCoachingStyle == style,
                        isRecommended: style == .tactician
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

    // #108, #109, #110, #113: Avatar section with cosmetic label, cleaner headers
    private var avatarSection: some View {
        cardSection(icon: "person.crop.circle.fill", title: "Your Look") {
            VStack(spacing: 6) {
                // #108: Clarify avatar is cosmetic
                Text("Cosmetic only — does not affect gameplay")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.textTertiary)

                AvatarSelectionView(selectedAvatarID: $selectedAvatarID, avatarSize: 60)
                    .padding(.vertical, 2)

                // #105: larger avatar name, #110: remove confusing "outside -> Male coach" text
                if let avatar = CoachAvatars.avatar(for: selectedAvatarID) {
                    Text("\"\(avatar.name)\"")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                }
            }
        }
    }

    // MARK: - Comparison Helpers

    // #102: Role comparison row
    private func roleComparisonRow(action: String, gmAvailable: Bool, gmhcAvailable: Bool) -> some View {
        HStack(spacing: 8) {
            Text(action)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 16) {
                // GM column
                Image(systemName: gmAvailable ? "checkmark.circle.fill" : "minus.circle")
                    .font(.caption)
                    .foregroundStyle(gmAvailable ? Color.success : Color.textTertiary)
                    .frame(width: 30)

                // GM&HC column
                Image(systemName: gmhcAvailable ? "checkmark.circle.fill" : "minus.circle")
                    .font(.caption)
                    .foregroundStyle(gmhcAvailable ? Color.success : Color.textTertiary)
                    .frame(width: 30)
            }
        }
    }

    // #103: Cap feature comparison row
    private func capFeatureRow(feature: String, simple: Bool, realistic: Bool) -> some View {
        HStack(spacing: 8) {
            Text(feature)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 16) {
                Image(systemName: simple ? "checkmark.circle.fill" : "minus.circle")
                    .font(.caption)
                    .foregroundStyle(simple ? Color.success : Color.textTertiary)
                    .frame(width: 30)

                Image(systemName: realistic ? "checkmark.circle.fill" : "minus.circle")
                    .font(.caption)
                    .foregroundStyle(realistic ? Color.success : Color.textTertiary)
                    .frame(width: 30)
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentGold)
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.accentGold)
            }

            content()
        }
        .padding(20)
        .cardBackground()
    }
}

// MARK: - Coaching Style Card (#104, #106, #107, #111)

private struct CoachingStyleCard: View {
    let style: CoachingStyle
    let isSelected: Bool
    var isRecommended: Bool = false

    /// #111: Gameplay effect description for each style
    private var gameplayEffect: String {
        switch style {
        case .tactician:
            return "Better play-calling in close games"
        case .playersCoach:
            return "Faster player progression each season"
        case .disciplinarian:
            return "Fewer penalties and turnovers"
        case .innovator:
            return "Faster scheme adaptation mid-season"
        case .motivator:
            return "Bigger morale boosts from wins"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(isSelected ? Color.accentGold.opacity(0.2) : Color.backgroundSecondary)
                    .frame(width: 36, height: 36)
                Image(systemName: style.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentGold : Color.textSecondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(style.displayName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(isSelected ? Color.accentGold : Color.textPrimary)

                    // #107: Beginner guidance tag
                    if isRecommended {
                        Text("Recommended")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.backgroundPrimary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(Color.accentGold)
                            )
                    }
                }

                Text(style.description)
                    .font(.caption2)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)

                // #111: Gameplay effect line
                Text(gameplayEffect)
                    .font(.system(size: 9, weight: .medium).italic())
                    .foregroundStyle(isSelected ? Color.accentGold.opacity(0.7) : Color.textTertiary)
            }

            Spacer(minLength: 4)

            // #104: Wider bonus area to prevent truncation
            VStack(spacing: 2) {
                Text("+\(style.bonusValue)")
                    .font(.system(size: 14, weight: .bold).monospacedDigit())
                    .foregroundStyle(isSelected ? Color.accentGold : Color.textTertiary)
                Text(style.bonusAttribute)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentGold.opacity(0.8) : Color.textTertiary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(width: 75)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
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
