import SwiftUI
import SwiftData

struct MainMenuView: View {

    @Query(sort: \Career.currentSeason, order: .reverse) private var careers: [Career]
    @Query private var teams: [Team]

    /// **The one sheet on this screen** (§2.8, and the house rule three separate
    /// `.sheet(isPresented:)` modifiers on one node keeps breaking).
    ///
    /// Settings, the tutorial and the save-slot picker are peer side-tasks off
    /// the same button stack, so they get the same presentation weight — one
    /// enum-shaped `.sheet(item:)` point. Stacked `isPresented` sheets are the
    /// bug this codebase has now found five times: SwiftUI honours one per view
    /// and the rest open blank or dismiss silently.
    private enum MenuSheet: String, Identifiable {
        case settings, tutorial, loadCareer
        var id: String { rawValue }
    }

    @State private var activeSheet: MenuSheet?

    /// The career the slot picker chose, held only for as long as the sheet
    /// takes to leave the screen. See `openPendingCareer`.
    @State private var pendingCareer: Career?

    @State private var continueCareer: Career?

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height

            ZStack {
                // MARK: - Full Screen Hero Image
                Image("HeroImage")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()

                // Dark gradient overlay
                LinearGradient(
                    stops: [
                        .init(color: Color.black.opacity(0.3), location: 0.0),
                        .init(color: Color.black.opacity(0.15), location: 0.25),
                        .init(color: Color.black.opacity(0.5), location: 0.5),
                        .init(color: Color.black.opacity(0.85), location: 0.75),
                        .init(color: Color.black.opacity(0.95), location: 1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // MARK: - Status Bar Scrim
                // Stronger gradient at the very top so battery/wifi/clock stay readable
                // against bright stadium imagery.
                VStack(spacing: 0) {
                    LinearGradient(
                        stops: [
                            .init(color: Color.black.opacity(0.75), location: 0.0),
                            .init(color: Color.black.opacity(0.45), location: 0.55),
                            .init(color: Color.black.opacity(0.0), location: 1.0),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 110)
                    Spacer()
                }
                .allowsHitTesting(false)

                if isLandscape {
                    // Landscape: content in lower-center area
                    VStack(spacing: 16) {
                        Spacer()
                        Spacer()
                        Spacer()
                        titleBlock
                        continueHintBlock
                        buttonsBlock
                        footerBlock
                        Spacer()
                    }
                } else {
                    // Portrait: content at bottom
                    VStack(spacing: 0) {
                        Spacer()
                        titleBlock
                            .padding(.bottom, 24)
                        continueHintBlock
                        buttonsBlock
                        footerBlock
                    }
                    // Extra clearance so the button stack and footer never crowd
                    // the iPad home-indicator gesture bar (persona audit).
                    .padding(.bottom, 36)
                }
            }
        }
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            // R39 (a): app start → main menu visible. Emitted once per process.
            PerfLog.measureLaunch("launch_to_menu")
            // Title-screen score. `CareerShellView` takes the base context over
            // while a career is open and hands it back on dismiss, so this is
            // both the app's first music state and its fallback.
            MusicDirector.shared.setBaseContext(.menu)
        }
        // §2.8 — one presentation point for the three peer side-tasks, and the
        // hand-off to the career process happens in `onDismiss`, which is what
        // retires the 350 ms `asyncAfter` this screen used to guess with.
        //
        // The old shape was structural, not cosmetic: the picker is a *side
        // task* that returns a selection and the career shell is the *process*
        // that selection starts, and the code tried to run both from the same
        // event. Presenting a cover in the same turn a sheet is dismissing is a
        // conflict UIKit resolves by dropping one of them, so a timer was added
        // to out-wait the transition — a number that is too long on a fast
        // device and too short on a loaded one. `onDismiss` fires when the sheet
        // has actually gone, so there is nothing left to race.
        .sheet(item: $activeSheet, onDismiss: openPendingCareer) { sheet in
            switch sheet {
            case .settings:
                SettingsView()
            case .tutorial:
                TutorialSheet()
            case .loadCareer:
                SaveSlotPickerSheet(
                    onContinue: { career in
                        pendingCareer = career
                        activeSheet = nil
                    }
                )
            }
        }
        .fullScreenCover(item: $continueCareer) { career in
            CareerShellView(career: career)
        }
    }

    /// Opens the career the slot picker chose, once its sheet is off screen.
    private func openPendingCareer() {
        guard let career = pendingCareer else { return }
        pendingCareer = nil
        PerfLog.mark("career_open")   // R39 (b): slot-picker path
        continueCareer = career
    }

    // MARK: - Subviews

    private var titleBlock: some View {
        VStack(spacing: 8) {
            // Brand monogram — simple glyph mark above the wordmark so the menu
            // carries an identity beyond pure typography (persona audit).
            ZStack {
                Circle()
                    .strokeBorder(Color.accentGold.opacity(0.75), lineWidth: 1.5)
                    .frame(width: 52, height: 52)
                Image(systemName: "football.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.accentGold)
            }
            .shadow(color: .black.opacity(0.5), radius: 6, y: 3)
            .padding(.bottom, 6)

            // The wordmark is a LOCKUP, not type — three lines set at fixed
            // sizes and fixed tracking that only read as one mark at those exact
            // values. §2.10's two voices govern the app's *type*; a logo is the
            // one place a bespoke setting is the correct answer, and routing it
            // through `DSType.display` (condensed) at tracking 12 would redraw
            // the brand rather than systematise it. Everything BELOW this block
            // is on the ladder.
            Text("SUNDAY NIGHT")
                .font(.system(size: 22, weight: .bold))
                .tracking(10)
                .foregroundStyle(Color.accentGold)

            Text("DYNASTY")
                .font(.system(size: 64, weight: .black))
                .tracking(12)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 8, y: 4)

            Text("PRO FOOTBALL MANAGER")
                .font(.system(size: 14, weight: .medium))
                .tracking(7.5)
                .foregroundStyle(Color.white.opacity(0.85))
                .shadow(color: .black.opacity(0.55), radius: 4, y: 2)
                .padding(.top, 4)
        }
        .padding(.bottom, 40)
        .multilineTextAlignment(.center)
    }

    /// Hint that appears above the buttons when a saved career exists.
    /// Format: "Continue: Green Bay Timberjacks — Week 6, 2026 season"
    /// When multiple careers exist the picker provides full context, so the
    /// hint is replaced with a simpler count line.
    @ViewBuilder
    private var continueHintBlock: some View {
        if careers.count > 1 {
            Text("\(careers.count) ACTIVE DYNASTIES")
                .font(DSType.display(DSType.Size.body, .semibold))
                .tracking(1.5)
                .foregroundStyle(Color.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 12)
        } else if let mostRecent = careers.first {
            Text(continueHintText(for: mostRecent))
                .font(DSType.display(DSType.Size.body, .semibold))
                .tracking(1.5)
                .foregroundStyle(Color.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 12)
        }
    }

    private func continueHintText(for career: Career) -> String {
        // Resolve team name from the in-memory teams query (avoid extra fetches).
        let teamName: String
        if let teamID = career.teamID,
           let team = teams.first(where: { $0.id == teamID }) {
            teamName = team.fullName
        } else {
            teamName = career.playerName
        }

        // Build a friendly progress fragment. The season year interpolates as
        // a String so locale digit grouping never renders "2 026".
        let seasonText = String(career.currentSeason)
        let progressFragment: String
        // `.tradeDeadline` is a real regular-season week (the deadline one), so it
        // reads as "Week 9, 2027 season" rather than as a phase name.
        let isGameWeek = career.currentPhase == .regularSeason
            || career.currentPhase == .tradeDeadline
        if isGameWeek && career.currentWeek > 0 {
            progressFragment = String(localized: "Week \(career.currentWeek), \(seasonText) season")
        } else {
            progressFragment = "\(phaseLabel(career.currentPhase)) — \(String(localized: "\(seasonText) season"))"
        }

        return String(localized: "CONTINUE: \(teamName)  -  \(progressFragment)").uppercased()
    }

    private func phaseLabel(_ phase: SeasonPhase) -> String {
        // Football terms (Draft, Combine, Free Agency, …) stay in English by
        // design; only UI-frame phases carry a translation in the catalog.
        switch phase {
        case .proBowl: return String(localized: "All-Star Game")
        case .superBowl: return String(localized: "The Championship")
        case .coachingChanges: return String(localized: "Coaching Changes")
        case .reviewRoster: return String(localized: "Review Roster")
        case .combine: return String(localized: "Combine")
        case .freeAgency: return String(localized: "Free Agency")
        case .proDays: return String(localized: "Pro Days")
        case .draft: return String(localized: "Draft")
        case .otas: return String(localized: "OTAs")
        case .trainingCamp: return String(localized: "Training Camp")
        case .preseason: return String(localized: "Preseason")
        case .rosterCuts: return String(localized: "Roster Cuts")
        case .regularSeason: return String(localized: "Regular Season")
        case .tradeDeadline: return String(localized: "Trade Deadline")
        case .playoffs: return String(localized: "Playoffs")
        }
    }

    private var buttonsBlock: some View {
        VStack(spacing: DSSpacing.md) {
            if careers.count > 1 {
                // Multiple saved careers — open the save slot picker
                Button {
                    activeSheet = .loadCareer
                } label: {
                    MenuButton(title: "Continue / Load", icon: "play.circle.fill")
                }
                .buttonStyle(.dsPrimary)
                .accessibilityLabel("Continue or Load Career")

                NavigationLink(destination: NewCareerView()) {
                    MenuButton(title: "New Career", icon: "plus.circle.fill")
                }
                .buttonStyle(.dsSecondary)
                .accessibilityLabel("New Career")
            } else if let mostRecentCareer = careers.first {
                // Exactly one saved career — keep simple Continue behavior
                Button {
                    PerfLog.mark("career_open")   // R39 (b): Continue tap
                    continueCareer = mostRecentCareer
                } label: {
                    MenuButton(title: "Continue Career", icon: "play.circle.fill")
                }
                .buttonStyle(.dsPrimary)
                .accessibilityLabel("Continue Career")

                NavigationLink(destination: NewCareerView()) {
                    MenuButton(title: "New Career", icon: "plus.circle.fill")
                }
                .buttonStyle(.dsSecondary)
                .accessibilityLabel("New Career")
            } else {
                // No saved careers — New Career is the primary action
                NavigationLink(destination: NewCareerView()) {
                    MenuButton(title: "New Career", icon: "plus.circle.fill")
                }
                .buttonStyle(.dsPrimary)
                .accessibilityLabel("New Career")
            }

            Button {
                activeSheet = .tutorial
            } label: {
                MenuButton(title: "How to Play", icon: "questionmark.circle.fill")
            }
            .buttonStyle(.dsSecondary)
            .accessibilityLabel("How to Play")

            Button {
                activeSheet = .settings
            } label: {
                MenuButton(title: "Settings", icon: "gearshape.fill")
            }
            .buttonStyle(.dsSecondary)
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 40)
        .padding(.bottom, DSSpacing.lg)
        .frame(maxWidth: 480)
    }

    private var footerBlock: some View {
        VStack(spacing: 2) {
            // §2.13's floor: nothing informational is quieter than `textQuiet`.
            // The build stamp is the line QA reads off a screenshot to know which
            // binary it is looking at, and at 25–35 % white over a photo it was
            // not reliably legible at all.
            Text("Sunday Night Dynasty  v\(Self.appVersion) (\(Self.buildNumber))\(Self.buildStamp)")
                .font(DSType.text(DSType.Size.caption, .medium, prose: true))
                .foregroundStyle(Color.white.opacity(0.60))
            Text("\u{00A9} \(Self.currentYear) Sunday Night Dynasty")
                .font(DSType.text(DSType.Size.micro, .regular, prose: true))
                .foregroundStyle(Color.white.opacity(0.50))
        }
        .padding(.bottom, 16)
    }

    // MARK: - Version helpers

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    /// Compile-time provenance: the executable's modification date IS the build
    /// time, so the menu names the exact binary that is running. Ends the
    /// "which build am I actually testing?" class of confusion — an Xcode Run
    /// and a simctl-installed QA build are otherwise indistinguishable (both
    /// say v1.0 (1)).
    ///
    /// DEBUG-only on purpose (#167): reading a file's modification date is a
    /// required-reason API (`NSPrivacyAccessedAPICategoryFileTimestamp`, reason
    /// `C617.1`). Keeping it out of Release means `PrivacyInfo.xcprivacy` only
    /// has to declare UserDefaults, and no shipped code path touches the
    /// timestamp API at all.
    private static var buildStamp: String {
        #if DEBUG
        guard let url = Bundle.main.executableURL,
              let date = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "d.M. HH:mm"
        return "  ·  build \(formatter.string(from: date))"
        #else
        return ""
        #endif
    }

    private static var currentYear: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return formatter.string(from: Date())
    }
}

