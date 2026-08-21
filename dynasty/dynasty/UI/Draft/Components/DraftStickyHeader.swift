import SwiftUI
import UIKit

// MARK: - DraftStickyHeader — the room's chrome (#105 Wave 3b, #194 D)
//
// UI_REDESIGN_VISION §3 family 8: "It needs the pick band on top of its
// text-only 'ROUND 2 — Pick 14/32'."
//
// That line is gone. `DraftPickBand`'s head is now **the one place the draft
// prints its count** (P1), and the header keeps only the things the band cannot
// say: who is on the clock, how long they have, what this club still needs —
// and, since #194 D, **what the user can do about any of it without looking
// down**.
//
// ## The action cluster (#194 D (a))
//
// The ask was "toiminnot ylhäällä", and it is the right ask: the header is
// where the eyes already are — the clock, the club, the ribbon of cards — while
// every verb the room offered lived at the bottom rail, ~900 pt away on a
// landscape iPad. #194 v2 round 2 narrowed that from "the verb for the current
// stance" to **one verb, in one stance**:
//
//   somebody else at the podium ... NOTHING. Round 1 put a ghost "Call about #N"
//                                   here — the same handler and the same words
//                                   as the bar's gold CTA — so the screenshot
//                                   carried the identical call to action twice.
//                                   One verb, one place; see `headerAction`.
//   his own clock, FROZEN ......... "Make the pick" (i.e. un-freeze it)
//   his own clock, running ........ NOTHING. The commit is not the header's to
//                                   offer: since #197 the card is handed in on
//                                   the board itself (`LiveBigBoardPanel`'s row
//                                   chip, or `ProspectDetailView` in
//                                   `ProspectDraftContext`), and neither of
//                                   those surfaces is reachable from here
//                                   without a second commit path.
//
// **The cluster never mints a second verb, and never mints a dead one.**
// `Make the pick` is `resume()` — hard-guarded on `mode == .paused`
// (`DraftDayCoordinator:500`), so the branch that draws it is keyed on that same
// mode rather than on `isUserOnClock`. Keying it on the flag is what made this a
// gold, fully-enabled button that did nothing at all for the whole 120 s of the
// user's turn. No new engine path, no second sheet.
//
// ## Gold discipline (P5 / P7), restated for two surfaces
//
// Gold has three jobs and this header holds one of them by name — "the live/now
// indicator (**the draft clock**, an open FA wave)". That one is gold *ink*. The
// other rule is that exactly one gold FILL may be lit on the screen at a time,
// and there are two surfaces that can light one, so the rule is enforced by
// construction rather than by comment:
//
//   the user is NOT on the clock .. `DraftControlBar`'s transport stance owns
//                                   the gold fill (`Call about #N`); this header
//                                   draws no verb at all.
//   his own clock, running ........ the bar's on-clock stance owns the gold fill
//                                   (`Shop this pick` — round 2, spec 5) and
//                                   this header draws no verb, so the budget is
//                                   spent exactly once.
//   his own clock, FROZEN ......... the bar is showing transport with `call ==
//                                   nil` (he IS the club on the clock, so there
//                                   is nobody to call about), which has no gold,
//                                   so the header's "Make the pick" is free to
//                                   take it.
//   …unless a club is on the phone  the bar's `.decision` stance fires for any
//                                   pending offer and lights a gold "Accept
//                                   trade". The header's CTA drops to SECONDARY
//                                   for that case; see `ownCardIsGold`.
//
// At most one gold fill, always, without either file having to ask the other
// what it is currently drawing.
//
// ## What #194 v2 changed (specs 2 and 5)
//
// The first restage was rejected on two counts this header owns: "värit
// puuttuvat" and "ei war room -tunnelmaa". Three answers, all here:
//
//   the club PLATE ..... a filled block of the club's own colour with its
//                        abbreviation on it, next to the sentence. A wash under
//                        text is bounded by that text's contrast floor and is,
//                        unavoidably, a tint of navy; a surface with no text on
//                        it can run the colour at 100 %. The wash (now 0.21,
//                        reaching to 0.55 of the width) and the 6 pt stripe stay
//                        — the plate is what makes them read as deliberate
//                        rather than as a rendering artefact.
//   the club BASE RULE . 3 pt of the same colour closing the header, replacing a
//                        neutral 1 pt hairline.
//   ONE STAR ........... see `Focus`. The header now knows which of the night's
//                        three beats is live and sizes itself against it, so it
//                        can hand the screen to the centre column's reveal card
//                        during an AI clock and take it back the moment the
//                        user's own card is three away.

struct DraftStickyHeader: View {
    @ObservedObject var coordinator: DraftDayCoordinator

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// **The round that just turned over, while its plate is up** (#198 (2)).
    /// `nil` the rest of the night. See ``roundRolloverPlate(_:)``.
    @State private var rolloverRound: Int?
    /// A rollover that has happened but has not been SHOWN yet, because the
    /// round recap sheet was covering the room when it did.
    @State private var armedRolloverRound: Int?
    /// Bumped whenever a plate's dwell is superseded, so an orphaned timer
    /// cannot take a later round's plate off the screen early.
    @State private var rolloverToken = 0

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack(alignment: .center, spacing: DSSpacing.sm) {
                clubIdentity
                Spacer(minLength: DSSpacing.sm)
                // **The escalation rides the top row** (#194 v3, fix 3). v2 put
                // it on the third row, left of the "your next pick" sentence —
                // correct type (title2) in the wrong postcode. That row is the
                // header's footnote line: it sits under the pick band, below the
                // fold of the glance, and shares its baseline with a strip of
                // 11 pt need pills, so the loudest beat of the night was
                // announced in the quietest slot on the surface.
                //
                // Here it is on the clock's own row, immediately before it, which
                // is where the eyes already are. The order still reads off the
                // type scale — title2 orange against a title3 gold clock during
                // escalation (the clock is only `isHero`/title1 on the user's own
                // card, and `focus` cannot be `.escalating` and `.ownClock` at
                // once) — so promoting the beat does not cost the clock its job.
                if case .escalating(let away) = focus {
                    escalationCall(picksAway: away)
                }
                headerActionButton
                DraftClockBadge(
                    seconds: coordinator.clockSeconds,
                    capacity: clockCapacity,
                    speed: coordinator.speed,
                    isPaused: coordinator.mode == .paused,
                    isUserOnClock: coordinator.isUserOnClock,
                    isRunning: coordinator.mode == .playing || coordinator.mode == .userPick,
                    isHero: focus == .ownClock
                )
            }

