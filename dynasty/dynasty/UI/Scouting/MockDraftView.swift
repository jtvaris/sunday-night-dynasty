import SwiftUI
import SwiftData

struct MockDraftView: View {
    let career: Career
    let prospects: [CollegeProspect]

    @Environment(\.modelContext) private var modelContext
    @State private var teams: [Team] = []
    @State private var players: [Player] = []
    @State private var teamDraftPicks: [DraftPick] = []
    @State private var selectedRound: Int = 1
    @State private var isLoading: Bool = true

    // MARK: - Performance caches
    @State private var cachedStrategyRecommendation: String = ""
    @State private var cachedTargetAvailability: [TargetAvailabilityInfo] = []
    @State private var cachedTradeHints: [TradeHint] = []
    @State private var cachedPicksForRound: [ScoutingEngine.MockDraftPick] = []
    @State private var cachedTargetCountdown: TargetCountdownInfo? = nil

    private var mockDraft: [ScoutingEngine.MockDraftPick] {
        WeekAdvancer.currentMockDraft
    }

    private var picksForRound: [ScoutingEngine.MockDraftPick] { cachedPicksForRound }

    private var availableRounds: [Int] {
        Array(Set(mockDraft.map { $0.round })).sorted()
    }

    private var userTeam: Team? {
        teams.first { $0.id == career.teamID }
    }

    private var userTeamAbbreviation: String? {
        userTeam?.abbreviation
    }

    /// Prospects the user has scouted (on their big board).
    private var scoutedProspects: [UUID: CollegeProspect] {
        Dictionary(uniqueKeysWithValues: prospects.filter { $0.scoutedOverall != nil }.map { ($0.id, $0) })
    }

    /// User's big board order — scouted prospects sorted by their scoutedOverall descending.
    private var userBoardOrder: [UUID] {
        prospects
            .filter { $0.scoutedOverall != nil }
            .sorted { ($0.scoutedOverall ?? 0) > ($1.scoutedOverall ?? 0) }
            .map { $0.id }
    }

    /// User's pick numbers across all rounds.
    private var userPickNumbers: Set<Int> {
        Set(mockDraft.filter { $0.teamAbbreviation == userTeamAbbreviation }.map { $0.pickNumber })
    }

    /// Strategy recommendation based on roster strength and needs.
    private var strategyRecommendation: String { cachedStrategyRecommendation }

    private func computeStrategyRecommendation() -> String {
        guard let teamID = career.teamID else { return "" }
        let teamPlayers = players.filter { $0.teamID == teamID }
        guard !teamPlayers.isEmpty else { return "" }

        let avgOverall = Double(teamPlayers.map(\.overall).reduce(0, +)) / Double(teamPlayers.count)

        // Find weakest position group
        var positionAverages: [Position: Double] = [:]
        for pos in Position.allCases {
            let posPlayers = teamPlayers.filter { $0.position == pos }
            if !posPlayers.isEmpty {
                positionAverages[pos] = Double(posPlayers.map(\.overall).reduce(0, +)) / Double(posPlayers.count)
            }
        }

        let weakest = positionAverages.min(by: { $0.value < $1.value })

        if avgOverall >= 72 {
            return "Strategy: Take BPA -- your roster is strong across positions"
        } else if let weakest, weakest.value < 58 {
            // Check if quality prospects at that position exist after user's pick
            let userFirstPick = mockDraft.first { $0.teamAbbreviation == userTeamAbbreviation }?.pickNumber ?? 32
            let prospectByID = Dictionary(uniqueKeysWithValues: prospects.map { ($0.id, $0) })
            let laterProspectsAtNeed = cachedPicksForRound.filter { pick in
                pick.pickNumber > userFirstPick &&
                prospectByID[pick.prospectID]?.position == weakest.key
            }
            if laterProspectsAtNeed.isEmpty {
                return "Strategy: Address \(weakest.key.rawValue) need -- no quality \(weakest.key.rawValue) after your pick"
            } else {
                return "Strategy: Address \(weakest.key.rawValue) need -- weak position group"
            }
        } else {
            return "Strategy: Balance BPA with needs -- roster has some gaps"
        }
    }

