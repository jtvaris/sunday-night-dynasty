import Foundation

// MARK: - Draft Day Trade Engine (R24, rebuilt in Wave 4)
//
// Everything that makes a phone ring on draft night:
// - An AI partner offers to TRADE UP into the user's pick (caller rolls the
//   dice, this engine builds the package).
// - The user shops a pick he is on the clock with — the TRADE DOWN search.
// - The user calls about MOVING UP to a specific pick or for a specific
//   prospect, and gets the counterparty's asking price back (Wave 4).
// - Two AI clubs swap picks with each other while the board falls (Wave 4 —
//   plan finding S6, "31 mannequins": before this, every AI team picked at its
//   original slot in every draft, forever).
//
// ## One chart, two prices
//
// Public value is the Jimmy Johnson chart via `TradeValueEngine.pickTradeValue`
// (which also applies the 20 %/year future-pick discount) and
// `playerTradeValue` — that is the number the war room and the offer banner
// quote, because decision §7.1 makes JJ the game's public language.
//
// What a deal actually COSTS is priced through the counterparty's
// `TradeValueEngine.GMMarketView`: his persona's hidden chart lean, his club's
// stance (a rebuilder pays up for future picks, a contender discounts them) and
// his starter-quality needs. Two GMs therefore quote two different prices for
// the same pick, which is what makes trading up feel like a negotiation rather
// than a subtraction.
//
// ## Why picks escape the Wave 2 package decay
//
// `GMMarketView.sideValue` charges each extra asset in a package ×0.85, ×0.70 …
// because a linear SUM of player values is the quantity-for-quality exploit
// (finding S4). Draft picks are different in kind: the JJ curve is already
// steeply convex, so "two 2nds for a 1st" is priced as a loss by the chart
// itself, and consolidating picks to move up is the single most characteristic
// move in the sport. Applying the S4 decay to picks would make the top of the
// board mathematically unbuyable — which is exactly finding S6's "top-5 picks
// become untradeable from season 2". So draft-day packages use a MILD decay
// that only starts at the fourth asset (see `packageValue`), plus an anchor
// rule that stops a pile of sevenths from pretending to be a first.
enum DraftDayTradeEngine {

    // MARK: - Tunables

    /// Assets one side may put into an everyday draft-day package.
    static let standardPackageCap = 3

    /// Assets allowed when the ask is first-round premium — the "mortgage the
    /// future" package. A top-5 pick is worth 1700-3000 chart points and no
    /// three assets outside the top ten reach that, which is why finding S6
    /// reports top-5 picks as untradeable; with future firsts as bridges, six
    /// assets do reach it (see the worked example in the Wave 4 report).
    static let bridgePackageCap = 6

    /// Chart points above which the bridge cap applies (≈ pick 8).
    static let bridgeThreshold = 1400.0

    /// The biggest single asset in a package has to carry this share of the
    /// ask. Without it the greedy builder would happily answer a 3000-point ask
    /// with twelve seventh-rounders, which no GM in the sport would take.
    static let anchorShare = 0.30

    /// …but the share is capped at a late first (pick 32 on the chart), because
    /// 30 % of a 3000-point ask is 900 points and demanding a single 900-point
    /// anchor is just finding S6's "top-5 picks are untradeable" wearing a
    /// different hat. Measured: the reference bridge package for pick #1 —
    /// a mid-first plus three future firsts plus a future second — anchors at
    /// 994 points, which clears the capped floor and fails the uncapped one.
    static let anchorCeilingPick = 32

    /// Ceiling on what an AI-built offer to the user may be worth relative to
    /// the pick it buys — above this the "offer" is a gift and reads as a bug.
    static let offerValueCeiling = 1.45

    /// How many of the falling men an AI club is allowed to be shopping for
    /// (see `aiVsAiSwap`).
    static let fallingWindow = 6

    /// How far past his own ceiling a buyer will go when the only packages his
    /// board can build overshoot the seller's ask. Draft-weekend move-ups are
    /// paid in whole picks, not in chart points.
    static let swapOvershootSlack = 1.12

    // MARK: - Assets

    /// One tradable thing on draft night. Players joined picks in Wave 4:
    /// draft-weekend veteran deals are ordinary NFL business (a club that just
    /// drafted his replacement shops the incumbent that same night), and they
    /// are also the only way a capped-out club can pay to move up.
    enum Asset: Identifiable {
        case pick(DraftPick)
        case player(Player)

        var id: UUID {
            switch self {
            case .pick(let pick):     return pick.id
            case .player(let player): return player.id
            }
        }

        /// Public-language label: "#14 (R1)" for this draft, "2029 R1" for a
        /// future pick whose slot is still provisional, "WR Deval (84)" for a
        /// player.
        func label(currentSeason: Int) -> String {
            switch self {
            case .pick(let pick):
                if pick.seasonYear > currentSeason {
                    return "\(pick.displayDraftYear) R\(pick.round)"   // #152
                }
                return "#\(pick.pickNumber) (R\(pick.round))"
            case .player(let player):
                return "\(player.position.rawValue) \(player.lastName) (\(player.overall))"
            }
        }

