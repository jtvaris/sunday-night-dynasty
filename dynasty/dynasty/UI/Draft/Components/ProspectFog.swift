import SwiftUI

/// Draft-room scouting fog — the one place that answers "how good does the user
/// get to *think* this prospect is".
///
/// Before this pass the live Big Board and the pick sheet printed
/// `prospect.trueOverall` (93 / 90 / 89 …) straight onto the screen. A save with
/// 0/8 scouts hired and 0 % of the class scouted read the board exactly as well
/// as a save that had scouted all spring, so "never scout" was the dominant
/// strategy — while the War Room's Best Available panel, two inches to the
/// right, correctly showed "?" for the same men.
///
/// Everything rendered through `ProspectFog` comes from one of two legitimate
/// sources:
///
/// * **Your scouts** — `CollegeProspect.effectiveOverallGrade`, the progressive
///   `GradeRange` the season-long Big Board and the War Room already use. One
///   report is a wide band; each further report (and the combine / interview /
///   pro day work behind `DraftIntel.scoutConfidence`) narrows it.
/// * **The media consensus** — `draftProjection`, the projected round every
///   prospect carries out of `DraftClassBuilder`. Public information, and
///   deliberately blunt: a whole round maps to one very wide band.
///
/// `trueOverall` never reaches a view again. The AI keeps drafting on the true
/// values internally (`DraftEngine.aiMakePick`, `DraftDayCoordinator`'s pick
/// grades) — this is a user-information change, not a nerf to pick quality.
enum ProspectFog {

    // MARK: - Source

    /// Where a rendered band came from. Drives its tint, so the user can tell
    /// his own scouting apart from the media's guesswork at a glance.
    enum Source {
        /// Your building has filed on him.
        case scouts
        /// Nobody has — this is the projected round, nothing more.
        case media
        /// Not even a projection.
        case none

        var tint: Color {
            switch self {
            case .scouts: return Color.accentGold
            case .media:  return Color.textTertiary
            case .none:   return Color.textTertiary
            }
        }

        var label: String {
            switch self {
            case .scouts: return "Scouts"
            case .media:  return "Media"
            case .none:   return "No intel"
            }
        }
    }

    // MARK: - Read

    /// What the user is allowed to know about one prospect's overall grade.
    struct Read {
        let band: GradeRange?
        let source: Source

        /// "B+" when the scouts have converged, "B-/A-" while they haven't,
        /// "—" when there is nothing to say.
        var text: String { band?.displayText ?? "—" }

        /// Fog-safe sort key (higher = better). Ordering by this instead of by
        /// `trueOverall` is what stops the board leaking through the sort.
        var rank: Int { band?.midGrade.rank ?? 0 }

        /// Prefixed form for prose contexts ("Scouts B+", "Media C+/A-").
        var labelledText: String {
            guard band != nil else { return source.label }
            return "\(source.label) \(text)"
        }

        var accessibilityText: String {
            guard let band else { return "no scouting intel" }
            if band.isSingleGrade {
                return "\(source.label) grade \(band.low.rawValue)"
            }
            return "\(source.label) grade between \(band.low.rawValue) and \(band.high.rawValue)"
        }
    }

    /// The user-facing read on a prospect. Scouted grade first, media
    /// projection as the fallback, nothing at all as the floor.
    static func read(_ prospect: CollegeProspect) -> Read {
        if let scouted = prospect.effectiveOverallGrade {
            let confidence = DraftIntel.scoutConfidence(for: prospect)
            return Read(band: widened(scouted, confidence: confidence), source: .scouts)
        }
        if let consensus = consensusBand(for: prospect) {
            return Read(band: consensus, source: .media)
        }
        return Read(band: nil, source: .none)
    }

    /// Convenience for sort closures.
    static func rank(_ prospect: CollegeProspect) -> Int { read(prospect).rank }

    // MARK: - Measurables

