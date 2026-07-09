import SwiftUI
import SceneKit

// MARK: - CoachedGameView

/// Full-screen live coached game. Unlike ``MatchView`` (which replays a
/// pre-simulated result), every play here is decided by ``LiveGameEngine`` at
/// the moment it is called: the user's offensive play call and defensive
/// package genuinely bias the simulation.
///
/// Layout (portrait iPad):
///   scoreboard / situation strip
///   3D field (SceneKit) with play choreography
///   mini play feed
///   call panel — offense play calling, 4th-down decisions, or defense presets
struct CoachedGameView: View {

    // MARK: Input

    let homeTeam: Team
    let awayTeam: Team
    let playerTeamIsHome: Bool
    /// Called when the user taps Continue on the final whistle overlay.
    /// The caller persists the result and presents the game summary.
    let onFinish: (LiveGameEngine) -> Void

    @StateObject private var engine: LiveGameEngine

    init(
        homeTeam: Team,
        awayTeam: Team,
        homeCoaches: [Coach],
        awayCoaches: [Coach],
        playerTeamIsHome: Bool,
        audibleBoost: Double = 0,
        defReadBoost: Double = 0,
        onFinish: @escaping (LiveGameEngine) -> Void
    ) {
        self.homeTeam = homeTeam
        self.awayTeam = awayTeam
        self.playerTeamIsHome = playerTeamIsHome
        self.onFinish = onFinish
        _engine = StateObject(wrappedValue: LiveGameEngine(
            homeTeam: homeTeam,
            awayTeam: awayTeam,
            homeCoaches: homeCoaches,
            awayCoaches: awayCoaches,
            playerTeamIsHome: playerTeamIsHome,
            audibleBoost: audibleBoost,
            defReadBoost: defReadBoost
        ))
    }

    // MARK: Scene & Flow State

    @State private var fieldScene = FootballFieldScene()
    @State private var isAnimating = false
    /// The field grows while a play is live and shrinks back when the call
    /// sheet needs the room.
    private var fieldExpanded: Bool { isAnimating }
    @State private var gameStarted = false
    @State private var resultBanner: String? = nil
    @State private var possessionBanner: String? = nil
    /// Retro broadcast plate ("1ST & 10") flashed at the snap.
    @State private var snapPlate: String? = nil
    /// Player-vs-player callouts for the play that just resolved.
    @State private var matchupCallouts: [PlayMatchups.Event] = []
    /// Whether the player's team was the offense on the play those callouts
    /// describe (possession may have flipped since).
    @State private var calloutsOffenseWasPlayer = true

    // Offense call state
    @State private var selectedCategory: String = "Run"
    @State private var selectedCall: OffensivePlayCall? = nil
    @State private var wentForIt = false
    /// AI suggestion cached per situation — the underlying hint rolls dice,
    /// so recomputing it on every body render would make the brain icon jump.
    @State private var cachedSuggestion: OffensivePlayCall? = nil

    // Defense call state
    @State private var defCall: DefensiveCall = .cover3Base

    // Dialogs
    @State private var showSimToEndConfirm = false
    @State private var showExitConfirm = false
    @State private var showFinal = false

    @Environment(\.dismiss) private var dismiss

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            GeometryReader { geo in
                VStack(spacing: 0) {
                    scoreboardBar
                    situationStrip
                    // The field takes over while the play is live — no dead
                    // spinner panel — and gives the space back for the call.
                    fieldSection(height: geo.size.height * (fieldExpanded ? 0.68 : 0.52))
                    miniPlayFeed
                    callPanel
                        .frame(maxHeight: .infinity)
                }
                .animation(.easeInOut(duration: 0.4), value: fieldExpanded)
            }

            bannerOverlay