        /// Jimmy Johnson points — the number the UI is allowed to show.
        func publicValue(currentSeason: Int) -> Int {
            switch self {
            case .pick(let pick):
                return TradeValueEngine.pickTradeValue(pick: pick, currentSeason: currentSeason)
            case .player(let player):
                return TradeValueEngine.playerTradeValue(player: player)
            }
        }
    }

    // MARK: - Offer model

    /// A draft-night deal between the user and one AI club, from the USER's
    /// point of view.
    struct DraftTradeOffer: Identifiable {
        enum Kind {
            /// The partner is buying the user's pick — the user moves DOWN.
            case userMovesDown
            /// The user is buying the partner's pick — the user moves UP.
            case userMovesUp
        }

        /// Who picked up the phone.
        ///
        /// Not cosmetic: it is the fix for the decline-blacklist bug (plan
        /// finding S6). An AI call the user declines must stop THAT club from
        /// calling again about the same pick; a price the user asked for and
        /// walked away from must not stop anyone from calling him. Both offers
        /// list the same pick under `userGives`, so direction alone cannot tell
        /// them apart — origin can.
        enum Origin {
            case aiCall
            case userCall
        }

        let id = UUID()
        let kind: Kind
        let origin: Origin
        let partnerTeamID: UUID
        let partnerAbbreviation: String
        /// The counterparty GM's name + archetype label, for the banner header.
        let gmName: String
        let gmStyle: String
        let userGives: [Asset]
        let userGets: [Asset]
        let motive: String
        /// Jimmy Johnson points, public language (see the type comment).
        let userGivesValue: Int
        let userGetsValue: Int
        /// False only on a trade-UP quote the user cannot currently afford: the
        /// package is still returned so the screen can show the price and what
        /// is missing.
        let isAffordable: Bool
        /// Human-readable gap on an unaffordable quote ("about a 2nd short").
        let shortfall: String?

        /// The `DraftPick` rows on each side, for the coordinator's proposal.
        var userGivesPicks: [DraftPick] {
            userGives.compactMap { if case .pick(let p) = $0 { return p } else { return nil } }
        }
        var userGetsPicks: [DraftPick] {
            userGets.compactMap { if case .pick(let p) = $0 { return p } else { return nil } }
        }
        var userGivesPlayers: [Player] {
            userGives.compactMap { if case .player(let p) = $0 { return p } else { return nil } }
        }
        var userGetsPlayers: [Player] {
            userGets.compactMap { if case .player(let p) = $0 { return p } else { return nil } }
        }

        func givesLabel(currentSeason: Int) -> String {
            userGives.map { $0.label(currentSeason: currentSeason) }.joined(separator: " + ")
        }
        func getsLabel(currentSeason: Int) -> String {
            userGets.map { $0.label(currentSeason: currentSeason) }.joined(separator: " + ")
        }
    }

    /// A swap struck between two AI clubs while the user watches.
    struct AISwap: Identifiable {
        let id = UUID()
        let buyerTeamID: UUID
        let sellerTeamID: UUID
        let buyerAbbreviation: String
        let sellerAbbreviation: String
        /// What the club moving UP sends (its own later picks / a veteran).
        let buyerGives: [Asset]
        /// What it gets — the pick it moved up for.
        let sellerGives: [DraftPick]
        /// Ticker copy, already written from the league's point of view.
        let headline: String
        /// One-line "why", for the drama beat.
        let motive: String
        let buyerValue: Int
        let sellerValue: Int
        let targetPickNumber: Int
    }

    // MARK: - Board context

    /// Everything the engine needs to read the room, bundled so the entry
    /// points stay legible. The coordinator owns the caching (`seat` is a
    /// closure precisely so 32 `GMMarketView`s are not rebuilt per dice roll).
    struct Board {
        /// The current draft's order, ascending by pick number.
        let picks: [DraftPick]
        /// Incomplete picks of LATER league years — the bridges that make the
        /// top of the board reachable (plan §6 Wave 1.1 minted these).
        let futurePicks: [DraftPick]
        let currentPickIndex: Int
        let currentSeason: Int
        let availableProspects: [CollegeProspect]
        let publicBoardRanks: [UUID: Int]
        /// Market view for one club, or nil when the team is unknown.
        let seat: (UUID) -> TradeValueEngine.GMMarketView?

        /// Incomplete picks of the current draft still ahead of the clock.
        var upcomingPicks: [DraftPick] {
            picks.dropFirst(currentPickIndex).filter { !$0.isComplete }
        }
    }

    // MARK: - Pricing

    /// What a club charges to give up a pick, as a multiple of the pick's own
    /// value TO THAT CLUB.
    ///
    /// Decision §7.1 in one function: the chart is public, the lean is hidden.
    /// An old-school GM ("the chart is the chart") sells at ~1.03, an analytics
    /// GM who prices draft capital above the chart wants ~1.20 and in practice
    /// refuses to move, and the per-week `askNoise` means the same GM is not a
    /// solvable equation.
    static func moveUpPremium(seller: TradeValueEngine.GMMarketView) -> Double {
        moveUpPremium(persona: seller.persona, noise: seller.noise)
    }

