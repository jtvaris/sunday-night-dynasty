import Foundation

/// Decides when to surface big dramatic moments during the live draft (steal
/// banner, round transition, gem flash, "your pick is coming up" pulse, Mr.
/// Irrelevant).
///
/// This is distinct from `ReactionsEngine`:
/// - `ReactionsEngine` represents what the four actors *say* about a pick
///   (owner, media, locker room, fans).
/// - `DraftDramaEngine` represents what the *broadcast / UI overlay* should
///   show about it: full-screen banners, particle bursts, screen flashes.
///
/// The view layer feeds each completed pick through `dramaEventsFor(...)`
/// and renders any returned events through its banner queue.
enum DraftDramaEngine {

    enum DramaEvent: Equatable {
        /// A clear "steal of the draft" moment — top of the broadcast.
        case stealOfTheDraft(playerName: String, teamAbbrev: String, valueDelta: Int)
        /// Round changed — show "ROUND N" curtain.
        case roundTransition(roundNumber: Int)
        /// Gem candidate selected — sparkle overlay on the pick card.
        case gemMoment(playerName: String, teamAbbrev: String)
        /// User's pick is approaching — pulse the on-the-clock chrome.
        case userPickIncoming(picksAway: Int)
        /// A man the user marked ELITE on his own board is still sitting there
        /// with the user's turn in sight. The one beat that makes a marked
        /// board pay off on draft night.
        case targetOnTheBoard(playerName: String, position: String, picksAway: Int)
        /// …and the sting when somebody else takes him first.
        case targetSniped(playerName: String, position: String, teamAbbrev: String)
        /// Final pick of the entire draft — Mr. Irrelevant moment.
        case finalPick
    }

    // MARK: - Tunables

    /// Pick must fall this many slots past projection to count as "steal of
    /// the draft". (Currently inferred via grade + isBigDrop until we expose
    /// projection on PickResult.)
    static let stealValueThreshold: Int = 8

    /// Distance ahead of the user's pick at which the incoming-pulse fires.
    static let pickIncomingDistance: Int = 3

    /// Distance at which the war room starts shouting about a marked target.
    /// Deliberately wider than `pickIncomingDistance` so the beat lands *before*
    /// the generic "your pick is next" pulse rather than fighting it: first
    /// "he's still there", then "you're up".
    static let targetWatchDistance: Int = 6

    // MARK: - API

    /// Returns a list of drama events triggered by this pick (often empty).
    ///
    /// - Parameters:
    ///   - result: the just-completed pick.
    ///   - currentRound: round of `result`.
    ///   - previousRound: round of the pick *before* `result`. Pass the same
    ///       value as `currentRound` if there was no previous pick (round 1
    ///       opener); a transition event will fire when these differ.
    ///   - picksUntilUserPick: distance from the next-on-the-clock pick to
    ///       the user's next pick, computed by the coordinator.
    ///   - isFinalPick: true if `result` was the last selection of the
    ///       entire draft.
    static func dramaEventsFor(
        result: PickResult,
        currentRound: Int,
        previousRound: Int,
        picksUntilUserPick: Int,
        isFinalPick: Bool
    ) -> [DramaEvent] {
        var events: [DramaEvent] = []

        // 1) Round transition — fires when round just changed.
        if currentRound != previousRound {
            events.append(.roundTransition(roundNumber: currentRound))
        }

        // 2) Steal of the draft — A+ Steal or HOF-Track grades, optionally
        //    with the bigDrop flag for emphasis.
        if result.grade == .stealAPlus || result.grade == .hofTrack {
            let magnitude = approximateStealMagnitude(for: result)
            if magnitude >= stealValueThreshold {
                events.append(.stealOfTheDraft(
                    playerName: result.playerName,
                    teamAbbrev: result.teamAbbrev,
                    valueDelta: magnitude
                ))
            }
        }

        // 3) Gem moment — separate sparkle even when the broadcast steal
        //    banner doesn't fire (e.g. top-10 gem doesn't qualify as a fall).
        if result.isGem &&
           !events.contains(where: { if case .stealOfTheDraft = $0 { return true } else { return false } }) {
            events.append(.gemMoment(
                playerName: result.playerName,
                teamAbbrev: result.teamAbbrev
            ))
        }

        // 4) User pick incoming — fire once when crossing into the warning
        //    distance. Caller passes the number of picks between the *next*
        //    on-the-clock pick and the user's next pick, so the moment we
        //    cross from > distance to == distance, we pulse.
        if picksUntilUserPick > 0 && picksUntilUserPick <= pickIncomingDistance {
            events.append(.userPickIncoming(picksAway: picksUntilUserPick))
        }

        // 5) Mr. Irrelevant.
        if isFinalPick {
            events.append(.finalPick)
        }

        return events
    }

    // MARK: - Marked-target beats

    /// "Your guy is still on the board, N picks to yours."
    ///
    /// Returns nil unless the user's turn is genuinely in sight — the beat is
    /// worth nothing if it fires at pick 3 of a round the user picks last in.
    /// The caller is responsible for firing it at most once per user turn.
    static func targetOnTheBoardBeat(
        playerName: String,
        position: String,
        picksUntilUserPick: Int
    ) -> DramaEvent? {
        guard picksUntilUserPick > 0, picksUntilUserPick <= targetWatchDistance else { return nil }
        return .targetOnTheBoard(
            playerName: playerName,
            position: position,
            picksAway: picksUntilUserPick
        )
    }

    /// The sting: a club ahead of the user just took a man he had marked.
    /// Only ever fires for a mark the user said he WANTED — losing a prospect
    /// tagged "avoid" is not a loss.
    static func targetSnipedBeat(
        playerName: String,
        position: String,
        teamAbbrev: String,
        isWantedTarget: Bool
    ) -> DramaEvent? {
        guard isWantedTarget else { return nil }
        return .targetSniped(
            playerName: playerName,
            position: position,
            teamAbbrev: teamAbbrev
        )
    }

    // MARK: - Heuristics

    /// Estimate of "how big a fall" a steal represents. Until PickResult
    /// carries a projection field, we synthesize from grade + isBigDrop.
    private static func approximateStealMagnitude(for result: PickResult) -> Int {
        var mag = 0
        switch result.grade {
        case .hofTrack:   mag += 20
        case .stealAPlus: mag += 12
        default:          mag += 0
        }
        if result.isBigDrop { mag += 10 }
        if result.isGem     { mag += 4 }
        return mag
    }
}
