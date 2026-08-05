import SwiftUI
import SwiftData

// MARK: - Private Workouts

/// The `.workouts` stage: a Big-Board-shaped list of men you can bring in for a
/// private session, and a modal that says what the session bought.
///
/// **One economy.** `career.workoutsUsed` / 30, the same counter the prospect
/// card bills. The screen this replaces ran a second, parallel workout economy:
/// a `@CareerScopedStorage("personalWorkoutsUsed")` counter capped at 10, spent
/// through `ScoutingEngine.attendProDay` — a whole-school pro day for the man's
/// college — while `ProspectDetailView` billed the same action to
/// `career.workoutsUsed` / 30 through `conductPersonalWorkout`. Two caps, two
/// engines, one feature (F7). Both the counter and the misuse are gone.
struct WorkoutsTabView: View {
    let career: Career
    let prospects: [CollegeProspect]
    let teamRoster: [Player]
    @Binding var positionFilter: ProspectPositionFilter
    var onRefresh: () -> Void

    @Environment(\.modelContext) private var modelContext
    @CareerScopedStorage("prospectCustomBoard") private var prospectCustomBoardJSON: String = "[]"

    @State private var boardRanks: [UUID: Int] = [:]
    /// Fog-safe grade rank per prospect, computed once per refresh. Sorting on
    /// `ProspectFog.rank` directly would re-read the fog O(n log n) times per
    /// body evaluation — the same shape of mistake as F6, one layer up.
    @State private var fogRanks: [UUID: Int] = [:]
    @State private var teamNeeds: Set<Position> = []
    @State private var coaches: [Coach] = []
    @State private var candidates: [CollegeProspect] = []

    @State private var searchText = ""
    @State private var sort: WorkoutSort = .board
    @State private var boardOnly = true
    @State private var showAll = false

    @State private var workoutResult: ScoutingEngine.WorkoutResult?
    @State private var workoutProspect: CollegeProspect?

    private static let maxWorkouts = 30
    private static let rowsBeforeFold = 25

    enum WorkoutSort: String, CaseIterable, Identifiable {
        case board = "My board"
        case grade = "Grade"
        case position = "Position"
        var id: String { rawValue }
    }

    // MARK: - Stage

    private var stage: DraftPrepStep { career.prepStep }
    private var isStageLocked: Bool { stage.order < DraftPrepStep.workouts.order }
    private var isStageClosed: Bool { stage.order > DraftPrepStep.workouts.order }
    private var canAct: Bool { !isStageLocked && !isStageClosed }

    private var used: Int { career.workoutsUsed }
    private var remaining: Int { max(0, Self.maxWorkouts - used) }

    // MARK: - Rows