    /// Height / weight / 40 times are public the moment a man runs them in
    /// front of 32 clubs — but only then. A prospect with no combine invite, no
    /// pro day and no report filed has no measurables the user could know.
    static func showsMeasurables(_ prospect: CollegeProspect) -> Bool {
        prospect.combineInvite
            || prospect.proDayCompleted
            || !prospect.scoutingReports.isEmpty
    }

    // MARK: - Combine fidelity

    /// How precisely the user may read one prospect's combine card.
    ///
    /// The combine is televised: a club that sends nobody to Indianapolis still
    /// learns that the receiver ran "about a four-five", because the broadcast
    /// said so. What it does not get is the hand-checked stopwatch sheet, the
    /// position-drill session, or the percentile the analytics staff would have
    /// run off it. That is the whole shape of `Send Scouts to the Combine`:
    /// attending buys **precision**, not access.
    enum MeasurableFidelity {
        /// Your own people were in the building — or have already worked this
        /// man out somewhere else, which beats the broadcast either way.
        case full
        /// You watched it on television with everybody else. The numbers are
        /// real; the decimals are not yours to have.
        case broadcast
    }

    /// The fidelity the open save is entitled to for `prospect`.
    ///
    /// `scoutsAttended` defaults to the career-scoped combine flag so a view can
    /// call this without threading the decision through every initialiser; pass
    /// it explicitly in previews and tests.
    static func combineFidelity(
        for prospect: CollegeProspect,
        scoutsAttended: Bool = CareerScopedDefaults.bool("scoutsSentToCombine")
    ) -> MeasurableFidelity {
        if scoutsAttended { return .full }
        // Work your own building has already done on this man outranks the
        // broadcast: a pro day or a filed report means somebody held the watch.
        if prospect.proDayCompleted || !prospect.scoutingReports.isEmpty { return .full }
        return .broadcast
    }

    /// Percentile / tier labels imply a precision the broadcast never had, so
    /// they are suppressed alongside the decimals rather than computed off a
    /// rounded number.
    static func showsPercentile(_ fidelity: MeasurableFidelity) -> Bool {
        fidelity == .full
    }

    /// Rounds `value` to the nearest `step` (0.1 s, 5 reps, 2 inches …).
    private static func snapped(_ value: Double, to step: Double) -> Double {
        (value / step).rounded() * step
    }

    /// Approximate values are prefixed rather than annotated: the combine table
    /// is a 60 pt column, and "~4.5" says it in one glyph.
    private static func approx(_ text: String) -> String { "~\(text)" }

    static func fortyText(_ value: Double?, fidelity: MeasurableFidelity, unit: String = "") -> String? {
        guard let value else { return nil }
        switch fidelity {
        case .full:      return String(format: "%.2f", value) + unit
        case .broadcast: return approx(String(format: "%.1f", snapped(value, to: 0.1)) + unit)
        }
    }

    static func benchText(_ value: Int?, fidelity: MeasurableFidelity, unit: String = "") -> String? {
        guard let value else { return nil }
        switch fidelity {
        case .full:      return "\(value)" + unit
        case .broadcast: return approx("\(Int(snapped(Double(value), to: 5)))" + unit)
        }
    }

    static func verticalText(_ value: Double?, fidelity: MeasurableFidelity, unit: String = "\u{22}") -> String? {
        guard let value else { return nil }
        switch fidelity {
        case .full:      return String(format: "%.1f", value) + unit
        case .broadcast: return approx(String(format: "%.0f", snapped(value, to: 2)) + unit)
        }
    }

    static func broadJumpText(_ value: Int?, fidelity: MeasurableFidelity, unit: String = "in") -> String? {
        guard let value else { return nil }
        switch fidelity {
        case .full:      return "\(value)" + unit
        case .broadcast: return approx("\(Int(snapped(Double(value), to: 3)))" + unit)
        }
    }

    /// The cone and the shuttle share one format — both are agility seconds.
    static func agilityText(_ value: Double?, fidelity: MeasurableFidelity, unit: String = "") -> String? {
        guard let value else { return nil }
        switch fidelity {
        case .full:      return String(format: "%.2f", value) + unit
        case .broadcast: return approx(String(format: "%.1f", snapped(value, to: 0.1)) + unit)
        }
    }

