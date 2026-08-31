import SwiftUI

// MARK: - First-Run Tips (R37)

/// One-time onboarding hints, each backed by a UserDefaults flag.
/// A tip renders until the player taps "Got it" (or finishes/skips a tour),
/// then never again — unless Settings → "Reset Tips" clears the flags.
enum FirstRunTip: String, CaseIterable {
    /// Multi-card tour on the first Career Dashboard open.
    case dashboardTour = "tip.dashboardTour.done"
    /// 3-step walkthrough at the first coached-game offensive snap window.
    case coachFirstSnap = "tip.coachFirstSnap.done"
    /// One-line banner on the first 4th-down decision panel.
    case fourthDown = "tip.fourthDown.done"
    /// One-line banner on the first XP / two-point choice panel.
    case twoPointTry = "tip.twoPointTry.done"
    /// One-line banner the first time the AUDIBLE button is available.
    case audible = "tip.audible.done"
    /// One rookie-GM mistake, on the closing screen of the intro sequence.
    /// The line itself comes from ``RookieGMTip``.
    ///
    /// **Scoped to a CAREER, not to the install** — the one tip here that is.
    /// ``RookieGMTip/pool`` exists so a second career opens on a line the first
    /// never showed, and a single global bool made every career after the first
    /// show nothing at all: the per-career draw was dead code the moment the
    /// banner was dismissed once. Read it through ``FirstRunTip/rookieGMSeen(career:)``
    /// and write it through ``FirstRunTip/markRookieGMSeen(career:)``; this case
    /// stays in `allCases` so "Reset Tips" still names it, and its own bool flag
    /// is simply not the flag the banner consults.
    case rookieGM = "tip.rookieGM.done"

    var isDone: Bool {
        UserDefaults.standard.bool(forKey: rawValue)
    }

    func markDone() {
        UserDefaults.standard.set(true, forKey: rawValue)
    }

    /// Careers that have already been shown their rookie-GM tip (#3008).
    ///
    /// One key holding a list of career ids rather than a key per career, so
    /// ``resetAll()`` clears every save's in the same one line the other tips
    /// take and nothing accumulates keys a career deletion would orphan.
    private static let rookieGMSeenKey = "tip.rookieGM.doneCareers"

    private static func rookieGMSeenCareers() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: rookieGMSeenKey) ?? [])
    }

    /// Has this career already dismissed its rookie-GM tip?
    static func rookieGMSeen(career id: UUID) -> Bool {
        rookieGMSeenCareers().contains(id.uuidString)
    }

    static func markRookieGMSeen(career id: UUID) {
        var seen = rookieGMSeenCareers()
        seen.insert(id.uuidString)
        UserDefaults.standard.set(seen.sorted(), forKey: rookieGMSeenKey)
    }

    /// Settings → "Reset Tips": every one-time hint shows again.
    static func resetAll() {
        for tip in allCases {
            UserDefaults.standard.removeObject(forKey: tip.rawValue)
        }
        // The rookie-GM tip's real flag is the per-career list, not the bool
        // above — clearing only the loop would leave every career still marked.
        UserDefaults.standard.removeObject(forKey: rookieGMSeenKey)
    }
}

// MARK: - Rookie-GM Tips (#3008)

/// The pool the intro's closing screen draws one line from — one mistake a
/// first-time GM makes, picked per career and then never seen again.
///
/// **Every line is about THIS game's engine**, not general football wisdom, and
/// every number in one is traced to the function that PRODUCES it at runtime —
/// which is not always the exported constant that names it. Two of these were
/// quoting a league-mean rail nothing in the market consults, and a third called
/// two age schedules identical where they deliberately diverge; where the
/// runtime answer is a band rather than a number, the line states the band —
/// which is also what #2987 asked copy to do. The sources, in order:
///
/// 1. `FreeAgencyEngine.capReserve(forTeam:)` — the reserve every AI club
///    actually holds, 0.08 / 0.14 / 0.15 / 0.18 by GM archetype. NOT
///    `capReservePercent` (0.15): that is the superseded league-average rail,
///    read by nothing in the market, and quoting it meant a retune of the
///    function moved the game and not the copy. The band cannot be
///    interpolated — the function is keyed on a team id — so the two figures
///    below are written out and must be changed with that switch.
/// 2. `FreeAgencyEngine.simulateAIFreeAgency` — `CoachingEngine.developmentAppeal`
///    (0.85-1.15) weights which club a free agent picks off his shortlist.
/// 3. `FreeAgencyEngine.marketAgeDiscountFrom` / `marketAgeDiscountPerYear`, whose
///    rate and start age `RosterValue.agePenaltyPerYear` / `agePenaltyFrom` match
///    exactly — but the CAPS differ on purpose (`RosterValue.agePenaltyCap` 20 vs
///    `marketAgeDiscountCap` 14, "set ABOVE the market's 14 … deliberately"), so
///    cutdown day goes on docking after the market has stopped. The line says so
///    rather than claiming the two are identical, which they are not at the age
///    the line itself names.
/// 4. `ContractEngine.impliedDeadCap` — `impliedGuaranteeRate` (0.15) times
///    `clubGuaranteeLean(forTeam:)` (0.72-1.30), i.e. 10.8 %-19.5 % a year by
///    archetype and never a flat 15 for anybody; the line rounds that band
///    outward to 11-20. Same "cannot be interpolated" note as 1: change the band
///    with that switch. `CampRosterEngine.campContractYears` is 1, so a camp
///    body's release still books nothing at all.
/// 5. `FreeAgencyEngine.ownCoreRetentionsPerClub` — an AI club keeps that many of
///    its own before the market opens, out of a cohort of ~30 expiring deals.
///
/// A pool and not one fixed line so a second career opens on something new: the
/// "seen" flag is per career (``FirstRunTip/rookieGMSeen(career:)``), which is
/// what makes that sentence true — a single global bool would have retired the
/// whole pool on the first dismissal. The draw is off the career's own id, so it
/// is stable for that save and cannot re-roll on a redraw.
enum RookieGMTip {

