import Foundation

// MARK: - Press Engine (#161)
//
// ONE engine-side home for everything a press conference decides: what the
// coach plausibly knows before he speaks (`ReactionPreview`), what an answer
// actually costs (`resolvedEffects`), and what a claim commits him to
// (`PressPromiseRecord`). `PressConferenceView` and `WeeklyPressConferenceView`
// are two separate screens by design (the visual merge is redesign wave 5) but
// after this file they are two *renderers* of the same mechanics — neither owns
// a number, a threshold, or a stance rule of its own, so they cannot drift.
//
// WHY THIS EXISTS. The shipped presser printed the exact deltas of every option
// before the player answered ("Owner +4 · Morale -2 · Fans +14 · Media +5"),
// which turned a roleplay beat into a spreadsheet: read four rows, sum, pick the
// max. Worse, the *safe* row was strictly the best one — Diplomatic was authored
// as +4/+4/+4/+4, positive on every axis in every question, so "always pick
// green" was a dominant strategy that never lost anything.
//
// The fix is the fog philosophy the rest of the game already runs on: DIRECTION,
// not magnitude, and only for the audiences a coach could actually read. The
// numbers do not disappear — they move to *after* the answer, next to the
// headline that ran, where they teach instead of optimise.
//
// ============================================================================
// THE CONTEXT MATRIX — tone × situation
// ============================================================================
// Every cell below is a `situationAdjustment` added on top of the question's
// authored base effects. Read it as "what this tone SOUNDS LIKE in this room".
// The column that matters most is `.crisis`: a question that demands a stance
// punishes the answer that refuses to take one.
//
//  tone        | intro          | after win      | after bad loss | crisis (skid) | high stakes
//  ------------|----------------|----------------|----------------|---------------|----------------
//  confident   | fans+ media+   | fans+ media+   | DELUSIONAL     | spine:        | fans++ media+
//              |                |                | media-- fans-- | morale++ own+ |
//  humble      | own+ mor+      | morale+ media+ | BEST NOTE      | no plan:      | timid:
//              | fans-          |                | media+ mor+    | own- fans-    | fans- media-
//  aggressive  | media+ mor-    | sours it:      | media+ mor--   | a stance:     | media+ mor-
//              |                | mor-- own-     |                | media++ own+  |
//  diplomatic  | forgettable:   | vanilla:       | protects room, | DODGING:      | no answer:
//              | media- fans--  | media- fans-   | bores press    | media--- fans-| media-- fans-
//  funny       | fans+ media-   | fans++ mor+    | TONE-DEAF      | media- own-   | fans+ own-
//              |                |                | media-- fans-- |               |
//
// NO TONE DOMINATES, by construction:
//   • Confident wins `.highStakes` and `.crisis`, loses `.afterBadLoss` hardest.
//   • Humble wins `.afterBadLoss`, loses `.crisis` and `.highStakes`.
//   • Aggressive owns media everywhere and is the *only* tone that never buys
//     morale — it pays for its headlines out of the locker room, every time.
//   • Diplomatic is negative on media/fans in EVERY situation and positive on
//     owner/morale in most — it is the "protect the building, bore the market"
//     play, correct when the room is fragile and wrong when the room wants a
//     stance. It is never Pareto-safe again.
//   • Funny wins fans when nothing is burning and is the worst answer in the
//     two situations where something is.
//
// Three further axes ride on top of the matrix and are what make the same tone
// land differently twice in one career:
//   • TEAM STATE vs GOALS (`standingAdjustment`) — a championship claim on a
//     rebuilding roster costs owner trust even as it buys fans; humility on a
//     loaded contender reads as a lack of belief and costs fans.
//   • REPORTER STANCE (`stanceAdjustment`) — hostile punishes evasion
//     (diplomatic/funny) and rewards candor (humble/aggressive); friendly
//     amplifies confidence and humor.
//   • REPETITION (`repetitionScale`) — the career-scoped tone ledger decays a
//     repeated tone's payoff and eventually earns a "sounding vanilla" media
//     label, mirroring the negotiation engine's pestering ratchet.
//
// MAGNITUDES stay inside the shipped ±4…±20 band (`effectFloor`/`effectCeiling`)
// so Career morale/media/legacy tuning is not destabilised. Legacy points are
// deliberately NOT context-modulated — legacy is the long-game currency and the
// promise ledger is what moves it.

extension PressConferenceEngine {

    // MARK: - Reporter Stance

    /// Where the reporter asking is coming from. Was duplicated as a private
    /// enum inside BOTH press views (identical outlet lists, identical labels);
    /// it lives here now because it is an input to the effect math, not a
    /// decoration.
    enum ReporterStance: String, Codable, Equatable {
        case friendly
        case neutral
        case hostile

        /// Chip copy. "Tough" rather than "Hostile" — the chip is what the coach
        /// sees, and a beat writer who asks hard questions is not an enemy.
        var label: String {
            switch self {
            case .friendly: return "Friendly"
            case .neutral:  return "Neutral"
            case .hostile:  return "Tough"
            }
        }
    }

