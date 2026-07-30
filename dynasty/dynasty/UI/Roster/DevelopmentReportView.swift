import SwiftUI
import SwiftData

// MARK: - DevelopmentReportView (R26)

/// Development hub for the user's team:
/// 1. Training Focus — pick up to 3 players for extra weekly reps in a
///    position-relevant skill area (young players convert reps the best).
/// 2. Mentorships — the active R25 veteran → youngster pairs and their
///    +10% development boost, surfaced instead of hidden in the engine.
/// 3. Position Conversions (§5.3) — buried players the staff would move to a
///    position that needs them, and the paths already running.
/// 4. Weekly Development Reports — who improved and why, who is stalled.
struct DevelopmentReportView: View {

    let career: Career

    @Environment(\.modelContext) private var modelContext

    @State private var players: [Player] = []
    @State private var coaches: [Coach] = []
    @State private var showFocusPicker = false

    // MARK: - Derived

    private var focusedPlayers: [Player] {
        players
            .filter { $0.trainingFocusArea != nil }
            .sorted { $0.age < $1.age }
    }

    private var mentorships: [LockerRoomEngine.Mentorship] {
        LockerRoomEngine.activeMentorships(players: players)
    }

    private var reports: [DevelopmentReport] {
        career.developmentReports
    }

    private var freeSlots: Int {
        max(0, TrainingFocusEngine.maxFocusPlayersPerTeam - focusedPlayers.count)
    }

    /// One row of the "already converting" list.
    private struct ActiveConversion: Identifiable {
        let player: Player
        let progress: VersatilityDevelopmentEngine.ConversionProgress
        var id: UUID { player.id }
    }

    /// §5.3: players already on a conversion path, and what the staff would
    /// raise next. Offers exclude anyone already converting, so the two lists
    /// never show the same man twice.
    private var activeConversions: [ActiveConversion] {
        players.compactMap { player in
            VersatilityDevelopmentEngine.activeConversion(for: player)
                .map { ActiveConversion(player: player, progress: $0) }
        }
        .sorted { $0.progress.fraction > $1.progress.fraction }
    }

    private var conversionOffers: [VersatilityDevelopmentEngine.ConversionOffer] {
        VersatilityDevelopmentEngine.conversionOffers(roster: players, coaches: coaches)
    }

    private var conversionSlotsFree: Bool {
        activeConversions.count < VersatilityDevelopmentEngine.maxActiveConversions
    }

    // MARK: - Focus Candidates (the math, surfaced)

    /// One unfocused player scored with the SAME numbers the weekly tick uses.
    ///
    /// Both figures come straight out of `TrainingFocusEngine` — no parallel
    /// formula lives here — so the picker can never rank players differently
    /// from the engine that will actually develop them.
    private struct FocusCandidate: Identifiable {
        let player: Player
        /// `TrainingFocusEngine.weeklyGainChance` — probability of a +1 this week.
        let weeklyChance: Double
        /// Points left under `TrainingFocusEngine.potentialCeiling`, floored at 0.
        let headroom: Int

        var id: UUID { player.id }

        /// "31%/wk" — the engine's own roll, printed.
        var chanceLabel: String { "\(Int((weeklyChance * 100).rounded()))%/wk" }

        var headroomLabel: String { headroom > 0 ? "+\(headroom) headroom" : "at ceiling" }

        /// A slot spent here is money burned: he cannot gain a point.
        var isCapped: Bool { headroom <= 0 }
    }

    /// Candidates for a new focus slot, best expected gain first.
    ///
    /// Was: youngest-first, showing OVR only — which is a proxy for the real
    /// answer, and a bad one for a 22-year-old who is already at his ceiling.
    /// Now ranked on the two numbers that decide the outcome: a player who
    /// cannot gain sinks to the bottom regardless of age, and above that line
    /// the weekly roll leads.
    private var focusCandidates: [FocusCandidate] {
        players
            .filter { $0.trainingFocusArea == nil }
            .map { player in
                FocusCandidate(
                    player: player,
                    weeklyChance: TrainingFocusEngine.weeklyGainChance(player: player, coaches: coaches),
                    headroom: max(0, TrainingFocusEngine.potentialCeiling(for: player) - player.overall)
                )
            }
            .sorted {
                if $0.isCapped != $1.isCapped { return !$0.isCapped }
                if abs($0.weeklyChance - $1.weeklyChance) > 0.0005 {
                    return $0.weeklyChance > $1.weeklyChance
                }
                if $0.headroom != $1.headroom { return $0.headroom > $1.headroom }
                return $0.player.overall > $1.player.overall
            }
    }

