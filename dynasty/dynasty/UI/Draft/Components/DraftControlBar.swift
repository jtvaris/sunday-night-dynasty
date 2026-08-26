import SwiftUI

// MARK: - DraftControlBar — transport, escalation, and the room's one commit surface
//
// UI_REDESIGN_VISION P5 / §2.5 built this bar as a pure transport rail with, by
// deliberate design, no primary and no gold. #194's player lens says that was
// right as a P5 fix and wrong as a game:
//
//   "for ~250 of 257 picks the bar offers the player nothing to *do*, only ways
//    to make the night go faster."
//
// The missing verb was already wired. `openTradeUpBoard(for:)` prices every
// callable slot ahead of the user — including the one currently on the clock —
// and tonight it is reachable only from a `.plain` caption button buried in the
// right rail and a 10 pt phone glyph on each board row. The screen's most
// interesting action was its least visible one.
//
// ## Three stances, never two at once
//
//   DECISION ...... a rival GM is on the phone. The whole bar becomes a
//                   `DSActionBar`: what the deal costs, what it returns, and
//                   `[ghost Decline] [PRIMARY Accept]` in the fixed order.
//
//   ON THE CLOCK .. his turn. The BOARD owns the commit (#197 — the pick modal
//                   is retired), so the bar does NOT duplicate it: it carries
//                   the one verb the board has no room for and the engine only
//                   permits here:
//                   shopping the pick (`requestTradeDown`, hard-guarded on
//                   `isUserOnClock` at `DraftDayCoordinator:641`) — plus Pause,
//                   the one transport control that still has a job while the
//                   clock running is his own.
//
//   TRANSPORT ..... the other ~250 picks. ONE fast-forward and the speed menu
//                   on the left, and on the right the contextual call:
//                   **"Call about #N"**, the one thing a GM can actually do
//                   while somebody else is at the podium.
//
// #195 cut the transport side from three buttons to one. "My pick", "Next
// event" and "Next round" were three phrasings of *make the night go faster*,
// and none of them said where the tape would stop — so the rail spent three
// slots teaching the user nothing and the one destination he actually cares
// about got no more weight than the two he does not. "Skip to my pick" names
// its target in its caption (`#42 · 12 cards away`) and, when his cards are
// spent, retitles itself "Skip to the end" rather than pretending there is
// still a turn to reach.
//
// ## The one thing that does NOT swap (#202)
//
// The War Room button is on the leading edge of all three stances. It carries
// the capital line the retired right-hand column used to print — `R3 · #83 ·
// 3624 pts` — and opens the drawer behind which the rest of that column now
// lives. It is the only control on this bar that is stance-independent, because
// "what am I holding" is the one question that is live in every stance, and a
// door that vanishes when a phone rings is a door you cannot rely on. See
// `warRoomButton` for why the chip and the button are one control and not two.
//
// ## Gold discipline (P5 / P7)
//
// One gold FILL per screen, and this bar holds it — at most once, because the
// three stances are mutually exclusive by construction:
//
//   DECISION ...... gold on `Accept trade`.
//   TRANSPORT ..... gold on `Call about #N`.
//   ON THE CLOCK .. gold on `Shop this pick` (#194 v2 round 2). This stance used
//                   to be deliberately gold-free — and the screenshot of it was
//                   the quietest frame of the night at the loudest moment of it,
//                   two muted navy buttons under a shot literally named
//                   `own_clock_gold_cta`. See `onClockBar` for the full reversal.
//
// The header's clock is gold *ink*, not a fill, and keeps its own job. The
// header no longer draws a CTA at all while an AI club is at the podium (round
// 2), so this bar is the only surface in the room that can light a fill.
//
// Escalation toward the user's turn is ORANGE, never gold — a second gold near
// the gold clock reads as a second clock (the exact defect P7 records). The
// on-deck badge appears at five cards out and tightens at three.
//
// **Swapping rather than stacking is not a layout convenience.** The coordinator
// stops the tape when a phone rings (`autoAdvanceUntil` breaks on
// `pendingTradeOffer != nil`), so there is nothing left for the transport
// controls to transport. A rail of live fast-forward buttons over a question the
// room is holding for you would be lying about the state it is in.