    /// Same ask, from the persona alone — what a screen OUTSIDE the draft room
    /// (the pre-draft mock board) can know about a rival front office without
    /// reading its roster.
    static func moveUpPremium(persona: TradeValueEngine.GMPersona, noise: Double) -> Double {
        // Draft-day business is quicker and rougher than a July phone call, so
        // only 60 % of the persona's negotiating premium survives into the ask.
        let base = 1.0 + (persona.askingPremium - 1.0) * 0.6
        let lean = 1.0 + (persona.pickLean - 1.0) * 0.5
        return base * lean * noise
    }

    // MARK: - Public-chart quoting (for screens outside the war room)

    /// What the club holding `targetPickNumber` asks for it, in Jimmy Johnson
    /// points, for a screen that has no roster context.
    ///
    /// This is the fix for the plan's "the pre-draft screen quotes trade-up
    /// costs the draft room would laugh at": the MockDraft hints used to price
    /// picks on the LINEAR `DraftEngine.pickValue`, which diverges 10× from the
    /// JJ chart by pick 160. Same chart, same premium formula, same GM — so the
    /// April estimate and the draft-night quote agree to within the seller's
    /// stance (which a pre-draft screen cannot see, and which largely cancels
    /// in a pick-for-pick ratio anyway).
    static func publicAskPrice(
        targetPickNumber: Int,
        sellerTeamID: UUID?,
        season: Int,
        week: Int
    ) -> Int {
        let base = Double(PickValueChart.points(forPick: targetPickNumber))
        guard let sellerTeamID else { return Int(base.rounded()) }
        let persona = TradeValueEngine.GMPersona.forTeam(id: sellerTeamID)
        let noise = TradeValueEngine.askNoise(teamID: sellerTeamID, season: season, week: week)
        return Int((base * moveUpPremium(persona: persona, noise: noise)).rounded())
    }

    /// Public-chart value of a package, with the same draft-day decay the
    /// market applies — one aggregation rule everywhere.
    static func publicPackageValue(_ picks: [DraftPick], currentSeason: Int) -> Int {
        Int(discounted(picks.map {
            Double(TradeValueEngine.pickTradeValue(pick: $0, currentSeason: currentSeason))
        }))
    }

    /// "Rd1 #14" for this year's board, "2028 Rd1" for a future pick whose slot
    /// is still provisional.
    static func pickLabel(_ pick: DraftPick, currentSeason: Int) -> String {
        pick.seasonYear > currentSeason
            ? "\(pick.displayDraftYear) Rd\(pick.round)"   // #152
            : "Rd\(pick.round) #\(pick.pickNumber)"
    }

    /// The most an AI club will pay, as a multiple of the target pick's value
    /// to that club. The mirror of `moveUpPremium`: the GM who prices picks
    /// BELOW the chart is the one who pays above it to move up, and the
    /// analytics GM lands under 1.0 — he does not move up, ever, which is
    /// exactly what his blurb promises.
    static func maxMoveUpPremium(buyer: TradeValueEngine.GMMarketView) -> Double {
        let lean = 1.0 + (1.0 - buyer.persona.pickLean) * 1.2
        let appetite = 1.0 + (buyer.persona.initiateWeight - 1.0) * 0.10
        return max(0.90, min(1.45, 1.06 * lean * appetite))
    }

    /// Package value in one GM's currency, with the mild draft-day decay
    /// documented at the top of the file: the first three assets count in full,
    /// the fourth ×0.9, the fifth ×0.8, everything after ×0.7.
    static func packageValue(
        _ assets: [Asset],
        seat: TradeValueEngine.GMMarketView,
        incoming: Bool
    ) -> Double {
        discounted(assets.map { assetValue($0, seat: seat, incoming: incoming) })
    }

    /// The one place the draft-day decay curve lives: the first three assets
    /// count in full, the fourth ×0.9, the fifth ×0.8, the rest ×0.7.
    private static func discounted(_ values: [Double]) -> Double {
        values.sorted(by: >).enumerated().reduce(0.0) { total, entry in
            let weight: Double
            switch entry.offset {
            case 0...2: weight = 1.0
            case 3:     weight = 0.9
            case 4:     weight = 0.8
            default:    weight = 0.7
            }
            return total + entry.element * weight
        }
    }

    static func assetValue(
        _ asset: Asset,
        seat: TradeValueEngine.GMMarketView,
        incoming: Bool
    ) -> Double {
        switch asset {
        case .pick(let pick):
            return seat.pickValue(pick)
        case .player(let player):
            return incoming ? seat.incomingPlayerValue(player) : seat.outgoingPlayerValue(player)
        }
    }

    static func publicValue(_ assets: [Asset], currentSeason: Int) -> Int {
        assets.reduce(0) { $0 + $1.publicValue(currentSeason: currentSeason) }
    }

    // MARK: - AI trade-up into the user's pick