    /// Local beat writers lean friendly, the national TV desk leans tough,
    /// everyone else is neutral. Stable per outlet so the chip never lies.
    ///
    /// The lists MUST stay in sync with `PressConferenceEngine.reporters` and
    /// `.localReporters` — an outlet rename that misses this function silently
    /// collapses a whole stance tier to `.neutral` and kills the matching
    /// branch of `stanceAdjustment`. (That is exactly what happened once: the
    /// tough list still named two real broadcasters after the press corps was
    /// made fictional, so no reporter was ever hostile.)
    ///
    /// SHARE MATTERS, not just reachability: the shipped mix was 2 tough
    /// reporters out of the 8 national ones. `Continental Sports` fields
    /// exactly two of the current eight, so it alone is the tough desk —
    /// adding a second outlet here would silently double how often evasion
    /// gets punished in a crisis presser.
    static func stance(forOutlet outlet: String) -> ReporterStance {
        let lower = outlet.lowercased()
        let local = ["local press", "city tribune", "local news 9"]
        if local.contains(where: { lower.contains($0) }) { return .friendly }
        // The national TV desk (Ty Brennan, Vivian Osei).
        let tough = ["continental sports"]
        if tough.contains(where: { lower.contains($0) }) { return .hostile }
        return .neutral
    }

    static func stance(for question: PressQuestion) -> ReporterStance {
        stance(forOutlet: question.outlet)
    }

    // MARK: - Situation

    /// What kind of room this is. Derived once per conference from the season
    /// state, never from the question text.
    enum PressSituation: String, Codable, Equatable {
        /// The career-creation presser: no season history exists yet.
        case introduction
        /// The team just won.
        case afterWin
        /// The team just lost, and it was not close.
        case afterBadLoss
        /// The year is coming apart — a skid, or a losing record deep enough
        /// that the question is really "what are you going to do about it".
        case crisis
        /// A playoff push, a hot streak, or a finale that decides something.
        case highStakes
        /// A midweek presser with nothing burning.
        case routine

        /// True when the room expects a position, not a posture. Dodging costs
        /// double here (see `stanceAdjustment`).
        var demandsAStance: Bool {
            self == .crisis || self == .afterBadLoss
        }
    }

    /// Where the roster actually is, which is what a promise gets measured
    /// against. Bands, not numbers — the coach knows which of the three he runs.
    enum TeamStanding: String, Codable, Equatable {
        case rebuilding
        case middling
        case contender

        var label: String {
            switch self {
            case .rebuilding: return "Rebuilding"
            case .middling:   return "In the middle"
            case .contender:  return "Contending"
            }
        }
    }

    /// The locker-room mood band — the one context axis a head coach reads for
    /// free, because he is in the building every day.
    enum LockerRoomBand: String, Codable, Equatable {
        case buoyant
        case steady
        case fragile

        var label: String {
            switch self {
            case .buoyant: return "Buoyant"
            case .steady:  return "Steady"
            case .fragile: return "Fragile"
            }
        }

        /// Bucket a roster's average morale (1–100).
        static func from(averageMorale: Int) -> LockerRoomBand {
            switch averageMorale {
            case 70...:   return .buoyant
            case ..<50:   return .fragile
            default:      return .steady
            }
        }
    }

    // MARK: - Press Context

    /// Everything the engine is allowed to know when it resolves an answer —
    /// and, coarsened, everything the *player* is allowed to see before he
    /// answers. Value type, cheap to carry, safe to hand a SwiftUI `@State`.
    struct PressContext: Equatable {
        var situation: PressSituation
        var standing: TeamStanding
        var lockerRoom: LockerRoomBand
        /// The owner's known persona. Shown on the owner meeting screen from
        /// day one, so keying effects off it is fog-legal.
        var ownerPrefersWinNow: Bool
        /// 1–10, also shown from day one.
        var ownerPatience: Int
        /// Recent tone picks, NEWEST FIRST, career-scoped. Drives the
        /// repetition ratchet. Includes the picks made earlier in THIS
        /// conference, so a player who answers Diplomatic four times in a row
        /// watches it stop working inside a single session.
        var recentTones: [ResponseTone]
        var season: Int
        var week: Int

        init(
            situation: PressSituation,
            standing: TeamStanding = .middling,
            lockerRoom: LockerRoomBand = .steady,
            ownerPrefersWinNow: Bool = false,
            ownerPatience: Int = 5,
            recentTones: [ResponseTone] = [],
            season: Int = 0,
            week: Int = 0
        ) {
            self.situation = situation
            self.standing = standing
            self.lockerRoom = lockerRoom
            self.ownerPrefersWinNow = ownerPrefersWinNow
            self.ownerPatience = ownerPatience
            self.recentTones = recentTones
            self.season = season
            self.week = week
        }

        /// A neutral context. Only for previews and for the defensive path where
        /// a caller could not assemble one.
        static let neutral = PressContext(situation: .routine)

        /// The context with `tone` pushed onto the ledger — how a view advances
        /// the ratchet between questions without touching storage.
        func appending(tone: ResponseTone) -> PressContext {
            var copy = self
            copy.recentTones = Array(([tone] + recentTones).prefix(toneLedgerDepth))
            return copy
        }
    }