    /// The position-drill grade is a judgement, not a stopwatch reading, so the
    /// broadcast version drops the +/- modifier: "B+" becomes "B". You know the
    /// tier the man tested in; you do not know where inside it he landed.
    static func drillGradeText(_ grade: String?, fidelity: MeasurableFidelity) -> String? {
        guard let grade else { return nil }
        switch fidelity {
        case .full:      return grade
        case .broadcast: return String(grade.prefix(1))
        }
    }

    // MARK: - Football IQ

    /// Where a rendered Football IQ came from.
    ///
    /// The board used to have no column for this at all: an interview wrote
    /// `CollegeProspect.interviewFootballIQ` and the number then lived on one
    /// tab of one detail screen, so a user who had spent his sixty combine
    /// slots could not sort, filter or even *see* what he had bought. The read
    /// has two legitimate sources and they are deliberately styled apart.
    enum IQSource {
        /// Your own people put him in a room and ran the whiteboard. An exact
        /// number, because that is what a meeting produces.
        case interview
        /// Nobody has met him — this is the scouting department reading tape,
        /// so it is a band off the `AWR` / `LRN` grades and nothing sharper.
        case scouts
        /// No tape, no meeting.
        case none

        var tint: Color {
            switch self {
            case .interview: return Color.accentBlue
            case .scouts:    return Color.accentGold
            case .none:      return Color.textTertiary
            }
        }

        var label: String {
            switch self {
            case .interview: return "Interview"
            case .scouts:    return "Scouts"
            case .none:      return "No intel"
            }
        }
    }

    /// What the user is allowed to know about one prospect's football IQ.
    struct IQRead {
        /// The interview's exact figure. `nil` until somebody has met him.
        let value: Int?
        /// The scouts' band. Present for both sources — an interviewed prospect
        /// still gets a band so a column can render a letter if it wants one.
        let band: GradeRange?
        let source: IQSource

        /// "84" once you have met him, "B/B+" while it is only tape, "—" when
        /// nobody has done either.
        var text: String {
            if let value { return "\(value)" }
            return band?.displayText ?? "\u{2014}"
        }

        /// Fog-safe sort key (higher = better). An un-met, un-scouted prospect
        /// sorts to the bottom rather than to the middle.
        var rank: Int {
            if let value { return value }
            guard let band else { return 0 }
            return ProspectFog.approximateValue(of: band.midGrade)
        }

        var isRevealed: Bool { value != nil }

        var accessibilityText: String {
            switch source {
            case .interview:
                return "Football IQ \(value.map(String.init) ?? "unknown"), from your interview"
            case .scouts:
                guard let band else { return "no football IQ read" }
                if band.isSingleGrade {
                    return "Football IQ graded \(band.low.rawValue) by your scouts"
                }
                return "Football IQ graded between \(band.low.rawValue) and \(band.high.rawValue) by your scouts"
            case .none:
                return "no football IQ read \u{2014} interview him to find out"
            }
        }
    }

    /// The football-IQ read the open save is entitled to for `prospect`.
    ///
    /// An interview outranks tape: the number it produced already carries the
    /// interviewer's own noise (`ScoutingEngine.conductInterview`), so widening
    /// it here would double-count the same uncertainty.
    static func footballIQ(_ prospect: CollegeProspect) -> IQRead {
        if let iq = prospect.interviewFootballIQ {
            return IQRead(
                value: iq,
                band: GradeRange(grade: LetterGrade.from(numericValue: iq)),
                source: .interview
            )
        }
        if let band = tapeMentalBand(for: prospect) {
            return IQRead(value: nil, band: band, source: .scouts)
        }
        return IQRead(value: nil, band: nil, source: .none)
    }

    /// Convenience for sort closures.
    static func iqRank(_ prospect: CollegeProspect) -> Int { footballIQ(prospect).rank }