// MARK: - Menu Button Style

/// The menu's row label — **chrome comes from the shared button styles**.
///
/// This used to be a fourth hand-copied gold recipe: its own `accentGold` fill,
/// its own `cornerRadius: 12`, its own glow, and a secondary variant (black 30 %
/// + white 8 % + a white hairline) that existed nowhere else in the app. §2.8's
/// whole point is that the first screen a player sees should be built out of the
/// same four styles as the last one, so the recipe is gone and the call sites
/// carry `.dsPrimary` / `.dsSecondary`.
///
/// What is left is the menu's own FORMAT — a 22 pt tracked title beside a 22 pt
/// glyph on a 40 pt row. That is a legitimate size decision (a title screen's
/// row is not a toolbar's) and it is now expressed as sizes rather than as
/// chrome.
private struct MenuButton: View {
    let title: LocalizedStringKey
    let icon: String

    var body: some View {
        HStack(spacing: DSSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
            Text(title)
                .font(DSType.text(DSType.Size.title3, .semibold))
                .tracking(2)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 40)
    }
}

// MARK: - Tutorial Sheet

/// Multi-page onboarding flow shown from the main menu.
/// Walks first-time players through the major systems of the game so they know
/// where to look once they hit the Career Dashboard.
private struct TutorialSheet: View {

