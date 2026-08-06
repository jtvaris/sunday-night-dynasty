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
    /// The signed deal behind each completed pick, keyed by `DraftPick.id`.
    @State private var dealsByPickID: [UUID: RookieDeal] = [:]
    /// Year-one cap charge of the USER's own class, in thousands.
    @State private var classCapCharge: Int = 0
    /// The club's cap room with that charge already on the books — `nil` when
    /// there is no user club (a spectator save) or the team row is missing.
    @State private var userCapRoom: Int?

    private var userTeamID: UUID? { career.teamID }

    /// What a drafted man is actually being paid.
    ///
    /// Task #94: the recap listed names and grades and never once said what the
    /// class COST, which is half of what a draft is — `completePick` charges the
    /// rookie slot to the club the moment the card is handed in, and the only
    /// screen that reported the picks said nothing about the money.
    struct RookieDeal {
        /// Average per year, in thousands.
        let salary: Int
        /// Length of the deal AS SIGNED, from the rookie slot chart.
        ///
        /// Not `contractYearsRemaining`. This screen is reachable all season and
        /// its header calls the line "the signed slot", so reading the live
        /// counter rendered a four-year rookie deal as "2 yrs" two league years
        /// later under a label claiming to quote the contract he put his name
        /// to. `DraftEngine.rookieContract` is deterministic in the pick number
        /// and cap-independent on this field, so it cannot drift.
        let years: Int
        /// Share of the DRAFTING club's cap, in percent. `nil` when that club's
        /// row could not be read.
        let capPercent: Double?

        /// "$10.9M · 4 yrs · 4.1%"
        var displayText: String {
            var parts = [DraftRecapView.formatCap(salary), "\(years) yr\(years == 1 ? "" : "s")"]
            if let capPercent {
                parts.append(String(format: "%.1f%%", capPercent))
            }
            return parts.joined(separator: " · ")
        }
    }

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
                // #152 — printed as the class year (see `DraftYearLabel`).
                Text(recapSeason.map { "\(String(DraftYearLabel.classYear(forStamped: $0))) Draft complete" } ?? "No draft on the books yet")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                Spacer(minLength: 0)
            }

            Text(headerSubtitle)
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            classMoneyCard

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

    // MARK: - Class money (task #94)

    /// What the class costs and what is left after it.
    ///
    /// The rookie slots are charged to the club at the podium
    /// (`DraftDayCoordinator.completePick`), unconditionally and with no
    /// affordability test — which is correct, a drafted man is signed whether
    /// the club has room or not. Nothing told the user, so a class could put a
    /// team over the cap in complete silence. The tint is the whole point: red
    /// here means the room is gone.
    /// Whether the recap draft is THIS league year's.
    ///
    /// `DraftPick.seasonYear` is stamped with `career.currentSeason`, and the
    /// year does not move until the roster-cuts → regular-season transition, so
    /// this is true from draft night to the end of that offseason and false
    /// forever after. It gates every LIVE cap read on the screen: `loadIfNeeded`
    /// takes the most recent completed draft and the screen is reachable all
    /// season, so a week-10 visit was measuring a March class against a cap that
    /// had since absorbed free agency, trades and cuts.
    private var recapIsCurrentLeagueYear: Bool {
        recapSeason == career.currentSeason
    }

    @ViewBuilder
    private var classMoneyCard: some View {
        if userPickCount > 0 {
            let liveRoom = recapIsCurrentLeagueYear ? userCapRoom : nil
            let overCap = (liveRoom ?? 0) < 0
            // What the club's room was BEFORE the class was charged. The charge
            // is on the books already, so this is an addition, not a guess.
            let roomBefore = liveRoom.map { $0 + classCapCharge }
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                HStack(alignment: .top, spacing: DSSpacing.lg) {
                    moneyStat(
                        label: "Class cap charge",
                        value: Self.formatCap(classCapCharge),
                        tint: Color.textPrimary
                    )
                    if let liveRoom {
                        moneyStat(
                            label: "Cap room after",
                            value: Self.formatCap(liveRoom),
                            tint: overCap ? Color.warning : Color.success
                        )
                    }
                    Spacer(minLength: 0)
                }

                if let liveRoom, overCap {
                    // Attribution, not assumption. A club that walked into the
                    // draft $5M over and spent $3M on the class was being told
                    // "this class put you $8.0M over the cap", which is simply
                    // untrue — the class is responsible for its own charge and
                    // nothing else.
                    let classCausedIt = (roomBefore ?? 0) >= 0
                    Label(
                        classCausedIt
                            ? "This class put you \(Self.formatCap(abs(liveRoom))) over the cap. Clear room before the new league year."
                            : "You are \(Self.formatCap(abs(liveRoom))) over the cap. \(Self.formatCap(classCapCharge)) of that is this class — you were already \(Self.formatCap(abs(roomBefore ?? 0))) over before it. Clear room before the new league year.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.warning)
                    .fixedSize(horizontal: false, vertical: true)
                }

                if !recapIsCurrentLeagueYear {
                    Text("Cap room is not shown for a past draft — the club's sheet has moved on since.")
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(DSSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                    .fill(overCap ? Color.warning.opacity(0.12) : Color.backgroundTertiary.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                            .strokeBorder(
                                overCap ? Color.warning.opacity(0.55) : Color.clear,
                                lineWidth: 1
                            )
                    )
            )
            .padding(.top, DSSpacing.xxs)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "Class cap charge \(Self.formatCap(classCapCharge))"
                + (liveRoom.map {
                    overCap
                        ? ", \(Self.formatCap(abs($0))) over the cap"
                        : ", cap room after \(Self.formatCap($0))"
                } ?? "")
            )
        }
    }

    private func moneyStat(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: DSType.Size.micro, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(Color.textTertiary)
            Text(value)
                .font(.subheadline.weight(.heavy).monospacedDigit())
                .foregroundStyle(tint)
        }
    }

    // MARK: - Draft Capital

    private var capitalSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            SectionHeaderText(title: "Your Draft Capital")

            ForEach(upcomingCapital, id: \.season) { entry in
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(DraftYearLabel.classYear(forStamped: entry.season)))
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
        // #152 — every year PRINTED on this screen is the class year; `season`
        // itself stays the stored stamp because `recapIsCurrentLeagueYear`
        // compares it against `career.currentSeason`.
        let label = DraftYearLabel.classYear(forStamped: season)
        return VStack(alignment: .leading, spacing: DSSpacing.sm) {
            SectionHeaderText(title: "\(label) Draft Results")

            if !recapIsCurrentLeagueYear {
                // The term comes from the slot chart and cannot drift, but the
                // salary and cap share are read live off the player row, so for
                // an older class they are what he is paid NOW — say so instead
                // of calling them the deal he signed.
                Text("Salaries shown are current, not as signed — these men have been on the books since \(label).")
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

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
                HStack(spacing: 5) {
                    if let college = pick.playerCollege, !college.isEmpty {
                        Text(college)
                            .font(.caption2)
                            .foregroundStyle(Color.textTertiary)
                            .lineLimit(1)
                            .layoutPriority(-1)
                    }
                    // The signed slot. Present for every completed pick whose
                    // player row still exists; a man who has since retired or
                    // been deleted simply drops the line.
                    if let deal = dealsByPickID[pick.id] {
                        Text(deal.displayText)
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(mine ? Color.accentGold : Color.textSecondary)
                            .lineLimit(1)
                    }
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
            + (dealsByPickID[pick.id].map { ", signed for \($0.displayText)" } ?? "")
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

    /// "$10.9M" / "$795K" / "-$3.2M". Sign is carried outside the dollar sign so
    /// an over-cap figure reads as money rather than as `$-3.2M`.
    static func formatCap(_ thousands: Int) -> String {
        let sign = thousands < 0 ? "-" : ""
        let magnitude = abs(thousands)
        if magnitude >= 1_000 {
            return sign + String(format: "$%.1fM", Double(magnitude) / 1_000.0)
        }
        return "\(sign)$\(magnitude)K"
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
            loadDeals(for: ofSeason, careerID: cid)
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

    /// Resolves the signed deal behind every completed pick of the recap draft.
    ///
    /// **The join is `DraftPick.playerID`.** The row already stores the drafted
    /// man's `Player.id` — stamped by `DraftDayCoordinator.completePick` in the
    /// same statement that stamps `playerName` — so there is no need to match on
    /// name plus club, and no risk of the wrong hit when two clubs draft men who
    /// share a name. One `IN`-shaped fetch over those ids, one over `Team`, and
    /// the whole recap is priced.
    private func loadDeals(for picks: [DraftPick], careerID cid: UUID) {
        let playerIDs = picks.compactMap(\.playerID)
        guard !playerIDs.isEmpty else { return }

        let players = (try? modelContext.fetch(FetchDescriptor<Player>(
            predicate: #Predicate<Player> { playerIDs.contains($0.id) }
        ))) ?? []
        guard !players.isEmpty else { return }
        let playersByID = Dictionary(players.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let teams = (try? modelContext.fetch(FetchDescriptor<Team>(
            predicate: #Predicate<Team> { $0.careerID == cid }
        ))) ?? []
        let capsByTeamID = Dictionary(teams.map { ($0.id, $0.salaryCap) }, uniquingKeysWith: { first, _ in first })

        var deals: [UUID: RookieDeal] = [:]
        var userCharge = 0
        for pick in picks {
            guard let playerID = pick.playerID, let player = playersByID[playerID] else { continue }
            let cap = capsByTeamID[pick.currentTeamID] ?? 0
            deals[pick.id] = RookieDeal(
                salary: player.annualSalary,
                years: DraftEngine.rookieContract(pickNumber: pick.pickNumber, salaryCap: cap).years,
                capPercent: cap > 0 ? Double(player.annualSalary) / Double(cap) * 100.0 : nil
            )
            if isUserPick(pick) { userCharge += player.annualSalary }
        }

        dealsByPickID = deals
        classCapCharge = userCharge
        // The charge is already ON the books — `completePick` debits the club at
        // the podium — so this is the room the user is actually living with, not
        // a projection.
        if let userTeamID {
            userCapRoom = teams.first { $0.id == userTeamID }?.availableCap
        }
    }
}
