import Foundation

enum ScoutingEngine {

    // MARK: - College List

    static let colleges = [
        "Alabama", "Ohio State", "Georgia", "Michigan", "Clemson",
        "LSU", "Oklahoma", "Texas", "USC", "Oregon",
        "Penn State", "Florida", "Tennessee", "Auburn", "Notre Dame",
        "Wisconsin", "Miami", "Florida State", "Texas A&M", "Washington",
        "UCLA", "Stanford", "Iowa", "Michigan State", "North Carolina",
        "Virginia Tech", "Baylor", "TCU", "Ole Miss", "Arkansas",
        "Kentucky", "Pittsburgh", "Utah", "Arizona State", "Colorado",
        "Minnesota", "Illinois", "Boston College", "Wake Forest", "Duke"
    ]

    // MARK: - Draft Class Strength

    /// Per-class positional strength profile. Owned by `DraftClassBuilder` now;
    /// re-exported here so existing news/UI call sites keep compiling.
    typealias DraftClassStrength = DraftClassBuilder.DraftClassStrength

    /// Strength profile of the most recently generated class.
    static var lastDraftClassStrength: DraftClassStrength? {
        DraftClassBuilder.lastClassStrength
    }

    // MARK: - Prospect Generation

    /// Generates a full draft class of college prospects.
    ///
    /// Thin wrapper — the generator itself lives in `DraftClassBuilder`
    /// (`docs/DRAFT_CLASS_OVERHAUL_PLAN.md` §2). Signature, return type and every
    /// call site are unchanged; `draftProjection` now comes straight from the
    /// prospect's grade band instead of a `trueOverall × positionValue` sort
    /// with per-position first-round caps and round-2 overflow.
    /// - Parameter careerID: the save this class belongs to. Only seeds the
    ///   market's consensus error (`DraftClassBuilder.consensusError`), so the
    ///   same save always produces the same wrong public board.
    static func generateDraftClass(
        count: Int = 350,
        careerID: UUID? = nil
    ) -> [CollegeProspect] {
        DraftClassBuilder.build(count: count, careerID: careerID).prospects
    }

    // MARK: - Anthropometrics (Hand Size / Arm Length / Wingspan)

    /// Generates position-appropriate hand size, arm length, and wingspan in inches.
    /// Heuristic distributions — premium positions skew larger.
    static func generateAnthropometrics(for position: Position) -> (handSize: Double, armLength: Double, wingspan: Double) {
        let handRange: ClosedRange<Double>
        let armRange: ClosedRange<Double>
        let wingspanRange: ClosedRange<Double>

        switch position {
        case .QB:
            // Large hands premium: 9.0-10.5 typical
            handRange = 8.75...10.5
            armRange = 31.0...33.5
            wingspanRange = 74.0...80.0
        case .LT, .RT, .LG, .RG, .C:
            // Long arms premium for OL: 33-36 elite tackles
            handRange = 9.25...10.75
            armRange = 32.5...36.0
            wingspanRange = 78.0...86.0
        case .DE, .DT:
            // DL: long arms + wingspan elite
            handRange = 9.0...10.5
            armRange = 32.0...35.5
            wingspanRange = 78.0...85.0
        case .CB, .FS, .SS:
            // DB: arm length 31-34, wingspan premium
            handRange = 8.5...10.0
            armRange = 30.5...34.0
            wingspanRange = 73.0...82.0
        case .WR:
            // WR: balanced, taller WRs benefit from longer arms
            handRange = 8.75...10.25
            armRange = 30.5...33.5
            wingspanRange = 72.0...80.0
        case .TE:
            // TE: longer arms aid blocking & catch radius
            handRange = 9.0...10.5
            armRange = 31.5...34.5
            wingspanRange = 76.0...83.0
        case .RB, .FB:
            // Average build
            handRange = 8.5...10.0
            armRange = 30.0...32.5
            wingspanRange = 72.0...78.0
        case .OLB, .MLB:
            // LB: balanced
            handRange = 9.0...10.25
            armRange = 31.0...34.0
            wingspanRange = 75.0...81.0
        case .K, .P:
            handRange = 8.0...9.5
            armRange = 30.0...32.5
            wingspanRange = 70.0...76.0
        }

        func roundToTwo(_ v: Double) -> Double {
            (v * 100).rounded() / 100
        }
        func clamp(_ v: Double, _ range: ClosedRange<Double>) -> Double {
            Swift.min(range.upperBound, Swift.max(range.lowerBound, v))
        }

        // Slight noise around the midpoint biased toward center for realism
        func rollInRange(_ range: ClosedRange<Double>) -> Double {
            let center = (range.lowerBound + range.upperBound) / 2.0
            let raw = Double.random(in: range)
            // Bias toward center via simple averaging
            return roundToTwo((raw + center) / 2.0)
        }

        let hand = rollInRange(handRange)
        let arm = rollInRange(armRange)
        // Wingspan is loosely correlated with arm length — add small jitter
        let wingBase = rollInRange(wingspanRange)
        let armCenter = (armRange.lowerBound + armRange.upperBound) / 2.0
        let wingspan = roundToTwo(wingBase + (arm - armCenter))

        return (
            handSize: clamp(hand, 8.0...11.5),
            armLength: clamp(arm, 30.0...37.0),
            wingspan: clamp(wingspan, 70.0...90.0)
        )
    }

    // MARK: - Personality Reads
    //
    // Every personality read in the build funnels through the two functions
    // below. Before #185 the honest version of this roll lived inside
    // `scoutProspect` — a function with ZERO callers — while the code that
    // actually ran, `applyReport`, flipped a hard-coded 70 % coin that ignored
    // the scout's `personalityRead` and his character focus entirely. The dead
    // function is gone; its logic lives here, where the live path calls it.

    /// What a scout files when he watched the man and still cannot tell you
    /// anything. Named rather than inlined because `applyPersonalityRead` has to
    /// recognise a shrug and refuse to turn it into an archetype on the card.
    static let inconclusivePersonalityNote =
        "Hard to get a clear read on personality. Seems fine on the surface."

    /// Rolls one evaluator's read of a prospect's character.
    ///
    /// A miss is not "no answer" — it is a CONFIDENT WRONG answer, which is the
    /// fog this game ships: a scout who cannot read a man still files an
    /// opinion. The CALLER decides what a miss is allowed to do; see
    /// `applyReport`'s F7 rule — a miss must never degrade a read that is
    /// already on the card.
    ///
    /// - Parameters:
    ///   - trueArchetype: The prospect's real archetype.
    ///   - readSkill: The evaluator's `personalityRead` (1–99).
    ///   - characterFocus: `true` when the scout is assigned to character work.
    ///     Worth +20, the same bonus `generateScoutReport` gives the prose note.
    /// - Returns: The archetype read, and whether it is the true one.
    static func rollPersonalityRead(
        trueArchetype: PersonalityArchetype,
        readSkill: Int,
        characterFocus: Bool
    ) -> (archetype: PersonalityArchetype, accurate: Bool) {
        let threshold = min(99, readSkill + (characterFocus ? 20 : 0))
        if Int.random(in: 1...100) <= threshold {
            return (trueArchetype, true)
        }
        let wrong = PersonalityArchetype.allCases
            .filter { $0 != trueArchetype }
            .randomElement() ?? trueArchetype
        return (wrong, false)
    }

    /// The one writer of `scoutedPersonality`, and the only place that stamps
    /// where the read came from.
    ///
    /// Refuses a read from an instrument weaker than the one already on file
    /// (`PersonalitySource.strength`): a routine weekly report cannot overwrite
    /// what a private workout established, and an interview read can only be
    /// revised by another interview — which is what makes the card's
    /// "From your interview" attribution true rather than decorative.
    ///
    /// - Returns: `true` when the read was written.
    @discardableResult
    static func recordPersonalityRead(
        _ archetype: PersonalityArchetype,
        source: PersonalitySource,
        on prospect: CollegeProspect
    ) -> Bool {
        if let current = prospect.scoutedPersonalitySource, source.strength < current.strength {
            return false
        }
        prospect.scoutedPersonality = archetype
        prospect.scoutedPersonalitySource = source
        return true
    }

    // MARK: - Report Precision (the one exchange rate)

    /// The two numbers `generateScoutReport` derives from a scout BEFORE it
    /// rolls anything: the ± band it puts on the prospect's overall, and the
    /// accuracy every letter grade and prose note is cut with.
    struct ReportPrecision {
        /// Half-width of the uniform noise on `scoutedOverall`, in OVR points.
        let overallError: Int
        /// The accuracy fed to the grade/note generators.
        let gradingAccuracy: Int
    }

    /// Prices a scout on one position, in the report's own units.
    ///
    /// Split out of `generateScoutReport` because the pro-day screen has to
    /// CHOOSE between two scouts, and the rule it chose with ("the specialist,
    /// else the most accurate man") recommended dominated picks. The
    /// specialisation bonus is +3 ERROR points and accuracy buys error points at
    /// 15 per 100, so a 59-accuracy specialist and a 79-accuracy generalist file
    /// the same ±3 read — and every specialist further below that line was a
    /// strictly worse report the screen recommended anyway. There is exactly one
    /// defensible exchange rate between accuracy points and the +3, and it is
    /// the one the report itself uses; this makes that rate callable rather than
    /// re-derivable, so the screen and the roll can never disagree.
    ///
    /// - Parameters:
    ///   - position: the position being evaluated, or `nil` to price the scout
    ///     with no specialisation or focus edge in play.
    ///   - onHomeBeat: whether the evaluation happens inside the scout's own
    ///     region — see `isHomeRegion(scout:college:)`.
    static func reportPrecision(
        scout: Scout,
        position: Position?,
        onHomeBeat: Bool = false
    ) -> ReportPrecision {
        // 1. Noise range based on scout accuracy (with familiarity bonus)
        let familiarityBonus = (scout.seasonsInRole >= 2 ? 5 : 0)
            + (onHomeBeat ? homeBeatAccuracyBonus : 0)
        let effectiveBaseAccuracy = min(99, scout.accuracy + familiarityBonus)
        let errorRange = max(2, Int(15.0 * (1.0 - Double(effectiveBaseAccuracy) / 100.0)))

        // Position specialization bonus
        var accuracyBonus = 0
        if let position, let spec = scout.positionSpecialization, spec == position {
            accuracyBonus += 3
        }
        // Focus position bonus: +15% accuracy when scout focuses on the prospect's position
        if let position, let focusPos = scout.focusPosition, focusPos == position {
            accuracyBonus += 15
        }
        return ReportPrecision(
            overallError: max(1, errorRange - accuracyBonus),
            gradingAccuracy: min(99, scout.accuracy + accuracyBonus)
        )
    }

    // MARK: - Phase-Based Scout Report Generation

    /// Generate a scouting report for a prospect based on scout's abilities and the scouting phase.
    ///
    /// - Parameter onHomeBeat: `true` when the scout is working inside his own
    ///   region. Only `attendProDay` passes it — the combine is in Indianapolis
    ///   and belongs to nobody's beat, and film study happens at the facility.
    static func generateScoutReport(
        scout: Scout,
        prospect: CollegeProspect,
        phase: ScoutingPhase,
        onHomeBeat: Bool = false
    ) -> ScoutingReport {
        // 1. Noise range and grading accuracy — one source of truth, shared with
        //    the pro-day screen's scout picker.
        let precision = reportPrecision(
            scout: scout,
            position: prospect.position,
            onHomeBeat: onHomeBeat
        )
        let adjustedError = precision.overallError

        // 2. Scouted overall with noise
        let overallNoise = Int.random(in: -adjustedError...adjustedError)
        let scoutedOverall = min(99, max(1, prospect.trueOverall + overallNoise))

        // 3. Scouted potential with noise based on potentialRead
        // Mental focus gives +15 bonus to potential read accuracy
        let mentalBonus = scout.focusAttribute == .mental ? 15 : 0
        let effectivePotentialRead = min(99, scout.potentialRead + mentalBonus)
        let potentialError = max(2, Int(15.0 * (1.0 - Double(effectivePotentialRead) / 100.0)))
        let potentialNoise = Int.random(in: -potentialError...potentialError)
        let scoutedPotential = min(99, max(1, prospect.truePotential + potentialNoise))

        // 4. Personality assessment based on personalityRead
        // Character focus gives +20 bonus to personality read
        let characterBonus = scout.focusAttribute == .character ? 20 : 0
        let personalityNotes: String?
        let personalityRoll = Int.random(in: 1...100)
        if personalityRoll <= min(99, scout.personalityRead + characterBonus) {
            personalityNotes = accuratePersonalityNote(archetype: prospect.truePersonality.archetype)
        } else if personalityRoll <= min(99, scout.personalityRead + characterBonus) + 25 {
            personalityNotes = inconclusivePersonalityNote
        } else {
            personalityNotes = nil
        }

        // 5. Strength and weakness notes (position-appropriate, 2-3 each)
        let effectiveAccuracy = precision.gradingAccuracy
        let strengthNotes = generatePositionStrengths(for: prospect, accuracy: effectiveAccuracy)
        let weaknessNotes = generatePositionWeaknesses(for: prospect, accuracy: effectiveAccuracy)

        // 6. Confidence level based on phase, with focus attribute bonus
        let baseConfidence = phase.confidenceLevel
        let focusAttrBonus: Double = (scout.focusAttribute == .physical || scout.focusAttribute == .mental) ? 0.10 : 0.0
        let confidenceLevel = min(1.0, baseConfidence + focusAttrBonus)

        // 7. Generate per-attribute letter grades for mental and position skills
        let mentalGrades = generateMentalGrades(
            mental: prospect.trueMental,
            learning: prospect.trueLearning,
            competitiveness: prospect.trueCompetitiveness,
            accuracy: effectiveAccuracy,
            positionSpec: scout.positionSpecialization == prospect.position,
            mentalFocus: scout.focusAttribute == .mental
        )
        let positionGrades = generatePositionSkillGrades(
            attributes: prospect.truePositionAttributes,
            accuracy: effectiveAccuracy,
            positionSpec: scout.positionSpecialization == prospect.position,
            physicalFocus: scout.focusAttribute == .physical
        )
        let overallLetterGrade = LetterGrade.from(numericValue: scoutedOverall)
        let potentialLabel = PotentialLabel.from(
            potential: prospect.truePotential,
            noise: max(0, 3 - (effectivePotentialRead / 30))
        )

        // 8. Create and return the report
        return ScoutingReport(
            prospectID: prospect.id,
            scoutID: scout.id,
            scoutName: scout.fullName,
            date: currentDateString(),
            phase: phase,
            overallGrade: scoutedOverall,
            potentialGrade: scoutedPotential,
            strengthNotes: strengthNotes,
            weaknessNotes: weaknessNotes,
            personalityNotes: personalityNotes,
            confidenceLevel: confidenceLevel,
            mentalGrades: mentalGrades,
            positionSkillGrades: positionGrades,
            overallLetterGrade: overallLetterGrade,
            potentialLabel: potentialLabel
        )
    }

    // MARK: - Grade Generation Helpers

    /// Generates letter grades for each mental attribute with noise based on scout accuracy.
    /// - Parameters:
    ///   - learning: The prospect's `trueLearning`, surfaced as the `LRN` grade.
    ///   - competitiveness: The prospect's `trueCompetitiveness`, surfaced as the
    ///     `CMP` grade (phase-2 plan §2.1). Same scout fog as every other mental
    ///     read — a fighter can be missed, and a coaster can grade out well.
    private static func generateMentalGrades(
        mental: MentalAttributes,
        learning: Int,
        competitiveness: Int,
        accuracy: Int,
        positionSpec: Bool,
        mentalFocus: Bool = false
    ) -> [String: LetterGrade] {
        // Higher accuracy = less noise. Noise in grade steps: low acc → ±3, high acc → ±1
        // Mental focus reduces noise by 1 additional step
        let noiseSteps = max(0, 4 - accuracy / 25 - (positionSpec ? 1 : 0) - (mentalFocus ? 1 : 0))

        func gradeWithNoise(_ value: Int) -> LetterGrade {
            let trueGrade = LetterGrade.from(numericValue: value)
            let shift = Int.random(in: -noiseSteps...noiseSteps)
            return trueGrade.shifted(by: shift)
        }

        return [
            "AWR": gradeWithNoise(mental.awareness),
            "DEC": gradeWithNoise(mental.decisionMaking),
            "CLT": gradeWithNoise(mental.clutch),
            "WRK": gradeWithNoise(mental.workEthic),
            "COA": gradeWithNoise(mental.coachability),
            "LDR": gradeWithNoise(mental.leadership),
            "LRN": gradeWithNoise(learning),
            "CMP": gradeWithNoise(competitiveness),
        ]
    }

    /// Generates letter grades for position-specific skills with noise.
    private static func generatePositionSkillGrades(attributes: PositionAttributes, accuracy: Int, positionSpec: Bool, physicalFocus: Bool = false) -> [String: LetterGrade] {
        // Physical focus reduces noise by 1 additional step
        let noiseSteps = max(0, 4 - accuracy / 25 - (positionSpec ? 1 : 0) - (physicalFocus ? 1 : 0))

        func gradeWithNoise(_ value: Int) -> LetterGrade {
            let trueGrade = LetterGrade.from(numericValue: value)
            let shift = Int.random(in: -noiseSteps...noiseSteps)
            return trueGrade.shifted(by: shift)
        }

        switch attributes {
        case .quarterback(let a):
            return ["ARM": gradeWithNoise(a.armStrength), "SAC": gradeWithNoise(a.accuracyShort),
                    "MAC": gradeWithNoise(a.accuracyMid), "DAC": gradeWithNoise(a.accuracyDeep),
                    "PKT": gradeWithNoise(a.pocketPresence), "SCR": gradeWithNoise(a.scrambling)]
        case .wideReceiver(let a):
            return ["RTE": gradeWithNoise(a.routeRunning), "CTH": gradeWithNoise(a.catching),
                    "RLS": gradeWithNoise(a.release), "SPC": gradeWithNoise(a.spectacularCatch)]
        case .runningBack(let a):
            return ["VIS": gradeWithNoise(a.vision), "ELU": gradeWithNoise(a.elusiveness),
                    "BTK": gradeWithNoise(a.breakTackle), "RCV": gradeWithNoise(a.receiving)]
        case .tightEnd(let a):
            return ["BLK": gradeWithNoise(a.blocking), "CTH": gradeWithNoise(a.catching),
                    "RTE": gradeWithNoise(a.routeRunning), "SPD": gradeWithNoise(a.speed)]
        case .offensiveLine(let a):
            return ["RBK": gradeWithNoise(a.runBlock), "PBK": gradeWithNoise(a.passBlock),
                    "PUL": gradeWithNoise(a.pull), "ANC": gradeWithNoise(a.anchor)]
        case .defensiveLine(let a):
            return ["PRU": gradeWithNoise(a.passRush), "BSH": gradeWithNoise(a.blockShedding),
                    "PWR": gradeWithNoise(a.powerMoves), "FIN": gradeWithNoise(a.finesseMoves)]
        case .linebacker(let a):
            return ["TKL": gradeWithNoise(a.tackling), "ZCV": gradeWithNoise(a.zoneCoverage),
                    "MCV": gradeWithNoise(a.manCoverage), "BLZ": gradeWithNoise(a.blitzing)]
        case .defensiveBack(let a):
            return ["MCV": gradeWithNoise(a.manCoverage), "ZCV": gradeWithNoise(a.zoneCoverage),
                    "PRS": gradeWithNoise(a.press), "BSK": gradeWithNoise(a.ballSkills)]
        case .kicking(let a):
            return ["PWR": gradeWithNoise(a.kickPower), "ACC": gradeWithNoise(a.kickAccuracy)]
        }
    }

    /// Apply a scouting report to update prospect's visible attributes based on the best available report.
    ///
    /// - Parameter scout: The scout who filed `report`, when one exists. His
    ///   `personalityRead` and character focus decide whether the report's
    ///   character read lands, so pass him wherever he is in hand. `nil` means
    ///   the filer is not a scout — a coaching-staff workout, a broadcast
    ///   showcase desk — and the personality read is left to that caller.
    static func applyReport(report: ScoutingReport, to prospect: CollegeProspect, scout: Scout? = nil) {
        // Add report to the prospect's collection
        prospect.scoutingReports.append(report)

        // Find the report with the highest confidence
        guard let bestReport = prospect.scoutingReports.max(by: { $0.confidenceLevel < $1.confidenceLevel }) else {
            return
        }

        // Legacy: Update numeric scouted values (kept for backward compat)
        prospect.scoutedOverall = bestReport.overallGrade
        prospect.scoutedPotential = bestReport.potentialGrade

        // Scout grade based on best scouted overall
        prospect.scoutGrade = LetterGrade.from(numericValue: bestReport.overallGrade).rawValue

        // New: Update grade-based scouting fields
        applyGradeBasedFields(report: report, to: prospect)

        applyPersonalityRead(from: report, scout: scout, to: prospect)
    }

    /// The personality half of `applyReport`, split out because #185 found four
    /// separate bugs living in the six lines it replaces:
    ///
    /// 1. It re-rolled whenever ANY report on file carried personality notes —
    ///    including the inherited "Previous Staff" row every top-50 prospect
    ///    starts the save with — so a report that read nothing still rewrote the
    ///    card. Only the report BEING FILED can move the read now.
    /// 2. It flipped a fixed 70 % coin, throwing away the scout's
    ///    `personalityRead` and his character focus. It now rolls the real
    ///    instrument, the same one that wrote the report's prose note.
    /// 3. It could overwrite the read the card attributes to the user's own
    ///    interview. `recordPersonalityRead` refuses weaker instruments.
    /// 4. A missed read replaced a good answer with a wrong one — #fleet review
    ///    F7, which had been fixed for the workout path only. A miss now writes
    ///    only onto a blank card; otherwise the earlier read stands.
    private static func applyPersonalityRead(
        from report: ScoutingReport,
        scout: Scout?,
        to prospect: CollegeProspect
    ) {
        // No scout, no instrument to roll. The coaching staff's private workout
        // files its own read right after this returns (`conductPrivateWorkout`).
        guard let scout else { return }

        // THIS report has to have produced a character read. `nil` notes mean
        // the scout came back with nothing, and the inconclusive note means he
        // came back with a shrug — a shrug must not turn into an archetype on
        // the card, or the paragraph and the label contradict each other on the
        // same screen.
        guard let notes = report.personalityNotes,
              notes != inconclusivePersonalityNote else { return }

        let read = rollPersonalityRead(
            trueArchetype: prospect.truePersonality.archetype,
            readSkill: scout.personalityRead,
            characterFocus: scout.focusAttribute == .character
        )

        // A confident misread is legitimate fog on a blank card. It is never an
        // upgrade on a read that is already on file (F7).
        guard read.accurate || prospect.scoutedPersonality == nil else { return }

        recordPersonalityRead(read.archetype, source: .report, on: prospect)
    }

    /// Aggregates grade data from all reports into progressive GradeRange fields.
    private static func applyGradeBasedFields(report: ScoutingReport, to prospect: CollegeProspect) {
        // Overall grade — narrow with each report
        if let letterGrade = report.overallLetterGrade {
            if var existing = prospect.scoutedOverallGrade {
                existing.incorporate(newGrade: letterGrade)
                prospect.scoutedOverallGrade = existing
            } else {
                // First report — wide range (±2 grades)
                // `shifted(by:)` counts POSITIVE as BETTER, so the floor is the
                // negative step. The old spelling had the two swapped and only
                // survived because `GradeRange.init` re-sorts them — the same
                // sign confusion that broke `incorporate` (#183).
                let low = letterGrade.shifted(by: -2)  // 2 grades worse
                let high = letterGrade.shifted(by: 2)  // 2 grades better
                prospect.scoutedOverallGrade = GradeRange(low: low, high: high, reportCount: 1)
            }
        }

        // Mental grades — aggregate each attribute
        if let mentalGrades = report.mentalGrades {
            var existing = prospect.scoutedMentalGrades ?? [:]
            for (key, grade) in mentalGrades {
                if var range = existing[key] {
                    range.incorporate(newGrade: grade)
                    existing[key] = range
                } else {
                    let low = grade.shifted(by: -2)   // 2 grades worse
                    let high = grade.shifted(by: 2)    // 2 grades better
                    existing[key] = GradeRange(low: low, high: high, reportCount: 1)
                }
            }
            prospect.scoutedMentalGrades = existing
        }

        // Position skill grades — same aggregation
        if let posGrades = report.positionSkillGrades {
            var existing = prospect.scoutedPositionGrades ?? [:]
            for (key, grade) in posGrades {
                if var range = existing[key] {
                    range.incorporate(newGrade: grade)
                    existing[key] = range
                } else {
                    let low = grade.shifted(by: -2)   // 2 grades worse
                    let high = grade.shifted(by: 2)    // 2 grades better
                    existing[key] = GradeRange(low: low, high: high, reportCount: 1)
                }
            }
            prospect.scoutedPositionGrades = existing
        }

        // Potential label — use the latest report's assessment (most recent = most informed)
        if let label = report.potentialLabel {
            prospect.scoutedPotentialLabel = label
        }
    }

    // MARK: - Position-Specific Note Generators

    private static func generatePositionStrengths(for prospect: CollegeProspect, accuracy: Int) -> String {
        var pool: [String] = []
        let phys = prospect.truePhysical
        let mental = prospect.trueMental
        let threshold = max(65, 90 - accuracy / 3)

        if phys.speed >= threshold { pool.append("Elite speed") }
        if phys.acceleration >= threshold { pool.append("Explosive first step") }
        if phys.strength >= threshold { pool.append("Strong at the point of attack") }
        if phys.agility >= threshold { pool.append("Excellent lateral agility") }
        if phys.stamina >= threshold { pool.append("High motor, plays all four quarters") }
        if phys.durability >= threshold { pool.append("Durable, rarely misses time") }
        if mental.awareness >= threshold { pool.append("High football IQ") }
        if mental.decisionMaking >= threshold { pool.append("Makes good decisions under pressure") }
        if mental.clutch >= threshold { pool.append("Performs well in big moments") }
        if mental.leadership >= threshold { pool.append("Natural leader on the field") }

        switch prospect.truePositionAttributes {
        case .quarterback(let qb):
            if qb.armStrength >= threshold { pool.append("Cannon arm, can make all the throws") }
            if qb.accuracyDeep >= threshold { pool.append("Accurate deep-ball thrower") }
            if qb.pocketPresence >= threshold { pool.append("Calm in the pocket, great pocket awareness") }
            if qb.scrambling >= threshold { pool.append("Dangerous when he escapes the pocket") }
        case .wideReceiver(let wr):
            if wr.routeRunning >= threshold { pool.append("Crisp route runner") }
            if wr.catching >= threshold { pool.append("Reliable hands") }
            if wr.release >= threshold { pool.append("Gets off the line quickly") }
            if wr.spectacularCatch >= threshold { pool.append("Makes highlight-reel catches") }
        case .runningBack(let rb):
            if rb.vision >= threshold { pool.append("Excellent vision, finds the hole") }
            if rb.elusiveness >= threshold { pool.append("Elusive in the open field") }
            if rb.breakTackle >= threshold { pool.append("Hard to bring down") }
            if rb.receiving >= threshold { pool.append("Reliable receiver out of the backfield") }
        case .tightEnd(let te):
            if te.blocking >= threshold { pool.append("Strong inline blocker") }
            if te.catching >= threshold { pool.append("Sure hands in traffic") }
            if te.routeRunning >= threshold { pool.append("Runs routes like a receiver") }
        case .offensiveLine(let ol):
            if ol.passBlock >= threshold { pool.append("Elite pass protector") }
            if ol.runBlock >= threshold { pool.append("Dominant run blocker") }
            if ol.anchor >= threshold { pool.append("Great anchor against bull rushes") }
            if ol.pull >= threshold { pool.append("Athletic puller, effective on screens") }
        case .defensiveLine(let dl):
            if dl.passRush >= threshold { pool.append("Disruptive pass rusher") }
            if dl.blockShedding >= threshold { pool.append("Sheds blocks quickly") }
            if dl.powerMoves >= threshold { pool.append("Powerful bull rush") }
            if dl.finesseMoves >= threshold { pool.append("Refined pass-rush moves") }
        case .linebacker(let lb):
            if lb.tackling >= threshold { pool.append("Sure tackler") }
            if lb.zoneCoverage >= threshold { pool.append("Reads routes well in zone") }
            if lb.manCoverage >= threshold { pool.append("Can cover tight ends and backs") }
            if lb.blitzing >= threshold { pool.append("Effective as a blitzer") }
        case .defensiveBack(let db):
            if db.manCoverage >= threshold { pool.append("Lockdown man coverage skills") }
            if db.zoneCoverage >= threshold { pool.append("Reads the quarterback well in zone") }
            if db.press >= threshold { pool.append("Physical at the line of scrimmage") }
            if db.ballSkills >= threshold { pool.append("Ball hawk, creates turnovers") }
        case .kicking(let k):
            if k.kickPower >= threshold { pool.append("Strong leg, can hit from 55+") }
            if k.kickAccuracy >= threshold { pool.append("Accurate and consistent") }
        }

        if pool.isEmpty {
            pool.append("Solid overall athlete with room to grow")
        }

        pool.shuffle()
        let count = min(pool.count, Int.random(in: 2...3))
        return pool.prefix(count).joined(separator: ". ") + "."
    }

