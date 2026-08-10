import SwiftUI
import SwiftData

// MARK: - Cap Compliance Workspace (#102)
//
// **The remediation half of the cap design.** Prevention lives in the free
// agency offer sheet (outstanding offers reserve cap, and an offer that does not
// fit is hard-blocked). Going over the cap is still possible through every other
// door — the draft class charge, a fifth-year option, a trade, a legacy save,
// and the acceptance-time backstop where a signing that breaches completes and
// flags compliance. This screen is what the user does about it.
//
// The shape is deliberate: one banner that states the debt in dollars, and then
// a list of PLAYERS ranked by how much room each of them can free, with the
// three real levers on every row.
//
// | lever | what it is | who decides |
// |---|---|---|
// | Release | cut him, eat the acceleration | `CapManagementEngine.releaseCapSplit` / `.applyRelease` — the one authority on a release, dead money and all |
// | Restructure | base salary above the veteran minimum converted to signing bonus and prorated | `ContractEngine.restructureQuote` / `.executeRestructure` |
// | Renegotiate | ask him to take less, in the Contact Agent chat | consent from `ContractNegotiationEngine.payCutVerdict`, the money from `ContractEngine.applyPayCut` |
//
// **This file computes no cap money.** Every number on it comes out of an
// engine; the screen's whole job is to rank the options and show the honest
// second number next to each of them — the dead money on a release, the
// future-year charges on a restructure, the morale on a pay cut. A workspace
// that showed only the relief would be a machine for making next year's problem.

struct CapComplianceView: View {

    let career: Career

    /// Why the user is on this screen.
    ///
    /// The free-agency step and the in-season compliance gate are the same
    /// workspace with different exits — one leads into the signing period, the
    /// other back to the week the required task interrupted. Defaulted to the
    /// free-agency gate so the two existing call sites (`CareerShellView`,
    /// `CareerDashboardView`) are unchanged.
    var context: Context = .freeAgencyGate

    enum Context {
        /// `FreeAgencyStep.capReview` — get legal, then open the market.
        case freeAgencyGate
        /// Deep-linked from the week-advance block. No FA button; the exit is
        /// simply being compliant again.
        case weekAdvanceGate
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var team: Team?
    @State private var players: [Player] = []
    /// Detailed deals for this club, so a release prices a real `Contract`
    /// where one exists instead of always using the engine's proxy.
    @State private var contractsByPlayer: [UUID: Contract] = [:]

    @State private var releaseTarget: Player?
    @State private var restructureTarget: Player?
    @State private var negotiationTarget: Player?
    /// Set when an agent answers a pay-cut ask with "then release him" — the
    /// workspace puts the Release lever in front of the user rather than leaving
    /// him to work out what just happened.
    @State private var releaseDemandName: String?

    // MARK: - Cap State

    private var isOverCap: Bool { capOverage > 0 }

    private var capOverage: Int {
        guard let team, career.capMode != .sandbox else { return 0 }
        return max(0, team.currentCapUsage - team.salaryCap)
    }

