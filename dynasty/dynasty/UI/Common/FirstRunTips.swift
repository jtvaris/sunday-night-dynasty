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
    case rookieGM = "tip.rookieGM.done"

    var isDone: Bool {
        UserDefaults.standard.bool(forKey: rawValue)
    }

    func markDone() {
        UserDefaults.standard.set(true, forKey: rawValue)
    }

    /// Settings → "Reset Tips": every one-time hint shows again.
    static func resetAll() {
        for tip in allCases {
            UserDefaults.standard.removeObject(forKey: tip.rawValue)
        }
    }
}

// MARK: - Rookie-GM Tips (#3008)

/// The pool the intro's closing screen draws one line from — one mistake a
/// first-time GM makes, picked per career and then never seen again.
///
/// **Every line is about THIS game's engine**, not general football wisdom, and
/// every number in one is interpolated from the constant that produces it so the
/// advice cannot outlive the balance it describes. The sources, in order:
///
/// 1. `FreeAgencyEngine.capReservePercent` — the reserve exists because the
///    draft class and the in-season refill cost a measured 6.6 % of cap that
///    nothing asks permission for.
/// 2. `FreeAgencyEngine.simulateAIFreeAgency` — `CoachingEngine.developmentAppeal`
///    (0.85-1.15) weights which club a free agent picks off his shortlist.
/// 3. `FreeAgencyEngine.marketAgeDiscountFrom` / `marketAgeDiscountPerYear`, which
///    match `RosterValue.keepScore`'s rate exactly — the market and cutdown day
///    ask the same question the same way.
/// 4. `ContractEngine.impliedGuaranteeRate` — a release books that share of the
///    salary for every year left; `CampRosterEngine.campContractYears` is 1 and a
///    camp body's release books nothing at all.
/// 5. `FreeAgencyEngine.ownCoreRetentionsPerClub` — an AI club keeps that many of
///    its own before the market opens, out of a cohort of ~30 expiring deals.
///
/// A pool and not one fixed line so a second career opens on something new; the
/// draw is off the career's own id, so it is stable for that save and cannot
/// re-roll on a redraw.
enum RookieGMTip {

    static let pool: [LocalizedStringKey] = [
        "Don't spend to the last dollar in March. Rival clubs hold back about \(Int(FreeAgencyEngine.capReservePercent * 100)) % of the cap for the draft class and the men who replace the injured — those bills arrive whether you budgeted for them or not.",
        "Hire the coordinators before the market opens. Their schemes decide who actually fits your roster, and a staff with a reputation for developing players pulls free agents your way.",
        "Age is priced twice. The market marks a free agent down for every year past \(FreeAgencyEngine.marketAgeDiscountFrom), and your own cutdown day marks him down at exactly the same rate — the cheap 30-year-old is cheap for a reason.",
        "Cutting a veteran is not free: a release books dead money at roughly \(Int(ContractEngine.impliedGuaranteeRate * 100)) % of his salary for every year left on the deal. A camp body on a one-year minimum is the man you can afford to be wrong about.",
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
