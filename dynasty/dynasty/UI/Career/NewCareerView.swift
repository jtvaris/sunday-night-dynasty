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
    /// The wizard opens on a name rather than on an empty field, because the
    /// only forward action on this screen is gated on one: an untouched Quick
    /// Start met the player with a dead "Choose Your Team" and a hint telling
    /// him why. A drawn name makes the field an edit instead of a gate, and it
    /// comes from the same pools the league itself is named from.
    @State private var playerName: String = {
        let drawn = RandomNameGenerator.randomName()
        return "\(drawn.first) \(drawn.last)"
    }()
    /// Which league the career is built from. `.generated` keeps the classic
    /// random path, so an untouched flow behaves exactly as before.
    @State private var leagueSource: LeagueSource = .generated
    /// The portrait the career starts on. Seeded from a fresh shuffle rather
    /// than pinned to a constant, so the wizard does not open on the same face
    /// every single career — and never on an illustration, which is what the old
    /// `"coach_m1"` default did to every Quick Start save (the Quick Start flow
    /// skips the identity step, so that default was the *only* thing most
    /// careers ever stored).
    @State private var selectedAvatarID: String = UserPortrait.randomStartingID()
    /// Q-M01 — the 20-portrait grid is collapsed behind a "Change" button.
    /// It is the biggest block on the screen and the only choice with no
    /// mechanical effect; the settings the sim actually reads now hold that
    /// space. One tap still reaches every face.
    @State private var showPortraitGrid = false
    @State private var selectedCoachingStyle: CoachingStyle = .tactician
    @State private var selectedRole: CareerRole = NewCareerView.recommendedRole
    @State private var capSelection: CapModeSelection = NewCareerView.recommendedCapMode

    // MARK: - The two step-1 recommendations
    //
    // The wizard pre-selects a role and a cap mode, and until now said nothing
    // about why — a first-time player had two irreversible-feeling choices and
    // no decision support on either. The "Recommended" badge marks the value the
    // flow already commits to, so the badge and the default are the same
    // constant by construction and cannot drift apart.

    /// The role the flow opens on, and the one the badge marks.
    private static let recommendedRole: CareerRole = .gmAndHeadCoach

    /// The cap mode the flow opens on, and the one the badge marks.
    private static let recommendedCapMode: CapModeSelection = .realistic

    /// Which segment of the two-wide role picker the badge sits under.
    private static var recommendedRoleSegmentIndex: Int {
        switch recommendedRole {
        case .gm:             return 0
        case .gmAndHeadCoach: return 1
        }
    }

    /// Which segment of the three-wide cap picker the badge sits under.
    private static var recommendedCapSegmentIndex: Int {
        switch recommendedCapMode {
        case .simple:    return 0
        case .realistic: return 1
        case .sandbox:   return 2
        }
    }

    /// Spoken name of the recommended role, for the badge's VoiceOver label.
    private static var recommendedRoleName: String {
        switch recommendedRole {
        case .gm:             return "General Manager"
        case .gmAndHeadCoach: return "GM and Head Coach"
        }
    }

    /// Spoken name of the recommended cap mode.
    private static var recommendedCapName: String {
        switch recommendedCapMode {
        case .simple:    return "Simple"
        case .realistic: return "Realistic"
        case .sandbox:   return "Sandbox"
        }
    }
    @State private var currentStep = 1
    @State private var showNameError = false

    // R40 — Game mode / scenario card + custom league settings.
    @State private var selectedSetup: CareerSetup = .standard
    @State private var injuryFrequency: InjuryFrequency = .normal

    // R37 — "What is this?" explainer toggle for modes vs. scenarios.
    @State private var showSetupExplainer = false

    @State private var viewWidth: CGFloat = 0
    @State private var viewHeight: CGFloat = 0

    /// iPad always reports .regular for both size classes, so orientation has to
    /// be measured. It used to be `viewWidth > 900`, which a 13-inch iPad
    /// satisfies in PORTRAIT (1032 pt) — the two-column branch then ran on a
    /// tall screen and left 40-45 % of it empty. Compare the two axes instead.
    private var isLandscape: Bool { viewWidth > viewHeight }

    private var isNameValid: Bool {
        playerName.trimmingCharacters(in: .whitespaces).count >= 2
    }

    /// Quick Start collapses to a single step on this screen; Custom League runs
    /// the full three (Career → Game Mode → Identity). Both counts include the
    /// team pick that follows, because it is a mandatory screen and a bar that
    /// reads "Step 1 of 1", filled edge to edge, over a button that pushes a
    /// whole further step is simply not true.
    private var totalSteps: Int { flowMode == .quickStart ? 2 : 4 }

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
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { newSize in
            viewWidth = newSize.width
            viewHeight = newSize.height
        }
        .navigationTitle(stepTitle(currentStep))
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        // Segmented-control palette is applied app-wide by DSAppearance.apply()
        // at launch; doing it here (.onAppear) was a frame too late to catch
        // the pickers this screen had already built.
    }

    // MARK: - Step Indicator (#98: larger progress bar)

    private var stepIndicator: some View {
        VStack(spacing: 8) {
            // The step's own title used to sit at the trailing end of this row.
            // It is the large navigation title two rows above it, verbatim.
            Text("Step \(currentStep) of \(totalSteps)")
                .font(.callout.weight(.bold))
                .foregroundStyle(Color.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.surfaceBorder)
                        .frame(height: 6)

                    let progress = CGFloat(currentStep) / CGFloat(totalSteps)

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
                    // Q-M01: Quick Start now SHOWS role, cap mode, game mode and
                    // coaching style as controls, so switching back to it must
                    // not silently overwrite a choice the user can still see on
                    // screen. What Quick Start does not show, it still resets —
                    // injury frequency lives on the Custom League step, and a
                    // value this screen never displays must not ride into the
                    // career behind the user's back.
                    injuryFrequency = .normal
                }
            }

            Text(flowMode == .quickStart
                 ? "Jump straight in. The four settings the league actually runs on are pre-filled below — change any of them in place."
                 : "Tailor everything: role, cap rules, game mode or scenario, league settings, coaching style, and portrait.")
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
                        // Quick Start: name, league, the four settings the sim
                        // reads — then the face, in a thumbnail.
                        //
                        // Q-M01: the portrait grid used to be the bottom ~40 % of
                        // this screen and is the one choice with no mechanical
                        // effect (the card's own copy says so), while the four
                        // settings the engine consumes appeared exactly once, as
                        // a grey sentence with no control on it. The mechanics
                        // are above the fold now and the portrait is a row.
                        nameSection
                        if isLandscape {
                            HStack(alignment: .top, spacing: 16) {
                                leagueSourceSection
                                quickStartSettingsSection
                            }
                        } else {
                            leagueSourceSection
                            quickStartSettingsSection
                        }
                        avatarSection
                    } else if isLandscape {
                        nameSection
                        leagueSourceSection
                        HStack(alignment: .top, spacing: 16) {
                            roleSection
                            capModeSection
                        }
                    } else {
                        nameSection
                        leagueSourceSection
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
                        .foregroundStyle(Color.dangerText)
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

    // MARK: - League Source (realistic-league phase 3)

    /// Which league the career is built from: the fixed 2026 snapshot or a
    /// freshly generated one. `LeagueSource.available` hides the dev template
    /// outside DEBUG builds, so Release only ever sees two options.
    private var leagueSourceSection: some View {
        cardSection(icon: "globe.americas.fill", title: "League") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Which league do you want to take over?")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)

                ForEach(LeagueSource.available) { option in
                    LeagueSourceCard(source: option, isSelected: leagueSource == option)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3)) {
                                leagueSource = option
                            }
                        }
                }

                Label(
                    leagueSource.isTemplate
                        ? "Fixed leagues are identical in every career — the same rosters, records and traded picks."
                        : "Generated leagues are rolled from scratch, so no two careers start the same.",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
            }
        }
    }

    // #100, #102: Role section with comparison bullet points
    private var roleSection: some View {
        cardSection(icon: "briefcase.fill", title: "Career Role") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(spacing: 6) {
                    Picker("Role", selection: $selectedRole) {
                        Text("General Manager").tag(CareerRole.gm)
                        Text("GM & Head Coach").tag(CareerRole.gmAndHeadCoach)
                    }
                    .pickerStyle(.segmented)

                    recommendedBadgeRow(
                        segmentCount: 2,
                        recommendedIndex: Self.recommendedRoleSegmentIndex,
                        accessibilityText: "\(Self.recommendedRoleName) is recommended for a first career."
                    )
                }

                // Role comparison
                VStack(alignment: .leading, spacing: 10) {
                    comparisonHeaderRow([
                        (title: "GM", isSelected: selectedRole == .gm),
                        (title: "GM & HC", isSelected: selectedRole == .gmAndHeadCoach)
                    ])

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

                Text(roleBlurb)
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)

                // `Career.role` is written in the initialiser and by nothing
                // else in the app — no screen, no engine, no migration ever
                // reassigns it. A choice that decides whether the player calls
                // plays for the next fifteen seasons was being presented like a
                // preference he could come back and flip.
                Label("Locked for the life of the career — you can't switch roles once it starts.",
                      systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            }
        }
    }

    /// One line per role, hoisted out of `roleSection` so the Quick Start
    /// settings card prints the same sentence for the same value. Two copies of
    /// this string is exactly how the two cards would drift apart.
    private var roleBlurb: String {
        switch selectedRole {
        case .gm:
            return "Focus on roster building and let your head coach handle game day."
        case .gmAndHeadCoach:
            return "Total control over every decision, from the roster to the play sheet."
        }
    }

    // #103, #101: Cap mode section with feature checklist
    private var capModeSection: some View {
        cardSection(icon: "dollarsign.circle.fill", title: "Salary Cap Mode") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(spacing: 6) {
                    Picker("Salary Cap", selection: $capSelection) {
                        Text("Simple").tag(CapModeSelection.simple)
                        Text("Realistic").tag(CapModeSelection.realistic)
                        Text("Sandbox").tag(CapModeSelection.sandbox)
                    }
                    .pickerStyle(.segmented)

                    recommendedBadgeRow(
                        segmentCount: 3,
                        recommendedIndex: Self.recommendedCapSegmentIndex,
                        accessibilityText: "\(Self.recommendedCapName) is the recommended salary cap mode."
                    )
                }

                // Feature checklist comparison
                VStack(alignment: .leading, spacing: 10) {
                    comparisonHeaderRow([
                        (title: "Simple", isSelected: capSelection == .simple),
                        (title: "Realistic", isSelected: capSelection == .realistic),
                        (title: "Sandbox", isSelected: capSelection == .sandbox)
                    ])

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

                Text(capBlurb)
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)

                // The rationale behind the Recommended badge, printed whatever is
                // selected. It used to be gated on `capSelection == .simple`, so
                // the one line of decision support on this card was invisible to
                // everybody who had not already moved off the default — which is
                // precisely the reader it was written for.
                Label("Realistic is the default and the full front-office game. New to cap management? Simple keeps the money simple; Sandbox turns the cap off entirely.",
                      systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// One line per cap mode — same hoist, same reason, as `roleBlurb`.
    private var capBlurb: String {
        switch capSelection {
        case .simple:
            return "Great for new players. Straightforward salaries, no hidden penalties."
        case .realistic:
            return "Full League cap rules. Every dollar and bonus structure matters."
        case .sandbox:
            return "No salary cap restrictions. Sign whoever you want, however you want."
        }
    }

    // MARK: - Quick Start Settings (Q-M01)

    /// The four settings the Quick Start path feeds the engine, as controls
    /// instead of as a sentence.
    ///
    /// All four are read by the simulation: `CareerRole` gates play-calling and
    /// staff management, `CapModeSelection.capMode` switches contract accounting
    /// on and off end-to-end (`ContractEngine`, `CapManagementEngine`,
    /// `FreeAgencyEngine`), `CareerSetup` picks both the roster build and the
    /// scenario, and `CoachingStyle` carries the +10 staff bonus *and* the
    /// `FranchiseIdentityDeclaration` seed the other 31 front offices price
    /// against. Until now Quick Start named them in grey body text with nothing
    /// to tap, so every Quick Start career in existence shipped the same four
    /// values.
    ///
    /// The DEFAULTS are untouched: this is a control for a value the flow was
    /// already committing to, not a retune of Quick Start.
    private var quickStartSettingsSection: some View {
        cardSection(icon: "slider.horizontal.3", title: "Quick Start Settings") {
            VStack(alignment: .leading, spacing: 14) {
                Text("These are what the league runs on. They come pre-filled — change any of them here, or switch to Custom League for the side-by-side comparisons.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)

                // Quick Start is the flow the wizard opens on, so these two are
                // the copies of the role and cap controls a first-time player is
                // most likely to meet — they carry the same Recommended badge as
                // the Custom League cards.
                quickSetting("Career Role", detail: roleBlurb) {
                    VStack(spacing: 6) {
                        Picker("Career Role", selection: $selectedRole) {
                            Text("General Manager").tag(CareerRole.gm)
                            Text("GM & Head Coach").tag(CareerRole.gmAndHeadCoach)
                        }
                        .pickerStyle(.segmented)

                        recommendedBadgeRow(
                            segmentCount: 2,
                            recommendedIndex: Self.recommendedRoleSegmentIndex,
                            accessibilityText: "\(Self.recommendedRoleName) is recommended for a first career."
                        )
                    }
                }

                quickSetting("Salary Cap", detail: capBlurb) {
                    VStack(spacing: 6) {
                        Picker("Salary Cap", selection: $capSelection) {
                            Text("Simple").tag(CapModeSelection.simple)
                            Text("Realistic").tag(CapModeSelection.realistic)
                            Text("Sandbox").tag(CapModeSelection.sandbox)
                        }
                        .pickerStyle(.segmented)

                        recommendedBadgeRow(
                            segmentCount: 3,
                            recommendedIndex: Self.recommendedCapSegmentIndex,
                            accessibilityText: "\(Self.recommendedCapName) is the recommended salary cap mode."
                        )
                    }
                }

                // Five options each, with names too long for a segmented row at
                // half an iPad's width — a menu keeps them readable and keeps the
                // card the height of the League card beside it.
                quickSetting("Game Mode", detail: selectedSetup.blurb) {
                    menuChip(
                        title: "Game Mode",
                        selection: $selectedSetup,
                        options: CareerSetup.allCases,
                        label: \.displayName
                    )
                }

                quickSetting("Coaching Style", detail: coachingStyleEffect(selectedCoachingStyle)) {
                    menuChip(
                        title: "Coaching Style",
                        selection: $selectedCoachingStyle,
                        options: CoachingStyle.allCases,
                        label: \.displayName
                    )
                }
            }
        }
    }

    /// Title above, control, then the one line that says what the current value
    /// does. The detail line is the same string the Custom League card prints.
    @ViewBuilder
    private func quickSetting<Control: View>(
        _ title: String,
        detail: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.textPrimary)

            control()

            Text(detail)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A full-width menu button for a choice with too many options to segment.
    ///
    /// `Menu { Picker }` rather than `Picker(.menu)` so the whole chip — padding
    /// and border included — is the tap target; a bare menu picker only accepts
    /// taps on its own label text. The 44 pt height is `DSButtonChrome`'s
    /// `minHeight`, so the chip matches every other control on the flow, and the
    /// 8 pt radius matches the name field directly above it.
    private func menuChip<Value: Hashable>(
        title: String,
        selection: Binding<Value>,
        options: [Value],
        label: KeyPath<Value, String>
    ) -> some View {
        Menu {
            Picker(title, selection: selection) {
                ForEach(options, id: \.self) { option in
                    Text(option[keyPath: label]).tag(option)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(selection.wrappedValue[keyPath: label])
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: DSType.Size.caption, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.backgroundPrimary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.surfaceBorder, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .accessibilityLabel(title)
        .accessibilityValue(selection.wrappedValue[keyPath: label])
    }

    // #106, #107, #111: Coaching style with gameplay effects and beginner tag
    private var coachingStyleSection: some View {
        cardSection(icon: "gamecontroller.fill", title: "Coaching Style") {
            VStack(spacing: 3) {
                ForEach(CoachingStyle.allCases, id: \.self) { style in
                    CoachingStyleCard(
                        style: style,
                        isSelected: selectedCoachingStyle == style,
                        isRecommended: style == recommendedCoachingStyle,
                        recommendationNote: coachingRecommendationNote
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

    /// The style the Coaching Style card badges as Recommended.
    ///
    /// It used to be `.tactician` for everybody, one step after the user chose
    /// whether he would ever call a play. The Tactician's edge is play-call
    /// accuracy in close games, and in a GM-only career the head coach the user
    /// *hires* makes those calls — `CoachingStaffView` only prints the style's
    /// +10 rating for a `gmAndHeadCoach` career, because that is the only career
    /// in which the user is sitting in the chair the rating belongs to.
    ///
    /// So the recommendation follows the role. For a GM-only career the half of
    /// the choice that still binds is the one the card prints underneath the
    /// effect: `FranchiseIdentityDeclaration.seed(for:)`, the identity the other
    /// 31 front offices price him against. The Players' Coach seeds `.balanced`
    /// — "no edge in either direction" — which is the market to learn the trade
    /// board in, and (by that file's own ruling) not a strictly better one.
    private var recommendedCoachingStyle: CoachingStyle {
        switch selectedRole {
        case .gmAndHeadCoach: return .tactician
        case .gm:             return .playersCoach
        }
    }

    /// Why that style is the recommendation, in the terms of the role the user
    /// picked one step earlier. A badge with no rationale is the complaint the
    /// footnote exists to answer, and a rationale that ignores the role is the
    /// same complaint one level down.
    private var coachingRecommendationNote: String {
        switch selectedRole {
        case .gmAndHeadCoach:
            return "Recommended for GM & Head Coach: you call the plays yourself, so this is the bonus you spend every Sunday."
        case .gm:
            return "Recommended for a GM career: your head coach calls the plays, so the front-office read above is the half you spend — and this one leaves the market even both ways."
        }
    }

    // #108, #109, #110, #113: portrait section with cosmetic label, cleaner headers
    //
    // Q-M01: the 20-face grid is behind a "Change" button now. It was the
    // largest block on the setup screen and, by the card's own admission, the
    // only choice with no mechanical effect — twenty loaded archetype names
    // ("The Enforcer", "The Bulldog") that are not even authored per face, but
    // applied in manifest order (`UserPortraitView.swift`). Collapsed, the
    // section is one 56 pt row; expanded, it is exactly the grid that shipped,
    // one tap away. Nothing about the choice itself changed.
    private var avatarSection: some View {
        cardSection(icon: "person.crop.circle.fill", title: "Your Portrait") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    UserPortraitView(
                        avatarID: selectedAvatarID,
                        name: playerName,
                        size: .medium
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        // #105: the persona name, still the loudest thing in the row
                        Text("\"\(UserPortrait.label(for: selectedAvatarID) ?? "Portrait")\"")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)

                        // #108: Clarify the portrait is cosmetic
                        // NOT "cosmetic only" any more, and it never quite was: the
                        // career's coaching STYLE carries a real modifier (the Tactician's
                        // +10 play-calling shows on the staff screen), and the
                        // introductory press conference builds a media read that its own
                        // recap says "shapes free-agent interest". Naming these portraits
                        // after archetypes while disclaiming any effect was the misleading
                        // half. The picture itself is still just a picture.
                        Text("The portrait is yours alone — your coaching style and your press answers are what the league reads.")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showPortraitGrid.toggle()
                        }
                    } label: {
                        Label(showPortraitGrid ? "Done" : "Change",
                              systemImage: showPortraitGrid ? "checkmark" : "person.crop.circle.badge.plus")
                    }
                    .buttonStyle(.dsSecondary)
                    .accessibilityHint(showPortraitGrid
                                       ? "Closes the portrait grid"
                                       : "Opens the grid of 20 portraits")
                }

                if showPortraitGrid {
                    UserPortraitPicker(selectedAvatarID: $selectedAvatarID, avatarSize: 56)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .onAppear {
            // The picker normalises a non-portrait id in its own `onAppear`.
            // Behind a collapsed grid that no longer runs on the first frame, so
            // the same guard lives here: the thumbnail must never be the one
            // surface that draws a stale id. A wizard-fresh id is already valid
            // (`randomStartingID`), so this only catches a build without extras.
            if !UserPortrait.isPortraitID(selectedAvatarID) {
                selectedAvatarID = UserPortrait.resolve(selectedAvatarID, seed: nil)
                    ?? UserPortrait.fallbackID
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
                            .font(.system(size: DSType.Size.caption, weight: .semibold))
                        Text("What is this?")
                            .font(.caption.weight(.semibold))
                        Image(systemName: showSetupExplainer ? "chevron.up" : "chevron.down")
                            .font(.system(size: DSType.Size.micro, weight: .bold))
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
                            // The second sentence is the timing, and it is here
                            // because the team picker draws its cards from the
                            // league BEFORE `CareerScenarioApplier` runs — the
                            // one thing on this screen the pick-time-league
                            // refactor could not pull forward, because a
                            // scenario reshapes whichever club the next screen's
                            // tap chooses.
                            Text("Scenarios (Rebuild, Win Now, Cap Hell) reshape your team into a hand-crafted situation with a clear challenge to solve. They are applied after you choose a club, so the team picker shows you each club as the league was built — the scenario's own changes are listed there before you confirm.")
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

    /// One geometry for both comparison tables. A header cell and the mark
    /// underneath it have to be the same column, so the width and the gap are
    /// stated once and read by the header row and the two row builders alike —
    /// a header that has drifted off its column is worse than the bare icons it
    /// replaced.
    ///
    /// The column is wider (and the gutter tighter) than the 30/16 it replaces
    /// because the header has to fit a word: `Realistic` is the longest of the
    /// five and it sets the floor.
    private static let comparisonColumnWidth: CGFloat = 52
    private static let comparisonColumnSpacing: CGFloat = 4

    /// Column headers for a comparison table, laid on exactly the grid the rows
    /// below use.
    ///
    /// The selected option's header is gold — the tint the segmented picker
    /// gives its own selection — so the control above and the column below read
    /// as the same choice. That link is what the checkmark columns were missing:
    /// a full-width segmented picker cannot be made to register with a table
    /// that carries a leading label column (the first segment's centre sits at
    /// one-sixth of the card, well inside the feature text), so the table names
    /// its own columns instead of chasing the picker's geometry.
    private func comparisonHeaderRow(_ columns: [(title: String, isSelected: Bool)]) -> some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)

            HStack(spacing: Self.comparisonColumnSpacing) {
                ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                    Text(column.title)
                        .font(.system(size: DSType.Size.micro, weight: .heavy))
                        .foregroundStyle(column.isSelected ? Color.accentGold : Color.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                        .frame(width: Self.comparisonColumnWidth)
                }
            }
        }
        // Every row below states its own columns for VoiceOver, so a spoken
        // header would only repeat itself.
        .accessibilityHidden(true)
    }

    /// A gold "Recommended" capsule parked under the segment it belongs to.
    ///
    /// A segmented `Picker` renders nothing but the `Text` inside each tag, so
    /// the badge cannot live inside the control. It can still line up with it:
    /// the segments divide the row into equal parts, so one equal-width cell per
    /// segment puts the capsule under its own option.
    private func recommendedBadgeRow(
        segmentCount: Int,
        recommendedIndex: Int,
        accessibilityText: String
    ) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(0..<segmentCount), id: \.self) { index in
                Group {
                    if index == recommendedIndex {
                        Text("Recommended")
                            .font(.system(size: DSType.Size.micro, weight: .bold))
                            .foregroundStyle(Color.backgroundPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentGold))
                    } else {
                        Color.clear.frame(height: 1)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    // #102: Role comparison row
    private func roleComparisonRow(action: String, gmAvailable: Bool, gmhcAvailable: Bool) -> some View {
        HStack(spacing: 8) {
            Text(action)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: Self.comparisonColumnSpacing) {
                // GM column
                Image(systemName: gmAvailable ? "checkmark.circle.fill" : "minus.circle")
                    .font(.caption)
                    .foregroundStyle(gmAvailable ? Color.success : Color.textTertiary)
                    .frame(width: Self.comparisonColumnWidth)

                // GM&HC column
                Image(systemName: gmhcAvailable ? "checkmark.circle.fill" : "minus.circle")
                    .font(.caption)
                    .foregroundStyle(gmhcAvailable ? Color.success : Color.textTertiary)
                    .frame(width: Self.comparisonColumnWidth)
            }
        }
        // Unlabelled glyphs read as "checkmark, minus-circle" and nothing else —
        // the same "which column is which" question the header row answers for
        // everybody else.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(action). General Manager: \(gmAvailable ? "yes" : "no"). "
                + "GM and Head Coach: \(gmhcAvailable ? "yes" : "no")."
        )
    }

    // #103: Cap feature comparison row
    private func capFeatureRow(feature: String, simple: Bool, realistic: Bool, sandbox: Bool) -> some View {
        HStack(spacing: 8) {
            Text(feature)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: Self.comparisonColumnSpacing) {
                Image(systemName: simple ? "checkmark.circle.fill" : "minus.circle")
                    .font(.caption)
                    .foregroundStyle(simple ? Color.success : Color.textTertiary)
                    .frame(width: Self.comparisonColumnWidth)

                Image(systemName: realistic ? "checkmark.circle.fill" : "minus.circle")
                    .font(.caption)
                    .foregroundStyle(realistic ? Color.success : Color.textTertiary)
                    .frame(width: Self.comparisonColumnWidth)

                Image(systemName: sandbox ? "checkmark.circle.fill" : "minus.circle")
                    .font(.caption)
                    .foregroundStyle(sandbox ? Color.success : Color.textTertiary)
                    .frame(width: Self.comparisonColumnWidth)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(feature). Simple: \(simple ? "yes" : "no"). "
                + "Realistic: \(realistic ? "yes" : "no"). "
                + "Sandbox: \(sandbox ? "yes" : "no")."
        )
    }

    // MARK: - Buttons

    /// The label every step commit on the entry flow wears (§2.8).
    ///
    /// New Career shipped four copies of one gold recipe — `cornerRadius: 12`,
    /// a 52 pt row, a gold stroke at 60 %, and a disabled state built out of
    /// `Color.surfaceBorder` plus `.opacity(0.7)`. The chrome is `.dsPrimary`'s
    /// job now; what stays here is the flow's own full-width format, because a
    /// wizard step's commit spans the column and a toolbar's does not.
    private func entryCommitLabel(
        _ title: LocalizedStringKey,
        systemImage: String,
        trailingIcon: Bool = false
    ) -> some View {
        HStack(spacing: DSSpacing.xs) {
            if !trailingIcon { Image(systemName: systemImage) }
            Text(title)
            if trailingIcon { Image(systemName: systemImage) }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 36)
    }

    private var nextButton: some View {
        Button {
            guard isNameValid else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                currentStep = 2
                showNameError = false
            }
        } label: {
            // §2.8: one gold recipe. The old one dimmed the gold to 70 % for its
            // disabled state, which is precisely what the vision forbids — a
            // dimmed primary still reads as pressable. `.dsPrimary` paints a
            // genuinely disabled grey instead.
            entryCommitLabel("Next", systemImage: "arrow.right", trailingIcon: true)
        }
        .buttonStyle(.dsPrimary)
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
                // The grid is collapsed on the *setup* screen (Q-M01), where it
                // crowded out the settings the sim reads. This step is called
                // "Your Identity" and has nothing else to spend the column on,
                // so it opens on the full grid — the same screen that shipped.
                showPortraitGrid = true
            }
        } label: {
            entryCommitLabel("Next", systemImage: "arrow.right", trailingIcon: true)
        }
        .buttonStyle(.dsPrimary)
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
            injuryFrequency: injuryFrequency,
            leagueSource: leagueSource
        )) {
            entryCommitLabel("Choose Your Team", systemImage: "sportscourt.fill")
        }
        .buttonStyle(.dsPrimary)
        .disabled(!isNameValid)
        .padding(.top, 4)
        .overlay(alignment: .bottom) { nameGateHint.offset(y: 22) }
    }

    /// Why the commit button will not move (QA 2026-08-21).
    ///
    /// `.disabled` on a `NavigationLink` does not just stop the push — it drops
    /// the control out of the accessibility tree entirely, so the button looked
    /// identical to a working one, did nothing when tapped, and said nothing
    /// about why. The Custom League path already had `showNameError` for this,
    /// but Quick Start never sets it, because a NavigationLink has no action to
    /// hang it on. A standing hint is the honest fix for a gate the user cannot
    /// otherwise see.
    @ViewBuilder
    private var nameGateHint: some View {
        if !isNameValid {
            Text("Enter your name above to choose a team.")
                .font(DSType.text(DSType.Size.footnote))
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, DSSpacing.xxs)
                .accessibilityHint("The Choose Your Team button stays disabled until a name is entered.")
        }
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
            injuryFrequency: injuryFrequency,
            leagueSource: leagueSource
        )) {
            entryCommitLabel("Choose Your Team", systemImage: "sportscourt.fill")
        }
        .buttonStyle(.dsPrimary)
        .padding(.top, 4)
    }

    private var backButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.3)) {
                currentStep = max(1, currentStep - 1)
                // Step 1 is the screen Q-M01 is about; the expanded grid does
                // not follow the user back onto it.
                if currentStep == 1 { showPortraitGrid = false }
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

    /// WHEN a card's promise is kept, for the three cards that keep it late.
    ///
    /// The pick-time-league refactor moved random-league generation in front of
    /// the team picker so that the club cards describe the league the player
    /// actually gets. A scenario is the one choice on this screen that cannot
    /// join it: `CareerScenarioApplier.apply` re-parametrizes the CHOSEN club —
    /// its ratings, its salaries and its pick ownership — and which club that
    /// is, is what the next screen's tap decides. So the picker's roster
    /// numbers are pre-scenario, and this is where the player is told, one
    /// screen before he starts reading them. `TeamDetailSheet`'s
    /// `scenarioRewriteCard` then lists the exact edits on the club he opens.
    ///
    /// Fantasy Draft needs no line here: it changes the same numbers, but the
    /// picker suppresses the roster cards outright in that mode rather than
    /// qualifying them.
    private var timingNote: String? {
        guard setup.scenario != nil else { return nil }
        return String(localized: "Applied to your club after you pick it — the team picker's roster, cap and pick numbers are what the league starts with, before this scenario rewrites them.")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(isSelected ? accent.opacity(0.2) : Color.backgroundSecondary)
                    .frame(width: 34, height: 34)
                Image(systemName: setup.icon)
                    .font(.system(size: DSType.Size.body, weight: .semibold))
                    .foregroundStyle(isSelected ? accent : Color.textSecondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(setup.displayName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.textPrimary)

                    Text(setup.badge)
                        .font(.system(size: DSType.Size.micro, weight: .heavy))
                        .tracking(0.8)
                        .foregroundStyle(isSelected ? Color.backgroundPrimary : Color.textSecondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(isSelected ? accent : Color.backgroundSecondary)
                        )

                    if let scenario = setup.scenario {
                        Text(scenario.tagline)
                            .font(.system(size: DSType.Size.caption, weight: .medium).italic())
                            .foregroundStyle(Color.textTertiary)
                            .lineLimit(1)
                    }
                }

                Text(setup.blurb)
                    .font(.system(size: DSType.Size.footnote, weight: .medium))
                    .foregroundStyle(isSelected ? Color.textSecondary : Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                if let timingNote {
                    HStack(alignment: .top, spacing: DSSpacing.xxs) {
                        Image(systemName: "clock.badge.exclamationmark")
                            .font(.system(size: DSType.Size.micro, weight: .semibold))
                            .foregroundStyle(Color.warning)
                        Text(timingNote)
                            .font(.system(size: DSType.Size.micro, weight: .medium))
                            .foregroundStyle(Color.textTertiaryReadable)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, DSSpacing.xxs)
                }
            }

            Spacer(minLength: 4)

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: DSType.Size.callout, weight: .semibold))
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
        .accessibilityLabel("\(setup.displayName), \(setup.badge.lowercased()). \(setup.blurb)\(timingNote.map { " \($0)" } ?? "")")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - League Source Card (realistic-league phase 3)

