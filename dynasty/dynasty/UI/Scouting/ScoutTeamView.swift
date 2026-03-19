import SwiftUI

struct ScoutTeamView: View {
    let scouts: [Scout]
    let canHire: Bool
    let onHire: () -> Void
    let onFire: (Scout) -> Void

    @State private var scoutToFire: Scout?
    @State private var showFireConfirmation = false

    // MARK: - Budget Computed Properties (#232)

    private var totalScoutSalary: Int {
        scouts.reduce(0) { $0 + $1.salary }
    }

    private var formattedTotalSalary: String {
        if totalScoutSalary >= 1000 {
            return String(format: "$%.1fM", Double(totalScoutSalary) / 1000.0)
        }
        return "$\(totalScoutSalary)K"
    }

    /// The most common specialization among scouts, if any.
    private var dominantSpecialization: Position? {
        let specs = scouts.compactMap(\.positionSpecialization)
        guard !specs.isEmpty else { return nil }
        let counts = Dictionary(grouping: specs) { $0 }.mapValues(\.count)
        return counts.max(by: { $0.value < $1.value })?.key
    }

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            if scouts.isEmpty {
                emptyState
            } else {
                List {
                    // Budget impact summary (#232)
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: "dollarsign.circle")
                                .foregroundStyle(Color.accentGold)
                                .font(.caption)
                            Text("Scout salaries: \(formattedTotalSalary) of coaching budget")
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                            Spacer()
                            if let spec = dominantSpecialization {
                                Text("\(spec.rawValue) Specialist: +10% accuracy on \(spec.rawValue) evaluations")
                                    .font(.caption2)
                                    .foregroundStyle(Color.success)
                            }
                        }
                    }
                    .listRowBackground(Color.backgroundSecondary)

                    ForEach(scouts) { scout in
                        NavigationLink(destination: ScoutDetailView(scout: scout)) {
                            ScoutRowView(scout: scout)
                        }
                        .listRowBackground(Color.backgroundSecondary)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                scoutToFire = scout
                                showFireConfirmation = true
                            } label: {
                                Label("Fire", systemImage: "person.fill.xmark")
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .listStyle(.insetGrouped)
            }
        }
        .toolbar {
            if canHire {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        onHire()
                    } label: {
                        Label("Hire Scout", systemImage: "person.badge.plus")
                    }
                    .tint(Color.accentGold)
                }
            }
        }
        .confirmationDialog(
            "Fire \(scoutToFire?.fullName ?? "Scout")?",
            isPresented: $showFireConfirmation,
            titleVisibility: .visible
        ) {
            Button("Fire Scout", role: .destructive) {
                if let scout = scoutToFire { onFire(scout) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This scout will be removed from your staff permanently.")
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.3")
                .font(.system(size: 52))
                .foregroundStyle(Color.textTertiary)

            Text("No Scouts on Staff")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.textPrimary)

            Text("Hire scouts to evaluate college prospects before the draft.")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            if canHire {
                Button(action: onHire) {
                    Label("Hire Your First Scout", systemImage: "person.badge.plus")
                        .font(.headline)
                        .foregroundStyle(Color.backgroundPrimary)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .background(Color.accentGold, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Scout Row View

struct ScoutRowView: View {
    let scout: Scout

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top) {
                // Name and specialization
                VStack(alignment: .leading, spacing: 4) {
                    Text(scout.fullName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)

                    HStack(spacing: 8) {
                        specializationBadge

                        Text("Exp. \(scout.experience) yr\(scout.experience == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)

                        if let spec = scout.positionSpecialization {
                            Text("+10% on \(spec.rawValue)")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(Color.success)
                        }
                    }
                }

                Spacer()

                // Salary
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formattedSalary)
                        .font(.callout.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color.accentGold)
                    Text("/ year")
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                }
            }

            // Stat bars
            VStack(spacing: 6) {
                ScoutStatBar(label: "Accuracy",         value: scout.accuracy)
                ScoutStatBar(label: "Personality Read", value: scout.personalityRead)
                ScoutStatBar(label: "Potential Read",   value: scout.potentialRead)
            }

            // Reports & Pro Days summary (#232)
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text")
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                    Text("~\(estimatedReports) reports")
                        .font(.caption2)
                        .foregroundStyle(Color.textSecondary)
                }

                HStack(spacing: 4) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                    Text("\(scout.proDaysAttended)/5 Pro Days")
                        .font(.caption2)
                        .foregroundStyle(Color.textSecondary)
                }

                Spacer()
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Reports Estimate (#232)

    /// Estimate reports generated based on experience, pro days, and role.
    private var estimatedReports: Int {
        let base = scout.experience * 3
        let proDayReports = scout.proDaysAttended * 4
        return base + proDayReports
    }

    // MARK: - Subviews

    private var specializationBadge: some View {
        let text = scout.positionSpecialization?.rawValue ?? "GEN"
        let color: Color = scout.positionSpecialization != nil ? .accentBlue : .textTertiary

        return Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(Color.textPrimary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.3), in: RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(color.opacity(0.6), lineWidth: 1)
            )
    }

    // MARK: - Helpers

    private var formattedSalary: String {
        if scout.salary >= 1000 {
            return String(format: "$%.1fM", Double(scout.salary) / 1000.0)
        }
        return "$\(scout.salary)K"
    }

    private var accessibilityDescription: String {
        let spec = scout.positionSpecialization?.rawValue ?? "Generalist"
        return "\(scout.fullName), \(spec) specialist, accuracy \(scout.accuracy), salary \(formattedSalary)"
    }
}

// MARK: - Scout Stat Bar

struct ScoutStatBar: View {
    let label: String
    let value: Int

    private var barColor: Color { Color.forRating(value) }

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .frame(width: 120, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.backgroundTertiary)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor)
                        .frame(width: geo.size.width * CGFloat(value) / 100.0)
                }
            }
            .frame(height: 6)

            Text("\(value)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(barColor)
                .frame(width: 28, alignment: .trailing)
        }
        .accessibilityLabel("\(label) \(value) out of 100")
    }
}