    /// How many tone picks the career-scoped ledger keeps. Twelve ≈ four
    /// conferences, which is the horizon over which "he always says the same
    /// thing" is a fair accusation.
    static let toneLedgerDepth = 12

    /// The window the ratchet actually scores. Shorter than the ledger so an
    /// old habit forgives.
    static let toneRepetitionWindow = 6

    // MARK: - Context Builders

    /// Context for the career-creation presser. Deliberately simplified: there
    /// is no season history, no last game, and no record — but it is the SAME
    /// engine path, so the intro cannot drift from the weekly presser.
    ///
    /// `standing` comes from the roster the new coach just inherited, which is
    /// exactly what the fans and the owner will measure a promise against.
    static func introContext(
        career: Career,
        team: Team,
        owner: Owner?,
        roster: [Player]
    ) -> PressContext {
        PressContext(
            situation: .introduction,
            standing: standing(forTeam: team, roster: roster),
            lockerRoom: lockerRoomBand(roster: roster),
            ownerPrefersWinNow: owner?.prefersWinNow ?? false,
            ownerPatience: owner?.patience ?? 5,
            recentTones: career.pressToneHistory,
            season: career.currentSeason,
            week: 0
        )
    }

    /// Context for an in-season presser, assembled by `WeekAdvancer` at the same
    /// moment it generates the questions.
    static func weeklyContext(
        career: Career,
        team: Team,
        owner: Owner?,
        roster: [Player],
        week: Int,
        facts: GameFacts?
    ) -> PressContext {
        PressContext(
            situation: situation(team: team, week: week, facts: facts),
            standing: standing(forTeam: team, roster: roster),
            lockerRoom: lockerRoomBand(roster: roster),
            ownerPrefersWinNow: owner?.prefersWinNow ?? false,
            ownerPatience: owner?.patience ?? 5,
            recentTones: career.pressToneHistory,
            season: career.currentSeason,
            week: week
        )
    }

    /// A loss by more than a converted touchdown is a *bad* loss; a one-score
    /// defeat is just a defeat.
    private static let badLossMargin = 9

    static func situation(team: Team, week: Int, facts: GameFacts?) -> PressSituation {
        let played = team.wins + team.losses + team.ties

        // The year coming apart outranks any single result: a coach 2-8 is not
        // having a routine Wednesday no matter what happened on Sunday.
        if played >= 6, team.losses >= team.wins + 3 { return .crisis }

        if let facts {
            if !facts.won && facts.margin >= badLossMargin { return .afterBadLoss }
            if facts.won { return played >= 10 && team.wins >= 7 ? .highStakes : .afterWin }
            return .afterBadLoss
        }

        // No game facts (season opener, or an advance that produced no box
        // score): fall back to the standings.
        if week >= 15 && team.wins >= 8 { return .highStakes }
        if played >= 10 && team.wins >= 7 { return .highStakes }
        return .routine
    }

    /// Roster quality first, record second — a 1-3 start does not make a
    /// stacked roster a rebuild, and week 1 has no record at all.
    static func standing(forTeam team: Team, roster: [Player]) -> TeamStanding {
        let active = roster.filter { !$0.isRetired }
        let avgOverall = active.isEmpty
            ? 68
            : active.map(\.overall).reduce(0, +) / active.count

        let played = team.wins + team.losses + team.ties
        if played >= 6 {
            if team.wins >= team.losses + 3 { return .contender }
            if team.losses >= team.wins + 4 { return .rebuilding }
        }
        switch avgOverall {
        case 74...:  return .contender
        case ..<67:  return .rebuilding
        default:     return .middling
        }
    }

    static func lockerRoomBand(roster: [Player]) -> LockerRoomBand {
        let active = roster.filter { !$0.isRetired }
        guard !active.isEmpty else { return .steady }
        return LockerRoomBand.from(
            averageMorale: active.map(\.morale).reduce(0, +) / active.count
        )
    }

    // MARK: - Effect Resolution

    /// Per-axis clamp. The shipped content already ranges ±4…±20; context can
    /// move an answer inside that band but never outside it, so nothing
    /// downstream (owner satisfaction, `LegacyTracker.mediaReputation`, morale)
    /// sees a magnitude it was not tuned for.
    static let effectCeiling = 20
    static let effectFloor = -20

    /// THE one place an answer's real cost is computed. Both views call it, the
    /// summary calls it, and the reveal prints what it returned.
    static func resolvedEffects(
        for response: PressResponse,
        question: PressQuestion,
        context: PressContext
    ) -> PressEffects {
        let stance = stance(for: question)
        let tone = response.tone

        var owner = response.effects.ownerSatisfaction
        var morale = response.effects.playerMorale
        var media = response.effects.mediaPerception
        var fans = response.effects.fanExcitement

        for delta in [
            situationAdjustment(tone: tone, situation: context.situation),
            standingAdjustment(tone: tone, response: response, context: context),
            personaAdjustment(tone: tone, response: response, context: context),
            stanceAdjustment(tone: tone, stance: stance, situation: context.situation),
            lockerRoomAdjustment(tone: tone, band: context.lockerRoom),
        ] {
            owner += delta.ownerSatisfaction
            morale += delta.playerMorale
            media += delta.mediaPerception
            fans += delta.fanExcitement
        }

        // The repetition ratchet decays the UPSIDE only. Saying the same thing
        // for the fifth time does not become dangerous, it becomes worthless —
        // and then it earns a label (below).
        let scale = repetitionScale(tone: tone, recentTones: context.recentTones)
        if scale < 1.0 {
            owner = decay(owner, scale)
            morale = decay(morale, scale)
            media = decay(media, scale)
            fans = decay(fans, scale)
            if isVanilla(tone: tone, recentTones: context.recentTones) {
                media += vanillaMediaCost
            }
        }

        return PressEffects(
            ownerSatisfaction: clamp(owner),
            playerMorale: clamp(morale),
            mediaPerception: clamp(media),
            // Legacy is NOT context-modulated — see the file header.
            legacyPoints: response.effects.legacyPoints,
            fanExcitement: clamp(fans)
        )
    }

