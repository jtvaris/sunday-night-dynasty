import SwiftUI
import SwiftData

// MARK: - Street Free Agency View
//
// **The wire, all year round** (D6 — the user's half of D4-A).
//
// `InSeasonMarketEngine` opened the street for the other 31 clubs and said in
// its own header why it stopped there: the pass filters the user out
// (`teams.filter { $0.id != career.teamID }`) because "he has no in-season
// free-agency screen either … the user's half is a screen". This is that
// screen, and it is deliberately not in-season-only — the hole it was written
// for is a club that walks out of March without a kicker, notices in August,
// and until now had no door to fix it through in either month.
//
// It signs the SAME pool at the SAME price the AI half signs at:
// `InSeasonMarketEngine.streetPool` and one year at
// `ContractEngine.veteranMinimum`. Nothing on this screen is a discount, and
// nothing here is a second free-agent market — see `isOpenToUser` for the one
// phase the door is shut in and why.

struct StreetFreeAgencyView: View {

    let career: Career

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var allPlayersUnscoped: [Player]
    @Query private var allTeamsUnscoped: [Team]

    @State private var scope: BoardScope = .needs
    @State private var confirming: Player? = nil
    @State private var banner: Banner? = nil

    private enum BoardScope: String, CaseIterable, Identifiable {
        case needs
        case everyone

        var id: String { rawValue }

        /// Not "Everyone": this picker widens the board from the short-handed
        /// rooms to the whole of `streetPool`, which is everyone ON THE WIRE —
        /// still `overall < streetCeilingOverall`, still not the whole unsigned
        /// population.
        var label: String {
            switch self {
            case .needs:    return "Our Needs"
            case .everyone: return "Whole Wire"
            }
        }
    }

    private struct Banner {
        let text: String
        let isGood: Bool
    }

    // MARK: - Scoped data

    // `@Query` cannot take a runtime predicate built from a stored property, so
    // the store-wide result is narrowed to THIS save here — the same shape
    // `PracticeSquadView` uses, and for the same reason: otherwise the wire
    // would list another career's free agents.
    private var allPlayers: [Player] { allPlayersUnscoped.filter { $0.careerID == career.id } }
    private var allTeams: [Team] { allTeamsUnscoped.filter { $0.careerID == career.id } }

    private var ourTeam: Team? {
        guard let teamID = career.teamID else { return nil }
        return allTeams.first { $0.id == teamID }
    }

    private var ourRoster: [Player] {
        guard let teamID = career.teamID else { return [] }
        return PracticeSquadEngine.activeRoster(of: teamID, in: allPlayers)
    }

    /// Position rooms below the ideal count on the AVAILABLE roster, straight
    /// from the engine the AI half gates its own signings on — so "we need a
    /// corner" means one thing on this screen, on the poach board and in the
    /// weekly pass.
    private var needs: [Position] {
        PracticeSquadEngine.shorthandedPositions(roster: ourRoster)
    }

    private var needSet: Set<Position> { Set(needs) }

    /// The wire: unsigned, uninjured, out of contract and under the street
    /// ceiling — `InSeasonMarketEngine.streetPool`, best keep-score first.
    private var pool: [Player] {
        InSeasonMarketEngine.streetPool(allPlayers: allPlayers)
    }

    private var board: [Player] {
        switch scope {
        case .needs:    return pool.filter { needSet.contains($0.position) }
        case .everyone: return pool
        }
    }

    // MARK: - The door

    private var rosterCeiling: Int {
        InSeasonMarketEngine.userRosterCeiling(phase: career.currentPhase)
    }

    private var dealSalary: Int {
        ourTeam.map { InSeasonMarketEngine.streetSalary(for: $0) } ?? 0
    }

    /// Whether this is the OPEN offseason half of the door — read off the
    /// ceiling `userRosterCeiling` hands back rather than by retyping the phase
    /// list, so the screen cannot disagree with the engine about which months
    /// are which. `isOpenToUser` keeps the note off the one phase where the
    /// answer is the market screen instead.
    private var isOffseasonDoor: Bool {
        InSeasonMarketEngine.isOpenToUser(phase: career.currentPhase)
            && rosterCeiling == TradeValueEngine.offseasonRosterCeiling
    }

    /// Why the club cannot sign right now — computed BEFORE the user presses
    /// anything, so the refusal is a sentence on the screen rather than a dead
    /// button he has to guess at.
    private var refusal: InSeasonMarketEngine.StreetRefusal? {
        guard let team = ourTeam else { return nil }
        return InSeasonMarketEngine.userRefusal(
            team: team,
            roster: ourRoster,
            capMode: career.capMode,
            phase: career.currentPhase
        )
    }

