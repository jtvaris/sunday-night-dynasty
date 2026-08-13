import SwiftUI

// MARK: - DraftPickBand — `DSSlatBand` at draft-night scale (#105 Wave 3b)
//
// UI_REDESIGN_VISION §2.1 names six scales for one component; this is the
// fourth of them ("draft picks (`DraftDayCoordinator`)"). §3 family 8 is the
// verdict it answers: the war room is *architecturally* the best flow in the
// app — a real `Mode` state machine with a genuine bottom control bar — and it
// rendered its position in that flow as a text line reading
// `"ROUND 2 — Pick 14 / 32 · Overall 46"`. A pick order is the most literally
// ordered thing in the game and it was the one flow with no band.
//
// **Past picks keep the name that went.** That is the whole reason the band
// beats the sentence it replaces: §2.1's `done` slat carries "the outcome", and
// on this scale the outcome is the man. Three cards back you can still read
// `#43 CHI · WR BLYTHE` without opening the ticker, so the ribbon is a live
// record of the run you are picking inside of, not a counter.
//
// ## What each channel carries here
//
//   index      the overall slot — "#46". The one numeral on the slat.
//   title      the club on that card, as its abbreviation (display voice).
//   done       outcome = `POS LASTNAME`, the name that went.
//   current    sub-caption = the club's full name, or "You are on the clock".
//              Gold top rule + the NOW pill: this is where the room is standing.
//   future     label only, per spec. The user's OWN upcoming slots set
//              `isAvailable`, which is exactly what that flag is for ("a future
//              slat the club may already act in") and raises their ink one tier
//              — so "which of these are mine" survives at peripheral distance
//              without a colour of its own.
//
// `locked` is unused: no slot in a draft order is shut, they are merely ahead.
//
// ## Why the slats are inert
//
// `onSelect` is `nil`, so `DSSlatButton` disables itself. §2.12 wants the
// signature element to be the most obviously interactive thing on a screen, but
// that presumes the band has destinations — draft prep's slats each open a room.
// A pick order has none: the user cannot jump to pick 40, and the two moves he
// *can* make ("skip to my pick", "skip to the next round") are transport and
// live on the bottom rail where every other transport control already is. A slat
// that looks pressable and does nothing is worse than one that does not.
//
// ## Why the window, and why nine
//
// A draft is ~257 slots and `DSSlatBand` lays its ribbon out in a plain `HStack`
// inside a `ScrollView` — every slat is realised. So the band draws a sliding
// window: three cards behind the clock, the card on it, five ahead. Nine slats
// is what fits the 1376 pt landscape iPad the app is built for without the
// ribbon scrolling: one current slat at `currentFlex` 2.5 plus eight at 1.0 is
// 10.5 units, and 10.5 × `minSlatWidth` (112) is 1176 pt of slat. Below that the
// band scrolls rather than breaking a word, which is `DSSlatGeometry`'s own
// documented contract.
//
// ## Why it is `Equatable`
//
// `clockSeconds` republishes once a second, so every view observing the
// coordinator re-evaluates its body once a second — including this one, whose
// body mounts a `GeometryReader` + `ScrollViewReader` + nine parallelograms.
// The band's inputs change only when a card is handed in, so the model is a
// value, the view is `Equatable` over it, and the header mounts it through
// `.equatable()`. Between picks the ribbon is not re-laid-out at all.

struct DraftPickBand: View, Equatable {

    /// Everything the band draws, computed once off the coordinator.
    ///
    /// A value type on purpose: `DSSlat` and `DSResourceMeter` are both
    /// `Equatable`, so the whole model is, which is what makes the
    /// `.equatable()` gate above actually gate anything.
    struct Model: Equatable {
        var slats: [DSSlat]
        var headline: String
        var meter: DSResourceMeter?
    }

    let model: Model

    static func == (lhs: DraftPickBand, rhs: DraftPickBand) -> Bool {
        lhs.model == rhs.model
    }

