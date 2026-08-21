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
/// `trueOverall` never reaches a view again.
///
/// ## What the AI sees, corrected
///
/// This used to end "the AI keeps drafting on the true values internally
/// (`DraftEngine.aiMakePick`, `DraftDayCoordinator`'s pick grades) — this is a
/// user-information change, not a nerf to pick quality". Both halves of that
/// have since stopped being true and the sentence was left standing, which is
/// worse than saying nothing:
///
/// * `aiMakePick` reads every rating through `AIDraftPerception`, a per-`(club,
///   prospect)` fog with a league mean absolute error of **3.96 OVR** and a 7 %
///   fat tail. No AI club sees `trueOverall` either.
/// * The pick grades come from `PickGradeCalculator` off
///   `DraftIntel.publicOVREstimate` — the user's own scouted read, or the media
///   band for a man nobody has filed on. The last `trueOverall` in a grade path
///   was `DraftEngine.generateMediaGrade`'s letter bump, closed by F-36.
///
/// The asymmetry that remains is COVERAGE, not accuracy, and it favours the
/// user: on a man he has actually paid to scout his read is *sharper* than any
/// AI club's (mean |error| 0.67-3.5 against the league's 3.96). He simply
/// cannot afford 350 of them.
///
/// What no club's board is fogged about is TASTE — see `GMTaste`. A house
/// preference is an opinion about visible evidence, and it is meant to be
/// learnable by watching a club draft.
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

    // MARK: - Whose work is this

    /// The scout name `ScoutingEngine.applyPreScoutedData` stamps on the
    /// baseline report the top ~250 of every class inherits at career creation.
    ///
    /// That pass is the sharpest hazard in this file's neighbourhood. It writes
    /// `scoutedOverall`, `scoutGrade`, `scoutedPotential` and a report row for a
    /// THIRD of the class before the user has spent a dollar or hired a scout —
    /// so any surface that reads `scoutedOverall != nil` or
    /// `!scoutingReports.isEmpty` and calls the answer "scouted by us" is
    /// claiming work nobody in this building did. It is the previous regime's
    /// paper: honest to read as "somebody once looked", never as "we know him".
    ///
    /// `ScoutEvaluationBudget.inheritedScoutName` is this same constant — the
    /// money question ("does this report move the price ladder") and the
    /// disclosure question ("does this report back what is on the screen") have
    /// always had the same answer, and they must not drift into two spellings.
    static let inheritedScoutName = "Previous Staff"

    /// Reports THIS regime ordered — the inherited baseline excluded.
    static func ownReportCount(_ prospect: CollegeProspect) -> Int {
        prospect.scoutingReports.reduce(into: 0) {
            $0 += ($1.scoutName == inheritedScoutName ? 0 : 1)
        }
    }

    /// The filled/empty dot string for `prospect`, one glyph vocabulary for
    /// every list that draws confidence dots.
    ///
    /// Counted on ``ownReportCount`` and capped at
    /// `ScoutEvaluationBudget.maxReportsPerProspect` — the same counter and the
    /// same denominator `ProspectDetailView.scoutConfidenceBadge` prints (#184).
    /// The retired `CollegeProspect.scoutConfidenceDots` ran off raw
    /// `scoutingReports.count`, so an untouched season-1 top-250 man showed
    /// "●○○" in a selection list and "Unscouted · 0/3 reports" on the card he
    /// opened from it — the same man, the same glyphs, two answers.
    static func confidenceDots(_ prospect: CollegeProspect) -> String {
        let cap = ScoutEvaluationBudget.maxReportsPerProspect
        let filled = min(ownReportCount(prospect), cap)
        return String(repeating: "\u{25CF}", count: filled)
            + String(repeating: "\u{25CB}", count: cap - filled)
    }

    /// Whether anybody in the user's own building has filed on this man. The
    /// predicate every "you have scouted N of the class" count belongs on.
    static func hasOwnReport(_ prospect: CollegeProspect) -> Bool {
        prospect.scoutingReports.contains { $0.scoutName != inheritedScoutName }
    }

    /// Whether the previous regime's freebie is the ONLY paper on him.
    ///
    /// A card in this state still has bands to draw — `applyPreScoutedData`
    /// writes them — and must say whose they are, because "2 reports on file"
    /// over inherited paper is exactly the claim #184 is about.
    static func hasOnlyInheritedReport(_ prospect: CollegeProspect) -> Bool {
        !prospect.scoutingReports.isEmpty && !hasOwnReport(prospect)
    }

    /// What the user calls the instrument that files a report in `phase`.
    ///
    /// The report ledger is the only record of *how* a band was bought, and a
    /// count ("3 reports on file") throws that away — three regional tape
    /// assignments and a combine trip plus two pro days are not the same
    /// evidence. Names, not tallies.
    static func sourceName(for phase: ScoutingPhase) -> String {
        switch phase {
        case .collegeSeason:   return "Film study"
        case .seniorBowl:      return "The Showcase"
        case .combine:         return "Combine trip"
        case .proDay:          return "Pro day"
        case .personalWorkout: return "Private workout"
        }
    }

    /// The instruments THIS regime ran on him, named, in the order they were
    /// first run. Repeats collapse to a multiplier ("Film study ×2") rather
    /// than repeating the word.
    static func ownReportSources(_ prospect: CollegeProspect) -> [String] {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for report in prospect.scoutingReports where report.scoutName != inheritedScoutName {
            let name = sourceName(for: report.phase)
            if counts[name] == nil { order.append(name) }
            counts[name, default: 0] += 1
        }
        return order.map { name in
            let n = counts[name] ?? 1
            return n > 1 ? "\(name) \u{00D7}\(n)" : name
        }
    }

    /// The band ONE report buys, centred on its observation: ±2 grades at
    /// `reportCount` 1.
    ///
    /// Mirrors `ScoutingEngine.applyGradeBasedFields`' first-report branch,
    /// which is the only thing in the build allowed to open a stored band. It
    /// is exposed here for `CareerShellView`'s save-repair pass — a band an
    /// earlier build fabricated has to be put back to the shape the writer
    /// would have produced, not to some second opinion of what one report is
    /// worth.
    static func firstReportBand(centredOn grade: LetterGrade) -> GradeRange {
        GradeRange(low: grade.shifted(by: -2), high: grade.shifted(by: 2), reportCount: 1)
    }

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
    ///
    /// Gated on ``hasOwnReport`` (#184). Off the raw ledger the inherited
    /// `Previous Staff` row bought `.full` for the top ~250 of every season-1
    /// class — so the combine trip was already paid for on exactly the men that
    /// matter, and worse, the decimal point itself became a free, always-correct
    /// readout of "true rank < 250", which is the one number the fog exists to
    /// hide. `proDayCompleted` stays: that is a genuine own-building event.
    static func combineFidelity(
        for prospect: CollegeProspect,
        scoutsAttended: Bool = CareerScopedDefaults.bool("scoutsSentToCombine")
    ) -> MeasurableFidelity {
        if scoutsAttended { return .full }
        // Work your own building has already done on this man outranks the
        // broadcast: a pro day or a report THIS regime ordered means somebody
        // held the watch. The previous department's paper does not.
        if prospect.proDayCompleted || hasOwnReport(prospect) { return .full }
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
    ///
    /// The read carries BOTH forms: `value` is the figure the prospect card
    /// prints, `band` the single grade it maps to, which is what the board's
    /// MEET column renders (#182).
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
    ///
    /// `scoutedMentalGrades` is a MERGED store: reports write it through
    /// `ScoutingEngine.applyGradeBasedFields`, and so does
    /// `revealMentalGradesFromInterview` (`AWR` and `LRN` are two of its five
    /// keys). Reading it raw meant one combine meeting lit the gold TAPE cell on
    /// a man nobody had ever filmed — the interview showing up in both columns,
    /// which is the exact merge the #182 split undoes. So: no band unless a
    /// report actually wrote mentals. That also keeps the inherited
    /// `Previous Staff` paper out of the scouts' column, since
    /// `applyPreScoutedData` files no mental grades at all.
    private static func tapeMentalBand(for prospect: CollegeProspect) -> GradeRange? {
        guard prospect.scoutingReports.contains(where: { $0.mentalGrades != nil }) else {
            return nil
        }
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
    ///   the regional tape assignment, Showcase week, the combine trip and the
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
        /// Reports THIS regime ordered. The tape half of the attribution line,
        /// and never `scoutingReports.count` — that tally includes the
        /// `Previous Staff` freebie, which writes no band and buys nothing
        /// (#184).
        let reportCount: Int
        /// The instruments behind those reports, NAMED — "Combine trip",
        /// "Film study ×2". A count says how much paper is in the folder; the
        /// names say what kind of looking produced it, which is the only half
        /// of the sentence a user can act on.
        let sources: [String]
        /// Whether a meeting has been held. The MEET half.
        let interviewed: Bool
        /// Bands drawn off the previous regime's inherited report and nothing
        /// else. The line then says so, rather than going silent and letting
        /// eight lit cells read as this building's work.
        let inheritedOnly: Bool

        var hasAny: Bool { !grades.isEmpty }

        subscript(key: String) -> GradeRange? { grades[key] }

        /// Which key is still dark, out of the keys a caller renders.
        func unread(of keys: [String]) -> [String] {
            keys.filter { grades[$0] == nil }
        }

        /// "Combine trip · Film study · Interview" — what paid for what is on
        /// the screen. `nil` when there is nothing on the screen to attribute.
        var attribution: String? {
            guard hasAny else { return nil }
            var parts = sources
            if interviewed { parts.append("Interview") }
            if parts.isEmpty && inheritedOnly { parts.append("Previous staff") }
            guard !parts.isEmpty else { return nil }
            return parts.joined(separator: " \u{00B7} ")
        }
    }

    /// The eight mental keys in board order. Matches
    /// `ScoutingEngine.generateMentalGrades`, which is what writes them.
    static let mentalKeys = ["AWR", "DEC", "WRK", "CLT", "COA", "LDR", "LRN", "CMP"]

    /// The mental block the user has bought on `prospect`.
    ///
    /// Counted on ``ownReportCount`` (#184). Off `scoutingReports.count` the
    /// line under an untouched season-1 top-250 prospect read "1 report on
    /// file" against the inherited `Previous Staff` row — a receipt for work
    /// this building never ordered, printed directly under eight lit cells.
    static func mentalDisclosure(_ prospect: CollegeProspect) -> AttributeDisclosure {
        AttributeDisclosure(
            grades: prospect.scoutedMentalGrades ?? [:],
            reportCount: ownReportCount(prospect),
            sources: ownReportSources(prospect),
            interviewed: prospect.interviewCompleted,
            inheritedOnly: hasOnlyInheritedReport(prospect)
        )
    }

    /// The position-skill block the user has bought on `prospect`. Never carries
    /// the interview half — see ``AttributeDisclosure``.
    static func positionSkillDisclosure(_ prospect: CollegeProspect) -> AttributeDisclosure {
        AttributeDisclosure(
            grades: prospect.scoutedPositionGrades ?? [:],
            reportCount: ownReportCount(prospect),
            sources: ownReportSources(prospect),
            interviewed: false,
            inheritedOnly: hasOnlyInheritedReport(prospect)
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
        if keys.allSatisfy({ interviewReads($0) }) {
            return prefix + "a scouting report or an interview opens them."
        }
        if keys.contains(where: { interviewReads($0) }) {
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
    ///
    /// Counted on ``ownReportCount`` (#184). The freebie `applyPreScoutedData`
    /// stamps on a third of the class is one report by the raw tally, so off
    /// `scoutingReports.count` every pre-scouted man opened at `.count` on day
    /// one — a torn ACL announced itself before the user had hired a scout —
    /// and a single paid look then took him straight to `.full`. Medical and
    /// character files open on THIS building's work.
    static func flagDisclosure(
        for prospect: CollegeProspect,
        userTeamID: UUID? = nil
    ) -> FlagDisclosure {
        let visited = userTeamID.map { prospect.top30VisitedByTeams.contains($0) } ?? false
        let reports = ownReportCount(prospect)
        if reports >= 2 || prospect.interviewCompleted || visited {
            return .full
        }
        if reports > 0 || prospect.proDayCompleted || prospect.combineInvite {
            return .count
        }
        return .hidden
    }

    /// One line of prose telling the user what would open the file the rest of
    /// the way. Only meaningful at `.count`.
    ///
    /// Reads the same counter as the gate above, so the hint cannot promise a
    /// step the gate will not honour.
    static func flagDisclosureHint(for prospect: CollegeProspect) -> String {
        switch ownReportCount(prospect) {
        case 0:  return "File a report, meet him, or spend a Top-30 visit to read it."
        case 1:  return "One more report \u{2014} or an interview \u{2014} opens the file."
        default: return "An interview or a Top-30 visit opens the file."
        }
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
            // The ladder's floor, not a literal — a two-grade band ("C-/B+")
            // has to survive a 40 pt column, so this cell stays at `micro`
            // rather than taking the display voice's 11 pt.
            .font(.system(size: DSType.Size.micro, weight: .bold))
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

/// The interview room's read — a single blue letter grade, or a dash until a
/// combine slot has been spent on him.
///
/// The cell printed the raw interview figure (`82`) until this pass, which put
/// a bare number in a strip of letter grades and asked the user to translate
/// between two vocabularies mid-scan. It is now the ONE grade the number maps
/// to on the same `LetterGrade.from(numericValue:)` scale every other grade in
/// the app uses — one letter, never a band, because a meeting produces an exact
/// read and there is no uncertainty to widen. The exact figure still lives on
/// the prospect card's Interview section, which is where a precise number is
/// worth reading.
///
/// Blue, not gold: the tint is what separates the room's read from the
/// scouting department's tape bands beside it.
struct ProspectMeetCell: View {
    let prospect: CollegeProspect
    var width: CGFloat = 34

    var body: some View {
        let read = ProspectFog.meetRead(prospect)
        // `meetRead` already carries the mapped grade in `band` (a single-grade
        // range built from the interview figure); the dash case falls through
        // to `read.text`, unchanged.
        let label = read.band.map(\.low.rawValue) ?? read.text
        Text(label)
            .font(DSType.display(11, .bold))
            .foregroundStyle(read.source == .none ? Color.textTertiary.opacity(0.5) : Color.accentBlue)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: width, alignment: .center)
            .accessibilityLabel(
                read.source == .none
                    ? "not interviewed \u{2014} spend a combine slot to meet him"
                    : "Football IQ graded \(label) from your interview"
            )
    }
}
