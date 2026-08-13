import SwiftUI

// MARK: - Stage copy

/// The half of the explainer that is presentation, not economy.
///
/// What a stage REVEALS lives on ``DraftPrepStep/unlocksExplainer`` — the same
/// sentence has to be true on the stage tab, in the task description and in the
/// skip confirmation, so it belongs to the domain and there is exactly one copy
/// of it. What survives here is the icon, the one-line framing and the price,
/// which are this screen's business and nobody else's.
struct DraftPrepStageCopy {
    let icon: String
    /// One line: what this stage IS.
    let headline: String
    /// What it spends — slots, budget, or nothing.
    let cost: String

    static func copy(for step: DraftPrepStep) -> DraftPrepStageCopy {
        switch step {
        case .combineReview:
            return DraftPrepStageCopy(
                icon: "stopwatch",
                headline: "Read Indianapolis before you spend a dollar.",
                cost: "Free to read. The department trip is priced against the scouting budget and is a one-window offer."
            )
        case .interviews:
            return DraftPrepStageCopy(
                icon: "bubble.left.and.bubble.right.fill",
                headline: "Put a man in a room and ask him.",
                cost: "One of \(DraftPrepProgress.interviewSlots) formal interview slots per cycle. No money."
            )
        case .filmStudy:
            return DraftPrepStageCopy(
                icon: "film.fill",
                headline: "Your scouts grind the tape you tell them to.",
                cost: "One of \(ScoutEvaluationBudget.slotsPerCycle) evaluation slots and a fee against the scouting budget, per report."
            )
        case .proDayFocus:
            return DraftPrepStageCopy(
                icon: "mappin.and.ellipse",
                headline: "Pick the campuses your people actually stand on.",
                cost: "One focus slot per school. Slots are your scouts' attention, not cash."
            )
        case .workouts:
            return DraftPrepStageCopy(
                icon: "figure.strengthtraining.traditional",
                headline: "Your building, your coordinators, one prospect.",
                cost: "One of \(DraftPrepProgress.workoutSlots) workout slots per cycle."
            )
        case .mockOne:
            return DraftPrepStageCopy(
                icon: "doc.text",
                headline: "Where the league has your board.",
                cost: "Nothing. It is printed whether you read it or not."
            )
        case .top30Visits:
            return DraftPrepStageCopy(
                icon: "building.2.fill",
                headline: "Thirty men in the facility.",
                cost: "One of \(DraftPrepProgress.top30Slots) visit slots per cycle."
            )
        case .mockTwo:
            return DraftPrepStageCopy(
                icon: "doc.text.fill",
                headline: "The final mock, printed with the order.",
                cost: "Nothing. Reading it closes the spring."
            )
        case .ready:
            return DraftPrepStageCopy(
                icon: "flag.checkered",
                headline: "The board is closed.",
                cost: "\u{2014}"
            )
        }
    }
}

// MARK: - Explainer card

/// The card every stage screen opens with.
///
/// It answers the one question the shipped wizard never answered: *what does
/// this stage put on a prospect, and what does it cost me*. Expanded by default
/// per stage, collapsed with one tap, and the preference is remembered per stage
/// so a user who already knows what interviews do is not told nine more times.
struct DraftPrepStageExplainer: View {
    let step: DraftPrepStep
    let state: DraftPrepStageCell.State
    /// "12 of 25 reports filed" — the stage's own count, in words.
    var counterText: String?
    /// One clause naming what opens a locked stage.
    var lockReason: String = ""
    /// What still has to happen before the club may advance out of this stage.
    var requirement: String = ""
    /// `true` when the stage is shut by the SEASON rather than by the club's own
    /// work — `DraftPrepProgress.Stage.isCalendarLocked`.
    ///
    /// The card is otherwise a set of instructions, and instructions over a
    /// stage that does not exist this week are what #107 reports: "Open the
    /// Combine tab and read the numbers" printed above a combine that has not
    /// been held. A wait is not a chore, so it loses the counter pill and says
    /// WAITING rather than LOCKED — nothing here is anybody's fault.
    var isWaitingOnCalendar: Bool = false

    @AppStorage private var isExpanded: Bool

    init(
        step: DraftPrepStep,
        state: DraftPrepStageCell.State,
        counterText: String? = nil,
        lockReason: String = "",
        requirement: String = "",
        isWaitingOnCalendar: Bool = false
    ) {
        self.step = step
        self.state = state
        self.counterText = counterText
        self.lockReason = lockReason
        self.requirement = requirement
        self.isWaitingOnCalendar = isWaitingOnCalendar
        // Per-stage key: collapsing the interview explainer must not collapse
        // the workout one, and the flag has to survive leaving the screen.
        _isExpanded = AppStorage(wrappedValue: true, "prepExplainerOpen_\(step.rawValue)")
    }

