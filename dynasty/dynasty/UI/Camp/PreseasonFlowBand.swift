import SwiftUI

// MARK: - PreseasonFlowBand — three games, on the shared spine
//
// `docs/OFFSEASON_ROSTER_PLAN.md` §4.1 / §5. Preseason is **three steps inside
// one `.preseason` phase**, exactly the shape free agency already ships: a
// multi-round market inside a single `.freeAgency` phase, driven by
// `Career.freeAgencyRound` / `freeAgencyStep` with `FAFlowBand` as its spine.
// This file is that band for the preseason slate, and it is modelled on
// `FAFlowBand.swift` line for line so the two processes read the same way.
//
// **No new `SeasonPhase` case, and no second count.** UI_REDESIGN_VISION §2.1's
// rule that a process prints its stage count exactly once is why the head owns
// "GAME 2 OF 3" and no screen underneath repeats it. The band is the only
// component allowed to say where in the slate the club stands.
//
// **The cut ladder is deliberately NOT on this band.** 87 → 75 → 65 → 53 is
// `CutDay`'s ladder and `RosterCutView` already mounts it as its own
// `DSSlatBand`. Printing "Cut to 65" as a fourth slat here would be the same
// ladder drawn twice, in two places that could disagree — the exact defect
// §2.1 exists to prevent. The 65 rung reaches the user through the task rail
// and through the exit gate, both of which derive from the roster count.
//
// **Not navigable.** `onSelect` is nil, so every slat is a disabled button and
// reads as one. A preseason game is advanced by playing it; a slat that looked
// tappable but silently refused would be worse than one that does not.

enum PreseasonFlowBand {

    /// The three games. A constant rather than a range so the count has one
    /// home and the band, the meter and the accessibility sentence cannot
    /// disagree about it.
    static let gameCount = 3

    /// Where inside a single game the club is standing.
    ///
    /// This is a **projection** of `PreseasonState.step`, not a second copy of
    /// it: `PreseasonView` maps the persisted step onto these three values in
    /// one place, which is the only place that has to change if the engine's
    /// own step enum is reshaped. The band itself stays free of the persisted
    /// type, so it previews and renders with no engine present.
    enum Stance: Equatable {
        /// A plan is owed for this game — pick a policy, then play it.
        case planning
        /// The game is played and its tape is on the screen.
        case reviewing
        /// All three are behind the club.
        case complete
    }

    static func title(game: Int) -> String { "Game \(game)" }

    /// What the slat the club is standing on is for.
    static func subcaption(_ stance: Stance) -> String {
        switch stance {
        case .planning:  return "Choose who dresses, then play it"
        case .reviewing: return "Read the tape before the next one"
        case .complete:  return "The slate is done"
        }
    }

    /// The head's left-hand line — **the one place the flow prints its count.**
    static func headline(game: Int, stance: Stance) -> String {
        if stance == .complete { return "Preseason \u{00B7} Slate complete" }
        return "Preseason \u{00B7} Game \(min(max(game, 1), gameCount)) of \(gameCount)"
    }

    /// The meter: a played game is a spent game, so `spent + left == total`
    /// holds the way `DSResourceMeter` documents it.
    static func meter(gamesPlayed: Int) -> DSResourceMeter {
        DSResourceMeter(
            spent: min(max(gamesPlayed, 0), gameCount),
            total: gameCount,
            unit: "preseason games"
        )
    }

    /// The slats.
    ///
    /// - Parameters:
    ///   - currentGame: 1…3 while the slate is live. Ignored when `stance` is
    ///     `.complete`, where every slat is behind the club.
    ///   - stance: where inside `currentGame` the club stands.
    ///   - outcomes: what a played game produced — "W 24\u{2013}17" — keyed by
    ///     game index. §2.1's `done` row is "check glyph + the outcome".
    ///   - tints: the result's colour for a played game's top rule, keyed the
    ///     same way. `nil` for a tie leaves the neutral rule.
    static func slats(
        currentGame: Int,
        stance: Stance,
        outcomes: [Int: String] = [:],
        tints: [Int: Color] = [:]
    ) -> [DSSlat] {
        let current = min(max(currentGame, 1), gameCount)
        return (1...gameCount).map { game in
            let state: DSSlat.State
            if stance == .complete || game < current {
                state = .done
            } else if game == current {
                state = .current
            } else {
                state = .future
            }
            let sub = state == .current ? subcaption(stance) : nil
            return DSSlat(
                id: "preseason-game-\(game)",
                index: "\(game)",
                title: title(game: game),
                subcaption: sub,
                state: state,
                // A later preseason game is reachable in principle but never
                // playable out of order, so nothing is raised to `isAvailable`.
                outcome: outcomes[game],
                tint: tints[game],
                accessibilityText: accessibilityText(
                    game: game,
                    state: state,
                    subcaption: sub,
                    outcome: outcomes[game]
                )
            )
        }
    }

    private static func accessibilityText(
        game: Int,
        state: DSSlat.State,
        subcaption: String?,
        outcome: String?
    ) -> String {
        let stateWord: String
        switch state {
        case .done:    stateWord = "played"
        case .current: stateWord = "current game"
        case .future:  stateWord = "not played"
        case .locked:  stateWord = "locked"
        }
        return [
            "Preseason game \(game) of \(gameCount)",
            stateWord,
            outcome,
            subcaption
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }
}

// MARK: - The view the preseason screen mounts

/// The band as `PreseasonView` uses it: pinned above the content, never inside
/// the scroll, so the spine cannot scroll away from the user (§2.5).
struct PreseasonFlowBandView: View {

    /// 1…3. Where the slate stands; ignored when `stance == .complete`.
    let currentGame: Int
    let stance: PreseasonFlowBand.Stance
    /// Played-game results, keyed by game index — "W 24\u{2013}17".
    var outcomes: [Int: String] = [:]
    /// Result tints, keyed by game index. Green for a win, red for a loss.
    var tints: [Int: Color] = [:]
    /// Games behind the club. Drives the meter only.
    var gamesPlayed: Int = 0

    var body: some View {
        DSSlatBand(
            slats: PreseasonFlowBand.slats(
                currentGame: currentGame,
                stance: stance,
                outcomes: outcomes,
                tints: tints
            ),
            headline: PreseasonFlowBand.headline(game: currentGame, stance: stance),
            meter: PreseasonFlowBand.meter(gamesPlayed: gamesPlayed)
        )
        .padding(.horizontal, DSSpacing.md)
        .padding(.top, DSSpacing.xs)
        .padding(.bottom, DSSpacing.xs)
        .background(Color.backgroundPrimary)
    }
}

// MARK: - Preview

#Preview("Planning game 2") {
    ZStack(alignment: .top) {
        Color.backgroundPrimary.ignoresSafeArea()
        PreseasonFlowBandView(
            currentGame: 2,
            stance: .planning,
            outcomes: [1: "W 24\u{2013}17"],
            tints: [1: .success],
            gamesPlayed: 1
        )
    }
}

#Preview("Slate complete") {
    ZStack(alignment: .top) {
        Color.backgroundPrimary.ignoresSafeArea()
        PreseasonFlowBandView(
            currentGame: 3,
            stance: .complete,
            outcomes: [1: "W 24\u{2013}17", 2: "L 10\u{2013}31", 3: "W 20\u{2013}13"],
            tints: [1: .success, 2: .dangerText, 3: .success],
            gamesPlayed: 3
        )
    }
}
