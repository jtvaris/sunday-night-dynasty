import SwiftUI

// MARK: - FA Round Summary — the market day, read back
//
// UI_REDESIGN_VISION §2.6's shape — outcome headline → what changed → a single
// Continue — with the sections in between, because a market day owes the user a
// transcript and `DSResultSheet` (rightly) has no slot for one. The parts it
// does own are used verbatim: the stat-chip grammar for "what changed" and
// `DSActionBar` for the commit.
//
// The `NavigationStack` wrapper is gone with the hand-rolled gold button. It
// existed only to hang a title on, and a modal that carries both a navigation
// title and a full-width Continue is two dismissal affordances for one job —
// the pattern §0 counted seven variants of.

struct FARoundSummaryView: View {

    let results: RoundResults
    let roundLabel: String
    let nextRoundLabel: String
    let onContinue: () -> Void

    var body: some View {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()

                VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 24) {
                        resultHeader

                        // Your signings
                        if !results.yourSignings.isEmpty {
                            summarySection(
                                title: "Your Signings",
                                icon: "checkmark.circle.fill",
                                color: .success
                            ) {
                                ForEach(Array(results.yourSignings.enumerated()), id: \.offset) { _, signing in
                                    HStack(spacing: 8) {
                                        Text(signing.position)
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(Color.textPrimary)
                                            .frame(width: 30)
                                            .padding(.vertical, 2)
                                            .background(Color.accentBlue, in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))
                                        Text(signing.playerName)
                                            .font(.subheadline)
                                            .foregroundStyle(Color.textPrimary)
                                            .lineLimit(1)
                                        Spacer()
                                        Text("\(formatMillions(signing.salary))/yr \u{00B7} \(signing.years)yr")
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(Color.textSecondary)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 6)
                                }
                            }
                        }

