import SwiftUI
import SwiftData

struct MainMenuView: View {

    @Query(sort: \Career.currentSeason, order: .reverse) private var careers: [Career]

    var body: some View {
        ZStack {
            Color.backgroundPrimary
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // MARK: - Trophy + Title Block
                ZStack {
                    // Trophy behind title, faded
                    LombardiTrophyView()
                        .frame(width: 140, height: 280)
                        .opacity(0.25)
                        .offset(y: -10)

                    VStack(spacing: 8) {
                        Text("SUNDAY NIGHT")
                            .font(.system(size: 24, weight: .bold))
                            .tracking(8)
                            .foregroundStyle(Color.accentGold)

                        Text("DYNASTY")
                            .font(.system(size: 72, weight: .black))
                            .tracking(10)
                            .foregroundStyle(Color.textPrimary)

                        Text("NFL FOOTBALL MANAGER")
                            .font(.system(size: 16, weight: .medium))
                            .tracking(6)
                            .foregroundStyle(Color.textSecondary)
                            .padding(.top, 4)
                    }
                }

                Spacer()

                // MARK: - Menu Buttons
                VStack(spacing: 16) {
                    NavigationLink(destination: NewCareerView()) {
                        MenuButton(title: "New Career", icon: "plus.circle.fill", isPrimary: true)
                    }

                    if !careers.isEmpty {
                        NavigationLink(destination: CareerListView()) {
                            MenuButton(title: "Continue Career", icon: "play.circle.fill", isPrimary: false)
                        }
                    }
                }
                .padding(.horizontal, 60)

                Spacer()

                // MARK: - Footer
                Text("v1.0")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                    .padding(.bottom, 20)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
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
                .font(.title2)
            Text(title)
                .font(.title2.weight(.semibold))
                .tracking(2)
        }
        .foregroundStyle(isPrimary ? Color.backgroundPrimary : Color.textPrimary)
        .frame(maxWidth: 400)
        .frame(height: 60)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isPrimary ? Color.accentGold : Color.backgroundTertiary)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(isPrimary ? Color.clear : Color.surfaceBorder, lineWidth: 1)
                )
        )
    }
}

// MARK: - Career List View

struct CareerListView: View {

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Career.currentSeason, order: .reverse) private var careers: [Career]

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            List {
                ForEach(careers) { career in
                    NavigationLink(destination: CareerDashboardView(career: career)) {
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

                Label("Season \(career.currentSeason)", systemImage: "calendar")
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