    @Environment(\.dismiss) private var dismiss
    @State private var currentPage: Int = 0

    private let pages: [TutorialPage] = TutorialPage.all

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Paginated content — swipe horizontally between pages.
                TabView(selection: $currentPage) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        TutorialPageView(page: page)
                            .tag(index)
                            .padding(.horizontal, 4)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                // Page indicator dots
                HStack(spacing: 8) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        Circle()
                            .fill(index == currentPage ? Color.accentBlue : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                            .animation(.easeInOut(duration: 0.2), value: currentPage)
                    }
                }
                .padding(.vertical, 12)

                // Navigation buttons (Back / Next or Done) — §2.5's order and
                // §2.8's style set. The blue-filled Next/Get Started was the
                // third hand-copied commit recipe (`cornerRadius: 10` again, a
                // third corner value on one screen); the tutorial's one primary
                // is now the same gold as every other primary in the app.
                HStack(spacing: DSSpacing.sm) {
                    if currentPage > 0 {
                        Button {
                            withAnimation { currentPage -= 1 }
                        } label: {
                            Label("Back", systemImage: "chevron.left")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.dsGhost)
                    }

                    if currentPage < pages.count - 1 {
                        Button {
                            withAnimation { currentPage += 1 }
                        } label: {
                            Label("Next", systemImage: "chevron.right")
                                .labelStyle(.titleAndIcon)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.dsPrimary)
                    } else {
                        Button {
                            dismiss()
                        } label: {
                            Label("Get Started", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.dsPrimary)
                    }
                }
                .padding(.horizontal, DSSpacing.md)
                .padding(.bottom, DSSpacing.md)
                .padding(.top, DSSpacing.xxs)
            }
            .navigationTitle("How to Play")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip Tutorial") { dismiss() }
                        .font(.subheadline)
                }
                ToolbarItem(placement: .principal) {
                    Text("Page \(currentPage + 1) of \(pages.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Tutorial Page Model

private struct TutorialPage: Identifiable {
    let id: String
    let icon: String
    let iconTint: Color
    let title: String
    let subtitle: String
    let body: String
    /// Optional bulleted list of supporting points (icon + text).
    let points: [(icon: String, text: String)]

    static let all: [TutorialPage] = [
        // 1. Welcome
        TutorialPage(
            id: "welcome",
            icon: "trophy.fill",
            iconTint: .accentGold,
            title: "Welcome to Sunday Night Dynasty",
            subtitle: "Your pro franchise. Your decisions.",
            body: "Take the reins of a pro football franchise as either a General Manager or a dual-role GM and Head Coach. Build a roster through scouting, free agency, and the draft, then guide your team to a Championship title across multiple seasons.",
            points: [
                ("calendar", "Advance the season one week at a time"),
                ("person.3.fill", "Manage roster, coaches, and scouts"),
                ("chart.line.uptrend.xyaxis", "Track owner demands and franchise legacy")
            ]
        ),

        // 2. Career flow
        TutorialPage(
            id: "career",
            icon: "map.fill",
            iconTint: .accentBlue,
            title: "Your Weekly Career Flow",
            subtitle: "Each week walks you through key tasks",
            body: "The Career Dashboard surfaces the right action at the right time. The yearly cycle moves through press conferences, coaching changes, roster review, the combine, free agency, the draft, training camp, and the regular season.",
            points: [
                ("mic.fill", "Press Conf — answer questions, set tone"),
                ("sportscourt.fill", "Coaching — hire and develop staff"),
                ("checklist", "Roster Eval — find weaknesses"),
                ("stopwatch.fill", "Combine — measure prospects"),
                ("dollarsign.circle.fill", "Free Agency — bid on veterans"),
                ("rectangle.stack.person.crop.fill", "Draft — pick the future")
            ]
        ),

        // 3. Scouting
        TutorialPage(
            id: "scouting",
            icon: "magnifyingglass",
            iconTint: .accentBlue,
            title: "Scouting & The Big Board",
            subtitle: "Information is your edge",
            body: "Scout reports are estimates, not facts. Each scout has a role (College, Pro, National) and an accuracy rating — better scouts give tighter percentile ranges. The Big Board ranks prospects by your scouts' consensus, but their grades are educated guesses.",
            points: [
                ("person.fill.checkmark", "Hire scouts that match your needs"),
                ("chart.bar.fill", "Percentile ranges show uncertainty"),
                ("a.square.fill", "Letter grades (A+ to F), not raw numbers"),
                ("eye.fill", "Combine and pro days narrow ranges")
            ]
        ),

        // 4. Free Agency
        TutorialPage(
            id: "freeAgency",
            icon: "dollarsign.circle.fill",
            iconTint: .accentGold,
            title: "Free Agency & The Cap",
            subtitle: "Spend smart, not loud",
            body: "Free Agency runs in weekly rounds. You bid on players using cap space, and rumors hint at competing offers. The strongest bid plus team fit wins — but overspending on one star can lock you out of building depth.",
            points: [
                ("creditcard.fill", "Stay under the salary cap"),
                ("ear.fill", "Rumor system reveals rival interest"),
                ("percent", "Cap % matters more than raw dollars"),
                ("clock.fill", "Top players sign earlier in rounds")
            ]
        ),

        // 5. Draft
        TutorialPage(
            id: "draft",
            icon: "rectangle.stack.person.crop.fill",
            iconTint: .accentBlue,
            title: "The Draft",
            subtitle: "Best Player Available vs. Need",
            body: "When your pick is up, you'll see your scouts' top recommendations and incoming trade offers. BPA (Best Player Available) builds long-term talent; drafting for need fills a hole now. A good GM balances both — and isn't afraid to trade back for picks.",
            points: [
                ("star.fill", "BPA — pick the highest grade"),
                ("target", "Need — fill weak position groups"),
                ("arrow.left.arrow.right", "Trade up, down, or for future picks"),
                ("checkmark.seal.fill", "Scout recommendations highlight value")
            ]
        ),

        // 6. Coaching
        TutorialPage(
            id: "coaching",
            icon: "person.crop.square.filled.and.at.rectangle.fill",
            iconTint: .accentBlue,
            title: "Coaching Staff & Schemes",
            subtitle: "The right scheme amplifies talent",
            body: "Coaches have schemes (e.g. Air Raid, 4-3 Over) and personality archetypes. Players gain familiarity with a scheme over time, and coaches develop expertise as they run it. Locker room chemistry rises when archetypes align.",
            points: [
                ("rectangle.3.group.fill", "Hire by role: HC, OC, DC, position coaches"),
                ("book.fill", "Scheme expertise grows year over year"),
                ("link", "Player familiarity boosts on-field play"),
                ("heart.fill", "Personality fit drives chemistry")
            ]
        ),

        // 7. Coach Mode (R37)
        TutorialPage(
            id: "coachMode",
            icon: "football.fill",
            iconTint: .accentGold,
            title: "Coach Mode: Call the Game",
            subtitle: "Live play-calling on a 3D field",
            body: "Coach your team's games play by play. Pick from the call sheet, snap when ready, and manage the clock. A decision clock keeps the pace — if it runs out, your QB just checks into a safe call, never a penalty. You can hand any game (or the rest of one) to the AI at any time.",
            points: [
                ("book.fill", "Call sheet — plays grouped Run to Deep"),
                ("timer", "Decision clock — safe check-down at zero"),
                ("megaphone.fill", "Audibles — 2 per half, same formation"),
                ("person.2.fill", "Manage — substitutions and hot hands"),
                ("forward.end.fill", "Sim to End whenever you're done")
            ]
        ),

        // 8. Development & Training (R37)
        TutorialPage(
            id: "development",
            icon: "chart.line.uptrend.xyaxis",
            iconTint: .accentBlue,
            title: "Development & Training",
            subtitle: "Rosters are grown, not bought",
            body: "Players develop through training focus, snaps, mentoring, and scheme fit. Weekly practice installs new plays for your call sheet, training camp settles position battles, and young players grow fastest — veterans plateau, then decline. Watch workload: overworked players get hurt.",
            points: [
                ("figure.strengthtraining.functional", "Set a training focus each week"),
                ("person.2.wave.2.fill", "Mentors accelerate young teammates"),
                ("list.clipboard.fill", "Practice a play 2 weeks to install it"),
                ("bolt.heart.fill", "Manage workload to avoid injuries"),
                ("arrow.up.right.circle.fill", "Development peaks in years 2-3")
            ]
        ),

        // 9. Offseason (R37)
        TutorialPage(
            id: "offseason",
            icon: "arrow.triangle.2.circlepath",
            iconTint: .accentGold,
            title: "The Offseason Loop",
            subtitle: "Championships are built in spring",
            body: "After the Championship the calendar resets: coaching changes, roster review, the Combine, free agency, the draft, OTAs, training camp, and roster cuts — then a new season kicks off. Each phase has its own tasks, and every year compounds the last one's decisions.",
            points: [
                ("person.crop.square.filled.and.at.rectangle.fill", "Feb — hire and re-sign your staff"),
                ("stopwatch.fill", "Mar — Combine and free agency"),
                ("rectangle.stack.person.crop.fill", "Apr — the draft"),
                ("sun.max.fill", "Summer — OTAs, camp, preseason"),
                ("scissors", "Aug — cut down to the final 53")
            ]
        ),

        // 10. Tips & FAQ
        TutorialPage(
            id: "tips",
            icon: "lightbulb.fill",
            iconTint: .accentGold,
            title: "Tips & Common Pitfalls",
            subtitle: "Wisdom from the front office",
            body: "A few hard-earned lessons: don't blow your cap on Day 1 of free agency, don't trust a single scout's grade, and don't fire a coach mid-scheme-install. Patience compounds. So does player development.",
            points: [
                ("exclamationmark.triangle.fill", "Avoid huge contracts for aging stars"),
                ("brain.head.profile", "Cross-check scout reports before drafting"),
                ("arrow.up.right.circle.fill", "Rookies improve fastest in years 2-3"),
                ("hand.raised.fill", "Owner demands hint at job security"),
                ("questionmark.circle.fill", "Tap any (?) icon for context help")
            ]
        )
    ]
}

// MARK: - Tutorial Page View

private struct TutorialPageView: View {
    let page: TutorialPage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Hero icon
                HStack {
                    Spacer()
                    Image(systemName: page.icon)
                        .font(.system(size: 64, weight: .semibold))
                        .foregroundStyle(page.iconTint)
                        .frame(width: 120, height: 120)
                        .background(
                            Circle()
                                .fill(page.iconTint.opacity(0.15))
                        )
                    Spacer()
                }
                .padding(.top, 20)
                .padding(.bottom, 8)

                // Title + subtitle
                VStack(alignment: .leading, spacing: 6) {
                    Text(page.title)
                        .font(.title2.bold())
                    Text(page.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Body copy
                Text(page.body)
                    .font(.body)
                    .foregroundStyle(.primary.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)

                // Bulleted points
                if !page.points.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(page.points.enumerated()), id: \.offset) { _, point in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: point.icon)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(page.iconTint)
                                    .frame(width: 24)
                                Text(point.text)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary.opacity(0.9))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.top, 4)
                }

                Spacer(minLength: 12)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Save Slot Picker

/// Sheet shown from the main menu when more than one saved career exists.
/// Lists every Career as a card so the player can pick which dynasty to load
/// (or delete obsolete ones).
private struct SaveSlotPickerSheet: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Career.currentSeason, order: .reverse) private var careers: [Career]
    @Query private var teams: [Team]

    /// Invoked when the player taps Continue on a row.
    /// The parent dismisses the sheet and presents the Career shell.
    let onContinue: (Career) -> Void

    @State private var pendingDeletion: Career?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()

                if careers.isEmpty {
                    Text("No saved careers.")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                } else {
                    ScrollView {
                        VStack(spacing: 14) {
                            ForEach(careers) { career in
                                SaveSlotCard(
                                    career: career,
                                    team: team(for: career),
                                    onContinue: { onContinue(career) },
                                    onDelete: { pendingDeletion = career }
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                    }
                }
            }
            .navigationTitle("Load Career")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .alert(
                "Delete Career?",
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: { if !$0 { pendingDeletion = nil } }
                ),
                presenting: pendingDeletion
            ) { career in
                Button("Delete", role: .destructive) {
                    // Cascade: `Career` has no SwiftData relationships, so
                    // deleting the row alone used to orphan the save's whole
                    // league — 32 teams, ~1 900 players, every game and pick —
                    // permanently, and every `New Career` compounded it.
                    CareerScope.cascadeDelete(career: career, context: modelContext)
                    pendingDeletion = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingDeletion = nil
                }
            } message: { career in
                Text("This permanently removes \(career.playerName)'s dynasty — "
                     + CareerScope.deletionSummary(career: career, context: modelContext)
                     + ". This cannot be undone.")
            }
        }
    }

    private func team(for career: Career) -> Team? {
        guard let teamID = career.teamID else { return nil }
        return teams.first { $0.id == teamID }
    }
}

