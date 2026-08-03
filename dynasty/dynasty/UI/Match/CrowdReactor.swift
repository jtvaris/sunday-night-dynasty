import Foundation

// MARK: - CrowdReactor

/// The stadium's reaction layer: the cheers, boos, gasps and chants that ride
/// ON TOP of ``AudioDirector``'s ambient bed.
///
/// # Whose crowd is it?
///
/// The crowd in the building belongs to the **home team**, always — never to
/// the coach. Every rule below therefore keys off one fact, `offenseWasHome`
/// (`CoachedGameView` captures `engine.homeHasPossession` before the snap and
/// hands it to `finishPlay`; the engine stamps the same value onto
/// `PlayResult.offenseWasHome`). `playerTeamIsHome` is deliberately NOT
/// consulted:
///
/// - Coach the home team and it reads the obvious way — your touchdown gets
///   the roar, your interception gets booed.
/// - Coach on the road and the building turns on you, which is the point of
///   playing on the road. The opponent's touchdown draws a cheer, your
///   fourth-down stop draws boos.
///
/// # De-confliction
///
/// One reaction at a time. A reaction claims the crowd for as long as its wav
/// runs and blocks anything of equal or lower magnitude behind it; only a
/// `.large` moment (a score, a takeaway) is allowed to talk over something
/// already playing, because those are the beats the player is waiting for.
/// Every reaction also ducks the bed for its own length so it lands in a hole
/// instead of fighting the murmur.
///
/// Muting is inherited: `AudioDirector.play` returns 0 and makes no sound when
/// the Settings toggle is off, and `duckCrowdBed` is a no-op outside a match,
/// so the whole layer goes quiet with the rest of the mix.
final class CrowdReactor {

    static let shared = CrowdReactor()

    /// How big the moment is. Drives the level, how deep the bed ducks, and
    /// which take of a multi-take cue gets picked (the cheers are ordered
    /// smallest → biggest on disk).
    enum Magnitude: Int, Comparable {
        case small = 0
        case medium
        case large

        static func < (lhs: Magnitude, rhs: Magnitude) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        var gainScale: Float {
            switch self {
            case .small:  return 0.55
            case .medium: return 0.8
            case .large:  return 1.0
            }
        }
    }

    // MARK: Tuning

    /// Chants are wallpaper if they show up every series — a minute and a
    /// half of silence between them keeps them feeling spontaneous.
    private static let chantCooldown: TimeInterval = 90
    /// …and even then only some first downs get one.
    private static let chantChance = 0.35
    /// A gain this big is worth a noise all by itself.
    private static let bigGainYards = 20
    private static let goodGainYards = 12

    // MARK: State

    private var matchActive = false
    /// The crowd is spoken for until this instant.
    private var busyUntil: Date = .distantPast
    /// …at this magnitude, so a bigger moment can still cut in.
    private var busyMagnitude: Magnitude = .small
    private var lastChant: Date = .distantPast

    private init() {}

    // MARK: Match lifecycle

    func matchDidStart() {
        matchActive = true
        busyUntil = .distantPast
        busyMagnitude = .small
        // Let the first chant land early in the game rather than never.
        lastChant = Date().addingTimeInterval(-Self.chantCooldown * 0.5)
    }

    func matchDidEnd() {
        matchActive = false
        busyUntil = .distantPast
    }

    // MARK: Play resolution

