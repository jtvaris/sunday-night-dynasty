import Foundation

/// Where in the pre-draft process this club is.
///
/// The prep spans three phases (`combine → freeAgency → proDays → draft`) and
/// until now nothing inside them said what the club had already done: the hub
/// showed nine tabs in every phase, private workouts — the most rationed
/// instrument in the game — were live on the first day the class existed, and
/// the required-task chain only covered the combine.
///
/// Shaped exactly like ``FreeAgencyStep``: a persisted raw string on ``Career``,
/// one required task per stage, one advance button that writes the next step.
/// Earlier stages stay viewable and read-only; every stage is skippable, none
/// silently so.
///
/// **Read it through `Career.prepStep`, never off `draftPrepStep` directly** —
/// the accessor carries the cycle stamp and the phase floor.
/// ## Case order is the pipeline; raw values are the save format
///
/// `order` is `allCases` position, so **reordering the cases reorders the
/// pipeline** and every `order`-based comparison in the app moves with it. The
/// raw strings are what a save carries, so they must never change.
///
/// **Migration note — v2 swapped `interviews` ahead of `filmStudy`** (they were
/// `combineReview → filmStudy → interviews` when #103 shipped in d1fadd0).
/// Interviews are the cheap, high-volume instrument the class starts with; tape
/// is what you order once you know who you want to look at.
///
/// A save stamped `"FilmStudy"` under the old order therefore reads one stage
/// LATER now (old order 1 → new order 2), i.e. it reads as "interviews already
/// behind us". That is safe by construction and deliberately not special-cased:
///
/// * an earlier stage is never CLOSED — `DraftPrepProgress` unlocks every stage
///   at or before the club's reach, so the interviews surface such a save
///   skipped past is still fully workable (this is the B3 fix);
/// * `Career.prepStep`'s evidence floor re-derives the stage from what the club
///   has actually done, so a save that had in fact conducted interviews lands on
///   `.interviews` or later from its own data rather than from the stamp;
/// * the required-task chain, not the stage, is what gates the phase advance.
///
/// The mirror case — a save stamped `"Interviews"` (old order 2 → new order 1) —
/// re-opens film study, which is an offer, not a loss.
enum DraftPrepStep: String, Codable, CaseIterable {
    /// Combine numbers + the reports the previous autumn filed.
    case combineReview  = "CombineReview"
    /// MEET — spends `career.interviewsUsed`.
    case interviews     = "Interviews"
    /// TAPE — spends `ScoutEvaluationBudget` slots (#79's economy, unchanged).
    case filmStudy      = "FilmStudy"
    /// Pick the schools. Everybody else's numbers arrive at broadcast precision.
    case proDayFocus    = "ProDayFocus"
    /// Private workouts, results in a modal. `career.workoutsUsed`.
    case workouts       = "Workouts"
    /// League event: the post-tour mock.
    case mockOne        = "MockOne"
    /// Facility visits — the last instrument before the draft.
    case top30Visits    = "Top30Visits"
    /// League event: the final mock.
    case mockTwo        = "MockTwo"
    /// Draft room unlocked.
    case ready          = "Ready"

    /// Position in the pipeline. Comparisons are always `order`-based so a case
    /// can be inserted later without every call site changing shape.
    ///
    /// Written out rather than derived from `allCases.firstIndex` because the
    /// process view reads it once per stage per body evaluation and
    /// `allCases` allocates a fresh array on every call.
    /// **Must stay in lockstep with the declaration order above.**
    var order: Int {
        switch self {
        case .combineReview: return 0
        case .interviews:    return 1
        case .filmStudy:     return 2
        case .proDayFocus:   return 3
        case .workouts:      return 4
        case .mockOne:       return 5
        case .top30Visits:   return 6
        case .mockTwo:       return 7
        case .ready:         return 8
        }
    }

    /// Human-readable stage name for the banner and the prep card.
    var displayName: String {
        switch self {
        case .combineReview: return "Combine Review"
        case .filmStudy:     return "Film Study"
        case .interviews:    return "Interviews"
        case .proDayFocus:   return "Pro Day Focus"
        case .workouts:      return "Private Workouts"
        case .mockOne:       return "Mock 1.0"
        case .top30Visits:   return "Top-30 Visits"
        case .mockTwo:       return "Final Mock"
        case .ready:         return "Ready"
        }
    }

    /// The phase this stage belongs to.
    ///
    /// `.freeAgency` is deliberately absent: the market has its own step machine
    /// and the prep stage is frozen while it runs.
    var phase: SeasonPhase {
        switch self {
        case .combineReview, .filmStudy, .interviews:
            return .combine
        case .proDayFocus, .workouts, .mockOne, .top30Visits, .mockTwo:
            return .proDays
        case .ready:
            return .draft
        }
    }

    /// Task title the stage's advance button is gated on.
    ///
    /// Compared against ``GameTask/matchKey``, never against `title` — the
    /// generator is free to decorate a title with a live counter
    /// (`"Conduct prospect interviews (12/60 done)"`), and matching the
    /// decorated string is exactly the bug `matchKey` exists to prevent.
    var requiredTaskKey: String? {
        switch self {
        case .combineReview: return "Review Combine results"
        case .filmStudy:     return "Order film study on your board"
        case .interviews:    return "Conduct prospect interviews"
        case .proDayFocus:   return "Choose pro-day schools"
        case .workouts:      return "Invite prospects to work out"
        case .mockOne:       return "Read the mock"
        case .top30Visits:   return "Host Top-30 visits"
        case .mockTwo:       return "Read the final mock"
        case .ready:         return nil
        }
    }

