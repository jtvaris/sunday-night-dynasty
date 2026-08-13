import Foundation

// MARK: - Deal Target Year (#186)

/// **Which league year a negotiated contract actually charges, and whether the
/// club can carry it in that year.**
///
/// The bug this closes. `ContractNegotiationView` printed
/// *"Covers 2027–2030 — his current deal runs through 2026"* directly above
/// *"CAN'T TABLE THIS — over this year's cap by $6.1M — the new rate goes on the
/// books as soon as he signs, not in 2027."* The screen knew the deal was a 2027
/// deal and refused it on 2026's bank balance, because the only thing the engine
/// could do with a signature was charge it to the open league year
/// (`ContractEngine.applyNegotiatedDeal`, #127's documented residue). A gate is
/// only honest if it measures the money against the year the money lands in, and
/// the booking is only honest if it lands there.
///
/// So this file owns the answer to one question — *what year is this, and what
/// does it cost in that year* — and both halves read it:
///
/// * the GATE (`verdict(...)`) asks whether the binding year can carry the
///   charge, and hands back the year and the shortfall so the refusal can name
///   them;
/// * the BOOKING (`ContractEngine.applyNegotiatedDeal`) charges the same year,
///   with the same numbers, off the same ``Plan``.
///
/// They cannot drift, because neither computes anything: both are handed one
/// `Plan` built by ``plan(player:offer:application:capMode:currentSeason:hasRolledOver:careerID:existingContract:)``.
///
/// **The three shapes a deal can have.** They are not a UI flavour — they are
/// facts about the player's books, which is why the plan reads the player and
/// not the screen he was opened from:
///
/// 1. **Tag replacement** — his tag has already been SETTLED
///    (`FreeAgencyEngine.settleFranchiseTags` consumed the forward row, so the
///    tag is his `annualSalary` and is sitting in `currentCapUsage`). Read off
///    `Player.franchiseTagSeason`, because the settling rollover clears
///    `isFranchiseTagged` in the same pass and the flag would answer "no" for
///    every man this case is about.
///    A long-term deal signed now is the NFL's tag-and-extend: it replaces the
///    tag contract, its first year IS the tag year, and the tag's charge comes
///    off the current year as the deal's charge goes on. It does not stack on
///    top of the tag year and it is not a deal about next season.
/// 2. **Deferred extension** — he is under contract for `N` more years and the
///    new years are added on top. The money starts `N` league years from here;
///    the open year is untouched, and the charge is parked on
///    `CommittedCapLedger`'s forward table until the rollover that opens its
///    binding season.
/// 3. **Current year** — a free agent, a re-sign of an expiring deal, or a
///    pay-cut reprice. Charges the year that is open, netting whatever the club
///    is already carrying for the man.
///
/// A **pending** tag (the forward row is still there, i.e. the tag was applied
/// this offseason and the rollover has not settled it) is deliberately NOT case
/// 1. In that state the tag has never touched the current year — it is only a
/// forward reservation — so there is nothing to net and nothing to relieve;
/// `ContractEngine.applyNegotiatedDeal` releases the row and the deal is then
/// planned by the ordinary rules. The tag hit has two different homes depending
/// on which side of the rollover you are standing, and only one of them is on
/// this year's books.
enum DealTargetYear {

    // MARK: - Shape

    /// Which of the three shapes above a deal has.
    enum Shape: Equatable {
        /// Replaces a settled franchise tag; year 1 is the tag year.
        case tagReplacement
        /// Adds years after the deal that is running; money starts later.
        case deferredExtension
        /// Charges the league year that is open.
        case currentYear
    }

    // MARK: - Plan

    /// Everything the gate and the booking both need, computed once.
    ///
    /// Every money field is in thousands, the unit `Team.currentCapUsage` is
    /// kept in.
    struct Plan: Equatable {

        let shape: Shape

        /// The first league year this deal charges. Equal to the OPEN league
        /// year (see ``openSeason(currentSeason:hasRolledOver:)``) for the two
        /// immediate shapes.
        let startSeason: Int

        /// `startSeason - openSeason`. 0 = the open year.
        let seasonsAhead: Int