    // MARK: - TAPE / MEET — the same data, un-merged

    /// What the SCOUTING DEPARTMENT has on a prospect's head, off tape.
    ///
    /// ``footballIQ`` is a precedence function: an interview number wins and the
    /// scouts' letter band is only the fallback. One column rendering the winner
    /// of that race is why a board row printed `86 MEET` beside `C-/B+ TAPE` and
    /// asked the user to compare a number with a letter down the same 40-point
    /// strip. They are two instruments answering two different questions — what
    /// he does on Saturdays, and what he knows in a room — so they are two reads
    /// and two columns.
    ///
    /// `footballIQ` stays as the precedence function behind ``iqRank``, which is
    /// what the board's IQ **sort** compares on — one instrument-agnostic
    /// ordering over two columns. (Its old renderer, `ProspectIQCell`, is gone:
    /// after the split it had zero call sites, and the draft room it was
    /// nominally "kept for" never drew it.)
    static func tapeRead(_ prospect: CollegeProspect) -> IQRead {
        guard let band = tapeMentalBand(for: prospect) else {
            return IQRead(value: nil, band: nil, source: .none)
        }
        return IQRead(value: nil, band: band, source: .scouts)
    }

    /// What YOUR OWN people got out of him in a room. Exact, because that is
    /// what a meeting produces; absent until somebody has spent a slot on him.
    static func meetRead(_ prospect: CollegeProspect) -> IQRead {
        guard let iq = prospect.interviewFootballIQ else {
            return IQRead(value: nil, band: nil, source: .none)
        }
        return IQRead(
            value: iq,
            band: GradeRange(grade: LetterGrade.from(numericValue: iq)),
            source: .interview
        )
    }

    /// Convenience for sort closures over the tape column.
    static func tapeRank(_ prospect: CollegeProspect) -> Int { tapeRead(prospect).rank }

    /// Convenience for sort closures over the meeting column.
    static func meetRank(_ prospect: CollegeProspect) -> Int { meetRead(prospect).rank }

    /// The tape half of football IQ: game awareness (`AWR`) blended with how
    /// fast he absorbs a playbook (`LRN`) — the same two attributes the
    /// interview itself is built from, so the band and the number the interview
    /// later returns describe one quantity rather than two.
    private static func tapeMentalBand(for prospect: CollegeProspect) -> GradeRange? {
        let grades = prospect.scoutedMentalGrades
        switch (grades?["AWR"], grades?["LRN"]) {
        case let (awareness?, learning?):
            return GradeRange(
                low: grade(nearestRank: (awareness.low.rank + learning.low.rank) / 2),
                high: grade(nearestRank: (awareness.high.rank + learning.high.rank + 1) / 2),
                reportCount: Swift.min(awareness.reportCount, learning.reportCount)
            )
        case let (awareness?, nil):
            return awareness
        case let (nil, learning?):
            return learning
        default:
            return nil
        }
    }

    /// Representative 40–99 value for a letter grade — the inverse of
    /// `LetterGrade.from(numericValue:)`, taken at each band's midpoint. Only
    /// used to put grades and interview numbers on ONE sort scale; it is never
    /// rendered, because printing "77" for a "B" would claim a precision the
    /// grade does not have.
    static func approximateValue(of grade: LetterGrade) -> Int {
        switch grade {
        case .aPlus:  return 97
        case .a:      return 92
        case .aMinus: return 87
        case .bPlus:  return 82
        case .b:      return 77
        case .bMinus: return 72
        case .cPlus:  return 67
        case .c:      return 62
        case .cMinus: return 57
        case .dPlus:  return 52
        case .d:      return 47
        case .f:      return 40
        }
    }

    /// The letter grade whose rank is closest to `rank`.
    static func grade(nearestRank rank: Int) -> LetterGrade {
        LetterGrade.allCases.min(by: { abs($0.rank - rank) < abs($1.rank - rank) }) ?? .c
    }

    // MARK: - Attribute-grade disclosure

