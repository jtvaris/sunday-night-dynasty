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