    private var canSign: Bool { ourTeam != nil && refusal == nil }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()

                VStack(spacing: 0) {
                    summaryBar

                    Picker("Board", selection: $scope) {
                        ForEach(BoardScope.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, DSSpacing.md)
                    .padding(.vertical, DSSpacing.xxs)

                    if let refusal {
                        noticeLine(refusalText(refusal), tint: .warning)
                    }
                    if let banner {
                        noticeLine(banner.text, tint: banner.isGood ? .success : .danger)
                    }

                    list
                }
            }
            .navigationTitle("Street Free Agents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                confirming.map { signPrompt(for: $0) } ?? "",
                isPresented: Binding(
                    get: { confirming != nil },
                    set: { if !$0 { confirming = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let player = confirming {
                    Button("Sign to active roster") { sign(player) }
                }
                Button("Cancel", role: .cancel) { confirming = nil }
            }
        }
    }

    // MARK: - Summary

    private var summaryBar: some View {
        HStack(spacing: DSSpacing.lg) {
            summaryStat(
                "Roster",
                "\(ourRoster.count)/\(rosterCeiling)",
                tint: ourRoster.count >= rosterCeiling ? Color.warning : Color.textPrimary
            )
            summaryStat(
                "Cap room",
                DraftRecapView.formatCap(ourTeam?.availableCap ?? 0),
                tint: capRoomTint
            )
            summaryStat(
                "Deal",
                "\(DraftRecapView.formatCap(dealSalary)) · 1 yr",
                tint: .textSecondary
            )
            Spacer()
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
        .background(Color.backgroundSecondary)
    }

    /// Sandbox spends no cap at all, so the column must not turn red in a mode
    /// where the number it is judging never binds.
    private var capRoomTint: Color {
        guard career.capMode != .sandbox else { return .textSecondary }
        guard let team = ourTeam else { return .textSecondary }
        return team.availableCap >= dealSalary ? Color.textSecondary : Color.danger
    }

    private func summaryStat(_ title: String, _ value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
            Text(title.uppercased())
                .font(.system(size: DSType.Size.micro, weight: .semibold))
                .foregroundStyle(Color.textSecondary)
            Text(value)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(tint)
        }
    }

    private func noticeLine(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DSSpacing.md)
            .padding(.bottom, DSSpacing.xxs)
    }

    // MARK: - List

    @ViewBuilder
    private var list: some View {
        if board.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: DSSpacing.xs) {
                    header
                    ForEach(board, id: \.id) { player in
                        row(player)
                    }
                }
                .padding(DSSpacing.md)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            // The ceiling is the whole character of this market and it is easy
            // to read an empty-looking board as a bug instead. `streetCeilingOverall`
            // is the engine's own constant, quoted rather than retyped.
            //
            // The sentence describes the BOARD, not the unsigned population:
            // `streetPool` applies `overall < streetCeilingOverall` as a filter
            // and measures nothing about who is unsigned. `PracticeSquadEngine`
            // (:141) records 176-207 unsigned men at a mean OVR of 74.1 standing
            // on the street in August, so a real share of them sit at or above
            // the ceiling — the board withholds those, and says so rather than
            // claiming they do not exist.
            Text("This wire lists free agents under \(InSeasonMarketEngine.streetCeilingOverall) overall — camp cuts, washouts and men coming back from a year out. Anyone still unsigned above that is not on this board. Every deal here is one year at the veteran minimum.")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isOffseasonDoor {
                offseasonCapNote
            }