    /// The three the staff would take, used to pre-populate the empty state.
    private var suggestedCandidates: [FocusCandidate] {
        Array(focusCandidates.prefix(TrainingFocusEngine.maxFocusPlayersPerTeam))
    }

    // MARK: - Focus Payoff History

    /// What the focus slots have actually produced lately.
    ///
    /// NOTE: a full previous-season tally is NOT retrievable. `FocusGain` is
    /// transient (it lives only inside the weekly tick), the persisted
    /// `Career.developmentReports` log is capped at the last 10 weeks, and
    /// `TrainingFocusEngine.SeasonBreakoutCounts` only ever holds the CURRENT
    /// season's cap usage. So this counts the reports that do survive and says
    /// exactly what window it covers rather than inventing a season total.
    private struct FocusPayoff {
        let focusGains: Int
        let breakouts: Int
        let reportCount: Int
        let seasonLabel: String
    }

    private var focusPayoff: FocusPayoff? {
        let log = reports.filter { $0.week != DevelopmentReportBuilder.campReportWeek }
        guard !log.isEmpty else { return nil }
        let gains = log.reduce(0) { $0 + $1.risers.filter { $0.reason == .focus }.count }
        let breakouts = log.reduce(0) { $0 + $1.breakouts.count }
        guard gains > 0 || breakouts > 0 else { return nil }

        let seasons = Set(log.map(\.season)).sorted()
        let label: String
        if let first = seasons.first, let last = seasons.last {
            label = first == last ? "Season \(String(first))" : "Seasons \(String(first))–\(String(last))"
        } else {
            label = ""
        }
        return FocusPayoff(
            focusGains: gains,
            breakouts: breakouts,
            reportCount: log.count,
            seasonLabel: label
        )
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            ScrollView {
                VStack(spacing: DSSpacing.lg) {
                    instructionBanner
                    focusSection
                    conversionSection
                    mentorSection
                    reportsSection
                }
                .padding(20)
                .frame(maxWidth: DSLayout.wideMeasure)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Development")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { loadPlayers() }
        .sheet(isPresented: $showFocusPicker) {
            focusPickerSheet
        }
    }

    // MARK: - Instruction Banner

    private var instructionBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.title2)
                .foregroundStyle(Color.eliteGreen)
            VStack(alignment: .leading, spacing: 4) {
                Text("Player Development")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                Text("Give up to \(TrainingFocusEngine.maxFocusPlayersPerTeam) players extra weekly reps in one skill area. Young players convert the work best — past their peak, gains dry up.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(16)
        .cardBackground()
    }

    // MARK: - Focus Section

    private var focusSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack {
                SectionHeaderText(title: "Training Focus")
                Spacer()
                Text("\(focusedPlayers.count)/\(TrainingFocusEngine.maxFocusPlayersPerTeam) slots")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
            }

            if let payoff = focusPayoff {
                focusPayoffStrip(payoff)
            }

            if focusedPlayers.isEmpty {
                emptyStateText("No focus players set. Extra reps go unused every week they sit idle.")
                suggestionBlock
            }

            ForEach(focusedPlayers, id: \.id) { player in
                focusSlotRow(player)
            }

            if freeSlots > 0 {
                Button {
                    showFocusPicker = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Focus Player")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(Color.accentGold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: DSCornerRadius.card)
                            .strokeBorder(
                                Color.accentGold.opacity(0.5),
                                style: StrokeStyle(lineWidth: 1, dash: [6, 4])
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .cardBackground()
    }

    // MARK: - Suggested Focus Players (empty state)

    /// The staff's three picks, one tap each.
    ///
    /// An empty screen that only offers "Add Focus Player" makes the manager
    /// open a 53-man list and guess. These are the same three the ranking
    /// above would put on top, with the reasons printed.
    @ViewBuilder
    private var suggestionBlock: some View {
        if !suggestedCandidates.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.eliteGreen)
                    Text("THE STAFF WOULD START HERE")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.7)
                        .foregroundStyle(Color.textTertiary)
                }

                ForEach(suggestedCandidates) { candidate in
                    suggestionRow(candidate)
                }

                if suggestedCandidates.count > 1 {
                    Button {
                        for candidate in suggestedCandidates {
                            setFocus(
                                player: candidate.player,
                                area: TrainingFocusArea.defaultArea(for: candidate.player.position)
                            )
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Accept all \(suggestedCandidates.count)")
                                .font(.caption.weight(.bold))
                        }
                        .foregroundStyle(Color.backgroundPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                                .fill(Color.eliteGreen)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Accept all \(suggestedCandidates.count) suggested focus players")
                }
            }
            .padding(.bottom, 2)
        }
    }

