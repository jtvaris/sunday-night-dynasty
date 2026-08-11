import SwiftUI
import SwiftData

/// What the Mock Draft screen can close, handed down by the hub.
///
/// **The two mock stages used to complete invisibly** — opening this tab stamped
/// the read and moved the pipeline, so two of the spring's nine stages were
/// satisfied by an act the user never performed and never saw acknowledged (P1,
/// UI_REDESIGN_VISION §4 wave 0). Reading a mock is a real act; it now takes a
/// button.
struct MockDraftFiling {
    /// "Mock 1.0" / "Final Mock".
    let stageName: String
    /// What filing does, for the action bar's explainer. Markdown emphasis.
    let explainer: String
    let file: () -> Void
}

struct MockDraftView: View {
    let career: Career
    let prospects: [CollegeProspect]
    /// Hands one man to the interview room (#137), exactly as the Big Board's
    /// rows do. Supplied by the hub only when the room is honestly open, so this
    /// screen never has to know the interview economy; `nil` and the menu item
    /// is not drawn at all.
    var onInterview: ((CollegeProspect) -> Void)? = nil
    /// The stage this screen can close, or `nil` when there is nothing to file —
    /// the mock is then the permanent reference screen it has always also been.
    var filing: MockDraftFiling? = nil

    @Environment(\.modelContext) private var modelContext
    @State private var teams: [Team] = []
    @State private var players: [Player] = []
    @State private var teamDraftPicks: [DraftPick] = []
    @State private var selectedRound: Int = 1
    @State private var isLoading: Bool = true
    /// Currently selected snapshot tag. "Latest" reads `currentMockDraft`,
    /// any other key reads `mockDraftHistory[selectedSnapshot]`.
    @State private var selectedSnapshot: String = "Latest"

    // MARK: - Performance caches
    @State private var cachedStrategyRecommendation: String = ""
    @State private var cachedTargetAvailability: [TargetAvailabilityInfo] = []
    @State private var cachedTradeHints: [TradeHint] = []
    @State private var cachedPicksForRound: [ScoutingEngine.MockDraftPick] = []
    @State private var cachedTargetCountdown: TargetCountdownInfo? = nil
    @State private var cachedTradeDownHints: [TradeDownHint] = []
    /// Mock 1.0 against the Final Mock — the three loudest climbs and slides.
    @State private var cachedMockComparison: [MockMove] = []
    /// `[ProspectID: user board slot]`. Cached because it was an O(n) `firstIndex`
    /// per rendered row over a ~285-man class.
    @State private var cachedUserBoardRanks: [UUID: Int] = [:]

    /// Ordered snapshot tags shown in the picker. `"Post-Pro-Day"` replaced
    /// `"Post-FA"` in #103 §5.7 when the third mock moved from the end of free
    /// agency to the far side of the pro-day circuit.
    private let snapshotTags: [String] = ["Latest", "Mid-Season", "Combine", "Post-Pro-Day", "Pre-Draft"]

    /// The two PUBLIC moments — the pair the comparison strip diffs.
    private static let mockOneTag = "Post-Pro-Day"
    private static let mockTwoTag = "Pre-Draft"

    /// What the picker prints for a tag. The two public mocks carry the names
    /// the feed, the inbox and the prep stages all use for them; the two quiet
    /// ones keep their calendar tags.
    private func snapshotLabel(_ tag: String) -> String {
        switch tag {
        case Self.mockOneTag: return "Mock 1.0"
        case Self.mockTwoTag: return "Final Mock"
        default:              return tag
        }
    }

    private var mockDraft: [ScoutingEngine.MockDraftPick] {
        if selectedSnapshot == "Latest" {
            return WeekAdvancer.currentMockDraft
        }
        return WeekAdvancer.mockDraftHistory[selectedSnapshot] ?? []
    }