    private static func generatePositionWeaknesses(for prospect: CollegeProspect, accuracy: Int) -> String {
        var pool: [String] = []
        let phys = prospect.truePhysical
        let mental = prospect.trueMental
        let threshold = min(58, 45 + accuracy / 4)

        if phys.speed <= threshold { pool.append("Limited top-end speed") }
        if phys.acceleration <= threshold { pool.append("Slow off the snap") }
        if phys.strength <= threshold { pool.append("Needs to add strength") }
        if phys.agility <= threshold { pool.append("Stiff in the hips") }
        if phys.stamina <= threshold { pool.append("Fades late in games") }
        if phys.durability <= threshold { pool.append("Injury concerns") }
        if mental.awareness <= threshold { pool.append("Can get lost on the field") }
        if mental.decisionMaking <= threshold { pool.append("Questionable decision-making") }
        if mental.workEthic <= threshold { pool.append("Work ethic is a concern") }

        switch prospect.truePositionAttributes {
        case .quarterback(let qb):
            if qb.armStrength <= threshold { pool.append("Arm strength limits deep throws") }
            if qb.accuracyDeep <= threshold { pool.append("Struggles with accuracy downfield") }
            if qb.pocketPresence <= threshold { pool.append("Gets rattled under pressure") }
            if qb.scrambling <= threshold { pool.append("Limited mobility outside the pocket") }
        case .wideReceiver(let wr):
            if wr.routeRunning <= threshold { pool.append("Route tree needs refinement") }
            if wr.catching <= threshold { pool.append("Too many drops") }
            if wr.release <= threshold { pool.append("Struggles to get off press coverage") }
        case .runningBack(let rb):
            if rb.vision <= threshold { pool.append("Needs to improve vision") }
            if rb.elusiveness <= threshold { pool.append("Not elusive enough in space") }
            if rb.receiving <= threshold { pool.append("Limited as a pass catcher") }
        case .tightEnd(let te):
            if te.blocking <= threshold { pool.append("Blocking needs work") }
            if te.catching <= threshold { pool.append("Hands can be unreliable") }
            if te.routeRunning <= threshold { pool.append("Route running is raw") }
        case .offensiveLine(let ol):
            if ol.passBlock <= threshold { pool.append("Pass protection is inconsistent") }
            if ol.runBlock <= threshold { pool.append("Struggles to create movement in the run game") }
            if ol.anchor <= threshold { pool.append("Gets pushed back against power") }
        case .defensiveLine(let dl):
            if dl.passRush <= threshold { pool.append("Limited pass-rush arsenal") }
            if dl.blockShedding <= threshold { pool.append("Gets stuck on blocks") }
        case .linebacker(let lb):
            if lb.tackling <= threshold { pool.append("Misses too many tackles") }
            if lb.zoneCoverage <= threshold { pool.append("Liability in coverage") }
            if lb.blitzing <= threshold { pool.append("Not effective as a pass rusher") }
        case .defensiveBack(let db):
            if db.manCoverage <= threshold { pool.append("Gets beaten in man coverage") }
            if db.zoneCoverage <= threshold { pool.append("Loses discipline in zone") }
            if db.ballSkills <= threshold { pool.append("Does not create turnovers") }
        case .kicking(let k):
            if k.kickPower <= threshold { pool.append("Limited range") }
            if k.kickAccuracy <= threshold { pool.append("Inconsistent accuracy") }
        }

        if pool.isEmpty {
            pool.append("No major red flags at this time")
        }

        pool.shuffle()
        let count = min(pool.count, Int.random(in: 2...3))
        return pool.prefix(count).joined(separator: ". ") + "."
    }

    // MARK: - Combine Simulation

    /// Generate realistic combine results for invited prospects (~330 of the draft class).
    /// Top prospects by trueOverall are invited (`combineInvite = true`).
    /// K/P only get height/weight measured — no athletic drills; QBs skip the bench.
    ///
    /// Every drill is drawn from its own **per-position** mean/σ
    /// (`DRAFT_NFL_REFERENCE.md` §5) correlated r ≈ 0.8 with the underlying
    /// physical attribute, truncated at the observed floor/ceiling, with a
    /// 0.5 % freak tail for record-flirting headlines. Previously bench, vert,
    /// broad, cone and shuttle shared three coarse position groups, so a
    /// cornerback and a quarterback tested from the same distribution.
    static func generateCombineResults(for prospects: inout [CollegeProspect], scoutingAbility: Int = 50) {
        // 1. Select top ~330 prospects by trueOverall as combine invitees
        let inviteCount = min(330, prospects.count)
        let sortedIndices = prospects.indices.sorted { prospects[$0].trueOverall > prospects[$1].trueOverall }
        let invitedIndices = Set(sortedIndices.prefix(inviteCount))

        for i in invitedIndices {
            prospects[i].combineInvite = true
        }

        // 2. Generate drill results for each invitee from the position's own curve
        for i in invitedIndices {
            let position = prospects[i].position
            let phys = prospects[i].truePhysical

            // K/P only get height/weight measured, no combine drills
            if position == .K || position == .P { continue }

            let combineModifier = combinePersonalityModifier()
            let drills = CombineDrillTable.drills(for: position)

            prospects[i].fortyTime = drillResult(
                drills.forty, attribute: phys.speed, attributeKind: .speed,
                position: position, modifier: combineModifier)

            // QBs do not bench at the combine (the field is Optional, so we can
            // simply leave it unmeasured rather than invent a number).
            if position == .QB {
                prospects[i].benchPress = nil
            } else {
                let bench = drillResult(
                    drills.bench, attribute: phys.strength, attributeKind: .strength,
                    position: position, modifier: combineModifier)
                prospects[i].benchPress = Int(bench.rounded())
            }

            prospects[i].verticalJump = drillResult(
                drills.vertical, attribute: (phys.agility + phys.acceleration) / 2,
                attributeKind: .explosion, position: position, modifier: combineModifier)

            let broad = drillResult(
                drills.broad, attribute: (phys.strength + phys.acceleration) / 2,
                attributeKind: .power, position: position, modifier: combineModifier)
            prospects[i].broadJump = Int(broad.rounded())

            prospects[i].coneDrill = drillResult(
                drills.cone, attribute: (phys.agility + phys.acceleration) / 2,
                attributeKind: .explosion, position: position, modifier: combineModifier)

            prospects[i].shuttleTime = drillResult(
                drills.shuttle, attribute: (phys.agility + phys.speed) / 2,
                attributeKind: .lateral, position: position, modifier: combineModifier)
        }

        // 3. Not everybody works out. Applied AFTER the draws rather than
        //    instead of them, so a prospect's real numbers still exist to be
        //    found at his pro day (`simulateProDay` fills every field it finds
        //    empty) — the DNP withholds information, it does not delete talent.
        //
        //    Nested rather than a sibling `private static func` on purpose:
        //    `tools/balance-harness/sync_sources.sh` slices this file by an
        //    anchor list, capturing each named member's balanced block. A helper
        //    declared outside `generateCombineResults` would be called by the
        //    slice and defined nowhere in it, and the draftclass gate would stop
        //    compiling until somebody edited the harness's anchor list too.
        //
        //    Real combine participation is far patchier than this game modelled
        //    it — every invitee ran every drill. At the actual event roughly a
        //    third of invited players skip the forty (rehab, medical rechecks,
        //    agents holding a client back for a friendlier pro-day surface) and
        //    barely half bench. Those rates would gut the scouting information
        //    economy here, where the combine screen *is* the pre-draft read, so
        //    these are deliberately milder: about one invitee in eight sits out
        //    entirely and one in six trims the card. That still leaves
        //    ~330 × 0.12 ≈ 40 full DNPs per class — enough that "who do I burn a
        //    personal workout on" has an answer.
        let fullDNPRate = 0.12
        let partialDNPRate = 0.16

        /// Blanks the drills of the prospects who did not work out and returns
        /// the indices that DID — the set the position-drill grader may rank.
        ///
        /// Kickers and punters are untouched: they never had drills to withhold,
        /// and counting them as DNPs would put a rehab note on a man who did
        /// exactly what his position does at the combine.
        func applyCombineDNP(_ prospects: inout [CollegeProspect]) -> Set<Int> {
            var workedOut: Set<Int> = []
            for i in invitedIndices {
                let position = prospects[i].position
                if position == .K || position == .P { continue }

                let roll = Double.random(in: 0..<1)
                if roll < fullDNPRate {
                    prospects[i].fortyTime = nil
                    prospects[i].benchPress = nil
                    prospects[i].verticalJump = nil
                    prospects[i].broadJump = nil
                    prospects[i].coneDrill = nil
                    prospects[i].shuttleTime = nil
                    prospects[i].positionDrillGrade = nil
                    continue
                }

                workedOut.insert(i)
                guard roll < fullDNPRate + partialDNPRate else { continue }

                // The two things a healthy prospect actually skips: the bench (a
                // long-armed tackle has nothing to gain) and the agility pair
                // (the cone and the shuttle are one session, so they drop
                // together). Split by the same roll so the two never stack — a
                // partial DNP is one decision, not two.
                if roll < fullDNPRate + partialDNPRate / 2 {
                    prospects[i].benchPress = nil
                } else {
                    prospects[i].coneDrill = nil
                    prospects[i].shuttleTime = nil
                }
            }
            return workedOut
        }

        let workedOut = applyCombineDNP(&prospects)

        // 4. Position drill grades are graded *relative to the prospect's own
        //    position*, so a class produces 1–3 A/A+ testers per position
        //    (`DRAFT_NFL_REFERENCE.md` §5) rather than grading everyone against
        //    one league-wide scale. Full DNPs are excluded: a man who never took
        //    the field cannot be ranked against the men who did, and leaving him
        //    in would also drag his position's mean toward a score nobody saw.
        applyPositionDrillGrades(&prospects, invited: workedOut, scoutingAbility: scoutingAbility)
    }

    // MARK: - Combine DNP

    /// How much of the combine a prospect actually did.
    ///
    /// Derived from the *stored* measurements plus the position rules, never
    /// from a field of its own: `CollegeProspect` has no "did not participate"
    /// column, and it does not need one — an invited non-specialist with no forty
    /// time is a DNP by construction, and that is the same fact a new Bool would
    /// have carried, minus the migration.
    enum CombineParticipation: Equatable {
        /// Never invited — no combine line at all.
        case notInvited
        /// Kickers and punters: measured, weighed, interviewed, no drills.
        case specialistMeasurementsOnly
        /// Invited, worked out, full card (a QB's absent bench counts as full —
        /// quarterbacks do not bench at the combine).
        case full
        /// Invited, ran, but sat out part of the card.
        case partial(reason: String)
        /// Invited, tested in nothing.
        case didNotParticipate(reason: String)

        /// Whether the UI should label the empty cells rather than dash them.
        var isDNP: Bool {
            switch self {
            case .partial, .didNotParticipate: return true
            default: return false
            }
        }

        /// Short badge text, or `nil` when there is nothing to say.
        var badge: String? {
            switch self {
            case .didNotParticipate: return "DNP"
            case .partial:           return "Partial"
            default:                 return nil
            }
        }

        /// The sentence behind the badge.
        var reason: String? {
            switch self {
            case .partial(let reason), .didNotParticipate(let reason): return reason
            default: return nil
            }
        }
    }

    /// What a prospect's combine line means, and the sentence to show for it.
    ///
    /// Pure function of stored state — safe to call from a view body, and it
    /// gives the same answer after a relaunch, which is why the flavour text is
    /// keyed off `FaceLibrary.stableHash` (FNV-1a over the UUID bytes) rather
    /// than `hashValue`, whose seed changes every launch.
    static func combineParticipation(for prospect: CollegeProspect) -> CombineParticipation {
        guard prospect.combineInvite || prospect.fortyTime != nil else { return .notInvited }
        if prospect.position == .K || prospect.position == .P {
            return .specialistMeasurementsOnly
        }
        let pick = { (pool: [String]) -> String in
            pool[Int(FaceLibrary.stableHash(prospect.id) % UInt64(pool.count))]
        }
        guard prospect.fortyTime != nil else {
            return .didNotParticipate(reason: pick(fullDNPReasons))
        }
        // A quarterback's missing bench is the rule, not a decision.
        let skippedBench = prospect.benchPress == nil && prospect.position != .QB
        let skippedAgility = prospect.coneDrill == nil || prospect.shuttleTime == nil
        if skippedBench {
            return .partial(reason: pick(benchSkipReasons))
        }
        if skippedAgility {
            return .partial(reason: pick(agilitySkipReasons))
        }
        return .full
    }

    /// Why a prospect tested in nothing. All five point at the pro day, because
    /// that is where the numbers actually turn up — `simulateProDay` fills every
    /// measurement it finds empty, so the DNP is a delay the GM can pay to undo.
    private static let fullDNPReasons = [
        "Rehabbing a shoulder — medicals and interviews only, will test at his pro day",
        "Held out of drills on his agent's advice; everything comes at the pro day",
        "Tweaked a hamstring in prep and shut it down before the workout",
        "Medical rechecks only — teams flagged a foot that never showed up on tape",
        "Post-season surgery still healing; the workout waits for his pro day",
    ]

    private static let benchSkipReasons = [
        "Skipped the bench press — long arms, and his agent saw no upside in the rep count",
        "Sat out the bench with a wrist he says has bothered him since October",
    ]

    private static let agilitySkipReasons = [
        "Ran, jumped, then pulled out of the agility drills with a tight groin",
        "Skipped the cone and shuttle — will run both on his own turf at the pro day",
    ]

    /// Grades each invitee's position drills against the distribution of *his own
    /// position* in this class (percentile → letter).
    ///
    /// Calibration note (balance-harness `draftclass`): this used to rank inside
    /// the three coarse `CombinePositionGroup`s. Because the generator *solves*
    /// the position-skill average from the talent target minus the position's
    /// physical/mental contribution, positions with low physical priors end up
    /// with structurally higher position-attribute averages — so inside one
    /// coarse group the A/A+ grades all went to the same position (measured: QB
    /// 3.2 per class vs WR 1.4 and CB 1.9 in `speedster`; DT 1.1 vs DE 0.4 in
    /// `bigman`). Ranking within the position self-normalises that away.
    private static func applyPositionDrillGrades(
        _ prospects: inout [CollegeProspect],
        invited: Set<Int>,
        scoutingAbility: Int
    ) {
        var scoresByPosition: [Position: [Double]] = [:]
        var rawScores: [Int: Double] = [:]

        for i in invited where prospects[i].position != .K && prospects[i].position != .P {
            let score = noisyPositionDrillScore(for: prospects[i], scoutingAbility: scoutingAbility)
            rawScores[i] = score
            scoresByPosition[prospects[i].position, default: []].append(score)
        }

        var stats: [Position: (mean: Double, sd: Double)] = [:]
        for (position, values) in scoresByPosition {
            let mean = values.reduce(0, +) / Double(values.count)
            let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(max(1, values.count))
            stats[position] = (mean, max(3.0, variance.squareRoot()))
        }

        for (i, score) in rawScores {
            guard let stat = stats[prospects[i].position] else { continue }
            let z = (score - stat.mean) / stat.sd
            prospects[i].positionDrillGrade = drillGradeLetter(forZScore: z)
        }
    }

    /// Percentile thresholds expressed as z-scores: A+ top 3 %, A top 5 %,
    /// A- top 15 %, B+ top 25 %, B top 35 %, B- top 50 %, then the C/D tail.
    private static func drillGradeLetter(forZScore z: Double) -> String {
        switch z {
        case 1.88...:      return "A+"
        case 1.645..<1.88: return "A"
        case 1.036..<1.645: return "A-"
        case 0.674..<1.036: return "B+"
        case 0.385..<0.674: return "B"
        case 0.0..<0.385:   return "B-"
        case -0.253..<0.0:  return "C+"
        case -0.524..<(-0.253): return "C"
        case -0.842..<(-0.524): return "C-"
        case -1.175..<(-0.842): return "D+"
        case -1.555..<(-1.175): return "D"
        case -1.881..<(-1.555): return "D-"
        default:            return "F"
        }
    }

    /// Generates a position drill grade (F through A+) based on the prospect's
    /// position-specific attributes. Noise varies by position (QB/DB hardest to
    /// evaluate, OL/DL most visible) and is reduced by better scouting staff.
    private static func noisyPositionDrillScore(for prospect: CollegeProspect, scoutingAbility: Int = 50) -> Double {
        let baseAvg = prospect.truePositionAttributes.overall

        // Position-specific base noise — some positions are harder to evaluate in drills
        // QB: decision-making/reads can't be fully measured in drills
        // DB: coverage instincts hard to isolate in controlled drills
        // OL/DL: technique and power most visible in 1-on-1 drills
        let positionNoise: Double = {
            switch prospect.position {
            case .QB:                          return 16.0  // Hardest — intangibles dominate
            case .CB, .FS, .SS:                return 15.0  // Coverage instincts hard to measure
            case .WR, .TE:                     return 13.0  // Route running partially visible
            case .RB, .FB:                     return 12.0  // Vision/instincts vs measurables
            case .MLB, .OLB:                   return 11.0  // Tackling/blitzing fairly observable
            case .DE, .DT:                     return 9.0   // Pass rush moves very visible
            case .LT, .LG, .C, .RG, .RT:      return 8.0   // Technique most measurable in 1-on-1
            case .K, .P:                       return 6.0   // Accuracy directly measurable
            }
        }()

        // Scouting staff modifier: ability 1-99 maps to 1.4x (worst) down to 0.6x (best)
        // Average staff (50) = 1.0x (no change)
        let staffModifier = 1.4 - (Double(max(1, min(99, scoutingAbility))) - 1.0) / 98.0 * 0.8

        let adjustedNoise = positionNoise * staffModifier
        let noise = Double.random(in: -adjustedNoise...adjustedNoise)
        return max(20, min(99, baseAvg + noise))
    }

    /// Legacy wrapper — calls generateCombineResults(for:).
    static func simulateCombine(prospects: inout [CollegeProspect], scoutingAbility: Int = 50) {
        generateCombineResults(for: &prospects, scoutingAbility: scoutingAbility)
    }

    // MARK: - Combine Position Groups

    /// Coarse groups used for pro-day hand timing and for grading position
    /// drills relative to peers. Combine *measurables* use the per-position
    /// table below, not these groups.
    enum CombinePositionGroup: Hashable {
        case speedster  // WR, CB, FS, SS, QB — fastest 40 times
        case bigman     // OL (LT, LG, C, RG, RT), DL (DE, DT) — highest bench press, slower 40
        case balanced   // RB, FB, TE, OLB, MLB — balanced across drills
    }

    private static func positionGroup(for position: Position) -> CombinePositionGroup {
        switch position {
        case .QB, .WR, .CB, .FS, .SS:
            return .speedster
        case .LT, .LG, .C, .RG, .RT, .DE, .DT:
            return .bigman
        case .RB, .FB, .TE, .OLB, .MLB:
            return .balanced
        case .K, .P:
            return .balanced  // Won't be reached (K/P excluded above)
        }
    }

    // MARK: - Per-Position Combine Drill Table

    /// One drill's distribution for one position: `N(mean, sd)` truncated to the
    /// observed floor/ceiling. Straight out of `DRAFT_NFL_REFERENCE.md` §5.
    struct CombineDrill {
        let mean: Double
        let sd: Double
        let range: ClosedRange<Double>
        let lowerIsBetter: Bool
    }

    /// Which physical attribute a drill is correlated with, and the position
    /// prior it is measured against.
    private enum DrillAttribute {
        case speed          // 40-yard dash
        case strength       // bench press
        case explosion      // vertical jump, 3-cone (agility + acceleration)
        case power          // broad jump (strength + acceleration)
        case lateral        // shuttle (agility + speed)

        func referenceMean(for position: Position) -> Double {
            let p = PositionPhysicalProfile.profile(for: position)
            switch self {
            case .speed:     return p.speed.mean
            case .strength:  return p.strength.mean
            case .explosion: return (p.agility.mean + p.acceleration.mean) / 2
            case .power:     return (p.strength.mean + p.acceleration.mean) / 2
            case .lateral:   return (p.agility.mean + p.speed.mean) / 2
            }
        }
    }

    /// Per-position combine measurables. All six drills now have their own
    /// mean/σ per position instead of five of them sharing three coarse groups.
    enum CombineDrillTable {
        struct PositionDrills {
            let forty: CombineDrill
            let bench: CombineDrill
            let vertical: CombineDrill
            let broad: CombineDrill
            let cone: CombineDrill
            let shuttle: CombineDrill
        }

        /// Absolute bounds any human has ever posted (used to truncate the ±3σ tails).
        private static let fortyBounds = 4.18...5.55
        private static let benchBounds = 2.0...49.0
        private static let vertBounds = 19.0...46.0
        private static let broadBounds = 82.0...147.0
        private static let coneBounds = 6.28...8.45
        private static let shuttleBounds = 3.75...5.25

        private static func drill(
            _ mean: Double,
            _ sd: Double,
            lowerIsBetter: Bool,
            bounds: ClosedRange<Double>,
            sigma: Double = 3.0
        ) -> CombineDrill {
            let low = max(bounds.lowerBound, mean - sd * sigma)
            let high = min(bounds.upperBound, mean + sd * sigma)
            return CombineDrill(mean: mean, sd: sd,
                                range: low...max(low + 0.01, high),
                                lowerIsBetter: lowerIsBetter)
        }

        private static func timed(_ mean: Double, _ sd: Double, _ floor: Double, _ ceiling: Double) -> CombineDrill {
            CombineDrill(mean: mean, sd: sd, range: floor...ceiling, lowerIsBetter: true)
        }

        static func drills(for position: Position) -> PositionDrills {
            switch position {
            case .QB:
                return PositionDrills(
                    forty: timed(4.83, 0.12, 4.55, 5.10),
                    bench: drill(18, 4, lowerIsBetter: false, bounds: benchBounds),
                    vertical: drill(30.5, 3, lowerIsBetter: false, bounds: vertBounds),
                    broad: drill(112, 6, lowerIsBetter: false, bounds: broadBounds),
                    cone: drill(7.15, 0.20, lowerIsBetter: true, bounds: coneBounds),
                    shuttle: drill(4.40, 0.15, lowerIsBetter: true, bounds: shuttleBounds))
            case .RB:
                return PositionDrills(
                    forty: timed(4.52, 0.08, 4.32, 4.75),
                    bench: drill(20, 4, lowerIsBetter: false, bounds: benchBounds),
                    vertical: drill(34.5, 3, lowerIsBetter: false, bounds: vertBounds),
                    broad: drill(119, 5, lowerIsBetter: false, bounds: broadBounds),
                    cone: drill(7.05, 0.15, lowerIsBetter: true, bounds: coneBounds),
                    shuttle: drill(4.30, 0.12, lowerIsBetter: true, bounds: shuttleBounds))
            case .FB:
                return PositionDrills(
                    forty: timed(4.78, 0.10, 4.55, 5.05),
                    bench: drill(24, 4, lowerIsBetter: false, bounds: benchBounds),
                    vertical: drill(32, 3, lowerIsBetter: false, bounds: vertBounds),
                    broad: drill(112, 5, lowerIsBetter: false, bounds: broadBounds),
                    cone: drill(7.20, 0.18, lowerIsBetter: true, bounds: coneBounds),
                    shuttle: drill(4.45, 0.12, lowerIsBetter: true, bounds: shuttleBounds))
            case .WR:
                return PositionDrills(
                    forty: timed(4.49, 0.08, 4.22, 4.70),
                    bench: drill(13, 3, lowerIsBetter: false, bounds: benchBounds),
                    vertical: drill(36, 3, lowerIsBetter: false, bounds: vertBounds),
                    broad: drill(122, 5, lowerIsBetter: false, bounds: broadBounds),
                    cone: drill(6.95, 0.15, lowerIsBetter: true, bounds: coneBounds),
                    shuttle: drill(4.25, 0.12, lowerIsBetter: true, bounds: shuttleBounds))
            case .TE:
                return PositionDrills(
                    forty: timed(4.72, 0.10, 4.55, 5.00),
                    bench: drill(21, 4, lowerIsBetter: false, bounds: benchBounds),
                    vertical: drill(33, 3, lowerIsBetter: false, bounds: vertBounds),
                    broad: drill(116, 5, lowerIsBetter: false, bounds: broadBounds),
                    cone: drill(7.10, 0.15, lowerIsBetter: true, bounds: coneBounds),
                    shuttle: drill(4.40, 0.12, lowerIsBetter: true, bounds: shuttleBounds))
            case .LT, .RT:
                return PositionDrills(
                    forty: timed(5.16, 0.13, 4.85, 5.45),
                    bench: drill(24, 5, lowerIsBetter: false, bounds: benchBounds),
                    vertical: drill(27.5, 3, lowerIsBetter: false, bounds: vertBounds),
                    broad: drill(103, 6, lowerIsBetter: false, bounds: broadBounds),
                    cone: drill(7.75, 0.25, lowerIsBetter: true, bounds: coneBounds),
                    shuttle: drill(4.80, 0.15, lowerIsBetter: true, bounds: shuttleBounds))
            case .LG, .C, .RG:
                return PositionDrills(
                    forty: timed(5.22, 0.12, 4.95, 5.50),
                    bench: drill(27, 5, lowerIsBetter: false, bounds: benchBounds),
                    vertical: drill(28, 3, lowerIsBetter: false, bounds: vertBounds),
                    broad: drill(104, 6, lowerIsBetter: false, bounds: broadBounds),
                    cone: drill(7.70, 0.22, lowerIsBetter: true, bounds: coneBounds),
                    shuttle: drill(4.75, 0.15, lowerIsBetter: true, bounds: shuttleBounds))
            case .DE:
                return PositionDrills(
                    forty: timed(4.70, 0.10, 4.40, 4.95),
                    bench: drill(24, 4, lowerIsBetter: false, bounds: benchBounds),
                    vertical: drill(33.5, 3.5, lowerIsBetter: false, bounds: vertBounds),
                    broad: drill(118, 6, lowerIsBetter: false, bounds: broadBounds),
                    cone: drill(7.15, 0.20, lowerIsBetter: true, bounds: coneBounds),
                    shuttle: drill(4.45, 0.13, lowerIsBetter: true, bounds: shuttleBounds))
            case .DT:
                return PositionDrills(
                    forty: timed(5.02, 0.14, 4.70, 5.35),
                    bench: drill(29, 5, lowerIsBetter: false, bounds: benchBounds),
                    vertical: drill(29, 3.5, lowerIsBetter: false, bounds: vertBounds),
                    broad: drill(108, 7, lowerIsBetter: false, bounds: broadBounds),
                    cone: drill(7.60, 0.25, lowerIsBetter: true, bounds: coneBounds),
                    shuttle: drill(4.75, 0.15, lowerIsBetter: true, bounds: shuttleBounds))
            case .OLB, .MLB:
                return PositionDrills(
                    forty: timed(4.62, 0.09, 4.38, 4.85),
                    bench: drill(22, 4, lowerIsBetter: false, bounds: benchBounds),
                    vertical: drill(34, 3, lowerIsBetter: false, bounds: vertBounds),
                    broad: drill(119, 5, lowerIsBetter: false, bounds: broadBounds),
                    cone: drill(7.10, 0.18, lowerIsBetter: true, bounds: coneBounds),
                    shuttle: drill(4.35, 0.12, lowerIsBetter: true, bounds: shuttleBounds))
            case .CB:
                return PositionDrills(
                    forty: timed(4.47, 0.07, 4.28, 4.65),
                    bench: drill(14, 3, lowerIsBetter: false, bounds: benchBounds),
                    vertical: drill(36.5, 3, lowerIsBetter: false, bounds: vertBounds),
                    broad: drill(124, 5, lowerIsBetter: false, bounds: broadBounds),
                    cone: drill(6.90, 0.15, lowerIsBetter: true, bounds: coneBounds),
                    shuttle: drill(4.20, 0.10, lowerIsBetter: true, bounds: shuttleBounds))
            case .FS, .SS:
                return PositionDrills(
                    forty: timed(4.53, 0.08, 4.35, 4.72),
                    bench: drill(16, 3, lowerIsBetter: false, bounds: benchBounds),
                    vertical: drill(36, 3, lowerIsBetter: false, bounds: vertBounds),
                    broad: drill(122, 5, lowerIsBetter: false, bounds: broadBounds),
                    cone: drill(7.00, 0.15, lowerIsBetter: true, bounds: coneBounds),
                    shuttle: drill(4.25, 0.10, lowerIsBetter: true, bounds: shuttleBounds))
            case .K, .P:
                return PositionDrills(
                    forty: timed(4.95, 0.15, 4.60, 5.40),
                    bench: drill(15, 4, lowerIsBetter: false, bounds: benchBounds),
                    vertical: drill(28, 4, lowerIsBetter: false, bounds: vertBounds),
                    broad: drill(105, 7, lowerIsBetter: false, bounds: broadBounds),
                    cone: drill(7.40, 0.25, lowerIsBetter: true, bounds: coneBounds),
                    shuttle: drill(4.55, 0.18, lowerIsBetter: true, bounds: shuttleBounds))
            }
        }
    }

