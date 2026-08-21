import Foundation

// MARK: - Deterministic pick helper

/// Stable pick from `options` driven by the coach's UUID — same coach, same
/// persona, every game and every screen.
///
/// Shared by all three coaching personas (`HCPersona` here, `DCPersona` and
/// `OCPersona` in `Engine/Match/CoordinatorPersona.swift`). Internal rather than
/// file-private for exactly that reason: two copies of a hash function are two
/// chances for the personas a player is shown to stop matching the ones the
/// engine plays.
func stablePersonaPick<T>(_ options: [T], id: UUID) -> T {
    let hash = id.uuidString.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }
    let index = ((hash % options.count) + options.count) % options.count
    return options[index]
}

// MARK: - Head Coach Persona (F-17 / D5-A)

/// The head coach's situational risk tolerance — the thing that decides whether
/// a club goes for it on 4th-and-2 from the opponent's 38, and whether it
/// remembers to take the knee with a lead and 1:20 left.
///
/// **Why this exists.** `GamePlan` has a `fourthDownAggressiveness` slider and
/// every write site in the repo was a SwiftUI view, so all 31 AI clubs went into
/// every game with `gamePlan: nil` and `PlaySimulator.decidePlayCall`'s two
/// `if let plan` branches were structurally unreachable for them. The resulting
/// AI 4th-down table went for it only on 4th-and-≤2 inside the opponent's 5, or
/// in a last-two-minutes desperation window — **zero** attempts between the
/// opponent's 6 and midfield, where the real 4th-and-1 attempt rate is 48.6 %.
///
/// **Why personas and not one better number.** The ruling (D5) is explicit that
/// the goal is not a better AI but a DIFFERENT one: real head coaches vary about
/// **threefold** in 4th-down aggression and most are measurably too conservative,
/// so a league where every club makes the EV-optimal call is *less* realistic
/// than one containing coaches who punt too much. The error therefore has to be
/// a property of the man — planned, persistent, and the same every week — and
/// never a die rolled at the moment of decision (D3's refinement, property 2).
///
/// Derivation mirrors ``DCPersona/derive(for:)``: the two rating fields decide
/// the corners, a stable id hash breaks the mixed middle. The middle is where
/// most coaches land (ratings cluster at 70), so the hash does real work and the
/// persona is deliberately NOT a clean proxy for coach quality — an orthodox
/// coach is not a bad coach, he is a coach who kicks.
///
/// **`twoPointBias` is deliberately absent.** F-17 specifies a third field, a
/// ±1 "chart-row shift" on `GameSimulator.shouldGoForTwo`. That chart is an
/// irregular, calibrated row set (`-16, -13, -11, -8, -5, -2, 1, 5`) on the DO
/// NOT TOUCH list, and every mechanical reading of "shift it by a row" either
/// moves the decision sideways without changing aggression at all (evaluating
/// the chart at `diff ± 1` yields the same eight rows, just different ones) or
/// requires hand-picking which rows to add and drop — which is rewriting the
/// chart, the one thing the ruling forbids. Two-point tries are also far too
/// rare to separate from noise in an 800-game campaign, so the change could not
/// be verified even if it were designed. Left out pending a specified mapping;
/// `fourthDownAggressiveness` carries the whole of D5-A's character return.
enum HCPersona: String, CaseIterable {
    /// Goes for it past midfield on 4th-and-short. The analytics-forward coach.
    case riverboat = "Riverboat"
    /// Today's league-median behaviour: situational, neither gambler nor kicker.
    case modern    = "Modern"
    /// The book coach — takes the points, makes them drive the field.
    case orthodox  = "Orthodox"
    /// Kicks and punts on principle. Historically the most common NFL coach and
    /// the one the engine could not previously represent at all.
    case punter    = "Punter"

    var displayName: String { rawValue }

    // MARK: Derivation

    /// The rating either field must reach to read as "above average". 70 is the
    /// engine-wide neutral point every other coaching channel is centred on
    /// (`CoachingModifiers`, `AdaptiveOpponentAI.counterShare`), so reusing it
    /// keeps one definition of an average coach in the codebase.
    private static let ratingPivot = 70

    /// Deterministic persona for a head coach. Adaptable **and** a sharp
    /// play-caller reads as a riverboat; neither reads as a punter; the mixed
    /// pair — one high, one low, which is most of the league — is broken by the
    /// stable id hash so the persona never collapses into a competence ladder.
    static func derive(for coach: Coach) -> HCPersona {
        let adaptable = coach.adaptability >= ratingPivot
        let sharp = coach.playCalling >= ratingPivot
        switch (adaptable, sharp) {
        case (true, true):   return .riverboat
        case (false, false): return .punter
        default:             return stablePersonaPick([.modern, .orthodox], id: coach.id)
        }
    }

