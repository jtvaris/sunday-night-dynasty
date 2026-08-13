import SwiftUI
import SwiftData

// MARK: - Rookie fog
//
// TRACK B. The draft room already refuses to print a prospect's true overall
// (`ProspectFog`) — but the second his name was called the same man appeared on
// the roster screen with an exact, unmissable OVR number. The fog ended at the
// podium, which made every scouting decision in the spring worthless: draft
// blind, read the roster afterwards.
//
// Nothing about the MECHANICS changes here. `DraftEngine.convertToPlayer` still
// makes a real `Player` at the pick, with real ratings the depth chart, the sim
// and the development pass all keep using. What changes is what the user is
// allowed to SEE: until the rookie reports to training camp he reads as a grade
// BAND, in exactly the vocabulary his scouts spoke in the draft room, and the
// camp-opening `RookieClassRevealView` is where the real numbers arrive.

/// Who may still be hidden, and behind what band.
enum RookieFog {

    /// Where a fogged rookie's band came from — the same two legitimate sources
    /// `ProspectFog` distinguishes, so the tint means the same thing here as it
    /// did on the big board.
    enum Source {
        /// Your building filed on him before you drafted him.
        case scouts
        /// Nobody did — this is the media consensus for his draft slot.
        case media

        var tint: Color {
            switch self {
            case .scouts: return Color.accentGold
            case .media:  return Color.textTertiary
            }
        }

        var label: String {
            switch self {
            case .scouts: return String(localized: "Scouts")
            case .media:  return String(localized: "Media")
            }
        }
    }

    /// The single predicate. A player is fogged when he is a rookie from the
    /// draft the user just ran AND the calendar has not yet reached training
    /// camp.
    ///
    /// `Career.currentSeason` only rolls over at the roster-cuts → regular-season
    /// boundary, so a man drafted in season N carries `draftSeason == N` through
    /// the whole pre-season; the phase ordinal is what closes the window. Camp
    /// (ordinal 9) and everything after it — preseason, cutdowns, the season —
    /// read the real number.
    static func isFogged(_ player: Player, season: Int, phase: SeasonPhase) -> Bool {
        guard let draftSeason = player.draftSeason, draftSeason == season else { return false }
        return phase.overallOrdinal < SeasonPhase.trainingCamp.overallOrdinal
    }

    /// The band the user is allowed to read on a fogged rookie.
    ///
    /// * `Player.preCampScoutBand` when his own scouts filed on the prospect —
    ///   stamped at the pick by `DraftDayCoordinator`.
    /// * Otherwise the media consensus for the round he came off the board in,
    ///   using the same cut points `ProspectFog.consensusBand` uses (that one is
    ///   `private` and reads a `CollegeProspect`, which no longer exists once
    ///   the pick is made — the mapping is mirrored, not forked).
    static func band(for player: Player) -> GradeRange {
        if let stored = parse(player.preCampScoutBand) { return stored }
        return consensusBand(round: player.draftRound)
    }

    static func source(for player: Player) -> Source {
        parse(player.preCampScoutBand) != nil ? .scouts : .media
    }

    /// "B+" (converged) or "B-/A-" (still a range).
    static func bandText(for player: Player) -> String {
        band(for: player).displayText
    }

    static func accessibilityText(for player: Player) -> String {
        let band = band(for: player)
        let source = source(for: player)
        if band.isSingleGrade {
            return String(localized: "\(source.label) grade \(band.low.rawValue), full evaluation at training camp")
        }
        return String(localized: "\(source.label) grade between \(band.low.rawValue) and \(band.high.rawValue), full evaluation at training camp")
    }

    /// A whole draft round is a blunt instrument and reads as one: the round's
    /// talent centre, opened two grades either way.
    static func consensusBand(round: Int?) -> GradeRange {
        let centre: LetterGrade
        switch round ?? 0 {
        case 1:       centre = .bPlus
        case 2:       centre = .b
        case 3, 4, 5: centre = .bMinus
        case 6, 7:    centre = .cPlus
        default:      centre = .c    // undrafted / unknown slot
        }
        return GradeRange(low: centre.shifted(by: -2), high: centre.shifted(by: 2), reportCount: 0)
    }

