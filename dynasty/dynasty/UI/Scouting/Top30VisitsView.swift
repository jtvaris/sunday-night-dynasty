import SwiftUI
import SwiftData

// MARK: - Top-30 Visits

/// The `.top30Visits` stage: bring men into the building.
///
/// This used to be a section buried inside the pro-day list, sharing one scroll
/// with the school circuit and the private workouts — three economies, three
/// clocks, one screen (F4). It is its own stage now, and it sits where the
/// chronology actually puts it: facility visits are the LAST instrument before
/// the draft, after the tour and after the workouts.
///
/// Same two structural rules as the tour screen: the board rank map is decoded
/// once into `@State`, and the visit itself goes through `DraftClassMutator` so
/// the interview, the medical and the revised football IQ survive a relaunch.
struct Top30VisitsView: View {
    let career: Career
    let scouts: [Scout]
    let prospects: [CollegeProspect]
    let teamRoster: [Player]
    var onRefresh: () -> Void

    @Environment(\.modelContext) private var modelContext
    @CareerScopedStorage("prospectCustomBoard") private var prospectCustomBoardJSON: String = "[]"

    @State private var boardRanks: [UUID: Int] = [:]
    @State private var teamNeeds: Set<Position> = []
    @State private var candidates: [CollegeProspect] = []
    @State private var showAll = false
    @State private var searchText = ""

    @State private var resultProspectName = ""
    @State private var resultSummary: ScoutingEngine.Top30VisitResult?
    @State private var showResult = false

    private static let visitLimit = 30
    private static let candidatesBeforeFold = 20

    // MARK: - Stage

    private var stage: DraftPrepStep { career.prepStep }
    private var isStageLocked: Bool { stage.order < DraftPrepStep.top30Visits.order }
    private var isStageClosed: Bool { stage.order > DraftPrepStep.top30Visits.order }
    private var canAct: Bool { !isStageLocked && !isStageClosed }

    private var used: Int { career.top30VisitsUsed }
    private var remaining: Int { max(0, Self.visitLimit - used) }