    /// Builds an offer where an AI team jumps up into `userPick`, paying with
    /// its own later picks, its future picks and — when the chart still leaves
    /// a hole — a veteran off its roster.
    ///
    /// Requires the partner to covet a top-6 board prospect at one of his
    /// starter-quality needs, so the user can always infer WHY the phone rang.
    /// Returns nil when no believable partner/package exists; the caller owns
    /// the per-pick dice roll.
    static func aiTradeUpOffer(
        userPick: DraftPick,
        board: Board,
        userTeamID: UUID
    ) -> DraftTradeOffer? {
        let topBoard = topOfBoard(board, limit: 6)
        let candidates = partnerCandidates(
            after: userPick,
            board: board,
            userTeamID: userTeamID,
            maxSlide: 24
        )

        for candidate in candidates.shuffled() {
            guard let buyer = board.seat(candidate.teamID) else { continue }
            // An analytics GM will not pay to move up — skip him before the
            // package builder wastes work on a deal he would refuse.
            guard maxMoveUpPremium(buyer: buyer) >= 1.0 else { continue }
            let needs = buyer.needs.topNeeds(limit: 3)
            guard let target = topBoard.first(where: { needs.contains($0.position) }) else { continue }

            guard let package = buildPayment(
                for: userPick,
                payer: buyer,
                priced: buyer,                       // the buyer values his own outgoing assets
                board: board,
                allowPlayers: true,
                excludingPicksAtOrBefore: userPick.pickNumber
            ) else { continue }

            // The buyer must be willing to pay what the package is worth to HIM.
            let paid = packageValue(package, seat: buyer, incoming: false)
            let worthToBuyer = buyer.pickValue(userPick)
            guard paid <= worthToBuyer * maxMoveUpPremium(buyer: buyer) else { continue }

            let givesValue = TradeValueEngine.pickTradeValue(pick: userPick, currentSeason: board.currentSeason)
            let getsValue = publicValue(package, currentSeason: board.currentSeason)
            let ratio = Double(getsValue) / Double(max(1, givesValue))
            guard ratio >= 0.98, ratio <= offerValueCeiling else { continue }

            let motive = "\(buyer.abbreviation) want to jump to #\(userPick.pickNumber) — \(buyer.persona.name) is targeting a \(target.position.rawValue) before the board turns."
            return DraftTradeOffer(
                kind: .userMovesDown,
                origin: .aiCall,
                partnerTeamID: buyer.team.id,
                partnerAbbreviation: buyer.abbreviation,
                gmName: buyer.persona.name,
                gmStyle: buyer.persona.archetype.label,
                userGives: [.pick(userPick)],
                userGets: package,
                motive: motive,
                userGivesValue: givesValue,
                userGetsValue: getsValue,
                isAffordable: true,
                shortfall: nil
            )
        }
        return nil
    }

    // MARK: - User-initiated trade down

    /// Searches for an AI team willing to move up into the pick the user has on
    /// the clock. Per-partner willingness: ~65 % when a top-8 board prospect
    /// sits at one of the partner's top-3 needs, ~20 % otherwise, plus up to
    /// +15 % when consensus top talent is sliding to this slot.
    static func userTradeDownOffer(
        currentPick: DraftPick,
        board: Board,
        userTeamID: UUID
    ) -> DraftTradeOffer? {
        let topBoard = topOfBoard(board, limit: 8)
        // Consensus value sliding to this slot makes moving up more tempting.
        let slidingTalent = board.availableProspects.filter {
            (board.publicBoardRanks[$0.id] ?? 999) <= currentPick.pickNumber + 3
        }.count
        let candidates = partnerCandidates(
            after: currentPick,
            board: board,
            userTeamID: userTeamID,
            maxSlide: 18
        )

        for candidate in candidates.shuffled() {
            guard let buyer = board.seat(candidate.teamID) else { continue }
            guard maxMoveUpPremium(buyer: buyer) >= 0.98 else { continue }
            let needs = buyer.needs.topNeeds(limit: 3)
            let target = topBoard.first(where: { needs.contains($0.position) })
            let willingness = (target != nil ? 0.65 : 0.20) + 0.05 * Double(min(3, slidingTalent))
            guard Double.random(in: 0..<1) < willingness else { continue }

            guard let package = buildPayment(
                for: currentPick,
                payer: buyer,
                priced: buyer,
                board: board,
                allowPlayers: true,
                excludingPicksAtOrBefore: currentPick.pickNumber
            ) else { continue }

            let paid = packageValue(package, seat: buyer, incoming: false)
            guard paid <= buyer.pickValue(currentPick) * maxMoveUpPremium(buyer: buyer) else { continue }

            let givesValue = TradeValueEngine.pickTradeValue(pick: currentPick, currentSeason: board.currentSeason)
            let getsValue = publicValue(package, currentSeason: board.currentSeason)
            let ratio = Double(getsValue) / Double(max(1, givesValue))
            guard ratio >= 0.98, ratio <= offerValueCeiling else { continue }

            let motive: String
            if let target {
                motive = "\(buyer.abbreviation) bite: \(buyer.persona.name) will move up for a \(target.position.rawValue) still on the board."
            } else {
                motive = "\(buyer.abbreviation) like the value at #\(currentPick.pickNumber) and will pay the chart price."
            }
            return DraftTradeOffer(
                kind: .userMovesDown,
                origin: .userCall,
                partnerTeamID: buyer.team.id,
                partnerAbbreviation: buyer.abbreviation,
                gmName: buyer.persona.name,
                gmStyle: buyer.persona.archetype.label,
                userGives: [.pick(currentPick)],
                userGets: package,
                motive: motive,
                userGivesValue: givesValue,
                userGetsValue: getsValue,
                isAffordable: true,
                shortfall: nil
            )
        }
        return nil
    }