    /// What the club's work has actually produced on one prospect's attribute
    /// grades — and, by omission, what it has not.
    ///
    /// `scoutedMentalGrades` and `scoutedPositionGrades` are written by exactly
    /// two things, and nothing else in the build touches them:
    ///
    /// * **A filed report** — `ScoutingEngine.applyGradeBasedFields`, reached
    ///   through `applyReport`. Every instrument that files one goes through it:
    ///   the regional tape assignment, Senior Bowl week, the combine trip and the
    ///   pro-day tour. It writes all eight mental keys AND the position block.
    /// * **An interview** — `ScoutingEngine.revealMentalGradesFromInterview`,
    ///   which writes the five keys in `interviewRevealedMentalKeys` and nothing
    ///   else. A meeting reads a man's head, never his hands, so it never touches
    ///   a position skill.
    ///
    /// A band on a screen therefore always has an instrument behind it. What the
    /// prospect card was missing was the other half of that sentence: it *dropped*
    /// the keys nobody had bought instead of drawing them dark, so eight grades
    /// sat directly above two empty "Interview" / "Pro Day" chips and read as a
    /// leak of the generator's own numbers. This type carries both halves.
    struct AttributeDisclosure {
        /// The bands the work has produced. Keys absent from here are work the
        /// user has not done — never data the fog is hiding from him.
        let grades: [String: GradeRange]
        /// Reports on file. The tape half of the attribution line.
        let reportCount: Int
        /// Whether a meeting has been held. The MEET half.
        let interviewed: Bool

        var hasAny: Bool { !grades.isEmpty }

        subscript(key: String) -> GradeRange? { grades[key] }

        /// Which key is still dark, out of the keys a caller renders.
        func unread(of keys: [String]) -> [String] {
            keys.filter { grades[$0] == nil }
        }

        /// "2 reports on file · interview" — what paid for what is on the screen.
        /// `nil` when there is nothing on the screen to attribute.
        var attribution: String? {
            guard hasAny else { return nil }
            var parts: [String] = []
            if reportCount > 0 {
                parts.append("\(reportCount) report\(reportCount == 1 ? "" : "s") on file")
            }
            if interviewed { parts.append("interview") }
            guard !parts.isEmpty else { return nil }
            return parts.joined(separator: " \u{00B7} ")
        }
    }

    /// The eight mental keys in board order. Matches
    /// `ScoutingEngine.generateMentalGrades`, which is what writes them.
    static let mentalKeys = ["AWR", "DEC", "WRK", "CLT", "COA", "LDR", "LRN", "CMP"]

    /// The mental block the user has bought on `prospect`.
    static func mentalDisclosure(_ prospect: CollegeProspect) -> AttributeDisclosure {
        AttributeDisclosure(
            grades: prospect.scoutedMentalGrades ?? [:],
            reportCount: prospect.scoutingReports.count,
            interviewed: prospect.interviewCompleted
        )
    }

    /// The position-skill block the user has bought on `prospect`. Never carries
    /// the interview half — see ``AttributeDisclosure``.
    static func positionSkillDisclosure(_ prospect: CollegeProspect) -> AttributeDisclosure {
        AttributeDisclosure(
            grades: prospect.scoutedPositionGrades ?? [:],
            reportCount: prospect.scoutingReports.count,
            interviewed: false
        )
    }