    /// Whether a snapshot tag has any data backing it.
    private func snapshotHasData(_ tag: String) -> Bool {
        if tag == "Latest" {
            return !WeekAdvancer.currentMockDraft.isEmpty
        }
        return !(WeekAdvancer.mockDraftHistory[tag]?.isEmpty ?? true)
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

    /// The user's board — the ONE persisted order (`prospectCustomBoard`) the
    /// Big Board writes and every "Your Board: #N" must print from.
    ///
    /// This screen used to sort by `scoutedOverall` descending, which made it a
    /// THIRD board: the tier movers, the drags and the auto-rank the user spent
    /// the spring on were invisible here, and "Your Board: #12" named a
    /// different man than the Big Board's #12.
    private var userBoardRanks: [UUID: Int] { cachedUserBoardRanks }

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
        // `slotMap`, not `rankMap`: the war room ranks the DECLARED class, so
        // ranking everybody here shifted every slot below any man who withdrew
        // in January and the two screens printed different "MY #N" for him.
        cachedUserBoardRanks = UserDraftBoard.slotMap(among: prospects)
        cachedStrategyRecommendation = computeStrategyRecommendation()
        cachedTargetAvailability = selectedRound == 1 ? computeTargetAvailability() : []
        cachedTradeHints = selectedRound == 1 ? computeTradeHints() : []
        cachedTradeDownHints = selectedRound == 1 ? computeTradeDownHints() : []
        cachedTargetCountdown = selectedRound == 1 ? computeTargetCountdown() : nil
        // Cycle-level, not round-level: the strip diffs the two public mocks and
        // reads the same on every round tab.
        cachedMockComparison = computeMockComparison()
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

                // Snapshot picker (history)
                snapshotPicker
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)

                // Consensus media mock (only on Latest + when there's a user pick)
                if selectedSnapshot == "Latest", !consensusMock.isEmpty {
                    consensusMockSection
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                }

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

                        // Mock 1.0 vs Final Mock — the spring in six rows.
                        mockComparisonSection

                        // Top targets countdown summary (#5)
                        targetCountdownSection

                        // Draft availability for user targets
                        targetAvailabilitySection

                        // Trade hints — up, then down.
                        tradeHintsSection
                        tradeDownHintsSection

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
                                            ProspectGradeContextMenu(
                                                prospect: prospect,
                                                onChange: { try? modelContext.save() },
                                                onInterview: ProspectGradeContextMenu.interviewAction(
                                                    for: prospect,
                                                    jump: onInterview
                                                )
                                            )
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

