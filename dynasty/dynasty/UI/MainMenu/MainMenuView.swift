import SwiftUI
import SwiftData

struct MainMenuView: View {

    @Query(sort: \Career.currentSeason, order: .reverse) private var careers: [Career]
    @State private var showSettings = false

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

                if isLandscape {
                    // Landscape: content in lower-center area
                    VStack(spacing: 16) {
                        Spacer()
                        Spacer()
                        Spacer()
                        titleBlock
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

    private var buttonsBlock: some View {
        VStack(spacing: 16) {
            if let mostRecentCareer = careers.first {
                // Continue Career is the primary action when a saved career exists
                NavigationLink(destination: CareerShellView(career: mostRecentCareer)) {
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
        Text("v2")
            .font(.caption2)
            .foregroundStyle(Color.white.opacity(0.2))
            .padding(.bottom, 16)
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
