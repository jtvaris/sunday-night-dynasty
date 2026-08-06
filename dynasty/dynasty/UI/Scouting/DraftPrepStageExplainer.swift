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
                    statusLine(
                        icon: "checkmark.seal.fill",
                        tint: .success,
                        text: "Stage complete \u{2014} open for review. Its priced actions are shut."
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
                        Text(step.displayName.uppercased())
                            .font(.system(size: DSType.Size.micro, weight: .black))
                            .foregroundStyle(state == .locked ? Color.textTertiaryReadable : Color.accentGold)
                        stateChip
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
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(step.displayName) explainer. \(isExpanded ? "Collapse" : "Expand")")
    }

    @ViewBuilder
    private var stateChip: some View {
        switch state {
        case .current:
            chip("CURRENT", fill: .accentGold, ink: .backgroundPrimary)
        case .done:
            chip("DONE", fill: .success, ink: .backgroundPrimary)
        case .open:
            chip("OPEN", fill: .accentBlue, ink: .backgroundPrimary)
        case .locked:
            // Same chip styling either way — a wait is drawn locked. Only the
            // word changes: LOCKED reads as "you have not got here yet", which
            // is untrue of a club standing in November.
            chip(isWaitingOnCalendar ? "WAITING" : "LOCKED",
                 fill: .backgroundTertiary, ink: .textTertiaryReadable)
        }
    }

    private func chip(_ text: String, fill: Color, ink: Color) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .black))
            .foregroundStyle(ink)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(fill))
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

// MARK: - Advance bar

/// The stage's forward transition, pinned to the bottom of the hub.
///
/// It used to live in `ScoutingHubHeader`, i.e. inside the Big Board list's
/// FIRST SECTION — a 12 pt greyed button that scrolled away with the header. On
/// a brand-new career that button was the only exit from stage 1, and finding it
/// required scrolling back up a 350-row list. That is the whole of bug B3: film
/// study was not broken, it was three taps behind a control the user could not
/// see. A transition is the most important thing on a process screen, so it gets
/// the bottom bar and it states its own requirement.
struct DraftPrepAdvanceBar: View {
    let stepName: String
    let nextName: String?
    /// What the user still has to do, in one sentence.
    let requirement: String
    /// What walking past this stage costs him.
    let skipCost: String
    let isComplete: Bool
    let isBlocked: Bool
    let blockedReason: String
    /// `false` for the stages whose own screen owns the transition (the pro-day
    /// tour spends its reservations *in* the advance) — then the bar routes to
    /// that screen instead of transitioning.
    let ownsTransition: Bool
    var onAdvance: () -> Void
    var onSkip: () -> Void
    var onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(isBlocked ? blockedReason : requirement)
                .font(.system(size: DSType.Size.micro, weight: .semibold))
                .foregroundStyle(isBlocked ? Color.textTertiaryReadable : Color.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                if let nextName {
                    if ownsTransition {
                        primary(
                            title: "Advance \u{2014} \(nextName)",
                            enabled: isComplete && !isBlocked,
                            action: onAdvance
                        )
                        skipButton
                    } else {
                        primary(title: "Open \(stepName)", enabled: !isBlocked, action: onOpen)
                    }
                } else {
                    primary(title: "The board is closed", enabled: false, action: {})
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.backgroundSecondary)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.surfaceBorder).frame(height: 1)
        }
    }

    private func primary(title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: DSType.Size.footnote, weight: .bold))
                .foregroundStyle(enabled ? Color.backgroundPrimary : Color.textTertiary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    enabled ? Color.accentGold : Color.backgroundTertiary,
                    in: RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityHint(enabled ? requirement : (isBlocked ? blockedReason : requirement))
    }

    @ViewBuilder
    private var skipButton: some View {
        if !isBlocked {
            Button(action: onSkip) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Skip this stage")
                        .font(.system(size: DSType.Size.caption, weight: .semibold))
                        .foregroundStyle(Color.textSecondary)
                    Text(skipCost)
                        .font(.system(size: 9))
                        .foregroundStyle(Color.textTertiaryReadable)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: DSCornerRadius.inline))
                .overlay(
                    RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                        .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Skip \(stepName). \(skipCost)")
        }
    }
}