    /// The whole scrimmage surface in one call, fired from
    /// `CoachedGameView.finishPlay` once the ball is dead on the field.
    ///
    /// - Parameters:
    ///   - offenseWasHome: who had the ball when the play started.
    ///   - homePlayerInjured: any of `engine.lastPlayInjuries` on the home
    ///     side — the building goes quiet when one of its own stays down.
    func playResolved(_ play: PlayResult, offenseWasHome: Bool, homePlayerInjured: Bool) {
        guard matchActive else { return }

        // 1. Scores outrank everything.
        if play.pointsScored >= 6 {
            return offenseWasHome ? cheer(.large) : boo(.large)
        }
        if play.outcome == .fieldGoalGood || play.outcome == .twoPointGood {
            return offenseWasHome ? cheer(.medium) : boo(.medium)
        }
        if play.outcome == .safety {
            // The offense gave up two — the crowd reacts to whose offense.
            return offenseWasHome ? boo(.medium) : cheer(.medium)
        }

        // 2. Takeaways. The defense won the ball, so the reaction flips.
        if play.isTurnover {
            return offenseWasHome ? boo(.large) : cheer(.large)
        }

        // 3. Turned it over on downs — the offense stayed on the field and
        //    came up short. Kicks and kneels don't count as a failed try.
        if play.down == 4, !play.isFirstDown, Self.isLiveScrimmage(play.playType),
           play.outcome != .penalty {
            return offenseWasHome ? boo(.medium) : cheer(.medium)
        }

        // 4. A man down. Quiet concern, not a roar — and it wins over the
        //    yardage reactions below however the play itself finished.
        if homePlayerInjured {
            return gasp()
        }

        // 5. Flag on the home team.
        if play.outcome == .penalty, offenseWasHome {
            return boo(.small)
        }

        // 6. Sacks: the crowd groans for its own QB, erupts for its own rush.
        if play.outcome == .sack {
            return offenseWasHome ? gasp() : cheer(.small)
        }

        // 7. Chunk plays. A visiting offense ripping off 30 gets silence, not
        //    boos — a home crowd goes quiet when the other team is rolling.
        if offenseWasHome {
            if play.yardsGained >= Self.bigGainYards { return cheer(.medium) }
            if play.yardsGained >= Self.goodGainYards { return cheer(.small) }
        } else if play.defensiveHighlight == true {
            // The home defense made the play (breakup, big hit, TFL).
            return cheer(.small)
        }

        // 8. Nothing loud happened — maybe the chant picks up behind the
        //    chains moving.
        if play.isFirstDown, offenseWasHome {
            chantIfDue()
        }
    }

    /// A kickoff housed for six. The returning team is the one being cheered.
    func kickoffReturnTouchdown(returningTeamIsHome: Bool) {
        guard matchActive else { return }
        returningTeamIsHome ? cheer(.large) : boo(.large)
    }

    /// A de-cleater on the field, reported by the choreography the instant it
    /// lands (mid-play, well before the whistle). `victimIsHome` comes from
    /// the node index the scene flattened the carrier onto — 0-10 are the home
    /// eleven, 11-21 the visitors.
    ///
    /// Getting your own man blown up is a gasp; blowing up the visitor is a
    /// roar. Either way this claims the crowd, so the whistle-time reaction a
    /// second later only speaks if it is a bigger moment.
    func bigHit(victimIsHome: Bool) {
        guard matchActive else { return }
        victimIsHome ? gasp() : cheer(.small)
    }

    // MARK: Reactions

    private func cheer(_ magnitude: Magnitude) {
        // The cheer takes are ordered smallest → biggest, so the magnitude
        // picks the recording as well as the level.
        fire(.crowdCheer, magnitude: magnitude, preferTake: magnitude.rawValue)
    }

    private func boo(_ magnitude: Magnitude) {
        fire(.crowdBoo, magnitude: magnitude)
    }

    private func gasp() {
        fire(.crowdGasp, magnitude: .medium)
    }

    private func chantIfDue() {
        let now = Date()
        guard now.timeIntervalSince(lastChant) >= Self.chantCooldown else { return }
        guard Double.random(in: 0..<1) < Self.chantChance else { return }
        // Only mark the cooldown if it actually got through the de-conflict.
        if fire(.crowdChant, magnitude: .small) { lastChant = now }
    }

    /// Plays a reaction unless the crowd is already busy with something at
    /// least as big. Returns whether it sounded.
    @discardableResult
    private func fire(_ cue: MatchSound, magnitude: Magnitude, preferTake: Int? = nil) -> Bool {
        let now = Date()
        if now < busyUntil, magnitude <= busyMagnitude { return false }

        let length = AudioDirector.shared.play(cue,
                                               gainScale: magnitude.gainScale,
                                               preferTake: preferTake)
        guard length > 0 else { return false }   // sound off, or asset missing

        busyUntil = now.addingTimeInterval(length)
        busyMagnitude = magnitude
        // Hold the bed down for the reaction, then let it breathe back in.
        AudioDirector.shared.duckCrowdBed(for: length * 0.75)
        return true
    }

    // MARK: Helpers

    /// A snap that could actually have converted — a punt, a field goal or a
    /// kneel on fourth down is not a failed attempt.
    private static func isLiveScrimmage(_ type: PlayType) -> Bool {
        switch type {
        case .run, .pass:
            return true
        case .punt, .fieldGoal, .kickoff, .extraPoint,
             .twoPointConversion, .kneel, .spike:
            return false
        }
    }
}
