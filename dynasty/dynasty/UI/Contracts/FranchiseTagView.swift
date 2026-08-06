import SwiftUI
import SwiftData

// MARK: - FranchiseTagView

struct FranchiseTagView: View {

    let career: Career

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var team: Team?
    @State private var teamPlayers: [Player] = []
    @State private var allPlayers: [Player] = []
    @State private var showSkipConfirmation = false

    /// The player whose agent is on the phone. Non-nil while the Contact Agent
    /// thread is open.
    @State private var negotiationPlayer: Player?

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            Group {
                if team != nil {
                    ScrollView {
                        VStack(spacing: 24) {
                            capBanner
                            tagRulesBanner
                            if !taggedPlayers.isEmpty {
                                taggedSection
                            }
                            expiringPlayersSection
                            skipTagButton
                        }
                        .padding(24)
                        .frame(maxWidth: DSLayout.contentMeasure)
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    ProgressView()
                        .tint(Color.accentGold)
                        .padding(.top, 80)
                }
            }
        }
        .navigationTitle("Franchise Tag")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            loadData()
        }
        .alert("Skip Franchise Tag?", isPresented: $showSkipConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Skip", role: .destructive) {
                CareerScopedDefaults.set(true, "franchiseTagVisited")
                dismiss()
            }
        } message: {
            Text("Are you sure? You won't be able to franchise tag any player this offseason.")
        }
        .fullScreenCover(item: $negotiationPlayer) { player in
            // ContractNegotiationView supplies its own "Close" toolbar item, so
            // the wrapper must NOT add a second one.
            NavigationStack {
                ContractNegotiationView(
                    player: player,
                    negotiationType: .extend,
                    teamCapSpace: max(0, team?.availableCap ?? 0),
                    onDealCompleted: { offer in
                        // Re-sign: the expiring deal is REPLACED, not extended.
                        // Through the engine so the club's cap ledger, the
                        // negotiated signing bonus and the detailed contract all
                        // move with the salary.
                        ContractEngine.applyNegotiatedDeal(
                            player: player,
                            team: team,
                            offer: offer,
                            application: .replaceContract,
                            capMode: career.capMode,
                            careerID: career.id,
                            modelContext: modelContext
                        )
                        // **The rollover's decrement, compensated for** — the
                        // same +1 `FinalPushView.applyReSignOffer` carries, and
                        // for the same reason. This screen runs in Review
                        // Roster, i.e. BEFORE `executeNewLeagueYear`, whose
                        // expiry loop decrements every contract in the league.
                        // `applyNegotiatedDeal(.replaceContract)` writes
                        // `contractYearsRemaining = offer.years`, so a deal
                        // agreed here was silently one year short and a 1-year
                        // re-sign expired the instant the league year turned —
                        // the man appeared as LOST on the very next screen,
                        // thirty seconds after being kept. (`FinalPushView`'s
                        // note lists this screen as an in-season path where "no
                        // rollover follows"; it is not one.)
                        //
                        // Conditional on the rollover still being PENDING, using
                        // the same test `WeekAdvancer` gates its own fallback
                        // with, so a screen re-entered after March cannot hand
                        // out a free extra year.
                        if career.lastRolloverSeason < career.currentSeason {
                            player.contractYearsRemaining += 1
                        }
                        try? modelContext.save()
                        loadData()
                        // No dismiss — the thread shows the signed card and the
                        // user closes it with Done.
                    }
                )
            }
        }
    }

    // MARK: - Cap Banner

    /// **The banner shows NEXT league year, because that is the year the tag is
    /// a decision about** (#127).
    ///
    /// It used to show "Available Cap Space" — this year's room — and the tag
    /// used to move it, which is how the bug announced itself: tagging a $36.9M
    /// quarterback at $32.8M *raised* the number by $4.0M. Both halves are now
    /// fixed, and the cheapest way to make the fix legible is to stop quoting a
    /// year the decision cannot touch. The tag charges the league year that opens
    /// in March; so does everything else on this screen.
    ///
    /// The three numbers are the ones a GM actually plans against, and each is
    /// read from the source the rest of the app already uses:
    ///
    /// * **Projected cap** — `salaryCap × (1 + capGrowthPerSeason)`, the engine's
    ///   own midpoint roll. Same one line `RosterEvaluationView`'s Next Season
    ///   Outlook, `CapOverviewView`'s year bars and the dashboard's 3-Year Cap
    ///   tile use, so no two screens can show the user two different futures
    ///   (task #87 / F15 closed exactly that split once already).
    /// * **Committed** — contracts that are still running next year
    ///   (`contractYearsRemaining > 1`) plus tags already applied. A man on an
    ///   expiring deal is deliberately NOT in it: if he is not re-signed he costs
    ///   nothing, and that is the whole question this screen asks.
    /// * **Projected space** — the difference, and the number "Cap after tag" on
    ///   every row is measured against.
    private var capBanner: some View {
        VStack(spacing: 10) {
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Projected \(seasonLabel(nextSeason)) Cap")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                    Text(formatMillions(projectedNextYearCap))
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.accentGold)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Committed to \(seasonLabel(nextSeason))")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                    Text(formatMillions(committedNextYear))
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.textPrimary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Projected Space")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                    Text(formatMillions(projectedNextYearSpace))
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(projectedNextYearSpace >= 0 ? Color.success : Color.danger)
                }
            }

            Divider().overlay(Color.surfaceBorder.opacity(0.6))

            // The current year is kept, small and explicitly labelled, because a
            // GM still wants to know where he stands today — but it is no longer
            // the headline and, more to the point, tagging no longer moves it.
            HStack(spacing: 8) {
                Text("\(seasonLabel(career.currentSeason)) cap space")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textTertiary)
                Text(formatMillions(team?.availableCap ?? 0))
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle((team?.availableCap ?? 0) >= 0 ? Color.textSecondary : Color.danger)
                Text("— unchanged by tagging")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textTertiary)
                Spacer()
                Text("\(expiringPlayers.count) expiring")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(Color.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.surfaceBorder, lineWidth: 1)
        )
    }

    // MARK: - Next League Year Projection (#127)

    /// The league year a tag applied on this screen charges.
    ///
    /// `currentSeason + 1` and not `currentSeason`: `WeekAdvancer` only
    /// increments the year at the roster-cuts → regular-season transition, so
    /// every offseason phase of a given league year reads the same number, and
    /// the year being decided is always the one after it. Same arithmetic
    /// `RosterEvaluationView` labels its "Next Season Outlook" with.
    private var nextSeason: Int { career.currentSeason + 1 }

    /// The club's cap rolled forward one league year at the engine's own growth
    /// midpoint — one formula, shared with every other projection in the app.
    private var projectedNextYearCap: Int {
        let cap = team?.salaryCap ?? ContractEngine.openingSalaryCap
        return Int(Double(cap) * (1.0 + ContractEngine.capGrowthPerSeason))
    }

    /// Salary already owed for next league year, in thousands.
    ///
    /// `contractYearsRemaining > 1` is "still under contract after this year's
    /// rollover" — the same test `ContractTimelineView` and `CapOverviewView`
    /// project a future year's committed cap with. Tagged men are excluded from
    /// the sum and added back through the forward ledger instead, so the tag is
    /// counted at the number the user was quoted rather than at the salary his
    /// expiring deal happens to still be carrying.
    private var committedNextYear: Int {
        let underContract = teamPlayers
            .filter { $0.contractYearsRemaining > 1 && !$0.isFranchiseTagged }
            .reduce(0) { $0 + $1.annualSalary }
        // Walked from the ROSTER rather than summed straight off the ledger, so
        // a man who was tagged and then released still owes nothing here. His
        // orphaned row survives until the rollover drops it (`consumeForward`
        // takes everything due, matched or not), and reading the ledger blind
        // would keep charging the club for a player it no longer employs.
        let tags = taggedPlayers.reduce(0) { $0 + tagCommitment(for: $1) }
        return underContract + tags
    }

    private var projectedNextYearSpace: Int { projectedNextYearCap - committedNextYear }

    /// `2027`, never `2 027` — a league year is a name, not a quantity, so it
    /// must not pick up the locale's group separator.
    private func seasonLabel(_ season: Int) -> String { String(season) }

    // MARK: - Rules Banner

    private var tagRulesBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Color.accentGold)
            VStack(alignment: .leading, spacing: 2) {
                Text("Franchise Tag Rules")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text("You can apply up to 1 franchise tag per season. A tagged player finishes his current deal, then plays \(seasonLabel(nextSeason)) at the average of the top 5 salaries at his position — so the tag charges the \(seasonLabel(nextSeason)) cap, not this year's.")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Color.accentGold.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentGold.opacity(0.3), lineWidth: 1))
    }

    // MARK: - Tagged Players Section

    private var taggedSection: some View {
        sectionCard(title: "Tagged Players", icon: "tag.fill") {
            VStack(spacing: 0) {
                ForEach(Array(taggedPlayers.enumerated()), id: \.element.id) { index, player in
                    taggedPlayerRow(player)
                    if index < taggedPlayers.count - 1 {
                        Divider()
                            .overlay(Color.surfaceBorder.opacity(0.5))
                            .padding(.horizontal, 8)
                    }
                }
            }
        }
    }

    private func taggedPlayerRow(_ player: Player) -> some View {
        HStack(spacing: 12) {
            positionBadge(player.position)

            VStack(alignment: .leading, spacing: 2) {
                Text(player.fullName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text("Age \(player.age)")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                    Text("\(player.overall) OVR")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.forRating(player.overall))
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                // #127: `annualSalary` is still the EXPIRING deal — the tag has
                // not been paid yet and does not overwrite it until the rollover
                // — so the number quoted here comes off the forward commitment
                // the tag actually booked. Showing `annualSalary` would now
                // print the old contract under the words "Tag Value".
                Text(formatMillions(tagCommitment(for: player)))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.accentGold)
                Text("\(seasonLabel(nextSeason)) Tag")
                    .font(.system(size: 9).weight(.medium))
                    .foregroundStyle(Color.textTertiary)
            }

            Button {
                removeTag(from: player)
            } label: {
                Text("Remove")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.danger)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.danger.opacity(0.15), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.danger.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Expiring Players Section

    private var expiringPlayersSection: some View {
        sectionCard(title: "Expiring Contracts (\(expiringPlayers.count) players)", icon: "clock.badge.exclamationmark") {
            if expiringPlayers.isEmpty {
                emptyStateRow("No players with expiring contracts.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(expiringPlayers.enumerated()), id: \.element.id) { index, player in
                        expiringPlayerRow(player)
                        if index < expiringPlayers.count - 1 {
                            Divider()
                                .overlay(Color.surfaceBorder.opacity(0.5))
                                .padding(.horizontal, 8)
                        }
                    }
                }
            }
        }
    }

    private func expiringPlayerRow(_ player: Player) -> some View {
        let tagCost = tagValue(for: player.position)
        // #127. This used to be `availableCap − tagCost + annualSalary`: next
        // year's tag netted against this year's room, with this year's salary
        // credited back as though the season already played were about to be
        // refunded. Every term was from the wrong year. The tag charges
        // `nextSeason`, where the man's expiring deal is already worth nothing —
        // so the honest answer is simply projected space less the tag.
        let capAfterTag = projectedNextYearSpace - tagCost
        let recommendation = smartRecommendation(for: player)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                positionBadge(player.position)

                VStack(alignment: .leading, spacing: 2) {
                    Text(player.fullName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Text("Age \(player.age)")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                        Text("\(player.overall) OVR")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.forRating(player.overall))
                        Text(formatMillions(player.annualSalary) + "/yr")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Color.textTertiary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatMillions(tagCost))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color.accentGold)
                    Text("Tag Cost")
                        .font(.system(size: 9).weight(.medium))
                        .foregroundStyle(Color.textTertiary)
                }

                if hasUsedTag {
                    // Already used the tag — show disabled state
                    Text("Tag Used")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textTertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.backgroundTertiary, in: Capsule())
                } else {
                    Button {
                        applyTag(to: player, tagCost: tagCost)
                    } label: {
                        Text("Apply Tag")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.backgroundPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.accentGold, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            // Recommendation
            HStack(spacing: 6) {
                Image(systemName: recommendation.icon)
                    .font(.caption)
                    .foregroundStyle(recommendation.color)
                Text(recommendation.text)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 46)

            // Cap impact
            HStack(spacing: 6) {
                Image(systemName: "dollarsign.circle")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                Text("\(seasonLabel(nextSeason)) space after tag: \(formatMillions(capAfterTag))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(capAfterTag >= 0 ? Color.textTertiary : Color.danger)
                if capAfterTag < 0 {
                    Text("OVER CAP")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.danger)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.danger.opacity(0.15), in: Capsule())
                }
            }
            .padding(.leading, 46)

            // The alternative to the tag is a conversation, so it belongs on the
            // same row as the tag. Identical wording and behaviour to every other
            // Contact Agent button in the app — it never says whether this camp
            // will actually talk.
            contactAgentButton(for: player)
                .padding(.leading, 46)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Contact Agent Entry

    private func contactAgentButton(for player: Player) -> some View {
        let badge = ContactAgentEntry.badge(for: player, season: career.currentSeason)
        return Button {
            negotiationPlayer = player
        } label: {
            HStack(spacing: 6) {
                Image(systemName: ContactAgentEntry.icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(ContactAgentEntry.title)
                    .font(.caption.weight(.semibold))
                if let badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentBlue.opacity(0.18), in: Capsule())
                }
            }
            .foregroundStyle(Color.accentBlue)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.accentBlue.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.accentBlue.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Contact \(player.fullName)'s agent")
    }

    // MARK: - Smart Recommendations

    private struct Recommendation {
        let text: String
        let icon: String
        let color: Color
    }

    private func smartRecommendation(for player: Player) -> Recommendation {
        let isPastPeak = player.age > player.position.peakAgeRange.upperBound

        if player.overall >= 85 {
            return Recommendation(
                text: "Elite player — strongly consider tagging.",
                icon: "star.fill",
                color: .accentGold
            )
        } else if isPastPeak {
            return Recommendation(
                text: "Aging veteran at \(player.age) — tag cost may not be worth it.",
                icon: "exclamationmark.triangle.fill",
                color: .warning
            )
        } else if player.overall < 75 {
            return Recommendation(
                text: "Role player — better to let walk and address in free agency.",
                icon: "arrow.right.circle.fill",
                color: .textTertiary
            )
        } else {
            return Recommendation(
                text: "Solid contributor — tag if you can't afford to lose him.",
                icon: "checkmark.circle.fill",
                color: .success
            )
        }
    }

    // MARK: - Section Card Shell

    private func sectionCard<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(Color.accentGold)
                    .font(.system(size: 15))
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.accentGold)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.accentGold.opacity(0.08))

            Divider().overlay(Color.surfaceBorder)

            content()
                .padding(.vertical, 8)
        }
        .cardBackground()
    }

    private func emptyStateRow(_ text: String) -> some View {
        CompactEmptyStateView(icon: "tray", message: text)
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
    }

    // MARK: - Skip Tag Button

    @ViewBuilder
    private var skipTagButton: some View {
        if hasUsedTag {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.success)
                Text("Franchise tag applied")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.surfaceBorder, lineWidth: 1)
            )
        } else {
            Button {
                showSkipConfirmation = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "forward.fill")
                        .font(.caption)
                    Text("Skip — No Tag This Year")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Computed Properties

    /// Players on the user's team with expiring contracts (not already tagged).
    private var expiringPlayers: [Player] {
        teamPlayers
            .filter { $0.contractYearsRemaining <= 1 && !$0.isFranchiseTagged }
            .sorted { $0.overall > $1.overall }
    }

    /// Players currently franchise-tagged on the user's team.
    private var taggedPlayers: [Player] {
        teamPlayers.filter { $0.isFranchiseTagged }
    }

    /// Whether the team has already used their franchise tag this season.
    private var hasUsedTag: Bool {
        !taggedPlayers.isEmpty
    }

    // MARK: - Tag Value Calculation

    /// What the tag on this man actually costs next year — the number
    /// `ContractEngine.applyFranchiseTag` booked, falling back to a fresh quote
    /// for a save whose tag predates the forward ledger.
    private func tagCommitment(for player: Player) -> Int {
        CommittedCapLedger.forwardCommitment(playerID: player.id, careerID: career.id)?.annualCapHit
            ?? tagValue(for: player.position)
    }

    private func tagValue(for position: Position) -> Int {
        let positionSalaries = allPlayers
            .filter { $0.position == position && $0.annualSalary > 0 }
            .map { $0.annualSalary }
        // Task #87 / F16: the `capMode:` overload (this screen used to charge a
        // sandbox save a real tag) and the shared cap-relative floor.
        return ContractEngine.franchiseTagValue(
            position: position,
            topSalaries: positionSalaries,
            capMode: career.capMode,
            salaryCap: team?.salaryCap ?? ContractEngine.openingSalaryCap
        )
    }

    // MARK: - Actions

    private func applyTag(to player: Player, tagCost: Int) {
        guard let team, !hasUsedTag else { return }

        ContractEngine.applyFranchiseTag(
            player: player,
            tagValue: tagCost,
            team: team,
            capMode: career.capMode,
            bindingSeason: nextSeason,
            careerID: career.id
        )

        // Persist so CareerShellView picks up the change
        try? modelContext.save()
        CareerScopedDefaults.set(true, "franchiseTagVisited")

        // Refresh local state
        loadData()
    }

    private func removeTag(from player: Player) {
        guard let team else { return }

        ContractEngine.removeFranchiseTag(
            player: player,
            team: team,
            capMode: career.capMode,
            careerID: career.id
        )

        // Persist so CareerShellView picks up the change
        try? modelContext.save()

        // Refresh local state
        loadData()
    }

    // MARK: - Helpers

    private func positionBadge(_ position: Position) -> some View {
        Text(position.rawValue)
            .font(.caption.weight(.bold))
            .foregroundStyle(Color.textPrimary)
            .frame(width: 34)
            .padding(.vertical, 4)
            .background(positionSideColor(position), in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))
    }

    private func positionSideColor(_ position: Position) -> Color {
        switch position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }

    private func formatMillions(_ thousands: Int) -> String {
        let millions = Double(thousands) / 1000.0
        if millions >= 1.0 {
            return String(format: "$%.1fM", millions)
        } else {
            return "$\(thousands)K"
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let teamID = career.teamID else { return }

        let teamDesc = FetchDescriptor<Team>(predicate: #Predicate { $0.id == teamID })
        team = try? modelContext.fetch(teamDesc).first

        guard let fetchedTeamID = team?.id else { return }
        var playerDesc = FetchDescriptor<Player>(
            predicate: #Predicate { $0.teamID == fetchedTeamID }
        )
        playerDesc.sortBy = [SortDescriptor(\.annualSalary, order: .reverse)]
        teamPlayers = (try? modelContext.fetch(playerDesc)) ?? []

        // Fetch all players league-wide for tag value calculation
        let cid = career.id
        let allDesc = FetchDescriptor<Player>(predicate: #Predicate { $0.careerID == cid })
        allPlayers = (try? modelContext.fetch(allDesc)) ?? []
    }
}

// MARK: - Preview

#Preview {
    let career = Career(playerName: "Sam Greer", role: .gm, capMode: .simple)
    NavigationStack {
        FranchiseTagView(career: career)
    }
    .modelContainer(for: [Career.self, Team.self, Player.self], inMemory: true)
}
