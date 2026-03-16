import SwiftUI
import SwiftData

struct ScoutingHubView: View {
    @Bindable var career: Career
    @Environment(\.modelContext) private var modelContext

    @State private var selectedTab: ScoutingTab = .scouts
    @State private var scouts: [Scout] = []
    @State private var prospects: [CollegeProspect] = []
    @State private var showHireScout = false

    private let maxScouts = 8

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                tabPicker
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                Divider()
                    .overlay(Color.surfaceBorder)

                tabContent
            }
        }
        .navigationTitle("Scouting")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { loadData() }
        .sheet(isPresented: $showHireScout, onDismiss: { loadData() }) {
            HireScoutSheet(career: career)
        }
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        Picker("Section", selection: $selectedTab) {
            ForEach(ScoutingTab.allCases) { tab in
                Text(tab.label).tag(tab)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .scouts:
            ScoutTeamView(
                scouts: scouts,
                canHire: scouts.count < maxScouts,
                onHire: { showHireScout = true },
                onFire: { fireScout($0) }
            )
        case .prospects:
            ProspectListView(career: career, prospects: prospects)
        case .bigBoard:
            BigBoardView(career: career, prospects: prospects)
        }
    }

    // MARK: - Data

    private func loadData() {
        guard let teamID = career.teamID else { return }

        let scoutDesc = FetchDescriptor<Scout>(
            predicate: #Predicate { $0.teamID == teamID }
        )
        scouts = (try? modelContext.fetch(scoutDesc)) ?? []

        let prospectDesc = FetchDescriptor<CollegeProspect>(
            predicate: #Predicate { $0.isDeclaringForDraft == true }
        )
        prospects = (try? modelContext.fetch(prospectDesc)) ?? []
    }

    private func fireScout(_ scout: Scout) {
        modelContext.delete(scout)
        try? modelContext.save()
        loadData()
    }
}

// MARK: - Tab Enum

enum ScoutingTab: String, CaseIterable, Identifiable {
    case scouts     = "scouts"
    case prospects  = "prospects"
    case bigBoard   = "bigBoard"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .scouts:    return "Scout Team"
        case .prospects: return "Prospects"
        case .bigBoard:  return "Big Board"
        }
    }
}

// MARK: - Hire Scout Sheet (placeholder)

private struct HireScoutSheet: View {
    let career: Career
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()
                VStack(spacing: 16) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.accentGold)
                    Text("Hire Scout")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color.textPrimary)
                    Text("Scout hiring market coming soon.")
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(40)
            }
            .navigationTitle("Hire Scout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ScoutingHubView(career: Career(
            playerName: "John Doe",
            role: .gm,
            capMode: .simple
        ))
    }
    .modelContainer(for: [Career.self, Scout.self, CollegeProspect.self], inMemory: true)
}