    private static func clamp(_ value: Int) -> Int {
        Swift.max(effectFloor, Swift.min(effectCeiling, value))
    }

    private static func decay(_ value: Int, _ scale: Double) -> Int {
        value > 0 ? Int((Double(value) * scale).rounded()) : value
    }

    // MARK: The matrix

    /// Tone × situation — the table in the file header, in code.
    static func situationAdjustment(
        tone: ResponseTone,
        situation: PressSituation
    ) -> PressEffects {
        switch situation {
        case .introduction:
            switch tone {
            case .confident:  return PressEffects(mediaPerception: 2, fanExcitement: 3)
            case .humble:     return PressEffects(ownerSatisfaction: 2, playerMorale: 2, fanExcitement: -2)
            case .aggressive: return PressEffects(playerMorale: -3, mediaPerception: 3)
            // The old dominant strategy. "There's talent here, we'll evaluate
            // everything" is the answer nobody remembers on day one.
            case .diplomatic: return PressEffects(mediaPerception: -5, fanExcitement: -6)
            case .funny:      return PressEffects(mediaPerception: -2, fanExcitement: 4)
            }

        case .afterWin:
            switch tone {
            case .confident:  return PressEffects(mediaPerception: 2, fanExcitement: 3)
            case .humble:     return PressEffects(playerMorale: 4, mediaPerception: 2)
            case .aggressive: return PressEffects(ownerSatisfaction: -2, playerMorale: -5, mediaPerception: 2)
            case .diplomatic: return PressEffects(mediaPerception: -4, fanExcitement: -3)
            case .funny:      return PressEffects(playerMorale: 3, mediaPerception: -2, fanExcitement: 5)
            }

        case .afterBadLoss:
            switch tone {
            // Sunny after a beating reads delusional. This is the cell the
            // playtest was missing.
            case .confident:  return PressEffects(ownerSatisfaction: -3, mediaPerception: -8, fanExcitement: -7)
            case .humble:     return PressEffects(ownerSatisfaction: 3, playerMorale: 5, mediaPerception: 6)
            case .aggressive: return PressEffects(playerMorale: -6, mediaPerception: 5, fanExcitement: 2)
            // Protects the room, bores the press — a real trade, not a free win.
            case .diplomatic: return PressEffects(mediaPerception: -5, fanExcitement: -4)
            case .funny:      return PressEffects(ownerSatisfaction: -4, playerMorale: -3, mediaPerception: -8, fanExcitement: -7)
            }

        case .crisis:
            switch tone {
            case .confident:  return PressEffects(ownerSatisfaction: 3, playerMorale: 6, mediaPerception: 2)
            // "We knew this might be a tough year" is not a plan.
            case .humble:     return PressEffects(ownerSatisfaction: -5, mediaPerception: 2, fanExcitement: -5)
            case .aggressive: return PressEffects(ownerSatisfaction: 4, playerMorale: -6, mediaPerception: 7)
            // Dodging a question that demanded a stance. The single hardest
            // punishment in the table, and the reason "always pick green" dies.
            case .diplomatic: return PressEffects(ownerSatisfaction: -4, mediaPerception: -10, fanExcitement: -6)
            case .funny:      return PressEffects(ownerSatisfaction: -5, mediaPerception: -7, fanExcitement: -4)
            }

        case .highStakes:
            switch tone {
            case .confident:  return PressEffects(mediaPerception: 4, fanExcitement: 5)
            case .humble:     return PressEffects(mediaPerception: -2, fanExcitement: -5)
            case .aggressive: return PressEffects(playerMorale: -4, mediaPerception: 5)
            case .diplomatic: return PressEffects(mediaPerception: -6, fanExcitement: -4)
            case .funny:      return PressEffects(ownerSatisfaction: -2, mediaPerception: -2, fanExcitement: 4)
            }

        case .routine:
            switch tone {
            case .confident:  return PressEffects(fanExcitement: 1)
            case .humble:     return PressEffects(ownerSatisfaction: 2, playerMorale: 2)
            case .aggressive: return PressEffects(playerMorale: -3, mediaPerception: 2)
            case .diplomatic: return PressEffects(mediaPerception: -2, fanExcitement: -2)
            case .funny:      return PressEffects(playerMorale: 2, mediaPerception: -1, fanExcitement: 3)
            }
        }
    }