/// Single-select card for the league picker: the fixed 2026 templates and the
/// classic generated league, each with its one-line description.
private struct LeagueSourceCard: View {
    let source: LeagueSource
    let isSelected: Bool

    /// Gold marks the fixed leagues (the curated content), blue the random one —
    /// the same split `CareerSetupCard` uses for scenarios vs. modes.
    private var accent: Color {
        source.isTemplate ? Color.accentGold : Color.accentBlue
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(isSelected ? accent.opacity(0.2) : Color.backgroundSecondary)
                    .frame(width: 34, height: 34)
                Image(systemName: source.icon)
                    .font(.system(size: DSType.Size.body, weight: .semibold))
                    .foregroundStyle(isSelected ? accent : Color.textSecondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(source.displayName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.textPrimary)

                    Text(source.badge)
                        .font(.system(size: DSType.Size.micro, weight: .heavy))
                        .tracking(0.8)
                        .foregroundStyle(isSelected ? Color.backgroundPrimary : Color.textSecondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(isSelected ? accent : Color.backgroundSecondary)
                        )
                }

                Text(source.blurb)
                    .font(.system(size: DSType.Size.footnote, weight: .medium))
                    .foregroundStyle(isSelected ? Color.textSecondary : Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: DSType.Size.callout, weight: .semibold))
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
        .accessibilityLabel("\(source.displayName), \(source.badge.lowercased()). \(source.blurb)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Coaching Style Card (#104, #106, #107, #111)

/// Concrete, gameplay-facing effect for each style. Replaces the previous
/// vague "+10 <Attribute>" badge so players understand the actual impact.
///
/// File scope rather than a member of `CoachingStyleCard` because the Quick
/// Start settings card (Q-M01) prints the same sentence for the same style, and
/// two copies of this string is exactly how the two cards would drift.
private func coachingStyleEffect(_ style: CoachingStyle) -> String {
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

private struct CoachingStyleCard: View {
    let style: CoachingStyle
    let isSelected: Bool
    var isRecommended: Bool = false
    /// The rationale printed under the badge. Supplied by the host so it can say
    /// why *this* career should take *this* style — the reason is different for
    /// a man who calls his own plays and a man who hires somebody to.
    var recommendationNote: String = "Recommended for first-time players: easier learning curve."

    private var gameplayEffect: String { coachingStyleEffect(style) }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(isSelected ? Color.accentBlue.opacity(0.2) : Color.backgroundSecondary)
                    .frame(width: 32, height: 32)
                Image(systemName: style.icon)
                    .font(.system(size: DSType.Size.body, weight: .semibold))
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
                            .font(.system(size: DSType.Size.micro, weight: .bold))
                            .foregroundStyle(Color.backgroundPrimary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                Capsule().fill(Color.accentGold)
                            )
                    }
                }

                Text(gameplayEffect)
                    .font(.system(size: DSType.Size.footnote, weight: .medium))
                    .foregroundStyle(isSelected ? Color.textSecondary : Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                // F-56: the second thing this choice buys. The style is not only
                // a coaching bonus — it is the identity the other 31 front
                // offices price you against (`FranchiseIdentityDeclaration`),
                // and a declaration the user cannot read is a hidden roll of the
                // kind this repo has spent the month deleting. Every number in
                // the line is derived from the engine constant it describes.
                Text(FranchiseIdentityDeclaration.frontOfficeLine(for: style))
                    .font(.system(size: DSType.Size.caption, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentBlue : Color.textTertiaryReadable)
                    .fixedSize(horizontal: false, vertical: true)

                if isRecommended {
                    // Footnote rationale — prevents the badge from feeling arbitrary.
                    Text(recommendationNote)
                        .font(.system(size: DSType.Size.caption, weight: .regular).italic())
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
        .accessibilityLabel(
            "\(style.displayName). \(gameplayEffect). "
                + FranchiseIdentityDeclaration.frontOfficeLine(for: style)
                // `.combine` is overridden by this label, so the badge and its
                // rationale reach VoiceOver only if they are said here.
                + (isRecommended ? ". \(recommendationNote)" : "")
        )
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