        /// The deal's term, as the CONTRACT will carry it — `offer.years` for a
        /// replacement, `remaining + offer.years` for an extension stacked on a
        /// running deal.
        let contractYears: Int

        /// The last league year the deal charges.
        ///
        /// ``contractYears`` is the CLOCK, counted from the open year — for a
        /// deferred extension it already contains the `remaining` years of the
        /// deal that is running, and ``startSeason`` is already those years
        /// ahead. Adding the whole clock to `startSeason` would count them
        /// twice, and printed a four-year extension on a two-year deal as
        /// "Covers 2028–2033". Only the NEW years run from `startSeason`, which
        /// is `contractYears - seasonsAhead` of them — and that is exactly the
        /// term `ContractEngine.applyNegotiatedDeal` writes onto the forward
        /// row (`years: max(1, offer.years)`), so the two agree by construction.
        var lastSeason: Int {
            startSeason + Swift.max(1, contractYears - seasonsAhead) - 1
        }

        /// The base-salary schedule the deal is written with, in realistic mode.
        /// Empty in the other two modes, which carry no per-year structure.
        let baseSalaries: [Int]

        /// The signing bonus, prorated over ``contractYears``.
        let proratedBonus: Int

        /// **What the binding year actually carries.**
        ///
        /// Realistic mode structures a deal, so year one is `baseSalary[0]`
        /// plus the prorated bonus and is NOT the average. Simple and sandbox
        /// have no schedule at all, so year one is the flat `annualCapHit` —
        /// and the gate says the same thing, because the books will.
        ///
        /// A DEFERRED deal is the exception and it is not an inconsistency: its
        /// binding year is rebuilt by `executeNewLeagueYear`'s cap true-up from
        /// `Player.annualSalary`, which is the flat rate, so the flat rate is
        /// what that year will really carry. The rule is the same in all three
        /// shapes — *charge what the books will show* — and only the books
        /// differ.
        let firstYearCapHit: Int

        /// What every year after the first carries: `offer.annualCapHit`, the
        /// flat rate `Player.annualSalary` is written with and the rollover
        /// true-up re-sums each March.
        let flatCapHit: Int

        /// What comes OFF the binding year's books when the deal is signed: the
        /// settled tag for a tag replacement, the running charge for a re-sign,
        /// 0 for a free agent and 0 for a deferred extension (by the time it
        /// binds, the old deal has already expired).
        let replacedCharge: Int

        /// The number the gate tests and the ledger moves by:
        /// ``firstYearCapHit`` less ``replacedCharge``. Negative when a
        /// tag-and-extend frees room, which is the whole point of one.
        var netChargeInStartYear: Int { firstYearCapHit - replacedCharge }

        /// Whether signing retires a franchise tag.
        let retiresFranchiseTag: Bool

        /// Whether the charge is parked on the forward ledger instead of being
        /// booked against the open year.
        var booksForward: Bool { shape == .deferredExtension }
    }

    // MARK: - The Open League Year

    /// **The league year the club's books are actually in.**
    ///
    /// `Career.currentSeason` is NOT that year for six phases of every
    /// offseason. `FreeAgencyEngine.executeNewLeagueYear` opens the new league
    /// year — decrementing every `contractYearsRemaining`, settling the tags,
    /// re-summing the cap — while the career is still in `.freeAgency`, but the
    /// season counter is only bumped at the rosterCuts→regularSeason boundary
    /// (`WeekAdvancer`). So from proDays through rosterCuts `currentSeason` is
    /// one BEHIND the year the money is being spent in.
    ///
    /// Every part of the app that has to know which side of March it is on
    /// tests the rollover stamp — `WeekAdvancer`'s compliance window and
    /// `FranchiseTagView`'s re-sign `+1` both read
    /// `career.lastRolloverSeason >= career.currentSeason` — and this file does
    /// the same rather than inventing a second convention. Deal arithmetic that
    /// skipped it bound a deferred extension one year early, i.e. onto the last
    /// year of the deal it was extending, and charged the club the new rate for
    /// a year it never agreed to buy.
    ///
    /// A caller with no season (harness, preview) passes 0 and gets 0 back: no
    /// season means no rollover to reason about.
    static func openSeason(currentSeason: Int, hasRolledOver: Bool) -> Int {
        guard currentSeason > 0, hasRolledOver else { return currentSeason }
        return currentSeason + 1
    }

