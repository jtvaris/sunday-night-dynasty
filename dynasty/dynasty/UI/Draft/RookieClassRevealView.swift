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

        /// The tally's word for the same verdict. `label` is a sentence written
        /// to be read out one row at a time; a scoreboard needs a word that
        /// fits under a number, three across.
        var shortLabel: String {
            switch self {
            case .above:   return String(localized: "beat it")
            case .matched: return String(localized: "on the mark")
            case .below:   return String(localized: "fell short")
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
        // No staff projection on this row. `Player.assessedPotential` is
        // written in exactly one place — the yearly development pass — and that
        // pass runs at camp EXIT, so a man drafted this spring has never been
        // through one and the field is nil for the whole class, every season.
        // The row was reserving layout for a gold chip that could not render.

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

    /// One man measured against the band he was shown in, and by how far.
    ///
    /// The row's arrow carries the DIRECTION he moved and nothing else, so a
    /// man who beat a converged A- band by two grades and a man who nicked the
    /// top of a five-grade media guess draw the identical glyph. `steps` is the
    /// magnitude that glyph cannot carry.
    struct Swing {
        let row: Row
        /// Grade steps past the band's nearer edge, always positive.
        /// `row.verdict` says which edge.
        let steps: Int
    }

    /// The class read as one object rather than as N rows.
    ///
    /// Every figure is arithmetic over `rows` — no new fetch, nothing asked of
    /// the engine — and it is computed once in `build` rather than in the view,
    /// because a view that counts is a view that recounts on every redraw.
    struct ClassShape {
        /// How the class landed against the reports it was drafted on.
        let above: Int
        let matched: Int
        let below: Int
        /// The two men who moved furthest from their band, either way.
        let biggestRiser: Swing?
        let biggestSlide: Swing?
        /// The best real overall in the class — the answer to "what did I
        /// actually come out of the spring with", which a list sorted by pick
        /// order never puts in one place.
        let headliner: Row?
        /// Picks whose band came out of your own building, and picks that came
        /// off the board on the media's read. The two tints of the legend,
        /// counted.
        let scoutedCount: Int
        let mediaCount: Int
        /// Mean real overall across the class.
        let averageOverall: Int
        /// What the class costs the club a year, in thousands — the per-man
        /// deals on the rows above, summed. Nobody was summing them.
        let annualCost: Int

        var total: Int { above + matched + below }

        /// One sentence on the tally, deliberately about the BOARD rather than
        /// about the players: the rows above grade the men, this card grades
        /// the spring that picked them.
        ///
        /// Every branch is phrased so it survives a class of one — a club that
        /// traded its way down to a single selection still gets a sentence
        /// rather than a plural that does not fit. The even split cannot occur
        /// there (a tie above zero needs two men), so it is free to be plural.
        var readLine: String {
            if above == 0 && below == 0 {
                return String(localized: "Every man landed inside the band your staff gave you.")
            }
            if above > below {
                return String(localized: "The class came out ahead of the reports it was drafted on.")
            }
            if below > above {
                return String(localized: "The class came out behind the reports it was drafted on.")
            }
            return String(localized: "As many risers as slides — the board split down the middle.")
        }

        /// The caveat that has to sit under the two source counts.
        ///
        /// "On the mark" is a cheaper verdict on a media pick than on a
        /// scouted one — the band it had to land inside is a whole round's
        /// consensus rather than a report — and printing the two counts side
        /// by side without saying so invites the user to read them as
        /// comparable. The two extremes get their own sentence because the
        /// middle one describes something not on their screen.
        var bandSourceLine: String {
            if mediaCount == 0 {
                return String(localized: "Your building filed a report on every man in this class.")
            }
            if scoutedCount == 0 {
                return String(localized: "Nobody in your building filed on this class — every band above is the round's consensus, opened two grades either way.")
            }
            return String(localized: "A media read is a whole round's consensus opened two grades either way — an easier band to land inside than a report on one man.")
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
        /// The same rows, counted. See `ClassShape`.
        let shape: ClassShape
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

        // "The room's favourite pick" has to be a judgement, not an artefact of
        // the sort. `max(by:)` returns the FIRST element under a total tie, so
        // whenever the class graded out level — which the current press
        // calibration makes common — the sentence simply named the earliest
        // selection and dressed it up as an opinion. Break the tie on the man
        // who actually came out of the fog highest, and say nothing at all when
        // every graded pick shares one grade.
        let gradesAllAgree = gradedRows.count > 1
            && Set(gradedRows.compactMap { $0.row.pressGrade }).count == 1
        let bestLine: String? = gradesAllAgree
            ? nil
            : gradedRows
                .max(by: {
                    $0.points != $1.points ? $0.points < $1.points : $0.row.overall < $1.row.overall
                })
                .map { "\($0.row.slotText) \($0.row.position) \($0.row.name)" }
        let reachLine: String? = {
            // Same tie-break, pointing the other way — a class of eleven C
            // grades named the earliest pick as the eyebrow-raiser for exactly
            // the same reason.
            guard let worst = gradedRows.min(by: {
                      $0.points != $1.points ? $0.points < $1.points : $0.row.overall < $1.row.overall
                  }),
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
            biggestReachLine: reachLine,
            shape: classShape(of: rows)
        )
    }

    /// How far past his band's edge a man actually landed, in grade steps.
    /// Zero whenever he came out inside it.
    ///
    /// Measured on the same ladder `RookieFog.verdict` compares on, so the
    /// number and the arrow can never disagree.
    static func swingSteps(of row: Row) -> Int {
        let actual = LetterGrade.from(numericValue: row.overall)
        switch row.verdict {
        case .above:   return actual.rank - row.band.high.rank
        case .below:   return row.band.low.rank - actual.rank
        case .matched: return 0
        }
    }

    /// The class-wide arithmetic, in one pass over rows that already exist.
    private static func classShape(of rows: [Row]) -> ClassShape {
        let swings = rows.map { Swing(row: $0, steps: swingSteps(of: $0)) }

        // Same tie-break shape as `bestLine` above, and for the same reason: a
        // class where two men both beat their band by one grade must not name
        // whoever the pick order happened to put first. The riser tie goes to
        // the better player and the slide tie to the worse one — in both cases
        // to the man the surprise actually mattered on.
        let biggestRiser = swings
            .filter { $0.row.verdict == .above }
            .max(by: { $0.steps != $1.steps ? $0.steps < $1.steps : $0.row.overall < $1.row.overall })
        let biggestSlide = swings
            .filter { $0.row.verdict == .below }
            .max(by: { $0.steps != $1.steps ? $0.steps < $1.steps : $0.row.overall > $1.row.overall })

        let overalls = rows.map(\.overall)
        let averageOverall = overalls.isEmpty
            ? 0
            : Int((Double(overalls.reduce(0, +)) / Double(overalls.count)).rounded())

        return ClassShape(
            above: rows.filter { $0.verdict == .above }.count,
            matched: rows.filter { $0.verdict == .matched }.count,
            below: rows.filter { $0.verdict == .below }.count,
            biggestRiser: biggestRiser,
            biggestSlide: biggestSlide,
            // `max(by:)` keeps the FIRST of equal maxima and the rows arrive in
            // pick order, so two men at the same overall resolve to the one the
            // club spent the earlier selection on.
            headliner: rows.max(by: { $0.overall < $1.overall }),
            scoutedCount: rows.filter { $0.bandSource == .scouts }.count,
            mediaCount: rows.filter { $0.bandSource == .media }.count,
            averageOverall: averageOverall,
            annualCost: rows.reduce(0) { $0 + $1.salary }
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
                        classShapeCard
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
                    // The glyph was the whole hit target — 28 pt against the
                    // 44 pt minimum, on the same header as a correct 50 pt
                    // "Open Camp". Padded out without growing the icon.
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
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

            VStack(alignment: .leading, spacing: 2) {  // ds-lint:allow(spacing) caption over its own legend
                Text(String(localized: "Pre-camp band vs. the evaluation your staff filed this morning."))
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
                // Three encodings in every row carry meaning and none of them
                // says so: who filed the band (the tint), how the real number
                // landed against it (the arrow), and that the last figure is
                // his true overall.
                Text(String(localized: "Gold band = your scouts · grey = the media's guess for his round · arrow = where he landed against it · last figure is his real OVR."))
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

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
                Spacer(minLength: 0)
                if let grade = row.pressGrade {
                    // WHEN this verdict was filed, not just who filed it: the
                    // chip is April's draft-night grade and the arrow above it
                    // is this morning's evaluation, and a green STEAL beside a
                    // red down-arrow reads as one grader contradicting himself.
                    Text(String(localized: "Draft night: \(grade.rawValue) · \(grade.qualifier)"))
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

    // MARK: Class shape
    //
    // The screen used to end at the last rookie, which on an iPad left roughly
    // a sixth of the page as empty ground under the card — and left the one
    // question the reveal exists to answer ("was my spring of scouting any
    // good?") to be answered by counting arrows by hand. Three things fill it,
    // in the order a user asks for them: the tally those arrows add up to, the
    // men who moved furthest from the band they were shown in, and what the
    // class costs. Nothing here is a second copy of the list above — it is the
    // arithmetic over it that the list cannot show.

    /// A man worth naming under the tally, with the caption that says why.
    /// `steps` is how far past his band's edge he landed; zero means there is
    /// nothing to say about the swing and no chip is drawn.
    private struct Callout: Identifiable {
        let id: UUID
        let caption: String
        let row: RookieClassReveal.Row
        let steps: Int
    }

    /// Never the same man twice. The top of the class is very often also the
    /// biggest riser, and printing him on two consecutive lines under two
    /// different captions reads as a bug rather than as a compliment — so the
    /// headliner claims the man first and the swing lines take who is left.
    /// (A riser and a slide can never collide: they sit on opposite sides of
    /// their bands.)
    private var callouts: [Callout] {
        let shape = summary.shape
        var out: [Callout] = []
        var named = Set<UUID>()

        if let top = shape.headliner {
            out.append(Callout(
                id: top.id,
                caption: String(localized: "Top of the class"),
                row: top,
                steps: RookieClassReveal.swingSteps(of: top)
            ))
            named.insert(top.id)
        }
        if let riser = shape.biggestRiser, !named.contains(riser.row.id) {
            out.append(Callout(
                id: riser.row.id,
                caption: String(localized: "Biggest riser"),
                row: riser.row,
                steps: riser.steps
            ))
            named.insert(riser.row.id)
        }
        if let slide = shape.biggestSlide, !named.contains(slide.row.id) {
            out.append(Callout(
                id: slide.row.id,
                caption: String(localized: "Biggest slide"),
                row: slide.row,
                steps: slide.steps
            ))
        }
        return out
    }

    private var classShapeCard: some View {
        let shape = summary.shape
        return VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "chart.bar.xaxis")
                    .foregroundStyle(Color.accentBlue)
                Text(String(localized: "How the Class Graded Out"))
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text(String(localized: "avg \(String(shape.averageOverall)) OVR"))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.forRating(shape.averageOverall))
            }

            tally(shape)

            Text(shape.readLine)
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                ForEach(callouts) { callout in
                    calloutLine(callout)
                }
            }

            Divider().overlay(Color.surfaceBorder)

            HStack(alignment: .top, spacing: DSSpacing.lg) {
                shapeStat(
                    label: String(localized: "Scouted bands"),
                    value: "\(shape.scoutedCount)",
                    tint: RookieFog.Source.scouts.tint
                )
                shapeStat(
                    label: String(localized: "Media reads"),
                    value: "\(shape.mediaCount)",
                    tint: RookieFog.Source.media.tint
                )
                shapeStat(
                    label: String(localized: "Cost per year"),
                    value: DraftRecapView.formatCap(shape.annualCost),
                    tint: Color.textPrimary
                )
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(String(
                localized: "\(shape.scoutedCount) scouted bands, \(shape.mediaCount) media reads, \(DraftRecapView.formatCap(shape.annualCost)) a year in salary."
            ))

            Text(shape.bandSourceLine)
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DSSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.card)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: DSCornerRadius.card)
                        .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                )
        )
    }

    private func tally(_ shape: RookieClassReveal.ClassShape) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            tallyBar(shape)
            HStack(spacing: DSSpacing.md) {
                tallyItem(.above, count: shape.above)
                tallyItem(.matched, count: shape.matched)
                tallyItem(.below, count: shape.below)
                Spacer(minLength: 0)
            }
        }
        // One statement, not a bar plus three fragments: element by element
        // this reads out as "arrow, 3, beat it, arrow, 4, on the mark…", which
        // is not a sentence.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(
            localized: "\(shape.above) beat the report, \(shape.matched) landed on it, \(shape.below) fell short."
        ))
    }

    /// One segment per verdict, sized by share of the class.
    ///
    /// A share, not a grid: the class is anywhere from one man to eleven, and
    /// the bar has to read as a proportion at both ends of that range. Zero
    /// counts drop out entirely rather than drawing a hairline nobody can hit.
    private func tallyBar(_ shape: RookieClassReveal.ClassShape) -> some View {
        let segments: [TallySegment] = [
            TallySegment(id: 0, count: shape.above, color: RookieFog.Verdict.above.color),
            TallySegment(id: 1, count: shape.matched, color: RookieFog.Verdict.matched.color),
            TallySegment(id: 2, count: shape.below, color: RookieFog.Verdict.below.color)
        ].filter { $0.count > 0 }
        let total = max(1, shape.total)

        return GeometryReader { geo in
            let gaps = CGFloat(max(0, segments.count - 1)) * DSSpacing.xxs
            let usable = max(0, geo.size.width - gaps)
            HStack(spacing: DSSpacing.xxs) {
                ForEach(segments) { segment in
                    Capsule()
                        .fill(segment.color)
                        .frame(width: usable * CGFloat(segment.count) / CGFloat(total))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 8)
    }

    private struct TallySegment: Identifiable {
        let id: Int
        let count: Int
        let color: Color
    }

    private func tallyItem(_ verdict: RookieFog.Verdict, count: Int) -> some View {
        // A zero is worth printing — "0 fell short" is the best line on this
        // screen — but it is not worth a colour: a tinted zero pulls the eye
        // exactly as hard as a count that actually happened.
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: verdict.icon)
                .font(.system(size: DSType.Size.micro, weight: .heavy))
            Text("\(count)")
                .font(.system(size: DSType.Size.callout, weight: .heavy).monospacedDigit())
            Text(verdict.shortLabel)
                .font(.system(size: DSType.Size.caption, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(count > 0 ? verdict.color : Color.textTertiary)
    }

    private func calloutLine(_ callout: Callout) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DSSpacing.xs) {
            Text(callout.caption)
                .font(.system(size: DSType.Size.caption, weight: .heavy))
                .tracking(0.4)
                .foregroundStyle(Color.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 104, alignment: .leading)

            Text(callout.row.slotText)
                .font(.system(size: DSType.Size.caption, weight: .heavy).monospacedDigit())
                .foregroundStyle(Color.textTertiary)
                .frame(width: 62, alignment: .leading)

            Text(callout.row.position)
                .font(.caption.weight(.heavy))
                .foregroundStyle(Color.accentBlue)
                .frame(width: 30, alignment: .leading)

            Text(callout.row.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: DSSpacing.xxs)

            if callout.steps > 0 {
                Text(swingText(steps: callout.steps, verdict: callout.row.verdict))
                    .font(.system(size: DSType.Size.micro, weight: .heavy))
                    .foregroundStyle(callout.row.verdict.color)
                    .lineLimit(1)
                    .padding(.horizontal, DSSpacing.xs)
                    .padding(.vertical, DSSpacing.xxs)
                    .background(
                        Capsule().stroke(callout.row.verdict.color.opacity(0.6), lineWidth: 1)
                    )
            }

            Text("\(callout.row.overall)")
                .font(.headline.monospacedDigit().weight(.heavy))
                .foregroundStyle(Color.forRating(callout.row.overall))
                .frame(width: 34, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(
            localized: "\(callout.caption): \(callout.row.slotText) \(callout.row.position) \(callout.row.name), overall \(String(callout.row.overall)). \(callout.row.verdict.label)"
        ))
    }

    /// "+2 grades" / "-1 grade" — the magnitude the row's arrow cannot carry.
    private func swingText(steps: Int, verdict: RookieFog.Verdict) -> String {
        let unit = steps == 1
            ? String(localized: "grade")
            : String(localized: "grades")
        return verdict == .below ? "-\(steps) \(unit)" : "+\(steps) \(unit)"
    }

    private func shapeStat(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
            Text(label.uppercased())
                .font(.system(size: DSType.Size.micro, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(Color.textTertiary)
            Text(value)
                .font(.subheadline.weight(.heavy).monospacedDigit())
                .foregroundStyle(tint)
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
