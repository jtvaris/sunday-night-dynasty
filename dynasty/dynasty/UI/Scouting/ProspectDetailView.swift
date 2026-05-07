import SwiftUI
import SwiftData

struct ProspectDetailView: View {
    let career: Career
    let prospect: CollegeProspect

    @Environment(\.modelContext) private var modelContext
    @State private var scouts: [Scout] = []
    @State private var coaches: [Coach] = []
    @State private var showSendScout = false
    @State private var showInterviewResult = false
    @State private var interviewResult: (personality: PersonalityArchetype, footballIQ: Int, characterNotes: [String])?
    @State private var positionRank: Int?
    @State private var teamPlayers: [Player] = []

    // MARK: - Derived

    /// Always read the grade through the model's `effectiveOverallGrade` extension
    /// so the detail header, Big Board, prospect lists, and combine table all agree
    /// on a single value for the same prospect.
    private var effectiveOverallGrade: GradeRange? {
        prospect.effectiveOverallGrade
    }

    private var isScouted: Bool { prospect.scoutedOverall != nil }
    private var hasCombine: Bool {
        prospect.fortyTime != nil || prospect.benchPress != nil ||
        prospect.verticalJump != nil || prospect.broadJump != nil ||
        prospect.shuttleTime != nil || prospect.coneDrill != nil
    }
    private var isCombinePhase: Bool { career.currentPhase == .combine }
    private var isDraftPhase: Bool { career.currentPhase == .draft }
    private var canInterview: Bool { isCombinePhase && !prospect.interviewCompleted && career.interviewsUsed < 60 }
    private var canWorkout: Bool { (isCombinePhase || isDraftPhase) && !prospect.proDayCompleted && career.workoutsUsed < 30 }

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            List {
                headerSection
                quickAssessmentRow
                if isScouted { scoutingReportSection }
                starterComparisonSection
                combineSection
                collegeProductionSection
                draftSection
                riskFlagsSection
                if prospect.interviewCompleted { interviewResultsSection }
                teamInterestRow
                actionsSection
            }
            .scrollContentBackground(.hidden)
            .listStyle(.insetGrouped)
        }
        .safeAreaInset(edge: .bottom) {
            actionButtonBar
        }
        .navigationTitle(prospect.fullName)
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { loadScouts(); loadCoaches(); loadPositionRank(); loadTeamPlayers() }
        .sheet(isPresented: $showSendScout) {
            SendScoutSheet(prospect: prospect, scouts: scouts, scoutingPhase: currentScoutingPhase)
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        Section {
            HStack(alignment: .top, spacing: 16) {
                // Position badge
                VStack {
                    Text(prospect.position.rawValue)
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(Color.textPrimary)
                        .frame(width: 54, height: 54)
                        .background(positionColor, in: RoundedRectangle(cornerRadius: 10))
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(prospect.college)
                            .font(.headline)
                            .foregroundStyle(Color.textSecondary)

                        if let rank = positionRank {
                            Text("#\(rank) \(prospect.position.rawValue) in class")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(rank <= 3 ? Color.accentGold : Color.textSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill((rank <= 3 ? Color.accentGold : Color.textSecondary).opacity(0.15))
                                )
                        }
                    }

                    HStack(spacing: 16) {
                        ProspectInfoPill(label: "Age", value: "\(prospect.age)")
                        ProspectInfoPill(label: "Ht", value: heightLabel)
                        ProspectInfoPill(label: "Wt", value: "\(prospect.weight) lbs")
                    }
                }

                Spacer()

                if let gradeRange = effectiveOverallGrade {
                    VStack(spacing: 2) {
                        Text(gradeRange.displayText)
                            .font(.system(size: gradeRange.isSingleGrade ? 36 : 28, weight: .heavy))
                            .foregroundStyle(detailGradeColor(gradeRange.midGrade))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text("Overall")
                            .font(.caption2)
                            .foregroundStyle(Color.textTertiary)
                        scoutConfidenceBadge

                        // Draft projection
                        if let rd = prospect.draftProjection {
                            Text("Rd \(rd)")
                                .font(.caption.weight(.heavy))
                                .foregroundStyle(projectionColor(rd))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(projectionColor(rd).opacity(0.15), in: Capsule())
                        }

                        // Potential assessment
                        potentialBadge
                    }
                } else {
                    VStack(spacing: 2) {
                        Text("?")
                            .font(.system(size: 36, weight: .heavy))
                            .foregroundStyle(Color.textTertiary)
                        Text("Unscouted")
                            .font(.caption2)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    // MARK: - Scout Confidence Badge

    private var scoutConfidenceBadge: some View {
        let count = prospect.scoutReportCount
        let confidenceColor: Color
        let confidenceLabel: String
        switch count {
        case 0:  confidenceColor = .textTertiary; confidenceLabel = "Unscouted"
        case 1:  confidenceColor = .warning;      confidenceLabel = "Low"
        case 2:  confidenceColor = .accentBlue;   confidenceLabel = "Medium"
        default: confidenceColor = .success;      confidenceLabel = "High"
        }
        // The grade above is only as reliable as the number of scout visits behind
        // it — make that explicit so the user knows whether to trust it or send
        // more scouts.
        return HStack(spacing: 4) {
            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(i < count ? confidenceColor : confidenceColor.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }
            Text("\(confidenceLabel) confidence · \(count)/3 scouts")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(confidenceColor)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(confidenceColor.opacity(0.12), in: Capsule())
        .help("Grade reliability: \(confidenceLabel.lowercased()) — \(count) of 3 possible scout visits completed.")
    }

    // MARK: - Potential Badge

    private var potentialBadge: some View {
        let label = prospect.scoutedPotentialLabel ?? .unknown
        let color = potentialLabelColor(label)
        return Group {
            if label != .unknown {
                Text(label.rawValue)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.12), in: Capsule())
            }
        }
    }

    // MARK: - Quick Assessment Row

    @ViewBuilder
    private var quickAssessmentRow: some View {
        let risk = prospect.riskLevel
        let fit = evaluateSchemeFit()
        Section {
            HStack(spacing: 8) {
                // Risk badge
                if risk != .unknown {
                    assessmentBadge(icon: risk.icon, label: risk.rawValue, color: risk.color)
                }
                // Scheme fit badge
                if let fit {
                    assessmentBadge(icon: schemeFitIcon(fit), label: "Fit: \(fit)", color: schemeFitColor(fit))
                }
                // Athletic profile badge
                if hasCombine {
                    assessmentBadge(icon: "figure.run", label: athleticProfileLabel, color: athleticProfileColor)
                }
                // Stock trajectory
                let trajectory = prospect.stockTrajectory
                if trajectory != .newOnBoard {
                    assessmentBadge(icon: trajectory.icon, label: trajectory.rawValue, color: trajectory.color)
                }
                // Draft value mismatch warning
                if let proj = prospect.draftProjection, let ovr = prospect.scoutedOverall {
                    let projectedMinOvr = projectionMinOverall(proj)
                    if ovr < projectedMinOvr {
                        assessmentBadge(icon: "exclamationmark.triangle.fill", label: "Overdraft?", color: .danger)
                    }
                }
            }
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    private func assessmentBadge(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(color.opacity(0.12), in: Capsule())
    }

    /// Minimum expected OVR for a given draft round projection
    private func projectionMinOverall(_ round: Int) -> Int {
        switch round {
        case 1: return 70
        case 2...3: return 60
        case 4...5: return 50
        default: return 40
        }
    }

    // MARK: - Athletic Profile

    private var athleticProfileLabel: String {
        let percentiles = [
            prospect.fortyTime.map { CombineBenchmarks.percentile(value: $0, benchmark: CombineBenchmarks.benchmarks(for: prospect.position).fortyYard) },
            prospect.benchPress.map { CombineBenchmarks.percentile(value: Double($0), benchmark: CombineBenchmarks.benchmarks(for: prospect.position).benchPress) },
            prospect.verticalJump.map { CombineBenchmarks.percentile(value: $0, benchmark: CombineBenchmarks.benchmarks(for: prospect.position).verticalJump) },
            prospect.broadJump.map { CombineBenchmarks.percentile(value: Double($0), benchmark: CombineBenchmarks.benchmarks(for: prospect.position).broadJump) },
            prospect.shuttleTime.map { CombineBenchmarks.percentile(value: $0, benchmark: CombineBenchmarks.benchmarks(for: prospect.position).shuttle) },
            prospect.coneDrill.map { CombineBenchmarks.percentile(value: $0, benchmark: CombineBenchmarks.benchmarks(for: prospect.position).threeCone) }
        ].compactMap { $0 }

        guard !percentiles.isEmpty else { return "No Data" }
        let avg = percentiles.reduce(0, +) / percentiles.count

        switch avg {
        case 80...: return "Elite"
        case 65..<80: return "Above Average"
        case 45..<65: return "Average"
        case 25..<45: return "Below Average"
        default: return "Poor"
        }
    }

    private var athleticProfileColor: Color {
        switch athleticProfileLabel {
        case "Elite": return .accentGold
        case "Above Average": return .success
        case "Average": return .accentBlue
        case "Below Average": return .warning
        default: return .danger
        }
    }

    private func riskExplanation(_ risk: ProspectRiskLevel) -> String {
        switch risk {
        case .safePick:
            return "Consistent evaluations and stable personality. Lower variance in scout reports."
        case .highCeiling:
            return "High upside with some uncertainty. Could outperform projection significantly."
        case .boomOrBust:
            return "Extreme variance between evaluations. Could be a star or a bust."
        case .unknown:
            return "Not enough data to evaluate risk profile."
        }
    }

    // MARK: - Starter Comparison Section

    @ViewBuilder
    private var starterComparisonSection: some View {
        if isScouted {
            let starters = teamPlayers
                .filter { $0.position == prospect.position }
                .sorted { $0.overall > $1.overall }
            if let starter = starters.first {
                Section("vs Current Starter") {
                    HStack(spacing: 12) {
                        // Prospect side — show grade range
                        VStack(spacing: 2) {
                            Text(prospect.fullName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.textPrimary)
                            if let gr = effectiveOverallGrade {
                                Text(gr.displayText)
                                    .font(.title3.weight(.heavy))
                                    .foregroundStyle(detailGradeColor(gr.midGrade))
                            } else {
                                Text("?")
                                    .font(.title3.weight(.heavy))
                                    .foregroundStyle(Color.textTertiary)
                            }
                            Text("Prospect")
                                .font(.caption2)
                                .foregroundStyle(Color.textTertiary)
                        }
                        .frame(maxWidth: .infinity)

                        // Qualitative comparison
                        let diff = (prospect.scoutedOverall ?? 0) - starter.overall
                        let compLabel = starterComparisonLabel(diff)
                        let compColor = starterComparisonColor(diff)
                        VStack(spacing: 2) {
                            Text("vs")
                                .font(.caption2)
                                .foregroundStyle(Color.textTertiary)
                            Text(compLabel)
                                .font(.caption.weight(.heavy))
                                .foregroundStyle(compColor)
                                .multilineTextAlignment(.center)
                        }

                        // Starter side — letter grade to match prospect
                        VStack(spacing: 2) {
                            Text(starter.fullName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.textPrimary)
                            let starterGrade = LetterGrade.from(numericValue: starter.overall)
                            Text(starterGrade.rawValue)
                                .font(.title3.weight(.heavy))
                                .foregroundStyle(detailGradeColor(starterGrade))
                            Text("Starter")
                                .font(.caption2)
                                .foregroundStyle(Color.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.backgroundSecondary)
            } else {
                Section("vs Current Starter") {
                    HStack(spacing: 8) {
                        Image(systemName: "person.fill.badge.plus")
                            .font(.caption)
                            .foregroundStyle(Color.success)
                        Text("No \(prospect.position.rawValue) on roster -- immediate starter")
                            .font(.subheadline)
                            .foregroundStyle(Color.success)
                    }
                }
                .listRowBackground(Color.backgroundSecondary)
            }
        }
    }

    private func starterComparisonLabel(_ diff: Int) -> String {
        if diff >= 0 { return "Upgrade" }
        if diff > -5 { return "Close" }
        if diff > -12 { return "Development\nProject" }
        return "Long-term\nProject"
    }

    private func starterComparisonColor(_ diff: Int) -> Color {
        if diff > -3 { return .success }
        if diff > -8 { return .accentGold }
        if diff > -15 { return .warning }
        return .textSecondary
    }

    // MARK: - Team Interest Row

    @ViewBuilder
    private var teamInterestRow: some View {
        if !prospect.teamInterest.isEmpty {
            Section {
                HStack(spacing: 8) {
                    InterestBadge(level: prospect.interestLevel)
                    Text("\(prospect.teamInterest.count) team\(prospect.teamInterest.count == 1 ? "" : "s") interested")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                }
            }
            .listRowBackground(Color.backgroundSecondary)
        }
    }

    // MARK: - Combine Section

    private var combineSection: some View {
        Section("Physical Measurables") {
            // Athletic profile summary
            if hasCombine {
                HStack {
                    Text("Athletic Profile")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Text(athleticProfileLabel)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(athleticProfileColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(athleticProfileColor.opacity(0.15), in: Capsule())
                }
            }

            let bm = CombineBenchmarks.benchmarks(for: prospect.position)
            let pos = prospect.position.rawValue

            CombineMeasurableRow(label: "40-Yard Dash",
                                 value: prospect.fortyTime.map { String(format: "%.2f sec", $0) },
                                 percentile: prospect.fortyTime.map { CombineBenchmarks.percentile(value: $0, benchmark: bm.fortyYard) },
                                 posLabel: pos,
                                 recordNote: prospect.fortyTime.flatMap { nearRecordNote(value: $0, record: CombineBenchmarks.records.fortyYard.value, name: CombineBenchmarks.records.fortyYard.name, lowerIsBetter: true, format: "%.2f") })

            CombineMeasurableRow(label: "Bench Press",
                                 value: prospect.benchPress.map { "\($0) reps" },
                                 percentile: prospect.benchPress.map { CombineBenchmarks.percentile(value: Double($0), benchmark: bm.benchPress) },
                                 posLabel: pos,
                                 recordNote: prospect.benchPress.flatMap { nearRecordNote(value: Double($0), record: Double(CombineBenchmarks.records.benchPress.value), name: CombineBenchmarks.records.benchPress.name, lowerIsBetter: false, format: "%.0f") })

            CombineMeasurableRow(label: "Vertical Jump",
                                 value: prospect.verticalJump.map { String(format: "%.1f in", $0) },
                                 percentile: prospect.verticalJump.map { CombineBenchmarks.percentile(value: $0, benchmark: bm.verticalJump) },
                                 posLabel: pos,
                                 recordNote: prospect.verticalJump.flatMap { nearRecordNote(value: $0, record: CombineBenchmarks.records.verticalJump.value, name: CombineBenchmarks.records.verticalJump.name, lowerIsBetter: false, format: "%.1f") })

            CombineMeasurableRow(label: "Broad Jump",
                                 value: prospect.broadJump.map { "\($0) in" },
                                 percentile: prospect.broadJump.map { CombineBenchmarks.percentile(value: Double($0), benchmark: bm.broadJump) },
                                 posLabel: pos,
                                 recordNote: prospect.broadJump.flatMap { nearRecordNote(value: Double($0), record: Double(CombineBenchmarks.records.broadJump.value), name: CombineBenchmarks.records.broadJump.name, lowerIsBetter: false, format: "%.0f") })

            CombineMeasurableRow(label: "Shuttle",
                                 value: prospect.shuttleTime.map { String(format: "%.2f sec", $0) },
                                 percentile: prospect.shuttleTime.map { CombineBenchmarks.percentile(value: $0, benchmark: bm.shuttle) },
                                 posLabel: pos,
                                 recordNote: prospect.shuttleTime.flatMap { nearRecordNote(value: $0, record: CombineBenchmarks.records.shuttle.value, name: CombineBenchmarks.records.shuttle.name, lowerIsBetter: true, format: "%.2f") })

            CombineMeasurableRow(label: "3-Cone Drill",
                                 value: prospect.coneDrill.map { String(format: "%.2f sec", $0) },
                                 percentile: prospect.coneDrill.map { CombineBenchmarks.percentile(value: $0, benchmark: bm.threeCone) },
                                 posLabel: pos,
                                 recordNote: prospect.coneDrill.flatMap { nearRecordNote(value: $0, record: CombineBenchmarks.records.threeCone.value, name: CombineBenchmarks.records.threeCone.name, lowerIsBetter: true, format: "%.2f") })

            // Position drill grade
            if let drillGrade = prospect.positionDrillGrade {
                HStack(spacing: 8) {
                    Image(systemName: "figure.run.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Position Drills")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                        Text("Estimated from \(prospect.position.rawValue)-specific combine drills")
                            .font(.caption2)
                            .foregroundStyle(Color.textTertiary)
                    }
                    Spacer()
                    Text(drillGrade)
                        .font(.title3.weight(.black))
                        .foregroundStyle(PositionGradeCalculator.gradeColorForLetter(drillGrade))
                    Image(systemName: "questionmark.circle")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }
            }

            if !hasCombine {
                HStack {
                    Image(systemName: "clock")
                        .foregroundStyle(Color.textTertiary)
                    Text("Combine results pending")
                        .font(.subheadline)
                        .foregroundStyle(Color.textTertiary)
                }
            }
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    /// Returns a "Near record!" note if the value is within 5% of the all-time record.
    private func nearRecordNote(value: Double, record: Double, name: String, lowerIsBetter: Bool, format: String) -> String? {
        let threshold = record * 0.05
        let isNear: Bool
        if lowerIsBetter {
            isNear = value <= record + threshold
        } else {
            isNear = value >= record - threshold
        }
        guard isNear else { return nil }
        return "Near record! (\(String(format: format, record)) by \(name))"
    }

    // MARK: - Scouting Report Section

    @ViewBuilder
    private var scoutingReportSection: some View {
        Section("Scouting Report") {
            // Overall grade
            if let gradeRange = effectiveOverallGrade {
                LabeledContent("Overall Grade") {
                    Text(gradeRange.displayText)
                        .font(.body.weight(.bold))
                        .foregroundStyle(detailGradeColor(gradeRange.midGrade))
                }
            }

            // Potential
            if let potentialLabel = prospect.scoutedPotentialLabel {
                LabeledContent("Potential") {
                    Text(potentialLabel.rawValue)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(potentialLabelColor(potentialLabel))
                }
            } else if let potential = prospect.scoutedPotential {
                let potentialGrade = LetterGrade.from(numericValue: potential)
                LabeledContent("Potential") {
                    Text(potentialGrade.rawValue)
                        .font(.body.weight(.bold))
                        .foregroundStyle(detailGradeColor(potentialGrade))
                }
            }

            if let grade = prospect.scoutGrade {
                LabeledContent("Scout Grade") {
                    Text(grade)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                }
            }

            if let personality = prospect.scoutedPersonality {
                LabeledContent("Personality") {
                    Text(personality.displayName)
                        .foregroundStyle(Color.textPrimary)
                }
            }

            // Mental grades — with fallback from trueMental
            mentalGradesGrid

            // Position grades — with fallback from truePositionAttributes
            positionGradesGrid

            // Status indicators
            HStack(spacing: 16) {
                StatusPill(label: "Interview", completed: prospect.interviewCompleted)
                StatusPill(label: "Pro Day",   completed: prospect.proDayCompleted)
            }
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    /// Mental grades grid with fallback from legacy numeric values.
    private var mentalGradesGrid: some View {
        let mentalKeys = ["AWR", "DEC", "WRK", "CLT", "COA", "LDR"]
        let scoutedGrades = prospect.scoutedMentalGrades
        let hasAny = scoutedGrades != nil && !(scoutedGrades?.isEmpty ?? true)

        return Group {
            if hasAny {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Mental Attributes")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                        ForEach(mentalKeys, id: \.self) { key in
                            if let gr = scoutedGrades?[key] {
                                gradeCell(key: key, grade: gr)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Position grades grid with fallback from legacy numeric values.
    private var positionGradesGrid: some View {
        let scoutedGrades = prospect.scoutedPositionGrades
        let hasAny = scoutedGrades != nil && !(scoutedGrades?.isEmpty ?? true)

        return Group {
            if hasAny {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Position Skills")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: min(scoutedGrades?.count ?? 4, 6)), spacing: 8) {
                        ForEach(Array((scoutedGrades ?? [:]).keys.sorted()), id: \.self) { key in
                            if let gr = scoutedGrades?[key] {
                                gradeCell(key: key, grade: gr)
                            }
                        }
                    }
                }
            }
        }
    }

    private func gradeCell(key: String, grade: GradeRange) -> some View {
        VStack(spacing: 2) {
            Text(grade.displayText)
                .font(.caption.weight(.bold))
                .foregroundStyle(detailGradeColor(grade.midGrade))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(detailGradeColor(grade.midGrade).opacity(0.12))
                )
            Text(key)
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
        }
    }

    // MARK: - Interview Results Section (Task 16: Full interview results in prospect detail)

    @ViewBuilder
    private var interviewResultsSection: some View {
        Section {
            // Header with interview grade
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.subheadline)
                        .foregroundStyle(Color.accentBlue)
                    Text("Interview Results")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Color.textPrimary)
                }
                Spacer()
                if let iq = prospect.interviewFootballIQ {
                    // Overall interview grade
                    let grade = interviewGradeLetter(iq: iq, personality: prospect.scoutedPersonality)
                    Text(grade)
                        .font(.title2.weight(.heavy))
                        .foregroundStyle(interviewDetailGradeColor(grade))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(interviewDetailGradeColor(grade).opacity(0.15))
                        )
                }
            }

            // Bust-risk delta card (replicated from InterviewSelectionView).
            // Shows pre- vs post-interview bust risk to give the user a single
            // glanceable decision-support number alongside the interview grade.
            if let iq = prospect.interviewFootballIQ {
                let baseRisk = estimateBustRiskPct(hasInterview: false)
                let postRisk = estimateBustRiskPct(
                    hasInterview: true,
                    iq: iq,
                    personality: prospect.scoutedPersonality,
                    hasOffField: prospect.interviewCharacterNotes?
                        .contains(where: { $0.contains("\u{1F6A9}") }) ?? false
                )
                if baseRisk != postRisk {
                    BustRiskDeltaCard(
                        label: "Bust risk",
                        before: baseRisk,
                        after: postRisk,
                        unit: "%",
                        direction: .lowerIsBetter,
                        trailingContext: "after interview",
                        prominent: true
                    )
                }
            }

            // Personality badge with colored background (Task 1)
            if let personality = prospect.scoutedPersonality {
                HStack {
                    Text("Personality")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill")
                            .font(.caption2)
                        Text(personality.displayName)
                            .font(.subheadline.weight(.bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(personalityDetailBadgeColor(personality))
                    )
                }
            }

            // Football IQ with letter grade (Task 2)
            if let iq = prospect.interviewFootballIQ {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Football IQ")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        HStack(spacing: 6) {
                            Text(footballIQGradeLetter(iq))
                                .font(.body.weight(.heavy))
                                .foregroundStyle(footballIQDetailColor(iq))
                            Text("(\(iq))")
                                .font(.caption.weight(.medium).monospacedDigit())
                                .foregroundStyle(Color.textTertiary)
                        }
                    }
                    Text("Affects scheme learning speed")
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)

                    // Football IQ impact (Task 11)
                    if iq >= 85 {
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.fill")
                                .font(.caption2)
                                .foregroundStyle(Color.success)
                            Text("High IQ = faster scheme learning, better decisions, fewer penalties")
                                .font(.caption2)
                                .foregroundStyle(Color.success)
                        }
                    } else if iq < 55 {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(Color.danger)
                            Text("Low IQ = slower scheme learning, more mental errors")
                                .font(.caption2)
                                .foregroundStyle(Color.danger)
                        }
                    }
                }
            }

            // Off-field / exemplary character indicators (Task 3: larger, more visible)
            if let notes = prospect.interviewCharacterNotes {
                let hasOffField = notes.contains(where: { $0.contains("\u{1F6A9}") })
                let hasExemplary = notes.contains(where: { $0.contains("\u{2705}") })

                if hasOffField {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.body)
                            .foregroundStyle(Color.danger)
                        Text("OFF-FIELD CONCERNS REPORTED")
                            .font(.subheadline.weight(.heavy))
                            .foregroundStyle(Color.danger)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.danger.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.danger.opacity(0.3))
                            )
                    )
                }

                if hasExemplary {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.body)
                            .foregroundStyle(Color.success)
                        Text("EXEMPLARY CHARACTER")
                            .font(.subheadline.weight(.heavy))
                            .foregroundStyle(Color.success)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.success.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.success.opacity(0.3))
                            )
                    )
                }
            }

            // Red/green flags summary (Task 12)
            if let iq = prospect.interviewFootballIQ {
                let personality = prospect.scoutedPersonality
                let hasOffField = prospect.interviewCharacterNotes?.contains(where: { $0.contains("\u{1F6A9}") }) ?? false

                VStack(alignment: .leading, spacing: 4) {
                    // Green flags
                    if iq >= 75 {
                        interviewFlagRow(color: .success, text: "High Football IQ")
                    }
                    if let p = personality, p.tier == .positive {
                        interviewFlagRow(color: .success, text: p.displayName)
                    }
                    if !hasOffField {
                        interviewFlagRow(color: .success, text: "Clean record")
                    }

                    // Red flags
                    if hasOffField {
                        interviewFlagRow(color: .danger, text: "Off-field concerns")
                    }
                    if iq < 55 {
                        interviewFlagRow(color: .danger, text: "Low Football IQ")
                    }
                    if let p = personality, p.tier == .risky {
                        interviewFlagRow(color: .danger, text: p.displayName)
                    }
                }
            }

            // Character notes (excluding off-field/exemplary which are shown above)
            if let notes = prospect.interviewCharacterNotes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Character Notes")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                    ForEach(notes.filter({ !$0.contains("\u{1F6A9}") && !$0.contains("\u{2705}") }), id: \.self) { note in
                        HStack(spacing: 6) {
                            Image(systemName: "quote.bubble.fill")
                                .font(.caption)
                                .foregroundStyle(Color.textTertiary)
                            Text(note)
                                .font(.subheadline)
                                .foregroundStyle(Color.textPrimary)
                        }
                    }
                }
            }
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    private func interviewFlagRow(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
        }
    }

    private func interviewGradeLetter(iq: Int, personality: PersonalityArchetype?) -> String {
        var score = iq
        if let p = personality {
            score += p.interviewScoreContribution
        }
        if let notes = prospect.interviewCharacterNotes {
            if notes.contains(where: { $0.contains("\u{1F6A9}") }) { score -= 15 }
            if notes.contains(where: { $0.contains("\u{2705}") }) { score += 10 }
        }
        score = max(0, min(99, score))
        if score >= 85 { return "A" }
        if score >= 75 { return "B" }
        if score >= 65 { return "C" }
        if score >= 55 { return "D" }
        return "F"
    }

    private func interviewDetailGradeColor(_ grade: String) -> Color {
        switch grade {
        case "A": return .accentGold
        case "B": return .success
        case "C": return .warning
        case "D": return .danger
        default:  return .danger
        }
    }

    private func personalityDetailBadgeColor(_ p: PersonalityArchetype) -> Color {
        switch p.tier {
        case .positive: return .success
        case .risky:    return .danger
        case .neutral:  return .warning.opacity(0.8)
        }
    }

    private func footballIQGradeLetter(_ iq: Int) -> String {
        if iq >= 85 { return "A" }
        if iq >= 75 { return "B" }
        if iq >= 65 { return "C" }
        if iq >= 55 { return "D" }
        return "F"
    }

    private func footballIQDetailColor(_ iq: Int) -> Color {
        if iq >= 85 { return .accentGold }
        if iq >= 75 { return .success }
        if iq >= 65 { return .warning }
        if iq >= 55 { return .danger }
        return .danger
    }

    /// Estimate bust risk percentage. Mirrors the formula in
    /// `InterviewSelectionView.estimateBustRisk` so both views display
    /// consistent numbers for the same prospect.
    private func estimateBustRiskPct(
        hasInterview: Bool,
        iq: Int = 65,
        personality: PersonalityArchetype? = nil,
        hasOffField: Bool = false
    ) -> Int {
        var risk = 35

        if prospect.position == .QB { risk += 10 }
        else if prospect.position == .WR || prospect.position == .CB { risk += 5 }

        if prospect.age <= 20 { risk += 5 }

        if hasInterview {
            if iq >= 85 { risk -= 15 }
            else if iq >= 75 { risk -= 10 }
            else if iq >= 65 { risk -= 5 }
            else if iq < 50 { risk += 10 }

            if let p = personality {
                if p.tier == .positive { risk -= 5 }
                else if p.tier == .risky { risk += 5 }
            }

            if hasOffField { risk += 10 }
        }

        return max(5, min(80, risk))
    }

    // MARK: - College Production Section (Position Skills)

    @ViewBuilder
    private var collegeProductionSection: some View {
        if isScouted {
            Section("Position Skills") {
                collegeFlavorStats
            }
            .listRowBackground(Color.backgroundSecondary)
        }
    }

    @ViewBuilder
    private var collegeFlavorStats: some View {
        let posGrades = prospect.scoutedPositionGrades
        let fb = positionFallbackValues
        switch prospect.truePositionAttributes {
        case .quarterback:
            HStack(spacing: 14) {
                flavorGradeStat(label: "Arm", key: "ARM", grades: posGrades, fallback: fb)
                flavorGradeStat(label: "Acc (S)", key: "SAc", grades: posGrades, fallback: fb)
                flavorGradeStat(label: "Acc (D)", key: "DAc", grades: posGrades, fallback: fb)
                flavorGradeStat(label: "Pocket", key: "PKT", grades: posGrades, fallback: fb)
            }
        case .wideReceiver:
            HStack(spacing: 14) {
                flavorGradeStat(label: "Route", key: "RTE", grades: posGrades, fallback: fb)
                flavorGradeStat(label: "Catch", key: "CTH", grades: posGrades, fallback: fb)
                flavorGradeStat(label: "Release", key: "RLS", grades: posGrades, fallback: fb)
            }
        case .runningBack:
            HStack(spacing: 14) {
                flavorGradeStat(label: "Vision", key: "VIS", grades: posGrades, fallback: fb)
                flavorGradeStat(label: "Elusiv", key: "ELU", grades: posGrades, fallback: fb)
                flavorGradeStat(label: "Recv", key: "RCV", grades: posGrades, fallback: fb)
            }
        case .defensiveBack:
            HStack(spacing: 14) {
                flavorGradeStat(label: "Man", key: "MCV", grades: posGrades, fallback: fb)
                flavorGradeStat(label: "Zone", key: "ZCV", grades: posGrades, fallback: fb)
                flavorGradeStat(label: "Press", key: "PRS", grades: posGrades, fallback: fb)
            }
        case .linebacker:
            HStack(spacing: 14) {
                flavorGradeStat(label: "Tackle", key: "TAK", grades: posGrades, fallback: fb)
                flavorGradeStat(label: "Zone", key: "ZCV", grades: posGrades, fallback: fb)
                flavorGradeStat(label: "Blitz", key: "BLZ", grades: posGrades, fallback: fb)
            }
        case .defensiveLine:
            HStack(spacing: 14) {
                flavorGradeStat(label: "Pass Rush", key: "PRU", grades: posGrades, fallback: fb)
                flavorGradeStat(label: "Shed", key: "BSH", grades: posGrades, fallback: fb)
                flavorGradeStat(label: "Power", key: "PWR", grades: posGrades, fallback: fb)
            }
        case .offensiveLine:
            HStack(spacing: 14) {
                flavorGradeStat(label: "Run Blk", key: "RBK", grades: posGrades, fallback: fb)
                flavorGradeStat(label: "Pass Blk", key: "PBK", grades: posGrades, fallback: fb)
                flavorGradeStat(label: "Anchor", key: "ANC", grades: posGrades, fallback: fb)
            }
        case .tightEnd:
            HStack(spacing: 14) {
                flavorGradeStat(label: "Block", key: "BLK", grades: posGrades, fallback: fb)
                flavorGradeStat(label: "Catch", key: "CTH", grades: posGrades, fallback: fb)
                flavorGradeStat(label: "Route", key: "RTE", grades: posGrades, fallback: fb)
            }
        case .kicking:
            HStack(spacing: 14) {
                flavorGradeStat(label: "Power", key: "PWR", grades: posGrades, fallback: fb)
                flavorGradeStat(label: "Accuracy", key: "ACC", grades: posGrades, fallback: fb)
            }
        }
    }

    /// Builds a fallback dictionary mapping position skill keys to numeric values from truePositionAttributes.
    private var positionFallbackValues: [String: Int] {
        switch prospect.truePositionAttributes {
        case .quarterback(let qb):
            return ["ARM": qb.armStrength, "SAc": qb.accuracyShort, "DAc": qb.accuracyDeep,
                    "PKT": qb.pocketPresence, "MAc": qb.accuracyMid, "SCR": qb.scrambling]
        case .wideReceiver(let wr):
            return ["RTE": wr.routeRunning, "CTH": wr.catching, "RLS": wr.release]
        case .runningBack(let rb):
            return ["VIS": rb.vision, "ELU": rb.elusiveness, "RCV": rb.receiving, "BTK": rb.breakTackle]
        case .defensiveBack(let db):
            return ["MCV": db.manCoverage, "ZCV": db.zoneCoverage, "PRS": db.press, "BLS": db.ballSkills]
        case .linebacker(let lb):
            return ["TAK": lb.tackling, "ZCV": lb.zoneCoverage, "BLZ": lb.blitzing]
        case .defensiveLine(let dl):
            return ["PRU": dl.passRush, "BSH": dl.blockShedding, "PWR": dl.powerMoves, "FIN": dl.finesseMoves]
        case .offensiveLine(let ol):
            return ["RBK": ol.runBlock, "PBK": ol.passBlock, "ANC": ol.anchor, "PUL": ol.pull]
        case .tightEnd(let te):
            return ["BLK": te.blocking, "CTH": te.catching, "RTE": te.routeRunning, "SPD": te.speed]
        case .kicking(let k):
            return ["PWR": k.kickPower, "ACC": k.kickAccuracy]
        }
    }

    private func flavorGradeStat(label: String, key: String, grades: [String: GradeRange]?, fallback: [String: Int]) -> some View {
        VStack(spacing: 2) {
            if let gr = grades?[key] {
                Text(gr.displayText)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(detailGradeColor(gr.midGrade))
            } else if let numVal = fallback[key] {
                let lg = LetterGrade.from(numericValue: numVal)
                Text(lg.rawValue)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(detailGradeColor(lg))
            } else {
                Text("?")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.textTertiary)
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
        }
    }

    // MARK: - Scheme Fit

    private func evaluateSchemeFit() -> String? {
        let oc = coaches.first(where: { $0.role == .offensiveCoordinator })
        let dc = coaches.first(where: { $0.role == .defensiveCoordinator })

        if prospect.position.side == .offense, let scheme = oc?.offensiveScheme {
            return offensiveSchemeFit(scheme: scheme)
        } else if prospect.position.side == .defense, let scheme = dc?.defensiveScheme {
            return defensiveSchemeFit(scheme: scheme)
        }
        return nil
    }

    private func offensiveSchemeFit(scheme: OffensiveScheme) -> String {
        var score = 0
        let physical = prospect.truePhysical

        switch prospect.truePositionAttributes {
        case .quarterback(let qb):
            switch scheme {
            case .airRaid, .spread:
                score = (qb.accuracyShort + qb.accuracyDeep + qb.armStrength) / 3
            case .westCoast, .proPassing:
                score = (qb.accuracyShort + qb.accuracyMid + qb.pocketPresence) / 3
            case .powerRun, .shanahan:
                score = (qb.pocketPresence + qb.scrambling + physical.strength) / 3
            case .rpo, .option:
                score = (qb.scrambling + physical.speed + qb.accuracyShort) / 3
            }
        case .wideReceiver(let wr):
            switch scheme {
            case .airRaid, .spread:
                score = (wr.routeRunning + wr.catching + physical.speed) / 3
            case .westCoast, .proPassing:
                score = (wr.routeRunning + wr.catching + wr.release) / 3
            case .powerRun, .shanahan:
                score = (physical.strength + wr.release + physical.speed) / 3
            default:
                score = (wr.routeRunning + wr.catching) / 2
            }
        case .runningBack(let rb):
            switch scheme {
            case .powerRun:
                score = (rb.breakTackle + rb.vision + physical.strength) / 3
            case .shanahan:
                score = (rb.vision + rb.elusiveness + physical.speed) / 3
            case .westCoast, .spread:
                score = (rb.receiving + rb.elusiveness + rb.vision) / 3
            default:
                score = (rb.vision + rb.elusiveness) / 2
            }
        case .offensiveLine(let ol):
            switch scheme {
            case .powerRun:
                score = (ol.runBlock + ol.anchor + physical.strength) / 3
            case .airRaid, .proPassing, .westCoast:
                score = (ol.passBlock + ol.anchor + physical.strength) / 3
            case .shanahan:
                score = (ol.pull + ol.runBlock + physical.agility) / 3
            default:
                score = (ol.runBlock + ol.passBlock) / 2
            }
        case .tightEnd(let te):
            switch scheme {
            case .airRaid, .spread, .westCoast:
                score = (te.catching + te.routeRunning + te.speed) / 3
            case .powerRun, .shanahan:
                score = (te.blocking + te.speed + physical.strength) / 3
            default:
                score = (te.catching + te.blocking) / 2
            }
        default:
            score = 65
        }
        return schemeFitLabel(score)
    }

    private func defensiveSchemeFit(scheme: DefensiveScheme) -> String {
        var score = 0
        let physical = prospect.truePhysical

        switch prospect.truePositionAttributes {
        case .defensiveBack(let db):
            switch scheme {
            case .pressMan:
                score = (db.manCoverage + db.press + physical.speed) / 3
            case .cover3, .tampa2:
                score = (db.zoneCoverage + db.ballSkills + physical.speed) / 3
            case .multiple, .hybrid:
                score = (db.manCoverage + db.zoneCoverage + db.press) / 3
            default:
                score = (db.manCoverage + db.zoneCoverage) / 2
            }
        case .linebacker(let lb):
            switch scheme {
            case .base34:
                score = (lb.tackling + lb.blitzing + physical.strength) / 3
            case .base43:
                score = (lb.tackling + lb.zoneCoverage + physical.speed) / 3
            case .tampa2:
                score = (lb.zoneCoverage + physical.speed + lb.tackling) / 3
            case .cover3:
                score = (lb.zoneCoverage + lb.tackling + physical.speed) / 3
            default:
                score = (lb.tackling + lb.zoneCoverage) / 2
            }
        case .defensiveLine(let dl):
            switch scheme {
            case .base43:
                score = (dl.passRush + dl.powerMoves + physical.strength) / 3
            case .base34:
                score = (dl.blockShedding + dl.powerMoves + physical.strength) / 3
            case .multiple, .hybrid:
                score = (dl.passRush + dl.finesseMoves + physical.agility) / 3
            default:
                score = (dl.passRush + dl.blockShedding) / 2
            }
        default:
            score = 65
        }
        return schemeFitLabel(score)
    }

    private func schemeFitLabel(_ score: Int) -> String {
        switch score {
        case 75...:  return "Good"
        case 55..<75: return "Fair"
        default:      return "Poor"
        }
    }

    private func schemeFitColor(_ fit: String) -> Color {
        switch fit {
        case "Good": return .success
        case "Fair": return .warning
        default:     return .danger
        }
    }

    private func schemeFitIcon(_ fit: String) -> String {
        switch fit {
        case "Good": return "checkmark.circle.fill"
        case "Fair": return "minus.circle.fill"
        default:     return "xmark.circle.fill"
        }
    }

    private func schemeFitExplanation(_ fit: String) -> String {
        switch fit {
        case "Good": return "Attributes align well with your coordinator's scheme."
        case "Fair": return "Decent fit but may need development in the scheme."
        default:     return "Skill set doesn't match scheme requirements well."
        }
    }

    // MARK: - Risk Flags Section

    @ViewBuilder
    private var riskFlagsSection: some View {
        let flags = collectRiskFlags()
        if !flags.isEmpty {
            Section("Risk Flags") {
                ForEach(flags, id: \.self) { flag in
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.danger)
                        Text(flag)
                            .font(.subheadline)
                            .foregroundStyle(Color.textPrimary)
                    }
                }
            }
            .listRowBackground(Color.backgroundSecondary)
        }
    }

    private func collectRiskFlags() -> [String] {
        var flags: [String] = []

        if let iq = prospect.interviewFootballIQ, iq < 50 {
            flags.append("Low Football IQ (\(iq)) -- may struggle with complex playbook")
        }

        let concernWords = ["concern", "issue", "trouble", "red flag", "questionable",
                           "immature", "selfish", "lazy", "undisciplined", "attitude"]
        if let notes = prospect.interviewCharacterNotes {
            for note in notes {
                let lower = note.lowercased()
                if concernWords.contains(where: { lower.contains($0) }) {
                    flags.append("Character concern: \(note)")
                }
            }
        }

        if isScouted && prospect.truePhysical.durability < 50 {
            flags.append("Durability concern -- injury-prone profile")
        }

        if isScouted && prospect.trueMental.workEthic < 45 {
            flags.append("Poor work ethic -- development may stall")
        }

        return flags
    }

    // MARK: - Draft Section

    private var draftSection: some View {
        Section("Draft Information") {
            LabeledContent("Declaring for Draft") {
                Text(prospect.isDeclaringForDraft ? "Yes" : "No")
                    .foregroundStyle(prospect.isDeclaringForDraft ? Color.success : Color.textSecondary)
            }

            if let proj = prospect.draftProjection {
                LabeledContent("Draft Projection") {
                    Text("Round \(proj)")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(projectionColor(proj))
                        .monospacedDigit()
                }
            } else {
                LabeledContent("Draft Projection") {
                    Text("Unknown")
                        .foregroundStyle(Color.textTertiary)
                }
            }

            // Rookie contract estimate
            if let proj = prospect.draftProjection {
                LabeledContent("Est. Rookie Deal") {
                    Text(rookieContractEstimate(round: proj))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                        .monospacedDigit()
                }
            }

            // Mock draft projection
            if let mockPick = prospect.mockDraftPickNumber,
               let mockTeam = prospect.mockDraftTeam {
                LabeledContent("Mock Draft") {
                    Text("Rd1 Pick #\(mockPick) — \(mockTeam)")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentGold)
                        .monospacedDigit()
                }
            }

            // Team interest indicator
            LabeledContent("Team Interest") {
                InterestBadge(level: prospect.interestLevel)
            }
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        Section {
            Button {
                showSendScout = true
            } label: {
                Label(
                    isScouted ? "Send Another Scout (\(currentScoutingPhase.displayName))" : "Send Scout to Evaluate",
                    systemImage: "magnifyingglass"
                )
                .foregroundStyle(Color.accentGold)
            }

            // Interview button (combine phase, max 60)
            if canInterview {
                Button {
                    performInterview()
                } label: {
                    HStack {
                        Label("Conduct Interview", systemImage: "person.crop.circle.badge.questionmark")
                            .foregroundStyle(Color.accentBlue)
                        Spacer()
                        Text("Interviews: \(career.interviewsUsed)/60 used")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            } else if prospect.interviewCompleted {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.success)
                        .font(.caption)
                    Text("Interview completed")
                        .font(.subheadline)
                        .foregroundStyle(Color.success)
                }
            }

            // Personal workout button (combine/draft phase, max 30)
            if canWorkout {
                Button {
                    performWorkout()
                } label: {
                    HStack {
                        Label("Invite for Workout", systemImage: "figure.run")
                            .foregroundStyle(Color.accentBlue)
                        Spacer()
                        Text("Workouts: \(career.workoutsUsed)/30 used")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            } else if prospect.proDayCompleted {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.success)
                        .font(.caption)
                    Text("Workout/Pro Day completed")
                        .font(.subheadline)
                        .foregroundStyle(Color.success)
                }
            }

            if isScouted {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Color.success)
                    Text("Scouted (\(prospect.scoutingReports.count) report\(prospect.scoutingReports.count == 1 ? "" : "s"))")
                        .foregroundStyle(Color.success)
                }
            }
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    // MARK: - Action Button Bar (#48)

    private var actionButtonBar: some View {
        HStack(spacing: 12) {
            // Add to Board / toggle flag — primary CTA, full-width emphasized.
            Button {
                withAnimation {
                    prospect.prospectFlag = prospect.prospectFlag == .mustHave ? .none : .mustHave
                    try? modelContext.save()
                }
            } label: {
                Label(
                    prospect.prospectFlag == .mustHave ? "On Board" : "Add to Board",
                    systemImage: prospect.prospectFlag == .mustHave ? "star.fill" : "star"
                )
                .font(.body.weight(.bold))
                .foregroundStyle(prospect.prospectFlag == .mustHave ? Color.accentGold : Color.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(prospect.prospectFlag == .mustHave ? Color.accentGold.opacity(0.22) : Color.backgroundSecondary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            prospect.prospectFlag == .mustHave ? Color.accentGold : Color.surfaceBorder,
                            lineWidth: prospect.prospectFlag == .mustHave ? 1.5 : 1
                        )
                )
            }

            // Interview button — only during combine phase.
            if canInterview {
                Button {
                    performInterview()
                } label: {
                    Label("Interview", systemImage: "bubble.left.fill")
                        .font(.body.weight(.bold))
                        .foregroundStyle(Color.accentBlue)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.accentBlue.opacity(0.18))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(Color.accentBlue.opacity(0.5), lineWidth: 1)
                        )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    // MARK: - Helpers

    private var positionColor: Color {
        switch prospect.position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }

    private var heightLabel: String {
        let feet = prospect.height / 12
        let inches = prospect.height % 12
        return "\(feet)'\(inches)\""
    }

    private func projectionColor(_ round: Int) -> Color {
        switch round {
        case 1:    return .accentGold
        case 2...3: return .success
        case 4...5: return .warning
        default:   return .textSecondary
        }
    }

    private func detailGradeColor(_ grade: LetterGrade) -> Color {
        // Aligned with the unified 5-tier palette so colors match across the app:
        // A+ → bright green, A/A- → green, B → blue, C → yellow, D/F → red.
        PositionGradeCalculator.gradeColorForLetter(grade.rawValue)
    }

    private func potentialLabelColor(_ label: PotentialLabel) -> Color {
        switch label {
        case .eliteCeiling:  return .accentGold
        case .highUpside:    return .success
        case .solidStarter:  return .accentBlue
        case .average:       return .warning
        case .limitedUpside: return .danger
        case .unknown:       return .textTertiary
        }
    }

    private func rookieContractEstimate(round: Int) -> String {
        switch round {
        case 1: return "~$12-40M / 4yr"
        case 2: return "~$6-10M / 4yr"
        case 3: return "~$4-6M / 4yr"
        case 4: return "~$3-4M / 4yr"
        case 5: return "~$2-3M / 4yr"
        case 6: return "~$1-2M / 4yr"
        default: return "~$900K / 4yr"
        }
    }

    /// Maps the career's current season phase to a scouting phase for report generation.
    private var currentScoutingPhase: ScoutingPhase {
        switch career.currentPhase {
        case .combine:
            return .combine
        case .freeAgency, .proDays, .draft:
            return .proDay
        case .otas, .trainingCamp, .preseason, .rosterCuts:
            return .personalWorkout
        default:
            // Pre-combine phases: college season or senior bowl
            return .collegeSeason
        }
    }

    private func loadScouts() {
        guard let teamID = career.teamID else { return }
        let desc = FetchDescriptor<Scout>(predicate: #Predicate { $0.teamID == teamID })
        scouts = (try? modelContext.fetch(desc)) ?? []
    }

    private func loadCoaches() {
        guard let teamID = career.teamID else { return }
        let desc = FetchDescriptor<Coach>(predicate: #Predicate { $0.teamID == teamID })
        coaches = (try? modelContext.fetch(desc)) ?? []
    }

    private func loadTeamPlayers() {
        guard let teamID = career.teamID else { return }
        let desc = FetchDescriptor<Player>(predicate: #Predicate { $0.teamID == teamID })
        teamPlayers = (try? modelContext.fetch(desc)) ?? []
    }

    private func loadPositionRank() {
        let desc = FetchDescriptor<CollegeProspect>()
        guard let all = try? modelContext.fetch(desc) else { return }
        let ranked = all
            .filter { $0.position == prospect.position && $0.scoutedOverall != nil }
            .sorted { ($0.scoutedOverall ?? 0) > ($1.scoutedOverall ?? 0) }
        if let idx = ranked.firstIndex(where: { $0.id == prospect.id }) {
            positionRank = idx + 1
        }
    }

    private func performInterview() {
        // Use best scout's personalityRead or HC's motivation as interviewer quality
        let interviewerQuality: Int
        if let bestScout = scouts.max(by: { $0.personalityRead < $1.personalityRead }) {
            interviewerQuality = bestScout.personalityRead
        } else if let hc = coaches.first(where: { $0.role == .headCoach }) {
            interviewerQuality = hc.motivation
        } else {
            interviewerQuality = 50
        }

        let result = ScoutingEngine.conductInterview(
            prospect: prospect,
            interviewerQuality: interviewerQuality
        )
        interviewResult = result
        career.interviewsUsed += 1
        try? modelContext.save()
    }

    private func performWorkout() {
        ScoutingEngine.conductPersonalWorkout(
            prospect: prospect,
            coaches: coaches
        )
        career.workoutsUsed += 1
        try? modelContext.save()
    }
}

// MARK: - Supporting Views

private struct ProspectInfoPill: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.textPrimary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
        }
    }
}

private struct MeasurableRow: View {
    let label: String
    let value: String?

    var body: some View {
        LabeledContent(label) {
            Text(value ?? "—")
                .font(.body.monospacedDigit())
                .foregroundStyle(value != nil ? Color.textPrimary : Color.textTertiary)
        }
    }
}

private struct CombineMeasurableRow: View {
    let label: String
    let value: String?
    let percentile: Int?
    let posLabel: String
    var recordNote: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.body)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                if let value {
                    HStack(spacing: 8) {
                        Text(value)
                            .font(.body.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Color.textPrimary)

                        if let pct = percentile {
                            Text("\(ordinal(pct)) %ile for \(posLabel)")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(percentileColor(pct))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(percentileColor(pct).opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                } else {
                    Text("—")
                        .font(.body.monospacedDigit())
                        .foregroundStyle(Color.textTertiary)
                }
            }

            if let note = recordNote {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.accentGold)
                    Text(note)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.accentGold)
                }
            }
        }
    }

    private func ordinal(_ n: Int) -> String {
        let suffix: String
        let ones = n % 10
        let tens = (n / 10) % 10
        if tens == 1 {
            suffix = "th"
        } else {
            switch ones {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(n)\(suffix)"
    }

    private func percentileColor(_ pct: Int) -> Color {
        if pct >= 90 { return .accentGold }
        if pct >= 75 { return .success }
        if pct >= 50 { return .accentBlue }
        if pct >= 25 { return .warning }
        return .danger
    }
}

private struct StatusPill: View {
    let label: String
    let completed: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(completed ? Color.success : Color.textTertiary)
                .font(.subheadline)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(completed ? Color.textPrimary : Color.textTertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(completed ? Color.success.opacity(0.15) : Color.backgroundTertiary)
        )
        .accessibilityLabel("\(label) \(completed ? "completed" : "not completed")")
    }
}

