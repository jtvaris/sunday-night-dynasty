import SwiftUI

// MARK: - QuarterReportView

/// End-of-quarter report overlay for the Q1→Q2 and Q3→Q4 breaks of a live
/// coached game (Q2→Q3 belongs to the richer ``HalftimeView``, which embeds
/// the same ``QuarterPlayersPanel``). A compact card: the score so far plus
/// the coached team's full player picture — day grades with trend, HOT/COLD
/// form, fatigue rings, snap counts, stat lines, rookie tracking, and one-tap
/// decision flags (sub suggestion, R28 injury risk, feed-the-hot-hand).
struct QuarterReportView: View {

    @ObservedObject var engine: LiveGameEngine
    let homeTeam: Team
    let awayTeam: Team
    let playerTeamIsHome: Bool
    /// Called when the coach taps Continue (the caller resolves the break).
    let onContinue: () -> Void

    /// The quarter that just ended — the engine has already rolled past it.
    private var endedQuarter: Int { max(1, engine.quarter - 1) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 14) {
                    Text("END OF Q\(endedQuarter)")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(Color.backgroundPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(Color.accentGold, in: Capsule())

                    scoreStrip

                    QuarterPlayersPanel(engine: engine)

                    Button(action: onContinue) {
                        Text("Continue")
                            .font(.system(size: 16, weight: .black))
                            .foregroundStyle(Color.backgroundPrimary)
                            .padding(.horizontal, 44)
                            .padding(.vertical, 13)
                            .background(Color.accentGold, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(22)
                .frame(maxWidth: 760)
                .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Color.accentGold.opacity(0.4), lineWidth: 1.5)
                )
                .padding(.vertical, 30)
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// One-line score: away at home, the coached side in gold.
    private var scoreStrip: some View {
        HStack(spacing: 14) {
            scoreBlock(abbr: awayTeam.abbreviation, score: engine.awayScore, isPlayer: !playerTeamIsHome)
            Text("—")
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(Color.textTertiary)
            scoreBlock(abbr: homeTeam.abbreviation, score: engine.homeScore, isPlayer: playerTeamIsHome)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(Color.backgroundTertiary, in: Capsule())
    }

    private func scoreBlock(abbr: String, score: Int, isPlayer: Bool) -> some View {
        HStack(spacing: 7) {
            Text(abbr)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(isPlayer ? Color.accentGold : Color.textPrimary)
            Text("\(score)")
                .font(.system(size: 19, weight: .black).monospacedDigit())
                .foregroundStyle(isPlayer ? Color.accentGold : Color.textPrimary)
        }
    }
}

// MARK: - QuarterPlayersPanel

/// The coached team's player situation report, shared by ``QuarterReportView``
/// and ``HalftimeView``'s Players tab: Offense and Defense columns of the
/// current field units (bench expandable under each), one compact row per
/// man. Decision flags ride the EXISTING engine mechanisms — a "Sub?" tap
/// queues through `LiveGameEngine.substitute` and lands at the next whistle;
/// the red risk flag reads the R28 rushed-back window. Presentation only.
struct QuarterPlayersPanel: View {

    @ObservedObject var engine: LiveGameEngine
    /// False while a live play owns the field (the engine would reject subs).
    var subsEnabled: Bool = true

    @State private var offenseBenchExpanded = false
    @State private var defenseBenchExpanded = false

    private static let offenseGroups: [LineupGroup] =
        [.quarterbacks, .backfield, .receivers, .tightEnds, .offensiveLine]
    private static let defenseGroups: [LineupGroup] =
        [.defensiveLine, .linebackers, .secondary]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            unitColumn(
                title: "OFFENSE", icon: "arrow.up.forward.circle.fill",
                unit: engine.playerOffenseUnit, isOffense: true,
                benchExpanded: $offenseBenchExpanded
            )
            unitColumn(
                title: "DEFENSE", icon: "shield.fill",
                unit: engine.playerDefenseUnit, isOffense: false,
                benchExpanded: $defenseBenchExpanded
            )
        }
    }

    // MARK: Columns

    private func unitColumn(
        title: String, icon: String, unit: FieldUnit, isOffense: Bool,
        benchExpanded: Binding<Bool>
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.accentGold)
                Text(title)
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(Color.textTertiary)
                    .tracking(1.5)
            }
            .padding(.bottom, 2)

            ForEach(unit.players, id: \.id) { player in
                playerRow(player, isOffense: isOffense)
            }

            benchSection(isOffense: isOffense, expanded: benchExpanded)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Field-player row

