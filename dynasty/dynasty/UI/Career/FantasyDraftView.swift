import SwiftUI

/// R40 — Fantasy Draft screen shown during career creation.
///
/// All 1,696 generated players enter one pool; 32 teams snake-draft new
/// rosters. The user picks by hand through `FantasyDraftEngine.interactiveRounds`
/// (AI picks between the user's turns resolve instantly and stream into the
/// "Latest picks" ticker); the remaining rounds auto-fill with the same
/// need+value AI. Nothing is persisted until the caller receives `onComplete`
/// — cancelling abandons the career cleanly.
struct FantasyDraftView: View {

    let teams: [Team]
    let userTeamID: UUID
    let poolPlayers: [Player]
    /// Called with the final rosters (teamID → drafted players, roster order).
    let onComplete: ([UUID: [Player]]) -> Void
    let onCancel: () -> Void

    // MARK: - Draft State

    @State private var pool: [FantasyDraftEngine.PoolEntry] = []
    @State private var rosters: [UUID: [FantasyDraftEngine.PoolEntry]] = [:]
    @State private var baseOrder: [UUID] = []
    /// 0-based overall pick counter (round = index / 32 + 1).
    @State private var pickIndex: Int = 0
    @State private var recentPicks: [PickRecord] = []
    @State private var positionFilter: Position? = nil
    @State private var isAutoFilling = false
    @State private var isFinished = false
    @State private var showCancelConfirm = false
    @State private var showAutoCompleteConfirm = false

    private struct PickRecord: Identifiable {
        let id = UUID()
        let round: Int
        let overallPick: Int
        let teamAbbreviation: String
        let playerName: String
        let position: Position
        let overall: Int
        let isUserPick: Bool
    }

    // MARK: - Derived

    private var totalPicks: Int { FantasyDraftEngine.rosterSize * teams.count }
    private var currentRound: Int { pickIndex / max(1, teams.count) + 1 }
    private var pickInRound: Int { pickIndex % max(1, teams.count) + 1 }

    private var currentTeamID: UUID? {
        guard pickIndex < totalPicks, !baseOrder.isEmpty else { return nil }
        let order = FantasyDraftEngine.order(forRound: currentRound, baseOrder: baseOrder)
        return order[pickIndex % order.count]
    }

    private var isUserTurn: Bool { currentTeamID == userTeamID }

    private var userTeam: Team? { teams.first { $0.id == userTeamID } }

    private var userRoster: [FantasyDraftEngine.PoolEntry] { rosters[userTeamID] ?? [] }

    private var userRosterCounts: [Position: Int] {
        userRoster.reduce(into: [:]) { $0[$1.position, default: 0] += 1 }
    }

    /// Blueprint deficits for the needs strip, biggest gaps first.
    private var userNeeds: [(position: Position, missing: Int)] {
        FantasyDraftEngine.targetCounts
            .map { (position: $0.key, missing: $0.value - (userRosterCounts[$0.key] ?? 0)) }
            .filter { $0.missing > 0 }
            .sorted { $0.missing == $1.missing ? $0.position.rawValue < $1.position.rawValue : $0.missing > $1.missing }
    }