    /// Reads `"B+"` / `"B-/A-"` back into a range. Anything unparseable (an
    /// empty string, a legacy row) is treated as "no scouted band".
    static func parse(_ text: String) -> GradeRange? {
        guard !text.isEmpty else { return nil }
        let parts = text.split(separator: "/").map(String.init)
        if parts.count == 1, let grade = LetterGrade(rawValue: parts[0]) {
            return GradeRange(grade: grade)
        }
        if parts.count == 2,
           let low = LetterGrade(rawValue: parts[0]),
           let high = LetterGrade(rawValue: parts[1]) {
            return GradeRange(low: low, high: high, reportCount: 1)
        }
        return nil
    }

    /// How the real number landed against the band the user was shown.
    enum Verdict {
        case above, matched, below

        var icon: String {
            switch self {
            case .above:   return "arrow.up.right"
            case .matched: return "equal"
            case .below:   return "arrow.down.right"
            }
        }

        var color: Color {
            switch self {
            case .above:   return Color.success
            case .matched: return Color.textSecondary
            case .below:   return Color.warning
            }
        }

        var label: String {
            switch self {
            case .above:   return String(localized: "Outperformed the report")
            case .matched: return String(localized: "Matched the report")
            case .below:   return String(localized: "Below the report")
            }
        }
    }

    static func verdict(realOverall: Int, band: GradeRange) -> Verdict {
        let actual = LetterGrade.from(numericValue: realOverall)
        if actual.rank > band.high.rank { return .above }
        if actual.rank < band.low.rank  { return .below }
        return .matched
    }
}

// MARK: - Fog context (environment)

/// The season + phase the surrounding screens are being read in. Injected once
/// by `CareerShellView`; every roster surface below it asks this rather than
/// threading a `Career` through a dozen row views.
///
/// The default is deliberately inert — a preview or a stand-alone list that
/// never got the context shows real numbers, exactly as it did before.
struct RookieFogContext: Equatable {
    var season: Int?
    var phase: SeasonPhase?

    static let inactive = RookieFogContext(season: nil, phase: nil)

    func isFogged(_ player: Player) -> Bool {
        guard let season, let phase else { return false }
        return RookieFog.isFogged(player, season: season, phase: phase)
    }
}

private struct RookieFogContextKey: EnvironmentKey {
    static let defaultValue = RookieFogContext.inactive
}

extension EnvironmentValues {
    var rookieFog: RookieFogContext {
        get { self[RookieFogContextKey.self] }
        set { self[RookieFogContextKey.self] = newValue }
    }
}

// MARK: - Band chip

/// A fogged rookie's grade band where his OVR number would have been. One line,
/// never wrapped, tinted by where the read came from (gold = your scouts,
/// grey = the media's guess) — the same code the draft room speaks.
struct RookieBandChip: View {
    let player: Player
    var font: Font = .caption2.monospaced().weight(.heavy)

    var body: some View {
        Text(RookieFog.bandText(for: player))
            .font(font)
            .foregroundStyle(RookieFog.source(for: player).tint)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .accessibilityLabel(RookieFog.accessibilityText(for: player))
    }
}

// MARK: - Reveal payload

/// "Rookies Report to Camp" — assembled once at the camp boundary from rows
/// that already exist (`Player`, `DraftPickGrade`), never a parallel system.
enum RookieClassReveal {

    // MARK: One-shot flag

    /// Career-scoped so two saves in the same install can each get their own
    /// reveal, and season-valued so the flag is self-describing: it holds the
    /// season whose class is still waiting to be shown.
    private static let flagBase = "rookieClassRevealPendingSeason"

    private static func flagKey(careerID: UUID) -> String {
        CareerScopedDefaults.key(flagBase, careerID: careerID)
    }

    /// Called by `WeekAdvancer` when the phase crosses INTO training camp.
    static func arm(careerID: UUID, season: Int) {
        UserDefaults.standard.set(season, forKey: flagKey(careerID: careerID))
    }

