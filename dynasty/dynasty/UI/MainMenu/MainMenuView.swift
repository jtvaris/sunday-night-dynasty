import SwiftUI
import SwiftData

struct MainMenuView: View {

    @Query(sort: \Career.currentSeason, order: .reverse) private var careers: [Career]
    @Query private var teams: [Team]
    @State private var showSettings = false
    @State private var showTutorial = false
    @State private var showSlotPicker = false
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
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showTutorial) {
            TutorialSheet()
        }
        .sheet(isPresented: $showSlotPicker) {
            SaveSlotPickerSheet(
                onContinue: { career in
                    showSlotPicker = false
                    // Defer presentation of the full-screen cover until the sheet
                    // has dismissed to avoid a presentation conflict.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        PerfLog.mark("career_open")   // R39 (b): slot-picker path
                        continueCareer = career
                    }
                }
            )
        }
        .fullScreenCover(item: $continueCareer) { career in
            CareerShellView(career: career)
        }
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

            Text("SUNDAY NIGHT")
                .font(.system(size: 22, weight: .bold))
                .tracking(10)
                .foregroundStyle(Color.accentGold)

            Text("DYNASTY")
                .font(.system(size: 64, weight: .black))
                .tracking(12)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 8, y: 4)

            Text("NFL FOOTBALL MANAGER")
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
    /// Format: "Continue: Green Bay Packers — Week 6, 2026 season"
    /// When multiple careers exist the picker provides full context, so the
    /// hint is replaced with a simpler count line.
    @ViewBuilder
    private var continueHintBlock: some View {
        if careers.count > 1 {
            Text("\(careers.count) ACTIVE DYNASTIES")
                .font(.system(size: 13, weight: .medium))
                .tracking(1.5)
                .foregroundStyle(Color.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 12)
        } else if let mostRecent = careers.first {
            Text(continueHintText(for: mostRecent))
                .font(.system(size: 13, weight: .medium))
                .tracking(1.5)
                .foregroundStyle(Color.white.opacity(0.75))
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
        if career.currentPhase == .regularSeason && career.currentWeek > 0 {
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
        case .proBowl: return String(localized: "Pro Bowl")
        case .superBowl: return String(localized: "Super Bowl")
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
        VStack(spacing: 16) {
            if careers.count > 1 {
                // Multiple saved careers — open the save slot picker
                Button {
                    showSlotPicker = true
                } label: {
                    MenuButton(title: "Continue / Load", icon: "play.circle.fill", isPrimary: true)
                }
                .accessibilityLabel("Continue or Load Career")

                NavigationLink(destination: NewCareerView()) {
                    MenuButton(title: "New Career", icon: "plus.circle.fill", isPrimary: false)
                }
                .accessibilityLabel("New Career")
            } else if let mostRecentCareer = careers.first {
                // Exactly one saved career — keep simple Continue behavior
                Button {
                    PerfLog.mark("career_open")   // R39 (b): Continue tap
                    continueCareer = mostRecentCareer
                } label: {
                    MenuButton(title: "Continue Career", icon: "play.circle.fill", isPrimary: true)
                }
                .accessibilityLabel("Continue Career")

                NavigationLink(destination: NewCareerView()) {
                    MenuButton(title: "New Career", icon: "plus.circle.fill", isPrimary: false)
                }
                .accessibilityLabel("New Career")
            } else {
                // No saved careers — New Career is the primary action
                NavigationLink(destination: NewCareerView()) {
                    MenuButton(title: "New Career", icon: "plus.circle.fill", isPrimary: true)
                }
                .accessibilityLabel("New Career")
            }

            Button {
                showTutorial = true
            } label: {
                MenuButton(title: "How to Play", icon: "questionmark.circle.fill", isPrimary: false)
            }
            .accessibilityLabel("How to Play")

            Button {
                showSettings = true
            } label: {
                MenuButton(title: "Settings", icon: "gearshape.fill", isPrimary: false)
            }
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 24)
        .frame(maxWidth: 480)
    }

    private var footerBlock: some View {
        VStack(spacing: 2) {
            Text("Sunday Night Dynasty  v\(Self.appVersion) (\(Self.buildNumber))")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.35))
            Text("\u{00A9} \(Self.currentYear) Sunday Night Dynasty")
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.25))
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

    private static var currentYear: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return formatter.string(from: Date())
    }
}

// MARK: - Menu Button Style

private struct MenuButton: View {
    let title: LocalizedStringKey
    let icon: String
    let isPrimary: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .tracking(2)
        }
        .foregroundStyle(isPrimary ? Color.backgroundPrimary : .white)
        .frame(maxWidth: 400)
        .frame(height: 56)
        .background(
            RoundedRectangle(cornerRadius: 12)
                // Secondary buttons: dark base + frosted tint so white labels stay
                // legible against busy photo areas (persona audit contrast fix).
                .fill(isPrimary ? Color.accentGold : Color.black.opacity(0.30))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isPrimary ? Color.clear : Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(isPrimary ? Color.clear : Color.white.opacity(0.35), lineWidth: 1)
                )
                .shadow(color: isPrimary ? Color.accentGold.opacity(0.3) : Color.clear, radius: 12, y: 4)
        )
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

                // Navigation buttons (Back / Next or Done)
                HStack(spacing: 12) {
                    if currentPage > 0 {
                        Button {
                            withAnimation { currentPage -= 1 }
                        } label: {
                            Label("Back", systemImage: "chevron.left")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.secondary.opacity(0.15))
                                )
                        }
                    }

                    if currentPage < pages.count - 1 {
                        Button {
                            withAnimation { currentPage += 1 }
                        } label: {
                            HStack {
                                Text("Next")
                                Image(systemName: "chevron.right")
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.accentBlue)
                            )
                        }
                    } else {
                        Button {
                            dismiss()
                        } label: {
                            Label("Get Started", systemImage: "checkmark.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.accentBlue)
                                )
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .padding(.top, 4)
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
            subtitle: "Your NFL franchise. Your decisions.",
            body: "Take the reins of an NFL franchise as either a General Manager or a dual-role GM and Head Coach. Build a roster through scouting, free agency, and the draft, then guide your team to a Super Bowl title across multiple seasons.",
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
            body: "After the Super Bowl the calendar resets: coaching changes, roster review, the Combine, free agency, the draft, OTAs, training camp, and roster cuts — then a new season kicks off. Each phase has its own tasks, and every year compounds the last one's decisions.",
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
                    modelContext.delete(career)
                    pendingDeletion = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingDeletion = nil
                }
            } message: { career in
                Text("This permanently removes \(career.playerName)'s dynasty. This cannot be undone.")
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

                VStack(alignment: .leading, spacing: 4) {
                    Text(team?.fullName ?? "Free Agent")
                        .font(.system(size: 18, weight: .bold))
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
                    .font(.system(size: 13, weight: .medium))
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
            HStack(spacing: 10) {
                Button(action: onContinue) {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                        Text("Continue")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.accentGold)
                    )
                    .foregroundStyle(Color.backgroundPrimary)
                }
                .buttonStyle(.plain)

                Button(action: onDelete) {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                        Text("Delete")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 110)
                    .frame(height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.red.opacity(0.6), lineWidth: 1)
                    )
                    .foregroundStyle(Color.red.opacity(0.9))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
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
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(1)
                .foregroundStyle(Color.textSecondary.opacity(0.7))
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let detail {
                Text(detail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func phaseLabel(_ phase: SeasonPhase) -> String {
        switch phase {
        case .proBowl: return String(localized: "Pro Bowl")
        case .superBowl: return String(localized: "Super Bowl")
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
            modelContext.delete(careers[index])
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
