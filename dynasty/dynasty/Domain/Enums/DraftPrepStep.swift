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
enum DraftPrepStep: String, Codable, CaseIterable {
    /// Combine numbers + the reports the previous autumn filed.
    case combineReview  = "CombineReview"
    /// TAPE — spends `ScoutEvaluationBudget` slots (#79's economy, unchanged).
    case filmStudy      = "FilmStudy"
    /// MEET — spends `career.interviewsUsed`.
    case interviews     = "Interviews"
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
    var order: Int { DraftPrepStep.allCases.firstIndex(of: self) ?? 0 }

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
        let all = DraftPrepStep.allCases
        let idx = order + 1
        return idx < all.count ? all[idx] : nil
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
