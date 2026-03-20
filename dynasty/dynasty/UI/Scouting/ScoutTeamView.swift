import SwiftUI

struct ScoutTeamView: View {
    let scouts: [Scout]
    let canHire: Bool
    let career: Career
    let scoutsSentToCombine: Bool
    let onHire: () -> Void
    let onFire: (Scout) -> Void
    let onSendToCombine: () -> Void

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

                    // Send Scouts to Combine button
                    if career.currentPhase == .combine {
                        Section {
                            sendScoutsToCombineRow
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    }

                    // Table header
                    Section {
                        scoutTableHeader
                            .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))

                        ForEach(scouts, id: \.id) { scout in
                            NavigationLink(value: scout) {
                                ScoutTableRow(scout: scout)
                            }
                            .buttonStyle(.plain)
                                .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
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
                    .listRowBackground(Color.backgroundSecondary)
                }
                .scrollContentBackground(.hidden)
                .listStyle(.insetGrouped)
                .navigationDestination(for: Scout.self) { scout in
                    ScoutDetailView(scout: scout)
                }
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

    // MARK: - Send Scouts to Combine Row

    private var sendScoutsToCombineRow: some View {
        Group {
            if scoutsSentToCombine {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.success)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Scouts at Combine")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color.success)
                        Text("Results are in \u{2014} check the Combine tab")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(Color.success.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.success.opacity(0.3), lineWidth: 1))
            } else {
                Button {
                    onSendToCombine()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "binoculars.fill")
                            .font(.title3)
                            .foregroundStyle(Color.accentGold)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Send Scouts to NFL Combine")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Color.textPrimary)
                            Text("\(scouts.count) scout\(scouts.count == 1 ? "" : "s") will evaluate ~330 prospects")
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Color.accentGold)
                    }
                    .padding(12)
                    .background(Color.accentGold.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentGold.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Table Header

    private var scoutTableHeader: some View {
        HStack(spacing: 0) {
            Text("Role")
                .frame(width: 36, alignment: .leading)
            Text("Name")
                .frame(minWidth: 100, alignment: .leading)
            Text("Spec")
                .frame(width: 40, alignment: .center)
            Text("ACC")
                .frame(width: 36, alignment: .center)
            Text("PER")
                .frame(width: 36, alignment: .center)
            Text("POT")
                .frame(width: 36, alignment: .center)
            Text("Salary")
                .frame(width: 56, alignment: .trailing)
            Spacer(minLength: 4)
            Text("Focus Assignment")
                .frame(minWidth: 180, alignment: .center)
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(Color.textTertiary)
        .padding(.vertical, 6)
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

// MARK: - Scout Table Row

struct ScoutTableRow: View {
    @Bindable var scout: Scout

    var body: some View {
        HStack(spacing: 0) {
            // Role badge
            Text(scout.scoutRole.abbreviation)
                .font(.caption2.weight(.bold))
                .foregroundStyle(scout.scoutRole.isChief ? Color.accentGold : Color.textPrimary)
                .frame(width: 36, alignment: .leading)

            // Name
            VStack(alignment: .leading, spacing: 1) {
                Text(scout.fullName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text("\(scout.experience) yr exp")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.textTertiary)
            }
            .frame(minWidth: 100, alignment: .leading)

            // Specialization position
            Text(scout.positionSpecialization?.rawValue ?? "GEN")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(scout.positionSpecialization != nil ? Color.accentBlue : Color.textTertiary)
                .frame(width: 40, alignment: .center)

            // Accuracy
            ratingCell(value: scout.accuracy)
                .frame(width: 36, alignment: .center)

            // Personality Read
            ratingCell(value: scout.personalityRead)
                .frame(width: 36, alignment: .center)

            // Potential Read
            ratingCell(value: scout.potentialRead)
                .frame(width: 36, alignment: .center)

            // Salary
            Text(formattedSalary)
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.accentGold)
                .frame(width: 56, alignment: .trailing)

            Spacer(minLength: 4)

            // Focus assignment — prominent dropdowns
            HStack(spacing: 6) {
                Menu {
                    Button("All Positions") { scout.focusPosition = nil }
                    ForEach(Position.allCases, id: \.self) { pos in
                        Button(pos.rawValue) { scout.focusPosition = pos }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 10))
                        Text(scout.focusPosition?.rawValue ?? "All Pos.")
                            .font(.caption.weight(.semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(Color.accentGold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.accentGold.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.accentGold.opacity(0.3), lineWidth: 1)
                    )
                }

                Menu {
                    Button("General") { scout.focusAttribute = nil }
                    ForEach(ScoutFocusAttribute.allCases) { attr in
                        Button {
                            scout.focusAttribute = attr
                        } label: {
                            Label(attr.label, systemImage: attr.icon)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: scout.focusAttribute?.icon ?? "gearshape")
                            .font(.system(size: 10))
                        Text(scout.focusAttribute?.label ?? "General")
                            .font(.caption.weight(.semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(Color.accentBlue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.accentBlue.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.accentBlue.opacity(0.3), lineWidth: 1)
                    )
                }
            }
            .frame(minWidth: 180, alignment: .center)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Helpers

    private func ratingCell(value: Int) -> some View {
        Text("\(value)")
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(Color.forRating(value))
    }

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

// MARK: - Scout Row View (used in scout pickers elsewhere)

struct ScoutRowView: View {
    @Bindable var scout: Scout

    var body: some View {
        HStack(spacing: 10) {
            Text(scout.scoutRole.abbreviation)
                .font(.caption2.weight(.bold))
                .foregroundStyle(scout.scoutRole.isChief ? Color.accentGold : Color.textPrimary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                Text(scout.fullName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)

                HStack(spacing: 6) {
                    Text(scout.positionSpecialization?.rawValue ?? "Generalist")
                        .font(.caption)
                        .foregroundStyle(scout.positionSpecialization != nil ? Color.accentBlue : Color.textTertiary)
                    Text("Acc \(scout.accuracy)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color.forRating(scout.accuracy))
                }
            }

            Spacer()

            Text(formattedSalary)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.accentGold)
        }
        .padding(.vertical, 4)
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
            career: Career(
                playerName: "John Doe",
                role: .gm,
                capMode: .simple
            ),
            scoutsSentToCombine: false,
            onHire: {},
            onFire: { _ in },
            onSendToCombine: {}
        )
    }
}
