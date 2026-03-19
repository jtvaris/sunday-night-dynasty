import SwiftUI
import SwiftData

// MARK: - Scheme Selection View (#67)

/// Allows changing a coordinator's offensive or defensive scheme.
/// Presents all available schemes with a roster fit preview for each.
struct SchemeSelectionView: View {

    let coordinator: Coach
    let players: [Player]
    let isOffensive: Bool

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Coordinator info header
                    coordinatorHeader

                    // Scheme options
                    if isOffensive {
                        ForEach(OffensiveScheme.allCases, id: \.self) { scheme in
                            offensiveSchemeRow(scheme)
                        }
                    } else {
                        ForEach(DefensiveScheme.allCases, id: \.self) { scheme in
                            defensiveSchemeRow(scheme)
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
        let avgFit = averageOffensiveFit(for: scheme)
        let avgPercent = Int(avgFit * 100)
        let fitColor = schemeFitColor(avgPercent)
        let expertiseValue = coordinator.expertise(for: scheme.rawValue)
        let expertiseColor = schemeExpertiseColor(expertiseValue)

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
                        Text(scheme.displayName)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(isSelected ? Color.accentGold : Color.textPrimary)

                        Text(offensiveSchemeDescription(scheme))
                            .font(.system(size: 10))
                            .foregroundStyle(Color.textTertiary)
                            .lineLimit(2)
                    }

                    Spacer()

                    // Coach expertise
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(expertiseValue)%")
                            .font(.system(size: 14, weight: .bold).monospacedDigit())
                            .foregroundStyle(expertiseColor)
                        Text("Expertise")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(Color.textTertiary)
                    }

                    // Roster fit preview
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(avgPercent)%")
                            .font(.system(size: 14, weight: .bold).monospacedDigit())
                            .foregroundStyle(fitColor)
                        Text("Roster Fit")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(Color.textTertiary)
                    }
                }

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
        let avgFit = averageDefensiveFit(for: scheme)
        let avgPercent = Int(avgFit * 100)
        let fitColor = schemeFitColor(avgPercent)
        let expertiseValue = coordinator.expertise(for: scheme.rawValue)
        let expertiseColor = schemeExpertiseColor(expertiseValue)

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
                        Text(scheme.displayName)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(isSelected ? Color.accentGold : Color.textPrimary)

                        Text(defensiveSchemeDescription(scheme))
                            .font(.system(size: 10))
                            .foregroundStyle(Color.textTertiary)
                            .lineLimit(2)
                    }

                    Spacer()

                    // Coach expertise
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(expertiseValue)%")
                            .font(.system(size: 14, weight: .bold).monospacedDigit())
                            .foregroundStyle(expertiseColor)
                        Text("Expertise")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(Color.textTertiary)
                    }

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(avgPercent)%")
                            .font(.system(size: 14, weight: .bold).monospacedDigit())
                            .foregroundStyle(fitColor)
                        Text("Roster Fit")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(Color.textTertiary)
                    }
                }

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

    // MARK: - Fit Calculations

    private func averageOffensiveFit(for scheme: OffensiveScheme) -> Double {
        guard !players.isEmpty else { return 0.5 }
        return players.reduce(0.0) { sum, player in
            sum + CoachingEngine.schemeFit(player: player, offensiveScheme: scheme, defensiveScheme: nil)
        } / Double(players.count)
    }

    private func averageDefensiveFit(for scheme: DefensiveScheme) -> Double {
        guard !players.isEmpty else { return 0.5 }
        return players.reduce(0.0) { sum, player in
            sum + CoachingEngine.schemeFit(player: player, offensiveScheme: nil, defensiveScheme: scheme)
        } / Double(players.count)
    }

    private func schemeFitColor(_ percent: Int) -> Color {
        if percent >= 80 { return Color.success }
        if percent >= 60 { return Color.accentGold }
        return Color.danger
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