    /// Draws one drill result: `mean ± sd·(0.8·attributeZ + 0.6·noise + modifier)`.
    ///
    /// The attribute term is normalised against the position's own physical
    /// prior, so "fast for a tackle" and "fast for a corner" mean different
    /// things — corr(attribute, result) ≈ 0.8 as the reference requires. A
    /// 0.5 % freak tail pushes an extra 1.5–2.5σ past the normal draw, which is
    /// how a 4.2x receiver or a 4.4 edge rusher shows up in the headlines.
    private static func drillResult(
        _ drill: CombineDrill,
        attribute: Int,
        attributeKind: DrillAttribute,
        position: Position,
        modifier: Double
    ) -> Double {
        // Spread of a position's attribute inside a class: prior σ combined with
        // the talent-driven level shift (≈8 points).
        let attributeSpread = 8.0
        let reference = attributeKind.referenceMean(for: position)
        let z = max(-2.5, min(2.5, (Double(attribute) - reference) / attributeSpread))

        let correlation = 0.8
        let signal = correlation * z
        let noise = (1.0 - correlation * correlation).squareRoot()
            * PositionPhysicalProfile.gaussian(mean: 0, sd: 1)

        var sigmas = signal + noise + modifier * 0.5

        // 0.5 % freak tail — record-flirting results.
        if Double.random(in: 0...1) < 0.005 {
            sigmas += Double.random(in: 1.5...2.5)
        }

        let raw = drill.lowerIsBetter
            ? drill.mean - drill.sd * sigmas
            : drill.mean + drill.sd * sigmas
        return min(drill.range.upperBound, max(drill.range.lowerBound, raw))
    }

    /// Returns a modifier: positive = combine warrior (tests better), negative = bad tester.
    /// Most prospects are neutral (0). ~10% are warriors, ~10% are bad testers.
    private static func combinePersonalityModifier() -> Double {
        let roll = Int.random(in: 1...100)
        if roll <= 10 {
            return Double.random(in: 0.5...1.0)   // Combine warrior
        } else if roll >= 91 {
            return Double.random(in: -1.0...(-0.5)) // Bad tester
        } else {
            return Double.random(in: -0.2...0.2)    // Neutral
        }
    }

    // MARK: - Pro Day Simulation

    /// Simulates a pro day for a single prospect. Slightly better results than combine (home field advantage).
    ///
    /// - Parameter markAttended: whether to flip `proDayCompleted`. The LEAGUE
    ///   circuit (`runLeagueProDays`) passes `false`: every school holds its pro
    ///   day whether or not this club sends anybody, so the numbers become
    ///   public — but `proDayCompleted` is what `ProspectFog.combineFidelity`
    ///   reads to hand out full stopwatch precision, and that is something a
    ///   club buys by turning up. `attendProDay` (the paid trip) is the only
    ///   caller that sets it.
    static func simulateProDay(prospect: inout CollegeProspect, markAttended: Bool = true) {
        let phys = prospect.truePhysical
        let homefieldBoost = 0.3 // Slight positive modifier

        // Kickers and punters are measured and weighed, never timed — the same
        // rule the combine path follows. Running one through the drill table
        // would invent a 40 time for a position that has never posted one.
        guard prospect.position != .K, prospect.position != .P else {
            if markAttended { prospect.proDayCompleted = true }
            return
        }

        let baseForty = 5.5 - (Double(phys.speed) * 0.013)
        let fortyVariance = Double.random(in: -0.06...0.04) - homefieldBoost * 0.03
        let proDayForty = max(4.2, min(5.5, baseForty + fortyVariance))
        // Keep best result
        if let existing = prospect.fortyTime {
            prospect.fortyTime = min(existing, proDayForty)
        } else {
            prospect.fortyTime = proDayForty
        }

        // Quarterbacks do not bench — combine rule, pro-day rule, same rule.
        if prospect.position != .QB {
            let baseBench = Int(Double(phys.strength) * 0.35) - 5
            let benchVariance = Int.random(in: -2...4)
            let proDayBench = max(8, min(45, baseBench + benchVariance))
            if let existing = prospect.benchPress {
                prospect.benchPress = max(existing, proDayBench)
            } else {
                prospect.benchPress = proDayBench
            }
        }

        let baseVertical = 20.0 + Double(phys.acceleration + phys.agility) * 0.13
        let vertVariance = Double.random(in: -1.0...2.0)
        let proDayVert = max(24.0, min(46.0, baseVertical + vertVariance))
        if let existing = prospect.verticalJump {
            prospect.verticalJump = max(existing, proDayVert)
        } else {
            prospect.verticalJump = proDayVert
        }

        let baseBroad = 80 + Int(Double(phys.strength + phys.acceleration) * 0.3)
        let broadVariance = Int.random(in: -2...5)
        let proDayBroad = max(95, min(145, baseBroad + broadVariance))
        if let existing = prospect.broadJump {
            prospect.broadJump = max(existing, proDayBroad)
        } else {
            prospect.broadJump = proDayBroad
        }

        let baseShuttle = 4.8 - (Double(phys.agility) * 0.01)
        let shuttleVariance = Double.random(in: -0.1...0.05)
        let proDayShuttle = max(3.7, min(4.8, baseShuttle + shuttleVariance))
        if let existing = prospect.shuttleTime {
            prospect.shuttleTime = min(existing, proDayShuttle)
        } else {
            prospect.shuttleTime = proDayShuttle
        }

        let baseCone = 7.8 - (Double(phys.agility + phys.acceleration) * 0.007)
        let coneVariance = Double.random(in: -0.12...0.06)
        let proDayCone = max(6.4, min(7.6, baseCone + coneVariance))
        if let existing = prospect.coneDrill {
            prospect.coneDrill = min(existing, proDayCone)
        } else {
            prospect.coneDrill = proDayCone
        }

        if markAttended { prospect.proDayCompleted = true }
    }

    // MARK: - Interview

    /// Conducts an interview with a prospect, revealing personality traits based on scout ability.
    /// Returns interview notes as a string.
    static func conductInterview(prospect: inout CollegeProspect, scout: Scout) -> String {
        prospect.interviewCompleted = true

        let archetype = prospect.truePersonality.archetype
        let motivation = prospect.truePersonality.motivation

        var notes: [String] = []

        // Personality insight based on scout's personalityRead
        let readRoll = Int.random(in: 1...100)
        if readRoll <= scout.personalityRead {
            // Accurate read
            notes.append(accuratePersonalityNote(archetype: archetype))
            notes.append(accurateMotivationNote(motivation: motivation))
        } else if readRoll <= scout.personalityRead + 30 {
            // Partially accurate — gets one right
            if Bool.random() {
                notes.append(accuratePersonalityNote(archetype: archetype))
                notes.append("Motivation is unclear from the interview.")
            } else {
                notes.append("Personality was hard to pin down in the meeting.")
                notes.append(accurateMotivationNote(motivation: motivation))
            }
        } else {
            // Misleading read
            notes.append("Came across well in the interview but hard to get a true read.")
            notes.append("Seems like a standard prospect — nothing stood out.")
        }

        // Work ethic hint
        let workEthic = prospect.trueMental.workEthic
        if workEthic >= 80 && Int.random(in: 1...100) <= scout.personalityRead + 20 {
            notes.append("Shows excellent dedication to the craft. Film study and preparation are top-notch.")
        } else if workEthic < 50 && Int.random(in: 1...100) <= scout.personalityRead + 10 {
            notes.append("Some concerns about work habits. May need extra motivation from coaching staff.")
        }

        // Leadership hint
        let leadership = prospect.trueMental.leadership
        if leadership >= 80 && Int.random(in: 1...100) <= scout.personalityRead + 15 {
            notes.append("Natural leader. Teammates gravitate toward him.")
        }

        return notes.joined(separator: " ")
    }

    // MARK: - Enhanced Interview System

    /// Attributes an interview is entitled to reveal.
    ///
    /// A meeting is a whiteboard, a playbook install and forty minutes of
    /// questions — it reads how a man thinks, learns, competes, leads and
    /// prepares. It does NOT read decision-making under a live rush or
    /// coachability across a season; those need tape, and they stay the
    /// scouting department's job. Keys match `generateMentalGrades`.
    static let interviewRevealedMentalKeys = ["AWR", "LRN", "CMP", "LDR", "WRK"]

    /// Writes the mental grade block an interview earns onto the prospect.
    ///
    /// Before this existed an interview stored `interviewFootballIQ` and
    /// nothing else, so the Big Board's Mental tab still read "?" across the
    /// row for a prospect the user had personally sat down with — the sixty
    /// combine slots bought a sentence on one detail screen and no data.
    ///
    /// Additive and idempotent-safe: an existing band is *narrowed* through
    /// `GradeRange.incorporate` (the same progressive-confidence path a second
    /// scouting report takes), never replaced, so an interview can no more make
    /// the user certain of a wrong number than a report can.
    ///
    /// - Parameters:
    ///   - prospect: mutated in place.
    ///   - interviewerQuality: 1-99. Drives band width — a sharp interviewer
    ///     comes out of the room with a single grade, a poor one with a spread.
    static func revealMentalGradesFromInterview(
        prospect: CollegeProspect,
        interviewerQuality: Int
    ) {
        // Band half-width in grade steps: 99 quality → 0 (a single grade),
        // 50 → 1, 25 → 2. Mirrors `generateMentalGrades`' noise ladder.
        let halfWidth = Swift.max(0, 3 - Swift.max(0, interviewerQuality) / 33)
        // Observation noise: the interviewer can be wrong about the centre too.
        let noiseSteps = Swift.max(0, 3 - Swift.max(0, interviewerQuality) / 30)

        func observed(_ value: Int) -> LetterGrade {
            let truth = LetterGrade.from(numericValue: value)
            guard noiseSteps > 0 else { return truth }
            return truth.shifted(by: Int.random(in: -noiseSteps...noiseSteps))
        }

        let mental = prospect.trueMental
        let sources: [String: Int] = [
            "AWR": mental.awareness,
            "LRN": prospect.trueLearning,
            "CMP": prospect.trueCompetitiveness,
            "LDR": mental.leadership,
            "WRK": mental.workEthic
        ]

        var existing = prospect.scoutedMentalGrades ?? [:]
        for key in interviewRevealedMentalKeys {
            guard let value = sources[key] else { continue }
            let grade = observed(value)
            if var range = existing[key] {
                range.incorporate(newGrade: grade)
                existing[key] = range
            } else {
                existing[key] = GradeRange(
                    low: grade.shifted(by: -halfWidth),
                    high: grade.shifted(by: halfWidth),
                    reportCount: 1
                )
            }
        }
        prospect.scoutedMentalGrades = existing
    }

    /// Conduct an interview with a prospect at the combine. Reveals personality, footballIQ, and character notes.
    /// - Parameters:
    ///   - prospect: The prospect to interview (mutated in place).
    ///   - interviewerQuality: HC or scout playCalling/motivation attribute (1-99).
    ///   - interviewerName: Who ran the meeting, stored for the detail screen's
    ///     attribution line. Defaulted so existing call sites keep compiling.
    ///   - occasionLabel: When/where it happened ("Combine \u{00B7} 2027").
    /// - Returns: Tuple of revealed personality, footballIQ, and character notes.
    static func conductInterview(
        prospect: CollegeProspect,
        interviewerQuality: Int,
        interviewerName: String? = nil,
        occasionLabel: String? = nil
    ) -> (personality: PersonalityArchetype, footballIQ: Int, characterNotes: [String]) {
        // 1. Reveal personality with noise based on interviewer quality
        let personalityRoll = Int.random(in: 1...100)
        let revealedPersonality: PersonalityArchetype
        if personalityRoll <= interviewerQuality {
            revealedPersonality = prospect.truePersonality.archetype
        } else {
            // Misread: return a wrong archetype
            let wrong = PersonalityArchetype.allCases.filter { $0 != prospect.truePersonality.archetype }
            revealedPersonality = wrong.randomElement() ?? prospect.truePersonality.archetype
        }

        // 2. Reveal footballIQ from the two attributes that actually describe it:
        //    game IQ (`awareness`) and how fast he absorbs a playbook
        //    (`trueLearning`). The old round-based floor/ceiling made the
        //    interview a restatement of the draft projection — a projected first
        //    rounder could never interview below 70, so the room told you nothing.
        let baseIQ = 0.5 * Double(prospect.trueMental.awareness) + 0.5 * Double(prospect.trueLearning)
        let maxNoise = max(1, 20 - (interviewerQuality * 20 / 100))
        let iqNoise = Int.random(in: -maxNoise...maxNoise)
        let footballIQ = min(99, max(25, Int(baseIQ.rounded()) + iqNoise))

        // 3. Generate 1-3 character notes based on true attributes
        var characterPool: [String] = []
        let mental = prospect.trueMental
        let personality = prospect.truePersonality

        if mental.leadership >= 75 { characterPool.append("Natural leader") }
        if mental.workEthic >= 80 { characterPool.append("High character") }
        if mental.workEthic < 45 { characterPool.append("Off-field concerns") }
        if mental.coachability >= 80 { characterPool.append("Extremely coachable") }
        if mental.coachability < 40 { characterPool.append("Resistant to coaching") }
        if mental.clutch >= 80 { characterPool.append("Clutch performer") }
        if mental.clutch < 40 { characterPool.append("Folds under pressure") }
        if personality.archetype == .teamLeader { characterPool.append("Team-first mentality") }
        if personality.archetype == .dramaQueen { characterPool.append("Maturity concerns") }
        if personality.archetype == .fieryCompetitor { characterPool.append("Intense competitor") }
        if personality.archetype == .mentor { characterPool.append("Mature beyond his years") }
        if personality.archetype == .loneWolf { characterPool.append("Keeps to himself") }

        // Noise: poor interviewers may miss notes or get wrong read
        if interviewerQuality < 50 && Int.random(in: 1...100) > interviewerQuality {
            // Replace a note with a misleading one
            let misleading = ["Seemed fine", "Hard to read", "Came across as average"]
            characterPool.append(misleading.randomElement()!)
        }

        if characterPool.isEmpty {
            characterPool.append("Nothing stood out, solid character")
        }

        characterPool.shuffle()
        let noteCount = min(characterPool.count, Int.random(in: 1...3))
        let characterNotes = Array(characterPool.prefix(noteCount))

        // 4. Update prospect state. The interview is the strongest character
        //    instrument in the build, so its read always lands — and stamping
        //    the source is what stops the next routine scout report from
        //    silently re-rolling it while the card still says the user's own
        //    meeting produced it (#185).
        prospect.interviewCompleted = true
        recordPersonalityRead(revealedPersonality, source: .interview, on: prospect)
        prospect.interviewFootballIQ = footballIQ
        prospect.interviewCharacterNotes = characterNotes
        prospect.interviewNotes = characterNotes.joined(separator: ". ") + "."
        if let interviewerName { prospect.interviewedByName = interviewerName }
        if let occasionLabel { prospect.interviewedOnLabel = occasionLabel }

        // 5. The room's real payload: the mental attribute block. Without this
        // the interview wrote one hidden integer and the board learned nothing.
        revealMentalGradesFromInterview(prospect: prospect, interviewerQuality: interviewerQuality)

        return (personality: revealedPersonality, footballIQ: footballIQ, characterNotes: characterNotes)
    }

    // MARK: - Pro Day System

    /// Send a scout to a Pro Day at a college. Generates combine-like results for all prospects at that school.
    /// For combine invitees, allows improving one drill result. For non-invitees, generates hand-timed results.
    /// Also generates a scout report at `.proDay` phase for each prospect.
    static func attendProDay(
        scout: Scout,
        college: String,
        prospects: inout [CollegeProspect]
    ) {
        let collegeIndices = prospects.indices.filter { prospects[$0].college == college }
        guard !collegeIndices.isEmpty else { return }

        // Is this the scout's own beat? The regional map existed and nothing
        // outside the weekly-report loop read it, so the five regional roles
        // were five identical scouts wearing different labels the moment the
        // season ended. A pro day is the one trip where the answer should show:
        // the man who has been in that building all autumn reads the workout
        // sharper than a colleague seeing the place for the first time.
        //
        // A property of (scout, school), so it is answered once rather than per
        // prospect. False for the chief and the extras by construction — see
        // `regionByCollege`.
        let onHomeBeat = isHomeRegion(scout: scout, college: college)

        for i in collegeIndices {
            let phys = prospects[i].truePhysical
            let position = prospects[i].position

            // K/P only get height/weight — no athletic drills
            if position == .K || position == .P {
                prospects[i].proDayCompleted = true
                // Still generate a scout report
                let report = generateScoutReport(
                    scout: scout, prospect: prospects[i], phase: .proDay, onHomeBeat: onHomeBeat)
                applyReport(report: report, to: prospects[i], scout: scout)
                continue
            }

            // The branch is "does he already have numbers", not "was he invited
            // to Indianapolis". The league circuit (`runLeagueProDays`) now
            // tests every declared man, so a non-invitee arrives here with a
            // public line already on him — re-rolling it hand-timed would let a
            // club that PAID to attend post a worse time than the broadcast
            // feed did. A man with numbers improves one drill; a man without
            // (the class never covered by the circuit) gets the hand-timed set.
            if prospects[i].fortyTime != nil {
                // One drill improved — the athlete picks his best chance.
                improveOneDrill(prospect: &prospects[i], physical: phys)
            } else {
                // Untested: generate hand-timed results (±3% less accurate)
                generateHandTimedResults(prospect: &prospects[i], physical: phys, position: position)
            }

            prospects[i].proDayCompleted = true

            // Generate scout report at Pro Day phase
            let report = generateScoutReport(
                scout: scout, prospect: prospects[i], phase: .proDay, onHomeBeat: onHomeBeat)
            applyReport(report: report, to: prospects[i], scout: scout)
        }

        scout.proDaysAttended += 1
        if !scout.proDayColleges.contains(college) {
            scout.proDayColleges.append(college)
        }
    }

    // MARK: - Pro Day school list (pure)

    /// One row of the pro-day school list, precomputed.
    ///
    /// Exists because the screen used to derive every one of these numbers
    /// inside a computed property, on every SwiftUI body evaluation, with a
    /// `JSONDecoder` pass over the persisted custom board behind each single
    /// board-rank lookup (plan finding F6).
    struct ProDaySchoolSummary: Identifiable {
        let college: String
        /// Men declaring for the draft out of this school.
        let declared: Int
        /// `userMark == .elite`.
        let eliteCount: Int
        /// `userMark.isBoardPositive` — elite AND target. Elite is a subset.
        let targetedCount: Int
        /// Men at one of the club's top-5 roster needs.
        let needCount: Int
        /// Highest-graded declared man at the school, for the "your #N" line.
        let bestProspectID: UUID?
        /// Sort key: `targeted*10 + top50*5 + need*3 + declared`.
        let relevance: Int
        /// A scout has this school reserved.
        let isFocused: Bool
        let focusedScoutName: String?

        var id: String { college }
    }

    /// Builds the whole school list in ONE pass.
    ///
    /// PURE by contract: it takes a precomputed `boardRanks` map and never
    /// touches `UserDefaults`, so a caller can compute it once into `@State`
    /// instead of paying for it per row per body evaluation.
    ///
    /// - Parameters:
    ///   - prospects: the draft class (filtered internally to declared men).
    ///   - scouts: the department, read only for focus reservations.
    ///   - teamNeeds: `DraftEngine.topTeamNeeds(roster:limit:5)`.
    ///   - boardRanks: prospect ID → 1-based rank on the user's custom board.
    /// - Returns: schools sorted by `relevance`, descending, name-stable.
    static func proDaySchoolSummaries(
        prospects: [CollegeProspect],
        scouts: [Scout],
        teamNeeds: Set<Position>,
        boardRanks: [UUID: Int]
    ) -> [ProDaySchoolSummary] {
        // Focus reservations, indexed once. `proDayColleges` is the reservation
        // ledger: a school lands in it when a slot is assigned, and the tour is
        // what later turns it into an executed visit.
        var focusByCollege: [String: String] = [:]
        for scout in scouts {
            for college in scout.proDayColleges where focusByCollege[college] == nil {
                focusByCollege[college] = scout.fullName
            }
        }

        struct Accumulator {
            var declared = 0
            var elite = 0
            var targeted = 0
            var need = 0
            var top50 = 0
            var bestID: UUID?
            var bestGrade = -1
        }

        var byCollege: [String: Accumulator] = [:]
        byCollege.reserveCapacity(128)

        for prospect in prospects where prospect.isDeclaringForDraft {
            var acc = byCollege[prospect.college] ?? Accumulator()
            acc.declared += 1
            let mark = prospect.userMark
            if mark == .elite { acc.elite += 1 }
            if mark.isBoardPositive { acc.targeted += 1 }
            if teamNeeds.contains(prospect.position) { acc.need += 1 }
            if let rank = boardRanks[prospect.id], rank <= 50 { acc.top50 += 1 }
            let grade = prospect.scoutedOverall ?? 0
            if grade > acc.bestGrade {
                acc.bestGrade = grade
                acc.bestID = prospect.id
            }
            byCollege[prospect.college] = acc
        }

        return byCollege
            .map { college, acc in
                ProDaySchoolSummary(
                    college: college,
                    declared: acc.declared,
                    eliteCount: acc.elite,
                    targetedCount: acc.targeted,
                    needCount: acc.need,
                    bestProspectID: acc.bestID,
                    relevance: acc.targeted * 10 + acc.top50 * 5 + acc.need * 3 + acc.declared,
                    isFocused: focusByCollege[college] != nil,
                    focusedScoutName: focusByCollege[college]
                )
            }
            .sorted {
                $0.relevance != $1.relevance
                    ? $0.relevance > $1.relevance
                    : $0.college < $1.college
            }
    }

    /// For combine invitees at pro day: improve their weakest drill result.
    private static func improveOneDrill(prospect: inout CollegeProspect, physical: PhysicalAttributes) {
        let homefieldBoost = 0.3

        // Pick the drill where they underperformed most (or a random one)
        // We'll try to improve their worst drill relative to their athletic ability
        let drills = ["forty", "bench", "vertical", "broad", "shuttle", "cone"]
        let drill = drills.randomElement()!

        switch drill {
        case "forty":
            let baseForty = 5.5 - (Double(physical.speed) * 0.013)
            let variance = Double.random(in: -0.06...0.04) - homefieldBoost * 0.03
            let proDayForty = max(4.2, min(5.5, baseForty + variance))
            if let existing = prospect.fortyTime {
                prospect.fortyTime = min(existing, proDayForty)
            }
        case "bench":
            let baseBench = Int(Double(physical.strength) * 0.35) - 5
            let variance = Int.random(in: -1...4)
            let proDayBench = max(8, min(45, baseBench + variance))
            if let existing = prospect.benchPress {
                prospect.benchPress = max(existing, proDayBench)
            }
        case "vertical":
            let baseVert = 20.0 + Double(physical.acceleration + physical.agility) * 0.13
            let variance = Double.random(in: -0.5...2.0)
            let proDayVert = max(24.0, min(46.0, baseVert + variance))
            if let existing = prospect.verticalJump {
                prospect.verticalJump = max(existing, proDayVert)
            }
        case "broad":
            let baseBroad = 80 + Int(Double(physical.strength + physical.acceleration) * 0.3)
            let variance = Int.random(in: -1...5)
            let proDayBroad = max(95, min(145, baseBroad + variance))
            if let existing = prospect.broadJump {
                prospect.broadJump = max(existing, proDayBroad)
            }
        case "shuttle":
            let baseShuttle = 4.8 - (Double(physical.agility + physical.speed) * 0.005)
            let variance = Double.random(in: -0.08...0.04)
            let proDayShuttle = max(3.7, min(4.8, baseShuttle + variance))
            if let existing = prospect.shuttleTime {
                prospect.shuttleTime = min(existing, proDayShuttle)
            }
        case "cone":
            let baseCone = 7.8 - (Double(physical.agility + physical.acceleration) * 0.007)
            let variance = Double.random(in: -0.10...0.05)
            let proDayCone = max(6.4, min(7.6, baseCone + variance))
            if let existing = prospect.coneDrill {
                prospect.coneDrill = min(existing, proDayCone)
            }
        default: break
        }
    }

    /// For non-combine invitees at pro day: generate hand-timed results (±3% less accurate than combine).
    private static func generateHandTimedResults(
        prospect: inout CollegeProspect,
        physical: PhysicalAttributes,
        position: Position
    ) {
        let posGroup = positionGroup(for: position)
        // Hand-timed = slightly favorable (no electronic precision) but noisier
        let handTimedBias = 0.03

        // 40-yard dash (hand-timed tends to be ~0.1 sec faster)
        let fortyBase: Double = {
            let raw = 5.5 - (Double(physical.speed) * 0.013)
            switch posGroup {
            case .speedster: return raw - 0.05
            case .bigman:    return raw + 0.15
            case .balanced:  return raw
            }
        }()
        let fortyNoise = Double.random(in: -0.05...0.05)
        prospect.fortyTime = max(4.22, min(5.40, fortyBase + fortyNoise - handTimedBias))

        // Bench press
        let benchBase: Int = {
            let raw = Int(Double(physical.strength) * 0.35) - 5
            switch posGroup {
            case .bigman:    return raw + 8
            case .balanced:  return raw + 2
            case .speedster: return raw - 2
            }
        }()
        prospect.benchPress = max(8, min(45, benchBase + Int.random(in: -3...3)))

        // Vertical jump
        let vertBase = 20.0 + Double(physical.agility + physical.acceleration) * 0.13
        prospect.verticalJump = max(24.0, min(46.0, vertBase + Double.random(in: -2.0...2.0)))

        // Broad jump
        let broadBase: Int = {
            let raw = 80 + Int(Double(physical.strength + physical.acceleration) * 0.3)
            switch posGroup {
            case .speedster: return raw + 2
            case .bigman:    return raw - 4
            case .balanced:  return raw
            }
        }()
        prospect.broadJump = max(95, min(145, broadBase + Int.random(in: -4...4)))

        // 3-cone drill
        let coneBase = 7.8 - (Double(physical.agility + physical.acceleration) * 0.007)
        prospect.coneDrill = max(6.40, min(7.60, coneBase + Double.random(in: -0.10...0.10)))

        // Shuttle
        let shuttleBase: Double = {
            let raw = 4.8 - (Double(physical.agility + physical.speed) * 0.005)
            switch posGroup {
            case .speedster: return raw - 0.05
            case .bigman:    return raw + 0.10
            case .balanced:  return raw
            }
        }()
        prospect.shuttleTime = max(3.80, min(4.80, shuttleBase + Double.random(in: -0.08...0.08)))
    }

