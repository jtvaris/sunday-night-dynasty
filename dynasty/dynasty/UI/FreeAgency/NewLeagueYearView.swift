import SwiftUI
import SwiftData

struct NewLeagueYearView: View {

    let career: Career

    @Environment(\.modelContext) private var modelContext

    @State private var summary: FreeAgencyEngine.LeagueYearSummary?
    @State private var hasExecuted = false

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                // §2.1 — free agency's spine. Step 2 of 5, on every screen of
                // the run, so a user routed straight here by the shell can see
                // what is behind him and what is ahead.
                FAFlowBandView(
                    step: .newLeagueYear,
                    currentSubcaption: summary.map { "\($0.totalFreeAgentCount) players hit the market" }
                )

                if let summary {
                    ScrollView {
                        VStack(spacing: DSSpacing.lg) {
                            transitionHeader(summary: summary)
                            capSummaryCard(summary: summary)
                            notableFACard(summary: summary)
                        }
                        .padding(DSSpacing.lg)
                        .frame(maxWidth: .infinity)
                    }
                    // §2.5 — the commit lives on the bar, not as the last item
                    // in a ScrollView the user has to reach the bottom of.
                    DSActionBar(
                        explainer: .init(
                            title: "Cap review",
                            message: "Contracts have rolled over. You must be **under the cap** before the market will take an offer."
                        ),
                        primary: .init(
                            title: "Continue \u{2192} Cap Review",
                            handler: { career.freeAgencyStep = FreeAgencyStep.capReview.rawValue }
                        )
                    )
                } else {
                    Spacer()
                    VStack(spacing: DSSpacing.md) {
                        ProgressView()
                            .tint(Color.accentBlue)
                        Text("Advancing contracts...")
                            .font(DSType.text(DSType.Size.body, .regular, prose: true))
                            .foregroundStyle(Color.textSecondary)
                    }
                    Spacer()
                }
            }
        }
        .navigationTitle("New League Year")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { executeTransition() }
    }

    // MARK: - Transition Header

    private func transitionHeader(summary: FreeAgencyEngine.LeagueYearSummary) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 44))
                .foregroundStyle(Color.accentGold)

            Text("NEW LEAGUE YEAR")
                .font(.title2.weight(.black))
                .foregroundStyle(Color.accentGold)

            Text("\(summary.totalFreeAgentCount) players hit free agency")
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.surfaceBorder, lineWidth: 1))
    }

    // MARK: - Cap Summary

    private func capSummaryCard(summary: FreeAgencyEngine.LeagueYearSummary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "dollarsign.circle.fill")
                    .foregroundStyle(Color.textSecondary)
                    .font(.system(size: 15))
                Text("Your Cap Situation")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider().overlay(Color.surfaceBorder)

            VStack(spacing: 12) {
                capRow(label: "Previous cap usage", value: formatMillions(summary.playerTeamCapBefore), color: .textSecondary)
                capRow(label: "Cap freed from expirations", value: "+\(formatMillions(summary.capFreed))", color: .success)
                capRow(label: "New cap usage", value: formatMillions(summary.playerTeamCapAfter), color: .textPrimary)
            }
            .padding(16)
        }
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.surfaceBorder, lineWidth: 1))
    }

    private func capRow(label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
        }
    }

    // MARK: - Notable Free Agents

    private func notableFACard(summary: FreeAgencyEngine.LeagueYearSummary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "star.fill")
                    .foregroundStyle(Color.textSecondary)
                    .font(.system(size: 15))
                Text("Notable New Free Agents")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider().overlay(Color.surfaceBorder)

            VStack(spacing: 0) {
                ForEach(Array(summary.notableFreeAgents.enumerated()), id: \.offset) { index, fa in
                    HStack(spacing: 10) {
                        Text(fa.position)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.textPrimary)
                            .frame(width: 34)
                            .padding(.vertical, 3)
                            .background(Color.accentBlue, in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))

                        Text(fa.name)
                            .font(.subheadline)
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)

                        Spacer()

                        Text("\(fa.overall) OVR")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Color.forRating(fa.overall))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                    if index < summary.notableFreeAgents.count - 1 {
                        Divider()
                            .overlay(Color.surfaceBorder.opacity(0.5))
                            .padding(.horizontal, 8)
                    }
                }
            }
        }
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.surfaceBorder, lineWidth: 1))
    }

    // MARK: - Continue Button (RETIRED, wave 3)
    //
    // The hand-rolled gold recipe at radius 14 that used to sit as the last item
    // in the ScrollView is gone: the commit is the `DSActionBar` primary in
    // `body`, which is `.dsPrimary` at `DSCornerRadius.inline` like every other
    // commit in the app (§2.5 / §2.8).

    // MARK: - Helpers

    private func formatMillions(_ thousands: Int) -> String {
        let millions = Double(thousands) / 1000.0
        if millions >= 1.0 {
            return String(format: "$%.1fM", millions)
        } else {
            return "$\(thousands)K"
        }
    }

    private func executeTransition() {
        guard !hasExecuted else { return }
        hasExecuted = true

        guard let teamID = career.teamID else { return }
        let cid = career.id
        let allPlayers = (try? modelContext.fetch(FetchDescriptor<Player>(
            predicate: #Predicate { $0.careerID == cid }
        ))) ?? []
        let allTeams = (try? modelContext.fetch(FetchDescriptor<Team>(
            predicate: #Predicate { $0.careerID == cid }
        ))) ?? []

        // Capture pre-FA snapshot before contracts expire
        let myTeam = allTeams.first { $0.id == teamID }
        let myRoster = allPlayers.filter { $0.teamID == teamID }
        let preCapUsage = myTeam?.currentCapUsage ?? 0
        let preOVR = myRoster.isEmpty ? 0 : myRoster.reduce(0) { $0 + $1.overall } / myRoster.count
        let idealCounts = PositionGradeCalculator.idealStarterCounts
        var starterGaps = 0
        for (pos, needed) in idealCounts {
            let have = myRoster.filter { $0.position == pos }.count
            if have < needed { starterGaps += (needed - have) }
        }
        let baseCap = myTeam?.salaryCap ?? ContractEngine.openingSalaryCap

        summary = FreeAgencyEngine.executeNewLeagueYear(
            allPlayers: allPlayers,
            allTeams: allTeams,
            playerTeamID: teamID,
            modelContext: modelContext,
            career: career
        )

        // Track lost players (those who were on our team and became FAs)
        if let summary {
            let myAbbr = myTeam?.abbreviation ?? ""
            let lostIDs = summary.newFreeAgents
                .filter { $0.formerTeam == myAbbr }
                .compactMap { fa in
                    allPlayers.first { $0.fullName == fa.name }?.id
                }
            FASigningTracker.trackLostPlayers(lostIDs)
            FASigningTracker.savePreFASnapshot(
                capUsage: preCapUsage,
                rosterOVR: preOVR,
                starterGaps: starterGaps,
                baseSalaryCap: baseCap
            )
        }
    }
}
