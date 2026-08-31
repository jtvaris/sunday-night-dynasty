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

    /// Which tag's arithmetic is open, if any.
    ///
    /// One piece of state at BODY level driving one `.sheet(item:)`, and
    /// deliberately not a `.popover(isPresented:)` hung off each row: eight rows
    /// in a `ForEach` sharing a single `@State` anchor the popover to whichever
    /// row SwiftUI laid out last, not to the one that was tapped. The request
    /// carries the whole quote (see `TagBreakdownRequest`), so the presented
    /// sheet has no nil case to render.
    @State private var tagBreakdown: TagBreakdownRequest?

    /// Every position this screen has to price, quoted once per load — see
    /// `buildTagQuotes`.
    @State private var tagQuotes: [Position: TagQuote] = [:]

    /// `Team.id` -> abbreviation, so the breakdown can say who the five men on
    /// it play for. Fetched with the rest of the screen's data, once.
    @State private var teamAbbreviations: [UUID: String] = [:]

    /// What each position's tag cost the LAST time this screen was opened —
    /// read from `CareerScopedDefaults` at the top of the first load and then
    /// left alone for the rest of the visit. See `captureTagPriceBaseline`.
    @State private var previousQuotes: [Position: TagPriceMemory.Quote] = [:]

    /// One baseline per visit, not one per `loadData`.
    @State private var baselineCaptured = false

    /// The tag the user has asked for and not yet agreed to.
    ///
    /// A tag is the least reversible thing on this screen — one per
    /// offseason, and it books next season's cap the moment it lands — and it
    /// used to commit on the first tap of a gold pill that sat on every row.
    /// `UI_REDESIGN_VISION.md` §"Irreversibility always confirms" names this
    /// screen by example.
    @State private var pendingTag: PendingTag?
    @State private var showTagConfirmation = false

    /// The terms of the tag being confirmed, captured at the tap so the sheet
    /// cannot quote a price that has since been recomputed.
    private struct PendingTag {
        let player: Player
        /// Which of the two tags. Both are irreversible and they cost different
        /// money, so the confirmation has to know which one it is describing.
        let kind: TagKind
        let tagCost: Int
    }

    /// **The transition tags this club holds**, read from `TransitionTagLedger`
    /// on every load — the tag sets no flag on `Player` (see that type's note),
    /// so this table is the only thing that knows.
    @State private var transitionTags: [TransitionTagLedger.Tag] = []

    /// The answer the user has chosen and not yet confirmed.
    private struct PendingAnswer {
        let row: TransitionTagLedger.Tag
        let answer: TransitionTagLedger.Answer
    }

    @State private var pendingAnswer: PendingAnswer?
    @State private var showAnswerConfirmation = false

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            Group {
                if team != nil {
                    ScrollView {
                        VStack(spacing: 24) {
                            capBanner
                            outstandingDecisionBanner
                            tagRulesBanner
                            if !taggedPlayers.isEmpty || !liveTransitionTags.isEmpty {
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
        // The screen spends one tag and there are two of them, so it is no
        // longer "Franchise Tag". The task that routes here is still called
        // Franchise Tag Decisions — that string lives in another lane's file and
        // is listed in `followUp`.
        .navigationTitle("Tag Decisions")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            loadData()
        }
        .alert("Skip Your Tag?", isPresented: $showSkipConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Skip", role: .destructive) {
                CareerScopedDefaults.set(true, "franchiseTagVisited")
                dismiss()
            }
        } message: {
            Text("Are you sure? You won't be able to franchise or transition tag any player this offseason.")
        }
        .alert("\(pendingTag?.kind.title ?? "Franchise") tag \(pendingTag?.player.fullName ?? "this player")?", isPresented: $showTagConfirmation, presenting: pendingTag) { pending in
            Button("Cancel", role: .cancel) { pendingTag = nil }
            Button("Apply Tag") {
                applyTag(to: pending.player, kind: pending.kind, tagCost: pending.tagCost)
                pendingTag = nil
            }
        } message: { pending in
            Text(tagConfirmationTerms(for: pending))
        }
        .alert(answerConfirmationTitle, isPresented: $showAnswerConfirmation, presenting: pendingAnswer) { pending in
            Button("Cancel", role: .cancel) { pendingAnswer = nil }
            // Two buttons rather than one with a computed role: only the
            // decline is destructive, and letting him go is exactly the kind of
            // thing that should be wearing the destructive colour.
            if pending.answer == .matched {
                Button("Match It") {
                    answerOfferSheet(pending)
                    pendingAnswer = nil
                }
            } else {
                Button("Let Him Go", role: .destructive) {
                    answerOfferSheet(pending)
                    pendingAnswer = nil
                }
            }
        } message: { pending in
            Text(answerConfirmationTerms(for: pending))
        }
        .sheet(item: $tagBreakdown) { request in
            TagBreakdownSheet(request: request, tagSeasonLabel: seasonLabel(nextSeason))
        }
        .fullScreenCover(item: $negotiationPlayer) { player in
            // ContractNegotiationView supplies its own "Close" toolbar item, so
            // the wrapper must NOT add a second one.
            NavigationStack {
                ContractNegotiationView(
                    player: player,
                    negotiationType: .extend,
                    teamCapSpace: max(0, team?.availableCap ?? 0),
                    // #186 — the gate must plan the deal this screen BOOKS. It
                    // replaces an expiring contract (see `onDealCompleted`
                    // below), so the money starts in the league year that is
                    // open; the default `.extendExisting` would have read the
                    // expiring man's last year as "one more year to wait" and
                    // quoted him against next season's projected cap.
                    dealApplication: .replaceContract,
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
                Text("\u{2022}")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textTertiary)
                // The tag is a one-shot, and the only place that said so was a
                // sentence buried in the grey rules paragraph — while eight rows
                // each offered a gold Apply Tag. The count of the resource
                // belongs next to the count of men it has to be spent on.
                Text(hasUsedTag ? "0 tags left" : "1 tag available")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(hasUsedTag ? Color.textTertiary : Color.accentGold)
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
        let transitionIDs = Set(liveTransitionTags.map(\.playerID))
        let underContract = teamPlayers
            .filter { $0.contractYearsRemaining > 1 && !$0.isFranchiseTagged && !transitionIDs.contains($0.id) }
            .reduce(0) { $0 + $1.annualSalary }
        // Walked from the ROSTER rather than summed straight off the ledger, so
        // a man who was tagged and then released still owes nothing here. His
        // orphaned row survives until the rollover drops it (`consumeForward`
        // takes everything due, matched or not), and reading the ledger blind
        // would keep charging the club for a player it no longer employs.
        let tags = taggedPlayers.reduce(0) { $0 + tagCommitment(for: $1) }
        // The transition tag is counted at exactly what
        // `FreeAgencyEngine.settleTransitionTags` would charge if the league year
        // opened right now: the tender where no sheet has been filed, the
        // MATCHED sheet's salary where one has been matched, and nothing at all
        // where a sheet stands unmatched — including one the user has not
        // answered, because an unanswered sheet settles as a decline. The row on
        // the screen says so in words; the banner must not quietly assume he is
        // being kept.
        let transition = liveTransitionTags.reduce(0) { $0 + ($1.isRetained ? $1.retainedSalary : 0) }
        return underContract + tags + transition
    }

    private var projectedNextYearSpace: Int { projectedNextYearCap - committedNextYear }

    /// `2027`, never `2 027` — a league year is a name, not a quantity, so it
    /// must not pick up the locale's group separator.
    private func seasonLabel(_ season: Int) -> String { String(season) }

    // MARK: - The Outstanding Decision

    /// **How the match-or-lose decision reaches the user.**
    ///
    /// A banner at the top of the screen, above the rules and above every row,
    /// and deliberately NOT an alert. The sheet is filed inside `applyTag`,
    /// which itself runs from the tag confirmation's button — and an alert
    /// raised while another alert is still dismissing is the one that silently
    /// never appears. A banner cannot fail to present, survives the user
    /// leaving and coming back, and is still there on the next visit if he
    /// walked away without answering.
    ///
    /// It states the deadline because the deadline is the whole of the danger:
    /// the rollover settles an unanswered sheet as a decline. The buttons are
    /// on the man's row rather than here, so answering always happens next to
    /// the terms being answered.
    @ViewBuilder
    private var outstandingDecisionBanner: some View {
        let outstanding = liveTransitionTags.filter(\.isDecisionOutstanding)
        if !outstanding.isEmpty {
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                ForEach(outstanding) { row in
                    HStack(alignment: .top, spacing: DSSpacing.xxs) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.warning)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(row.offer?.teamAbbreviation ?? "A rival club") have filed an offer sheet on \(row.playerName)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Match those terms on his row below, or let him go. If you do neither before the \(seasonLabel(nextSeason)) league year opens, he leaves and you get nothing.")
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DSSpacing.sm)
            .background(Color.warning.opacity(0.10), in: RoundedRectangle(cornerRadius: DSCornerRadius.inline))
            .overlay(
                RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                    .strokeBorder(Color.warning.opacity(0.4), lineWidth: 1)
            )
        }
    }

    // MARK: - Rules Banner

    /// The banner carries BOTH options' league year, not just the tag's.
    ///
    /// The row offers a tag and a Contact Agent thread side by side, and the two
    /// land in different years: the tag is a forward commitment against
    /// `nextSeason` and leaves today's room alone, while a re-sign agreed here
    /// REPLACES the expiring deal on the spot (the `.replaceContract` gate at the
    /// top of this file) and so charges the open year first. The screen used to
    /// state only the tag's year, which left the user comparing a `nextSeason`
    /// price against a conversation that quotes him this year's — and never said
    /// what keeping the man does to the projected space the tag is being weighed
    /// against. It is said once here rather than on every row, and deliberately
    /// without a price: what the agent will ASK is what Contact Agent is for
    /// (#127).
    private var tagRulesBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Color.accentGold)
            VStack(alignment: .leading, spacing: 2) {
                Text("Tag Rules")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text("You have one tag per offseason and two ways to spend it. Either way the man finishes his current deal and then plays \(seasonLabel(nextSeason)) on the tag, so it charges the \(seasonLabel(nextSeason)) cap and not this year's.\n\nFRANCHISE — the average of the top \(ContractEngine.franchiseTagPoolSize) salaries at his position. Nobody else may sign him.\n\nTRANSITION — the average of the top \(ContractEngine.transitionTagPoolSize), which is the same list read deeper and so never dearer. It buys you the right to MATCH, not the right to refuse: a rival club may put a contract in front of him, and you either take on those exact terms or lose him for nothing.\n\nRe-signing a man through Contact Agent instead replaces his expiring deal on the spot: it charges your \(seasonLabel(career.currentSeason)) space the moment he signs, and commits \(seasonLabel(nextSeason)) on top.")
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
                    if index < taggedPlayers.count - 1 || !liveTransitionTags.isEmpty {
                        Divider()
                            .overlay(Color.surfaceBorder.opacity(0.5))
                            .padding(.horizontal, 8)
                    }
                }
                ForEach(Array(liveTransitionTags.enumerated()), id: \.element.id) { index, row in
                    transitionTaggedRow(row)
                    if index < liveTransitionTags.count - 1 {
                        Divider()
                            .overlay(Color.surfaceBorder.opacity(0.5))
                            .padding(.horizontal, 8)
                    }
                }
            }
        }
    }

    // MARK: - The Transition Row, and the decision on it

    /// **Where the match-or-lose decision lives.**
    ///
    /// It is on the row rather than behind a notification because the row is the
    /// only thing on this screen that survives the user walking away and coming
    /// back — and an unanswered sheet settles as a decline, so the decision has
    /// to still be there when he returns. ``outstandingDecisionBanner`` points
    /// at it from the top of the screen; the answering happens here, beside the
    /// terms being answered.
    ///
    /// Five states, and the row says which one it is in:
    ///
    /// * **Not yet canvassed.** The league has not looked at him.
    /// * **Nobody came.** The tender stands; he plays next league year on it.
    /// * **A sheet is on the table.** Both prices, both consequences, two
    ///   buttons, and the deadline stated — the new league year.
    /// * **Matched.** The club took the sheet's terms; the row prints them.
    /// * **Declined.** He leaves at the rollover and the club gets nothing.
    @ViewBuilder
    private func transitionTaggedRow(_ row: TransitionTagLedger.Tag) -> some View {
        let player = teamPlayers.first { $0.id == row.playerID }

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                if let position = row.position {
                    positionBadge(position)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(row.playerName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Text("TRANSITION")
                            .font(.system(size: DSType.Size.micro, weight: .bold))
                            .foregroundStyle(Color.accentBlue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentBlue.opacity(0.18), in: Capsule())
                        if let player {
                            Text("Age \(player.age)")
                                .font(.caption)
                                .foregroundStyle(Color.textTertiary)
                            Text("\(player.overall) OVR")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.forRating(player.overall))
                        }
                    }
                }

                Spacer()

                Button {
                    if let player { tagBreakdown = tagBreakdownRequest(for: player, booked: row.price, bookedKind: .transition) }
                } label: {
                    VStack(alignment: .trailing, spacing: 2) {
                        infoCaption("\(seasonLabel(nextSeason)) Tender")
                        Text(formatMillions(row.price))
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Color.accentGold)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(seasonLabel(nextSeason)) transition tender \(formatMillions(row.price)) for \(row.playerName)")
                .accessibilityHint("Shows the salaries the tender averages")

                // Remove is offered only while nothing is outstanding. With a
                // sheet on the table the way out is Let Him Go, which costs the
                // club exactly what withdrawing the tag would — the man — and
                // says so, where a quiet Remove would not.
                if !row.isDecisionOutstanding {
                    removePill { if let player { removeTransitionTag(from: player) } }
                }
            }

            offerSheetPanel(row)
                .padding(.leading, 46)

            if let player {
                contactAgentButton(for: player)
                    .padding(.leading, 46)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func offerSheetPanel(_ row: TransitionTagLedger.Tag) -> some View {
        if let offer = row.offer {
            let total = offer.annualSalary * max(1, offer.years)
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                HStack(spacing: DSSpacing.xxs) {
                    Image(systemName: "envelope.badge.fill")
                        .font(.caption)
                        .foregroundStyle(row.answer == nil ? Color.warning : Color.textTertiary)
                    Text("\(offer.teamAbbreviation) offer sheet — \(formatMillions(offer.annualSalary))/yr for \(offer.years) \(offer.years == 1 ? "year" : "years") (\(formatMillions(total)) total)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if row.answer == .matched {
                    Text("Matched. He stays on \(offer.teamAbbreviation)'s terms: \(formatMillions(offer.annualSalary)) a year for \(offer.years), starting \(seasonLabel(nextSeason)). The tender no longer applies.")
                        .font(.caption)
                        .foregroundStyle(Color.success)
                        .fixedSize(horizontal: false, vertical: true)
                } else if row.answer == .declined {
                    Text("Not matched. He signs with \(offer.teamAbbreviation) when the \(seasonLabel(nextSeason)) league year opens, and you get nothing back for him.")
                        .font(.caption)
                        .foregroundStyle(Color.danger)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Match it and you owe \(formatMillions(offer.annualSalary)) a year for \(offer.years) instead of \(formatMillions(row.price)) for one. Decline and he is \(offer.teamAbbreviation)'s for nothing. Answer before the \(seasonLabel(nextSeason)) league year opens — no answer is a decline.")
                        .font(.caption)
                        .foregroundStyle(Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: DSSpacing.xs) {
                        tagPill(title: "Match Offer", filled: true, tint: Color.accentGold) {
                            pendingAnswer = PendingAnswer(row: row, answer: .matched)
                            showAnswerConfirmation = true
                        }
                        tagPill(title: "Let Him Go", filled: false, tint: Color.danger) {
                            pendingAnswer = PendingAnswer(row: row, answer: .declined)
                            showAnswerConfirmation = true
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DSSpacing.sm)
            .background(
                (row.answer == nil ? Color.warning : Color.backgroundSecondary).opacity(row.answer == nil ? 0.08 : 0.6),
                in: RoundedRectangle(cornerRadius: DSCornerRadius.inline)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                    .strokeBorder(
                        row.answer == nil ? Color.warning.opacity(0.3) : Color.surfaceBorder,
                        lineWidth: 1
                    )
            )
        } else if row.canvassed {
            HStack(spacing: DSSpacing.xxs) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.caption)
                    .foregroundStyle(Color.success)
                Text("No club filed an offer sheet. He plays \(seasonLabel(nextSeason)) on the tender.")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            HStack(spacing: DSSpacing.xxs) {
                Image(systemName: "clock")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                Text("The league has not looked at him yet.")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func taggedPlayerRow(_ player: Player) -> some View {
        // Read once for the row. `tagCommitment` decodes the forward ledger out
        // of `UserDefaults`, and the row now shows the number, speaks it and
        // hands it to the sheet — three reads of a JSON table on a screen that
        // redraws on a timer, where one will do.
        let booked = tagCommitment(for: player)

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
                        // The deal the tag is an alternative to. Every expiring
                        // row states it; the tagged man's row did not, so his
                        // tag figure had nothing on the row to be read against.
                        Text(formatMillions(player.annualSalary) + "/yr")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Color.textTertiary)
                    }
                }

                Spacer()

                // The booked tag opens the same breakdown the expiring rows do,
                // carrying its booked number with it. It is the one figure on
                // the screen that does NOT move with the market — the club
                // agreed a price and owns it — and the sheet is the only place
                // that can say so next to the salaries that have moved since.
                Button {
                    tagBreakdown = tagBreakdownRequest(for: player, booked: booked, bookedKind: .franchise)
                } label: {
                    VStack(alignment: .trailing, spacing: 2) {
                        // #127: `annualSalary` is still the EXPIRING deal — the tag has
                        // not been paid yet and does not overwrite it until the rollover
                        // — so the number quoted here comes off the forward commitment
                        // the tag actually booked. Showing `annualSalary` would now
                        // print the old contract under the words "Tag Value".
                        Text(formatMillions(booked))
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Color.accentGold)
                        infoCaption("\(seasonLabel(nextSeason)) Tag")
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(seasonLabel(nextSeason)) tag \(formatMillions(booked)) for \(player.fullName)")
                .accessibilityHint("Shows the \(player.position.rawValue) salaries both tags average")

                removePill { removeTag(from: player) }
            }

            // A tag is not a terminal state. The man can still sign a long deal
            // — `applyNegotiatedDeal` rescinds the tag's books on signature — and
            // this row was the only one on the screen with no way to make the
            // call, so the one screen that applies tags offered no way to convert
            // one into a contract.
            contactAgentButton(for: player)
                .padding(.leading, 46)
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
                // Read once for the whole section rather than per row: the
                // favourite has to price every candidate's tag to find itself.
                let favouriteID = tagFavourite?.id
                VStack(spacing: 0) {
                    ForEach(Array(expiringPlayers.enumerated()), id: \.element.id) { index, player in
                        expiringPlayerRow(player, isFavourite: player.id == favouriteID)
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

    private func expiringPlayerRow(_ player: Player, isFavourite: Bool) -> some View {
        let tagCost = tagValue(for: player.position)
        let transitionCost = tagValue(for: player.position, kind: .transition)
        // #127. This used to be `availableCap − tagCost + annualSalary`: next
        // year's tag netted against this year's room, with this year's salary
        // credited back as though the season already played were about to be
        // refunded. Every term was from the wrong year. The tag charges
        // `nextSeason`, where the man's expiring deal is already worth nothing —
        // so the honest answer is simply projected space less the tag.
        //
        // Both terms are snapped to the tenth of a million the screen prints
        // first. Subtracting the exact thousands and rounding once at the end
        // showed $70.8M − $15.6M = $55.3M on one row (70 845 − 15 550 = 55 295),
        // because the two operands rounded in opposite directions. Every row
        // here has to survive the subtraction the reader does in his head
        // against the banner.
        let capAfterTag = roundedToDisplay(projectedNextYearSpace) - roundedToDisplay(tagCost)
        let capAfterTransition = roundedToDisplay(projectedNextYearSpace) - roundedToDisplay(transitionCost)
        let recommendation = smartRecommendation(for: player)
        // Read once for the row: the chip renders it and the button speaks it.
        let priceChange = tagPriceChange(for: player.position)

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

                // **The derived numbers now say where they derive from.** The
                // rules banner states the rules (the average of the top 5, and
                // of the top 10, at his position); it cannot state the
                // salaries, and until this sheet existed nothing on the screen
                // could — which is also why the price moving between two visits
                // read as the app changing its mind. ONE button for both
                // figures, because one sheet explains both: they are the same
                // sorted list read to a different depth.
                Button {
                    tagBreakdown = tagBreakdownRequest(for: player, booked: nil, bookedKind: nil)
                } label: {
                    VStack(alignment: .trailing, spacing: 2) {
                        // Caption first, figure under it. A column whose small
                        // grey word sat BELOW its number read as a caption for
                        // whatever came next; above it, it is a heading for the
                        // dollars it introduces, which is the order the eye
                        // wants and the order every other labelled figure on
                        // this screen already uses.
                        infoCaption("Tag Cost")
                        // Not gold. Eight rows priced in the screen's emphasis
                        // colour made twenty gold elements out of a screen with one
                        // decision on it, and a price the club pays at most once is
                        // not a call to action — the headline number and the
                        // endorsed row's pill are. Once the tag is spent this figure
                        // is the price of a move the row can no longer make, so it
                        // drops again to tertiary.
                        Text(formatMillions(tagCost))
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(hasUsedTag ? Color.textTertiary : Color.textPrimary)
                        // The transition price, smaller and under it: it is the
                        // same decision priced a second way, not a second
                        // decision. It is only ever at or below the franchise
                        // figure — ranks 6-10 cannot raise an average of ranks
                        // 1-5 — so the eye reads the pair as "or, cheaper".
                        Text("or \(formatMillions(transitionCost)) transition")
                            .font(.system(size: DSType.Size.micro, weight: .medium).monospacedDigit())
                            .foregroundStyle(Color.textTertiary)
                        if let priceChange {
                            tagChangeChip(priceChange)
                        }
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(spokenTagCost(tagCost, transition: transitionCost, for: player, change: priceChange))
                .accessibilityHint("Shows the \(player.position.rawValue) salaries both tags average")

                if hasUsedTag {
                    // Already used the tag — show disabled state
                    Text("Tag Used")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textTertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.backgroundTertiary, in: Capsule())
                }
            }

            if !hasUsedTag {
                tagChoiceRow(
                    player: player,
                    isFavourite: isFavourite,
                    tagCost: tagCost,
                    transitionCost: transitionCost
                )
                .padding(.leading, 46)
            }

            // Recommendation. `textPrimary`, not secondary: this is the only
            // line in the row that tells the GM what to do, and it was the
            // faintest string on it.
            HStack(spacing: 6) {
                Image(systemName: recommendation.icon)
                    .font(.caption)
                    .foregroundStyle(recommendation.color)
                Text(recommendation.text)
                    .font(.caption)
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 46)

            // Cap impact. Only while a tag is there to spend: `committedNextYear`
            // already carries the tag this club HAS applied, so once it is spent
            // this line was projecting the room left after a SECOND tag — a
            // number the rules three cards up forbid.
            if !hasUsedTag {
                HStack(spacing: 6) {
                    Image(systemName: "dollarsign.circle")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                    Text("\(seasonLabel(nextSeason)) space after: \(formatMillions(capAfterTag)) franchise")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(capAfterTag >= 0 ? Color.textTertiary : Color.danger)
                    // The transition figure is what the TENDER leaves. A matched
                    // offer sheet costs more, and how much more is not knowable
                    // until a club files one — so the line quotes the number the
                    // club is certain to owe and the row's panel quotes the
                    // other when it exists.
                    Text("\u{00B7} \(formatMillions(capAfterTransition)) transition")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(capAfterTransition >= 0 ? Color.textTertiary : Color.danger)
                    if capAfterTag < 0 && capAfterTransition < 0 {
                        Text("OVER CAP")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.danger)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.danger.opacity(0.15), in: Capsule())
                    }
                }
                .padding(.leading, 46)
            }

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

    /// **The two ways to spend the one tag, side by side**, because that is the
    /// choice: not "tag or not" twice over. They sit under the row rather than
    /// beside the price for the plain reason that two pills and a two-line price
    /// column do not fit a phone's width.
    ///
    /// One tag, eight rows: a filled gold pill on every one of them reads as
    /// eight primary actions for a resource the club has exactly one of. Only
    /// the favourite's FRANCHISE pill is filled — the tag that actually keeps
    /// the man, on the man the screen endorses; the rest are the same actions,
    /// offered rather than urged.
    private func tagChoiceRow(
        player: Player,
        isFavourite: Bool,
        tagCost: Int,
        transitionCost: Int
    ) -> some View {
        HStack(spacing: 8) {
            tagPill(
                title: "Franchise \(formatMillions(tagCost))",
                filled: isFavourite,
                tint: Color.accentGold
            ) {
                pendingTag = PendingTag(player: player, kind: .franchise, tagCost: tagCost)
                showTagConfirmation = true
            }
            tagPill(
                title: "Transition \(formatMillions(transitionCost))",
                filled: false,
                tint: Color.accentBlue
            ) {
                pendingTag = PendingTag(player: player, kind: .transition, tagCost: transitionCost)
                showTagConfirmation = true
            }
            Spacer(minLength: 0)
        }
    }

    /// The small grey heading over a tappable figure, with the affordance that
    /// says it opens something.
    ///
    /// Three rows print one of these — Tag Cost, the booked franchise tag, the
    /// booked transition tender — and until this existed there were three
    /// copies of the same six lines. One copy, so a caption cannot end up
    /// styled three ways.
    private func infoCaption(_ text: String) -> some View {
        HStack(spacing: DSSpacing.xxs) {
            Text(text)
                .font(.system(size: DSType.Size.caption).weight(.medium))
            Image(systemName: "info.circle")
                .font(.system(size: DSType.Size.micro, weight: .semibold))
        }
        .foregroundStyle(Color.textTertiary)
    }

    /// Take the tag off. One shape for both tags: a franchise tag and a
    /// transition tag are withdrawn by the same gesture and there is no reason
    /// for the two buttons to be able to drift apart.
    private func removePill(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("Remove")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.danger)
                .padding(.horizontal, DSSpacing.sm)
                .padding(.vertical, 6)
                .background(Color.danger.opacity(0.15), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.danger.opacity(0.4), lineWidth: 1))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// One of the Apply pills. Same shape every time so a pair reads as one
    /// choice with two prices rather than two unrelated buttons.
    private func tagPill(
        title: String,
        filled: Bool,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(filled ? Color.backgroundPrimary : tint)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(filled ? tint : tint.opacity(0.10), in: Capsule())
                .overlay(Capsule().strokeBorder(tint.opacity(filled ? 0 : 0.45), lineWidth: 1))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                        .font(.system(size: DSType.Size.caption, weight: .bold))
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
            // The pill stays a pill; the finger gets the 44pt it is entitled to.
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Contact \(player.fullName)'s agent")
    }

    // MARK: - Smart Recommendations

    private struct Recommendation {
        let text: String
        let icon: String
        let color: Color
        /// Whether the screen is actually steering the one tag at this man. It
        /// is what decides which single pill is filled — see `tagFavourite`.
        let endorsesTag: Bool
    }

    /// Where a man stands against the far edge of his position's peak window.
    ///
    /// The screen used to know two states, `age > upperBound` and everything
    /// else, and that single hard gate is wrong at both ends. A 30-year-old CB
    /// sits exactly ON the bound (25...30) and was told nothing, though the tag
    /// buys his 31st season; and the gate was read only after the elite branch
    /// had already returned, so a 33-year-old at 87 OVR was urged to tag with no
    /// mention of his age at all. Three states, checked for everyone.
    private enum AgeStanding {
        /// Comfortably inside the peak window.
        case inPrime
        /// The last year of it — the tag buys the first season after the peak.
        case atTheEdge
        /// Beyond it.
        case pastPeak
    }

    private func ageStanding(for player: Player) -> AgeStanding {
        let upperBound = player.position.peakAgeRange.upperBound
        if player.age > upperBound { return .pastPeak }
        if player.age == upperBound { return .atTheEdge }
        return .inPrime
    }

    /// The judgement of the man never changes; the decision it is advice ABOUT
    /// does. Once the tag is spent, "strongly consider tagging" recommends a
    /// move this row has already disabled, so each tier states the choice that
    /// is still open — re-sign him through his agent, or let him walk.
    private func smartRecommendation(for player: Player) -> Recommendation {
        let standing = ageStanding(for: player)

        if player.overall >= 85 {
            switch standing {
            case .pastPeak:
                // The discontinuity this fixes: at 84 OVR and 33 he was an
                // "aging veteran, tag cost may not be worth it"; one rating
                // point higher he was "strongly consider tagging" with no age
                // mentioned. A tag is top-five money at his position for one
                // season, and a man past his window is the wrong place to spend
                // it — so the elite tier stops endorsing it too.
                return Recommendation(
                    text: hasUsedTag
                        ? "Elite on tape but past peak at \(player.age) — re-sign him short, or let him go."
                        : "Elite on tape, but past peak at \(player.age) — a tag pays top-5 money for a declining year.",
                    icon: "exclamationmark.triangle.fill",
                    color: .warning,
                    endorsesTag: false
                )
            case .atTheEdge:
                return Recommendation(
                    text: hasUsedTag
                        ? "Elite player — re-sign him or lose him for nothing. At \(player.age) this is his last peak year."
                        : "Elite player — strongly consider tagging. At \(player.age) this is his last peak year for a \(player.position.rawValue).",
                    icon: "star.fill",
                    color: .accentGold,
                    endorsesTag: true
                )
            case .inPrime:
                return Recommendation(
                    text: hasUsedTag
                        ? "Elite player — re-sign him or lose him for nothing."
                        : "Elite player — strongly consider tagging.",
                    icon: "star.fill",
                    color: .accentGold,
                    endorsesTag: true
                )
            }
        } else if standing == .atTheEdge {
            // The band that did not exist. The tag buys the season AFTER the
            // one being played, so a man in the last year of his window is
            // being paid for his first year outside it.
            return Recommendation(
                text: hasUsedTag
                    ? "At \(player.age) he is in his last peak year — re-sign him short or let him walk."
                    : "At \(player.age) he is in his last peak year for a \(player.position.rawValue) — the tag would buy his first year past it.",
                icon: "hourglass",
                color: .warning,
                endorsesTag: false
            )
        } else if standing == .pastPeak {
            return Recommendation(
                text: hasUsedTag
                    ? "Aging veteran at \(player.age) — let him walk unless he re-signs cheap."
                    : "Aging veteran at \(player.age) — tag cost may not be worth it.",
                icon: "exclamationmark.triangle.fill",
                color: .warning,
                endorsesTag: false
            )
        } else if player.overall < 75 {
            return Recommendation(
                text: "Role player — better to let walk and address in free agency.",
                icon: "arrow.right.circle.fill",
                color: .textTertiary,
                endorsesTag: false
            )
        } else {
            return Recommendation(
                text: hasUsedTag
                    ? "Solid contributor — re-sign him if the price is right."
                    : "Solid contributor — tag if you can't afford to lose him.",
                icon: "checkmark.circle.fill",
                color: .success,
                endorsesTag: true
            )
        }
    }

    /// The one row that gets the filled pill.
    ///
    /// `expiringPlayers` is already sorted by rating, so this is the best man
    /// the screen endorses tagging whose tag the projected cap can actually
    /// absorb. Nobody qualifying means nothing is filled — the screen has no
    /// business urging a tag it would then have to call unaffordable two lines
    /// further down.
    private var tagFavourite: Player? {
        guard !hasUsedTag else { return nil }
        return expiringPlayers.first {
            smartRecommendation(for: $0).endorsesTag
                && projectedNextYearSpace - tagValue(for: $0.position) >= 0
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
                    .font(.system(size: DSType.Size.callout))
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

    /// Players on the user's team with expiring contracts (not already tagged
    /// with either tag).
    private var expiringPlayers: [Player] {
        let transitionIDs = Set(liveTransitionTags.map(\.playerID))
        return teamPlayers
            .filter { $0.contractYearsRemaining <= 1 && !$0.isFranchiseTagged && !transitionIDs.contains($0.id) }
            .sorted { $0.overall > $1.overall }
    }

    /// Players currently franchise-tagged on the user's team.
    private var taggedPlayers: [Player] {
        teamPlayers.filter { $0.isFranchiseTagged }
    }

    /// This club's transition tags for the league year being decided.
    ///
    /// Filtered to men still on the roster: a tagged player who was then traded
    /// or released leaves an orphaned row behind, and the rollover drops it
    /// (`TransitionTagLedger.consume` takes everything due, matched or not).
    /// Showing it would have the screen offer a match-or-lose decision about
    /// somebody the club no longer employs.
    private var liveTransitionTags: [TransitionTagLedger.Tag] {
        let rostered = Set(teamPlayers.map(\.id))
        return transitionTags.filter { $0.bindingSeason == nextSeason && rostered.contains($0.playerID) }
    }

    /// Whether the club has already spent its one tag this offseason — either
    /// one. A club gets one tag, not one of each.
    private var hasUsedTag: Bool {
        !taggedPlayers.isEmpty || !liveTransitionTags.isEmpty
    }

    // MARK: - Tag Value Calculation

    /// What the tag on this man actually costs next year — the number
    /// `ContractEngine.applyFranchiseTag` booked, falling back to a fresh quote
    /// for a save whose tag predates the forward ledger.
    private func tagCommitment(for player: Player) -> Int {
        CommittedCapLedger.forwardCommitment(playerID: player.id, careerID: career.id)?.annualCapHit
            ?? tagValue(for: player.position)
    }

    /// The quoted tag for a position, off the per-load table.
    ///
    /// The fallback is the same live calculation this function used to BE, kept
    /// for the position the table does not carry. Nothing on the screen asks for
    /// one — `buildTagQuotes` prices exactly the positions the rows are drawn
    /// from — but a miss returning a silent $0 would be a price, and a wrong one.
    private func tagValue(for position: Position, kind: TagKind = .franchise) -> Int {
        tagQuotes[position]?.price(kind) ?? liveTagValue(for: position, kind: kind)
    }

    private func liveTagValue(for position: Position, kind: TagKind) -> Int {
        let positionSalaries = allPlayers
            .filter { $0.position == position && $0.annualSalary > 0 }
            .map { $0.annualSalary }
        let cap = team?.salaryCap ?? ContractEngine.openingSalaryCap
        // Task #87 / F16: the `capMode:` overload (this screen used to charge a
        // sandbox save a real tag) and the shared cap-relative floor.
        switch kind {
        case .franchise:
            return ContractEngine.franchiseTagValue(
                position: position,
                topSalaries: positionSalaries,
                capMode: career.capMode,
                salaryCap: cap
            )
        case .transition:
            return ContractEngine.transitionTagValue(
                position: position,
                topSalaries: positionSalaries,
                capMode: career.capMode,
                salaryCap: cap
            )
        }
    }

    /// Prices every position this screen has to quote, **once per load**.
    ///
    /// `liveTagValue` walks all ~1 700 league players, and it is asked for a
    /// price by every expiring row, by every tagged row, and by `tagFavourite`
    /// — which prices the whole expiring list to find one man — on every
    /// redraw. The set of positions is small (the club's expiring men plus
    /// whoever is tagged), the answer only changes when `allPlayers` does, and
    /// `allPlayers` only changes in `loadData`. So it is one pass, there.
    ///
    /// The quote carries the men behind the numbers as well as the numbers,
    /// because that is what the breakdown sheet exists to show and re-deriving
    /// it when the sheet opens would be a second, separate walk of the league.
    private func buildTagQuotes() -> [Position: TagQuote] {
        // Transition-tagged men are in by name and not only by their clock. The
        // tag floors the clock at 1 so they would fall in anyway, but the row
        // that quotes a tender must never be able to find no quote — and a
        // union is cheaper than the bug.
        let transitionIDs = Set(liveTransitionTags.map(\.playerID))
        let priced = Set(
            teamPlayers
                .filter { $0.contractYearsRemaining <= 1 || $0.isFranchiseTagged || transitionIDs.contains($0.id) }
                .map(\.position)
        )
        guard !priced.isEmpty else { return [:] }

        let salaryCap = team?.salaryCap ?? ContractEngine.openingSalaryCap
        let ownTeamID = team?.id

        // The same population `liveTagValue` filters, grouped in one pass
        // instead of re-filtered per position. A man with no club and a salary
        // still on him is in it, exactly as he is in the engine's list — the
        // screen must not print a five-man average the engine did not take.
        var byPosition: [Position: [Player]] = [:]
        for player in allPlayers where player.annualSalary > 0 && priced.contains(player.position) {
            byPosition[player.position, default: []].append(player)
        }

        var quotes: [Position: TagQuote] = [:]
        for position in priced {
            let candidates = byPosition[position] ?? []
            let salaries = candidates.map(\.annualSalary)

            // The engine sorts the bare numbers; this sorts the MEN carrying
            // them, so the sheet can name them. The id tiebreak only decides
            // which of two men on an identical salary is printed — the
            // salaries, and therefore both averages, are the engine's either
            // way. Ten deep, because that is what the transition tag takes and
            // the franchise five are its own first five.
            let topSalaries = candidates
                .dsSorted(false, by: { $0.annualSalary }, id: { $0.id.uuidString })
                .prefix(ContractEngine.transitionTagPoolSize)
                .map { player in
                    TagTopSalary(
                        id: player.id,
                        name: player.fullName,
                        teamAbbreviation: player.teamID.flatMap { teamAbbreviations[$0] },
                        age: player.age,
                        overall: player.overall,
                        salary: player.annualSalary,
                        isOwnPlayer: player.teamID != nil && player.teamID == ownTeamID
                    )
                }

            // Both engine overloads for both tags, deliberately: the
            // floored/sandbox price is what the club is charged, the raw
            // average is what the rules banner describes, and the sheet has to
            // be able to say when the two are not the same number. Four calls
            // into ONE engine average (`ContractEngine.topSalaryAverage`) — the
            // screen never does the arithmetic itself.
            let franchiseAverage = ContractEngine.franchiseTagValue(position: position, topSalaries: salaries)
            let franchisePrice = ContractEngine.franchiseTagValue(
                position: position,
                topSalaries: salaries,
                capMode: career.capMode,
                salaryCap: salaryCap
            )
            let transitionAverage = ContractEngine.transitionTagValue(position: position, topSalaries: salaries)
            let transitionPrice = ContractEngine.transitionTagValue(
                position: position,
                topSalaries: salaries,
                capMode: career.capMode,
                salaryCap: salaryCap
            )

            quotes[position] = TagQuote(
                position: position,
                topSalaries: topSalaries,
                franchiseAverage: franchiseAverage,
                franchisePrice: franchisePrice,
                transitionAverage: transitionAverage,
                transitionPrice: transitionPrice,
                floor: Int(ContractEngine.franchiseTagFloorShare * Double(salaryCap)),
                isFranchiseFloored: career.capMode != .sandbox && franchisePrice > franchiseAverage,
                isTransitionFloored: career.capMode != .sandbox && transitionPrice > transitionAverage,
                isSandbox: career.capMode == .sandbox
            )
        }
        return quotes
    }

    /// The breakdown request for one man's row, or nil for a position the load
    /// did not price (which is no row on this screen — see `buildTagQuotes`).
    private func tagBreakdownRequest(for player: Player, booked: Int?, bookedKind: TagKind?) -> TagBreakdownRequest? {
        guard let quote = tagQuotes[player.position] else { return nil }
        return TagBreakdownRequest(
            quote: quote,
            previous: previousQuotes[player.position],
            bookedCommitment: booked,
            bookedKind: bookedKind,
            playerName: player.fullName
        )
    }

    // MARK: - Tag Price Memory (#127 follow-up: "it moved, with no note")

    /// The scoped key the previous visit's quotes live under.
    ///
    /// **Not yet listed in `CareerScopedDefaults.keys`** — that file is another
    /// lane's this wave. The value is career-scoped regardless (`set` suffixes
    /// it with the open save's uuid, so no career can read another's) and it is
    /// season-stamped, so the only cost of the omission is that a deleted save
    /// leaves one small string behind. It belongs on the purge list.
    private static let tagPriceMemoryKey = "franchiseTagPriceMemory"

    /// Reads the previous visit's quotes, then records this one.
    ///
    /// **Once per appearance, not once per `loadData`.** Applying a tag, or
    /// signing a man through Contact Agent, reloads the screen; re-basing there
    /// would quietly zero the very delta the user came back to see. Measuring
    /// from the moment the screen opened also means a re-sign agreed HERE shows
    /// up against his own position's tag — which is exactly what it does to it,
    /// since a new top-five salary is a new top-five salary whoever wrote it.
    ///
    /// The clearing rule is the season stamp: a memory from an earlier league
    /// year is discarded rather than shown. At the rollover the cap grows and
    /// every contract in the league re-prices, so a cross-year delta measures
    /// inflation rather than the market — and the tag it would be compared
    /// against is a different league year's tag anyway.
    private func captureTagPriceBaseline() {
        guard !baselineCaptured, !tagQuotes.isEmpty else { return }
        baselineCaptured = true

        let stored = storedTagPriceMemory()
        let current: TagPriceMemory? = stored?.season == career.currentSeason ? stored : nil

        var previous: [Position: TagPriceMemory.Quote] = [:]
        for (raw, quote) in current?.quotes ?? [:] {
            guard let position = Position(rawValue: raw) else { continue }
            previous[position] = quote
        }
        previousQuotes = previous

        // This visit's quotes are merged over the season's existing ones rather
        // than replacing them: which positions the screen prices depends on who
        // is expiring TODAY, and a man re-signed this visit takes his position
        // off the list. Dropping it would silently restart that position's
        // baseline the next time somebody at it hits his last year.
        var quotes = current?.quotes ?? [:]
        for (position, quote) in tagQuotes {
            quotes[position.rawValue] = TagPriceMemory.Quote(
                price: quote.franchisePrice,
                topFive: quote.topFiveSalaries
            )
        }
        writeTagPriceMemory(TagPriceMemory(season: career.currentSeason, quotes: quotes))
    }

    private func storedTagPriceMemory() -> TagPriceMemory? {
        guard let raw = CareerScopedDefaults.string(Self.tagPriceMemoryKey),
              let memory = try? JSONDecoder().decode(TagPriceMemory.self, from: Data(raw.utf8))
        else { return nil }
        return memory
    }

    private func writeTagPriceMemory(_ memory: TagPriceMemory) {
        guard let data = try? JSONEncoder().encode(memory) else { return }
        CareerScopedDefaults.set(String(decoding: data, as: UTF8.self), Self.tagPriceMemoryKey)
    }

    /// What this position's tag has done since the screen was last opened, in
    /// thousands — nil when there is nothing to report.
    ///
    /// Both ends are snapped to the tenth of a million the screen prints, for
    /// the same reason `capAfterTag` is: a move the reader cannot reproduce
    /// from the two figures he was shown is worse than no move at all. It is
    /// also what stops a $40K drift being announced as a change.
    private func tagPriceChange(for position: Position) -> Int? {
        guard let quote = tagQuotes[position],
              let previous = previousQuotes[position]
        else { return nil }
        let change = roundedToDisplay(quote.franchisePrice) - roundedToDisplay(previous.price)
        return change == 0 ? nil : change
    }

    /// The move, as the smallest thing that can carry it.
    ///
    /// Warning and success, never gold: a tag that got dearer is a cost and one
    /// that got cheaper is a saving, and neither is the screen asking for a
    /// decision. The chip only appears on a row whose price actually moved, so
    /// on an ordinary revisit the column looks exactly as it did.
    private func tagChangeChip(_ change: Int) -> some View {
        HStack(spacing: 2) {
            Image(systemName: change > 0 ? "arrow.up.right" : "arrow.down.right")
            Text(formatMillions(abs(change)))
        }
        .font(.system(size: DSType.Size.micro, weight: .semibold).monospacedDigit())
        .foregroundStyle(change > 0 ? Color.warning : Color.success)
    }

    /// The row's price, spoken.
    ///
    /// The chip carries no label of its own: it lives inside a button that
    /// declares one, and VoiceOver reads the button rather than its children —
    /// so news left on the chip would be news nobody hears.
    private func spokenTagCost(_ tagCost: Int, transition: Int, for player: Player, change: Int?) -> String {
        var spoken = "Franchise tag \(formatMillions(tagCost)), transition tag \(formatMillions(transition)), for \(player.fullName)"
        if let change {
            // Named, because two figures are now read out and only one of them
            // is measured: the price memory records the franchise number.
            spoken += ". Franchise \(change > 0 ? "up" : "down") \(formatMillions(abs(change))) since your last visit"
        }
        return spoken
    }

    // MARK: - Actions

    /// The deal, spelled out before it is signed.
    ///
    /// Everything in it is a term the user is agreeing to and could not read off
    /// the row: that it is ONE season and which one, what it costs, that it
    /// spends the club's only tag, and what is left of next spring afterwards.
    private func tagConfirmationTerms(for pending: PendingTag) -> String {
        let player = pending.player
        let remaining = roundedToDisplay(projectedNextYearSpace) - roundedToDisplay(pending.tagCost)
        let identity = "\(player.position.rawValue) \(player.fullName), \(player.overall) OVR, age \(player.age)."

        switch pending.kind {
        case .franchise:
            return """
            \(identity)

            One season in \(seasonLabel(nextSeason)) at \(formatMillions(pending.tagCost)) — the average of the top \(ContractEngine.franchiseTagPoolSize) salaries at his position. It charges the \(seasonLabel(nextSeason)) cap, leaving \(formatMillions(remaining)) projected.

            No other club may sign him. This is your only tag this offseason — franchise or transition — and you can remove it from this screen afterwards.
            """
        case .transition:
            return """
            \(identity)

            One season in \(seasonLabel(nextSeason)) at \(formatMillions(pending.tagCost)) — the average of the top \(ContractEngine.transitionTagPoolSize) salaries at his position. It charges the \(seasonLabel(nextSeason)) cap, leaving \(formatMillions(remaining)) projected.

            It does NOT stop other clubs signing him. Any of them may put a contract in front of him, and you then either take on those exact terms — salary and years — or lose him for nothing.

            This is your only tag this offseason, franchise or transition.
            """
        }
    }

    private func applyTag(to player: Player, kind: TagKind, tagCost: Int) {
        guard let team, !hasUsedTag else { return }

        switch kind {
        case .franchise:
            ContractEngine.applyFranchiseTag(
                player: player,
                tagValue: tagCost,
                team: team,
                capMode: career.capMode,
                bindingSeason: nextSeason,
                careerID: career.id
            )
        case .transition:
            ContractEngine.applyTransitionTag(
                player: player,
                tagValue: tagCost,
                position: player.position,
                team: team,
                capMode: career.capMode,
                bindingSeason: nextSeason,
                careerID: career.id
            )
        }

        // Persist so CareerShellView picks up the change
        try? modelContext.save()
        // The offseason task "Franchise Tag Decisions" completes on a tag OR on
        // this flag, and a transition tag sets no `Player` flag for it to see —
        // so the flag is what tells the shell the decision was made. Set for
        // both tags, exactly as it already was for one.
        CareerScopedDefaults.set(true, "franchiseTagVisited")

        // Refresh local state — which is also where the league gets its one look
        // at a transition-tagged man (`loadData` calls
        // `FreeAgencyEngine.canvassTransitionTags`). Canvassing HERE, on the tap,
        // and not on some later screen, is what guarantees the match-or-lose
        // decision is in front of the user while he is still on the screen that
        // can answer it: the tag is applied during Review Roster and settled by
        // the rollover out of it, so this visit is the whole window.
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

    private func removeTransitionTag(from player: Player) {
        ContractEngine.removeTransitionTag(
            player: player,
            team: team,
            capMode: career.capMode,
            careerID: career.id
        )
        try? modelContext.save()
        loadData()
    }

    // MARK: - Answering an Offer Sheet

    private var answerConfirmationTitle: String {
        guard let pending = pendingAnswer else { return "Answer the offer sheet?" }
        return pending.answer == .matched
            ? "Match \(pending.row.offer?.teamAbbreviation ?? "the")'s offer?"
            : "Let \(pending.row.playerName) go?"
    }

    /// Both answers spelled out before either is given, because
    /// `TransitionTagLedger.answer` refuses to change one afterwards.
    private func answerConfirmationTerms(for pending: PendingAnswer) -> String {
        guard let offer = pending.row.offer else { return "" }
        let total = offer.annualSalary * max(1, offer.years)
        let yearWord = offer.years == 1 ? "year" : "years"

        switch pending.answer {
        case .matched:
            // A straight subtraction, and it is right because the banner is not
            // carrying him: `committedNextYear` charges an UNANSWERED sheet
            // nothing, since an unanswered sheet settles as a decline. Matching
            // is therefore the whole of the new commitment.
            let remaining = roundedToDisplay(projectedNextYearSpace) - roundedToDisplay(offer.annualSalary)
            return """
            \(pending.row.playerName) stays, on \(offer.teamAbbreviation)'s terms rather than yours: \(formatMillions(offer.annualSalary)) a year for \(offer.years) \(yearWord), \(formatMillions(total)) in all, starting \(seasonLabel(nextSeason)).

            That replaces the \(formatMillions(pending.row.price)) one-year tender, so your \(seasonLabel(nextSeason)) projected space becomes \(formatMillions(remaining)).

            You cannot change this answer.
            """
        case .declined:
            return """
            \(pending.row.playerName) signs with \(offer.teamAbbreviation) when the \(seasonLabel(nextSeason)) league year opens — \(formatMillions(offer.annualSalary)) a year for \(offer.years) \(yearWord) — and you get nothing back for him. No pick, no compensation.

            Your tag is still spent for this offseason.

            You cannot change this answer.
            """
        }
    }

    private func answerOfferSheet(_ pending: PendingAnswer) {
        guard TransitionTagLedger.answer(pending.answer, playerID: pending.row.playerID, careerID: career.id) else { return }
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

    private func formatMillions(_ thousands: Int) -> String { tagMillions(thousands) }

    /// Money as this screen actually prints it: thousands snapped to the tenth
    /// of a million `formatMillions` rounds to. Arithmetic a reader can check
    /// on screen has to be done on the figures on screen.
    private func roundedToDisplay(_ thousands: Int) -> Int {
        Int((Double(thousands) / 100.0).rounded()) * 100
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

        // The 32 clubs, for the breakdown's salary rows and for the offer-sheet
        // round. One fetch per load, not one per row: the sheet names the man's
        // employer and `Player` carries only his `teamID`.
        let teamsDesc = FetchDescriptor<Team>(predicate: #Predicate { $0.careerID == cid })
        // Local, not `@State`: the only things the screen keeps are the
        // abbreviations, and the offer-sheet round needs the clubs for the
        // length of this call and no longer.
        let leagueTeams = (try? modelContext.fetch(teamsDesc)) ?? []
        teamAbbreviations = leagueTeams.reduce(into: [UUID: String]()) { $0[$1.id] = $1.abbreviation }

        // **The league's one look at every transition-tagged man.**
        //
        // Idempotent: `canvassTransitionTags` only touches rows whose
        // `canvassed` flag is still false, and sets it whether or not anybody
        // filed. So a screen reloaded five times is still one market, not five
        // rolls of the dice — which is the difference between a market and a
        // slot machine the user can feed by leaving and coming back.
        FreeAgencyEngine.canvassTransitionTags(
            allPlayers: allPlayers,
            allTeams: leagueTeams,
            career: career,
            userTeamID: fetchedTeamID,
            salaryCap: team?.salaryCap ?? ContractEngine.openingSalaryCap
        )
        transitionTags = TransitionTagLedger.tags(careerID: career.id)

        tagQuotes = buildTagQuotes()
        captureTagPriceBaseline()
    }
}

// MARK: - Tag Cost Breakdown Model
//
// #127 left the tag price stated but not shown: the rules banner says it is the
// average of the top 5 salaries at the position, and nothing on the screen
// could name those five. A price that is derived, unexplained and free to move
// between two visits reads as the app changing its mind — which is precisely
// what the screenshot audit recorded ("moved $3.3M between visits with no
// note"). These five types are the answer: the two tags, the quote, the men
// behind it, the
// request that opens it, and the memory that makes "since your last visit" a
// real measurement rather than a claim.
//
// File-scope `private` rather than nested in the view, because the sheet is its
// own `View` and a type nested `private` inside `FranchiseTagView` is not
// visible to it.

/// **The two tags this screen can spend.**
///
/// A club has one tag per offseason and it must choose which. The difference is
/// two numbers and one rule, and both live on this type so no row, alert or
/// sheet has to spell either of them out twice.
private enum TagKind {
    case franchise
    case transition

    var title: String {
        switch self {
        case .franchise:  return "Franchise"
        case .transition: return "Transition"
        }
    }

    /// How many salaries this tag's price averages — read off the engine, never
    /// re-typed, so the screen cannot claim a slice the engine does not take.
    var poolSize: Int {
        switch self {
        case .franchise:  return ContractEngine.franchiseTagPoolSize
        case .transition: return ContractEngine.transitionTagPoolSize
        }
    }
}

/// One position's tag prices, and everything needed to explain them.
private struct TagQuote {
    let position: Position
    /// Up to ten salaries, highest first — the transition tag's whole slice, of
    /// which the leading five are the franchise tag's. Fewer than ten when the
    /// league has fewer salaried men at the position: the engine divides by what
    /// it has, and so does the sheet.
    let topSalaries: [TagTopSalary]
    /// The straight average of the top five, before the floor.
    let franchiseAverage: Int
    /// What a franchise tag actually costs — the average, the floor, or $0 in
    /// sandbox.
    let franchisePrice: Int
    /// The straight average of the top ten, before the floor.
    let transitionAverage: Int
    /// What a transition tag actually costs.
    let transitionPrice: Int
    /// The cap-relative floor as it stands for this club, this year. One floor,
    /// shared by both tags — see `ContractEngine.transitionTagValue`.
    let floor: Int
    let isFranchiseFloored: Bool
    let isTransitionFloored: Bool
    let isSandbox: Bool

    /// The five men the franchise tag averages.
    var franchiseBand: [TagTopSalary] {
        Array(topSalaries.prefix(ContractEngine.franchiseTagPoolSize))
    }

    /// The salaries as the price memory stores them. Deliberately still the top
    /// FIVE: the memory is a season-stamped record of what the screen quoted on
    /// its last visit, existing saves hold five, and the delta it drives is the
    /// one printed beside the franchise price.
    var topFiveSalaries: [Int] { franchiseBand.map(\.salary) }

    func price(_ kind: TagKind) -> Int {
        switch kind {
        case .franchise:  return franchisePrice
        case .transition: return transitionPrice
        }
    }

    func average(_ kind: TagKind) -> Int {
        switch kind {
        case .franchise:  return franchiseAverage
        case .transition: return transitionAverage
        }
    }

    /// How many salaries this quote could actually take for `kind`.
    func bandCount(_ kind: TagKind) -> Int {
        min(topSalaries.count, kind.poolSize)
    }
}

/// One man in a position's top ten.
private struct TagTopSalary: Identifiable {
    let id: UUID
    let name: String
    /// `nil` for a man with no club. A free agent still carrying a salary is in
    /// the engine's own list, so he is in this one.
    let teamAbbreviation: String?
    let age: Int
    let overall: Int
    let salary: Int
    /// Your own player. Worth marking: a club's own big contract raises the tag
    /// it would have to pay to keep the next man at that position.
    let isOwnPlayer: Bool

    var subtitle: String {
        "\(teamAbbreviation ?? "FA") \u{00B7} Age \(age) \u{00B7} \(overall) OVR"
    }
}

/// One request to open the breakdown.
///
/// It carries the quote rather than a key into the view's table, so the
/// presented sheet cannot have a nil case to render — the alternative is a
/// `.sheet` whose content is an `if let` with an empty else, i.e. a modal that
/// can come up blank.
private struct TagBreakdownRequest: Identifiable {
    let id = UUID()
    let quote: TagQuote
    let previous: TagPriceMemory.Quote?
    /// The tagged man's BOOKED price, when the sheet was opened from his row.
    /// Non-nil is what tells the sheet to explain that his number is fixed and
    /// the market's is not.
    let bookedCommitment: Int?
    /// Which tag booked it. The note has to name the right one — a transition
    /// tender described as a franchise tag would be the reused-name mistake
    /// this file's own header warns about.
    let bookedKind: TagKind?
    let playerName: String
}

/// What the screen quoted on its last visit, per position.
///
/// Persisted through `CareerScopedDefaults` because the whole complaint it
/// answers is about what happened BETWEEN two visits — in-memory state cannot
/// see across the gap.
private struct TagPriceMemory: Codable {
    /// The league year the quotes were taken in. See
    /// `FranchiseTagView.captureTagPriceBaseline` for why a stamp from an
    /// earlier season is discarded rather than shown.
    var season: Int
    /// `Position.rawValue` -> the quote.
    var quotes: [String: Quote]

    struct Quote: Codable {
        /// What the screen printed as Tag Cost.
        var price: Int
        /// The five salaries behind it, so the breakdown can show WHICH rank
        /// moved rather than only that the average did.
        var topFive: [Int]
    }
}

/// Money as this screen prints it, in one place: the view formats a dozen
/// figures with it and the breakdown sheet another dozen, and two copies of a
/// rounding rule is how a screen ends up disagreeing with its own sheet.
private func tagMillions(_ thousands: Int) -> String {
    let millions = Double(thousands) / 1000.0
    if millions >= 1.0 {
        return String(format: "$%.1fM", millions)
    } else {
        return "$\(thousands)K"
    }
}

// MARK: - Tag Cost Breakdown Sheet

/// Where a derived number shows its work.
///
/// Three questions, in the order a GM asks them: **what are these numbers** (the
/// two headline prices and the arithmetic that produced each), **what have they
/// done since I last looked** (the change card, and the LAST VISIT column that
/// says which rank moved), and **whose salaries are these** (the ranked rows).
/// The notes at the foot cover the cases where a headline is not simply the
/// average — the floor, sandbox, a thin position, and a tag already booked.
///
/// One sheet for both tags, because there is one list: the franchise number is
/// its first five entries averaged and the transition number is all ten. Two
/// sheets would have printed the same salaries twice and invited them to
/// disagree.
///
/// It reads nothing. Every figure arrives on the `TagBreakdownRequest`, priced
/// in the one pass `buildTagQuotes` already makes, so opening the sheet does
/// not walk the league a second time.
private struct TagBreakdownSheet: View {

    let request: TagBreakdownRequest
    /// The league year the tag charges, already labelled by the parent — one
    /// screen, one answer to "which season is this".
    let tagSeasonLabel: String

    @Environment(\.dismiss) private var dismiss

    private var quote: TagQuote { request.quote }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.md) {
                    headline
                    if let change { changeCard(change) }
                    salaryTable
                    notes
                }
                .padding(DSSpacing.lg)
                .frame(maxWidth: DSLayout.contentMeasure)
                .frame(maxWidth: .infinity)
            }
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("\(quote.position.rawValue) Tag Cost")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Headline

    private var headline: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            if quote.isSandbox {
                Text("Sandbox cap mode: either tag is booked at $0. The salaries below are what they would cost in a capped save.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Both prices, one above the other, because they are one decision.
            // The franchise figure leads: it is the dearer of the two by
            // construction (ranks 6-10 cannot raise an average of ranks 1-5)
            // and it is the tag that ends the conversation.
            priceBlock(
                .franchise,
                blurb: "The average of the top \(ContractEngine.franchiseTagPoolSize) \(quote.position.rawValue) salaries in the league — charged against your \(tagSeasonLabel) cap, not this year's. Nobody else may sign him."
            )
            Divider().overlay(Color.surfaceBorder.opacity(0.6))
            priceBlock(
                .transition,
                blurb: "The same list read \(ContractEngine.transitionTagPoolSize) deep, so it is never the dearer of the two. It buys the right to MATCH a rival club's offer sheet, not the right to refuse one."
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.md)
        .background(Color.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: DSCornerRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: DSCornerRadius.card)
                .strokeBorder(Color.surfaceBorder, lineWidth: 1)
        )
    }

    private func priceBlock(_ kind: TagKind, blurb: String) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text(kind.title.uppercased())
                .font(.system(size: DSType.Size.micro, weight: .bold))
                .foregroundStyle(Color.textTertiary)
            Text(tagMillions(quote.price(kind)))
                .font(.system(size: DSType.Size.title1, weight: .bold).monospacedDigit())
                .foregroundStyle(kind == .franchise ? Color.accentGold : Color.accentBlue)
            Text(blurb)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if !quote.topSalaries.isEmpty {
                // The sum on one line. It is the shortest possible proof that
                // the rows underneath are the whole of the number above them,
                // and it is the line a reader checks when he does not believe
                // the price.
                Text(arithmetic(kind))
                    .font(.system(size: DSType.Size.footnote).monospacedDigit())
                    .foregroundStyle(Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The arithmetic for one tag, over the men it could actually take.
    ///
    /// `bandCount` and not the pool size: `ContractEngine.topSalaryAverage`
    /// divides by what the league supplied, so a position with seven salaried
    /// men has a real seven-man transition average, and the line has to divide
    /// by seven or it is describing a different function.
    private func arithmetic(_ kind: TagKind) -> String {
        let band = Array(quote.topSalaries.prefix(quote.bandCount(kind)))
        let terms = band.map { tagMillions($0.salary) }.joined(separator: " + ")
        return "(\(terms)) \u{00F7} \(band.count) = \(tagMillions(quote.average(kind)))"
    }

    // MARK: - Since Last Visit

    /// The move, on the price the screen actually printed. Nil when there is no
    /// baseline (a first visit this league year) or nothing moved.
    /// The FRANCHISE price, and only it: that is the one figure `TagPriceMemory`
    /// has ever stored, so it is the only one with a last-visit value to be
    /// measured against. The card says which number it is talking about.
    private var change: Int? {
        guard let previous = request.previous else { return nil }
        let delta = displayRounded(quote.franchisePrice) - displayRounded(previous.price)
        return delta == 0 ? nil : delta
    }

    private func changeCard(_ change: Int) -> some View {
        HStack(alignment: .top, spacing: DSSpacing.sm) {
            Image(systemName: change > 0 ? "arrow.up.right" : "arrow.down.right")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(change > 0 ? Color.warning : Color.success)
            VStack(alignment: .leading, spacing: 2) {
                Text("Franchise tag \(change > 0 ? "up" : "down") \(tagMillions(abs(change))) since your last visit")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text("It was \(tagMillions(request.previous?.price ?? 0)) when you last opened this screen. The tag follows the league's top five at the position, so any signing anywhere in the league can move it — including one you made yourself. The transition number moves the same way; this screen has only ever recorded the franchise one, so that is the only move it can prove.")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.sm)
        .background(
            (change > 0 ? Color.warning : Color.success).opacity(0.08),
            in: RoundedRectangle(cornerRadius: DSCornerRadius.inline)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                .strokeBorder((change > 0 ? Color.warning : Color.success).opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - The Five Salaries

    private var salaryTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "list.number")
                    .foregroundStyle(Color.accentGold)
                    .font(.system(size: DSType.Size.callout))
                Text(tableTitle)
                    .font(.headline)
                    .foregroundStyle(Color.accentGold)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.accentGold.opacity(0.08))

            Divider().overlay(Color.surfaceBorder)

            if quote.topSalaries.isEmpty {
                CompactEmptyStateView(
                    icon: "tray",
                    message: "No salaried \(quote.position.rawValue) in the league — both tags fall back to the floor."
                )
                .padding(.horizontal, 8)
                .padding(.vertical, 12)
            } else {
                VStack(spacing: 0) {
                    DSListHeaderRow(
                        density: .scan,
                        reservesRank: true,
                        portraitWidth: 0,
                        identityLabel: "PLAYER"
                    ) {
                        DSColumnHeader("SALARY", width: DSListColumn.money, alignment: .trailing)
                        if request.previous != nil {
                            DSColumnHeader("LAST VISIT", width: DSListColumn.money, alignment: .trailing)
                        }
                    }
                    .padding(.horizontal, 12)

                    Divider().overlay(Color.surfaceBorder.opacity(0.5))

                    ForEach(Array(quote.topSalaries.enumerated()), id: \.element.id) { index, entry in
                        salaryRow(entry, rank: index + 1, previous: previousSalary(at: index))
                            .padding(.horizontal, 12)
                        // The band boundary, drawn once and only where the list
                        // is actually long enough to have one: everything above
                        // this line is in the franchise average, everything in
                        // the whole list is in the transition average.
                        if index + 1 == ContractEngine.franchiseTagPoolSize,
                           quote.topSalaries.count > ContractEngine.franchiseTagPoolSize {
                            bandDivider
                        } else if index < quote.topSalaries.count - 1 {
                            Divider()
                                .overlay(Color.surfaceBorder.opacity(0.5))
                                .padding(.horizontal, 8)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .cardBackground()
    }

    private var bandDivider: some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(Color.accentGold.opacity(0.4))
                .frame(height: 1)
            Text("\u{2191} FRANCHISE AVERAGES THESE \(quote.bandCount(.franchise)) \u{00B7} TRANSITION AVERAGES ALL \(quote.topSalaries.count)")
                .font(.system(size: DSType.Size.micro, weight: .bold))
                .foregroundStyle(Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Rectangle()
                .fill(Color.accentGold.opacity(0.4))
                .frame(height: 1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    /// "Top 10" is the deeper of the two rules; the count is what the league
    /// could actually supply. The empty case still says 10, because there is
    /// nothing to have taken 0 of.
    private var tableTitle: String {
        let count = quote.topSalaries.isEmpty ? ContractEngine.transitionTagPoolSize : quote.topSalaries.count
        return "Top \(count) \(quote.position.rawValue) Salaries"
    }

    private func salaryRow(_ entry: TagTopSalary, rank: Int, previous: Int?) -> some View {
        DSListRow(
            density: .scan,
            rank: DSRank(value: rank),
            portraitWidth: 0,
            portrait: { EmptyView() },
            identity: {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(entry.name)
                            .font(DSType.text(DSListDensity.scan.nameSize, .semibold, prose: true))
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                        if entry.isOwnPlayer {
                            // Your own contract is in your own tag. It is the
                            // one thing on this list the GM can do something
                            // about, so it is the one thing marked.
                            Text("YOUR CLUB")
                                .font(DSType.display(11, .heavy))
                                .foregroundStyle(Color.accentGold)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.accentGold.opacity(0.15), in: Capsule())
                        }
                    }
                    Text(entry.subtitle)
                        .font(DSType.display(11, .medium))
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)
                }
            },
            columns: {
                Text(tagMillions(entry.salary))
                    .font(DSType.display(13, .bold))
                    .foregroundStyle(Color.textPrimary)
                    .dsColumn(DSListColumn.money, alignment: .trailing)
                if request.previous != nil {
                    Text(previous.map(tagMillions) ?? "\u{2014}")
                        .font(DSType.display(11, .semibold))
                        .foregroundStyle(previousTint(current: entry.salary, previous: previous))
                        .dsColumn(DSListColumn.money, alignment: .trailing)
                }
            }
        )
    }

    /// What sat at this rank last visit. Nil when the position had fewer men at
    /// a salary then than it does now — an em dash rather than a zero, because
    /// "there was nobody here" is not "he earned nothing". Ranks 6-10 are always
    /// nil: the memory records five, deliberately (see `TagQuote.topFiveSalaries`),
    /// so the column simply stops rather than inventing a history it never kept.
    private func previousSalary(at index: Int) -> Int? {
        guard let previous = request.previous, index < previous.topFive.count else { return nil }
        return previous.topFive[index]
    }

    /// Tertiary while the rank is unchanged, tinted when it moved: the column is
    /// there to be scanned for the line that is not grey.
    private func previousTint(current: Int, previous: Int?) -> Color {
        guard let previous, displayRounded(previous) != displayRounded(current) else {
            return Color.textTertiary
        }
        return current > previous ? Color.warning : Color.success
    }

    // MARK: - Notes

    @ViewBuilder
    private var notes: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            if let booked = request.bookedCommitment {
                let kindWord = (request.bookedKind ?? .franchise) == .transition ? "transition tender" : "franchise tag"
                note(
                    "lock.fill",
                    "\(request.playerName)'s \(kindWord) is booked at \(tagMillions(booked)) and does not move with the market. The prices above are what tagging a \(quote.position.rawValue) would cost today."
                )
            }
            if quote.isFranchiseFloored && quote.isTransitionFloored {
                note(
                    "arrow.up.to.line",
                    "Both averages are under the league's minimum tender (\(tagMillions(quote.floor))), so both tags are charged at that floor — which is why they cost the same here."
                )
            } else if quote.isFranchiseFloored {
                note(
                    "arrow.up.to.line",
                    "The top-\(quote.bandCount(.franchise)) average is under the league's minimum tender (\(tagMillions(quote.floor))), so the franchise tag is charged at that floor instead."
                )
            } else if quote.isTransitionFloored {
                note(
                    "arrow.up.to.line",
                    "The top-\(quote.bandCount(.transition)) average is under the league's minimum tender (\(tagMillions(quote.floor))), so the transition tag is charged at that floor instead."
                )
            }
            // No sandbox note: the headline already says both tags are $0 there,
            // and saying it twice on one sheet is the app arguing with itself.
            if !quote.topSalaries.isEmpty && quote.topSalaries.count < ContractEngine.transitionTagPoolSize {
                note(
                    "exclamationmark.triangle.fill",
                    quote.topSalaries.count <= ContractEngine.franchiseTagPoolSize
                        ? "Only \(quote.topSalaries.count) salaried \(quote.position.rawValue) in the league, so both averages are taken over \(quote.topSalaries.count) — and both tags therefore cost the same."
                        : "Only \(quote.topSalaries.count) salaried \(quote.position.rawValue) in the league, so the transition average is taken over \(quote.topSalaries.count) rather than \(ContractEngine.transitionTagPoolSize)."
                )
            }
            note(
                "envelope",
                "The transition tag does not keep him. Any other club may file an offer sheet on him, and you then match those exact terms — salary and years — or lose him for nothing."
            )
            note(
                "arrow.triangle.2.circlepath",
                "These prices are re-read every time the screen opens. Re-signings, free-agent deals and trades anywhere in the league move the list above, and both tags with it."
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.sm)
        .background(Color.backgroundSecondary.opacity(0.6), in: RoundedRectangle(cornerRadius: DSCornerRadius.inline))
    }

    private func note(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
                .frame(width: 16)
            Text(text)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The same snap-to-the-printed-figure rule the parent screen uses, so a
    /// delta on the row and a delta in this sheet cannot disagree.
    private func displayRounded(_ thousands: Int) -> Int {
        Int((Double(thousands) / 100.0).rounded()) * 100
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