// MARK: - Scout Detail View

struct ScoutDetailView: View {
    let scout: Scout

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            List {
                Section("Profile") {
                    LabeledContent("Name", value: scout.fullName)
                    LabeledContent("Specialization") {
                        Text(scout.positionSpecialization?.rawValue ?? "Generalist")
                            .foregroundStyle(
                                scout.positionSpecialization != nil ? Color.accentBlue : Color.textSecondary
                            )
                    }
                    LabeledContent("Experience") {
                        Text("\(scout.experience) year\(scout.experience == 1 ? "" : "s")")
                            .foregroundStyle(Color.textPrimary)
                            .monospacedDigit()
                    }
                    LabeledContent("Annual Salary") {
                        Text(formattedSalary)
                            .foregroundStyle(Color.accentGold)
                            .monospacedDigit()
                    }
                }
                .listRowBackground(Color.backgroundSecondary)

                Section("Scouting Ratings") {
                    AttributeRow(name: "Accuracy",         value: scout.accuracy)
                    AttributeRow(name: "Personality Read", value: scout.personalityRead)
                    AttributeRow(name: "Potential Read",   value: scout.potentialRead)
                }
                .listRowBackground(Color.backgroundSecondary)
            }
            .scrollContentBackground(.hidden)
            .listStyle(.insetGrouped)
        }
        .navigationTitle(scout.fullName)
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private var formattedSalary: String {
        if scout.salary >= 1000 {
            return String(format: "$%.1fM", Double(scout.salary) / 1000.0)
        }
        return "$\(scout.salary)K"
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ScoutTeamView(
            scouts: [
                Scout(
                    firstName: "Ray", lastName: "Collins",
                    positionSpecialization: .QB,
                    accuracy: 78, personalityRead: 65, potentialRead: 82,
                    experience: 5, salary: 250
                ),
                Scout(
                    firstName: "Maria", lastName: "Santos",
                    positionSpecialization: nil,
                    accuracy: 55, personalityRead: 70, potentialRead: 60,
                    experience: 2, salary: 150
                ),
            ],
            canHire: true,
            onHire: {},
            onFire: { _ in }
        )
    }
}