    // MARK: - User-initiated trade UP (Wave 4)

    /// Prices moving up to `targetPick`: the owner's asking premium applied to
    /// what the pick is worth to HIM, answered with the best package the user
    /// can assemble out of his remaining picks, his future picks and (opt-in)
    /// his veterans.
    ///
    /// Always returns a quote when the user has anything to trade — an
    /// unaffordable one carries `isAffordable == false` and a `shortfall`
    /// string, because "here is the price and here is what you're missing" is
    /// the answer a GM actually wants.
    static func userTradeUpQuote(
        targetPick: DraftPick,
        board: Board,
        userTeamID: UUID,
        allowPlayers: Bool,
        targetProspect: CollegeProspect? = nil
    ) -> DraftTradeOffer? {
        guard targetPick.currentTeamID != userTeamID, !targetPick.isComplete else { return nil }
        guard let seller = board.seat(targetPick.currentTeamID),
              let user = board.seat(userTeamID) else { return nil }

        let askRatio = moveUpPremium(seller: seller)
        let required = seller.pickValue(targetPick) * askRatio

        // Every candidate is valued through the SELLER's eyes — his lean and
        // his stance are what decide whether the package covers the ask.
        let assembled = bestPackage(
            required: required,
            board: board,
            teamID: userTeamID,
            payer: user,
            priced: seller,
            cutoff: targetPick.pickNumber,
            allowPlayers: allowPlayers
        )
        guard !assembled.assets.isEmpty else { return nil }

        let givesValue = publicValue(assembled.assets, currentSeason: board.currentSeason)
        let getsValue = TradeValueEngine.pickTradeValue(pick: targetPick, currentSeason: board.currentSeason)

        let motive: String
        if let targetProspect {
            motive = "\(seller.abbreviation) hold #\(targetPick.pickNumber). \(seller.persona.name) (\(seller.persona.archetype.label)) will talk about \(targetProspect.lastName) — at his price."
        } else {
            motive = "\(seller.abbreviation) hold #\(targetPick.pickNumber). \(seller.persona.name) (\(seller.persona.archetype.label)) names his price to move down."
        }

        return DraftTradeOffer(
            kind: .userMovesUp,
            origin: .userCall,
            partnerTeamID: seller.team.id,
            partnerAbbreviation: seller.abbreviation,
            gmName: seller.persona.name,
            gmStyle: seller.persona.archetype.label,
            userGives: assembled.assets,
            userGets: [.pick(targetPick)],
            motive: motive,
            userGivesValue: givesValue,
            userGetsValue: getsValue,
            isAffordable: assembled.covered,
            shortfall: assembled.covered ? nil : shortfallText(
                missing: required - assembled.value,
                currentSeason: board.currentSeason
            )
        )
    }

    /// The picks worth calling about when the user wants a specific prospect:
    /// every upcoming pick ahead of his own next one, nearest first, capped at
    /// `limit` so the call sheet stays a sheet.
    static func tradeUpTargets(
        board: Board,
        userTeamID: UUID,
        limit: Int = 8
    ) -> [DraftPick] {
        let upcoming = board.upcomingPicks
        let onClock = upcoming.first

        // The reference is the user's next turn — except when he is ALREADY on
        // the clock, in which case moving "up" can only mean getting ahead of
        // the turn after this one. You cannot jump a pick you are making.
        let ownPicks = upcoming.filter { $0.currentTeamID == userTeamID }
        let reference = (onClock?.currentTeamID == userTeamID)
            ? ownPicks.dropFirst().first
            : ownPicks.first

        guard let reference else {
            // No later turn of his own — he can still buy his way in, so quote
            // the next few slots on the board.
            return Array(upcoming.filter { $0.currentTeamID != userTeamID }.prefix(limit))
        }
        return Array(
            upcoming
                .filter { $0.currentTeamID != userTeamID && $0.pickNumber < reference.pickNumber }
                .suffix(limit)
        )
    }

    // MARK: - AI vs AI swaps (Wave 4 — plan finding S6)