    // MARK: - Personal Workout System

    /// What one private workout actually told the building — the payload the
    /// workout modal renders.
    ///
    /// The workout used to be a `Void` call: it appended a 0.9-confidence report
    /// and the user was shown an alert that said "done". The grade band moved
    /// underneath him with no before/after, and the two most expensive things
    /// the session buys — the scheme-fit read and the personality read — were
    /// written into the report's notes where nothing surfaced them.
    struct WorkoutResult: Identifiable {
        let prospectID: UUID
        /// The prospect's **stored** overall band before the session, straight
        /// off `CollegeProspect.effectiveOverallGrade` (`nil` = nobody had filed
        /// on him).
        ///
        /// Deliberately the stored range and not the fogged one: `ProspectFog`
        /// is a UI type (`UI/Draft/Components/ProspectFog.swift`) and the engine
        /// does not reach up into the UI layer. The stored range reads a little
        /// more certain than the department actually is, which is honest for a
        /// before → after pair rendered side by side — both halves come off the
        /// same ruler, so the delta is exact — and the callers that print a band
        /// on its own already re-fog: `WorkoutReportEntry.init(filed:report:)`
        /// rebuilds a saved batch card from `ProspectFog.read`, and every board
        /// row goes through `ProspectGradeBand`.
        let gradeBefore: GradeRange?
        /// The stored band after the report landed — same ruler as
        /// ``gradeBefore``, see its note.
        let gradeAfter: GradeRange?
        /// How he fits what the coordinators run.
        let schemeFitNote: String
        /// The room's read on the man, when the staff got one (85 % of the time).
        let personalityNote: String?
        /// Position strengths and weaknesses the session surfaced.
        let impressions: [String]

        var id: UUID { prospectID }
    }

    /// Has this club already spent a private-workout slot on this man?
    ///
    /// The record of a private workout is the `.personalWorkout` report the
    /// session files — that report IS the receipt, and it is the only marker
    /// that means "worked out" and nothing else. `proDayCompleted` does NOT:
    /// `attendProDay` flips it for every declared man at a focused school, so
    /// using it as the workout gate made a pro-day tour silently delete the
    /// workout stage's whole candidate list one stage later.
    ///
    /// One line, one authority — `WorkoutsTabView`, `ProspectDetailView` and
    /// the board's work-up column all read this.
    static func hasWorkedOutPrivately(_ prospect: CollegeProspect) -> Bool {
        prospect.scoutingReports.contains { $0.phase == .personalWorkout }
    }

    /// Invite a prospect for a personal workout. Highest accuracy evaluation (confidence 0.9).
    /// Generates a scout report at `.personalWorkout` phase with scheme fit evaluation.
    ///
    /// Returns what the session found so the caller can put it in front of the
    /// user. The mutation itself must go through ``DraftClassMutator`` — the
    /// canonical class is what every other surface reads.
    ///
    /// The session files a FULL report: overall letter, potential label, all
    /// eight mental keys and the whole position block, applied through
    /// ``applyReport`` like every other instrument. It used to file only the two
    /// numeric grades and the prose notes, so the most expensive and most
    /// rationed look in the game (30 slots a cycle) left the prospect card's
    /// Mental Attributes and Position Skills grids exactly as dark as it found
    /// them — and, because it never reached `applyGradeBasedFields`, could not
    /// even narrow the overall band it reported a before → after on.
    @discardableResult
    static func conductPersonalWorkout(
        prospect: CollegeProspect,
        coaches: [Coach]
    ) -> WorkoutResult {
        // 0. The band the user was looking at when he spent the slot. Stored,
        // not fogged — see `WorkoutResult.gradeBefore`.
        let gradeBefore = prospect.effectiveOverallGrade

        // 1. Generate a high-confidence scout report
        // Use the best coaching staff member's scouting ability as the basis
        let bestScoutingAbility = coaches.map { $0.scoutingAbility }.max() ?? 50

        // The session's accuracy basis: the best eye in the building plus the
        // +15 that having the man in your own facility, on your own field, for a
        // whole day is worth. One value drives the prose notes AND the attribute
        // grades, so the card can never disagree with the paragraph beside it.
        let workoutAccuracy = min(99, bestScoutingAbility + 15)

        // Create a virtual "scout" with high accuracy for the workout evaluation
        let errorRange = max(1, Int(8.0 * (1.0 - Double(bestScoutingAbility) / 100.0)))

        let overallNoise = Int.random(in: -errorRange...errorRange)
        let scoutedOverall = min(99, max(1, prospect.trueOverall + overallNoise))

        let potentialNoise = Int.random(in: -(errorRange + 2)...(errorRange + 2))
        let scoutedPotential = min(99, max(1, prospect.truePotential + potentialNoise))

        // 2. Scheme fit evaluation based on coaches
        let schemeFitNotes = evaluateSchemeFit(prospect: prospect, coaches: coaches)

        // 3. Personality read (very accurate in personal setting). Kept as its
        // own value so the modal can print the two instruments apart; the
        // report's `personalityNotes` field still carries the merged string it
        // always did.
        let personalityRead: String? = Int.random(in: 1...100) <= 85
            ? accuratePersonalityNote(archetype: prospect.truePersonality.archetype)
            : nil
        let personalityNotes: String? = personalityRead.map { $0 + " " + schemeFitNotes } ?? schemeFitNotes

        // 4. Generate full workout report
        let strengthNotes = generatePositionStrengths(for: prospect, accuracy: workoutAccuracy)
        let weaknessNotes = generatePositionWeaknesses(for: prospect, accuracy: workoutAccuracy)

        // 4b. The attribute grades the slot actually buys, off the SAME two
        // generators every filed report uses — no bespoke workout math, so a
        // session can never grade a man on a different ruler than his tape did.
        //
        // What the generators control is where the observation LANDS, not how
        // wide the stored band is: band width is `applyGradeBasedFields`'
        // progressive-confidence ladder and is the same for every instrument.
        // So "highest fidelity" here means the best-centred observation on that
        // shared ladder, which is exactly what confidence 0.9 should buy.
        //
        // POSITION SKILLS are the session's specialty: the whole afternoon is
        // position drills run by the man's own position coach with nobody else
        // on the field. They take both narrowing steps `noiseSteps` offers — the
        // position-specialist step and the focus step — so at any staff whose
        // best eye clears ~35 the observation is dead on the true grade. Nothing
        // else in the build reads a man's hands that well.
        //
        // MENTAL is the full eight keys at plain report fidelity (specialist
        // step, no focus step): from ~60 that is still a zero-noise read, i.e.
        // no worse than the best scout in the league files. The workout IS a
        // filed report by the coaching staff and every filed report grades all
        // eight, so it writes all eight — but the extra mental step stays the
        // interview's, because a whiteboard and forty minutes of questions read
        // a man's head better than a field session does
        // (`interviewRevealedMentalKeys`).
        let mentalGrades = generateMentalGrades(
            mental: prospect.trueMental,
            learning: prospect.trueLearning,
            competitiveness: prospect.trueCompetitiveness,
            accuracy: workoutAccuracy,
            positionSpec: true
        )
        let positionGrades = generatePositionSkillGrades(
            attributes: prospect.truePositionAttributes,
            accuracy: workoutAccuracy,
            positionSpec: true,
            physicalFocus: true
        )

        let report = ScoutingReport(
            prospectID: prospect.id,
            scoutID: UUID(), // Virtual "coaching staff" report
            scoutName: "Coaching Staff",
            date: currentDateString(),
            phase: .personalWorkout,
            overallGrade: scoutedOverall,
            potentialGrade: scoutedPotential,
            strengthNotes: strengthNotes,
            weaknessNotes: weaknessNotes,
            personalityNotes: personalityNotes,
            confidenceLevel: 0.9,
            mentalGrades: mentalGrades,
            positionSkillGrades: positionGrades,
            overallLetterGrade: LetterGrade.from(numericValue: scoutedOverall),
            potentialLabel: PotentialLabel.from(
                potential: prospect.truePotential,
                noise: max(0, 3 - (workoutAccuracy / 30))
            )
        )

        // 5. Apply the report through the one writer set.
        //
        // `applyReport` appends it, re-picks the best-confidence report for the
        // legacy numeric fields, and — the half this function used to hand-roll
        // and drop — runs `applyGradeBasedFields`, which is the only thing in the
        // build that narrows `scoutedOverallGrade` and writes
        // `scoutedMentalGrades` / `scoutedPositionGrades`. Filing through it is
        // what makes the session show up on the prospect card at all.
        //
        // Personality is NOT `applyReport`'s business here: no `scout:` is
        // passed, because the filer is the coaching staff and the session ran
        // its own sharper roll (the 85 % above) before this line. #fleet review
        // F7 used to be handled by saving the read, letting `applyReport`'s
        // generic coin flip clobber it, and putting it back; #185 removed the
        // coin flip, so the restore dance is gone with it.
        applyReport(report: report, to: prospect)

        // The session's own read, filed through the one writer. A miss writes
        // nothing at all — what was on the card stays on the card (F7). A hit
        // writes the truth, unless the man has already sat across a table from
        // this staff: an interview reads character better than a field session
        // does, so `recordPersonalityRead` refuses, and the modal then says
        // nothing about character rather than printing a line the card's own
        // label would contradict.
        let personalityNoteForModal: String?
        if personalityRead != nil {
            let written = recordPersonalityRead(
                prospect.truePersonality.archetype,
                source: .workout,
                on: prospect
            )
            personalityNoteForModal = written ? personalityRead : nil
        } else {
            personalityNoteForModal = nil
        }

        prospect.proDayCompleted = true

        // 6. Hand the session back to the caller so the modal can show what the
        // slot bought instead of a "done" alert. Both bands are the STORED range
        // on the same ruler — see `WorkoutResult.gradeBefore` for why the engine
        // does not fog them here.
        let impressions = [strengthNotes, weaknessNotes]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return WorkoutResult(
            prospectID: prospect.id,
            gradeBefore: gradeBefore,
            gradeAfter: prospect.effectiveOverallGrade,
            schemeFitNote: schemeFitNotes,
            personalityNote: personalityNoteForModal,
            impressions: impressions
        )
    }

    /// Evaluate how well a prospect fits the team's schemes based on coaching staff.
    private static func evaluateSchemeFit(prospect: CollegeProspect, coaches: [Coach]) -> String {
        var fitNotes: [String] = []

        // Find the OC and DC for scheme references
        let oc = coaches.first { $0.role == .offensiveCoordinator }
        let dc = coaches.first { $0.role == .defensiveCoordinator }

        let isOffense = [Position.QB, .RB, .FB, .WR, .TE, .LT, .LG, .C, .RG, .RT].contains(prospect.position)

        if isOffense, let scheme = oc?.offensiveScheme {
            switch prospect.truePositionAttributes {
            case .quarterback(let qb):
                if scheme == .westCoast && qb.accuracyShort >= 75 {
                    fitNotes.append("Accuracy profile fits the West Coast scheme well")
                } else if scheme == .airRaid && qb.accuracyDeep >= 70 {
                    fitNotes.append("Deep ball ability suits the Air Raid system")
                } else if (scheme == .spread || scheme == .option || scheme == .rpo) && qb.scrambling >= 70 {
                    fitNotes.append("Mobility is ideal for the spread/option scheme")
                }
            case .runningBack(let rb):
                if scheme == .powerRun && rb.breakTackle >= 70 {
                    fitNotes.append("Physical runner, great fit for power run game")
                } else if (scheme == .spread || scheme == .rpo) && rb.elusiveness >= 70 {
                    fitNotes.append("Elusiveness works well in zone-read concepts")
                }
            case .wideReceiver(let wr):
                if scheme == .westCoast && wr.routeRunning >= 70 {
                    fitNotes.append("Route precision fits the West Coast timing game")
                } else if scheme == .airRaid && wr.catching >= 70 {
                    fitNotes.append("Reliable hands suit the high-volume passing attack")
                }
            default: break
            }
        } else if !isOffense, let scheme = dc?.defensiveScheme {
            switch prospect.truePositionAttributes {
            case .defensiveLine(let dl):
                if scheme == .base34 && dl.passRush >= 70 {
                    fitNotes.append("Pass rush ability fits the 3-4 front well")
                } else if scheme == .base43 && dl.blockShedding >= 70 {
                    fitNotes.append("Block shedding suits the 4-3 scheme")
                }
            case .linebacker(let lb):
                if scheme == .base34 && lb.blitzing >= 70 {
                    fitNotes.append("Blitzing ability ideal for 3-4 OLB role")
                } else if scheme == .base43 && lb.zoneCoverage >= 70 {
                    fitNotes.append("Zone coverage skills fit the 4-3 scheme well")
                }
            case .defensiveBack(let db):
                if scheme == .tampa2 && db.zoneCoverage >= 70 {
                    fitNotes.append("Zone instincts are perfect for Tampa 2")
                } else if scheme == .cover3 && db.manCoverage >= 70 {
                    fitNotes.append("Man coverage ability fits the Cover 3 scheme")
                } else if scheme == .pressMan && db.press >= 70 {
                    fitNotes.append("Press technique is ideal for the press man scheme")
                }
            default: break
            }
        }

        if fitNotes.isEmpty {
            fitNotes.append("Scheme fit is average. Versatile enough to contribute.")
        }

        return fitNotes.joined(separator: ". ") + "."
    }

    // MARK: - Scout Development

    /// Develops a scout over the offseason. Accuracy and reads improve with experience.
    static func developScout(_ scout: Scout) {
        scout.experience += 1

        // Early career scouts improve faster
        let improvementChance: Int
        if scout.experience <= 5 {
            improvementChance = 70
        } else if scout.experience <= 10 {
            improvementChance = 45
        } else {
            improvementChance = 20
        }

        if Int.random(in: 1...100) <= improvementChance {
            scout.accuracy = min(99, scout.accuracy + Int.random(in: 1...2))
        }
        if Int.random(in: 1...100) <= improvementChance {
            scout.personalityRead = min(99, scout.personalityRead + Int.random(in: 1...2))
        }
        if Int.random(in: 1...100) <= improvementChance {
            scout.potentialRead = min(99, scout.potentialRead + Int.random(in: 1...2))
        }
    }

    // MARK: - Note Generation Helpers

    private static func generateStrengthNotes(for prospect: CollegeProspect, accuracy: Int) -> String {
        var strengths: [String] = []
        let phys = prospect.truePhysical
        let mental = prospect.trueMental

        // Only mention strengths the scout can actually detect (accuracy-gated)
        let threshold = max(70, 95 - accuracy / 2) // Higher accuracy = notices lower-rated strengths

        if phys.speed >= threshold { strengths.append("Excellent speed") }
        if phys.acceleration >= threshold { strengths.append("Explosive first step") }
        if phys.strength >= threshold { strengths.append("Strong at the point of attack") }
        if phys.agility >= threshold { strengths.append("Very agile, changes direction well") }
        if phys.stamina >= threshold { strengths.append("High motor, plays all four quarters") }
        if phys.durability >= threshold { strengths.append("Durable, rarely misses time") }
        if mental.awareness >= threshold { strengths.append("High football IQ") }
        if mental.decisionMaking >= threshold { strengths.append("Makes good decisions under pressure") }
        if mental.clutch >= threshold { strengths.append("Performs well in big moments") }

        if strengths.isEmpty {
            strengths.append("Solid overall athlete with room to grow")
        }

        return strengths.joined(separator: ". ") + "."
    }

    private static func generateWeaknessNotes(for prospect: CollegeProspect, accuracy: Int) -> String {
        var weaknesses: [String] = []
        let phys = prospect.truePhysical
        let mental = prospect.trueMental

        let threshold = min(55, 40 + accuracy / 3) // Higher accuracy = catches higher-rated weaknesses

        if phys.speed <= threshold { weaknesses.append("Limited top-end speed") }
        if phys.acceleration <= threshold { weaknesses.append("Slow off the line") }
        if phys.strength <= threshold { weaknesses.append("Needs to add strength") }
        if phys.agility <= threshold { weaknesses.append("Stiff in the hips") }
        if phys.stamina <= threshold { weaknesses.append("Fades late in games") }
        if phys.durability <= threshold { weaknesses.append("Injury concerns") }
        if mental.awareness <= threshold { weaknesses.append("Can get lost on the field") }
        if mental.decisionMaking <= threshold { weaknesses.append("Questionable decision-making") }
        if mental.workEthic <= threshold { weaknesses.append("Work ethic is a concern") }

        if weaknesses.isEmpty {
            weaknesses.append("No major red flags at this time")
        }

        return weaknesses.joined(separator: ". ") + "."
    }

    private static func generatePersonalityNotes(for prospect: CollegeProspect, scout: Scout) -> String? {
        guard Int.random(in: 1...100) <= scout.personalityRead else { return nil }

        let archetype = prospect.truePersonality.archetype
        switch archetype {
        case .teamLeader:
            return "True team-first mentality. Well-respected in the locker room."
        case .loneWolf:
            return "Keeps to himself. Not a problem but won't be a vocal leader."
        case .feelPlayer:
            return "Performance can be streaky. When he's on, he's dominant."
        case .steadyPerformer:
            return "Consistent week to week. You know what you're getting."
        case .dramaQueen:
            return "Some character concerns. Has had issues with coaches in the past."
        case .quietProfessional:
            return "Low maintenance. Shows up, does his job, goes home."
        case .mentor:
            return "Great with younger players. Could be a locker room asset."
        case .fieryCompetitor:
            return "Intense competitor. Plays with an edge but occasionally crosses the line."
        case .classClown:
            return "Fun personality, keeps things light. Needs to know when to be serious."
        }
    }

    private static func accuratePersonalityNote(archetype: PersonalityArchetype) -> String {
        switch archetype {
        case .teamLeader:
            return "Clearly a leader — commands respect from his peers."
        case .loneWolf:
            return "Independent personality. Prefers to do his own thing."
        case .feelPlayer:
            return "Emotional player — highs are very high, lows can be low."
        case .steadyPerformer:
            return "Even-keeled demeanor. Very consistent personality."
        case .dramaQueen:
            return "High-maintenance personality. Will need careful management."
        case .quietProfessional:
            return "Quiet and focused. All business."
        case .mentor:
            return "Mature beyond his years. Natural teacher."
        case .fieryCompetitor:
            return "Extremely competitive. Hates losing more than he loves winning."
        case .classClown:
            return "Lighthearted and charismatic. Keeps the room loose."
        }
    }

    private static func accurateMotivationNote(motivation: Motivation) -> String {
        switch motivation {
        case .money:
            return "Clearly motivated by the financial opportunity."
        case .winning:
            return "Wants to win above all else. Will prioritize contenders."
        case .stats:
            return "Very aware of his numbers. Wants opportunities to produce."
        case .loyalty:
            return "Values loyalty and long-term commitment from an organization."
        case .fame:
            return "Drawn to the spotlight. Wants to be a star."
        }
    }

    private static func currentDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    // MARK: - Mock Draft Generation

    /// A single entry in a mock draft projection.
    struct MockDraftPick {
        let pickNumber: Int
        let round: Int
        let prospectID: UUID
        let teamAbbreviation: String
        let teamID: UUID
        /// Top positional needs for the team at the time of the pick.
        let teamNeeds: [Position]
        /// Why this pick was made: "BPA at position of need", "Best Player Available", etc.
        let pickRationale: String
        /// Media comment: "Perfect fit", "Surprise pick", "Steal of the draft", etc.
        let mediaComment: String
    }

    /// Generate a mock draft projection for rounds 1-3 (up to 96+ picks).
    ///
    /// Called at: midseason (week 9), entering combine phase, entering draft phase.
    /// The mock simulates which prospect each team would take based on roster needs,
    /// with +-3-5 pick variance to represent media imperfection.
    /// Applies positional draft value so P/K/FB never appear in round 1.
    /// Enforces position diversity: max 1 per position in top 5, max 2 in top 10 (QB exempted up to 2 in top 5).
    ///
    /// - Parameters:
    ///   - prospects: All available college prospects.
    ///   - draftPicks: Current draft pick assignments (used for team order). If empty, uses team order by wins (worst first).
    ///   - teams: All 32 teams.
    ///   - players: All current NFL players (used to evaluate team needs).
    /// - Returns: Array of mock pick assignments for rounds 1-3.
    static func generateMockDraft(
        prospects: [CollegeProspect],
        draftPicks: [DraftPick],
        teams: [Team],
        players: [Player]
    ) -> [MockDraftPick] {
        guard !prospects.isEmpty, !teams.isEmpty else { return [] }

        let teamLookup = Dictionary(uniqueKeysWithValues: teams.map { ($0.id, $0) })

        // Build team pick order for rounds 1-3.
        let teamOrder: [(pickNumber: Int, round: Int, teamID: UUID, abbreviation: String)]

        if !draftPicks.isEmpty {
            let roundPicks = draftPicks
                .filter { $0.round >= 1 && $0.round <= 3 }
                .sorted { $0.pickNumber < $1.pickNumber }
            teamOrder = roundPicks.compactMap { pick in
                guard let team = teamLookup[pick.currentTeamID] else { return nil }
                return (pickNumber: pick.pickNumber, round: pick.round, teamID: team.id, abbreviation: team.abbreviation)
            }
        } else {
            // Pre-draft: order by worst record first, generate 3 rounds
            let sorted = teams.sorted { ($0.wins - $0.losses) < ($1.wins - $1.losses) }
            var order: [(pickNumber: Int, round: Int, teamID: UUID, abbreviation: String)] = []
            for round in 1...3 {
                let roundTeams = round % 2 == 1 ? sorted : sorted.reversed()
                for (index, team) in roundTeams.prefix(32).enumerated() {
                    let pickNum = (round - 1) * 32 + index + 1
                    order.append((pickNumber: pickNum, round: round, teamID: team.id, abbreviation: team.abbreviation))
                }
            }
            teamOrder = order
        }

        guard !teamOrder.isEmpty else { return [] }

        // Pre-compute team needs
        let playersByTeam = Dictionary(grouping: players) { $0.teamID ?? UUID() }
        var teamNeeds: [UUID: [Position: Double]] = [:]
        for team in teams {
            let roster = playersByTeam[team.id] ?? []
            teamNeeds[team.id] = evaluateTeamNeedsForMock(roster: roster)
        }

        // Consensus board order. Positional value is already baked into the
        // class blueprint (a position's talent is decided by the board slots it
        // is allocated), so a second positional multiplier here would double-count
        // it and re-create the "every QB above every RB" sort.
        //
        // Task #78: the sort key is `consensusOverall`, not `trueOverall`. A mock
        // draft is the MEDIA's board — the same public board `draftProjection`
        // was slotted from — so a man the consensus is 12 points high on goes
        // top-10 in every mock all spring and busts on draft night, and the one
        // it is 12 points low on falls to day 3 for whoever scouted him
        // properly. Reading the true rating here made the mock omniscient and
        // silently re-created the perfect market the projection no longer is.
        let sortedProspects = prospects
            .filter { $0.isDeclaringForDraft }
            .sorted { lhs, rhs in
                if lhs.consensusOverall != rhs.consensusOverall {
                    return lhs.consensusOverall > rhs.consensusOverall
                }
                return (lhs.draftProjection ?? 8) < (rhs.draftProjection ?? 8)
            }

        var takenIDs = Set<UUID>()
        var mockPicks: [MockDraftPick] = []
        // Track position counts for diversity enforcement in top 10
        var positionCountsTop5: [Position: Int] = [:]
        var positionCountsTop10: [Position: Int] = [:]

        for entry in teamOrder {
            let needs = teamNeeds[entry.teamID] ?? [:]
            let topNeeds = needs.sorted { $0.value > $1.value }.prefix(3).map { $0.key }
            let available = sortedProspects.filter { !takenIDs.contains($0.id) }
            guard !available.isEmpty else { break }

            // Score each available prospect
            let scored = available.prefix(80).compactMap { prospect -> (CollegeProspect, Double, String, String)? in
                // Fogged, like the sort above: the mock scores the man the
                // consensus thinks it is looking at (task #78).
                var score = Double(prospect.consensusOverall)

                // Positional need boost
                let needMultiplier = needs[prospect.position] ?? 1.0
                score *= needMultiplier

                // QB premium
                if prospect.position == .QB && (needs[.QB] ?? 1.0) > 1.2 {
                    score *= 1.15
                }

                // Potential factor
                score += Double(prospect.consensusPotential) * 0.15

                // Media noise: +-3-5 points of variance (media isn't perfect)
                let noise = Double.random(in: -5.0...5.0)
                score += noise

                // Position diversity enforcement for round 1
                if entry.round == 1 {
                    let pickNum = entry.pickNumber
                    // Top 5: max 1 per position (QB can have 2)
                    if pickNum <= 5 {
                        let currentCount = positionCountsTop5[prospect.position] ?? 0
                        let maxAllowed = prospect.position == .QB ? 2 : 1
                        if currentCount >= maxAllowed {
                            return nil // skip this prospect
                        }
                    }
                    // Top 10: max 2 per position
                    if pickNum <= 10 {
                        let currentCount = positionCountsTop10[prospect.position] ?? 0
                        if currentCount >= 2 {
                            return nil // skip this prospect
                        }
                    }
                }

                // Determine rationale
                let isNeedPosition = topNeeds.contains(prospect.position)
                let rationale: String
                if isNeedPosition && needMultiplier > 1.15 {
                    rationale = "BPA at position of need"
                } else if isNeedPosition {
                    rationale = "Addresses team need"
                } else {
                    rationale = "Best Player Available"
                }

                return (prospect, score, rationale, "")
            }

            if let best = scored.max(by: { $0.1 < $1.1 }) {
                takenIDs.insert(best.0.id)

                // Update position diversity trackers
                if entry.round == 1 {
                    if entry.pickNumber <= 5 {
                        positionCountsTop5[best.0.position, default: 0] += 1
                    }
                    if entry.pickNumber <= 10 {
                        positionCountsTop10[best.0.position, default: 0] += 1
                    }
                }

                // Generate media comment based on pick position vs projected round
                let projectedRound = best.0.draftProjection ?? entry.round
                let mediaComment: String
                if entry.round == 1 && projectedRound >= 3 {
                    mediaComment = "Reaches for need"
                } else if entry.round >= 2 && projectedRound == 1 {
                    mediaComment = "Steal of the draft"
                } else if entry.round == 1 && projectedRound == 1 {
                    let isNeed = topNeeds.contains(best.0.position)
                    if isNeed {
                        mediaComment = "Perfect fit"
                    } else {
                        mediaComment = "Best player available"
                    }
                } else if entry.pickNumber <= 10 && projectedRound >= 2 {
                    mediaComment = "Surprise pick"
                } else {
                    mediaComment = ""
                }

                mockPicks.append(MockDraftPick(
                    pickNumber: entry.pickNumber,
                    round: entry.round,
                    prospectID: best.0.id,
                    teamAbbreviation: entry.abbreviation,
                    teamID: entry.teamID,
                    teamNeeds: topNeeds,
                    pickRationale: best.2,
                    mediaComment: mediaComment
                ))
            }
        }

        return mockPicks
    }