    /// Cap rules are off in sandbox — the workspace is readable, but there is
    /// nothing to comply with and no gate to clear.
    private var enforcesCap: Bool { career.capMode != .sandbox }

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            if let team {
                VStack(spacing: 0) {
                    // §2.1 — free agency's spine, step 3 of 5. Only on the FA
                    // gate: deep-linked from the week-advance block this screen
                    // is not a step in that run, and a band claiming otherwise
                    // would be lying about where the user stands.
                    if context == .freeAgencyGate {
                        FAFlowBandView(
                            step: .capReview,
                            currentSubcaption: isOverCap
                                ? "\(formatMillions(capOverage)) over \u{2014} the market is shut until you are legal"
                                : "Under the cap \u{2014} the market will take your offers"
                        )
                    }
                    ScrollView {
                        VStack(spacing: DSSpacing.lg) {
                            complianceBanner(team: team)
                            leverListCard(team: team)
                        }
                        .padding(DSSpacing.lg)
                        .frame(maxWidth: DSLayout.wideMeasure)
                        .frame(maxWidth: .infinity)
                    }
                    // §2.5 — the commit surface. Its explainer is where a
                    // blocked commit says WHY (§2.12); the reason used to be a
                    // red caption under a dead grey button.
                    if context == .freeAgencyGate {
                        DSActionBar(
                            explainer: enterFAExplainer,
                            primary: .init(
                                title: "Enter free agency \u{2192}",
                                isEnabled: !isOverCap,
                                handler: {
                                    career.freeAgencyStep = FreeAgencyStep.signing.rawValue
                                    career.freeAgencyRound = 1
                                }
                            )
                        )
                    }
                }
            } else {
                ProgressView()
                    .tint(Color.accentGold)
            }
        }
        .navigationTitle("Cap Compliance")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { loadData() }
        .alert("Release Player?", isPresented: .init(
            get: { releaseTarget != nil },
            set: { if !$0 { releaseTarget = nil } }
        )) {
            if let player = releaseTarget {
                Button("Release \(player.fullName)", role: .destructive) {
                    releasePlayer(player)
                }
                Button("Cancel", role: .cancel) {}
            }
        } message: {
            if let player = releaseTarget {
                // One number, from the engine that books the release (#68) —
                // simple mode used to be told it got the whole salary back.
                let split = releaseSplit(for: player)
                Text("Releasing \(player.fullName) frees \(formatMillions(split.capSavings)) of cap space and leaves \(formatMillions(split.deadCap)) of dead money on your books this year.")
            }
        }
        .alert("He wants his release", isPresented: .init(
            get: { releaseDemandName != nil },
            set: { if !$0 { releaseDemandName = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("\(releaseDemandName ?? "He") would rather test the market than take a cut. The Release lever on his row is still open to you.")
        }
        .sheet(item: $restructureTarget) { player in
            RestructureQuoteSheet(
                player: player,
                quote: restructureQuote(for: player),
                onConfirm: { applyRestructure(player) }
            )
        }
        .fullScreenCover(item: $negotiationTarget) { player in
            // ContractNegotiationView supplies its own "Close" toolbar item, so
            // the wrapper must NOT add a second one.
            NavigationStack {
                ContractNegotiationView(
                    player: player,
                    negotiationType: .payCut,
                    teamCapSpace: max(0, team?.availableCap ?? 0),
                    onPayCutAgreed: { newSalary, moraleDelta in
                        applyPayCut(player: player, newSalary: newSalary, moraleDelta: moraleDelta)
                    },
                    onReleaseDemanded: {
                        releaseDemandName = player.firstName
                    }
                )
            }
        }
    }

    // MARK: - Compliance Banner

    /// **"You are $X over."** The one sentence the whole screen exists to answer,
    /// stated in dollars rather than as a percentage — a GM fixes a number, not
    /// a ratio.
    private func complianceBanner(team: Team) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: isOverCap ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(isOverCap ? Color.danger : Color.success)
                    .font(.system(size: 15))
                Text(isOverCap ? "OVER THE CAP" : "Cap Compliant")
                    .font(.headline)
                    .foregroundStyle(isOverCap ? Color.danger : Color.success)
                Spacer()
                if !enforcesCap {
                    Text("SANDBOX")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(Color.textPrimary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.backgroundTertiary, in: Capsule())
                }
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.top, 14)
            .padding(.bottom, DSSpacing.sm)

            Divider().overlay(Color.surfaceBorder)

            VStack(spacing: DSSpacing.sm) {
                if isOverCap {
                    HStack(alignment: .firstTextBaseline, spacing: DSSpacing.xs) {
                        Text("You are")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                        Text(formatMillions(capOverage))
                            .font(.system(size: 34, weight: .black).monospacedDigit())
                            .foregroundStyle(Color.danger)
                        Text("over the salary cap")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                    }
                    Text(context == .weekAdvanceGate
                         ? "The league will not let you play another week until you are legal. Use the levers below."
                         : "You must be under the cap before free agency opens. Use the levers below.")
                        .font(.caption)
                        .foregroundStyle(Color.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Cap bar
                VStack(alignment: .leading, spacing: DSSpacing.xxs + 2) {
                    HStack {
                        Text("Cap Usage")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        let pct = team.salaryCap > 0 ? Double(team.currentCapUsage) / Double(team.salaryCap) : 0
                        Text(String(format: "%.1f%%", pct * 100))
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(isOverCap ? Color.danger : Color.success)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.backgroundTertiary)
                                .frame(height: 10)
                            let pct = team.salaryCap > 0 ? Double(team.currentCapUsage) / Double(team.salaryCap) : 0
                            RoundedRectangle(cornerRadius: 5)
                                .fill(isOverCap ? Color.danger : Color.success)
                                .frame(width: geo.size.width * min(pct, 1.0), height: 10)
                        }
                    }
                    .frame(height: 10)
                }

                HStack(spacing: 0) {
                    capStat(label: "Salary Cap", value: formatMillions(team.salaryCap), color: .accentGold)
                    capStat(label: "Used", value: formatMillions(team.currentCapUsage), color: isOverCap ? .danger : .textPrimary)
                    capStat(
                        label: isOverCap ? "Over By" : "Available",
                        value: formatMillions(isOverCap ? capOverage : team.availableCap),
                        color: isOverCap ? .danger : .success
                    )
                }
            }
            .padding(DSSpacing.md)
        }
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isOverCap ? Color.danger.opacity(0.5) : Color.surfaceBorder, lineWidth: isOverCap ? 2 : 1)
        )
    }

    private func capStat(label: String, value: String, color: Color) -> some View {
        VStack(spacing: DSSpacing.xxs) {
            Text(value)
                .font(.system(size: 18, weight: .bold).monospacedDigit())
                .foregroundStyle(color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Lever List

    /// One player, one row, three levers — ordered by the biggest number the club
    /// could actually free from him.
    ///
    /// Ranked by BEST AVAILABLE saving rather than by salary, which is the whole
    /// difference between a workspace and a roster list: the biggest contract on
    /// the books is frequently the worst one to touch, because a bonus-heavy deal
    /// can cost more to cut than to keep (`ReleaseCapSplit.capSavings` goes
    /// negative, and the row says so).
    private func leverListCard(team: Team) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(Color.accentGold)
                    .font(.system(size: 15))
                Text("Levers — Ranked by Cap Freed")
                    .font(.headline)
                    .foregroundStyle(Color.accentGold)
                Spacer()
                Text("\(rankedPlayers.count) players")
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.top, 14)
            .padding(.bottom, DSSpacing.sm)

            Divider().overlay(Color.surfaceBorder)

            if rankedPlayers.isEmpty {
                Text("No players under contract.")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                    .padding(DSSpacing.md)
            } else {
                ForEach(Array(rankedPlayers.enumerated()), id: \.element.id) { index, player in
                    leverRow(player: player)
                    if index < rankedPlayers.count - 1 {
                        Divider()
                            .overlay(Color.surfaceBorder.opacity(0.5))
                            .padding(.horizontal, DSSpacing.xs)
                    }
                }
            }
        }
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.surfaceBorder, lineWidth: 1))
    }

    private func leverRow(player: Player) -> some View {
        let split = releaseSplit(for: player)
        let quote = restructureQuote(for: player)

        return VStack(alignment: .leading, spacing: DSSpacing.xs) {
            // Identity + what he costs
            HStack(spacing: DSSpacing.xs) {
                Text(player.position.rawValue)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                    .frame(width: 28)
                    .padding(.vertical, 2)
                    .background(positionSideColor(player.position), in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))
                Text(player.fullName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text("\(player.overall)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(Color.forRating(player.overall))
                Text("Age \(player.age)")
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(formatMillions(player.annualSalary))/yr")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.textPrimary)
                    Text("\(player.contractYearsRemaining) yr\(player.contractYearsRemaining == 1 ? "" : "s") left")
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(player.contractYearsRemaining <= 1 ? Color.warning : Color.textTertiary)
                }
            }

            // The three levers, each labelled with its own honest number.
            HStack(spacing: DSSpacing.xs) {
                leverButton(
                    title: "Release",
                    headline: split.capSavings >= 0
                        ? "+\(formatMillions(split.capSavings))"
                        : formatMillions(split.capSavings),
                    footnote: "\(formatMillions(split.deadCap)) dead",
                    tint: split.capSavings > 0 ? Color.danger : Color.textTertiary,
                    enabled: true
                ) {
                    releaseTarget = player
                }

                leverButton(
                    title: "Restructure",
                    headline: quote.map { "+\(formatMillions($0.immediateRelief))" } ?? "—",
                    footnote: quote.map { "+\(formatMillions($0.proratedPerYear))/yr later" } ?? "Not available",
                    tint: quote != nil ? Color.accentGold : Color.textTertiary,
                    enabled: quote != nil
                ) {
                    restructureTarget = player
                }

                leverButton(
                    title: "Renegotiate",
                    headline: "Ask",
                    footnote: "His call",
                    tint: Color.accentBlue,
                    enabled: true
                ) {
                    negotiationTarget = player
                }
            }
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
    }

    private func leverButton(
        title: String,
        headline: String,
        footnote: String,
        tint: Color,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(enabled ? tint : Color.textTertiary)
                Text(headline)
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(enabled ? Color.textPrimary : Color.textTertiary)
                Text(footnote)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DSSpacing.xs)
            .background(
                (enabled ? tint : Color.textTertiary).opacity(enabled ? 0.10 : 0.05),
                in: RoundedRectangle(cornerRadius: DSCornerRadius.inline)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                    .strokeBorder((enabled ? tint : Color.surfaceBorder).opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: - Ranking

    /// Every man under contract, ordered by the biggest number he can free.
    private var rankedPlayers: [Player] {
        players
            .filter { $0.annualSalary > 0 }
            .sorted { lhs, rhs in
                let l = bestSaving(for: lhs)
                let r = bestSaving(for: rhs)
                if l != r { return l > r }
                return lhs.annualSalary > rhs.annualSalary
            }
    }

    /// The best this-year relief available from one player, across the levers
    /// that do not need his consent.
    ///
    /// The pay cut is deliberately excluded from the ranking: what it frees
    /// depends on a number the user has not chosen yet and on an answer the man
    /// has not given, and ranking on a figure nobody has agreed to would put the
    /// screen's most speculative lever at the top of its list.
    private func bestSaving(for player: Player) -> Int {
        let release = releaseSplit(for: player).capSavings
        let restructure = restructureQuote(for: player)?.immediateRelief ?? 0
        return max(release, restructure)
    }

    // MARK: - Engine Adapters
    //
    // The whole surface where this screen touches the cap engines, kept in one
    // block on purpose: if the engine's spelling moves, exactly these four
    // functions change and nothing else on the screen does.

    /// The share of the league year still unpaid, for the release split (#26).
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

    /// The club's cap ceiling — every engine call that prices a floor needs it.
    private var salaryCap: Int { team?.salaryCap ?? ContractEngine.openingSalaryCap }

    /// What a restructure would do to this man's cap charge, and why not when it
    /// cannot. The verdict carries its own refusal sentence, so the screen never
    /// invents a reason of its own.
    private func restructureVerdict(for player: Player) -> ContractEngine.RestructureVerdict {
        ContractEngine.restructureQuote(
            player: player,
            contract: contractsByPlayer[player.id],
            capMode: career.capMode,
            salaryCap: salaryCap
        )
    }

    private func restructureQuote(for player: Player) -> ContractEngine.RestructureQuote? {
        restructureVerdict(for: player).quote
    }

    // MARK: - Actions

    private func releasePlayer(_ player: Player) {
        guard let team else { return }
        // ONE authority (#68) — and cap-mode aware, which the old
        // `cutPlayerSimple` never was: a sandbox release must not credit a cap
        // it never charged.
        CapManagementEngine.applyRelease(
            player: player,
            team: team,
            contract: contractsByPlayer[player.id],
            capMode: career.capMode,
            leagueYearRemaining: leagueYearRemaining,
            careerID: career.id,
            modelContext: modelContext
        )
        releaseTarget = nil
        loadData()
    }

    private func applyRestructure(_ player: Player) {
        ContractEngine.executeRestructure(
            player: player,
            team: team,
            contract: contractsByPlayer[player.id],
            capMode: career.capMode,
            salaryCap: salaryCap
        )
        try? modelContext.save()
        restructureTarget = nil
        loadData()
    }

    /// Books an agreed pay cut through the one engine that books pay cuts.
    ///
    /// The chat owns the man's CONSENT and the persona-scaled morale number; the
    /// four-ledger write — team total, `annualSalary` (which the league-year
    /// true-up rebuilds from), the detailed row's current-year base, and the
    /// morale itself — is `ContractEngine.applyPayCut`'s. Doing any of it here
    /// would be a second place a pay cut is booked, which is the shape of bug
    /// #68 spent a wave closing.
    private func applyPayCut(player: Player, newSalary: Int, moraleDelta: Int) {
        ContractEngine.applyPayCut(
            player: player,
            team: team,
            contract: contractsByPlayer[player.id],
            capMode: career.capMode,
            salaryCap: salaryCap,
            newAnnualSalary: newSalary,
            moraleDelta: moraleDelta
        )
        try? modelContext.save()
        loadData()
    }

    // MARK: - Enter FA

    /// What committing does — or, when the gate is shut, exactly what is holding
    /// it shut and by how much (§2.12: a blocked commit swaps the rule to orange
    /// and states the reason).
    private var enterFAExplainer: DSActionBar.Explainer {
        guard enforcesCap else {
            return .init(
                title: "Sandbox \u{2014} no cap to clear",
                message: "Cap rules are off in this league. The market is open."
            )
        }
        if isOverCap {
            return .init(
                title: "The gate is shut",
                message: "You are **\(formatMillions(capOverage)) over** the cap. Release, restructure or renegotiate until you are legal.",
                isWarning: true
            )
        }
        let room = max(0, team?.availableCap ?? 0)
        return .init(
            title: "Open the market",
            message: "You are legal with **\(formatMillions(room))** of room. Free agency opens on **Day 1** and every outstanding offer will reserve part of it."
        )
    }

    // MARK: - Helpers

    private func positionSideColor(_ position: Position) -> Color {
        switch position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }

    private func formatMillions(_ thousands: Int) -> String {
        let millions = Double(thousands) / 1000.0
        if abs(millions) >= 1.0 {
            return String(format: "$%.1fM", millions)
        }
        return "$\(thousands)K"
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let teamID = career.teamID else { return }

        let teamDesc = FetchDescriptor<Team>(predicate: #Predicate { $0.id == teamID })
        team = try? modelContext.fetch(teamDesc).first

        guard let fetchedTeamID = team?.id else { return }
        var playerDesc = FetchDescriptor<Player>(
            predicate: #Predicate<Player> { $0.teamID == fetchedTeamID }
        )
        playerDesc.sortBy = [SortDescriptor(\.annualSalary, order: .reverse)]
        players = (try? modelContext.fetch(playerDesc)) ?? []

        let contractDesc = FetchDescriptor<Contract>(
            predicate: #Predicate<Contract> { $0.teamID == fetchedTeamID }
        )
        let contracts = (try? modelContext.fetch(contractDesc)) ?? []
        contractsByPlayer = Dictionary(contracts.map { ($0.playerID, $0) }, uniquingKeysWith: { first, _ in first })
    }
}

// MARK: - Restructure Quote Sheet

/// **The restructure, priced honestly.**
///
/// A restructure is the only lever on the workspace that costs nothing today and
/// everything later, which makes it the one the user will reach for first and
/// the one most likely to bury him. So the sheet is built around the SECOND
/// number: this year's relief is stated once, and the future-year charges it
/// creates are stated year by year underneath it. Nothing is hidden behind a
/// disclosure, because a charge the user has to tap to see is a charge he will
/// not see.
struct RestructureQuoteSheet: View {

    let player: Player
    let quote: ContractEngine.RestructureQuote?
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: DSSpacing.md) {
                        if let quote {
                            headerCard(quote: quote)
                            mechanicsCard(quote: quote)
                            futureCard(quote: quote)
                            confirmButton
                        } else {
                            Text("\(player.fullName)'s contract cannot be restructured. A restructure needs at least two years left on the deal and base salary above the veteran minimum to convert.")
                                .font(.subheadline)
                                .foregroundStyle(Color.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(DSSpacing.md)
                                .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    .padding(DSSpacing.lg)
                    .frame(maxWidth: DSLayout.contentMeasure)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Restructure")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
    }

    private func headerCard(quote: ContractEngine.RestructureQuote) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text(player.fullName)
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.textPrimary)
            Text("\(player.position.rawValue)  ·  \(player.overall) OVR  ·  \(quote.yearsRemaining) year\(quote.yearsRemaining == 1 ? "" : "s") remaining")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)

            Divider().overlay(Color.surfaceBorder).padding(.vertical, DSSpacing.xxs)

            HStack(alignment: .firstTextBaseline, spacing: DSSpacing.xs) {
                Text("Frees")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                Text(formatMillions(quote.immediateRelief))
                    .font(.system(size: 32, weight: .black).monospacedDigit())
                    .foregroundStyle(Color.success)
                Text("this year")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
            }
        }
        .padding(DSSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.surfaceBorder, lineWidth: 1))
    }

    private func mechanicsCard(quote: ContractEngine.RestructureQuote) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text("What Happens")
                .font(.headline)
                .foregroundStyle(Color.accentGold)
            row("Base salary converted", formatMillions(quote.convertedAmount), .textPrimary)
            row("Spread across", "\(quote.yearsRemaining) years", .textPrimary)
            row("New proration per year", formatMillions(quote.proratedPerYear), .textPrimary)
            Divider().overlay(Color.surfaceBorder)
            row("Cap hit before", formatMillions(quote.currentCapHit), .textSecondary)
            row("Cap hit after", formatMillions(quote.newCapHit), .success)
            Text("\(player.firstName) is paid exactly the same money — it just arrives as a signing bonus, and the cap charge for it is spread over the years left on the deal. He has no say in it, and it costs him nothing.")
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DSSpacing.xxs)
        }
        .padding(DSSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.surfaceBorder, lineWidth: 1))
    }

    /// **The bill.** Every future year this move adds to, and what a release
    /// would cost after it — the two things a restructure quietly makes worse.
    private func futureCard(quote: ContractEngine.RestructureQuote) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack(spacing: DSSpacing.xxs + 2) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(Color.warning)
                Text("What It Costs Later")
                    .font(.headline)
                    .foregroundStyle(Color.warning)
                Spacer()
            }

            // Year by year, not as one lump: `futureYearCapHit` is what he
            // costs in EACH remaining season afterwards, and a GM who only sees
            // a total will not feel the shape of it.
            if quote.yearsRemaining <= 1 {
                Text("No future years are affected.")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            } else {
                ForEach(1..<quote.yearsRemaining, id: \.self) { offset in
                    row(
                        "Year +\(offset)",
                        "\(formatMillions(quote.futureYearCapHit))  (+\(formatMillions(quote.proratedPerYear)))",
                        .warning
                    )
                }
            }

            Divider().overlay(Color.surfaceBorder)
            row(
                "Total added later",
                "+\(formatMillions(quote.proratedPerYear * max(0, quote.yearsRemaining - 1)))",
                .warning
            )
            row("Dead money if cut after", formatMillions(quote.deadMoneyAdded), .danger)

            Text("Restructuring buys room now by borrowing it from years you have not played yet, and it makes him more expensive to release. Use it on players you intend to keep.")
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DSSpacing.xxs)
        }
        .padding(DSSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.warning.opacity(0.3), lineWidth: 1))
    }

    private var confirmButton: some View {
        Button {
            onConfirm()
            dismiss()
        } label: {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "arrow.triangle.2.circlepath")
                Text("Restructure Contract")
                    .font(.headline)
            }
            .foregroundStyle(Color.backgroundPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.accentGold, in: RoundedRectangle(cornerRadius: DSCornerRadius.card))
        }
        .buttonStyle(.plain)
    }

    private func row(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
        }
    }

    private func formatMillions(_ thousands: Int) -> String {
        let millions = Double(thousands) / 1000.0
        if abs(millions) >= 1.0 {
            return String(format: "$%.1fM", millions)
        }
        return "$\(thousands)K"
    }
}