                        // Your rejections
                        if !results.yourRejections.isEmpty {
                            summarySection(
                                title: "Rejections",
                                icon: "xmark.circle.fill",
                                color: .danger
                            ) {
                                ForEach(Array(results.yourRejections.enumerated()), id: \.offset) { _, rejection in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 8) {
                                            Text(rejection.position)
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(Color.textPrimary)
                                                .frame(width: 30)
                                                .padding(.vertical, 2)
                                                .background(Color.accentBlue, in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))
                                            Text(rejection.playerName)
                                                .font(.subheadline)
                                                .foregroundStyle(Color.textPrimary)
                                                .lineLimit(1)
                                            Spacer()
                                            if let chosenTeam = rejection.chosenTeam {
                                                Text("\u{2192} \(chosenTeam)")
                                                    .font(.caption.weight(.bold))
                                                    .foregroundStyle(Color.textSecondary)
                                            }
                                        }
                                        Text("\"\(rejection.reason)\"")
                                            .font(.caption)
                                            .foregroundStyle(Color.textTertiary)
                                            .italic()
                                            .padding(.leading, 38)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 6)
                                }
                            }
                        }

                        // Bidding Wars
                        if !results.biddingWars.isEmpty {
                            summarySection(
                                title: "Bidding Wars",
                                icon: "flame.fill",
                                color: .orange
                            ) {
                                ForEach(Array(results.biddingWars.enumerated()), id: \.offset) { _, war in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 8) {
                                            Text(war.position)
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(Color.textPrimary)
                                                .frame(width: 30)
                                                .padding(.vertical, 2)
                                                .background(Color.orange, in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))
                                            Text(war.playerName)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(Color.textPrimary)
                                                .lineLimit(1)
                                            Spacer()
                                            Text("\(war.bidderCount) teams")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(Color.danger)
                                        }
                                        HStack(spacing: 4) {
                                            Text("Price escalated to ~\(formatMillions(war.escalatedPrice))/yr")
                                                .font(.caption2)
                                                .foregroundStyle(Color.warning)
                                            if !war.droppedOutTeams.isEmpty {
                                                Text("\u{2022} \(war.droppedOutTeams.joined(separator: ", ")) dropped out")
                                                    .font(.caption2)
                                                    .foregroundStyle(Color.textTertiary)
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 6)
                                }
                            }
                        }

                        // Shopping Around (players still weighing options)
                        if !results.shoppingAround.isEmpty {
                            summarySection(
                                title: "Still Shopping Around",
                                icon: "clock.arrow.circlepath",
                                color: .accentGold
                            ) {
                                ForEach(Array(results.shoppingAround.enumerated()), id: \.offset) { _, player in
                                    HStack(spacing: 8) {
                                        Text(player.position)
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(Color.textPrimary)
                                            .frame(width: 30)
                                            .padding(.vertical, 2)
                                            .background(Color.accentGold.opacity(0.3), in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))
                                        Text(player.playerName)
                                            .font(.subheadline)
                                            .foregroundStyle(Color.textPrimary)
                                            .lineLimit(1)
                                        Spacer()
                                        Text("Exploring options")
                                            .font(.caption2)
                                            .foregroundStyle(Color.textTertiary)
                                            .italic()
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 4)
                                }
                            }
                        }

                        // Bidding Updates (for active offers)
                        if !results.biddingUpdates.isEmpty {
                            summarySection(
                                title: "Your Active Negotiations",
                                icon: "megaphone.fill",
                                color: .accentGold
                            ) {
                                ForEach(Array(results.biddingUpdates.enumerated()), id: \.offset) { _, update in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 8) {
                                            Text(update.position)
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(Color.textPrimary)
                                                .frame(width: 30)
                                                .padding(.vertical, 2)
                                                .background(Color.accentBlue, in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))
                                            Text(update.playerName)
                                                .font(.subheadline)
                                                .foregroundStyle(Color.textPrimary)
                                                .lineLimit(1)
                                            Spacer()
                                            if update.isBiddingWar {
                                                Text("BIDDING WAR")
                                                    .font(.system(size: DSType.Size.micro, weight: .black))
                                                    .foregroundStyle(.white)
                                                    .padding(.horizontal, 4)
                                                    .padding(.vertical, 1)
                                                    .background(Color.danger, in: Capsule())
                                            }
                                        }
                                        HStack(spacing: 12) {
                                            Text("Your offer: \(formatMillions(update.yourOffer))/yr")
                                                .font(.caption2.monospacedDigit())
                                                .foregroundStyle(Color.accentGold)
                                            if let highest = update.highestCompetingOffer,
                                               let teamAbbr = update.highestCompetingTeam {
                                                Text("Highest: ~\(formatMillions(highest))/yr from \(teamAbbr)")
                                                    .font(.caption2.monospacedDigit())
                                                    .foregroundStyle(Color.warning)
                                            }
                                        }
                                        Text(update.playerLeaning.rawValue)
                                            .font(.caption2.weight(.medium))
                                            .foregroundStyle(
                                                update.playerLeaning == .strongInterest || update.playerLeaning == .prefersYou
                                                    ? Color.success
                                                    : update.playerLeaning == .undecided
                                                        ? Color.warning : Color.danger
                                            )
                                            .italic()
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 6)
                                }
                            }
                        }

                        // AI signings
                        if !results.aiSignings.isEmpty {
                            summarySection(
                                title: "Around the League",
                                icon: "newspaper.fill",
                                color: .accentBlue
                            ) {
                                ForEach(Array(results.aiSignings.prefix(8).enumerated()), id: \.offset) { _, signing in
                                    HStack(spacing: 8) {
                                        Text(signing.position)
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(Color.textPrimary)
                                            .frame(width: 30)
                                            .padding(.vertical, 2)
                                            .background(Color.accentBlue, in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))
                                        Text(signing.playerName)
                                            .font(.caption)
                                            .foregroundStyle(Color.textPrimary)
                                            .lineLimit(1)
                                        Spacer()
                                        Text("\u{2192} \(signing.team)")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(Color.textSecondary)
                                        Text(formatMillions(signing.salary))
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(Color.textTertiary)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 4)
                                }
                            }
                        }

                        // Media headlines
                        if !results.headlines.isEmpty {
                            summarySection(
                                title: "Headlines",
                                icon: "newspaper.fill",
                                color: .accentGold
                            ) {
                                ForEach(Array(results.headlines.enumerated()), id: \.offset) { _, headline in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text("\u{201C}")
                                            .font(.title3.weight(.bold))
                                            .foregroundStyle(Color.accentGold)
                                        Text(headline)
                                            .font(.caption)
                                            .foregroundStyle(Color.textPrimary)
                                            .italic()
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 4)
                                }
                            }
                        }

                    }
                    .padding(24)
                    .frame(maxWidth: .infinity)
                }

                // §2.5 — one commit, one place. The "Market update" pair that
                // used to sit above the button is in the header's chip row now,
                // where every other number this sheet reports lives.
                DSActionBar(
                    explainer: .init(
                        title: "\(roundLabel) is closed",
                        message: continueMessage
                    ),
                    primary: .init(
                        title: "Continue \u{2192} \(nextRoundLabel)",
                        handler: onContinue
                    )
                )
                }
            }
    }

    // MARK: - Outcome headline + what changed (§2.3 / §2.6)

    private var resultHeader: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text("\(roundLabel) results".uppercased())
                .font(DSType.display(11, .heavy))
                .tracking(0.7)
                .foregroundStyle(Color.accentGold)

            Text(headline)
                .font(DSType.display(DSType.Size.title2, .heavy))
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            // Three named bands as a grid, not three stacks: §2.3's layout rule.
            Grid(alignment: .leading, horizontalSpacing: DSSpacing.lg, verticalSpacing: DSSpacing.xxs) {
                GridRow {
                    ForEach(chips, id: \.label) { chip in
                        Text(chip.label.uppercased())
                            .font(DSType.display(11, .heavy))
                            .tracking(0.6)
                            .foregroundStyle(Color.textTertiaryReadable)
                            .lineLimit(1)
                    }
                }
                GridRow {
                    ForEach(chips, id: \.label) { chip in
                        Text(chip.value)
                            .font(DSType.display(DSType.Size.title2, .heavy))
                            .foregroundStyle(chip.color)
                            .lineLimit(1)
                    }
                }
                GridRow {
                    ForEach(chips, id: \.label) { chip in
                        // The context row is always reserved, so a chip that
                        // carries one and a chip that does not sit at the same
                        // height (§2.2's slot rule).
                        Text(chip.context ?? " ")
                            .font(DSType.display(11, .semibold))
                            .foregroundStyle(Color.textTertiaryReadable)
                            .lineLimit(1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private struct SummaryChip {
        let label: String
        let value: String
        var context: String?
        var color: Color = .textPrimary
    }

    private var chips: [SummaryChip] {
        [
            SummaryChip(
                label: "Signed",
                value: "\(results.yourSignings.count)",
                context: results.yourSignings.isEmpty ? nil : "this round",
                color: results.yourSignings.isEmpty ? .textPrimary : .success
            ),
            SummaryChip(
                label: "Lost",
                value: "\(results.yourRejections.count)",
                context: results.yourRejections.isEmpty ? nil : "signed elsewhere",
                color: results.yourRejections.isEmpty ? .textPrimary : .dangerText
            ),
            SummaryChip(
                label: "Still out",
                value: "\(results.shoppingAround.count)",
                context: results.shoppingAround.isEmpty ? nil : "offers carried over"
            ),
            SummaryChip(
                label: "Board",
                value: "\(results.playersRemaining)",
                context: "still available"
            ),
            SummaryChip(
                label: "Cap room",
                value: formatMillions(results.capRemaining),
                context: "after the round",
                color: results.capRemaining > 0 ? .textPrimary : .dangerText
            )
        ]
    }

    /// The outcome, in the club's words rather than as a bare round number.
    private var headline: String {
        let signed = results.yourSignings.count
        let lost = results.yourRejections.count
        if signed == 0 && lost == 0 { return "Nothing moved for you" }
        if signed > 0 && lost == 0 {
            return "\(signed) signed \(signed == 1 ? "his" : "their") deal with you"
        }
        if signed == 0 {
            return "\(lost) chose somebody else"
        }
        return "\(signed) signed, \(lost) got away"
    }

    private var continueMessage: String {
        let carried = results.shoppingAround.count
        if carried > 0 {
            return "**\(carried)** of your offers \(carried == 1 ? "is" : "are") still on the table and \(carried == 1 ? "keeps" : "keep") reserving cap."
        }
        return "Nothing of yours is outstanding. The next day opens with your full room."
    }

    // MARK: - Section

    private func summarySection<Content: View>(
        title: String,
        icon: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.system(size: DSType.Size.body))
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(color)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider().overlay(Color.surfaceBorder)

            content()

            Spacer().frame(height: 8)
        }
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.surfaceBorder, lineWidth: 1))
    }

    // MARK: - Helpers

    private func formatMillions(_ thousands: Int) -> String {
        let millions = Double(thousands) / 1000.0
        if millions >= 1.0 {
            return String(format: "$%.1fM", millions)
        } else {
            return "$\(thousands)K"
        }
    }
}
