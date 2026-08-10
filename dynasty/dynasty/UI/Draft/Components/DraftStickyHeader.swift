import SwiftUI

// MARK: - DraftStickyHeader — the room's chrome (#105 Wave 3b)
//
// UI_REDESIGN_VISION §3 family 8: "It needs the pick band on top of its
// text-only 'ROUND 2 — Pick 14/32'."
//
// That line is gone. `DraftPickBand`'s head is now **the one place the draft
// prints its count** (P1), and the header keeps only the three things the band
// cannot say: who is on the clock, how long they have, and what this club still
// needs. Three rows before, three rows after — the counter row was traded for
// the ribbon, so the panels below lose ~56 pt rather than ~90.
//
// Gold discipline (P5): gold has exactly three jobs, and one of them is named
// in the vision by hand — "the live/now indicator (**the draft clock**, an open
// FA wave)". So the clock is the gold on this surface and nothing else here is:
// the needs strip used to paint five chips in `draftStealGold` at five
// opacities, and the "your pick is close" line used to turn gold too.

struct DraftStickyHeader: View {
    @ObservedObject var coordinator: DraftDayCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: DSSpacing.sm) {
                onTheClockText
                Spacer(minLength: DSSpacing.sm)
                clockBadge
            }

            // The pick band. `.equatable()` is load-bearing, not tidy:
            // `clockSeconds` republishes once a second, and without the gate the
            // ribbon's `GeometryReader` + `ScrollViewReader` + nine
            // parallelograms are re-laid-out on every tick. See `DraftPickBand`.
            DraftPickBand(model: DraftPickBand.Model(coordinator: coordinator))
                .equatable()

            HStack(alignment: .center, spacing: DSSpacing.sm) {
                userNextPickInfo
                Spacer(minLength: DSSpacing.sm)
                if !coordinator.teamNeedScores.isEmpty {
                    teamNeedsStrip
                }
            }
        }
        .padding(DSSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.backgroundSecondary)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.surfaceBorder).frame(height: 1)
        }
    }

    // MARK: - Who is on the clock

    private var onTheClockText: some View {
        Group {
            if let pick = coordinator.currentPick,
               let team = coordinator.teamsByID[pick.currentTeamID] {
                if coordinator.isUserOnClock {
                    Text("You are on the clock")
                        .font(DSType.display(DSType.Size.title2, .black))
                        .tracking(1.0)
                        .foregroundStyle(Color.textPrimary)
                } else {
                    Text("On the clock: \(team.fullName)")
                        .font(DSType.display(DSType.Size.title2, .heavy))
                        .tracking(0.8)
                        .foregroundStyle(Color.textPrimary)
                }
            } else {
                Text("Draft")
                    .font(DSType.display(DSType.Size.title2, .heavy))
                    .tracking(0.8)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .lineLimit(1)
    }

    /// Gold's third job, and the only gold on this surface.
    private var clockBadge: some View {
        let urgent = coordinator.clockSeconds <= 30
        return HStack(spacing: DSSpacing.xxs) {
            Image(systemName: "timer")
                .font(DSType.display(DSType.Size.title3, .heavy))
            Text("\(coordinator.clockSeconds)s")
                .font(DSType.display(DSType.Size.title1, .black))
        }
        .foregroundStyle(urgent ? Color.dangerText : Color.accentGold)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(coordinator.clockSeconds) seconds on the clock")
    }

    // MARK: - Your own cards

    private var userNextPickInfo: some View {
        let picksAway = coordinator.picksUntilUserPick
        let closing = picksAway > 0 && picksAway <= 3
        // `picksUntilUserPick` returns -1 and `nextUserPickNumber` returns nil
        // once his card count is spent, which the old format string printed
        // literally: "Your next pick: #0 (-1 picks away)" after the last pick of
        // the draft (task #153d). No turns left is its own sentence.
        let text: String = {
            guard let next = nextUserPickNumber(), picksAway >= 0 else {
                return "No picks remaining"
            }
            if picksAway == 0 { return "You are on the clock \u{2014} #\(next)" }
            let away = picksAway == 1 ? "1 pick away" : "\(picksAway) picks away"
            return "Your next pick #\(next) \u{00B7} \(away) \u{00B7} \(coordinator.userPicksRemaining) remaining"
        }()
        return Text(text)
            .font(DSType.text(14, .semibold))
            // Urgency is orange, not gold (P7's semantic hue separation: at
            // 11-14 pt `warning` and `accentGold` are the same hue, and gold
            // one row under the gold clock would read as a second clock).
            .foregroundStyle(closing ? Color.alertOrange : Color.textSecondary)
            .lineLimit(1)
    }

    private func nextUserPickNumber() -> Int? {
        guard let teamID = coordinator.userTeamID else { return nil }
        return coordinator.picks
            .dropFirst(coordinator.currentPickIndex)
            .first(where: { $0.currentTeamID == teamID })?.pickNumber
    }

    // MARK: - Needs

    /// Five positions, **in order of need**, as `DSStatusPill`s at stated
    /// thresholds (P7 rule 2).
    ///
    /// They used to be gold chips at five different opacities — a continuous
    /// colour ramp with no legend, on the one hue that already has three jobs,
    /// encoding a 0–1 score nobody could read off it. The severity now has two
    /// channels that both survive a screenshot: the left-to-right ORDER, and
    /// three tones at thresholds written down here.
    private var teamNeedsStrip: some View {
        let needs = coordinator.teamNeedScores
            .sorted { $0.value > $1.value }
            .prefix(5)
        return HStack(spacing: DSSpacing.xxs) {
            Text("NEEDS")
                .font(DSType.display(11, .heavy))
                .tracking(0.7)
                .foregroundStyle(Color.textSecondary)
                .padding(.trailing, DSSpacing.xxs)
            ForEach(Array(needs), id: \.key) { entry in
                DSStatusPill(
                    label: entry.key.rawValue,
                    tone: tone(for: entry.value),
                    showsDot: false,
                    spokenLabel: "\(entry.key.rawValue), \(spokenNeed(entry.value)) need"
                )
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    /// The thresholds, stated once. `teamNeedScores` runs roughly 0.2…1.0.
    private func tone(for score: Double) -> DSStatusPill.Tone {
        if score >= 0.75 { return .bad }
        if score >= 0.50 { return .warn }
        return .neutral
    }

    private func spokenNeed(_ score: Double) -> String {
        if score >= 0.75 { return "urgent" }
        if score >= 0.50 { return "clear" }
        return "minor"
    }
}