            // THE RIBBON ROLLS OVER, AND IT SAYS SO (#198 (2)).
            //
            // `DraftBroadcastRail`'s header records why the full-screen gold
            // "ROUND 2 BEGINS" curtain was deleted: it fired ~7 times a night,
            // carried no information, and arrived in the same instant as the
            // round recap sheet — two interruptions for one event. Its
            // replacement was supposed to be structural ("the ribbon rolls over
            // and its head reads ROUND 3 · PICK 1 OF 32"), and the head does
            // read that — but a headline changing while nine slats slide by one
            // position is not a beat, it is a diff. Seven rounds went past with
            // nothing marking any of them.
            //
            // This is the structural version: the ribbon dims and slides out
            // from under a plate that names the round that just finished and
            // the one now on the clock, for ``rolloverDwell`` seconds, INSIDE
            // the band's own height. Three properties keep it from becoming the
            // curtain again:
            //
            //   * **It never covers a deadline.** The plate is confined to the
            //     band, so the clock row above it and the needs row below stay
            //     visible — the exact rule the rail's placement obeys.
            //   * **It never doubles the recap.** A round boundary raises
            //     `pendingRoundRecap` in the same instant, and a plate drawn
            //     behind a sheet is a beat nobody sees. It is ARMED instead and
            //     shown when the room comes back (``presentArmedRollover()``).
            //   * **It is not a modal.** Nothing waits for it, nothing is
            //     hidden behind it, and Reduce Motion gets the same plate with
            //     no animation at all.
            // `.leading` — vertically centred on the band, so the plate lands on
            // the RIBBON rather than on the band's own head, which is the line
            // that already states the count the plate is punctuating.
            ZStack(alignment: .leading) {
                // The pick band. `.equatable()` is load-bearing, not tidy:
                // `clockSeconds` republishes once a second, and without the
                // gate the ribbon's `GeometryReader` + `ScrollViewReader` +
                // nine parallelograms are re-laid-out on every tick. See
                // `DraftPickBand`.
                DraftPickBand(model: DraftPickBand.Model(coordinator: coordinator))
                    .equatable()
                    // The ROLL. Both channels are non-layout-affecting, so the
                    // ribbon cannot resize the header on its way past — the
                    // lesson `PickRevealCard`'s entrance learned the hard way
                    // (a scale re-paints a card's box inside a clipping panel).
                    .opacity(rolloverRound == nil ? 1 : 0.22)
                    .offset(x: rolloverRound == nil ? 0 : 28)

                if let round = rolloverRound {
                    roundRolloverPlate(round)
                }
            }
            .onChange(of: coordinator.currentPick?.round) { old, new in
                roundDidChange(from: old, to: new)
            }
            // The recap sheet coming down is the cue for an armed plate. A
            // Bool rather than the value itself: `RoundRecapData` is not
            // `Equatable`, and "is the room visible" is all this needs.
            .onChange(of: coordinator.pendingRoundRecap == nil) { _, isClear in
                if isClear { presentArmedRollover() }
            }

