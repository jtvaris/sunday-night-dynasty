import SwiftUI

// MARK: - Attribute Color Helper

/// Color codes attribute values: green (80+), gold (60-79), orange (40-59), red (<40).
private func colorForAttribute(_ value: Int) -> Color {
    switch value {
    case 80...:   return .success
    case 60..<80: return .accentGold
    case 40..<60: return .warning
    default:      return .danger
    }
}

struct PlayerDetailView: View {
    let player: Player

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// True when in landscape on iPad.
    private var isLandscape: Bool {
        verticalSizeClass == .compact
    }

    /// True for iPad regular-width layouts.
    private var isWideLayout: Bool {
        horizontalSizeClass == .regular
    }

    /// Number of columns for attribute grids: 3 in landscape, 2 on wide, 1 on compact.
    private var attributeColumns: Int {
        if isLandscape { return 3 }
        if isWideLayout { return 2 }
        return 1
    }

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            if isLandscape {
                // Landscape: two-column master layout
                HStack(alignment: .top, spacing: 0) {
                    // Left column: header + overview + contract
                    List {
                        playerHeader
                        overviewSection
                        contractDetailSection
                        developmentSection
                        versatilitySection
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.insetGrouped)
                    .frame(maxWidth: .infinity)

                    // Right column: attributes + personality + scheme
                    List {
                        physicalAttributesGrid
                        mentalAttributesGrid
                        positionAttributesGridSection
                        personalitySection
                        schemeFitSection
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.insetGrouped)
                    .frame(maxWidth: .infinity)
                }
            } else {
                List {
                    playerHeader
                    overviewSection
                    contractDetailSection
                    developmentSection
                    versatilitySection
                    if isWideLayout {
                        // Wide portrait: use grid layout for attributes
                        physicalAttributesGrid
                        mentalAttributesGrid
                        positionAttributesGridSection
                    } else {
                        physicalSection
                        mentalSection
                        positionAttributesSection
                    }
                    personalitySection
                    schemeFitSection
                }
                .scrollContentBackground(.hidden)
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(player.fullName)
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink(destination: PlayerStatsView(player: player, seasonStats: [])) {
                    Label("Stats", systemImage: "chart.bar.fill")
                }
            }
        }
    }

    // MARK: - Player Header Card

    private var playerHeader: some View {
        Section {
            VStack(spacing: 12) {
                HStack(spacing: 16) {
                    // Player avatar
                    PlayerAvatarView(player: player, size: 80)

                    // Large OVR circle
                    ZStack {
                        Circle()
                            .strokeBorder(Color.forRating(player.overall), lineWidth: 3)
                            .frame(width: 64, height: 64)
                        VStack(spacing: 0) {
                            Text("\(player.overall)")
                                .font(.title2.monospacedDigit())
                                .fontWeight(.bold)
                                .foregroundStyle(Color.forRating(player.overall))
                            Text("OVR")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Color.textTertiary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            positionLabel
                            developmentBadge
                        }

                        Text(player.fullName)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.textPrimary)

                        HStack(spacing: 12) {
                            Label("Age \(player.age)", systemImage: "calendar")
                            Label(
                                player.yearsPro == 0 ? "Rookie" : "\(player.yearsPro)yr pro",
                                systemImage: "figure.american.football"
                            )
                        }
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                    }

                    Spacer()
                }

                // Quick stats row
                HStack(spacing: 0) {
                    quickStat(label: "Morale", value: "\(player.morale)", color: moraleColor)
                    quickStatDivider
                    quickStat(
                        label: "Health",
                        value: player.isInjured ? "INJ \(player.injuryWeeksRemaining)wk" : "OK",
                        color: player.isInjured ? .danger : .success
                    )
                    quickStatDivider
                    quickStat(
                        label: "Salary",
                        value: formattedSalary,
                        color: .textSecondary
                    )
                    quickStatDivider
                    quickStat(
                        label: "Contract",
                        value: "\(player.contractYearsRemaining)yr",
                        color: player.contractYearsRemaining <= 1 ? .warning : .textSecondary
                    )
                }
                .padding(.vertical, 8)
                .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    private func quickStat(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.caption)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var quickStatDivider: some View {
        Rectangle()
            .fill(Color.surfaceBorder)
            .frame(width: 1, height: 24)
    }

    // MARK: - Overview Section

    private var overviewSection: some View {
        Section("Overview") {
            LabeledContent("Position") {
                positionLabel
            }
            LabeledContent("Age") {
                Text("\(player.age)")
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
            }
            LabeledContent("Experience") {
                Text(player.yearsPro == 0 ? "Rookie" : "\(player.yearsPro) year\(player.yearsPro == 1 ? "" : "s") pro")
                    .monospacedDigit()
                    .foregroundStyle(Color.textSecondary)
            }
            ColorCodedAttributeRow(name: "Overall", value: player.overall)
            LabeledContent("Morale") {
                HStack(spacing: 6) {
                    moraleIcon
                    Text(moraleLabel)
                        .foregroundStyle(moraleColor)
                }
            }
            .accessibilityLabel("Morale, \(moraleLabel)")
            if player.isInjured {
                LabeledContent("Status") {
                    Label("Injured -- \(player.injuryWeeksRemaining) wk\(player.injuryWeeksRemaining == 1 ? "" : "s")", systemImage: "cross.circle.fill")
                        .monospacedDigit()
                        .foregroundStyle(Color.danger)
                }
            }
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    // MARK: - Contract Detail Section

    private var contractDetailSection: some View {
        Section("Contract") {
            LabeledContent("Years Remaining") {
                HStack(spacing: 4) {
                    Text("\(player.contractYearsRemaining)")
                        .monospacedDigit()
                        .fontWeight(.semibold)
                        .foregroundStyle(player.contractYearsRemaining <= 1 ? Color.warning : Color.textPrimary)
                    if player.contractYearsRemaining <= 1 {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.warning)
                    }
                }
            }
            LabeledContent("Annual Salary") {
                Text(formattedSalary)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(Color.textSecondary)
            }
            LabeledContent("Market Value Est.") {
                Text(estimatedMarketValue)
                    .fontWeight(.medium)
                    .monospacedDigit()
                    .foregroundStyle(marketValueComparison.color)
            }
            LabeledContent("Value Assessment") {
                HStack(spacing: 4) {
                    Image(systemName: marketValueComparison.icon)
                        .font(.caption)
                    Text(marketValueComparison.label)
                        .font(.subheadline)
                }
                .foregroundStyle(marketValueComparison.color)
            }
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    // MARK: - Development Projection Section

    private var developmentSection: some View {
        Section("Development") {
            LabeledContent("Peak Age Range") {
                Text("\(player.position.peakAgeRange.lowerBound)-\(player.position.peakAgeRange.upperBound)")
                    .monospacedDigit()
                    .foregroundStyle(Color.textSecondary)
            }
            LabeledContent("Current Phase") {
                HStack(spacing: 4) {
                    Image(systemName: developmentPhase.icon)
                        .font(.caption)
                    Text(developmentPhase.label)
                }
                .foregroundStyle(developmentPhase.color)
            }
            LabeledContent("Trajectory") {
                Text(trajectoryDescription)
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            }

            // Visual age timeline
            VStack(alignment: .leading, spacing: 6) {
                Text("Career Timeline")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                GeometryReader { geo in
                    let width = geo.size.width
                    let minAge = 21
                    let maxAge = 40
                    let range = CGFloat(maxAge - minAge)
                    let peakStart = CGFloat(player.position.peakAgeRange.lowerBound - minAge) / range
                    let peakEnd = CGFloat(player.position.peakAgeRange.upperBound - minAge) / range
                    let currentPos = CGFloat(player.age - minAge) / range

                    ZStack(alignment: .leading) {
                        // Full bar
                        Capsule()
                            .fill(Color.backgroundTertiary)
                            .frame(height: 8)

                        // Peak range
                        Capsule()
                            .fill(Color.success.opacity(0.4))
                            .frame(width: (peakEnd - peakStart) * width, height: 8)
                            .offset(x: peakStart * width)

                        // Current age marker
                        Circle()
                            .fill(developmentPhase.color)
                            .frame(width: 12, height: 12)
                            .offset(x: min(max(currentPos * width - 6, 0), width - 12))
                    }
                }
                .frame(height: 12)

                HStack {
                    Text("21")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.textTertiary)
                    Spacer()
                    Text("Peak: \(player.position.peakAgeRange.lowerBound)-\(player.position.peakAgeRange.upperBound)")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.success)
                    Spacer()
                    Text("40")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    // MARK: - Physical Section

    private var physicalSection: some View {
        Section("Physical Attributes") {
            ColorCodedAttributeRow(name: "Speed",        value: player.physical.speed)
            ColorCodedAttributeRow(name: "Acceleration", value: player.physical.acceleration)
            ColorCodedAttributeRow(name: "Strength",     value: player.physical.strength)
            ColorCodedAttributeRow(name: "Agility",      value: player.physical.agility)
            ColorCodedAttributeRow(name: "Stamina",      value: player.physical.stamina)
            ColorCodedAttributeRow(name: "Durability",   value: player.physical.durability)
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    // MARK: - Mental Section

    private var mentalSection: some View {
        Section("Mental Attributes") {
            ColorCodedAttributeRow(name: "Awareness",       value: player.mental.awareness)
            ColorCodedAttributeRow(name: "Decision Making",  value: player.mental.decisionMaking)
            ColorCodedAttributeRow(name: "Clutch",           value: player.mental.clutch)
            ColorCodedAttributeRow(name: "Work Ethic",       value: player.mental.workEthic)
            ColorCodedAttributeRow(name: "Coachability",     value: player.mental.coachability)
            ColorCodedAttributeRow(name: "Leadership",       value: player.mental.leadership)
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    // MARK: - Position-Specific Attributes Section

    @ViewBuilder
    private var positionAttributesSection: some View {
        switch player.positionAttributes {
        case .quarterback(let attrs):
            Section("Quarterback Skills") {
                ColorCodedAttributeRow(name: "Arm Strength",    value: attrs.armStrength)
                ColorCodedAttributeRow(name: "Accuracy Short",  value: attrs.accuracyShort)
                ColorCodedAttributeRow(name: "Accuracy Mid",    value: attrs.accuracyMid)
                ColorCodedAttributeRow(name: "Accuracy Deep",   value: attrs.accuracyDeep)
                ColorCodedAttributeRow(name: "Pocket Presence", value: attrs.pocketPresence)
                ColorCodedAttributeRow(name: "Scrambling",      value: attrs.scrambling)
            }
            .listRowBackground(Color.backgroundSecondary)

        case .wideReceiver(let attrs):
            Section("Receiver Skills") {
                ColorCodedAttributeRow(name: "Route Running",     value: attrs.routeRunning)
                ColorCodedAttributeRow(name: "Catching",          value: attrs.catching)
                ColorCodedAttributeRow(name: "Release",           value: attrs.release)
                ColorCodedAttributeRow(name: "Spectacular Catch", value: attrs.spectacularCatch)
            }
            .listRowBackground(Color.backgroundSecondary)

        case .runningBack(let attrs):
            Section("Running Back Skills") {
                ColorCodedAttributeRow(name: "Vision",       value: attrs.vision)
                ColorCodedAttributeRow(name: "Elusiveness",  value: attrs.elusiveness)
                ColorCodedAttributeRow(name: "Break Tackle", value: attrs.breakTackle)
                ColorCodedAttributeRow(name: "Receiving",    value: attrs.receiving)
            }
            .listRowBackground(Color.backgroundSecondary)

        case .tightEnd(let attrs):
            Section("Tight End Skills") {
                ColorCodedAttributeRow(name: "Blocking",      value: attrs.blocking)
                ColorCodedAttributeRow(name: "Catching",      value: attrs.catching)
                ColorCodedAttributeRow(name: "Route Running", value: attrs.routeRunning)
                ColorCodedAttributeRow(name: "Speed",         value: attrs.speed)
            }
            .listRowBackground(Color.backgroundSecondary)

        case .offensiveLine(let attrs):
            Section("Offensive Line Skills") {
                ColorCodedAttributeRow(name: "Run Block",  value: attrs.runBlock)
                ColorCodedAttributeRow(name: "Pass Block", value: attrs.passBlock)
                ColorCodedAttributeRow(name: "Pull",       value: attrs.pull)
                ColorCodedAttributeRow(name: "Anchor",     value: attrs.anchor)
            }
            .listRowBackground(Color.backgroundSecondary)

        case .defensiveLine(let attrs):
            Section("Defensive Line Skills") {
                ColorCodedAttributeRow(name: "Pass Rush",      value: attrs.passRush)
                ColorCodedAttributeRow(name: "Block Shedding", value: attrs.blockShedding)
                ColorCodedAttributeRow(name: "Power Moves",    value: attrs.powerMoves)
                ColorCodedAttributeRow(name: "Finesse Moves",  value: attrs.finesseMoves)
            }
            .listRowBackground(Color.backgroundSecondary)

        case .linebacker(let attrs):
            Section("Linebacker Skills") {
                ColorCodedAttributeRow(name: "Tackling",      value: attrs.tackling)
                ColorCodedAttributeRow(name: "Zone Coverage", value: attrs.zoneCoverage)
                ColorCodedAttributeRow(name: "Man Coverage",  value: attrs.manCoverage)
                ColorCodedAttributeRow(name: "Blitzing",      value: attrs.blitzing)
            }
            .listRowBackground(Color.backgroundSecondary)

        case .defensiveBack(let attrs):
            Section("Defensive Back Skills") {
                ColorCodedAttributeRow(name: "Man Coverage",  value: attrs.manCoverage)
                ColorCodedAttributeRow(name: "Zone Coverage", value: attrs.zoneCoverage)
                ColorCodedAttributeRow(name: "Press",         value: attrs.press)
                ColorCodedAttributeRow(name: "Ball Skills",   value: attrs.ballSkills)
            }
            .listRowBackground(Color.backgroundSecondary)

        case .kicking(let attrs):
            Section("Kicking Skills") {
                ColorCodedAttributeRow(name: "Kick Power",    value: attrs.kickPower)
                ColorCodedAttributeRow(name: "Kick Accuracy", value: attrs.kickAccuracy)
            }
            .listRowBackground(Color.backgroundSecondary)
        }
    }

    // MARK: - Personality Section

    private var personalitySection: some View {
        Section("Personality") {
            LabeledContent("Archetype", value: archetypeDisplayName)
            LabeledContent("Motivation", value: player.personality.motivation.rawValue)
            if player.personality.isMentor {
                Label("Mentor influence on team", systemImage: "person.2.fill")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
            }
            if player.personality.isDramaticInMedia {
                Label("Can generate media drama", systemImage: "exclamationmark.bubble.fill")
                    .font(.footnote)
                    .foregroundStyle(Color.warning)
            }
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    // MARK: - Versatility & Scheme Familiarity Section

    private var versatilitySection: some View {
        Section("Versatility & Scheme") {
            // Position familiarity bars for non-zero alternate positions
            let altPositions = player.positionFamiliarity
                .filter { $0.key != player.position.rawValue && $0.value > 0 }
                .sorted { $0.value > $1.value }

            if !altPositions.isEmpty || player.trainingPosition != nil {
                // Training status
                if let trainingPos = player.trainingPosition, trainingPos != player.position {
                    HStack(spacing: 6) {
                        Image(systemName: "figure.run")
                            .font(.caption)
                            .foregroundStyle(Color.accentGold)
                        Text("Training: \(trainingPos.rawValue)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentGold)
                        Spacer()
                        let familiarity = player.familiarity(at: trainingPos)
                        let ceiling = VersatilityDevelopmentEngine.versatilityCeiling(player: player, at: trainingPos)
                        Text("\(familiarity)/\(ceiling)")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(Color.accentGold)
                    }
                }

                // Alternate position familiarity bars
                ForEach(altPositions, id: \.key) { posKey, familiarity in
                    if let pos = Position(rawValue: posKey) {
                        let ceiling = VersatilityDevelopmentEngine.versatilityCeiling(player: player, at: pos)
                        HStack(spacing: 8) {
                            Text(posKey)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.textPrimary)
                                .frame(width: 30, alignment: .leading)

                            GeometryReader { geo in
                                let barWidth = geo.size.width
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.backgroundTertiary)
                                        .frame(height: 6)
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(versatilityBarColor(familiarity))
                                        .frame(width: barWidth * CGFloat(familiarity) / 100.0, height: 6)
                                    // Ceiling marker
                                    Rectangle()
                                        .fill(Color.textTertiary)
                                        .frame(width: 1.5, height: 10)
                                        .offset(x: barWidth * CGFloat(ceiling) / 100.0 - 0.75)
                                }
                            }
                            .frame(height: 10)

                            Text("\(familiarity)%")
                                .font(.caption2.weight(.bold).monospacedDigit())
                                .foregroundStyle(versatilityBarColor(familiarity))
                                .frame(width: 36, alignment: .trailing)
                        }
                    }
                }
            } else {
                Text("No alternate position experience")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            }

            // Scheme familiarity bars
            let schemeFams = player.schemeFamiliarity
                .filter { $0.value > 0 }
                .sorted { $0.value > $1.value }

            if !schemeFams.isEmpty {
                Divider().overlay(Color.surfaceBorder)

                Text("Scheme Familiarity")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)

                ForEach(schemeFams, id: \.key) { scheme, familiarity in
                    HStack(spacing: 8) {
                        Text(scheme)
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                            .frame(width: 80, alignment: .leading)
                            .lineLimit(1)

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.backgroundTertiary)
                                    .frame(height: 6)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(schemeFamColor(familiarity))
                                    .frame(width: geo.size.width * CGFloat(familiarity) / 100.0, height: 6)
                            }
                        }
                        .frame(height: 6)

                        Text("\(familiarity)%")
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .foregroundStyle(schemeFamColor(familiarity))
                            .frame(width: 36, alignment: .trailing)
                    }
                }
            }
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    private func versatilityBarColor(_ value: Int) -> Color {
        if value >= 80 { return .accentGold }
        if value >= 60 { return .success }
        if value >= 40 { return .accentBlue }
        return .warning
    }

    private func schemeFamColor(_ value: Int) -> Color {
        if value >= 80 { return .accentGold }
        if value >= 60 { return .success }
        if value >= 40 { return .accentBlue }
        return .danger
    }

    // MARK: - Scheme Fit Section

    private var schemeFitSection: some View {
        Section("Scheme Fit") {
            LabeledContent("Position Group") {
                Text(positionGroupName)
                    .foregroundStyle(Color.textSecondary)
            }
            LabeledContent("Physical Profile") {
                let avg = player.physical.average
                HStack(spacing: 4) {
                    Text(physicalProfileLabel(for: Int(avg.rounded())))
                        .font(.subheadline)
                    Text("(\(Int(avg.rounded())))")
                        .monospacedDigit()
                        .foregroundStyle(colorForAttribute(Int(avg.rounded())))
                }
                .foregroundStyle(Color.textSecondary)
            }
            LabeledContent("Mental Profile") {
                let avg = player.mental.average
                HStack(spacing: 4) {
                    Text(mentalProfileLabel(for: Int(avg.rounded())))
                        .font(.subheadline)
                    Text("(\(Int(avg.rounded())))")
                        .monospacedDigit()
                        .foregroundStyle(colorForAttribute(Int(avg.rounded())))
                }
                .foregroundStyle(Color.textSecondary)
            }
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    // MARK: - Grid Attribute Sections (iPad / landscape)

    private var physicalAttributesGrid: some View {
        Section("Physical Attributes") {
            attributeGrid([
                ("Speed",        player.physical.speed),
                ("Acceleration", player.physical.acceleration),
                ("Strength",     player.physical.strength),
                ("Agility",      player.physical.agility),
                ("Stamina",      player.physical.stamina),
                ("Durability",   player.physical.durability),
            ])
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    private var mentalAttributesGrid: some View {
        Section("Mental Attributes") {
            attributeGrid([
                ("Awareness",       player.mental.awareness),
                ("Decision Making",  player.mental.decisionMaking),
                ("Clutch",           player.mental.clutch),
                ("Work Ethic",       player.mental.workEthic),
                ("Coachability",     player.mental.coachability),
                ("Leadership",       player.mental.leadership),
            ])
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    @ViewBuilder
    private var positionAttributesGridSection: some View {
        switch player.positionAttributes {
        case .quarterback(let a):
            Section("Quarterback Skills") {
                attributeGrid([
                    ("Arm Strength", a.armStrength), ("Accuracy Short", a.accuracyShort),
                    ("Accuracy Mid", a.accuracyMid), ("Accuracy Deep", a.accuracyDeep),
                    ("Pocket Presence", a.pocketPresence), ("Scrambling", a.scrambling),
                ])
            }.listRowBackground(Color.backgroundSecondary)
        case .wideReceiver(let a):
            Section("Receiver Skills") {
                attributeGrid([
                    ("Route Running", a.routeRunning), ("Catching", a.catching),
                    ("Release", a.release), ("Spectacular Catch", a.spectacularCatch),
                ])
            }.listRowBackground(Color.backgroundSecondary)
        case .runningBack(let a):
            Section("Running Back Skills") {
                attributeGrid([
                    ("Vision", a.vision), ("Elusiveness", a.elusiveness),
                    ("Break Tackle", a.breakTackle), ("Receiving", a.receiving),
                ])
            }.listRowBackground(Color.backgroundSecondary)
        case .tightEnd(let a):
            Section("Tight End Skills") {
                attributeGrid([
                    ("Blocking", a.blocking), ("Catching", a.catching),
                    ("Route Running", a.routeRunning), ("Speed", a.speed),
                ])
            }.listRowBackground(Color.backgroundSecondary)
        case .offensiveLine(let a):
            Section("Offensive Line Skills") {
                attributeGrid([
                    ("Run Block", a.runBlock), ("Pass Block", a.passBlock),
                    ("Pull", a.pull), ("Anchor", a.anchor),
                ])
            }.listRowBackground(Color.backgroundSecondary)
        case .defensiveLine(let a):
            Section("Defensive Line Skills") {
                attributeGrid([
                    ("Pass Rush", a.passRush), ("Block Shedding", a.blockShedding),
                    ("Power Moves", a.powerMoves), ("Finesse Moves", a.finesseMoves),
                ])
            }.listRowBackground(Color.backgroundSecondary)
        case .linebacker(let a):
            Section("Linebacker Skills") {
                attributeGrid([
                    ("Tackling", a.tackling), ("Zone Coverage", a.zoneCoverage),
                    ("Man Coverage", a.manCoverage), ("Blitzing", a.blitzing),
                ])
            }.listRowBackground(Color.backgroundSecondary)
        case .defensiveBack(let a):
            Section("Defensive Back Skills") {
                attributeGrid([
                    ("Man Coverage", a.manCoverage), ("Zone Coverage", a.zoneCoverage),
                    ("Press", a.press), ("Ball Skills", a.ballSkills),
                ])
            }.listRowBackground(Color.backgroundSecondary)
        case .kicking(let a):
            Section("Kicking Skills") {
                attributeGrid([
                    ("Kick Power", a.kickPower), ("Kick Accuracy", a.kickAccuracy),
                ])
            }.listRowBackground(Color.backgroundSecondary)
        }
    }

    private func attributeGrid(_ attributes: [(String, Int)]) -> some View {
        let cols = attributeColumns
        let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: cols)
        return LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 8) {
            ForEach(attributes, id: \.0) { attr in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(colorForAttribute(attr.1))
                        .frame(width: 3, height: 16)
                    Text(attr.0)
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                    Spacer()
                    Text("\(attr.1)")
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundStyle(colorForAttribute(attr.1))
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private var positionLabel: some View {
        HStack(spacing: 6) {
            Text(player.position.rawValue)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(Color.textPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(positionSideColor, in: RoundedRectangle(cornerRadius: 4))
            Text(player.position.side.rawValue)
                .foregroundStyle(Color.textSecondary)
        }
    }

    private var developmentBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: developmentPhase.icon)
                .font(.system(size: 9))
            Text(developmentPhase.shortLabel)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(developmentPhase.color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(developmentPhase.color.opacity(0.15), in: Capsule())
    }

    private var positionSideColor: Color {
        switch player.position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }

    private var moraleLabel: String {
        switch player.morale {
        case 85...: return "Excellent (\(player.morale))"
        case 70..<85: return "Good (\(player.morale))"
        case 55..<70: return "Neutral (\(player.morale))"
        default:    return "Low (\(player.morale))"
        }
    }

    private var moraleColor: Color {
        Color.forRating(player.morale)
    }

    private var moraleIcon: some View {
        Image(systemName: moraleSystemImage)
            .foregroundStyle(moraleColor)
    }

    private var moraleSystemImage: String {
        switch player.morale {
        case 85...: return "face.smiling.fill"
        case 70..<85: return "face.smiling"
        case 55..<70: return "face.dashed"
        default:    return "face.dashed.fill"
        }
    }

    private var archetypeDisplayName: String {
        switch player.personality.archetype {
        case .teamLeader:        return "Team Leader"
        case .loneWolf:          return "Lone Wolf"
        case .feelPlayer:        return "Feel Player"
        case .steadyPerformer:   return "Steady Performer"
        case .dramaQueen:        return "Drama Queen"
        case .quietProfessional: return "Quiet Professional"
        case .mentor:            return "Mentor"
        case .fieryCompetitor:   return "Fiery Competitor"
        case .classClown:        return "Class Clown"
        }
    }

    private var formattedSalary: String {
        let millions = Double(player.annualSalary) / 1000.0
        if millions >= 1.0 {
            return String(format: "$%.2fM", millions)
        } else {
            return "$\(player.annualSalary)K"
        }
    }

    // MARK: - Market Value Estimation

    private var estimatedMarketValue: String {
        let marketValue = estimateMarketValueAmount
        let millions = Double(marketValue) / 1000.0
        if millions >= 1.0 {
            return String(format: "$%.2fM", millions)
        } else {
            return "$\(marketValue)K"
        }
    }

    /// Rough market value estimate based on overall, age, and position.
    private var estimateMarketValueAmount: Int {
        let baseValue = player.overall * player.overall  // Quadratic scaling
        let ageFactor: Double
        let peak = player.position.peakAgeRange
        if peak.contains(player.age) {
            ageFactor = 1.0
        } else if player.age < peak.lowerBound {
            ageFactor = 0.85
        } else {
            let yearsOver = player.age - peak.upperBound
            ageFactor = max(0.3, 1.0 - Double(yearsOver) * 0.15)
        }
        return Int(Double(baseValue) * ageFactor / 10.0)
    }

    private var marketValueComparison: MarketValueAssessment {
        let market = estimateMarketValueAmount
        let salary = player.annualSalary
        let ratio = salary > 0 ? Double(market) / Double(salary) : 2.0
        if ratio > 1.3 {
            return .bargain
        } else if ratio > 0.8 {
            return .fairValue
        } else {
            return .overpaid
        }
    }

    // MARK: - Development Phase

    private var developmentPhase: DevelopmentPhaseInfo {
        let peak = player.position.peakAgeRange
        if player.age < peak.lowerBound {
            return .rising
        } else if peak.contains(player.age) {
            return .prime
        } else {
            return .declining
        }
    }

    private var trajectoryDescription: String {
        let peak = player.position.peakAgeRange
        if player.age < peak.lowerBound {
            let yearsToGo = peak.lowerBound - player.age
            return "Entering prime in ~\(yearsToGo) year\(yearsToGo == 1 ? "" : "s"). Expect improvement."
        } else if peak.contains(player.age) {
            let yearsLeft = peak.upperBound - player.age
            return "In prime window. ~\(yearsLeft) year\(yearsLeft == 1 ? "" : "s") of peak performance remaining."
        } else {
            let yearsOver = player.age - peak.upperBound
            return "Past prime by \(yearsOver) year\(yearsOver == 1 ? "" : "s"). Expect gradual decline."
        }
    }

    // MARK: - Scheme Fit Helpers

    private var positionGroupName: String {
        switch player.position {
        case .QB: return "Quarterback"
        case .RB, .FB: return "Backfield"
        case .WR: return "Receiving Corps"
        case .TE: return "Tight End"
        case .LT, .LG, .C, .RG, .RT: return "Offensive Line"
        case .DE, .DT: return "Defensive Line"
        case .OLB, .MLB: return "Linebacker Corps"
        case .CB, .FS, .SS: return "Secondary"
        case .K: return "Kicking"
        case .P: return "Punting"
        }
    }

    private func physicalProfileLabel(for value: Int) -> String {
        switch value {
        case 85...:   return "Elite Athlete"
        case 75..<85: return "Above Average"
        case 65..<75: return "Average"
        case 55..<65: return "Below Average"
        default:      return "Limited"
        }
    }

    private func mentalProfileLabel(for value: Int) -> String {
        switch value {
        case 85...:   return "Football IQ Genius"
        case 75..<85: return "High IQ"
        case 65..<75: return "Average IQ"
        case 55..<65: return "Developing"
        default:      return "Raw"
        }
    }
}

// MARK: - Market Value Assessment

enum MarketValueAssessment {
    case bargain, fairValue, overpaid

    var label: String {
        switch self {
        case .bargain:   return "Bargain"
        case .fairValue: return "Fair Value"
        case .overpaid:  return "Overpaid"
        }
    }

    var icon: String {
        switch self {
        case .bargain:   return "arrow.down.circle.fill"
        case .fairValue: return "equal.circle.fill"
        case .overpaid:  return "arrow.up.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .bargain:   return .success
        case .fairValue: return .accentGold
        case .overpaid:  return .danger
        }
    }
}

// MARK: - Development Phase Info

enum DevelopmentPhaseInfo {
    case rising, prime, declining

    var label: String {
        switch self {
        case .rising:    return "Rising"
        case .prime:     return "Prime"
        case .declining: return "Declining"
        }
    }

    var shortLabel: String {
        switch self {
        case .rising:    return "Rising"
        case .prime:     return "Prime"
        case .declining: return "Decline"
        }
    }

    var icon: String {
        switch self {
        case .rising:    return "arrow.up.right"
        case .prime:     return "star.fill"
        case .declining: return "arrow.down.right"
        }
    }

    var color: Color {
        switch self {
        case .rising:    return .success
        case .prime:     return .accentGold
        case .declining: return .danger
        }
    }
}

// MARK: - Color-Coded Attribute Row

/// Displays an attribute name and value with color coding:
/// green (80+), gold/yellow (60-79), orange (40-59), red (<40).
struct ColorCodedAttributeRow: View {
    let name: String
    let value: Int

    private var attributeColor: Color {
        colorForAttribute(value)
    }

    private var ratingLabel: String {
        switch value {
        case 80...:   return "elite"
        case 60..<80: return "good"
        case 40..<60: return "average"
        default:      return "below average"
        }
    }

    var body: some View {
        LabeledContent(name) {
            HStack(spacing: 6) {
                // Color bar indicator
                RoundedRectangle(cornerRadius: 2)
                    .fill(attributeColor)
                    .frame(width: 3, height: 16)

                Text("\(value)")
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(attributeColor)
            }
        }
        .accessibilityLabel("\(name), \(value), \(ratingLabel)")
    }
}

// MARK: - Legacy AttributeRow (kept for backward compatibility)

struct AttributeRow: View {
    let name: String
    let value: Int

    var body: some View {
        ColorCodedAttributeRow(name: name, value: value)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        PlayerDetailView(player: Player(
            firstName: "Patrick",
            lastName: "Mahomes",
            position: .QB,
            age: 28,
            yearsPro: 7,
            physical: PhysicalAttributes(
                speed: 72, acceleration: 78, strength: 65,
                agility: 80, stamina: 85, durability: 88
            ),
            mental: MentalAttributes(
                awareness: 94, decisionMaking: 92, clutch: 96,
                workEthic: 88, coachability: 82, leadership: 90
            ),
            positionAttributes: .quarterback(QBAttributes(
                armStrength: 95, accuracyShort: 88, accuracyMid: 91,
                accuracyDeep: 87, pocketPresence: 92, scrambling: 80
            )),
            personality: PlayerPersonality(archetype: .fieryCompetitor, motivation: .winning),
            morale: 90,
            contractYearsRemaining: 3,
            annualSalary: 45000
        ))
    }
}
