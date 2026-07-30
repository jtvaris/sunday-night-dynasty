import Foundation

// MARK: - Trade Window Rules (Wave 3)
//
// The user-facing screens' side of the Wave 2 market calendar. `TradeValueEngine`
// owns the rules (`MarketWindow`, `rosterBounds(for:)`); this maps the career's
// phase/week onto them so the Trade Center and the negotiation screen validate
// against the SAME bounds the AI-vs-AI market does.
//
// The bug this closes (task #25): every user-facing `validationErrors` call took
// the defaults — an in-season roster ceiling of 75 and a floor of 40 — in every
// window. In the offseason that is not a rule anywhere: between the draft and
// cutdown day a club legitimately carries 80-90 players, and between the last
// game and free agency it legitimately sits in the low 30s. So the Trade Center
// vetoed deals in exactly the windows the league does most of its business in,
// while the AI market next door executed the same deals happily.
enum TradeWindowRules {

    /// The market window the career is standing in right now.
    ///
    /// `.regularSeason` past the deadline week reads as `.deadline` rather than
    /// `.week(n)` so a career that reaches the deadline without the phase flag
    /// having flipped still gets deadline-week treatment — the window rule
    /// (`isTradeWindowOpen`) already treats them the same way.
    static func window(phase: SeasonPhase, week: Int) -> TradeValueEngine.MarketWindow {
        switch phase {
        case .regularSeason:
            return week >= TradeValueEngine.deadlineWeek ? .deadline : .week(week)
        case .tradeDeadline:
            return .deadline
        default:
            return .offseason(phase)
        }
    }

    /// Roster bounds a deal in this window must respect.
    static func rosterBounds(phase: SeasonPhase, week: Int) -> (floor: Int, ceiling: Int) {
        TradeValueEngine.rosterBounds(for: window(phase: phase, week: week))
    }

    /// When an offer left on the desk stops being worth anything, in words.
    /// Shown as a chip on every open negotiation so a thread the user is
    /// sitting on carries its own deadline.
    static func expiryNote(phase: SeasonPhase, week: Int) -> String {
        switch phase {
        case .regularSeason, .tradeDeadline:
            let remaining = TradeValueEngine.deadlineWeek - week
            if remaining <= 0 {
                return "Expires when this week ends — the deadline is here"
            }
            if remaining == 1 {
                return "Expires at the Week \(TradeValueEngine.deadlineWeek) deadline — one week left"
            }
            return "Expires at the Week \(TradeValueEngine.deadlineWeek) deadline"
        case .playoffs, .proBowl, .superBowl:
            return "Trade window is closed until the new league year"
        default:
            return "Open through the offseason — expires when the season starts"
        }
    }
}