            HStack(alignment: .center, spacing: DSSpacing.sm) {
                userNextPickInfo
                Spacer(minLength: DSSpacing.sm)
                if !coordinator.teamNeedScores.isEmpty {
                    teamNeedsStrip
                }
            }
        }
        // **THE HEADER IS A BAND, AND ITS HEIGHT IS AN ADDITION** (#206).
        //
        // Every term is fixed, and they are written down because the whole
        // defect this pass fixes was one of them silently becoming flexible:
        //
        //     12 + 12  the band's own vertical padding (`sm`, not `md` — the
        //              three rows already carry their own breathing room and
        //              16 pt top and bottom is a fourth gap that buys nothing)
        //     ~42      row 1, set by the hero clock: title1 numerals over a
        //              4 pt gap and the 4 pt drain bar
        //     8        `xs`
        //     90       `DSSlatBand` at full scale: 8 + 14 head + 4 + 56 ribbon
        //              + 8
        //     8        `xs`
        //     ~22      row 3, the next-pick line and the needs pills
        //     ------
        //     ~194 pt  on the user's own clock; ~186 with the clock at title3.
        //
        // Horizontal padding stays `md`: the club plate has to clear the 6 pt
        // club stripe `clubSurface` paints down the leading edge.
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(clubSurface)
        .overlay(alignment: .bottom) { clubBaseRule }
    }

    /// The header's foot, in the colours of the club at the podium.
    ///
    /// A 1 pt `surfaceBorder` hairline used to close the header, which is the
    /// correct treatment for a divider between two neutral surfaces and the
    /// wrong one for the edge of the only band on the screen that changes hands
    /// every sixty seconds. 3 pt of club colour, cross-fading with the podium,
    /// is a non-text mark — `DraftTeamTint` already guarantees it ≥ 3 : 1
    /// against the plate (WCAG 2.2 SC 1.4.11) — and it is the third statement of
    /// the same fact, after the plate and the wash.
    private var clubBaseRule: some View {
        Rectangle()
            .fill(onClockAbbreviation.map { DraftTeamTint.accent(for: $0) } ?? Color.surfaceBorder)
            .frame(height: onClockAbbreviation == nil ? 1 : 3)
            .animation(.easeInOut(duration: 0.35), value: onClockAbbreviation)
    }

    // MARK: - One star per moment (#194 v2, spec 5)
    //
    // The room has three beats and exactly one of them may be loud at a time.
    // This type resolves which, and every size in the header is expressed
    // against it — so the answer to "what is the biggest thing on this screen
    // right now" is one switch rather than an emergent property of six views
    // that each picked their own font.
    //
    //   podium ...... somebody else is at the podium and the user is not close.
    //                 The star is the centre column's reveal card, so NOTHING in
    //                 this header exceeds `title3`, the clock included.
    //   escalating .. his card is three or fewer away. The header IS the star:
    //                 the approach line goes to `title2` and takes a rule and a
    //                 pulsing dot with it.
    //   ownClock .... his clock is running or frozen. The star is the clock and
    //                 the gold CTA beside it; the clock alone goes to `title1`
    //                 and everything else stays at or under `title3`.

    private enum Focus: Equatable {
        case podium
        case escalating(picksAway: Int)
        case ownClock
    }

    private var focus: Focus {
        if coordinator.isUserOnClock { return .ownClock }
        let away = coordinator.picksUntilUserPick
        if away > 0, away <= 3 { return .escalating(picksAway: away) }
        return .podium
    }

    /// The headline never takes the star. It NAMES the club, and the plate
    /// beside it is already carrying that at full strength.
    private var headlineSize: CGFloat { DSType.Size.title3 }

    // MARK: - The club on the clock (#194 A)

    /// The abbreviation of whoever is on the clock, or `nil` between picks.
    ///
    /// Falls back to the pick's stored abbreviation the way `DraftPickBand`
    /// does: a traded pick whose new owner is not in `teamsByID` still knows
    /// which club is holding it.
    private var onClockAbbreviation: String? {
        guard let pick = coordinator.currentPick else { return nil }
        return coordinator.teamsByID[pick.currentTeamID]?.abbreviation ?? pick.teamAbbreviation
    }

    /// The header's surface, wearing the colours of the club on the clock.
    ///
    /// The war room is the one screen in the app that is *about* thirty-two
    /// clubs taking turns, and it painted none of them — the same header, in the
    /// same navy, whoever was standing at the podium. Now the club is stated
    /// three ways at once, none of which is colour alone: the sentence names
    /// them, the band's current slat carries the abbreviation, and this surface
    /// carries their tint.
    ///
    /// **The contrast budget is `DraftTeamTint.headerWashOpacity`, and it is
    /// measured, not chosen** — see that file. Two further guards here:
    ///
    ///   * The plate is `backgroundSecondary` at `DraftRoomSurface`'s
    ///     **0.82**, which is what lets the war room read through the header as
    ///     well as through the three glass columns below it. Composited over the
    ///     brightest pixel in the backdrop's header band (a blown-out ceiling
    ///     downlight, already knocked down by the image's 0.42 and the scrim's
    ///     0.60) AND wearing each club's own wash — which since #194 v3 is
    ///     solved per club rather than flat, ranging 0.22 (CIN, DEN, KC, NO) to
    ///     0.40 (PIT, LV, CHI, SEA, CAR) — this surface leaves, across all 32
    ///     clubs, `textPrimary` at ≥ 8.78 : 1, `accentGold` at ≥ 4.25 : 1 and
    ///     `alertOrange` at ≥ 3.43 : 1. The last of those appears only as
    ///     `escalationCall`'s 22 pt black, i.e. WCAG large text on a 3 : 1 floor.
    ///     `textSecondary` is no longer printed inside the washed zone at all
    ///     (it would measure 3.7 : 1 under the strongest wash); that is what paid
    ///     for the colour, in round 2 and again in v3.
    ///
    ///     Raising the plate is NOT the lever it looks like: 0.82 → 0.92 buys
    ///     0.13 : 1, because the scrim above the plate already dominates the
    ///     composite. The lever is the ink.
    ///
    ///     **This is why the backdrop's scrim is heavy at the top and light in
    ///     the middle.** The header is the tightest budget on the screen — it is
    ///     the only surface that carries a club wash under text — so it gets
    ///     0.60 of plate over the room while the table band, whose cards carry
    ///     no wash, gets 0.10 and shows the photograph.
    ///   * The stripe and the wash are the club's whole presence. No text on
    ///     this header is ever painted in a club colour, so nothing here has to
    ///     clear 4.5 : 1 in thirty-two different hues.
    private var clubSurface: some View {
        ZStack(alignment: .leading) {
            Color.backgroundSecondary.opacity(DraftRoomSurface.headerFillAlpha)
            if let abbreviation = onClockAbbreviation {
                DraftTeamTint.headerWash(for: abbreviation)
                Rectangle()
                    .fill(DraftTeamTint.accent(for: abbreviation))
                    .frame(width: DraftTeamTint.stripeWidth)
            }
        }
        // The club cross-fades as the podium changes hands. Driven off the
        // abbreviation, not off the coordinator, so the once-a-second clock
        // republish does not restart it.
        .animation(.easeInOut(duration: 0.35), value: onClockAbbreviation)
    }

    // MARK: - Who is on the clock

    /// The club, stated as a colour first and a sentence second.
    private var clubIdentity: some View {
        HStack(spacing: DSSpacing.xs) {
            if let abbreviation = onClockAbbreviation {
                clubPlate(abbreviation)
                    .transition(.opacity)
            }
            onTheClockText
        }
        .animation(.easeInOut(duration: 0.35), value: onClockAbbreviation)
    }

    /// **The club, at full saturation, in one solid block** (#194 v2, spec 2).
    ///
    /// The v1 pass painted club identity as a 4 pt stripe and a 0.14 wash, and
    /// the verdict on it was "värit puuttuvat" — correctly. A wash that has to
    /// stay under a contrast budget for the small text printed on top of it can
    /// only ever be a tint of navy; at the size a screenshot is actually read it
    /// is navy. The fix is not a bigger wash (the budget is real and measured in
    /// `DraftTeamTint.headerWashOpacity`) but a surface with NO small text on
    /// it: three uppercase letters on a filled plate, where the club colour can
    /// run at 100 %.
    ///
    /// ## The ink is chosen, not assumed — and it is chosen ONCE for the room
    ///
    /// `DraftTeamTint.accent` promises 3 : 1 against the app's plate, which is
    /// the right floor for a rule and the wrong one for a word. `DraftClubInk`
    /// is the room's answer to that (it lifts the same accent to ≥ 4.6 : 1
    /// against `backgroundPlate` and prints the plate as ink), and this plate
    /// uses it rather than re-deriving its own: the header and the ticker's club
    /// chips would otherwise show the same club in two different shades of the
    /// same hue on one screen, which reads as a rendering fault rather than as
    /// two components.
    ///
    /// Hue is still never touched, so Seattle is blue and Baltimore is purple.
    private func clubPlate(_ abbreviation: String) -> some View {
        let fill = DraftClubInk.fill(for: abbreviation)
        return Text(abbreviation)
            .font(DSType.display(DSType.Size.title3, .black))
            .tracking(1.2)
            .foregroundStyle(fill == nil ? Color.textSecondary : DraftClubInk.ink)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, DSSpacing.xs)
            .padding(.vertical, DSSpacing.xxs)
            .background(
                RoundedRectangle(cornerRadius: DSCornerRadius.inline, style: .continuous)
                    .fill(fill ?? Color.backgroundTertiary)
            )
            .accessibilityHidden(true)
    }

    private var onTheClockText: some View {
        Group {
            if let pick = coordinator.currentPick,
               let team = coordinator.teamsByID[pick.currentTeamID] {
                if coordinator.isUserOnClock {
                    Text("You are on the clock")
                        .font(DSType.display(headlineSize, .black))
                        .tracking(1.0)
                        .foregroundStyle(Color.textPrimary)
                } else {
                    Text("On the clock: \(team.fullName)")
                        .font(DSType.display(headlineSize, .heavy))
                        .tracking(0.8)
                        .foregroundStyle(Color.textPrimary)
                }
            } else {
                Text("Draft")
                    .font(DSType.display(headlineSize, .heavy))
                    .tracking(0.8)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .lineLimit(1)
    }

    // MARK: - The action cluster (#194 D (a))

    /// The one verb this stance offers, or nothing.
    ///
    /// Resolved once per body pass — the same shape as `DraftControlBar.Stance`
    /// and reading the same coordinator facts in the same order, so the two
    /// surfaces cannot end up disagreeing about which stance the room is in.
    private enum HeaderAction {
        /// It is the user's slot and he stopped his own clock on it.
        case ownCard
    }

    private var headerAction: HeaderAction? {
        guard coordinator.userTeamID != nil,
              coordinator.mode != .loading,
              coordinator.mode != .preDraft,
              coordinator.mode != .complete else { return nil }
        if coordinator.isUserOnClock {
            // `.paused`, NOT `isUserOnClock` — the same distinction
            // `DraftControlBar.stance` draws (DraftControlBar:122-127), and for
            // the same reason: the verb behind this case is `resume()`, which
            // returns immediately unless the clock is actually frozen. Offering
            // it on a *running* own clock printed a gold, enabled "Make the
            // pick" that could not do anything, for the whole turn, on the one
            // screen where a dead primary costs the user a card. The running
            // clock's commit lives on the board (#197); the header stays quiet
            // rather than duplicating it with something that does not fire.
            return coordinator.mode == .paused ? .ownCard : nil
        }
        // **AN AI CLUB IS AT THE PODIUM: THE HEADER OFFERS NOTHING** (#194 v2,
        // round 2, spec 5).
        //
        // This branch used to mint a ghost `Call about #N` — the *same verb,
        // same handler, same wording* as the control bar's gold CTA, rendered
        // 900 pt above it on a landscape iPad. Round 1's screenshot therefore
        // carried two "Call about #2" buttons at once, and the one moment the
        // spec reserves for the centre column's reveal card was the one moment
        // the header had a button on it.
        //
        // Demoting the copy would only have made a quieter duplicate. One verb,
        // one place: the bar's gold `Call about #N`, which is where every other
        // commit and transport control on this screen already lives. The header
        // goes back to being chrome during an AI clock, which is exactly what
        // "one star per moment" asks of it.
        return nil
    }

    /// Whether the header's own-card CTA may take the screen's gold fill.
    ///
    /// It may not while a rival GM is on the phone. `DraftControlBar` swaps to
    /// its `.decision` stance for any pending offer at all (#197), including on
    /// a paused own clock — the one state this CTA renders in — and that stance
    /// lights a gold `Accept trade`. Two gold fills is the one thing P5
    /// forbids outright, and the offer is the more perishable of the two: it can
    /// be withdrawn, while the card cannot be handed to anybody else.
    private var ownCardIsGold: Bool {
        coordinator.pendingTradeOffer == nil
    }

    @ViewBuilder
    private var headerActionButton: some View {
        if let action = headerAction {
            actionButton(for: action)
        }
    }

    @ViewBuilder
    private func actionButton(for action: HeaderAction) -> some View {
        switch action {
        case .ownCard:
            // Reached only while `mode == .paused` on the user's own slot (see
            // `headerAction`), which is exactly the state `resume()` serves:
            // the clock is frozen at the second it stopped on and the only other
            // way back to it is a transport button labelled "Resume" at the far
            // bottom of a landscape iPad. Un-freezing restores `.userPick` and
            // the board's commit with it.
            Button {
                coordinator.resume()
            } label: {
                Label("Make the pick", systemImage: "checkmark.seal.fill")
                    .lineLimit(1)
            }
            .buttonStyle(DSEitherButtonStyle(isPrimary: ownCardIsGold))
            .accessibilityLabel("Make the pick")
            .accessibilityHint("Restarts your clock at \(coordinator.clockSeconds) seconds so you can hand in a card")
        }
    }

    // MARK: - Your own cards

    /// The quiet distance marker: four and five cards out, where the news is
    /// worth stating but not worth shouting. Three and under is `Focus`'s
    /// escalation, which is a different, louder thing entirely.
    private var approachPill: Int? {
        let away = coordinator.picksUntilUserPick
        guard away == 4 || away == 5 else { return nil }
        return away
    }

    /// The supporting line, and — from five cards out — a pill in front of it.
    ///
    /// #194 (c): the approach toward your own turn was one 14 pt grey sentence
    /// that turned orange at three. That is the same visual weight as a table
    /// row, for one of the three beats that should carry the night. The distance
    /// is a `DSStatusPill` now, at the thresholds stated here, and the sentence
    /// behind it went back to being what it always was — a fact, not a warning,
    /// so it no longer changes colour and the pill is the only thing that moves.
    ///
    /// Orange, never gold: at 11 pt `accentGold` and `warning` are the same hue,
    /// and a gold pill one row under the gold clock reads as a second clock (the
    /// exact defect P7 records).
    private var userNextPickInfo: some View {
        // `picksUntilUserPick` returns -1 and `nextUserPickNumber` returns nil
        // once his card count is spent, which the old format string printed
        // literally: "Your next pick: #0 (-1 picks away)" after the last pick of
        // the draft (task #153d). No turns left is its own sentence.
        let picksAway = coordinator.picksUntilUserPick
        let line: String = {
            guard let next = nextUserPickNumber(), picksAway >= 0 else {
                return "No picks remaining"
            }
            if picksAway == 0 {
                return "Your card \u{2014} #\(next) \u{00B7} \(coordinator.userPicksRemaining) remaining"
            }
            return "Your next pick #\(next) \u{00B7} \(coordinator.userPicksRemaining) remaining"
        }()
        return HStack(spacing: DSSpacing.xs) {
            // The escalation used to render here and now rides the top row (see
            // `body`); four and five cards out is still this line's business,
            // because a distance marker IS a footnote and the escalation is not.
            if let approachPill {
                DSStatusPill(
                    label: "IN \(approachPill)",
                    tone: .neutral,
                    showsDot: false,
                    spokenLabel: "Your pick is \(approachPill) cards away"
                )
            }
            // `textPrimary`, not `textSecondary`, and that is what buys the
            // stronger club wash — twice over now. This is the only small ink the
            // header prints directly onto the washed surface; under v3's per-club
            // alphas `textSecondary` bottoms out at 3.7 : 1, well under AA, while
            // `textPrimary` holds ≥ 8.78 : 1 across the whole league. Raising the
            // ink one tier costs a hair of hierarchy and buys the header its
            // colour back; see `DraftTeamTint.headerWashOpacity`.
            Text(line)
                .font(DSType.text(DSType.Size.body, .semibold))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
        }
    }

    /// **The escalation state** (#194 v2, spec 5): three cards out, the header
    /// stops being chrome and becomes the loudest thing in the room.
    ///
    /// v1 rendered this beat as an 11 pt pill — the same visual weight as a
    /// table row for the moment the user has about ninety seconds to decide what
    /// he wants. It is `title2` now, which is the largest type the header can
    /// carry in any state except a running own clock, so the ORDER of the three
    /// beats is legible from the type scale alone.
    ///
    /// Orange, never gold, and stated three ways: the word, the leading rule and
    /// the dot. At 22 pt black this is WCAG "large text" (≥ 18.66 pt bold), so
    /// the floor is 3 : 1. Re-measured against the club washes as they stand
    /// after #194 v3 (per-club alphas, worst-case backdrop pixel), `alertOrange`
    /// runs **3.43 : 1 (CAR, the strongest wash in the league) to 5.1 : 1 (TB)**
    /// — clear of the large-text floor everywhere, and clear of the small-text
    /// floor for most of the league. It is the pairing that sets
    /// `DraftTeamTint.headerWashCeiling`; if this call ever drops below 22 pt
    /// black, that ceiling has to come down with it.
    private func escalationCall(picksAway: Int) -> some View {
        // **THE RULE IS A BACKGROUND, NOT A ROW MEMBER** (#206).
        //
        // It used to be an `HStack` sibling — `Rectangle().frame(width: 3)`
        // carrying `.frame(maxHeight: .infinity)` so it would run the height of
        // the words beside it. That is not what `maxHeight: .infinity` means. It
        // means "I accept any height you offer", which made the rule flexible,
        // which made this `HStack` flexible, which made the header's top row
        // flexible, which made the WHOLE HEADER a flexible child of
        // `DraftDayView`'s outer `VStack` — competing on equal terms with the
        // table's `.frame(maxHeight: .infinity)`. A `VStack` splits its
        // remaining height between equally flexible children, so the header took
        // HALF THE SCREEN, and because its rows are centre-aligned the club
        // plate, this call and the clock floated in the middle of a void with
        // the pick band shoved to the foot of it. That is the user's landscape
        // screenshot exactly, and the reason it only ever appeared here is that
        // this view only exists while `focus == .escalating` — three cards out,
        // the one moment the room is supposed to be at its tightest.
        //
        // As a `background` the rule is *proposed the content's size*, so it
        // still spans the full height of the words and contributes nothing to
        // the layout. The header goes back to being sized by what is in it, and
        // the table gets the rest. The leading pad is the rule's 3 pt plus the
        // same `xs` gap the row already used, so the mark is pixel-identical.
        HStack(spacing: DSSpacing.xs) {
            EscalationDot()
            Text(picksAway == 1 ? "YOU ARE UP NEXT" : "YOUR PICK IN \(picksAway)")
                .font(DSType.display(DSType.Size.title2, .black))
                .tracking(0.8)
                .foregroundStyle(Color.alertOrange)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.leading, DSSpacing.xs + 3)
        .background(alignment: .leading) {
            Rectangle()
                .fill(Color.alertOrange)
                .frame(width: 3)
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            picksAway == 1 ? "You are up next" : "Your pick is \(picksAway) cards away"
        )
    }

    private func nextUserPickNumber() -> Int? {
        guard let teamID = coordinator.userTeamID else { return nil }
        return coordinator.picks
            .dropFirst(coordinator.currentPickIndex)
            .first(where: { $0.currentTeamID == teamID })?.pickNumber
    }

    // MARK: - The clock's denominator

    /// What a full clock is worth in the stance the room is in.
    ///
    /// `DraftDayCoordinator.beginCurrentPick` opens the user's own slot at 120 s
    /// and everybody else's at 60 s; those two constants are the drain bar's
    /// denominator. The `max` is the seatbelt — if the engine ever hands out a
    /// longer clock the bar clamps to full instead of overrunning its track.
    private var clockCapacity: Int {
        max(coordinator.clockSeconds, coordinator.isUserOnClock ? 120 : 60)
    }

    // MARK: - The round rollover (#198 (2))

    /// How long the plate stays up. Long enough to read two lines, short enough
    /// that the ribbon it is standing on is back before the next card lands —
    /// an AI clock is 60 s at 1× and the room skips through it faster than that,
    /// so this is deliberately under the shortest gap between two picks the
    /// room can produce.
    private static let rolloverDwell: Double = 1.9

    /// The plate itself: what just finished, and what is now on the clock.
    ///
    /// **No gold.** The band's current-slat rule and the clock badge are the
    /// two gold marks the header is allowed (P5), and a third one on a plate
    /// that covers the first would read as the clock having moved. The eyebrow
    /// takes `accentBlue`, which is this room's information hue everywhere else
    /// (`DraftBroadcastRail`'s trade and target beats).
    private func roundRolloverPlate(_ round: Int) -> some View {
        HStack(spacing: DSSpacing.sm) {
            Image(systemName: "flag.checkered")
                .font(DSType.display(DSType.Size.title3, .black))
                .foregroundStyle(Color.accentBlue)
            VStack(alignment: .leading, spacing: 1) {
                Text("ROUND \(max(1, round - 1)) IS IN THE BOOKS")
                    .font(DSType.display(DSType.Size.caption, .heavy))
                    .tracking(1.0)
                    .foregroundStyle(Color.accentBlue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("ROUND \(round) ON THE CLOCK")
                    .font(DSType.display(DSType.Size.title3, .black))
                    .tracking(1.4)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DSSpacing.sm)
        .padding(.vertical, DSSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.card, style: .continuous)
                .fill(Color.backgroundPlate.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: DSCornerRadius.card, style: .continuous)
                        .strokeBorder(Color.accentBlue.opacity(0.45), lineWidth: 1)
                )
        )
        // The plate slides in over the ribbon from the leading edge and fades
        // out where it stands: an entrance says "this is new", and an exit that
        // travels would pull the eye off the board the room is handing back.
        .transition(
            .asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .opacity
            )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Round \(max(1, round - 1)) complete. Round \(round) is on the clock.")
    }

    /// The band's round changed. A rollover is a round going UP — the cursor
    /// also moves backwards when the room is rewound to a completed draft, and
    /// that is not a beat.
    private func roundDidChange(from old: Int?, to new: Int?) {
        guard let new, let old, new > old else { return }
        armedRolloverRound = new
        presentArmedRollover()
    }

    /// Shows an armed plate, if the room is actually visible to show it in.
    ///
    /// Called from the round change itself and from the recap sheet clearing,
    /// so a rollover that happened under a sheet is not lost — it is simply
    /// late, which is the honest reading of "the ribbon rolled over while you
    /// were looking at the recap".
    private func presentArmedRollover() {
        guard let round = armedRolloverRound,
              coordinator.pendingRoundRecap == nil else { return }
        armedRolloverRound = nil
        setRolloverPlate(round)
        rolloverToken &+= 1
        let mine = rolloverToken
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(Self.rolloverDwell * 1_000_000_000))
            guard mine == rolloverToken else { return }
            setRolloverPlate(nil)
        }
    }

    /// One animation, honoured or skipped in one place. Reduce Motion gets the
    /// plate and the dwell with no travel and no cross-fade — the words, the
    /// hue and the dimmed ribbon carry the beat without them.
    private func setRolloverPlate(_ round: Int?) {
        guard !reduceMotion else {
            rolloverRound = round
            return
        }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            rolloverRound = round
        }
    }

    // MARK: - Needs

    /// Five positions, **in order of need**, as `DSStatusPill`s at stated
    /// thresholds (P7 rule 2).
    ///
    /// They used to be gold chips at five different opacities — a continuous
    /// colour ramp with no legend, on the one hue that already has three jobs,
    /// encoding a 0–1 score nobody could read off it. The severity now has two
    /// channels that both survive a screenshot: the left-to-right ORDER, and
    /// three tones at thresholds written down here.
    private var teamNeedsStrip: some View {
        let needs = coordinator.teamNeedScores
            .sorted { $0.value > $1.value }
            .prefix(5)
        let pressure = showsBoardPressure ? boardPressure : [:]
        return HStack(spacing: DSSpacing.xxs) {
            Text(showsBoardPressure ? "NEEDS \u{00B7} MY TOP \(Self.pressureDepth)" : "NEEDS")
                .font(DSType.display(DSType.Size.caption, .heavy))
                .tracking(0.7)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
                .padding(.trailing, DSSpacing.xxs)
            ForEach(Array(needs), id: \.key) { entry in
                let left = pressure[entry.key]
                DSStatusPill(
                    label: entry.key.rawValue,
                    tone: tone(for: entry.value),
                    value: showsBoardPressure ? "\(left ?? 0)" : nil,
                    showsDot: false,
                    spokenLabel: spokenPill(
                        position: entry.key.rawValue,
                        score: entry.value,
                        left: showsBoardPressure ? (left ?? 0) : nil
                    )
                )
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - Board pressure (#198 (4))

    /// **How deep "the top of my board" is.** Twenty is the read that decides
    /// trade-up versus sit: inside twenty slots a man is somebody the user's own
    /// building filed a real opinion on, and past it the arithmetic of moving up
    /// stops paying for itself.
    private static let pressureDepth = 20

    /// **Per position of need, how many men are LEFT inside the top
    /// ``pressureDepth`` of the user's own board** (#198 (4)).
    ///
    /// This is the one number the needs strip was missing and the only number on
    /// this screen that answers "do I move up or do I sit": three tackles inside
    /// his top twenty means the run can come to him, one means the phone is the
    /// only way to get him, and zero means the need is not solvable tonight at
    /// any price and the strip is telling him to stop planning around it.
    ///
    /// ## Fog discipline
    ///
    /// `userBoardRanks` is the user's OWN board — `UserDraftBoard.slotMap`, the
    /// order he left it in, over the declared class — and it is the identical
    /// map the Big Board prints `MY #N` from. It is an annotation, not an
    /// evaluation: the fog never covered it, and nothing here reads
    /// `trueOverall`, `scoutedOverall` or any other rating. A man the user never
    /// scouted has no slot at all and is therefore counted by nobody, which is
    /// the correct answer — the board cannot be under pressure over a name it
    /// has never heard.
    private var boardPressure: [Position: Int] {
        var counts: [Position: Int] = [:]
        for prospect in coordinator.availableProspects {
            guard let rank = coordinator.userBoardRanks[prospect.id],
                  rank <= Self.pressureDepth else { continue }
            counts[prospect.position, default: 0] += 1
        }
        return counts
    }

    /// **A top twenty needs twenty men in it.**
    ///
    /// `UserDraftBoard.order` ranks the men the user's building has actually
    /// filed on — his stored board order plus every scouted man behind it — so a
    /// club that scouted nobody has an EMPTY board, and a pressure column of
    /// five zeroes on that save would read as "no help at any position", which
    /// is the opposite of the truth (the class is untouched; he simply has no
    /// opinion about it). Below the threshold the strip prints the needs alone,
    /// exactly as it did before this pass.
    private var showsBoardPressure: Bool {
        coordinator.userBoardRanks.count >= Self.pressureDepth
    }

    private func spokenPill(position: String, score: Double, left: Int?) -> String {
        let need = "\(position), \(spokenNeed(score)) need"
        guard let left else { return need }
        switch left {
        case 0:  return need + ", none left in your top \(Self.pressureDepth)"
        case 1:  return need + ", 1 man left in your top \(Self.pressureDepth)"
        default: return need + ", \(left) men left in your top \(Self.pressureDepth)"
        }
    }

    /// The thresholds, stated once. `teamNeedScores` runs roughly 0.2…1.0.
    private func tone(for score: Double) -> DSStatusPill.Tone {
        if score >= 0.75 { return .bad }
        if score >= 0.50 { return .warn }
        return .neutral
    }

    private func spokenNeed(_ score: Double) -> String {
        if score >= 0.75 { return "urgent" }
        if score >= 0.50 { return "clear" }
        return "minor"
    }
}

// MARK: - EscalationDot — the approach, as motion
//
// The one moving mark on the header that is not the clock. It exists because
// the escalation has to survive peripheral vision: the user is reading the
// board, not the chrome, when his card comes within three.
//
// The breath starts on appear and the view is torn down when the state ends, so
// there is no "stuck mid-breath" case to cancel — the `repeatForever` dies with
// its host. Reduce Motion gets a solid dot; the word, the rule and the colour
// carry the state without it.

private struct EscalationDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    var body: some View {
        Circle()
            .fill(Color.alertOrange)
            .frame(width: 8, height: 8)  // ds-lint:allow(spacing) state dot: sized to the 22 pt cap height beside it
            .opacity(breathing ? 0.35 : 1.0)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    breathing = true
                }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - DSEitherButtonStyle — one button, two dressings, one identity
//
// `.buttonStyle(gold ? .dsPrimary : .dsSecondary)` does not type-check (two
// different concrete `ButtonStyle`s), and branching the *view* instead —
// `if gold { Button(…) } else { Button(…) }` — hands SwiftUI two different view
// identities, so the CTA is torn down and rebuilt every time a trade offer
// arrives or clears, taking its press state and any in-flight animation with it.
// One button, one style, a boolean inside.

private struct DSEitherButtonStyle: ButtonStyle {
    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        Group {
            if isPrimary {
                DSPrimaryButtonStyle().makeBody(configuration: configuration)
            } else {
                DSSecondaryButtonStyle().makeBody(configuration: configuration)
            }
        }
    }
}

// MARK: - DraftClockBadge — gold's named job, given a pulse (#194 D (b))
//
// The vision hands gold three jobs and names this one by hand: "the live/now
// indicator (**the draft clock**, an open FA wave)". It was a `timer` glyph and
// a number, and that number was the only thing in the whole room that ever
// moved. Four changes, one per complaint from the #194 pass:
//
//   monospaced digits ... `DSType.display` is already `.monospacedDigit()`, but
//                         the badge printed "120s" → "99s" → "9s" and SHED A
//                         GLYPH at each step, so the trailing edge of the header
//                         jumped twice a minute however tabular the figures
//                         were. `m:ss` is fixed-width for the whole countdown
//                         and reads as a clock rather than a counter.
//   the drain bar ....... the countdown had no *shape*: 60 and 12 looked alike
//                         at a glance. A 96 pt track under the numerals empties
//                         in real time, and its slide is the coordinator's own
//                         tick interval (1 s ÷ speed), so at 4× the bar drains
//                         at 4× instead of lagging a second behind the digits.
//   the 30 s turn ....... colour AND motion. `dangerText` (6.03 : 1 on this
//                         plate, where raw `danger` is 3.4 : 1 and unreadable as
//                         words) plus a slow scale pulse anchored to the
//                         trailing edge so the numerals breathe without swimming
//                         sideways.
//   the 10 s haptic ..... one impact per second through the last ten, heavier
//                         through the last five, and **only on the user's own
//                         clock**. Buzzing the device through the last ten
//                         seconds of ~250 AI clocks would be a vibrating iPad
//                         for most of an hour; buzzing it while HIS card is
//                         unfiled is the entire point. Since #197 nothing covers
//                         the header while that runs — the pick is handed in on
//                         the board — so the taps land next to a visible clock.
//
// #195's paused state is preserved and extended: a frozen clock now means
// something (resume picks up at the second it stopped on), so it must not look
// like a running one. Paused drops the gold, swaps the glyph, stops the pulse,
// mutes the bar, and says so in the accessibility label.
//
// Reduce Motion turns off the pulse and the bar's animation. The digits, the
// bar's length and the colour carry the state on their own.

private struct DraftClockBadge: View {
    let seconds: Int
    let capacity: Int
    let speed: Double
    let isPaused: Bool
    let isUserOnClock: Bool
    let isRunning: Bool
    /// **Whether the clock is the screen's one star right now** (#194 v2,
    /// spec 5).
    ///
    /// It is, on the user's own card, and it is not while an AI club is at the
    /// podium — that beat belongs to the centre column's reveal, and a 28 pt
    /// gold countdown in the corner competes with it for the same glance. The
    /// digits drop a step rather than the badge disappearing: gold's named job
    /// here is "the live/now indicator", and a live indicator that switches off
    /// for 250 of the night's 257 picks is not one.
    var isHero: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsed = false

    private var urgent: Bool { !isPaused && seconds <= 30 }

    private var tint: Color {
        if isPaused { return Color.textSecondary }
        return urgent ? Color.dangerText : Color.accentGold
    }

    /// How much of the track is still full, 0…1.
    private var remaining: Double {
        guard capacity > 0 else { return 0 }
        return min(1, max(0, Double(seconds) / Double(capacity)))
    }

    /// The coordinator sleeps `1 s ÷ speed` between ticks, so the bar's slide
    /// has to take exactly that long or it is still moving when the next digit
    /// lands.
    private var tickDuration: Double { 1.0 / max(0.25, speed) }

    /// `m:ss`, so the badge is the same width at 2:00 and at 0:09.
    private var clockText: String {
        let clamped = max(0, seconds)
        return "\(clamped / 60):\(String(format: "%02d", clamped % 60))"
    }

    /// The pulse runs only while the clock is actually counting down toward a
    /// deadline: not paused, not stopped, and not on a device asking for less
    /// motion.
    private var pulses: Bool { urgent && isRunning && !reduceMotion }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: DSSpacing.xxs) {
                Image(systemName: isPaused ? "pause.fill" : "timer")
                    .font(DSType.display(isHero ? DSType.Size.title3 : DSType.Size.footnote, .heavy))
                Text(clockText)
                    .font(DSType.display(isHero ? DSType.Size.title1 : DSType.Size.title3, .black))
            }
            .foregroundStyle(tint)

            drainBar
        }
        .scaleEffect(pulsed ? 1.05 : 1.0, anchor: .trailing)
        // Both directions are driven explicitly, which is the fix for the defect
        // `DraftControlBar.OnDeckPulse` solves with `.id`: a `repeatForever`
        // animation started once and never cancelled leaves the badge stuck
        // mid-breath when urgency ends, because the value it animates never
        // changes again. `.id` cannot do that job here — it would sit inside
        // this view's own `body` and so would reset the identity of the subtree
        // rather than of the view that owns `pulsed`.
        .onAppear { setPulse(pulses) }
        .onChange(of: pulses) { _, active in setPulse(active) }
        .onChange(of: seconds) { _, newValue in
            fireHapticIfNeeded(at: newValue)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    /// Starts or stops the breath. Stopping is an explicit animation to 1.0 so
    /// the repeating one is replaced rather than left running under a value that
    /// no longer changes.
    private func setPulse(_ active: Bool) {
        if active {
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                pulsed = true
            }
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                pulsed = false
            }
        }
    }

    private var drainBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.backgroundTertiary)
                Capsule()
                    .fill(tint.opacity(isPaused ? 0.45 : 1))
                    .frame(width: geo.size.width * remaining)
            }
        }
        .frame(width: 96, height: 4)
        .animation(reduceMotion ? nil : .linear(duration: tickDuration), value: remaining)
        .accessibilityHidden(true)
    }

    private var spoken: String {
        let count = seconds == 1 ? "1 second" : "\(seconds) seconds"
        if isPaused { return "Clock paused, \(count) left" }
        return isUserOnClock ? "Your clock, \(count) left" : "\(count) on the clock"
    }

    /// One impact per second through the last ten, heavier through the last
    /// five. Gated on the user's own running clock — see the type comment.
    ///
    /// The generator is built per tap rather than kept alive: a `@State`
    /// generator would have to be prepared and re-prepared around every pause,
    /// and once a second is far too slow a cadence for the allocation to matter.
    private func fireHapticIfNeeded(at value: Int) {
        guard isUserOnClock, isRunning, !isPaused, value > 0, value <= 10 else { return }
        let style: UIImpactFeedbackGenerator.FeedbackStyle = value <= 5 ? .heavy : .light
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}
