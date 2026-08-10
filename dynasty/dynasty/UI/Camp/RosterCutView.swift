import SwiftUI
import SwiftData

// MARK: - Roster Cut View
//
// The three-stage cutdown — 90 → 75 → 65 → 53 — on the wave-3 standard:
// `DSSlatBand` for the ladder, `DSActionBar` for the commit, `DSResultSheet` for
// the ending (UI_REDESIGN_VISION §2.1 / §2.5 / §2.6).
//
// **What was actually wrong here was the ending, not the list.** The screen
// committed a set of releases and then advanced its own `@State stage` — the
// in-place body swap §2.6 bans by name. The header re-titled itself, the target
// changed and the list shortened, all silently, and the user was never told how
// many men he had released, how much room it had freed, or how much dead money
// it had left behind. Every one of those numbers already existed: the engine
// returns them and the screen threw them away.
//
// Two structural changes follow from fixing that:
//
//   1. **The stage is derived, not stored.** The roster count is the truth, so
//      a stored stage was a second copy of a fact that could disagree with the
//      list underneath it (it did: the stage always opened at 90 → 75 no matter
//      what the roster actually held, so a club resuming a half-done cutdown
//      was shown the wrong target). Deriving only works if the count is live:
//      the `roster` parameter the shell passes in is a one-shot fetch that
//      never refreshes, so this screen owns `liveRoster` and re-fetches it
//      after every commit. Without that the derived stage freezes at the value
//      it opened with and the cutdown can never be finished.
//   2. **The commit confirms.** A release is irreversible and career-affecting,
//      which is exactly the class §0 counted committing on first tap.

struct RosterCutView: View {

    let career: Career
    /// The shell's opening snapshot. Used only until the first fetch lands —
    /// see `activeRoster`.
    let roster: [Player]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// The club as it stands **now**. `nil` before the first fetch, so the very
    /// first render still has the shell's snapshot to draw rather than an empty
    /// list. Refreshed on appear and after every commit.
    @State private var liveRoster: [Player]?

    @State private var positionGroup: CutPositionGroup = .all
    @State private var selectedIDs: Set<UUID> = []
    /// Player IDs that the user has flagged as practice-squad-eligible.
    @State private var practiceSquadIDs: Set<UUID> = []
    /// Detailed deals for this club, so the release split prices a real
    /// `Contract` where one exists instead of always using the proxy.
    @State private var contractsByPlayer: [UUID: Contract] = [:]
    /// Releases already booked this cutdown, keyed by the stage that booked
    /// them — what each finished slat reports (§2.1's `done` row).
    @State private var releasesByStage: [CutDay: Int] = [:]
    /// The commit is irreversible, so it asks first.
    @State private var showCutConfirm = false
    /// **The one modal slot.** One `.sheet(item:)`, per the house rule.
    @State private var result: CutResult?

    /// What a completed stage did, as `DSResultSheet` needs it.
    struct CutResult: Identifiable {
        let id = UUID()
        let released: Int
        let capFreed: Int
        let deadMoney: Int
        let practiceSquadFlagged: Int
        let rosterAfter: Int
        let stage: CutDay
        /// The stage the club stands on once this one is banked, if any.
        let nextStage: CutDay?
    }

    var body: some View {
        VStack(spacing: 0) {
            band
            tabBar
            list
            actionBar
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("Roster Cuts")
        .navigationBarTitleDisplayMode(.inline)
        .task { loadLedger() }
        // Confirmation only (§2.8) — never a result.
        .alert("Release \(selectedIDs.count) player\(selectedIDs.count == 1 ? "" : "s")?", isPresented: $showCutConfirm) {
            Button("Release", role: .destructive) { performCuts() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This frees \(money(selectionSavings)) and leaves \(money(selectionDeadMoney)) of dead money on this year's books. "
                + "Releases cannot be undone."
            )
        }
        .sheet(item: $result) { result in
            resultSheet(result)
        }
    }

    // MARK: - The ladder (§2.1)

    private var band: some View {
        DSSlatBand(
            slats: CutDay.allCases.enumerated().map { index, day in
                slat(for: day, position: index + 1)
            },
            headline: headline,
            meter: meter
        )
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.xs)
        .background(Color.backgroundPrimary)
    }