    /// Persona for a club with no head-coach record. Every shipped club has one,
    /// so this is reached only by the balance harness's coachless tier rosters —
    /// but it matters that it is reached, because a club that drew no persona
    /// would silently measure as the old `nil` game plan and the harness would
    /// report this whole change as a no-op. Seeded from the club id, so it is
    /// stable per team and uniform across the league.
    /// Written as an explicit `if let` rather than `headCoach.map(derive(for:))`:
    /// passing an actor-isolated method as a closure VALUE strips its isolation
    /// and warns under Swift 6, while calling it directly inherits the caller's.
    static func derive(headCoach: Coach?, teamID: UUID) -> HCPersona {
        if let headCoach { return derive(for: headCoach) }
        return stablePersonaPick(HCPersona.allCases, id: teamID)
    }

    // MARK: Decision fields

    /// The value written into the `GamePlan.fourthDownAggressiveness` slot.
    ///
    /// The two consumer branches in `PlaySimulator.decidePlayCall` are gated at
    /// `< 0.35` (kick/punt even on 4th-and-short) and `> 0.65` (go for it on
    /// 4th-and-≤3 once past midfield), so these four numbers straddle both gates
    /// deliberately: `riverboat` clears the upper gate, `punter` falls through
    /// the lower one, and `modern` / `orthodox` sit between them and reproduce
    /// the pre-persona `nil` behaviour exactly. That is the threefold real-world
    /// spread, bought without touching either branch's own logic — which is what
    /// F-17 asks for, and it is why the two middle archetypes are not spaced
    /// evenly: their job is to be the unchanged control group.
    ///
    /// Trades against: scoring. A riverboat club converts more short fourth
    /// downs (real 4th-and-1 conversion is 71.3 %) and also hands the opponent a
    /// short field when it fails, so the two largely cancel in points per
    /// team-game — which is the band this was measured against.
    var fourthDownAggressiveness: Double {
        switch self {
        case .riverboat: return 0.85
        case .modern:    return 0.60
        case .orthodox:  return 0.40
        case .punter:    return 0.15
        }
    }

    /// Chance per eligible decision that the coach botches an endgame clock
    /// call — fails to take the knee that ends the game, or leaves a timeout in
    /// his pocket. Scaled at the call site by `1 + leverageIndex`, so the
    /// mistake is likeliest in exactly the moment it costs the most, which is
    /// how clock blunders actually happen.
    ///
    /// Trades against: how often the AI gives a won game back. Three kneel-down
    /// dropbacks at ~2.3 % INT each is a ~7 % giveback, so a `punter` at 0.35
    /// scaled by `1 + leverage` fails to kneel in roughly half of one-score
    /// fourth quarters — both a real error rate and correct football history.
    /// Held below 0.40 because above that the archetype stops reading as a coach
    /// with a philosophy and starts reading as a broken engine.
    var clockErrorRate: Double {
        switch self {
        case .riverboat: return 0.10
        case .modern:    return 0.15
        case .orthodox:  return 0.25
        case .punter:    return 0.35
        }
    }

    /// The AI club's offensive game plan for a game: the persona's 4th-down
    /// tolerance and **nothing else**.
    ///
    /// Every other slider is pinned at the neutral 0.5 on purpose.
    /// `decidePlayCall` derives `planPassBias` from `runPassRatio − 0.5`, so a
    /// persona that also carried a run/pass lean would shift the play mix of all
    /// 31 clubs in the same commit that changed their 4th-down behaviour, and
    /// the two effects could not be told apart in the harness. Run/pass identity
    /// already has an owner — the OC's scheme, through `schemeOnlyPassBias` —
    /// and duplicating it on the head coach would double-count it.
    var gamePlan: GamePlan {
        GamePlan(
            offensiveAggression: 0.5,
            defensiveAggression: 0.5,
            runPassRatio: 0.5,
            blitzFrequency: 0.5,
            fourthDownAggressiveness: fourthDownAggressiveness
        )
    }

    // MARK: Presentation

    /// Week Prep scouting line (GamePlanView opponent panel).
    var scoutingBlurb: String {
        switch self {
        case .riverboat: return "Goes for it. Fourth-and-short is a green light."
        case .modern:    return "Plays the situation — takes what the math offers."
        case .orthodox:  return "By the book. Takes the points when they're there."
        case .punter:    return "Kicks and punts. Won't hand you a short field."
        }
    }

    /// Pre-kickoff booth intel line for the broadcast feed.
    func broadcastIntro(abbr: String) -> String {
        switch self {
        case .riverboat: return "\(abbr)'s head coach is a riverboat gambler — fourth down means nothing to him"
        case .modern:    return "\(abbr)'s head coach plays the percentages down to down"
        case .orthodox:  return "\(abbr)'s head coach is old school — he'll take the three"
        case .punter:    return "\(abbr)'s head coach will punt it. He always punts it"
        }
    }
}