    /// Updates team interest on all prospects based on positional need matching.
    ///
    /// Each team's top 2-3 positional needs are identified, and prospects at those
    /// positions receive that team's ID in their `teamInterest` array.
    ///
    /// PUBLIC INFORMATION ONLY (task #78). The pass used to carry a second
    /// branch — `else if prospects[i].trueOverall >= 74` — which meant a club
    /// showed interest in a man because of his HIDDEN rating. Two things were
    /// wrong with it: the row the user reads ("Hot / Warm / Cold") was a direct
    /// tell for a number the fog spends the whole draft cycle hiding, and it
    /// made interest immune to the market — a prospect the consensus had badly
    /// wrong still drew 32 phone calls, because the branch was reading past the
    /// consensus to the truth underneath it. Interest is now exactly what a
    /// projected round and a stated need imply, which is what it claims to be.
    ///
    /// Writes are diffed rather than wiped: the old pass cleared all ~350 rows
    /// and re-appended, so every call dirtied the whole class in SwiftData even
    /// when nothing changed (finding S8). Only rows whose interest list actually
    /// moves are assigned now.
    static func updateTeamInterest(
        prospects: inout [CollegeProspect],
        teams: [Team],
        players: [Player]
    ) {
        let playersByTeam = Dictionary(grouping: players) { $0.teamID ?? UUID() }

        var rebuilt = [[UUID]](repeating: [], count: prospects.count)

        for team in teams {
            let roster = playersByTeam[team.id] ?? []
            let needs = evaluateTeamNeedsForMock(roster: roster)

            // Get top 3 need positions (highest multiplier)
            let topNeeds = needs
                .sorted { $0.value > $1.value }
                .prefix(3)
                .map { $0.key }

            // Add this team's interest to matching prospects — the men the
            // MEDIA has inside the top three rounds, nothing else.
            for i in prospects.indices where topNeeds.contains(prospects[i].position) {
                guard prospects[i].isDeclaringForDraft else { continue }
                if let proj = prospects[i].draftProjection, proj <= 3 {
                    rebuilt[i].append(team.id)
                }
            }
        }

        for i in prospects.indices where prospects[i].teamInterest != rebuilt[i] {
            prospects[i].teamInterest = rebuilt[i]
        }
    }

    /// Updates prospect mock draft annotations from mock draft results.
    static func applyMockDraftToProspects(
        prospects: inout [CollegeProspect],
        mockDraft: [MockDraftPick]
    ) {
        // Clear previous mock annotations
        for i in prospects.indices {
            prospects[i].mockDraftPickNumber = nil
            prospects[i].mockDraftTeam = nil
        }

        // Apply new mock draft data
        for pick in mockDraft {
            if let idx = prospects.firstIndex(where: { $0.id == pick.prospectID }) {
                prospects[idx].mockDraftPickNumber = pick.pickNumber
                prospects[idx].mockDraftTeam = pick.teamAbbreviation
            }
        }
    }

    /// Evaluates which positions a team needs most (mirrors DraftEngine logic).
    private static func evaluateTeamNeedsForMock(roster: [Player]) -> [Position: Double] {
        let idealCounts: [Position: Int] = [
            .QB: 2, .RB: 3, .FB: 1, .WR: 5, .TE: 3,
            .LT: 2, .LG: 2, .C: 2, .RG: 2, .RT: 2,
            .DE: 4, .DT: 3, .OLB: 4, .MLB: 2,
            .CB: 5, .FS: 2, .SS: 2,
            .K: 1, .P: 1
        ]

        var currentCounts: [Position: Int] = [:]
        for player in roster {
            currentCounts[player.position, default: 0] += 1
        }

        var positionOveralls: [Position: [Int]] = [:]
        for player in roster {
            positionOveralls[player.position, default: []].append(player.overall)
        }

        var needs: [Position: Double] = [:]
        for position in Position.allCases {
            let ideal = idealCounts[position] ?? 1
            let current = currentCounts[position] ?? 0
            let deficit = max(0, ideal - current)

            var multiplier = 1.0 + Double(deficit) * 0.15

            if let overalls = positionOveralls[position], !overalls.isEmpty {
                let avgOverall = Double(overalls.reduce(0, +)) / Double(overalls.count)
                if avgOverall < 60.0 {
                    multiplier += 0.2
                } else if avgOverall < 70.0 {
                    multiplier += 0.1
                }
            } else {
                multiplier += 0.3
            }

            needs[position] = multiplier
        }

        return needs
    }

    // MARK: - Regional College Mapping

    /// Maps scout roles to the colleges in their scouting region.
    private static func colleges(forRegion role: ScoutRole) -> [String] {
        switch role {
        case .regionalScout1: // East — ACC / Big East
            return ["Clemson", "Miami", "Florida State", "Virginia Tech",
                    "Boston College", "Wake Forest", "Duke", "Pittsburgh", "Notre Dame"]
        case .regionalScout2: // West — Pac-12 / Mountain West
            return ["USC", "Oregon", "Washington", "UCLA", "Stanford",
                    "Arizona State", "Colorado", "Utah"]
        case .regionalScout3: // South — SEC / Sun Belt
            return ["Alabama", "Georgia", "LSU", "Florida", "Tennessee",
                    "Auburn", "Ole Miss", "Arkansas", "Kentucky", "Texas A&M"]
        case .regionalScout4: // North — Big Ten / MAC
            return ["Ohio State", "Michigan", "Penn State", "Wisconsin",
                    "Michigan State", "Iowa", "Minnesota", "Illinois"]
        case .regionalScout5: // Central — Big 12 / AAC
            return ["Oklahoma", "Texas", "Baylor", "TCU", "North Carolina"]
        case .chiefScout, .extraScout1, .extraScout2:
            return colleges // Chief Scout and extra scouts can evaluate any prospect
        }
    }

    /// The beat name the pro-day screen prints — "East", "South".
    ///
    /// Lives next to the table above so the label and the school list cannot
    /// drift apart. `ScoutRole.displayName` spells the same thing "Regional
    /// Scout (East)", which is a job title, not a place.
    static func regionName(_ role: ScoutRole) -> String? {
        switch role {
        case .regionalScout1: return "East"
        case .regionalScout2: return "West"
        case .regionalScout3: return "South"
        case .regionalScout4: return "North"
        case .regionalScout5: return "Central"
        case .chiefScout, .extraScout1, .extraScout2: return nil
        }
    }

    /// School → the regional scout whose beat it is on.
    ///
    /// Derived from `colleges(forRegion:)`, so there is one region table in the
    /// app and this is a view of it, not a second copy.
    ///
    /// **The chief and the two extra scouts are deliberately absent.** Their
    /// entry in that table is the whole college list, which is a REACH rule
    /// ("may evaluate any prospect"), not a familiarity one. Reading it as
    /// familiarity would make the chief a local at all 40 schools — he would
    /// collect the bonus below everywhere while the five men who actually work a
    /// beat could never out-read him on their own ground, which is the opposite
    /// of what a beat is for.
    private static let regionByCollege: [String: ScoutRole] = {
        let beats: [ScoutRole] = [
            .regionalScout1, .regionalScout2, .regionalScout3,
            .regionalScout4, .regionalScout5,
        ]
        var map: [String: ScoutRole] = [:]
        for role in beats {
            for college in colleges(forRegion: role) where map[college] == nil {
                map[college] = role
            }
        }
        return map
    }()

    /// Whose beat a school sits on, or `nil` when no region owns it.
    static func homeRegion(for college: String) -> ScoutRole? {
        regionByCollege[college]
    }

    /// Whether this scout is on his own ground at this school.
    static func isHomeRegion(scout: Scout, college: String) -> Bool {
        guard let owner = regionByCollege[college] else { return false }
        return scout.scoutRole == owner
    }

    /// What working his own beat is worth to a scout, in accuracy points.
    ///
    /// Deliberately the SAME +5, through the same channel, as the tenure
    /// familiarity bonus `reportPrecision` already applies for
    /// `seasonsInRole >= 2`: both say "he knows this ground", so pricing them
    /// differently would need a reason neither the design nor the code has. It
    /// is also exactly half the +10 `generateWeeklyReports` pays the chief for
    /// running the department, which is the right ordering — knowing the campus
    /// is worth less than being the best evaluator in the building.
    ///
    /// In error terms +5 accuracy is at most ONE point off the ± band, and over
    /// the accuracy draw `CoachingEngine.generateScoutCandidates` actually
    /// produces for a regional scout (experience 1–15 → 25…85) it averages
    /// 0.73 of a point against a mean band of 6.9 — a 10.7 % narrowing, and
    /// nothing at all above accuracy 87 where `max(2, …)` has already floored.
    /// A nudge, matching the pro day's standing as the CHEAP half of the
    /// circuit (`runLeagueProDays`).
    static let homeBeatAccuracyBonus = 5

    // MARK: - Weekly Scout Reports (In-Season)

    /// Generate weekly scout reports during regular season.
    /// Each scout evaluates 3-5 prospects per week from their assigned region.
    /// Earlier weeks have more uncertainty; later weeks provide better data.
    static func generateWeeklyReports(
        scouts: [Scout],
        prospects: [CollegeProspect],
        week: Int
    ) -> [ScoutingReport] {
        guard !scouts.isEmpty, !prospects.isEmpty else { return [] }

        var reports: [ScoutingReport] = []

        // R27: consensus board built from public knowledge only (current scouted
        // overalls + media draft projection) — never from hidden true ratings.
        // Used to resolve "Top 50 / Top 150" watch assignments.
        let consensusBoard = prospects.sorted { a, b in
            let aOvr = a.scoutedOverall ?? -1
            let bOvr = b.scoutedOverall ?? -1
            if aOvr != bOvr { return aOvr > bOvr }
            return (a.draftProjection ?? 8) < (b.draftProjection ?? 8)
        }

        for scout in scouts {
            let regionalColleges = colleges(forRegion: scout.scoutRole)
            let regionalProspects = prospects.filter { regionalColleges.contains($0.college) }

            guard !regionalProspects.isEmpty else { continue }

            // R27: narrow the weekly visit pool by the scout's assignments.
            // Watch pool (top-50/top-150 of the consensus board) first, then
            // focus position. Always fall back to the region if a filter
            // would empty the pool.
            var visitPool = regionalProspects
            if let pool = scout.assignmentPool {
                let watchIDs = Set(consensusBoard.prefix(pool.boardSize).map(\.id))
                let watched = visitPool.filter { watchIDs.contains($0.id) }
                if !watched.isEmpty { visitPool = watched }
            }
            if let focusPos = scout.focusPosition {
                let focused = visitPool.filter { $0.position == focusPos }
                if !focused.isEmpty { visitPool = focused }
            }
            let isTargeted = scout.assignmentPool != nil || scout.focusPosition != nil

            // Each scout evaluates 3-5 prospects per week; a targeted scout
            // covers a narrower pool and gets one extra visit in (4-6).
            let evaluationCount = isTargeted ? Int.random(in: 4...6) : Int.random(in: 3...5)
            let shuffled = visitPool.shuffled()
            let toEvaluate = Array(shuffled.prefix(evaluationCount))

            for prospect in toEvaluate {
                // Chief Scout gets +10% accuracy bonus
                let chiefBonus = scout.scoutRole.isChief ? 10 : 0
                // Familiarity bonus: scouts with 2+ seasons in role know their region better
                let familiarityBonus = scout.seasonsInRole >= 2 ? 5 : 0
                var effectiveAccuracy = min(99, scout.accuracy + chiefBonus + familiarityBonus)

                // Position specialization bonus
                if let spec = scout.positionSpecialization, spec == prospect.position {
                    effectiveAccuracy = min(99, effectiveAccuracy + 10)
                }

                // R27: focus assignment bonuses — a scout dialed into a position
                // reads it sharper; a watch-pool assignment means deeper film work.
                if let focusPos = scout.focusPosition, focusPos == prospect.position {
                    effectiveAccuracy = min(99, effectiveAccuracy + 10)
                }
                if scout.assignmentPool != nil {
                    effectiveAccuracy = min(99, effectiveAccuracy + 5)
                }

                // Earlier weeks = more uncertainty, later weeks = better data
                // Week 1: -15 accuracy, Week 18: +5 accuracy (linear ramp)
                let weekModifier = Int(Double(week - 1) / 17.0 * 20.0) - 15
                effectiveAccuracy = min(99, max(10, effectiveAccuracy + weekModifier))

                // Base confidence is collegeSeason level (0.4), improved by week progression
                let weekConfidenceBoost = Double(week) / 18.0 * 0.15
                let baseConfidence = 0.4 + weekConfidenceBoost
                let experienceBonus = min(0.1, Double(scout.experience) * 0.01)
                let confidence = min(0.7, baseConfidence + experienceBonus)

                // Calculate scouted overall with error margin
                let maxError = max(1, 30 - (effectiveAccuracy * 30 / 100))
                let overallError = Int.random(in: -maxError...maxError)
                let scoutedOvr = min(99, max(1, prospect.trueOverall + overallError))

                // Calculate scouted potential
                let potentialMaxError = max(1, 30 - (scout.potentialRead * 30 / 100))
                let potentialError = Int.random(in: -potentialMaxError...potentialMaxError)
                let scoutedPot = min(99, max(1, prospect.truePotential + potentialError))

                // Generate college production notes
                let productionNotes = generateProductionNotes(for: prospect, week: week)

                let strengthNotes = generateStrengthNotes(for: prospect, accuracy: effectiveAccuracy)
                let weaknessNotes = generateWeaknessNotes(for: prospect, accuracy: effectiveAccuracy)
                let personalityNotes = generatePersonalityNotes(for: prospect, scout: scout)

                let report = ScoutingReport(
                    prospectID: prospect.id,
                    scoutID: scout.id,
                    scoutName: scout.fullName,
                    date: "Week \(week)",
                    phase: .collegeSeason,
                    overallGrade: scoutedOvr,
                    potentialGrade: scoutedPot,
                    strengthNotes: strengthNotes,
                    weaknessNotes: weaknessNotes,
                    personalityNotes: personalityNotes,
                    confidenceLevel: confidence,
                    productionNotes: productionNotes
                )
                reports.append(report)
            }
        }

        return reports
    }

    /// Apply weekly scout reports: append to prospect's report list and update scouted values
    /// using the best (highest confidence) report available.
    static func applyWeeklyReports(_ reports: [ScoutingReport], to prospects: inout [CollegeProspect]) {
        let reportsByProspect = Dictionary(grouping: reports, by: { $0.prospectID })

        for i in prospects.indices {
            guard let newReports = reportsByProspect[prospects[i].id] else { continue }

            // Append reports
            prospects[i].scoutingReports.append(contentsOf: newReports)

            // Find the best report (highest confidence) across ALL reports for this prospect
            guard let bestReport = prospects[i].scoutingReports.max(by: {
                $0.confidenceLevel < $1.confidenceLevel
            }) else { continue }

            // Update scouted values from the best report
            prospects[i].scoutedOverall = bestReport.overallGrade
            prospects[i].scoutedPotential = bestReport.potentialGrade

            // Set scout grade based on best scouted overall
            prospects[i].scoutGrade = LetterGrade.from(numericValue: bestReport.overallGrade).rawValue
        }
    }

    /// Generate college production notes based on position and week progression.
    private static func generateProductionNotes(for prospect: CollegeProspect, week: Int) -> String {
        let gamesPlayed = min(week, 12) // College season ~12 games
        let overall = prospect.trueOverall

        switch prospect.position {
        case .QB:
            let tdsPerGame = Double(overall) / 30.0
            let totalTDs = Int(tdsPerGame * Double(gamesPlayed))
            let totalINTs = Int(Double(gamesPlayed) * (1.0 - Double(overall) / 120.0))
            let yards = Int(Double(gamesPlayed) * Double(overall) * 2.8)
            return "\(totalTDs) TDs, \(totalINTs) INTs, \(yards) yards in \(gamesPlayed) games"
        case .RB, .FB:
            let yardsPerGame = Double(overall) * 0.9
            let totalYards = Int(yardsPerGame * Double(gamesPlayed))
            let tds = Int(Double(overall) / 12.0 * Double(gamesPlayed) / 4.0)
            return "\(totalYards) rushing yards, \(tds) TDs in \(gamesPlayed) games"
        case .WR, .TE:
            let recPerGame = Double(overall) / 18.0
            let totalRec = Int(recPerGame * Double(gamesPlayed))
            let totalYards = Int(Double(totalRec) * Double(overall) / 7.0)
            let tds = Int(Double(overall) / 15.0 * Double(gamesPlayed) / 5.0)
            return "\(totalRec) receptions, \(totalYards) yards, \(tds) TDs in \(gamesPlayed) games"
        case .DE, .DT:
            let sacks = Double(overall) / 20.0 * Double(gamesPlayed) / 5.0
            let tfls = sacks * 1.5
            return String(format: "%.1f sacks, %.0f TFLs in %d games", sacks, tfls, gamesPlayed)
        case .OLB, .MLB:
            let tacklesPerGame = Double(overall) / 12.0
            let totalTackles = Int(tacklesPerGame * Double(gamesPlayed))
            return "\(totalTackles) tackles in \(gamesPlayed) games"
        case .CB, .FS, .SS:
            let ints = Int(Double(overall) / 25.0 * Double(gamesPlayed) / 6.0)
            let pds = ints * 3 + Int.random(in: 1...4)
            return "\(ints) INTs, \(pds) pass deflections in \(gamesPlayed) games"
        case .LT, .LG, .C, .RG, .RT:
            let sacked = overall >= 70 ? "zero sacks allowed" : "\(Int.random(in: 1...3)) sacks allowed"
            return "Started all \(gamesPlayed) games, \(sacked)"
        case .K:
            let attempts = Int(Double(gamesPlayed) * 2.5)
            let made = Int(Double(attempts) * Double(overall) / 110.0)
            return "\(made)/\(attempts) FG in \(gamesPlayed) games"
        case .P:
            let avgYards = 38.0 + Double(overall) / 10.0
            return String(format: "%.1f avg punt yards in %d games", avgYards, gamesPlayed)
        }
    }

    // MARK: - Declaration Period

    /// Writes `declarationStatusRaw` for a class that went through the January
    /// window BEFORE the field existed (finding C5).
    ///
    /// `generateDeclarations` is idempotent — it returns immediately once any
    /// underclassman carries `isDeclaringForDraft == false` — so a save created
    /// before this wave never gets the string written and the whole class
    /// decodes as `.undecided`. `declarationLikelihood` then returns a value for
    /// every underclassman and the board paints a green "LIKELY" chip on a man
    /// who withdrew in January and cannot be drafted at all.
    ///
    /// The decision itself is never re-rolled: the status is reconstructed from
    /// the `isDeclaringForDraft` flag the class already carries. Runs only for a
    /// class whose window has demonstrably closed (the same test the generator's
    /// own guard uses), so a genuinely undecided autumn class is left alone.
    ///
    /// Deliberately NOT called from `generateDeclarations`: that member is
    /// sliced verbatim into the balance harness by `sync_sources.sh`, and a call
    /// to a function defined outside the slice would stop the `draftclass` gate
    /// compiling.
    ///
    /// - Returns: how many rows were healed.
    @discardableResult
    static func backfillDeclarationStatus(_ prospects: inout [CollegeProspect]) -> Int {
        let seniorAge = CollegeProspect.seniorAge
        guard prospects.contains(where: { $0.age < seniorAge && !$0.isDeclaringForDraft }) else {
            return 0
        }
        var healed = 0
        for i in prospects.indices where prospects[i].declarationStatusRaw.isEmpty {
            prospects[i].declarationStatusRaw = prospects[i].isDeclaringForDraft
                ? DeclarationStatus.declared.rawValue
                : DeclarationStatus.withdrawn.rawValue
            healed += 1
        }
        return healed
    }

    /// Simulates the draft declaration period: seniors auto-declare, the best
    /// underclassmen declare on a talent-weighted roll (~70, more when the class
    /// is senior-light), ~5-10 withdraw, and exactly one genuine top-of-board
    /// underclassman pulls his name back. The declaring pool is guaranteed to
    /// exceed the draft's 224 picks by a UDFA-market cushion.
    /// Returns news items for top declarations and withdrawals.
    ///
    /// Idempotent, like `runSeniorBowl` and `applyPreDraftAttrition`: a class
    /// that has already been through the declaration window is left alone. It
    /// was the one cycle pass without a guard, and re-entering `.coachingChanges`
    /// therefore withdrew ANOTHER 5-11 declared underclassmen and shocked a
    /// second top-of-board name off the board every time.
    ///
    /// `seed` is honoured by every draw when it is non-zero (the shipped game
    /// always passes `cycleSeed`, so a reloaded save re-runs the window
    /// identically). `seed == 0` — the balance harness, which wants an
    /// independent sample per generated class — falls back to the global RNG.
    static func generateDeclarations(
        prospects: inout [CollegeProspect],
        seed: UInt64 = 0
    ) -> [(name: String, isDeclaration: Bool, headline: String, isShock: Bool)] {
        var newsItems: [(name: String, isDeclaration: Bool, headline: String, isShock: Bool)] = []

        // Deterministic stream for the shock withdrawal below. Written as a
        // NESTED helper on purpose, for the same reason `applyCombineDNP` is:
        // `tools/balance-harness/sync_sources.sh` slices this file by an anchor
        // list and captures each named member's balanced block, so a sibling
        // `private struct SeededGenerator` would be *called* by the slice and
        // *defined* nowhere in it, and the draftclass gate would stop compiling.
        // SplitMix64, seeded from (careerID, season) by the caller.
        var seedState = seed
        func seededRoll(_ bound: Int) -> Int {
            guard bound > 1 else { return 0 }
            seedState &+= 0x9E37_79B9_7F4A_7C15
            var z = seedState
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z = z ^ (z >> 31)
            return Int(z % UInt64(bound))
        }
        // Every draw in the pass, seeded when the caller gave a seed.
        func roll(_ range: ClosedRange<Int>) -> Int {
            guard seed != 0 else { return Int.random(in: range) }
            return range.lowerBound + seededRoll(range.count)
        }

        // Separate seniors and underclassmen. The cut lives on the model
        // (`CollegeProspect.seniorAge`) so the January window and the board's
        // own declaration read cannot drift into two different definitions of
        // who still has eligibility to keep.
        let seniorAge = CollegeProspect.seniorAge

        // 0. Idempotency guard. Before the window runs, `isDeclaringForDraft`
        //    carries the model default of `true` for the whole class; the pass
        //    below is the only thing that ever sets an UNDERCLASSMAN to false.
        //    So one undeclared underclassman means this class has already been
        //    through the window.
        guard !prospects.contains(where: { $0.age < seniorAge && !$0.isDeclaringForDraft }) else {
            return []
        }

        // 1. All seniors auto-declare
        for i in prospects.indices where prospects[i].age >= seniorAge {
            prospects[i].isDeclaringForDraft = true
            prospects[i].declarationStatusRaw = DeclarationStatus.declared.rawValue
        }

        // 2. Underclassmen: ~70 declare based on talent (higher overall = more likely)
        var underclassmenIndices = prospects.indices.filter { prospects[$0].age < seniorAge }
        underclassmenIndices.sort { prospects[$0].trueOverall > prospects[$1].trueOverall }

        // Nobody in the underclass declares until he is drawn below — the model
        // default is `true`, so leaving an underclassman untouched would silently
        // declare him.
        for i in underclassmenIndices {
            prospects[i].isDeclaringForDraft = false
            // The window is open, so nobody in the underclass is `.undecided`
            // once it closes: whoever is not flipped below stayed in school.
            prospects[i].declarationStatusRaw = DeclarationStatus.withdrawn.rawValue
        }

        // The declaring pool has to fill the whole draft AND leave a UDFA market
        // behind it. The class's senior count swings roughly 140–203 between
        // classes (age is drawn per prospect), so a flat 65–75 underclassmen
        // target left 17 % of classes with fewer declared players than the 224
        // picks the seven rounds consume — the board then empties mid-draft,
        // late picks silently vanish and `DraftEngine.aiMakePick` traps on an
        // empty pool. The target is therefore the larger of the flavour band and
        // "enough bodies for every pick plus a UDFA class", so the pool lands at
        // ≥ 224 + `udfaCushion` in every class.
        //
        // PHASE 2 TARGET CHANGE (plan §2.9.8): the cushion was 26, which is a
        // UDFA market of roughly ONE signing per club — the 31 AI teams then
        // fought over ~28 players while each asked for 10-14, and the fix to
        // that loop (`WeekAdvancer`, shuffled order + a fair per-team share) is
        // only half the story: the market itself was too thin to be a market.
        // 60 puts annual inflow at 224 picks + ~60 undrafted ≈ the ~250-300
        // new players a season `DEVELOPMENT_NFL_REFERENCE.md` §8 calls for.
        // This is a deliberate raise of the target, not a relaxed guard: the
        // ≥ 224 + cushion floor still holds in EVERY class by construction
        // (target ≤ underclass count is guaranteed while 224 + 60 + 10 ≤ 350).
        // Harness-measured over 200 generated classes with the new cushion
        // (`./run.sh draftclass`, assert 7.11): declared pool mean ≈ 286.6
        // (286.4-286.8 across runs), min 284, max 289 — 0 classes short of the
        // 284 floor.
        //
        // `maxWithdrawals` is 11, not 10, because the withdrawal pass below now
        // ends with ONE genuine top-40 underclassman pulling his name back (the
        // annual shock). Reserving his slot here is what keeps the ≥ 284 floor
        // exactly where assert 7.11 measured it.
        let seniorCount = prospects.count - underclassmenIndices.count
        let draftCapacity = 224
        let udfaCushion = 60
        let maxWithdrawals = 11
        let flavourTarget = roll(65...75)
        let targetDeclarations = min(
            underclassmenIndices.count,
            max(flavourTarget, draftCapacity + udfaCushion + maxWithdrawals - seniorCount)
        )

        var declarationCount = 0
        var undeclared: [Int] = []

        for i in underclassmenIndices {
            guard declarationCount < targetDeclarations else {
                undeclared.append(i)
                continue
            }

            // Higher-rated underclassmen are more likely to declare.
            // Thresholds re-anchored to the generator-v2 talent curve
            // (#1 ≈ 92 · #28 ≈ 79 · #100 ≈ 72.5 · #350 ≈ 62); the old 80/70/60
            // cut points were tuned against the compressed 60–69 band and would
            // now put every prospect in the top bracket.
            let declareChance: Int
            let overall = prospects[i].trueOverall
            if overall >= 79 { declareChance = 95 }
            else if overall >= 73 { declareChance = 62 }
            else if overall >= 68 { declareChance = 32 }
            else { declareChance = 10 }

            if roll(1...100) <= declareChance {
                prospects[i].isDeclaringForDraft = true
                prospects[i].declarationStatusRaw = DeclarationStatus.declared.rawValue
                declarationCount += 1

                // Track top declarations for news
                if newsItems.filter({ $0.isDeclaration }).count < 5 {
                    let pos = prospects[i].position.rawValue
                    newsItems.append((
                        name: prospects[i].fullName,
                        isDeclaration: true,
                        headline: "\(prospects[i].college) \(pos) \(prospects[i].fullName) declares for draft",
                        isShock: false
                    ))
                }
            } else {
                undeclared.append(i)
            }
        }

        // The per-bracket rates only reach ~63 declarations over a typical
        // 174-man underclass, i.e. below the target every time. Top the pool up
        // from the best remaining underclassmen so the target is an actual
        // target rather than a ceiling the draw never touches.
        for i in undeclared where declarationCount < targetDeclarations {
            prospects[i].isDeclaringForDraft = true
            prospects[i].declarationStatusRaw = DeclarationStatus.declared.rawValue
            declarationCount += 1
        }

        // 3. Withdrawals: ~5-10 declared underclassmen change their mind.
        //    The `trueOverall < 76` cap keeps this pass to the anonymous churn
        //    it is meant to be — a fringe player who reads his grade and goes
        //    back for another year is not a story.
        let withdrawalCount = roll(5...10)
        // Canonical UUID order first, then a seeded Fisher-Yates: the class
        // arrives in whatever order SwiftData handed back, so shuffling the raw
        // index list would pick array slots rather than men.
        var declaredUnderclassmen = prospects.indices.filter {
            prospects[$0].age < seniorAge && prospects[$0].isDeclaringForDraft && prospects[$0].trueOverall < 76
        }.sorted { prospects[$0].id.uuidString < prospects[$1].id.uuidString }
        if seed != 0 {
            var upper = declaredUnderclassmen.count - 1
            while upper > 0 {
                declaredUnderclassmen.swapAt(upper, seededRoll(upper + 1))
                upper -= 1
            }
        } else {
            declaredUnderclassmen.shuffle()
        }

        for i in declaredUnderclassmen.prefix(withdrawalCount) {
            prospects[i].isDeclaringForDraft = false
            prospects[i].declarationStatusRaw = DeclarationStatus.withdrawn.rawValue
            let pos = prospects[i].position.rawValue
            newsItems.append((
                name: prospects[i].fullName,
                isDeclaration: false,
                headline: "Top \(pos) \(prospects[i].fullName) returns to \(prospects[i].college) for senior year",
                isShock: false
            ))
        }

        // 4. The shock withdrawal. Every real class loses one name off the top
        //    of the board in January — a projected early-round man who goes back
        //    for a title run, a degree, or on the advice of a medical recheck —
        //    and it reshapes the round for everybody behind him. Exactly ONE per
        //    class. Only an underclassman can do this: a senior has no
        //    eligibility left to go back to.
        //
        //    Drawn off the PUBLIC board (`draftProjection`), never `trueOverall`.
        //    The old pool was the top 40 by the hidden rating and the headline
        //    asserted "projected first-round" whatever his real projection was,
        //    so (a) a round-4 name could be announced as a first-rounder, which
        //    contradicted his own board row, and (b) because a withdrawn
        //    underclassman comes BACK in a later class, the headline was a
        //    durable tell that this specific man is genuine top-40 talent.
        let shockPool = Array(
            prospects.indices
                .filter { prospects[$0].age < seniorAge && prospects[$0].isDeclaringForDraft }
                .sorted { a, b in
                    let pa = prospects[a].draftProjection ?? 8
                    let pb = prospects[b].draftProjection ?? 8
                    if pa != pb { return pa < pb }
                    let ma = prospects[a].mockDraftPickNumber ?? Int.max
                    let mb = prospects[b].mockDraftPickNumber ?? Int.max
                    if ma != mb { return ma < mb }
                    return prospects[a].id.uuidString < prospects[b].id.uuidString
                }
                .prefix(40)
        )
        if !shockPool.isEmpty {
            let choice = shockPool[seededRoll(shockPool.count)]
            prospects[choice].isDeclaringForDraft = false
            prospects[choice].declarationStatusRaw = DeclarationStatus.withdrawn.rawValue
            let pos = prospects[choice].position.rawValue
            let college = prospects[choice].college
            // Phrased from the projection his own board row shows.
            let band: String
            switch prospects[choice].draftProjection ?? 3 {
            case 1:  band = "projected first-round"
            case 2:  band = "projected second-round"
            case 3:  band = "projected third-round"
            default: band = "projected day-two"
            }
            let reasons = [
                "returns to \(college) for one more run at a title",
                "pulls his name out to finish his degree at \(college)",
                "withdraws on medical advice and returns to \(college)"
            ]
            let reason = reasons[seededRoll(reasons.count)]
            newsItems.append((
                name: prospects[choice].fullName,
                isDeclaration: false,
                headline: "SHOCK: \(band) \(pos) \(prospects[choice].fullName) \(reason)",
                isShock: true
            ))
        }

        return newsItems
    }