private struct InterestBadge: View {
    let level: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: iconName)
                .foregroundStyle(badgeColor)
                .font(.caption)
            Text(level)
                .font(.caption.weight(.semibold))
                .foregroundStyle(badgeColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(badgeColor.opacity(0.15))
        )
    }

    private var iconName: String {
        switch level {
        case "Hot":     return "flame.fill"
        case "Warm":    return "thermometer.medium"
        case "Cold":    return "thermometer.snowflake"
        default:        return "questionmark.circle"
        }
    }

    private var badgeColor: Color {
        switch level {
        case "Hot":     return .danger
        case "Warm":    return .warning
        case "Cold":    return .accentBlue
        default:        return .textTertiary
        }
    }
}

// MARK: - Send Scout Sheet

private struct SendScoutSheet: View {
    let prospect: CollegeProspect
    let scouts: [Scout]
    let scoutingPhase: ScoutingPhase
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()

                if scouts.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "person.slash")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.textTertiary)
                        Text("No Scouts Available")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                        Text("Hire scouts from the Scout Team tab.")
                            .foregroundStyle(Color.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section {
                            HStack(spacing: 8) {
                                Image(systemName: "info.circle")
                                    .foregroundStyle(Color.accentBlue.opacity(0.6))
                                Text("Phase: \(scoutingPhase.displayName) (Confidence: \(Int(scoutingPhase.confidenceLevel * 100))%)")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                        .listRowBackground(Color.backgroundSecondary)

                        Section("Select a Scout") {
                            ForEach(scouts) { scout in
                                Button {
                                    sendScout(scout)
                                } label: {
                                    ScoutRowView(scout: scout)
                                }
                                .listRowBackground(Color.backgroundSecondary)
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Send Scout to \(prospect.firstName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func sendScout(_ scout: Scout) {
        let report = ScoutingEngine.generateScoutReport(
            scout: scout,
            prospect: prospect,
            phase: scoutingPhase
        )
        ScoutingEngine.applyReport(report: report, to: prospect)
        dismiss()
    }
}
