import SwiftUI
import SwiftData

// MARK: - Scheme Selection View (#67)

/// Allows changing a coordinator's offensive or defensive scheme.
/// Presents all available schemes with a roster fit preview for each.
struct SchemeSelectionView: View {

    let coordinator: Coach
    let players: [Player]
    let isOffensive: Bool
    var coaches: [Coach] = []

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Coordinator info header
                    coordinatorHeader

                    // Scheme options grouped by family
                    if isOffensive {
                        ForEach(offensiveFamilies, id: \.family) { group in
                            schemeFamilySection(
                                family: group.family,
                                description: group.description,
                                content: AnyView(
                                    VStack(spacing: 8) {
                                        ForEach(group.schemes, id: \.self) { scheme in
                                            offensiveSchemeRow(scheme)
                                        }
                                    }
                                )
                            )
                        }
                    } else {
                        ForEach(defensiveFamilies, id: \.family) { group in
                            schemeFamilySection(
                                family: group.family,
                                description: group.description,
                                content: AnyView(
                                    VStack(spacing: 8) {
                                        ForEach(group.schemes, id: \.self) { scheme in
                                            defensiveSchemeRow(scheme)
                                        }
                                    }
                                )
                            )
                        }
                    }

                    // Coordinator aptitude note
                    aptitudeNote
                }
                .padding(16)
            }
            .background(Color.backgroundPrimary)
            .navigationTitle("Select Scheme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(Color.textSecondary)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    // MARK: - Scheme Family Groupings

    /// Pretty grouping for offensive schemes shown in this picker.
    private var offensiveFamilies: [(family: String, description: String, schemes: [OffensiveScheme])] {
        [
            (
                family: "Pass-First",
                description: "Spread the field and attack through the air.",
                schemes: [.westCoast, .airRaid, .proPassing, .spread]
            ),
            (
                family: "Run-First",
                description: "Establish the run and use play-action off it.",
                schemes: [.powerRun, .shanahan, .option, .rpo]
            )
        ]
    }

    /// Pretty grouping for defensive schemes.
    private var defensiveFamilies: [(family: String, description: String, schemes: [DefensiveScheme])] {
        [
            (
                family: "Aggressive / Man",
                description: "Press at the line and pressure the QB.",
                schemes: [.pressMan, .base43]
            ),
            (
                family: "Zone-Heavy",
                description: "Read-and-react with disciplined zone coverage.",
                schemes: [.cover3, .tampa2, .base34]
            ),
            (
                family: "Hybrid / Multiple",
                description: "Disguise looks and rotate fronts pre-snap.",
                schemes: [.multiple, .hybrid]
            )
        ]
    }

    /// Wraps a family of schemes with a header.
    @ViewBuilder
    private func schemeFamilySection(family: String, description: String, content: AnyView) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.accentGold)
                Text(family.uppercased())
                    .font(.system(size: 11, weight: .black))
                    .tracking(1.5)
                    .foregroundStyle(Color.accentGold)
            }
            Text(description)
                .font(.system(size: 10))
                .foregroundStyle(Color.textTertiary)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Coordinator Header

    private var coordinatorHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: isOffensive ? "football.fill" : "shield.fill")
                .font(.title2)
                .foregroundStyle(isOffensive ? Color.accentBlue : Color.danger)

            VStack(alignment: .leading, spacing: 4) {
                Text(coordinator.fullName)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                Text(coordinator.role == .offensiveCoordinator ? "Offensive Coordinator" : "Defensive Coordinator")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("Play Calling")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.textTertiary)
                Text("\(coordinator.playCalling)")
                    .font(.system(size: 16, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color.forRating(coordinator.playCalling))
            }
        }
        .padding(16)
        .cardBackground()
    }

    // MARK: - Offensive Scheme Row

    private func offensiveSchemeRow(_ scheme: OffensiveScheme) -> some View {
        let isSelected = coordinator.offensiveScheme == scheme
        let expertiseValue = coordinator.expertise(for: scheme.rawValue)
        let expertiseColor = schemeExpertiseColor(expertiseValue)
        let coachFit = staffCoachFit(schemeKey: scheme.rawValue, isOffensive: true)
        let rosterFam = rosterFamiliarity(schemeKey: scheme.rawValue, side: .offense)
        let coachesKnowing = coachesKnowingScheme(key: scheme.rawValue)

        return Button {
            selectOffensiveScheme(scheme)
        } label: {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    // Selection indicator
                    Circle()
                        .fill(isSelected ? Color.accentGold : Color.clear)
                        .overlay(
                            Circle()
                                .strokeBorder(isSelected ? Color.accentGold : Color.textTertiary, lineWidth: 2)
                        )
                        .frame(width: 20, height: 20)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(scheme.displayName)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(isSelected ? Color.accentGold : Color.textPrimary)

                            // Per-scheme coach availability badge
                            coachAvailabilityBadge(count: coachesKnowing)
                        }

                        Text(offensiveSchemeDescription(scheme))
                            .font(.system(size: 10))
                            .foregroundStyle(Color.textTertiary)
                            .lineLimit(2)
                    }

                    Spacer()

                    // Coach expertise (coordinator)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(expertiseValue)%")
                            .font(.system(size: 14, weight: .bold).monospacedDigit())
                            .foregroundStyle(expertiseColor)
                        Text("Expertise")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(Color.textTertiary)
                    }
                }

                // Coach Fit + Roster Familiarity bars
                VStack(spacing: 4) {
                    schemeMetricBar(
                        label: "Staff Fit",
                        percent: coachFit,
                        icon: "person.2.fill"
                    )
                    schemeMetricBar(
                        label: "Roster Fam",
                        percent: rosterFam,
                        icon: "person.3.fill"
                    )
                }
                .padding(.top, 8)
                .padding(.leading, 32)

                // Low expertise warning
                if expertiseValue < 40 {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                        Text("Coach has only \(expertiseValue)% expertise -- players will learn slower")
                            .font(.system(size: 9))
                    }
                    .foregroundStyle(Color.warning)
                    .padding(.top, 6)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentGold.opacity(0.08) : Color.backgroundSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(
                                isSelected ? Color.accentGold.opacity(0.5) : Color.surfaceBorder,
                                lineWidth: isSelected ? 1.5 : 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Defensive Scheme Row

    private func defensiveSchemeRow(_ scheme: DefensiveScheme) -> some View {
        let isSelected = coordinator.defensiveScheme == scheme
        let expertiseValue = coordinator.expertise(for: scheme.rawValue)
        let expertiseColor = schemeExpertiseColor(expertiseValue)
        let coachFit = staffCoachFit(schemeKey: scheme.rawValue, isOffensive: false)
        let rosterFam = rosterFamiliarity(schemeKey: scheme.rawValue, side: .defense)
        let coachesKnowing = coachesKnowingScheme(key: scheme.rawValue)

        return Button {
            selectDefensiveScheme(scheme)
        } label: {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(isSelected ? Color.accentGold : Color.clear)
                        .overlay(
                            Circle()
                                .strokeBorder(isSelected ? Color.accentGold : Color.textTertiary, lineWidth: 2)
                        )
                        .frame(width: 20, height: 20)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(scheme.displayName)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(isSelected ? Color.accentGold : Color.textPrimary)

                            // Per-scheme coach availability badge
                            coachAvailabilityBadge(count: coachesKnowing)
                        }

                        Text(defensiveSchemeDescription(scheme))
                            .font(.system(size: 10))
                            .foregroundStyle(Color.textTertiary)
                            .lineLimit(2)
                    }

                    Spacer()

                    // Coach expertise (coordinator)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(expertiseValue)%")
                            .font(.system(size: 14, weight: .bold).monospacedDigit())
                            .foregroundStyle(expertiseColor)
                        Text("Expertise")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(Color.textTertiary)
                    }
                }

                // Coach Fit + Roster Familiarity bars
                VStack(spacing: 4) {
                    schemeMetricBar(
                        label: "Staff Fit",
                        percent: coachFit,
                        icon: "person.2.fill"
                    )
                    schemeMetricBar(
                        label: "Roster Fam",
                        percent: rosterFam,
                        icon: "person.3.fill"
                    )
                }
                .padding(.top, 8)
                .padding(.leading, 32)

                // Low expertise warning
                if expertiseValue < 40 {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                        Text("Coach has only \(expertiseValue)% expertise -- players will learn slower")
                            .font(.system(size: 9))
                    }
                    .foregroundStyle(Color.warning)
                    .padding(.top, 6)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentGold.opacity(0.08) : Color.backgroundSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(
                                isSelected ? Color.accentGold.opacity(0.5) : Color.surfaceBorder,
                                lineWidth: isSelected ? 1.5 : 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Aptitude Note

    private var aptitudeNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("COORDINATOR APTITUDE")
                .font(.system(size: 11, weight: .black))
                .tracking(1.5)
                .foregroundStyle(Color.accentGold)

            HStack(spacing: 16) {
                aptitudeStatView(label: "Play Calling", value: coordinator.playCalling)
                aptitudeStatView(label: "Adaptability", value: coordinator.adaptability)
                aptitudeStatView(label: "Game Planning", value: coordinator.gamePlanning)
            }

            Text("A coordinator's play calling and adaptability determine how effectively they can run each scheme. Higher adaptability means smoother transitions when changing schemes.")
                .font(.system(size: 10))
                .foregroundStyle(Color.textTertiary)
        }
        .padding(16)
        .cardBackground()
    }

    private func aptitudeStatView(label: String, value: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 16, weight: .bold).monospacedDigit())
                .foregroundStyle(Color.forRating(value))
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private func selectOffensiveScheme(_ scheme: OffensiveScheme) {
        coordinator.offensiveScheme = scheme
        try? modelContext.save()
        dismiss()
    }

    private func selectDefensiveScheme(_ scheme: DefensiveScheme) {
        coordinator.defensiveScheme = scheme
        try? modelContext.save()
        dismiss()
    }

    // MARK: - Shared Metric Bar

    private func schemeMetricBar(label: String, percent: Int, icon: String) -> some View {
        let color = metricColor(percent)
        return HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 8))
                .foregroundStyle(color)
                .frame(width: 12)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.textTertiary)
                .frame(width: 58, alignment: .leading)
            Text("\(percent)%")
                .font(.system(size: 9, weight: .bold).monospacedDigit())
                .foregroundStyle(color)
                .frame(width: 28, alignment: .trailing)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.surfaceBorder.opacity(0.4))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(min(percent, 100)) / 100.0)
                }
            }
            .frame(height: 5)
        }
    }

    // MARK: - Coach Availability

    /// Count of coaches on the staff (including coordinator) with >= 60 expertise in the given scheme.
    private func coachesKnowingScheme(key: String) -> Int {
        var staff = coaches
        if !staff.contains(where: { $0.id == coordinator.id }) {
            staff.append(coordinator)
        }
        return staff.filter { $0.expertise(for: key) >= 60 }.count
    }

    /// Compact badge showing how many coaches on staff know the scheme.
    @ViewBuilder
    private func coachAvailabilityBadge(count: Int) -> some View {
        let color: Color = {
            switch count {
            case 0:  return .danger
            case 1:  return .warning
            case 2:  return .accentGold
            default: return .success
            }
        }()
        HStack(spacing: 3) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 8))
            Text(count == 0 ? "0 coaches" : "\(count)")
                .font(.system(size: 9, weight: .bold).monospacedDigit())
        }
        .foregroundStyle(color)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(color.opacity(0.15))
                .overlay(
                    Capsule()
                        .strokeBorder(color.opacity(0.4), lineWidth: 1)
                )
        )
        .accessibilityLabel("\(count) coaches on staff know this scheme")
    }

    // MARK: - Fit Calculations

    /// Average scheme expertise across all relevant staff (coordinator + position coaches).
    private func staffCoachFit(schemeKey: String, isOffensive: Bool) -> Int {
        let relevantRoles: [CoachRole] = isOffensive
            ? [.offensiveCoordinator, .qbCoach, .rbCoach, .wrCoach, .olCoach]
            : [.defensiveCoordinator, .dlCoach, .lbCoach, .dbCoach]
        var relevantCoaches = coaches.filter { relevantRoles.contains($0.role) }
        // Always include the coordinator being viewed
        if !relevantCoaches.contains(where: { $0.id == coordinator.id }) {
            relevantCoaches.append(coordinator)
        }
        guard !relevantCoaches.isEmpty else { return coordinator.expertise(for: schemeKey) }
        return relevantCoaches.reduce(0) { $0 + $1.expertise(for: schemeKey) } / relevantCoaches.count
    }

    /// Percentage of top-11 starters (by OVR) on the given side with schemeFamiliarity >= 50.
    private func rosterFamiliarity(schemeKey: String, side: PositionSide) -> Int {
        let sidePlayers = players.filter { $0.position.side == side }
        let starters = Array(sidePlayers.sorted { $0.overall > $1.overall }.prefix(11))
        guard !starters.isEmpty else { return 0 }
        let familiarCount = starters.filter { $0.schemeFam(for: schemeKey) >= 50 }.count
        return Int(Double(familiarCount) / Double(starters.count) * 100)
    }

    private func metricColor(_ percent: Int) -> Color {
        if percent >= 75 { return .success }
        if percent >= 50 { return .accentGold }
        if percent >= 25 { return .warning }
        return .danger
    }

    private func schemeExpertiseColor(_ value: Int) -> Color {
        if value >= 80 { return Color.accentGold }
        if value >= 60 { return Color.success }
        if value >= 40 { return Color.accentBlue }
        return Color.danger
    }

    // MARK: - Scheme Descriptions

    private func offensiveSchemeDescription(_ scheme: OffensiveScheme) -> String {
        switch scheme {
        case .westCoast:  return "Short-to-intermediate passing with high-percentage throws and run-after-catch emphasis."
        case .airRaid:    return "Spread formations with four- and five-wide sets, emphasizing the vertical passing game."
        case .spread:     return "Space the field with spread formations, using both run and pass to exploit matchups."
        case .powerRun:   return "Downhill running attack with pulling guards and fullback leads."
        case .shanahan:   return "Outside zone running scheme with play-action boots and misdirection."
        case .proPassing: return "Pro-style balanced attack with multiple formations and under-center play-action."
        case .rpo:        return "Run-pass option plays that let the QB read the defense post-snap."
        case .option:     return "Triple-option and read-option concepts emphasizing athletic QBs."
        }
    }

    private func defensiveSchemeDescription(_ scheme: DefensiveScheme) -> String {
        switch scheme {
        case .base34:   return "3-4 base with versatile OLBs who can rush and drop into coverage."
        case .base43:   return "4-3 base with four down linemen generating the pass rush."
        case .cover3:   return "Cover 3 zone with three deep defenders and four underneath zones."
        case .pressMan: return "Aggressive press-man coverage at the line with tight man-to-man assignments."
        case .tampa2:   return "Tampa 2 zone with a fast MLB dropping into deep middle coverage."
        case .multiple: return "Multiple fronts and coverages that disguise the defense pre-snap."
        case .hybrid:   return "Hybrid defense blending 3-4 and 4-3 principles with positionless players."
        }
    }
}

// MARK: - Preview

#Preview {
    SchemeSelectionView(
        coordinator: Coach(
            firstName: "Sean",
            lastName: "McVay",
            age: 38,
            role: .offensiveCoordinator,
            offensiveScheme: .westCoast,
            playCalling: 85,
            adaptability: 78,
            gamePlanning: 82
        ),
        players: [],
        isOffensive: true
    )
    .modelContainer(for: [Coach.self, Player.self], inMemory: true)
}