    /// Team state vs what the answer claims. A championship promise is cheap
    /// talk on a 5-win roster and a statement of intent on a 12-win one.
    static func standingAdjustment(
        tone: ResponseTone,
        response: PressResponse,
        context: PressContext
    ) -> PressEffects {
        let claimsATitle = promiseKind(for: response) == .championship

        // A title claim on a roster that cannot get near one: the owner hears
        // an expectation he did not set and cannot meet. Applies to whichever
        // tone made the claim.
        if claimsATitle, context.standing == .rebuilding {
            return PressEffects(ownerSatisfaction: -6, mediaPerception: -3, fanExcitement: 2)
        }

        switch (tone, context.standing) {
        case (.confident, .rebuilding):
            return PressEffects(ownerSatisfaction: -2)
        case (.confident, .contender):
            return PressEffects(ownerSatisfaction: 2, fanExcitement: 2)
        // Humility on a loaded roster reads as a coach who does not believe.
        case (.humble, .contender):
            return PressEffects(ownerSatisfaction: -3, fanExcitement: -5)
        case (.humble, .rebuilding):
            return PressEffects(ownerSatisfaction: 3)
        case (.aggressive, .contender):
            return PressEffects(playerMorale: -4)
        case (.aggressive, .rebuilding):
            return PressEffects(ownerSatisfaction: 2, mediaPerception: 2)
        default:
            return PressEffects()
        }
    }

    /// The owner's known persona. Skipped for `.introduction` on purpose: the
    /// four intro questions already branch their base effects on
    /// `owner.prefersWinNow` (see `generateVisionQuestion`), and applying the
    /// persona twice would double-count it.
    static func personaAdjustment(
        tone: ResponseTone,
        response: PressResponse,
        context: PressContext
    ) -> PressEffects {
        guard context.situation != .introduction else { return PressEffects() }

        if context.ownerPrefersWinNow {
            switch tone {
            case .confident:  return PressEffects(ownerSatisfaction: 3)
            case .humble:     return PressEffects(ownerSatisfaction: -4)
            case .diplomatic: return PressEffects(ownerSatisfaction: -2)
            default:          return PressEffects()
            }
        }
        // A patient owner backing a plan. An impatient one (patience ≤ 3) is
        // still a builder, but a thinner-skinned one — the promise stings more.
        let claimSting = context.ownerPatience <= 3 ? -6 : -4
        switch tone {
        case .confident:
            return promiseKind(for: response) == nil
                ? PressEffects()
                : PressEffects(ownerSatisfaction: claimSting)
        case .humble:     return PressEffects(ownerSatisfaction: 3)
        case .aggressive: return PressEffects(ownerSatisfaction: -3)
        default:          return PressEffects()
        }
    }

    /// Hostile punishes evasion and rewards candor; friendly amplifies
    /// confidence and humor. `demandsAStance` doubles the evasion penalty —
    /// dodging a hard question in front of a hostile writer is the worst
    /// combination on the board.
    static func stanceAdjustment(
        tone: ResponseTone,
        stance: ReporterStance,
        situation: PressSituation
    ) -> PressEffects {
        switch stance {
        case .neutral:
            return PressEffects()
        case .hostile:
            switch tone {
            case .diplomatic, .funny:
                return PressEffects(mediaPerception: situation.demandsAStance ? -10 : -6)
            case .humble, .aggressive:
                return PressEffects(mediaPerception: 4)
            case .confident:
                return PressEffects(mediaPerception: -2, fanExcitement: 2)
            }
        case .friendly:
            switch tone {
            case .confident:  return PressEffects(mediaPerception: 3, fanExcitement: 3)
            case .funny:      return PressEffects(mediaPerception: 4, fanExcitement: 3)
            case .humble:     return PressEffects(mediaPerception: 2)
            case .aggressive: return PressEffects(mediaPerception: -2)
            case .diplomatic: return PressEffects()
            }
        }
    }

    /// A fragile room takes a whipping badly and an arm round the shoulder
    /// well; a buoyant one can absorb the whip.
    static func lockerRoomAdjustment(
        tone: ResponseTone,
        band: LockerRoomBand
    ) -> PressEffects {
        switch band {
        case .steady:
            return PressEffects()
        case .fragile:
            switch tone {
            case .aggressive: return PressEffects(playerMorale: -6)
            case .humble:     return PressEffects(playerMorale: 4)
            case .confident:  return PressEffects(playerMorale: 3)
            case .diplomatic: return PressEffects(playerMorale: 2)
            case .funny:      return PressEffects(playerMorale: 2)
            }
        case .buoyant:
            switch tone {
            case .aggressive: return PressEffects(playerMorale: 2)
            case .confident:  return PressEffects(playerMorale: 3)
            default:          return PressEffects()
            }
        }
    }

    // MARK: The repetition ratchet

    /// Extra media hit once a tone has become the coach's only note.
    static let vanillaMediaCost = -4

    /// How many times `tone` appears in the scored window.
    static func repetitionCount(tone: ResponseTone, recentTones: [ResponseTone]) -> Int {
        recentTones.prefix(toneRepetitionWindow).filter { $0 == tone }.count
    }

