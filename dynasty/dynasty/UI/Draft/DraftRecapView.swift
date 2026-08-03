import SwiftUI
import SwiftData

/// Read-only recap of the most recent completed NFL Draft, plus the club's
/// upcoming draft capital.
///
/// This is the destination behind the top-nav "Draft" entry **outside** the
/// draft phase. Before it existed, that entry pushed `DraftDayView`, which
/// rebuilt a live war room from persisted picks — so opening "Draft" in Week 1
/// of the regular season resumed a running 60-second pick clock for a draft the
/// sidebar already reported as Complete. Nothing here mutates state or ticks a
/// clock: it reads `DraftPick` rows and renders them.
struct DraftRecapView: View {

    let career: Career

    @Environment(\.modelContext) private var modelContext

    @State private var loaded = false
    /// Season of the newest draft that has at least one completed pick.
    @State private var recapSeason: Int?
    /// Completed picks of `recapSeason`, grouped by round in pick order.
    @State private var roundsOfRecap: [(round: Int, picks: [DraftPick])] = []
    /// Outstanding (not yet used) picks the user's club owns, newest year last.
    @State private var upcomingCapital: [(season: Int, picks: [DraftPick])] = []

    private var userTeamID: UUID? { career.teamID }

    /// How many of the recap draft's picks belonged to the user.
    private var userPickCount: Int {
        roundsOfRecap.reduce(0) { $0 + $1.picks.filter(isUserPick).count }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.lg) {
                if recapSeason == nil && upcomingCapital.isEmpty {
                    emptyState
                } else {
                    headerCard
                    if !upcomingCapital.isEmpty {
                        capitalSection
                    }
                    if let season = recapSeason {
                        resultsSection(season: season)
                    }
                }
            }
            .padding(DSSpacing.md)
            .frame(maxWidth: DSLayout.wideMeasure, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color.backgroundPrimary)
        .navigationTitle("Draft")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear(perform: loadIfNeeded)
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.success)
                Text(recapSeason.map { "\(String($0)) Draft complete" } ?? "No draft on the books yet")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                Spacer(minLength: 0)
            }

            Text(headerSubtitle)
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            NavigationLink(value: CareerShellView.ShellDestination.draftReportCard) {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.doc.horizontal")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Draft Report Card")
                        .font(.footnote.weight(.semibold))
                }
                .foregroundStyle(Color.accentGold)
                .padding(.horizontal, DSSpacing.sm)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                        .fill(Color.accentGold.opacity(0.12))
                )
            }
            .buttonStyle(.plain)
            .padding(.top, DSSpacing.xxs)
        }
        .padding(DSSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.card)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: DSCornerRadius.card)
                        .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                )
        )
    }

    private var headerSubtitle: String {
        guard recapSeason != nil else {
            return "The war room opens during the NFL Draft phase. Until then this screen tracks the picks you hold."
        }
        let picks = userPickCount == 1 ? "1 pick" : "\(userPickCount) picks"
        return "You made \(picks). The war room reopens on draft day — this is the record until then."
    }

    // MARK: - Draft Capital

    private var capitalSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            SectionHeaderText(title: "Your Draft Capital")

            ForEach(upcomingCapital, id: \.season) { entry in
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(entry.season))
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.accentGold)

                    // Rounds owned, as compact chips.
                    let rounds = entry.picks.map(\.round).sorted()
                    HStack(spacing: 6) {
                        ForEach(Array(rounds.enumerated()), id: \.offset) { _, round in
                            Text("R\(round)")
                                .font(.caption.weight(.bold).monospacedDigit())
                                .foregroundStyle(Color.textPrimary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule().fill(Color.backgroundTertiary)
                                )
                        }
                        Spacer(minLength: 0)
                        Text("\(entry.picks.count) pick\(entry.picks.count == 1 ? "" : "s")")
                            .font(.caption2.weight(.medium).monospacedDigit())
                            .foregroundStyle(Color.textTertiary)
                    }
                }
                .padding(DSSpacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: DSCornerRadius.card)
                        .fill(Color.backgroundSecondary)
                )
            }
        }
    }

    // MARK: - Results By Round

    private func resultsSection(season: Int) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            SectionHeaderText(title: "\(season) Draft Results")

            ForEach(roundsOfRecap, id: \.round) { entry in
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Round \(entry.round)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        let mine = entry.picks.filter(isUserPick).count
                        if mine > 0 {
                            Text("\(mine) yours")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color.accentGold)
                        }
                    }
                    .padding(.horizontal, DSSpacing.sm)
                    .padding(.vertical, DSSpacing.xs)
                    .frame(maxWidth: .infinity)
                    .background(Color.backgroundTertiary)

                    ForEach(entry.picks, id: \.id) { pick in
                        pickRow(pick)
                        if pick.id != entry.picks.last?.id {
                            Divider().overlay(Color.surfaceBorder.opacity(0.5))
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: DSCornerRadius.card)
                        .fill(Color.backgroundSecondary)
                )
                .clipShape(RoundedRectangle(cornerRadius: DSCornerRadius.card))
            }
        }
    }

    private func pickRow(_ pick: DraftPick) -> some View {
        let mine = isUserPick(pick)
        return HStack(spacing: DSSpacing.xs) {
            Text("#\(pick.pickNumber)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(mine ? Color.accentGold : Color.textTertiary)
                .frame(width: 40, alignment: .leading)

            Text(pick.teamAbbreviation ?? "—")
                .font(.caption.weight(.heavy))
                .foregroundStyle(mine ? Color.accentGold : Color.textSecondary)
                .frame(width: 44, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                Text(pick.playerName ?? "No selection")
                    .font(.subheadline.weight(mine ? .bold : .medium))
                    .foregroundStyle(pick.playerName == nil ? Color.textTertiary : Color.textPrimary)
                    .lineLimit(1)
                if let college = pick.playerCollege, !college.isEmpty {
                    Text(college)
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: DSSpacing.xxs)

            if let position = pick.playerPosition, !position.isEmpty {
                Text(position)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 34, height: 20)
                    .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))
            }

            if let grade = pick.mediaGrade ?? pick.scoutGrade, !grade.isEmpty {
                Text(grade)
                    .font(.caption.weight(.heavy).monospacedDigit())
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 30, alignment: .trailing)
            }
        }
        .padding(.horizontal, DSSpacing.sm)
        .padding(.vertical, 7)
        .background(mine ? Color.accentGold.opacity(0.10) : Color.clear)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Pick \(pick.pickNumber), \(pick.teamAbbreviation ?? "unknown team"), "
            + "\(pick.playerName ?? "no selection")\(mine ? ", your pick" : "")"
        )
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: DSSpacing.sm) {
            Image(systemName: "list.clipboard")
                .font(.system(size: 44))
                .foregroundStyle(Color.textTertiary)
            Text("No Draft On Record")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
            Text("Your first draft happens in the NFL Draft phase. Results and remaining picks will appear here afterwards.")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DSSpacing.xl)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DSSpacing.xl)
    }

    // MARK: - Helpers

    private func isUserPick(_ pick: DraftPick) -> Bool {
        guard let userTeamID else { return false }
        return pick.currentTeamID == userTeamID
    }

    // MARK: - Load

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true

        let cid = career.id
        let allPicks = (try? modelContext.fetch(FetchDescriptor<DraftPick>(
            predicate: #Predicate<DraftPick> { $0.careerID == cid }
        ))) ?? []
        guard !allPicks.isEmpty else { return }

        // Most recent draft that actually ran.
        let completed = allPicks.filter { $0.isComplete }
        if let season = completed.map(\.seasonYear).max() {
            recapSeason = season
            let ofSeason = completed
                .filter { $0.seasonYear == season }
                .sorted { $0.pickNumber < $1.pickNumber }
            roundsOfRecap = Dictionary(grouping: ofSeason, by: \.round)
                .map { (round: $0.key, picks: $0.value) }
                .sorted { $0.round < $1.round }
        }

        // Picks the club still holds, from the year after the recap onwards.
        if let userTeamID {
            let floor = recapSeason ?? (career.currentSeason - 1)
            let outstanding = allPicks.filter {
                !$0.isComplete && $0.currentTeamID == userTeamID && $0.seasonYear > floor
            }
            upcomingCapital = Dictionary(grouping: outstanding, by: \.seasonYear)
                .map { (season: $0.key, picks: $0.value.sorted { $0.round < $1.round }) }
                .sorted { $0.season < $1.season }
        }
    }
}