    /// Rolls one AI-vs-AI move-up into the pick currently on the clock.
    ///
    /// The trigger is falling board value, the same thing that moves the phones
    /// in a real war room: a consensus top-`slideWindow` prospect is still
    /// sitting there when the slot he was ranked for has passed, and some club
    /// behind needs that position. Both sides are priced through their own
    /// `GMMarketView`, so an analytics GM behind never buys and an old-school
    /// GM in front never sells cheap.
    ///
    /// Returns nil far more often than not — the caller rolls the dice first.
    static func aiVsAiSwap(
        board: Board,
        userTeamID: UUID?
    ) -> AISwap? {
        guard board.currentPickIndex < board.picks.count else { return nil }
        let onClock = board.picks[board.currentPickIndex]
        guard !onClock.isComplete, onClock.currentTeamID != userTeamID else { return nil }
        guard let seller = board.seat(onClock.currentTeamID) else { return nil }

        // Who is falling? The best few prospects ranked comfortably ahead of
        // this slot — not just the single best.
        //
        // Reading only `falling.first` is why an entire 234-pick draft could go
        // by without one AI-vs-AI swap (task #148a): the AI board and the media
        // board are ordered differently, so the top of the *media* board tends
        // to hold the same handful of men nobody's scorer rates all night. If no
        // club behind needed that one position, every roll of the night died on
        // the same line. A war room jumps the queue for whoever is falling that
        // it wants, not for the board's #1 specifically.
        let falling = board.availableProspects
            .compactMap { prospect -> (prospect: CollegeProspect, rank: Int)? in
                guard let rank = board.publicBoardRanks[prospect.id] else { return nil }
                guard rank + 4 <= onClock.pickNumber else { return nil }
                return (prospect, rank)
            }
            .sorted { $0.rank < $1.rank }
            .prefix(fallingWindow)
        guard !falling.isEmpty else { return nil }

        let candidates = partnerCandidates(
            after: onClock,
            board: board,
            userTeamID: userTeamID,
            maxSlide: 30
        )

        for candidate in candidates.shuffled() {
            guard candidate.teamID != onClock.currentTeamID,
                  let buyer = board.seat(candidate.teamID) else { continue }
            // He has to actually want one of the men who are falling.
            guard let slider = falling.first(where: {
                buyer.needs.severity($0.prospect.position) >= 0.22
            }) else { continue }
            guard maxMoveUpPremium(buyer: buyer) >= 1.0 else { continue }

            guard let package = buildPayment(
                for: onClock,
                payer: buyer,
                priced: seller,                    // the SELLER prices what he is offered
                board: board,
                allowPlayers: true,
                excludingPicksAtOrBefore: onClock.pickNumber
            ) else { continue }

            // Seller's bar…
            let offered = packageValue(package, seat: seller, incoming: true)
            guard offered >= seller.pickValue(onClock) * moveUpPremium(seller: seller) else { continue }
            // …and the buyer's ceiling, plus the slack a whole-pick package
            // forces on him. Both bars are ratios against the same chart value,
            // so a seller asking 1.07× and a balanced buyer capped at 1.06×
            // could never trade at ALL — and a package is assembled out of whole
            // picks, so even a feasible pair has to overshoot the ask to clear
            // it. Pricing the buyer to the point closed a window the sport keeps
            // open: the club moving up in April is the one that overpays.
            let cost = packageValue(package, seat: buyer, incoming: false)
            let ceiling = max(
                maxMoveUpPremium(buyer: buyer),
                moveUpPremium(seller: seller) * swapOvershootSlack
            )
            guard cost <= buyer.pickValue(onClock) * ceiling else { continue }

            let buyerValue = publicValue(package, currentSeason: board.currentSeason)
            let sellerValue = TradeValueEngine.pickTradeValue(pick: onClock, currentSeason: board.currentSeason)
            let assets = package.map { $0.label(currentSeason: board.currentSeason) }.joined(separator: " + ")

            return AISwap(
                buyerTeamID: buyer.team.id,
                sellerTeamID: seller.team.id,
                buyerAbbreviation: buyer.abbreviation,
                sellerAbbreviation: seller.abbreviation,
                buyerGives: package,
                sellerGives: [onClock],
                headline: "TRADE — \(buyer.abbreviation) move up to #\(onClock.pickNumber), sending \(assets) to \(seller.abbreviation)",
                motive: "\(buyer.persona.name) jumped the line for a \(slider.prospect.position.rawValue): \(slider.prospect.lastName) was BB #\(slider.rank) and is still on the board.",
                buyerValue: buyerValue,
                sellerValue: sellerValue,
                targetPickNumber: onClock.pickNumber
            )
        }
        return nil
    }

    /// Per-pick probability that any AI club even picks up the phone.
    ///
    /// Calibrated against §5's "12-35 draft-weekend pick swaps league-wide,
    /// ≥ 3 in Round 1": 32 × 0.15 + 64 × 0.10 + 128 × 0.06 ≈ 19 attempts a
    /// draft, of which roughly two thirds find a willing counterparty — call it
    /// 12-14 swaps, ~4-5 of them in the first round, before the user's own
    /// deals are counted.
    static func aiSwapChance(round: Int) -> Double {
        switch round {
        case 1:    return 0.15
        case 2, 3: return 0.10
        default:   return 0.06
        }
    }

    // MARK: - Package construction