    /// Upside multiplier. Mirrors `ContractNegotiationEngine`'s pestering
    /// ratchet: the third repeat costs a third of the payoff, the fourth costs
    /// most of it.
    static func repetitionScale(tone: ResponseTone, recentTones: [ResponseTone]) -> Double {
        switch repetitionCount(tone: tone, recentTones: recentTones) {
        case 4...: return 0.40
        case 3:    return 0.65
        default:   return 1.0
        }
    }

    /// True once the press has a name for it.
    static func isVanilla(tone: ResponseTone, recentTones: [ResponseTone]) -> Bool {
        repetitionCount(tone: tone, recentTones: recentTones) >= 4
    }

    /// The label the press room hangs on a coach with one note.
    static func vanillaLabel(for tone: ResponseTone) -> String {
        switch tone {
        case .confident:  return "All bluster, every week"
        case .humble:     return "The same humble script"
        case .aggressive: return "Angry on a loop"
        case .diplomatic: return "Says nothing, beautifully"
        case .funny:      return "The bit is getting old"
        }
    }

    // MARK: - Fogged Preview

    /// One audience's readable direction. Never carries a number — that is the
    /// entire point.
    struct ReactionHint: Identifiable, Equatable {
        enum Audience: String, CaseIterable, Identifiable {
            case owner, lockerRoom, fans, media
            var id: String { rawValue }

            var label: String {
                switch self {
                case .owner:      return "Owner"
                case .lockerRoom: return "Locker room"
                case .fans:       return "Fans"
                case .media:      return "Media"
                }
            }

            var icon: String {
                switch self {
                case .owner:      return "building.2.fill"
                case .lockerRoom: return "person.3.fill"
                case .fans:       return "hands.clap.fill"
                case .media:      return "newspaper.fill"
                }
            }
        }

        enum Direction: String, Equatable {
            case up, down, neutral, unknown

            var glyph: String {
                switch self {
                case .up:      return "arrow.up"
                case .down:    return "arrow.down"
                case .neutral: return "minus"
                case .unknown: return "questionmark"
                }
            }
        }

        var id: String { audience.rawValue }
        let audience: Audience
        let direction: Direction
        /// Short qualitative phrase. "likely approves", "risky", "—".
        let phrase: String
    }

    /// What a card shows BEFORE the answer is committed.
    struct ReactionPreview: Equatable {
        let hints: [ReactionHint]
        /// The press already has a name for this note.
        let isVanilla: Bool
        let vanillaLabel: String?
    }

    /// Anything inside ±`hintDeadBand` reads as "no strong reaction" rather than
    /// as a direction — a 2-point nudge is not something a coach can feel.
    static let hintDeadBand = 3

    /// The fogged preview. Derived from the SAME resolution the commit will run,
    /// then coarsened to direction and gated by what the coach could plausibly
    /// read in this room.
    static func preview(
        for response: PressResponse,
        question: PressQuestion,
        context: PressContext
    ) -> ReactionPreview {
        let resolved = resolvedEffects(for: response, question: question, context: context)
        let stance = stance(for: question)

        // READABILITY GATES — the fog. An audience the coach cannot read shows
        // "—", not a guess.
        //   • Owner and locker room: always readable. He knows his boss's
        //     persona from the hiring meeting and he is in the building daily.
        //   • Fans: readable when the moment is loud enough to have a mood.
        //   • Media: readable when the reporter has declared a stance, or when
        //     the story writes itself (a crisis, a beating).
        let fansReadable = context.situation != .routine
        let mediaReadable = stance != .neutral || context.situation.demandsAStance

        func hint(_ audience: ReactionHint.Audience, _ delta: Int, readable: Bool) -> ReactionHint {
            guard readable else {
                return ReactionHint(audience: audience, direction: .unknown, phrase: "\u{2014}")
            }
            let direction: ReactionHint.Direction =
                delta > hintDeadBand ? .up : (delta < -hintDeadBand ? .down : .neutral)
            return ReactionHint(
                audience: audience,
                direction: direction,
                phrase: phrase(for: audience, direction: direction)
            )
        }

        return ReactionPreview(
            hints: [
                hint(.owner, resolved.ownerSatisfaction, readable: true),
                hint(.lockerRoom, resolved.playerMorale, readable: true),
                hint(.fans, resolved.fanExcitement, readable: fansReadable),
                hint(.media, resolved.mediaPerception, readable: mediaReadable),
            ],
            isVanilla: isVanilla(tone: response.tone, recentTones: context.recentTones),
            vanillaLabel: isVanilla(tone: response.tone, recentTones: context.recentTones)
                ? vanillaLabel(for: response.tone)
                : nil
        )
    }

    private static func phrase(
        for audience: ReactionHint.Audience,
        direction: ReactionHint.Direction
    ) -> String {
        switch (audience, direction) {
        case (.owner, .up):           return "likely approves"
        case (.owner, .down):         return "won't like it"
        case (.owner, .neutral):      return "no strong read"
        case (.lockerRoom, .up):      return "will back you"
        case (.lockerRoom, .down):    return "risky"
        case (.lockerRoom, .neutral): return "shrugs"
        case (.fans, .up):            return "will eat it up"
        case (.fans, .down):          return "will groan"
        case (.fans, .neutral):       return "muted"
        case (.media, .up):           return "good copy"
        case (.media, .down):         return "they'll pounce"
        case (.media, .neutral):      return "a shrug"
        case (_, .unknown):           return "\u{2014}"
        }
    }

