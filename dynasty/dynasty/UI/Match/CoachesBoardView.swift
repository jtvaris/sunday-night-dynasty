import SwiftUI

// MARK: - Coach's Board

/// Full-screen in-game player management for the PLAYER's team — replaces the
/// old narrow squad sheet.
///
/// LEFT (~58 %): the current eleven laid out in a real formation on a tactics
/// board (LOS, yard lines, hash marks), every man carrying his DAY GRADE
/// (0–100, color-coded), a fatigue ring, and status badges. Tap a card to
/// select him.
///
/// RIGHT (~42 %): the selected player's panel — big grade with trend arrow,
/// per-category battle bars (pass pro, coverage, …), today's stat line,
/// OVR / morale / personality / fatigue — and the position-group bench with
/// one-tap SUB IN. Substitutions ride the existing `LiveGameEngine.substitute`
/// queue and land at the next whistle; a pending chip marks the queued swap.
/// The AI opponent is never shown and never substitutes.
struct CoachesBoardView: View {

    /// A contract holdout of the coached team: he never suited up, so the
    /// engine's rosters don't contain him — surfaced on the bench as context.
    struct HoldoutLine: Identifiable {
        let id: UUID
        let name: String
        let position: Position
    }

    @ObservedObject var engine: LiveGameEngine
    /// The coached team's abbreviation, for the header.
    let teamAbbr: String
    /// Holdouts on the coached team's roster (possibly empty).
    let holdouts: [HoldoutLine]
    /// True while a play animation is running — substitutions are locked.
    let subsDisabled: Bool

    @Environment(\.dismiss) private var dismiss

    /// Offense/Defense unit toggle.
    @State private var showingOffense: Bool
    /// The field player whose panel is open (always someone in the unit).
    @State private var selectedPlayerID: UUID?

    init(
        engine: LiveGameEngine,
        teamAbbr: String,
        holdouts: [HoldoutLine],
        initialUnitIsOffense: Bool,
        subsDisabled: Bool
    ) {
        self.engine = engine
        self.teamAbbr = teamAbbr
        self.holdouts = holdouts
        self.subsDisabled = subsDisabled
        _showingOffense = State(initialValue: initialUnitIsOffense)
        let unit = initialUnitIsOffense ? engine.playerOffenseUnit : engine.playerDefenseUnit
        _selectedPlayerID = State(initialValue: unit.players.first?.id)
    }

    // MARK: Layout Constants

    /// Board fraction of the screen width (right panel takes the rest).
    private static let boardFraction: CGFloat = 0.58
    /// Line of scrimmage, as a fraction of board height from the top.
    private static let losY: CGFloat = 0.12

    /// Normalized board slots per offensive role
    /// (0=QB 1=RB 2=LT 3=LG 4=C 5=RG 6=RT 7=WR-L 8=WR-R 9=slot 10=TE).
    private static let offenseSlots: [CGPoint] = [
        CGPoint(x: 0.50, y: 0.37),  // QB
        CGPoint(x: 0.50, y: 0.53),  // RB
        CGPoint(x: 0.22, y: 0.20),  // LT
        CGPoint(x: 0.36, y: 0.20),  // LG
        CGPoint(x: 0.50, y: 0.20),  // C
        CGPoint(x: 0.64, y: 0.20),  // RG
        CGPoint(x: 0.78, y: 0.20),  // RT
        CGPoint(x: 0.08, y: 0.20),  // WR-L (split end, on the line)
        CGPoint(x: 0.85, y: 0.33),  // WR-R (flanker, off the line)
        CGPoint(x: 0.15, y: 0.33),  // slot
        CGPoint(x: 0.92, y: 0.20),  // TE (inline right)
    ]

    /// Normalized board slots per defensive role
    /// (0–3=DL 4–6=LB 7–8=CB 9–10=S), lined up under the LOS facing up.
    private static let defenseSlots: [CGPoint] = [
        CGPoint(x: 0.29, y: 0.20),  // DE-L
        CGPoint(x: 0.43, y: 0.20),  // DT
        CGPoint(x: 0.57, y: 0.20),  // DT
        CGPoint(x: 0.71, y: 0.20),  // DE-R
        CGPoint(x: 0.29, y: 0.36),  // LB-L
        CGPoint(x: 0.50, y: 0.36),  // MLB
        CGPoint(x: 0.71, y: 0.36),  // LB-R
        CGPoint(x: 0.08, y: 0.22),  // CB-L
        CGPoint(x: 0.92, y: 0.22),  // CB-R
        CGPoint(x: 0.35, y: 0.54),  // S-L
        CGPoint(x: 0.65, y: 0.54),  // S-R
    ]

