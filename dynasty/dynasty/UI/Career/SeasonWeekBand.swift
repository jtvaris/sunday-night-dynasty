import SwiftUI

// MARK: - SeasonWeekBand — the season on the shared spine, as a WEEK ladder
//
// UI_REDESIGN_VISION §1 P1, second iteration-2 amendment, quoted because the
// shape of this file is entirely dictated by it:
//
// > The regular season is **not a stage**. It never renders as a "Regular
// > Season" node inside a phase stepper — the season band is a **week ladder**:
// > one slat per week, results carried as a coloured top rule on played weeks,
// > the current week expanded in place with opponent, window and stakes, and
// > the playoff tail as a single locked slat. History compresses (a played week
// > can shrink to its number and its W/L), the near future expands. What the
// > player lives in is the week, so the week is the unit the UI shows.
//
// §2.1 names "season weeks (the ladder, P1)" as the first of `DSSlatBand`'s six
// scales, and `DSSlat.tint` was added for this consumer specifically — its doc
// comment already says "W green / L red at season scale". This is the binding
// that was missing.
//
// ## Why there is no phase stepper here
//
// The eighteen weeks of a season are ONE `SeasonPhase` (`.regularSeason`, plus
// `.tradeDeadline`, which is a regular-season week wearing a phase's name). A
// stepper over `SeasonPhase` therefore spends five months of play parked on a
// single node saying "Regular Season" — it cannot tell Week 2 from Week 15,
// which is the only distinction the player cares about. The ladder is one slat
// per week for exactly that reason, and the phases the season does contain
// (`.playoffs`) arrive as the tail slat rather than as peers of the weeks.
//
// ## Where it is mounted, and why it is not everywhere
//
// `CareerShellView` owns it — it is shell chrome, drawn under the persistent top
// bar — but it renders only at the hub, i.e. while the shell's navigation path
// is empty. P1's amendment says a screen with no order gets no band, and the
// roster, the cap sheet and the staff room are sets and objects, not positions
// in the season. Pinning the ladder over them would make it decoration, which
// is the thing the amendment exists to forbid.
//
// ## The band is not interactive
//
// `onSelect` is nil, so every slat is a disabled button and reads as one. A week
// is not a destination: the calendar sheet and the schedule screen are, and
// they are one tap away in the top bar. A slat that looked tappable and refused
// would be worse than one that plainly does not.

enum SeasonWeekBand {

    /// The regular season's length. `WeekAdvancer` flips to `.playoffs` once
    /// `currentWeek > 18`, so this is that boundary and not a second opinion
    /// about it.
    static let regularSeasonWeeks = 18

    /// One week of the user's schedule, reduced to what the ladder draws.
    ///
    /// Assembled by the shell from rows it has already fetched — the band never
    /// touches the store, so it cannot disagree with the hero card above it.
    struct Fixture: Equatable {
        let week: Int
        /// The opponent's abbreviation, or `nil` for a bye.
        let opponentAbbreviation: String?
        let isHome: Bool
        /// The user's points, once the game has been played.
        let ourScore: Int?
        /// The opponent's points, once the game has been played.
        let theirScore: Int?

        var isPlayed: Bool { ourScore != nil && theirScore != nil }
        var isBye: Bool { opponentAbbreviation == nil }
    }

    /// The opponent tag a slat wears — "@ SF", "VS SEA", "BYE".
    static func opponentTag(_ fixture: Fixture?) -> String {
        guard let fixture, let opponent = fixture.opponentAbbreviation else { return "Bye" }
        return fixture.isHome ? "vs \(opponent)" : "@ \(opponent)"
    }

    /// The result line on a played week — "W 27–13". `nil` while unplayed.
    static func resultLine(_ fixture: Fixture?) -> String? {
        guard let fixture, let ours = fixture.ourScore, let theirs = fixture.theirScore else { return nil }
        let mark = ours > theirs ? "W" : (theirs > ours ? "L" : "T")
        return "\(mark) \(ours)\u{2013}\(theirs)"
    }

