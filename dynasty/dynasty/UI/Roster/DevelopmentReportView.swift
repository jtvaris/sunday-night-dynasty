import SwiftUI
import SwiftData

// MARK: - DevelopmentReportView (R26)

/// Development hub for the user's team:
/// 1. Training Focus — pick up to 3 players for extra weekly reps in a
///    position-relevant skill area (young players convert reps the best).
/// 2. Mentorships — the active R25 veteran → youngster pairs and their
///    +10% development boost, surfaced instead of hidden in the engine.
/// 3. Weekly Development Reports — who improved and why, who is stalled.
struct DevelopmentReportView: View {

    let career: Career

    @Environment(\.modelContext) private var modelContext

    @State private var players: [Player] = []
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

    /// Candidates for a new focus slot: unfocused, young-first.
    private var focusCandidates: [Player] {
        players
            .filter { $0.trainingFocusArea == nil }
            .sorted {
                if $0.age != $1.age { return $0.age < $1.age }
                return $0.overall > $1.overall
            }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            ScrollView {
                VStack(spacing: DSSpacing.lg) {
                    instructionBanner
                    focusSection
                    mentorSection
                    reportsSection
                }
                .padding(20)
                .frame(maxWidth: 860)
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

            if focusedPlayers.isEmpty {
                emptyStateText("No focus players set. Extra reps go unused every week they sit idle.")
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
        VStack(alignment: .leading, spacing: 10) {
            Text("Week \(report.week) · Season \(report.season)")
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
                        color: entry.reason == .injury || entry.reason == .holdout
                            ? Color.danger : Color.warning
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

    private func reportRow(entry: DevelopmentReport.Entry, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
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
                        ForEach(focusCandidates, id: \.id) { player in
                            Button {
                                setFocus(
                                    player: player,
                                    area: TrainingFocusArea.defaultArea(for: player.position)
                                )
                                showFocusPicker = false
                            } label: {
                                candidateRow(player)
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

    private func candidateRow(_ player: Player) -> some View {
        let pastPeak = player.age > player.position.peakAgeRange.upperBound

        return HStack(spacing: 10) {
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
                    if let label = player.assessedPotential, !label.isEmpty {
                        Text("· Potential: \(label)")
                            .font(.caption)
                            .foregroundStyle(Color.accentGold)
                    }
                }
            }
            Spacer()
            Text(pastPeak ? "Low gains" : "Add")
                .font(.caption.weight(.semibold))
                .foregroundStyle(pastPeak ? Color.warning : Color.accentGold)
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
    }
}