            if showFinal {
                finalOverlay
            }
        }
        .statusBarHidden()
        .onAppear(perform: startGame)
        .onChange(of: selectedCall) { _, _ in previewFormation() }
        .onChange(of: defCall) { _, _ in
            if !engine.playerIsOnOffense { previewFormation() }
        }
        .confirmationDialog(
            "Sim rest of the game?",
            isPresented: $showSimToEndConfirm,
            titleVisibility: .visible
        ) {
            Button("Sim to Final") { simToEnd() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The engine finishes the game with AI play-calling on both sides.")
        }
        .confirmationDialog(
            "Leave the game?",
            isPresented: $showExitConfirm,
            titleVisibility: .visible
        ) {
            Button("Sim to Final & Leave") { simToEnd() }
            Button("Abandon Game", role: .destructive) { dismiss() }
            Button("Keep Coaching", role: .cancel) {}
        } message: {
            Text("You can sim the remaining plays or abandon (nothing is saved).")
        }
    }

    // MARK: - Scoreboard

    private var scoreboardBar: some View {
        HStack(spacing: 0) {
            teamBlock(team: awayTeam, score: engine.awayScore, hasBall: !engine.homeHasPossession, leading: true)
            Spacer()
            VStack(spacing: 2) {
                Text(quarterLabel)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.textTertiary)
                Text(engine.formattedClock)
                    .font(.system(size: 24, weight: .heavy).monospacedDigit())
                    .foregroundStyle(Color.textPrimary)
            }
            Spacer()
            teamBlock(team: homeTeam, score: engine.homeScore, hasBall: engine.homeHasPossession, leading: false)
        }
        .padding(.leading, 20)
        .padding(.trailing, 56) // keep the right team block clear of the exit button
        .padding(.top, 14)
        .padding(.bottom, 8)
        .background(Color.backgroundSecondary)
        .overlay(alignment: .topTrailing) { exitButton.padding(.top, 10).padding(.trailing, 12) }
    }

    private var quarterLabel: String {
        engine.quarter <= 4 ? "Q\(engine.quarter)" : "OT"
    }

    private func teamBlock(team: Team, score: Int, hasBall: Bool, leading: Bool) -> some View {
        HStack(spacing: 8) {
            if !leading, hasBall { possessionDot }
            VStack(alignment: leading ? .leading : .trailing, spacing: 0) {
                Text(team.abbreviation)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isPlayerTeam(team) ? Color.accentGold : Color.textSecondary)
                Text("\(score)")
                    .font(.system(size: 34, weight: .black).monospacedDigit())
                    .foregroundStyle(Color.textPrimary)
                    .contentTransition(.numericText())
                    .animation(.spring(duration: 0.4), value: score)
            }
            if leading, hasBall { possessionDot }
        }
        .frame(minWidth: 84, alignment: leading ? .leading : .trailing)
    }

    private var possessionDot: some View {
        Image(systemName: "football.fill")
            .font(.system(size: 11))
            .foregroundStyle(Color.accentGold)
    }

    private func isPlayerTeam(_ team: Team) -> Bool {
        (team.id == homeTeam.id) == playerTeamIsHome
    }

    private var exitButton: some View {
        Button {
            if engine.isGameOver { dismiss() } else { showExitConfirm = true }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 30, height: 30)
                .background(Color.backgroundTertiary, in: Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Situation Strip

    private var situationStrip: some View {
        HStack(spacing: 10) {
            chip(downDistanceText, color: .accentGold)
            chip(fieldPositionText, color: .accentBlue)
            chip(possessionText, color: engine.playerIsOnOffense ? .success : .danger)
            Spacer()
            if !engine.isGameOver {
                Button {
                    showSimToEndConfirm = true
                } label: {
                    Label("Sim to End", systemImage: "forward.end.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.backgroundTertiary, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isAnimating)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.backgroundSecondary)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.surfaceBorder), alignment: .bottom)
    }

    private func chip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(color.opacity(0.14), in: Capsule())
    }

    private var downDistanceText: String {
        let ord: String
        switch engine.down {
        case 1: ord = "1st"; case 2: ord = "2nd"; case 3: ord = "3rd"; default: ord = "\(engine.down)th"
        }
        let goal = 100 - engine.yardLine <= engine.distance
        return "\(ord) & \(goal ? "Goal" : "\(engine.distance)")"
    }

    private var fieldPositionText: String {
        let yl = engine.yardLine
        if yl == 50 { return "Midfield" }
        return yl > 50 ? "OPP \(100 - yl)" : "OWN \(yl)"
    }

    private var possessionText: String {
        let abbr = engine.homeHasPossession ? homeTeam.abbreviation : awayTeam.abbreviation
        return "\(abbr) ball"
    }

    // MARK: - Field

    private func fieldSection(height: CGFloat) -> some View {
        SceneKitFieldView(scene: fieldScene)
            .frame(height: height)
            .overlay(alignment: .topLeading) {
                if let text = possessionBanner {
                    Text(text)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.backgroundPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.accentGold, in: Capsule())
                        .padding(10)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .overlay(alignment: .bottomLeading) {
                if !matchupCallouts.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(matchupCallouts) { event in
                            matchupCalloutRow(event)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 50) // clear of the broadcast plate
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .overlay(alignment: .bottom) {
                if let plate = snapPlate {
                    HStack(spacing: 0) {
                        Text(plate.uppercased())
                            .font(.system(size: 17, weight: .black, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 8)
                    }
                    .background(Color.black.opacity(0.88))
                    .overlay(Rectangle().strokeBorder(Color(red: 0.75, green: 0.1, blue: 0.1), lineWidth: 2.5))
                    .padding(.bottom, 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.3), value: possessionBanner)
            .animation(.spring(duration: 0.3), value: matchupCallouts.count)
            .animation(.spring(duration: 0.25), value: snapPlate)
    }

    /// One "who won the rep" line over the field: gold sword for a battle
    /// your side won, red for one it lost, purple book for a scheme bust.
    private func matchupCalloutRow(_ event: PlayMatchups.Event) -> some View {
        let playerWon = event.offenseWon == calloutsOffenseWasPlayer
        let (icon, tint): (String, Color) = {
            switch event.kind {
            case .bust: return ("book.closed.fill", Color(red: 0.72, green: 0.55, blue: 0.95))
            case .star: return ("star.fill", .accentGold)
            default:    return ("figure.american.football", playerWon ? .success : .danger)
            }
        }()
        return HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
            Text(event.text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(Color.backgroundPrimary.opacity(0.82), in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(0.5), lineWidth: 1))
    }

    // MARK: - Mini Play Feed

    private var miniPlayFeed: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(engine.playLog.suffix(2).enumerated()), id: \.offset) { _, play in
                HStack(spacing: 8) {
                    Circle()
                        .fill(feedDotColor(play))
                        .frame(width: 6, height: 6)
                    Text(play.description)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                    Spacer()
                }
            }
            if engine.playLog.isEmpty {
                Text("Kickoff — the game is about to start.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(height: 56, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.backgroundPrimary)
    }

    private func feedDotColor(_ play: PlayResult) -> Color {
        if play.scoringPlay { return .accentGold }
        if play.isTurnover { return .danger }
        if play.isFirstDown { return .success }
        return .textTertiary
    }

    // MARK: - Call Panel

    @ViewBuilder
    private var callPanel: some View {
        VStack(spacing: 0) {
            Divider().background(Color.surfaceBorder)
            if engine.isGameOver {
                Spacer()
            } else if !engine.playerIsOnOffense {
                // Opponent possession: stance stays adjustable while plays
                // roll automatically, so no dead spinner panel.
                defensePanel
            } else if isAnimating {
                animatingPanel
            } else if engine.isFourthDown && !wentForIt {
                fourthDownPanel
            } else {
                offenseCallPanel
            }
        }
        .background(Color.backgroundSecondary)
    }

    private var animatingPanel: some View {
        VStack {
            Spacer()
            HStack(spacing: 10) {
                ProgressView()
                    .tint(Color.accentGold)
                Text(engine.playerIsOnOffense ? "Play is live…" : "\(opponentAbbr) offense on the field…")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var opponentAbbr: String {
        playerTeamIsHome ? awayTeam.abbreviation : homeTeam.abbreviation
    }

    // MARK: Offense panel

    private let categories = ["Run", "Short Pass", "Medium Pass", "Deep Pass", "Special"]

    private var offenseCallPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Playbook header: the scheme decides which plays are installed.
            HStack(spacing: 8) {
                Image(systemName: "book.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.accentGold)
                Text(playbookTitle)
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(Color.textTertiary)
                    .tracking(1.4)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)

            HStack(spacing: 6) {
                ForEach(categories, id: \.self) { cat in
                    categoryTab(cat)
                }
            }
            .padding(.horizontal, 14)

            // Clipboard-style call sheet: every play as a card with its
            // chalkboard art and a one-line description; installed plays first.
            let sectionPlays = OffensivePlayCall.allCases
                .filter { $0.category == selectedCategory && $0 != .kneel && $0 != .spike }
            // Stable order: installed playbook plays first, original order kept.
            let plays = sectionPlays.filter { $0.isInPlaybook(of: engine.playerOffensiveScheme) }
                + sectionPlays.filter { !$0.isInPlaybook(of: engine.playerOffensiveScheme) }
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
                    ForEach(plays, id: \.self) { play in
                        playCard(play)
                    }
                }
                .padding(.horizontal, 14)
            }

            Spacer(minLength: 0)

            // Snap bar
            HStack(spacing: 12) {
                if let suggestion = cachedSuggestion {
                    Button {
                        selectedCall = suggestion
                        selectedCategory = suggestion.category
                    } label: {
                        Label(suggestion.rawValue, systemImage: "brain")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.accentBlue)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.accentBlue.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                if clockManagementAvailable {
                    Button { snap(call: .spike) } label: {
                        Text("Spike")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.backgroundTertiary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    Button { snap(call: .kneel) } label: {
                        Text("Kneel")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.backgroundTertiary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button {
                    if let call = selectedCall { snap(call: call) }
                } label: {
                    Label("SNAP", systemImage: "arrow.up.circle.fill")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(Color.backgroundPrimary)
                        .padding(.horizontal, 30)
                        .padding(.vertical, 12)
                        .background(selectedCall != nil ? Color.accentGold : Color.backgroundTertiary, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(selectedCall == nil)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
    }

    private var playbookTitle: String {
        guard let scheme = engine.playerOffensiveScheme else { return "BASE PLAYBOOK" }
        let name = schemeDisplayName(scheme).uppercased()
        return "\(name) PLAYBOOK · \(engine.playerPlaybookFamiliarity)% LEARNED"
    }

    private func schemeDisplayName(_ scheme: OffensiveScheme) -> String {
        switch scheme {
        case .westCoast:  return "West Coast"
        case .airRaid:    return "Air Raid"
        case .spread:     return "Spread"
        case .powerRun:   return "Power Run"
        case .shanahan:   return "Wide Zone"
        case .proPassing: return "Pro Style"
        case .rpo:        return "RPO"
        case .option:     return "Option"
        }
    }

    private func categoryTab(_ category: String) -> some View {
        let isSelected = selectedCategory == category
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { selectedCategory = category }
        } label: {
            Text(shortCategoryName(category))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isSelected ? Color.backgroundPrimary : Color.textSecondary)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity)
                .background(isSelected ? Color.accentGold : Color.backgroundTertiary, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func shortCategoryName(_ category: String) -> String {
        switch category {
        case "Short Pass": return "Short"
        case "Medium Pass": return "Medium"
        case "Deep Pass": return "Deep"
        default: return category
        }
    }

    /// Clipboard-style play card: chalkboard art on top, name + badges, and a
    /// one-line coach-speak description underneath.
    private func playCard(_ play: OffensivePlayCall) -> some View {
        let isSelected = selectedCall == play
        let isSuggested = cachedSuggestion == play
        let installed = play.isInPlaybook(of: engine.playerOffensiveScheme)
        return Button {
            withAnimation(.spring(duration: 0.15)) { selectedCall = play }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                PlayDiagramView(call: play)
                    .frame(maxWidth: .infinity)
                    .opacity(installed ? 1 : 0.45)
                HStack(spacing: 4) {
                    Text(play.rawValue)
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(isSelected ? Color.accentGold
                                         : (installed ? Color.textPrimary : Color.textTertiary))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    if !installed {
                        Image(systemName: "book.closed")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.textTertiary)
                    }
                    if isSuggested {
                        Image(systemName: "brain")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.accentBlue)
                    }
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.accentGold)
                    }
                }
                Text(play.blurb)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
            }
            .padding(8)
            .background(
                isSelected ? Color.accentGold.opacity(0.14) : Color.backgroundTertiary,
                in: RoundedRectangle(cornerRadius: 11)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(isSelected ? Color.accentGold : Color.surfaceBorder,
                                  lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// Spike/kneel shortcuts are only meaningful late in a half.
    private var clockManagementAvailable: Bool {
        (engine.quarter == 2 || engine.quarter >= 4) && engine.timeRemaining <= 150
    }

    /// Maps the engine's situational PlayType hint to a concrete play call,
    /// keeping the suggestion inside the team's installed playbook.
    private var aiSuggestion: OffensivePlayCall? {
        let raw: OffensivePlayCall?
        switch engine.aiOffensiveCallHint() {
        case .run:
            raw = engine.distance <= 1 ? .qbSneak : (engine.distance <= 5 ? .insideRun : .outsideRun)
        case .pass:
            if engine.distance <= 4 { raw = .slant }
            else if engine.distance <= 8 { raw = .curl }
            else { raw = .dig }
        case .kneel: raw = .kneel
        case .spike: raw = .spike
        default: raw = nil
        }
        guard let pick = raw else { return nil }
        if pick.isInPlaybook(of: engine.playerOffensiveScheme) { return pick }
        // Substitute the closest installed play from the same category.
        return OffensivePlayCall.allCases.first {
            $0.category == pick.category && $0.isInPlaybook(of: engine.playerOffensiveScheme)
        } ?? pick
    }

    // MARK: 4th down panel

    private var fourthDownPanel: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.accentGold)
                Text("4th & \(engine.distance) — your call, coach")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Color.textPrimary)
            }
            .padding(.top, 14)

            HStack(spacing: 10) {
                fourthDownButton(
                    title: "Punt",
                    subtitle: "Flip the field",
                    icon: "arrow.up.forward",
                    prominent: engine.yardLine < 55
                ) {
                    snap(forcedType: .punt)
                }

                if engine.canAttemptFieldGoal {
                    fourthDownButton(
                        title: "Field Goal",
                        subtitle: "\(engine.fieldGoalDistance) yd attempt",
                        icon: "flag.fill",
                        prominent: true
                    ) {
                        snap(forcedType: .fieldGoal)
                    }
                }

                fourthDownButton(
                    title: "Go For It",
                    subtitle: "Keep the drive alive",
                    icon: "flame.fill",
                    prominent: false
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) { wentForIt = true }
                }
            }
            .padding(.horizontal, 14)

            Spacer(minLength: 0)
        }
    }

    private func fourthDownButton(
        title: String,
        subtitle: String,
        icon: String,
        prominent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold))
                Text(title)
                    .font(.system(size: 14, weight: .heavy))
                Text(subtitle)
                    .font(.system(size: 10))
                    .opacity(0.75)
            }
            .foregroundStyle(prominent ? Color.backgroundPrimary : Color.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                prominent ? Color.accentGold : Color.backgroundTertiary,
                in: RoundedRectangle(cornerRadius: 12)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Defense panel

    private var defensePanel: some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: "shield.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.accentBlue)
                Text(defensePanelTitle)
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(Color.textTertiary)
                    .tracking(1.5)
                Spacer()
                Button {
                    skipDrive()
                } label: {
                    Label("Skip Drive", systemImage: "forward.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.backgroundTertiary, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
                    ForEach(DefensiveCall.allCases) { call in
                        defenseCallCard(call)
                    }
                }
                .padding(.horizontal, 14)

                Text("\(opponentAbbr) has the ball — plays run automatically with your call applied.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
            }

            Spacer(minLength: 0)
        }
    }

    private var defensePanelTitle: String {
        guard let scheme = engine.playerDefensiveScheme else { return "DEFENSIVE STANCE" }
        let name: String
        switch scheme {
        case .base34:   name = "3-4 Base"
        case .base43:   name = "4-3 Base"
        case .cover3:   name = "Cover 3"
        case .pressMan: name = "Press Man"
        case .tampa2:   name = "Tampa 2"
        case .multiple: name = "Multiple"
        case .hybrid:   name = "Hybrid"
        }
        return "\(name.uppercased()) DEFENSE · STANCE"
    }

    /// Clipboard-style defensive call card: mini X&O art, name, one-line blurb.
    private func defenseCallCard(_ call: DefensiveCall) -> some View {
        let isSelected = defCall == call
        let installed = call.isInPlaybook(of: engine.playerDefensiveScheme)
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { defCall = call }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                DefenseDiagramView(coverage: call.package.coverage, blitz: call.package.blitz)
                    .frame(maxWidth: .infinity)
                    .opacity(installed ? 1 : 0.45)
                HStack(spacing: 4) {
                    Text(call.rawValue)
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(isSelected ? Color.accentGold
                                         : (installed ? Color.textPrimary : Color.textTertiary))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    if !installed {
                        Image(systemName: "book.closed")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.textTertiary)
                    }
                }
                Text(call.blurb)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
            }
            .padding(8)
            .background(
                isSelected ? Color.accentGold.opacity(0.14) : Color.backgroundTertiary,
                in: RoundedRectangle(cornerRadius: 11)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(isSelected ? Color.accentGold : Color.surfaceBorder,
                                  lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Banner

    private var bannerOverlay: some View {
        VStack {
            Spacer()
            if let banner = resultBanner {
                Text(banner)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(Color.backgroundTertiary.opacity(0.96), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.surfaceBorder, lineWidth: 1))
                    .padding(.bottom, 300)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: resultBanner)
        .allowsHitTesting(false)
    }

    // MARK: - Final Overlay

    private var finalOverlay: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()

            VStack(spacing: 18) {
                Text("FINAL")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(Color.backgroundPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .background(Color.accentGold, in: Capsule())

                HStack(spacing: 28) {
                    finalTeamScore(team: awayTeam, score: engine.awayScore)
                    Text("—")
                        .font(.system(size: 26, weight: .black))
                        .foregroundStyle(Color.textTertiary)
                    finalTeamScore(team: homeTeam, score: engine.homeScore)
                }

                Text(playerWon ? "Victory, coach." : (isTie ? "It ends in a tie." : "They got us today."))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(playerWon ? Color.success : Color.textSecondary)

                Button {
                    onFinish(engine)
                } label: {
                    Text("Continue")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(Color.backgroundPrimary)
                        .padding(.horizontal, 44)
                        .padding(.vertical, 13)
                        .background(Color.accentGold, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(36)
            .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Color.accentGold.opacity(0.4), lineWidth: 1.5)
            )
        }
        .transition(.opacity)
    }

    private func finalTeamScore(team: Team, score: Int) -> some View {
        VStack(spacing: 4) {
            Text(team.abbreviation)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(isPlayerTeam(team) ? Color.accentGold : Color.textSecondary)
            Text("\(score)")
                .font(.system(size: 44, weight: .black).monospacedDigit())
                .foregroundStyle(Color.textPrimary)
        }
    }

    private var playerWon: Bool {
        playerTeamIsHome ? engine.homeScore > engine.awayScore : engine.awayScore > engine.homeScore
    }

    private var isTie: Bool { engine.homeScore == engine.awayScore }

    // MARK: - Game Flow

    private func startGame() {
        guard !gameStarted else { return }
        gameStarted = true

        // NFL convention: home wears team color, road team wears white with
        // team-color pants and helmet — always readable against the grass.
        let colors = MatchTeamColors.matchup(home: homeTeam.abbreviation, away: awayTeam.abbreviation)
        fieldScene.setUniforms(
            home: .home(teamColor: colors.home),
            away: .away(teamColor: colors.away)
        )
        fieldScene.setFieldDressing(
            homeAbbr: homeTeam.abbreviation,
            awayAbbr: awayTeam.abbreviation,
            homeColor: colors.home
        )
        fieldScene.setEndZoneColors(home: colors.home, away: colors.away)

        // Opening formation at the kickoff spot
        let losZ = PlayChoreographer.losZ(yardLine: engine.yardLine, offenseIsHome: engine.homeHasPossession)
        let formation = PlayChoreographer.formation(
            for: .run, losZ: losZ, direction: engine.homeHasPossession ? 1 : -1,
            offenseNumbers: engine.currentOffenseUnit.numbers,
            defenseNumbers: engine.currentDefenseUnit.numbers
        )
        let openingCrouch = PlayChoreographer.stanceCrouchIndices(offenseIsHome: engine.homeHasPossession)
        fieldScene.movePlayersToFormation(home: formation.home, away: formation.away, duration: 0.1,
                                          crouchHome: openingCrouch.home, crouchAway: openingCrouch.away)
        fieldScene.focusCamera(z: losZ, animated: false)

        showPossessionBanner()
        proceed(after: 1.0)
    }

    /// Decides what happens after a play fully resolves.
    private func proceed(after delay: TimeInterval = 0.8) {
        guard !engine.isGameOver else {
            withAnimation(.easeInOut(duration: 0.3)) { showFinal = true }
            return
        }
        if engine.playerIsOnOffense {
            // Line the teams up at the new scrimmage spot while the user
            // considers the call, and pre-select the AI pick.
            syncFieldToSituation()
            cachedSuggestion = aiSuggestion
            selectedCall = cachedSuggestion
            if let suggestion = selectedCall { selectedCategory = suggestion.category }
            wentForIt = false
        } else {
            // Opponent possession: auto-run the next play with the user's stance.
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard !isAnimating, !engine.isGameOver, !engine.playerIsOnOffense else { return }
                runPlay(offCall: nil, forcedType: nil)
            }
        }
    }

    private func snap(call: OffensivePlayCall) {
        runPlay(offCall: call, forcedType: nil)
    }

    private func snap(forcedType: PlayType) {
        runPlay(offCall: nil, forcedType: forcedType)
    }

    /// Steps the engine one play and choreographs the result on the field.
    private func runPlay(offCall: OffensivePlayCall?, forcedType: PlayType?) {
        guard !isAnimating, !engine.isGameOver else { return }

        let losYard = engine.yardLine
        let distanceBefore = engine.distance
        let offenseIsHome = engine.homeHasPossession
        let possessionBefore = engine.homeHasPossession

        // Retro broadcast plate for the snap ("1ST & 10").
        let plateText = downDistanceText
        snapPlate = plateText
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            if snapPlate == plateText { snapPlate = nil }
        }

        // Both sides always play a real call: yours from the call sheet, the
        // AI's from its situational picker — so both formations mean something.
        let defPackage = engine.playerIsOnOffense
            ? engine.aiDefensivePackage()
            : defCall.package
        let play = engine.step(
            offensiveCall: engine.playerIsOnOffense ? offCall : nil,
            forcedPlayType: forcedType,
            defensivePackage: defPackage
        )

        isAnimating = true
        selectedCall = nil

        let matchups = engine.lastMatchups
        let offUnit = possessionBefore ? engine.homeOffenseUnit : engine.awayOffenseUnit
        let defUnit = possessionBefore ? engine.awayDefenseUnit : engine.homeDefenseUnit

        // Pre-snap: shift both teams into the alignment their calls dictate,
        // then run the play from that same look.
        let formation = PlayChoreographer.preSnapStep(
            for: play, losYardLine: losYard, offenseIsHome: offenseIsHome,
            call: offCall, defensivePackage: defPackage,
            offenseNumbers: offUnit.numbers, defenseNumbers: defUnit.numbers
        )
        let presnapCrouch = PlayChoreographer.stanceCrouchIndices(offenseIsHome: offenseIsHome)
        fieldScene.movePlayersToFormation(home: formation.home, away: formation.away, duration: 0.7,
                                          crouchHome: presnapCrouch.home, crouchAway: presnapCrouch.away)
        fieldScene.focusCamera(z: PlayChoreographer.losZ(yardLine: losYard, offenseIsHome: offenseIsHome))

        // Markers stay on THIS play's line/1st-down through the animation.
        let playLosZ = PlayChoreographer.losZ(yardLine: losYard, offenseIsHome: offenseIsHome)
        let playDir: Float = offenseIsHome ? 1 : -1
        let playGoalToGo = 100 - losYard <= distanceBefore
        fieldScene.updateMarkers(
            losZ: playLosZ,
            firstDownZ: playGoalToGo ? nil : playLosZ + playDir * Float(distanceBefore)
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            let steps = PlayChoreographer.steps(for: play, losYardLine: losYard,
                                                offenseIsHome: offenseIsHome, matchups: matchups,
                                                call: offCall, defensivePackage: defPackage)
            fieldScene.runPlay(steps: steps) {
                finishPlay(play, possessionBefore: possessionBefore)
            }
        }
    }

    private func finishPlay(_ play: PlayResult, possessionBefore: Bool) {
        isAnimating = false

        // Scoring plays get the full presentation: camera to the end zone
        // and a confetti burst for touchdowns.
        if play.scoringPlay {
            let endzoneZ: Float = possessionBefore ? 50 : -50
            fieldScene.focusCamera(z: endzoneZ, duration: 1.1)
            if play.pointsScored >= 6 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    fieldScene.celebrate(atZ: endzoneZ)
                }
            }
        }

        showBanner(play.description)
        showMatchupCallouts(possessionBefore: possessionBefore)

        if engine.homeHasPossession != possessionBefore && !engine.isGameOver {
            showPossessionBanner()
        }

        proceed(after: play.scoringPlay ? 1.6 : 0.9)
    }

    /// Runs the rest of the opponent's drive instantly (no animation).
    /// Works mid-animation too — the current play's outcome is already
    /// decided, so cancelling the visuals loses nothing.
    private func skipDrive() {
        guard !engine.isGameOver, !engine.playerIsOnOffense else { return }
        fieldScene.cancelPlay()
        isAnimating = false
        var safety = 0
        while !engine.playerIsOnOffense && !engine.isGameOver && safety < 40 {
            engine.step(defensivePackage: defCall.package)
            safety += 1
        }
        syncFieldToSituation()
        if let last = engine.lastPlay { showBanner(last.description) }
        showPossessionBanner()
        proceed(after: 0.6)
    }

    private func simToEnd() {
        guard !engine.isGameOver else { return }
        fieldScene.cancelPlay()
        isAnimating = false
        engine.simToEnd()
        syncFieldToSituation()
        withAnimation(.easeInOut(duration: 0.3)) { showFinal = true }
    }

    /// Teleports the formation/camera to the engine's current situation,
    /// aligned to whatever calls are currently on the table.
    private func syncFieldToSituation() {
        let losZ = PlayChoreographer.losZ(yardLine: engine.yardLine, offenseIsHome: engine.homeHasPossession)
        let formation = PlayChoreographer.formation(
            for: .run,
            call: engine.playerIsOnOffense ? (selectedCall ?? cachedSuggestion) : nil,
            defensivePackage: engine.playerIsOnOffense ? engine.aiDefensivePackage() : defCall.package,
            losZ: losZ, direction: engine.homeHasPossession ? 1 : -1,
            offenseNumbers: engine.currentOffenseUnit.numbers,
            defenseNumbers: engine.currentDefenseUnit.numbers
        )
        let crouch = PlayChoreographer.stanceCrouchIndices(offenseIsHome: engine.homeHasPossession)
        fieldScene.movePlayersToFormation(home: formation.home, away: formation.away, duration: 0.3,
                                          crouchHome: crouch.home, crouchAway: crouch.away)
        fieldScene.focusCamera(z: losZ)
        updateMarkers()
    }

    /// Positions the broadcast LOS/first-down stripes for the current situation.
    private func updateMarkers() {
        guard !engine.isGameOver else {
            fieldScene.updateMarkers(losZ: nil, firstDownZ: nil)
            return
        }
        let dir: Float = engine.homeHasPossession ? 1 : -1
        let losZ = PlayChoreographer.losZ(yardLine: engine.yardLine, offenseIsHome: engine.homeHasPossession)
        let goalToGo = 100 - engine.yardLine <= engine.distance
        let firstDownZ: Float? = goalToGo ? nil : losZ + dir * Float(engine.distance)
        fieldScene.updateMarkers(losZ: losZ, firstDownZ: firstDownZ)
    }

    /// Live pre-snap preview: browsing the call sheet realigns the offense on
    /// the field (I-form for inside runs, spread for deep shots), and changing
    /// the defensive call re-shows the shell/blitz look.
    private func previewFormation() {
        guard gameStarted, !isAnimating, !engine.isGameOver else { return }
        syncFieldToSituation()
    }

    private func showBanner(_ text: String) {
        resultBanner = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
            if resultBanner == text { resultBanner = nil }
        }
    }

    /// Surfaces the last play's individual battles: callout capsules over the
    /// field and a pulse on each matchup winner so the coach can find him.
    private func showMatchupCallouts(possessionBefore: Bool) {
        guard let matchups = engine.lastMatchups, !matchups.events.isEmpty else {
            matchupCallouts = []
            return
        }
        let events = Array(matchups.events.prefix(2))
        calloutsOffenseWasPlayer = (playerTeamIsHome == possessionBefore)
        matchupCallouts = events

        let oBase = possessionBefore ? 0 : 11
        let dBase = possessionBefore ? 11 : 0
        for event in events {
            let winnerNode = event.offenseWon
                ? event.offRole.map { oBase + $0 }
                : event.defRole.map { dBase + $0 }
            if let winnerNode { fieldScene.pulse(nodeIndex: winnerNode) }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.4) {
            if matchupCallouts.first?.id == events.first?.id { matchupCallouts = [] }
        }
    }

    private func showPossessionBanner() {
        let abbr = engine.homeHasPossession ? homeTeam.abbreviation : awayTeam.abbreviation
        let text = "\(abbr) ball · 1st & 10"
        possessionBanner = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            if possessionBanner == text { possessionBanner = nil }
        }
    }
}
