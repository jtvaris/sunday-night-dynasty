import SwiftUI
import SwiftData

// MARK: - CoachingTreeView

/// Displays the player's full coaching tree — every coach who worked under them,
/// where those coaches went, and the legacy score the player has built over their career.
struct CoachingTreeView: View {

    @Bindable var career: Career

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            List {
                legacyScoreSection
                currentStaffSection
                alumniSection
            }
            .scrollContentBackground(.hidden)
            .listStyle(.insetGrouped)
        }
        .navigationTitle("Coaching Tree")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    // MARK: - Coaching Tree Data

    private var tree: CoachingTreeData {
        career.coachingTree
    }

    private var alumni: [CoachRelationshipEngine.CoachingTreeEntry] {
        tree.alumni.sorted { ($0.yearLeft ?? 0) > ($1.yearLeft ?? 0) }
    }

    private var currentStaff: [CoachRelationshipEngine.CoachingTreeEntry] {
        tree.currentStaff.sorted { $0.yearHired > $1.yearHired }
    }

    // MARK: - Legacy Score Section

    private var legacyScoreSection: some View {
        Section("Legacy") {
            VStack(spacing: 16) {
                HStack(alignment: .bottom, spacing: 8) {
                    Text("\(tree.legacyScore)")
                        .font(.system(size: 52, weight: .bold).monospacedDigit())
                        .foregroundStyle(legacyScoreColor)
                    Text("/ 100")
                        .font(.title3)
                        .foregroundStyle(Color.textTertiary)
                        .padding(.bottom, 8)
                }

                Text(legacyScoreLabel)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(legacyScoreColor)

                // Legacy bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.backgroundTertiary)
                            .frame(height: 8)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(legacyScoreColor)
                            .frame(
                                width: geo.size.width * CGFloat(tree.legacyScore) / 100.0,
                                height: 8
                            )
                            .animation(.easeInOut(duration: 0.5), value: tree.legacyScore)
                    }
                }
                .frame(height: 8)

                // Summary stats
                HStack(spacing: 0) {
                    legacyStat(value: tree.entries.count, label: "Total Coaches")
                    legacyStat(value: tree.alumni.count, label: "Alumni")
                    legacyStat(value: tree.headsCoachAlumni.count, label: "HC Alumni")
                    legacyStat(
                        value: tree.alumni.filter { $0.wasSuccessful }.count,
                        label: "Successful"
                    )
                }
            }
            .padding(.vertical, 8)
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    // MARK: - Current Staff Section

    @ViewBuilder
    private var currentStaffSection: some View {
        if !currentStaff.isEmpty {
            Section("Current Staff") {
                ForEach(currentStaff) { entry in
                    coachEntryRow(entry: entry, isCurrent: true)
                }
            }
            .listRowBackground(Color.backgroundSecondary)
        }
    }

    // MARK: - Alumni Section

    @ViewBuilder
    private var alumniSection: some View {
        if alumni.isEmpty {
            Section("Alumni") {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "person.3")
                            .font(.largeTitle)
                            .foregroundStyle(Color.textTertiary)
                        Text("No coaching alumni yet.")
                            .font(.subheadline)
                            .foregroundStyle(Color.textTertiary)
                        Text("As coaches depart for other opportunities,\nthey'll appear here.")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 16)
                    Spacer()
                }
            }
            .listRowBackground(Color.backgroundSecondary)
        } else {
            Section("Alumni (\(alumni.count))") {
                ForEach(alumni) { entry in
                    coachEntryRow(entry: entry, isCurrent: false)
                }
            }
            .listRowBackground(Color.backgroundSecondary)
        }
    }

    // MARK: - Coach Entry Row

    private func coachEntryRow(
        entry: CoachRelationshipEngine.CoachingTreeEntry,
        isCurrent: Bool
    ) -> some View {
        HStack(spacing: 12) {
            // Role badge
            Text(entry.role.abbreviation)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.backgroundPrimary)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(entry.role.badgeColor, in: RoundedRectangle(cornerRadius: 5))
                .frame(width: 44)

            // Name and tenure
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.coachName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)

                if isCurrent {
                    Text("Since \(entry.yearHired)")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                } else {
                    let tenureYears = (entry.yearLeft ?? career.currentSeason) - entry.yearHired
                    let tenureText = tenureYears <= 0 ? "< 1 yr" : "\(tenureYears) yr\(tenureYears == 1 ? "" : "s")"
                    Text("\(entry.yearHired)–\(entry.yearLeft.map(String.init) ?? "Present") · \(tenureText)")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }

                if let destination = entry.destination, !destination.isEmpty {
                    Text(destination)
                        .font(.caption)
                        .foregroundStyle(destinationColor(entry: entry))
                }
            }

            Spacer()

            // Success indicator for alumni
            if !isCurrent {
                successBadge(entry: entry)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.success)
                    .font(.subheadline)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: entry, isCurrent: isCurrent))
    }

    // MARK: - Success Badge

    @ViewBuilder
    private func successBadge(
        entry: CoachRelationshipEngine.CoachingTreeEntry
    ) -> some View {
        if entry.destination?.lowercased().contains("hc") == true ||
           entry.destination?.lowercased().contains("head coach") == true {
            VStack(spacing: 2) {
                Image(systemName: entry.wasSuccessful ? "trophy.fill" : "person.fill")
                    .foregroundStyle(entry.wasSuccessful ? Color.accentGold : Color.textTertiary)
                    .font(.subheadline)
                Text("HC")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(entry.wasSuccessful ? Color.accentGold : Color.textTertiary)
            }
        } else if entry.wasSuccessful {
            Image(systemName: "star.fill")
                .foregroundStyle(Color.accentGold)
                .font(.subheadline)
        } else if entry.yearLeft != nil {
            Image(systemName: "arrow.right.circle")
                .foregroundStyle(Color.textTertiary)
                .font(.subheadline)
        }
    }

    // MARK: - Legacy Stat Helper

    private func legacyStat(value: Int, label: String) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(Color.textPrimary)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value)")
    }

    // MARK: - Computed Helpers

    private var legacyScoreColor: Color {
        switch tree.legacyScore {
        case 70...: return .success
        case 40..<70: return .accentGold
        case 20..<40: return .warning
        default: return .textTertiary
        }
    }

    private var legacyScoreLabel: String {
        switch tree.legacyScore {
        case 80...: return "Hall of Fame Coaching Tree"
        case 60..<80: return "Elite Developer"
        case 40..<60: return "Strong Mentor"
        case 20..<40: return "Building a Legacy"
        case 1..<20:  return "Early Career"
        default:      return "No Legacy Yet"
        }
    }

    private func destinationColor(entry: CoachRelationshipEngine.CoachingTreeEntry) -> Color {
        guard let dest = entry.destination?.lowercased() else { return Color.textSecondary }
        if dest.contains("hc") || dest.contains("head coach") {
            return entry.wasSuccessful ? Color.accentGold : Color.accentBlue
        }
        if dest.contains("retired") { return Color.textTertiary }
        return Color.textSecondary
    }

    private func accessibilityLabel(
        for entry: CoachRelationshipEngine.CoachingTreeEntry,
        isCurrent: Bool
    ) -> String {
        let status = isCurrent ? "current staff member" : "alumni"
        let dest = entry.destination.map { ", \($0)" } ?? ""
        let success = entry.wasSuccessful ? ", successful" : ""
        return "\(entry.coachName), \(entry.role.displayName), \(status)\(dest)\(success)"
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        CoachingTreeView(career: {
            let c = Career(playerName: "Bill Walsh", role: .gmAndHeadCoach, capMode: .simple)

            // Seed some tree entries for the preview
            var entry1 = CoachRelationshipEngine.CoachingTreeEntry(
                coachName: "Mike Holmgren",
                role: .offensiveCoordinator,
                yearHired: 2020,
                yearLeft: 2023,
                destination: "HC at Green Bay",
                wasSuccessful: true
            )
            _ = entry1  // suppress unused warning in preview

            var tree = CoachingTreeData()
            tree.entries = [
                CoachRelationshipEngine.CoachingTreeEntry(
                    coachName: "Mike Holmgren",
                    role: .offensiveCoordinator,
                    yearHired: 2020,
                    yearLeft: 2023,
                    destination: "HC at Green Bay Packers",
                    wasSuccessful: true
                ),
                CoachRelationshipEngine.CoachingTreeEntry(
                    coachName: "Ray Rhodes",
                    role: .defensiveCoordinator,
                    yearHired: 2021,
                    yearLeft: 2024,
                    destination: "DC at Philadelphia Eagles",
                    wasSuccessful: false
                ),
                CoachRelationshipEngine.CoachingTreeEntry(
                    coachName: "Dennis Green",
                    role: .offensiveCoordinator,
                    yearHired: 2024,
                    yearLeft: nil,
                    destination: nil,
                    wasSuccessful: false
                ),
            ]
            c.coachingTree = tree
            return c
        }())
    }
    .modelContainer(for: Career.self, inMemory: true)
}
