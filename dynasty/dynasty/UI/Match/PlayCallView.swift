import SwiftUI

// MARK: - PlayCallView

/// Full-screen overlay shown when the player must make a play call before the
/// next snap.  It displays the current game situation at the top, a scrollable
/// grid of play-call buttons in the center, and a Snap / confirm button at the
/// bottom.
///
/// The caller is responsible for dismissing the view once a call is confirmed.
/// The selected `OffensivePlayCall` or `DefensivePackage` is reported via the
/// `onOffensiveCall` / `onDefensiveCall` closures, then the parent immediately
/// dismisses the sheet.
///
/// - Note: If both offense and defense are controlled by the player, two
///   separate overlays are sequenced by `MatchView` — first defense (so the
///   player knows what coverage they're bringing), then offense.
struct PlayCallView: View {

    // MARK: - Input

    let side: CallSide

    /// Game situation shown in the header.
    let situation: GameSituation

    /// AI-suggested play.  Highlighted in the grid as the recommended choice.
    let aiOffensiveSuggestion: OffensivePlayCall?
    let aiDefensiveSuggestion: DefensivePackage?

    /// Called when the player confirms an offensive call.
    var onOffensiveCall: (OffensivePlayCall) -> Void = { _ in }
    /// Called when the player confirms a defensive package.
    var onDefensiveCall: (DefensivePackage) -> Void = { _ in }

    // MARK: - Local State

    @State private var selectedOffensiveCall: OffensivePlayCall?
    @State private var selectedCoverage: DefensivePlayCall = .cover3
    @State private var selectedBlitz: DefensivePlayCall    = .noBlitz
    @State private var selectedFront: DefensivePlayCall    = .base

    /// Flash state when the snap button is tapped.
    @State private var snapConfirmed: Bool = false

    // MARK: - Body

