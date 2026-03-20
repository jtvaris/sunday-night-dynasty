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
                boomBustSection
                starterComparisonSection
                collegeProductionSection
                schemeFitSection
                riskFlagsSection
                combineSection
                if prospect.interviewCompleted { interviewResultsSection }
                if isScouted { scoutingReportSection }
                draftSection
                actionsSection
            }
            .scrollContentBackground(.hidden)
            .listStyle(.insetGrouped)
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

                if let overall = prospect.scoutedOverall {
                    VStack(spacing: 2) {
                        Text("\(overall)")
                            .font(.system(size: 36, weight: .heavy).monospacedDigit())
                            .foregroundStyle(Color.forRating(overall))
                        Text("Overall")
                            .font(.caption2)
                            .foregroundStyle(Color.textTertiary)
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

    // MARK: - Boom/Bust Risk Section

    @ViewBuilder
    private var boomBustSection: some View {
        let risk = prospect.riskLevel
        if risk != .unknown {
            Section("Risk Profile") {
                HStack(spacing: 10) {
                    Image(systemName: risk.icon)
                        .font(.title3)
                        .foregroundStyle(risk.color)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(risk.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(risk.color)
                        Text(riskExplanation(risk))
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                    Spacer()
                    Text(risk.rawValue)
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(risk.color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(risk.color.opacity(0.15))
                        )
                }

                // Show scout report variance detail if multiple reports
                if prospect.scoutingReports.count >= 2 {
                    let grades = prospect.scoutingReports.map { $0.overallGrade }
                    let minG = grades.min() ?? 0
                    let maxG = grades.max() ?? 0
                    HStack(spacing: 8) {
                        Image(systemName: "chart.bar.fill")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                        Text("Scout grades range: \(minG) - \(maxG) (spread: \(maxG - minG))")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                if let pot = prospect.scoutedPotential, let ovr = prospect.scoutedOverall {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                        Text("Potential gap: +\(pot - ovr) from current (\(ovr) \u{2192} \(pot))")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
            .listRowBackground(Color.backgroundSecondary)
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
        if isScouted, let prospectOVR = prospect.scoutedOverall {
            let starters = teamPlayers
                .filter { $0.position == prospect.position }
                .sorted { $0.overall > $1.overall }
            if let starter = starters.first {
                Section("vs Current Starter") {
                    HStack(spacing: 12) {
                        VStack(spacing: 2) {
                            Text(prospect.fullName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.textPrimary)
                            Text("\(prospectOVR)")
                                .font(.title3.weight(.heavy).monospacedDigit())
                                .foregroundStyle(Color.forRating(prospectOVR))
                            Text("Prospect")
                                .font(.caption2)
                                .foregroundStyle(Color.textTertiary)
                        }
                        .frame(maxWidth: .infinity)

                        let diff = prospectOVR - starter.overall
                        VStack(spacing: 2) {
                            Text("vs")
                                .font(.caption2)
                                .foregroundStyle(Color.textTertiary)
                            Text(diff >= 0 ? "+\(diff)" : "\(diff)")
                                .font(.callout.weight(.heavy).monospacedDigit())
                                .foregroundStyle(diff > 0 ? Color.success : (diff == 0 ? Color.warning : Color.danger))
                            Text(diff > 0 ? "Upgrade" : (diff == 0 ? "Lateral" : "Depth add"))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(diff > 0 ? Color.success : (diff == 0 ? Color.warning : Color.textSecondary))
                        }

                        VStack(spacing: 2) {
                            Text(starter.fullName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.textPrimary)
                            Text("\(starter.overall)")
                                .font(.title3.weight(.heavy).monospacedDigit())
                                .foregroundStyle(Color.forRating(starter.overall))
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

    // MARK: - Combine Section

    private var combineSection: some View {
        Section("Physical Measurables") {
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
            if let overall = prospect.scoutedOverall {
                LabeledContent("Overall Grade") {
                    Text("\(overall)")
                        .font(.body.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.forRating(overall))
                }
            }

            if let potential = prospect.scoutedPotential {
                LabeledContent("Potential Grade") {
                    Text("\(potential)")
                        .font(.body.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.forRating(potential))
                }
            }

            if let grade = prospect.scoutGrade {
                LabeledContent("Scout Grade") {
                    Text(grade)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentGold)
                }
            }

            if let personality = prospect.scoutedPersonality {
                LabeledContent("Personality") {
                    Text(personality.displayName)
                        .foregroundStyle(Color.textPrimary)
                }
            }

            // Status indicators
            HStack(spacing: 16) {
                StatusPill(label: "Interview", completed: prospect.interviewCompleted)
                StatusPill(label: "Pro Day",   completed: prospect.proDayCompleted)
            }
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    // MARK: - Interview Results Section

    @ViewBuilder
    private var interviewResultsSection: some View {
        Section("Interview Results") {
            if let personality = prospect.scoutedPersonality {
                LabeledContent("Personality") {
                    Text(personality.displayName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentGold)
                }
            }

            if let iq = prospect.interviewFootballIQ {
                LabeledContent("Football IQ") {
                    Text("\(iq)")
                        .font(.body.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.forRating(iq))
                }
            }

            if let notes = prospect.interviewCharacterNotes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Character Notes")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                    ForEach(notes, id: \.self) { note in
                        HStack(spacing: 6) {
                            Image(systemName: "person.fill.checkmark")
                                .font(.caption)
                                .foregroundStyle(Color.accentBlue)
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

    // MARK: - College Production Section

    @ViewBuilder
    private var collegeProductionSection: some View {
        Section("College Production") {
            HStack(spacing: 20) {
                ProspectInfoPill(label: "Height", value: heightLabel)
                ProspectInfoPill(label: "Weight", value: "\(prospect.weight) lbs")
                ProspectInfoPill(label: "Age", value: "\(prospect.age)")
            }

            if isScouted {
                collegeFlavorStats
            }
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    @ViewBuilder
    private var collegeFlavorStats: some View {
        switch prospect.truePositionAttributes {
        case .quarterback(let qb):
            HStack(spacing: 14) {
                flavorStat(label: "Arm", value: qb.armStrength)
                flavorStat(label: "Acc (S)", value: qb.accuracyShort)
                flavorStat(label: "Acc (D)", value: qb.accuracyDeep)
                flavorStat(label: "Pocket", value: qb.pocketPresence)
            }
        case .wideReceiver(let wr):
            HStack(spacing: 14) {
                flavorStat(label: "Route", value: wr.routeRunning)
                flavorStat(label: "Catch", value: wr.catching)
                flavorStat(label: "Release", value: wr.release)
            }
        case .runningBack(let rb):
            HStack(spacing: 14) {
                flavorStat(label: "Vision", value: rb.vision)
                flavorStat(label: "Elusiv", value: rb.elusiveness)
                flavorStat(label: "Recv", value: rb.receiving)
            }
        case .defensiveBack(let db):
            HStack(spacing: 14) {
                flavorStat(label: "Man", value: db.manCoverage)
                flavorStat(label: "Zone", value: db.zoneCoverage)
                flavorStat(label: "Press", value: db.press)
            }
        case .linebacker(let lb):
            HStack(spacing: 14) {
                flavorStat(label: "Tackle", value: lb.tackling)
                flavorStat(label: "Zone", value: lb.zoneCoverage)
                flavorStat(label: "Blitz", value: lb.blitzing)
            }
        case .defensiveLine(let dl):
            HStack(spacing: 14) {
                flavorStat(label: "Pass Rush", value: dl.passRush)
                flavorStat(label: "Shed", value: dl.blockShedding)
                flavorStat(label: "Power", value: dl.powerMoves)
            }
        case .offensiveLine(let ol):
            HStack(spacing: 14) {
                flavorStat(label: "Run Blk", value: ol.runBlock)
                flavorStat(label: "Pass Blk", value: ol.passBlock)
                flavorStat(label: "Anchor", value: ol.anchor)
            }
        case .tightEnd(let te):
            HStack(spacing: 14) {
                flavorStat(label: "Block", value: te.blocking)
                flavorStat(label: "Catch", value: te.catching)
                flavorStat(label: "Route", value: te.routeRunning)
            }
        case .kicking(let k):
            HStack(spacing: 14) {
                flavorStat(label: "Power", value: k.kickPower)
                flavorStat(label: "Accuracy", value: k.kickAccuracy)
            }
        }
    }

    private func flavorStat(label: String, value: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(Color.forRating(value))
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
        }
    }

    // MARK: - Scheme Fit Section

    @ViewBuilder
    private var schemeFitSection: some View {
        if isScouted, let fit = evaluateSchemeFit() {
            Section("Scheme Fit") {
                HStack(spacing: 10) {
                    Image(systemName: schemeFitIcon(fit))
                        .font(.title3)
                        .foregroundStyle(schemeFitColor(fit))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Scheme Fit: \(fit)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(schemeFitColor(fit))
                        Text(schemeFitExplanation(fit))
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                    Spacer()
                    Text(fit)
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(schemeFitColor(fit))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(schemeFitColor(fit).opacity(0.15))
                        )
                }
            }
            .listRowBackground(Color.backgroundSecondary)
        }
    }

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
                            .foregroundStyle(Color.accentGold)
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
        case 1:    return .success
        case 2...3: return .accentGold
        case 4...5: return .warning
        default:   return .textSecondary
        }
    }

    /// Maps the career's current season phase to a scouting phase for report generation.
    private var currentScoutingPhase: ScoutingPhase {
        switch career.currentPhase {
        case .combine:
            return .combine
        case .freeAgency, .draft:
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
        if pct >= 70 { return .success }
        if pct >= 40 { return .textPrimary }
        return .warning
    }
}

private struct StatusPill: View {
    let label: String
    let completed: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(completed ? Color.success : Color.textTertiary)
                .font(.caption)
            Text(label)
                .font(.caption)
                .foregroundStyle(completed ? Color.textPrimary : Color.textTertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
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
                                    .foregroundStyle(Color.accentGold)
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


// MARK: - Preview

#Preview {
    NavigationStack {
        ProspectDetailView(
            career: Career(playerName: "John Doe", role: .gm, capMode: .simple),
            prospect: CollegeProspect(
                firstName: "Caleb", lastName: "Williams",
                college: "USC", position: .QB,
                age: 21, height: 74, weight: 214,
                truePositionAttributes: .quarterback(QBAttributes(
                    armStrength: 92, accuracyShort: 88, accuracyMid: 90,
                    accuracyDeep: 85, pocketPresence: 87, scrambling: 78
                )),
                truePersonality: PlayerPersonality(archetype: .fieryCompetitor, motivation: .winning),
                scoutedOverall: 89, scoutedPotential: 94,
                scoutedPersonality: .fieryCompetitor,
                scoutGrade: "A",
                fortyTime: 4.62, benchPress: 18, verticalJump: 33.5,
                broadJump: 118, shuttleTime: 4.24, coneDrill: 6.87,
                interviewCompleted: true, proDayCompleted: false,
                draftProjection: 1
            )
        )
    }
    .modelContainer(for: [Career.self, Scout.self, CollegeProspect.self], inMemory: true)
}