    /// The result's colour, on the rating-independent W/L ladder. `nil` for a
    /// tie or an unplayed week, which leaves the band's neutral rule in place.
    ///
    /// P7: this is not the 0–100 rating ladder and must not borrow it. A win and
    /// a loss are a two-value categorical, and `success`/`danger` are the two
    /// values the app already spends on exactly that.
    static func resultTint(_ fixture: Fixture?) -> Color? {
        guard let fixture, let ours = fixture.ourScore, let theirs = fixture.theirScore else { return nil }
        if ours > theirs { return .success }
        if theirs > ours { return .danger }
        return nil
    }

    /// Playoff round names by absolute week. Weeks 19–22 are the bracket
    /// (`WeekAdvancer`: wild card 19 → divisional 20 → conference 21 → Super
    /// Bowl 22).
    static func playoffRoundName(week: Int) -> String {
        switch week {
        case ..<20: return "Wild Card"
        case 20:    return "Divisional"
        case 21:    return "Conference"
        default:    return "The Championship"
        }
    }

    // MARK: - Slats

    /// The ladder: eighteen week slats plus one postseason tail.
    ///
    /// - Parameters:
    ///   - currentWeek: `Career.currentWeek`.
    ///   - inPlayoffs: true once the calendar has left the regular season, in
    ///     which case every week slat is behind the club and the tail is where
    ///     it stands.
    ///   - fixtures: the user's schedule, keyed by week. Missing weeks are byes.
    static func slats(
        currentWeek: Int,
        inPlayoffs: Bool,
        fixtures: [Int: Fixture]
    ) -> [DSSlat] {
        var slats: [DSSlat] = (1...regularSeasonWeeks).map { week in
            let fixture = fixtures[week]
            let state: DSSlat.State
            if inPlayoffs || week < currentWeek {
                state = .done
            } else if week == currentWeek {
                state = .current
            } else {
                state = .future
            }

            let tag = opponentTag(fixture)
            let result = resultLine(fixture)

            // A week the club is standing in but has already played reports its
            // result as the sub-caption rather than pretending it is still
            // ahead: `done` owns `outcome`, `current` owns `subcaption`, and
            // "Sunday is over" is exactly the state the hero card shows too.
            //
            // Before the game the fallback was `tag`, i.e. the title again —
            // the widest slat in the band spent its second line printing
            // "@ JAX" under "@ JAX" while the played slat beside it carried a
            // score there. The slot says what the score is waiting on instead.
            let subcaption: String?
            switch state {
            case .current: subcaption = result ?? (fixture?.isBye ?? true ? "No game this week" : "Not played yet")
            case .done, .future, .locked: subcaption = nil
            }

            return DSSlat(
                id: "week-\(week)",
                index: "\(week)",
                title: tag,
                subcaption: subcaption,
                state: state,
                outcome: state == .done ? (result ?? (fixture?.isBye ?? true ? "Bye" : nil)) : nil,
                tint: state == .done ? resultTint(fixture) : nil,
                isLive: state == .current,
                accessibilityText: weekAccessibilityText(
                    week: week,
                    state: state,
                    tag: tag,
                    result: result,
                    isBye: fixture?.isBye ?? true
                )
            )
        }

        slats.append(postseasonSlat(currentWeek: currentWeek, inPlayoffs: inPlayoffs, fixtures: fixtures))
        return slats
    }