    // MARK: - UDFA Pool

    /// **Membership** in the undrafted pool — the one authority for who is in it.
    ///
    /// Ordering is deliberately NOT part of membership: the UDFA market (#204)
    /// needs two different orders over the same set and they must not be able to
    /// disagree about *who* is in it. See ``getUDFAPool`` (fog-safe, the order any
    /// user-facing surface may read) and ``getUDFAPoolByTrueValue`` (engine-only).
    ///
    /// A man leaves the pool the moment he is signed, because every signing path
    /// routes through `DraftEngine.convertUDFAToPlayer`, which clears
    /// `isDeclaringForDraft` (defect D1). That is also what makes the market
    /// double-signing-proof: the Draft Day panel and the OTAs board read this
    /// same predicate, so a man signed on draft night is simply not in the pool
    /// the OTAs board opens on.
    static func udfaPoolMembers(prospects: [CollegeProspect]) -> [CollegeProspect] {
        prospects.filter { $0.isDeclaringForDraft && $0.mockDraftPickNumber == nil }
    }

    /// The undrafted pool in **fog-safe** order: the user's own board, best
    /// scouted grade first.
    ///
    /// This used to sort by `trueOverall` and it was a live fog leak (defect D2,
    /// `OFFSEASON_ROSTER_PLAN.md` §0): the OTAs inbox message printed
    /// `pool.prefix(5)` off that sort, i.e. the league's REAL top five undrafted
    /// men, straight past the scouting screen the whole draft is played through.
    /// Invariant (5) says a user-facing surface may only be ordered by what his
    /// own department has seen, so the key here is `effectiveOverallGrade` — the
    /// scouted band, with the legacy `scoutedOverall` / `scoutGrade` fallbacks —
    /// and an unscouted man sorts last rather than being silently ranked.
    ///
    /// Ties break on `lastName` then `id`, so the same board comes back in the
    /// same order twice. (Grade midpoints tie constantly — a `Dictionary`- or
    /// hash-ordered tiebreak would reshuffle the board on every redraw.)
    static func getUDFAPool(prospects: [CollegeProspect]) -> [CollegeProspect] {
        udfaPoolMembers(prospects: prospects).sorted { lhs, rhs in
            let lhsRank = lhs.effectiveOverallGrade?.midGrade.rank ?? Int.min
            let rhsRank = rhs.effectiveOverallGrade?.midGrade.rank ?? Int.min
            if lhsRank != rhsRank { return lhsRank > rhsRank }
            if lhs.lastName != rhs.lastName { return lhs.lastName < rhs.lastName }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// The undrafted pool in **true-value** order, best first.
    ///
    /// ENGINE-ONLY. An AI club runs its own scouting department, so its internal
    /// board may be the real one; nothing derived from this order may be printed,
    /// badged, sorted into a user-facing list or leaked through an inbox message.
    /// The only caller is `UDFAMarketEngine`'s AI bidding pass.
    static func getUDFAPoolByTrueValue(prospects: [CollegeProspect]) -> [CollegeProspect] {
        udfaPoolMembers(prospects: prospects).sorted { lhs, rhs in
            if lhs.trueOverall != rhs.trueOverall { return lhs.trueOverall > rhs.trueOverall }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    // MARK: - Pre-Scouted Data (First Season)

    /// Generate pre-scouted data for first season (simulates previous GM's scouting work).
    /// Top 50 prospects get advanced scouting, next 100 basic, next 100 minimal, rest unknown.
    static func applyPreScoutedData(prospects: inout [CollegeProspect]) {
        // Sort by true overall to determine tiers
        let sortedIndices = prospects.indices.sorted {
            prospects[$0].trueOverall > prospects[$1].trueOverall
        }

        for (rank, idx) in sortedIndices.enumerated() {
            if rank < 50 {
                // Advanced scouting: within +-5 of true, accurate grade, personality/potential
                let error = Int.random(in: -5...5)
                let scoutedOvr = min(99, max(1, prospects[idx].trueOverall + error))
                prospects[idx].scoutedOverall = scoutedOvr

                // Accurate scout grade
                prospects[idx].scoutGrade = LetterGrade.from(numericValue: scoutedOvr).rawValue

                // Potential revealed with moderate accuracy (within +-8)
                let potError = Int.random(in: -8...8)
                prospects[idx].scoutedPotential = min(99, max(1,
                    prospects[idx].truePotential + potError))

                // Personality revealed (80% accurate). This is INHERITED work —
                // the previous department's file, not anything the user's staff
                // saw — so it is stamped `.leagueConsensus`, the weakest source
                // there is: any read your own people produce may replace it
                // (#185).
                let inheritedRead = rollPersonalityRead(
                    trueArchetype: prospects[idx].truePersonality.archetype,
                    readSkill: 80,
                    characterFocus: false
                )
                recordPersonalityRead(
                    inheritedRead.archetype,
                    source: .leagueConsensus,
                    on: prospects[idx]
                )

                // Generate a pre-scout report
                let report = ScoutingReport(
                    prospectID: prospects[idx].id,
                    scoutID: UUID(),
                    scoutName: "Previous Staff",
                    date: "Pre-Season",
                    phase: .collegeSeason,
                    overallGrade: scoutedOvr,
                    potentialGrade: prospects[idx].scoutedPotential ?? scoutedOvr,
                    strengthNotes: "Thorough evaluation from previous scouting department.",
                    weaknessNotes: "Full report on file.",
                    personalityNotes: prospects[idx].scoutedPersonality != nil
                        ? "Personality assessment included." : nil,
                    confidenceLevel: 0.65,
                    productionNotes: generateProductionNotes(for: prospects[idx], week: 12)
                )
                prospects[idx].scoutingReports.append(report)

            } else if rank < 150 {
                // Basic scouting: within +-10 of true, grade set (possibly inaccurate)
                let error = Int.random(in: -10...10)
                let scoutedOvr = min(99, max(1, prospects[idx].trueOverall + error))
                prospects[idx].scoutedOverall = scoutedOvr
                prospects[idx].scoutGrade = LetterGrade.from(numericValue: scoutedOvr).rawValue

                let report = ScoutingReport(
                    prospectID: prospects[idx].id,
                    scoutID: UUID(),
                    scoutName: "Previous Staff",
                    date: "Pre-Season",
                    phase: .collegeSeason,
                    overallGrade: scoutedOvr,
                    potentialGrade: scoutedOvr,
                    strengthNotes: "Basic evaluation on file.",
                    weaknessNotes: "Limited tape review.",
                    personalityNotes: nil,
                    confidenceLevel: 0.45,
                    productionNotes: generateProductionNotes(for: prospects[idx], week: 8)
                )
                prospects[idx].scoutingReports.append(report)

            } else if rank < 250 {
                // Minimal scouting: within +-15 of true, only general info
                let error = Int.random(in: -15...15)
                let scoutedOvr = min(99, max(1, prospects[idx].trueOverall + error))
                prospects[idx].scoutedOverall = scoutedOvr

                let report = ScoutingReport(
                    prospectID: prospects[idx].id,
                    scoutID: UUID(),
                    scoutName: "Previous Staff",
                    date: "Pre-Season",
                    phase: .collegeSeason,
                    overallGrade: scoutedOvr,
                    potentialGrade: scoutedOvr,
                    strengthNotes: "Name on the board. Minimal evaluation.",
                    weaknessNotes: "Needs further evaluation.",
                    personalityNotes: nil,
                    confidenceLevel: 0.25
                )
                prospects[idx].scoutingReports.append(report)
            }
            // Remaining prospects (rank >= 250): no scouted data
        }
    }

    // MARK: - Next Year's Draft Class Preview

    /// A lightweight preview prospect for next year's draft class.
    /// No detailed attributes -- just name, position, college, and a rough projected grade.
    struct NextYearProspect: Identifiable {
        let id = UUID()
        let firstName: String
        let lastName: String
        let position: Position
        let college: String
        let classYear: String        // "Junior" or "Sophomore"
        let projectedGrade: String   // "Top 10 Pick", "1st Round", "Day 2"

        var fullName: String { "\(firstName) \(lastName)" }
    }

    /// Generates top ~25 prospects for NEXT year's draft class.
    ///
    /// These are early buzz projections with only surface-level info:
    /// name, position, college, class year, and a rough projected grade.
    /// Full scouting begins next season.
    ///
    /// - Parameter count: Number of preview prospects to generate (default 25).
    /// - Returns: An array of `NextYearProspect` sorted by projected grade.
    static func generateNextYearPreview(count: Int = 25) -> [NextYearProspect] {
        var prospects: [NextYearProspect] = []

        // Position distribution for the preview (heavy on premium positions)
        let previewPositions: [Position] = [
            .QB, .QB, .QB,
            .WR, .WR, .WR,
            .DE, .DE,
            .CB, .CB,
            .OLB, .OLB,
            .LT, .LT,
            .RB, .RB,
            .TE,
            .DT, .DT,
            .MLB,
            .FS, .SS,
            .WR, .RG, .C
        ]

        let gradeDistribution: [String] = [
            "Top 10 Pick", "Top 10 Pick", "Top 10 Pick",
            "1st Round", "1st Round", "1st Round", "1st Round", "1st Round",
            "1st Round", "1st Round",
            "Day 2", "Day 2", "Day 2", "Day 2", "Day 2",
            "Day 2", "Day 2", "Day 2", "Day 2", "Day 2",
            "Day 2", "Day 2", "Day 2", "Day 2", "Day 2"
        ]

        for i in 0..<min(count, previewPositions.count) {
            let name = RandomNameGenerator.randomName()
            let college = colleges.randomElement()!
            let classYear = i < 8 ? "Junior" : (Bool.random() ? "Junior" : "Sophomore")
            let grade = i < gradeDistribution.count ? gradeDistribution[i] : "Day 2"

            prospects.append(NextYearProspect(
                firstName: name.first,
                lastName: name.last,
                position: previewPositions[i],
                college: college,
                classYear: classYear,
                projectedGrade: grade
            ))
        }

        return prospects
    }

    // MARK: - Combine Media Summary (#259)

    struct CombineMediaMention {
        let prospectID: UUID
        let prospectName: String
        let position: String
        let headline: String
        let category: String  // "Standout", "Stock Riser", "Stock Faller", "Surprise"
    }

    /// Generates combine media coverage and stamps `combineMediaMention` on highlighted prospects.
    static func generateCombineMedia(prospects: inout [CollegeProspect]) -> [CombineMediaMention] {
        var mentions: [CombineMediaMention] = []

        let invited = prospects.filter { $0.combineInvite && $0.fortyTime != nil }
        guard !invited.isEmpty else { return mentions }

        // --- Standouts: prospects with any elite drill result (top 5% for position) ---
        // Limited to 1-3 per position to prevent unrealistic clustering (e.g. 5 QBs)
        let standoutCandidates = invited.filter { p in
            let bm = CombineBenchmarks.benchmarks(for: p.position)
            return isElite(p.fortyTime, benchmark: bm.fortyYard)
                || isElite(Double(p.benchPress ?? 0), benchmark: bm.benchPress)
                || isElite(p.verticalJump, benchmark: bm.verticalJump)
                || isElite(Double(p.broadJump ?? 0), benchmark: bm.broadJump)
                || isElite(p.coneDrill, benchmark: bm.threeCone)
                || isElite(p.shuttleTime, benchmark: bm.shuttle)
        }
        .sorted { ($0.trueOverall) > ($1.trueOverall) }

        // Limit to 1-3 standouts per position to ensure diversity
        var standoutPositionCount: [Position: Int] = [:]
        var selectedStandouts: [CollegeProspect] = []
        for p in standoutCandidates {
            let posCount = standoutPositionCount[p.position, default: 0]
            let maxPerPosition = Int.random(in: 1...2) // 1-2 per position
            if posCount < maxPerPosition {
                selectedStandouts.append(p)
                standoutPositionCount[p.position, default: 0] += 1
            }
            if selectedStandouts.count >= Int.random(in: 4...7) { break }
        }

        for p in selectedStandouts {
            let headline = standoutHeadline(for: p)
            mentions.append(CombineMediaMention(
                prospectID: p.id, prospectName: p.fullName,
                position: p.position.rawValue, headline: headline, category: "Standout"
            ))
        }

        let standoutIDs = Set(mentions.map { $0.prospectID })

        // --- Stock Risers: combine improved grade vs pre-combine projection ---
        let riserCandidates = invited.filter { p in
            guard !standoutIDs.contains(p.id) else { return false }
            guard let proj = p.draftProjection else { return false }
            // Lower projection number = better. If true overall suggests higher pick
            // than projection, they rose.
            let combineGrade = combineAveragePercentile(p)
            return combineGrade >= 70 && proj >= 3  // Decent combine but was projected late
        }
        .sorted { combineAveragePercentile($0) > combineAveragePercentile($1) }

        let riserIDs = Set(riserCandidates.prefix(Int.random(in: 3...5)).map { $0.id })
        for p in riserCandidates.prefix(Int.random(in: 3...5)) {
            let headline = riserHeadline(for: p)
            mentions.append(CombineMediaMention(
                prospectID: p.id, prospectName: p.fullName,
                position: p.position.rawValue, headline: headline, category: "Stock Riser"
            ))
        }

        // --- Stock Fallers: high OVR but poor combine (slow 40, low bench) ---
        let fallerCandidates = invited.filter { p in
            guard !standoutIDs.contains(p.id), !riserIDs.contains(p.id) else { return false }
            let combineGrade = combineAveragePercentile(p)
            return p.trueOverall >= 70 && combineGrade < 40
        }
        .sorted { $0.trueOverall > $1.trueOverall }

        let fallerIDs = Set(fallerCandidates.prefix(Int.random(in: 2...3)).map { $0.id })
        for p in fallerCandidates.prefix(Int.random(in: 2...3)) {
            let headline = fallerHeadline(for: p)
            mentions.append(CombineMediaMention(
                prospectID: p.id, prospectName: p.fullName,
                position: p.position.rawValue, headline: headline, category: "Stock Faller"
            ))
        }

        // --- Surprises: low-projected prospects with elite combine numbers ---
        let surpriseCandidates = invited.filter { p in
            guard !standoutIDs.contains(p.id), !riserIDs.contains(p.id),
                  !fallerIDs.contains(p.id) else { return false }
            guard let proj = p.draftProjection else { return false }
            let combineGrade = combineAveragePercentile(p)
            return proj >= 5 && combineGrade >= 75
        }
        .sorted { combineAveragePercentile($0) > combineAveragePercentile($1) }

        for p in surpriseCandidates.prefix(Int.random(in: 2...3)) {
            let headline = surpriseHeadline(for: p)
            mentions.append(CombineMediaMention(
                prospectID: p.id, prospectName: p.fullName,
                position: p.position.rawValue, headline: headline, category: "Surprise"
            ))
        }

        // Stamp combineMediaMention on prospects (prefixed with category for color coding)
        let mentionMap = Dictionary(
            mentions.map { ($0.prospectID, "[\($0.category)] \($0.headline)") },
            uniquingKeysWith: { a, _ in a }
        )
        for i in prospects.indices {
            if let taggedHeadline = mentionMap[prospects[i].id] {
                prospects[i].combineMediaMention = taggedHeadline
            }
        }

        return mentions
    }

    // MARK: - Combine as a League Event

    /// Runs the combine for a draft class that has not had one yet.
    ///
    /// The combine happens in Indianapolis in front of a television audience
    /// whether or not any one club sends staff, and this is the function that
    /// says so. It used to be reachable only from the "Send Scouts to Combine"
    /// button in the scouting hub, which meant a user who advanced past the
    /// phase without pressing it — or any user at all from season 2 onward,
    /// where the career-scoped "already sent" flag was never cleared — ended the
    /// cycle with a draft class carrying no measurements of any kind and a
    /// Combine tab that could never fill in. Attendance is now a *fidelity*
    /// decision (`ProspectFog.combineFidelity`), not the switch that decides
    /// whether the event occurred.
    ///
    /// Idempotent: a class that already has a forty time on it is left alone, so
    /// this is safe to call from the phase transition, from a view's load, and
    /// from the button, all in the same cycle.
    ///
    /// - Returns: `true` when this call actually ran the event.
    @discardableResult
    static func runLeagueCombine(
        prospects: inout [CollegeProspect],
        scoutingAbility: Int = 50
    ) -> Bool {
        guard !prospects.isEmpty else { return false }
        guard !prospects.contains(where: { $0.fortyTime != nil }) else { return false }

        // Snapshot the pre-combine read so the risers/fallers strip has a
        // baseline to diff against. Must happen before any new report lands.
        for i in prospects.indices {
            prospects[i].preCombineGrade = prospects[i].scoutGrade
        }

        generateCombineResults(for: &prospects, scoutingAbility: scoutingAbility)
        _ = generateCombineMedia(prospects: &prospects)
        return true
    }

    /// What sending your own department to the combine buys on top of the
    /// broadcast: a filed `.combine` report on the men your board actually
    /// tracks, which narrows their grade band and lifts
    /// `DraftIntel.scoutConfidence`.
    ///
    /// Deliberately capped. A club has a week and a few dozen people in
    /// Indianapolis; it does not re-scout all 330 invitees, and letting it would
    /// make the trip strictly better than a season of regional work.
    ///
    /// - Parameter trackedIDs: prospects the user has starred, flagged or ranked.
    /// - Returns: how many reports were filed.
    @discardableResult
    static func applyCombineScouting(
        prospects: inout [CollegeProspect],
        trackedIDs: Set<UUID>,
        scouts: [Scout],
        limit: Int = 40
    ) -> Int {
        guard !scouts.isEmpty, !trackedIDs.isEmpty else { return 0 }

        var filed = 0
        for i in prospects.indices {
            guard filed < limit else { break }
            guard prospects[i].combineInvite else { continue }
            guard trackedIDs.contains(prospects[i].id) else { continue }
            // One combine report per prospect — re-entering the phase must not
            // stack bands narrower and narrower for free.
            guard !prospects[i].scoutingReports.contains(where: { $0.phase == .combine }) else { continue }

            let scout = scouts[filed % scouts.count]
            let report = generateScoutReport(scout: scout, prospect: prospects[i], phase: .combine)
            applyReport(report: report, to: prospects[i], scout: scout)
            filed += 1
        }
        return filed
    }

    /// Cost in thousands of sending the scouting department to Indianapolis.
    ///
    /// Travel, a week of hotels and the analytics contractor who turns the
    /// stopwatch sheet into percentiles — it scales with how many people go,
    /// because a bigger department gets more of the board covered.
    ///
    /// **Re-priced in #104, down from `300 + 40n` ($620K for a full department).**
    /// The old figure was written against the *nominal* $4.0M scouting pot, but
    /// the pot is not what the trip is bought out of: scout salaries come out of
    /// the same money first. A club that filled all eight scout jobs at market
    /// rate — which the staff screen's auto-hire does by design — was left with
    /// about $190K, so the FULLEST department in the league was the one that
    /// could never attend, while a two-man shop could. The cost rose with
    /// headcount exactly as the money available fell with it.
    ///
    /// The trip is now a travel line, not a second salary bill: it is reachable
    /// from what a fully-staffed department has left, and the money that
    /// actually rations the spring is salaries and per-prospect evaluations
    /// (`ScoutEvaluationBudget`, $20-55K a report, 25 a cycle).
    static func combineTripCost(scoutCount: Int) -> Int {
        60 + 10 * max(0, min(8, scoutCount))
    }

    /// Everything a surface needs to draw the combine-trip CTA: the price, what
    /// is left to pay it with, and — when it cannot be paid — the sentence that
    /// says so.
    ///
    /// **One gate, one quote (#104).** The trip had two entry points with one
    /// affordability rule between them: `CombineResultsView` was handed
    /// `canAffordTrip` and greyed its button correctly, while the Scout Team
    /// tab's gold "Send Scouts to the Combine" row was handed neither the
    /// verdict nor a `disabled` modifier — so it stayed live, ran
    /// `sendScoutsToCombine()`, hit that function's own `guard canAfford else
    /// { return }` and did nothing at all. A tap with no state change, no alert
    /// and no sheet, on the one task the phase was gated on. Any surface that
    /// offers the trip reads this.
    struct CombineTripQuote {
        /// Price in thousands.
        let cost: Int
        /// Scouting pot left after salaries and spend already committed.
        let remaining: Int

        var canAfford: Bool { remaining >= cost }

        /// Why the button is dead, or `nil` when it is live. A disabled control
        /// that does not say why is the bug this type exists to stop repeating.
        var blockedReason: String? {
            guard !canAfford else { return nil }
            return "Not enough scouting budget \u{2014} the trip costs $\(cost)K and $\(max(0, remaining))K is left after salaries."
        }
    }

    /// Quotes the combine trip against what the department can actually spend.
    ///
    /// - Parameters:
    ///   - scoutCount: how many scouts travel.
    ///   - remainingBudget: the owner's scouting pot minus scout salaries and
    ///     any discretionary spend already committed this cycle.
    static func combineTripQuote(scoutCount: Int, remainingBudget: Int) -> CombineTripQuote {
        CombineTripQuote(
            cost: combineTripCost(scoutCount: scoutCount),
            remaining: remainingBudget
        )
    }

    /// Rebuilds the combine media digest from what is stored on the prospects.
    ///
    /// `generateCombineMedia` stamps `combineMediaMention` as
    /// `"[Category] headline"`, so the report sheet can be reopened after a
    /// relaunch — or after the event was run by the phase transition rather than
    /// by the button — without re-rolling a second, contradictory set of
    /// headlines.
    static func combineMediaDigest(prospects: [CollegeProspect]) -> [CombineMediaMention] {
        prospects.compactMap { prospect -> CombineMediaMention? in
            guard let stored = prospect.combineMediaMention else { return nil }
            let (category, headline) = splitTaggedMention(stored)
            return CombineMediaMention(
                prospectID: prospect.id,
                prospectName: prospect.fullName,
                position: prospect.position.rawValue,
                headline: headline,
                category: category
            )
        }
    }

    /// `"[Stock Riser] He ran a 4.41"` -> `("Stock Riser", "He ran a 4.41")`.
    /// An untagged string (older save) keeps its text and lands in "Standout".
    static func splitTaggedMention(_ stored: String) -> (category: String, headline: String) {
        guard stored.hasPrefix("["), let close = stored.firstIndex(of: "]") else {
            return ("Standout", stored)
        }
        let category = String(stored[stored.index(after: stored.startIndex)..<close])
        let headline = String(stored[stored.index(after: close)...])
            .trimmingCharacters(in: .whitespaces)
        return (category, headline.isEmpty ? stored : headline)
    }

    // MARK: - Combine Media Helpers

    private static func isElite(_ value: Double?, benchmark: CombineBenchmarks.DrillBenchmark) -> Bool {
        guard let value else { return false }
        if benchmark.lowerIsBetter {
            // Top 5% = within 5% of elite threshold toward lower
            return value <= benchmark.elite * 1.02
        } else {
            return value >= benchmark.elite * 0.98
        }
    }

    private static func combineAveragePercentile(_ p: CollegeProspect) -> Int {
        let bm = CombineBenchmarks.benchmarks(for: p.position)
        var pcts: [Int] = []
        if let v = p.fortyTime { pcts.append(CombineBenchmarks.percentile(value: v, benchmark: bm.fortyYard)) }
        if let v = p.benchPress { pcts.append(CombineBenchmarks.percentile(value: Double(v), benchmark: bm.benchPress)) }
        if let v = p.verticalJump { pcts.append(CombineBenchmarks.percentile(value: v, benchmark: bm.verticalJump)) }
        if let v = p.broadJump { pcts.append(CombineBenchmarks.percentile(value: Double(v), benchmark: bm.broadJump)) }
        if let v = p.coneDrill { pcts.append(CombineBenchmarks.percentile(value: v, benchmark: bm.threeCone)) }
        if let v = p.shuttleTime { pcts.append(CombineBenchmarks.percentile(value: v, benchmark: bm.shuttle)) }
        guard !pcts.isEmpty else { return 50 }
        return pcts.reduce(0, +) / pcts.count
    }

    /// The wire line for a standout.
    ///
    /// Surname, not `fullName`: the combine report row and the media popover
    /// both draw the man's full name directly above this sentence, so opening
    /// with it printed "Jamari Goddard / Jamari Goddard posts elite combine
    /// numbers…". Dropping the name entirely is not available — the same string
    /// is the standalone headline of a news item
    /// (`NewsGenerator.combineMediaNews`), where a subjectless sentence has
    /// nobody in it — and a surname is how a wire desk writes the second
    /// reference anyway.
    ///
    /// The branches also asked a different question than the selection did. A
    /// man reaches this function because `isElite` found one of his drills in
    /// the top 5% FOR HIS POSITION, and the copy then tested absolute numbers —
    /// a sub-4.40 forty, 35 bench reps, a 40" vertical — which an interior
    /// lineman elite on the bench FOR A LINEMAN never meets. Three standouts in
    /// four fell through to the one generic sentence. Each drill now has its
    /// own line, gated on the same test that put him on the list.
    private static func standoutHeadline(for p: CollegeProspect) -> String {
        let bm = CombineBenchmarks.benchmarks(for: p.position)
        if let ft = p.fortyTime, isElite(ft, benchmark: bm.fortyYard) {
            return "\(p.lastName) blazes a \(String(format: "%.2f", ft)) forty — first-round wheels"
        }
        if let vj = p.verticalJump, isElite(vj, benchmark: bm.verticalJump) {
            return "\(p.lastName) soars to a \(String(format: "%.1f", vj))\" vertical, rare explosion off the ground"
        }
        if let bj = p.broadJump, isElite(Double(bj), benchmark: bm.broadJump) {
            return "\(p.lastName) broad jumps \(bj / 12)'\(bj % 12)\", top of the class in lower-body power"
        }
        if let bp = p.benchPress, isElite(Double(bp), benchmark: bm.benchPress) {
            return "\(p.lastName) powers out \(bp) bench reps, dominating the strength testing"
        }
        if let cone = p.coneDrill, isElite(cone, benchmark: bm.threeCone) {
            return "\(p.lastName) bends a \(String(format: "%.2f", cone)) three-cone, elite change of direction for the position"
        }
        if let shuttle = p.shuttleTime, isElite(shuttle, benchmark: bm.shuttle) {
            return "\(p.lastName) fires a \(String(format: "%.2f", shuttle)) short shuttle, elite short-area quickness"
        }
        return "\(p.lastName) posts elite combine numbers across the board"
    }

    private static func riserHeadline(for p: CollegeProspect) -> String {
        if let ft = p.fortyTime {
            return "\(p.lastName) surprises with a \(String(format: "%.2f", ft)) forty, vaults up draft boards"
        }
        return "\(p.lastName) impresses at the combine, stock soaring"
    }

    private static func fallerHeadline(for p: CollegeProspect) -> String {
        if let ft = p.fortyTime, ft > 4.70 {
            return "\(p.lastName) disappoints with a \(String(format: "%.2f", ft)) forty, stock drops"
        }
        return "\(p.lastName) underwhelms at the combine, raising red flags for scouts"
    }

    private static func surpriseHeadline(for p: CollegeProspect) -> String {
        if let ft = p.fortyTime, ft < 4.50 {
            return "Unheralded \(p.position.rawValue) \(p.lastName) runs a \(String(format: "%.2f", ft)), turns heads at the combine"
        }
        return "Late-round projection \(p.lastName) steals the show with elite testing"
    }

    // MARK: - Risk Profile (Medical & Character)

    /// Generates a medical / character risk profile for a prospect.
    /// Distribution (heuristic):
    ///   - 80% clean (no flags)
    ///   - 14% one medical flag
    ///   - 4%  one red (off-field/character) flag
    ///   - 2%  both medical AND red flag
    /// Modifies `medicalConcerns` and `redFlags` on the prospect.
    static func generateRiskProfile(for prospect: inout CollegeProspect) {
        let medicalPool = [
            "ACL repair 2024",
            "Past concussion history",
            "Chronic shoulder",
            "Knee soreness flagged",
            "Lower back tightness",
            "Prior hamstring strain",
            "Previous foot fracture",
            "Hip flexor history"
        ]
        let redFlagPool = [
            "Off-field arrest",
            "Failed drug test",
            "Practice habits questioned",
            "Locker-room concerns",
            "Missed team meetings",
            "Coach clashed with player",
            "Social media incident"
        ]

        let roll = Int.random(in: 1...100)
        switch roll {
        case 1...80:
            // Clean — leave nil
            prospect.medicalConcerns = nil
            prospect.redFlags = nil
        case 81...94:
            // One medical flag
            prospect.medicalConcerns = [medicalPool.randomElement()!]
            prospect.redFlags = nil
        case 95...98:
            // One red flag
            prospect.medicalConcerns = nil
            prospect.redFlags = [redFlagPool.randomElement()!]
        default:
            // Both
            prospect.medicalConcerns = [medicalPool.randomElement()!]
            prospect.redFlags = [redFlagPool.randomElement()!]
        }
    }

    // MARK: - Top-30 Visit System

    /// Result of a Top-30 visit, returned for caller to surface in UI.
    /// The visit itself mutates the prospect (sets `interviewCompleted`, appends visiting team,
    /// fills `medicalConcerns` etc.). The struct is returned so callers can show a summary.
    struct Top30VisitResult {
        /// 2-3 character / leadership notes from a deep interview.
        let interviewNotes: [String]
        /// Football IQ revealed in the interview, 40..99.
        let footballIQRevised: Int
        /// 0-2 medical concerns surfaced during the medical exam.
        let medicalConcerns: [String]
        /// 1-2 workout impressions tailored to the visiting team's needs.
        let workoutImpressions: [String]
        /// Team-fit score (0..1) versus visiting team's roster context.
        let teamFitScore: Double
    }

    /// Conducts a Top-30 visit which combines (a) a deep interview,
    /// (b) a focused workout for the visiting team's needs,
    /// (c) a medical check.
    /// Mutates the prospect:
    ///   - sets `interviewCompleted = true`
    ///   - appends `visitingTeamID` to `top30VisitedByTeams` (idempotent)
    ///   - merges generated medical concerns into `medicalConcerns`
    ///   - revises `interviewFootballIQ` and persists character notes
    /// Returns enriched results that the caller can surface in UI / persist further.
    static func conductTop30Visit(
        prospect: inout CollegeProspect,
        visitingTeamID: UUID,
        interviewerQuality: Int,
        interviewerName: String? = nil,
        occasionLabel: String? = nil
    ) -> Top30VisitResult {
        // 1. Mark as visited by this team (idempotent).
        if !prospect.top30VisitedByTeams.contains(visitingTeamID) {
            prospect.top30VisitedByTeams.append(visitingTeamID)
        }

        // 2. Deep interview — reuse the existing interview engine.
        let interview = conductInterview(
            prospect: prospect,
            interviewerQuality: interviewerQuality,
            interviewerName: interviewerName,
            occasionLabel: occasionLabel ?? "Top-30 Visit"
        )
        // conductInterview already mutates interviewCompleted, scoutedPersonality,
        // interviewFootballIQ, interviewCharacterNotes, interviewNotes and the
        // revealed mental grade block. We pass a copy via the non-inout overload,
        // then re-apply onto the inout binding.
        prospect.interviewCompleted = true
        recordPersonalityRead(interview.personality, source: .interview, on: prospect)
        prospect.interviewFootballIQ = interview.footballIQ
        prospect.interviewCharacterNotes = interview.characterNotes

        // 3. Medical check — 25% chance per visit to surface a concern.
        var newMedicalConcerns: [String] = []
        if Int.random(in: 1...100) <= 25 {
            let medicalPool = [
                "Knee soreness flagged",
                "Past concussion history",
                "Shoulder labrum noted",
                "Lingering ankle issue",
                "Back stiffness on exam",
                "Hip mobility limited"
            ]
            newMedicalConcerns.append(medicalPool.randomElement()!)
            // Small chance of a second concern.
            if Int.random(in: 1...100) <= 25 {
                let second = medicalPool.randomElement()!
                if !newMedicalConcerns.contains(second) {
                    newMedicalConcerns.append(second)
                }
            }

            // Merge into prospect
            var existing = prospect.medicalConcerns ?? []
            for c in newMedicalConcerns where !existing.contains(c) {
                existing.append(c)
            }
            prospect.medicalConcerns = existing.isEmpty ? nil : existing
        }

        // 4. Workout impressions — position-specific.
        let workoutImpressions = generateWorkoutImpressions(for: prospect.position, prospect: prospect)

        // 5. Team-fit score — heuristic combining talent, board standing, and
        // personality fit. Board standing replaces the old positional-value
        // multiplier: a prospect's grade band already encodes how the league
        // values his position.
        let baseFit = Double(prospect.trueOverall) / 99.0
        let boardStanding = 1.0 - Double(min(8, max(1, prospect.draftProjection ?? 5)) - 1) / 7.0
        let personalityBonus: Double
        switch prospect.truePersonality.archetype {
        case .teamLeader, .quietProfessional, .mentor: personalityBonus = 0.10
        case .steadyPerformer:                          personalityBonus = 0.05
        case .dramaQueen, .feelPlayer:                  personalityBonus = -0.10
        case .classClown:                               personalityBonus = -0.03
        default:                                        personalityBonus = 0.0
        }
        let rawFit = baseFit * 0.6 + boardStanding * 0.3 + personalityBonus
        let teamFit = Swift.min(1.0, Swift.max(0.0, rawFit + Double.random(in: -0.05...0.05)))

        return Top30VisitResult(
            interviewNotes: interview.characterNotes,
            footballIQRevised: interview.footballIQ,
            medicalConcerns: newMedicalConcerns,
            workoutImpressions: workoutImpressions,
            teamFitScore: teamFit
        )
    }

    /// Generates 1-2 position-specific workout impressions for a Top-30 visit.
    private static func generateWorkoutImpressions(for position: Position, prospect: CollegeProspect) -> [String] {
        let positives: [String]
        let negatives: [String]
        switch position {
        case .QB:
            positives = ["Crisp ball placement", "Quick processing on whiteboard", "Clean throwing motion", "Velocity on intermediate routes"]
            negatives = ["Mechanics break down under pressure", "Slow second-read progression", "Footwork inconsistent"]
        case .WR:
            positives = ["Smooth route running", "Strong hands at the catch", "Crisp releases off press", "Adjusts well to off-target throws"]
            negatives = ["Drops at the catch point", "Lacks burst out of breaks", "Limited release package"]
        case .RB, .FB:
            positives = ["Patient runner with vision", "Strong contact balance", "Soft hands out of backfield"]
            negatives = ["Lacks burst through hole", "Pass protection needs work", "Limited route tree"]
        case .TE:
            positives = ["Reliable hands in traffic", "Functional in-line blocking", "Adjusts to ball in air"]
            negatives = ["Stiff in space", "Loses leverage as a blocker"]
        case .LT, .RT, .LG, .RG, .C:
            positives = ["Anchors well in pass pro", "Quick out of stance", "Plays with leverage"]
            negatives = ["Late hands in pass pro", "Struggles with second-level blocks", "Over-extends and lunges"]
        case .DE, .DT:
            positives = ["Active hands at point of attack", "Quick first step", "Diverse pass-rush plan"]
            negatives = ["Limited counter moves", "Plays high off the snap", "Loses gap integrity"]
        case .OLB, .MLB:
            positives = ["Reads keys quickly", "Smooth in coverage drops", "Sheds blocks well"]
            negatives = ["Late to trigger downhill", "Stiff hips in coverage"]
        case .CB:
            positives = ["Fluid hips in transition", "Sticky in press coverage", "Good ball skills at catch point"]
            negatives = ["Grabby downfield", "Bites on double moves", "Tackling inconsistent"]
        case .FS, .SS:
            positives = ["Range to the deep middle", "Aggressive downhill trigger", "Tackles in space"]
            negatives = ["Takes poor angles", "Coverage discipline lapses"]
        case .K, .P:
            positives = ["Consistent ball flight", "Good leg under pressure"]
            negatives = ["Inconsistent operation time", "Leg speed average"]
        }

        // Bias the impressions toward the prospect's true ability so high-overall prospects
        // skew positive, low-overall ones skew negative.
        let posValue = prospect.truePositionAttributes.overall
        let positiveWeight: Int
        if posValue >= 80 { positiveWeight = 80 }
        else if posValue >= 70 { positiveWeight = 60 }
        else if posValue >= 60 { positiveWeight = 45 }
        else { positiveWeight = 30 }

        var result: [String] = []
        let count = Int.random(in: 1...2)
        for _ in 0..<count {
            let pool = (Int.random(in: 1...100) <= positiveWeight) ? positives : negatives
            if let pick = pool.randomElement(), !result.contains(pick) {
                result.append(pick)
            }
        }
        if result.isEmpty, let p = positives.randomElement() {
            result.append(p)
        }
        return result
    }

    // MARK: - The Living Draft Market
    //
    // Everything below models the four months between the last college snap and
    // the draft as a MARKET rather than a static board: a January all-star week,
    // the combine, four mock-draft re-reads and the pre-draft medical attrition
    // that quietly rewrites the top of every real class. All of it is
    // deterministically seeded per (careerID, season) — reload a save, advance
    // the same phase, and the same men rise, fall and get hurt.

    /// Deterministic seed for one cycle event.
    ///
    /// Mixes the career UUID's raw bytes (FNV-1a — never `hashValue`, whose seed
    /// changes every launch), the season and a per-event salt, so the combine,
    /// the Showcase and the pro-day attrition each draw their own independent
    /// stream while staying reproducible across relaunches.
    static func cycleSeed(careerID: UUID?, season: Int, salt: UInt64) -> UInt64 {
        var mixed: UInt64 = 0xCBF2_9CE4_8422_2325
        if let careerID {
            withUnsafeBytes(of: careerID.uuid) { raw in
                for byte in raw {
                    mixed = (mixed ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
                }
            }
        }
        mixed = (mixed ^ UInt64(bitPattern: Int64(season))) &* 0x0000_0100_0000_01B3
        mixed = (mixed ^ salt) &* 0x0000_0100_0000_01B3
        return mixed
    }

    /// Salts for `cycleSeed` — one per cycle event, so two events in the same
    /// season never share a stream.
    enum CycleSalt {
        static let seniorBowl: UInt64      = 0x5E_4109_B0_17
        static let combineDrift: UInt64    = 0xC0_4B19_E0_D1
        static let mockDrift: UInt64       = 0x40_C1D2_A0_F7
        static let proDayAttrition: UInt64 = 0x94_0D47_A7_31
        static let declarations: UInt64    = 0xDE_C1A4_E0_5D
        static let proDayDrift: UInt64     = 0x9D_0DA7_D8_1F
        static let combineCharacter: UInt64 = 0xC4_A8AC_7E_11
        static let proDayCharacter: UInt64  = 0xC4_A8AC_7E_22
    }

    // MARK: - The League Pro-Day Circuit (task #78)

    /// What the league-wide pro-day circuit produced.
    struct ProDayCircuitResult {
        /// Prospects who finally posted numbers.
        let tested: Int
        /// The men the circuit covered — the population `proDayPressure` grades.
        let cohort: Set<UUID>
    }

    /// Runs every school's pro day for the prospects the combine left blank.
    ///
    /// The combine deliberately sends about one invitee in eight home without a
    /// number (`generateCombineResults` step 3) and every one of the five DNP
    /// reasons ends "…at his pro day". Nothing then held one: `simulateProDay`
    /// had been written, documented and never called from anywhere in the app,
    /// so the DNP cohort carried empty cells from February all the way to the
    /// draft and the `.proDays` phase was a calendar window with one event in it
    /// (the medical attrition pass).
    ///
    /// This is the league half of that phase, and it is deliberately the CHEAP
    /// half: the numbers become public — every club is at every pro day that
    /// matters — but `proDayCompleted` is left alone, so `ProspectFog` still
    /// only hands out broadcast-precision readings ("~4.5") to a club that did
    /// not go. `attendProDay` remains the paid trip that buys the decimals, a
    /// filed `.proDay` report and the flag-disclosure step.
    ///
    /// Idempotent by construction: the cohort is defined as "declared, no forty
    /// time", which this pass empties. Kickers and punters are excluded — they
    /// never had drills to miss.
    ///
    /// **The cohort is every declared man, not just combine invitees.** It used
    /// to carry an extra `combineInvite` clause, which made the circuit cover
    /// only the invitees the combine had sent home blank — so a declared
    /// non-invitee at a school nobody focused got no numbers at all and carried
    /// empty combine cells to the draft, while the pro-day screen told the user
    /// (correctly, per plan §5.5/§5.8) that "every club reads every pro day off
    /// the feed". Small-school pro days are exactly the ones scouts fly to; the
    /// distinction the design rations is PRECISION, not existence, and that
    /// distinction is `proDayCompleted` — still untouched here, so a club that
    /// stayed home reads "~4.5" through `ProspectFog.combineFidelity` while the
    /// club that travelled reads the decimal.
    ///
    /// - Returns: `nil` when there was nobody to test.
    @discardableResult
    static func runLeagueProDays(prospects: inout [CollegeProspect]) -> ProDayCircuitResult? {
        // Canonical UUID order: `WeekAdvancer.currentDraftClass` comes back from
        // an unsorted `FetchDescriptor`, and the drill draws are un-seeded, so
        // walking raw array order would at least make the *cohort* unstable.
        let cohortIndices = prospects.indices
            .filter { index in
                let p = prospects[index]
                return p.isDeclaringForDraft
                    && p.position != .K && p.position != .P
                    && p.fortyTime == nil
            }
            .sorted { prospects[$0].id.uuidString < prospects[$1].id.uuidString }
        guard !cohortIndices.isEmpty else { return nil }

        var cohort = Set<UUID>()
        for index in cohortIndices {
            simulateProDay(prospect: &prospects[index], markAttended: false)
            cohort.insert(prospects[index].id)
        }

        return ProDayCircuitResult(tested: cohortIndices.count, cohort: cohort)
    }

    /// Stock pressure out of the pro-day circuit — `combinePressure`'s sibling.
    ///
    /// Same shape (how a man tested against his own position group's class-year
    /// mean percentile) with two deliberate differences:
    ///
    /// * the position MEAN is taken over everybody who has tested, combine or
    ///   pro day, so the late testers are graded against the same bar the
    ///   February group set rather than against each other; and
    /// * the divisor is wider and the clamp tighter. A pro-day number is
    ///   hand-timed on a friendly surface, and every scouting department
    ///   discounts it — so the circuit is a nudge where the combine is a shove.
    ///
    /// Only `cohort` receives pressure: a man who ran in Indianapolis already
    /// had his stock moved by `combinePressure`, and grading him twice off one
    /// forty time would double-count the same information.
    static func proDayPressure(
        _ prospects: [CollegeProspect],
        cohort: Set<UUID>
    ) -> [UUID: Double] {
        guard !cohort.isEmpty else { return [:] }

        var percentileByIndex: [Int: Int] = [:]
        var byPosition: [Position: [Int]] = [:]
        for i in prospects.indices {
            guard prospects[i].fortyTime != nil else { continue }
            let pct = combineAveragePercentile(prospects[i])
            percentileByIndex[i] = pct
            byPosition[prospects[i].position, default: []].append(pct)
        }
        guard !percentileByIndex.isEmpty else { return [:] }

        var meanByPosition: [Position: Double] = [:]
        for (position, values) in byPosition where !values.isEmpty {
            meanByPosition[position] = Double(values.reduce(0, +)) / Double(values.count)
        }

        var pressure: [UUID: Double] = [:]
        for i in prospects.indices {
            guard cohort.contains(prospects[i].id), let pct = percentileByIndex[i] else { continue }
            let mean = meanByPosition[prospects[i].position] ?? 50.0
            pressure[prospects[i].id] = max(-1.8, min(1.8, (Double(pct) - mean) / 30.0))
        }
        return pressure
    }

    // MARK: - Mid-cycle character findings (task #78)

    /// One character flag that surfaced between the last college snap and the
    /// draft.
    struct CharacterFinding {
        let prospectID: UUID
        let name: String
        let position: String
        let college: String
        /// The flag as it was appended to `redFlags`.
        let flag: String
        /// His projected round when it broke — the reason it is a story.
        let projection: Int?
    }

    /// The two flag pools, split by the moment they can surface at.
    ///
    /// Splitting them is what makes each pass independently idempotent: the
    /// guard is "does anybody in this class already carry a flag from THIS
    /// pool", so a combine finding cannot suppress the pro-day pass and
    /// re-entering either phase cannot stack a second wave. Deliberately
    /// disjoint from `generateRiskProfile`'s generation-time pool for the same
    /// reason, and phrased as things that surface in FEBRUARY and MARCH rather
    /// than as things that were always on the file.
    static let combineCharacterFindings = [
        "Combine interview raised maturity questions",
        "Failed a screening at the combine",
        "Multiple clubs flagged his interview answers",
        "Suspended for the bowl game, never explained why",
        "Combine medical staff noted a missed rehab program"
    ]

    static let proDayCharacterFindings = [
        "Background check turned up an unresolved case",
        "Left his pro day early after a sideline argument",
        "Position coaches questioned his work habits on the record",
        "Two teammates declined to vouch for him",
        "Skipped a scheduled club visit without notice"
    ]

    /// Appends one new character flag to 2-4 declared prospects.
    ///
    /// The board has always carried `redFlags`, and every one of them was
    /// written at generation and never moved again — so a user who had read a
    /// prospect's file in September knew it could not change. Real character
    /// intel breaks in February and March, on the men whose interviews go badly
    /// and whose backgrounds get checked, and it is the single most common
    /// reason a projected first-rounder slides in a real draft.
    ///
    /// The flag lands in `redFlags` and is therefore revealed through the
    /// EXISTING `ProspectFog.flagDisclosure` ladder — hidden until somebody in
    /// your building has been near him, a count once they have, the text itself
    /// at two reports / an interview / a Top-30 visit. Nothing here bypasses the
    /// fog; it only gives it something new to disclose.
    ///
    /// Deterministic per `(careerID, season, phase)` and idempotent per pool.
    @discardableResult
    static func applyCharacterFindings(
        prospects: inout [CollegeProspect],
        pool: [String],
        seed: UInt64
    ) -> [CharacterFinding] {
        guard !prospects.isEmpty, !pool.isEmpty else { return [] }
        let poolSet = Set(pool)
        guard !prospects.contains(where: { p in
            (p.redFlags ?? []).contains { poolSet.contains($0) }
        }) else { return [] }

        // Canonical order before the seeded shuffle, for the same reason
        // `applyPreDraftAttrition` sorts first: the array order the store hands
        // back is not stable, so an unsorted draw would pick SLOTS, not men.
        let candidates = prospects.indices
            .filter { prospects[$0].isDeclaringForDraft }
            .sorted { prospects[$0].id.uuidString < prospects[$1].id.uuidString }
        guard candidates.count >= 40 else { return [] }

        var rng = ScoutingCycleRandom(seed: seed)
        let count = Int.random(in: 2...4, using: &rng)

        // Weighted toward the top of the PUBLIC board: a story is a story
        // because of where the man was projected, not because of who he is.
        // Two thirds of the draws come from the graded first four rounds.
        let early = candidates.filter { (prospects[$0].draftProjection ?? 8) <= 4 }
        let rest = candidates.filter { (prospects[$0].draftProjection ?? 8) > 4 }
        var earlyPool = early.shuffled(using: &rng)
        var restPool = rest.shuffled(using: &rng)

        var findings: [CharacterFinding] = []
        var flags = pool.shuffled(using: &rng)
        for slot in 0..<count {
            let preferEarly = slot < (count * 2 + 2) / 3
            let pick: Int?
            if preferEarly, !earlyPool.isEmpty {
                pick = earlyPool.removeLast()
            } else if !restPool.isEmpty {
                pick = restPool.removeLast()
            } else if !earlyPool.isEmpty {
                pick = earlyPool.removeLast()
            } else {
                pick = nil
            }
            guard let index = pick, !flags.isEmpty else { break }
            let flag = flags.removeLast()

            var existing = prospects[index].redFlags ?? []
            existing.append(flag)
            prospects[index].redFlags = existing

            findings.append(CharacterFinding(
                prospectID: prospects[index].id,
                name: prospects[index].fullName,
                position: prospects[index].position.rawValue,
                college: prospects[index].college,
                flag: flag,
                projection: prospects[index].draftProjection
            ))
        }
        return findings
    }

    // MARK: - Projection Drift (the zero-sum board)

    /// One prospect's move on the media board.
    struct ProjectionMove {
        let prospectID: UUID
        let name: String
        let position: String
        let college: String
        let from: Int
        let to: Int
        var isRise: Bool { to < from }
        var rounds: Int { abs(to - from) }
    }

    /// Moves `draftProjection` around the class in response to new public
    /// information, WITHOUT changing the shape of the class.
    ///
    /// The model is a **paired swap**: a riser only climbs into a band by taking
    /// the slot of a faller who was already in it, and the faller takes the
    /// riser's old band in exchange. Two consequences, both deliberate:
    ///
    /// * The multiset of `draftProjection` values over the class is *exactly*
    ///   preserved — same number of round-1 projections, same number of round-7
    ///   projections, before and after. `draftProjection` anchors AI perception
    ///   (`AIDraftPerception`) and the rookie-contract band fallbacks, so a
    ///   drift model that could inflate the round-1 population would quietly
    ///   re-tune the whole draft. This one provably cannot.
    /// * Every move is hard-bounded by `maxShift` rounds, because a pair is only
    ///   formed when the two men are within `maxShift` bands of each other. No
    ///   prospect who was not himself under pressure ever moves.
    ///
    /// - Parameters:
    ///   - pressure: signed per-prospect stock pressure; **positive = rising**
    ///     (toward round 1). Built by `combinePressure` / `mockConsensusPressure`
    ///     / the Showcase.
    ///   - maxShift: hard cap on how many rounds one prospect may move.
    ///   - maxPairs: cap on how many riser/faller swaps this moment may make.
    ///   - seed: deterministic per (careerID, season, event).
    @discardableResult
    static func applyProjectionDrift(
        prospects: inout [CollegeProspect],
        pressure: [UUID: Double],
        maxShift: Int,
        maxPairs: Int,
        seed: UInt64
    ) -> [ProjectionMove] {
        guard maxShift > 0, maxPairs > 0, !pressure.isEmpty, !prospects.isEmpty else { return [] }

        // Candidates are walked in index order (never dictionary order), but the
        // jitter each one gets is derived from HIS OWN UUID rather than drawn
        // off a stream consumed in that order. `WeekAdvancer.currentDraftClass`
        // is restored with an unsorted `FetchDescriptor`, so array order is not
        // stable across a relaunch: an rng walked in index order would bind each
        // draw to an array SLOT, and the same save advanced through the same
        // phase after a relaunch would jitter a different set of men. Deriving
        // it per-UUID makes the pass genuinely reproducible, which is what its
        // own header claims.
        struct Candidate { let idx: Int; let id: UUID; let projection: Int; let pressure: Double }
        var candidates: [Candidate] = []
        for i in prospects.indices {
            guard let projection = prospects[i].draftProjection, (1...7).contains(projection) else { continue }
            guard prospects[i].isDeclaringForDraft else { continue }
            guard let raw = pressure[prospects[i].id], raw != 0 else { continue }
            // Tiny jitter breaks ties between identical pressures without ever
            // flipping the sign or crossing the ±0.5 activation threshold.
            let mixed = cycleSeed(careerID: prospects[i].id, season: 0, salt: seed)
            let jitter = Double(mixed % 8_001) / 100_000.0 - 0.04
            candidates.append(Candidate(
                idx: i,
                id: prospects[i].id,
                projection: projection,
                pressure: raw + jitter
            ))
        }
        guard !candidates.isEmpty else { return [] }

        // UUID tie-break: `sorted(by:)` is not stable, so two men on identical
        // pressure would otherwise be ordered by the same array position the
        // jitter was just taken off.
        let risers = candidates.filter { $0.pressure >= 0.5 }.sorted {
            if $0.pressure != $1.pressure { return $0.pressure > $1.pressure }
            return $0.id.uuidString < $1.id.uuidString
        }
        var fallers = candidates.filter { $0.pressure <= -0.5 }.sorted {
            if $0.pressure != $1.pressure { return $0.pressure < $1.pressure }
            return $0.id.uuidString < $1.id.uuidString
        }
        guard !risers.isEmpty, !fallers.isEmpty else { return [] }

        var moves: [ProjectionMove] = []
        var pairs = 0

        for riser in risers {
            guard pairs < maxPairs else { break }
            // A riser can only climb into a band somebody is vacating, and only
            // if that band is within `maxShift` of where he already is.
            guard let matchPosition = fallers.firstIndex(where: { faller in
                faller.projection < riser.projection
                    && riser.projection - faller.projection <= maxShift
            }) else { continue }
            let faller = fallers.remove(at: matchPosition)

            prospects[riser.idx].draftProjection = faller.projection
            prospects[faller.idx].draftProjection = riser.projection
            pairs += 1

            moves.append(ProjectionMove(
                prospectID: prospects[riser.idx].id,
                name: prospects[riser.idx].fullName,
                position: prospects[riser.idx].position.rawValue,
                college: prospects[riser.idx].college,
                from: riser.projection,
                to: faller.projection
            ))
            moves.append(ProjectionMove(
                prospectID: prospects[faller.idx].id,
                name: prospects[faller.idx].fullName,
                position: prospects[faller.idx].position.rawValue,
                college: prospects[faller.idx].college,
                from: faller.projection,
                to: riser.projection
            ))
        }

        return moves
    }

    /// Stock pressure out of the combine: how a man tested against **his own
    /// position group's** class-year mean percentile, not against the field.
    ///
    /// `combineAveragePercentile` is already position-relative, so the position
    /// mean would normally sit near 50; taking the real per-position mean of
    /// *this* class keeps the read honest for a class that happens to be
    /// stacked (or thin) at a position.
    ///
    /// +25 percentile points over the position mean ≈ one round of pressure.
    static func combinePressure(_ prospects: [CollegeProspect]) -> [UUID: Double] {
        var percentileByIndex: [Int: Int] = [:]
        var byPosition: [Position: [Int]] = [:]
        for i in prospects.indices {
            guard prospects[i].combineInvite, prospects[i].fortyTime != nil else { continue }
            let pct = combineAveragePercentile(prospects[i])
            percentileByIndex[i] = pct
            byPosition[prospects[i].position, default: []].append(pct)
        }
        guard !percentileByIndex.isEmpty else { return [:] }

        var meanByPosition: [Position: Double] = [:]
        for (position, values) in byPosition where !values.isEmpty {
            meanByPosition[position] = Double(values.reduce(0, +)) / Double(values.count)
        }

        var pressure: [UUID: Double] = [:]
        for i in prospects.indices {
            guard let pct = percentileByIndex[i] else { continue }
            let mean = meanByPosition[prospects[i].position] ?? 50.0
            let delta = (Double(pct) - mean) / 25.0
            pressure[prospects[i].id] = max(-2.5, min(2.5, delta))
        }
        return pressure
    }

    /// Stock pressure out of a freshly regenerated mock draft: the market's own
    /// re-read of a man against the round his projection still says he is.
    ///
    /// Deliberately weaker than the combine read — a mock is one analyst's
    /// board, not a stopwatch — which is what makes the four mock moments a
    /// *nudge* and the combine a shove.
    static func mockConsensusPressure(_ prospects: [CollegeProspect]) -> [UUID: Double] {
        // How deep the mock actually went. `generateMockDraft` builds THREE
        // rounds (96 picks) — it filters `draftPicks` to `round 1...3` and its
        // no-picks fallback loops `for round in 1...3`. Reading the depth off
        // the class rather than hardcoding it keeps this honest if the mock is
        // ever lengthened.
        let deepestMockPick = prospects.compactMap(\.mockDraftPickNumber).filter { $0 > 0 }.max()
        let coveredRounds = deepestMockPick.map { min(7, ($0 - 1) / 32 + 1) } ?? 3

        var pressure: [UUID: Double] = [:]
        for prospect in prospects {
            guard let projection = prospect.draftProjection, (1...7).contains(projection) else { continue }
            guard prospect.isDeclaringForDraft else { continue }
            if let pick = prospect.mockDraftPickNumber, pick > 0 {
                let impliedRound = min(7, (pick - 1) / 32 + 1)
                pressure[prospect.id] = max(-1.2, min(1.2, Double(projection - impliedRound) * 0.7))
            } else if projection <= coveredRounds {
                // He was projected INSIDE the mock's coverage and the mock still
                // did not call his name — that is the whole signal. The old test
                // was `projection <= 5`, but a man projected round 4 or 5 is
                // structurally incapable of appearing in a three-round mock, so
                // every day-three prospect in the class took a flat -0.7 at all
                // four mock moments, forever. The faller list was then a crowd
                // of identical -0.7s separated only by jitter, i.e. by nothing.
                //
                // Scaled by how deep inside coverage he was: missing a 96-pick
                // mock as a projected first-rounder is a much louder fall than
                // missing it as a projected third-rounder, and the scale keeps
                // the band tie-free.
                let missDepth = Double(coveredRounds - projection + 1) / Double(coveredRounds)
                pressure[prospect.id] = -1.2 * missDepth
            }
        }
        return pressure
    }

    // MARK: - Showcase (January)

    /// What the Showcase week produced.
    struct SeniorBowlResult {
        struct Note {
            let prospectID: UUID
            let name: String
            let position: String
            let college: String
            let headline: String
            let body: String
            let isRiser: Bool
        }
        let invitees: Int
        let reportsFiled: Int
        let notes: [Note]
        /// Feeds `applyProjectionDrift` — the practice week moves stock.
        let pressure: [UUID: Double]
    }

    /// Runs the January all-star week: ~110 senior invitees, a practice-week
    /// evaluation on all of them, filed `.seniorBowl` reports on the subset the
    /// week actually exposed, and 2-4 named stories.
    ///
    /// The Showcase is a televised league event like the combine, so it runs
    /// whether or not this club sends anybody — attendance only decides *whose
    /// name* is on the report. `ScoutingPhase.seniorBowl` already carried the
    /// 0.55 confidence level and its slot in the phase sort order; this is the
    /// event that finally files one.
    ///
    /// Idempotent: a class that already carries a `.seniorBowl` report is left
    /// alone, so re-entering the phase cannot stack a second week onto it.
    ///
    /// - Returns: `nil` when the week did not run (no class, too few seniors, or
    ///   already held).
    static func runSeniorBowl(
        prospects: inout [CollegeProspect],
        scouts: [Scout],
        seed: UInt64
    ) -> SeniorBowlResult? {
        guard !prospects.isEmpty else { return nil }
        guard !prospects.contains(where: { p in
            p.scoutingReports.contains { $0.phase == .seniorBowl }
        }) else { return nil }

        // Invite list = the best SENIORS on the PUBLIC board. Underclassmen are
        // not eligible for the game, which is exactly why the week matters: it
        // is the one place the senior half of the class is graded head to head.
        let seniorAge = 22
        let eligible = prospects.indices.filter {
            prospects[$0].age >= seniorAge && prospects[$0].isDeclaringForDraft
        }
        guard eligible.count >= 40 else { return nil }

        let board = eligible.sorted { a, b in
            let pa = prospects[a].draftProjection ?? 8
            let pb = prospects[b].draftProjection ?? 8
            if pa != pb { return pa < pb }
            let oa = prospects[a].scoutedOverall ?? 0
            let ob = prospects[b].scoutedOverall ?? 0
            if oa != ob { return oa > ob }
            return prospects[a].id.uuidString < prospects[b].id.uuidString
        }
        let invited = Array(board.prefix(110))

        // Practice-week score. The week rewards the things an all-star practice
        // actually exposes — competitiveness against real bodies and how NFL-
        // ready the technique is — more than raw talent, which is why it
        // reorders boards at all.
        var rng = ScoutingCycleRandom(seed: seed)
        var scoreByIndex: [Int: Double] = [:]
        for i in invited {
            let p = prospects[i]
            let base = 0.40 * Double(p.trueCompetitiveness)
                     + 0.30 * Double(p.nflReadiness)
                     + 0.30 * Double(p.trueOverall)
            scoreByIndex[i] = base + Double.random(in: -14.0...14.0, using: &rng)
        }
        let scores = invited.compactMap { scoreByIndex[$0] }
        let mean = scores.reduce(0, +) / Double(scores.count)

        var pressure: [UUID: Double] = [:]
        for i in invited {
            guard let score = scoreByIndex[i] else { continue }
            pressure[prospects[i].id] = max(-1.5, min(1.5, (score - mean) / 16.0))
        }

        // Reports land on what the week actually showed: the practice standouts
        // and the men who were exposed. The middle of the field goes home the
        // way it arrived.
        let ranked = invited.sorted { (scoreByIndex[$0] ?? 0) > (scoreByIndex[$1] ?? 0) }
        var visible = Array(ranked.prefix(18))
        visible.append(contentsOf: ranked.suffix(8))

        let broadcastEvaluator = UUID(uuidString: "5E410B0B-0000-4000-A000-000000000001")
            ?? UUID()

        // EXPLICIT BALANCE DECISION, not a side effect of the news feature.
        //
        // The week files 26 reports (18 practice winners + 8 exposed, ~9 % of
        // the declared class) on every club, charged to no budget and gated on
        // no assignment. That is deliberate — Mobile is televised and all 32
        // clubs are in the building — but it must not be a cheap substitute for
        // the department you actually pay for. So the reports carry ONE fixed
        // evaluator accuracy for everybody: no per-scout accuracy, no chief
        // bonus, no scaling with staff size. Your scouts' name goes on the
        // report for flavour; the club with the best staff gets exactly the same
        // read from Showcase week as the club with none, and buys its edge
        // with the weekly assignments it is charged for.
        let eventAccuracy = 58
        var filed = 0
        for (n, i) in visible.enumerated() {
            let scoutName: String
            let scoutID: UUID
            let accuracy = eventAccuracy
            if scouts.isEmpty {
                scoutID = broadcastEvaluator
                scoutName = "Showcase Practices"
            } else {
                let scout = scouts[n % scouts.count]
                scoutID = scout.id
                scoutName = scout.fullName
            }

            let p = prospects[i]
            let maxError = max(1, 26 - accuracy * 26 / 100)
            let ovr = min(99, max(1, p.trueOverall + Int.random(in: -maxError...maxError, using: &rng)))
            let potError = maxError + 4
            let pot = min(99, max(ovr, p.truePotential + Int.random(in: -potError...potError, using: &rng)))

            let report = ScoutingReport(
                prospectID: p.id,
                scoutID: scoutID,
                scoutName: scoutName,
                date: "The Showcase",
                phase: .seniorBowl,
                overallGrade: ovr,
                potentialGrade: pot,
                strengthNotes: generateStrengthNotes(for: p, accuracy: accuracy),
                weaknessNotes: generateWeaknessNotes(for: p, accuracy: accuracy),
                personalityNotes: nil,
                confidenceLevel: ScoutingPhase.seniorBowl.confidenceLevel,
                productionNotes: "Showcase week: \(n < 18 ? "graded out as a practice winner" : "struggled in one-on-ones")",
                overallLetterGrade: LetterGrade.from(numericValue: ovr)
            )
            applyReport(report: report, to: prospects[i])
            filed += 1
        }

        // 2-4 named stories: the week's winners, and the highly projected senior
        // it went badly for.
        var notes: [SeniorBowlResult.Note] = []
        for i in ranked.prefix(2) where (pressure[prospects[i].id] ?? 0) >= 0.7 {
            let p = prospects[i]
            notes.append(SeniorBowlResult.Note(
                prospectID: p.id,
                name: p.fullName,
                position: p.position.rawValue,
                college: p.college,
                headline: "\(p.college) \(p.position.rawValue) \(p.fullName) owns Showcase week",
                body: "\(p.fullName) was the most consistent winner of the week in Mobile, stacking reps against the best senior competition in the class. Scouts who came for somebody else left writing his name down.",
                isRiser: true
            ))
        }
        for i in ranked.reversed().prefix(6)
        where (pressure[prospects[i].id] ?? 0) <= -0.7 && (prospects[i].draftProjection ?? 8) <= 4 {
            guard notes.filter({ !$0.isRiser }).count < 2 else { break }
            let p = prospects[i]
            notes.append(SeniorBowlResult.Note(
                prospectID: p.id,
                name: p.fullName,
                position: p.position.rawValue,
                college: p.college,
                headline: "Rough week in Mobile for \(p.college) \(p.position.rawValue) \(p.fullName)",
                body: "\(p.fullName) arrived with a top-\(max(1, (prospects[i].draftProjection ?? 4) * 32)) projection and spent three days getting beaten in one-on-ones. Nobody drops a man off a board for one practice week, but the tape will be re-checked.",
                isRiser: false
            ))
        }

        return SeniorBowlResult(
            invitees: invited.count,
            reportsFiled: filed,
            notes: notes,
            pressure: pressure
        )
    }

    // MARK: - Pre-Draft Attrition (Pro Days)

    /// A prospect whose spring went wrong.
    struct PreDraftSetback {
        let prospectID: UUID
        let name: String
        let position: String
        let college: String
        let injury: String
        let weeksOut: Int
        let severity: Int
        let concern: String
        let projectionFrom: Int?
        let projectionTo: Int?
    }

    /// Marker every pre-draft medical note carries, so the pass can tell its own
    /// work from the generator's `generateRiskProfile` notes and stay idempotent.
    static let preDraftConcernPrefix = "Pre-draft: "

    /// A pre-draft injury, decoded back out of the note the attrition pass wrote.
    struct PreDraftInjuryCarry {
        let type: InjuryType
        /// Weeks the medical staff projected on the day it happened.
        let weeksOut: Int
        /// The note itself, for the news/inbox copy.
        let concern: String
    }

    /// Weeks between the pro-day window (where `applyPreDraftAttrition` fires)
    /// and the first day of training camp.
    ///
    /// The offseason calendar this game runs is `proDays → draft → OTAs →
    /// trainingCamp`; in real months that is late March to late July. A knee
    /// that cost 14 weeks in March is a man who limps into camp; a 3-week
    /// hamstring is a line on his file and nothing else. This constant is what
    /// makes the difference between the two survive the draft boundary
    /// (finding S15).
    static let preDraftToCampWeeks = 8

    /// Reads a pre-draft setback back off a prospect's medical file.
    ///
    /// The attrition pass writes `"Pre-draft: {InjuryType.rawValue} —
    /// {n}-week recovery"`; this is the inverse, so `DraftEngine`'s
    /// prospect → player copy can carry the injury into the roster instead of
    /// dropping it at the draft boundary — the prospect who tore a knee at his
    /// pro day used to arrive at camp perfectly healthy with a scouting note
    /// nobody would ever read again.
    ///
    /// Returns the WORST concern on file when there is more than one.
    static func preDraftInjury(from concerns: [String]?) -> PreDraftInjuryCarry? {
        guard let concerns else { return nil }
        var best: PreDraftInjuryCarry?
        for concern in concerns where concern.hasPrefix(preDraftConcernPrefix) {
            let body = String(concern.dropFirst(preDraftConcernPrefix.count))
            let parts = body.components(separatedBy: " \u{2014} ")
            guard parts.count == 2, let type = InjuryType(rawValue: parts[0]) else { continue }
            let weeks = Int(parts[1].prefix(while: { $0.isNumber })) ?? 0
            guard weeks > 0 else { continue }
            let carry = PreDraftInjuryCarry(type: type, weeksOut: weeks, concern: concern)
            if let current = best {
                let better = type.severity > current.type.severity
                    || (type.severity == current.type.severity && weeks > current.weeksOut)
                if better { best = carry }
            } else {
                best = carry
            }
        }
        return best
    }

    /// About 2 % of the declared class gets hurt between the combine and the
    /// draft — a torn ACL in a pro-day drill, a labrum found on a recheck, a
    /// hamstring pulled running for a stopwatch. It is the single most reliable
    /// thing that happens to a real draft class every spring and the board here
    /// used to be frozen from February to April.
    ///
    /// Uses the `MedicalEngine` vocabulary (`InjuryType` and its own recovery
    /// bands) so a pre-draft knee reads exactly like an in-season knee, stamps
    /// the note into `medicalConcerns`, and knocks the man's projection down by
    /// the severity of what he did.
    ///
    /// Deliberately NOT zero-sum, unlike `applyProjectionDrift`: an injury
    /// genuinely removes value from the class rather than moving it between two
    /// men. Bounded at ~2 % of the declared pool so the class-quality
    /// distribution moves by at most a few prospects.
    ///
    /// Idempotent — a class that already carries a pre-draft concern is skipped.
    @discardableResult
    static func applyPreDraftAttrition(
        prospects: inout [CollegeProspect],
        seed: UInt64
    ) -> [PreDraftSetback] {
        guard !prospects.isEmpty else { return [] }
        guard !prospects.contains(where: { p in
            (p.medicalConcerns ?? []).contains { $0.hasPrefix(preDraftConcernPrefix) }
        }) else { return [] }

        // Canonical order BEFORE the seeded shuffle. `WeekAdvancer
        // .currentDraftClass` is restored with an unsorted `FetchDescriptor`,
        // so the raw index list is in whatever order the store handed back:
        // shuffling it made the seed pick array SLOTS rather than men, and the
        // same save advanced through pro days after a relaunch hurt a different
        // six prospects. Sorting by UUID first makes the draw depend only on
        // (seed, set of declared prospects), which is what this pass claims.
        let declared = prospects.indices
            .filter { prospects[$0].isDeclaringForDraft }
            .sorted { prospects[$0].id.uuidString < prospects[$1].id.uuidString }
        guard declared.count >= 50 else { return [] }

        var rng = ScoutingCycleRandom(seed: seed)
        let count = max(1, Int((Double(declared.count) * 0.02).rounded()))

        // Draw without replacement from a seeded shuffle of the declared pool.
        let pool = declared.shuffled(using: &rng)
        var setbacks: [PreDraftSetback] = []

        for idx in pool.prefix(count) {
            let injury = InjuryType.allCases.randomElement(using: &rng) ?? .hamstring
            // Spring injuries are the ones that happen at full speed with no
            // game to protect: take the upper half of the medical band.
            let band = injury.baseRecoveryWeeks
            let floor = band.lowerBound + (band.upperBound - band.lowerBound) / 2
            let weeksOut = Int.random(in: floor...band.upperBound, using: &rng)

            let concern = "\(preDraftConcernPrefix)\(injury.rawValue) — \(weeksOut)-week recovery"
            var concerns = prospects[idx].medicalConcerns ?? []
            concerns.append(concern)
            prospects[idx].medicalConcerns = concerns

            // The projection knock scales with what the medical staff will find.
            let knock: Int
            switch injury.severity {
            case 4:  knock = 3
            case 3:  knock = 2
            case 2:  knock = 1
            default: knock = weeksOut >= 4 ? 1 : 0
            }
            let from = prospects[idx].draftProjection
            if let from, knock > 0 {
                prospects[idx].draftProjection = min(7, from + knock)
            }

            setbacks.append(PreDraftSetback(
                prospectID: prospects[idx].id,
                name: prospects[idx].fullName,
                position: prospects[idx].position.rawValue,
                college: prospects[idx].college,
                injury: injury.rawValue,
                weeksOut: weeksOut,
                severity: injury.severity,
                concern: concern,
                projectionFrom: from,
                projectionTo: prospects[idx].draftProjection
            ))
        }

        // Most-serious first — the news and the inbox both lead with the worst.
        return setbacks.sorted {
            if $0.severity != $1.severity { return $0.severity > $1.severity }
            return ($0.projectionFrom ?? 8) < ($1.projectionFrom ?? 8)
        }
    }

    // MARK: - Weekly Scouting Digest

    /// A snapshot of what the department knew about one prospect.
    struct GradeSnapshot {
        let grade: String?
        let reportCount: Int
        /// Width of the public grade band in letter steps; `nil` when no band
        /// has been established yet.
        let bandWidth: Int?
    }

    /// Captures the current read on every prospect, so the week's reports can be
    /// diffed against it.
    static func gradeSnapshot(_ prospects: [CollegeProspect]) -> [UUID: GradeSnapshot] {
        var snapshot: [UUID: GradeSnapshot] = [:]
        for prospect in prospects {
            let width = prospect.scoutedOverallGrade.map { $0.high.rank - $0.low.rank }
            snapshot[prospect.id] = GradeSnapshot(
                grade: prospect.scoutGrade,
                reportCount: prospect.scoutingReports.count,
                bandWidth: width
            )
        }
        return snapshot
    }

    /// What one week of regional scouting actually changed.
    struct WeeklyScoutingDigest {
        let week: Int
        let reportCount: Int
        let prospectsCovered: Int
        let firstLooks: Int
        let bandsNarrowed: Int
        /// The biggest single grade move, if any: (name, position, old, new).
        let headline: (name: String, position: String, from: String, to: String)?
        let headlineIsRise: Bool
    }

    /// Diffs the post-report board against a pre-report snapshot.
    ///
    /// Returns `nil` for a week that changed nothing, so the caller can skip the
    /// message entirely rather than mail an empty one.
    static func weeklyDigest(
        prospects: [CollegeProspect],
        before: [UUID: GradeSnapshot],
        week: Int
    ) -> WeeklyScoutingDigest? {
        var reportCount = 0
        var covered = 0
        var firstLooks = 0
        var narrowed = 0
        var bestMove: (name: String, position: String, from: String, to: String)?
        var bestDelta = 0
        var bestIsRise = false

        for prospect in prospects {
            guard let old = before[prospect.id] else { continue }
            let newReports = prospect.scoutingReports.count - old.reportCount
            guard newReports > 0 else { continue }
            reportCount += newReports
            covered += 1
            if old.reportCount == 0 { firstLooks += 1 }

            // "Narrowed" spans both grade systems on purpose. The GradeRange
            // band tightens on the report paths that run `applyGradeBasedFields`
            // (combine / pro day / workout / top-30); the weekly in-season pass
            // firms a read up the older way, by stacking reports — which is
            // exactly what `ProspectFog.confidenceDots` and the card's
            // confidence band show the user. Either counts, and a prospect we
            // had never seen before
            // does not (he is a `firstLook`, not a tightened read).
            if old.reportCount > 0 {
                let newWidth = prospect.scoutedOverallGrade.map { $0.high.rank - $0.low.rank }
                let widthShrank = (newWidth != nil && old.bandWidth != nil && newWidth! < old.bandWidth!)
                let confidenceTierRose = min(prospect.scoutingReports.count, 3) > min(old.reportCount, 3)
                if widthShrank || confidenceTierRose { narrowed += 1 }
            }

            if let from = old.grade, let to = prospect.scoutGrade, from != to,
               let fromGrade = LetterGrade(rawValue: from), let toGrade = LetterGrade(rawValue: to) {
                let delta = abs(toGrade.rank - fromGrade.rank)
                if delta > bestDelta {
                    bestDelta = delta
                    bestIsRise = toGrade.rank > fromGrade.rank
                    bestMove = (prospect.fullName, prospect.position.rawValue, from, to)
                }
            }
        }

        guard reportCount > 0 else { return nil }
        return WeeklyScoutingDigest(
            week: week,
            reportCount: reportCount,
            prospectsCovered: covered,
            firstLooks: firstLooks,
            bandsNarrowed: narrowed,
            headline: bestMove,
            headlineIsRise: bestIsRise
        )
    }
}

// MARK: - Seeded RNG

/// SplitMix64 — the deterministic stream every cycle event draws from.
///
/// Seeded through `ScoutingEngine.cycleSeed(careerID:season:salt:)`, never from
/// `hashValue` (whose seed changes every launch, which would make "deterministic
/// per career-season" true only until the next relaunch).
private struct ScoutingCycleRandom: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - Combine Benchmarks

struct CombineBenchmarks {
    struct DrillBenchmark {
        let elite: Double
        let average: Double
        let poor: Double
        let lowerIsBetter: Bool  // true for timed drills
    }

    struct PositionBenchmarks {
        let fortyYard: DrillBenchmark
        let benchPress: DrillBenchmark
        let verticalJump: DrillBenchmark
        let broadJump: DrillBenchmark
        let threeCone: DrillBenchmark
        let shuttle: DrillBenchmark
    }

    // All-time records
    static let records = (
        fortyYard: (value: 4.21, name: "Xavier Worthy", year: 2024),
        benchPress: (value: 49, name: "Stephen Paea", year: 2011),
        verticalJump: (value: 46.0, name: "Gerald Sensabaugh", year: 2005),
        broadJump: (value: 147, name: "Byron Jones", year: 2015),
        threeCone: (value: 6.28, name: "Jordan Thomas", year: 2018),
        shuttle: (value: 3.75, name: "Dunta Robinson", year: 2004)
    )

    /// Per-position drill benchmarks, derived from the SAME distribution the
    /// generator draws combine results from (`ScoutingEngine.CombineDrillTable`,
    /// `DRAFT_NFL_REFERENCE.md` §5) instead of a hand-written all-time-outlier
    /// table.
    ///
    /// `percentile(value:benchmark:)` maps `average` → 50, `elite` → 95 and
    /// `poor` → 15, so the three anchors have to BE those percentiles of the
    /// generated distribution: `mean`, `mean ± 1.645σ` and `mean ∓ 1.036σ`.
    /// The previous table anchored `elite` on record-flirting values the
    /// ±3σ-truncated generator can no longer reach (CB broad 147" vs a 139"
    /// generated max), which compressed the whole top half of every percentile
    /// — the class's best athlete graded ~72 and the combine-media "Stock
    /// Riser" / "Surprise" gates (≥70 / ≥75) were unreachable.
    ///
    /// Measured over 60 classes after the re-anchor: drill results at the "gold"
    /// ≥90 tier 0.31 % → 4.4 %, combine average p99 72 → 85, and the media gates
    /// produce 7.3 Stock-Riser and 0.8 Surprise candidates per class (was 0.03
    /// and 0.00).
    static func benchmarks(for position: Position) -> PositionBenchmarks {
        let drills = ScoutingEngine.CombineDrillTable.drills(for: position)
        return PositionBenchmarks(
            fortyYard: benchmark(from: drills.forty),
            benchPress: benchmark(from: drills.bench),
            verticalJump: benchmark(from: drills.vertical),
            broadJump: benchmark(from: drills.broad),
            threeCone: benchmark(from: drills.cone),
            shuttle: benchmark(from: drills.shuttle)
        )
    }

    /// 95th / 50th / 15th percentile of a drill's `N(mean, sd)` draw, clamped to
    /// the drill's own truncation range so no anchor sits outside what the
    /// generator can produce.
    private static func benchmark(from drill: ScoutingEngine.CombineDrill) -> DrillBenchmark {
        let z95 = 1.645
        let z15 = 1.036
        let elite = drill.lowerIsBetter ? drill.mean - z95 * drill.sd : drill.mean + z95 * drill.sd
        let poor = drill.lowerIsBetter ? drill.mean + z15 * drill.sd : drill.mean - z15 * drill.sd
        func clamped(_ value: Double) -> Double {
            min(drill.range.upperBound, max(drill.range.lowerBound, value))
        }
        return DrillBenchmark(
            elite: clamped(elite),
            average: clamped(drill.mean),
            poor: clamped(poor),
            lowerIsBetter: drill.lowerIsBetter
        )
    }

    /// Calculate percentile (0-100) for a drill value at a position.
    static func percentile(value: Double, benchmark: DrillBenchmark) -> Int {
        if benchmark.lowerIsBetter {
            // Lower is better (timed drills): elite=95th, avg=50th, poor=15th
            if value <= benchmark.elite {
                return min(99, Int(95 + (benchmark.elite - value) / 0.05 * 2))
            }
            if value <= benchmark.average {
                return 50 + Int(45 * (benchmark.average - value) / (benchmark.average - benchmark.elite))
            }
            if value <= benchmark.poor {
                return 15 + Int(35 * (benchmark.poor - value) / (benchmark.poor - benchmark.average))
            }
            return max(1, Int(15 * (benchmark.poor + 0.3 - value) / 0.3))
        } else {
            // Higher is better (bench, jumps)
            if value >= benchmark.elite {
                return min(99, Int(95 + (value - benchmark.elite) / 2.0 * 2))
            }
            if value >= benchmark.average {
                return 50 + Int(45 * (value - benchmark.average) / (benchmark.elite - benchmark.average))
            }
            if value >= benchmark.poor {
                return 15 + Int(35 * (value - benchmark.poor) / (benchmark.average - benchmark.poor))
            }
            return max(1, Int(15 * value / benchmark.poor))
        }
    }

    /// Color for a percentile value.
    static func percentileColor(_ pct: Int) -> String {
        if pct >= 90 { return "gold" }
        if pct >= 70 { return "green" }
        if pct >= 40 { return "white" }
        return "orange"
    }
}