    private var copy: DraftPrepStageCopy { DraftPrepStageCopy.copy(for: step) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerRow
            if isExpanded {
                Text(step.unlocksExplainer)
                    .font(.system(size: DSType.Size.caption))
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: "creditcard")
                        .font(.system(size: DSType.Size.micro))
                        .foregroundStyle(Color.textTertiaryReadable)
                    Text(copy.cost)
                        .font(.system(size: DSType.Size.micro))
                        .foregroundStyle(Color.textTertiaryReadable)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if state == .locked, !lockReason.isEmpty {
                    // The lock sentence REPLACES the requirement line. A stage
                    // the club cannot enter has no target, and printing one is
                    // how the February hub ended up telling a user to go read
                    // combine numbers that did not exist.
                    statusLine(
                        icon: isWaitingOnCalendar ? "calendar.badge.clock" : "lock.fill",
                        tint: .warning,
                        text: lockReason
                    )
                } else if state == .done {
                    // ONE STAGE-COMPLETE VISUAL (#105 wave 0). This used to draw
                    // a green "Stage complete" seal one row under a band whose
                    // `done` slat — check glyph, top rule, outcome — already
                    // makes the claim. What is left here is the only part the
                    // band cannot say: that the room is still open to walk into,
                    // and that its priced actions are not.
                    statusLine(
                        icon: "eye",
                        tint: .textSecondary,
                        text: "Open for review \u{2014} its priced actions are shut."
                    )
                } else if state == .open {
                    // Says only what is true of BOTH open cases — the stages
                    // behind the club, which never shut, and the next room,
                    // which `reach` opens as soon as this stage is satisfied.
                    // The old sentence promised "doing the work here moves the
                    // department onto this stage" over screens whose buttons
                    // were dead; `DraftPrepProgress.canAct` now decides both the
                    // puck and the buttons, so the promise is kept.
                    statusLine(
                        icon: "arrow.right.circle.fill",
                        tint: .accentBlue,
                        text: "Open \u{2014} this stage is workable right now."
                    )
                } else if !requirement.isEmpty {
                    statusLine(icon: "target", tint: .accentGold, text: requirement)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: DSCornerRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: DSCornerRadius.card)
                .strokeBorder(borderTint, lineWidth: 1)
        )
    }

    private var borderTint: Color {
        switch state {
        case .current: return Color.accentGold.opacity(0.30)
        case .open:    return Color.accentBlue.opacity(0.25)
        case .done:    return Color.surfaceBorder.opacity(0.7)
        case .locked:  return Color.surfaceBorder.opacity(0.5)
        }
    }

    private var headerRow: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: copy.icon)
                    .font(.system(size: DSType.Size.caption))
                    .foregroundStyle(state == .locked ? Color.textTertiaryReadable : Color.accentGold)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        // No state chip. The band's slat carries the state in
                        // three channels at once, one row above this card; a
                        // CURRENT/DONE/OPEN/LOCKED capsule here was a second
                        // rendering of it — and the gold CURRENT fill was a
                        // third gold on the screen (#105 wave 0, P5/P7).
                        Text(step.displayName.uppercased())
                            .font(.system(size: DSType.Size.micro, weight: .black))
                            .foregroundStyle(state == .locked ? Color.textTertiaryReadable : Color.accentGold)
                    }
                    Text(copy.headline)
                        .font(.system(size: DSType.Size.caption, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(isExpanded ? 2 : 1)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                // No counter over a wait: "Opens at combine" in a pill next to
                // a WAITING chip says the same thing twice, and a "0/60" pill
                // says a ration is being spent in a stage that is not open.
                if let counterText, !isWaitingOnCalendar {
                    Text(counterText)
                        .font(.system(size: DSType.Size.micro, weight: .heavy).monospacedDigit())
                        .foregroundStyle(Color.textPrimary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.backgroundTertiary, in: Capsule())
                }

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: DSType.Size.micro, weight: .bold))
                    .foregroundStyle(Color.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(step.displayName) explainer. \(isExpanded ? "Collapse" : "Expand")")
    }

    private func statusLine(icon: String, tint: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: DSType.Size.micro))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: DSType.Size.micro, weight: .semibold))
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Advance bar (deleted)
//
// `DraftPrepAdvanceBar` lived here: a bespoke bottom bar with its own gold
// recipe, its own corner radius and its own two-line skip chip. Wave 0 of #105
// moved the hub's commit onto the shared `DSActionBar` (§2.5): one explainer
// slot, one ghost carrying the hub's single skip, one gold primary, and a
// genuinely grey disabled state instead of dimmed gold. See
// `ScoutingHubView.advanceBar`.