    var body: some View {
        DSSlatBand(
            slats: model.slats,
            headline: model.headline,
            meter: model.meter
        )
    }
}

// MARK: - Building the model

extension DraftPickBand.Model {

    /// Cards drawn behind the clock. Enough to read the run that produced the
    /// board you are looking at; not so many that the ribbon scrolls.
    private static let cardsBehind = 3
    /// Cards drawn ahead of the clock.
    private static let cardsAhead = 5

    @MainActor
    init(coordinator: DraftDayCoordinator) {
        let picks = coordinator.picks
        let cursor = coordinator.currentPickIndex
        let userTeamID = coordinator.userTeamID

        guard !picks.isEmpty else {
            self.init(slats: [], headline: "Draft order pending", meter: nil)
            return
        }

        let isComplete = cursor >= picks.count
        let span = Self.cardsBehind + Self.cardsAhead + 1
        let range: Range<Int> = isComplete
            ? max(0, picks.count - span)..<picks.count
            : max(0, cursor - Self.cardsBehind)..<min(picks.count, cursor + Self.cardsAhead + 1)

        let slats: [DSSlat] = range.map { index in
            Self.slat(
                for: picks[index],
                state: index < cursor ? .done : (index == cursor ? .current : .future),
                userTeamID: userTeamID,
                teamsByID: coordinator.teamsByID
            )
        }

        self.init(
            slats: slats,
            headline: Self.headlineText(picks: picks, cursor: cursor),
            meter: Self.capitalMeter(picks: picks, cursor: cursor, userTeamID: userTeamID)
        )
    }

    // MARK: One slat

    private static func slat(
        for pick: DraftPick,
        state: DSSlat.State,
        userTeamID: UUID?,
        teamsByID: [UUID: Team]
    ) -> DSSlat {
        let team = teamsByID[pick.currentTeamID]
        let abbrev = team?.abbreviation ?? pick.teamAbbreviation ?? "TBD"
        let isUsers = userTeamID != nil && pick.currentTeamID == userTeamID
        let outcome = state == .done ? selectionLabel(for: pick) : nil

        var subcaption: String?
        if state == .current {
            subcaption = isUsers ? "You are on the clock" : (team?.fullName ?? abbrev)
        }

        return DSSlat(
            id: "pick-\(pick.pickNumber)",
            index: "#\(pick.pickNumber)",
            title: abbrev,
            subcaption: subcaption,
            state: state,
            // Exactly what the flag is documented for: a future slat the club
            // may already act in. Never a fifth state, never a colour.
            isAvailable: state == .future && isUsers,
            outcome: outcome,
            // The club that made the pick, in its own colours (#194 A).
            //
            // `DSSlat.tint` is documented as "optional tint for a `done` slat's
            // top rule", and the renderer reads it in exactly two places — the
            // 2 pt rule and the check glyph that replaces the numeral — so this
            // is the band's existing channel, used for the thing it was built
            // for, on the one screen where a finished step *belongs to somebody*.
            // Set only on `done` on purpose: the current slat's rule is gold and
            // stays gold, so a club colour can never be mistaken for "the room
            // is standing here".
            tint: state == .done ? DraftTeamTint.accentIfKnown(for: abbrev) : nil,
            isLive: state == .current,
            accessibilityText: accessibilityText(
                pick: pick,
                state: state,
                abbrev: abbrev,
                team: team,
                isUsers: isUsers
            ),
            // THE CELL ON THE CLOCK WEARS THE CLUB (#194 v2).
            //
            // `tint` above covers the cards already handed in; this covers the
            // two states it deliberately does not touch. `DSSlat.accent` draws
            // it on channels no state owns — a bottom rule on both, plus a wash
            // across the empty trailing half of the widened `current` slat — so
            // the ribbon reads as thirty-two clubs taking turns rather than as
            // nine identical navy parallelograms.
            //
            // The gold budget is untouched: the current slat's 3 pt top rule and
            // its NOW pill are still the only gold in the band, which is what
            // keeps "the room is standing HERE" separable from "and this is who
            // is standing there".
            accent: state == .done ? nil : DraftTeamTint.accentIfKnown(for: abbrev)
        )
    }