    private func suggestionRow(_ candidate: FocusCandidate) -> some View {
        HStack(spacing: 10) {
            positionBadge(candidate.player.position)

            VStack(alignment: .leading, spacing: 3) {
                Text(candidate.player.fullName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                candidateReasonChips(candidate)
            }

            Spacer(minLength: 6)

            Button {
                setFocus(
                    player: candidate.player,
                    area: TrainingFocusArea.defaultArea(for: candidate.player.position)
                )
            } label: {
                Text("Accept")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.backgroundPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.eliteGreen))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Give \(candidate.player.fullName) a focus slot")
            .accessibilityHint(candidateReasonText(candidate))
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                .fill(Color.backgroundTertiary)
                .overlay(
                    RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                        .strokeBorder(Color.eliteGreen.opacity(0.35), lineWidth: 1)
                )
        )
    }

    /// Age · headroom · weekly chance — the whole case for a slot in one line.
    private func candidateReasonChips(_ candidate: FocusCandidate) -> some View {
        HStack(spacing: 4) {
            reasonChip("Age \(candidate.player.age)", color: .textSecondary)
            reasonChip(
                candidate.headroomLabel,
                color: candidate.isCapped ? .warning : .accentBlue
            )
            reasonChip(
                candidate.chanceLabel,
                color: candidate.weeklyChance >= 0.25
                    ? .eliteGreen
                    : (candidate.weeklyChance >= 0.12 ? .accentGold : .warning)
            )
        }
    }

    private func candidateReasonText(_ candidate: FocusCandidate) -> String {
        "Age \(candidate.player.age), \(candidate.headroomLabel), \(candidate.chanceLabel) gain chance"
    }