    // MARK: - Planning

    /// Builds the plan. **The one place the three shapes are told apart.**
    ///
    /// - Parameter currentSeason: `Career.currentSeason`, raw. It does not
    ///   advance across the offseason, so it is turned into the year the books
    ///   are in by ``openSeason(currentSeason:hasRolledOver:)`` before any
    ///   binding year is derived from it.
    /// - Parameter hasRolledOver: `career.lastRolloverSeason >= career.currentSeason`
    ///   — whether `executeNewLeagueYear` has already opened the next league
    ///   year. Defaults to `false`, which is the pre-rollover reading and the
    ///   behaviour every caller had before this parameter existed.
    /// - Parameter careerID: the save whose forward table decides whether a tag
    ///   is pending or already settled. A nil reads as "no row", i.e. settled,
    ///   which is the safe direction: it nets the tag off the current year
    ///   rather than charging it twice.
    static func plan(
        player: Player,
        offer: NegotiationOffer,
        application: ContractEngine.DealApplication,
        capMode: CapMode,
        currentSeason: Int,
        hasRolledOver: Bool = false,
        careerID: UUID?,
        existingContract: Contract? = nil
    ) -> Plan {
        let offerYears = Swift.max(1, offer.years)

        // A tag that still has its forward row has never charged the open year;
        // one whose row the rollover consumed IS the open year's salary.
        let pendingRow = player.isFranchiseTagged
            ? CommittedCapLedger.forwardCommitment(
                playerID: player.id,
                careerID: careerID,
                kind: .franchiseTag
            )
            : nil
        let tagPending = pendingRow != nil

        // A settled tag is read off `franchiseTagSeason` and NOT off the flag:
        // the rollover that settles the tag clears the flag in the same pass, so
        // by the time the tag is the man's salary he no longer carries one. See
        // `Player.franchiseTagSeason`. `>=` rather than `==` because
        // `currentSeason` does not advance across the offseason (see the note on
        // this function), so a tag that settled into league year N reads
        // `currentSeason == N - 1` for the rest of that offseason and `N` once
        // the season starts — both of them the tag year.
        // A caller with no season to pass (harness, a save the career could not
        // be read from) gets 0, and 0 cannot decide whether a tag year is still
        // running — so it does not decide: the deal is planned by the ordinary
        // rules, which is the pre-#186 behaviour and never invents relief.
        // DELIBERATELY the raw counter and not `openSeason`: the `>=` is written
        // to be true on BOTH sides of the rollover, which is the whole point of
        // it, and re-basing it would need `==` to say the same thing.
        let playingOutTag = currentSeason > 0
            && player.franchiseTagSeason > 0
            && player.franchiseTagSeason >= currentSeason
            && player.contractYearsRemaining > 0
        let settledTag = !tagPending && (player.isFranchiseTagged || playingOutTag)

        // The clock as it will stand ONCE THE SIGNATURE RESCINDS THE TAG, which
        // is the number the new years are added to. `applyFranchiseTag` floors
        // the clock at 1 and stashes what it raised on the row; `applyNegotiatedDeal`
        // undoes that before it writes the term, so a plan built off the flag's
        // inflated clock would hand out a year the club never agreed to.
        let remaining = Swift.max(0, pendingRow?.priorYears ?? player.contractYearsRemaining)

        let shape: Shape = {
            if settledTag { return .tagReplacement }
            if application == .extendExisting && remaining > 0 { return .deferredExtension }
            return .currentYear
        }()

        // The term. A replacement does not stack — its first year IS the year
        // the old deal would have covered — so a 4-year deal that retires a
        // 1-year tag is four league years, not five.
        let contractYears: Int = {
            switch shape {
            case .tagReplacement, .currentYear: return offerYears
            case .deferredExtension: return remaining + offerYears
            }
        }()

        let seasonsAhead = shape == .deferredExtension ? remaining : 0
        let prorated = contractYears > 0 ? offer.signingBonus / contractYears : 0

        // What the club is carrying for this man right now, read with exactly
        // the precedence `applyNegotiatedDeal` reads it with.
        let runningCharge = existingContract?.capHit ?? player.annualSalary
        let replacedCharge: Int = {
            switch shape {
            case .tagReplacement: return Swift.max(0, player.annualSalary)
            case .currentYear: return Swift.max(0, runningCharge)
            case .deferredExtension: return 0
            }
        }()

        // **The tag-and-extend ceiling.** A club retires a $41.9M tag in order
        // to get UNDER it — that is the entire commercial reason the mechanism
        // exists. A schedule whose first year costs more than the tag it just
        // replaced is not an extension, it is a penalty for signing one, and no
        // front office writes it: the deal is structured so year one lands at or
        // below the tag, and the money is pushed into the later years the deal
        // was negotiated for. Nothing is forgiven — `cappedFirstYear` preserves
        // the schedule's total to the thousand.
        //
        // Note the direction the un-ceilinged schedule would go: a tagged
        // veteran is over 28, so `frontLoadedBaseSalaries` opens 15 % ABOVE the
        // average and a tag-and-extend would make the current year worse than
        // doing nothing. That is the arithmetic that produced the refusal in the
        // report.
        let ceiling: Int? = shape == .tagReplacement
            ? Swift.max(500, player.annualSalary - prorated)
            : nil

        let baseSalaries: [Int] = capMode == .realistic
            ? ContractEngine.negotiatedBaseSalaries(
                annualSalary: offer.annualSalary,
                years: contractYears,
                age: player.age,
                firstYearCeiling: ceiling
            )
            : []

        let firstYearCapHit: Int = {
            switch shape {
            case .deferredExtension:
                // Settled by the rollover true-up off `annualSalary` — see the
                // note on `Plan.firstYearCapHit`.
                return offer.annualCapHit
            case .tagReplacement, .currentYear:
                guard capMode == .realistic, let first = baseSalaries.first else {
                    return offer.annualCapHit
                }
                return first + prorated
            }
        }()

        return Plan(
            shape: shape,
            // Off the OPEN year, never the raw counter — see `openSeason`. Post
            // rollover the extension's years are counted from the league year
            // the club is already spending in, which is the year
            // `settleFranchiseTags` will look for when it collects the forward
            // row (`bindingSeason = currentSeason + 1`).
            startSeason: openSeason(currentSeason: currentSeason, hasRolledOver: hasRolledOver)
                + seasonsAhead,
            seasonsAhead: seasonsAhead,
            contractYears: contractYears,
            baseSalaries: baseSalaries,
            proratedBonus: prorated,
            firstYearCapHit: firstYearCapHit,
            flatCapHit: offer.annualCapHit,
            replacedCharge: replacedCharge,
            retiresFranchiseTag: player.isFranchiseTagged || shape == .tagReplacement
        )
    }

