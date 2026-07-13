import SwiftUI
import SwiftData

struct NewCareerView: View {

    /// Local-only UI flow mode. Quick Start pre-fills sensible defaults and
    /// jumps straight to team selection; Custom League keeps the full 2-step flow.
    private enum FlowMode: Hashable {
        case quickStart
        case custom
    }

    /// Local-only cap selection mirroring the persisted `CapMode` enum. Each
    /// case maps 1:1 onto a `CapMode` value; sandbox flows through to the
    /// engine-side `CapMode.sandbox` short-circuits.
    private enum CapModeSelection: Hashable {
        case simple
        case realistic
        case sandbox

        var capMode: CapMode {
            switch self {
            case .simple:    return .simple
            case .realistic: return .realistic
            case .sandbox:   return .sandbox
            }
        }
    }

    @State private var flowMode: FlowMode = .quickStart
    @State private var playerName: String = ""
    @State private var selectedAvatarID: String = "coach_m1"
    @State private var selectedCoachingStyle: CoachingStyle = .tactician
    @State private var selectedRole: CareerRole = .gmAndHeadCoach
    @State private var capSelection: CapModeSelection = .realistic
    @State private var currentStep = 1
    @State private var showNameError = false

    // R40 — Game mode / scenario card + custom league settings.
    @State private var selectedSetup: CareerSetup = .standard
    @State private var injuryFrequency: InjuryFrequency = .normal

    // R37 — "What is this?" explainer toggle for modes vs. scenarios.
    @State private var showSetupExplainer = false

    @State private var viewWidth: CGFloat = 0

    /// iPad always reports .regular for both size classes, so use actual width
    private var isLandscape: Bool { viewWidth > 900 }

    private var isNameValid: Bool {
        playerName.trimmingCharacters(in: .whitespaces).count >= 2
    }

    /// Quick Start collapses to a single step; Custom League runs the full
    /// three-step flow (Career → Game Mode → Identity).
    private var totalSteps: Int { flowMode == .quickStart ? 1 : 3 }

    /// Step titles for the indicator and the navigation bar.
    private func stepTitle(_ step: Int) -> String {
        switch step {
        case 1:  return "Your Career"
        case 2:  return "Game Mode"
        default: return "Your Identity"
        }
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

                // MARK: - Flow Mode Toggle (Quick Start vs Custom League)
                if currentStep == 1 {
                    flowModeToggle
                }

                // MARK: - Page Content
                switch currentStep {
                case 1:  page1Content(isLandscape: isLandscape)
                case 2:  gameModeContent(isLandscape: isLandscape)
                default: identityContent(isLandscape: isLandscape)
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            viewWidth = newWidth
        }
        .navigationTitle(stepTitle(currentStep))
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            UISegmentedControl.appearance().selectedSegmentTintColor = UIColor(Color.accentBlue)
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
                Text("Step \(currentStep) of \(totalSteps)")
                    .font(.callout.weight(.bold))
                    .foregroundStyle(Color.textPrimary)

                Spacer()

                Text(stepTitle(currentStep))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.surfaceBorder)
                        .frame(height: 6)