    private func reasonChip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.14)))
    }

    // MARK: - Focus Payoff Strip

    private func focusPayoffStrip(_ payoff: FocusPayoff) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.eliteGreen)
                Text("\(payoff.focusGains) focus gain\(payoff.focusGains == 1 ? "" : "s")")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.eliteGreen)
                Text("·")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                Text("\(payoff.breakouts) breakout\(payoff.breakouts == 1 ? "" : "s")")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.draftStealGold)
                Spacer(minLength: 4)
                Text(payoff.seasonLabel)
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
            }
            // Full-season totals genuinely do not exist in the save — say so
            // rather than let "10 reports" read as "the whole year".
            Text("Across the last \(payoff.reportCount) weekly report\(payoff.reportCount == 1 ? "" : "s") — the log keeps 10, so this is a rolling window, not a season total.")
                .font(.system(size: 9))
                .foregroundStyle(Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                .fill(Color.backgroundTertiary.opacity(0.6))
        )
        .accessibilityElement(children: .combine)
    }

    private func focusSlotRow(_ player: Player) -> some View {
        let pastPeak = player.age > player.position.peakAgeRange.upperBound

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                positionBadge(player.position)

                VStack(alignment: .leading, spacing: 2) {
                    Text(player.fullName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    HStack(spacing: 6) {
                        Text("OVR \(player.overall)")
                            .font(.caption)
                            .foregroundStyle(Color.forRating(player.overall))
                        Text("· Age \(player.age) · Yr \(player.yearsPro + 1)")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                        if pastPeak {
                            Text("PAST PEAK")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.warning)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill(Color.warning.opacity(0.15))
                                )
                        }
                    }
                }

                Spacer()

                areaMenu(for: player)

                Button {
                    setFocus(player: player, area: nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove focus from \(player.fullName)")
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                .fill(Color.backgroundTertiary)
        )
    }

    private func areaMenu(for player: Player) -> some View {
        Menu {
            ForEach(TrainingFocusArea.areas(for: player.position)) { area in
                Button {
                    setFocus(player: player, area: area)
                } label: {
                    if player.trainingFocusArea == area {
                        Label(area.displayName, systemImage: "checkmark")
                    } else {
                        Text(area.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: player.trainingFocusArea?.icon ?? "target")
                    .font(.system(size: 11, weight: .semibold))
                Text(player.trainingFocusArea?.displayName ?? "Pick Area")
                    .font(.caption.weight(.semibold))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(Color.accentBlue)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(Color.accentBlue.opacity(0.12))
            )
        }
    }

    // MARK: - Conversion Section (§5.3)

    private var conversionSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack {
                SectionHeaderText(title: "Position Conversions")
                Spacer()
                Text("\(activeConversions.count)/\(VersatilityDevelopmentEngine.maxActiveConversions) paths")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
            }

            Text("Moving a man is a rebuild, not a depth-chart edit: he cross-trains for weeks, then takes a one-off rating hit as he learns a new job. Young players earn it back. Veterans mostly do not, which is why they are never suggested.")
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(activeConversions) { row in
                activeConversionRow(row.player, row.progress)
            }

            if conversionOffers.isEmpty {
                if activeConversions.isEmpty {
                    emptyStateText("No conversions on the board. The staff raises one when a young player is buried at his own position and profiles at one the roster is thin at.")
                }
            } else {
                ForEach(conversionOffers) { offer in
                    conversionOfferRow(offer)
                }
            }
        }
        .padding(16)
        .cardBackground()
    }

    private func activeConversionRow(
        _ player: Player,
        _ progress: VersatilityDevelopmentEngine.ConversionProgress
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                positionBadge(player.position)
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                positionBadge(progress.target)

                VStack(alignment: .leading, spacing: 2) {
                    Text(player.fullName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text(
                        progress.familiarity >= progress.threshold
                            ? "Ready to switch — held until he isn't starting at \(player.position.rawValue)"
                            : "\(progress.familiarity)% learned · switches at \(progress.threshold)%"
                    )
                    .font(.caption)
                    .foregroundStyle(
                        progress.familiarity >= progress.threshold ? Color.success : Color.textSecondary
                    )
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button {
                    VersatilityDevelopmentEngine.cancelConversion(player: player)
                    try? modelContext.save()
                    loadPlayers()
                } label: {
                    Text("Stop")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.danger)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.danger.opacity(0.15)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop converting \(player.fullName)")
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.backgroundSecondary)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.accentGold)
                        .frame(width: geo.size.width * progress.fraction)
                }
            }
            .frame(height: 6)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                .fill(Color.backgroundTertiary)
        )
    }

    private func conversionOfferRow(
        _ offer: VersatilityDevelopmentEngine.ConversionOffer
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(offer.headline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button {
                    accept(offer)
                } label: {
                    Text("Start")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.backgroundPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(conversionSlotsFree ? Color.accentGold : Color.textTertiary.opacity(0.4))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!conversionSlotsFree)
            }

            Text(offer.rationale)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Label(
                    offer.overallDelta >= 0 ? "+\(offer.overallDelta) OVR" : "\(offer.overallDelta) OVR",
                    systemImage: offer.overallDelta >= 0 ? "arrow.up.right" : "arrow.down.right"
                )
                .font(.caption2.weight(.bold))
                .foregroundStyle(offer.overallDelta >= 0 ? Color.success : Color.warning)

                if let weeks = offer.weeksEstimate {
                    Label(
                        weeks <= 0 ? "ready now" : "~\(weeks) wk of reps",
                        systemImage: "calendar"
                    )
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
                } else {
                    Label("needs an offseason", systemImage: "calendar")
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                }

                Label("\(offer.familiarity)% learned", systemImage: "brain.head.profile")
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                        .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                )
        )
    }

    private func accept(_ offer: VersatilityDevelopmentEngine.ConversionOffer) {
        guard conversionSlotsFree,
              let player = players.first(where: { $0.id == offer.playerID }) else { return }
        guard VersatilityDevelopmentEngine.startConversion(player: player, to: offer.to) else { return }
        try? modelContext.save()
        loadPlayers()
    }

    // MARK: - Mentor Section

    private var mentorSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack {
                SectionHeaderText(title: "Active Mentorships")
                Spacer()
                Text("+10% development speed")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.eliteGreen)
            }

            if mentorships.isEmpty {
                emptyStateText("No active mentor pairs. A veteran Mentor or Team Leader (4+ yrs, high leadership) automatically tutors the greenest player at his position.")
            } else {
                ForEach(mentorships) { pairing in
                    HStack(spacing: 10) {
                        positionBadge(pairing.protege.position)
                        Text(pairing.mentor.fullName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                        Image(systemName: "arrow.right")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                        Text(pairing.protege.fullName)
                            .font(.subheadline)
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        Image(systemName: "person.2.wave.2.fill")
                            .font(.caption)
                            .foregroundStyle(Color.eliteGreen)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                            .fill(Color.backgroundTertiary)
                    )
                }
            }
        }
        .padding(16)
        .cardBackground()
    }

    // MARK: - Reports Section

    private var reportsSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            SectionHeaderText(title: "Weekly Reports")

            if reports.isEmpty {
                emptyStateText("Reports land here every regular-season week: risers, breakouts, mentor effects, and stalled players.")
            } else {
                ForEach(reports) { report in
                    reportCard(report)
                }
            }
        }
        .padding(16)
        .cardBackground()
    }

    private func reportCard(_ report: DevelopmentReport) -> some View {
        // Week 0 is the training-camp edition (plan §2.10): motivation states,
        // plateau tags, late bloomers and install-year notes.
        let isCamp = report.week == DevelopmentReportBuilder.campReportWeek

        return VStack(alignment: .leading, spacing: 10) {
            Group {
                if isCamp {
                    Text("Training Camp · Season \(String(report.season))")
                } else {
                    Text("Week \(report.week) · Season \(String(report.season))")
                }
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(Color.accentGold)

            if !report.breakouts.isEmpty {
                ForEach(report.breakouts) { entry in
                    reportRow(
                        entry: entry,
                        icon: "star.fill",
                        color: Color.draftStealGold
                    )
                }
            }

            if !report.risers.isEmpty {
                ForEach(report.risers) { entry in
                    reportRow(
                        entry: entry,
                        icon: "arrow.up.circle.fill",
                        color: Color.success
                    )
                }
            }

            if !report.mentorships.isEmpty {
                ForEach(report.mentorships) { line in
                    HStack(spacing: 8) {
                        Image(systemName: "person.2.wave.2.fill")
                            .font(.caption)
                            .foregroundStyle(Color.eliteGreen)
                            .frame(width: 18)
                        Text("\(line.mentorName) → \(line.protegeName)")
                            .font(.caption)
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        Text(line.boostText)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.eliteGreen)
                    }
                }
            }

            if !report.stalled.isEmpty {
                ForEach(report.stalled) { entry in
                    reportRow(
                        entry: entry,
                        icon: "arrow.down.circle.fill",
                        color: stalledColor(for: entry.reason)
                    )
                }
            }

            if report.isEmpty {
                Text("Quiet week — no notable development movement.")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                .fill(Color.backgroundTertiary)
        )
    }

    /// Severity color for a stalled line. Injuries and holdouts are hard stops;
    /// an install year is simply a slower year, so it reads informational.
    private func stalledColor(for reason: DevelopmentReport.Reason) -> Color {
        switch reason {
        case .injury, .holdout: return Color.danger
        case .schemeChange:     return Color.accentBlue
        default:                return Color.warning
        }
    }

    private func reportRow(entry: DevelopmentReport.Entry, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            // The phase-2 narrative reasons carry their own glyph — a plateau
            // is not a fall, an install is not a slump.
            Image(systemName: entry.reason.iconOverride ?? icon)
                .font(.caption)
                .foregroundStyle(color)
                .frame(width: 18)
            Text("\(entry.playerName) (\(entry.positionRaw))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
            Text(entry.detail)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(2)
            Spacer()
            Text(entry.reason.label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(color.opacity(0.12)))
        }
    }

    // MARK: - Focus Picker Sheet

    private var focusPickerSheet: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: 8) {
                        pickerLegend

                        ForEach(focusCandidates) { candidate in
                            Button {
                                setFocus(
                                    player: candidate.player,
                                    area: TrainingFocusArea.defaultArea(for: candidate.player.position)
                                )
                                showFocusPicker = false
                            } label: {
                                candidateRow(candidate)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Pick Focus Player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { showFocusPicker = false }
                        .foregroundStyle(Color.accentBlue)
                }
            }
        }
    }

    /// Explains the two numbers the rows are sorted on, once, at the top.
    private var pickerLegend: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.accentBlue)
            Text("Ranked by expected gain. **%/wk** is the chance one week's extra reps produce a +1; **headroom** is how many points he still has under his ceiling. Age, work ethic, his position coach and his mood all move the weekly number.")
                .font(.caption2)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                .fill(Color.backgroundTertiary.opacity(0.6))
        )
    }

    private func candidateRow(_ candidate: FocusCandidate) -> some View {
        let player = candidate.player
        let pastPeak = player.age > player.position.peakAgeRange.upperBound

        return HStack(spacing: 10) {
            positionBadge(player.position)
            VStack(alignment: .leading, spacing: 3) {
                Text(player.fullName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                HStack(spacing: 6) {
                    Text("OVR \(player.overall)")
                        .font(.caption)
                        .foregroundStyle(Color.forRating(player.overall))
                    Text("· Age \(player.age) · Yr \(player.yearsPro + 1)")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                    if let label = player.assessedPotential, !label.isEmpty {
                        Text("· Potential: \(label)")
                            .font(.caption)
                            .foregroundStyle(Color.accentGold)
                    }
                }
                candidateReasonChips(candidate)
            }
            Spacer(minLength: 6)

            // The two numbers that decide the slot, stacked and legible.
            VStack(alignment: .trailing, spacing: 2) {
                Text(candidate.chanceLabel)
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(
                        candidate.isCapped
                            ? Color.textTertiary
                            : (candidate.weeklyChance >= 0.25 ? Color.eliteGreen : Color.accentGold)
                    )
                Text(candidate.isCapped ? "At ceiling" : (pastPeak ? "Low gains" : "Add"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(
                        candidate.isCapped || pastPeak ? Color.warning : Color.accentGold
                    )
            }
        }
        .padding(12)
        .opacity(candidate.isCapped ? 0.65 : 1.0)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                        .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(player.fullName), \(player.position.rawValue), overall \(player.overall). \(candidateReasonText(candidate))")
    }

    // MARK: - Shared Bits

    private func positionBadge(_ position: Position) -> some View {
        Text(position.rawValue)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Color.backgroundPrimary)
            .frame(width: 34, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 5).fill(Color.accentGold)
            )
    }

    private func emptyStateText(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(Color.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
    }

    // MARK: - Actions

    /// Sets or clears a player's focus area, enforcing the 3-slot cap.
    private func setFocus(player: Player, area: TrainingFocusArea?) {
        if area != nil,
           player.trainingFocusArea == nil,
           focusedPlayers.count >= TrainingFocusEngine.maxFocusPlayersPerTeam {
            return
        }
        player.trainingFocusArea = area
        try? modelContext.save()
    }

    private func loadPlayers() {
        guard let teamID = career.teamID else { return }
        let descriptor = FetchDescriptor<Player>(predicate: #Predicate { $0.teamID == teamID })
        players = (try? modelContext.fetch(descriptor)) ?? []
        // §5.3: the conversion offers need the staff for their week estimates.
        let coachDesc = FetchDescriptor<Coach>(predicate: #Predicate<Coach> { $0.teamID == teamID })
        coaches = (try? modelContext.fetch(coachDesc)) ?? []
    }
}