    private func slat(for day: CutDay, position: Int) -> DSSlat {
        let state: DSSlat.State
        if isComplete || day.target > stage.target {
            // A larger target than the one the club is working to is behind it:
            // the ladder counts DOWN, so "done" is the higher number.
            state = .done
        } else if day == stage {
            state = .current
        } else {
            state = .future
        }
        let released = releasesByStage[day] ?? 0
        return DSSlat(
            id: day.rawValue,
            index: "\(position)",
            title: day.slatTitle,
            subcaption: state == .current ? currentSubcaption : nil,
            state: state,
            outcome: state == .done && released > 0 ? "\(released) released" : nil,
            accessibilityText: [
                "Cut stage \(position) of \(CutDay.allCases.count)",
                day.slatTitle,
                state == .done ? "complete" : (state == .current ? "current stage" : "not started"),
                state == .done && released > 0 ? "\(released) released" : nil,
                state == .current ? currentSubcaption : nil
            ]
            .compactMap { $0 }
            .joined(separator: ", ")
        )
    }

    /// **The one place the stage count is printed** (§2.1).
    private var headline: String {
        guard let index = CutDay.allCases.firstIndex(of: stage), !isComplete else {
            return "Cutdown complete"
        }
        return "Cut day \(index + 1) of \(CutDay.allCases.count)"
    }

    private var currentSubcaption: String {
        guard requiredCuts > 0 else { return "At the limit \u{2014} bank it and move on" }
        return "\(activeRoster.count) on the roster \u{00B7} \(remaining) more to release"
    }