// MARK: - Save Slot Card

private struct SaveSlotCard: View {
    let career: Career
    let team: Team?
    let onContinue: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header: logo + team / player
            HStack(spacing: 14) {
                TeamLogoPlaceholder(
                    abbreviation: team?.abbreviation ?? "—",
                    size: 56
                )

                // Whose save this is. Two careers on the same team are otherwise
                // told apart only by a name in 13 pt type.
                UserPortraitView(career: career, size: .medium)

                VStack(alignment: .leading, spacing: 4) {
                    Text(team?.fullName ?? "Free Agent")
                        .font(DSType.text(DSType.Size.title3, .bold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Image(systemName: career.role == .gm ? "briefcase.fill" : "sportscourt.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text(career.playerName)
                            .lineLimit(1)
                        Text("•")
                            .foregroundStyle(Color.textSecondary.opacity(0.5))
                        Text(roleLabel)
                            .lineLimit(1)
                    }
                    .font(DSType.text(DSType.Size.footnote, .medium))
                    .foregroundStyle(Color.textSecondary)
                }

                Spacer(minLength: 0)
            }

            // Stats row
            HStack(alignment: .top, spacing: 12) {
                statBlock(
                    title: String(localized: "Season"),
                    value: "\(career.currentSeason)",
                    detail: weekDetail
                )
                Divider()
                    .background(Color.white.opacity(0.1))
                    .frame(height: 36)
                statBlock(
                    title: String(localized: "Phase"),
                    value: phaseLabel(career.currentPhase),
                    detail: nil
                )
                Divider()
                    .background(Color.white.opacity(0.1))
                    .frame(height: 36)
                statBlock(
                    title: String(localized: "Wins"),
                    value: "\(career.totalWins)",
                    detail: String(localized: "\(career.totalLosses) L")
                )
                Divider()
                    .background(Color.white.opacity(0.1))
                    .frame(height: 36)
                statBlock(
                    title: String(localized: "Rings"),
                    value: "\(career.championships)",
                    detail: nil
                )
            }

            // Actions
            // §2.5's button order — destructive first, separated, never
            // adjacent to the primary — on §2.8's one style set. This card
            // carried the app's second hand-copied gold recipe (`cornerRadius:
            // 10` + a raw `Color.red` border, both off the token scale) and had
            // Delete sitting shoulder to shoulder with Continue.
            HStack(spacing: DSSpacing.xs) {
                Button(action: onDelete) {
                    Label("Delete", systemImage: "trash")
                        .frame(width: 96)
                }
                .buttonStyle(.dsDestructive)

                Rectangle()
                    .fill(Color.surfaceBorder)
                    .frame(width: 1, height: 28)

                Button(action: onContinue) {
                    Label("Continue", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.dsPrimary)
            }
        }
        .padding(DSSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.card)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: DSCornerRadius.card)
                        .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                )
        )
    }

    private var roleLabel: String {
        career.role == .gm ? "General Manager" : "GM & Head Coach"
    }

    private var weekDetail: String? {
        career.currentWeek > 0 ? String(localized: "Wk \(career.currentWeek)") : nil
    }

    private func statBlock(title: String, value: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // §2.3's stat grammar: LABEL / value / context, one voice each.
            Text(title.uppercased())
                .font(DSType.display(DSType.Size.caption, .heavy))
                .tracking(0.7)
                .foregroundStyle(Color.textTertiaryReadable)
            Text(value)
                .font(DSType.display(DSType.Size.callout, .black))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let detail {
                Text(detail)
                    .font(DSType.display(DSType.Size.caption, .semibold))
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func phaseLabel(_ phase: SeasonPhase) -> String {
        switch phase {
        case .proBowl: return String(localized: "All-Star Game")
        case .superBowl: return String(localized: "The Championship")
        case .coachingChanges: return String(localized: "Coaching")
        case .reviewRoster: return String(localized: "Review")
        case .combine: return String(localized: "Combine")
        case .freeAgency: return String(localized: "Free Agency")
        case .proDays: return String(localized: "Pro Days")
        case .draft: return String(localized: "Draft")
        case .otas: return String(localized: "OTAs")
        case .trainingCamp: return String(localized: "Camp")
        case .preseason: return String(localized: "Preseason")
        case .rosterCuts: return String(localized: "Cuts")
        case .regularSeason: return String(localized: "Regular")
        case .tradeDeadline: return String(localized: "Trade DL")
        case .playoffs: return String(localized: "Playoffs")
        }
    }
}

// MARK: - Career List View

struct CareerListView: View {

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Career.currentSeason, order: .reverse) private var careers: [Career]
    @State private var selectedCareer: Career?

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            List {
                ForEach(careers) { career in
                    Button {
                        selectedCareer = career
                    } label: {
                        CareerRowView(career: career)
                    }
                    .listRowBackground(Color.backgroundSecondary)
                }
                .onDelete(perform: deleteCareers)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Continue Career")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .fullScreenCover(item: $selectedCareer) { career in
            CareerShellView(career: career)
        }
    }

    private func deleteCareers(at offsets: IndexSet) {
        for index in offsets {
            // Same cascade the save-slot picker runs — deleting only the
            // `Career` row leaves its entire league orphaned in the store.
            CareerScope.cascadeDelete(career: careers[index], context: modelContext)
        }
    }
}

// MARK: - Career Row

private struct CareerRowView: View {
    let career: Career

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(career.playerName)
                .font(.headline)
                .foregroundStyle(Color.textPrimary)

            HStack(spacing: 16) {
                Label(
                    career.role == .gm ? "General Manager" : "GM & Head Coach",
                    systemImage: career.role == .gm ? "briefcase.fill" : "sportscourt.fill"
                )

                Label("Season \(String(career.currentSeason))", systemImage: "calendar")
            }
            .font(.subheadline)
            .foregroundStyle(Color.textSecondary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        MainMenuView()
    }
    .modelContainer(for: Career.self, inMemory: true)
}