    // MARK: - Session Feedback

    /// The running-impact verdict under the totals strip. It reads only
    /// ALREADY-COMMITTED deltas, so it is a readout, not a preview — but the
    /// thresholds that decide "Owner growing impatient" were a hand-copied
    /// table living in BOTH press views, which is precisely the drift this
    /// engine exists to end. The severity is an engine word; the two screens
    /// map it to a colour, because a colour is the one thing a view may own.
    struct SessionFeedback: Equatable {
        enum Severity: String, Equatable {
            case good, warning, bad, neutral
        }
        let text: String
        let icon: String
        let severity: Severity
    }

    /// Highlights the strongest signal first, then falls back to the net trend.
    static func sessionFeedback(for totals: PressEffects) -> SessionFeedback {
        let owner = totals.ownerSatisfaction
        let morale = totals.playerMorale
        let fans = totals.fanExcitement
        let media = totals.mediaPerception
        let net = owner + morale + fans + media

        if owner <= -8 {
            return SessionFeedback(
                text: "Owner growing impatient",
                icon: "exclamationmark.triangle.fill", severity: .bad)
        }
        if morale <= -10 {
            return SessionFeedback(
                text: "Locker room is restless",
                icon: "person.3.fill", severity: .bad)
        }
        if media >= 15 {
            return SessionFeedback(
                text: "Media buzzing \u{2014} you're driving headlines",
                icon: "newspaper.fill", severity: .warning)
        }
        if fans >= 15 {
            return SessionFeedback(
                text: "Fans are fired up",
                icon: "hands.clap.fill", severity: .good)
        }
        if owner >= 10 && morale >= 5 {
            return SessionFeedback(
                text: "Front office and locker room aligned",
                icon: "checkmark.seal.fill", severity: .good)
        }
        if net >= 10 {
            return SessionFeedback(
                text: "Landing well across the board",
                icon: "hand.thumbsup.fill", severity: .good)
        }
        if net <= -10 {
            return SessionFeedback(
                text: "Tough room \u{2014} losing them",
                icon: "hand.thumbsdown.fill", severity: .bad)
        }
        if net == 0 {
            return SessionFeedback(
                text: "Reporters waiting for a real take",
                icon: "ellipsis.circle.fill", severity: .neutral)
        }
        return SessionFeedback(
            text: "Steady so far",
            icon: "equal.circle.fill", severity: .neutral)
    }

    // MARK: - Promise Ledger (#161 D)

    /// A measurable claim the coach made at a podium, and whether the season
    /// backed it up. Career-scoped, JSON on `Career` (`pressPromiseLedger`) —
    /// the `announcedMilestoneKeys` storage precedent from #154.
    struct PressPromiseRecord: Codable, Identifiable, Equatable {

        /// v1 scope is deliberately three kinds, each with a threshold the
        /// season either clears or does not. No partial credit, no fuzz.
        enum Kind: String, Codable, Equatable {
            /// "Start planning the parade route." → win the Championship.
            case championship
            /// "We're here to compete." → reach the postseason.
            case playoffs
            /// "There are going to be a lot of changes." → beat last year's
            /// win total, or reach the postseason.
            case overhaul

            var shortLabel: String {
                switch self {
                case .championship: return "Championship"
                case .playoffs:     return "Playoffs"
                case .overhaul:     return "Big changes"
                }
            }

            /// What the season has to produce, in the coach's own words.
            var thresholdCopy: String {
                switch self {
                case .championship: return "Win the Championship this season."
                case .playoffs:     return "Reach the postseason this season."
                case .overhaul:     return "Improve on last season's win total."
                }
            }
        }

        let id: UUID
        let kind: Kind
        /// The line, verbatim. The payoff story quotes it back.
        let statement: String
        let season: Int
        var resolvedSeason: Int?
        var wasMet: Bool?

        init(
            id: UUID = UUID(),
            kind: Kind,
            statement: String,
            season: Int,
            resolvedSeason: Int? = nil,
            wasMet: Bool? = nil
        ) {
            self.id = id
            self.kind = kind
            self.statement = statement
            self.season = season
            self.resolvedSeason = resolvedSeason
            self.wasMet = wasMet
        }

        var isPending: Bool { wasMet == nil }
    }

    /// Does this answer commit to something measurable? Only the two tones that
    /// actually make claims can — a humble or diplomatic answer is, by
    /// construction, a refusal to promise anything.
    static func promiseKind(for response: PressResponse) -> PressPromiseRecord.Kind? {
        guard response.tone == .confident || response.tone == .aggressive else { return nil }
        let text = response.text.lowercased()

        if text.contains("championship") || text.contains("super bowl")
            || text.contains("parade") || text.contains("title") {
            return .championship
        }
        if text.contains("playoff") || text.contains("postseason") {
            return .playoffs
        }
        if text.contains("a lot of changes") || text.contains("complete overhaul")
            || text.contains("changes are coming") || text.contains("big changes") {
            return .overhaul
        }
        return nil
    }

    // MARK: - Commit

