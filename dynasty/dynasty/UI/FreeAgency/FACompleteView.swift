import SwiftUI
import SwiftData

struct FACompleteView: View {

    let career: Career

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var team: Team?
    @State private var recentSignings: [SigningDetail] = []
    @State private var lostPlayers: [LostPlayerDetail] = []
    @State private var leagueSignings: [LeagueSigningDetail] = []
    @State private var faGrade: FAGradeResult = .init(grade: "C", explanation: "Evaluating...", score: 50, components: [])
    @State private var beforeAfter: BeforeAfterComparison?
    @State private var remainingNeeds: [(position: Position, level: String)] = []
    @State private var compPickEstimate: [String] = []
    @State private var mediaQuote: String = ""
    @State private var baseSalaryCap: Int = ContractEngine.openingSalaryCap
    @State private var isLoading: Bool = true

    // MARK: - Data Types

    struct SigningDetail: Identifiable {
        let id: UUID
        let name: String
        let position: Position
        let overall: Int
        let annualSalary: Int
        let years: Int
        let totalValue: Int
        /// The deal's real guarantee, off the `Contract` row. `nil` in simple and
        /// sandbox mode, which carry no contract row and therefore no guarantee to
        /// quote — the chip is dropped rather than invented.
        let guaranteedMoney: Int?
        let marketValue: Int
        let replacesPlayer: String?
        let ovrUpgrade: Int?
        let fillsStarter: Bool
        let valueTag: ValueTag
    }

    enum ValueTag: String {
        case steal = "Steal!"
        case goodValue = "Good Value"
        case fairDeal = "Fair Deal"
        case overpay = "Overpay"
        case bigOverpay = "Big Overpay"
    }

    struct LostPlayerDetail: Identifiable {
        let id: UUID
        let name: String
        let position: Position
        let overall: Int
        let newTeam: String
    }

    struct LeagueSigningDetail: Identifiable {
        let id: UUID
        let playerName: String
        let position: Position
        let overall: Int
        let teamAbbr: String
        let salary: Int
    }

    struct FAGradeResult {
        let grade: String
        let explanation: String
        let score: Int
        /// The signed terms the score was built from. `calculateFAGrade` had them
        /// as locals and threw them away for a canned sentence, which is how a "D"
        /// ends up unarguable. Empty when there is no arithmetic worth showing —
        /// the "nobody moved" baseline.
        let components: [GradeComponent]
    }

    /// One line of the grade's working.
    struct GradeComponent {
        let label: String
        let points: Double

        var pointsText: String {
            let rounded = Int(points.rounded())
            return rounded > 0 ? "+\(rounded)" : "\(rounded)"
        }
    }