struct DraftControlBar: View {
    @ObservedObject var coordinator: DraftDayCoordinator

    /// Raises the War Room drawer. Owned by `DraftDayView`, because the room has
    /// exactly one `.sheet(item:)` and this is one of the things it presents.
    var onOpenWarRoom: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        switch stance {
        case .decision(let offer):
            decisionBar(for: offer)
        case .onTheClock(let pickNumber):
            onClockBar(pickNumber: pickNumber)
        case .transport(let call):
            transportRail(call: call)
        }
    }

    // MARK: - Which bar

    /// The bar's three states, resolved once per body pass so no two branches
    /// can ever disagree about which one is live.
    private enum Stance {
        case decision(DraftDayTradeEngine.DraftTradeOffer)
        case onTheClock(pickNumber: Int)
        /// `call` is nil when there is nothing to call about: the draft is not
        /// live, or his card count is spent (`picksUntilUserPick == -1`).
        case transport(call: CallTarget?)
    }

    /// Everything the contextual CTA needs, gathered in one place because
    /// `picksUntilUserPick` is an O(n) scan and the bar rebuilds once a second
    /// behind the ticking clock.
    private struct CallTarget {
        let onClockPickNumber: Int
        /// Always > 0 here; 0 is the on-the-clock stance.
        let picksAway: Int
        let nextUserPickNumber: Int?
    }

    private var stance: Stance {
        // The phone wins, INCLUDING on his own clock (#197). It used to be
        // `mode != .userPick` here, because the pick sheet rendered the offer
        // banner inline and the bar deferred to it. That sheet is retired and
        // the room has no other surface that can answer a call, so without this
        // an AI club trading up for the slot the user is on the clock with
        // would be an offer he could see in the ticker and never accept or
        // decline. Nothing is lost from the on-the-clock stance while an offer
        // is live: `Shop this pick` is already disabled by
        // `pendingTradeOffer != nil`, and the commit — the card he hands in —
        // is on the board behind this bar, not on the bar itself.
        if let offer = coordinator.pendingTradeOffer {
            return .decision(offer)
        }
        // `mode == .userPick`, NOT `isUserOnClock`. Pausing on your own clock
        // leaves `isUserOnClock` true while `mode` goes to `.paused` — keying
        // the stance off the flag would swap the transport rail out from under
        // a paused user and strand him with no Resume button. The paused case
        // belongs to transport.
        if coordinator.mode == .userPick {
            return .onTheClock(pickNumber: coordinator.currentPick?.pickNumber ?? 0)
        }
        let away = coordinator.picksUntilUserPick
        guard away > 0,
              coordinator.mode != .complete,
              coordinator.mode != .loading,
              let onClock = coordinator.currentPick?.pickNumber else {
            return .transport(call: nil)
        }
        return .transport(
            call: CallTarget(
                onClockPickNumber: onClock,
                picksAway: away,
                nextUserPickNumber: nextUserPickNumber()
            )
        )
    }

    /// The slot his next card is in. Same walk the sticky header does — the two
    /// must never print different numbers, so both read `picks` from
    /// `currentPickIndex` forward rather than caching anything.
    private func nextUserPickNumber() -> Int? {
        guard let teamID = coordinator.userTeamID else { return nil }
        return coordinator.picks
            .dropFirst(coordinator.currentPickIndex)
            .first(where: { $0.currentTeamID == teamID })?
            .pickNumber
    }

    // MARK: - The War Room chip (#202)

    /// The capital read AND the door to the drawer, as ONE control.
    ///
    /// #202 retired the room's right-hand column. Two of the four things it held
    /// are continuous facts — the slot your next card is in, and what your board
    /// is worth in chart points — and the other two (the full ledger, the scout
    /// chatter, the phone radar) are reference material. So the continuous half
    /// comes down here and the reference half goes behind a drawer.
    ///
    /// **Why one control rather than a chip beside a button.** The brief asks
    /// for both, and both is what this is: the chip's line is the button's face.
    /// The rail is already at its width budget in portrait — an on-deck badge, a
    /// two-line skip, Pause, the speed menu and a gold call measure ~656 pt
    /// inside 802 pt of usable 834 pt iPad — so a read-only capsule at ~78 pt
    /// plus a labelled button at ~110 pt does not fit, and what gives way when
    /// it does not fit is the skip caption that names where the tape stops. A
    /// button whose caption is the number costs one width for two jobs, and the
    /// number is *more* useful when it is the thing you press to go read the
    /// ledger behind it.
    ///
    /// **Why it is on every stance, at the leading edge.** The decision stance
    /// is the one moment a GM most wants to know what he is holding, and the
    /// on-clock stance is the one moment he most wants the phone radar — so a
    /// door that vanishes exactly when the room gets interesting is the wrong
    /// door. Leading edge in all three so it does not move under the thumb when
    /// the bar swaps beneath it.
    ///
    /// **Never gold.** The bar's one fill belongs to the stance's commit
    /// (P5/P7). This is a secondary — a place to go and look, not a thing to do.
    private var warRoomButton: some View {
        Button(action: onOpenWarRoom) {
            VStack(alignment: .leading, spacing: 0) {
                Text("WAR ROOM")
                    .font(DSType.display(11, .heavy))
                    .tracking(0.8)
                    .lineLimit(1)
                Text(DraftCapital.chipText(coordinator))
                    .font(DSType.display(11, .semibold))
                    .opacity(0.75)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        // `DSButtonChrome` already guarantees the 44 pt target and paints the
        // plate; the two `Text`s set their own fonts, so the style's 14 pt
        // default lands on neither of them.
        .buttonStyle(.dsSecondary)
        .accessibilityLabel("Open the war room. \(DraftCapital.chipAccessibilityText(coordinator))")
        .accessibilityHint("Your full pick ledger, scout chatter and the trade radar")
    }

    // MARK: - Decision

    /// The explainer says WHO is calling and WHY; each button says what taking
    /// it leaves you holding, in chart points, on the control that produces that
    /// outcome. That is P4's cost→unlock line, split across the two answers
    /// instead of asserted once above them — the user compares the two captions
    /// rather than doing the subtraction himself.
    private func decisionBar(for offer: DraftDayTradeEngine.DraftTradeOffer) -> some View {
        let gives = offer.givesLabel(currentSeason: coordinator.draftYear)
        let gets = offer.getsLabel(currentSeason: coordinator.draftYear)
        let message = [offer.motive, slideRead(for: offer)]
            .compactMap { $0 }
            .joined(separator: " ")
        return stanceStrip {
            DSActionBar(
                explainer: .init(
                    title: "Trade offer \u{2014} \(offer.gmName) \u{00B7} \(offer.gmStyle)",
                    message: message
                ),
                ghost: .init(
                    title: "Decline",
                    caption: "Keep \(gives) \u{00B7} \(offer.userGivesValue) pts",
                    handler: { coordinator.declineTradeOffer() }
                ),
                primary: .init(
                    title: "Accept trade",
                    caption: "Get \(gets) \u{00B7} \(offer.userGetsValue) pts",
                    handler: { coordinator.acceptTradeOffer() }
                )
            )
        }
    }

    /// Whether the man at the top of YOUR board survives the slide, as a
    /// sentence for the offer explainer.
    ///
    /// Sit-or-move is not a points question and the bar was asking it as one:
    /// `875 pts` against `921 pts`, and the bigger number wins every time.
    /// `DraftAvailability` has modelled the actual input — is he still there
    /// when you pick again — since the scouting screens were built, and the
    /// draft room was the one place it was never printed.
    ///
    /// Only on a slide. Moving UP lands you ahead of the board, where survival
    /// is not the question being asked, and a deal that returns nothing in this
    /// year's pool has no landing slot to read against.
    private func slideRead(for offer: DraftDayTradeEngine.DraftTradeOffer) -> String? {
        guard case .userMovesDown = offer.kind else { return nil }
        guard let landing = offer.userGetsPicks
            .filter({ $0.seasonYear == coordinator.draftYear })
            .map({ $0.pickNumber })
            .min() else { return nil }
        // The club's own board, not the media's — the whole point of the read is
        // that it answers for the man the building wants.
        let ranked = coordinator.availableProspects.compactMap { prospect in
            coordinator.userBoardRanks[prospect.id].map { (prospect: prospect, rank: $0) }
        }
        guard let target = ranked.min(by: { $0.rank < $1.rank })?.prospect,
              let read = DraftAvailability.read(
                  for: target,
                  atPick: landing,
                  consensusRank: coordinator.publicBoardRanks[target.id]
              ) else { return nil }
        return "Your board's top man, \(target.position.rawValue) \(target.fullName), "
            + "is **\(read.percent)%** to reach #\(landing)."
    }

    // MARK: - The strip the two `DSActionBar` stances sit on

    /// `DSActionBar` paints its own plate and hairline over its own width, so a
    /// control rendered *beside* it — the War Room button, and Pause on the
    /// clock — would float over the board with a seam down the middle of the
    /// rail. This carries the plate and the top rule across the whole width so
    /// each stance reads as one surface.
    ///
    /// Extracted in #202: `onClockBar` grew this treatment for Pause and the
    /// decision stance now needs the same thing for the War Room button, and two
    /// copies of a plate-and-hairline is how the two stances end up a pixel
    /// apart.
    private func stanceStrip<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: DSSpacing.xs) {
            warRoomButton
                .padding(.leading, DSSpacing.md)
            content()
        }
        .background(Color.backgroundSecondary)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.surfaceBorder).frame(height: 1)
        }
    }

    // MARK: - On the clock

    /// His turn. The BOARD in front of this bar owns the commit — a second
    /// "make your pick" here would be a gold button that cannot do anything the
    /// board is not already doing, which is the dead-primary defect in reverse.
    /// (#197: that used to read "the sheet". The pick modal is retired; the
    /// commit is the row's PICK chip and the full card's `Draft him — Pick #N`.)
    ///
    /// What the bar adds is the verb the engine only permits in this exact
    /// window. `requestTradeDown()` is hard-guarded on `isUserOnClock`, so
    /// trade-down genuinely cannot surface early; the moment it CAN, it is on
    /// the room's own commit surface instead of three-quarters of the way down
    /// a modal's scroll body.
    ///
    /// **The gold moved HERE in round 2, and the reasoning that kept it out was
    /// backwards** (#194 v2, spec 5: "oma kello → kello + kulta-CTA hallitsee").
    ///
    /// The old argument was that a gold `Shop this pick` would out-shout the
    /// commit on the board. What the round-1 screenshots actually showed was the
    /// opposite failure: during ~250 AI clocks the bar carried a bright gold
    /// `Call about #N`, and then at the one moment of the night that belongs to
    /// the user — his own clock, named in the shot as `own_clock_gold_cta` —
    /// **both** actions rendered as muted dark navy. The screen got quieter
    /// exactly when it should get louder, and the user reads that as "there is
    /// nothing to do here".
    ///
    /// So the fill is inverted. Gold marks the stance's one *bar-level* verb,
    /// which is the trade-down the engine permits only in this window, and the
    /// header spends none of the budget while a running own clock is up (see
    /// `DraftStickyHeader.headerAction`) — so the count is still exactly one
    /// gold fill on the screen. The card he hands in is still committed on the
    /// board and on the prospect's own full card; those are gold-free surfaces
    /// with their own affordances, and the board is not competing with a bar
    /// button for the same tap.
    ///
    /// `tradeDownMessage` is cleared at the top of every `beginCurrentPick`, so
    /// a non-nil message means *this* slot has already been answered — and the
    /// gold goes disabled-grey with it, which is the correct reading: the verb
    /// is spent, not missing.
    ///
    /// A live offer never reaches this branch any more — `stance` gives the bar
    /// to the phone — so the copy below no longer has an "answer it elsewhere"
    /// case to explain.
    ///
    /// **Pause leads the stance.** The stance split moved the transport rail out
    /// from under the user the moment his own clock started, and `pauseButton`
    /// lived only on that rail — so the one clock he most needs to stop (he opens
    /// a prospect's full card to read the file, which deliberately does NOT hold
    /// the countdown) was the one clock with no stop control, and `autoPickForUser`
    /// filed a card for him while he read. It is rendered beside the bar rather
    /// than inside it because `DSActionBar`'s three right-hand slots are spoken
    /// for and Pause is transport, not a commit. Tapping it sends `mode` to
    /// `.paused`, which hands the bar back to the transport rail and its Resume —
    /// the round trip `pausedMode` was built for.
    private func onClockBar(pickNumber: Int) -> some View {
        let alreadyShopped = coordinator.tradeDownMessage != nil
        let message: String = {
            if let feedback = coordinator.tradeDownMessage { return feedback }
            return "**\(coordinator.clockSeconds)s** left. Hand in a card from the board, or shop the slot to a club behind you."
        }()
        return stanceStrip {
            pauseButton

            DSActionBar(
                explainer: .init(
                    title: "You are on the clock \u{2014} #\(pickNumber)",
                    message: message,
                    isWarning: alreadyShopped || coordinator.clockSeconds <= 30
                ),
                ghost: .init(
                    title: "Call about moving up",
                    caption: "Price the slots ahead of you",
                    isEnabled: !coordinator.isTradeUpBoardOpen,
                    handler: { coordinator.openTradeUpBoard() }
                ),
                // THE GOLD, ON THE ONE STANCE THAT USED TO HAVE NONE.
                // See `onClockBar`'s doc for why this inverted in round 2.
                primary: .init(
                    title: "Shop this pick",
                    caption: alreadyShopped ? "Already shopped" : "Take calls from behind you",
                    isEnabled: !alreadyShopped && coordinator.pendingTradeOffer == nil,
                    handler: { coordinator.requestTradeDown() }
                )
            )
        }
    }

    // MARK: - Transport

    private func transportRail(call: CallTarget?) -> some View {
        HStack(spacing: DSSpacing.xs) {
            // Leading, exactly as in the other two stances (see `warRoomButton`)
            // so the door to the ledger does not move under the thumb when the
            // bar swaps beneath it.
            warRoomButton

            if let call, call.picksAway <= 5 {
                onDeckBadge(call)
            }

            skipButton

            Spacer(minLength: DSSpacing.sm)

            pauseButton

            speedMenu

            if let call {
                callButton(call)
            }
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.backgroundSecondary)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.surfaceBorder).frame(height: 1)
        }
        .dsElevation(.bar)
    }

    // MARK: Pause / Resume — shared by the transport rail and the on-clock bar

    /// One button that flips, and it is only live while there is a clock to
    /// stop. Both stances that have one render it: the rail (`.playing`, and
    /// `.paused` where it is the Resume) and `onClockBar` (`.userPick`). `pause()` and `resume()` are both hard-guarded on the mode
    /// (#195), so before the draft starts and after it ends this used to be a
    /// control that reported nothing and did nothing when tapped.
    ///
    /// Resume no longer costs the user his remaining seconds — the countdown
    /// picks up where it stopped — so "Pause" is now a genuine transport
    /// control rather than the free timeout it was.
    private var pauseButton: some View {
        let paused = coordinator.mode == .paused
        let live = paused
            || coordinator.mode == .playing
            || coordinator.mode == .userPick
        return Button {
            if paused { coordinator.resume() } else { coordinator.pause() }
        } label: {
            Label(
                paused ? "Resume" : "Pause",
                systemImage: paused ? "play.fill" : "pause.fill"
            )
        }
        .buttonStyle(.dsSecondary)
        .disabled(!live)
        .accessibilityLabel(
            paused
                ? "Resume the draft at \(coordinator.clockSeconds) seconds"
                : "Pause the draft"
        )
    }

    // MARK: The one fast-forward (#195)

    /// Where a tap on the rail's fast-forward is aiming.
    ///
    /// The three states are what the old three buttons were hiding. "My pick",
    /// "Next event" and "Next round" were three ways of saying *make the night
    /// go faster* and not one of them said **where it would stop** — and two of
    /// them stopped somewhere the user had not asked for and could not predict.
    /// One button that names its destination is a smaller surface that answers a
    /// bigger question.
    private enum SkipTarget {
        /// `number` is the slot his next card is in; `picksAway` is ≥ 1.
        case myPick(number: Int?, picksAway: Int)
        /// His card count is spent — the only thing left to skip to is the end.
        case endOfDraft
        case unavailable(reason: String)
    }

    private var skipTarget: SkipTarget {
        guard coordinator.userTeamID != nil else {
            return .unavailable(reason: "No club on the clock for you")
        }
        switch coordinator.mode {
        case .loading, .preDraft:
            return .unavailable(reason: "The draft has not started")
        case .complete:
            return .unavailable(reason: "The draft is over")
        case .playing, .paused, .userPick:
            break
        }
        let away = coordinator.picksUntilUserPick
        // -1 is `picksUntilUserPick`'s "he owns nothing else tonight".
        if away < 0 { return .endOfDraft }
        // 0 means he IS on the clock, which only reaches the transport rail when
        // he paused on his own turn. Resume is the button that matters there.
        if away == 0 { return .unavailable(reason: "You are on the clock") }
        return .myPick(number: nextUserPickNumber(), picksAway: away)
    }

    /// One ghost button, never gold: the gold on this rail belongs to
    /// "Call about #N", the thing a GM can *do*. Fast-forward is how he gets
    /// through the parts he cannot act on, and a second fill beside the first
    /// would put the room's loudest control on its least consequential verb.
    ///
    /// It routes to `skipToMyPick()`, which is the existing advance mechanism —
    /// `autoAdvanceUntil` runs the AI's cards with the market rolls intact and
    /// stops at the two things the user owes an answer to (a ringing phone, a
    /// round recap) — and falls through to `completeDraft()` on its own when the
    /// board runs out, which is the `.endOfDraft` case with no separate path.
    private var skipButton: some View {
        let target = skipTarget
        let enabled: Bool = {
            if case .unavailable = target { return false }
            return true
        }()
        return Button { coordinator.skipToMyPick() } label: {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "forward.end.fill")
                VStack(alignment: .leading, spacing: 0) {
                    Text(skipTitle(target))
                        .font(DSType.text(14, .semibold))
                        .lineLimit(1)
                    Text(skipCaption(target))
                        .font(DSType.display(11, .semibold))
                        .opacity(0.75)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.dsGhost)
        .disabled(!enabled)
        .accessibilityLabel("\(skipTitle(target)). \(skipCaption(target))")
    }

    private func skipTitle(_ target: SkipTarget) -> String {
        switch target {
        case .endOfDraft: return "Skip to the end"
        default:          return "Skip to my pick"
        }
    }

    private func skipCaption(_ target: SkipTarget) -> String {
        switch target {
        case .myPick(let number, let picksAway):
            guard let number else {
                return picksAway == 1 ? "Next card" : "\(picksAway) cards away"
            }
            return picksAway == 1
                ? "#\(number) \u{2014} next card"
                : "#\(number) \u{00B7} \(picksAway) cards away"
        case .endOfDraft:
            return "No cards left \u{00B7} play it out"
        case .unavailable(let reason):
            return reason
        }
    }

    // MARK: The contextual call

    /// The bar's one gold fill, and the only thing a GM can DO while somebody
    /// else is at the podium.
    ///
    /// It routes to the existing `openTradeUpBoard()` with no prospect, which is
    /// the "price every callable slot ahead of me" case the coordinator already
    /// implements — `DraftDayTradeEngine.tradeUpTargets` returns exactly those
    /// picks, the one on the clock included. No new engine path; the sheet this
    /// opens is the same `TradeUpBoardSheet` the right rail's caption button and
    /// the big board's phone glyph have always opened.
    private func callButton(_ call: CallTarget) -> some View {
        Button {
            coordinator.openTradeUpBoard()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text("Call about #\(call.onClockPickNumber)")
                    .font(DSType.text(14, .semibold))
                    .lineLimit(1)
                Text(callCaption(call))
                    .font(DSType.display(11, .semibold))
                    .opacity(0.75)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.dsPrimary)
        .disabled(coordinator.isTradeUpBoardOpen || coordinator.mode == .preDraft)
        .accessibilityLabel(
            "Call about pick number \(call.onClockPickNumber). \(callCaption(call))"
        )
    }

    private func callCaption(_ call: CallTarget) -> String {
        guard let next = call.nextUserPickNumber else { return "Move up the board" }
        return "Move up from #\(next)"
    }

    // MARK: The escalation

    /// "N picks away", rendered at a weight the room can be read at.
    ///
    /// #194: the approach toward your own turn used to be one 14 pt grey
    /// sentence in the header that turned orange at ≤3 — the same visual weight
    /// as a table row, for one of the three beats that should carry the night.
    /// Here it is a badge that appears at five cards out, hardens at three, and
    /// breathes at two so it catches the eye of a user watching the board rather
    /// than the chrome.
    ///
    /// Orange, not gold: gold's jobs on this screen are the clock and the bar's
    /// single primary fill, and a third gold beside them reads as a second
    /// clock (P7's semantic hue separation).
    private func onDeckBadge(_ call: CallTarget) -> some View {
        let urgent = call.picksAway <= 3
        let tint: Color = urgent ? Color.alertOrange : Color.textSecondary
        let label = call.picksAway == 1
            ? "UP NEXT"
            : "\(call.picksAway) PICKS AWAY"
        return HStack(spacing: DSSpacing.xxs) {
            // `.id` is load-bearing: the modifier's own `@State` must start from
            // "not dimmed" every time breathing turns on, otherwise a badge that
            // has already breathed once tonight comes back stuck at 0.30 with no
            // animation to move it (the value it animates never changed).
            OnDeckPulse(tint: tint, active: breathes(call))
                .id(breathes(call))
            Text(label)
                .font(DSType.display(12, .heavy))
                .tracking(0.8)
                .foregroundStyle(tint)
                .lineLimit(1)
        }
        .padding(.horizontal, DSSpacing.xs)
        .frame(minHeight: 44)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                .fill(tint.opacity(urgent ? 0.16 : 0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                .strokeBorder(tint.opacity(0.45), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            call.picksAway == 1
                ? "You are up next"
                : "Your pick is \(call.picksAway) cards away"
        )
    }

    /// Reduce Motion turns the pulse off entirely — the colour and the copy
    /// already carry the state, so nothing is lost when the dot holds still.
    private func breathes(_ call: CallTarget) -> Bool {
        !reduceMotion && call.picksAway <= 2
    }

    // MARK: Speed

    /// Speed is a *setting*, not a commit, so it stays a menu — but it is a
    /// 44 pt one now (§2.12 has no exceptions) and it states its unit, because
    /// a bare "2" beside three transport buttons reads as a count of something.
    private var speedMenu: some View {
        Menu {
            ForEach(Self.speeds, id: \.self) { speed in
                Button(Self.label(for: speed)) { coordinator.setSpeed(speed) }
            }
        } label: {
            HStack(spacing: DSSpacing.xxs) {
                Image(systemName: "speedometer")
                Text(Self.label(for: coordinator.speed))
                    .font(DSType.display(14, .heavy))
            }
            .foregroundStyle(Color.textPrimary)
            .padding(.horizontal, DSSpacing.md)
            .frame(minWidth: 88, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                    .fill(Color.backgroundTertiary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                    .strokeBorder(Color.surfaceBorder, lineWidth: 1)
            )
            .dsElevation(.chip)
        }
        .accessibilityLabel("Broadcast speed, \(Self.label(for: coordinator.speed))")
    }

    private static let speeds: [Double] = [0.5, 1.0, 2.0, 4.0]

    /// `Int(0.5)` is 0, so the old menu offered "0×" — a speed at which the
    /// draft does not happen.
    private static func label(for speed: Double) -> String {
        speed == speed.rounded() ? "\(Int(speed))\u{00D7}" : "\(speed)\u{00D7}"
    }
}

// MARK: - The on-deck dot
//
// A 6 pt breathing dot, in its own view so the repeating animation owns a piece
// of state nobody else writes to. It is the ONLY motion the control bar has:
// §2.12's rule is that motion states a change, and "your turn is two cards away"
// is the one change on this surface that the user is not already looking at.
//
// Reduce Motion is honoured by the CALLER passing `active: false` — the tint and
// the copy carry the state on their own, so nothing is lost when the dot holds
// still.

private struct OnDeckPulse: View {
    let tint: Color
    let active: Bool

    @State private var dim = false

    var body: some View {
        Circle()
            .fill(tint)
            .frame(width: 6, height: 6)
            .opacity(dim ? 0.30 : 1)
            .onAppear {
                guard active else { return }
                withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
                    dim = true
                }
            }
    }
}