    private var filtered: [CollegeProspect] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        return candidates.filter { prospect in
            guard positionFilter.matches(prospect.position) else { return false }
            guard !boardOnly || prospect.userMark.isBoardPositive else { return false }
            guard !query.isEmpty else { return true }
            return prospect.fullName.lowercased().contains(query)
                || prospect.college.lowercased().contains(query)
        }
    }

    private var sorted: [CollegeProspect] {
        switch sort {
        case .board:
            return filtered.sorted { a, b in
                let aRank = boardRanks[a.id] ?? Int.max
                let bRank = boardRanks[b.id] ?? Int.max
                if aRank != bRank { return aRank < bRank }
                return (fogRanks[a.id] ?? 0) > (fogRanks[b.id] ?? 0)
            }
        case .grade:
            return filtered.sorted { (fogRanks[$0.id] ?? 0) > (fogRanks[$1.id] ?? 0) }
        case .position:
            return filtered.sorted { a, b in
                a.position.rawValue == b.position.rawValue
                    ? (fogRanks[a.id] ?? 0) > (fogRanks[b.id] ?? 0)
                    : a.position.rawValue < b.position.rawValue
            }
        }
    }

    private var visible: [CollegeProspect] {
        showAll || !searchText.isEmpty ? sorted : Array(sorted.prefix(Self.rowsBeforeFold))
    }

    // MARK: - Body

    var body: some View {
        Group {
            if isStageLocked {
                lockedState
            } else {
                workoutList
            }
        }
        .task { refresh() }
        .sheet(item: $workoutResult) { result in
            WorkoutResultSheet(
                result: result,
                prospect: workoutProspect,
                slotsUsed: used,
                slotLimit: Self.maxWorkouts
            )
        }
    }

    private var lockedState: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.run.circle")
                .font(.system(size: 44))
                .foregroundStyle(Color.textTertiary)
            Text("Workouts Have Not Opened")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
            Text("Private workouts run after the pro-day circuit \u{2014} you bring a man in once you know who is worth the trip. You are at: \(stage.displayName).")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var workoutList: some View {
        List {
            explainerSection
            controlsSection
            rowsSection
            if canAct { advanceSection }
        }
        .scrollContentBackground(.hidden)
        .listStyle(.insetGrouped)
    }

    private var explainerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "dumbbell.fill")
                        .font(.caption)
                        .foregroundStyle(Color.accentBlue)
                    Text("Your building, your coaches, one man")
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
                Text("The most accurate read in the game: your coordinators run him through what they actually call. Thirty a cycle.")
                    .font(.caption2)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.vertical, 2)
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    private var controlsSection: some View {
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

            HStack(spacing: 10) {
                Toggle(isOn: $boardOnly) {
                    Text("Only men on my board")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                .toggleStyle(.switch)
                .tint(Color.accentGold)

                Spacer()

                Menu {
                    ForEach(WorkoutSort.allCases) { option in
                        Button {
                            sort = option
                        } label: {
                            if sort == option {
                                Label(option.rawValue, systemImage: "checkmark")
                            } else {
                                Text(option.rawValue)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.caption2)
                        Text(sort.rawValue)
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(Color.accentBlue)
                }
            }
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    private var rowsSection: some View {
        Section {
            if visible.isEmpty {
                Text(boardOnly
                     ? "Nobody on your board is still un-worked. Turn off the board filter to see the rest of the class."
                     : "Nobody left to bring in.")
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
                    .padding(.vertical, 4)
            } else {
                ForEach(visible) { prospect in
                    workoutRow(prospect)
                }
                if !showAll && searchText.isEmpty && sorted.count > Self.rowsBeforeFold {
                    Button { showAll = true } label: {
                        Text("Show all \(sorted.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentBlue)
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            HStack {
                Label("PRIVATE WORKOUTS", systemImage: "dumbbell.fill")
                    .foregroundStyle(Color.accentBlue)
                Spacer()
                Text("\(used) / \(Self.maxWorkouts) used \u{2022} \(remaining) left")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(remaining == 0 ? Color.danger : Color.textSecondary)
            }
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    private func workoutRow(_ prospect: CollegeProspect) -> some View {
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

            Button { runWorkout(prospect) } label: {
                Text("Invite")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(blocked ? Color.textTertiary : Color.backgroundPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(blocked ? Color.backgroundTertiary : Color.accentBlue,
                                in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .disabled(blocked)
            .accessibilityLabel("Invite \(prospect.fullName) for a private workout")
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
                        Text(used > 0 ? "Done with the workouts" : "Skip the workouts")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color.backgroundPrimary)
                        Text(used > 0
                             ? (used == 1 ? "1 man worked out for your staff" : "\(used) men worked out for your staff")
                             : "Nobody works out for your staff this cycle")
                            .font(.caption)
                            .foregroundStyle(Color.backgroundPrimary.opacity(0.8))
                    }
                    Spacer()
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.backgroundPrimary)
                }
                .padding(12)
                .background(Color.accentBlue, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
    }

    // MARK: - Actions

    /// One workout: through the chokepoint, billed once, surfaced in a modal.
    private func runWorkout(_ prospect: CollegeProspect) {
        guard canAct, remaining > 0 else { return }

        var result: ScoutingEngine.WorkoutResult?
        let applied = DraftClassMutator.mutate(modelContext) { klass in
            guard let idx = klass.firstIndex(where: { $0.id == prospect.id }) else { return }
            result = ScoutingEngine.conductPersonalWorkout(prospect: klass[idx], coaches: coaches)
        }
        guard applied, let result else { return }

        career.workoutsUsed += 1
        try? modelContext.save()

        workoutProspect = prospect
        workoutResult = result

        refresh()
        onRefresh()
    }

    private func advanceStage() {
        guard canAct else { return }
        career.advancePrepStep(to: .mockOne)
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

        // The gate is "has this man already been worked out privately", and the
        // record of that is the filed `.personalWorkout` report — the same thing
        // the board's work-up column reads.
        //
        // It used to be `proDayCompleted`, which is wrong by construction now
        // that the stages are adjacent and forced: `attendProDay` flips that
        // flag for EVERY declared man at every focused school, so the tour
        // deleted its own targets out of the very next stage. Reserve five
        // schools, send the department out, advance to Workouts — and every man
        // the trip was for was missing from the list and greyed out on his card.
        candidates = prospects.filter {
            $0.isDeclaringForDraft && !ScoutingEngine.hasWorkedOutPrivately($0)
        }

        var fog: [UUID: Int] = [:]
        fog.reserveCapacity(candidates.count)
        for prospect in candidates { fog[prospect.id] = ProspectFog.rank(prospect) }
        fogRanks = fog

        if coaches.isEmpty, let teamID = career.teamID {
            let descriptor = FetchDescriptor<Coach>(predicate: #Predicate { $0.teamID == teamID })
            coaches = (try? modelContext.fetch(descriptor)) ?? []
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

// MARK: - Workout result sheet

/// What the slot bought, as a modal rather than the one-line `.alert` the old
/// screen showed. Shared with `ProspectDetailView`, so a workout looks the same
/// wherever it was ordered from.
struct WorkoutResultSheet: View {
    let result: ScoutingEngine.WorkoutResult
    let prospect: CollegeProspect?
    let slotsUsed: Int
    let slotLimit: Int

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()
                List {
                    gradeSection
                    if let note = result.personalityNote { readSection(title: "The room", body: note) }
                    readSection(title: "Scheme fit", body: result.schemeFitNote)
                    if !result.impressions.isEmpty { impressionsSection }
                    medicalSection
                    slotSection
                }
                .scrollContentBackground(.hidden)
                .listStyle(.insetGrouped)
            }
            .navigationTitle(prospect?.fullName ?? "Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var gradeSection: some View {
        Section {
            HStack(spacing: 14) {
                gradeColumn("Before", text: result.gradeBefore?.displayText ?? "\u{2014}", tint: .textTertiary)
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                gradeColumn("After", text: result.gradeAfter?.displayText ?? "\u{2014}", tint: .accentGold)
                Spacer()
            }
            .padding(.vertical, 4)
        } header: {
            Text("Grade band")
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    private func gradeColumn(_ label: String, text: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
            Text(text)
                .font(.title3.weight(.bold))
                .foregroundStyle(tint)
        }
    }

    private func readSection(title: String, body: String) -> some View {
        Section {
            Text(body)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        } header: {
            Text(title)
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    private var impressionsSection: some View {
        Section {
            ForEach(result.impressions, id: \.self) { line in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 5))
                        .foregroundStyle(Color.accentBlue)
                        .padding(.top, 5)
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(Color.textPrimary)
                }
            }
        } header: {
            Text("What the staff saw")
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    @ViewBuilder
    private var medicalSection: some View {
        let concerns = prospect?.medicalConcerns ?? []
        let flags = prospect?.redFlags ?? []
        Section {
            if concerns.isEmpty && flags.isEmpty {
                Text("Nothing new on the medical or the background.")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            } else {
                ForEach(concerns, id: \.self) { concern in
                    Label(concern, systemImage: "cross.case.fill")
                        .font(.caption)
                        .foregroundStyle(Color.warning)
                }
                ForEach(flags, id: \.self) { flag in
                    Label(flag, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.danger)
                }
            }
        } header: {
            Text("Medical & flags")
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    private var slotSection: some View {
        Section {
            Text("\(slotsUsed) of \(slotLimit) workout slots used this cycle.")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Color.textTertiary)
        }
        .listRowBackground(Color.backgroundSecondary)
    }
}
