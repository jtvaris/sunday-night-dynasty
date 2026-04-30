import SwiftUI
import SwiftData

struct MainMenuView: View {

    @Query(sort: \Career.currentSeason, order: .reverse) private var careers: [Career]
    @Query private var teams: [Team]
    @State private var showSettings = false
    @State private var showTutorial = false
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
                    .padding(.bottom, 16)
                }
            }
        }
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showTutorial) {
            TutorialSheet()
        }
        .fullScreenCover(item: $continueCareer) { career in
            CareerShellView(career: career)
        }
    }

    // MARK: - Subviews

    private var titleBlock: some View {
        VStack(spacing: 8) {
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
                .tracking(6)
                .foregroundStyle(Color.white.opacity(0.7))
                .padding(.top, 4)
        }
        .padding(.bottom, 40)
        .multilineTextAlignment(.center)
    }

    /// Hint that appears above the buttons when a saved career exists.
    /// Format: "Continue: Green Bay Packers — Week 6, 2026 season"
    @ViewBuilder
    private var continueHintBlock: some View {
        if let mostRecent = careers.first {
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

        // Build a friendly progress fragment.
        let progressFragment: String
        if career.currentPhase == .regularSeason && career.currentWeek > 0 {
            progressFragment = "Week \(career.currentWeek), \(career.currentSeason) season"
        } else {
            progressFragment = "\(phaseLabel(career.currentPhase)) — \(career.currentSeason) season"
        }

        return "CONTINUE: \(teamName.uppercased())  -  \(progressFragment.uppercased())"
    }

    private func phaseLabel(_ phase: SeasonPhase) -> String {
        switch phase {
        case .proBowl: return "Pro Bowl"
        case .superBowl: return "Super Bowl"
        case .coachingChanges: return "Coaching Changes"
        case .reviewRoster: return "Review Roster"
        case .combine: return "Combine"
        case .freeAgency: return "Free Agency"
        case .proDays: return "Pro Days"
        case .draft: return "Draft"
        case .otas: return "OTAs"
        case .trainingCamp: return "Training Camp"
        case .preseason: return "Preseason"
        case .rosterCuts: return "Roster Cuts"
        case .regularSeason: return "Regular Season"
        case .tradeDeadline: return "Trade Deadline"
        case .playoffs: return "Playoffs"
        }
    }

    private var buttonsBlock: some View {
        VStack(spacing: 16) {
            if let mostRecentCareer = careers.first {
                // Continue Career is the primary action when a saved career exists
                Button {
                    continueCareer = mostRecentCareer
                } label: {
                    MenuButton(title: "Continue Career", icon: "play.circle.fill", isPrimary: true)
                }
                .accessibilityLabel("Continue Career")

                NavigationLink(destination: NewCareerView()) {
                    MenuButton(title: "New Career", icon: "plus.circle.fill", isPrimary: false)
                }
                .accessibilityLabel("New Career")

                if careers.count > 1 {
                    NavigationLink(destination: CareerListView()) {
                        MenuButton(title: "All Careers", icon: "list.bullet", isPrimary: false)
                    }
                    .accessibilityLabel("All Careers")
                }
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
    let title: String
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
                .fill(isPrimary ? Color.accentGold : Color.white.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(isPrimary ? Color.clear : Color.white.opacity(0.25), lineWidth: 1)
                )
                .shadow(color: isPrimary ? Color.accentGold.opacity(0.3) : Color.clear, radius: 12, y: 4)
        )
    }
}

// MARK: - Tutorial Sheet

/// Lightweight onboarding sheet shown from the main menu.
/// Acts as a placeholder until the full tutorial flow ships.
private struct TutorialSheet: View {

    @Environment(\.dismiss) private var dismiss

    private let bullets: [(icon: String, title: String, body: String)] = [
        (
            "person.crop.circle.badge.plus",
            "Build your career",
            "Choose to be a General Manager or take on both GM and Head Coach duties. Your decisions shape the franchise."
        ),
        (
            "sportscourt.fill",
            "Run your team week by week",
            "Manage the roster, hire coaches, scout prospects, and advance the season one week at a time from the Career Dashboard."
        ),
        (
            "magnifyingglass",
            "Scout, draft, and sign players",
            "Use the Scouting Hub for the combine and Big Board, then build your team in Free Agency and the Draft."
        ),
        (
            "trophy.fill",
            "Win championships, build a legacy",
            "Hit owner demands, keep the locker room happy, and chase Super Bowl glory across multiple seasons."
        ),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Welcome to Sunday Night Dynasty")
                        .font(.title2.bold())
                        .padding(.top, 8)

                    Text("A full tutorial is on the way. Here is the short version:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(bullets, id: \.title) { bullet in
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: bullet.icon)
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(Color.accentBlue)
                                    .frame(width: 32)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(bullet.title)
                                        .font(.headline)
                                    Text(bullet.body)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.top, 4)

                    Text("Tip: Tap the help icon inside any screen for context-specific guidance (coming soon).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 12)
                }
                .padding(20)
            }
            .navigationTitle("How to Play")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
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