    private var filtered: [CollegeProspect] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return candidates }
        return candidates.filter {
            $0.fullName.lowercased().contains(query) || $0.college.lowercased().contains(query)
        }
    }

    private var visible: [CollegeProspect] {
        showAll || !searchText.isEmpty ? filtered : Array(filtered.prefix(Self.candidatesBeforeFold))
    }

    // MARK: - Body

    var body: some View {
        Group {
            if isStageLocked {
                lockedState
            } else {
                visitList
            }
        }
        .task { refresh() }
        .alert(
            "Visit: \(resultProspectName)",
            isPresented: $showResult,
            presenting: resultSummary
        ) { _ in
            Button("Done", role: .cancel) { }
        } message: { result in
            let medical = result.medicalConcerns.isEmpty ? "No new concerns" : result.medicalConcerns.joined(separator: ", ")
            let workout = result.workoutImpressions.joined(separator: ", ")
            let fit = Int((result.teamFitScore * 100).rounded())
            Text("Football IQ: \(result.footballIQRevised)\nMedical: \(medical)\nWorkout: \(workout)\nTeam fit: \(fit)%")
        }
    }

    private var lockedState: some View {
        VStack(spacing: 16) {
            Image(systemName: "house.badge.clock")
                .font(.system(size: 44))
                .foregroundStyle(Color.textTertiary)
            Text("The Visit Book Is Not Open")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
            Text("Facility visits are the last instrument before the draft. You are at: \(stage.displayName).")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var visitList: some View {
        List {
            explainerSection
            searchSection
            candidateSection
            if canAct { advanceSection }
        }
        .scrollContentBackground(.hidden)
        .listStyle(.insetGrouped)
    }

    /// Inline search, matching `BigBoardView`'s bar rather than `.searchable`:
    /// this surface lives inside the hub's navigation stack, and a system search
    /// field would attach itself to the shell's navigation bar.
    private var searchSection: some View {
        Section {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                TextField("Search prospects or schools", text: $searchText)
                    .font(.subheadline)
                    .foregroundStyle(Color.textPrimary)
                    .autocorrectionDisabled()
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    private var explainerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "house.fill")
                        .foregroundStyle(Color.accentGold)
                        .font(.caption)
                    Text("Bring a prospect to your facility")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    if isStageClosed {
                        Text("CLOSED")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(Color.textTertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))
                    }
                }
                Text("A deep interview, a focused workout for what you run, and your own medical staff on him. Thirty visits a cycle, league rule.")
                    .font(.caption2)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.vertical, 2)
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    private var candidateSection: some View {
        Section {
            if visible.isEmpty {
                Text(searchText.isEmpty
                     ? "Everybody worth a visit has already been in the building."
                     : "Nobody matches \u{201C}\(searchText)\u{201D}.")
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
                    .padding(.vertical, 4)
            } else {
                ForEach(visible) { prospect in
                    candidateRow(prospect)
                }
                if !showAll && searchText.isEmpty && filtered.count > Self.candidatesBeforeFold {
                    Button { showAll = true } label: {
                        Text("Show all \(filtered.count) candidates")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentBlue)
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            HStack {
                Label("TOP-30 VISITS", systemImage: "person.crop.circle.badge.checkmark")
                    .foregroundStyle(Color.accentGold)
                Spacer()
                Text("\(used) / \(Self.visitLimit) used \u{2022} \(remaining) left")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(remaining == 0 ? Color.danger : Color.textSecondary)
            }
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    private func candidateRow(_ prospect: CollegeProspect) -> some View {
        let read = ProspectFog.read(prospect)
        let blocked = !canAct || remaining == 0
        return HStack(spacing: 8) {
            Text(boardRanks[prospect.id].map { "#\($0)" } ?? "--")
                .font(.system(size: 10, weight: .heavy).monospacedDigit())
                .foregroundStyle((boardRanks[prospect.id] ?? 999) <= 10 ? Color.accentGold : Color.textTertiary)
                .frame(width: 28, alignment: .trailing)

            Text(prospect.position.rawValue)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 28, height: 18)
                .background(positionColor(prospect.position), in: RoundedRectangle(cornerRadius: 3))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(prospect.fullName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    if prospect.userMark != .none {
                        ProspectMarkChip(mark: prospect.userMark)
                    }
                }
                HStack(spacing: 6) {
                    Text(read.text)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(read.source.tint)
                    Text(prospect.college)
                        .font(.system(size: 9))
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)
                    if teamNeeds.contains(prospect.position) {
                        Text("NEED")
                            .font(.system(size: DSType.Size.micro, weight: .black))
                            .foregroundStyle(Color.danger)
                    }
                }
            }

            Spacer()

            Button { scheduleVisit(prospect) } label: {
                Text("Invite")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(blocked ? Color.textTertiary : Color.backgroundPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(blocked ? Color.backgroundTertiary : Color.accentGold,
                                in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .disabled(blocked)
            .accessibilityLabel("Invite \(prospect.fullName) for a facility visit")
        }
        .padding(.vertical, 2)
    }

    private var advanceSection: some View {
        Section {
            Button { advanceStage() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.backgroundPrimary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(used > 0 ? "Close the visit book" : "Skip the visits")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color.backgroundPrimary)
                        Text(used > 0
                             ? (used == 1 ? "1 man came through the building" : "\(used) men came through the building")
                             : "You will draft on tape and other people's medicals")
                            .font(.caption)
                            .foregroundStyle(Color.backgroundPrimary.opacity(0.8))
                    }
                    Spacer()
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.backgroundPrimary)
                }
                .padding(12)
                .background(Color.accentGold, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
    }

    // MARK: - Actions

    /// One visit. The mutation goes through the canonical class (F7) — the old
    /// version of this code was already correct about that and is kept, only
    /// routed through the single chokepoint instead of hand-rolling it.
    private func scheduleVisit(_ prospect: CollegeProspect) {
        guard canAct, remaining > 0, let teamID = career.teamID else { return }

        let leadScout = scouts.max(by: { $0.accuracy < $1.accuracy })
        let interviewerQuality = scouts.isEmpty
            ? 60
            : scouts.reduce(0) { $0 + $1.accuracy } / scouts.count

        var result: ScoutingEngine.Top30VisitResult?
        let applied = DraftClassMutator.mutate(modelContext) { klass in
            guard let idx = klass.firstIndex(where: { $0.id == prospect.id }) else { return }
            result = ScoutingEngine.conductTop30Visit(
                prospect: &klass[idx],
                visitingTeamID: teamID,
                interviewerQuality: interviewerQuality,
                interviewerName: leadScout.map { "Scout \($0.fullName)" } ?? "Scouting Staff",
                occasionLabel: "Top-30 Visit \u{00B7} " + String(career.currentSeason)
            )
        }
        guard applied, let result else { return }

        career.top30VisitsUsed += 1
        try? modelContext.save()

        resultProspectName = prospect.fullName
        resultSummary = result
        showResult = true

        refresh()
        onRefresh()
    }

    private func advanceStage() {
        guard canAct else { return }
        career.advancePrepStep(to: .mockTwo)
        try? modelContext.save()
        onRefresh()
    }

    // MARK: - Refresh

    private func refresh() {
        let ids = (try? JSONDecoder().decode([String].self, from: Data(prospectCustomBoardJSON.utf8))) ?? []
        var ranks: [UUID: Int] = [:]
        ranks.reserveCapacity(ids.count)
        for (index, raw) in ids.enumerated() {
            if let uuid = UUID(uuidString: raw) { ranks[uuid] = index + 1 }
        }
        boardRanks = ranks
        teamNeeds = Set(DraftEngine.topTeamNeeds(roster: teamRoster, limit: 5))

        let teamID = career.teamID
        candidates = prospects
            .filter { prospect in
                guard prospect.isDeclaringForDraft else { return false }
                guard let teamID else { return true }
                return !prospect.top30VisitedByTeams.contains(teamID)
            }
            .sorted { a, b in
                let aMark = a.userMark.isBoardPositive ? 1 : 0
                let bMark = b.userMark.isBoardPositive ? 1 : 0
                if aMark != bMark { return aMark > bMark }

                let aNeed = teamNeeds.contains(a.position) ? 1 : 0
                let bNeed = teamNeeds.contains(b.position) ? 1 : 0
                if aNeed != bNeed { return aNeed > bNeed }

                let aRank = ranks[a.id] ?? Int.max
                let bRank = ranks[b.id] ?? Int.max
                if aRank != bRank { return aRank < bRank }

                return ProspectFog.rank(a) > ProspectFog.rank(b)
            }
    }

    private func positionColor(_ position: Position) -> Color {
        switch position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }
}
