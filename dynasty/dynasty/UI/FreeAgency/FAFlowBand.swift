import SwiftUI

// MARK: - FAFlowBand — free agency's five steps, on the shared spine
//
// UI_REDESIGN_VISION §2.1 names "free agency waves (`FreeAgencyStep`)" as one of
// the six scales `DSSlatBand` was built for, and §4 wave 3 asks for the process
// to mount the band. This is that binding, in one place, because free agency is
// **five separate screens** — `FinalPushView`, `NewLeagueYearView`,
// `CapComplianceView`, `FAWeeklyView`, `FACompleteView` — routed by
// `CareerShellView` off `Career.freeAgencyStep`. Before this, none of the five
// said where in the run it stood, so a user dropped onto Cap Compliance by the
// shell had no way to know that two steps were behind him and two ahead.
//
// **One band, one count.** §2.1's rule that a process prints its stage count
// exactly once is the reason the head owns "STEP 4 OF 5" and no screen repeats
// it. `FAWeeklyView`'s six market days are NOT a second band: they are the
// resource the signing step spends, so they are the head's meter — a filled pip
// is a spent day — and the day name rides the current slat's sub-caption. That
// collapses what used to be four separate printings of the round (a title, a
// six-dot rail, a "Day N" header and the submit button's label) into the band
// plus the one place a commit is allowed to name its destination.
//
// The band is deliberately **not** navigable: `FreeAgencyStep` is advanced by
// the engine and by each screen's own commit, and a slat that looked tappable
// but silently refused would be worse than one that does not. `onSelect` is nil,
// so every slat is a disabled button and reads as one.

enum FAFlowBand {

    /// The run, in order. `FreeAgencyStep` itself is a persisted raw-value enum
    /// with no ordering, so the order lives here rather than being inferred from
    /// declaration order somewhere it could be reshuffled by a migration.
    static let steps: [FreeAgencyStep] = [
        .finalPush, .newLeagueYear, .capReview, .signing, .complete
    ]

    static func title(_ step: FreeAgencyStep) -> String {
        switch step {
        case .finalPush:     return "Final Push"
        case .newLeagueYear: return "New League Year"
        case .capReview:     return "Cap Review"
        case .signing:       return "Signing"
        case .complete:      return "Complete"
        }
    }

    /// What each step is for, on the slat the club is standing on.
    static func subcaption(_ step: FreeAgencyStep) -> String {
        switch step {
        case .finalPush:     return "Re-sign your own before the market opens"
        case .newLeagueYear: return "Contracts roll over"
        case .capReview:     return "Get legal before you can bid"
        case .signing:       return "Bid against the league"
        case .complete:      return "The market is shut"
        }
    }

    /// Position of `step` in the run, or nil for a value the run does not carry.
    static func index(of step: FreeAgencyStep) -> Int? {
        steps.firstIndex(of: step)
    }

    /// The head's left-hand line — **the one place the flow prints its count.**
    static func headline(current: FreeAgencyStep) -> String {
        guard let i = index(of: current) else { return "Free agency" }
        return "Free agency \u{00B7} Step \(i + 1) of \(steps.count)"
    }

    /// The slats.
    ///
    /// - Parameters:
    ///   - current: the step the club is standing on.
    ///   - currentSubcaption: overrides the current slat's stock sub-caption, so
    ///     the signing step can say which market day it is on without a second
    ///     component printing the day.
    ///   - outcomes: what a finished step produced, keyed by step. §2.1's `done`
    ///     row is "check glyph + the outcome"; a step with nothing worth
    ///     reporting simply gets the check.
    static func slats(
        current: FreeAgencyStep,
        currentSubcaption: String? = nil,
        outcomes: [FreeAgencyStep: String] = [:]
    ) -> [DSSlat] {
        let currentIndex = index(of: current) ?? 0
        return steps.enumerated().map { i, step in
            let state: DSSlat.State = i < currentIndex ? .done : (i == currentIndex ? .current : .future)
            return DSSlat(
                id: step.rawValue,
                index: "\(i + 1)",
                title: title(step),
                subcaption: state == .current ? (currentSubcaption ?? subcaption(step)) : nil,
                state: state,
                // A future FA step is reachable in principle but never actable
                // out of order, so nothing is ever raised to `isAvailable`.
                outcome: outcomes[step],
                accessibilityText: accessibilityText(
                    step: step,
                    position: i + 1,
                    state: state,
                    subcaption: state == .current ? (currentSubcaption ?? subcaption(step)) : nil,
                    outcome: outcomes[step]
                )
            )
        }
    }

    private static func accessibilityText(
        step: FreeAgencyStep,
        position: Int,
        state: DSSlat.State,
        subcaption: String?,
        outcome: String?
    ) -> String {
        let stateWord: String
        switch state {
        case .done:    stateWord = "complete"
        case .current: stateWord = "current step"
        case .future:  stateWord = "not started"
        case .locked:  stateWord = "locked"
        }
        return [
            "Free agency step \(position) of \(steps.count)",
            title(step),
            stateWord,
            outcome,
            subcaption
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }
}

// MARK: - The view every free-agency screen mounts

/// The band as the five FA screens use it: pinned above their content, never
/// inside the scroll, so the spine cannot scroll away from the user the way
/// draft prep's advance button used to (§2.5).
struct FAFlowBandView: View {

    let step: FreeAgencyStep
    /// Overrides the current slat's sub-caption — see `FAFlowBand.slats`.
    var currentSubcaption: String?
    var outcomes: [FreeAgencyStep: String] = [:]
    var meter: DSResourceMeter?

    var body: some View {
        DSSlatBand(
            slats: FAFlowBand.slats(
                current: step,
                currentSubcaption: currentSubcaption,
                outcomes: outcomes
            ),
            headline: FAFlowBand.headline(current: step),
            meter: meter
        )
        .padding(.horizontal, DSSpacing.md)
        .padding(.top, DSSpacing.xs)
        .padding(.bottom, DSSpacing.xs)
        .background(Color.backgroundPrimary)
    }
}

// MARK: - Preview

#Preview("Signing") {
    ZStack(alignment: .top) {
        Color.backgroundPrimary.ignoresSafeArea()
        FAFlowBandView(
            step: .signing,
            currentSubcaption: "Day 3 \u{00B7} Mid-tier FAs settle",
            outcomes: [.finalPush: "4 re-signed", .capReview: "Legal"],
            meter: DSResourceMeter(spent: 3, total: 6, unit: "market days")
        )
    }
}

#Preview("Cap review") {
    ZStack(alignment: .top) {
        Color.backgroundPrimary.ignoresSafeArea()
        FAFlowBandView(step: .capReview, outcomes: [.finalPush: "4 re-signed"])
    }
}