    /// The stage after this one, or `nil` at the end of the pipeline.
    var next: DraftPrepStep? {
        DraftPrepStep.allCases.first { $0.order == order + 1 }
    }

    /// The stage before this one, or `nil` at the head of the pipeline.
    var previous: DraftPrepStep? {
        DraftPrepStep.allCases.first { $0.order == order - 1 }
    }

    /// What working this stage puts on a prospect that was not there before —
    /// the one-line explainer every stage tab opens with.
    ///
    /// Lives on the enum, not in the view, because it is a statement about the
    /// intel economy: the same sentence has to be true on the stage tab, in the
    /// task description and in the skip confirmation.
    var unlocksExplainer: String {
        switch self {
        case .combineReview:
            return "Testing numbers and the media's read of them. Exact times for the men your department watched in Indianapolis, rounded broadcast numbers for everybody else."
        case .interviews:
            return "Fifteen minutes in a room. Reveals football IQ, personality and the character flags no workout shows \u{2014} the widest net in the spring, and the cheapest."
        case .filmStudy:
            return "Tape. A filed scouting report narrows a man's rating band and raises your confidence in it; three reports is as close to the truth as your building gets."
        case .proDayFocus:
            return "The schools you travel to. Exact decimals, a filed report and a face-to-face at those campuses \u{2014} broadcast precision everywhere else."
        case .workouts:
            return "A private session with your coaching staff. The highest-fidelity look in the game, and the most rationed: it re-measures a man against your scheme."
        case .mockOne:
            return "Where the league has your board after the pro-day circuit. Shows the consensus, and the gaps between it and your own ranking."
        case .top30Visits:
            return "Thirty men in your building. Opens medical and character files, and the rest of the league sees who walks in."
        case .mockTwo:
            return "The last mock printed before the draft order. Your final read on who will actually be there when you pick."
        case .ready:
            return "The board is closed and the room is open. Everything you bought this spring is on the card."
        }
    }

    /// The stage a task belongs to, matched on ``GameTask/matchKey``.
    ///
    /// One lookup table instead of a `switch` per call site, so the shell, the
    /// task panel and the hub cannot disagree about which task owns a stage.
    static func stage(forTaskKey key: String) -> DraftPrepStep? {
        taskKeyIndex[key]
    }

    private static let taskKeyIndex: [String: DraftPrepStep] = {
        var map: [String: DraftPrepStep] = [:]
        for step in DraftPrepStep.allCases {
            if let key = step.requiredTaskKey { map[key] = step }
        }
        return map
    }()
}

// MARK: - Phase floor

extension SeasonPhase {

    /// The earliest prep stage a club sitting in this phase can honestly be in.
    ///
    /// The floor is what makes in-flight saves safe. A save written before the
    /// stage machine existed carries `draftPrepStepSeason == 0`, so the stored
    /// step reads as `.combineReview` — and a save parked in `.proDays` would
    /// find the pro-day surface locked behind stages it can no longer reach.
    /// The phase already proves the club got there, so it raises the floor.
    ///
    /// `.freeAgency` deliberately does NOT raise it: the market is not part of
    /// the prep pipeline, and a club that skipped straight through the combine
    /// really is still at `.combineReview` when free agency opens.
    var minimumPrepStep: DraftPrepStep {
        switch self {
        case .proDays: return .proDayFocus
        case .draft:   return .ready
        default:       return .combineReview
        }
    }

    /// The furthest stage a club sitting in this phase may be derived into.
    ///
    /// The mirror of ``minimumPrepStep``, and the reason the evidence floor in
    /// ``Career/prepStep`` cannot run ahead of the season. `career.workoutsUsed`
    /// is a per-cycle counter that is only zeroed at kickoff, so a club standing
    /// in the combine with last spring's workouts still on the clock would
    /// otherwise be derived straight into `.workouts` — a pro-day stage, in
    /// February, with the pro-day tab open.
    ///
    /// A stored step is NOT clamped by this: only the derivation is. The hub's
    /// own advance button already refuses to cross a phase boundary
    /// (`ScoutingStageGate.isPhaseBlocked`), and lowering a stored step here
    /// would fight ``Career/advancePrepStep(to:)``'s never-lower rule.
    var maximumPrepStep: DraftPrepStep {
        switch self {
        // The last stage of the combine block. Free agency freezes the prep,
        // so a club standing in the market keeps the combine stages it is in
        // and gets no further.
        case .combine, .freeAgency: return .filmStudy
        case .proDays:              return .mockTwo
        case .draft:                return .ready
        // Outside the four pre-draft phases there is no pipeline at all.
        default:                    return .combineReview
        }
    }

    /// Where this phase sits on the **draft-prep calendar**, for the cap that
    /// stops the stage machine running ahead of the season.
    ///
    /// `SeasonPhase.allCases` is declaration order, not the calendar's cyclic
    /// order: `regularSeason` is index 12 and `draft` is index 7, so an
    /// `allCases.firstIndex` comparison read November as "later than the draft"
    /// and let eight taps on Skip walk a club to `.ready` — "the board is
    /// closed, draft" — in week 9, with every stage tab open.
    ///
    /// Only the four pre-draft phases carry a rank. Everything else is `0`, i.e.
    /// **below the first stage**, so no stage at all can be advanced into from
    /// outside the window. `.freeAgency` ranks between the combine and the pro
    /// days because the prep is frozen there (the market has its own step
    /// machine) but the combine stages the club is standing in stay workable.
    var prepCalendarRank: Int {
        switch self {
        case .combine:    return 1
        case .freeAgency: return 2
        case .proDays:    return 3
        case .draft:      return 4
        default:          return 0
        }
    }
}