                    let progress: CGFloat = {
                        if totalSteps == 1 { return 1.0 }
                        return CGFloat(currentStep) / CGFloat(totalSteps)
                    }()

                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.accentBlue)
                        .frame(width: geo.size.width * progress, height: 6)
                        .animation(.easeInOut(duration: 0.3), value: currentStep)
                        .animation(.easeInOut(duration: 0.3), value: totalSteps)
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    // MARK: - Flow Mode Toggle (Quick Start vs Custom League)

    private var flowModeToggle: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Flow", selection: $flowMode) {
                Text("Quick Start").tag(FlowMode.quickStart)
                Text("Custom League").tag(FlowMode.custom)
            }
            .pickerStyle(.segmented)
            .onChange(of: flowMode) { _, newValue in
                if newValue == .quickStart {
                    // Pre-fill sensible defaults so the team-selection screen
                    // gets a coherent setup straight out of the gate.
                    selectedRole = .gmAndHeadCoach
                    capSelection = .realistic
                    selectedCoachingStyle = .tactician
                    selectedSetup = .standard
                    injuryFrequency = .normal
                }
            }

            Text(flowMode == .quickStart
                 ? "Jump straight in with sensible defaults: GM & Head Coach, Realistic cap, standard mode, Tactician style."
                 : "Tailor everything: role, cap rules, game mode or scenario, league settings, coaching style, and avatar.")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    // MARK: - Page 1: Your Career (#97: wider content, more vertical space)

    @ViewBuilder
    private func page1Content(isLandscape: Bool) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 24) {
                    if flowMode == .quickStart {
                        // Quick Start: only the name section is needed; defaults
                        // cover the rest of the configuration surface.
                        nameSection
                    } else if isLandscape {
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

                // Action button: Quick Start jumps straight to team selection,
                // Custom League advances to Step 2 (Your Identity).
                Group {
                    if flowMode == .quickStart {
                        quickStartChooseTeamButton
                    } else {
                        nextButton
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Page 2: Game Mode & League Settings (R40)

    @ViewBuilder
    private func gameModeContent(isLandscape: Bool) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 16) {
                    if isLandscape {
                        HStack(alignment: .top, spacing: 16) {
                            gameModeSection
                            leagueSettingsSection
                        }
                    } else {
                        gameModeSection
                        leagueSettingsSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)

                VStack(spacing: 8) {
                    nextToIdentityButton
                    backButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Page 3: Your Identity

    @ViewBuilder
    private func identityContent(isLandscape: Bool) -> some View {
        ScrollView {
            VStack(spacing: 0) {
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

                // Bottom buttons
                VStack(spacing: 8) {
                    chooseTeamButton
                    backButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 16)
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
                    Text("Please enter at least 2 characters to continue.")
                        .font(.subheadline)
                        .foregroundStyle(Color.danger)
                } else if !playerName.isEmpty && !isNameValid {
                    // Inline hint while the user is typing but hasn't yet hit
                    // the minimum length.
                    Text("Names need to be at least 2 characters.")
                        .font(.subheadline)
                        .foregroundStyle(Color.textTertiary)
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
                Picker("Salary Cap", selection: $capSelection) {
                    Text("Simple").tag(CapModeSelection.simple)
                    Text("Realistic").tag(CapModeSelection.realistic)
                    Text("Sandbox").tag(CapModeSelection.sandbox)
                }
                .pickerStyle(.segmented)

                // Feature checklist comparison
                VStack(alignment: .leading, spacing: 10) {
                    capFeatureRow(feature: "Annual salary cap",
                                  simple: true, realistic: true, sandbox: false)
                    capFeatureRow(feature: "Signing bonuses",
                                  simple: false, realistic: true, sandbox: false)
                    capFeatureRow(feature: "Dead cap penalties",
                                  simple: false, realistic: true, sandbox: false)
                    capFeatureRow(feature: "Contract restructures",
                                  simple: false, realistic: true, sandbox: false)
                    capFeatureRow(feature: "Franchise tags",
                                  simple: false, realistic: true, sandbox: false)
                    capFeatureRow(feature: "Cap rollover",
                                  simple: false, realistic: true, sandbox: false)
                }

                Group {
                    switch capSelection {
                    case .simple:
                        Text("Great for new players. Straightforward salaries, no hidden penalties.")
                    case .realistic:
                        Text("Full NFL cap rules. Every dollar and bonus structure matters.")
                    case .sandbox:
                        Text("No salary cap restrictions. Sign whoever you want, however you want.")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)

                // Rationale footnote for the Recommended badge shown on Simple.
                if capSelection == .simple {
                    Label("Recommended for first-time players: easier learning curve.",
                          systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }
            }
        }
    }

    // #106, #107, #111: Coaching style with gameplay effects and beginner tag
    private var coachingStyleSection: some View {
        cardSection(icon: "gamecontroller.fill", title: "Coaching Style") {
            VStack(spacing: 3) {
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
            VStack(spacing: 4) {
                // #108: Clarify avatar is cosmetic
                Text("Cosmetic only — does not affect gameplay")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.textTertiary)

                AvatarSelectionView(selectedAvatarID: $selectedAvatarID, avatarSize: 48)

                // #105: larger avatar name, #110: remove confusing "outside -> Male coach" text
                if let avatar = CoachAvatars.avatar(for: selectedAvatarID) {
                    Text("\"\(avatar.name)\"")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                }
            }
        }
    }

    // MARK: - Game Mode Section (R40)

    private var gameModeSection: some View {
        cardSection(icon: "square.grid.2x2.fill", title: "Game Mode & Scenarios") {
            VStack(alignment: .leading, spacing: 8) {
                Text("How do you want to start? Modes change how the league is built; scenarios drop you into a hand-crafted situation.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)

                // R37: collapsible primer for players seeing these cards
                // for the first time, plus a concrete recommendation.
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showSetupExplainer.toggle() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 11, weight: .semibold))
                        Text("What is this?")
                            .font(.caption.weight(.semibold))
                        Image(systemName: showSetupExplainer ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(Color.accentBlue)
                }
                .buttonStyle(.plain)

                if showSetupExplainer {
                    VStack(alignment: .leading, spacing: 6) {
                        Label {
                            Text("Modes (Standard, Fantasy Draft) decide how rosters are built on day one: real depth charts, or a league-wide redraft.")
                        } icon: {
                            Image(systemName: "square.grid.2x2.fill")
                                .foregroundStyle(Color.accentBlue)
                        }
                        Label {
                            Text("Scenarios (Rebuild, Win Now, Cap Hell) reshape your team into a hand-crafted situation with a clear challenge to solve.")
                        } icon: {
                            Image(systemName: "flag.checkered")
                                .foregroundStyle(Color.accentGold)
                        }
                        Label {
                            Text("New to Dynasty? Start with Standard — it's the classic experience. Rebuild makes a great second career: low expectations, plenty of picks.")
                        } icon: {
                            Image(systemName: "graduationcap.fill")
                                .foregroundStyle(Color.success)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .padding(10)
                    .background(Color.backgroundPrimary, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                ForEach(CareerSetup.allCases, id: \.self) { setup in
                    CareerSetupCard(setup: setup, isSelected: selectedSetup == setup)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3)) {
                                selectedSetup = setup
                            }
                        }
                }
            }
        }
    }

    // MARK: - League Settings Section (R40)

    private var leagueSettingsSection: some View {
        cardSection(icon: "slider.horizontal.3", title: "League Settings") {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Injury Frequency")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)

                    Picker("Injury Frequency", selection: $injuryFrequency) {
                        ForEach(InjuryFrequency.allCases, id: \.self) { frequency in
                            Text(frequency.displayName).tag(frequency)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(injuryFrequency.blurb)
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                }

                Divider().overlay(Color.surfaceBorder)

                VStack(alignment: .leading, spacing: 6) {
                    Label("Salary cap rules are set in Step 1 (\(capSelection.capMode.rawValue)).",
                          systemImage: "dollarsign.circle")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                    Label("Season length is fixed at 17 games (18 weeks).",
                          systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
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
    private func capFeatureRow(feature: String, simple: Bool, realistic: Bool, sandbox: Bool) -> some View {
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

                Image(systemName: sandbox ? "checkmark.circle.fill" : "minus.circle")
                    .font(.caption)
                    .foregroundStyle(sandbox ? Color.success : Color.textTertiary)
                    .frame(width: 30)
            }
        }
    }

    // MARK: - Buttons

    private var nextButton: some View {
        Button {
            guard isNameValid else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                currentStep = 2
                showNameError = false
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
                    .fill(isNameValid ? Color.accentGold : Color.surfaceBorder)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        (isNameValid ? Color.accentGold : Color.surfaceBorder).opacity(0.6),
                        lineWidth: 1
                    )
            )
            .opacity(isNameValid ? 1.0 : 0.7)
        }
        .disabled(!isNameValid)
        .accessibilityHint(isNameValid
                           ? "Continues to Step 2"
                           : "Enter your name (at least 2 characters) to continue")
        .padding(.top, 4)
    }

    /// Step 2 → Step 3 (Game Mode → Identity).
    private var nextToIdentityButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.3)) {
                currentStep = 3
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
        .accessibilityHint("Continues to Step 3, Your Identity")
        .padding(.top, 4)
    }

    /// Quick Start path: skips Step 2 and feeds the same destination with
    /// the pre-filled defaults. Disabled until the name is valid.
    private var quickStartChooseTeamButton: some View {
        NavigationLink(destination: TeamSelectionView(
            playerName: playerName,
            avatarID: selectedAvatarID,
            coachingStyle: selectedCoachingStyle,
            selectedRole: selectedRole,
            selectedCapMode: capSelection.capMode,
            gameMode: selectedSetup.mode,
            scenario: selectedSetup.scenario,
            injuryFrequency: injuryFrequency
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
                    .fill(isNameValid ? Color.accentGold : Color.surfaceBorder)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        (isNameValid ? Color.accentGold : Color.surfaceBorder).opacity(0.6),
                        lineWidth: 1
                    )
            )
            .opacity(isNameValid ? 1.0 : 0.7)
        }
        .disabled(!isNameValid)
        .padding(.top, 4)
    }

    private var chooseTeamButton: some View {
        NavigationLink(destination: TeamSelectionView(
            playerName: playerName,
            avatarID: selectedAvatarID,
            coachingStyle: selectedCoachingStyle,
            selectedRole: selectedRole,
            selectedCapMode: capSelection.capMode,
            gameMode: selectedSetup.mode,
            scenario: selectedSetup.scenario,
            injuryFrequency: injuryFrequency
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
                currentStep = max(1, currentStep - 1)
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
                    .foregroundStyle(Color.textSecondary)
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
            }

            content()
        }
        .padding(20)
        .cardBackground()
    }
}

// MARK: - Career Setup Card (R40)

/// Single-select card for the Game Mode step: two modes (Standard, Fantasy
/// Draft) and three scenario starts (Rebuild, Win Now, Cap Hell).
private struct CareerSetupCard: View {
    let setup: CareerSetup
    let isSelected: Bool

    private var accent: Color {
        setup.scenario == nil ? Color.accentBlue : Color.accentGold
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(isSelected ? accent.opacity(0.2) : Color.backgroundSecondary)
                    .frame(width: 34, height: 34)
                Image(systemName: setup.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? accent : Color.textSecondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(setup.displayName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.textPrimary)

                    Text(setup.badge)
                        .font(.system(size: 8, weight: .heavy))
                        .tracking(0.8)
                        .foregroundStyle(isSelected ? Color.backgroundPrimary : Color.textSecondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(isSelected ? accent : Color.backgroundSecondary)
                        )

                    if let scenario = setup.scenario {
                        Text(scenario.tagline)
                            .font(.system(size: 9, weight: .medium).italic())
                            .foregroundStyle(Color.textTertiary)
                            .lineLimit(1)
                    }
                }

                Text(setup.blurb)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isSelected ? Color.textSecondary : Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isSelected ? accent : Color.textTertiary.opacity(0.5))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? accent.opacity(0.08) : Color.backgroundPrimary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isSelected ? accent : Color.surfaceBorder,
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(setup.displayName), \(setup.badge.lowercased()). \(setup.blurb)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Coaching Style Card (#104, #106, #107, #111)

private struct CoachingStyleCard: View {
    let style: CoachingStyle
    let isSelected: Bool
    var isRecommended: Bool = false

    /// Concrete, gameplay-facing effect for each style. Replaces the previous
    /// vague "+10 <Attribute>" badge so players understand the actual impact.
    private var gameplayEffect: String {
        switch style {
        case .tactician:
            return "+10% play-call accuracy in close-game situations"
        case .playersCoach:
            return "+10% player development speed during practices"
        case .disciplinarian:
            return "-10% penalties and fumbles drawn each game"
        case .innovator:
            return "+10% scheme familiarity gain when teaching playbooks"
        case .motivator:
            return "+10% morale boost from wins and locker-room moments"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(isSelected ? Color.accentBlue.opacity(0.2) : Color.backgroundSecondary)
                    .frame(width: 32, height: 32)
                Image(systemName: style.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentBlue : Color.textSecondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(style.displayName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.textPrimary)

                    // #107: Beginner guidance tag
                    if isRecommended {
                        Text("Recommended")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color.backgroundPrimary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                Capsule().fill(Color.accentGold)
                            )
                    }
                }

                Text(gameplayEffect)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isSelected ? Color.textSecondary : Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                if isRecommended {
                    // Footnote rationale — prevents the badge from feeling arbitrary.
                    Text("Recommended for first-time players: easier learning curve.")
                        .font(.system(size: 9, weight: .regular).italic())
                        .foregroundStyle(Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 4)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.accentBlue.opacity(0.08) : Color.backgroundPrimary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isSelected ? Color.accentBlue : Color.surfaceBorder,
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(style.displayName). \(gameplayEffect).")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview {
    NavigationStack {
        NewCareerView()
    }
    .modelContainer(for: Career.self, inMemory: true)
}

// Sandbox cap mode is now wired end-to-end: `CapMode.sandbox` flows from this
// view into TeamSelectionView and is consumed by `ContractEngine`,
// `CapManagementEngine`, and `FreeAgencyEngine` via cap-mode-aware overloads
// that short-circuit cap accounting (no contract validation, no cap room
// blocking, no franchise tag costs, no salary floor enforcement).