    /// The season whose reveal is still owed, if any.
    static func pendingSeason(careerID: UUID) -> Int? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: flagKey(careerID: careerID)) != nil else { return nil }
        return defaults.integer(forKey: flagKey(careerID: careerID))
    }

    /// Consumed on dismissal — the reveal is a once-per-season event.
    static func clear(careerID: UUID) {
        UserDefaults.standard.removeObject(forKey: flagKey(careerID: careerID))
    }

    // MARK: Model

    struct Row: Identifiable {
        let id: UUID
        let name: String
        let position: String
        let college: String?
        let round: Int
        let pickNumber: Int
        /// What the user was shown before camp.
        let band: GradeRange
        let bandSource: RookieFog.Source
        /// What he actually is.
        let overall: Int
        let verdict: RookieFog.Verdict
        /// The staff's first read on his ceiling (noise-2 by design).
        let projection: PotentialLabel?
        /// The press grade the pick itself was given on draft night.
        let pressGrade: PickGrade?
        /// Average per year of the deal he signed at the podium, in thousands.
        let salary: Int
        /// Years still on that deal.
        let contractYears: Int

        var slotText: String {
            round > 0 ? "R\(round) · #\(pickNumber)" : "UDFA"
        }

        /// "$10.9M · 4 yrs" (task #94).
        ///
        /// The reveal is the first screen that puts a real number on a rookie,
        /// and it used to put exactly one there — the OVR. What the club is
        /// PAYING for that number belongs in the same row: a B-grade at
        /// `$1.1M` and a B-grade at `$10.9M` are not the same draft pick.
        ///
        /// No cap share here, unlike `DraftRecapView`: `build` is called from
        /// `WeekAdvancer` and `CareerShellView`, and neither hands this type a
        /// salary cap to divide by.
        var dealText: String {
            "\(DraftRecapView.formatCap(salary)) · \(contractYears) yr\(contractYears == 1 ? "" : "s")"
        }
    }

    struct Summary: Identifiable {
        let id = UUID()
        let season: Int
        let teamName: String
        let teamAbbreviation: String
        let rows: [Row]
        /// Average of the picks' press grades, as one letter.
        let classGrade: String
        /// One paragraph of press verdict.
        let verdict: String
        let bestPickLine: String?
        let biggestReachLine: String?
    }

    // MARK: Build

    /// - Parameters:
    ///   - players: any player population; filtered here to this club's rookies
    ///     from `season`.
    ///   - grades: persisted `DraftPickGrade` rows (the press grade of record,
    ///     written by `DraftDayCoordinator.completePick`).
    /// - Returns: `nil` when the club drafted nobody — there is no class to show.
    static func build(
        season: Int,
        teamID: UUID,
        teamName: String,
        teamAbbreviation: String,
        players: [Player],
        grades: [DraftPickGrade]
    ) -> Summary? {
        let gradesByPlayer = Dictionary(
            grades.compactMap { grade -> (UUID, DraftPickGrade)? in
                guard let playerID = grade.playerID else { return nil }
                return (playerID, grade)
            },
            uniquingKeysWith: { first, _ in first }
        )

        let rookies = players
            .filter { $0.teamID == teamID && $0.draftSeason == season }
            .sorted { ($0.draftPickNumber ?? Int.max) < ($1.draftPickNumber ?? Int.max) }

        guard !rookies.isEmpty else { return nil }

        let rows: [Row] = rookies.map { player in
            let band = RookieFog.band(for: player)
            return Row(
                id: player.id,
                name: player.fullName,
                position: player.position.rawValue,
                college: player.college,
                round: player.draftRound ?? 0,
                pickNumber: player.draftPickNumber ?? 0,
                band: band,
                bandSource: RookieFog.source(for: player),
                overall: player.overall,
                verdict: RookieFog.verdict(realOverall: player.overall, band: band),
                projection: player.assessedPotential.flatMap(PotentialLabel.init(rawValue:)),
                pressGrade: gradesByPlayer[player.id]?.publicGrade,
                salary: player.annualSalary,
                contractYears: player.contractYearsRemaining
            )
        }

        // Graded rows only: a class whose grades never persisted (a legacy save)
        // still renders, it simply has no press verdict to average.
        let gradedRows: [(row: Row, points: Double)] = rows.compactMap { row in
            guard let grade = row.pressGrade else { return nil }
            return (row, points(for: grade))
        }
        let classGrade = letterForAverage(gradedRows.isEmpty
            ? 3.0
            : gradedRows.map(\.points).reduce(0, +) / Double(gradedRows.count))

        let bestLine = gradedRows.max(by: { $0.points < $1.points })
            .map { "\($0.row.slotText) \($0.row.position) \($0.row.name)" }
        let reachLine: String? = {
            guard let worst = gradedRows.min(by: { $0.points < $1.points }),
                  let grade = worst.row.pressGrade,
                  grade == .reach || grade == .bigReach else { return nil }
            return "\(worst.row.slotText) \(worst.row.position) \(worst.row.name)"
        }()

        return Summary(
            season: season,
            teamName: teamName,
            teamAbbreviation: teamAbbreviation,
            rows: rows,
            classGrade: classGrade,
            verdict: verdictParagraph(
                teamName: teamName,
                classGrade: classGrade,
                pickCount: rows.count,
                bestLine: bestLine,
                reachLine: reachLine
            ),
            bestPickLine: bestLine,
            biggestReachLine: reachLine
        )
    }

    /// Grade-point value of one press grade, on the usual 4.0 scale.
    static func points(for grade: PickGrade) -> Double {
        switch grade {
        case .hofTrack:   return 4.5
        case .stealAPlus: return 4.3
        case .smartA:     return 4.0
        case .solid:      return 3.0
        case .reach:      return 2.0
        case .bigReach:   return 1.0
        }
    }

    /// Average grade points → the letter the press prints.
    static func letterForAverage(_ average: Double) -> String {
        switch average {
        case 4.15...:     return "A+"
        case 3.85..<4.15: return "A"
        case 3.50..<3.85: return "A-"
        case 3.15..<3.50: return "B+"
        case 2.85..<3.15: return "B"
        case 2.50..<2.85: return "B-"
        case 2.15..<2.50: return "C+"
        case 1.85..<2.15: return "C"
        case 1.50..<1.85: return "C-"
        case 1.15..<1.50: return "D+"
        default:          return "D"
        }
    }

    /// The one paragraph of press verdict shared by the modal header, the news
    /// item and the inbox letter — written once so all three agree.
    static func verdictParagraph(
        teamName: String,
        classGrade: String,
        pickCount: Int,
        bestLine: String?,
        reachLine: String?
    ) -> String {
        var sentences: [String] = []
        let picks = pickCount == 1
            ? String(localized: "one selection")
            : String(localized: "\(pickCount) selections")
        sentences.append(String(
            localized: "The \(teamName) come out of the draft with \(picks) and a class grade of \(classGrade)."
        ))
        if let bestLine {
            sentences.append(String(localized: "The room's favourite pick: \(bestLine)."))
        }
        if let reachLine {
            sentences.append(String(localized: "The one that raised eyebrows: \(reachLine)."))
        } else {
            sentences.append(String(localized: "No selection was graded a reach."))
        }
        sentences.append(String(
            localized: "Camp is where the tape starts, and the board gets re-written by September."
        ))
        return sentences.joined(separator: " ")
    }
}