    /// Writes a finished conference into the career-scoped ledgers: the tone
    /// history the ratchet reads, and any promises the coach just made. Called
    /// by BOTH apply-sites so the two screens cannot book different things.
    static func commit(result: PressConferenceResult, to career: Career) {
        // Newest first, and the conference's own order preserved inside it.
        let tones = result.selectedResponses.map(\.tone).reversed()
        career.pressToneHistory = Array((Array(tones) + career.pressToneHistory).prefix(toneLedgerDepth))

        guard !result.promises.isEmpty else { return }
        var ledger = career.pressPromiseLedger
        for promise in result.promises {
            // One live promise per kind per season — repeating "parade route"
            // in three consecutive pressers is one broken promise, not three.
            guard !ledger.contains(where: {
                $0.kind == promise.kind && $0.season == promise.season && $0.isPending
            }) else { continue }
            ledger.append(promise)
        }
        career.pressPromiseLedger = ledger
    }

    // MARK: - Promise Resolution (the check site)

    /// Everything a season-end resolution produces. The caller owns the writes
    /// so this stays a pure function.
    struct PromiseSettlement {
        var news: [NewsItem] = []
        var inbox: [InboxMessage] = []
        var legacyDelta: Int = 0
        var mediaDelta: Int = 0
        var ownerDelta: Int = 0
        var resolved: [PressPromiseRecord] = []
    }

    /// Settle every pending promise made in `season`.
    ///
    /// ONE check site: `WeekAdvancer.recordSeasonSummary`, in the `.superBowl`
    /// phase — the only moment where the championship, the playoff run and the
    /// final record are all known at once, and already idempotent per season.
    ///
    /// A promise is settled at the end of the season it was made in. One-season
    /// horizon on purpose: "we're going to bring a championship to this city"
    /// said in year one and cashed in year six is not a promise, it is a hope.
    static func settlePromises(
        career: Career,
        season: Int,
        userWins: Int,
        userLosses: Int,
        priorSeasonWins: Int?,
        madePlayoffs: Bool,
        wonChampionship: Bool,
        teamName: String
    ) -> PromiseSettlement {
        var settlement = PromiseSettlement()
        var ledger = career.pressPromiseLedger
        guard !ledger.isEmpty else { return settlement }

        for index in ledger.indices where ledger[index].isPending && ledger[index].season <= season {
            let promise = ledger[index]
            let met: Bool
            switch promise.kind {
            case .championship: met = wonChampionship
            case .playoffs:     met = madePlayoffs
            case .overhaul:
                // Measurable, and measurable against something that exists:
                // last year's win column. With no prior season on record
                // (career year one), the postseason is the only honest bar.
                if let prior = priorSeasonWins { met = userWins > prior || madePlayoffs }
                else { met = madePlayoffs }
            }

            ledger[index].wasMet = met
            ledger[index].resolvedSeason = season
            settlement.resolved.append(ledger[index])

            let payoff = payoff(for: promise.kind, met: met)
            settlement.legacyDelta += payoff.legacy
            settlement.mediaDelta += payoff.media
            settlement.ownerDelta += payoff.owner

            settlement.news.append(NewsItem(
                headline: met
                    ? "\(teamName) deliver on the promise"
                    : "\(teamName) fall short of the promise",
                body: met
                    ? "Back at the podium this year, the head coach said: \u{201C}\(promise.statement)\u{201D} "
                        + "\(promise.kind.thresholdCopy.replacingOccurrences(of: " this season.", with: "")) — done. "
                        + "The quote holds up."
                    : "Back at the podium this year, the head coach said: \u{201C}\(promise.statement)\u{201D} "
                        + "The season ended \(userWins)-\(userLosses) without it. "
                        + "\(promise.kind.thresholdCopy) That was the bar he set himself.",
                category: .award,
                week: 22,
                season: season,
                relatedTeamID: career.teamID,
                sentiment: met ? .positive : .negative
            ))

            if !met {
                settlement.inbox.append(InboxMessage(
                    sender: .media(outlet: "The Gridiron Weekly"),
                    subject: "About that quote",
                    body: "You said it in a press conference this season: \u{201C}\(promise.statement)\u{201D} "
                        + "\(promise.kind.thresholdCopy) It did not happen. "
                        + "We are running the quote next to the final standings. No comment needed.",
                    date: "Season \(season) review",
                    category: .mediaRequest
                ))
            }
        }

        career.pressPromiseLedger = ledger
        return settlement
    }

    /// Magnitudes sit in the same ±4…±25 neighbourhood as the achievements
    /// `LegacyTracker` already books, so a promise is a season-scale event and
    /// not a career-scale one.
    private static func payoff(
        for kind: PressPromiseRecord.Kind,
        met: Bool
    ) -> (legacy: Int, media: Int, owner: Int) {
        switch (kind, met) {
        case (.championship, true):  return (25, 12, 6)
        case (.championship, false): return (-15, -10, -8)
        case (.playoffs, true):      return (12, 8, 4)
        case (.playoffs, false):     return (-8, -6, -5)
        case (.overhaul, true):      return (8, 6, 3)
        case (.overhaul, false):     return (-6, -5, -4)
        }
    }
}