    /// Assembles what `payer` sends to buy `targetPick`, priced through
    /// `priced` (the club whose bar the package has to clear).
    private static func buildPayment(
        for targetPick: DraftPick,
        payer: TradeValueEngine.GMMarketView,
        priced: TradeValueEngine.GMMarketView,
        board: Board,
        allowPlayers: Bool,
        excludingPicksAtOrBefore cutoff: Int
    ) -> [Asset]? {
        let required = priced.pickValue(targetPick) * moveUpPremium(seller: priced)
        let attempt = bestPackage(
            required: required,
            board: board,
            teamID: payer.team.id,
            payer: payer,
            priced: priced,
            cutoff: cutoff,
            allowPlayers: allowPlayers
        )
        guard attempt.covered else { return nil }
        return attempt.assets
    }

    /// Picks first, players only if the picks cannot get there.
    ///
    /// The ordering matters more than it looks. The builder is greedy-
    /// descending, and an 80-OVR veteran outvalues a second-round pick on the
    /// chart — so a single pass over a mixed pool would open with the veteran
    /// and EVERY draft-night swap in the league would be a blockbuster. Real
    /// war rooms spend draft capital to move up and put a player on the table
    /// only when the capital runs out (a capped-out club, or a top-5 bridge).
    /// Two passes buy exactly that behaviour for six lines.
    private static func bestPackage(
        required: Double,
        board: Board,
        teamID: UUID,
        payer: TradeValueEngine.GMMarketView,
        priced: TradeValueEngine.GMMarketView,
        cutoff: Int,
        allowPlayers: Bool
    ) -> (assets: [Asset], value: Double, covered: Bool) {
        let cap = required >= bridgeThreshold ? bridgePackageCap : standardPackageCap

        func pass(_ withPlayers: Bool) -> (assets: [Asset], value: Double, covered: Bool) {
            let ranked = clubAssets(
                board: board,
                teamID: teamID,
                excludingPicksAtOrBefore: cutoff,
                allowPlayers: withPlayers,
                seat: payer
            )
            .map { (asset: $0, value: assetValue($0, seat: priced, incoming: true)) }
            .sorted { $0.value > $1.value }
            guard !ranked.isEmpty else { return ([], 0, false) }
            return assemble(priced: ranked, required: required, cap: cap)
        }

        let picksOnly = pass(false)
        if picksOnly.covered || !allowPlayers { return picksOnly }
        let withPlayers = pass(true)
        // If players still don't get there, report whichever attempt got
        // closest — the shortfall copy is more useful than an empty hand.
        return withPlayers.covered || withPlayers.value > picksOnly.value
            ? withPlayers
            : picksOnly
    }

    /// The cheapest package that covers the ask, searched exhaustively to three
    /// assets; the greedy-descending fill is the fallback for the bridge case.
    ///
    /// The greedy fill alone was a real bug (task #148b). It opens with the most
    /// valuable thing on the shelf and stops the moment the running total clears
    /// the ask, so a user holding a future first paid THAT first for every slot
    /// he called about: the move-up sheet quoted "2027 R1, 800 pts" for pick #55
    /// (350 chart points) and the identical package for #62 (284). A price that
    /// does not move with the thing being bought is not a price. Three assets is
    /// where the search stops because that is `standardPackageCap` — beyond it
    /// the ask is a first-round bridge, where "everything you have" IS the
    /// answer and the greedy pass is the right shape.
    private static func assemble(
        priced: [(asset: Asset, value: Double)],
        required: Double,
        cap: Int
    ) -> (assets: [Asset], value: Double, covered: Bool) {
        if let minimal = cheapestCoveringPackage(priced: priced, required: required, cap: cap) {
            return minimal
        }

        var chosen: [(asset: Asset, value: Double)] = []
        for entry in priced {
            guard chosen.count < cap else { break }
            if valueOf(chosen) >= required { break }
            chosen.append(entry)
        }
        // Prune the smallest assets that the package does not need.
        for entry in chosen.sorted(by: { $0.value < $1.value }) {
            let without = chosen.filter { $0.asset.id != entry.asset.id }
            if valueOf(without) >= required {
                chosen = without
            }
        }

        let total = valueOf(chosen)
        let anchorOK = (chosen.map(\.value).max() ?? 0) >= anchorFloor(required: required)
        return (chosen.map(\.asset), total, total >= required && anchorOK)
    }

    /// Depth of the exhaustive minimum-overpay search.
    private static let minimalSearchDepth = 3

    /// Smallest total that still clears `required` and the anchor rule, over
    /// every combination of up to `minimalSearchDepth` assets. `nil` when
    /// nothing that small covers the ask.
    private static func cheapestCoveringPackage(
        priced: [(asset: Asset, value: Double)],
        required: Double,
        cap: Int
    ) -> (assets: [Asset], value: Double, covered: Bool)? {
        let depth = min(cap, minimalSearchDepth)
        guard depth >= 1, !priced.isEmpty else { return nil }
        let floor = anchorFloor(required: required)
        // Descending, so the first combination found at a given total is also
        // the one with the biggest anchor in it.
        let pool = priced.sorted { $0.value > $1.value }
        var best: (assets: [Asset], value: Double)?

        func consider(_ combo: [(asset: Asset, value: Double)]) {
            let total = valueOf(combo)
            guard total >= required else { return }
            guard (combo.map(\.value).max() ?? 0) >= floor else { return }
            if let current = best, current.value <= total { return }
            best = (combo.map(\.asset), total)
        }

        for i in pool.indices {
            consider([pool[i]])
            guard depth >= 2 else { continue }
            for j in pool.indices where j > i {
                consider([pool[i], pool[j]])
                guard depth >= 3 else { continue }
                for k in pool.indices where k > j {
                    consider([pool[i], pool[j], pool[k]])
                }
            }
        }

        guard let best else { return nil }
        return (best.assets, best.value, true)
    }