    // MARK: - Room in the Binding Year

    /// Cap, commitments and what is left — for ONE league year, named.
    struct Space: Equatable {

        /// The league year these three numbers describe.
        let season: Int

        /// `0` for the open year.
        let seasonsAhead: Int

        /// The club's cap that year: the real one now, the league's own
        /// projection later (`ContractEngine.projectedCap`).
        let cap: Int

        /// Salary the club already owes that year.
        let committed: Int

        /// Whether `cap` is a projection rather than the club's actual number.
        var isProjected: Bool { seasonsAhead > 0 }

        var available: Int { cap - committed }
    }

    /// **The room a deal has to fit into, in the year it binds.**
    ///
    /// One function, so no two surfaces can quote two futures. It is the
    /// arithmetic `CapOverviewView.committedCap`, `ContractTimelineView` and the
    /// dashboard's cap-outlook tile all perform by hand today, with two
    /// corrections that only an engine-side version can make honestly:
    ///
    /// * **the man being negotiated is excluded from his own target year.** A
    ///   tagged player's forward row was being added to the very year his
    ///   extension was being measured against, so a tag-and-extend was charged
    ///   against itself before it existed.
    /// * **every forward row counts, not just tags.** `forwardCommitted` is
    ///   player-scoped on purpose (an orphaned row must not keep charging a club
    ///   for a man it released), and callers used to pass only the tagged men.
    ///   Deferred extensions live in the same table now, so the ids passed are
    ///   the whole roster and the year bound on each row does the filtering.
    static func space(
        team: Team,
        roster: [Player],
        currentSeason: Int,
        hasRolledOver: Bool = false,
        seasonsAhead: Int,
        careerID: UUID?,
        excluding excludedPlayerID: UUID?
    ) -> Space {
        // The year the club's books are in, which is what `currentCapUsage` and
        // every `contractYearsRemaining` below are already counted from once the
        // rollover has run. See `openSeason`.
        let openYear = openSeason(currentSeason: currentSeason, hasRolledOver: hasRolledOver)

        guard seasonsAhead > 0 else {
            return Space(
                season: openYear,
                seasonsAhead: 0,
                cap: team.salaryCap,
                committed: team.currentCapUsage
            )
        }

        let season = openYear + seasonsAhead
        let others = roster.filter { $0.id != excludedPlayerID }

        // **A forward row SUPERSEDES the salary on the man's row for the years
        // it covers — it does not add to it.** A deferred extension writes the
        // whole contract clock the day it is signed and deliberately leaves
        // `annualSalary` at the old rate until its binding rollover, so for
        // exactly those years both tests below are true of the same player: he
        // is "still under contract" at $12M *and* he has a $30M row. Counting
        // both charges the club $42M for a $30M deal, and every further
        // deferral on the roster widens the error. The tag escapes it only
        // because of a flag; a deferred deal has no flag, so the coverage map
        // is what does the netting.
        let coverage = CommittedCapLedger.forwardCoverage(
            playerIDs: others.map(\.id),
            careerID: careerID,
            season: season
        )

        // "Still under contract that year" — the same test every projection in
        // the app uses, less the men whose money for that year is on a row.
        let underContract = others
            .filter {
                $0.contractYearsRemaining > seasonsAhead
                    && coverage[$0.id] == nil
                    && !$0.isFranchiseTagged
            }
            .reduce(0) { $0 + Swift.max(0, $1.annualSalary) }

        let forward = coverage.values.reduce(0, +)

        return Space(
            season: season,
            seasonsAhead: seasonsAhead,
            cap: ContractEngine.projectedCap(team.salaryCap, seasonsAhead: seasonsAhead),
            committed: underContract + forward
        )
    }

