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

    // MARK: - F-65: the switch is armed, not fired
    //
    // Tapping a scheme used to write it to the coordinator, save, and dismiss —
    // one tap, no preview, no confirmation, for a decision that costs a season
    // of scheme fit and takes the better part of two to earn back. The tax is
    // correct and untouched; only the disclosure was missing.
    //
    // A tap now ARMS the change: the row expands with a priced forecast and the
    // commit moves to a `DSActionBar` whose explainer is the bill (§2.5 / P4 —
    // cost and outcome stated, in that order, before commit). Choosing the
    // system already installed disarms instead, so the screen is still a
    // one-tap escape from a mis-tap.

    /// The scheme the user has selected but not yet installed.
    @State private var pendingOffense: OffensiveScheme?
    @State private var pendingDefense: DefensiveScheme?

    /// The priced forecast for whatever is pending.
    ///
    /// Cached rather than computed in the row body on purpose: `price` runs
    /// `learnScheme` a few hundred times and `rosterSchemeFit` twice per
    /// starter, which is nothing once and far too much for every row on every
    /// redraw.
    @State private var forecast: SchemeInstallForecast?

    /// What the building installs on the side this picker is NOT editing. Held
    /// fixed in the forecast so the fit delta isolates the one change.
    private var installedOffense: OffensiveScheme? {
        isOffensive
            ? coordinator.offensiveScheme
            : coaches.first { $0.role == .offensiveCoordinator }?.offensiveScheme
    }

    private var installedDefense: DefensiveScheme? {
        isOffensive
            ? coaches.first { $0.role == .defensiveCoordinator }?.defensiveScheme
            : coordinator.defensiveScheme
    }

    private var pendingName: String? {
        pendingOffense?.displayName ?? pendingDefense?.displayName
    }

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
            .safeAreaInset(edge: .bottom) { installBar }
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

    // MARK: - The commit surface (F-65)

    /// The bill, then the button. Nothing installs from a row tap any more.
    @ViewBuilder
    private var installBar: some View {
        if let name = pendingName, let forecast {
            DSActionBar(
                explainer: .init(
                    title: "What the switch costs",
                    message: forecast.costHeadline,
                    isWarning: forecast.fitCost >= 5
                ),
                ghost: .init(title: "Keep current", handler: disarm),
                primary: .init(
                    title: "Install \(name)",
                    caption: forecast.seasonsToPivot.map { _ in "install year starts next camp" }
                        ?? "no install year needed",
                    handler: commitPending
                )
            )
        } else {
            DSActionBar(
                explainer: .init(
                    title: "Nothing armed",
                    message: "Pick a system to see what installing it would cost this roster. **Nothing changes until you install it.**"
                )
            )
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
                    .font(.system(size: DSType.Size.micro))
                    .foregroundStyle(Color.accentGold)
                Text(family.uppercased())
                    .font(.system(size: DSType.Size.caption, weight: .black))
                    .tracking(1.5)
                    .foregroundStyle(Color.accentGold)
            }
            Text(description)
                .font(.system(size: DSType.Size.micro))
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
                    .font(.system(size: DSType.Size.caption))
                    .foregroundStyle(Color.textTertiary)
                Text("\(coordinator.playCalling)")
                    .font(.system(size: DSType.Size.callout, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color.forRating(coordinator.playCalling))
            }
        }
        .padding(16)
        .cardBackground()
    }

    // MARK: - Offensive Scheme Row

    private func offensiveSchemeRow(_ scheme: OffensiveScheme) -> some View {
        // F-65: "selected" used to mean one thing — what is installed — and now
        // means two. The gold ring stays the INSTALLED system, because that is
        // what the building runs today and the user must never lose sight of it
        // while shopping. The armed candidate takes the blue informational ring,
        // which is the palette's job for "this is the one you are looking at"
        // (P7: gold is the commit, and the commit is on the action bar).
        let isInstalled = coordinator.offensiveScheme == scheme
        let isArmed = pendingOffense == scheme
        let isSelected = isInstalled || isArmed
        let tint: Color = isInstalled ? .accentGold : .accentBlue
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
                        .fill(isSelected ? tint : Color.clear)
                        .overlay(
                            Circle()
                                .strokeBorder(isSelected ? tint : Color.textTertiary, lineWidth: 2)
                        )
                        .frame(width: 20, height: 20)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(scheme.displayName)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(isSelected ? tint : Color.textPrimary)

                            // Per-scheme coach availability badge
                            coachAvailabilityBadge(count: coachesKnowing)
                        }

                        Text(offensiveSchemeDescription(scheme))
                            .font(.system(size: DSType.Size.micro))
                            .foregroundStyle(Color.textTertiary)
                            .lineLimit(2)
                    }

                    Spacer()

                    // Coach expertise (coordinator)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(expertiseValue)%")
                            .font(.system(size: DSType.Size.body, weight: .bold).monospacedDigit())
                            .foregroundStyle(expertiseColor)
                        Text("Expertise")
                            .font(.system(size: DSType.Size.micro, weight: .medium))
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
                            .font(.system(size: DSType.Size.micro))
                        Text("Coach has only \(expertiseValue)% expertise -- players will learn slower")
                            .font(.system(size: DSType.Size.caption))
                    }
                    .foregroundStyle(Color.warning)
                    .padding(.top, 6)
                }

                // F-65: the bill, on the row the user is looking at.
                if isArmed, let forecast {
                    installForecastPanel(forecast)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? tint.opacity(0.08) : Color.backgroundSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(
                                isSelected ? tint.opacity(0.5) : Color.surfaceBorder,
                                lineWidth: isSelected ? 1.5 : 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Defensive Scheme Row

    private func defensiveSchemeRow(_ scheme: DefensiveScheme) -> some View {
        // See `offensiveSchemeRow` for why installed and armed are separate.
        let isInstalled = coordinator.defensiveScheme == scheme
        let isArmed = pendingDefense == scheme
        let isSelected = isInstalled || isArmed
        let tint: Color = isInstalled ? .accentGold : .accentBlue
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
                        .fill(isSelected ? tint : Color.clear)
                        .overlay(
                            Circle()
                                .strokeBorder(isSelected ? tint : Color.textTertiary, lineWidth: 2)
                        )
                        .frame(width: 20, height: 20)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(scheme.displayName)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(isSelected ? tint : Color.textPrimary)

                            // Per-scheme coach availability badge
                            coachAvailabilityBadge(count: coachesKnowing)
                        }

                        Text(defensiveSchemeDescription(scheme))
                            .font(.system(size: DSType.Size.micro))
                            .foregroundStyle(Color.textTertiary)
                            .lineLimit(2)
                    }

                    Spacer()

                    // Coach expertise (coordinator)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(expertiseValue)%")
                            .font(.system(size: DSType.Size.body, weight: .bold).monospacedDigit())
                            .foregroundStyle(expertiseColor)
                        Text("Expertise")
                            .font(.system(size: DSType.Size.micro, weight: .medium))
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
                            .font(.system(size: DSType.Size.micro))
                        Text("Coach has only \(expertiseValue)% expertise -- players will learn slower")
                            .font(.system(size: DSType.Size.caption))
                    }
                    .foregroundStyle(Color.warning)
                    .padding(.top, 6)
                }

                // F-65: the bill, on the row the user is looking at.
                if isArmed, let forecast {
                    installForecastPanel(forecast)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? tint.opacity(0.08) : Color.backgroundSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(
                                isSelected ? tint.opacity(0.5) : Color.surfaceBorder,
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
                .font(.system(size: DSType.Size.caption, weight: .black))
                .tracking(1.5)
                .foregroundStyle(Color.accentGold)

            HStack(spacing: 16) {
                aptitudeStatView(label: "Play Calling", value: coordinator.playCalling)
                aptitudeStatView(label: "Adaptability", value: coordinator.adaptability)
                aptitudeStatView(label: "Game Planning", value: coordinator.gamePlanning)
            }

            Text("A coordinator's play calling and adaptability determine how effectively they can run each scheme. Higher adaptability means smoother transitions when changing schemes.")
                .font(.system(size: DSType.Size.micro))
                .foregroundStyle(Color.textTertiary)
        }
        .padding(16)
        .cardBackground()
    }

    private func aptitudeStatView(label: String, value: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: DSType.Size.callout, weight: .bold).monospacedDigit())
                .foregroundStyle(Color.forRating(value))
            Text(label)
                .font(.system(size: DSType.Size.caption))
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    /// Arms an offensive scheme and prices it. Tapping the installed system
    /// disarms — a mis-tap costs one more tap, not a season.
    private func selectOffensiveScheme(_ scheme: OffensiveScheme) {
        guard scheme != coordinator.offensiveScheme else { return disarm() }
        pendingDefense = nil
        pendingOffense = scheme
        forecast = SchemeInstallForecast.price(
            candidateOffense: scheme,
            candidateDefense: nil,
            currentOffense: installedOffense,
            currentDefense: installedDefense,
            players: players,
            coordinator: coordinator
        )
    }

    private func selectDefensiveScheme(_ scheme: DefensiveScheme) {
        guard scheme != coordinator.defensiveScheme else { return disarm() }
        pendingOffense = nil
        pendingDefense = scheme
        forecast = SchemeInstallForecast.price(
            candidateOffense: nil,
            candidateDefense: scheme,
            currentOffense: installedOffense,
            currentDefense: installedDefense,
            players: players,
            coordinator: coordinator
        )
    }

    private func disarm() {
        pendingOffense = nil
        pendingDefense = nil
        forecast = nil
    }

    /// The only write in this file. `WeekAdvancer.applySchemeChanges` picks the
    /// swap up at the next training camp and marks the install year; nothing
    /// here has to tell it anything.
    private func commitPending() {
        if let pendingOffense {
            coordinator.offensiveScheme = pendingOffense
        } else if let pendingDefense {
            coordinator.defensiveScheme = pendingDefense
        } else {
            return
        }
        try? modelContext.save()
        dismiss()
    }

    // MARK: - Install Forecast Panel (F-65)

    /// The install curve, shown inline on the armed row.
    ///
    /// Three lines and no more: where the room starts and how long the climb is,
    /// what happens to the playbook being abandoned, and the one thing working
    /// in the user's favour. The scheme-fit cost itself is not repeated here —
    /// it is the action bar's explainer, and §2.13's arithmetic gate is easier
    /// to keep when a number has one home.
    @ViewBuilder
    private func installForecastPanel(_ forecast: SchemeInstallForecast) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text("IF YOU INSTALL THIS")
                .font(DSType.display(DSType.Size.caption, .heavy))
                .tracking(0.7)
                .foregroundStyle(Color.textSecondary)

            if forecast.starterCount == 0 {
                Text(forecast.costHeadline)
                    .font(DSType.text(DSType.Size.caption, .medium, prose: true))
                    .foregroundStyle(Color.textTertiaryReadable)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                forecastLine(icon: "chart.line.uptrend.xyaxis", text: forecast.curveLine)
                forecastLine(icon: "arrow.down.right.circle", text: forecast.abandonedLine)
                forecastLine(icon: "figure.american.football", text: forecast.installYearLine)
            }
        }
        .padding(DSSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                .fill(Color.backgroundTertiary)
        )
        .padding(.top, DSSpacing.xs)
    }

    private func forecastLine(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: DSSpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: DSType.Size.caption, weight: .semibold))
                .foregroundStyle(Color.accentBlue)
                .frame(width: 14)
            Text(text)
                .font(DSType.text(DSType.Size.caption, .medium, prose: true))
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Shared Metric Bar

    private func schemeMetricBar(label: String, percent: Int, icon: String) -> some View {
        let color = metricColor(percent)
        return HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: DSType.Size.micro))
                .foregroundStyle(color)
                .frame(width: 12)
            Text(label)
                .font(.system(size: DSType.Size.caption, weight: .medium))
                .foregroundStyle(Color.textTertiary)
                .frame(width: 68, alignment: .leading)
            Text("\(percent)%")
                .font(.system(size: DSType.Size.caption, weight: .bold).monospacedDigit())
                .foregroundStyle(color)
                .frame(width: 34, alignment: .trailing)
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
                .font(.system(size: DSType.Size.micro))
            Text(count == 0 ? "0 coaches" : "\(count)")
                .font(.system(size: DSType.Size.caption, weight: .bold).monospacedDigit())
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

    /// Unified onto `Color.forRating(scale: .percent)`. This bar and
    /// `schemeExpertiseColor` sat six lines apart in one file and banded the
    /// same kind of 0–100 percentage differently — 55 % familiarity read gold
    /// here and red there.
    private func metricColor(_ percent: Int) -> Color {
        Color.forRating(percent, scale: .percent)
    }

    /// Unified onto `Color.forRating(scale: .percent)` so coach expertise reads
    /// on the same ladder as every other 0–100 number in the app.
    private func schemeExpertiseColor(_ value: Int) -> Color {
        Color.forRating(value, scale: .percent)
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
