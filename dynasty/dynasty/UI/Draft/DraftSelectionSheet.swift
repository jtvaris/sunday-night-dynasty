import SwiftUI
import SwiftData

// MARK: - Sort Option

private enum DraftSelectionSort: String, CaseIterable, Identifiable {
    case overall    = "Overall"
    case projection = "Projection"
    case position   = "Position"
    case grade      = "Grade"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overall:    return "star.fill"
        case .projection: return "list.number"
        case .position:   return "rectangle.3.group"
        case .grade:      return "checkmark.seal.fill"
        }
    }
}

// MARK: - DraftSelectionSheet

/// Presented as a sheet when it is the player's turn to pick.
struct DraftSelectionSheet: View {

    let career: Career
    let availableProspects: [CollegeProspect]
    let pickNumber: Int
    let round: Int
    let onDraft: (CollegeProspect) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var positionFilter: ProspectPositionFilter = .all
    @State private var sortOption: DraftSelectionSort = .overall
    @State private var selectedProspect: CollegeProspect?
    @State private var showConfirmation = false

    // MARK: - Filtered Prospects

    private var filtered: [CollegeProspect] {
        var result = availableProspects

        if !searchText.isEmpty {
            result = result.filter {
                $0.fullName.localizedCaseInsensitiveContains(searchText) ||
                $0.college.localizedCaseInsensitiveContains(searchText) ||
                $0.position.rawValue.localizedCaseInsensitiveContains(searchText)
            }
        }

        if positionFilter != .all {
            result = result.filter { positionFilter.matches($0.position) }
        }

        switch sortOption {
        case .overall:
            return result.sorted { ($0.scoutedOverall ?? -1) > ($1.scoutedOverall ?? -1) }
        case .projection:
            return result.sorted {
                ($0.draftProjection ?? Int.max) < ($1.draftProjection ?? Int.max)
            }
        case .position:
            return result.sorted {
                let ai = Position.allCases.firstIndex(of: $0.position) ?? 0
                let bi = Position.allCases.firstIndex(of: $1.position) ?? 0
                if ai != bi { return ai < bi }
                return ($0.scoutedOverall ?? 0) > ($1.scoutedOverall ?? 0)
            }
        case .grade:
            return result.sorted {
                let ag = gradeOrder($0.scoutGrade)
                let bg = gradeOrder($1.scoutGrade)
                return ag < bg
            }
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()

                VStack(spacing: 0) {
                    pickHeader
                    filterBar
                    sortBar
                    prospectList
                }
            }
            .navigationTitle("Your Pick")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    sortMenu
                }
            }
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search prospects..."
            )
            .alert("Draft \(selectedProspect?.fullName ?? "")?", isPresented: $showConfirmation) {
                Button("Draft", role: .none) {
                    if let prospect = selectedProspect {
                        onDraft(prospect)
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let p = selectedProspect {
                    Text("\(p.position.rawValue) from \(p.college)\(p.scoutedOverall.map { " — \($0) OVR" } ?? "")")
                }
            }
        }
    }

    // MARK: - Pick Header

    private var pickHeader: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("ON THE CLOCK")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Color.accentGold)
                    .tracking(1.5)
                Text("Round \(round)  ·  Pick \(pickNumber)")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(filtered.count)")
                    .font(.title3.weight(.heavy).monospacedDigit())
                    .foregroundStyle(Color.textPrimary)
                Text("Available")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(Color.backgroundSecondary)
        .overlay(
            Rectangle()
                .fill(Color.accentGold.opacity(0.6))
                .frame(height: 2),
            alignment: .bottom
        )
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ProspectPositionFilter.allCases) { filter in
                    filterChip(filter)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .background(Color.backgroundSecondary)
        .overlay(
            Rectangle()
                .fill(Color.surfaceBorder)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    private func filterChip(_ filter: ProspectPositionFilter) -> some View {
        Button {
            positionFilter = filter
        } label: {
            Text(filter.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(positionFilter == filter ? Color.backgroundPrimary : Color.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(positionFilter == filter ? Color.accentGold : Color.backgroundTertiary)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sort Bar

    private var sortBar: some View {
        HStack(spacing: 0) {
            Text("Sort:")
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
                .padding(.leading, 20)

            ForEach(DraftSelectionSort.allCases) { option in
                Button {
                    sortOption = option
                } label: {
                    Text(option.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(sortOption == option ? Color.accentGold : Color.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .background(Color.backgroundSecondary)
        .overlay(
            Rectangle()
                .fill(Color.surfaceBorder)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort by", selection: $sortOption) {
                ForEach(DraftSelectionSort.allCases) { sort in
                    Label(sort.rawValue, systemImage: sort.icon).tag(sort)
                }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
    }

    // MARK: - Prospect List

    private var prospectList: some View {
        Group {
            if filtered.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "person.slash")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.textTertiary)
                    Text("No Prospects Match")
                        .font(.headline)
                        .foregroundStyle(Color.textSecondary)
                    Text("Adjust your filter or search.")
                        .font(.subheadline)
                        .foregroundStyle(Color.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filtered) { prospect in
                        prospectRow(prospect)
                            .listRowBackground(Color.backgroundSecondary)
                            .listRowSeparatorTint(Color.surfaceBorder)
                    }
                }
                .scrollContentBackground(.hidden)
                .listStyle(.plain)
            }
        }
    }

    private func prospectRow(_ prospect: CollegeProspect) -> some View {
        HStack(spacing: 12) {
            // Position badge
            Text(prospect.position.rawValue)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 36, height: 28)
                .background(positionColor(prospect.position), in: RoundedRectangle(cornerRadius: 4))

            // Name + college
            VStack(alignment: .leading, spacing: 2) {
                Text(prospect.fullName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(prospect.college)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                    if let proj = prospect.draftProjection {
                        Text("·")
                            .foregroundStyle(Color.textTertiary)
                            .font(.caption)
                        Text("Rd \(proj) projection")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }

            Spacer()

            // Grade & overall
            VStack(alignment: .trailing, spacing: 3) {
                if let overall = prospect.scoutedOverall {
                    Text("\(overall)")
                        .font(.callout.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.forRating(overall))
                } else {
                    Text("?")
                        .font(.callout.weight(.bold))
                        .foregroundStyle(Color.textTertiary)
                }
                if let grade = prospect.scoutGrade {
                    Text(grade)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentGold)
                }
            }
            .frame(minWidth: 36)

            // Detail / Draft buttons
            HStack(spacing: 8) {
                NavigationLink {
                    ProspectDetailView(career: career, prospect: prospect)
                } label: {
                    Text("View")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentBlue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.accentBlue.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)

                Button {
                    selectedProspect = prospect
                    showConfirmation = true
                } label: {
                    Text("Draft")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(Color.backgroundPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.accentGold)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    // MARK: - Helpers

    private func positionColor(_ position: Position) -> Color {
        switch position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }

    private func gradeOrder(_ grade: String?) -> Int {
        switch grade {
        case "A+": return 0
        case "A":  return 1
        case "A-": return 2
        case "B+": return 3
        case "B":  return 4
        case "B-": return 5
        case "C+": return 6
        case "C":  return 7
        default:   return 8
        }
    }
}

// MARK: - Preview

#Preview {
    let career = Career(playerName: "John Doe", role: .gm, capMode: .simple)
    let prospects: [CollegeProspect] = [
        CollegeProspect(
            firstName: "Caleb", lastName: "Williams",
            college: "USC", position: .QB,
            age: 21, height: 74, weight: 214,
            truePositionAttributes: .quarterback(QBAttributes(
                armStrength: 92, accuracyShort: 88, accuracyMid: 90,
                accuracyDeep: 85, pocketPresence: 87, scrambling: 78
            )),
            truePersonality: PlayerPersonality(archetype: .fieryCompetitor, motivation: .winning),
            scoutedOverall: 89, scoutGrade: "A", draftProjection: 1
        ),
        CollegeProspect(
            firstName: "Marvin", lastName: "Harrison Jr.",
            college: "Ohio State", position: .WR,
            age: 21, height: 75, weight: 209,
            truePositionAttributes: .wideReceiver(WRAttributes(
                routeRunning: 91, catching: 93, release: 90, spectacularCatch: 88
            )),
            truePersonality: PlayerPersonality(archetype: .quietProfessional, motivation: .winning),
            scoutedOverall: 91, scoutGrade: "A+", draftProjection: 1
        ),
    ]

    DraftSelectionSheet(
        career: career,
        availableProspects: prospects,
        pickNumber: 1,
        round: 1,
        onDraft: { _ in }
    )
    .modelContainer(for: [Career.self, CollegeProspect.self], inMemory: true)
}