    /// The room for a specific plan — ``space(team:roster:currentSeason:hasRolledOver:seasonsAhead:careerID:excluding:)``
    /// with the plan's own year and its own player left out.
    ///
    /// `hasRolledOver` must be the same value the plan was built with, or the
    /// gate would price a different league year than the one the booking binds.
    static func space(
        for plan: Plan,
        player: Player,
        team: Team,
        roster: [Player],
        currentSeason: Int,
        hasRolledOver: Bool = false,
        careerID: UUID?
    ) -> Space {
        space(
            team: team,
            roster: roster,
            currentSeason: currentSeason,
            hasRolledOver: hasRolledOver,
            seasonsAhead: plan.seasonsAhead,
            careerID: careerID,
            excluding: player.id
        )
    }

    // MARK: - The Gate

    /// Why an offer cannot be tabled, with the year named.
    ///
    /// Everything the refusal sentence needs is a field, so the copy can say
    /// *"Over the 2027 cap by $5.8M"* without re-deriving a number the gate
    /// already knows — which is how the screen came to refuse a 2027 deal with a
    /// 2026 figure in the first place.
    struct Block: Equatable {

        /// The league year that cannot carry the deal.
        let season: Int

        /// Whether that year is the one that is open right now.
        let isCurrentYear: Bool

        /// Whether `capRoom` is the league's projection rather than a real cap.
        let isProjected: Bool

        /// What the deal charges that year, net of what it replaces.
        let charge: Int

        /// What the deal charges that year gross, before the replacement.
        let grossCharge: Int