            if !needs.isEmpty {
                needsStrip
            }
        }
        .padding(.bottom, DSSpacing.xxs)
    }

    /// The one way a summer signing made here differs from every other body
    /// that walks into a camp roster: `CampRosterEngine.invite` is deliberately
    /// cap-exempt ("NO `team.currentCapUsage += …`. That is the whole
    /// mechanism."), while this door signs a real one-year deal through
    /// `ContractEngine.signPlayerSimple`, which debits `annualSalary` the moment
    /// it lands. Sandbox charges nothing at all, so the line stays off there.
    @ViewBuilder
    private var offseasonCapNote: some View {
        if career.capMode != .sandbox {
            Text("Out of season this is still a real contract, not a camp invite: a camp body is cap-exempt, and \(DraftRecapView.formatCap(dealSalary)) goes on the cap the moment you sign here.")
                .font(.caption)
                .foregroundStyle(Color.warning)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The short-handed rooms, exactly as `shorthandedPositions` returns them —
    /// a position is listed when its GROUP is under the ideal count the
    /// free-agent market prices need with, which is why a thin offensive line
    /// lights up all five of its slots rather than one.
    private var needsStrip: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
            Text("SHORT-HANDED")
                .font(.system(size: DSType.Size.micro, weight: .semibold))
                .foregroundStyle(Color.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DSSpacing.xxs) {
                    ForEach(needs, id: \.self) { position in
                        Text(position.rawValue)
                            .font(.system(size: DSType.Size.micro, weight: .bold))
                            .foregroundStyle(Color.accentGold)
                            .padding(.horizontal, DSSpacing.xs)
                            .padding(.vertical, DSSpacing.xxs)
                            .background(
                                Color.accentGold.opacity(0.15),
                                in: RoundedRectangle(cornerRadius: DSCornerRadius.tight)
                            )
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: DSSpacing.sm) {
            Image(systemName: "figure.american.football")
                .font(.system(size: DSType.Size.display))
                .foregroundStyle(Color.textSecondary.opacity(0.5))
            Text(emptyStateText)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DSSpacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateText: String {
        if pool.isEmpty {
            return "Nobody is on the wire. It fills again as clubs release players and each league year's free agents go unsigned."
        }
        if needs.isEmpty {
            return "No position room is below strength, so there is nobody the wire has to fix. Switch to Whole Wire to look anyway."
        }
        return "Nobody on the wire plays a position you are short at. Switch to Whole Wire to see the rest of it."
    }

    private func row(_ player: Player) -> some View {
        HStack(spacing: DSSpacing.sm) {
            Text(player.position.rawValue)
                .font(.caption.weight(.bold))
                .foregroundStyle(needSet.contains(player.position) ? Color.accentGold : Color.textPrimary)
                .frame(width: 38, alignment: .leading)

            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text(player.fullName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text(subtitle(for: player))
                    .font(.caption2)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: DSSpacing.xs)

            VStack(alignment: .trailing, spacing: DSSpacing.xxs) {
                Text("\(player.overall)")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(Color.textPrimary)
                Text("POT \(player.assessedPotential ?? "—")")
                    .font(.system(size: DSType.Size.micro))
                    .foregroundStyle(Color.textSecondary)
            }

            Button {
                confirming = player
            } label: {
                Text("Sign")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, DSSpacing.sm)
                    .padding(.vertical, DSSpacing.xxs)
                    .background(
                        canSign ? Color.accentGold : Color.textSecondary.opacity(0.3),
                        in: RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                    )
                    .foregroundStyle(canSign ? Color.black : Color.textSecondary)
            }
            .buttonStyle(.plain)
            .disabled(!canSign)
        }
        .padding(DSSpacing.sm)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: DSCornerRadius.card))
    }

    private func subtitle(for player: Player) -> String {
        var parts: [String] = ["\(player.age) yrs", "\(player.yearsPro) yr pro"]
        if needSet.contains(player.position) { parts.append("fills a need") }
        return parts.joined(separator: " · ")
    }

    private func signPrompt(for player: Player) -> String {
        "Sign \(player.fullName) for one year at \(DraftRecapView.formatCap(dealSalary))?"
    }

    private func refusalText(_ refusal: InSeasonMarketEngine.StreetRefusal) -> String {
        switch refusal {
        case .marketOpen:
            return "Free agency is open — these men are on the market screen, at market prices. The street reopens once the market closes."
        case .rosterFull(let ceiling):
            return "Roster full at \(ceiling). Release a player before you sign one."
        case .shortOfCap(let needed, let available):
            return "The veteran minimum is \(DraftRecapView.formatCap(needed)) and you have \(DraftRecapView.formatCap(available)). Clear room first."
        }
    }

    // MARK: - Actions

    private func sign(_ player: Player) {
        defer { confirming = nil }
        guard let team = ourTeam else { return }
        let name = player.fullName
        let position = player.position.rawValue

        let outcome = InSeasonMarketEngine.signForUser(
            player,
            to: team,
            roster: ourRoster,
            capMode: career.capMode,
            phase: career.currentPhase
        )

        switch outcome {
        case .signed(let salary):
            try? modelContext.save()
            banner = Banner(
                text: "\(name) (\(position)) signed for one year at \(DraftRecapView.formatCap(salary)).",
                isGood: true
            )
        case .refused(let reason):
            banner = Banner(text: refusalText(reason), isGood: false)
        }
    }
}