    /// The position-skill keys a report writes for `prospect`, in card order.
    ///
    /// Copied from `ScoutingEngine.generatePositionSkillGrades` — the writer is
    /// the authority on the spelling. Reading `truePositionAttributes` here is
    /// reading the enum CASE (the position group, which is on his jersey), never
    /// the payload.
    ///
    /// Three surfaces had drifted from the writer and were looking up keys that
    /// can never exist: `SAc` / `DAc` for a quarterback (written `SAC` / `DAC`)
    /// and `TAK` for a linebacker (written `TKL`). Every one of those lookups
    /// missed on a fully scouted man.
    static func positionSkillKeys(for prospect: CollegeProspect) -> [String] {
        switch prospect.truePositionAttributes {
        case .quarterback:    return ["ARM", "SAC", "MAC", "DAC", "PKT", "SCR"]
        case .wideReceiver:   return ["RTE", "CTH", "RLS", "SPC"]
        case .runningBack:    return ["VIS", "ELU", "BTK", "RCV"]
        case .tightEnd:       return ["BLK", "CTH", "RTE", "SPD"]
        case .offensiveLine:  return ["RBK", "PBK", "PUL", "ANC"]
        case .defensiveLine:  return ["PRU", "BSH", "PWR", "FIN"]
        case .linebacker:     return ["TKL", "ZCV", "MCV", "BLZ"]
        case .defensiveBack:  return ["MCV", "ZCV", "PRS", "BSK"]
        case .kicking:        return ["PWR", "ACC"]
        }
    }

    /// Whether an interview can read `key` on its own — the five in
    /// `ScoutingEngine.interviewRevealedMentalKeys`. `DEC`, `CLT` and `COA` are
    /// deliberately not among them: decision-making under a live rush, playing
    /// big in a big moment and taking coaching across a season are tape
    /// questions, and forty minutes in a room cannot answer them.
    static func interviewReads(_ key: String) -> Bool {
        ScoutingEngine.interviewRevealedMentalKeys.contains(key)
    }

    /// One line naming what would fill the DARK cells of a mental block, given
    /// exactly which keys are dark.
    ///
    /// Per-key rather than blanket on purpose: a user looking at three empty
    /// cells that read `DEC` / `CLT` / `COA` must not be told to spend an
    /// interview slot, because the room cannot answer any of them.
    static func mentalUnlockHint(forUnread keys: [String]) -> String {
        let prefix = "Dark cells are work you have not bought \u{2014} "
        if keys.allSatisfy(interviewReads) {
            return prefix + "a scouting report or an interview opens them."
        }
        if keys.contains(where: interviewReads) {
            return prefix + "a report grades all eight; an interview reads AWR, LRN, CMP, LDR and WRK."
        }
        return prefix + "decision-making, clutch and coachability are tape questions, so only a scouting report opens them."
    }

    /// The same line for a position block. There is only one instrument here:
    /// every filed report writes the whole block, and nothing else writes any of
    /// it — a meeting never touches it, and a pro day only counts because the
    /// tour files a `.proDay` report.
    static let positionSkillUnlockHint =
        "Dark cells are work you have not bought \u{2014} any filed report (regional tape, the combine trip, a pro day) grades every skill."

    // MARK: - Risk-flag disclosure

    /// How much of a prospect's medical / character file the user may read.
    ///
    /// `DraftClassBuilder` has been writing `medicalConcerns` and `redFlags`
    /// into every class since the generator overhaul, and no screen has ever
    /// rendered either of them — a torn ACL and a failed drug test were data
    /// the game knew and the user could not buy at any price. They are not
    /// public information either, though: a club learns them by doing the work,
    /// so the file opens in three steps.
    enum FlagDisclosure {
        /// Nobody in your building has been near him. You do not know a file
        /// exists.
        case hidden
        /// Somebody has — one report, a pro day, an invite to Indianapolis.
        /// Enough to know there IS something on file, not what it says.
        case count
        /// Two reports, a meeting, or a Top-30 visit: you have read the file.
        case full
    }

    /// The disclosure level the open save is entitled to for `prospect`.
    ///
    /// `userTeamID` is the club whose Top-30 visits count — another team's
    /// visit tells you nothing.
    static func flagDisclosure(
        for prospect: CollegeProspect,
        userTeamID: UUID? = nil
    ) -> FlagDisclosure {
        let visited = userTeamID.map { prospect.top30VisitedByTeams.contains($0) } ?? false
        if prospect.scoutingReports.count >= 2 || prospect.interviewCompleted || visited {
            return .full
        }
        if !prospect.scoutingReports.isEmpty || prospect.proDayCompleted || prospect.combineInvite {
            return .count
        }
        return .hidden
    }