    /// Recomputes all derived caches. Called from .task and on dependency changes.
    private func refreshCaches() {
        cachedPicksForRound = mockDraft.filter { $0.round == selectedRound }
        cachedStrategyRecommendation = computeStrategyRecommendation()
        cachedTargetAvailability = selectedRound == 1 ? computeTargetAvailability() : []
        cachedTradeHints = selectedRound == 1 ? computeTradeHints() : []
        cachedTargetCountdown = selectedRound == 1 ? computeTargetCountdown() : nil
    }

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(1.5)
                        .tint(Color.accentBlue)
                    Text("Loading Mock Draft...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else {
            VStack(spacing: 0) {
                headerBar
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                // Strategy recommendation
                if !strategyRecommendation.isEmpty && !mockDraft.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "lightbulb.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.accentBlue)
                        Text(strategyRecommendation)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Color.textSecondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }

                // Round picker
                if availableRounds.count > 1 {
                    roundPicker
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                }

                Divider()
                    .overlay(Color.surfaceBorder)

                if mockDraft.isEmpty {
                    emptyState
                } else {
                    List {
                        // User pick projection (prominent)
                        if let userPick = picksForRound.first(where: { $0.teamAbbreviation == userTeamAbbreviation }),
                           let prospect = prospects.first(where: { $0.id == userPick.prospectID }) {
                            Section {
                                userPickProjection(pick: userPick, prospect: prospect)
                            } header: {
                                Text("YOUR PICK PROJECTION")
                                    .font(.caption2.weight(.heavy))
                                    .foregroundStyle(Color.accentGold)
                            }
                            .listRowBackground(Color.accentGold.opacity(0.08))
                        }

                        // Top targets countdown summary (#5)
                        targetCountdownSection

                        // Draft availability for user targets
                        targetAvailabilitySection

                        // Trade hints
                        tradeHintsSection

                        // All picks for the round
                        Section {
                            ForEach(picksForRound, id: \.pickNumber) { pick in
                                let prospect = prospects.first { $0.id == pick.prospectID }
                                let isUserPick = pick.teamAbbreviation == userTeamAbbreviation

                                mockDraftRow(pick: pick, prospect: prospect, isUserPick: isUserPick)
                                    .listRowBackground(
                                        isUserPick
                                            ? Color.accentGold.opacity(0.1)
                                            : Color.backgroundSecondary
                                    )
                                    .contextMenu {
                                        if let prospect {
                                            ProspectGradeContextMenu(prospectID: prospect.id)
                                        }
                                    }
                            }
                        } header: {
                            Text(roundLabel(selectedRound).uppercased())
                                .font(.caption2.weight(.heavy))
                                .foregroundStyle(Color.textSecondary)
                        }

                        Section {
                            HStack {
                                Image(systemName: "info.circle")
                                    .foregroundStyle(Color.textTertiary)
                                    .font(.caption)
                                Text("Mock drafts are projections and may not reflect actual draft results.")
                                    .font(.caption)
                                    .foregroundStyle(Color.textTertiary)
                            }
                        }
                        .listRowBackground(Color.backgroundPrimary)
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.insetGrouped)
                }
            }
            } // end else (not loading)
        }
        .task {
            loadData()
            refreshCaches()
            isLoading = false
        }
        .onChange(of: selectedRound) { _, _ in refreshCaches() }
        .onChange(of: players.count) { _, _ in refreshCaches() }
        .onChange(of: teamDraftPicks.count) { _, _ in refreshCaches() }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("MEDIA MOCK DRAFT")
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(Color.textPrimary)

                Text("Season \(String(career.currentSeason)) \u{2022} Week \(String(career.currentWeek))")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(roundLabel(selectedRound))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                Text("\(picksForRound.count) picks")
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
            }
        }
    }

    // MARK: - Round Picker

    private var roundPicker: some View {
        HStack(spacing: 0) {
            ForEach(availableRounds, id: \.self) { round in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedRound = round
                    }
                } label: {
                    Text(roundLabel(round))
                        .font(.caption.weight(selectedRound == round ? .bold : .medium))
                        .foregroundStyle(selectedRound == round ? Color.textPrimary : Color.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            selectedRound == round
                                ? Color.accentBlue.opacity(0.18)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.surfaceBorder, lineWidth: 1))
    }

    // MARK: - Target Availability Section

    private var targetAvailabilityData: [TargetAvailabilityInfo] { cachedTargetAvailability }

    @ViewBuilder
    private var targetAvailabilitySection: some View {
        if !targetAvailabilityData.isEmpty {
            Section {
                ForEach(targetAvailabilityData, id: \.prospectID) { target in
                    targetAvailabilityRow(target: target)
                }
            } header: {
                Text("TARGET AVAILABILITY")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(Color.textSecondary)
            }
            .listRowBackground(Color.backgroundSecondary)
        }
    }

    // MARK: - Trade Hints Section

    private var tradeHintsData: [TradeHint] { cachedTradeHints }

    @ViewBuilder
    private var tradeHintsSection: some View {
        if !tradeHintsData.isEmpty {
            Section {
                ForEach(tradeHintsData, id: \.prospectID) { hint in
                    tradeHintRow(hint: hint)
                }
            } header: {
                Text("TRADE SCENARIOS")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(Color.textSecondary)
            }
            .listRowBackground(Color.backgroundSecondary)
        }
    }

    // MARK: - User Pick Projection

    private func userPickProjection(pick: ScoutingEngine.MockDraftPick, prospect: CollegeProspect) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Pick #\(pick.pickNumber)")
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(Color.accentGold)

                Spacer()

                Text("YOUR PICK")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(Color.backgroundPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentGold, in: Capsule())
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(prospect.fullName)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Color.textPrimary)

                    HStack(spacing: 6) {
                        Text(prospect.position.rawValue)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.textPrimary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(positionColor(for: prospect), in: RoundedRectangle(cornerRadius: 4))

                        Text(prospect.college)
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                Spacer()

                if let scouted = scoutedProspects[prospect.id] {
                    VStack(alignment: .trailing, spacing: 2) {
                        DualGradeDisplay(
                            prospectID: prospect.id,
                            scoutGradeText: scouted.overallGradeDisplay,
                            scoutGradeColor: PositionGradeCalculator.gradeColorForLetter(scouted.overallGradeDisplay)
                        )
                        HStack(spacing: 3) {
                            Text("Scout Grade")
                                .font(.caption2)
                                .foregroundStyle(Color.textTertiary)
                            InfoTooltipButton(
                                text: "Your scout's read on this prospect. If you've logged a personal grade it appears as \"Yours / Scout\" — a wider gap means more uncertainty. Letter grades follow standard A-F tiers (see legend).",
                                showLetterGradeKey: true,
                                size: 10
                            )
                        }
                    }
                }
            }

            // Rationale
            HStack(spacing: 6) {
                Image(systemName: "text.bubble.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
                Text(pick.pickRationale)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.textSecondary)
            }

            // Team needs
            if !pick.teamNeeds.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checklist")
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                    Text("Needs: \(pick.teamNeeds.map(\.rawValue).joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Row

    private func mockDraftRow(pick: ScoutingEngine.MockDraftPick, prospect: CollegeProspect?, isUserPick: Bool) -> some View {
        HStack(spacing: 12) {
            // Star toggle
            if let prospect {
                ProspectStarButton(prospectID: prospect.id)
                    .frame(width: 36)
            }

            // Pick number
            Text("\(pick.pickNumber)")
                .font(.title3.weight(.heavy).monospacedDigit())
                .foregroundStyle(isUserPick ? Color.accentGold : Color.textSecondary)
                .frame(width: 32, alignment: .trailing)

            // Team abbreviation + needs
            VStack(spacing: 2) {
                Text(pick.teamAbbreviation)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isUserPick ? Color.accentGold : Color.textPrimary)
                    .frame(width: 44, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.backgroundPrimary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(isUserPick ? Color.accentGold : Color.surfaceBorder, lineWidth: isUserPick ? 2 : 1)
                            )
                    )

                if !pick.teamNeeds.isEmpty {
                    Text(pick.teamNeeds.prefix(2).map(\.rawValue).joined(separator: ", "))
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(width: 48)

            // Prospect info
            if let prospect {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(prospect.fullName)
                            .font(.body.weight(.medium))
                            .foregroundStyle(Color.textPrimary)

                        UserGradeBadge(prospectID: prospect.id)

                        if isUserPick {
                            Text("YOUR PICK")
                                .font(.system(size: 8, weight: .heavy))
                                .foregroundStyle(Color.backgroundPrimary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.accentGold, in: Capsule())
                        }
                    }

                    HStack(spacing: 6) {
                        Text(prospect.position.rawValue)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.textPrimary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(positionColor(for: prospect), in: RoundedRectangle(cornerRadius: 3))

                        Text(prospect.college)
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)

                        // Media comment
                        if !pick.mediaComment.isEmpty {
                            Text(pick.mediaComment)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(mediaCommentColor(pick.mediaComment))
                                .italic()
                        }
                    }

                    // Big board comparison
                    if let boardRank = userBoardRank(for: prospect.id) {
                        Text("Your Board: #\(boardRank) | Mock: #\(pick.pickNumber)")
                            .font(.system(size: 9, weight: .medium).monospacedDigit())
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            } else {
                Text("Unknown Prospect")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.textTertiary)
            }

            Spacer()

            // Scouted grade (dual grade display)
            if let prospect, let scouted = scoutedProspects[prospect.id] {
                VStack(alignment: .trailing, spacing: 2) {
                    DualGradeDisplay(
                        prospectID: prospect.id,
                        scoutGradeText: scouted.overallGradeDisplay,
                        scoutGradeColor: PositionGradeCalculator.gradeColorForLetter(scouted.overallGradeDisplay)
                    )
                    Text("Scout Grade")
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                }
            }

            // Expert confidence
            VStack(alignment: .trailing, spacing: 2) {
                let confidence = expertConfidence(for: pick.pickNumber)
                Text("\(confidence)%")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(confidenceColor(for: confidence))
                Text("Confidence")
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
            }
            .frame(width: 72)
        }
        .padding(.vertical, 4)
        .overlay(
            isUserPick
                ? RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentGold, lineWidth: 2)
                    .padding(-4)
                : nil
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(pick: pick, prospect: prospect, isUserPick: isUserPick))
    }

    // MARK: - Target Availability

    private struct TargetAvailabilityInfo {
        let prospectID: UUID
        let name: String
        let position: Position
        let mockPickNumber: Int
        let userPickNumber: Int
        let availabilityPercent: Int
    }

    private func computeTargetAvailability() -> [TargetAvailabilityInfo] {
        guard let userAbbr = userTeamAbbreviation else { return [] }
        let userPicks = mockDraft.filter { $0.teamAbbreviation == userAbbr }.map { $0.pickNumber }.sorted()
        guard let firstUserPick = userPicks.first else { return [] }

        // Find scouted prospects the user might want
        return scoutedProspects.values
            .compactMap { prospect -> TargetAvailabilityInfo? in
                guard let mockPick = prospect.mockDraftPickNumber else { return nil }
                // Only show targets that are projected near or above the user's pick
                guard mockPick >= firstUserPick - 10 && mockPick <= firstUserPick + 10 else { return nil }

                // Availability probability: higher if mock pick is after user's pick
                let diff = mockPick - firstUserPick
                let probability: Int
                if diff > 5 {
                    probability = min(95, 70 + diff * 3)
                } else if diff > 0 {
                    probability = 55 + diff * 5
                } else if diff == 0 {
                    probability = 45
                } else {
                    probability = max(5, 40 + diff * 8)
                }

                return TargetAvailabilityInfo(
                    prospectID: prospect.id,
                    name: prospect.fullName,
                    position: prospect.position,
                    mockPickNumber: mockPick,
                    userPickNumber: firstUserPick,
                    availabilityPercent: probability
                )
            }
            .sorted { $0.availabilityPercent > $1.availabilityPercent }
            .prefix(5)
            .map { $0 }
    }

    private func targetAvailabilityRow(target: TargetAvailabilityInfo) -> some View {
        HStack(spacing: 10) {
            Text(target.position.rawValue)
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.textPrimary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.accentBlue.opacity(0.3), in: RoundedRectangle(cornerRadius: 3))

            Text(target.name)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.textPrimary)

            Spacer()

            Text("\(target.availabilityPercent)% available at #\(target.userPickNumber)")
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(availabilityColor(target.availabilityPercent))
        }
    }

    // MARK: - Trade Hints

    private struct TradeHint {
        let prospectID: UUID
        let name: String
        let position: Position
        let projectedPick: Int
        let userPick: Int
        let estimatedCost: String
        /// Concrete user-pick description (e.g. "Rd1 #14 + Rd2 #46").
        let offerDescription: String
        /// Whether the user has the picks to make this realistic.
        let feasible: Bool
        /// Surplus or deficit in pick value (negative = user falls short).
        let valueDelta: Int
    }

    private func computeTradeHints() -> [TradeHint] {
        guard let userAbbr = userTeamAbbreviation else { return [] }
        let userPicks = mockDraft.filter { $0.teamAbbreviation == userAbbr && $0.round == 1 }.map { $0.pickNumber }.sorted()
        guard let firstUserPick = userPicks.first else { return [] }

        // Real user picks from DraftPick model, sorted by pick number ascending.
        let realPicks = teamDraftPicks
            .filter { !$0.isComplete }
            .sorted { $0.pickNumber < $1.pickNumber }

        // Find user-scouted prospects that are projected above the user's pick
        return scoutedProspects.values
            .compactMap { prospect -> TradeHint? in
                guard let mockPick = prospect.mockDraftPickNumber,
                      mockPick < firstUserPick,
                      mockPick >= 1 else { return nil }

                let gap = firstUserPick - mockPick
                guard gap >= 3 else { return nil } // Only show if meaningful trade up needed

                // Required value: target pick value minus what user gives up at their pick.
                // Approximate Jimmy-Johnson-style: value(target) - value(currentPick) = value of additional picks needed.
                let targetValue = DraftEngine.pickValue(mockPick)
                let currentValue = DraftEngine.pickValue(firstUserPick)
                let needed = max(0, targetValue - currentValue)

                // Greedily pick from user's remaining picks (skip the first round one we are already trading) to cover `needed`.
                let candidates = realPicks.filter { $0.pickNumber != firstUserPick }
                var offerPicks: [DraftPick] = []
                var coverage = 0
                for pick in candidates {
                    if coverage >= needed { break }
                    offerPicks.append(pick)
                    coverage += DraftEngine.pickValue(pick.pickNumber)
                }
                let feasible = coverage >= needed
                let valueDelta = coverage - needed

                let offerDesc: String = {
                    let primary = "Rd\(realPicks.first(where: { $0.pickNumber == firstUserPick })?.round ?? 1) #\(firstUserPick)"
                    if offerPicks.isEmpty {
                        return primary
                    }
                    let extras = offerPicks.map { "Rd\($0.round) #\($0.pickNumber)" }.joined(separator: " + ")
                    return "\(primary) + \(extras)"
                }()

                // Cost description, fallback to round-based summary if no picks loaded.
                let cost: String
                if !realPicks.isEmpty && !offerPicks.isEmpty {
                    cost = offerPicks.map { "Rd\($0.round)" }.joined(separator: " + ")
                } else if gap <= 5 {
                    cost = "~Rd 2"
                } else if gap <= 10 {
                    cost = "~Rd 1 + Rd 3"
                } else if gap <= 15 {
                    cost = "~Rd 1 + Rd 2"
                } else {
                    cost = "~2 Rd 1s"
                }

                return TradeHint(
                    prospectID: prospect.id,
                    name: prospect.fullName,
                    position: prospect.position,
                    projectedPick: mockPick,
                    userPick: firstUserPick,
                    estimatedCost: cost,
                    offerDescription: offerDesc,
                    feasible: feasible,
                    valueDelta: valueDelta
                )
            }
            .sorted { $0.projectedPick < $1.projectedPick }
            .prefix(3)
            .map { $0 }
    }

    private func tradeHintRow(hint: TradeHint) -> some View {
        HStack(spacing: 10) {
            Image(systemName: hint.feasible ? "arrow.up.circle.fill" : "arrow.up.circle")
                .font(.caption)
                .foregroundStyle(hint.feasible ? Color.accentBlue : Color.warning)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("Trade up for \(hint.name)?")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.textPrimary)
                    if !hint.feasible {
                        Text("short")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(Color.backgroundPrimary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.warning, in: Capsule())
                    }
                }
                Text("Projected #\(hint.projectedPick) - need ~\(hint.estimatedCost)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Color.textTertiary)
                if !teamDraftPicks.isEmpty {
                    Text("Send: \(hint.offerDescription)")
                        .font(.system(size: 9, weight: .medium).monospacedDigit())
                        .foregroundStyle(hint.feasible ? Color.success : Color.warning)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }

            Spacer()
        }
    }

    // MARK: - #5: Top Targets Countdown

    /// Snapshot of how many of the user's "top targets" are likely to still be on the board at their pick.
    private struct TargetCountdownInfo {
        let userPickNumber: Int
        let totalTargets: Int
        let likelyAvailable: Int   // probability >= 0.5
        let coinflipAvailable: Int // probability >= 0.25 && < 0.5
        let topAvailableNames: [String]
    }

    /// Determine "targets" — top user-graded prospects (or top-board prospects) above mid-tier.
    private func computeTargetCountdown() -> TargetCountdownInfo? {
        guard let userAbbr = userTeamAbbreviation else { return nil }
        let userPicks = mockDraft.filter { $0.teamAbbreviation == userAbbr }.map { $0.pickNumber }.sorted()
        guard let firstUserPick = userPicks.first else { return nil }

        // Targets = top 10 prospects on the user's big board (sorted by scoutedOverall).
        let targets = prospects
            .filter { $0.scoutedOverall != nil }
            .sorted { ($0.scoutedOverall ?? 0) > ($1.scoutedOverall ?? 0) }
            .prefix(10)

        guard !targets.isEmpty else { return nil }

        var likely = 0
        var coinflip = 0
        var availableNames: [String] = []
        for prospect in targets {
            let prob = availabilityProbability(for: prospect, userPick: firstUserPick)
            if prob >= 0.5 {
                likely += 1
                if availableNames.count < 3 { availableNames.append(prospect.lastName) }
            } else if prob >= 0.25 {
                coinflip += 1
            }
        }

        return TargetCountdownInfo(
            userPickNumber: firstUserPick,
            totalTargets: targets.count,
            likelyAvailable: likely,
            coinflipAvailable: coinflip,
            topAvailableNames: availableNames
        )
    }

    /// Probability a prospect is still available at the user's pick, mirroring target availability logic.
    private func availabilityProbability(for prospect: CollegeProspect, userPick: Int) -> Double {
        guard let mockPick = prospect.mockDraftPickNumber else { return 0.5 }
        let diff = mockPick - userPick
        if diff > 5 { return min(0.95, 0.70 + Double(diff) * 0.03) }
        if diff > 0 { return min(0.85, 0.55 + Double(diff) * 0.05) }
        if diff == 0 { return 0.45 }
        return max(0.05, 0.40 + Double(diff) * 0.08)
    }

    @ViewBuilder
    private var targetCountdownSection: some View {
        if let info = cachedTargetCountdown {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "scope")
                            .font(.caption)
                            .foregroundStyle(Color.accentBlue)
                        Text("\(info.likelyAvailable) of \(info.totalTargets) top targets likely at #\(info.userPickNumber)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                    }
                    if info.coinflipAvailable > 0 {
                        Text("\(info.coinflipAvailable) coinflip — could go either way")
                            .font(.caption2)
                            .foregroundStyle(Color.warning)
                    }
                    if !info.topAvailableNames.isEmpty {
                        Text("Likely available: \(info.topAvailableNames.joined(separator: ", "))")
                            .font(.caption2)
                            .foregroundStyle(Color.textTertiary)
                            .lineLimit(2)
                    }
                }
            } header: {
                Text("TOP TARGETS COUNTDOWN")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(Color.textSecondary)
            }
            .listRowBackground(Color.backgroundSecondary)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 52))
                .foregroundStyle(Color.textTertiary)

            Text("No Mock Draft Available")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.textPrimary)

            Text("The first mock draft will be generated at midseason (Week 9).")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func roundLabel(_ round: Int) -> String {
        switch round {
        case 1: return "First Round"
        case 2: return "Second Round"
        case 3: return "Third Round"
        default: return "Round \(round)"
        }
    }

    private func positionColor(for prospect: CollegeProspect) -> Color {
        switch prospect.position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }

    /// Deterministic "expert confidence" seeded by pick number so it stays stable.
    private func expertConfidence(for pickNumber: Int) -> Int {
        // Higher picks get higher base confidence, with per-pick variance
        let base: Int
        switch pickNumber {
        case 1...5:   base = 78
        case 6...10:  base = 65
        case 11...20: base = 52
        case 21...32: base = 40
        case 33...64: base = 32
        default:      base = 25
        }
        // Use pick number as seed for stable pseudo-random offset
        let offset = ((pickNumber * 7 + 13) % 21) - 10  // range -10...10
        return max(15, min(95, base + offset))
    }

    /// Color for confidence percentage: 85%+ green, 70-84% gold, <70% orange/red.
    private func confidenceColor(for confidence: Int) -> Color {
        if confidence >= 85 { return .success }
        if confidence >= 70 { return .accentBlue }
        return .warning
    }

    private func mediaCommentColor(_ comment: String) -> Color {
        switch comment {
        case "Perfect fit":          return .success
        case "Steal of the draft":   return .success
        case "Best player available": return .accentBlue
        case "Surprise pick":        return .accentGold
        case "Reaches for need":     return .warning
        default:                     return .textTertiary
        }
    }

    private func availabilityColor(_ percent: Int) -> Color {
        if percent >= 70 { return .success }
        if percent >= 40 { return .accentBlue }
        return .danger
    }

    /// Returns the user's big board rank (1-based) for a prospect, or nil if not on board.
    private func userBoardRank(for prospectID: UUID) -> Int? {
        guard let idx = userBoardOrder.firstIndex(of: prospectID) else { return nil }
        return idx + 1
    }

    private func loadData() {
        let teamDesc = FetchDescriptor<Team>()
        teams = (try? modelContext.fetch(teamDesc)) ?? []

        let playerDesc = FetchDescriptor<Player>()
        players = (try? modelContext.fetch(playerDesc)) ?? []

        if let teamID = career.teamID {
            let pickDesc = FetchDescriptor<DraftPick>(predicate: #Predicate { $0.currentTeamID == teamID })
            teamDraftPicks = (try? modelContext.fetch(pickDesc)) ?? []
        }
    }

    private func accessibilityLabel(pick: ScoutingEngine.MockDraftPick, prospect: CollegeProspect?, isUserPick: Bool) -> String {
        let name = prospect?.fullName ?? "Unknown"
        let pos = prospect?.position.rawValue ?? ""
        let team = isUserPick ? "\(pick.teamAbbreviation) (your team)" : pick.teamAbbreviation
        return "Pick \(pick.pickNumber), \(team), \(name) \(pos), confidence \(expertConfidence(for: pick.pickNumber)) percent"
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        MockDraftView(
            career: Career(playerName: "John Doe", role: .gm, capMode: .simple),
            prospects: [
                CollegeProspect(
                    firstName: "Caleb", lastName: "Williams",
                    college: "USC", position: .QB,
                    age: 21, height: 74, weight: 214,
                    truePositionAttributes: .quarterback(QBAttributes(
                        armStrength: 92, accuracyShort: 88, accuracyMid: 90,
                        accuracyDeep: 85, pocketPresence: 87, scrambling: 78
                    )),
                    truePersonality: PlayerPersonality(archetype: .fieryCompetitor, motivation: .winning),
                    scoutedOverall: 89, scoutGrade: "A",
                    draftProjection: 1,
                    mockDraftPickNumber: 1, mockDraftTeam: "CHI"
                ),
            ]
        )
    }
    .modelContainer(for: [Career.self, Team.self, CollegeProspect.self], inMemory: true)
}
