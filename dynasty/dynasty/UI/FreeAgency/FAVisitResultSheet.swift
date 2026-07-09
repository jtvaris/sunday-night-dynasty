import SwiftUI

// MARK: - Visit Outcome (R23)

/// Everything the front office learns from hosting a free agent on a visit.
struct FAVisitOutcome: Identifiable {
    let id: UUID              // player id
    let playerName: String
    let position: String
    let overall: Int
    let age: Int
    let askingPrice: Int      // thousands/yr
    let motivation: Motivation
    let preferences: [PlayerPreferenceTag]
    let roleNote: String
    let breakdown: SigningInterestEngine.Breakdown
}

// MARK: - FAVisitResultSheet

/// R23 — shown after hosting a free agent at the facility. The visit burns one
/// of the 3 per-phase visit slots, permanently boosts signing interest, and
/// reveals the player's true decision drivers.
struct FAVisitResultSheet: View {

    let outcome: FAVisitOutcome
    let visitsRemaining: Int

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        headerCard
                        interestCard
                        prioritiesCard
                        footerNote
                    }
                    .padding(24)
                    .frame(maxWidth: 500)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Facility Visit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.accentGold)
                }
            }
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "building.2.crop.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.accentGold)
            Text("\(outcome.playerName) toured the facility")
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.center)
            HStack(spacing: 8) {
                Text(outcome.position)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentBlue, in: RoundedRectangle(cornerRadius: 4))
                Text("\(outcome.overall) OVR")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.forRating(outcome.overall))
                Text("Age \(outcome.age)")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                Text("Asking \(formatMillions(outcome.askingPrice))/yr")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.accentGold)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.accentGold.opacity(0.4), lineWidth: 1))
    }

    // MARK: - Interest

    private var interestCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "gauge.with.needle")
                    .font(.caption)
                    .foregroundStyle(Color.accentGold)
                Text("Signing Interest")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Text("+ visit boost")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.success)
            }

            InterestMeterBar(breakdown: outcome.breakdown)

            Text("The visit left an impression — his camp will remember it when offers land.")
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
        }
        .padding(16)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.surfaceBorder, lineWidth: 1))
    }

    // MARK: - Revealed Priorities

    private var prioritiesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "eye.fill")
                    .font(.caption)
                    .foregroundStyle(Color.accentBlue)
                Text("What He's Really Looking For")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
            }

            priorityRow(
                icon: motivationIcon(outcome.motivation),
                title: motivationTitle(outcome.motivation),
                detail: motivationDetail(outcome.motivation),
                tint: .accentGold
            )

            ForEach(outcome.preferences, id: \.self) { pref in
                priorityRow(
                    icon: pref.revealIcon,
                    title: pref.revealLabel,
                    detail: pref.revealDetail,
                    tint: .accentBlue
                )
            }

            priorityRow(
                icon: "person.crop.rectangle.stack",
                title: "Role expectation",
                detail: outcome.roleNote,
                tint: .warning
            )
        }
        .padding(16)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.surfaceBorder, lineWidth: 1))
    }

    private func priorityRow(icon: String, title: String, detail: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var footerNote: some View {
        Text("\(visitsRemaining) visit\(visitsRemaining == 1 ? "" : "s") remaining this free agency period")
            .font(.caption)
            .foregroundStyle(Color.textTertiary)
    }

    // MARK: - Motivation copy

    private func motivationIcon(_ motivation: Motivation) -> String {
        switch motivation {
        case .money:   return "dollarsign.circle.fill"
        case .winning: return "trophy.fill"
        case .stats:   return "chart.bar.fill"
        case .loyalty: return "heart.fill"
        case .fame:    return "star.fill"
        }
    }

    private func motivationTitle(_ motivation: Motivation) -> String {
        switch motivation {
        case .money:   return "Primary driver: money"
        case .winning: return "Primary driver: winning"
        case .stats:   return "Primary driver: production"
        case .loyalty: return "Primary driver: loyalty"
        case .fame:    return "Primary driver: spotlight"
        }
    }

    private func motivationDetail(_ motivation: Motivation) -> String {
        switch motivation {
        case .money:   return "The money is the message — the highest offer wins, everything else is a tiebreaker."
        case .winning: return "Your record matters as much as the check. Contenders get a real discount."
        case .stats:   return "He wants the ball. A clear starting role moves him more than an extra million."
        case .loyalty: return "Relationships matter to him — he rewards teams that show they're invested."
        case .fame:    return "He wants the bright lights. Market size and exposure weigh on the decision."
        }
    }

    private func formatMillions(_ thousands: Int) -> String {
        let millions = Double(thousands) / 1000.0
        return millions >= 1.0 ? String(format: "$%.1fM", millions) : "$\(thousands)K"
    }
}