                // The stage's commit, where a commit belongs (§2.5). Drawn only
                // while there is something to file: once the read is recorded
                // the band's `done` slat is the ONE place that says so.
                if let filing {
                    DSActionBar(
                        explainer: DSActionBar.Explainer(
                            title: "File \(filing.stageName)",
                            message: filing.explainer
                        ),
                        primary: DSActionBar.Action(
                            title: "File this mock",
                            accessibilityLabel: "File \(filing.stageName). "
                                + DSActionBar.Explainer.spoken(filing.explainer),
                            handler: filing.file
                        )
                    )
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
        .onChange(of: selectedSnapshot) { _, _ in refreshCaches() }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("MEDIA MOCK DRAFT")
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(Color.textPrimary)

                Text("\(String(DraftYearLabel.classYear(duringSeason: career.currentSeason))) Draft Class \u{2022} Week \(String(career.currentWeek))")
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

    // MARK: - Snapshot Picker

    private var snapshotPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(snapshotTags, id: \.self) { tag in
                    let hasData = snapshotHasData(tag)
                    let isSelected = selectedSnapshot == tag
                    Button {
                        guard hasData else { return }
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedSnapshot = tag
                        }
                    } label: {
                        Text(snapshotLabel(tag))
                            .font(.caption2.weight(isSelected ? .heavy : .semibold))
                            .foregroundStyle(snapshotLabelColor(isSelected: isSelected, hasData: hasData))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                snapshotBackground(isSelected: isSelected, hasData: hasData),
                                in: Capsule()
                            )
                            .overlay(
                                Capsule().strokeBorder(
                                    isSelected ? Color.accentBlue : Color.surfaceBorder,
                                    lineWidth: isSelected ? 1.5 : 1
                                )
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!hasData)
                    .accessibilityLabel("\(snapshotLabel(tag)) mock draft snapshot\(hasData ? "" : ", unavailable")")
                }
            }
        }
    }

    private func snapshotLabelColor(isSelected: Bool, hasData: Bool) -> Color {
        if !hasData { return Color.textTertiary.opacity(0.5) }
        return isSelected ? Color.accentBlue : Color.textSecondary
    }

    private func snapshotBackground(isSelected: Bool, hasData: Bool) -> Color {
        if !hasData { return Color.backgroundSecondary.opacity(0.4) }
        return isSelected ? Color.accentBlue.opacity(0.18) : Color.backgroundSecondary
    }

    // MARK: - Consensus Mock (Media)

    private struct ConsensusEntry: Identifiable {
        let id = UUID()
        let brand: String
        let symbol: String
        let prospectName: String
        let confidence: Int
    }

    /// Three "media outlets" with deterministically nudged predictions for
    /// the user's first projected pick.
    private var consensusMock: [ConsensusEntry] {
        guard let userAbbr = userTeamAbbreviation,
              let userPick = WeekAdvancer.currentMockDraft.first(where: { $0.teamAbbreviation == userAbbr }),
              let actualProspect = prospects.first(where: { $0.id == userPick.prospectID })
        else { return [] }

        // National Sports Network: matches the engine's prediction (most accurate, ~88% confidence).
        let nsn = ConsensusEntry(
            brand: "National Sports Network",
            symbol: "tv",
            prospectName: actualProspect.fullName,
            confidence: 88
        )

        // League Network: nudge ~2 picks (medium accuracy).
        let leagueNetProspect = nudgedPredictionProspect(
            forPickNumber: userPick.pickNumber,
            seedSalt: 11,
            maxNudge: 4
        ) ?? actualProspect
        let leagueNet = ConsensusEntry(
            brand: "League Network",
            symbol: "antenna.radiowaves.left.and.right",
            prospectName: leagueNetProspect.fullName,
            confidence: 72
        )

        // The Gridiron Weekly: bias-heavy, larger variance.
        let weeklyProspect = nudgedPredictionProspect(
            forPickNumber: userPick.pickNumber,
            seedSalt: 29,
            maxNudge: 12
        ) ?? actualProspect
        let weekly = ConsensusEntry(
            brand: "The Gridiron Weekly",
            symbol: "newspaper",
            prospectName: weeklyProspect.fullName,
            confidence: 60
        )

        return [nsn, leagueNet, weekly]
    }

    /// Returns the prospect projected at `pickNumber + offset` in the current
    /// mock draft, where offset is a deterministic pseudo-random nudge driven
    /// by `seedSalt` and bounded to ±`maxNudge`.
    private func nudgedPredictionProspect(forPickNumber pickNumber: Int, seedSalt: Int, maxNudge: Int) -> CollegeProspect? {
        let raw = (pickNumber * 7 + seedSalt * 13 + 17) % (maxNudge * 2 + 1)
        let offset = raw - maxNudge
        let target = max(1, pickNumber + offset)
        let mock = WeekAdvancer.currentMockDraft
        if let pick = mock.first(where: { $0.pickNumber == target }),
           let prospect = prospects.first(where: { $0.id == pick.prospectID }) {
            return prospect
        }
        // Fallback to nearest existing pick.
        if let pick = mock.min(by: { abs($0.pickNumber - target) < abs($1.pickNumber - target) }),
           let prospect = prospects.first(where: { $0.id == pick.prospectID }) {
            return prospect
        }
        return nil
    }

    private var consensusMockSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "person.3.sequence.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.accentBlue)
                Text("CONSENSUS MOCK \u{2014} YOUR PICK")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(Color.textSecondary)
            }

            HStack(spacing: 8) {
                ForEach(consensusMock) { entry in
                    consensusCard(entry: entry)
                }
            }
        }
        .padding(10)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.surfaceBorder, lineWidth: 1))
    }

    private func consensusCard(entry: ConsensusEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: entry.symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.accentBlue)
                Text(entry.brand)
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Color.textPrimary)
            }
            Text(entry.prospectName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(spacing: 3) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: DSType.Size.micro))
                    .foregroundStyle(confidenceColor(for: entry.confidence))
                Text("\(entry.confidence)% confidence")
                    .font(.system(size: 9, weight: .medium).monospacedDigit())
                    .foregroundStyle(confidenceColor(for: entry.confidence))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.backgroundPrimary, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.surfaceBorder, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.brand) projects \(entry.prospectName), \(entry.confidence) percent confidence")
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
                            .background(positionColor(for: prospect), in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))

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
            // The ONE mark, same control as the board.
            if let prospect {
                ProspectMarkButton(
                    prospect: prospect,
                    onChange: { try? modelContext.save() }
                )
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
                        .font(.system(size: DSType.Size.micro, weight: .medium))
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

                        ProspectMarkChip(mark: prospect.userMark)

                        UserGradeBadge(prospectID: prospect.id)

                        if isUserPick {
                            Text("YOUR PICK")
                                .font(.system(size: DSType.Size.micro, weight: .heavy))
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

                        // College production tier
                        ProductionTierChip(tier: prospect.collegeProductionTier, width: nil)

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
        let mark: ProspectMarkTier
        let boardRank: Int?
        let userPickNumber: Int
        let read: DraftAvailability.Read
    }

    /// Availability for the men on the USER's board, through the one shared
    /// model (`DraftAvailability`).
    ///
    /// It used to walk every scouted prospect and interpolate off
    /// `mockDraftPickNumber` alone — a second opinion that disagreed with the
    /// Big Board's round-bucket version on every prospect the media had named a
    /// slot for, and that had nothing at all to say about a man the media only
    /// put in a band.
    private func computeTargetAvailability() -> [TargetAvailabilityInfo] {
        guard let userAbbr = userTeamAbbreviation else { return [] }
        let userPicks = mockDraft.filter { $0.teamAbbreviation == userAbbr }.map { $0.pickNumber }.sorted()
        guard let firstUserPick = userPicks.first else { return [] }

        return UserDraftBoard.targets(among: prospects, limit: 12)
            .compactMap { prospect -> TargetAvailabilityInfo? in
                guard let read = DraftAvailability.read(for: prospect, atPick: firstUserPick) else { return nil }
                // A man the room has going 80 slots before your pick is not a
                // decision — he is a fantasy. Keep the window around your slot.
                guard abs(read.expectedPick - firstUserPick) <= max(16, read.windowWidth) else { return nil }
                return TargetAvailabilityInfo(
                    prospectID: prospect.id,
                    name: prospect.fullName,
                    position: prospect.position,
                    mark: prospect.userMark,
                    boardRank: userBoardRanks[prospect.id],
                    userPickNumber: firstUserPick,
                    read: read
                )
            }
            .sorted { $0.read.probability > $1.read.probability }
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

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(target.name)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.textPrimary)
                    if target.mark != .none {
                        Text(target.mark.shortLabel)
                            .font(.system(size: DSType.Size.micro, weight: .heavy))
                            .foregroundStyle(target.mark.color)
                    }
                }
                if let rank = target.boardRank {
                    Text("Your Board: #\(rank)")
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(Color.textTertiary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text("\(target.read.percent)% available at #\(target.userPickNumber)")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(target.read.tier.color)
                // Says WHY the number is soft: a band read is the media
                // shrugging at a whole round, not a slot opinion.
                Text(target.read.isBandEstimate
                     ? "Round-band estimate"
                     : "Mocked #\(target.read.expectedPick)")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(target.name), \(target.read.percent) percent available at pick \(target.userPickNumber)")
    }

    // MARK: - Trade Hints

    /// A "call about moving up" idea, priced the way the draft room will price
    /// it (Wave 4). Before this the hints ran on `DraftEngine.pickValue`, a
    /// LINEAR curve that diverges 10x from the Jimmy Johnson chart by pick 160
    /// — the pre-draft screen quoted costs the war room would have laughed at
    /// (plan finding S6). Now: same chart, same package decay, same GM ask.
    private struct TradeHint {
        let prospectID: UUID
        let name: String
        let position: Position
        let projectedPick: Int
        let userPick: Int
        /// Abbreviation of the club that holds the target slot.
        let sellerAbbreviation: String
        /// What that GM asks, in Jimmy Johnson points.
        let askPoints: Int
        /// What the assembled package is worth on the same chart.
        let packagePoints: Int
        /// Concrete package description (e.g. "Rd1 #14 + 2028 Rd1").
        let offerDescription: String
        /// Whether the user has the capital to make this realistic.
        let feasible: Bool
        /// Surplus or deficit in chart points (negative = user falls short).
        let valueDelta: Int
    }

    private func computeTradeHints() -> [TradeHint] {
        guard let userAbbr = userTeamAbbreviation else { return [] }
        let season = career.currentSeason
        let userPicks = mockDraft.filter { $0.teamAbbreviation == userAbbr && $0.round == 1 }.map { $0.pickNumber }.sorted()
        guard let firstUserPick = userPicks.first else { return [] }

        // Every pick the user still owns, this year AND the future years Wave 1
        // minted — the future firsts are what make a real jump reachable.
        let realPicks = teamDraftPicks.filter { !$0.isComplete }
        let anchor = realPicks.first { $0.seasonYear == season && $0.pickNumber == firstUserPick }
        let extras = realPicks
            .filter { $0.id != anchor?.id }
            .sorted {
                TradeValueEngine.pickTradeValue(pick: $0, currentSeason: season) >
                TradeValueEngine.pickTradeValue(pick: $1, currentSeason: season)
            }

        // Keyed to the user's own board, like the trade-DOWN hints below: a
        // "trade up for him?" card about a man he never marked is a suggestion
        // from nobody. Walking every scouted prospect also made the list a
        // second board (see `userBoardRanks`).
        return UserDraftBoard.targets(among: prospects, limit: 12)
            .compactMap { prospect -> TradeHint? in
                guard let mockPick = prospect.mockDraftPickNumber,
                      mockPick < firstUserPick,
                      mockPick >= 1 else { return nil }

                let gap = firstUserPick - mockPick
                guard gap >= 3 else { return nil } // Only show if meaningful trade up needed

                // The slot's owner sets the price, not an average.
                let sellerAbbr = mockDraft.first { $0.pickNumber == mockPick }?.teamAbbreviation
                let sellerTeam = teams.first { $0.abbreviation == sellerAbbr }
                let ask = DraftDayTradeEngine.publicAskPrice(
                    targetPickNumber: mockPick,
                    sellerTeamID: sellerTeam?.id,
                    season: season,
                    week: career.currentWeek
                )

                // Greedy-descending fill, same shape as the war room's builder.
                var package: [DraftPick] = anchor.map { [$0] } ?? []
                var covered = DraftDayTradeEngine.publicPackageValue(package, currentSeason: season)
                for pick in extras {
                    if covered >= ask { break }
                    if package.count >= DraftDayTradeEngine.bridgePackageCap { break }
                    package.append(pick)
                    covered = DraftDayTradeEngine.publicPackageValue(package, currentSeason: season)
                }

                let offerDesc: String = {
                    guard !package.isEmpty else { return "Rd1 #\(firstUserPick)" }
                    return package
                        .map { DraftDayTradeEngine.pickLabel($0, currentSeason: season) }
                        .joined(separator: " + ")
                }()

                return TradeHint(
                    prospectID: prospect.id,
                    name: prospect.fullName,
                    position: prospect.position,
                    projectedPick: mockPick,
                    userPick: firstUserPick,
                    sellerAbbreviation: sellerAbbr ?? "???",
                    askPoints: ask,
                    packagePoints: covered,
                    offerDescription: offerDesc,
                    feasible: covered >= ask,
                    valueDelta: covered - ask
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
                            .font(.system(size: DSType.Size.micro, weight: .heavy))
                            .foregroundStyle(Color.backgroundPrimary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.warning, in: Capsule())
                    }
                }
                Text("Projected #\(hint.projectedPick) · \(hint.sellerAbbreviation) ask \(hint.askPoints) pts")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Color.textTertiary)
                if !teamDraftPicks.isEmpty {
                    Text("Send: \(hint.offerDescription) (\(hint.packagePoints) pts)")
                        .font(.system(size: 9, weight: .medium).monospacedDigit())
                        .foregroundStyle(hint.feasible ? Color.success : Color.warning)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                // The pre-draft screen cannot make the call; the draft room can.
                // Same chart, same GM, same ask — so this line is a plan, not a
                // guess that gets laughed at on the night.
                Text(hint.feasible
                     ? "Callable on draft night from the Big Board or the pick sheet."
                     : "Short \(-hint.valueDelta) pts — add future capital before the draft.")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            Spacer()
        }
    }

    // MARK: - Trade DOWN hints

    /// The other half of the phone.
    ///
    /// Every trade idea on this screen was a move UP: "pay this club to jump
    /// ahead of the room". The move the draft actually rewards more often is
    /// the slide — and it was unplannable, because nothing said who behind you
    /// wants up, what the chart says you would collect, or (the only question
    /// that decides it) whether the men you MARKED are still there when you
    /// pick again.
    private struct TradeDownHint {
        let buyerAbbreviation: String
        /// The slot you would slide back to.
        let buyerPickNumber: Int
        let userPickNumber: Int
        /// Why that club wants up: a top-of-the-board position it needs.
        let buyerNeed: Position
        /// Jimmy Johnson gap between the two slots — what they have to make up,
        /// i.e. what you collect on top of the swap.
        let chartGain: Int
        /// Your marked targets with a real chance of surviving to their slot.
        let survivingTargets: [String]
        let targetCount: Int

        var id: Int { buyerPickNumber }
    }

    private func computeTradeDownHints() -> [TradeDownHint] {
        guard let userAbbr = userTeamAbbreviation else { return [] }
        let userPicks = mockDraft.filter { $0.teamAbbreviation == userAbbr && $0.round == 1 }.map { $0.pickNumber }.sorted()
        guard let firstUserPick = userPicks.first else { return [] }

        // The positions at the top of the board are what makes anybody want to
        // move up at all — nobody trades a third-rounder to jump for a man the
        // room has 90th.
        let topBoardPositions = DraftIntel
            .consensusTop(prospects.filter(\.isDeclaringForDraft), count: 14)
            .map(\.position)
        let targets = UserDraftBoard.targets(among: prospects, limit: 8)
        let userPoints = PickValueChart.points(forPick: firstUserPick)

        var seenTeams = Set<String>()
        var hints: [TradeDownHint] = []
        for pick in mockDraft.sorted(by: { $0.pickNumber < $1.pickNumber }) {
            guard hints.count < 3 else { break }
            guard pick.pickNumber > firstUserPick,
                  pick.pickNumber <= firstUserPick + 20,
                  pick.teamAbbreviation != userAbbr,
                  seenTeams.insert(pick.teamAbbreviation).inserted else { continue }

            guard let team = teams.first(where: { $0.abbreviation == pick.teamAbbreviation }) else { continue }
            let roster = players.filter { $0.teamID == team.id }
            let needs = DraftEngine.topTeamNeeds(roster: roster, limit: 3)
            guard let match = topBoardPositions.first(where: { needs.contains($0) }) else { continue }

            // Same chart the war room prices a real move on.
            let gain = userPoints - PickValueChart.points(forPick: pick.pickNumber)
            guard gain > 0 else { continue }

            let survivors = targets.filter {
                DraftAvailability.probability(for: $0, atPick: pick.pickNumber) >= 0.35
            }

            hints.append(TradeDownHint(
                buyerAbbreviation: pick.teamAbbreviation,
                buyerPickNumber: pick.pickNumber,
                userPickNumber: firstUserPick,
                buyerNeed: match,
                chartGain: gain,
                survivingTargets: survivors.prefix(3).map(\.lastName),
                targetCount: survivors.count
            ))
        }
        return hints
    }

    private var tradeDownHintsData: [TradeDownHint] { cachedTradeDownHints }

    @ViewBuilder
    private var tradeDownHintsSection: some View {
        if !tradeDownHintsData.isEmpty {
            Section {
                ForEach(tradeDownHintsData, id: \.id) { hint in
                    tradeDownHintRow(hint: hint)
                }
            } header: {
                Text("TRADE DOWN SCENARIOS")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(Color.textSecondary)
            }
            .listRowBackground(Color.backgroundSecondary)
        }
    }

    private func tradeDownHintRow(hint: TradeDownHint) -> some View {
        HStack(spacing: 10) {
            Image(systemName: hint.targetCount > 0 ? "arrow.down.circle.fill" : "arrow.down.circle")
                .font(.caption)
                .foregroundStyle(hint.targetCount > 0 ? Color.success : Color.textTertiary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Slide to #\(hint.buyerPickNumber) with \(hint.buyerAbbreviation)?")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.textPrimary)
                Text("\(hint.buyerAbbreviation) needs \(hint.buyerNeed.rawValue) and the board is thin there \u{2014} they must make up \(hint.chartGain) pts from #\(hint.userPickNumber).")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(2)
                // The decision, not the arithmetic: a slide is only free when
                // the men you marked survive it.
                if hint.targetCount > 0 {
                    Text("\(hint.targetCount) of your targets still there at #\(hint.buyerPickNumber): \(hint.survivingTargets.joined(separator: ", "))")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.success)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                } else {
                    Text("None of your marked targets survive to #\(hint.buyerPickNumber) \u{2014} sliding costs you the board.")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.warning)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }

            Spacer()
        }
        .accessibilityElement(children: .combine)
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

    /// Targets = the men the USER marked, in his own board order (see
    /// `UserDraftBoard.targets`). Not "whatever my scouts rated highest" — a
    /// countdown of ten men the user never picked is a countdown of nobody.
    private func computeTargetCountdown() -> TargetCountdownInfo? {
        guard let userAbbr = userTeamAbbreviation else { return nil }
        let userPicks = mockDraft.filter { $0.teamAbbreviation == userAbbr }.map { $0.pickNumber }.sorted()
        guard let firstUserPick = userPicks.first else { return nil }

        let targets = UserDraftBoard.targets(among: prospects, limit: 10)
        guard !targets.isEmpty else { return nil }

        var likely = 0
        var coinflip = 0
        var availableNames: [String] = []
        for prospect in targets {
            guard let read = DraftAvailability.read(for: prospect, atPick: firstUserPick) else { continue }
            switch read.tier {
            case .likely:
                likely += 1
                if availableNames.count < 3 { availableNames.append(prospect.lastName) }
            case .coinflip:
                coinflip += 1
            case .longShot:
                break
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

    // MARK: - Mock 1.0 vs Final Mock (#103 §5.7)

    /// One prospect's slot in the first public mock against his slot in the
    /// last one.
    private struct MockMove: Identifiable {
        let id: UUID
        let name: String
        let position: String
        let from: Int
        let to: Int
        /// Positive = climbed (a smaller pick number).
        var delta: Int { from - to }
    }

    /// The spring in one strip: who the two public mocks disagree about.
    ///
    /// Only the two ANNOUNCED moments are diffed — the mid-season and combine
    /// mocks are placeholders the league never talked about, and diffing
    /// against February would price in four months of ordinary board churn
    /// instead of what the pro-day circuit and the pre-draft weeks did.
    private func computeMockComparison() -> [MockMove] {
        guard let opening = WeekAdvancer.mockDraftHistory[Self.mockOneTag], !opening.isEmpty,
              let closing = WeekAdvancer.mockDraftHistory[Self.mockTwoTag], !closing.isEmpty
        else { return [] }

        var openingSlot: [UUID: Int] = [:]
        for pick in opening where openingSlot[pick.prospectID] == nil {
            openingSlot[pick.prospectID] = pick.pickNumber
        }
        let prospectByID = Dictionary(
            prospects.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var moves: [MockMove] = []
        for pick in closing {
            guard let was = openingSlot[pick.prospectID], was != pick.pickNumber,
                  let prospect = prospectByID[pick.prospectID]
            else { continue }
            moves.append(MockMove(
                id: pick.prospectID,
                name: prospect.fullName,
                position: prospect.position.rawValue,
                from: was,
                to: pick.pickNumber
            ))
        }

        let risers = moves.filter { $0.delta > 0 }.sorted { $0.delta > $1.delta }.prefix(3)
        let fallers = moves.filter { $0.delta < 0 }.sorted { $0.delta < $1.delta }.prefix(3)
        return Array(risers) + Array(fallers)
    }

    @ViewBuilder
    private var mockComparisonSection: some View {
        if !cachedMockComparison.isEmpty {
            Section {
                ForEach(cachedMockComparison) { move in
                    HStack(spacing: 10) {
                        Image(systemName: move.delta > 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(move.delta > 0 ? Color.success : Color.warning)
                            .frame(width: 16)

                        Text(move.position)
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(Color.textTertiary)
                            .frame(width: 30, alignment: .leading)

                        Text(move.name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        Text("#\(String(move.from)) \u{2192} #\(String(move.to))")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Color.textSecondary)
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "\(move.position) \(move.name), \(move.delta > 0 ? "up" : "down") "
                        + "from pick \(move.from) to pick \(move.to)"
                    )
                }
            } header: {
                Text("MOCK 1.0 \u{2192} FINAL MOCK")
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
    /// Unified onto `Color.forRating(scale: .percent)` — mock-draft confidence
    /// is a 0–100 gauge, and its bottom band had no red at all.
    private func confidenceColor(for confidence: Int) -> Color {
        Color.forRating(confidence, scale: .percent)
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

    /// Returns the user's big board rank (1-based) for a prospect, or nil if not on board.
    private func userBoardRank(for prospectID: UUID) -> Int? {
        userBoardRanks[prospectID]
    }

    private func loadData() {
        // #103 §5.7: `WeekAdvancer.mockDraftHistory` is a process static, so a
        // force-quit used to empty this screen's entire snapshot picker — the
        // one affordance four stored mocks exist for. The history is mirrored
        // onto the save now; warm the static back up before anything reads it.
        // Idempotent and season-stamped: a blob from an earlier draft cycle is
        // discarded rather than shown against this year's class.
        WeekAdvancer.restoreMockDraftHistory(from: career)

        let cid = career.id
        let teamDesc = FetchDescriptor<Team>(predicate: #Predicate { $0.careerID == cid })
        teams = (try? modelContext.fetch(teamDesc)) ?? []

        let playerDesc = FetchDescriptor<Player>(predicate: #Predicate { $0.careerID == cid })
        players = (try? modelContext.fetch(playerDesc)) ?? []

        if let teamID = career.teamID {
            // THIS year's picks only. The tradable horizon holds three more
            // drafts whose slots are provisional midpoints (`round * 32 - 16`),
            // and an unfiltered fetch mixed them in — the same board then showed
            // "Rd 1 #16" three times for a club picking fourth.
            let season = career.currentSeason
            let pickDesc = FetchDescriptor<DraftPick>(
                predicate: #Predicate<DraftPick> {
                    $0.currentTeamID == teamID && $0.seasonYear == season
                }
            )
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
