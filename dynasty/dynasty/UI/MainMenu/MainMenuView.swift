import SwiftUI
import SwiftData

struct MainMenuView: View {

    @Query(sort: \Career.currentSeason, order: .reverse) private var careers: [Career]

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()

                // MARK: - Title Block
                VStack(spacing: 8) {
                    Text("DYNASTY")
                        .font(.system(size: 72, weight: .black))
                        .tracking(10)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.orange, Color.yellow],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Text("NFL Football Manager")
                        .font(.system(size: 20, weight: .medium))
                        .tracking(4)
                        .foregroundStyle(.gray)
                        .textCase(.uppercase)
                }

                Spacer()

                // MARK: - Menu Buttons
                VStack(spacing: 16) {
                    NavigationLink(destination: NewCareerView()) {
                        MenuButton(title: "New Career", icon: "plus.circle.fill")
                    }

                    if !careers.isEmpty {
                        NavigationLink(destination: CareerListView()) {
                            MenuButton(title: "Continue Career", icon: "play.circle.fill")
                        }
                    }
                }
                .padding(.horizontal, 60)

                Spacer()

                // MARK: - Footer
                Text("v1.0")
                    .font(.caption)
                    .foregroundStyle(.gray.opacity(0.5))
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

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
            Text(title)
                .font(.title2.weight(.semibold))
                .tracking(2)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: 400)
        .frame(height: 60)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
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
            Color.black.ignoresSafeArea()

            List {
                ForEach(careers) { career in
                    NavigationLink(destination: CareerDashboardView(career: career)) {
                        CareerRowView(career: career)
                    }
                    .listRowBackground(Color.white.opacity(0.05))
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
                .foregroundStyle(.white)

            HStack(spacing: 16) {
                Label(career.role == .gm ? "General Manager" : "GM & Head Coach",
                      systemImage: career.role == .gm ? "briefcase.fill" : "sportscourt.fill")

                Label("Season \(career.currentSeason)", systemImage: "calendar")
            }
            .font(.subheadline)
            .foregroundStyle(.gray)
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