// MARK: - Interest Meter Bar (shared, R23)

/// Cold→hot gradient bar with a marker at the current interest reading.
/// Used in the visit result sheet and the FA offer sheet.
struct InterestMeterBar: View {

    let breakdown: SigningInterestEngine.Breakdown

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(
                            LinearGradient(
                                colors: [Color.accentBlue, Color.warning, Color.danger],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .opacity(0.35)
                    RoundedRectangle(cornerRadius: 5)
                        .fill(
                            LinearGradient(
                                colors: [Color.accentBlue, Color.warning, Color.danger],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(8, geo.size.width * breakdown.total))

                    // Marker
                    Circle()
                        .fill(Color.textPrimary)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().strokeBorder(Color.backgroundPrimary, lineWidth: 2))
                        .offset(x: max(0, geo.size.width * breakdown.total - 7))
                }
            }
            .frame(height: 10)
            .animation(.easeOut(duration: 0.2), value: breakdown.total)

            HStack {
                HStack(spacing: 4) {
                    Image(systemName: breakdown.tier.icon)
                        .font(.system(size: 10))
                    Text(breakdown.tier.rawValue.uppercased())
                        .font(.system(size: 10, weight: .black))
                }
                .foregroundStyle(tierColor(breakdown.tier))
                Spacer()
                Text("Cold")
                    .font(.system(size: 8))
                    .foregroundStyle(Color.textTertiary)
                Image(systemName: "arrow.right")
                    .font(.system(size: 7))
                    .foregroundStyle(Color.textTertiary)
                Text("Hot")
                    .font(.system(size: 8))
                    .foregroundStyle(Color.textTertiary)
            }
        }
    }

    private func tierColor(_ tier: SigningInterestEngine.InterestTier) -> Color {
        switch tier {
        case .cold:      return .accentBlue
        case .lukewarm:  return .textSecondary
        case .warm:      return .warning
        case .hot:       return .danger
        case .scorching: return .draftStealGold
        }
    }
}

// MARK: - Preference Tag Reveal Copy (R23)

extension PlayerPreferenceTag {

    var revealIcon: String {
        switch self {
        case .contenderShot:  return "trophy"
        case .maxMoney:       return "banknote"
        case .familyLocation: return "figure.2.and.child.holdinghands"
        case .warmClimate:    return "sun.max.fill"
        case .startingRole:   return "star.circle"
        case .loyaltyToCoach: return "person.2.fill"
        case .hometownReturn: return "house.fill"
        }
    }

    var revealLabel: String {
        switch self {
        case .contenderShot:  return "Wants a shot at a ring"
        case .maxMoney:       return "Chasing max money"
        case .familyLocation: return "Family location matters"
        case .warmClimate:    return "Prefers a warm climate"
        case .startingRole:   return "Demands a starting role"
        case .loyaltyToCoach: return "Follows coaches he trusts"
        case .hometownReturn: return "Dreams of a hometown return"
        }
    }

    var revealDetail: String {
        switch self {
        case .contenderShot:  return "A playoff-caliber roster can win the negotiation even without the top offer."
        case .maxMoney:       return "His agent has told everyone the same thing: bring the biggest number."
        case .familyLocation: return "His family has a say — geography quietly shapes his short list."
        case .warmClimate:    return "Cold-weather teams start a step behind with him."
        case .startingRole:   return "If a better player sits ahead of him on the depth chart, interest cools fast."
        case .loyaltyToCoach: return "A familiar coach on staff is worth real money to him."
        case .hometownReturn: return "The hometown club gets an edge no one else can match."
        }
    }
}