        /// What signing takes off that year's books (a settled tag, an expiring
        /// deal). 0 when nothing is replaced.
        let replacedCharge: Int

        /// Room in that year before this deal.
        let available: Int

        /// `charge - available`, always positive.
        let overage: Int

        /// The refusal, phrased once so every surface refuses identically —
        /// the same discipline `CommittedCapLedger.blockMessage` keeps.
        var message: String {
            let year = String(season)
            let over = CommittedCapLedger.money(overage)
            if isCurrentYear {
                return "Over the \(year) cap by \(over) — this deal charges \(year), "
                    + "and \(CommittedCapLedger.money(available)) is all the room there is."
            }
            return "Over the projected \(year) cap by \(over) — that is the year this deal "
                + "first charges. Free up room in \(year) before you offer this."
        }
    }

    /// What tabling an offer would do, when it is allowed.
    struct Allowance: Equatable {
        let season: Int
        let isProjected: Bool
        /// Net charge in the binding year. Negative when the deal frees room —
        /// a tag-and-extend that lands under the tag it retires.
        let charge: Int
        let available: Int
        /// Room in the binding year after the deal.
        var remaining: Int { available - charge }
    }

    enum Verdict: Equatable {
        case clear(Allowance)
        case blocked(Block)

        var isBlocked: Bool { if case .blocked = self { return true }; return false }
        var block: Block? { if case .blocked(let b) = self { return b }; return nil }
    }

    /// **The cap gate, on the year the deal targets.**
    ///
    /// Exactly one league year is tested: the year the money first lands in.
    /// Not the open year for a deal that does not charge it — that was the bug —
    /// and deliberately not every year of the term either. A club is required to
    /// be legal in the league year it is in; the years after it each get their
    /// own offseason of cuts, restructures and expiries first, and the
    /// projection cannot see a single one of them. Refusing on year four would
    /// be `commitForward`'s refusal in reverse, and that function documents at
    /// length why it never refuses.
    ///
    /// Sandbox short-circuits, as every cap gate in the game does.
    static func verdict(plan: Plan, space: Space, capMode: CapMode) -> Verdict {
        let charge = plan.netChargeInStartYear
        let allowance = Allowance(
            season: space.season,
            isProjected: space.isProjected,
            charge: charge,
            available: space.available
        )
        guard capMode != .sandbox else { return .clear(allowance) }
        guard charge > space.available else { return .clear(allowance) }

        return .blocked(Block(
            season: space.season,
            isCurrentYear: !space.isProjected,
            isProjected: space.isProjected,
            charge: charge,
            grossCharge: plan.firstYearCapHit,
            replacedCharge: plan.replacedCharge,
            available: space.available,
            overage: charge - space.available
        ))
    }

    /// The whole gate in one call, for a surface that holds a roster and a
    /// career: plan the deal, price the year, answer.
    static func verdict(
        player: Player,
        offer: NegotiationOffer,
        application: ContractEngine.DealApplication,
        capMode: CapMode,
        currentSeason: Int,
        hasRolledOver: Bool = false,
        careerID: UUID?,
        team: Team,
        roster: [Player],
        existingContract: Contract? = nil
    ) -> (plan: Plan, space: Space, verdict: Verdict) {
        let plan = plan(
            player: player,
            offer: offer,
            application: application,
            capMode: capMode,
            currentSeason: currentSeason,
            hasRolledOver: hasRolledOver,
            careerID: careerID,
            existingContract: existingContract
        )
        let room = space(
            for: plan,
            player: player,
            team: team,
            roster: roster,
            currentSeason: currentSeason,
            hasRolledOver: hasRolledOver,
            careerID: careerID
        )
        return (plan, room, verdict(plan: plan, space: room, capMode: capMode))
    }

    // MARK: - Copy Data

    /// `"2027"` for a one-year deal, `"2027–2029"` for three. A league year is a
    /// name and not a quantity, so `String(_:)` and never a grouped format.
    static func yearSpan(_ plan: Plan) -> String {
        plan.lastSeason == plan.startSeason
            ? String(plan.startSeason)
            : "\(String(plan.startSeason))\u{2013}\(String(plan.lastSeason))"
    }
}
