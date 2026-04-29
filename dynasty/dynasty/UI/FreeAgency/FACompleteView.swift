import SwiftUI
import SwiftData

struct FACompleteView: View {

    let career: Career

    @Environment(\.modelContext) private var modelContext

    @State private var team: Team?
    @State private var recentSignings: [SigningDetail] = []
    @State private var lostPlayers: [LostPlayerDetail] = []
    @State private var leagueSignings: [LeagueSigningDetail] = []
    @State private var faGrade: FAGradeResult = .init(grade: "C", explanation: "Evaluating...", score: 50)
    @State private var beforeAfter: BeforeAfterComparison?
    @State private var remainingNeeds: [(position: Position, level: String)] = []
    @State private var compPickEstimate: [String] = []
    @State private var mediaQuote: String = ""
    @State private var baseSalaryCap: Int = 265_000
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
        let guaranteedMoney: Int
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
                        .foregroundColor(.secondary)
                }
            } else {
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
                    continueButton
                }
                .padding(24)
                .frame(maxWidth: .infinity)
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

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.success)

            Text("FREE AGENCY COMPLETE")
                .font(.title2.weight(.black))
                .foregroundStyle(Color.accentGold)

            Text("All free agency rounds are finished. Your roster has been updated.")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 16)
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
                    improved: true
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

    private func comparisonRow(label: String, before: String, after: String, improved: Bool) -> some View {
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
                .foregroundStyle(improved ? Color.success : Color.warning)
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
                    .font(.system(size: 56, weight: .black))
                    .foregroundStyle(PositionGradeCalculator.gradeColorForLetter(faGrade.grade))
                    .frame(width: 80)

                VStack(alignment: .leading, spacing: 6) {
                    Text(faGrade.explanation)
                        .font(.subheadline)
                        .foregroundStyle(Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.surfaceBorder, lineWidth: 1))
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
                            .background(Color.accentBlue, in: RoundedRectangle(cornerRadius: 4))

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
                                        in: RoundedRectangle(cornerRadius: 4))
                    }

                    // Contract details
                    HStack(spacing: 12) {
                        Label("\(signing.years)yr", systemImage: "calendar")
                        Label(formatMillions(signing.totalValue) + " total", systemImage: "dollarsign.circle")
                        Label(formatMillions(signing.guaranteedMoney) + " gtd", systemImage: "lock.fill")
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
                        .background(Color.danger.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))

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
                        .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: 4))
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
                        .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: 4))

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
                        .font(.system(size: 5))
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

    // MARK: - Continue Button

    private var continueButton: some View {
        Button {
            WeekAdvancer.advanceWeek(career: career, modelContext: modelContext)
        } label: {
            HStack(spacing: 10) {
                Text("Continue to Pro Days")
                    .font(.headline)
                Image(systemName: "arrow.right")
                    .font(.title3)
            }
            .foregroundStyle(Color.backgroundPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.accentGold, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

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

    // MARK: - Load Data

    private func loadData() {
        guard let teamID = career.teamID else { return }
        let teamDesc = FetchDescriptor<Team>(predicate: #Predicate { $0.id == teamID })
        team = try? modelContext.fetch(teamDesc).first
        guard let team else { return }

        let allTeams = (try? modelContext.fetch(FetchDescriptor<Team>())) ?? []
        let allPlayers = (try? modelContext.fetch(FetchDescriptor<Player>())) ?? []
        let myPlayers = allPlayers.filter { $0.teamID == teamID }
        baseSalaryCap = FASigningTracker.getBaseSalaryCap()

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
                guaranteedMoney: Int(Double(player.annualSalary * player.contractYearsRemaining) * 0.55),
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
        let currentOVR = myPlayers.isEmpty ? 0 : myPlayers.reduce(0) { $0 + $1.overall } / myPlayers.count
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
        if !lostPlayers.isEmpty {
            let lostValue = lostIDs.compactMap { id in allPlayers.first { $0.id == id } }
                .reduce(0) { $0 + ContractEngine.estimateMarketValue(player: $1, salaryCap: team.salaryCap) }
            let gainedValue = signedPlayers
                .reduce(0) { $0 + ContractEngine.estimateMarketValue(player: $1, salaryCap: team.salaryCap) }
            let delta = lostValue - gainedValue
            if delta > 0 {
                let numPicks = min(delta / 5_000, 4)
                compPickEstimate = (0..<numPicks).map { i in
                    let round = min(3 + i, 7)
                    return "Round \(round) compensatory pick"
                }
            }
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

        // OVR improvement
        if let ba = beforeAfter {
            let ovrDelta = ba.rosterOVRAfter - ba.rosterOVRBefore
            score += Double(ovrDelta) * 3.0

            let gapReduction = ba.starterGapsBefore - ba.starterGapsAfter
            score += Double(gapReduction) * 4.0
        }

        // Penalty for remaining high needs
        let remainingHigh = remainingNeeds.filter { $0.level == "High" }.count
        score -= Double(remainingHigh) * 5.0

        // Bonus if no signings were needed and none made (maintained a good team)
        if signings.isEmpty && lostPlayers.isEmpty {
            score = 70 // B- baseline for a team that didn't need FA
        }

        // Clamp
        score = max(20, min(100, score))

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

        return FAGradeResult(grade: grade, explanation: explanation, score: Int(score))
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
                "ESPN: '\(teamAbbr) had an impressive free agency, headlined by the \(signing.name) signing at \(signing.position.rawValue). Grade: \(grade.grade)'",
                "NFL Network: 'The \(teamName) addressed their needs this offseason. The \(signing.name) addition gives them a real boost. Grade: \(grade.grade)'",
                "The Athletic: '\(teamAbbr) were one of the winners of free agency. \(signing.name) is a significant upgrade. Grade: \(grade.grade)'"
            ]
            return templates[abs(teamAbbr.hashValue) % templates.count]
        } else if let loss = topLoss, grade.score < 55 {
            let templates = [
                "ESPN: '\(teamAbbr) failed to replace \(loss.name) adequately. A lot of work to do in the draft. Grade: \(grade.grade)'",
                "NFL Network: 'Losing \(loss.name) hurts, and \(teamAbbr) didn\u{2019}t do enough to fill the void. Grade: \(grade.grade)'",
                "The Athletic: 'A quiet free agency for \(teamAbbr). The draft becomes critical now. Grade: \(grade.grade)'"
            ]
            return templates[abs(teamAbbr.hashValue) % templates.count]
        } else if let signing = topSigning {
            let templates = [
                "ESPN: '\(teamAbbr) made some moves, highlighted by \(signing.name). A solid but unspectacular FA. Grade: \(grade.grade)'",
                "NFL Network: 'The \(teamName) were selective in free agency. \(signing.name) is the key pickup. Grade: \(grade.grade)'",
                "The Athletic: '\(teamAbbr) took a measured approach to FA. The real work starts in the draft. Grade: \(grade.grade)'"
            ]
            return templates[abs(teamAbbr.hashValue) % templates.count]
        } else {
            return "ESPN: '\(teamAbbr) were quiet in free agency. All eyes on the draft now. Grade: \(grade.grade)'"
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