    private func playerRow(_ player: SimPlayer, isOffense: Bool) -> some View {
        let grade = engine.playerGameGrade(player.id)
        let trend = engine.gradeTrend(player.id)
        let fatigue = engine.liveLine(for: player.id)?.fatigue ?? player.fatigue
        let snaps = engine.snapCount(player.id)
        let statLine = engine.liveLine(for: player.id)?.statLine ?? ""
        let streak = engine.formStreak(player.id)

        return HStack(spacing: 7) {
            gradeRing(grade: grade, fatigue: fatigue, diameter: 30)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(player.shortName)
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("#\(player.displayNumber)")
                        .font(.system(size: 8.5, weight: .bold).monospacedDigit())
                        .foregroundStyle(Color.textTertiary)
                    trendArrow(trend)
                    formIcon(streak)
                    temperamentBadge(player)
                    rookieBadge(player.id)
                }
                HStack(spacing: 4) {
                    Text("\(snaps) SNP")
                        .font(.system(size: 8.5, weight: .black).monospacedDigit())
                        .foregroundStyle(Color.textTertiary)
                    if !statLine.isEmpty {
                        Text("· \(statLine)")
                            .font(.system(size: 8.5, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
            }

            Spacer(minLength: 3)

            flagChip(for: player, isOffense: isOffense, fatigue: fatigue,
                     trend: trend, streak: streak)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Color.backgroundTertiary.opacity(0.45), in: RoundedRectangle(cornerRadius: 9))
    }

    // MARK: Decision flags

    /// The row's single decision-support chip, priority-ordered: a queued
    /// sub confirms itself, R28 injury risk outranks everything actionable,
    /// then the fatigue-driven sub suggestion, the hot hand, the cold note.
    @ViewBuilder
    private func flagChip(
        for player: SimPlayer, isOffense: Bool, fatigue: Int,
        trend: Int, streak: LiveGameEngine.FormStreak?
    ) -> some View {
        if engine.pendingSubstitutions.contains(where: { $0.fieldPlayerID == player.id }) {
            chip(text: "QUEUED", icon: "clock.fill", tint: .warning)
        } else if engine.hasElevatedInjuryRisk(player.id) {
            chip(text: "INJURY RISK", icon: "exclamationmark.triangle.fill", tint: .danger)
        } else if fatigue >= 70, trend <= -1,
                  let bench = bestBenchOption(for: player, fatigue: fatigue) {
            subSuggestionChip(bench: bench, fieldPlayer: player)
        } else if engine.isFrustrated(player.id) {
            // #36B mech 2: a starved ego star — feed him or he presses.
            chip(text: "WANTS BALL", icon: "hand.raised.fill", tint: .warning)
        } else if streak == .hot, isOffense, isFeedablePosition(player.position) {
            chip(text: "FEED HIM", icon: "flame.fill", tint: .success)
        } else if streak == .cold {
            chip(text: "COLD", icon: "snowflake", tint: .textTertiary)
        }
    }

    /// "Sub? → J. Cook" — one tap queues the swap into the existing whistle
    /// queue (`LiveGameEngine.substitute`); the row then shows QUEUED.
    private func subSuggestionChip(bench: SimPlayer, fieldPlayer: SimPlayer) -> some View {
        Button {
            engine.substitute(benchPlayerID: bench.id, forFieldPlayerID: fieldPlayer.id)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 8, weight: .black))
                Text("SUB? → \(bench.shortName)")
                    .font(.system(size: 8.5, weight: .black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(subsEnabled ? Color.backgroundPrimary : Color.textTertiary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(subsEnabled ? Color.warning : Color.backgroundTertiary, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!subsEnabled)
        .accessibilityLabel(Text("Substitute \(bench.shortName) in for \(fieldPlayer.shortName)"))
    }

    private func chip(text: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .black))
            Text(text)
                .font(.system(size: 8.5, weight: .black))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(tint.opacity(0.14), in: Capsule())
    }

    /// The best rested bench man in the tired starter's position group —
    /// same freshness bar the auto RB rotation uses (10+ points fresher).
    private func bestBenchOption(for player: SimPlayer, fatigue: Int) -> SimPlayer? {
        engine.benchPlayers(forHome: engine.playerTeamIsHome,
                            position: LineupGroup(of: player.position))
            .first { $0.fatigue <= fatigue - 10 }
    }

    /// "Feed him" only makes sense for the men you can scheme touches to.
    private func isFeedablePosition(_ position: Position) -> Bool {
        switch position {
        case .RB, .FB, .WR, .TE: return true
        default:                 return false
        }
    }

    // MARK: Rookie badge

    /// "R · EXCEEDING / ON TRACK / BEHIND" against the draft-slot billing;
    /// a plain grey R until the rookie has taken a snap.
    @ViewBuilder
    private func rookieBadge(_ playerID: UUID) -> some View {
        if engine.isRookie(playerID) {
            if let watch = engine.rookieWatch(playerID) {
                let (label, tint): (String, Color) = {
                    switch watch.verdict {
                    case .exceeding:  return ("R · EXCEEDING", .success)
                    case .meeting:    return ("R · ON TRACK", .textSecondary)
                    case .struggling: return ("R · BEHIND", .danger)
                    }
                }()
                Text(label)
                    .font(.system(size: 7.5, weight: .black))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(tint.opacity(0.14), in: Capsule())
                    .accessibilityLabel(Text("Rookie, \(watch.expectationLabel), \(label)"))
            } else {
                Text("R")
                    .font(.system(size: 7.5, weight: .black))
                    .foregroundStyle(Color.textTertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.textTertiary.opacity(0.14), in: Capsule())
                    .accessibilityLabel(Text("Rookie"))
            }
        }
    }

    // MARK: Bench

    @ViewBuilder
    private func benchSection(isOffense: Bool, expanded: Binding<Bool>) -> some View {
        let bench = benchPlayers(isOffense: isOffense)
        if !bench.isEmpty {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.wrappedValue.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: expanded.wrappedValue ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .black))
                    Text("BENCH (\(bench.count))")
                        .font(.system(size: 9, weight: .black))
                        .tracking(1.0)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Color.textTertiary)
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded.wrappedValue {
                ForEach(bench, id: \.id) { player in
                    benchRow(player)
                }
            }
        }
    }

    /// Group-ordered bench (each group best-first, per the engine's sort).
    private func benchPlayers(isOffense: Bool) -> [SimPlayer] {
        let groups = isOffense ? QuarterPlayersPanel.offenseGroups : QuarterPlayersPanel.defenseGroups
        return groups.flatMap {
            engine.benchPlayers(forHome: engine.playerTeamIsHome, position: $0)
        }
    }

    /// Compact bench line: position, name, form icon, snaps (if any), OVR,
    /// fatigue bar — enough to judge the "Sub?" suggestions at a glance.
    private func benchRow(_ player: SimPlayer) -> some View {
        let snaps = engine.snapCount(player.id)
        return HStack(spacing: 6) {
            Text(player.position.rawValue)
                .font(.system(size: 8.5, weight: .black))
                .foregroundStyle(Color.textTertiary)
                .frame(width: 24, alignment: .leading)
            Text(player.shortName)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            formIcon(engine.formStreak(player.id))
            temperamentBadge(player)
            if snaps > 0 {
                Text("\(snaps) SNP")
                    .font(.system(size: 8, weight: .black).monospacedDigit())
                    .foregroundStyle(Color.textTertiary)
            }
            Spacer(minLength: 3)
            Text("\(player.overall)")
                .font(.system(size: 10.5, weight: .black).monospacedDigit())
                .foregroundStyle(Color.forRating(player.overall))
            fatigueBar(player.fatigue)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.backgroundTertiary.opacity(0.25), in: RoundedRectangle(cornerRadius: 7))
    }

    // MARK: Bits

    /// Day grade inside a fatigue ring — same visual language as the
    /// Coach's Board (ring fills and reddens as the man tires).
    private func gradeRing(grade: Int, fatigue: Int, diameter: CGFloat) -> some View {
        let fraction = min(1.0, max(0.0, Double(fatigue) / 100.0))
        let ringColor: Color = fatigue >= 70 ? .danger : (fatigue >= 40 ? .warning : .success)
        return ZStack {
            Circle()
                .stroke(Color.backgroundTertiary, lineWidth: 3)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(grade)")
                .font(.system(size: 11.5, weight: .black).monospacedDigit())
                .foregroundStyle(gradeColor(grade))
        }
        .frame(width: diameter, height: diameter)
    }

    /// Day-grade color bands — same thresholds as the Coach's Board.
    private func gradeColor(_ grade: Int) -> Color {
        switch grade {
        case 80...:   return .accentGold
        case 70..<80: return .success
        case 55..<70: return .textSecondary
        default:      return .danger
        }
    }

    private func trendArrow(_ trend: Int) -> some View {
        Image(systemName: trend >= 2 ? "arrow.up.right" : (trend <= -2 ? "arrow.down.right" : "arrow.right"))
            .font(.system(size: 9, weight: .black))
            .foregroundStyle(trend >= 2 ? Color.success : (trend <= -2 ? Color.danger : Color.textTertiary))
    }

    @ViewBuilder
    private func formIcon(_ streak: LiveGameEngine.FormStreak?) -> some View {
        switch streak {
        case .hot:
            Image(systemName: "flame.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.warning)
                .accessibilityLabel(Text("Hot streak"))
        case .cold:
            Image(systemName: "snowflake")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.accentBlue)
                .accessibilityLabel(Text("Cold streak"))
        case nil:
            EmptyView()
        }
    }

    /// #36B mech 4: a static temperament tag so the coach can lead with
    /// personalities — the crown demands touches, the bolt runs hot & cold,
    /// the seal is unflappable. Distinct from `formIcon` (the live streak).
    @ViewBuilder
    private func temperamentBadge(_ player: SimPlayer) -> some View {
        switch player.mentalTemperament {
        case .egoDriven:
            Image(systemName: "crown.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color.accentGold)
                .accessibilityLabel(Text("Ego-driven"))
        case .streaky:
            Image(systemName: "bolt.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color.warning)
                .accessibilityLabel(Text("Streaky temperament"))
        case .unflappable:
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color.accentBlue)
                .accessibilityLabel(Text("Unflappable"))
        case .neutral:
            EmptyView()
        }
    }

    private func fatigueBar(_ fatigue: Int) -> some View {
        let fraction = min(1.0, max(0.0, Double(fatigue) / 100.0))
        let color: Color = fatigue >= 70 ? .danger : (fatigue >= 40 ? .warning : .success)
        return ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.backgroundTertiary)
                .frame(width: 30, height: 4)
            Capsule()
                .fill(color)
                .frame(width: max(2, 30 * fraction), height: 4)
        }
    }
}