    /// The tail. One slat, locked until the bracket opens — P1's amendment asks
    /// for exactly this rather than four speculative round slats hanging off the
    /// end of every Week 1.
    private static func postseasonSlat(
        currentWeek: Int,
        inPlayoffs: Bool,
        fixtures: [Int: Fixture]
    ) -> DSSlat {
        guard inPlayoffs else {
            return DSSlat(
                id: "postseason",
                index: nil,
                title: "Postseason",
                subcaption: "Opens after Week \(regularSeasonWeeks)",
                state: .locked,
                accessibilityText: "Postseason, locked, opens after week \(regularSeasonWeeks)"
            )
        }

        let round = playoffRoundName(week: currentWeek)
        let fixture = fixtures[currentWeek]
        let result = resultLine(fixture)
        let subcaption = result ?? (fixture == nil ? "Not in the bracket" : opponentTag(fixture))

        return DSSlat(
            id: "postseason",
            index: nil,
            title: round,
            subcaption: subcaption,
            state: .current,
            isLive: true,
            accessibilityText: "Postseason, \(round), current, \(subcaption)"
        )
    }

    private static func weekAccessibilityText(
        week: Int,
        state: DSSlat.State,
        tag: String,
        result: String?,
        isBye: Bool
    ) -> String {
        let stateWord: String
        switch state {
        case .done:    stateWord = "played"
        case .current: stateWord = "this week"
        case .future:  stateWord = "upcoming"
        case .locked:  stateWord = "locked"
        }
        let opponent = isBye ? "bye week" : tag
        return ["Week \(week)", stateWord, opponent, result]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

// MARK: - The view the shell mounts

/// The season ladder as `CareerShellView` draws it: pinned under the top bar,
/// above the hub, never inside a scroll.
struct SeasonWeekBandView: View {

    let currentWeek: Int
    let inPlayoffs: Bool
    let fixtures: [Int: SeasonWeekBand.Fixture]
    /// Printed in the band head — **the one place the season prints its count.**
    let seasonYear: Int

    private var headline: String {
        if inPlayoffs {
            return "\(String(seasonYear)) season \u{00B7} Postseason"
        }
        return "\(String(seasonYear)) season \u{00B7} Week \(currentWeek) of \(SeasonWeekBand.regularSeasonWeeks)"
    }

    var body: some View {
        DSSlatBand(
            slats: SeasonWeekBand.slats(
                currentWeek: currentWeek,
                inPlayoffs: inPlayoffs,
                fixtures: fixtures
            ),
            headline: headline
        )
        // Nineteen slats never fit, so the ribbon scrolls — and it parks itself
        // on the current week in `onAppear`, which only fires when the view is
        // built. Re-keying on the week is what makes the ladder follow the
        // calendar instead of staying where Week 1 left it.
        .id(currentWeek)
        .padding(.horizontal, DSSpacing.sm)
        .padding(.bottom, DSSpacing.xxs)
        .background(Color.backgroundPrimary)
    }
}

// MARK: - Preview

#Preview("Week 7") {
    ZStack(alignment: .top) {
        Color.backgroundPrimary.ignoresSafeArea()
        SeasonWeekBandView(
            currentWeek: 7,
            inPlayoffs: false,
            fixtures: [
                1: .init(week: 1, opponentAbbreviation: "SEA", isHome: true, ourScore: 27, theirScore: 13),
                2: .init(week: 2, opponentAbbreviation: "SF", isHome: false, ourScore: 10, theirScore: 24),
                3: .init(week: 3, opponentAbbreviation: "ARI", isHome: true, ourScore: 31, theirScore: 31),
                4: .init(week: 4, opponentAbbreviation: nil, isHome: true, ourScore: nil, theirScore: nil),
                5: .init(week: 5, opponentAbbreviation: "DAL", isHome: false, ourScore: 21, theirScore: 17),
                6: .init(week: 6, opponentAbbreviation: "NYG", isHome: true, ourScore: 14, theirScore: 20),
                7: .init(week: 7, opponentAbbreviation: "PHI", isHome: false, ourScore: nil, theirScore: nil),
                8: .init(week: 8, opponentAbbreviation: "WAS", isHome: true, ourScore: nil, theirScore: nil),
            ],
            seasonYear: 2026
        )
    }
}