    /// One line of prose telling the user what would open the file the rest of
    /// the way. Only meaningful at `.count`.
    static func flagDisclosureHint(for prospect: CollegeProspect) -> String {
        if prospect.scoutingReports.isEmpty {
            return "File a report, meet him, or spend a Top-30 visit to read it."
        }
        if prospect.scoutingReports.count == 1 {
            return "One more report — or an interview — opens the file."
        }
        return "An interview or a Top-30 visit opens the file."
    }

    // MARK: - Value vs my grade

    /// Where the market has a prospect versus where the user's own grade puts
    /// him. Both halves are information the user legitimately has: the market
    /// rank is media consensus (`DraftIntel.consensusRank`), and the other half
    /// is the grade he wrote himself.
    ///
    /// The arithmetic belongs to `DraftIntel` (`valueDelta` / `marketVerdict`)
    /// so the scouting board and the draft-night room cannot drift into two
    /// different definitions of a steal. This is the presentation wrapper the
    /// scouting rows render.
    struct ValueRead {
        /// Media consensus board slot (1 = first off the board).
        let marketRank: Int
        /// The board slot the user's own grade implies.
        let impliedPick: Int
        /// The market's reading of the gap, thresholded by board depth.
        let verdict: DraftIntel.MarketVerdict

        /// `marketRank − impliedPick`. Positive = the market will let him fall
        /// past where you rate him; negative = you would have to reach.
        var delta: Int { verdict.delta }

        /// Whether the gap is big enough to be worth a chip at this depth.
        var isMeaningful: Bool {
            if case .aligned = verdict { return false }
            return true
        }

        var isValue: Bool { delta > 0 }

        /// "+18" / "−12" — the row chip.
        var chipText: String {
            delta > 0 ? "+\(delta)" : "\u{2212}\(abs(delta))"
        }

        /// "+18 VALUE" / "-21 MARKET" / "IN LINE" — the prose form.
        var label: String { verdict.label }

        /// One sentence for a detail row.
        var detail: String { verdict.detail }

        var tint: Color {
            guard isMeaningful else { return .textTertiary }
            return isValue ? .success : .warning
        }
    }

    /// The letter-grade ordinal (A+ = 12 … F = 1) behind one of the user's own
    /// draft grades — the input `DraftIntel.valueDelta` expects.
    static func gradeOrdinal(for grade: UserGrade) -> Int? {
        LetterGrade(rawValue: grade.letterGrade)?.rank
    }

    /// The value read for one prospect, or `nil` when there is nothing honest
    /// to say — no grade of the user's own, no media rank, or a prospect so
    /// fogged the user has no read on him at all.
    ///
    /// `marketRank` comes from `DraftIntel.consensusRank`, which is media-only
    /// by contract (mock pick, then projected round — never `scoutedOverall`),
    /// so nothing here can leak the board through the delta. The fog check is
    /// the second half of that: a prospect nobody has filed on and the media
    /// has not projected shows no chip at all.
    static func valueRead(
        for prospect: CollegeProspect,
        marketRank: Int?,
        myGrade: UserGrade?
    ) -> ValueRead? {
        guard let marketRank, marketRank > 0,
              let myGrade,
              let ordinal = gradeOrdinal(for: myGrade) else { return nil }
        guard read(prospect).source != .none else { return nil }
        let verdict = DraftIntel.marketVerdict(
            userGradeOrdinal: ordinal,
            consensusRank: marketRank
        )
        return ValueRead(
            marketRank: marketRank,
            impliedPick: marketRank - verdict.delta,
            verdict: verdict
        )
    }

    // MARK: - Band construction