    private var filteredPool: [FantasyDraftEngine.PoolEntry] {
        guard let filter = positionFilter else { return Array(pool.prefix(60)) }
        return Array(pool.lazy.filter { $0.position == filter }.prefix(60))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()

                if isFinished {
                    summaryContent
                } else {
                    draftContent
                }

                if isAutoFilling {
                    autoFillOverlay
                }
            }
            .navigationTitle("Fantasy Draft")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                if !isFinished {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showCancelConfirm = true }
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
            .confirmationDialog(
                "Abandon the fantasy draft?",
                isPresented: $showCancelConfirm,
                titleVisibility: .visible
            ) {
                Button("Abandon Draft", role: .destructive) { onCancel() }
                Button("Keep Drafting", role: .cancel) {}
            } message: {
                Text("No career will be created. You'll return to team selection.")
            }
            .confirmationDialog(
                "Auto-complete the entire draft?",
                isPresented: $showAutoCompleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Auto-Complete Draft") { runAutoFill(throughRound: FantasyDraftEngine.rosterSize) }
                Button("Keep Drafting", role: .cancel) {}
            } message: {
                Text("The AI fills every remaining pick for all teams, including yours, using need and value.")
            }
        }
        .interactiveDismissDisabled()
        .onAppear(perform: setUpDraft)
    }

    // MARK: - Setup

    private func setUpDraft() {
        guard pool.isEmpty, !poolPlayers.isEmpty else { return }
        pool = poolPlayers
            .map(FantasyDraftEngine.PoolEntry.init(player:))
            .sorted { $0.overall > $1.overall }
        rosters = Dictionary(uniqueKeysWithValues: teams.map { ($0.id, []) })
        baseOrder = teams.map(\.id).shuffled()
        advanceToUserTurn()
    }

    // MARK: - Draft Flow

    /// Resolves AI picks until it's the user's turn again. Once the board
    /// moves past the interactive rounds, hands off to the auto-fill.
    private func advanceToUserTurn() {
        while pickIndex < totalPicks && currentRound <= FantasyDraftEngine.interactiveRounds && !isUserTurn {
            makeAIPick()
        }
        if pickIndex >= totalPicks {
            isFinished = true
        } else if currentRound > FantasyDraftEngine.interactiveRounds {
            runAutoFill(throughRound: FantasyDraftEngine.rosterSize)
        }
    }

    private func makeAIPick() {
        guard let teamID = currentTeamID, let team = teams.first(where: { $0.id == teamID }) else { return }
        let counts = (rosters[teamID] ?? []).reduce(into: [Position: Int]()) { $0[$1.position, default: 0] += 1 }
        guard let index = FantasyDraftEngine.aiPickIndex(
            pool: pool, rosterCounts: counts, round: currentRound
        ) else { return }
        assign(pool[index], to: team, poolIndex: index)
    }

    private func draftForUser(_ entry: FantasyDraftEngine.PoolEntry) {
        guard isUserTurn, let team = userTeam,
              let index = pool.firstIndex(of: entry) else { return }
        assign(entry, to: team, poolIndex: index)
        advanceToUserTurn()
    }

    private func autoPickForUser() {
        guard isUserTurn, let team = userTeam else { return }
        guard let index = FantasyDraftEngine.aiPickIndex(
            pool: pool, rosterCounts: userRosterCounts, round: currentRound
        ) else { return }
        assign(pool[index], to: team, poolIndex: index)
        advanceToUserTurn()
    }

    private func assign(_ entry: FantasyDraftEngine.PoolEntry, to team: Team, poolIndex: Int) {
        rosters[team.id, default: []].append(entry)
        pool.remove(at: poolIndex)
        recentPicks.insert(PickRecord(
            round: currentRound,
            overallPick: pickIndex + 1,
            teamAbbreviation: team.abbreviation,
            playerName: entry.name,
            position: entry.position,
            overall: entry.overall,
            isUserPick: team.id == userTeamID
        ), at: 0)
        if recentPicks.count > 10 { recentPicks.removeLast() }
        pickIndex += 1
    }

    /// Completes every remaining pick with the AI, yielding periodically so
    /// the progress overlay renders. Runs for the post-interactive rounds
    /// (documented streamlining) and for "Auto-Complete Draft".
    private func runAutoFill(throughRound: Int) {
        guard !isAutoFilling else { return }
        isAutoFilling = true
        Task { @MainActor in
            var sinceYield = 0
            while pickIndex < totalPicks && currentRound <= throughRound {
                makeAIPick()
                sinceYield += 1
                if sinceYield >= 64 {
                    sinceYield = 0
                    await Task.yield()
                }
            }
            isAutoFilling = false
            if pickIndex >= totalPicks {
                isFinished = true
            }
        }
    }

    private func finish() {
        var result: [UUID: [Player]] = [:]
        for (teamID, entries) in rosters {
            result[teamID] = entries.map(\.player)
        }
        onComplete(result)
    }

    // MARK: - Draft Content

    private var draftContent: some View {
        VStack(spacing: 0) {
            onTheClockHeader
                .padding(.horizontal, 16)
                .padding(.top, 10)

            needsStrip
                .padding(.horizontal, 16)
                .padding(.top, 8)

            positionFilterBar
                .padding(.top, 8)

            HStack(alignment: .top, spacing: 12) {
                bestAvailableList
                    .frame(maxWidth: .infinity)

                recentPicksPanel
                    .frame(width: 240)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
    }

    private var onTheClockHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("ROUND \(currentRound) OF \(FantasyDraftEngine.rosterSize) \u{2022} PICK \(pickInRound)/\(teams.count)")
                    .font(.system(size: 10, weight: .heavy).monospacedDigit())
                    .tracking(1.2)
                    .foregroundStyle(Color.textTertiary)
                HStack(spacing: 8) {
                    if let team = userTeam {
                        TeamLogoPlaceholder(abbreviation: team.abbreviation, size: 26)
                    }
                    Text(isUserTurn ? "You're on the clock" : "Simulating...")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                    Text("\(userRoster.count)/\(FantasyDraftEngine.rosterSize) drafted")
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color.textSecondary)
                }
            }

            Spacer()

            if !isUserTurn && !isAutoFilling {
                Button {
                    advanceToUserTurn()
                } label: {
                    actionChip(icon: "forward.fill", label: "Sim to My Pick", tint: Color.accentBlue)
                }
                .buttonStyle(.plain)
            }

            Button {
                autoPickForUser()
            } label: {
                actionChip(icon: "wand.and.stars", label: "Auto Pick", tint: Color.accentBlue)
            }
            .buttonStyle(.plain)
            .disabled(!isUserTurn)
            .opacity(isUserTurn ? 1 : 0.4)

            Button {
                showAutoCompleteConfirm = true
            } label: {
                actionChip(icon: "checkmark.seal.fill", label: "Auto-Complete", tint: Color.accentGold)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(isUserTurn ? Color.accentGold.opacity(0.6) : Color.surfaceBorder, lineWidth: 1)
                )
        )
    }

    private func actionChip(icon: String, label: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(label)
                .font(.system(size: 12, weight: .bold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(tint.opacity(0.14))
                .overlay(Capsule().strokeBorder(tint.opacity(0.4), lineWidth: 0.5))
        )
    }

    private var needsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Text("NEEDS")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.2)
                    .foregroundStyle(Color.textTertiary)
                if userNeeds.isEmpty {
                    Text("Roster blueprint filled")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.success)
                }
                ForEach(userNeeds, id: \.position) { need in
                    Button {
                        positionFilter = positionFilter == need.position ? nil : need.position
                    } label: {
                        Text("\(need.position.rawValue)\(need.missing > 1 ? " \u{00D7}\(need.missing)" : "")")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(positionFilter == need.position ? Color.backgroundPrimary : Color.warning)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(positionFilter == need.position ? Color.warning : Color.warning.opacity(0.15))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var positionFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                filterChip(label: "All", isOn: positionFilter == nil) { positionFilter = nil }
                ForEach(Position.allCases, id: \.self) { position in
                    filterChip(label: position.rawValue, isOn: positionFilter == position) {
                        positionFilter = positionFilter == position ? nil : position
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func filterChip(label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isOn ? Color.backgroundPrimary : Color.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isOn ? Color.accentBlue : Color.backgroundSecondary)
                        .overlay(Capsule().strokeBorder(Color.surfaceBorder, lineWidth: isOn ? 0 : 0.5))
                )
        }
        .buttonStyle(.plain)
    }

    private var bestAvailableList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("BEST AVAILABLE")
                .font(.system(size: 10, weight: .heavy))
                .tracking(1.2)
                .foregroundStyle(Color.textTertiary)

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(filteredPool) { entry in
                        poolRow(entry)
                    }
                }
                .padding(.bottom, 12)
            }
        }
    }

    private func poolRow(_ entry: FantasyDraftEngine.PoolEntry) -> some View {
        HStack(spacing: 10) {
            Text(entry.position.rawValue)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 36, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text("Age \(entry.age)")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(Color.textTertiary)
            }

            Spacer(minLength: 4)

            VStack(spacing: 0) {
                Text("\(entry.overall)")
                    .font(.system(size: 16, weight: .black).monospacedDigit())
                    .foregroundStyle(Color.forRating(entry.overall))
                Text("OVR")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Color.textTertiary)
            }
            .frame(width: 36)

            Button {
                draftForUser(entry)
            } label: {
                Text("DRAFT")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(Color.backgroundPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(isUserTurn ? Color.accentGold : Color.surfaceBorder))
            }
            .buttonStyle(.plain)
            .disabled(!isUserTurn)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.backgroundSecondary)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.surfaceBorder, lineWidth: 0.5))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.name), \(entry.position.rawValue), \(entry.overall) overall, age \(entry.age)")
    }

    private var recentPicksPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LATEST PICKS")
                .font(.system(size: 10, weight: .heavy))
                .tracking(1.2)
                .foregroundStyle(Color.textTertiary)

            ScrollView {
                VStack(spacing: 4) {
                    if recentPicks.isEmpty {
                        Text("The board is live — your pick opens the draft.")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    ForEach(recentPicks) { pick in
                        HStack(spacing: 8) {
                            Text("R\(pick.round)")
                                .font(.system(size: 9, weight: .bold).monospacedDigit())
                                .foregroundStyle(Color.textTertiary)
                                .frame(width: 26, alignment: .leading)
                            Text(pick.teamAbbreviation)
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundStyle(pick.isUserPick ? Color.accentGold : Color.textSecondary)
                                .frame(width: 34, alignment: .leading)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(pick.playerName)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color.textPrimary)
                                    .lineLimit(1)
                                Text("\(pick.position.rawValue) \u{2022} \(pick.overall) OVR")
                                    .font(.system(size: 9).monospacedDigit())
                                    .foregroundStyle(Color.textTertiary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(pick.isUserPick ? Color.accentGold.opacity(0.10) : Color.backgroundSecondary)
                        )
                    }
                }
                .padding(.bottom, 12)
            }
        }
    }

    // MARK: - Auto-fill Overlay

    private var autoFillOverlay: some View {
        ZStack {
            Color.backgroundPrimary.opacity(0.85).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                    .tint(Color.accentBlue)
                Text("Completing Draft...")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                Text("Round \(min(currentRound, FantasyDraftEngine.rosterSize)) of \(FantasyDraftEngine.rosterSize)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }

    // MARK: - Summary

    /// Position-group counts of the user's final roster.
    private var summaryGroups: [(label: String, count: Int)] {
        let counts = userRosterCounts
        func total(_ positions: [Position]) -> Int {
            positions.reduce(0) { $0 + (counts[$1] ?? 0) }
        }
        return [
            ("QB", total([.QB])),
            ("RB/FB", total([.RB, .FB])),
            ("WR", total([.WR])),
            ("TE", total([.TE])),
            ("OL", total([.LT, .LG, .C, .RG, .RT])),
            ("DL", total([.DE, .DT])),
            ("LB", total([.OLB, .MLB])),
            ("DB", total([.CB, .FS, .SS])),
            ("K/P", total([.K, .P]))
        ]
    }

    private var summaryContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let team = userTeam {
                    VStack(spacing: 10) {
                        TeamLogoPlaceholder(abbreviation: team.abbreviation, size: 64)
                        Text("Draft Complete")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(Color.textPrimary)
                        Text("Your \(team.fullName) roster is set — \(userRoster.count) players drafted.")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .padding(.top, 32)
                }

                HStack(spacing: 0) {
                    ForEach(summaryGroups, id: \.label) { group in
                        VStack(spacing: 4) {
                            Text("\(group.count)")
                                .font(.system(size: 20, weight: .bold).monospacedDigit())
                                .foregroundStyle(Color.textPrimary)
                            Text(group.label)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 14)
                .cardBackground()

                VStack(alignment: .leading, spacing: 6) {
                    Text("TOP OF YOUR CLASS")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1.2)
                        .foregroundStyle(Color.textTertiary)
                    ForEach(userRoster.sorted { $0.overall > $1.overall }.prefix(8)) { entry in
                        HStack(spacing: 10) {
                            Text(entry.position.rawValue)
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundStyle(Color.textSecondary)
                                .frame(width: 36, alignment: .leading)
                            Text(entry.name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                            Text("\(entry.overall) OVR")
                                .font(.system(size: 13, weight: .bold).monospacedDigit())
                                .foregroundStyle(Color.forRating(entry.overall))
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(16)
                .cardBackground()

                Button {
                    finish()
                } label: {
                    Text("START YOUR CAREER")
                        .font(.system(size: 16, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(Color.backgroundPrimary)
                        .frame(maxWidth: 500)
                        .padding(.vertical, 16)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.accentGold))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 32)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
    }
}