    // Night-turf board tones (chrome stays on the shared design tokens; the
    // board surface itself is deliberately field-green, like the 3D turf).
    private static let boardGreenTop = Color(red: 0.075, green: 0.196, blue: 0.110)
    private static let boardGreenBottom = Color(red: 0.047, green: 0.129, blue: 0.078)

    // MARK: Body

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        formationPanel
                            .frame(width: geo.size.width * CoachesBoardView.boardFraction)
                            .padding([.leading, .bottom], 12)
                            .padding(.top, 4)
                        detailPanel
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    // MARK: Top Bar

    private var topBar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.grid.3x2.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.accentGold)
                Text("COACH'S BOARD · \(teamAbbr)")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(Color.textPrimary)
                    .tracking(1.6)
            }

            unitToggle

            if subsDisabled && !engine.isGameOver {
                HStack(spacing: 6) {
                    ProgressView()
                        .tint(Color.accentGold)
                        .scaleEffect(0.7)
                    Text("Play is live — subs unlock at the whistle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.textSecondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.backgroundTertiary.opacity(0.7), in: Capsule())
            }

            Spacer(minLength: 8)

            if !engine.pendingSubstitutions.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text("\(engine.pendingSubstitutions.count) sub\(engine.pendingSubstitutions.count == 1 ? "" : "s") at next whistle")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(Color.warning)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.warning.opacity(0.14), in: Capsule())
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(Color.backgroundTertiary, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.backgroundSecondary)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.surfaceBorder), alignment: .bottom)
    }

    private var unitToggle: some View {
        HStack(spacing: 4) {
            unitTab("OFFENSE", isOn: showingOffense) { switchUnit(toOffense: true) }
            unitTab("DEFENSE", isOn: !showingOffense) { switchUnit(toOffense: false) }
        }
        .padding(3)
        .background(Color.backgroundTertiary, in: Capsule())
    }

    private func unitTab(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .black))
                .tracking(0.8)
                .foregroundStyle(isOn ? Color.backgroundPrimary : Color.textSecondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isOn ? Color.accentGold : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func switchUnit(toOffense: Bool) {
        guard showingOffense != toOffense else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            showingOffense = toOffense
            selectedPlayerID = (toOffense ? engine.playerOffenseUnit : engine.playerDefenseUnit)
                .players.first?.id
        }
    }

    // MARK: Current Unit & Selection

    private var currentUnit: FieldUnit {
        showingOffense ? engine.playerOffenseUnit : engine.playerDefenseUnit
    }

    /// The selected man, falling back to the unit's first slot so the panel
    /// is never empty (selection can go stale across a unit toggle).
    private var selectedPlayer: SimPlayer {
        let unit = currentUnit
        return unit.players.first { $0.id == selectedPlayerID } ?? unit[0]
    }

    // MARK: - Formation Panel (left)

    private var formationPanel: some View {
        GeometryReader { geo in
            let unit = currentUnit
            let slots = showingOffense ? CoachesBoardView.offenseSlots : CoachesBoardView.defenseSlots
            let cardWidth = min(76, max(52, geo.size.width * 0.125))
            ZStack {
                boardBackdrop
                ForEach(Array(unit.players.enumerated()), id: \.element.id) { role, player in
                    formationCard(player: player, width: cardWidth)
                        .position(
                            x: min(geo.size.width - cardWidth / 2 - 5,
                                   max(cardWidth / 2 + 5, slots[role].x * geo.size.width)),
                            y: slots[role].y * geo.size.height
                        )
                }
            }
            .overlay(alignment: .bottom) { gradeLegend.padding(.bottom, 12) }
        }
    }

    /// Tactics-board turf: LOS, receding yard lines, and hash-mark columns.
    private var boardBackdrop: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(LinearGradient(
                    colors: [CoachesBoardView.boardGreenTop, CoachesBoardView.boardGreenBottom],
                    startPoint: .top, endPoint: .bottom
                ))
            Canvas { context, size in
                let losY = CoachesBoardView.losY * size.height
                // Yard lines every "5 yards" below the LOS, fading with depth.
                var y = losY
                var index = 0
                while y < size.height - 12 {
                    var line = Path()
                    line.move(to: CGPoint(x: 12, y: y))
                    line.addLine(to: CGPoint(x: size.width - 12, y: y))
                    if index == 0 {
                        context.stroke(line, with: .color(.white.opacity(0.55)), lineWidth: 2)
                    } else {
                        context.stroke(line, with: .color(.white.opacity(0.10)), lineWidth: 1)
                    }
                    y += size.height * 0.14
                    index += 1
                }
                // NFL hash columns astride the middle of the field.
                for xFraction in [0.44, 0.56] {
                    let x = xFraction * size.width
                    var tickY = losY + size.height * 0.035
                    while tickY < size.height - 14 {
                        var tick = Path()
                        tick.move(to: CGPoint(x: x - 4, y: tickY))
                        tick.addLine(to: CGPoint(x: x + 4, y: tickY))
                        context.stroke(tick, with: .color(.white.opacity(0.14)), lineWidth: 1.5)
                        tickY += size.height * 0.07
                    }
                }
                // Label the line of scrimmage in the top-right corner.
                context.draw(
                    Text("LOS")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(.white.opacity(0.55)),
                    at: CGPoint(x: size.width - 26, y: losY - 10)
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.surfaceBorder, lineWidth: 1)
        )
    }

    /// One man on the board: grade in a fatigue ring, name, number + position.
    private func formationCard(player: SimPlayer, width: CGFloat) -> some View {
        let grade = engine.playerGameGrade(player.id)
        let fatigue = engine.liveLine(for: player.id)?.fatigue ?? player.fatigue
        let isSelected = selectedPlayer.id == player.id
        let hasPendingSub = engine.pendingSubstitutions.contains { $0.fieldPlayerID == player.id }
        let isOut = engine.wentDownThisGame(player.id)

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { selectedPlayerID = player.id }
        } label: {
            VStack(spacing: 3) {
                gradeRing(grade: grade, fatigue: fatigue, diameter: 44, gradeFontSize: 17)
                Text(player.shortName)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("#\(player.displayNumber) \(player.position.rawValue)")
                    .font(.system(size: 8.5, weight: .black).monospacedDigit())
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 3)
            .frame(width: width)
            .background(
                RoundedRectangle(cornerRadius: 11)
                    .fill(Color.backgroundSecondary.opacity(isSelected ? 1.0 : 0.9))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(
                        isSelected ? Color.accentGold : Color.surfaceBorder,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .overlay(alignment: .topTrailing) {
                if isOut {
                    statusBadge(icon: "cross.fill", tint: .danger)
                } else if hasPendingSub {
                    statusBadge(icon: "clock.fill", tint: .warning)
                }
            }
            .shadow(color: isSelected ? Color.accentGold.opacity(0.35) : .clear, radius: 7)
        }
        .buttonStyle(.plain)
    }

    private func statusBadge(icon: String, tint: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 8, weight: .black))
            .foregroundStyle(Color.backgroundPrimary)
            .frame(width: 16, height: 16)
            .background(tint, in: Circle())
            .offset(x: 5, y: -5)
    }

    /// Day grade inside a fatigue ring: the ring fills (and reddens) as the
    /// man tires — same thresholds the auto-rotation reacts to.
    private func gradeRing(grade: Int, fatigue: Int, diameter: CGFloat, gradeFontSize: CGFloat) -> some View {
        let fraction = min(1.0, max(0.0, Double(fatigue) / 100.0))
        let ringColor: Color = fatigue >= 70 ? .danger : (fatigue >= 40 ? .warning : .success)
        return ZStack {
            Circle()
                .stroke(Color.backgroundTertiary, lineWidth: diameter > 60 ? 5 : 3.5)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(ringColor, style: StrokeStyle(lineWidth: diameter > 60 ? 5 : 3.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(grade)")
                .font(.system(size: gradeFontSize, weight: .black).monospacedDigit())
                .foregroundStyle(gradeColor(grade))
        }
        .frame(width: diameter, height: diameter)
    }

    /// Board legend for the grade colors.
    private var gradeLegend: some View {
        HStack(spacing: 12) {
            legendDot(color: .accentGold, label: "80+")
            legendDot(color: .success, label: "70+")
            legendDot(color: .textSecondary, label: "55+")
            legendDot(color: .danger, label: "<55")
            Text("· ring = fatigue")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.35), in: Capsule())
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 10, weight: .bold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    /// Day-grade color bands: gold 80+, green 70–79, grey 55–69, red < 55.
    private func gradeColor(_ grade: Int) -> Color {
        switch grade {
        case 80...:   return .accentGold
        case 70..<80: return .success
        case 55..<70: return .textSecondary
        default:      return .danger
        }
    }

    // MARK: - Detail Panel (right)

    private var detailPanel: some View {
        ScrollView {
            VStack(spacing: 12) {
                if !engine.pendingSubstitutions.isEmpty { pendingCard }
                selectedPlayerCard
                benchCard
            }
            .padding(12)
        }
    }

    /// Queued swaps waiting for the whistle, each cancellable.
    private var pendingCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("PENDING · AT NEXT WHISTLE", icon: "clock.fill", tint: .warning)
            ForEach(engine.pendingSubstitutions) { sub in
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.warning)
                    Text("\(sub.benchName) in for \(sub.fieldName)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        engine.cancelSubstitution(sub.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(Color.textTertiary)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.warning.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(Color.warning.opacity(0.35), lineWidth: 1)
                )
            }
        }
        .padding(14)
        .cardBackground()
    }

    // MARK: Selected Player

    private var selectedPlayerCard: some View {
        let player = selectedPlayer
        let line = engine.liveLine(for: player.id)
        let grade = engine.playerGameGrade(player.id)
        let trend = engine.gradeTrend(player.id)

        return VStack(alignment: .leading, spacing: 12) {
            // Identity row
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(player.shortName)
                        .font(.system(size: 19, weight: .black))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    HStack(spacing: 6) {
                        Text("#\(player.displayNumber) · \(player.position.rawValue)")
                            .font(.system(size: 12, weight: .bold).monospacedDigit())
                            .foregroundStyle(Color.textSecondary)
                        if let archetype = engine.personalityArchetype(for: player.id) {
                            personalityChip(archetype)
                        }
                    }
                }
                Spacer()
                VStack(spacing: 2) {
                    Text("OVR")
                        .font(.system(size: 9, weight: .black))
                        .tracking(1.2)
                        .foregroundStyle(Color.textTertiary)
                    Text("\(player.overall)")
                        .font(.system(size: 22, weight: .black).monospacedDigit())
                        .foregroundStyle(Color.forRating(player.overall))
                }
            }

            // Day grade, big and color-coded, with the trend arrow.
            HStack(spacing: 14) {
                gradeRing(grade: grade, fatigue: line?.fatigue ?? player.fatigue,
                          diameter: 86, gradeFontSize: 36)
                VStack(alignment: .leading, spacing: 5) {
                    Text("DAY GRADE")
                        .font(.system(size: 10, weight: .black))
                        .tracking(1.4)
                        .foregroundStyle(Color.textTertiary)
                    HStack(spacing: 7) {
                        trendArrow(trend)
                        Text(trendLabel(trend))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(trendColor(trend))
                    }
                    Text(line.map { $0.statLine.isEmpty ? "No touches yet" : $0.statLine }
                         ?? "No touches yet")
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }

            // Battle record split by category (role-relevant bars).
            let categories = engine.categoryLines(for: player.id, position: player.position)
            if !categories.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    sectionTitle(
                        "BATTLES \(battleRecordText(line))",
                        icon: "figure.wrestling", tint: .accentGold
                    )
                    ForEach(categories) { category in
                        categoryBar(category)
                    }
                }
            }

            // Condition meters.
            HStack(spacing: 14) {
                conditionMeter(
                    label: "FATIGUE",
                    value: line?.fatigue ?? player.fatigue,
                    color: (line?.fatigue ?? player.fatigue) >= 70 ? .danger
                        : ((line?.fatigue ?? player.fatigue) >= 40 ? .warning : .success)
                )
                conditionMeter(
                    label: "MORALE",
                    value: line?.morale ?? player.morale,
                    color: (line?.morale ?? player.morale) >= 65 ? .success
                        : ((line?.morale ?? player.morale) >= 40 ? .warning : .danger)
                )
            }
        }
        .padding(14)
        .cardBackground()
    }

    private func battleRecordText(_ line: LiveGameEngine.LivePlayerLine?) -> String {
        guard let line, line.matchupWins + line.matchupLosses > 0 else { return "" }
        return "· \(line.matchupWins)-\(line.matchupLosses)"
    }

    private func personalityChip(_ archetype: PersonalityArchetype) -> some View {
        let tint: Color
        switch archetype.tier {
        case .positive: tint = .success
        case .risky:    tint = .danger
        case .neutral:  tint = .textSecondary
        }
        return Text(archetype.shortLabel.uppercased())
            .font(.system(size: 9, weight: .black))
            .tracking(0.6)
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.14), in: Capsule())
    }

    private func trendArrow(_ trend: Int) -> some View {
        Image(systemName: trend >= 2 ? "arrow.up.right" : (trend <= -2 ? "arrow.down.right" : "arrow.right"))
            .font(.system(size: 14, weight: .black))
            .foregroundStyle(trendColor(trend))
    }

    private func trendColor(_ trend: Int) -> Color {
        trend >= 2 ? .success : (trend <= -2 ? .danger : .textSecondary)
    }

    private func trendLabel(_ trend: Int) -> String {
        trend >= 2 ? "Trending up" : (trend <= -2 ? "Trending down" : "Holding steady")
    }

    /// One category's W–L split bar: green wins vs red losses, grey when unfought.
    private func categoryBar(_ line: LiveGameEngine.CategoryLine) -> some View {
        let total = line.wins + line.losses
        return HStack(spacing: 8) {
            Text(line.category.rawValue.uppercased())
                .font(.system(size: 10, weight: .black))
                .tracking(0.8)
                .foregroundStyle(total == 0 ? Color.textTertiary : Color.textSecondary)
                .frame(width: 104, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.backgroundTertiary)
                    if total > 0 {
                        HStack(spacing: 1) {
                            Capsule()
                                .fill(Color.success)
                                .frame(width: max(line.wins > 0 ? 4 : 0,
                                                  geo.size.width * CGFloat(line.wins) / CGFloat(total)))
                            Capsule()
                                .fill(Color.danger)
                                .frame(maxWidth: .infinity)
                                .opacity(line.losses > 0 ? 1 : 0)
                        }
                    }
                }
            }
            .frame(height: 7)
            Text(total == 0 ? "—" : "\(line.wins)-\(line.losses)")
                .font(.system(size: 12, weight: .bold).monospacedDigit())
                .foregroundStyle(total == 0 ? Color.textTertiary
                                 : (line.wins >= line.losses ? Color.success : Color.danger))
                .frame(width: 34, alignment: .trailing)
        }
    }

    private func conditionMeter(label: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 9, weight: .black))
                    .tracking(1.2)
                    .foregroundStyle(Color.textTertiary)
                Spacer()
                Text("\(value)")
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .foregroundStyle(color)
            }
            ZStack(alignment: .leading) {
                Capsule().fill(Color.backgroundTertiary).frame(height: 6)
                GeometryReader { geo in
                    Capsule()
                        .fill(color)
                        .frame(width: max(3, geo.size.width * CGFloat(min(100, max(0, value))) / 100))
                }
                .frame(height: 6)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Bench

    private var benchCard: some View {
        let player = selectedPlayer
        let group = LineupGroup(of: player.position)
        let candidates = engine.benchPlayers(forHome: engine.playerTeamIsHome, position: group)
        let out = engine.injuredPlayers(forHome: engine.playerTeamIsHome, position: group)
        let groupHoldouts = holdouts.filter { LineupGroup(of: $0.position) == group }

        return VStack(alignment: .leading, spacing: 8) {
            sectionTitle("BENCH · \(group.sectionTitle)", icon: "chair.lounge.fill", tint: .accentGold)

            if candidates.isEmpty && out.isEmpty && groupHoldouts.isEmpty {
                Text("No substitutes in this group.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textTertiary)
                    .padding(.vertical, 4)
            }

            ForEach(candidates, id: \.id) { candidate in
                benchRow(candidate, replacing: player)
            }

            ForEach(out, id: \.id) { man in
                unavailableRow(name: man.shortName, number: man.displayNumber,
                               position: man.position.rawValue, badge: "OUT", tint: .danger)
            }
            ForEach(groupHoldouts) { holdout in
                unavailableRow(name: holdout.name, number: nil,
                               position: holdout.position.rawValue, badge: "HOLDOUT", tint: .warning)
            }
        }
        .padding(14)
        .cardBackground()
    }

    /// One healthy bench man: OVR, day W-L (if he already played), fatigue,
    /// and the one-tap SUB IN that queues the swap for the next whistle.
    private func benchRow(_ candidate: SimPlayer, replacing fieldPlayer: SimPlayer) -> some View {
        let line = engine.liveLine(for: candidate.id)
        let isQueued = engine.pendingSubstitutions.contains {
            $0.benchPlayerID == candidate.id && $0.fieldPlayerID == fieldPlayer.id
        }
        return HStack(spacing: 8) {
            Text("#\(candidate.displayNumber)")
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .foregroundStyle(Color.textTertiary)
                .frame(width: 32, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(candidate.shortName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(candidate.position.rawValue)
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(Color.textTertiary)
                    if let line, line.matchupWins + line.matchupLosses > 0 {
                        Text("\(line.matchupWins)-\(line.matchupLosses) battles")
                            .font(.system(size: 9, weight: .bold).monospacedDigit())
                            .foregroundStyle(line.matchupWins >= line.matchupLosses
                                             ? Color.success : Color.danger)
                    }
                }
            }
            Spacer(minLength: 4)
            Text("\(candidate.overall)")
                .font(.system(size: 14, weight: .black).monospacedDigit())
                .foregroundStyle(Color.forRating(candidate.overall))
                .frame(width: 26, alignment: .trailing)
            benchFatigueBar(line?.fatigue ?? candidate.fatigue)
            if isQueued {
                HStack(spacing: 4) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text("QUEUED")
                        .font(.system(size: 10, weight: .black))
                }
                .foregroundStyle(Color.warning)
                .padding(.horizontal, 9)
                .frame(minHeight: 36)
                .background(Color.warning.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
            } else {
                Button {
                    // Queues at the next whistle; a rejection (e.g. stale
                    // state) simply leaves the row actionable.
                    engine.substitute(
                        benchPlayerID: candidate.id,
                        forFieldPlayerID: fieldPlayer.id
                    )
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text("SUB IN")
                            .font(.system(size: 11, weight: .black))
                            .tracking(0.5)
                    }
                    .foregroundStyle(subsDisabled ? Color.textTertiary : Color.backgroundPrimary)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 36)
                    .background(
                        subsDisabled ? Color.backgroundTertiary : Color.success,
                        in: RoundedRectangle(cornerRadius: 9)
                    )
                }
                .buttonStyle(.plain)
                .disabled(subsDisabled)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.backgroundTertiary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }

    /// Greyed roster line for men who cannot enter (injured out / holdout).
    private func unavailableRow(
        name: String, number: Int?, position: String, badge: String, tint: Color
    ) -> some View {
        HStack(spacing: 8) {
            Text(number.map { "#\($0)" } ?? "—")
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .foregroundStyle(Color.textTertiary)
                .frame(width: 32, alignment: .leading)
            Text(name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
                .lineLimit(1)
            Text(position)
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(Color.textTertiary)
            Spacer(minLength: 4)
            Text(badge)
                .font(.system(size: 9, weight: .black))
                .tracking(0.8)
                .foregroundStyle(tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(tint.opacity(0.14), in: Capsule())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.backgroundTertiary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
    }

    private func benchFatigueBar(_ fatigue: Int) -> some View {
        let fraction = min(1.0, max(0.0, Double(fatigue) / 100.0))
        let color: Color = fatigue >= 70 ? .danger : (fatigue >= 40 ? .warning : .success)
        return ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.backgroundTertiary)
                .frame(width: 44, height: 5)
            Capsule()
                .fill(color)
                .frame(width: max(3, 44 * fraction), height: 5)
        }
    }

    // MARK: Bits

    private func sectionTitle(_ text: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(Color.textTertiary)
                .tracking(1.5)
        }
    }
}
