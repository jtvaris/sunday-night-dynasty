import SwiftUI
import SwiftData

struct HireCoachView: View {

    let role: CoachRole
    let teamID: UUID
    let remainingBudget: Int
    var onHired: ((String, String) -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var allCoaches: [Coach]

    @State private var candidates: [Coach] = []
    @State private var hiredCoachID: UUID?
    @State private var sortColumn: SortColumn = .ovr
    @State private var sortAscending: Bool = false
    @State private var selectedCandidate: Coach?
    @State private var showAffordableOnly: Bool = false
    @State private var schemeFilter: String = "All"
    @State private var showValueLegend: Bool = false
    @State private var showSchemeTip: Bool = false

    /// The team's head coach, used to determine current team scheme for fit indicator.
    private var teamHeadCoach: Coach? {
        allCoaches.first { $0.teamID == teamID && $0.role == .headCoach }
    }

    /// The current coach in the role being hired for (Fix #63: comparison).
    private var currentCoach: Coach? {
        allCoaches.first { $0.teamID == teamID && $0.role == role }
    }

    // MARK: - Sort Column

    enum SortColumn: String, CaseIterable {
        case name    = "Name"
        case age     = "Age"
        case scheme  = "Scheme"
        case ovr     = "OVR"
        case play    = "Play"
        case dev     = "Dev"
        case game    = "Game"
        case salary  = "Salary"
        case value   = "Value"
    }

    // MARK: - Helpers

    private func coachOverall(_ coach: Coach) -> Int {
        let sum = coach.playCalling + coach.playerDevelopment + coach.gamePlanning
            + coach.scoutingAbility + coach.recruiting + coach.motivation
            + coach.discipline + coach.adaptability + coach.mediaHandling
            + coach.contractNegotiation + coach.moraleInfluence + coach.reputation
        return sum / 12
    }

    /// Fix #60: Value score — skill-to-salary ratio normalized to a label.
    private func valueScore(_ coach: Coach) -> (label: String, color: Color) {
        let ovr = coachOverall(coach)
        let salaryM = max(Double(coach.salary) / 1000.0, 0.1)
        let ratio = Double(ovr) / salaryM  // Higher = better value
        if ratio >= 40 { return ("Great", .success) }
        if ratio >= 25 { return ("Good", .accentBlue) }
        if ratio >= 15 { return ("Fair", .warning) }
        return ("Poor", .danger)
    }

    private func valueRatio(_ coach: Coach) -> Double {
        let ovr = coachOverall(coach)
        let salaryM = max(Double(coach.salary) / 1000.0, 0.1)
        return Double(ovr) / salaryM
    }

    /// Fix #56: Top-3 candidate indices in the current sorted list.
    private var top3IDs: Set<UUID> {
        // Rank by OVR regardless of current sort
        let byOVR = filteredCandidates.sorted { coachOverall($0) > coachOverall($1) }
        return Set(byOVR.prefix(3).map { $0.id })
    }

    /// Available scheme names for the filter dropdown (Fix #58).
    private var availableSchemes: [String] {
        var schemes = Set<String>()
        for c in candidates {
            if let o = c.offensiveScheme { schemes.insert(o.displayName) }
            if let d = c.defensiveScheme { schemes.insert(d.displayName) }
        }
        return ["All"] + schemes.sorted()
    }

    // MARK: - Filtered & Sorted Candidates

    private var filteredCandidates: [Coach] {
        var list = candidates
        if showAffordableOnly {
            list = list.filter { $0.salary <= remainingBudget }
        }
        // Fix #58: Scheme filter
        if schemeFilter != "All" {
            list = list.filter { schemeLabel($0) == schemeFilter }
        }
        return list
    }

    private var sortedCandidates: [Coach] {
        let list = filteredCandidates
        let sorted: [Coach]
        switch sortColumn {
        case .name:    sorted = list.sorted { $0.lastName < $1.lastName }
        case .age:     sorted = list.sorted { $0.age < $1.age }
        case .scheme:  sorted = list.sorted { schemeLabel($0) < schemeLabel($1) }
        case .ovr:     sorted = list.sorted { coachOverall($0) > coachOverall($1) }
        case .play:    sorted = list.sorted { $0.playCalling > $1.playCalling }
        case .dev:     sorted = list.sorted { $0.playerDevelopment > $1.playerDevelopment }
        case .game:    sorted = list.sorted { $0.gamePlanning > $1.gamePlanning }
        case .salary:  sorted = list.sorted { $0.salary < $1.salary }
        case .value:   sorted = list.sorted { valueRatio($0) > valueRatio($1) }
        }
        return sortAscending ? sorted.reversed() : sorted
    }

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            GeometryReader { geo in
                Image("BgCoachStadium1")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .opacity(0.15)
            }
            .ignoresSafeArea()

            LinearGradient(
                colors: [Color.backgroundPrimary.opacity(0.85), Color.backgroundPrimary.opacity(0.5), Color.backgroundPrimary.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Sticky budget header + filter
                budgetHeader
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.backgroundSecondary)

                Divider().overlay(Color.surfaceBorder)

                // #149: Horizontally scrollable table for cramped columns
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Sticky column headers
                        tableHeaderRow
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.backgroundTertiary.opacity(0.6))

                        Divider().overlay(Color.surfaceBorder)

                        // Candidate rows
                        ScrollView(.vertical) {
                            LazyVStack(spacing: 0) {
                                ForEach(sortedCandidates) { candidate in
                                    candidateRow(candidate)

                                    Divider()
                                        .overlay(Color.surfaceBorder.opacity(0.4))
                                        .padding(.horizontal, 12)
                                }
                            }
                        }
                    }
                    .frame(minWidth: 620)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Hire \(role.displayName)")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            if candidates.isEmpty {
                let count = Int.random(in: 20...30)
                candidates = CoachingEngine.generateCoachCandidates(role: role, count: count)
            }
        }
        // #157: Full screen cover on iPad for max space
        .fullScreenCover(item: $selectedCandidate) { candidate in
            CandidateDetailSheet(
                candidate: candidate,
                remainingBudget: remainingBudget,
                isHired: hiredCoachID == candidate.id,
                headCoach: teamHeadCoach,
                currentCoach: currentCoach,
                candidateRank: candidateRank(for: candidate),
                totalCandidates: filteredCandidates.count,
                schemeFitResult: schemeFit(for: candidate),
                onHire: { hire(candidate) }
            )
        }
    }

    // MARK: - Budget Header

    private var budgetHeader: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Budget Remaining")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                    Text("$\(formatBudget(remainingBudget))M")
                        .font(.headline.weight(.bold).monospacedDigit())
                        .foregroundStyle(remainingBudget > 0 ? Color.success : Color.danger)
                }
                Spacer()

                // Fix #58: Scheme filter dropdown
                Menu {
                    ForEach(availableSchemes, id: \.self) { scheme in
                        Button {
                            schemeFilter = scheme
                        } label: {
                            HStack {
                                Text(scheme)
                                if schemeFilter == scheme {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 12))
                        Text(schemeFilter == "All" ? "Scheme" : schemeFilter)
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(schemeFilter == "All" ? Color.textSecondary : Color.accentGold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: 6))
                }

                Spacer().frame(width: 8)

                // Fix #39: Affordable-only toggle
                Toggle(isOn: $showAffordableOnly) {
                    Text("Affordable")
                        .font(.caption2)
                        .foregroundStyle(Color.textSecondary)
                }
                .toggleStyle(.switch)
                .tint(Color.accentGold)
                .fixedSize()

                Spacer().frame(width: 16)

                Text("\(filteredCandidates.count) candidates")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            // #153: Value column legend
            if showValueLegend {
                HStack(spacing: 12) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.accentGold)
                    Text("Val = skill-to-salary ratio: Great = high skill/low salary, Poor = low skill/high salary")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Button { showValueLegend = false } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.textTertiary)
                    }
                }
                .padding(8)
                .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: 6))
            }

            // #151: Scheme info tooltip
            if showSchemeTip, let first = sortedCandidates.first {
                let label = schemeLabel(first)
                let desc = schemeDescription(label)
                if !desc.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.accentBlue)
                        Text("\(label): \(desc)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        Button { showSchemeTip = false } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.textTertiary)
                        }
                    }
                    .padding(8)
                    .background(Color.accentBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                }
            }

            // Fix #63: Current coach comparison bar
            if let current = currentCoach {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.accentGold)
                    Text("Replacing:")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.textTertiary)
                    Text(current.fullName)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.textPrimary)
                    Text("OVR \(coachOverall(current))")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.forRating(coachOverall(current)))
                    Text("\u{00B7}")
                        .foregroundStyle(Color.textTertiary)
                    Text(salaryFormatted(current.salary))
                        .font(.caption2.weight(.medium).monospacedDigit())
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.accentGold.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    // MARK: - Table Header (Fix #42: simplified columns — OVR + numeric skills)

    private var tableHeaderRow: some View {
        HStack(spacing: 0) {
            headerButton("Name", column: .name, width: nil, alignment: .leading)
            headerButton("Age", column: .age, width: 34)
            // #151: Scheme column with info button
            Button {
                showSchemeTip.toggle()
            } label: {
                HStack(spacing: 2) {
                    Text("Scheme")
                    Image(systemName: "info.circle")
                        .font(.system(size: 7))
                        .foregroundStyle(Color.accentBlue.opacity(0.6))
                }
                .frame(width: 62)
            }
            .foregroundStyle(sortColumn == .scheme ? Color.accentGold : Color.textTertiary)
            // Fix #38: Scheme fit column header
            if teamHeadCoach != nil || !candidates.isEmpty {
                Text("Fit")
                    .frame(width: 32)
            }
            headerButton("OVR", column: .ovr, width: 36)
            headerButton("Play", column: .play, width: 36)
            headerButton("Dev", column: .dev, width: 36)
            headerButton("Game", column: .game, width: 36)
            headerButton("Salary", column: .salary, width: 56)
            // Fix #60 + #153: Value column with info legend
            Button {
                showValueLegend.toggle()
            } label: {
                HStack(spacing: 2) {
                    Text("Val")
                    Image(systemName: "info.circle")
                        .font(.system(size: 7))
                        .foregroundStyle(Color.accentGold.opacity(0.6))
                }
                .frame(width: 40)
            }
            .foregroundStyle(sortColumn == .value ? Color.accentGold : Color.textTertiary)
            // Status column
            Text("")
                .frame(width: 30)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(Color.textTertiary)
    }

    private func headerButton(_ title: String, column: SortColumn, width: CGFloat?, alignment: Alignment = .center) -> some View {
        Button {
            if sortColumn == column {
                sortAscending.toggle()
            } else {
                sortColumn = column
                sortAscending = false
            }
        } label: {
            HStack(spacing: 2) {
                Text(title)
                if sortColumn == column {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 7))
                }
            }
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
            .frame(width: width)
        }
        .foregroundStyle(sortColumn == column ? Color.accentGold : Color.textTertiary)
    }

    // MARK: - Candidate Row (Fix #42: one star rating + numeric skill values)

    private func candidateRow(_ candidate: Coach) -> some View {
        let isOverBudget = candidate.salary > remainingBudget
        let isHired = hiredCoachID == candidate.id
        let ovr = coachOverall(candidate)
        let isTop3 = top3IDs.contains(candidate.id)
        let val = valueScore(candidate)
        // Fix #63: OVR delta vs current coach
        let ovrDelta: Int? = currentCoach.map { coachOverall(candidate) - coachOverall($0) }

        return Button {
            selectedCandidate = candidate
        } label: {
            HStack(spacing: 0) {
                // Fix #55: Larger name area with personality + top-3 badge
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(candidate.fullName)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(isOverBudget ? Color.textTertiary : Color.textPrimary)
                            .lineLimit(1)
                        // Potential label badge
                        let potLabel = candidate.potentialLabel(seasonsOnTeam: 0)
                        Text(potLabel)
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(potentialBadgeColor(potLabel))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(potentialBadgeColor(potLabel).opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                        // Fix #56: Best Available badge for top 3
                        if isTop3 {
                            Text("TOP")
                                .font(.system(size: 7, weight: .black))
                                .foregroundStyle(Color.backgroundPrimary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.accentGold, in: RoundedRectangle(cornerRadius: 3))
                        }
                    }
                    HStack(spacing: 4) {
                        // Fix #59 + #148: Coaching personality — shorter labels to avoid truncation
                        Text(candidate.personality.shortLabel)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color.accentBlue)
                            .lineLimit(1)
                        // Fix #63: OVR delta vs current
                        if let delta = ovrDelta {
                            Text(delta >= 0 ? "+\(delta)" : "\(delta)")
                                .font(.system(size: 9, weight: .bold).monospacedDigit())
                                .foregroundStyle(delta > 0 ? Color.success : delta < 0 ? Color.danger : Color.textTertiary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Age
                Text("\(candidate.age)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 34)

                // Scheme
                Text(schemeLabel(candidate))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.accentBlue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: 62)

                // Fix #38 + #152: Scheme/roster fit indicator (shows even without HC)
                if teamHeadCoach != nil || !candidates.isEmpty {
                    Group {
                        if let fit = schemeFit(for: candidate) {
                            Circle()
                                .fill(fit.color)
                                .frame(width: 8, height: 8)
                                .overlay(
                                    Circle()
                                        .strokeBorder(fit.color.opacity(0.5), lineWidth: 1)
                                )
                                .accessibilityLabel("Scheme fit: \(fit.label)")
                        } else {
                            Text("--")
                                .font(.system(size: 8))
                                .foregroundStyle(Color.textTertiary)
                        }
                    }
                    .frame(width: 32)
                }

                // OVR numeric
                Text("\(ovr)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.forRating(ovr))
                    .frame(width: 36)

                // Key skill numerics
                Text("\(candidate.playCalling)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.forRating(candidate.playCalling))
                    .frame(width: 36)

                Text("\(candidate.playerDevelopment)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.forRating(candidate.playerDevelopment))
                    .frame(width: 36)

                Text("\(candidate.gamePlanning)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.forRating(candidate.gamePlanning))
                    .frame(width: 36)

                // Salary
                Text(salaryFormatted(candidate.salary))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(isOverBudget ? Color.danger : Color.textSecondary)
                    .frame(width: 56)

                // Fix #60: Value badge
                Text(val.label)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(val.color)
                    .frame(width: 40)

                // Status indicator
                Group {
                    if isHired {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.success)
                    } else if isOverBudget {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.danger.opacity(0.5))
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.textTertiary)
                    }
                }
                .frame(width: 30)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isOverBudget ? 0.6 : 1.0)
        .background(
            Group {
                if isHired {
                    Color.success.opacity(0.06)
                } else if isTop3 {
                    // Fix #56: Subtle gold highlight for top 3
                    Color.accentGold.opacity(0.04)
                } else {
                    Color.clear
                }
            }
        )
        // Fix #56: Gold left border for top 3
        .overlay(alignment: .leading) {
            if isTop3 {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.accentGold)
                    .frame(width: 3)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(candidate.fullName), \(candidate.personality.displayName), age \(candidate.age), overall \(ovr), salary \(candidate.salary) thousand, value \(val.label)")
    }

    // MARK: - Helpers

    /// Color for potential label badge text.
    private func potentialBadgeColor(_ label: String) -> Color {
        switch label {
        case "Elite Ceiling":   return Color.accentGold
        case "High Ceiling":    return .green
        case "Solid Ceiling":   return Color.accentBlue
        case "Limited Upside":  return .orange
        case "Low Ceiling":     return .red
        default:                return Color.textSecondary
        }
    }

    private func schemeLabel(_ coach: Coach) -> String {
        if let o = coach.offensiveScheme { return o.displayName }
        if let d = coach.defensiveScheme { return d.displayName }
        return "--"
    }

    // MARK: - Scheme Fit (Fix #38)

    /// Determines how well a candidate's scheme fits the team's current scheme (via HC).
    /// Returns (color, label) for the fit indicator.
    private func schemeFit(for candidate: Coach) -> (color: Color, label: String)? {
        guard let hc = teamHeadCoach else { return nil }

        // Compare offensive schemes
        if let candidateOff = candidate.offensiveScheme {
            if let hcOff = hc.offensiveScheme {
                if candidateOff == hcOff {
                    return (.success, "Great")
                }
                // Similar scheme families
                let passingSchemes: Set<OffensiveScheme> = [.westCoast, .airRaid, .proPassing, .spread]
                let runSchemes: Set<OffensiveScheme> = [.powerRun, .shanahan, .option, .rpo]
                if (passingSchemes.contains(candidateOff) && passingSchemes.contains(hcOff))
                    || (runSchemes.contains(candidateOff) && runSchemes.contains(hcOff)) {
                    return (.warning, "OK")
                }
                return (.danger, "Poor")
            }
            return nil // HC has no offensive scheme set
        }

        // Compare defensive schemes
        if let candidateDef = candidate.defensiveScheme {
            if let hcDef = hc.defensiveScheme {
                if candidateDef == hcDef {
                    return (.success, "Great")
                }
                // Similar scheme families
                let frontSchemes: Set<DefensiveScheme> = [.base34, .base43]
                let coverageSchemes: Set<DefensiveScheme> = [.cover3, .tampa2, .pressMan]
                let flexSchemes: Set<DefensiveScheme> = [.multiple, .hybrid]
                if (frontSchemes.contains(candidateDef) && frontSchemes.contains(hcDef))
                    || (coverageSchemes.contains(candidateDef) && coverageSchemes.contains(hcDef))
                    || (flexSchemes.contains(candidateDef) && flexSchemes.contains(hcDef)) {
                    return (.warning, "OK")
                }
                return (.danger, "Poor")
            }
            return nil // HC has no defensive scheme set
        }

        return nil
    }

    private func salaryFormatted(_ thousands: Int) -> String {
        let millions = Double(thousands) / 1_000.0
        return String(format: "$%.1fM", millions)
    }

    private func formatBudget(_ thousands: Int) -> String {
        let millions = Double(thousands) / 1_000.0
        return String(format: "%.1f", millions)
    }

    /// #151: Scheme tooltip descriptions.
    private func schemeDescription(_ label: String) -> String {
        switch label {
        case "West Coast":  return "Short-to-intermediate passing, high-percentage throws"
        case "Air Raid":    return "Four/five-wide sets, vertical passing emphasis"
        case "Spread":      return "Space the field with spread formations"
        case "Power Run":   return "Downhill running with pulling guards"
        case "Shanahan":    return "Outside zone running, play-action boots"
        case "Pro Passing": return "Pro-style balanced attack, under-center play-action"
        case "RPO":         return "Run-pass options, QB reads defense post-snap"
        case "Option":      return "Triple/read-option, requires athletic QB"
        case "3-4 Base":    return "Versatile OLBs who rush and drop into coverage"
        case "4-3 Base":    return "Four down linemen generating pass rush"
        case "Cover 3":     return "Three deep defenders, four underneath zones"
        case "Press Man":   return "Aggressive press coverage at the line"
        case "Tampa 2":     return "Zone coverage, requires fast MLB for deep middle"
        case "Multiple":    return "Disguised fronts and coverages pre-snap"
        case "Hybrid":      return "Blends 3-4/4-3 with positionless players"
        default:            return ""
        }
    }

    /// #160: OVR context label — league average comparison.
    private func ovrContextLabel(_ ovr: Int) -> String {
        if ovr >= 80 { return "Elite" }
        if ovr >= 70 { return "Above Avg" }
        if ovr >= 60 { return "Average" }
        if ovr >= 50 { return "Below Avg" }
        return "Poor"
    }

    /// Fix #67: Candidate ranking by OVR among filtered list.
    private func candidateRank(for candidate: Coach) -> Int {
        let byOVR = filteredCandidates.sorted { coachOverall($0) > coachOverall($1) }
        if let idx = byOVR.firstIndex(where: { $0.id == candidate.id }) {
            return idx + 1
        }
        return 0
    }

    // MARK: - Hire Action

    private func hire(_ candidate: Coach) {
        guard candidate.salary <= remainingBudget else { return }

        let descriptor = FetchDescriptor<Coach>(
            predicate: #Predicate { $0.teamID == teamID }
        )
        if let existing = try? modelContext.fetch(descriptor) {
            existing.filter { $0.role == role }.forEach { modelContext.delete($0) }
        }

        candidate.teamID = teamID
        modelContext.insert(candidate)
        hiredCoachID = candidate.id

        // Fix #88: Save context before dismissing so CoachingStaffView's @Query refreshes
        try? modelContext.save()

        // Fix #49: Notify parent about the hire for toast display
        let hiredName = candidate.fullName
        let hiredRole = role.displayName

        // Fix #87: Dismiss sheet first, then pop HireCoachView after sheet animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            selectedCandidate = nil  // Close the sheet
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                onHired?(hiredName, hiredRole)
                dismiss()
            }
        }
    }
}

// MARK: - Candidate Detail / Negotiation Sheet

private struct CandidateDetailSheet: View {
    let candidate: Coach
    let remainingBudget: Int
    let isHired: Bool
    let headCoach: Coach?
    let currentCoach: Coach?
    let candidateRank: Int
    let totalCandidates: Int
    let schemeFitResult: (color: Color, label: String)?
    let onHire: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var proposedSalary: Double
    @State private var proposedYears: Int = 3
    @State private var negotiationResult: NegotiationResult?

    init(candidate: Coach, remainingBudget: Int, isHired: Bool, headCoach: Coach?, currentCoach: Coach?, candidateRank: Int, totalCandidates: Int, schemeFitResult: (color: Color, label: String)?, onHire: @escaping () -> Void) {
        self.candidate = candidate
        self.remainingBudget = remainingBudget
        self.isHired = isHired
        self.headCoach = headCoach
        self.currentCoach = currentCoach
        self.candidateRank = candidateRank
        self.totalCandidates = totalCandidates
        self.schemeFitResult = schemeFitResult
        self.onHire = onHire
        self._proposedSalary = State(initialValue: Double(candidate.salary))
    }

    private var askingSalary: Double { Double(candidate.salary) }

    /// Chance the candidate rejects a below-asking offer (0.0 - 1.0).
    private var rejectionChance: Double {
        guard proposedSalary < askingSalary else { return 0.0 }
        let discount = (askingSalary - proposedSalary) / askingSalary
        // Up to 90% rejection at 50%+ discount
        return min(0.9, discount * 1.8)
    }

    /// Fix #69: Acceptance likelihood label that updates with salary slider.
    private var acceptanceLikelihood: (label: String, color: Color) {
        let chance = 1.0 - rejectionChance
        if chance >= 0.95 { return ("Very High", .success) }
        if chance >= 0.75 { return ("High", .success) }
        if chance >= 0.50 { return ("Medium", .warning) }
        if chance >= 0.25 { return ("Low", .danger) }
        return ("Very Low", .danger)
    }

    private var isOverBudget: Bool {
        Int(proposedSalary) > remainingBudget
    }

    /// #162: Contract length effect description.
    private var contractLengthEffect: String {
        switch proposedYears {
        case 1:  return "Short deal: higher acceptance, but coach may leave soon"
        case 2:  return "Standard short: balanced flexibility and commitment"
        case 3:  return "Standard deal: good balance of cost and stability"
        case 4:  return "Long deal: coach expects slight discount, higher commitment"
        case 5:  return "Max deal: coach expects best terms, locked in long-term"
        default: return ""
        }
    }

    /// Fix #65: Budget remaining after this hire.
    private var budgetAfterHire: Int {
        remainingBudget - Int(proposedSalary)
    }

    /// #160: OVR context label.
    private func ovrContextLabel(_ ovr: Int) -> String {
        if ovr >= 80 { return "Elite" }
        if ovr >= 70 { return "Above Avg" }
        if ovr >= 60 { return "Average" }
        if ovr >= 50 { return "Below Avg" }
        return "Poor"
    }

    private func coachOverall(_ coach: Coach) -> Int {
        let sum = coach.playCalling + coach.playerDevelopment + coach.gamePlanning
            + coach.scoutingAbility + coach.recruiting + coach.motivation
            + coach.discipline + coach.adaptability + coach.mediaHandling
            + coach.contractNegotiation + coach.moraleInfluence + coach.reputation
        return sum / 12
    }

    /// Fix #68: Personality effect descriptions.
    private var personalityEffects: [(effect: String, icon: String)] {
        switch candidate.personality {
        case .teamLeader:        return [("Player morale +5%", "arrow.up"), ("Team chemistry +3%", "person.2")]
        case .loneWolf:          return [("Individual skill dev +8%", "figure.walk"), ("Team chemistry -3%", "person.2.slash")]
        case .feelPlayer:        return [("Adaptability +5%", "arrow.triangle.2.circlepath"), ("Consistency -3%", "waveform.path")]
        case .steadyPerformer:   return [("Consistency +5%", "equal.circle"), ("Development stability +3%", "chart.line.flattrend.xyaxis")]
        case .dramaQueen:        return [("Media handling +8%", "mic.fill"), ("Locker room drama risk +5%", "exclamationmark.bubble")]
        case .quietProfessional: return [("Discipline +5%", "checkmark.shield"), ("Media handling -3%", "mic.slash")]
        case .mentor:            return [("Player development +8%", "graduationcap"), ("Young player growth +5%", "figure.and.child.holdinghands")]
        case .fieryCompetitor:   return [("Motivation +8%", "flame"), ("Discipline risk +3%", "exclamationmark.triangle")]
        case .classClown:        return [("Morale boost +5%", "face.smiling"), ("Discipline -3%", "exclamationmark.triangle")]
        }
    }

    /// Fix #70: Pre-hire chemistry prediction with HC.
    private var chemistryPrediction: (label: String, color: Color, description: String) {
        guard let hc = headCoach else {
            return ("Unknown", .textTertiary, "No Head Coach on staff to evaluate chemistry.")
        }

        // Simple personality compatibility matrix
        let compatiblePairs: Set<Set<String>> = [
            ["TeamLeader", "QuietProfessional"],
            ["Mentor", "SteadyPerformer"],
            ["FieryCompetitor", "TeamLeader"],
            ["Mentor", "TeamLeader"],
            ["QuietProfessional", "SteadyPerformer"],
        ]
        let clashingPairs: Set<Set<String>> = [
            ["DramaQueen", "QuietProfessional"],
            ["FieryCompetitor", "DramaQueen"],
            ["LoneWolf", "TeamLeader"],
            ["ClassClown", "FieryCompetitor"],
        ]

        let pair: Set<String> = [candidate.personality.rawValue, hc.personality.rawValue]

        if candidate.personality == hc.personality {
            return ("Neutral", .warning, "Same personality type (\(hc.personality.displayName)) — may overlap rather than complement.")
        }
        if compatiblePairs.contains(pair) {
            return ("Strong", .success, "\(candidate.personality.displayName) and \(hc.personality.displayName) complement each other well.")
        }
        if clashingPairs.contains(pair) {
            return ("Weak", .danger, "\(candidate.personality.displayName) may clash with HC's \(hc.personality.displayName) style.")
        }
        return ("Average", .textSecondary, "No strong synergy or conflict expected with \(hc.personality.displayName) HC.")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        // Fix #67: Candidate ranking badge
                        rankingBadge

                        // Profile header
                        profileHeader

                        // Fix #43: Prominent hire button at top of sheet
                        if !isHired && negotiationResult?.accepted != true {
                            quickHireButton
                        }

                        if isHired || negotiationResult?.accepted == true {
                            hiredBanner
                        }

                        // Fix #63: Comparison to current coach
                        if let current = currentCoach {
                            comparisonCard(current: current)
                        }

                        // Two-column layout for cards
                        HStack(alignment: .top, spacing: 12) {
                            VStack(spacing: 12) {
                                // All attributes
                                attributesCard
                                // Background story
                                if !candidate.background.isEmpty {
                                    backgroundCard
                                }
                            }
                            VStack(spacing: 12) {
                                // Fix #66: Scheme fit analysis
                                schemeFitCard
                                // Fix #68 + #70: Coaching style & chemistry
                                coachingStyleCard
                                // Negotiation section
                                negotiationCard
                            }
                        }

                        Spacer(minLength: 20)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Candidate Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    // MARK: - Ranking Badge (Fix #67)

    private var rankingBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "number")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.accentGold)
            Text("Ranked #\(candidateRank) of \(totalCandidates) candidates")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
            Spacer()
            if candidateRank <= 3 {
                Text("Best Available")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(Color.backgroundPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentGold, in: RoundedRectangle(cornerRadius: 4))
            }
        }
    }

    // MARK: - Profile Header

    private var profileHeader: some View {
        VStack(spacing: 12) {
            // Name + role badge
            HStack(spacing: 10) {
                Text(candidate.role.abbreviation)
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(Color.backgroundPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(candidate.role.badgeColor, in: RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.fullName)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color.textPrimary)

                    HStack(spacing: 8) {
                        Text("Age \(candidate.age)")
                        Text("\u{00B7}")
                        Text("\(candidate.yearsExperience) yrs experience")
                        Text("\u{00B7}")
                        Text(candidate.personality.displayName)
                            .foregroundStyle(Color.accentBlue)
                    }
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Overall rating + scheme + salary summary
            HStack(spacing: 12) {
                // #160: Overall badge with context label
                let ovr = coachOverall(candidate)
                VStack(spacing: 2) {
                    Text("\(ovr)")
                        .font(.system(size: 22, weight: .black).monospacedDigit())
                        .foregroundStyle(Color.forRating(ovr))
                    Text("OVR")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.textTertiary)
                    Text(ovrContextLabel(ovr))
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(Color.forRating(ovr).opacity(0.8))
                }
                .frame(width: 52, height: 58)
                .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: 8))

                if let off = candidate.offensiveScheme {
                    schemeTag(off.displayName, color: .accentBlue)
                }
                if let def = candidate.defensiveScheme {
                    schemeTag(def.displayName, color: .danger)
                }

                // Fix #66: Scheme fit badge in header
                if let fit = schemeFitResult {
                    HStack(spacing: 4) {
                        Circle().fill(fit.color).frame(width: 8, height: 8)
                        Text(fit.label)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(fit.color)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(fit.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
                }

                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Asking Salary")
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                    Text(salaryFormatted(candidate.salary))
                        .font(.headline.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.accentGold)
                }
            }
        }
        .padding(16)
        .cardBackground()
    }

    // MARK: - Quick Hire Button (Fix #43 + #65: budget impact)

    private var quickHireButton: some View {
        Button {
            proposedSalary = askingSalary
            proposedYears = 3
            makeOffer()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "handshake.fill")
                    .font(.system(size: 16, weight: .semibold))
                VStack(spacing: 2) {
                    Text("Offer Contract")
                        .font(.headline.weight(.bold))
                    // Fix #65: Budget impact
                    Text("at \(salaryFormatted(candidate.salary))/yr \u{00B7} Budget after: $\(formatBudget(remainingBudget - candidate.salary))M")
                        .font(.caption2)
                        .opacity(0.8)
                }
            }
            .foregroundStyle(Color.backgroundPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(candidate.salary > remainingBudget ? Color.backgroundTertiary : Color.accentGold)
            )
        }
        .disabled(candidate.salary > remainingBudget)
        .buttonStyle(.plain)
    }

    // MARK: - Hired Banner

    private var hiredBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.success)
            Text("Hired!")
                .font(.headline.weight(.bold))
                .foregroundStyle(Color.success)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.success.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.success.opacity(0.3), lineWidth: 1)
                )
        )
    }

    // MARK: - Comparison Card (Fix #63)

    private func comparisonCard(current: Coach) -> some View {
        let curOVR = coachOverall(current)
        let newOVR = coachOverall(candidate)
        let delta = newOVR - curOVR

        return VStack(alignment: .leading, spacing: 10) {
            Text("VS CURRENT \(candidate.role.displayName.uppercased())")
                .font(.system(size: 11, weight: .black))
                .tracking(1.5)
                .foregroundStyle(Color.accentGold)

            HStack(spacing: 16) {
                // Current
                VStack(spacing: 4) {
                    Text(current.fullName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                    Text("\(curOVR)")
                        .font(.system(size: 18, weight: .black).monospacedDigit())
                        .foregroundStyle(Color.forRating(curOVR))
                    Text(salaryFormatted(current.salary))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Color.textTertiary)
                }
                .frame(maxWidth: .infinity)

                // Arrow with delta
                VStack(spacing: 2) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.textTertiary)
                    Text(delta >= 0 ? "+\(delta)" : "\(delta)")
                        .font(.system(size: 12, weight: .bold).monospacedDigit())
                        .foregroundStyle(delta > 0 ? Color.success : delta < 0 ? Color.danger : Color.textTertiary)
                }

                // New candidate
                VStack(spacing: 4) {
                    Text(candidate.fullName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    Text("\(newOVR)")
                        .font(.system(size: 18, weight: .black).monospacedDigit())
                        .foregroundStyle(Color.forRating(newOVR))
                    Text(salaryFormatted(candidate.salary))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Color.textTertiary)
                }
                .frame(maxWidth: .infinity)
            }

            // Key attribute comparison
            let comparisons: [(String, Int, Int)] = [
                ("Play Calling", current.playCalling, candidate.playCalling),
                ("Player Dev", current.playerDevelopment, candidate.playerDevelopment),
                ("Game Plan", current.gamePlanning, candidate.gamePlanning),
                ("Motivation", current.motivation, candidate.motivation),
            ]
            HStack(spacing: 6) {
                ForEach(comparisons, id: \.0) { name, curVal, newVal in
                    let d = newVal - curVal
                    VStack(spacing: 2) {
                        Text(name)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(Color.textTertiary)
                        Text(d >= 0 ? "+\(d)" : "\(d)")
                            .font(.system(size: 10, weight: .bold).monospacedDigit())
                            .foregroundStyle(d > 0 ? Color.success : d < 0 ? Color.danger : Color.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .cardBackground()
    }

    // MARK: - Attributes Card (Fix #64: color-coded)

    private var attributesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ATTRIBUTES")
                .font(.system(size: 11, weight: .black))
                .tracking(1.5)
                .foregroundStyle(Color.accentGold)

            // #158: Full attribute names (no truncation in 2-column layout)
            let attrs: [(String, Int)] = [
                ("Play Calling", candidate.playCalling),
                ("Player Development", candidate.playerDevelopment),
                ("Game Planning", candidate.gamePlanning),
                ("Scouting Ability", candidate.scoutingAbility),
                ("Recruiting", candidate.recruiting),
                ("Motivation", candidate.motivation),
                ("Discipline", candidate.discipline),
                ("Adaptability", candidate.adaptability),
                ("Media Handling", candidate.mediaHandling),
                ("Contract Negotiation", candidate.contractNegotiation),
                ("Morale Influence", candidate.moraleInfluence),
                ("Reputation", candidate.reputation),
            ]

            VStack(spacing: 8) {
                ForEach(0..<(attrs.count / 2), id: \.self) { rowIndex in
                    let left = attrs[rowIndex * 2]
                    let right = attrs[rowIndex * 2 + 1]
                    HStack(spacing: 8) {
                        attributeCell(name: left.0, value: left.1)
                        attributeCell(name: right.0, value: right.1)
                    }
                }
            }
        }
        .padding(16)
        .cardBackground()
    }

    /// Fix #64: Color-coded attribute cells with tier label.
    private func attributeCell(name: String, value: Int) -> some View {
        let tierLabel = attributeTierLabel(value)
        return HStack(spacing: 6) {
            Text(name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(tierLabel)
                .font(.system(size: 7, weight: .semibold))
                .foregroundStyle(Color.forRating(value).opacity(0.8))
            Text("\(value)")
                .font(.system(size: 16, weight: .bold).monospacedDigit())
                .foregroundStyle(Color.forRating(value))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.forRating(value).opacity(0.06))
        )
    }

    /// Tier label for attribute value (Fix #64).
    private func attributeTierLabel(_ value: Int) -> String {
        if value >= 90 { return "Elite" }
        if value >= 80 { return "Great" }
        if value >= 70 { return "Good" }
        if value >= 60 { return "Avg" }
        if value >= 50 { return "Below" }
        return "Poor"
    }

    // MARK: - Background Card

    private var backgroundCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BACKGROUND")
                .font(.system(size: 11, weight: .black))
                .tracking(1.5)
                .foregroundStyle(Color.accentGold)

            Text(candidate.background)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    // MARK: - Scheme Fit Card (Fix #66)

    private var schemeFitCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SCHEME FIT")
                .font(.system(size: 11, weight: .black))
                .tracking(1.5)
                .foregroundStyle(Color.accentGold)

            if let fit = schemeFitResult, let hc = headCoach {
                HStack(spacing: 10) {
                    Circle()
                        .fill(fit.color)
                        .frame(width: 14, height: 14)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Scheme Compatibility: \(fit.label)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(fit.color)
                        let hcScheme = hc.offensiveScheme?.displayName ?? hc.defensiveScheme?.displayName ?? "Unknown"
                        let candScheme = candidate.offensiveScheme?.displayName ?? candidate.defensiveScheme?.displayName ?? "Unknown"
                        Text("HC runs \(hcScheme) \u{00B7} Candidate prefers \(candScheme)")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            } else if headCoach == nil {
                // #159: Show candidate's scheme even without HC
                let candScheme = candidate.offensiveScheme?.displayName ?? candidate.defensiveScheme?.displayName ?? nil
                if let scheme = candScheme {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color.textTertiary)
                            .frame(width: 14, height: 14)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Candidate prefers: \(scheme)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.textPrimary)
                            Text("Hire a Head Coach first for scheme compatibility rating.")
                                .font(.caption)
                                .foregroundStyle(Color.textTertiary)
                        }
                    }
                } else {
                    Text("No scheme data available for comparison.")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }
            } else {
                Text("No scheme data available for comparison.")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    // MARK: - Coaching Style & Chemistry Card (Fix #68 + #70)

    private var coachingStyleCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("COACHING STYLE")
                .font(.system(size: 11, weight: .black))
                .tracking(1.5)
                .foregroundStyle(Color.accentGold)

            // Personality
            HStack(spacing: 8) {
                Image(systemName: "person.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.accentBlue)
                Text(candidate.personality.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
            }

            // Fix #68 + #161: Style effects — green for positive, red for negative
            ForEach(personalityEffects, id: \.effect) { item in
                let isNegative = item.effect.contains("-") || item.effect.lowercased().contains("risk")
                HStack(spacing: 6) {
                    Image(systemName: item.icon)
                        .font(.system(size: 10))
                        .foregroundStyle(isNegative ? Color.danger : Color.success)
                        .frame(width: 16)
                    Text(item.effect)
                        .font(.caption)
                        .foregroundStyle(isNegative ? Color.danger : Color.success)
                }
            }

            Divider().overlay(Color.surfaceBorder)

            // Fix #70: Chemistry prediction with HC
            let chem = chemistryPrediction
            HStack(spacing: 8) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(chem.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text("HC Chemistry: \(chem.label)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(chem.color)
                    Text(chem.description)
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    // MARK: - Negotiation Card

    private var negotiationCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("NEGOTIATE")
                .font(.system(size: 11, weight: .black))
                .tracking(1.5)
                .foregroundStyle(Color.accentGold)

            // Proposed salary slider
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Proposed Salary")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Text(salaryFormatted(Int(proposedSalary)))
                        .font(.headline.weight(.bold).monospacedDigit())
                        .foregroundStyle(isOverBudget ? Color.danger : Color.accentGold)
                }

                let minSalary = max(100, Double(candidate.salary) * 0.5)
                let maxSalary = Double(candidate.salary) * 1.3
                Slider(value: $proposedSalary, in: minSalary...maxSalary, step: 50)
                    .tint(Color.accentGold)

                HStack {
                    Text(salaryFormatted(Int(minSalary)))
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                    Spacer()
                    Text("Asking: \(salaryFormatted(candidate.salary))")
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                    Spacer()
                    Text(salaryFormatted(Int(maxSalary)))
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                }
            }

            // Fix #69: Acceptance likelihood
            HStack(spacing: 8) {
                Image(systemName: "gauge.medium")
                    .foregroundStyle(acceptanceLikelihood.color)
                Text("Acceptance: \(acceptanceLikelihood.label)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(acceptanceLikelihood.color)
                Spacer()
                // Fix #65: Budget after hire
                Text("Budget after: $\(formatBudget(budgetAfterHire))M")
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(budgetAfterHire >= 0 ? Color.textSecondary : Color.danger)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.backgroundTertiary.opacity(0.5))
            )

            // Contract years + #162: Show contract length effect
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Contract Length")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Text("\(proposedYears) year\(proposedYears == 1 ? "" : "s")")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color.textPrimary)
                }
                Stepper("Years", value: $proposedYears, in: 1...5)
                    .labelsHidden()

                // #162: Contract length effect on salary/acceptance
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textTertiary)
                    Text(contractLengthEffect)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                }
            }

            // Rejection warning
            if rejectionChance > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(rejectionChance > 0.5 ? Color.danger : Color.warning)
                    Text("Rejection risk: \(Int(rejectionChance * 100))%")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(rejectionChance > 0.5 ? Color.danger : Color.warning)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill((rejectionChance > 0.5 ? Color.danger : Color.warning).opacity(0.1))
                )
            }

            if isOverBudget {
                HStack(spacing: 8) {
                    Image(systemName: "dollarsign.circle.fill")
                        .foregroundStyle(Color.danger)
                    Text("Over budget")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.danger)
                }
            }

            // Negotiation result
            if let result = negotiationResult {
                HStack(spacing: 10) {
                    Image(systemName: result.accepted ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(result.accepted ? Color.success : Color.danger)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.accepted ? "Offer Accepted!" : "Offer Rejected")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(result.accepted ? Color.success : Color.danger)
                        Text(result.message)
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill((result.accepted ? Color.success : Color.danger).opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder((result.accepted ? Color.success : Color.danger).opacity(0.3), lineWidth: 1)
                        )
                )
            }

            // Make Offer button
            if !isHired && negotiationResult?.accepted != true {
                Button {
                    makeOffer()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "handshake.fill")
                            .font(.system(size: 16, weight: .semibold))
                        VStack(spacing: 2) {
                            Text("Offer Contract")
                                .font(.headline.weight(.bold))
                            // Fix #65: Budget impact on offer button
                            Text("Budget after hire: $\(formatBudget(budgetAfterHire))M remaining")
                                .font(.caption2)
                                .opacity(0.8)
                        }
                    }
                    .foregroundStyle(Color.backgroundPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isOverBudget ? Color.backgroundTertiary : Color.accentGold)
                    )
                }
                .disabled(isOverBudget)
                .buttonStyle(.plain)
            }

            if isHired || negotiationResult?.accepted == true {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.success)
                    Text("Hired!")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Color.success)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
        }
        .padding(16)
        .cardBackground()
    }

    // MARK: - Offer Logic

    private func makeOffer() {
        let roll = Double.random(in: 0...1)
        let accepted = roll >= rejectionChance

        if accepted {
            negotiationResult = NegotiationResult(
                accepted: true,
                message: proposedSalary < askingSalary
                    ? "\(candidate.firstName) accepted your below-market offer of \(salaryFormatted(Int(proposedSalary)))/yr for \(proposedYears) years."
                    : "\(candidate.firstName) is pleased with the offer of \(salaryFormatted(Int(proposedSalary)))/yr for \(proposedYears) years."
            )
            candidate.salary = Int(proposedSalary)
            onHire()
        } else {
            negotiationResult = NegotiationResult(
                accepted: false,
                message: "\(candidate.firstName) turned down your offer. They feel \(salaryFormatted(candidate.salary)) is fair compensation. You can adjust your offer and try again."
            )
        }
    }

    // MARK: - Helpers

    private func salaryFormatted(_ thousands: Int) -> String {
        let millions = Double(thousands) / 1_000.0
        return String(format: "$%.1fM", millions)
    }

    private func formatBudget(_ thousands: Int) -> String {
        let millions = Double(thousands) / 1_000.0
        return String(format: "%.1f", millions)
    }

    private func schemeTag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(color.opacity(0.3), lineWidth: 0.5)
            )
    }
}

// MARK: - Negotiation Result

private struct NegotiationResult {
    let accepted: Bool
    let message: String
}

// MARK: - Preview

#Preview {
    NavigationStack {
        HireCoachView(role: .offensiveCoordinator, teamID: UUID(), remainingBudget: 15_000)
    }
    .modelContainer(for: Coach.self, inMemory: true)
}
