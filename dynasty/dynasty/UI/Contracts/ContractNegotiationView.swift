import SwiftUI
import SwiftData

// MARK: - Contract Negotiation (Contact Agent wave)
//
// A contract talk is a CONVERSATION, so this screen is a chat and nothing else.
//
// What changed and why:
//
// 1. ONE entry, everywhere. `ContactAgentEntry` is the only door in, and it
//    never reveals willingness — a hidden "Extend Contract" button used to tell
//    the user the answer before he asked the question. Everyone can be called.
//
// 2. The agent speaks first, in character. A client who will not talk says so
//    HERE, with a reason ("My client has no interest in negotiating with this
//    team right now — he hasn't taken a meaningful snap all year"), instead of
//    the flat system banner the freeze-out used to print. The thread stays
//    readable, and next league year opens a clean one.
//
// 3. Counters carry their number in the sentence. The offer composer is still
//    structured — years, salary, bonus, guarantees, clauses — but every reply
//    renders as speech, and the money in the speech is the money on the card
//    below it, because both come from the same engine offer.
//
// 4. Nothing auto-exits. Signing appends the agent's closing line, then an
//    inline signed card, and leaves a Done button. The user decides when the
//    conversation is over — the old sheet dismissed itself on the frame the
//    deal closed, so the line the agent said at the handshake was never read.
//
// 5. The tone of the close is written to the man. A smooth close at his number
//    is a small morale lift and a nudge toward `.driven`; a grinding close well
//    under his ask costs a few points of morale and leaves a "wants more" note
//    that the roster keeps showing.
//
// OWNERSHIP: this file writes copy and persists the transcript. Every number in
// it comes out of `ContractNegotiationEngine` — the opening demand, the
// counters, the accept/walk/break-off verdicts. Nothing here prices a contract.
//
// ---------------------------------------------------------------------------
// #105 WAVE 3c — the presentation layer moved out; the negotiation did not.
//
// `NegotiationChat.swift` now owns the chrome this screen and `TradeNegotiationView`
// used to own a copy of each: the header, the bubbles, the transcript, the
// notice banner and the close strip. What changed HERE is only where things are
// drawn:
//
//   * rounds are `DSSlatBand` steps with the agent's patience as its meter,
//     instead of a "N rounds of patience left" sentence in the header;
//   * the commit lives in `DSActionBar` — one gold primary, the cap sentence as
//     its explainer, Walk Away separated as the destructive;
//   * the ending is a `DSResultSheet` instead of a body swap plus a gold "Done";
//   * the duplicate dismissal is gone. There was a toolbar "Close" AND an inline
//     "Done" AND a "Leave It" on the pay-cut path — three doors out of one
//     screen, which is the defect UI_REDESIGN_VISION §P5 names by file name.
//     One 44 pt X, top-trailing.
//
// **Not one line of negotiation logic moved.** The ratchet, the stance pinning
// and the pricing ladders (9a53918) are untouched: every `submitCounterOffer`,
// `submitPayCut`, `pester`, `close` and `commit` below is the code that shipped,
// and the engine calls inside them have the same arguments in the same order.

struct ContractNegotiationView: View {

    let player: Player
    let negotiationType: NegotiationType
    let teamCapSpace: Int

    /// **What the host will do with a signature** (#186), declared by the host
    /// because only the host knows.
    ///
    /// The gate cannot infer it, and the difference is a whole league year.
    /// `PlayerDetailView` and `CapOverviewView` ADD years to a running deal
    /// (`.extendExisting`), so the money starts when that deal runs out.
    /// `FranchiseTagView` and `FinalPushView` REPLACE an expiring one
    /// (`.replaceContract`), so it starts in the year that is open. Both open
    /// the same `.extend` conversation with the same man, and an expiring
    /// contract reads `contractYearsRemaining == 1` right up to the rollover —
    /// so from inside this screen the two are indistinguishable, and guessing
    /// would quote a Final Push re-sign against next year's cap while the
    /// booking charged it to this one. `DealTargetYear.plan` takes the
    /// application for exactly that reason; this passes the host's answer to it.
    ///
    /// Defaulted so the extension hosts need say nothing, and ignored outside an
    /// `.extend` talk: a pay cut reprices the year that is running, always.
    var dealApplication: ContractEngine.DealApplication = .extendExisting

    var onDealCompleted: ((NegotiationOffer) -> Void)?

    /// **The pay-cut payoff** (#102). Called with the agreed per-year salary and
    /// the persona-scaled morale consequence, both in the moment the agent
    /// consents.
    ///
    /// A separate hook from ``onDealCompleted`` rather than a one-year
    /// `NegotiationOffer` through the same door, because the two are different
    /// transactions: a signing ADDS a contract, a pay cut REPRICES the one that
    /// exists. The host calls `ContractEngine.applyPayCut` — the one place a pay
    /// cut is booked — and passes `moraleDelta` straight through, which is why
    /// this screen writes no morale of its own on the pay-cut path: the engine's
    /// `applyPayCut` already does it, and doing it here as well would charge the
    /// man twice for one bad afternoon.
    var onPayCutAgreed: ((_ newSalary: Int, _ moraleDelta: Int) -> Void)?

    /// The client answered a pay-cut ask with "then release me". Lets the host
    /// (the Cap Compliance workspace) put the Release lever in front of the user
    /// instead of leaving him to work out what just happened.
    var onReleaseDemanded: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    // MARK: - State

    /// The persisted conversation. `nil` only before the first load pass.
    @State private var thread: NegotiationThread?
    @State private var season: Int = 0
    @State private var currentWeek: Int = 0
    @State private var team: Team?
    @State private var career: Career?
    /// The club's roster, fetched once when the thread opens. Its only job is
    /// `DealTargetYear.space` (#127/#186) — projecting what the club already
    /// owes in the league year the deal being negotiated actually starts
    /// charging. Empty for a free agent (no club to project) and never read on
    /// the current-year path, so nothing pays for it that does not use it.
    @State private var teamRoster: [Player] = []
    /// The man's detailed contract in realistic mode, if he has one.
    ///
    /// Fetched so the gate nets against the SAME running charge the booking
    /// nets against: `ContractEngine.applyNegotiatedDeal` reads
    /// `existingContract?.capHit ?? player.annualSalary`, and a gate that only
    /// ever read `annualSalary` priced a structured deal's replacement wrong by
    /// the prorated bonus. `nil` in simple/sandbox, where no `Contract` row is
    /// written at all.
    @State private var existingContract: Contract?
    /// `DraftReputation.ownerTrust` — a separate row, so it is fetched
    /// separately and defaults to the neutral 70 the row is created with.
    @State private var ownerTrust: Int = 70
    @State private var scrollTarget: UUID?
    @State private var showYearlyBreakdown = false
    @State private var didLoad = false

    // Offer builder state
    @State private var offerYears: Int = 2
    @State private var offerSalary: Int = 5000
    @State private var offerBonus: Int = 0
    @State private var offerGuaranteed: Int = 30

    // Incentive builder state (TODO §5.5).
    //
    // `incentiveMenu` holds the candidate clauses — position-appropriate, priced
    // off the agent's opening ask — and `enabledIncentiveIDs` says which of them
    // are actually on the offer. Splitting them keeps a clause's negotiated
    // threshold intact while the GM toggles it off and back on.
    @State private var incentiveMenu: [ContractIncentive] = []
    @State private var enabledIncentiveIDs: Set<String> = []
    @State private var showIncentives = false

    // Pay-cut composer state (#102). One dial — the new per-year number — because
    // a pay cut has exactly one term to argue about. `payCutSettled` latches once
    // the man has signed, so the composer cannot ask him twice for the same year.
    @State private var payCutSalary: Int = 0
    @State private var payCutSettled = false
    /// The last answer, kept so the release demand can stay on screen under the
    /// composer instead of scrolling away with the transcript.
    @State private var payCutLastOutcome: ContractNegotiationEngine.PayCutOutcome?

    // MARK: - Result presentation (#105 Wave 3c)

    /// **The one sheet on this screen.** Enum-shaped and driven by `.sheet(item:)`
    /// rather than a second `isPresented` flag: a view hierarchy with two
    /// `.sheet(isPresented:)` modifiers dismisses one of them silently, which is
    /// a bug this codebase has now shipped four times.
    @State private var outcome: NegotiationOutcome?

    /// The status the screen has already reacted to. A result sheet fires on a
    /// TRANSITION, never on arrival — otherwise re-opening a thread that was
    /// broken off last month would greet the user with a modal about it.
    @State private var lastSeenStatus: NegotiationThreadStatus?

    /// Two facts the result sheet needs that the world has already overwritten
    /// by the time it is built.
    ///
    /// `onDealCompleted` / `onPayCutAgreed` fire BEFORE `commit`, and both hosts
    /// write the new salary onto the player inside them — so by the time the
    /// sheet asks "what did this cost", `player.annualSalary` is the number the
    /// deal produced and a freshly planned deal reads back ≈ $0. Snapshotting
    /// the values at the moment of the handshake is the only honest way to state
    /// the before and the after.
    @State private var salaryBeforeClose: Int = 0
    /// Years left on the deal he was on, for the same reason and read at the
    /// same instant: the signature rewrites the clock, so a sheet headed WHAT
    /// CHANGED cannot ask the player what it used to say.
    @State private var yearsBeforeClose: Int = 0
    @State private var capChargeAtClose: Int?
    /// The plan the deal was signed under (#186), snapshotted for the same
    /// reason: the shape is read off the player, and the signature changes the
    /// player. Re-planning after the host has written the contract would tell a
    /// tag-and-extend it was an ordinary re-sign.
    @State private var planAtClose: DealTargetYear.Plan?