    /// A filled pip is a spent cut — the meter's one meaning, everywhere.
    /// Suppressed when the stage asks for nothing, because a meter of zero pips
    /// is a rendering artefact rather than a reading.
    private var meter: DSResourceMeter? {
        guard requiredCuts > 0 else { return nil }
        return DSResourceMeter(
            spent: min(selectedIDs.count, requiredCuts),
            total: requiredCuts,
            unit: "cuts"
        )
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DSSpacing.xs) {
                ForEach(CutPositionGroup.allCases) { group in
                    Button {
                        positionGroup = group
                    } label: {
                        Text(group.label)
                            .font(DSType.text(DSType.Size.footnote, .semibold))
                            .padding(.horizontal, DSSpacing.sm)
                            .padding(.vertical, DSSpacing.xs)
                            .background(
                                RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                                    .fill(positionGroup == group ? Color.backgroundTertiary : Color.backgroundSecondary)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                                    .strokeBorder(
                                        positionGroup == group ? Color.accentBlue : Color.surfaceBorder,
                                        lineWidth: positionGroup == group ? 2 : 1
                                    )
                            )
                            .foregroundStyle(positionGroup == group ? Color.textPrimary : Color.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(positionGroup == group ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.xs)
        }
        .background(Color.backgroundPrimary)
    }

    // MARK: - List

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: DSSpacing.xs) {
                ForEach(filteredRoster, id: \.id) { player in
                    row(for: player)
                }
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)
        }
    }

    private func row(for player: Player) -> some View {
        let isSelected = selectedIDs.contains(player.id)
        let isPS = practiceSquadIDs.contains(player.id)
        return HStack(spacing: DSSpacing.sm) {
            // Avatar placeholder
            Circle()
                .fill(Color.backgroundTertiary)
                .frame(width: 36, height: 36)
                .overlay(
                    Text(initials(for: player))
                        .font(DSType.display(DSType.Size.footnote, .bold))
                        .foregroundStyle(Color.textSecondary)
                )

            VStack(alignment: .leading, spacing: 2) {  // ds-lint:allow(spacing) name-over-meta lockup inside one row
                HStack(spacing: DSSpacing.xxs) {
                    Text(player.position.rawValue)
                        .font(DSType.display(11, .heavy))
                        .padding(.horizontal, DSSpacing.xxs)
                        .padding(.vertical, 2)  // ds-lint:allow(spacing) position badge must not grow the row
                        .background(
                            RoundedRectangle(cornerRadius: DSCornerRadius.tight)
                                .fill(Color.backgroundTertiary)
                        )
                        .foregroundStyle(Color.textSecondary)
                    Text(player.fullName)
                        .font(DSType.text(DSType.Size.body, .semibold, prose: true))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                }
                HStack(spacing: DSSpacing.xs) {
                    Text("OVR \(player.overall)")
                        .font(DSType.display(11, .semibold))
                        .foregroundStyle(Color.forRating(player.overall))
                    Text("Age \(player.age)")
                        .font(DSType.display(11, .semibold))
                        .foregroundStyle(Color.textTertiaryReadable)
                    if let grade = player.campGrade {
                        Text("Camp \(grade.displayLabel)")
                            .font(DSType.display(11, .heavy))
                            .foregroundStyle(Color.accentGold)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {  // ds-lint:allow(spacing) value-over-control lockup inside one row
                Text(capSavingsLabel(for: player))
                    .font(DSType.display(DSType.Size.footnote, .heavy))
                    .foregroundStyle(Color.success)
                Button {
                    togglePracticeSquad(player)
                } label: {
                    Text(isPS ? "PS \u{2713}" : "PS")
                        .font(DSType.display(11, .heavy))
                        .padding(.horizontal, DSSpacing.xs)
                        .padding(.vertical, 3)  // ds-lint:allow(spacing) inline toggle inside a fixed row height
                        .background(
                            RoundedRectangle(cornerRadius: DSCornerRadius.tight)
                                .fill(isPS ? Color.accentBlue : Color.backgroundTertiary)
                        )
                        .foregroundStyle(isPS ? Color.textPrimary : Color.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    isPS
                        ? "\(player.fullName) is flagged for the practice squad"
                        : "Flag \(player.fullName) for the practice squad"
                )
            }
        }
        .padding(DSSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.card)
                .fill(isSelected ? Color.danger.opacity(0.18) : Color.backgroundSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DSCornerRadius.card)
                .strokeBorder(isSelected ? Color.danger : Color.surfaceBorder, lineWidth: isSelected ? 1.5 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { toggleSelection(player) }
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(isSelected ? "Tap to keep him" : "Tap to mark him for release")
    }

    // MARK: - The commit surface (§2.5)

    private var actionBar: some View {
        DSActionBar(
            explainer: explainer,
            primary: isComplete
                ? .init(title: "Done \u{2014} roster is set", handler: { dismiss() })
                : .init(
                    title: selectedIDs.isEmpty
                        ? "Release players"
                        : "Release \(selectedIDs.count) player\(selectedIDs.count == 1 ? "" : "s")",
                    isEnabled: !selectedIDs.isEmpty,
                    handler: { showCutConfirm = true }
                )
        )
    }

    /// What committing does and what it costs (P4) — or, when it is blocked,
    /// why (§2.12: a blocked commit swaps the rule to orange and says the
    /// reason rather than presenting a dead grey button with no explanation).
    private var explainer: DSActionBar.Explainer {
        if isComplete {
            return .init(
                title: "Cutdown complete",
                message: "Your roster is at **\(activeRoster.count)**. Nothing more is owed here."
            )
        }
        if selectedIDs.isEmpty {
            return .init(
                title: "Nobody selected",
                message: remaining > 0
                    ? "You are **\(remaining) over** the \(stage.target)-man limit. Tap a player to mark him for release."
                    : "You are at the **\(stage.target)-man limit** already \u{2014} tap a player only if you want to go under it.",
                isWarning: remaining > 0
            )
        }
        let ps = practiceSquadIDs.intersection(selectedIDs).count
        let psLine = ps > 0 ? " **\(ps)** flagged for the practice squad." : ""
        return .init(
            title: "Release \(selectedIDs.count) \u{2014} \(activeRoster.count - selectedIDs.count) left on the roster",
            message: "Frees **\(money(selectionSavings))** and leaves **\(money(selectionDeadMoney))** of dead money.\(psLine)"
        )
    }

    // MARK: - The ending (§2.6)

    private func resultSheet(_ result: CutResult) -> some View {
        DSResultSheet(
            tone: result.deadMoney > result.capFreed ? .bad : .neutral,
            eyebrow: "Cutdown \u{00B7} \(result.stage.slatTitle)",
            headline: "\(result.released) player\(result.released == 1 ? "" : "s") released",
            message: result.nextStage == nil
                ? "Your roster is at **\(result.rosterAfter)**. The cutdown is done."
                : "Your roster is at **\(result.rosterAfter)**. Next: **\(result.nextStage!.slatTitle)**.",
            chips: [
                .init(id: "roster", label: "Roster", value: "\(result.rosterAfter)", context: "\(result.released) released"),
                .init(
                    id: "freed",
                    label: "Cap freed",
                    value: money(result.capFreed),
                    context: "this year",
                    valueColor: .success
                ),
                .init(
                    id: "dead",
                    label: "Dead money",
                    value: money(result.deadMoney),
                    context: "stays on the books",
                    valueColor: result.deadMoney > 0 ? .dangerText : .textPrimary
                ),
                .init(
                    id: "ps",
                    label: "Practice squad",
                    value: "\(result.practiceSquadFlagged)",
                    context: "flagged"
                )
            ],
            cost: result.deadMoney > 0
                ? "**\(money(result.deadMoney))** of dead cap stays on this year's books, and a flagged man can still be claimed off waivers before you sign him."
                : "Nothing accelerated onto this year's cap. Flagged men can still be claimed off waivers before you sign them.",
            continueTitle: result.nextStage == nil ? "Done" : "Continue",
            onContinue: { self.result = nil }
        )
    }

    // MARK: - Stage, derived

    /// **Every derivation below reads this, never `roster`.** The parameter is
    /// a frozen snapshot; this is the club after the releases already booked.
    private var activeRoster: [Player] { liveRoster ?? roster }

    /// The stage the club is working to, read off the roster rather than stored.
    private var stage: CutDay {
        CutDay.stage(forRosterCount: activeRoster.count) ?? .cut65To53
    }

    private var isComplete: Bool { activeRoster.count <= CutDay.cut65To53.target }

    /// Men over this stage's limit before any selection.
    private var requiredCuts: Int { max(0, activeRoster.count - stage.target) }

    /// Men still to be marked after the current selection.
    private var remaining: Int { max(0, activeRoster.count - selectedIDs.count - stage.target) }

    private var filteredRoster: [Player] {
        activeRoster.filter { positionGroup.includes($0.position) }
    }

    // MARK: - Selection

    private func toggleSelection(_ player: Player) {
        if selectedIDs.contains(player.id) {
            selectedIDs.remove(player.id)
        } else {
            selectedIDs.insert(player.id)
        }
    }

    private func togglePracticeSquad(_ player: Player) {
        if practiceSquadIDs.contains(player.id) {
            practiceSquadIDs.remove(player.id)
        } else {
            practiceSquadIDs.insert(player.id)
        }
    }

    private func initials(for player: Player) -> String {
        let f = player.firstName.first.map(String.init) ?? ""
        let l = player.lastName.first.map(String.init) ?? ""
        return "\(f)\(l)"
    }

    // MARK: - Money

    /// The share of the league year still unpaid, for the release split (#26).
    /// Cutdown day is an offseason phase, so this is 1.0 in the normal flow —
    /// it is read from the career anyway so a release made while the regular
    /// season is running prices the remaining game checks, not a full year.
    private var leagueYearRemaining: Double {
        CapManagementEngine.leagueYearRemaining(
            phase: career.currentPhase,
            week: career.currentWeek
        )
    }

    private func releaseSplit(for player: Player) -> CapManagementEngine.ReleaseCapSplit {
        CapManagementEngine.releaseCapSplit(
            player: player,
            contract: contractsByPlayer[player.id],
            capMode: career.capMode,
            leagueYearRemaining: leagueYearRemaining
        )
    }

    /// What the current selection frees, quoted from the same engine the cut
    /// itself books (#68), so the bar and the ledger cannot disagree.
    private var selectionSavings: Int {
        selectedIDs.reduce(0) { total, id in
            guard let player = activeRoster.first(where: { $0.id == id }) else { return total }
            return total + releaseSplit(for: player).capSavings
        }
    }

    /// What it leaves behind — the honest second number §2.4 asks every cost to
    /// carry.
    private var selectionDeadMoney: Int {
        selectedIDs.reduce(0) { total, id in
            guard let player = activeRoster.first(where: { $0.id == id }) else { return total }
            return total + releaseSplit(for: player).deadCap
        }
    }

    /// Net cap effect of releasing this man — relief minus the dead money that
    /// stays behind.
    private func capSavingsLabel(for player: Player) -> String {
        let savings = releaseSplit(for: player).capSavings
        return (savings < 0 ? "\u{2212}" : "+") + money(abs(savings))
    }

    private func money(_ thousands: Int) -> String {
        String(format: "$%.1fM", Double(thousands) / 1_000.0)
    }

    // MARK: - Data

    /// Detailed deals for this club, keyed by player. Most players have none —
    /// `Contract` rows are only minted for realistic-mode signings — and the
    /// engine falls back to the 15 %/yr proxy for the rest.
    ///
    /// The cut ledger is read in the same pass: a finished slat has to be able
    /// to report what it produced, and the `RosterCut` rows are where that lives
    /// across a relaunch.
    ///
    /// **And the roster itself**, because the whole ladder is derived from its
    /// count. This is the only hook that puts the released men back out of the
    /// list and moves the stage on.
    private func loadLedger() {
        guard let teamID = career.teamID else { return }
        liveRoster = (try? modelContext.fetch(FetchDescriptor<Player>(
            predicate: #Predicate<Player> { $0.teamID == teamID }
        ))) ?? []

        let contractRows = (try? modelContext.fetch(FetchDescriptor<Contract>(
            predicate: #Predicate<Contract> { $0.teamID == teamID }
        ))) ?? []
        contractsByPlayer = Dictionary(
            contractRows.map { ($0.playerID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let season = career.currentSeason
        let cutRows = (try? modelContext.fetch(FetchDescriptor<RosterCut>(
            predicate: #Predicate<RosterCut> { $0.teamID == teamID && $0.seasonYear == season }
        ))) ?? []
        var byStage: [CutDay: Int] = [:]
        for cut in cutRows {
            guard let day = CutDay(rawValue: cut.cutDayRaw) else { continue }
            byStage[day, default: 0] += 1
        }
        releasesByStage = byStage
    }

    private func performCuts() {
        guard let teamID = career.teamID, !selectedIDs.isEmpty else { return }
        let teamDescriptor = FetchDescriptor<Team>(predicate: #Predicate<Team> { $0.id == teamID })
        guard let team = try? modelContext.fetch(teamDescriptor).first else { return }

        let bankedStage = stage
        let now = Date()
        var released = 0
        var capFreed = 0
        var deadMoney = 0
        var psFlagged = 0

        for id in selectedIDs {
            guard let player = activeRoster.first(where: { $0.id == id }) else { continue }
            // A man already off the books cannot be released twice: without this
            // a stale tap would re-run `applyRelease` on a `teamID == nil`
            // player and book a second, $0 `RosterCut` row for him.
            guard player.teamID == teamID else { continue }
            // ONE authority for the money AND the roster move: this screen used
            // to write a receipt and nothing else — the player stayed on the 53
            // and not a cent of dead cap ever reached `currentCapUsage` (#68).
            let split = CapManagementEngine.applyRelease(
                player: player,
                team: team,
                contract: contractsByPlayer[player.id],
                capMode: career.capMode,
                leagueYearRemaining: leagueYearRemaining,
                careerID: career.id,
                modelContext: modelContext
            )
            let isPS = practiceSquadIDs.contains(player.id)
            let cut = RosterCut(
                playerID: player.id,
                teamID: teamID,
                seasonYear: career.currentSeason,
                cutDayRaw: bankedStage.rawValue,
                capSavings: split.capSavings,
                deadCap: split.deadCap,
                practiceSquadEligible: isPS,
                occurredAt: now
            )
            cut.careerID = career.id
            modelContext.insert(cut)

            released += 1
            capFreed += split.capSavings
            deadMoney += split.deadCap
            if isPS { psFlagged += 1 }
        }
        try? modelContext.save()

        selectedIDs.removeAll()
        practiceSquadIDs.removeAll()
        // Re-reads the roster as well as the ledger, so the ladder, the list and
        // the count below all move on together.
        loadLedger()
        let rosterAfter = activeRoster.count

        // Every man in the selection was already gone (a stale tap): nothing was
        // booked, so there is nothing to report. The refreshed list above is the
        // correction the user needs to see.
        guard released > 0 else { return }

        // §2.6 — the flow states what it did. It used to advance a `@State`
        // stage and say nothing at all.
        result = CutResult(
            released: released,
            capFreed: capFreed,
            deadMoney: deadMoney,
            practiceSquadFlagged: psFlagged,
            rosterAfter: rosterAfter,
            stage: bankedStage,
            nextStage: CutDay.stage(forRosterCount: rosterAfter)
        )
    }
}

// MARK: - Cut stages, as the band draws them

extension CutDay {
    /// The roster size this stage is cutting **to**.
    var target: Int {
        switch self {
        case .cut90To75: return 75
        case .cut75To65: return 65
        case .cut65To53: return 53
        }
    }

    /// The slat label. Short on purpose: at three slats across an iPad the band
    /// has room, but the title is still held to the two-line box every other
    /// band lives in.
    var slatTitle: String {
        switch self {
        case .cut90To75: return "Cut to 75"
        case .cut75To65: return "Cut to 65"
        case .cut65To53: return "Cut to 53"
        }
    }

    /// The stage a club of this size is working to, or nil once it is legal.
    /// The same derivation `RosterCutView.stage` uses, exposed so the result
    /// sheet can name what comes next without duplicating the ladder.
    static func stage(forRosterCount count: Int) -> CutDay? {
        if count > CutDay.cut90To75.target { return .cut90To75 }
        if count > CutDay.cut75To65.target { return .cut75To65 }
        if count > CutDay.cut65To53.target { return .cut65To53 }
        return nil
    }
}

// MARK: - Position Groups

private enum CutPositionGroup: String, CaseIterable, Identifiable {
    case all
    case qb
    case backs
    case receivers
    case oline
    case dline
    case lb
    case db
    case st

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:       return "All"
        case .qb:        return "QB"
        case .backs:     return "RB / FB"
        case .receivers: return "WR / TE"
        case .oline:     return "OL"
        case .dline:     return "DL"
        case .lb:        return "LB"
        case .db:        return "DB"
        case .st:        return "ST"
        }
    }

    func includes(_ position: Position) -> Bool {
        switch self {
        case .all:       return true
        case .qb:        return position == .QB
        case .backs:     return position == .RB || position == .FB
        case .receivers: return position == .WR || position == .TE
        case .oline:     return [.LT, .LG, .C, .RG, .RT].contains(position)
        case .dline:     return position == .DE || position == .DT
        case .lb:        return position == .OLB || position == .MLB
        case .db:        return [.CB, .FS, .SS].contains(position)
        case .st:        return position == .K || position == .P
        }
    }
}