    /// The confidence stars used to sit beside the grade as their own widget
    /// (and wrapped 3 + 2 onto two lines on every Big Board row). They are the
    /// band *width* now: five stars leaves the stored range alone, one star
    /// opens it two grades either way. The band is only ever widened — a stored
    /// range that is already wider than the confidence demands is left as it is,
    /// so this can never make the user look more certain than his scouts are.
    private static func widened(_ range: GradeRange, confidence: Int) -> GradeRange {
        let storedHalfWidth = (range.high.rank - range.low.rank) / 2
        let requiredHalfWidth: Int
        switch confidence {
        case 5, 4: requiredHalfWidth = 0
        case 3, 2: requiredHalfWidth = 1
        default:   requiredHalfWidth = 2
        }
        let extra = requiredHalfWidth - storedHalfWidth
        guard extra > 0 else { return range }
        return GradeRange(
            low: range.low.shifted(by: -extra),
            high: range.high.shifted(by: extra),
            reportCount: range.reportCount
        )
    }

    /// Media band for a prospect nobody in your building has filed on.
    ///
    /// Centred on the projected round's talent band (the same cut points
    /// `BigBoardView.boardProjectedRound` uses, read backwards) and opened two
    /// grades either way — a round is a blunt instrument, and it should read as
    /// one. Rounds 3-5 share a centre on purpose: on the generator-v2 talent
    /// curve those bands are ~4 points of overall wide in total.
    private static func consensusBand(for prospect: CollegeProspect) -> GradeRange? {
        guard let round = prospect.draftProjection, round > 0 else { return nil }
        let centre: LetterGrade
        switch round {
        case 1:       centre = .bPlus   // band ≈ 79-99
        case 2:       centre = .b       // band ≈ 75-79
        case 3, 4, 5: centre = .bMinus  // band ≈ 69-75
        case 6, 7:    centre = .cPlus   // band ≈ 65-69
        default:      centre = .c       // undrafted projection
        }
        return GradeRange(
            low: centre.shifted(by: -2),
            high: centre.shifted(by: 2),
            reportCount: 0
        )
    }
}

// MARK: - Band view

/// The grade band as it appears on a row: one line, never wrapped, tinted by
/// where the information came from (gold = your scouts, grey = media guess).
struct ProspectGradeBand: View {
    let prospect: CollegeProspect
    var width: CGFloat? = nil
    var alignment: Alignment = .trailing
    var font: Font = .caption2.monospaced().weight(.heavy)

    var body: some View {
        let read = ProspectFog.read(prospect)
        Text(read.text)
            .font(font)
            .foregroundStyle(read.source.tint)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: width, alignment: alignment)
            .accessibilityLabel(read.accessibilityText)
    }
}

// MARK: - TAPE / MEET cells

/// The scouting department's tape read on a prospect's head — a gold letter
/// band, or a dash when nobody in the building has filed on him.
///
/// A dash here is a *hole in your work*, not a fogged value, which is why the
/// column is always rendered rather than hidden when empty: the question the
/// user scans a board asking is which men he has not done the work on.
struct ProspectTapeCell: View {
    let prospect: CollegeProspect
    var width: CGFloat = 40

    var body: some View {
        let read = ProspectFog.tapeRead(prospect)
        Text(read.text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(read.source == .none ? Color.textTertiary.opacity(0.5) : Color.accentGold)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .frame(width: width, alignment: .center)
            .accessibilityLabel(
                read.source == .none
                    ? "no tape read \u{2014} file a scouting report to get one"
                    : read.accessibilityText
            )
    }
}

/// The interview room's read — an exact number in blue, or a dash until a
/// combine slot has been spent on him.
struct ProspectMeetCell: View {
    let prospect: CollegeProspect
    var width: CGFloat = 34

    var body: some View {
        let read = ProspectFog.meetRead(prospect)
        Text(read.text)
            .font(.system(size: 11, weight: .bold).monospacedDigit())
            .foregroundStyle(read.source == .none ? Color.textTertiary.opacity(0.5) : Color.accentBlue)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: width, alignment: .center)
            .accessibilityLabel(
                read.source == .none
                    ? "not interviewed \u{2014} spend a combine slot to meet him"
                    : read.accessibilityText
            )
    }
}