    var body: some View {
        ZStack {
            // Scrim
            Color.backgroundPrimary
                .opacity(0.96)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                situationHeader
                    .zIndex(1)

                Divider().background(Color.surfaceBorder)

                if side == .offense {
                    offenseGrid
                } else {
                    defenseGrid
                }

                Divider().background(Color.surfaceBorder)

                snapBar
            }
        }
        .onAppear {
            // Pre-select AI suggestion so the player can immediately snap it
            if side == .offense {
                selectedOffensiveCall = aiOffensiveSuggestion
            } else {
                if let sug = aiDefensiveSuggestion {
                    selectedCoverage = sug.coverage
                    selectedBlitz    = sug.blitz
                    selectedFront    = sug.front
                }
            }
        }
    }

    // MARK: - Side

    enum CallSide {
        case offense
        case defense
    }

    // MARK: - Game Situation

    struct GameSituation {
        let down: Int
        let distance: Int
        let yardLine: Int
        let quarter: Int
        let timeRemaining: Int
        let homeScore: Int
        let awayScore: Int
        let homeAbbreviation: String
        let awayAbbreviation: String
        let playerTeamIsHome: Bool

        var formattedClock: String {
            String(format: "%d:%02d", timeRemaining / 60, timeRemaining % 60)
        }

        var quarterLabel: String {
            quarter <= 4 ? "Q\(quarter)" : "OT"
        }

        var downDistanceLabel: String {
            "\(ordinal(down)) & \(distance)"
        }

        var yardLineLabel: String {
            yardLine == 50 ? "50 yd line" : yardLine > 50 ? "OPP \(100 - yardLine)" : "OWN \(yardLine)"
        }

        var scoreLine: String {
            "\(awayAbbreviation) \(playerTeamIsHome ? awayScore : homeScore)  ·  \(homeAbbreviation) \(playerTeamIsHome ? homeScore : awayScore)"
        }

        private func ordinal(_ n: Int) -> String {
            switch n {
            case 1: return "1st"; case 2: return "2nd"
            case 3: return "3rd"; case 4: return "4th"
            default: return "\(n)th"
            }
        }
    }

    // MARK: - Situation Header

    private var situationHeader: some View {
        VStack(spacing: 6) {
            // Title bar
            HStack {
                Image(systemName: side == .offense ? "arrow.right.circle.fill" : "shield.lefthalf.filled")
                    .foregroundStyle(Color.accentGold)
                Text(side == .offense ? "Call Your Play" : "Set Your Defense")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                // Score / clock
                VStack(alignment: .trailing, spacing: 2) {
                    Text(situation.scoreLine)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.textSecondary)
                    HStack(spacing: 4) {
                        Text(situation.quarterLabel)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.textTertiary)
                        Text(situation.formattedClock)
                            .font(.system(size: 14, weight: .heavy).monospacedDigit())
                            .foregroundStyle(Color.textPrimary)
                    }
                }
            }

            // Down, distance, yard line
            HStack(spacing: 12) {
                situationChip(text: situation.downDistanceLabel, color: .accentGold)
                situationChip(text: situation.yardLineLabel, color: .accentBlue)
                Spacer()
                if let sug = aiOffensiveSuggestion, side == .offense {
                    Label("AI: \(sug.rawValue)", systemImage: "brain")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.textTertiary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.backgroundSecondary)
    }

    private func situationChip(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.15), in: Capsule())
    }

    // MARK: - Offense Grid

    /// The offensive play-call panel groups plays by category.
    private var offenseGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(offensiveCategories, id: \.self) { category in
                    offenseCategorySection(category)
                }
            }
            .padding(20)
        }
    }

    private let offensiveCategories = ["Run", "Short Pass", "Medium Pass", "Deep Pass", "Special"]

    private func offenseCategorySection(_ category: String) -> some View {
        let plays = OffensivePlayCall.allCases.filter { $0.category == category }
        return VStack(alignment: .leading, spacing: 10) {
            // Section header
            Text(category.uppercased())
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(Color.textTertiary)
                .tracking(1.5)

            // Play button grid (two columns)
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                ForEach(plays, id: \.self) { play in
                    offensePlayButton(play)
                }
            }
        }
    }

    @ViewBuilder
    private func offensePlayButton(_ play: OffensivePlayCall) -> some View {
        let isSelected   = selectedOffensiveCall == play
        let isSuggested  = aiOffensiveSuggestion == play
        let borderColor: Color = isSelected ? .accentGold : (isSuggested ? .accentBlue : .surfaceBorder)
        let bgColor: Color     = isSelected ? Color.accentGold.opacity(0.18) : Color.backgroundTertiary
        let textColor: Color   = isSelected ? .accentGold : .textPrimary

        Button {
            withAnimation(.spring(duration: 0.2)) {
                selectedOffensiveCall = play
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(play.rawValue)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(textColor)
                    Spacer()
                    if isSuggested {
                        Image(systemName: "brain")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.accentBlue)
                    }
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.accentGold)
                    }
                }
                Text(playHintText(for: play))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(bgColor, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(borderColor, lineWidth: isSelected || isSuggested ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Defense Grid

    /// The defensive call panel lets the player independently choose a coverage
    /// shell, blitz package, and front alignment — three columns, one selection
    /// active per column.
    private var defenseGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(defensiveCategories, id: \.self) { category in
                    defenseCategorySection(category)
                }

                // Live package summary
                defensePackageSummary
            }
            .padding(20)
        }
    }

    private let defensiveCategories = ["Coverage", "Blitz", "Front"]

    private func defenseCategorySection(_ category: String) -> some View {
        let calls = DefensivePlayCall.allCases.filter { $0.category == category }
        return VStack(alignment: .leading, spacing: 10) {
            Text(category.uppercased())
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(Color.textTertiary)
                .tracking(1.5)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: calls.count),
                spacing: 10
            ) {
                ForEach(calls, id: \.self) { call in
                    defenseCallButton(call)
                }
            }
        }
    }

    @ViewBuilder
    private func defenseCallButton(_ call: DefensivePlayCall) -> some View {
        let isSelected: Bool = {
            switch call.category {
            case "Coverage": return selectedCoverage == call
            case "Blitz":    return selectedBlitz == call
            default:         return selectedFront == call
            }
        }()

        let isSuggested: Bool = {
            guard let sug = aiDefensiveSuggestion else { return false }
            switch call.category {
            case "Coverage": return sug.coverage == call
            case "Blitz":    return sug.blitz == call
            default:         return sug.front == call
            }
        }()

        let borderColor: Color = isSelected ? .accentGold : (isSuggested ? .accentBlue : .surfaceBorder)
        let bgColor: Color     = isSelected ? Color.accentGold.opacity(0.18) : Color.backgroundTertiary
        let textColor: Color   = isSelected ? .accentGold : .textPrimary

        Button {
            withAnimation(.spring(duration: 0.2)) {
                switch call.category {
                case "Coverage": selectedCoverage = call
                case "Blitz":    selectedBlitz = call
                default:         selectedFront = call
                }
            }
        } label: {
            VStack(spacing: 4) {
                Text(call.rawValue)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(textColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                if isSuggested && !isSelected {
                    Image(systemName: "brain")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.accentBlue)
                }
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.accentGold)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(bgColor, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(borderColor, lineWidth: isSelected || isSuggested ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// Summarises the currently selected defensive package modifiers so the
    /// player can see roughly what they're dialing in.
    private var defensePackageSummary: some View {
        let pkg = currentDefensivePackage
        return VStack(alignment: .leading, spacing: 8) {
            Text("PACKAGE SUMMARY")
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(Color.textTertiary)
                .tracking(1.5)

            HStack(spacing: 12) {
                packageStat(
                    label: "Coverage",
                    value: pkg.totalCoverageModifier,
                    iconName: "eye"
                )
                packageStat(
                    label: "Pressure",
                    value: pkg.totalPressureModifier,
                    iconName: "bolt"
                )
                packageStat(
                    label: "Run Stop",
                    value: pkg.totalRunStopModifier,
                    iconName: "figure.walk"
                )
            }
        }
        .padding(14)
        .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.surfaceBorder, lineWidth: 1)
        )
    }

    private func packageStat(label: String, value: Double, iconName: String) -> some View {
        let color: Color = value > 0.05 ? .success : value < -0.05 ? .danger : .textSecondary
        let formatted = value >= 0 ? "+\(Int(value * 100))%" : "\(Int(value * 100))%"
        return VStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.system(size: 14))
                .foregroundStyle(color)
            Text(formatted)
                .font(.system(size: 13, weight: .bold).monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Snap Bar

    private var snapBar: some View {
        HStack(spacing: 16) {
            // Selected play summary
            VStack(alignment: .leading, spacing: 2) {
                Text("Selected")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textTertiary)
                Text(selectedCallSummary)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
            }

            Spacer()

            // Snap button
            Button {
                confirmCall()
            } label: {
                Label("Snap", systemImage: "arrow.up.circle.fill")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(Color.backgroundPrimary)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(
                        snapConfirmed ? Color.success : Color.accentGold,
                        in: Capsule()
                    )
            }
            .disabled(side == .offense && selectedOffensiveCall == nil)
            .animation(.easeInOut(duration: 0.2), value: snapConfirmed)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.backgroundSecondary)
    }

    // MARK: - Helpers

    private var selectedCallSummary: String {
        if side == .offense {
            return selectedOffensiveCall?.rawValue ?? "None selected"
        } else {
            return "\(selectedCoverage.rawValue) / \(selectedBlitz.rawValue) / \(selectedFront.rawValue)"
        }
    }

    private var currentDefensivePackage: DefensivePackage {
        DefensivePackage(
            coverage: selectedCoverage,
            blitz: selectedBlitz,
            front: selectedFront
        )
    }

    private func confirmCall() {
        guard !snapConfirmed else { return }
        snapConfirmed = true

        if side == .offense, let call = selectedOffensiveCall {
            onOffensiveCall(call)
        } else if side == .defense {
            onDefensiveCall(currentDefensivePackage)
        }
    }

    /// Short hint string shown below each play button label.
    private func playHintText(for play: OffensivePlayCall) -> String {
        switch play {
        case .insideRun:    return "Power between the tackles"
        case .outsideRun:   return "Stretch to the edge"
        case .draw:         return "Disguised run; neutralises blitz"
        case .screen:       return "Behind LOS; big YAC upside"
        case .slant:        return "Quick inside break; anti-blitz"
        case .quickOut:     return "Sideline; immediate release"
        case .flat:         return "RB / TE flat; clock stoppage"
        case .drag:         return "Shallow crossing route"
        case .curl:         return "Back-shoulder curl; safe"
        case .dig:          return "Across the middle, 15–20 yds"
        case .postCorner:   return "Double-move; beats safety"
        case .comeback:     return "Down-and-back; precise"
        case .goRoute:      return "Speed vertical; jump ball"
        case .post:         return "Deep middle; vs. Cover 2"
        case .corner:       return "Deep corner; vs. single high"
        case .bomb:         return "Max effort; high INT risk"
        case .qbSneak:      return "Short yardage QB push"
        case .spike:        return "Stop the clock (inc.)"
        case .kneel:        return "Kill clock, take the loss"
        }
    }
}

// MARK: - Preview

#Preview("Offense") {
    PlayCallView(
        side: .offense,
        situation: .init(
            down: 2, distance: 7, yardLine: 38,
            quarter: 3, timeRemaining: 412,
            homeScore: 17, awayScore: 14,
            homeAbbreviation: "KC", awayAbbreviation: "PHI",
            playerTeamIsHome: true
        ),
        aiOffensiveSuggestion: .slant,
        aiDefensiveSuggestion: nil,
        onOffensiveCall: { _ in }
    )
}

#Preview("Defense") {
    PlayCallView(
        side: .defense,
        situation: .init(
            down: 3, distance: 4, yardLine: 62,
            quarter: 4, timeRemaining: 204,
            homeScore: 21, awayScore: 24,
            homeAbbreviation: "KC", awayAbbreviation: "PHI",
            playerTeamIsHome: false
        ),
        aiOffensiveSuggestion: nil,
        aiDefensiveSuggestion: DefensivePackage(coverage: .manToMan, blitz: .lbBlitz, front: .nickel),
        onDefensiveCall: { _ in }
    )
}