    struct BeforeAfterComparison {
        let rosterOVRBefore: Int
        let rosterOVRAfter: Int
        let capUsedBefore: Int
        let capUsedAfter: Int
        let starterGapsBefore: Int
        let starterGapsAfter: Int
    }

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(1.5)
                        .tint(Color.accentGold)
                    Text("Loading FA Summary...")
                        .font(.subheadline)
                        .foregroundColor(Color.textSecondary)
                }
            } else {
            VStack(spacing: 0) {
                // §2.1 — free agency's spine, at its last step. Every slat
                // behind it is done, which is the point: this screen is where
                // the run is read back.
                FAFlowBandView(
                    step: .complete,
                    currentSubcaption: "\(recentSignings.count) signed \u{00B7} \(lostPlayers.count) lost"
                )
                ScrollView {
                    LazyVStack(spacing: 20) {
                        headerSection
                        if let team { capSummarySection(team: team) }
                        if let ba = beforeAfter { beforeAfterSection(ba) }
                        faGradeSection
                        if !recentSignings.isEmpty { signingsSection }
                        if !lostPlayers.isEmpty { lostPlayersSection }
                        if !leagueSignings.isEmpty { leagueSigningsSection }
                        if !remainingNeeds.isEmpty { remainingNeedsSection }
                        if !compPickEstimate.isEmpty { compPickSection }
                        if !mediaQuote.isEmpty { mediaSection }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity)
                }
                // §2.5 — the one commit, pinned. It used to be the last item
                // under nine optional sections, so a quiet free agency put it
                // on screen and a busy one buried it.
                DSActionBar(
                    explainer: .init(
                        title: "Free agency is over",
                        message: "Advancing closes the league year's signing period and opens **Pro Days**."
                    ),
                    primary: .init(
                        title: "Continue \u{2192} Pro Days",
                        handler: {
                            WeekAdvancer.advanceWeek(career: career, modelContext: modelContext)
                            // Pop the FA modal stack back to the Career Dashboard
                            // so the user can see the new .proDays phase tasks.
                            dismiss()
                        }
                    )
                )
            }
            } // end else (not loading)
        }
        .navigationTitle("FA Complete")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            loadData()
            isLoading = false
        }
    }

    // MARK: - Header

    /// Narrative tone derived from the FA grade.
    private struct GradeNarrative {
        let icon: String
        let iconColor: Color
        let title: String
        let subtitle: String
        let backgroundOpacity: Double
    }

    private func gradeNarrative(_ grade: FAGradeResult) -> GradeNarrative {
        switch grade.score {
        case 90...:
            return GradeNarrative(
                icon: "trophy.fill",
                iconColor: .accentGold,
                title: "MASTERFUL OFFSEASON",
                subtitle: "Front-office of the year material — fans are ecstatic.",
                backgroundOpacity: 0.20
            )
        case 80..<90:
            return GradeNarrative(
                icon: "star.circle.fill",
                iconColor: .accentGold,
                title: "EXCELLENT FREE AGENCY",
                subtitle: "Major needs addressed at fair prices. Confidence is high.",
                backgroundOpacity: 0.16
            )
        case 70..<80:
            return GradeNarrative(
                icon: "checkmark.seal.fill",
                iconColor: .success,
                title: "SOLID FREE AGENCY",
                subtitle: "Smart pickups improve the roster heading into the draft.",
                backgroundOpacity: 0.12
            )
        case 60..<70:
            return GradeNarrative(
                icon: "hand.thumbsup",
                iconColor: .accentBlue,
                title: "DECENT WORK",
                subtitle: "Some good moves — but a few key needs still linger.",
                backgroundOpacity: 0.10
            )
        case 50..<60:
            return GradeNarrative(
                icon: "minus.circle",
                iconColor: .warning,
                title: "MIXED RESULTS",
                subtitle: "Modest improvements. The draft will need to do heavier lifting.",
                backgroundOpacity: 0.10
            )
        case 40..<50:
            return GradeNarrative(
                icon: "exclamationmark.triangle.fill",
                iconColor: .warning,
                title: "DISAPPOINTING FA",
                subtitle: "Critical needs went unaddressed. The pressure is on the GM.",
                backgroundOpacity: 0.12
            )
        default:
            return GradeNarrative(
                icon: "xmark.octagon.fill",
                iconColor: .danger,
                title: "FREE AGENCY DISASTER",
                subtitle: "Roster gaps remain and the cap sheet looks rough. Damage control time.",
                backgroundOpacity: 0.16
            )
        }
    }

    private var headerSection: some View {
        let narrative = gradeNarrative(faGrade)

        return VStack(spacing: 12) {
            Image(systemName: narrative.icon)
                .font(.system(size: DSType.Size.hero))
                .foregroundStyle(narrative.iconColor)
                .shadow(color: narrative.iconColor.opacity(0.4), radius: 12)

            Text(narrative.title)
                .font(.title2.weight(.black))
                .foregroundStyle(narrative.iconColor)
                .multilineTextAlignment(.center)

            Text(narrative.subtitle)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            // Quick highlight bar: top signing or biggest loss
            if let topSigning = recentSignings.first {
                // The capsule used to be green with an up-arrow whatever the deal
                // was, so a "Big Overpay" got celebrated three inches under a
                // "critical needs went unaddressed" headline and beside its own
                // red chip — one man, three verdicts, one screen. The deal's own
                // value tag paints it now, and says which verdict it is.
                let tone = headlineTone(topSigning.valueTag)
                let tint = valueTagColor(topSigning.valueTag)
                HStack(spacing: 6) {
                    Image(systemName: tone.icon)
                        .font(.caption)
                        .foregroundStyle(tint)
                    Text("\(tone.lead): \(topSigning.name) (\(topSigning.position.rawValue), \(topSigning.overall) OVR) \u{2014} \(topSigning.valueTag.rawValue)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(tint.opacity(0.10), in: Capsule())
            } else if let topLoss = lostPlayers.first {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.right.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.danger)
                    Text("Biggest loss: \(topLoss.name) → \(topLoss.newTeam)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.danger.opacity(0.10), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(narrative.iconColor.opacity(narrative.backgroundOpacity))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(narrative.iconColor.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Cap Summary

    private func capSummarySection(team: Team) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(icon: "dollarsign.circle.fill", title: "Final Cap Situation")

            HStack(spacing: 0) {
                capStat(label: "Cap", value: formatMillions(team.salaryCap), color: .accentGold)
                capStat(label: "Used", value: formatMillions(team.currentCapUsage), color: .textPrimary)
                capStat(label: "Available", value: formatMillions(team.availableCap),
                        color: team.availableCap >= 0 ? .success : .danger)
            }

            // Cap breakdown explanation
            let base = baseSalaryCap
            let rollover = team.salaryCap - base
            if rollover > 0 && base > 0 {
                Text("(\(formatMillions(base)) base + \(formatMillions(rollover)) cap growth)")
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.surfaceBorder, lineWidth: 1))
    }

    // MARK: - Before/After Comparison

    private func beforeAfterSection(_ ba: BeforeAfterComparison) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(icon: "arrow.left.arrow.right", title: "Before / After FA")
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider().overlay(Color.surfaceBorder)

            VStack(spacing: 8) {
                comparisonRow(
                    label: "Roster OVR",
                    before: "\(ba.rosterOVRBefore)",
                    after: "\(ba.rosterOVRAfter)",
                    improved: ba.rosterOVRAfter >= ba.rosterOVRBefore
                )
                comparisonRow(
                    label: "Cap Used",
                    before: formatMillions(ba.capUsedBefore),
                    after: formatMillions(ba.capUsedAfter),
                    // Spending has no good direction on this page. It used to be
                    // hardcoded `improved: true`, so a club that saved its room by
                    // signing nobody and a club that spent it on a starter both got
                    // the same green — even under a "critical needs went
                    // unaddressed" headline. The rows either side carry the verdict;
                    // this one carries the number.
                    improved: nil
                )
                comparisonRow(
                    label: "Starter Gaps",
                    before: "\(ba.starterGapsBefore)",
                    after: "\(ba.starterGapsAfter)",
                    improved: ba.starterGapsAfter <= ba.starterGapsBefore
                )
            }
            .padding(16)
        }
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.surfaceBorder, lineWidth: 1))
    }

    /// `improved` is optional: `nil` is a row whose movement carries no verdict,
    /// and it renders in plain text rather than borrowing success or warning paint.
    private func comparisonRow(label: String, before: String, after: String, improved: Bool?) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(before)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Color.textTertiary)
            Image(systemName: "arrow.right")
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
            Text(after)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(improved.map { $0 ? Color.success : Color.warning } ?? Color.textPrimary)
        }
    }

    // MARK: - FA Grade

    private var faGradeSection: some View {
        VStack(spacing: 12) {
            sectionHeader(icon: "star.circle.fill", title: "Free Agency Grade")
                .padding(.horizontal, 16)
                .padding(.top, 14)

            HStack(spacing: 20) {
                // Large grade letter
                Text(faGrade.grade)
                    .font(.system(size: DSType.Size.hero, weight: .black))
                    .foregroundStyle(PositionGradeCalculator.gradeColorForLetter(faGrade.grade))
                    .frame(width: 80)

                VStack(alignment: .leading, spacing: 6) {
                    Text(faGrade.explanation)
                        .font(.subheadline)
                        .foregroundStyle(Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    // The half of this card that used to be empty. The letter is
                    // built from four separable terms and the user is entitled to
                    // see which one cost him the grade.
                    if !faGrade.components.isEmpty {
                        Divider().overlay(Color.surfaceBorder)
                            .padding(.vertical, 2)

                        ForEach(Array(faGrade.components.enumerated()), id: \.offset) { _, term in
                            gradeTermRow(label: term.label, value: term.pointsText,
                                         tint: term.points < 0 ? Color.warning : Color.textSecondary)
                        }

                        Divider().overlay(Color.surfaceBorder)
                            .padding(.vertical, 2)

                        gradeTermRow(label: "Score", value: "\(faGrade.score)", tint: Color.textPrimary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.surfaceBorder, lineWidth: 1))
    }

    private func gradeTermRow(label: String, value: String, tint: Color) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(tint)
        }
    }

    // MARK: - Your FA Signings

    private var signingsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(icon: "person.badge.plus", title: "Your FA Signings (\(recentSignings.count))")
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider().overlay(Color.surfaceBorder)

            ForEach(recentSignings) { signing in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Text(signing.position.rawValue)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.textPrimary)
                            .frame(width: 30)
                            .padding(.vertical, 3)
                            .background(positionSideColor(signing.position), in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))

                        Text(signing.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)

                        Spacer()

                        Text("\(signing.overall) OVR")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Color.forRating(signing.overall))

                        // Value tag
                        Text(signing.valueTag.rawValue)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(valueTagColor(signing.valueTag))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(valueTagColor(signing.valueTag).opacity(0.15),
                                        in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))
                    }

                    // Contract details
                    HStack(spacing: 12) {
                        Label("\(signing.years)yr", systemImage: "calendar")
                        Label(formatMillions(signing.totalValue) + " total", systemImage: "dollarsign.circle")
                        if let guaranteed = signing.guaranteedMoney {
                            Label(formatMillions(guaranteed) + " gtd", systemImage: "lock.fill")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)

                    // Roster impact
                    if let replaces = signing.replacesPlayer, let upgrade = signing.ovrUpgrade {
                        let sign = upgrade >= 0 ? "+" : ""
                        Text("Replaces \(replaces) (\(sign)\(upgrade) OVR)")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(upgrade > 0 ? Color.success : Color.warning)
                    } else if signing.fillsStarter {
                        Text("Fills starting \(signing.position.rawValue) spot")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Color.success)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.surfaceBorder, lineWidth: 1))
    }

    // MARK: - Players Lost

    private var lostPlayersSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(icon: "person.badge.minus", title: "Players Lost (\(lostPlayers.count))")
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider().overlay(Color.surfaceBorder)

            ForEach(lostPlayers) { player in
                HStack(spacing: 10) {
                    Text(player.position.rawValue)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.textPrimary)
                        .frame(width: 30)
                        .padding(.vertical, 3)
                        .background(positionSideColor(player.position), in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))

                    Text(player.name)
                        .font(.subheadline)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)

                    Spacer()

                    Text("\(player.overall) OVR")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color.forRating(player.overall))

                    Text(player.newTeam)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.surfaceBorder, lineWidth: 1))
    }

    // MARK: - League Signings

    private var leagueSigningsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(icon: "globe", title: "Key Signings Around the League")
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider().overlay(Color.surfaceBorder)

            ForEach(leagueSignings) { signing in
                HStack(spacing: 10) {
                    Text(signing.position.rawValue)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.textPrimary)
                        .frame(width: 30)
                        .padding(.vertical, 3)
                        .background(positionSideColor(signing.position), in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))

                    Text(signing.playerName)
                        .font(.subheadline)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)

                    Spacer()

                    Text("\(signing.overall) OVR")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color.forRating(signing.overall))

                    Text(signing.teamAbbr)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.accentBlue)

                    Text(formatMillions(signing.salary) + "/yr")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Color.textTertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.surfaceBorder, lineWidth: 1))
    }

    // MARK: - Remaining Needs

    private var remainingNeedsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(icon: "exclamationmark.triangle.fill", title: "Remaining Needs")
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider().overlay(Color.surfaceBorder)

            HStack(spacing: 0) {
                ForEach(Array(remainingNeeds.prefix(6).enumerated()), id: \.offset) { _, need in
                    VStack(spacing: 4) {
                        Text(need.position.rawValue)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.textPrimary)
                        Text(need.level)
                            .font(.caption2)
                            .foregroundStyle(need.level == "High" ? Color.danger : Color.warning)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
            }
            .padding(.horizontal, 8)

            Text("Address in the Draft or Pro Days workouts")
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 10)
        }
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.surfaceBorder, lineWidth: 1))
    }

    // MARK: - Comp Pick Estimate

    private var compPickSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(icon: "ticket.fill", title: "Expected Compensatory Picks")
                .padding(.horizontal, 16)
                .padding(.top, 14)

            ForEach(Array(compPickEstimate.enumerated()), id: \.offset) { _, pick in
                HStack(spacing: 8) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 5))  // ds-lint:allow(font) decorative list bullet glyph, not text
                        .foregroundStyle(Color.accentGold)
                    Text(pick)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                .padding(.horizontal, 16)
            }

            Text("Based on net value of players lost vs. signed")
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.surfaceBorder, lineWidth: 1))
    }

    // MARK: - Media Reaction

    private var mediaSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(icon: "newspaper.fill", title: "Media Reaction")
                .padding(.horizontal, 16)
                .padding(.top, 14)

            Text("\"\(mediaQuote)\"")
                .font(.subheadline.italic())
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
                .fixedSize(horizontal: false, vertical: true)
        }
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.surfaceBorder, lineWidth: 1))
    }

    // MARK: - Continue Button (RETIRED, wave 3)
    //
    // The hand-rolled gold recipe at radius 14 is gone; the commit is the
    // `DSActionBar` primary in `body` (§2.5 / §2.8).

    // MARK: - Section Header Helper

    private func sectionHeader(icon: String, title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentGold)
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.accentGold)
            Spacer()
        }
    }

    // MARK: - Helpers

    private func capStat(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .bold).monospacedDigit())
                .foregroundStyle(color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func formatMillions(_ thousands: Int) -> String {
        let millions = Double(thousands) / 1000.0
        if millions >= 1.0 {
            return String(format: "$%.1fM", millions)
        } else {
            return "$\(thousands)K"
        }
    }

    private func valueTagColor(_ tag: ValueTag) -> Color {
        switch tag {
        case .steal:      return .success
        case .goodValue:  return .success
        case .fairDeal:   return .accentBlue
        case .overpay:    return .warning
        case .bigOverpay: return .danger
        }
    }

    /// The header capsule's glyph and lead-in. A deal the club paid over the odds
    /// for is not a "headline signing", it is the biggest cheque written.
    private func headlineTone(_ tag: ValueTag) -> (icon: String, lead: String) {
        switch tag {
        case .steal, .goodValue: return ("arrow.up.right.circle.fill", "Headline signing")
        case .fairDeal:          return ("checkmark.circle.fill", "Headline signing")
        case .overpay:           return ("exclamationmark.circle.fill", "Biggest commitment")
        case .bigOverpay:        return ("arrow.down.right.circle.fill", "Biggest commitment")
        }
    }

    /// Side of ball, the one thing a position chip means everywhere else in the
    /// app (`RosterView.positionSideColor`, the cap sheet, the roster screens).
    /// This screen used to paint the chip by SIGNED / LOST instead, so the same
    /// MLB badge was blue here and red on Cap Review one tap earlier.
    private func positionSideColor(_ position: Position) -> Color {
        switch position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }

    // MARK: - Load Data

    private func loadData() {
        guard let teamID = career.teamID else { return }
        let teamDesc = FetchDescriptor<Team>(predicate: #Predicate { $0.id == teamID })
        team = try? modelContext.fetch(teamDesc).first
        guard let team else { return }

        let cid = career.id
        let allTeams = (try? modelContext.fetch(FetchDescriptor<Team>(
            predicate: #Predicate { $0.careerID == cid }
        ))) ?? []
        let allPlayers = (try? modelContext.fetch(FetchDescriptor<Player>(
            predicate: #Predicate { $0.careerID == cid }
        ))) ?? []
        let myPlayers = allPlayers.filter { $0.teamID == teamID }
        baseSalaryCap = FASigningTracker.getBaseSalaryCap()

        // The guarantee is a TERM of the deal, not a fraction of it. This card
        // used to print 55 % of total value, so every signing in the game read
        // exactly 55 % guaranteed and none of them matched what walking away
        // would actually cost — `Contract.deadCap` charges the real guarantee
        // (F-61), and a summary screen that quotes a different number is a
        // screen the user plans against and loses.
        let contractRows = (try? modelContext.fetch(FetchDescriptor<Contract>(
            predicate: #Predicate<Contract> { $0.teamID == teamID }
        ))) ?? []
        let contractsByPlayer = Dictionary(
            contractRows.map { ($0.playerID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // --- Signings ---
        let signingIDs = FASigningTracker.getSigningIDs()
        let signedPlayers = myPlayers.filter { signingIDs.contains($0.id) }
            .sorted { $0.overall > $1.overall }

        recentSignings = signedPlayers.map { player in
            let marketVal = ContractEngine.estimateMarketValue(player: player, salaryCap: team.salaryCap)
            let valueTag = classifyValue(salary: player.annualSalary, marketValue: marketVal)

            // Find who this player might replace
            let samePos = myPlayers.filter { $0.position == player.position && $0.id != player.id }
            let bestExisting = samePos.max(by: { $0.overall < $1.overall })
            let idealCount = PositionGradeCalculator.idealStarterCounts[player.position] ?? 1
            let posCount = samePos.count // not counting new signing
            let fillsStarter = posCount < idealCount

            let replacesName: String?
            let ovrUpgrade: Int?
            if let best = bestExisting, player.overall > best.overall {
                replacesName = best.fullName
                ovrUpgrade = player.overall - best.overall
            } else {
                replacesName = nil
                ovrUpgrade = nil
            }

            return SigningDetail(
                id: player.id,
                name: player.fullName,
                position: player.position,
                overall: player.overall,
                annualSalary: player.annualSalary,
                years: player.contractYearsRemaining,
                totalValue: player.annualSalary * player.contractYearsRemaining,
                guaranteedMoney: contractsByPlayer[player.id]?.guaranteedMoney,
                marketValue: marketVal,
                replacesPlayer: replacesName,
                ovrUpgrade: ovrUpgrade,
                fillsStarter: fillsStarter,
                valueTag: valueTag
            )
        }

        // --- Lost Players ---
        let lostIDs = FASigningTracker.getLostPlayerIDs()
        lostPlayers = lostIDs.compactMap { id in
            guard let player = allPlayers.first(where: { $0.id == id }) else { return nil }
            let newTeamName: String
            if let newTeamID = player.teamID, let newTeam = allTeams.first(where: { $0.id == newTeamID }) {
                newTeamName = newTeam.abbreviation
            } else {
                newTeamName = "Unsigned"
            }
            return LostPlayerDetail(
                id: player.id,
                name: player.fullName,
                position: player.position,
                overall: player.overall,
                newTeam: newTeamName
            )
        }.sorted { $0.overall > $1.overall }

        // --- League Signings ---
        // Find notable non-team signings: high OVR players on other teams who weren't on those teams before
        // (players with low contract years = recently signed)
        let otherTeamPlayers = allPlayers
            .filter { $0.teamID != nil && $0.teamID != teamID && !signingIDs.contains($0.id) }
        // Players with short contracts (likely just signed) and high OVR
        let recentLeagueSignings = otherTeamPlayers
            .filter { $0.contractYearsRemaining >= 1 && $0.contractYearsRemaining <= 5 && $0.overall >= 78 }
            .sorted { $0.overall > $1.overall }
        leagueSignings = Array(recentLeagueSignings.prefix(8)).map { player in
            let teamAbbr = allTeams.first(where: { $0.id == player.teamID })?.abbreviation ?? "?"
            return LeagueSigningDetail(
                id: player.id,
                playerName: player.fullName,
                position: player.position,
                overall: player.overall,
                teamAbbr: teamAbbr,
                salary: player.annualSalary
            )
        }

        // --- Before/After ---
        let preOVR = FASigningTracker.getPreFARosterOVR()
        let preCap = FASigningTracker.getPreFACapUsage()
        let preGaps = FASigningTracker.getPreFAStarterGaps()
        // Starter average, matching the dashboard and the team picker — see
        // `RosterStrength`. The whole-roster mean this used to take reads eight
        // points lower on an offseason roster, because it averages in the camp
        // tail, and it made one label mean two things across three screens.
        let currentOVR = RosterStrength.starterAverage(myPlayers) ?? 0
        let idealCounts = PositionGradeCalculator.idealStarterCounts
        var currentGaps = 0
        for (pos, needed) in idealCounts {
            let have = myPlayers.filter { $0.position == pos }.count
            if have < needed { currentGaps += (needed - have) }
        }

        if preOVR > 0 || preCap > 0 {
            beforeAfter = BeforeAfterComparison(
                rosterOVRBefore: preOVR,
                rosterOVRAfter: currentOVR,
                capUsedBefore: preCap,
                capUsedAfter: team.currentCapUsage,
                starterGapsBefore: preGaps,
                starterGapsAfter: currentGaps
            )
        }

        // --- Remaining Needs ---
        var needs: [(position: Position, level: String)] = []
        for (pos, needed) in idealCounts {
            let have = myPlayers.filter { $0.position == pos }.count
            let posOveralls = myPlayers.filter { $0.position == pos }.map(\.overall)
            let avgOVR = posOveralls.isEmpty ? 0 : posOveralls.reduce(0, +) / posOveralls.count
            if have < needed {
                needs.append((position: pos, level: "High"))
            } else if avgOVR > 0 && avgOVR < 65 {
                needs.append((position: pos, level: "Med"))
            }
        }
        remainingNeeds = needs.sorted { levelPriority($0.level) > levelPriority($1.level) }

        // --- Comp Pick Estimate ---
        // R23: project from the real departure ledger + formula, so this
        // preview matches exactly what the league awards when FA closes.
        let projectedAwards = CompensatoryPickEngine.projectedAwards(
            forTeam: teamID,
            allPlayers: allPlayers,
            allTeams: allTeams
        )
        compPickEstimate = projectedAwards.map { award in
            "Round \(award.round) compensatory pick — for losing \(award.lostPlayerName)"
        }

        // --- FA Grade ---
        faGrade = calculateFAGrade(
            signings: recentSignings,
            lostPlayers: lostPlayers,
            beforeAfter: beforeAfter,
            remainingNeeds: remainingNeeds
        )

        // --- Media Quote ---
        mediaQuote = generateMediaQuote(
            teamName: team.fullName,
            teamAbbr: team.abbreviation,
            grade: faGrade,
            signings: recentSignings,
            lostPlayers: lostPlayers
        )
    }

    // MARK: - Value Classification

    private func classifyValue(salary: Int, marketValue: Int) -> ValueTag {
        guard marketValue > 0 else { return .fairDeal }
        let ratio = Double(salary) / Double(marketValue)
        if ratio < 0.75 { return .steal }
        if ratio < 0.90 { return .goodValue }
        if ratio < 1.10 { return .fairDeal }
        if ratio < 1.30 { return .overpay }
        return .bigOverpay
    }

    // MARK: - FA Grade Calculation

    private func calculateFAGrade(
        signings: [SigningDetail],
        lostPlayers: [LostPlayerDetail],
        beforeAfter: BeforeAfterComparison?,
        remainingNeeds: [(position: Position, level: String)]
    ) -> FAGradeResult {
        var score = 50.0
        // Every term is recorded as it lands so the card can print its working.
        // `mark` is the running total at the end of the previous term — the
        // arithmetic below is untouched, the ledger just watches it.
        var components: [GradeComponent] = [GradeComponent(label: "Baseline", points: score)]
        var mark = score

        // Needs addressed: each signing that fills a starter spot or replaces someone = +8
        let highNeedPositions = remainingNeeds.filter { $0.level == "High" }.map(\.position)
        for signing in signings {
            if signing.fillsStarter || signing.replacesPlayer != nil {
                score += 8
            }
            // Extra for filling a high-need position (check if the position was a need before signing)
            if highNeedPositions.contains(signing.position) {
                score += 4
            }
        }
        components.append(GradeComponent(label: "Needs addressed", points: score - mark))
        mark = score

        // Value analysis: steals boost, overpays reduce
        for signing in signings {
            switch signing.valueTag {
            case .steal:      score += 6
            case .goodValue:  score += 3
            case .fairDeal:   score += 1
            case .overpay:    score -= 3
            case .bigOverpay: score -= 6
            }
        }
        components.append(GradeComponent(label: "Contract value", points: score - mark))
        mark = score

        // OVR improvement
        if let ba = beforeAfter {
            let ovrDelta = ba.rosterOVRAfter - ba.rosterOVRBefore
            score += Double(ovrDelta) * 3.0
            components.append(GradeComponent(label: "Roster OVR", points: Double(ovrDelta) * 3.0))

            let gapReduction = ba.starterGapsBefore - ba.starterGapsAfter
            score += Double(gapReduction) * 4.0
            components.append(GradeComponent(label: "Starter gaps", points: Double(gapReduction) * 4.0))
            mark = score
        }

        // Penalty for remaining high needs
        let remainingHigh = remainingNeeds.filter { $0.level == "High" }.count
        score -= Double(remainingHigh) * 5.0
        components.append(GradeComponent(label: "High needs still open", points: score - mark))

        // Bonus if no signings were needed and none made (maintained a good team)
        if signings.isEmpty && lostPlayers.isEmpty {
            score = 70 // B- baseline for a team that didn't need FA
            // Nothing was added up — a ledger here would be arithmetic the club
            // never did.
            components = []
        }

        // Clamp
        let uncapped = score
        score = max(20, min(100, score))
        if score != uncapped, !components.isEmpty {
            components.append(GradeComponent(
                label: score > uncapped ? "Floor (20)" : "Ceiling (100)",
                points: score - uncapped
            ))
        }

        let grade: String
        let explanation: String

        switch Int(score) {
        case 90...:
            grade = "A+"
            explanation = "Outstanding free agency. Addressed key needs with excellent value signings."
        case 85..<90:
            grade = "A"
            explanation = "Excellent FA period. Major roster improvements at fair prices."
        case 80..<85:
            grade = "A-"
            explanation = "Very strong FA class. Key positions upgraded without overpaying."
        case 75..<80:
            grade = "B+"
            explanation = "Solid free agency. Good additions that improved the roster."
        case 70..<75:
            grade = "B"
            explanation = "Above average FA. Some nice pickups, though a few needs remain."
        case 65..<70:
            grade = "B-"
            explanation = "Decent FA period. Roster is improved but gaps still exist."
        case 60..<65:
            grade = "C+"
            explanation = "Mixed results. Some good signings offset by overpays or unaddressed needs."
        case 55..<60:
            grade = "C"
            explanation = "Average free agency. Modest improvements with room for more."
        case 50..<55:
            grade = "C-"
            explanation = "Below expectations. Key needs remain heading into the draft."
        case 40..<50:
            grade = "D"
            explanation = "Disappointing FA. Several needs unaddressed and some questionable spending."
        default:
            grade = "F"
            explanation = "Poor free agency. Major roster holes remain with limited cap flexibility."
        }

        return FAGradeResult(
            grade: grade,
            explanation: explanation,
            score: Int(score),
            components: components
        )
    }

    // MARK: - Media Quote Generation

    private func generateMediaQuote(
        teamName: String,
        teamAbbr: String,
        grade: FAGradeResult,
        signings: [SigningDetail],
        lostPlayers: [LostPlayerDetail]
    ) -> String {
        let topSigning = signings.first
        let topLoss = lostPlayers.first

        if let signing = topSigning, grade.score >= 70 {
            let templates = [
                "National Sports Network: '\(teamAbbr) had an impressive free agency, headlined by the \(signing.name) signing at \(signing.position.rawValue). Grade: \(grade.grade)'",
                "League Network: 'The \(teamName) addressed their needs this offseason. The \(signing.name) addition gives them a real boost. Grade: \(grade.grade)'",
                "The Gridiron Weekly: '\(teamAbbr) were one of the winners of free agency. \(signing.name) is a significant upgrade. Grade: \(grade.grade)'"
            ]
            return templates[abs(teamAbbr.hashValue) % templates.count]
        } else if let loss = topLoss, grade.score < 55 {
            let templates = [
                "National Sports Network: '\(teamAbbr) failed to replace \(loss.name) adequately. A lot of work to do in the draft. Grade: \(grade.grade)'",
                "League Network: 'Losing \(loss.name) hurts, and \(teamAbbr) didn\u{2019}t do enough to fill the void. Grade: \(grade.grade)'",
                "The Gridiron Weekly: 'A quiet free agency for \(teamAbbr). The draft becomes critical now. Grade: \(grade.grade)'"
            ]
            return templates[abs(teamAbbr.hashValue) % templates.count]
        } else if let signing = topSigning {
            let templates = [
                "National Sports Network: '\(teamAbbr) made some moves, highlighted by \(signing.name). A solid but unspectacular FA. Grade: \(grade.grade)'",
                "League Network: 'The \(teamName) were selective in free agency. \(signing.name) is the key pickup. Grade: \(grade.grade)'",
                "The Gridiron Weekly: '\(teamAbbr) took a measured approach to FA. The real work starts in the draft. Grade: \(grade.grade)'"
            ]
            return templates[abs(teamAbbr.hashValue) % templates.count]
        } else {
            return "National Sports Network: '\(teamAbbr) were quiet in free agency. All eyes on the draft now. Grade: \(grade.grade)'"
        }
    }

    private func levelPriority(_ level: String) -> Int {
        switch level {
        case "High": return 2
        case "Med":  return 1
        default:     return 0
        }
    }
}