    /// The biggest single asset a package has to contain — see `anchorShare`.
    private static func anchorFloor(required: Double) -> Double {
        min(
            required * anchorShare,
            Double(PickValueChart.points(forPick: anchorCeilingPick))
        )
    }

    private static func valueOf(_ chosen: [(asset: Asset, value: Double)]) -> Double {
        discounted(chosen.map(\.value))
    }

    // MARK: - Asset pools

    /// Tradable assets of one AI club: its remaining picks in this draft after
    /// `cutoff`, its future picks, and — when allowed — one spare veteran.
    private static func clubAssets(
        board: Board,
        teamID: UUID,
        excludingPicksAtOrBefore cutoff: Int,
        allowPlayers: Bool,
        seat: TradeValueEngine.GMMarketView
    ) -> [Asset] {
        var assets: [Asset] = board.upcomingPicks
            .filter { $0.currentTeamID == teamID && $0.pickNumber > cutoff }
            .map { Asset.pick($0) }
        assets += board.futurePicks
            .filter { $0.currentTeamID == teamID }
            .map { Asset.pick($0) }
        if allowPlayers {
            assets += tradableVeterans(seat: seat).map { Asset.player($0) }
        }
        return assets
    }

    /// Veterans a club would actually put in a draft-weekend package.
    ///
    /// Reuses the Wave 2 guard rails rather than inventing draft-specific ones:
    /// nobody moves the last body at a position that has to line up on Sunday
    /// (`lastManReason`), nobody moves a franchise cornerstone
    /// (`untouchableReason`), and starters are only shopped when the club has
    /// real depth behind them. Sorted best-first so the package builder can use
    /// a veteran as a genuine anchor when the picks alone cannot reach the ask.
    private static func tradableVeterans(seat: TradeValueEngine.GMMarketView) -> [Player] {
        seat.roster
            .filter { player in
                guard !player.isRetired, player.overall >= 68 else { return false }
                guard seat.untouchableReason(player) == nil else { return false }
                guard seat.lastManReason(player) == nil else { return false }
                if seat.isStarter(player) {
                    // A starter is only available when someone can replace him.
                    return seat.depth(at: player.position).count >= 3
                }
                return true
            }
            .sorted { $0.overall > $1.overall }
            .prefix(6)
            .map { $0 }
    }

    // MARK: - Helpers

    /// Teams (≠ user) owning incomplete picks 2...maxSlide slots after the
    /// reference pick, with each team's picks sorted by pick number.
    private static func partnerCandidates(
        after referencePick: DraftPick,
        board: Board,
        userTeamID: UUID?,
        maxSlide: Int
    ) -> [(teamID: UUID, picks: [DraftPick])] {
        var byTeam: [UUID: [DraftPick]] = [:]
        for pick in board.upcomingPicks {
            guard pick.currentTeamID != userTeamID,
                  pick.pickNumber > referencePick.pickNumber else { continue }
            byTeam[pick.currentTeamID, default: []].append(pick)
        }
        return byTeam.compactMap { teamID, teamPicks in
            let sorted = teamPicks.sorted { $0.pickNumber < $1.pickNumber }
            guard let first = sorted.first else { return nil }
            let slide = first.pickNumber - referencePick.pickNumber
            guard slide >= 2, slide <= maxSlide else { return nil }
            return (teamID, sorted)
        }
    }

    /// Top of the PUBLIC board (consensus ranks only — no hidden data leaks).
    private static func topOfBoard(_ board: Board, limit: Int) -> [CollegeProspect] {
        board.availableProspects
            .filter { board.publicBoardRanks[$0.id] != nil }
            .sorted { (board.publicBoardRanks[$0.id] ?? 999) < (board.publicBoardRanks[$1.id] ?? 999) }
            .prefix(limit)
            .map { $0 }
    }

    /// "about a 2nd short" — the gap expressed in the only unit a draft room
    /// speaks, instead of a raw point number the user cannot act on.
    ///
    /// The number in brackets is in the SELLER's currency (his lean and stance
    /// are baked in), which is why it is labelled "points" rather than "chart
    /// points": the chart is what both sides quote, this is what one GM wants.
    private static func shortfallText(missing: Double, currentSeason: Int) -> String {
        let points = max(0, Int(missing))
        let round: String
        switch points {
        case ..<40:   round = "a late-round pick"
        case ..<130:  round = "a 4th"
        case ..<270:  round = "a 3rd"
        case ..<590:  round = "a 2nd"
        case ..<1100: round = "a late 1st"
        default:      round = "a premium 1st"
        }
        return "About \(round) short (\(points) points to their front office)."
    }
}
