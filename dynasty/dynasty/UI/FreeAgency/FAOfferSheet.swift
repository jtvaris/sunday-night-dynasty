import SwiftUI
import SwiftData

struct FAOfferSheet: View {

    let player: Player
    let career: Career
    let team: Team
    let marketValue: Int
    /// R23 — inputs for the live signing-interest meter. Defaults keep older
    /// call sites compiling; without roster data the role factor is neutral.
    var allPlayers: [Player] = []
    var offensiveScheme: OffensiveScheme? = nil
    var defensiveScheme: DefensiveScheme? = nil
    var hostedVisit: Bool = false
    let onSubmit: (Int, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var offerSalary: Int = 5000
    @State private var offerYears: Int = 2
    @State private var comparables: [ComparableSigning] = []

    /// A recent contract used to ground player expectations.
    struct ComparableSigning: Identifiable {
        let id: UUID
        let name: String
        let position: Position
        let overall: Int
        let annualSalary: Int
        let years: Int
        let teamAbbr: String
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        playerInfoCard
                        offerTermsCard
                        interestCard
                        capImpactCard
                        if !comparables.isEmpty {
                            comparablesCard
                        }
                        submitButton
                    }
                    .padding(24)
                    .frame(maxWidth: 500)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Make Offer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .onAppear {
                offerSalary = marketValue
                offerYears = 2
                loadComparables()
            }
        }
    }

    // MARK: - Player Info

    private var playerInfoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(player.position.rawValue)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                    .frame(width: 34)
                    .padding(.vertical, 4)
                    .background(positionSideColor, in: RoundedRectangle(cornerRadius: 4))

                VStack(alignment: .leading, spacing: 2) {
                    Text(player.fullName)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Color.textPrimary)
                    HStack(spacing: 8) {
                        Text("\(player.overall) OVR")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Color.forRating(player.overall))
                        Text("Age \(player.age)")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                Spacer()
            }

            HStack(spacing: 12) {
                statPill(label: "Asking", value: formatMillions(marketValue) + "/yr")
                statPill(label: "Motivation", value: player.personality.motivation.rawValue)
            }
        }
        .padding(16)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.surfaceBorder, lineWidth: 1))
    }

    // MARK: - Offer Terms

    private var offerTermsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Contract Terms")
                .font(.headline)
                .foregroundStyle(Color.accentGold)

            // Years
            HStack {
                Text("Years:")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Stepper("\(offerYears)", value: $offerYears, in: 1...5)
                    .font(.subheadline.weight(.bold).monospacedDigit())
            }

            // Salary
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Annual Salary:")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Text(formatMillions(offerSalary) + "/yr")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.accentGold)
                }
                Slider(
                    value: Binding(
                        get: { Double(offerSalary) },
                        set: { offerSalary = Int(($0 / 500).rounded()) * 500 }
                    ),
                    in: 500...75000,
                    step: 500
                )
                .tint(Color.accentGold)
            }

            // Total value
            HStack {
                Text("Total Value:")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Text(formatMillions(offerSalary * offerYears))
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(Color.textPrimary)
            }

            // vs market
            let diff = offerSalary - marketValue
            HStack {
                Text("vs. Asking Price:")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                Spacer()
                Text(diff >= 0 ? "+\(formatMillions(diff))" : formatMillions(diff))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(diff >= 0 ? Color.success : Color.danger)
            }
        }
        .padding(16)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.surfaceBorder, lineWidth: 1))
    }

    // MARK: - R23: Signing Interest (live, updates with the offer slider)

    private var currentBreakdown: SigningInterestEngine.Breakdown {
        SigningInterestEngine.interest(
            player: player,
            askingPrice: marketValue,
            offer: (salary: offerSalary, years: offerYears),
            team: team,
            allPlayers: allPlayers,
            offensiveScheme: offensiveScheme,
            defensiveScheme: defensiveScheme,
            hostedVisit: hostedVisit
        )
    }

    private var interestCard: some View {
        let breakdown = currentBreakdown

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "gauge.with.needle")
                    .font(.caption)
                    .foregroundStyle(Color.accentGold)
                Text("Signing Interest")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                if hostedVisit {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 8))
                        Text("VISIT BOOST")
                            .font(.system(size: 8, weight: .black))
                    }
                    .foregroundStyle(Color.success)
                }
            }

            InterestMeterBar(breakdown: breakdown)

            // Factor rows — the same inputs the player weighs on decision day.
            VStack(spacing: 6) {
                factorRow(
                    label: "Money vs. asking",
                    value: breakdown.money,
                    note: offerSalary >= marketValue ? "At or above his number" : "Below his asking price"
                )
                factorRow(
                    label: "Team success",
                    value: breakdown.teamSuccess,
                    note: "\(team.wins)-\(team.losses) last season"
                )
                factorRow(
                    label: "Projected role",
                    value: breakdown.role,
                    note: roleNoteShort(breakdown.role)
                )
                if let scheme = breakdown.schemeFit {
                    factorRow(
                        label: "Scheme fit",
                        value: scheme,
                        note: scheme >= 0.6 ? "Fits your system" : (scheme >= 0.4 ? "Workable fit" : "Awkward fit")
                    )
                }
            }
        }
        .padding(16)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.surfaceBorder, lineWidth: 1))
    }

    private func factorRow(label: String, value: Double, note: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.textSecondary)
                .frame(width: 100, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.backgroundTertiary)
                    Capsule()
                        .fill(factorColor(value))
                        .frame(width: max(3, geo.size.width * value))
                }
            }
            .frame(height: 5)
            Text(note)
                .font(.system(size: 8))
                .foregroundStyle(Color.textTertiary)
                .frame(width: 110, alignment: .trailing)
                .lineLimit(2)
        }
    }

    private func factorColor(_ value: Double) -> Color {
        if value >= 0.65 { return .success }
        if value >= 0.4 { return .warning }
        return .danger
    }

    private func roleNoteShort(_ role: Double) -> String {
        switch role {
        case 0.9...:   return "Clear starter for you"
        case 0.6...:   return "Competes to start"
        case 0.3...:   return "Rotational role"
        default:       return "Buried on depth chart"
        }
    }

    // MARK: - Cap Impact (live recalculation as slider moves)

    private var capImpactCard: some View {
        let remaining = team.availableCap - offerSalary
        let capPct = team.salaryCap > 0 ? Double(offerSalary) / Double(team.salaryCap) : 0
        let usagePct = max(0, min(1, capPct))
        let barColor: Color = {
            if remaining < 0 { return .danger }
            if usagePct > 0.15 { return .warning }
            return .success
        }()

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Cap Impact")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Text(String(format: "%.1f%% of cap", usagePct * 100))
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(barColor)
            }

            // Live cap usage bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.backgroundTertiary)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(barColor)
                        .frame(width: geo.size.width * usagePct)
                }
            }
            .frame(height: 8)
            .animation(.easeOut(duration: 0.15), value: offerSalary)

            HStack {
                Text("Current Available:")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                Spacer()
                Text(formatMillions(team.availableCap))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.textPrimary)
            }
            HStack {
                Text("After Signing:")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                Spacer()
                Text(formatMillions(remaining))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(remaining >= 0 ? Color.success : Color.danger)
            }

            // Multi-year total commitment
            HStack {
                Text("Total Commitment (\(offerYears)yr):")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                Spacer()
                Text(formatMillions(offerSalary * offerYears))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.textPrimary)
            }
        }
        .padding(16)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.surfaceBorder, lineWidth: 1))
    }

    // MARK: - Comparable Recent Signings

    private var comparablesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.caption)
                    .foregroundStyle(Color.accentBlue)
                Text("Comparable Recent Signings")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Text("\(comparables.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Color.textTertiary)
            }
            Text("Similar \(player.position.rawValue)s, OVR \(player.overall - 4)–\(player.overall + 4)")
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)

            Divider().overlay(Color.surfaceBorder)

            ForEach(comparables) { comp in
                HStack(spacing: 8) {
                    Text(comp.position.rawValue)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.textPrimary)
                        .frame(width: 28)
                        .padding(.vertical, 2)
                        .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: 3))
                    Text(comp.name)
                        .font(.caption)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    Text("\(comp.overall)")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color.forRating(comp.overall))
                    Spacer()
                    Text(comp.teamAbbr)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.accentBlue)
                    Text(formatMillions(comp.annualSalary) + "/yr")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(highlightSalary(comp.annualSalary))
                    Text("(\(comp.years)yr)")
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                }
            }

            // Avg
            let avgSalary = comparables.reduce(0) { $0 + $1.annualSalary } / max(1, comparables.count)
            Divider().overlay(Color.surfaceBorder)
            HStack {
                Text("Avg comparable:")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Text(formatMillions(avgSalary) + "/yr")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(Color.accentGold)
                let diff = offerSalary - avgSalary
                Text(diff >= 0 ? "(+\(formatMillions(diff)))" : "(\(formatMillions(diff)))")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(diff >= 0 ? Color.success : Color.warning)
            }
        }
        .padding(16)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.surfaceBorder, lineWidth: 1))
    }

    private func highlightSalary(_ salary: Int) -> Color {
        // Color the comp salary relative to the user's current offer
        let diff = Double(salary - offerSalary) / Double(max(offerSalary, 1))
        if abs(diff) < 0.10 { return .textPrimary }
        return diff > 0 ? .success : .warning
    }

    // MARK: - Load Comparables

    private func loadComparables() {
        // Find players at the same position, similar OVR, currently under contract
        // (i.e. recently signed). Sample up to 4.
        let targetOVR = player.overall
        let position = player.position
        let descriptor = FetchDescriptor<Player>(
            predicate: #Predicate { p in
                p.contractYearsRemaining > 0 && p.teamID != nil
            }
        )
        let allSigned = (try? modelContext.fetch(descriptor)) ?? []
        let similar = allSigned
            .filter { $0.id != player.id && $0.position == position && abs($0.overall - targetOVR) <= 4 }
            .sorted { abs($0.overall - targetOVR) < abs($1.overall - targetOVR) }
            .prefix(8)

        // Map to display, looking up team abbreviations
        let allTeams = (try? modelContext.fetch(FetchDescriptor<Team>())) ?? []
        let mapped = similar.compactMap { p -> ComparableSigning? in
            guard p.annualSalary > 0 else { return nil }
            let abbr = allTeams.first(where: { $0.id == p.teamID })?.abbreviation ?? "?"
            return ComparableSigning(
                id: p.id,
                name: p.fullName,
                position: p.position,
                overall: p.overall,
                annualSalary: p.annualSalary,
                years: max(1, p.contractYearsRemaining),
                teamAbbr: abbr
            )
        }
        // Take top 4
        comparables = Array(mapped.prefix(4))
    }

    // MARK: - Submit

    private var submitButton: some View {
        Button {
            onSubmit(offerSalary, offerYears)
            dismiss()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "signature")
                Text("Submit Offer")
                    .font(.headline)
            }
            .foregroundStyle(Color.backgroundPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.accentGold, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private var positionSideColor: Color {
        switch player.position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }

    private func statPill(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label + ":")
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.textPrimary)
        }
    }

    private func formatMillions(_ thousands: Int) -> String {
        let millions = Double(thousands) / 1000.0
        if millions >= 1.0 {
            return String(format: "$%.1fM", millions)
        } else {
            return "$\(thousands)K"
        }
    }
}