// MARK: - Reveal screen

/// Full-screen, once-per-season: the moment the fog lifts off the user's own
/// draft class. Every row puts the band he was shown next to the number he
/// actually got, so a spring of scouting is finally graded.
struct RookieClassRevealView: View {

    let summary: RookieClassReveal.Summary
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        verdictCard
                        classCard
                    }
                    .padding(20)
                    .frame(maxWidth: DSLayout.contentMeasure)
                    .frame(maxWidth: .infinity)
                }
                footer
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Rookies Report to Camp"))
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(Color.textPrimary)
                // #152 — the class is named for the season it debuts in.
                Text(String(localized: "\(summary.teamName) · \(String(DraftYearLabel.classYear(forStamped: summary.season))) draft class"))
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Close rookie class report"))
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .background(Color.backgroundSecondary)
        .overlay(alignment: .bottom) {
            Divider().overlay(Color.surfaceBorder)
        }
    }

    // MARK: Verdict

    private var verdictCard: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 2) {
                Text(summary.classGrade)
                    .font(.system(size: DSType.Size.display, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.accentGold)
                Text(String(localized: "CLASS GRADE"))
                    .font(.system(size: DSType.Size.caption, weight: .heavy))
                    .tracking(0.5)
                    .foregroundStyle(Color.textTertiary)
            }
            .frame(width: 96)

            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "The press verdict"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.textSecondary)
                Text(summary.verdict)
                    .font(.footnote)
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.accentGold.opacity(0.35), lineWidth: 1)
                )
        )
    }

    // MARK: Class

    private var classCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "person.3.sequence.fill")
                    .foregroundStyle(Color.accentBlue)
                Text(String(localized: "Your Draft Class"))
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text(String(localized: "\(summary.rows.count) reporting"))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.textTertiary)
            }

            Text(String(localized: "Pre-camp band vs. the evaluation your staff filed this morning."))
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)

            VStack(spacing: 8) {
                ForEach(summary.rows) { row in
                    rookieRow(row)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                )
        )
    }

    private func rookieRow(_ row: RookieClassReveal.Row) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(row.slotText)
                    .font(.system(size: 11, weight: .heavy).monospacedDigit())
                    .foregroundStyle(Color.textTertiary)
                    .frame(width: 74, alignment: .leading)

                Text(row.position)
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(Color.accentBlue)
                    .frame(width: 30, alignment: .leading)

                Text(row.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 4)

                // Band → real OVR, with the delta arrow between them.
                HStack(spacing: 6) {
                    Text(row.band.displayText)
                        .font(.caption2.monospaced().weight(.heavy))
                        .foregroundStyle(row.bandSource.tint)
                    Image(systemName: row.verdict.icon)
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(row.verdict.color)
                    Text("\(row.overall)")
                        .font(.headline.monospacedDigit().weight(.heavy))
                        .foregroundStyle(Color.forRating(row.overall))
                        .frame(width: 34, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(String(
                    localized: "\(row.bandSource.label) band \(row.band.displayText), actual overall \(String(row.overall)). \(row.verdict.label)"
                ))
            }

            HStack(spacing: 8) {
                if let college = row.college, !college.isEmpty {
                    Text(college)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)
                }
                Text(row.dealText)
                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                    .accessibilityLabel(String(localized: "Signed for \(row.dealText)"))
                if let projection = row.projection {
                    Label(projection.displayName, systemImage: "binoculars.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.accentGold)
                        .labelStyle(.titleAndIcon)
                }
                Spacer(minLength: 0)
                if let grade = row.pressGrade {
                    Text(String(localized: "Press \(grade.rawValue) · \(grade.qualifier)"))
                        .font(.system(size: DSType.Size.caption, weight: .heavy))
                        .tracking(0.4)
                        .foregroundStyle(pressTint(grade))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().stroke(pressTint(grade).opacity(0.6), lineWidth: 1))
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.backgroundTertiary.opacity(0.4))
        )
    }

    private func pressTint(_ grade: PickGrade) -> Color {
        switch grade {
        case .hofTrack, .stealAPlus: return Color.success
        case .smartA:                return Color.accentGold
        case .solid:                 return Color.textSecondary
        case .reach:                 return Color.warning
        case .bigReach:              return Color.danger
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 10) {
            Button(action: onDismiss) {
                Text(String(localized: "Open Camp"))
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.backgroundPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 12).fill(Color.accentGold)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(maxWidth: DSLayout.contentMeasure)
        .frame(maxWidth: .infinity)
        .background(Color.backgroundSecondary)
        .overlay(alignment: .top) {
            Divider().overlay(Color.surfaceBorder)
        }
    }
}