    /// The name that went, sized for an 11 pt second line inside a ~120 pt slat.
    ///
    /// `POS LASTNAME` rather than the full name: the slat's outcome row is
    /// `lineLimit(1)`, and "Malik Reed" already truncates at the width nine
    /// slats leave. The whole name stays in the accessibility sentence, and the
    /// ticker beside the band prints it in full.
    private static func selectionLabel(for pick: DraftPick) -> String {
        guard let name = pick.playerName, !name.isEmpty else { return "\u{2014}" }
        let surname = name.split(separator: " ").last.map(String.init) ?? name
        guard let position = pick.playerPosition, !position.isEmpty else {
            return surname.uppercased()
        }
        return "\(position) \(surname)".uppercased()
    }

    private static func accessibilityText(
        pick: DraftPick,
        state: DSSlat.State,
        abbrev: String,
        team: Team?,
        isUsers: Bool
    ) -> String {
        let club = team?.fullName ?? abbrev
        switch state {
        case .done:
            let name = pick.playerName ?? "no selection recorded"
            let position = pick.playerPosition.map { "\($0) " } ?? ""
            return "Pick \(pick.pickNumber), \(club) selected \(position)\(name)"
        case .current:
            return isUsers
                ? "Pick \(pick.pickNumber), you are on the clock"
                : "Pick \(pick.pickNumber), \(club) on the clock"
        default:
            return isUsers
                ? "Pick \(pick.pickNumber), your pick"
                : "Pick \(pick.pickNumber), \(club)"
        }
    }

    // MARK: The head

    /// **The one place the draft prints its count** (P1 / §2.1).
    ///
    /// `DraftStickyHeader` used to carry this as prose above the room, on the
    /// same row as the clock; the band head is where it lives now, and the
    /// header no longer states it at all.
    private static func headlineText(picks: [DraftPick], cursor: Int) -> String {
        guard cursor < picks.count else {
            return "Draft complete \u{00B7} \(picks.count) picks"
        }
        let pick = picks[cursor]
        let slot = roundSlot(picks: picks, pick: pick)
        return "Round \(pick.round) \u{00B7} pick \(slot.index) of \(slot.total) \u{00B7} overall #\(pick.pickNumber)"
    }

    /// Where the card on the clock sits INSIDE its round, and how many cards
    /// that round actually holds.
    ///
    /// Counted off the real order rather than a hardcoded 32 — a round carrying
    /// compensatory selections overruns the literal and the header used to read
    /// "ROUND 4 — Pick 34 / 32" (task #153c). This is that fix, moved with the
    /// counter it belongs to.
    private static func roundSlot(picks: [DraftPick], pick: DraftPick) -> (index: Int, total: Int) {
        let inRound = picks.filter { $0.round == pick.round }
        let index = inRound.firstIndex { $0.id == pick.id }.map { $0 + 1 } ?? 1
        return (index, max(index, inRound.count))
    }

    /// The band head's meter: **the user's own draft capital**, on the one
    /// meaning the meter has everywhere — a filled pip is a spent pip.
    ///
    /// Not "picks made in this round" and not "rounds elapsed": the resource the
    /// user is actually spending tonight is his stack of cards, and the value
    /// line reads `3 spent · 4 left` against it. A club with no picks left in
    /// the draft gets no meter rather than an empty rail.
    private static func capitalMeter(
        picks: [DraftPick],
        cursor: Int,
        userTeamID: UUID?
    ) -> DSResourceMeter? {
        guard let userTeamID else { return nil }
        let mine = picks.filter { $0.currentTeamID == userTeamID }
        guard !mine.isEmpty else { return nil }
        let spent = picks.prefix(cursor).filter { $0.currentTeamID == userTeamID }.count
        return DSResourceMeter(spent: spent, total: mine.count, unit: "draft picks")
    }
}