    static let pool: [LocalizedStringKey] = [
        "Don't spend to the last dollar in March. Rival clubs hold 8-18 % of the cap back for the draft class and the men who replace the injured — the boldest front offices keep the least, and those bills arrive whether anyone budgeted for them or not.",
        "Hire the coordinators before the market opens. Their schemes decide who actually fits your roster, and a staff with a reputation for developing players pulls free agents your way.",
        "Age is priced twice. The market marks a free agent down for every year past \(FreeAgencyEngine.marketAgeDiscountFrom), and your own cutdown day docks him from the same age at the same rate — and keeps docking after the market has stopped. The cheap 30-year-old is cheap for a reason.",
        "Cutting a veteran is not free: a release books dead money at 11-20 % of his salary for every year left on the deal, depending on how freely that front office guarantees money. A camp body on a one-year minimum is the man you can afford to be wrong about.",
        "Re-sign your own before free agency. A rival club keeps up to \(FreeAgencyEngine.ownCoreRetentionsPerClub) of its own men off the market; anyone you leave unsigned is out there bidding against 31 other front offices.",
    ]

    /// The line this career gets — the same one every time it is asked.
    ///
    /// Seeded off the career id rather than `randomElement()`, for the reason
    /// the intro's confetti is seeded off a flake index: a draw inside a
    /// SwiftUI `body` re-rolls on every redraw, so the tip would change while
    /// the player was reading it.
    static func line(forCareer id: UUID) -> LocalizedStringKey {
        let seed = id.uuid.0 &+ id.uuid.7 &+ id.uuid.15
        return pool[Int(seed) % pool.count]
    }
}

// MARK: - Coach Mark Step

/// One card of a sequenced coach-mark tour.
struct CoachMarkStep {
    let icon: String
    let title: String
    let text: String
}

// MARK: - Coach Mark Overlay

/// Lightweight sequenced walkthrough card. It never blocks the screen —
/// only the card itself is hit-testable, everything behind it stays live.
/// Drive it with an optional step index: non-nil shows that step, and the
/// overlay sets it back to nil (calling `onComplete`) on Skip / Got it.
struct CoachMarkOverlay: View {

    let steps: [CoachMarkStep]
    @Binding var step: Int?
    /// Called exactly once when the tour ends (finished or skipped) —
    /// the caller marks the matching `FirstRunTip` flag here.
    let onComplete: () -> Void

    private var index: Int { min(step ?? 0, steps.count - 1) }
    private var isLast: Bool { index == steps.count - 1 }

    var body: some View {
        let current = steps[index]
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.accentGold.opacity(0.16))
                        .frame(width: 38, height: 38)
                    Image(systemName: current.icon)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.accentGold)
                }
                Text(current.title)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Color.textPrimary)
                Spacer(minLength: 0)
                if steps.count > 1 {
                    Text("\(index + 1)/\(steps.count)")
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                        .foregroundStyle(Color.textTertiary)
                }
            }

            Text(current.text)
                .font(.system(size: DSType.Size.body, weight: .medium))
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                // Step dots
                HStack(spacing: 5) {
                    ForEach(0..<steps.count, id: \.self) { dot in
                        Circle()
                            .fill(dot == index ? Color.accentGold : Color.textTertiary.opacity(0.4))
                            .frame(width: 6, height: 6)
                    }
                }
                Spacer()
                if !isLast {
                    Button {
                        finish()
                    } label: {
                        Text("Skip")
                            .font(.system(size: DSType.Size.body, weight: .semibold))
                            .foregroundStyle(Color.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    if isLast {
                        finish()
                    } else {
                        withAnimation(.easeInOut(duration: 0.2)) { step = index + 1 }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(isLast ? "Got it" : "Next")
                            .font(.system(size: DSType.Size.body, weight: .heavy))
                        if !isLast {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .black))
                        }
                    }
                    .foregroundStyle(Color.backgroundPrimary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(Color.accentGold, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: 420)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.backgroundSecondary)
                .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.accentGold.opacity(0.5), lineWidth: 1)
        )
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(current.title). \(current.text)")
    }

    private func finish() {
        withAnimation(.easeInOut(duration: 0.2)) { step = nil }
        onComplete()
    }
}

// MARK: - Tip Banner

/// One-line contextual hint with a "Got it" dismissal — used for the first
/// 4th-down call, the first XP/two-point choice, and the first audible.
struct TipBanner: View {

    let icon: String
    /// R38: localized key so tip copy picks up catalog translations.
    let text: LocalizedStringKey
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.accentGold)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(action: onDismiss) {
                Text("Got it")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Color.accentGold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.accentGold.opacity(0.14), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.accentGold.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.accentGold.opacity(0.3), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}