    private let salaryStep = 500
    private let bonusStep = 500
    private let guaranteedStep = 5
    private let minSalary = 500
    private let maxSalary = 75_000

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                playerHeader
                if showsRoundBand { roundBand }
                // Bottom-anchored, because a round-one thread holds exactly one
                // bubble and the transcript absorbs every point of slack in the
                // body: the agent's opening ask sat a third of the way down a
                // 13-inch page with the rest of it empty. The newest line
                // belongs against the composer that answers it.
                NegotiationTranscript(lines: chatLines, scrollTarget: scrollTarget)
                    .defaultScrollAnchor(.bottom)
                if isComposerLive {
                    if isPayCut { payCutComposer } else { offerBuilder }
                    commitBar
                } else {
                    closeStrip
                }
            }
        }
        .navigationTitle("Contact Agent")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        // P5's corollary: ONE dismissal. The gold "Done" in the old closing bar
        // and the "Leave It" on the pay-cut composer both said the same thing
        // this says, in two other places and two other verbs.
        .negotiationDismissButton(label: "Close the conversation. The thread stays saved.") {
            dismiss()
        }
        // §2.6: a process ends in a result sheet, never in an in-place body swap.
        .sheet(item: $outcome) { result in
            DSResultSheet(
                tone: result.tone,
                eyebrow: isPayCut ? "Renegotiation" : "Contract talks",
                headline: result.headline,
                message: result.message,
                chips: result.chips,
                cost: result.cost,
                onContinue: {
                    outcome = nil
                    dismiss()
                }
            )
        }
        .task { loadIfNeeded() }
    }

    /// Whether the user still has something to do here.
    private var isComposerLive: Bool {
        isPayCut ? (isNegotiationActive && !payCutSettled) : isNegotiationActive
    }

    /// A pay cut is one question with one answer — it has no round budget to
    /// draw, so it gets no band. Every other talk does.
    private var showsRoundBand: Bool { !isPayCut && thread != nil }

    /// Whether the composer stays on screen.
    ///
    /// `acceptsOffers`, not `isOpen`: a refusal keeps the composer, because a
    /// front office is always allowed to table another offer. What that costs is
    /// the engine's business (`ContractNegotiationEngine`'s pestering path) and
    /// the agent's to say out loud — it is not something this screen prevents by
    /// taking the buttons away.
    private var isNegotiationActive: Bool { thread?.status.acceptsOffers ?? false }

    /// The refusing thread, if this conversation is one. Drives the stance
    /// banner over the composer.
    private var refusalReason: AgentRefusalReason? {
        guard thread?.status == .refused else { return nil }
        return thread?.refusalReason
    }

    private var pesterCount: Int { thread?.pesterCount ?? 0 }

    // MARK: - Agent Identity

    /// Deterministic agent persona for this player (derived from player.id).
    private var agentPersona: AgentPersona { AgentPersona.forPlayer(id: player.id) }

    /// Deterministic agent name for this player.
    private var agentName: String { AgentPersona.agentName(for: player.id) }

    /// The character the persona speaks in.
    private var agentVoice: AgentVoice { agentPersona.voice(for: player.id) }

    // Rounds left used to be a sentence in the header ("3 rounds of patience
    // left"). It is now the round band's `DSResourceMeter` — §2.1's rule that a
    // process prints its count in exactly one place — computed from the same
    // `ContractDemand.maxRounds`, which still SHRINKS as `insultCount` climbs.
    // That is what "the ask hardens" looks like from the GM's chair, and the
    // band shows it by locking a slat rather than by decrementing a noun.

    /// The situation-driven character of this talk, if it has one — the engine's
    /// verdict, rendered as a chip. The chat never derives a stance of its own.
    private var stance: NegotiationStance? { liveDemand.stance }

    // **What this client is actually negotiating for** (#86) — the axis every
    // high-traffic line in the chat is written on — is deliberately NOT a
    // property here. `AgentDesire.primary` is called at each message site with
    // the demand THAT site is speaking about (the opening demand, the round's
    // graded demand, the demand the deal closed against), and it decodes
    // `Player.injuryHistory` from JSON, which is cheap once per message and
    // wasteful once per SwiftUI body pass.
    //
    // It is also not shown as a chip anywhere, on purpose: the user is meant to
    // work out what a man wants from how his agent talks, and a label over the
    // conversation would answer the question the conversation is asking.

    /// The line picker for one exchange.
    ///
    /// Seeded on the thread, the round and the site, so the same conversation
    /// says the same words on every re-open — and carrying the thread's
    /// `lastLineIndex` so it never says the same one twice running.
    private func selector(for thread: NegotiationThread, round: Int) -> DialogueSelector {
        DialogueSelector(threadID: thread.id, round: round, lastIndex: thread.lastLineIndex)
    }

    // MARK: - Economy Inputs
    //
    // Everything below is read from the world and handed to the engine. The
    // chat computes no money: it supplies the league's cap, the club's season
    // and the user's standing, and the demand model prices the man.

    /// The league's ACTUAL cap. Defaulting to 265 000 — which is what every
    /// call from this screen used to do — meant that by season 10 the agent
    /// quoted season-1 money while the free-agency screen and the AI market
    /// quoted the real number.
    private var salaryCap: Int { team?.salaryCap ?? ContractEngine.openingSalaryCap }

    private var capMode: CapMode { career?.capMode ?? .simple }

    /// What the league knows about this front office. Previously never
    /// constructed at all, so `gmAdjustment` was identically zero on every
    /// shipped negotiation and the whole five-line breakdown — plus the
    /// `NegotiationLedger` feeding it — was write-only.
    private var gmStanding: GMStanding {
        guard let career else { return .neutral }
        return GMStanding.from(career: career, ownerTrust: ownerTrust)
    }

    /// The club and the season, as the demand model reads them.
    private var negotiationSituation: NegotiationSituation {
        // "Contender" is `ContractNegotiationEngine.isContender` and nothing
        // else. It used to be an inline expression here, which meant this screen
        // owned a second definition of the word that the ring-chaser's exit
        // condition and the legacy veteran's discount would have had to agree
        // with by coincidence.
        ContractNegotiationEngine.situation(
            for: player,
            season: season,
            teamWins: team?.wins ?? 0,
            teamLosses: team?.losses ?? 0,
            weeksPlayed: currentWeek
        )
    }

    /// The agent's standing demand, priced for THIS club in THIS season with
    /// the lowballs this thread has already absorbed.
    private var liveDemand: ContractDemand {
        ContractNegotiationEngine.demand(
            player: player,
            negotiationType: negotiationType,
            salaryCap: salaryCap,
            situation: negotiationSituation,
            standing: gmStanding,
            insultCount: thread?.insultCount ?? 0
        )
    }

    // MARK: - Cap Gate (#127 → #186)

    /// The offer as the composer currently has it.
    private var builderOffer: NegotiationOffer {
        NegotiationOffer(
            years: offerYears,
            annualSalary: offerSalary,
            signingBonus: offerBonus,
            guaranteedPercent: offerGuaranteed,
            noTradeClause: false,
            incentives: activeIncentives
        )
    }

    // MARK: - Which League Year This Deal Charges (#127 → #186)

    /// ``dealApplication``, narrowed by the conversation.
    ///
    /// A pay cut is deliberately never an extension whatever the host declares:
    /// it reprices the deal that is running, in the year that is running, so it
    /// must not be planned as deferred. That is the work `dealStartOffset`'s
    /// `negotiationType == .extend` guard used to do, and losing it would have
    /// moved every pay-cut quote into a season the club is not in.
    private var plannedApplication: ContractEngine.DealApplication {
        negotiationType == .extend ? dealApplication : .replaceContract
    }

    /// **What this offer is, in the engine's words** — which year it charges,
    /// what it costs there, and what it takes off the books when it lands.
    ///
    /// The screen no longer works any of that out. It used to own seven private
    /// derivations (`dealStartOffset`, `projectedStartYearCap`,
    /// `committedStartYear`, `currentYearOverage`, `startYearOverage`, …), and
    /// they disagreed with `ContractEngine.applyNegotiatedDeal` in the way #186
    /// describes: the composer printed *"Covers 2027–2030"* and the gate under
    /// it refused the deal on 2026's bank balance. One of those two sentences
    /// had to be a lie because two different pieces of arithmetic wrote them.
    /// Now the label and the gate are the same `Plan`, so they cannot differ.
    ///
    /// One of the seven was also simply wrong. `committedStartYear` added the
    /// tagged men's forward rows to the projected year WITHOUT excluding the man
    /// being negotiated, so a tag-and-extend was charged against its own tag
    /// before it existed. `DealTargetYear.space` excludes him by construction.
    private func dealPlan(for offer: NegotiationOffer) -> DealTargetYear.Plan {
        DealTargetYear.plan(
            player: player,
            offer: offer,
            application: plannedApplication,
            capMode: capMode,
            currentSeason: season,
            hasRolledOver: hasRolledOver,
            careerID: career?.id,
            existingContract: existingContract
        )
    }

    /// **The deal as it will be WRITTEN, which is not the deal as it averages.**
    ///
    /// `ContractEngine.negotiatedBaseSalaries` is deliberately not renormalised
    /// — its own doc measures a 2-year veteran schedule at 10.4 % over
    /// `annualSalary × years` — so `NegotiationOffer.totalValue` and
    /// `.annualCapHit` are the numbers the two sides BARGAINED, not the numbers
    /// `applyNegotiatedDeal` puts on the `Contract` row. Quoting the flat pair as
    /// the cost is the lie the screen used to tell: it printed "$108.0M total,
    /// $54.0M/yr" over a booking of $117.0M whose first year charged $60.5M, and
    /// its own cap sentence ("Charges $23.0M") was measured off the $60.5M.
    ///
    /// Simple and sandbox write no schedule, and a deferred extension is
    /// re-summed off the flat rate when it binds (see `Plan.firstYearCapHit`), so
    /// in those three cases the bargained numbers already are the written ones.
    private struct WrittenDeal {
        let firstYearCapHit: Int
        let total: Int
        /// Guaranteed DOLLARS, not the percent. The percent is a percent of the
        /// bargained package, so it overstates the guarantee against the written
        /// one; the money is the same either way and is what gets persisted.
        let guaranteed: Int
    }

    private func writtenDeal(_ offer: NegotiationOffer, plan: DealTargetYear.Plan) -> WrittenDeal {
        guard !plan.booksForward, !plan.baseSalaries.isEmpty else {
            return WrittenDeal(
                firstYearCapHit: offer.annualCapHit,
                total: offer.totalValue,
                guaranteed: offer.guaranteedMoney
            )
        }
        return WrittenDeal(
            firstYearCapHit: plan.firstYearCapHit,
            total: plan.baseSalaries.reduce(0, +) + offer.signingBonus,
            guaranteed: offer.guaranteedMoney
        )
    }

    /// Whether the new league year is already open — the six offseason phases
    /// between `executeNewLeagueYear` and the season counter's bump, where
    /// `season` is one BEHIND the year the club's books are in. Without it an
    /// extension talked in, say, the draft binds a year early, onto the last
    /// year of the deal it is extending. The same test `WeekAdvancer` and
    /// `FranchiseTagView` use; see `DealTargetYear.openSeason`.
    private var hasRolledOver: Bool {
        guard let career else { return false }
        return career.lastRolloverSeason >= career.currentSeason
    }

    /// The room the plan has to fit into, in the year it binds.
    ///
    /// A free agent has no `Team` on this screen — `team` is loaded off
    /// `player.teamID` and he has none — so the host's `teamCapSpace` is the
    /// only club number in hand. That is not a loss: a free agent signs into the
    /// year that is open, which is the year `teamCapSpace` describes.
    private func capSpace(for plan: DealTargetYear.Plan) -> DealTargetYear.Space {
        guard let team else {
            return DealTargetYear.Space(
                season: DealTargetYear.openSeason(
                    currentSeason: season,
                    hasRolledOver: hasRolledOver
                ),
                seasonsAhead: 0,
                cap: teamCapSpace,
                committed: 0
            )
        }
        return DealTargetYear.space(
            for: plan,
            player: player,
            team: team,
            roster: teamRoster,
            currentSeason: season,
            hasRolledOver: hasRolledOver,
            careerID: career?.id
        )
    }

    /// Plan, room and verdict in one read — the whole gate, for one offer.
    private func capGate(for offer: NegotiationOffer) -> DealGate {
        let plan = dealPlan(for: offer)
        let space = capSpace(for: plan)
        return DealGate(
            plan: plan,
            space: space,
            verdict: DealTargetYear.verdict(plan: plan, space: space, capMode: capMode)
        )
    }

    /// Named rather than a tuple because the composer, the action bar and the
    /// belt-and-braces guards all pass it around.
    private struct DealGate {
        let plan: DealTargetYear.Plan
        let space: DealTargetYear.Space
        let verdict: DealTargetYear.Verdict
    }

    /// **Whether the club can actually fit a deal.** One year is tested — the
    /// one the money lands in — because that is the one year the booking will
    /// charge. Sandbox short-circuits inside `DealTargetYear.verdict`, so this
    /// screen no longer keeps its own copy of that rule either.
    private func exceedsCap(_ offer: NegotiationOffer) -> Bool {
        capGate(for: offer).verdict.isBlocked
    }

    /// The gate for what is in the composer right now.
    private var builderGate: DealGate { capGate(for: builderOffer) }

    private var builderExceedsCap: Bool { builderGate.verdict.isBlocked }

    /// The bonus ceiling. Unbounded before, and because only `annualSalary` was
    /// ever written to the player, a $500K salary with a $200M bonus read as a
    /// $50.5M/yr offer to the agent and as the veteran minimum to the league.
    /// Half the deal's value is the outer edge of a real signing bonus.
    private var maxBonus: Int { max(bonusStep, offerSalary * max(1, offerYears)) }

    // MARK: - Player Header

    private var playerHeader: some View {
        NegotiationChatHeader(
            title: player.fullName,
            chips: factChips,
            identityChips: agentChips,
            note: headerNote,
            noteColor: headerNoteColor
        ) {
            VStack(alignment: .trailing, spacing: DSSpacing.xxs) {
                Text("\(player.overall)")
                    .font(DSType.display(DSType.Size.display, .heavy))
                    .foregroundStyle(Color.forRating(player.overall))
                Text("OVR")
                    .font(DSType.display(11, .heavy))
                    .tracking(0.6)
                    .foregroundStyle(Color.textTertiaryReadable)
            }
        }
    }

    /// The facts about the man: what he plays, how old he is, what he already
    /// costs. Nothing fogged — a player under contract to the user's club has no
    /// hidden salary.
    private var factChips: [NegotiationChatChip] {
        var chips: [NegotiationChatChip] = [
            .init(id: "pos", text: player.position.rawValue, color: positionSideColor, style: .solid),
            .init(id: "age", text: "Age \(player.age)"),
            .init(id: "pay", text: "\(formatMillions(player.annualSalary))/yr")
        ]
        if contractYearsLeft > 0 {
            chips.append(.init(id: "yrs", text: "\(contractYearsLeft)yr left"))
        }
        return chips
    }

    /// The term chip's number — **the deal the man is actually on**.
    ///
    /// `player.contractYearsRemaining` stops being that the moment an offseason
    /// deal is signed. The re-sign hosts add a year to that counter so
    /// `executeNewLeagueYear`'s decrement cannot expire a deal the day it was
    /// agreed (`FranchiseTagView.onDealCompleted`, `FinalPushView.applyReSignOffer`),
    /// and the compensation lands on the one field this header reads: a 2-year
    /// deal closed in Review Roster printed "3yr left" directly above a receipt
    /// that said "2 years", i.e. a $162M commitment where $117M was signed.
    /// After a signature the plan's own term is the honest answer.
    private var contractYearsLeft: Int {
        planAtClose?.contractYears ?? player.contractYearsRemaining
    }

    /// Who is on the phone: his name, how he bargains, how he talks — and the
    /// situation chip when the engine says this talk has one. A normal
    /// negotiation is the overwhelming majority and must not be dressed up as a
    /// story it isn't, so `stance` stays optional.
    private var agentChips: [NegotiationChatChip] {
        var chips: [NegotiationChatChip] = [
            .init(id: "agent", text: agentName, icon: agentPersona.symbolName, color: personaColor, style: .tinted),
            .init(id: "style", text: agentPersona.styleLabel, color: personaColor, style: .tinted),
            .init(id: "voice", text: agentVoice.label, color: .textTertiaryReadable, style: .tinted)
        ]
        if let stance {
            chips.append(.init(id: "stance", text: stance.label, color: .accentBlue, style: .tinted))
        }
        return chips
    }

    /// The one prose line under the chips.
    ///
    /// Patience USED to be spelled out here ("3 rounds of patience left"). It is
    /// now the round band's meter — the one place a process prints its count —
    /// so what survives is the character note, plus the pestering tally, which
    /// the band cannot show because a refusing camp is not spending rounds.
    private var headerNote: String {
        guard refusalReason != nil, pesterCount > 0 else { return agentPersona.styleDescription }
        return "\(agentPersona.styleDescription)  ·  \(pesterCount) offer\(pesterCount == 1 ? "" : "s") tabled since he declined"
    }

    private var headerNoteColor: Color {
        (refusalReason != nil && pesterCount >= 2) ? .dangerText : .textTertiaryReadable
    }

    // MARK: - Round Band

    /// The agent's patience, as the app's one process spine (§2.1).
    ///
    /// Two channels, two quantities, exactly as the band documents. The RIBBON is
    /// the run this conversation has actually had — every spoken round gets a
    /// slat, and an open thread always has one more to step into. The METER is
    /// the resource: `ContractDemand.maxRounds` is the engine's own patience
    /// model, and it SHRINKS as `insultCount` climbs, which is what a lowball
    /// costing the man's goodwill looks like from the GM's chair. Feeding that
    /// shrinking number to the ribbon printed a count the transcript contradicted
    /// — two lowballs and the band said "Round 2 of 2, done" with the composer
    /// still live — so it now drives only the meter.
    private var roundBand: some View {
        let used = thread?.round ?? 0
        let patience = max(1, liveDemand.maxRounds)
        return NegotiationRoundBand(
            used: used,
            limit: max(patience, used + (isNegotiationActive ? 1 : 0)),
            meter: DSResourceMeter(
                spent: min(used, patience),
                total: patience,
                unit: "rounds of patience"
            ),
            outcomes: roundOutcomes,
            isClosed: !isNegotiationActive,
            unit: "rounds of patience"
        )
    }

    /// What each finished round produced — the money the club tabled in it, read
    /// straight off the transcript so the band cannot quote a number the
    /// conversation does not contain.
    private var roundOutcomes: [Int: String] {
        var byRound: [Int: String] = [:]
        for message in thread?.messages ?? [] where message.sender == .you {
            guard let offer = message.offer else { continue }
            byRound[message.round] = formatMillions(offer.offer.annualSalary)
        }
        return byRound
    }

    // MARK: - Transcript

    /// The persisted messages, mapped onto the shared line model. The mapping is
    /// the whole of what this screen has to say about how a chat looks.
    private var chatLines: [NegotiationChatLine] {
        let speaker = thread?.agentName ?? agentName
        return (thread?.messages ?? []).map { message in
            var receipt: NegotiationChatLine.Receipt?
            if message.isSignedCard {
                receipt = NegotiationChatLine.Receipt(
                    title: isPayCut ? "Pay cut agreed" : "Contract signed"
                )
            }
            var tone: NegotiationChatLine.Tone?
            if !message.isSignedCard, let key = message.tone {
                tone = toneChip(key)
            }
            var attachment: AnyView?
            if let snapshot = message.offer {
                attachment = AnyView(offerCard(snapshot.offer, isAgent: message.sender == .agent))
            }
            return NegotiationChatLine(
                id: message.id,
                side: side(for: message.sender),
                speaker: speaker,
                text: message.text,
                tone: tone,
                isAlarmed: message.tone == .insulted,
                receipt: receipt,
                attachment: attachment
            )
        }
    }

    private func side(for sender: NegotiationThreadSender) -> NegotiationChatSide {
        switch sender {
        case .agent:  return .them
        case .you:    return .you
        case .system: return .system
        }
    }

    /// The badge on an agent line that names the tone it was said in. Only the
    /// tones a GM needs to READ are chipped — the rest is in the wording.
    private func toneChip(_ tone: AgentToneKey) -> NegotiationChatLine.Tone? {
        switch tone {
        case .insulted: return .init(label: "Ask hardened", color: .dangerText)
        case .refusing: return .init(label: "Refusing", color: .warning)
        case .eager:    return .init(label: "Ready to sign", color: .success)
        default:        return nil
        }
    }

    // MARK: - Offer Card (inside bubble)

    private func offerCard(_ offer: NegotiationOffer, isAgent: Bool) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 16) {
                offerStat("Years", "\(offer.years)")
                offerStat("Salary", formatMillions(offer.annualSalary))
                offerStat("Bonus", formatMillions(offer.signingBonus))
                offerStat("Gtd", "\(offer.guaranteedPercent)%")
            }

            // The AVERAGE, and labelled as one. `annualCapHit` is the number the
            // agent grades on (`closeTone(signedPerYear:)`), not the charge the
            // books take — see `writtenDeal` — and this bubble is the one money
            // surface here with no `Plan` in hand to price the schedule from. So
            // it states the term it can state truthfully and leaves the cost to
            // the composer's footer and the receipt, which both have the plan.
            Text("Avg: \(formatMillions(offer.annualCapHit))/yr")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(isAgent ? Color.textPrimary : Color.accentGold)

            // §5.5: clauses ride under the money so both bubbles show the same
            // deal the engine graded.
            if !offer.incentives.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(offer.incentives) { incentive in
                        HStack(spacing: 4) {
                            Image(systemName: "target")
                                .font(.system(size: DSType.Size.caption))
                                .foregroundStyle(Color.accentGold)
                            Text(incentive.summary)
                                .font(.system(size: DSType.Size.caption))
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                    Text("Max \(formatMillions(offer.maxValue))")
                        .font(.system(size: DSType.Size.caption, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.backgroundPrimary.opacity(0.5))
        )
    }

    private func offerStat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(Color.textPrimary)
            Text(label)
                .font(.system(size: DSType.Size.caption))
                .foregroundStyle(Color.textTertiary)
        }
    }

    // MARK: - Close Strip

    /// What replaces the composer once the conversation is over.
    ///
    /// **No button.** The outcome was delivered by `DSResultSheet` at the moment
    /// it happened, and the way out is the single X in the corner — the gold
    /// "Done" that used to sit here was the second half of the "Close"/"Done"
    /// pair the vision names by file (§P5's dismissal corollary). What survives
    /// is the reading half: the lingering grudge, and how long the door stays
    /// shut.
    private var closeStrip: some View {
        NegotiationCloseStrip(
            status: closeStatusLine,
            note: thread?.lingeringNote
        )
    }

    private var closeStatusLine: String {
        switch thread?.status {
        case .signed:
            return isPayCut
                ? "\(player.firstName) agreed to the reduced salary. The saving is already on your cap."
                : "\(player.fullName) is signed. The deal is on your books."
        case .walkedAway:
            return "You ended these talks. His camp will take another call."
        case .playerWalked:
            return "\(player.firstName)'s camp walked. They'll listen again next league year."
        // `.refused` is deliberately absent: that thread keeps its composer, so
        // it never reaches this strip. The only camp that genuinely will not
        // hear from you again this league year is the one that hung up on a
        // lowball.
        case .brokenOff:
            return "\(thread?.agentName ?? agentName) has cut off contract talks. You can reach out again next league year."
        default:
            // The pay-cut settled latch: the thread is still `.open`, but the
            // man has already given this league year's answer.
            return "\(player.fullName) already agreed to a reduced salary this league year. His camp will not revisit it until the new one."
        }
    }

    // MARK: - Commit Bar (§2.5)

    /// **The one place this screen commits.** One gold primary, the cap sentence
    /// as its explainer, and Walk Away as the destructive with the bar's own
    /// separating rule between them — instead of the three equal-weight
    /// full-width buttons that shipped.
    @ViewBuilder
    private var commitBar: some View {
        if isPayCut {
            DSActionBar(
                explainer: .init(
                    title: "Ask for a pay cut",
                    message: payCutExplainer,
                    isWarning: payCutSavings <= 0
                ),
                primary: .init(
                    title: "Ask for Pay Cut",
                    isEnabled: payCutSavings > 0,
                    accessibilityLabel: payCutSavings <= 0
                        ? "Ask for pay cut. Disabled: move the dial below his current salary first."
                        : "Asks \(player.firstName)'s agent to take \(formatMillions(payCutSalary)) per year.",
                    handler: { submitPayCut() }
                )
            )
        } else {
            DSActionBar(
                explainer: .init(
                    title: builderExceedsCap ? "Can't table this" : "Send this offer",
                    message: commitExplainerMessage,
                    isWarning: builderExceedsCap
                ),
                destructive: .init(
                    title: "Walk Away",
                    accessibilityLabel: "Walk away from talks with \(player.fullName)'s camp.",
                    handler: { walkAway() }
                ),
                secondary: acceptAction,
                primary: .init(
                    title: "Send Offer",
                    isEnabled: !builderExceedsCap,
                    accessibilityLabel: builderExceedsCap
                        ? "Send offer. Disabled: the offer exceeds your available cap space."
                        : (refusalReason != nil
                           ? "Tables this package at a camp that has declined to negotiate. The ask hardens and he loses morale."
                           : "Sends this package to the agent."),
                    handler: { submitCounterOffer() }
                )
            )
        }
    }

    /// "Accept Theirs", but only while there IS a standing number to accept.
    ///
    /// It carries its OWN cost as the button's caption. `DSActionBar` shows one
    /// explainer and that explainer belongs to the primary, so the only money
    /// sentence beside this button described the package in the composer — a
    /// different deal, and on a round-one thread routinely a third of the
    /// money. A commit that quotes the wrong number is worse than one that
    /// quotes none.
    private var acceptAction: DSActionBar.Action? {
        guard let snapshot = thread?.pendingAgentOffer else { return nil }
        let gate = capGate(for: snapshot.offer)
        let cost = acceptCostLine(for: gate)
        return DSActionBar.Action(
            title: "Accept Theirs",
            caption: cost,
            isEnabled: !gate.verdict.isBlocked,
            accessibilityLabel: gate.verdict.isBlocked
                ? "Accept their offer. Disabled: the agent's number exceeds your available cap space."
                : ["Signs the agent's standing offer.", cost].compactMap { $0 }.joined(separator: " "),
            handler: { acceptAgentOffer() }
        )
    }

    /// The agent's package priced, in the two short lines a button caption has.
    ///
    /// Deliberately terser than ``capSentence(for:)`` — that one is a full
    /// sentence for the explainer slot — but it keeps the discipline #127 bought:
    /// it names the year whenever the year is not the one that is open.
    private func acceptCostLine(for gate: DealGate) -> String? {
        guard capMode != .sandbox else { return nil }
        if let block = gate.verdict.block {
            return "Over \(String(block.season)) by \(formatMillions(block.overage))"
        }
        let net = gate.plan.netChargeInStartYear
        if net < 0 {
            return "Frees \(formatMillions(-net)) in \(String(gate.space.season))"
        }
        if gate.space.isProjected {
            return "Charges \(formatMillions(net)) of \(String(gate.space.season))'s \(formatMillions(gate.space.available))"
        }
        return "Charges \(formatMillions(net)) of your \(formatMillions(gate.space.available))"
    }

    /// The pay-cut bar's cost line: what the ask buys, and where it sits against
    /// what the league would pay him.
    private var payCutExplainer: String {
        guard payCutSavings > 0 else {
            return "Move the dial **below \(formatMillions(player.annualSalary))** — an ask for more money is an extension, and that talk has its own door."
        }
        return "Frees **\(formatMillions(payCutSavings))** this year. \(payCutMarketNote)"
    }

    // MARK: - Pay Cut Composer (#102)

    private var isPayCut: Bool { negotiationType == .payCut }

    /// The floor the dial cannot go under: the veteran minimum, from the engine
    /// that every other salary floor in the game comes from.
    private var payCutFloor: Int {
        ContractNegotiationEngine.veteranMinimum(salaryCap: salaryCap)
    }

    /// The ceiling: what he is paid today. Asking for MORE is an extension, and
    /// that conversation has its own door.
    private var payCutCeiling: Int { max(payCutFloor, player.annualSalary) }

    /// This year's cap relief the ask would buy.
    private var payCutSavings: Int { max(0, player.annualSalary - payCutSalary) }

    /// **The renegotiation composer.** One number, what it saves, and what the
    /// man is actually worth — the three facts a GM needs to know whether he is
    /// asking for help or asking for a favour he will pay for later.
    ///
    /// The market line is shown UNCONDITIONALLY, and that is the design: a pay
    /// cut is only signable where the player could not get the same money
    /// elsewhere, so hiding his market would make the lever a guessing game
    /// rather than a judgement. What stays hidden is his personal floor — that
    /// is what the agent is for.
    private var payCutComposer: some View {
        VStack(spacing: 12) {
            Rectangle()
                .fill(Color.surfaceBorder)
                .frame(height: 1)

            refusalBanner
            payCutOutcomeBanner

            VStack(spacing: 10) {
                builderRow(
                    label: "New Salary",
                    value: formatMillions(payCutSalary),
                    valueColor: .accentGold
                ) {
                    stepperButton(systemImage: "minus") {
                        payCutSalary = max(payCutFloor, payCutSalary - salaryStep)
                    }
                    .disabled(payCutSalary <= payCutFloor)
                } plus: {
                    stepperButton(systemImage: "plus") {
                        payCutSalary = min(payCutCeiling, payCutSalary + salaryStep)
                    }
                    .disabled(payCutSalary >= payCutCeiling)
                }

                Slider(
                    value: Binding(
                        get: { Double(payCutSalary) },
                        set: { payCutSalary = max(payCutFloor, min(payCutCeiling, Int(($0 / Double(salaryStep)).rounded()) * salaryStep)) }
                    ),
                    in: Double(payCutFloor)...Double(max(payCutFloor + salaryStep, payCutCeiling)),
                    step: Double(salaryStep)
                )
                .tint(Color.accentGold)
            }

            // What the dial costs and what it buys now lives in the action bar's
            // explainer, beside the commit it explains (§2.5) — printing it here
            // as well would state the same two facts twice on one screen. What
            // stays is the anchor the dial is measured against.
            HStack {
                Text("Current: \(formatMillions(player.annualSalary))/yr")
                    .font(DSType.display(11, .semibold))
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Text("Saves \(formatMillions(payCutSavings)) this year")
                    .font(DSType.display(11, .heavy))
                    .foregroundStyle(payCutSavings > 0 ? Color.success : Color.textTertiaryReadable)
            }
            .padding(.horizontal, DSSpacing.xxs)
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
        .frame(maxWidth: DSLayout.contentMeasure)
        .frame(maxWidth: .infinity)
        .background(Color.backgroundSecondary)
    }

    /// **The one market anchor on this screen**, in one set of words.
    ///
    /// Both composers open on it: the pay cut asks how far under it the man will
    /// go, the offer builder asks how far over it the club has to reach. Written
    /// once so the two branches cannot quote the same man at two prices.
    private var marketClause: String {
        "Market for a \(player.overall) OVR \(player.position.rawValue) is \(formatMillions(liveDemand.marketValue))/yr"
    }

    /// Where the dial sits against what the league would pay him.
    private var payCutMarketNote: String {
        let market = liveDemand.marketValue
        let delta = payCutSalary - market
        if delta >= 0 {
            return "\(marketClause) — you're still at or above it."
        }
        let pct = market > 0 ? Int((Double(-delta) / Double(market) * 100).rounded()) : 0
        return "\(marketClause) — this asks him to play \(pct)% under it."
    }

    /// The standing answer, kept under the composer so a release demand does not
    /// scroll away with the transcript. One shared `NegotiationNotice` shape,
    /// which is the same banner the refusal and the trade screen's league-office
    /// blockers now draw.
    @ViewBuilder
    private var payCutOutcomeBanner: some View {
        switch payCutLastOutcome {
        case .demandsRelease:
            NegotiationNotice(
                icon: "person.crop.circle.badge.xmark",
                color: .dangerText,
                title: "He wants his release",
                message: "\(player.firstName) would rather test the market than fund the club's cap. Release him from the Cap Compliance workspace, or leave the contract alone."
            )
        case .countered(let perYear):
            NegotiationNotice(
                icon: "arrow.left.arrow.right",
                color: .warning,
                title: "He'll go to \(formatMillions(perYear))",
                message: "That is his floor. Set the dial there and ask again, or walk away from it."
            )
        case .refused:
            NegotiationNotice(
                icon: "hand.raised.fill",
                color: .warning,
                title: "He said no",
                message: "You can ask again with a softer number. Whether he listens is his agent's call."
            )
        case .accepted, .none:
            EmptyView()
        }
    }

    // MARK: - Offer Builder

    private var offerBuilder: some View {
        VStack(spacing: 12) {
            Rectangle()
                .fill(Color.surfaceBorder)
                .frame(height: 1)

            // The stance banner. Shown ABOVE the composer rather than instead of
            // it: the user can still make the offer, and should — he just gets
            // to make it knowing what he is doing and what it will cost.
            refusalBanner

            VStack(spacing: 10) {
                // Years
                builderRow(label: "Years", value: "\(offerYears) yr\(offerYears == 1 ? "" : "s")") {
                    stepperButton(systemImage: "minus") { if offerYears > 1 { offerYears -= 1 } }
                        .disabled(offerYears <= 1)
                } plus: {
                    stepperButton(systemImage: "plus") { if offerYears < 6 { offerYears += 1 } }
                        .disabled(offerYears >= 6)
                }

                // Salary
                builderRow(label: "Salary", value: formatMillions(offerSalary), valueColor: .accentGold) {
                    stepperButton(systemImage: "minus") {
                        if offerSalary > minSalary { offerSalary -= salaryStep }
                    }
                    .disabled(offerSalary <= minSalary)
                } plus: {
                    stepperButton(systemImage: "plus") {
                        if offerSalary < maxSalary { offerSalary += salaryStep }
                    }
                    .disabled(offerSalary >= maxSalary)
                }

                // The salary dial's slider — the same one the pay-cut composer
                // has had since #102, for the same reason. At $500K a step, the
                // distance between a seeded counter and a top receiver's ask is
                // a dozen presses; the slider crosses it in one gesture and the
                // steppers stay for the last $500K.
                Slider(
                    value: Binding(
                        get: { Double(offerSalary) },
                        set: { offerSalary = roundToStep(Int($0.rounded())) }
                    ),
                    in: Double(minSalary)...Double(maxSalary),
                    step: Double(salaryStep)
                )
                .tint(Color.accentGold)

                // Signing bonus
                builderRow(label: "Bonus", value: formatMillions(offerBonus)) {
                    stepperButton(systemImage: "minus") {
                        if offerBonus >= bonusStep { offerBonus -= bonusStep }
                    }
                    .disabled(offerBonus <= 0)
                } plus: {
                    stepperButton(systemImage: "plus") {
                        offerBonus = min(maxBonus, offerBonus + bonusStep)
                    }
                    .disabled(offerBonus >= maxBonus)
                }

                // Guaranteed %
                builderRow(label: "Guaranteed", value: "\(offerGuaranteed)%") {
                    stepperButton(systemImage: "minus") {
                        if offerGuaranteed > 0 { offerGuaranteed -= guaranteedStep }
                    }
                    .disabled(offerGuaranteed <= 0)
                } plus: {
                    stepperButton(systemImage: "plus") {
                        if offerGuaranteed < 100 { offerGuaranteed += guaranteedStep }
                    }
                    .disabled(offerGuaranteed >= 100)
                }
            }

            // The anchor the dials are measured against, in the shape the
            // pay-cut composer states its own ("Current: … / Saves …"). The
            // offer builder shipped with no price context whatever: the only
            // numbers on the page were the agent's ask and whatever the
            // composer happened to be seeded with, so "is this close?" had no
            // answer anywhere on the screen.
            HStack {
                Text(marketClause)
                    .font(DSType.display(11, .semibold))
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Text(offerMarketNote)
                    .font(DSType.display(11, .heavy))
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.horizontal, DSSpacing.xxs)

            // The market is the league's price; the ASK is the number the gold
            // button is answering, and the composer opens seeded well under it
            // (`primeComposer`). Nothing said so, so the one obvious action on
            // the screen tabled a lowball the user never chose to make — and a
            // tabled lowball costs morale and hardens a refusing camp's ask.
            if let askNote = askGapNote {
                HStack {
                    Text(askNote)
                        .font(DSType.display(11, .semibold))
                        .foregroundStyle(Color.textTertiary)
                    Spacer()
                }
                .padding(.horizontal, DSSpacing.xxs)
            }

            // Cap impact preview
            capPreview

            // Performance clauses (TODO §5.5)
            incentiveSection

            // Yearly breakdown toggle
            yearlyBreakdownSection

            // The commit is NOT here any more — it is the `DSActionBar` below
            // this panel (§2.5: "the bar is the only place a screen commits").
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
        .frame(maxWidth: DSLayout.contentMeasure)
        .frame(maxWidth: .infinity)
        .background(Color.backgroundSecondary)
    }

    /// Where the composer sits against ``marketClause``.
    ///
    /// Measured on `annualCapHit`, not on the salary dial alone, because that is
    /// the number the agent grades — an offer that looks $7M light on salary and
    /// carries a $30M bonus is not light at all, and saying so off the salary
    /// dial would be a price the engine does not agree with.
    private var offerMarketNote: String {
        let delta = builderOffer.annualCapHit - liveDemand.marketValue
        if delta == 0 { return "Your offer is at market" }
        return delta > 0
            ? "Your offer is \(formatMillions(delta)) over it"
            : "Your offer is \(formatMillions(-delta)) under it"
    }

    /// Where the composer sits against the number his camp actually asked for,
    /// or `nil` when no ask is standing (a pay cut, a camp that never tabled
    /// one). Graded on `annualCapHit` for the same reason ``offerMarketNote``
    /// is: that is the figure the agent reads.
    private var askGapNote: String? {
        guard !isPayCut,
              let ask = (thread?.pendingAgentOffer ?? thread?.openingAsk)?.offer else { return nil }
        let delta = builderOffer.annualCapHit - ask.annualCapHit
        if delta == 0 { return "Matches his \(formatMillions(ask.annualCapHit))/yr ask" }
        return delta > 0
            ? "\(formatMillions(delta))/yr over his \(formatMillions(ask.annualCapHit)) ask"
            : "\(formatMillions(-delta))/yr under his \(formatMillions(ask.annualCapHit)) ask"
    }

    /// What his camp said, and the one thing that would change it.
    ///
    /// The exit condition is the whole reason this is a banner and not a locked
    /// door: a refusal the user cannot read is a wall, and a refusal that names
    /// its own exit is a puzzle. `neverSignsAtAnyPrice` gets the sharper framing
    /// because it is the only stance where tabling a better number is not a long
    /// shot but a category error.
    @ViewBuilder
    private var refusalBanner: some View {
        if let reason = refusalReason {
            NegotiationNotice(
                icon: reason.neverSignsAtAnyPrice ? "nosign" : "hand.raised.fill",
                color: reason.neverSignsAtAnyPrice ? .dangerText : .warning,
                title: reason.badgeLabel,
                message: reason.exitCondition,
                footnote: reason.neverSignsAtAnyPrice
                    ? "You can still table an offer. He will not read it as one — the ask hardens, and he hears about every call."
                    : "You can still table an offer. It will not be graded on the money, the ask hardens, and he hears about every call."
            )
        }
    }

    private func builderRow(
        label: String,
        value: String,
        valueColor: Color = .textPrimary,
        @ViewBuilder minus: () -> some View,
        @ViewBuilder plus: () -> some View
    ) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .frame(width: 90, alignment: .leading)

            Spacer()

            HStack(spacing: 12) {
                minus()
                Text(value)
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(valueColor)
                    .frame(minWidth: 64, alignment: .center)
                plus()
            }
        }
    }

    /// The money footer under the composer.
    ///
    /// #127 gave it a YEAR. It used to say "Charges $40.3M of your $27.2M in
    /// room" no matter which league year the deal actually started charging, so
    /// an offseason re-sign — the single most common contract talk in the game —
    /// was quoted against the cap of a season that had already been played. The
    /// deal's span is now stated out loud ("Covers 2027–2029") and the charge is
    /// measured against the projected cap of the year it lands in.
    ///
    /// A deal that starts THIS year — every free agency signing, every pay cut —
    /// keeps the original sentence verbatim, because for those it was right.
    ///
    /// #186 gave the line a third case. A long-term deal that retires a SETTLED
    /// franchise tag starts in the tag year, not after it, and saying so out
    /// loud is the difference between "why is this refusing me" and a mechanic
    /// the user can use: year one replaces the tag rather than stacking on it.
    private var capPreview: some View {
        let offer = builderOffer
        let plan = builderGate.plan
        // The written pair, not the flat one — otherwise this footer quotes an
        // average while the sentence under it quotes the charge derived from
        // year one, and the two cannot be reconciled by anyone reading them.
        // See `writtenDeal`.
        let written = writtenDeal(offer, plan: plan)

        return VStack(spacing: 4) {
            HStack {
                Text("Year 1: \(formatMillions(written.firstYearCapHit))")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.accentGold)
                Spacer()
                Text("Total: \(formatMillions(written.total))")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.textSecondary)
            }

            if let span = coverageLine(for: plan) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textTertiary)
                    Text(span)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textTertiary)
                    Spacer()
                }
            }

            // The cap SENTENCE moved to the action bar's explainer (§2.5) — it is
            // what committing costs, so it belongs beside the commit. Printing it
            // here as well would put the same clause on the screen twice, 40 pt
            // apart.
        }
        .padding(.horizontal, DSSpacing.xxs)
    }

    /// The span line under the composer, or `nil` for an ordinary deal that
    /// starts in the year that is open — there is nothing to explain about that
    /// one, and a line saying "Covers 2026" would be noise on every free-agent
    /// signing in the game.
    private func coverageLine(for plan: DealTargetYear.Plan) -> String? {
        switch plan.shape {
        case .deferredExtension:
            return "Covers \(DealTargetYear.yearSpan(plan)) — his current deal runs through \(String(plan.startSeason - 1))."
        case .tagReplacement:
            return "Covers \(DealTargetYear.yearSpan(plan)) — year one replaces his \(String(plan.startSeason)) franchise tag."
        case .currentYear:
            return nil
        }
    }

    /// What tabling this offer does, in the action bar's explainer slot.
    ///
    /// Sandbox keeps its own sentence rather than borrowing the cap one: with
    /// `exceedsCap` short-circuited there is no room to quote, and quoting it
    /// anyway would tell a sandbox GM he is $12M over something that cannot stop
    /// him.
    private var commitExplainerMessage: String {
        guard capMode != .sandbox else {
            return "Sends this package to \(thread?.agentName ?? agentName). **Sandbox cap** — no offer is blocked by room."
        }
        return capSentence(for: builderGate)
    }

    /// One sentence, and it always names the year it is talking about — the same
    /// year the gate tested and the booking will charge, because all three read
    /// one `Plan`.
    ///
    /// The refusal is not written here at all: `DealTargetYear.Block.message`
    /// owns it, so the composer, the pending-offer bar and any future surface
    /// refuse in identical words with the identical number. Writing it locally
    /// is precisely how this screen came to refuse a 2027 deal with a 2026
    /// figure.
    private func capSentence(for gate: DealGate) -> String {
        if let block = gate.verdict.block { return block.message }

        let plan = gate.plan
        let space = gate.space
        let net = plan.netChargeInStartYear
        let year = String(space.season)

        // A tag-and-extend that lands under the tag it retires FREES room, and
        // the whole commercial point of one is that it does. Reporting it as a
        // charge of "$0" (the old `max(0, …)`) hid the mechanic the user needs
        // to see to reach for it.
        if net < 0 {
            let freed = formatMillions(-net)
            let after = formatMillions(space.available - net)
            return plan.shape == .tagReplacement
                ? "Frees \(freed) in \(year) — year one lands under the \(formatMillions(plan.replacedCharge)) tag it retires, leaving \(after)."
                : "Frees \(freed) in \(year) — it comes in under the \(formatMillions(plan.replacedCharge)) already on his row, leaving \(after)."
        }

        if space.isProjected {
            return "Charges \(formatMillions(net)) against the projected \(year) cap of "
                + "\(formatMillions(space.cap)) — est. \(formatMillions(space.available - net)) free that year."
        }

        if plan.shape == .tagReplacement {
            return "Charges \(formatMillions(net)) of your \(formatMillions(space.available)) in room, "
                + "net of the \(formatMillions(plan.replacedCharge)) tag it retires."
        }

        // A re-sign nets what the club is ALREADY carrying for this man, and the
        // bare sentence never said so: "$46.0M/yr" in gold 40 pt above and
        // "Charges $14.2M" here read as a contradiction, with the $31.8M gap —
        // his old charge coming off the books — stated nowhere on the screen.
        // The other two shapes name what they net; this one now does too. A
        // free agent carries nothing, so he keeps the short sentence.
        if plan.replacedCharge > 0 {
            return "Charges \(formatMillions(net)) of your \(formatMillions(space.available)) in room — "
                + "\(formatMillions(plan.firstYearCapHit)) in year one, net of the "
                + "\(formatMillions(plan.replacedCharge)) he already carries."
        }

        return "Charges \(formatMillions(net)) of your \(formatMillions(space.available)) in room."
    }

    // MARK: - Incentive Section (TODO §5.5)

    /// The clauses currently ON the offer, in menu order.
    private var activeIncentives: [ContractIncentive] {
        incentiveMenu.filter { enabledIncentiveIDs.contains($0.id) }
    }

    /// What this agent will actually count the active clauses for, across the
    /// whole deal — the number that decides whether they close the gap.
    private var creditedIncentiveValue: Int {
        ContractEngine.creditedIncentiveValue(
            activeIncentives,
            player: player,
            persona: agentPersona,
            years: max(1, offerYears)
        )
    }

    private var incentiveSection: some View {
        VStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showIncentives.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Performance Incentives")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                    if !activeIncentives.isEmpty {
                        Text("\(activeIncentives.count)")
                            .font(.system(size: DSType.Size.caption, weight: .bold))
                            .foregroundStyle(Color.backgroundPrimary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentGold, in: Capsule())
                    }
                    Spacer()
                    Image(systemName: showIncentives ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                }
                .padding(.horizontal, 4)
            }
            .buttonStyle(.plain)
            .accessibilityHint(showIncentives ? "Collapse performance incentives" : "Expand performance incentives")

            if showIncentives {
                VStack(spacing: 8) {
                    if incentiveMenu.isEmpty {
                        Text("No clauses available for this position.")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(incentiveMenu) { incentive in
                            incentiveRow(incentive)
                        }
                        incentiveFooter
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.backgroundPrimary.opacity(0.5))
                )
            }
        }
    }

    private func incentiveRow(_ incentive: ContractIncentive) -> some View {
        let isOn = enabledIncentiveIDs.contains(incentive.id)
        return VStack(spacing: 4) {
            HStack(spacing: 8) {
                Button {
                    toggleIncentive(incentive)
                } label: {
                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: DSType.Size.callout))
                        .foregroundStyle(isOn ? Color.accentGold : Color.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isOn ? "Remove \(incentive.category.displayName) clause" : "Add \(incentive.category.displayName) clause")

                Text(incentive.category.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isOn ? Color.textPrimary : Color.textTertiary)

                Spacer()

                Text(ContractIncentive.money(incentive.bonusK))
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .foregroundStyle(isOn ? Color.accentGold : Color.textTertiary)
            }

            // Threshold dial. A binary clause (playoff berth) has nothing to
            // tune, so it shows its odds instead of a stepper.
            HStack(spacing: 10) {
                Text(incentive.category.isBinary ? "Reach the postseason" : "Tier")
                    .font(.system(size: DSType.Size.caption))
                    .foregroundStyle(Color.textTertiary)

                Spacer()

                if !incentive.category.isBinary {
                    stepperButton(systemImage: "minus") { adjustThreshold(incentive, direction: -1) }
                        .disabled(!isOn)
                    Text(incentive.category.format(incentive.threshold))
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                        .foregroundStyle(isOn ? Color.textPrimary : Color.textTertiary)
                        .frame(minWidth: 46)
                    stepperButton(systemImage: "plus") { adjustThreshold(incentive, direction: 1) }
                        .disabled(!isOn)
                }

                Text(likelihoodLabel(for: incentive))
                    .font(.system(size: DSType.Size.caption, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.textSecondary)
                    .frame(minWidth: 56, alignment: .trailing)
            }
        }
        .padding(.vertical, 2)
    }

    private var incentiveFooter: some View {
        VStack(spacing: 4) {
            Divider().overlay(Color.surfaceBorder.opacity(0.5))
            HStack {
                Text("Max \(formatMillions(ContractEngine.maxSeasonIncentiveValue(activeIncentives)))/yr")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Text("\(agentPersona.styleLabel) credits \(formatMillions(creditedIncentiveValue))")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(personaColor)
            }
            // Says the rule out loud so the cap treatment is never a surprise.
            Text("Charged to the cap only when earned, at season end.")
                .font(.system(size: DSType.Size.caption))
                .foregroundStyle(Color.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func likelihoodLabel(for incentive: ContractIncentive) -> String {
        let p = ContractEngine.incentiveLikelihood(incentive, player: player)
        return "\(Int((p * 100).rounded()))% odds"
    }

    /// Step size for one tap on the threshold dial — big enough to matter on a
    /// yardage tier, exact on a counting one.
    private func thresholdStep(for category: IncentiveCategory) -> Double {
        switch category {
        case .passYards, .rushYards, .recYards: return 50
        case .sacks:                            return 0.5
        default:                                return 1
        }
    }

    private func adjustThreshold(_ incentive: ContractIncentive, direction: Double) {
        guard let index = incentiveMenu.firstIndex(where: { $0.id == incentive.id }) else { return }
        let step = thresholdStep(for: incentive.category)
        // Floor at one step: a clause worth nothing to reach is not a clause.
        let next = max(step, incentiveMenu[index].threshold + direction * step)
        incentiveMenu[index] = ContractIncentive(
            category: incentiveMenu[index].category,
            threshold: next,
            bonusK: incentiveMenu[index].bonusK
        )
    }

    private func toggleIncentive(_ incentive: ContractIncentive) {
        if enabledIncentiveIDs.contains(incentive.id) {
            enabledIncentiveIDs.remove(incentive.id)
        } else {
            enabledIncentiveIDs.insert(incentive.id)
        }
    }

    /// Folds clauses the agent wrote himself into the builder, so the GM can see
    /// (and keep) what he is about to accept.
    private func absorbAgentIncentives(_ incentives: [ContractIncentive]) {
        for incentive in incentives {
            if let index = incentiveMenu.firstIndex(where: { $0.id == incentive.id }) {
                incentiveMenu[index] = incentive
            } else {
                incentiveMenu.append(incentive)
            }
            enabledIncentiveIDs.insert(incentive.id)
        }
        if !incentives.isEmpty { showIncentives = true }
    }

    // MARK: - Yearly Breakdown Section

    private var yearlyBreakdownSection: some View {
        VStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showYearlyBreakdown.toggle()
                }
            } label: {
                HStack {
                    Text("Yearly Breakdown")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Image(systemName: showYearlyBreakdown ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                }
                .padding(.horizontal, 4)
            }
            .buttonStyle(.plain)
            .accessibilityHint(showYearlyBreakdown ? "Collapse yearly breakdown" : "Expand yearly breakdown")

            if showYearlyBreakdown {
                let previewOffer = NegotiationOffer(
                    years: offerYears,
                    annualSalary: offerSalary,
                    signingBonus: offerBonus,
                    guaranteedPercent: offerGuaranteed,
                    noTradeClause: false
                )
                let breakdown = previewOffer.yearlyBreakdown(playerAge: player.age)

                VStack(spacing: 0) {
                    // Header row
                    HStack(spacing: 0) {
                        Text("Year")
                            .frame(width: 40, alignment: .leading)
                        Text("Base")
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Text("Bonus")
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Text("Cap Hit")
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Text("Dead Cap")
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .font(.system(size: DSType.Size.caption).weight(.bold))
                    .foregroundStyle(Color.textTertiary)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)

                    Divider().overlay(Color.surfaceBorder.opacity(0.5))

                    // Year rows
                    ForEach(breakdown) { year in
                        HStack(spacing: 0) {
                            Text("Yr \(year.yearNumber)")
                                .frame(width: 40, alignment: .leading)
                            Text(formatMillions(year.baseSalary))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            Text(formatMillions(year.proratedBonus))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            Text(formatMillions(year.capHit))
                                .foregroundStyle(Color.accentGold)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            Text(formatMillions(year.deadCapIfCut))
                                .foregroundStyle(Color.danger.opacity(0.8))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .font(.system(size: 10).weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color.textSecondary)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 8)
                    }

                    Divider().overlay(Color.surfaceBorder.opacity(0.5))

                    // Totals row
                    HStack(spacing: 0) {
                        Text("Total")
                            .frame(width: 40, alignment: .leading)
                        Text(formatMillions(breakdown.reduce(0) { $0 + $1.baseSalary }))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Text(formatMillions(breakdown.reduce(0) { $0 + $1.proratedBonus }))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Text(formatMillions(breakdown.reduce(0) { $0 + $1.capHit }))
                            .foregroundStyle(Color.accentGold)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Text("")
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .font(.system(size: 10).weight(.bold).monospacedDigit())
                    .foregroundStyle(Color.textPrimary)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                }
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.backgroundPrimary.opacity(0.5))
                )
            }
        }
    }

    // MARK: - Load

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true

        loadContext()

        // **A pay-cut talk never touches the thread store.**
        //
        // `NegotiationThreadStore` keys one thread per player per save, with no
        // room for the type — so resuming here would hand a pay-cut composer the
        // club's live EXTENSION transcript, and committing would overwrite it.
        // Neither is acceptable, and widening the store's key is a shared-model
        // change this screen has no business making.
        //
        // Nothing is lost by keeping it in memory: a pay cut is one question
        // with one answer, not a multi-round position that has to survive the
        // sheet. What DOES persist is the only thing that matters — the reduced
        // salary and the morale, both booked by `ContractEngine.applyPayCut`.
        if isPayCut {
            openNewThread()
            restorePayCutSettlement()
            return
        }

        // An existing conversation from THIS league year is resumed verbatim —
        // EXCEPT a refusal the man has since changed his mind about. A stance is
        // a mood, and freezing the verdict in the transcript meant a player
        // whose morale climbed from 44 to 70 in week 8 still read "Not talking"
        // for the rest of the season, with no lever he could pull.
        if let existing = NegotiationThreadStore.liveThread(for: player, season: season) {
            let stanceLifted = existing.status == .refused
                && !NegotiationLockRegistry.isLocked(player.id)
                && !liveDemand.isRefusing
            if !stanceLifted {
                thread = existing
                // Arrival, not a transition — the result sheet must not fire for
                // an ending the user already lived through (#105 Wave 3c).
                lastSeenStatus = existing.status
                restoreBuilder(from: existing)
                scrollTarget = existing.messages.last?.id
                return
            }
            // The door opened. **Continue the conversation rather than wiping
            // it**: this is the payoff for meeting the exit condition the banner
            // named — you started the winter being told no, you started him /
                // won games / gave him time, and now the same man is at the same
            // table. Opening a blank thread here (which is what shipped) threw
            // away the refusal, every offer tabled at it, and the entire reason
            // this moment means anything.
            reopenAfterStanceLift(existing)
            return
        }

        openNewThread()
    }

    /// **The pay-cut latch, restored from the save** (#102 F9).
    ///
    /// The transcript is deliberately in-memory (see `loadIfNeeded`), so the
    /// ONE fact that has to outlive the sheet is carried separately: whether
    /// this man has already given his answer this league year. Without it,
    /// dismissing and reopening handed the user a live composer on a player who
    /// had already signed a reduced deal — the same year's cap savings offered
    /// twice — which is exactly what `payCutSettled` was introduced to prevent
    /// and exactly what `@State` cannot do.
    private func restorePayCutSettlement() {
        guard PayCutRegistry.isSettled(playerID: player.id, season: season) else { return }
        payCutSettled = true
        guard var live = thread else { return }
        live.append(NegotiationThreadMessage(
            sender: .system,
            text: "\(player.fullName) already agreed to a reduced salary this league year. His camp will not revisit it until the new league year.",
            round: live.round
        ))
        commit(live)
    }

    /// Turns a refused thread back into a live negotiation, in place.
    ///
    /// The pestering history is deliberately KEPT — `insultCount` rides forward,
    /// so a GM who spent the autumn tabling offers at a man who kept saying no
    /// opens this conversation against a ratcheted ask. That is the cost of not
    /// listening, and it is not forgiven just because he is listening now.
    private func reopenAfterStanceLift(_ existing: NegotiationThread) {
        var live = existing
        // `generateOpeningDemand` cannot be used here: it opens at
        // `insultCount: 0`, which would hand the ask back at market and quietly
        // refund every offer tabled at the closed door. The demand model is
        // asked directly, with the count this thread actually carries.
        let opening = ContractNegotiationEngine.demand(
            player: player,
            negotiationType: negotiationType,
            salaryCap: salaryCap,
            situation: negotiationSituation,
            standing: gmStanding,
            insultCount: existing.insultCount ?? 0
        )
        let ask = opening.openingOffer
        let sel = selector(for: live, round: live.round)

        live.status = .open
        live.refusalReasonRaw = nil
        live.openingAsk = NegotiationOfferSnapshot(ask)
        live.pendingAgentOffer = NegotiationOfferSnapshot(ask)
        live.append(NegotiationThreadMessage(
            sender: .system,
            text: "\(live.agentName) called back — \(player.firstName)'s camp is willing to talk now.",
            round: live.round
        ))
        live.append(NegotiationThreadMessage(
            sender: .agent,
            text: openerText(demand: opening, ask: ask, sel: sel, isReopen: true),
            offer: NegotiationOfferSnapshot(ask),
            round: live.round,
            tone: opening.personaTone
        ))

        primeComposer(from: ask)
        commit(live, sel: sel)
    }

    /// Season, week, team and the user's standing — everything the demand model
    /// reads about the world, fetched once.
    private func loadContext() {
        guard let careerID = player.careerID else { return }
        if let found = (try? modelContext.fetch(FetchDescriptor<Career>()))?
            .first(where: { $0.id == careerID }) {
            career = found
            season = found.currentSeason
            currentWeek = found.currentWeek
        }
        if let teamID = player.teamID {
            team = (try? modelContext.fetch(FetchDescriptor<Team>()))?
                .first(where: { $0.id == teamID && $0.careerID == careerID })
            // #127/#186 — the club's forward payroll, for the projection
            // `DealTargetYear.space` builds when the deal binds in a later year.
            // Fetched for every own-club extension talk rather than only when
            // `contractYearsRemaining > 0`: the shape is the ENGINE's to decide
            // now, and it reads a pending tag's stashed `priorYears` in
            // preference to the clock the tag inflated, so the screen cannot
            // know from the clock alone whether a projection is coming. A free
            // agent (no club) and a pay cut (this year, by definition) still
            // pay for nothing.
            if negotiationType == .extend {
                let rosterDescriptor = FetchDescriptor<Player>(
                    predicate: #Predicate<Player> { $0.teamID == teamID }
                )
                teamRoster = (try? modelContext.fetch(rosterDescriptor)) ?? []
            }
        }
        // The detailed contract, so the gate nets against the same running
        // charge the booking nets against. Realistic mode only — the other two
        // write no `Contract` row, and `player.annualSalary` is the whole truth
        // there.
        if career?.capMode == .realistic {
            let playerID = player.id
            let contractDescriptor = FetchDescriptor<Contract>(
                predicate: #Predicate<Contract> { $0.playerID == playerID }
            )
            existingContract = try? modelContext.fetch(contractDescriptor).first
        }
        // Owner trust lives on its own row; the most recent one wins, and its
        // absence means the owner has never reacted to anything — which must
        // cost nothing, hence `GMStanding`'s neutral 70.
        if let reputation = (try? modelContext.fetch(FetchDescriptor<DraftReputation>()))?
            .filter({ $0.careerID == careerID })
            .max(by: { $0.seasonYear < $1.seasonYear }) {
            ownerTrust = reputation.ownerTrust
        }

        #if DEBUG
        logStanceCensus(careerID: careerID)
        #endif
    }

    #if DEBUG
    /// One line, once per app run, measuring the rarity budget against the live
    /// league instead of against the arithmetic in `ContractNegotiationEngine`'s
    /// doc comments. Grep for `STANCE-CENSUS`.
    ///
    /// Opening a Contact Agent thread is the cheapest honest trigger available:
    /// the fetch is already warm here, the numbers only mean anything mid-season
    /// (the record-driven stances all gate on `weeksPlayed >= 6`), and it costs
    /// a shipped build exactly nothing.
    private static var stanceCensusLogged = false

    private func logStanceCensus(careerID: UUID) {
        guard !Self.stanceCensusLogged else { return }
        Self.stanceCensusLogged = true
        let teams = ((try? modelContext.fetch(FetchDescriptor<Team>())) ?? [])
            .filter { $0.careerID == careerID }
        let players = ((try? modelContext.fetch(FetchDescriptor<Player>())) ?? [])
            .filter { $0.careerID == careerID && $0.teamID != nil }
        var records: [UUID: (wins: Int, losses: Int)] = [:]
        for t in teams { records[t.id] = (wins: t.wins, losses: t.losses) }
        let census = ContractNegotiationEngine.stanceCensus(
            players: players,
            recordByTeamID: records,
            season: season,
            weeksPlayed: currentWeek
        )
        print("STANCE-CENSUS season=\(season) week=\(currentWeek) \(census.summary)")
    }
    #endif

    private func openNewThread() {
        var newThread = NegotiationThread(
            playerID: player.id,
            playerName: player.fullName,
            agentName: agentName,
            persona: agentPersona,
            typeRaw: threadTypeRaw,
            season: season
        )
        let sel = selector(for: newThread, round: 0)

        // 1. A hardliner who was lowballed earlier this offseason. The freeze-out
        //    is a REFUSAL like any other now — he says it himself instead of the
        //    screen printing a banner at the user.
        if NegotiationLockRegistry.isLocked(player.id) {
            newThread.append(NegotiationThreadMessage(
                sender: .agent,
                text: AgentDialogue.brokenOffLine(voice: agentVoice, ctx: baseContext(), sel: sel),
                round: 0,
                tone: .refusing
            ))
            newThread.status = .brokenOff
            commit(newThread, sel: sel)
            return
        }

        // 2. A client with no interest in this building right now.
        //
        //    The verdict comes from `ContractNegotiationEngine.refusalVerdict`
        //    via the demand model, NOT from `AgentRefusalReason.evaluate`
        //    directly. Calling the stance model straight was what made the
        //    engine's own second door — a mercenary who will not sign up to lose
        //    for a front office he does not rate — unreachable, and with it the
        //    "a bad GM gets more refusals" half of the feature. The demand model
        //    also owns the extension-only rule (a free agent taking meetings is
        //    by definition at the table).
        let opening = ContractNegotiationEngine.generateOpeningDemand(
            player: player,
            negotiationType: negotiationType,
            salaryCap: salaryCap,
            situation: negotiationSituation,
            standing: gmStanding
        )

        if opening.demand.isRefusing, let reason = opening.demand.refusalReason {
            newThread.append(NegotiationThreadMessage(
                sender: .agent,
                text: AgentDialogue.refusalLine(
                    voice: agentVoice, reason: reason, ctx: baseContext(), sel: sel
                ),
                round: 0,
                tone: .refusing
            ))
            newThread.status = .refused
            newThread.refusalReasonRaw = reason.rawValue
            // The composer survives a refusal, so it has to be primed for one
            // too. Without this the dials sat at the $5M default and the user's
            // first act of pestering was a lowball he never meant to make.
            primeComposer(from: opening.demand.openingOffer)
            // The ring-chaser does not merely decline — he asks out, publicly.
            // News plus a flag the trade AI reads, and nothing more: see
            // `TradeRequestRegistry` for why a request must never move a player
            // on its own.
            if reason == .ringChasing { fileTradeRequest() }
            commit(newThread, sel: sel)
            return
        }

        // 3. He'll talk. The engine prices the ask; the agent says it out loud.
        let ask = opening.offer

        // A pay-cut call opens with NO offer card and NO standing agent offer:
        // nobody has asked the club for anything, and rendering the extension
        // ask he would have wanted underneath "I know why you're calling" would
        // quote a raise in a conversation about a reduction. The demand is still
        // computed — the market value it carries is what the composer prices
        // against — it simply is not spoken as an offer.
        if !isPayCut {
            newThread.openingAsk = NegotiationOfferSnapshot(ask)
            newThread.pendingAgentOffer = NegotiationOfferSnapshot(ask)
        }
        newThread.append(NegotiationThreadMessage(
            sender: .agent,
            text: openerText(demand: opening.demand, ask: ask, sel: sel),
            offer: isPayCut ? nil : NegotiationOfferSnapshot(ask),
            round: 0,
            // The engine's own opening frame, not a second copy of the rule.
            tone: opening.demand.personaTone
        ))

        primeComposer(from: ask)
        commit(newThread, sel: sel)
    }

    /// The agent's opening line: hello, what his client is after, and the number
    /// it takes.
    ///
    /// Two branches. A client who won a prove-it bet opens by saying so, because
    /// the user WROTE that bet last winter and the mechanic is worthless if he
    /// cannot see it pay out. A client whose refusal has just lifted opens with
    /// the reopener, which is the same desire and the same number said by a man
    /// who was saying no last month.
    private func openerText(
        demand: ContractDemand,
        ask: NegotiationOffer,
        sel: DialogueSelector,
        isReopen: Bool = false
    ) -> String {
        let ctx = context(ask: ask)
        if demand.stance == .provenBet, !isReopen {
            return AgentDialogue.provenBetLine(voice: agentVoice, ctx: ctx, sel: sel)
        }
        let want = AgentDesire.primary(player: player, demand: demand)
        if isReopen {
            return AgentDialogue.reopener(voice: agentVoice, desire: want, ctx: ctx, sel: sel)
        }
        // A pay-cut call has no ask to open with — the CLUB is about to ask. The
        // agent picks up knowing why the phone rang, which is the engine's own
        // opening copy for this type.
        if isPayCut {
            return ContractNegotiationEngine.generateOpeningDemand(
                player: player,
                negotiationType: .payCut,
                salaryCap: salaryCap,
                situation: negotiationSituation,
                standing: gmStanding
            ).message
        }
        return AgentDialogue.opener(
            voice: agentVoice,
            desire: want,
            isExtension: negotiationType.isOwnClub,
            ctx: ctx,
            sel: sel
        )
    }

    /// The transcript's own discriminator. `NegotiationType` is not `Codable`,
    /// so the thread stores the string — see `NegotiationThread.typeRaw`.
    private var threadTypeRaw: String {
        switch negotiationType {
        case .extend:    return "extend"
        case .freeAgent: return "freeAgent"
        case .payCut:    return "payCut"
        }
    }

    /// Pre-fills the composer slightly below the ask and prices the clause menu.
    private func primeComposer(from ask: NegotiationOffer) {
        // The pay-cut dial opens at his MARKET, not at a fraction of his ask:
        // market is the number a cut can realistically land on, so the composer
        // starts at the reasonable request and lets the user push from there.
        if isPayCut {
            payCutSalary = max(payCutFloor, min(payCutCeiling, liveDemand.marketValue))
        }
        offerYears = ask.years
        offerSalary = roundToStep(Int(Double(ask.annualSalary) * 0.85))
        offerBonus = roundToStep(Int(Double(ask.signingBonus) * 0.75))
        offerGuaranteed = max(0, ask.guaranteedPercent - 10)

        // §5.5: the clause menu is priced off the agent's ASK, not off the
        // pre-filled lowball, so the bonuses stay stable while the GM works the
        // salary dial. Every clause starts switched OFF.
        incentiveMenu = ContractEngine.suggestedIncentives(
            player: player,
            annualSalaryK: ask.annualSalary
        )
        enabledIncentiveIDs = []
    }

    // MARK: - Trade Request (ring-chaser)

    /// Files a public trade request: a news story and a flag, through the
    /// machinery that already exists.
    ///
    /// **Minimal on purpose.** `HoldoutEngine.forceTrade` is the precedent for
    /// "a player actually leaves", and it is a much heavier thing — a valuation,
    /// a partner, an executed `TradeRecord`, dead money. A REQUEST is the step
    /// before that: the league finds out, the trade AI starts treating him as
    /// available (`TradeValueEngine.saleCandidates`), and the decision about
    /// what to do next stays with the user, who is the one being asked. No new
    /// trade mechanics, and nothing here moves a player.
    private func fileTradeRequest() {
        guard let career, let team else { return }
        guard TradeRequestRegistry.record(playerID: player.id, season: season) else { return }
        // F-49(1): `append` on a newest-first, 150-truncated list is a silent
        // no-op once the career is established. `postNews` prepends.
        career.postNews(NewsItem(
            headline: "\(player.fullName) asks \(team.abbreviation) for a trade",
            body: "\(player.fullName)'s agent went public today, saying the \(player.position.rawValue) has told the club he wants to play for a contender. "
                + "\"This isn't about money,\" the agent said. \"He's given this building his best football and watched it go nowhere. He wants a chance to win.\" "
                + "The \(team.abbreviation) front office has not commented.",
            category: .trade,
            week: currentWeek,
            season: season,
            relatedTeamID: team.id,
            relatedPlayerID: player.id,
            sentiment: .negative
        ))
        try? modelContext.save()
    }

    /// Puts the composer back where a resumed conversation left it.
    private func restoreBuilder(from existing: NegotiationThread) {
        // A pay-cut thread has no standing offer to restore from — the dial is
        // the whole composer. The settled latch comes from `PayCutRegistry`
        // rather than from the thread's status (#102 F9): a pay-cut transcript
        // never reaches the store, so `existing.status` could not be the source
        // of truth here and this branch is only reachable defensively at all.
        if isPayCut {
            payCutSettled = PayCutRegistry.isSettled(playerID: player.id, season: season)
            payCutSalary = max(payCutFloor, min(payCutCeiling, liveDemand.marketValue))
            return
        }
        // A refused thread has neither a standing counter nor an opening ask —
        // nobody ever put a number on the table. It still has a live composer,
        // so it is primed off the demand model instead of left on the defaults.
        guard let reference = existing.pendingAgentOffer ?? existing.openingAsk else {
            if existing.status == .refused {
                primeComposer(from: liveDemand.openingOffer)
            }
            return
        }
        offerYears = reference.years
        offerSalary = roundToStep(Int(Double(reference.annualSalary) * 0.9))
        offerBonus = roundToStep(Int(Double(reference.signingBonus) * 0.8))
        offerGuaranteed = max(0, reference.guaranteedPercent - 5)

        if let ask = existing.openingAsk {
            incentiveMenu = ContractEngine.suggestedIncentives(
                player: player,
                annualSalaryK: ask.annualSalary
            )
        }
        enabledIncentiveIDs = []
        absorbAgentIncentives(reference.incentives)
    }

    // MARK: - Actions

    private func submitCounterOffer() {
        guard var live = thread, live.status.acceptsOffers else { return }

        // A refusing camp has no standing offer to counter, so this path forks
        // before the normal one: there is nothing to grade the money against
        // because the money was never the question.
        if live.status == .refused {
            pester(&live)
            return
        }

        guard live.isOpen, let askSnapshot = live.pendingAgentOffer else { return }
        let agentAsk = askSnapshot.offer

        let gmOffer = builderOffer
        // The cap gate. The button is disabled here too, so this is the belt to
        // that braces — but a negotiation is the one screen where "the club
        // cannot fit this" has to be unconditional.
        guard !exceedsCap(gmOffer) else { return }

        live.round += 1
        let round = live.round
        let sel = selector(for: live, round: round)

        live.append(NegotiationThreadMessage(
            sender: .you,
            text: AgentDialogue.gmOfferLine(round: round, playerFirst: player.firstName, sel: sel),
            offer: NegotiationOfferSnapshot(gmOffer),
            round: round
        ))

        // The engine decides — the verdict, the counter AND the tone it is
        // spoken in. Everything below only chooses the words.
        let result = ContractNegotiationEngine.evaluateCounterOffer(
            gmOffer: gmOffer,
            player: player,
            previousAgentOffer: agentAsk,
            roundNumber: round,
            negotiationType: negotiationType,
            salaryCap: salaryCap,
            situation: negotiationSituation,
            standing: gmStanding,
            insultCount: live.insultCount ?? 0
        )
        // Persisted so the patience cost of a lowball survives the round: the
        // demand is a pure function, so a count that lives only in this call is
        // a count that is always zero.
        live.insultCount = result.insultCount

        // What the CLIENT wants, graded off the demand this round produced —
        // every line below weaves it, so the user can read the man out of the
        // way his agent argues.
        let want = AgentDesire.primary(player: player, demand: result.demand)

        switch result.outcome {
        case .dealReached(let finalOffer):
            close(&live, with: finalOffer, round: round, demand: result.demand, sel: sel)

        case .negotiationsBrokenOff:
            live.append(NegotiationThreadMessage(
                sender: .agent,
                text: AgentDialogue.brokenOffLine(
                    voice: agentVoice, ctx: context(ask: agentAsk, gmOffer: gmOffer), sel: sel
                ),
                round: round,
                tone: .insulted
            ))
            live.status = .brokenOff
            live.pendingAgentOffer = nil
            NegotiationLockRegistry.lock(player.id)
            live.append(NegotiationThreadMessage(
                sender: .system,
                text: "\(live.agentName) has cut off contract talks for \(player.fullName) until next league year.",
                round: round
            ))

        case .playerWalked:
            live.append(NegotiationThreadMessage(
                sender: .agent,
                text: AgentDialogue.walkAwayLine(
                    voice: agentVoice,
                    ctx: context(ask: agentAsk, gmOffer: gmOffer), sel: sel
                ),
                round: round,
                tone: .hardline
            ))
            live.status = .playerWalked
            live.pendingAgentOffer = nil

        case .pending, .walkedAway:
            guard let counter = result.counterOffer else {
                // The engine kept talks open without a counter — nothing to say
                // that the transcript does not already show.
                break
            }
            // The engine's verdict, not a second opinion computed here.
            let tone = result.tone
            let ctx = context(ask: counter, gmOffer: gmOffer, rounds: round)
            let text: String = {
                // The one case the engine answers with structure rather than
                // money: the deal is too long for the man's body.
                if result.isYearsPushback {
                    return AgentDialogue.yearsPushbackLine(
                        voice: agentVoice,
                        age: player.age,
                        requestedYears: gmOffer.years,
                        maxYears: ContractNegotiationEngine.maxContractYears(forAge: player.age),
                        ctx: ctx,
                        sel: sel
                    )
                }
                return AgentDialogue.counterLine(
                    voice: agentVoice, desire: want, tone: tone, ctx: ctx, sel: sel
                )
            }()

            live.append(NegotiationThreadMessage(
                sender: .agent,
                text: text,
                offer: NegotiationOfferSnapshot(counter),
                round: round,
                tone: tone
            ))
            live.pendingAgentOffer = NegotiationOfferSnapshot(counter)
            absorbAgentIncentives(counter.incentives)
        }

        commit(live, sel: sel)
    }

    // MARK: - Pay Cut (#102)

    /// **One pay-cut ask, start to finish.**
    ///
    /// The shape mirrors ``submitCounterOffer`` deliberately — the club's line,
    /// the engine's verdict, the agent's answer, one commit — because it is the
    /// same conversation with the money pointing the other way. What it does NOT
    /// do is run a bid loop: there is no standing counter to accept, no patience
    /// meter to spend and no walk-away, because a pay cut is a question with an
    /// answer rather than a negotiation with a midpoint. Ask again with a
    /// different number and you get a different answer; that is the whole loop.
    ///
    /// **The cap write is the host's.** This function moves the man's morale and
    /// his `annualSalary` is left alone here: `onPayCutAgreed` hands the agreed
    /// number to the surface that knows which `Contract` row backs him and which
    /// ledger to charge. A chat that reached into `Team.currentCapUsage` would be
    /// a fifth place that books cap money, which is the exact class of split #68
    /// spent a wave closing.
    private func submitPayCut() {
        guard var live = thread, live.status.acceptsOffers, !payCutSettled else { return }
        guard payCutSalary < player.annualSalary else { return }

        // Presentation-only snapshot (#105 Wave 3c) — see `salaryBeforeClose`.
        // Taken before any consent hook can reprice the man.
        salaryBeforeClose = player.annualSalary

        // #102 F7 — a refusing camp is not a free suggestion box.
        //
        // `NegotiationThreadStatus.acceptsOffers` is deliberately true for `.refused`
        // (a front office is always allowed to table something), and
        // `submitCounterOffer` pays for that privilege by forking into
        // `pester`: the ask ratchets, the ledger books an insult, the man loses
        // morale and the agent's answers sharpen. This screen shipped the same
        // permission with none of the price, so a client who had declined to
        // negotiate could be asked to take a pay cut every round of the season
        // for nothing. Same fork, same consequences — the money pointing the
        // other way does not make the phone call less unwelcome.
        if live.status == .refused {
            pester(&live, payCutAsk: payCutSalary)
            return
        }

        live.round += 1
        let round = live.round
        let sel = selector(for: live, round: round)

        let verdict = ContractNegotiationEngine.payCutVerdict(
            player: player,
            demand: liveDemand,
            currentSalary: player.annualSalary,
            proposedSalary: payCutSalary,
            salaryCap: salaryCap
        )

        // The club's line quotes the number on the dial; the agent's quotes the
        // engine's counter where there is one. Both come out of one `Context`,
        // so the transcript can never disagree with itself.
        var ctx = baseContext()
        ctx.offerPerYear = formatMillions(payCutSalary)
        ctx.askPerYear = formatMillions(verdict.concessionFloor)

        live.append(NegotiationThreadMessage(
            sender: .you,
            text: AgentDialogue.payCutAskLine(playerFirst: player.firstName, ctx: ctx, sel: sel),
            round: round
        ))
        live.append(NegotiationThreadMessage(
            sender: .agent,
            text: AgentDialogue.payCutAnswerLine(
                voice: agentVoice, outcome: verdict.outcome, ctx: ctx, sel: sel
            ),
            round: round,
            tone: verdict.tone
        ))

        payCutLastOutcome = verdict.outcome

        switch verdict.outcome {
        case .accepted:
            live.append(NegotiationThreadMessage(
                sender: .system,
                text: "\(player.fullName) agreed to a reduced salary — \(formatMillions(payCutSalary))/yr, freeing \(formatMillions(verdict.savings)) of cap space this year.",
                round: round,
                isSignedCard: true
            ))
            live.status = .signed
            live.closeToneRaw = verdict.tone.rawValue
            payCutSettled = true
            // #102 F9 — the latch outlives the sheet. `@State` alone let a
            // dismiss-and-reopen sell the same year's savings twice.
            PayCutRegistry.recordSettled(playerID: player.id, season: season)

            // A cut he consented to still stings, and the roster keeps showing
            // it. The morale itself is written by `ContractEngine.applyPayCut`
            // through the host — see `onPayCutAgreed` for why this path does not
            // touch `player.morale` directly.
            if !live.moraleApplied {
                live.moraleApplied = true
                live.lingeringNote = "Took a pay cut to keep the roster together. He'll remember who asked."
            }
            onPayCutAgreed?(payCutSalary, verdict.moraleDelta)

        case .demandsRelease:
            // The ask is the insult, whether or not the club follows through —
            // but ONCE per league year (#102 F9). The charge used to be re-run
            // on every reopen of the sheet, so closing and reopening a demanded
            // release was a −12 morale button the user could hold down.
            if PayCutRegistry.chargeReleaseDemand(playerID: player.id, season: season) {
                player.morale = max(1, min(100, player.morale + ContractNegotiationEngine.payCutReleaseDemandMoraleCost))
                try? modelContext.save()
            }
            onReleaseDemanded?()

        case .countered(let perYear):
            // Put his floor on the dial so the next ask is one tap away.
            payCutSalary = max(payCutFloor, min(payCutCeiling, perYear))

        case .refused:
            break
        }

        commit(live, sel: sel)
    }

    // MARK: - Pestering

    /// An offer tabled at a client who has already declined to negotiate.
    ///
    /// **This is a full mechanic, not a rejection message.** The engine grades
    /// nothing (the money was never the question), and the four things that
    /// happen instead are the four things that would actually happen: the
    /// standing ask ratchets 6 % (`respond`'s pestering path calls
    /// `ContractDemand.escalated`), the ledger books it as an insult so it rides
    /// into every future negotiation in the league, the man himself loses
    /// `pesterMoraleCost` morale because his agent tells him about the call, and
    /// the agent's answer gets sharper each time.
    ///
    /// The cap gate still applies. An offer the club cannot fit is not a
    /// legitimate way to annoy somebody.
    ///
    /// - Parameter payCutAsk: set when the thing being tabled is a pay-cut ask
    ///   rather than a contract offer (#102 F7). A pay cut has one term, no
    ///   offer card and — because it only ever LOWERS the club's charge — no cap
    ///   gate to clear; everything after the club's own line is identical,
    ///   which is the point of routing it through here instead of writing the
    ///   ratchet a second time.
    private func pester(_ live: inout NegotiationThread, payCutAsk: Int? = nil) {
        let gmOffer: NegotiationOffer
        if let payCutAsk {
            gmOffer = NegotiationOffer(
                years: max(1, player.contractYearsRemaining),
                annualSalary: payCutAsk,
                signingBonus: 0,
                guaranteedPercent: 0,
                noTradeClause: false
            )
        } else {
            gmOffer = builderOffer
            guard !exceedsCap(gmOffer) else { return }
        }

        let attempt = (live.pesterCount ?? 0) + 1
        live.pesterCount = attempt
        live.round += 1
        let round = live.round
        let sel = selector(for: live, round: round)

        if let payCutAsk {
            var ctx = baseContext()
            ctx.offerPerYear = formatMillions(payCutAsk)
            live.append(NegotiationThreadMessage(
                sender: .you,
                text: AgentDialogue.payCutAskLine(
                    playerFirst: player.firstName, ctx: ctx, sel: sel
                ),
                round: round
            ))
        } else {
            live.append(NegotiationThreadMessage(
                sender: .you,
                text: AgentDialogue.gmOfferLine(round: round, playerFirst: player.firstName, sel: sel),
                offer: NegotiationOfferSnapshot(gmOffer),
                round: round
            ))
        }

        // The engine owns the consequence; this only chooses the words. Note
        // that `previousAgentOffer` is the GM's own offer here — a refusing camp
        // has no standing number, and `respond` short-circuits before it reads
        // one, so passing the offer back is honest rather than a placeholder.
        let result = ContractNegotiationEngine.evaluateCounterOffer(
            gmOffer: gmOffer,
            player: player,
            previousAgentOffer: gmOffer,
            roundNumber: round,
            negotiationType: negotiationType,
            salaryCap: salaryCap,
            situation: negotiationSituation,
            standing: gmStanding,
            insultCount: live.insultCount ?? 0
        )
        live.insultCount = result.insultCount

        let reason = live.refusalReason ?? .losingCulture
        live.append(NegotiationThreadMessage(
            sender: .agent,
            text: AgentDialogue.pesteringLine(
                voice: agentVoice,
                reason: reason,
                attempt: attempt,
                ctx: context(ask: gmOffer, gmOffer: gmOffer, rounds: round),
                sel: sel
            ),
            round: round,
            tone: .refusing
        ))

        // He hears about it. Small, and cumulative — which is the point.
        player.morale = max(1, min(100, player.morale - ContractNegotiationEngine.pesterMoraleCost))
        try? modelContext.save()

        // The third time, say out loud what has been happening to the price.
        if attempt >= 3 {
            live.append(NegotiationThreadMessage(
                sender: .system,
                text: "\(player.fullName)'s asking price has hardened \(attempt) times since his camp declined to negotiate.",
                round: round
            ))
        }

        commit(live, sel: sel)
    }

    private func acceptAgentOffer() {
        guard var live = thread, live.isOpen, let snapshot = live.pendingAgentOffer else { return }
        guard !exceedsCap(snapshot.offer) else { return }
        let round = live.round
        let sel = selector(for: live, round: round)

        live.append(NegotiationThreadMessage(
            sender: .you,
            text: "We accept your terms. Let's get it signed.",
            offer: snapshot,
            round: round
        ))
        // This path does NOT go through `respond`, so the ledger write that
        // lives there never fires — which is why the GM's negotiating
        // reputation could only ever get worse: every insult was recorded and
        // the most natural way to close a deal was not.
        close(&live, with: snapshot.offer, round: round, demand: liveDemand,
              sel: sel, recordToLedger: true)
        // The handshake spent the round the user was standing in. Without this
        // the band RETRACTED on signing — "Round 2 of 3" became "1 round
        // spoken" with round 2 hatched as never used, under a transcript that
        // now held a second YOU bubble and the close — and the result sheet
        // said "closed it after 1 round" about the same two exchanges.
        //
        // Advanced AFTER `close`, deliberately: the engine's close tone (and
        // through it the morale it books) grades the round the accepted offer
        // was made in, and that is the round it was made in.
        live.round = round + 1
        commit(live, sel: sel)
    }

    private func walkAway() {
        guard var live = thread, live.isOpen else { return }
        live.append(NegotiationThreadMessage(
            sender: .you,
            text: "We're going to pass. Thank you for your time.",
            round: live.round
        ))
        live.append(NegotiationThreadMessage(
            sender: .system,
            text: "You ended talks with \(player.fullName)'s camp.",
            round: live.round
        ))
        live.status = .walkedAway
        live.pendingAgentOffer = nil
        commit(live)
    }

    // MARK: - Close

    /// Signs the deal: the agent's closing line in the tone of the JOURNEY, the
    /// inline receipt, the clause commit, the host's contract write, and the
    /// morale/motivation consequence. No dismiss — that is the user's call.
    private func close(
        _ live: inout NegotiationThread,
        with offer: NegotiationOffer,
        round: Int,
        demand: ContractDemand,
        sel: DialogueSelector,
        recordToLedger: Bool = false
    ) {
        // Presentation-only snapshot (#105 Wave 3c) — see `capChargeAtClose`.
        // Taken FIRST, before the receipt is written and before the host's
        // contract write moves `player.annualSalary`: the receipt is priced off
        // this plan's schedule, and the shape is read off a player the signature
        // is about to change.
        salaryBeforeClose = player.annualSalary
        yearsBeforeClose = player.contractYearsRemaining
        let signedPlan = dealPlan(for: offer)
        planAtClose = signedPlan
        capChargeAtClose = signedPlan.netChargeInStartYear

        // ECONOMY owns the verdict; this file only decides how it is said and
        // what it does to the man.
        let openerPerYear = live.openingAsk.map { $0.offer.annualCapHit } ?? offer.annualCapHit
        let tone = ContractNegotiationEngine.closeTone(
            signedPerYear: offer.annualCapHit,
            openingAskPerYear: openerPerYear,
            rounds: round,
            demand: demand
        )
        if recordToLedger { NegotiationLedger.recordSigning(tone: tone) }
        let ctx = context(ask: offer, signed: offer, rounds: round)
        let want = AgentDesire.primary(player: player, demand: demand)

        live.append(NegotiationThreadMessage(
            sender: .agent,
            text: AgentDialogue.acceptLine(
                voice: agentVoice, desire: want, tone: tone, ctx: ctx, sel: sel
            ),
            round: round,
            tone: tone
        ))
        live.append(NegotiationThreadMessage(
            sender: .system,
            text: signedSummary(offer, plan: signedPlan),
            offer: NegotiationOfferSnapshot(offer),
            round: round,
            isSignedCard: true
        ))

        live.status = .signed
        live.closeToneRaw = tone.rawValue
        live.pendingAgentOffer = nil

        // §5.5: the clauses ride onto the player here rather than in
        // `onDealCompleted` — four screens present this view and each applies
        // the money its own way, so a clause that only survived on some of those
        // paths would be worse than no clause at all.
        ContractIncentiveRegistry.set(offer.incentives, for: player)

        // The prove-it bet, booked and settled in the one place a contract is
        // actually signed.
        //
        // Booking it: a short deal to a client the engine graded prove-it IS the
        // bet, and next winter's demand model has no other way to know it
        // happened (see `ProveItRegistry`). Settling it: a man who just cashed a
        // proven bet has been paid for it, and leaving the flag standing would
        // charge the club the same premium every year forever.
        if demand.stance == .provenBet {
            ProveItRegistry.clear(playerID: player.id)
        } else if demand.isProveIt, offer.years <= 2 {
            ProveItRegistry.record(playerID: player.id, season: season)
        }
        // He signed. Whatever he was asking the league for, he is staying.
        TradeRequestRegistry.clear(playerID: player.id)

        if !live.moraleApplied {
            live.moraleApplied = true
            live.lingeringNote = applyCloseEffects(tone: tone, desire: want, ctx: ctx, sel: sel)
        }

        onDealCompleted?(offer)
    }

    /// Tone -> morale/motivation. Modest by design: a negotiation moves a man's
    /// head, it does not rebuild him.
    ///
    /// Returns the lingering note a begrudging close leaves behind, if any.
    @discardableResult
    private func applyCloseEffects(
        tone: AgentToneKey,
        desire: AgentDesire,
        ctx: AgentDialogue.Context,
        sel: DialogueSelector
    ) -> String? {
        var note: String?
        switch tone {
        case .eager:
            // Got his number, got it fast. Small lift, and he shows up with
            // something to prove rather than a cheque to cash.
            player.morale = max(1, min(100, player.morale + 5))
            if player.motivationState != .driven {
                player.motivationState = .driven
            }
        case .professional:
            player.morale = max(1, min(100, player.morale + 2))
        default:
            // Ground down below his ask. He signs, and he remembers.
            player.morale = max(1, min(100, player.morale - 4))
            note = AgentDialogue.lingeringNote(desire: desire, ctx: ctx, sel: sel)
        }
        try? modelContext.save()
        return note
    }

    // MARK: - Tone
    //
    // There is nothing here on purpose. Every tone in this screen —
    // the opener's, each counter's and the close's — is
    // `ContractNegotiationEngine`'s verdict, read off `ContractDemand`,
    // `ChatVerdict.tone` and `closeTone(signedPerYear:…)` respectively.
    //
    // The three functions that used to live here re-derived it from
    // `NegotiationOffer.totalValue` while the engine graded `annualCapHit`, and
    // the two metrics disagreed in both directions: a shorter, richer package
    // rendered as a red "Ask hardened" bubble on an offer the engine called
    // professional, and a longer, thinner one rendered green on a hardline
    // counter. The close was worse — it charged 4 points of morale and left a
    // grudge note for deals the engine graded delighted.

    // MARK: - Dialogue Context

    private func baseContext() -> AgentDialogue.Context {
        AgentDialogue.Context(
            playerFirst: player.firstName,
            playerFull: player.fullName,
            position: player.position.rawValue,
            // A noun phrase, so the free-agent fallback reads as English in the
            // same sentence the real club does — see `Context.team`.
            team: team.map { "the \($0.name)" } ?? "this club"
        )
    }

    /// Fills the line-pool context from offers the ENGINE produced, so the money
    /// in the sentence and the money on the card underneath are the same money.
    private func context(
        ask: NegotiationOffer,
        gmOffer: NegotiationOffer? = nil,
        signed: NegotiationOffer? = nil,
        rounds: Int = 0
    ) -> AgentDialogue.Context {
        var ctx = baseContext()
        ctx.askPerYear = formatMillions(ask.annualSalary)
        ctx.askTotal = formatMillions(ask.totalValue)
        ctx.askYears = ask.years
        if let gmOffer {
            ctx.offerPerYear = formatMillions(gmOffer.annualSalary)
        }
        if let signed {
            ctx.signedPerYear = formatMillions(signed.annualSalary)
            ctx.signedTotal = formatMillions(signed.totalValue)
            ctx.signedYears = signed.years
        }
        ctx.rounds = rounds
        return ctx
    }

    /// The receipt copy — names the clause ceiling when the deal has one, so the
    /// GM never signs clauses without seeing what they can cost.
    ///
    /// Priced off the plan the deal is BOOKED with, not off the bargained
    /// average (`writtenDeal`), and the guarantee is stated in money for the
    /// same reason: the percent is a percent of a package the row never holds.
    private func signedSummary(_ offer: NegotiationOffer, plan: DealTargetYear.Plan) -> String {
        let written = writtenDeal(offer, plan: plan)
        let base = "\(player.fullName) — \(offer.years) year\(offer.years == 1 ? "" : "s"), \(formatMillions(written.total)) total, \(formatMillions(written.guaranteed)) guaranteed."
        guard !offer.incentives.isEmpty else { return base }
        // The clause ceiling rides on the written total, so the two numbers in
        // the sentence are measured the same way.
        let ceiling = written.total + (offer.maxValue - offer.totalValue)
        return base + " \(offer.incentives.count) performance clause\(offer.incentives.count == 1 ? "" : "s") take it to \(formatMillions(ceiling)) if he hits them all."
    }

    // MARK: - Persistence

    /// Writes the thread to state AND to the save. Every mutation goes through
    /// here — a transcript that only exists in `@State` is the bug this wave
    /// was opened to fix.
    ///
    /// - Parameter sel: the picker that chose this exchange's lines, if any. Its
    ///   memory rides onto the thread here rather than at each call site, so a
    ///   new dialogue site cannot forget to persist its own no-repeat state.
    private func commit(_ updated: NegotiationThread, sel: DialogueSelector? = nil) {
        var updated = updated
        if let sel { updated.lastLineIndex = sel.lastIndex }
        let previous = lastSeenStatus
        thread = updated
        scrollTarget = updated.messages.last?.id
        announce(status: updated.status, from: previous)
        // Pay-cut talks stay in memory — see `loadIfNeeded` for why writing one
        // would clobber the player's extension transcript.
        guard !isPayCut else { return }
        if let careerID = player.careerID {
            NegotiationThreadStore.upsert(updated, careerID: careerID)
        }
    }

    // MARK: - Result (#105 Wave 3c)

    /// **Raises the result sheet on a TRANSITION, and never on arrival.**
    ///
    /// `previous == nil` is the load pass — a thread that was already broken off
    /// last month, or a pay-cut thread rebuilt in memory on every open, must not
    /// greet the user with a modal about something he already knows. `.refused`
    /// is not an ending either: that camp still has a live composer, and the
    /// pestering mechanic is the whole point of leaving it there.
    private func announce(status: NegotiationThreadStatus, from previous: NegotiationThreadStatus?) {
        lastSeenStatus = status
        guard let previous, previous != status else { return }
        guard status.isTerminal, status != .refused else { return }
        outcome = makeOutcome(for: status)
    }

    /// The ending, in `DSResultSheet`'s grammar: what happened, what changed,
    /// what it cost.
    private func makeOutcome(for status: NegotiationThreadStatus) -> NegotiationOutcome {
        let signed = thread?.messages.last(where: { $0.isSignedCard })?.offer?.offer
        switch status {
        case .signed where isPayCut:
            return NegotiationOutcome(
                tone: .good,
                headline: "\(player.firstName) takes the cut",
                message: "His camp signed off on **\(formatMillions(payCutSalary))** a year for the rest of the deal.",
                chips: [
                    .init(id: "was", label: "Was", value: "\(formatMillions(salaryBeforeClose))/yr"),
                    .init(id: "now", label: "Now", value: "\(formatMillions(payCutSalary))/yr", valueColor: .accentGold),
                    .init(
                        id: "freed",
                        label: "Freed",
                        value: formatMillions(max(0, salaryBeforeClose - payCutSalary)),
                        valueColor: .success
                    )
                ],
                cost: thread?.lingeringNote
                    ?? "He agreed, and he'll remember who asked. Morale is already booked against him."
            )

        case .signed:
            let offer = signed ?? builderOffer
            let plan = planAtClose ?? dealPlan(for: offer)
            let written = writtenDeal(offer, plan: plan)
            // He was already on this club's books, so the sheet has a BEFORE to
            // state. A free agent has none — nothing on these books changed
            // when his old club's deal ran out.
            let wasUnderContract = yearsBeforeClose > 0 && salaryBeforeClose > 0
            // Year one, because year one is what the books take and what the
            // cost line under these chips is netted from. The average survives
            // as the context line when the two differ — see `writtenDeal` and
            // `Plan.flatCapHit` — but the BEFORE outranks it when there is one:
            // the section is headed WHAT CHANGED and every figure under it was
            // an absolute, so the one thing it never said was what changed.
            let payContext: String?
            if wasUnderContract {
                payContext = "was \(formatMillions(salaryBeforeClose))/yr"
            } else if offer.years > 1, written.firstYearCapHit != plan.flatCapHit {
                payContext = "then \(formatMillions(plan.flatCapHit))/yr"
            } else {
                payContext = nil
            }
            return NegotiationOutcome(
                tone: .good,
                headline: "\(player.fullName) signs for \(offer.years) year\(offer.years == 1 ? "" : "s")",
                message: "\(thread?.agentName ?? agentName) closed it after \(roundsSpoken) round\(roundsSpoken == 1 ? "" : "s").",
                chips: [
                    .init(
                        id: "years",
                        label: "Years",
                        value: "\(offer.years)",
                        context: wasUnderContract ? "was \(yearsBeforeClose) left" : nil
                    ),
                    .init(
                        id: "aav",
                        label: "Year 1 cap",
                        value: formatMillions(written.firstYearCapHit),
                        context: payContext,
                        valueColor: .accentGold
                    ),
                    .init(id: "total", label: "Total", value: formatMillions(written.total)),
                    .init(id: "gtd", label: "Guaranteed", value: formatMillions(written.guaranteed))
                ],
                cost: signedCostLine(offer)
            )

        case .playerWalked:
            return NegotiationOutcome(
                tone: .bad,
                headline: "\(player.firstName)'s camp walked",
                message: "They stopped short of a deal. Nothing is signed, and nothing is on your cap.",
                chips: [],
                cost: "The talk is over for now. His camp will take another call, and the ask you hardened stays hardened."
            )

        case .brokenOff:
            return NegotiationOutcome(
                tone: .bad,
                headline: "\(thread?.agentName ?? agentName) hung up",
                message: "He has cut off contract talks for \(player.fullName) until the new league year.",
                chips: [],
                cost: "No further offers this league year — and the insults on the ledger ride into every negotiation the league has with you."
            )

        case .walkedAway:
            return NegotiationOutcome(
                tone: .neutral,
                headline: "You ended the talks",
                message: "Nothing was signed. His camp holds no grudge for a front office that says no politely.",
                chips: [],
                cost: "The thread stays saved. You can call again from his player card."
            )

        default:
            return NegotiationOutcome(
                tone: .neutral,
                headline: "Talks are over",
                message: nil,
                chips: [],
                cost: nil
            )
        }
    }

    /// Rounds the two sides actually spoke — `thread.round` counts the club's
    /// turns, and the opener is round 0.
    private var roundsSpoken: Int { max(1, thread?.round ?? 1) }

    /// What the signature just did to the books.
    ///
    /// It reads `planAtClose`, not a fresh plan: by the time this sheet renders,
    /// the host has already written the deal onto the player, so re-planning
    /// would describe the contract as it now stands rather than the transaction
    /// that produced it.
    ///
    /// The deferred line used to end *"and the new rate goes on this year's
    /// books the moment he signs"*. That was true of the old booking and is a
    /// lie about the new one — #186 parks a deferred extension on the forward
    /// ledger and leaves the open year alone — so it says what actually
    /// happened.
    private func signedCostLine(_ offer: NegotiationOffer) -> String {
        guard capMode != .sandbox else {
            return "**Sandbox cap** — the deal is on the roster and charges nothing you have to fit."
        }
        let plan = planAtClose ?? dealPlan(for: offer)

        if plan.booksForward {
            return "Charges **\(formatMillions(plan.flatCapHit))** from \(String(plan.startSeason)) — this year's books are untouched until then."
        }

        let net = capChargeAtClose ?? plan.netChargeInStartYear
        if net < 0 {
            return plan.shape == .tagReplacement
                ? "**Frees \(formatMillions(-net))** this year — the \(formatMillions(plan.replacedCharge)) tag comes off as the deal goes on."
                : "**Frees \(formatMillions(-net))** this year against what he was already carrying."
        }
        if plan.shape == .tagReplacement {
            return "Charges **\(formatMillions(net))** this year, net of the \(formatMillions(plan.replacedCharge)) tag it retires."
        }
        return "Charges **\(formatMillions(net))** of your \(formatMillions(teamCapSpace)) in room."
    }

    // MARK: - Helpers

    private var positionSideColor: Color {
        switch player.position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }

    /// Persona accent color for the agent chip.
    private var personaColor: Color {
        switch agentPersona {
        case .hardliner:   return .danger
        case .cooperative: return .success
        case .loyalist:    return .accentGold
        }
    }

    /// A 28 pt chip inside a 44 pt target. The chip is what the composer's rows
    /// are drawn to; the target is what a thumb needs, and the dial a GM presses
    /// a dozen times to cross a salary range is the last control in the app that
    /// should be under it.
    private func stepperButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: DSType.Size.body, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 28, height: 28)
                .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: 6))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func roundToStep(_ value: Int) -> Int {
        let rounded = (value / salaryStep) * salaryStep
        return max(minSalary, min(maxSalary, rounded))
    }

    private func formatMillions(_ thousands: Int) -> String {
        let millions = Double(thousands) / 1000.0
        if millions >= 1.0 {
            return String(format: "$%.1fM", millions)
        }
        return "$\(thousands)K"
    }
}
